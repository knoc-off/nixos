//! Lua engine setup and model-script execution.
//!
//! A model script is a Lua module that returns a table with two
//! functions:
//!
//! ```lua
//! local M = {}
//! function M.card_names() return { "Front", "Back" } end
//! function M.generate(note, ctx) return { Front = "...", Back = "..." } end
//! return M
//! ```
//!
//! Stock models (basic, cloze) never reach this engine -- they render
//! through `sync::engine::render_stock`.

use anyhow::{bail, Context, Result};
use mlua::{chunk::ChunkMode, Function, HookTriggers, Lua, LuaOptions, StdLib, Table, Value};
use std::cell::Cell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::time::SystemTime;
use tracing::debug;

/// Output of a model's `generate()`: field name -> HTML string.
pub type ModelOutput = HashMap<String, String>;

/// How many VM instructions a single script invocation may run before it
/// is aborted. Generous -- this is a runaway guard, not a tuning knob.
const INSTRUCTION_BUDGET: i64 = 50_000_000;
/// The hook fires this often; the budget is charged in these increments.
const HOOK_INTERVAL: u32 = 100_000;

/// A loaded model: its `generate` function and the card list its
/// `card_names()` returned at load time.
pub struct CompiledModel {
    pub name: String,
    pub generate: Function,
    pub card_names: Vec<String>,
    /// `M.renames` (old card name -> new): cards of a renamed template keep
    /// their review history.
    pub renames: HashMap<String, String>,
    /// `M.allow_card_removal = true`: permit dropping card types that still
    /// have cards (their reviews are lost).
    pub allow_card_removal: bool,
    /// `M.describe()`: one-paragraph summary for authors (and the MCP
    /// context), e.g. which sections/tags the model reads. Optional.
    pub describe: Option<String>,
    /// Modified time of the `.lua` file when it was loaded. Used to
    /// detect on-disk edits so the cache reloads only what changed,
    /// instead of being cleared wholesale every sync cycle.
    mtime: Option<SystemTime>,
}

/// The scripting runtime: one Lua state plus a cache of loaded models.
pub struct ScriptEngine {
    lua: Lua,
    models_dir: PathBuf,
    compiled: HashMap<String, Arc<CompiledModel>>,
    /// Unsaved model sources (previewing a draft over MCP) that shadow
    /// `models/<name>.lua` until [`ScriptEngine::clear_drafts`].
    drafts: HashMap<String, Arc<CompiledModel>>,
    /// Remaining instruction budget for the currently running script,
    /// charged down by the execution hook. Reset before each invocation.
    budget: Rc<Cell<i64>>,
}

impl ScriptEngine {
    /// Create a new engine. `models_dir` holds `<name>.lua` model
    /// scripts; `lib_dir` (if set) is prepended to `package.path` so
    /// scripts can `require` shared libraries.
    pub fn new(models_dir: PathBuf, lib_dir: Option<PathBuf>) -> Self {
        // Model scripts may be written by an LLM over MCP, so they get pure
        // computation only: no io/os/package/debug, and no load/dofile that
        // could read files or run bytecode. Shared libs come in through the
        // restricted `require` installed below.
        let lua = Lua::new_with(
            StdLib::TABLE | StdLib::STRING | StdLib::MATH | StdLib::UTF8 | StdLib::COROUTINE,
            LuaOptions::default(),
        )
        .expect("create sandboxed Lua state");
        {
            let g = lua.globals();
            for name in ["dofile", "loadfile", "load", "collectgarbage"] {
                g.raw_remove(name).expect("strip unsafe global");
            }
        }
        let budget = Rc::new(Cell::new(INSTRUCTION_BUDGET));

        // Charge the budget down every HOOK_INTERVAL instructions and
        // abort once it is exhausted.
        let b = Rc::clone(&budget);
        lua.set_hook(
            HookTriggers::new().every_nth_instruction(HOOK_INTERVAL),
            move |_lua, _debug| {
                let left = b.get() - HOOK_INTERVAL as i64;
                b.set(left);
                if left <= 0 {
                    Err(mlua::Error::runtime("instruction budget exceeded"))
                } else {
                    Ok(mlua::VmState::Continue)
                }
            },
        )
        .expect("install budget hook");

        install_require(&lua, lib_dir).expect("install require");

        Self {
            lua,
            models_dir,
            compiled: HashMap::new(),
            drafts: HashMap::new(),
            budget,
        }
    }

    fn reset_budget(&self) {
        self.budget.set(INSTRUCTION_BUDGET);
    }

    /// Load (or return from cache) a custom model by name. Only reads
    /// `models/<name>.lua`; basic and cloze bypass this engine.
    ///
    /// The cache is keyed on the file's modified time: an unchanged file
    /// is served from cache, an edited one is transparently reloaded.
    pub fn load_model(&mut self, name: &str) -> Result<Arc<CompiledModel>> {
        if let Some(d) = self.drafts.get(name) {
            return Ok(Arc::clone(d));
        }
        let path = self.models_dir.join(format!("{name}.lua"));
        let mtime = std::fs::metadata(&path).and_then(|m| m.modified()).ok();

        if let Some(cached) = self.compiled.get(name) {
            if cached.mtime == mtime {
                return Ok(Arc::clone(cached));
            }
        }

        let source = std::fs::read_to_string(&path)
            .with_context(|| format!("load model script: {}", path.display()))?;
        let compiled = Arc::new(self.compile(name, &source, mtime)?);
        self.compiled.insert(name.to_string(), Arc::clone(&compiled));
        Ok(compiled)
    }

    /// Compile `source` as model `name` and let it shadow the file on disk
    /// for every later [`ScriptEngine::load_model`], until cleared.
    pub fn set_draft(&mut self, name: &str, source: &str) -> Result<Arc<CompiledModel>> {
        let compiled = Arc::new(self.compile(name, source, None)?);
        self.drafts.insert(name.to_string(), Arc::clone(&compiled));
        Ok(compiled)
    }

    pub fn clear_drafts(&mut self) {
        self.drafts.clear();
    }

    fn compile(&self, name: &str, source: &str, mtime: Option<SystemTime>) -> Result<CompiledModel> {
        self.reset_budget();
        let module: Table = self
            .lua
            .load(source)
            .set_name(name)
            .set_mode(ChunkMode::Text)
            .eval()
            .map_err(|e| anyhow::anyhow!("load model '{name}': {e}"))?;

        let generate: Function = module
            .get("generate")
            .map_err(|_| anyhow::anyhow!("model '{name}' must define generate()"))?;
        let card_names = self.extract_card_names(name, &module)?;
        let renames: HashMap<String, String> = module
            .get::<Option<HashMap<String, String>>>("renames")
            .map_err(|e| anyhow::anyhow!("model '{name}': M.renames must map strings to strings: {e}"))?
            .unwrap_or_default();
        let allow_card_removal = module
            .get::<Option<bool>>("allow_card_removal")
            .map_err(|e| anyhow::anyhow!("model '{name}': M.allow_card_removal must be a boolean: {e}"))?
            .unwrap_or(false);

        let describe = match module.get::<Option<Function>>("describe") {
            Ok(Some(f)) => {
                self.reset_budget();
                Some(
                    f.call::<String>(())
                        .map_err(|e| anyhow::anyhow!("model '{name}' describe(): {e}"))?,
                )
            }
            _ => None,
        };

        debug!(model = name, cards = ?card_names, "loaded model");
        Ok(CompiledModel {
            describe,
            name: name.to_string(),
            generate,
            card_names,
            renames,
            allow_card_removal,
            mtime,
        })
    }

    /// Execute a model's `generate(note, ctx)`.
    pub fn execute(
        &self,
        model: &CompiledModel,
        note: crate::note::Note,
        ctx: super::context::RenderContext,
    ) -> Result<ModelOutput> {
        let note_ud = self
            .lua
            .create_userdata(note)
            .map_err(|e| anyhow::anyhow!("wrap note for '{}': {e}", model.name))?;
        let ctx_ud = self
            .lua
            .create_userdata(ctx)
            .map_err(|e| anyhow::anyhow!("wrap ctx for '{}': {e}", model.name))?;

        self.reset_budget();
        let result: Table = model
            .generate
            .call((note_ud, ctx_ud))
            .map_err(|e| anyhow::anyhow!("model '{}' generate(): {e}", model.name))?;

        let mut output = HashMap::new();
        for pair in result.pairs::<String, String>() {
            let (key, html) = pair.map_err(|e| {
                anyhow::anyhow!(
                    "model '{}' generate() fields must be string->string: {e}",
                    model.name
                )
            })?;
            output.insert(key, html);
        }
        Ok(output)
    }

    /// Call `card_names()` on a loaded module to get its template list.
    fn extract_card_names(&self, name: &str, module: &Table) -> Result<Vec<String>> {
        let f: Function = module
            .get("card_names")
            .map_err(|_| anyhow::anyhow!("model '{name}' must define card_names()"))?;

        self.reset_budget();
        let names: Vec<String> = f
            .call(())
            .map_err(|e| anyhow::anyhow!("model '{name}' card_names(): {e}"))?;

        if names.is_empty() {
            bail!("model '{name}' card_names() returned an empty list");
        }
        Ok(names)
    }

    /// Drop a single model from the cache (its file changed on disk).
    pub fn invalidate(&mut self, name: &str) {
        if self.compiled.remove(name).is_some() {
            debug!(model = name, "invalidated cached model");
        }
    }

    /// Drop every cached model.
    pub fn invalidate_all(&mut self) {
        self.compiled.clear();
        debug!("invalidated all cached models");
    }
}

/// A `require` that only loads `<lib_dir>/<name>.lua` as source text.
/// Names are restricted to `[A-Za-z0-9_-]` (with `.` as a dir separator,
/// like stock Lua) so a script cannot escape `lib_dir` or load C modules.
/// Results are cached per name, matching stock `require` semantics.
fn install_require(lua: &Lua, lib_dir: Option<PathBuf>) -> mlua::Result<()> {
    let loaded = lua.create_table()?;
    let require = lua.create_function(move |lua, name: String| {
        if let Ok(v) = loaded.raw_get::<Value>(name.as_str()) {
            if !v.is_nil() {
                return Ok(v);
            }
        }
        let valid = !name.is_empty()
            && name
                .split('.')
                .all(|seg| !seg.is_empty() && seg.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-'));
        if !valid {
            return Err(mlua::Error::runtime(format!("require({name:?}): invalid module name")));
        }
        let Some(lib) = &lib_dir else {
            return Err(mlua::Error::runtime(format!("require({name:?}): no lib_dir configured")));
        };
        let path = lib.join(format!("{}.lua", name.replace('.', "/")));
        let src = std::fs::read_to_string(&path).map_err(|e| {
            mlua::Error::runtime(format!("require({name:?}): {}: {e}", path.display()))
        })?;
        let v: Value = lua
            .load(&src)
            .set_name(format!("@{}", path.display()))
            .set_mode(ChunkMode::Text)
            .eval()?;
        let v = if v.is_nil() { Value::Boolean(true) } else { v };
        loaded.raw_set(name.as_str(), v.clone())?;
        Ok(v)
    })?;
    lua.globals().set("require", require)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_missing_model_errors() {
        let mut se = ScriptEngine::new(PathBuf::from("/nonexistent"), None);
        assert!(se.load_model("does-not-exist").is_err());
    }

    #[test]
    fn basic_cloze_not_loaded_as_scripts() {
        let mut se = ScriptEngine::new(PathBuf::from("/nonexistent"), None);
        // basic and cloze bypass the script engine, so there is no file.
        assert!(se.load_model("basic").is_err());
        assert!(se.load_model("cloze").is_err());
    }

    #[test]
    fn sandbox_blocks_io_os_and_escaping_require() {
        let dir = std::env::temp_dir().join(format!("marki-lua-sandbox-{}", std::process::id()));
        let lib = dir.join("lib");
        std::fs::create_dir_all(&lib).unwrap();
        std::fs::write(lib.join("helper.lua"), "return { x = 42 }").unwrap();

        let se = ScriptEngine::new(dir.clone(), Some(lib));
        let eval = |src: &str| se.lua.load(src).eval::<Value>();

        for probe in [
            "return os.execute('true')",
            "return io.open('/etc/passwd')",
            "return package.loadlib",
            "return debug.getinfo(1)",
            "return dofile('/etc/passwd')",
            "return loadfile('/etc/passwd')",
            "return load('return 1')()",
            "return require('../../etc/passwd')",
            "return require('/etc/passwd')",
        ] {
            let r = eval(probe);
            assert!(
                r.is_err() || matches!(r, Ok(Value::Nil)),
                "sandbox leak: {probe} -> {r:?}"
            );
        }

        // Safe libs and lib_dir require still work.
        let n: i64 = se.lua.load("return require('helper').x + #string.rep('a', 3) + math.floor(1.5)").eval().unwrap();
        assert_eq!(n, 46);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn executes_lua_model_end_to_end() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scripting::context::RenderContext;

        let dir = std::env::temp_dir().join("marki-lua-e2e");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("demo.lua"),
            r#"
local M = {}
function M.card_names() return { "Front", "Back" } end
function M.generate(note, ctx)
  local h = note:heading(1)
  return {
    Front = "Q: " .. (h and h:text() or ""),
    Back = ctx:section_html(note, 2),
  }
end
return M
"#,
        )
        .unwrap();

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("demo").unwrap();
        assert_eq!(compiled.card_names, vec!["Front".to_string(), "Back".to_string()]);

        // A second load of an unchanged file is served from cache.
        let again = se.load_model("demo").unwrap();
        assert!(Arc::ptr_eq(&compiled, &again));

        let note = parse_note(
            "# Berlin\n\n---\n\nCapital of Germany.\n",
            PathBuf::from("/tmp/x.md"),
        );
        let ctx = RenderContext::new(
            Arc::new(Registry::new()),
            PathBuf::from("/tmp/x.md"),
            PathBuf::from("/tmp"),
        );
        let out = se.execute(&compiled, note, ctx).unwrap();
        assert_eq!(out.get("Front").unwrap(), "Q: Berlin");
        assert!(out.get("Back").unwrap().contains("Capital of Germany"));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn instruction_budget_aborts_runaway_scripts() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scripting::context::RenderContext;

        let dir = std::env::temp_dir().join("marki-lua-budget");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("loop.lua"),
            r#"
local M = {}
function M.card_names() return { "Front" } end
function M.generate(note, ctx)
  while true do end
end
return M
"#,
        )
        .unwrap();

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("loop").unwrap();
        let note = parse_note("x\n", PathBuf::from("/tmp/x.md"));
        let ctx = RenderContext::new(
            Arc::new(Registry::new()),
            PathBuf::from("/tmp/x.md"),
            PathBuf::from("/tmp"),
        );
        let err = se.execute(&compiled, note, ctx).unwrap_err().to_string();
        assert!(err.contains("budget"), "expected budget abort, got: {err}");

        std::fs::remove_dir_all(&dir).ok();
    }
}
