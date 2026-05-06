//! Rhai engine setup and script execution.

use anyhow::{Context, Result, bail};
use rhai::{AST, Dynamic, Engine, Map, Scope};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tracing::debug;

use super::types::register_types;

/// Output of running a model script's `generate()` function.
/// Maps field names (e.g., "LocateFront", "LocateBack") to HTML strings.
pub type ModelOutput = HashMap<String, String>;

/// A compiled and cached model script.
pub struct CompiledModel {
    pub name: String,
    pub ast: AST,
    pub card_names: Vec<String>,
}

/// The scripting runtime. Wraps a configured Rhai `Engine` and a cache
/// of compiled model scripts.
pub struct ScriptEngine {
    engine: Engine,
    models_dir: PathBuf,
    compiled: HashMap<String, Arc<CompiledModel>>,
}

impl ScriptEngine {
    /// Create a new script engine. `models_dir` is the directory
    /// containing `.rhai` model scripts. `lib_dir` is for shared
    /// libraries importable via `import "lib/..." as ...`.
    pub fn new(models_dir: PathBuf, lib_dir: Option<PathBuf>) -> Self {
        let mut engine = Engine::new();

        // Register our custom types (Note, Block, etc.) into the engine.
        register_types(&mut engine);

        // Set up module resolver for shared libraries.
        if let Some(lib) = lib_dir {
            let resolver = rhai::module_resolvers::FileModuleResolver::new_with_path(lib);
            engine.set_module_resolver(resolver);
        }

        // Limit script execution to prevent runaway scripts.
        engine.set_max_operations(1_000_000);
        engine.set_max_expr_depths(64, 64);

        Self {
            engine,
            models_dir,
            compiled: HashMap::new(),
        }
    }

    /// Load (or retrieve from cache) a custom model by name.
    /// Only loads from `models/<name>.rhai` on disk. Basic and cloze
    /// cards bypass the script engine entirely.
    pub fn load_model(&mut self, name: &str) -> Result<Arc<CompiledModel>> {
        // Check cache first.
        if let Some(cached) = self.compiled.get(name) {
            return Ok(Arc::clone(cached));
        }

        // Load source from disk.
        let path = self.models_dir.join(format!("{name}.rhai"));
        let source = std::fs::read_to_string(&path)
            .with_context(|| format!("load model script: {}", path.display()))?;

        // Compile.
        let ast = self.engine.compile(&source)
            .map_err(|e| anyhow::anyhow!("compile model '{name}': {e}"))?;

        // Extract card_names by calling the function.
        let card_names = self.extract_card_names(name, &ast)?;

        debug!(model = name, cards = ?card_names, "compiled model");

        let compiled = Arc::new(CompiledModel {
            name: name.to_string(),
            ast,
            card_names,
        });
        self.compiled.insert(name.to_string(), Arc::clone(&compiled));
        Ok(compiled)
    }

    /// Execute a model's `generate(note, ctx)` function.
    ///
    /// Returns a map of field names → HTML strings. The caller maps
    /// these to Anki note fields based on `card_names`.
    pub fn execute(
        &self,
        model: &CompiledModel,
        note: Dynamic,
        ctx: Dynamic,
    ) -> Result<ModelOutput> {
        let mut scope = Scope::new();

        let result: Dynamic = self.engine
            .call_fn(&mut scope, &model.ast, "generate", (note, ctx))
            .map_err(|e| anyhow::anyhow!("model '{}' generate(): {e}", model.name))?;

        // Convert the Rhai Map to our ModelOutput.
        let type_name = result.type_name().to_string();
        let map = result.try_cast::<Map>()
            .ok_or_else(|| anyhow::anyhow!(
                "model '{}' generate() must return a Map, got {}",
                model.name, type_name
            ))?;

        let mut output = HashMap::new();
        for (key, val) in map {
            let html = val.into_string()
                .map_err(|e| anyhow::anyhow!(
                    "model '{}' field '{}' must be a string: {e:?}",
                    model.name, key
                ))?;
            output.insert(key.to_string(), html);
        }
        Ok(output)
    }

    /// Call `card_names()` on a compiled model to get the template list.
    fn extract_card_names(&self, name: &str, ast: &AST) -> Result<Vec<String>> {
        let mut scope = Scope::new();
        let result: Dynamic = self.engine
            .call_fn(&mut scope, ast, "card_names", ())
            .map_err(|e| anyhow::anyhow!("model '{name}' card_names(): {e}"))?;

        let arr = result.into_array()
            .map_err(|e| anyhow::anyhow!(
                "model '{name}' card_names() must return an array: {e:?}"
            ))?;

        let mut names = Vec::new();
        for item in arr {
            let s = item.into_string()
                .map_err(|e| anyhow::anyhow!(
                    "model '{name}' card_names() entries must be strings: {e:?}"
                ))?;
            names.push(s);
        }

        if names.is_empty() {
            bail!("model '{name}' card_names() returned empty array");
        }
        Ok(names)
    }

    /// Invalidate the cache for a specific model (e.g., when its file
    /// changes on disk).
    pub fn invalidate(&mut self, name: &str) {
        if self.compiled.remove(name).is_some() {
            debug!(model = name, "invalidated cached model");
        }
    }

    /// Invalidate all cached models.
    pub fn invalidate_all(&mut self) {
        self.compiled.clear();
        debug!("invalidated all cached models");
    }
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
        // basic and cloze should NOT be loadable — they bypass Rhai.
        assert!(se.load_model("basic").is_err());
        assert!(se.load_model("cloze").is_err());
    }
}
