//! Lua engine setup and model-script execution.
//!
//! A model script is a Lua module; the full author-facing reference is
//! `MODEL_API` (served to agents as `marki://docs/models`). In short:
//!
//! ```lua
//! local M = {}
//! M.card_names = { "Forward", "Reverse" }  -- or a function returning it
//! function M.describe() return "..." end
//! function M.generate(note, ctx)
//!   return { ForwardFront = "...", ForwardBack = "...",
//!            ReverseFront = "...", ReverseBack = "..." }
//! end
//! return M
//! ```
//!
//! `generate` keys are `<Card>Front`/`<Card>Back`; any other key is an error.
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

impl CompiledModel {
    /// The keys `generate` may return, in ord order.
    pub fn field_names(&self) -> Vec<String> {
        self.card_names
            .iter()
            .flat_map(|c| [format!("{c}Front"), format!("{c}Back")])
            .collect()
    }
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
        // A misspelled key used to become an empty field, i.e. a silently
        // missing card. Reject it and name the valid keys.
        let valid = model.field_names();
        let mut unknown: Vec<&String> = output.keys().filter(|k| !valid.contains(k)).collect();
        if !unknown.is_empty() {
            unknown.sort();
            bail!(
                "model '{}' generate() returned unknown key(s) {}; valid keys are {} \
                 (<Card>Front / <Card>Back for each name in card_names)",
                model.name,
                unknown.iter().map(|k| format!("{k:?}")).collect::<Vec<_>>().join(", "),
                valid.join(", ")
            );
        }
        Ok(output)
    }

    /// `M.card_names`: a list of names, or a function returning one.
    fn extract_card_names(&self, name: &str, module: &Table) -> Result<Vec<String>> {
        let names: Vec<String> = match module.get::<Value>("card_names") {
            Ok(Value::Function(f)) => {
                self.reset_budget();
                f.call(()).map_err(|e| anyhow::anyhow!("model '{name}' card_names(): {e}"))?
            }
            Ok(v @ Value::Table(_)) => self
                .lua
                .unpack(v)
                .map_err(|e| anyhow::anyhow!("model '{name}' card_names must list strings: {e}"))?,
            _ => bail!(
                "model '{name}' must define M.card_names, e.g. M.card_names = {{ \"Card\" }}"
            ),
        };
        if names.is_empty() {
            bail!("model '{name}' card_names is empty");
        }
        let mut seen = std::collections::HashSet::new();
        for n in &names {
            if n.is_empty() || !n.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-' || c == ' ') {
                bail!("model '{name}' card name {n:?}: use letters, digits, space, _ or -");
            }
            if !seen.insert(n) {
                bail!("model '{name}' card name {n:?} appears twice");
            }
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
M.card_names = { "Card" }
function M.generate(note, ctx)
  local h = note:heading(1)
  return {
    CardFront = "Q: " .. (h and h:text() or ""),
    CardBack = ctx:section_html(note, 2),
  }
end
return M
"#,
        )
        .unwrap();

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("demo").unwrap();
        assert_eq!(compiled.card_names, vec!["Card".to_string()]);

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
        assert_eq!(out.get("CardFront").unwrap(), "Q: Berlin");
        assert!(out.get("CardBack").unwrap().contains("Capital of Germany"));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ctx_notes_filters_sorts_excludes_self_and_is_capped() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scan::ScannedNote;
        use crate::scripting::context::{NoteIndex, RenderContext};

        let dir = std::env::temp_dir().join(format!("marki-lua-notes-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("demo.lua"),
            r#"
local M = {}
M.card_names = { "Card" }
function M.generate(note, ctx)
  local out = {}
  for _, n in ipairs(ctx:notes{ tag = "history" }) do
    out[#out + 1] = n:path() .. "|" .. n:deck() .. "|" .. n:heading(1):text() .. "|" .. tostring(n:tag("date"))
  end
  local geo = #ctx:notes{ deck = "Geo" }
  local ok, err = pcall(function() return ctx:notes{} end)
  return { CardFront = table.concat(out, ";"), CardBack = geo .. " " .. tostring(ok) .. " " .. tostring(err) }
end
return M
"#,
        )
        .unwrap();
        let root = dir.join("cards");
        let scanned = |rel: &str, src: &str| {
            let path = root.join(rel);
            ScannedNote { note: parse_note(src, path.clone()), path, source: src.into() }
        };
        let notes = vec![
            scanned("hist/b.md", "# Fire\n\n#id(b1) #history #date(1666-09-02)\n"),
            scanned("hist/a.md", "# Plague\n\n#id(a1) #history #date(1665)\n"),
            scanned("hist/self.md", "# Me\n\n#id(c1) #history\n"),
            scanned("hist/draft.md", "# No id\n\n#history\n"),
            scanned("Geo/Rivers/r.md", "# Rhine\n\n#id(d1)\n"),
            scanned("Geography/g.md", "# Not Geo\n\n#id(e1)\n"),
        ];
        let index = Arc::new(NoteIndex::new(&root, &notes));

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("demo").unwrap();
        let me = &notes[2];
        let ctx = RenderContext::new(Arc::new(Registry::new()), me.path.clone(), dir.join("cache"))
            .with_index(Some(index));
        let out = se.execute(&compiled, me.note.clone(), ctx.clone()).unwrap();
        assert_eq!(
            out.get("CardFront").unwrap(),
            "hist/a.md|hist|Plague|1665;hist/b.md|hist|Fire|1666-09-02",
            "sorted by path, self and unformatted notes excluded"
        );
        let back = out.get("CardBack").unwrap();
        assert!(back.starts_with("1 false "), "deck prefix on :: boundaries: {back}");
        assert!(back.contains("at least one"), "{back}");
        assert!(ctx.read_other_notes());

        // Query limit.
        std::fs::write(
            dir.join("greedy.lua"),
            "local M = {}\nM.card_names = { \"Card\" }\nfunction M.generate(note, ctx)\n  for i = 1, 17 do ctx:notes{ tag = \"history\" } end\n  return { CardFront = \"x\" }\nend\nreturn M\n",
        )
        .unwrap();
        let greedy = se.load_model("greedy").unwrap();
        let ctx = RenderContext::new(Arc::new(Registry::new()), me.path.clone(), dir.join("cache"))
            .with_index(Some(Arc::new(NoteIndex::new(&root, &notes))));
        let err = se.execute(&greedy, me.note.clone(), ctx).unwrap_err().to_string();
        assert!(err.contains("more than 16"), "{err}");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ctx_geo_looks_up_any_map_ref() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scripting::context::RenderContext;

        let dir = std::env::temp_dir().join(format!("marki-lua-geo-{}", std::process::id()));
        let geo_dir = dir.join(".marki/geo");
        std::fs::create_dir_all(&geo_dir).unwrap();
        std::fs::write(
            geo_dir.join("zoo.geojson"),
            r#"{"type":"Point","coordinates":[13.3325,52.5075]}"#,
        )
        .unwrap();
        std::fs::write(
            dir.join("demo.lua"),
            r#"
local M = {}
M.card_names = { "Card" }
function M.generate(note, ctx)
  local g = ctx:geo("geo/zoo")
  return { CardFront = g.kind .. " " .. g.center[1] .. "," .. g.center[2], CardBack = "x" }
end
return M
"#,
        )
        .unwrap();

        let mut registry = Registry::new();
        registry.register(Box::new(marki_map::MapRenderer::new().with_geo_dir(geo_dir)));

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("demo").unwrap();
        let note = parse_note("x\n", PathBuf::from("/tmp/x.md"));
        let ctx = RenderContext::new(Arc::new(registry), PathBuf::from("/tmp/x.md"), dir.join("cache"));
        let out = se.execute(&compiled, note, ctx).unwrap();
        assert_eq!(out.get("CardFront").unwrap(), "point 13.3325,52.5075");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ctx_render_map_reports_frame_and_xy() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scripting::context::RenderContext;

        let dir = std::env::temp_dir().join(format!("marki-lua-mapxy-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("demo.lua"),
            r#"
local M = {}
M.card_names = { "Card" }
function M.generate(note, ctx)
  local r = ctx:render("map", "[viewport]\nbbox = [10.0, 45.0, 20.0, 55.0]\n[layers.base]\n")
  local x, y = r.xy(15.0, 50.0)
  return {
    CardFront = string.format("%d %d %.1f %.1f", r.map.width, r.map.height, x, y),
    CardBack = "x",
  }
end
return M
"#,
        )
        .unwrap();

        let mut registry = Registry::new();
        registry.register(Box::new(marki_map::MapRenderer::new()));

        let mut se = ScriptEngine::new(dir.clone(), None);
        let compiled = se.load_model("demo").unwrap();
        let note = parse_note("x\n", PathBuf::from("/tmp/x.md"));
        let ctx = RenderContext::new(Arc::new(registry), PathBuf::from("/tmp/x.md"), dir.join("cache"));
        let out = se.execute(&compiled, note, ctx).unwrap();
        let front = out.get("CardFront").unwrap();
        let parts: Vec<&str> = front.split(' ').collect();
        let (w, h): (f64, f64) = (parts[0].parse().unwrap(), parts[1].parse().unwrap());
        let (x, y): (f64, f64) = (parts[2].parse().unwrap(), parts[3].parse().unwrap());
        assert!(w > 0.0 && h > 0.0, "{front}");
        // (15, 50) is the bbox's midpoint -> roughly (but not exactly,
        // Mercator stretches y) at 50% x, near 50% y.
        assert!((x - 50.0).abs() < 1.0, "{front}");
        assert!((45.0..55.0).contains(&y), "{front}");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn generate_keys_and_card_names_are_validated() {
        use crate::note_parser::parse_note;
        use crate::render::Registry;
        use crate::scripting::context::RenderContext;

        let se = ScriptEngine::new(std::env::temp_dir(), None);
        let run = |src: &str| -> Result<ModelOutput> {
            let m = se.compile("t", src, None)?;
            let note = parse_note("x\n", PathBuf::from("/tmp/x.md"));
            let ctx = RenderContext::new(Arc::new(Registry::new()), PathBuf::from("/tmp/x.md"), PathBuf::from("/tmp"));
            se.execute(&m, note, ctx)
        };
        // The pre-fix trap: keys named after the card, not <Card>Front/Back.
        let err = run(r#"return { card_names = {"A","B"},
            generate = function() return { A = "x", B = "y" } end }"#)
            .unwrap_err()
            .to_string();
        assert!(err.contains(r#"unknown key(s) "A", "B""#) && err.contains("AFront, ABack, BFront, BBack"), "{err}");
        // card_names as a function still works.
        assert!(run(r#"return { card_names = function() return {"A"} end,
            generate = function() return { AFront = "x" } end }"#).is_ok());
        for (src, want) in [
            (r#"return { generate = function() end }"#, "must define M.card_names"),
            (r#"return { card_names = {}, generate = function() end }"#, "is empty"),
            (r#"return { card_names = {"A","A"}, generate = function() end }"#, "appears twice"),
            (r#"return { card_names = {"a{b"}, generate = function() end }"#, "use letters"),
        ] {
            let err = se.compile("t", src, None).err().map(|e| e.to_string()).unwrap_or_default();
            assert!(err.contains(want), "{src}: {err}");
        }
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
