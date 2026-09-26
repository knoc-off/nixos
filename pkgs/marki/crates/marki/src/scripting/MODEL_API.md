# marki model API

A model is `.marki/models/<name>.lua` (plus optional `<name>.css`), used by
cards tagged `#model(<name>)`. It becomes the Anki note type `marki:<name>`.

```lua
local M = {}

-- Card types, in order. A list, or a function returning one.
M.card_names = { "Forward", "Reverse" }

-- Required: one short paragraph for authors (which sections/tags it reads).
function M.describe()
  return "Section 1 and 2 are two sides; #one-way skips the reverse card."
end

-- Called once per note. Return HTML per field. Keys are <Card>Front and
-- <Card>Back for each name in card_names; any other key is an error. A card
-- whose Front is empty or missing is not created; a note with no cards at
-- all is an error. The answer side shows only <Card>Back: to keep the
-- question visible there, include it, e.g. a .. "<hr id=answer>" .. b.
function M.generate(note, ctx)
  local a, b = ctx:section_html(note, 1), ctx:section_html(note, 2)
  local f = { ForwardFront = a, ForwardBack = b }
  if not note:has_tag("one-way") then
    f.ReverseFront, f.ReverseBack = b, a
  end
  return f
end

return M
```

## Rendering: use ctx, not raw blocks

`ctx:section_html(note, n)` and `ctx:body_html(note)` render blocks exactly
like the built-in models do: they render ```` ```media ````, ```` ```map ````
and ```` ```typst ```` blocks and collect their files, turn ```` ```math ````
into display math, and highlight code. **`block:html()` does not.** On a code
block it returns the raw source, so a media block built with it shows up as
text and its file is never pushed. Use block methods for *deciding* (text,
language), and ctx for *output*.

- `ctx:section_html(note, n)` -> string. Section `n` (1-based) rendered.
  Sections are split by `---` lines.
- `ctx:body_html(note)` -> string. The whole note rendered.
- `ctx:render(lang, source)` -> `{ front_html, back_html, assets }`. Renders
  one block given as source text. `back_html` is extra content for the
  answer side (for example map labels).

## note

Indices are 1-based. A missing element returns `nil` (for lists, `{}`).

- `note:sections()` -> list of sections, each a list of blocks.
  `note:section(n)` -> list of blocks.
- `note:paragraphs()`, `note:paragraph(n)`.
- `note:headings()`, `note:heading(n)`.
- `note:code_blocks(lang)`, `note:code_block(lang)` -> the fenced blocks
  with that language.
- `note:lists()`, `note:blockquotes()`.
- `note:has_tag(name)` -> bool. `note:tag(name)` -> tag value or nil.
  - `#flag` gives `v:is_bool() == true`.
  - `#deck(x)` gives `v:value() == "x"`; `tostring(v)` works too.
- `note:anki_tags()` -> list of strings. These are the tags Anki will get.
- `note:id()`, `note:model()`, `note:source()` (raw markdown).

## block

- `block:text()` -> plain text. Empty for lists and tables.
- `block:html()` -> inline HTML of prose blocks, **raw source of code blocks**
  (see above).
- `block:lang()`, `block:source()` -> code blocks only, else nil.

## Changing a model that already has cards

Appending card names is always safe. Renaming or reordering card types moves
review history only when you say how:

- `M.renames = { OldName = "NewName" }` keeps a renamed card type's cards and
  reviews.
- `M.allow_card_removal = true` permits dropping a card type that still has
  cards. Their reviews are lost, so get the user's consent first.

A changed card list (anything but css) bumps the collection schema. Every
device then needs a one-way full sync; `marki_push` reports this as
`full_sync_required`.

## Math

`$x$` is inline math and `$$x$$` is display math, in cards and in rendered
sections alike. So is a ```` ```math ```` block. Anki shows them with MathJax.

## Built-in models

`basic` and `cloze` are built in, not Lua. `marki_read_model` shows each one
as an equivalent Lua model for reference.
