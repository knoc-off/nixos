# marki-render

This crate defines how block renderers plug into marki. It contains only
types: no I/O and no dependencies on other marki crates. `marki-map`,
`marki-media` and `marki-typst` each implement the trait, and the `marki` CLI
dispatches to them.

## The trait

```rust
pub trait Renderer: Send + Sync {
    /// Fence language, e.g. "map". Also used as the name for script-side constructors.
    fn lang(&self) -> &'static str;
    fn render(&self, input: Input<'_>, ctx: &mut RenderCtx<'_>) -> Result<Fragment, RenderError>;
}
```

- `Input::Raw(&str)` is the verbatim fence body. `Input::Spec(toml::Value)` is
  an already-structured value from a script. `input.deserialize::<MySpec>()`
  handles both.
- `RenderCtx` carries `source_path` (the card's `.md` path) and `cache_dir`.
- `Fragment { html, reveal, assets }`:
  - `html` goes on the side where the block was written.
  - `reveal` is added to the back of the card, usually a `<style>` that
    uncovers something hidden on the front.
  - `assets` are files uploaded to Anki's media collection. Give them
    content-addressed filenames so identical files are only stored once.
- `escape_html` is provided for building HTML safely.

## Adding a block type

1. Create a crate `crates/marki-<name>` that depends only on `marki-render`
   (plus its own dependencies), and implement `Renderer`.
2. Add it to the workspace `members` and `[workspace.dependencies]` in the root
   `Cargo.toml`.
3. Register it in `build_registry` in `crates/marki/src/main.rs`:

   ```rust
   reg.register(Box::new(MyRenderer::new()));
   ```

That's all. The parser then treats ` ```<name> ` fences as raw input instead of
highlighting them, and Lua models can call `ctx:render("<name>", src)`. Two
renderers can't register the same `lang`; marki panics at startup if they do.
