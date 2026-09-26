# Models

A model is a custom card type written in Lua. One note can produce several
cards. Select a model with a tag in the card:

```markdown
#model(geographic-location)
```

marki then loads `<models_dir>/geographic-location.lua`, where `models_dir`
defaults to `.marki/models/`. `basic` and `cloze` are built in and need no
script.

This directory holds an example. Copy what you need into your project's
`.marki/models/`.

## Contract

A model is a Lua 5.4 module that returns a table with `card_names`,
`generate` and `describe`:

```lua
local M = {}

-- One Anki card template per name. A list, or a function returning one.
M.card_names = { "Recall" }

-- One short paragraph for authors (required by marki_write_model).
function M.describe() return "Heading 1 asks, section 2 answers." end

-- Field name -> HTML. Fields are named <CardName>Front and <CardName>Back.
function M.generate(note, ctx)
  local h = note:heading(1)
  return {
    RecallFront = "<p>" .. (h and h:text() or "") .. "</p>",
    RecallBack  = ctx:section_html(note, 2),
  }
end

return M
```

- `card_names` must be a non-empty list of unique names (letters, digits,
  `_`, `-`, space).
- `generate()` must return a table mapping strings to strings. Keys other than
  `<Card>Front` / `<Card>Back` are an error naming the valid ones.
- If a Front is missing or empty, Anki doesn't generate that card. Use this to
  skip cards that don't apply, like a flag card for a note without a flag. A
  note that produces no card at all is an error.
- The answer side shows only `<Card>Back`. To keep the question visible
  there, include it in the Back.
- An optional `<name>.css` next to the script becomes the note type's styling.
  Without one, marki uses a small built-in stylesheet.
- Shared helpers go in `lib_dir` (default `.marki/lib/`) and are loaded with
  `require "helper"`.
- Each `generate()` call is limited to about 50M Lua instructions, so an
  infinite loop fails instead of hanging.
- Scripts reload automatically when the file changes, including in `watch`.

Scripts run in a sandbox: only `string`, `table`, `math`, `utf8` and
`coroutine` are available. There is no `io`, `os`, `load` or `dofile`, and
`require` only loads `.lua` files from `lib_dir`.

## Changing a model that's in use

Anki cards belong to a card type, and review history belongs to cards. marki
keeps history wherever a card type survives a change:

| Change in `card_names()`       | What happens                                               |
| ------------------------------ | ---------------------------------------------------------- |
| Append a name                  | New cards are generated for existing notes                 |
| Reorder names                  | Cards follow their name; history kept                      |
| Rename (declare it, below)     | Cards follow the new name; history kept                    |
| Remove a name                  | Refused while cards use it, unless allowed (below)         |

```lua
local M = {
  renames = { Ask = "Question" },  -- old card name -> new
  allow_card_removal = true,       -- drop removed card types and their history
}
```

Once a push has applied a rename, the `renames` entry can be deleted.

A model that can't be updated (for example a refused removal) is reported as
an error and only its own notes are skipped; the rest of the push goes ahead.
Anything other than an append or a CSS change is a schema change, so devices
need a full sync afterwards (choose **download**).

Changing a single note's `#model` works the same way: cards whose card type
exists in both models keep their history.

## API

Indices are 1-based. An out-of-range index returns `nil`, or an empty table for
list methods.

### `note`

| Method                    | Returns                                              |
| ------------------------- | ---------------------------------------------------- |
| `note:id()`               | The `#id` hex string                                 |
| `note:model()`            | Model name                                           |
| `note:source()`           | The raw markdown                                     |
| `note:anki_tags()`        | List of tag strings                                  |
| `note:sections()`         | List of sections, each a list of blocks              |
| `note:section(n)`         | List of blocks in section `n`                        |
| `note:headings()` / `note:heading(n)` | Heading blocks / the nth heading         |
| `note:paragraphs()` / `note:paragraph(n)` | Paragraph blocks / the nth paragraph |
| `note:code_blocks(lang)`  | All fenced blocks with that language                 |
| `note:code_block(lang)`   | The first one, or `nil`                              |
| `note:lists()`            | List blocks                                          |
| `note:blockquotes()`      | Blockquote blocks                                    |
| `note:tag(name)`          | A `TagValue`, or `nil`                               |
| `note:has_tag(name)`      | Boolean                                              |

### Block

| Method           | Returns                                   |
| ---------------- | ----------------------------------------- |
| `block:text()`   | Plain text                                |
| `block:html()`   | Inline HTML of prose; **raw source for code blocks** |
| `block:lang()`   | Fence language, for code blocks           |
| `block:source()` | Raw fence body, for code blocks           |

`block:html()` does not run block renderers, so a ` ```media ` block built
with it shows as text and its file is never pushed. Use block methods to
decide, and `ctx:section_html` / `ctx:body_html` to output.

### TagValue

`#country(JAM)` gives `note:tag("country"):value() == "JAM"`. For a bare
`#flag`, `value()` returns `true` and `is_bool()` is true. `tostring(tag)` also
works.

### `ctx`

| Method                        | Returns                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `ctx:render(lang, source)`    | `{ front_html, back_html, assets }`. Runs a block renderer such as `map`, `media` or `typst` on raw source |
| `ctx:section_html(note, n)`   | Section `n` rendered to HTML, including any blocks inside it            |
| `ctx:body_html(note)`         | The whole note rendered to HTML                                         |

`back_html` is the reveal part of a block: for a map, it's a `<style>` that
shows the answer layer. Put `front_html` alone on the front of the card, and
`front_html .. back_html` on the back. Assets from any of these calls are
uploaded to Anki automatically.

## Example: `geographic-location`

One note describes a country, and up to 4 cards come from it:

| Card            | Front                  | Back                     | Requires           |
| --------------- | ---------------------- | ------------------------ | ------------------ |
| `Locate`        | "Where is X?" + map    | Map with answer + facts  | always             |
| `Identify`      | Map with answer        | Name + facts             | a ` ```map ` block |
| `FlagToCountry` | Flag                   | Name + map               | a ` ```media ` block |
| `CountryToFlag` | "What is the flag of X?" | Flag + map             | a heading + media  |

The card it expects:

````markdown
# Jamaica

```map
[layers.base]
features = ["country/JAM"]
context = ["neighbors/JAM"]

[layers.answer]
highlights = ["country/JAM"]
```

```media
src = "flags/jm"
```

---

- Capital: Kingston
- Population: ~2.8M

#model(geographic-location) #geography
````

How the script uses it:

- `note:heading(1)` gives the name (`Jamaica`).
- `note:code_block("map")` goes through `ctx:render("map", ...)`, producing a
  hidden-answer version (`front_html`) and a revealed one
  (`front_html .. back_html`).
- `note:code_block("media")` provides the flag.
- `ctx:section_html(note, 2)` renders everything after `---` as the facts.
- Each card's fields are only set when the block they need exists, so a note
  without a flag gets 2 cards instead of 4.

`geographic-location.css` is plain Anki card CSS (`.card`, `.card img`,
`.answer-divider`).
