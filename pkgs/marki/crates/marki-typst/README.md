# marki-typst

Renders ` ```typst ` blocks to SVG by running the `typst` CLI.

This renderer is only active when `typst_binary` is set, either in the config
or with `MARKI_TYPST` / `--typst-binary`. Without it, typst blocks are shown as
syntax-highlighted source.

```toml
typst_binary = "${TYPST_BIN:-typst}"
```

## Syntax

Unlike `map` and `media`, the block body is plain Typst source, not TOML:

````markdown
What is the Gaussian integral?

---

```typst
$ integral_0^oo e^(-x^2) dif x = sqrt(pi) / 2 $
```
````

Anything the `typst` binary supports works here, including math, `#import`, and
`@preview/...` packages.

## Details

- marki adds this line before your source:
  `#set page(width: auto, height: auto, margin: 0pt, fill: none)`. The page
  shrinks to fit the content and has a transparent background. Your own
  `#set page(...)` comes later, so it takes precedence.
- The card's directory is the Typst root, so `#image("diagram.png")` resolves
  relative to the `.md` file.
- The output SVG is placed in a `div.marki-typst` and scales down to fit
  narrow screens.
- Compiled SVGs are cached, keyed by a hash of the source. A block that hasn't
  changed never runs typst again.
- If compilation fails, the typst error appears in a red box on the card.
