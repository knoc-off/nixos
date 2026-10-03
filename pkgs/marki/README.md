# marki

Syncs a directory of markdown flashcards into Anki. There's no AnkiConnect and
no add-on: marki is one more Anki device. It keeps its own collection, writes
cards into it through SQLite the way Anki does, and syncs it with an Anki sync
server (anki-sync-server, or anything Anki itself syncs with) using Anki's own
library. Your phone and desktop get the cards on their next sync, and reviews
made there are never touched.

A push pulls the server's changes first, then writes, then syncs back up.
`status`, `check` and `marki_query` work offline against the copy as of its
last sync. Without `[sync]`, marki only writes the local collection, which is
how to write straight into Anki desktop's profile (with Anki closed).

## Quick start

```sh
marki init                  # create .marki/ (config.toml, models/, lib/, media/)
$EDITOR geography/france.md
marki fmt                   # mint ids, normalize formatting
marki status                # preview what would change
marki push                  # pull, write, sync
```

Set `[sync]` in `.marki/config.toml` first (see [Config](#config)). The first
push downloads the server's collection; later ones only exchange changes.

## Writing cards

One `.md` file is one note. There's no frontmatter.

```markdown
What is the capital of France?

---

**Paris**, on the Seine.

#id(3f9a1c2b6e4d5078a1b2c3d4e5f60718) #geography
```

### Sections

A `---` line splits the note into sections:

| Section | Basic card | Cloze card   | Custom model          |
| ------- | ---------- | ------------ | --------------------- |
| 1       | Front      | Text         | `note:section(1)`     |
| 2       | Back       | Back Extra   | `note:section(2)`     |
| 3+      | ignored    | ignored      | available to the model |

### Tags

Tags start with `#` and can go anywhere in the prose. `marki fmt` moves them all
to a single line at the end of the file. A `#` inside a code block or inline
code is left alone.

| Tag                                 | Meaning                                                                 |
| ----------------------------------- | ----------------------------------------------------------------------- |
| `#id(<hex>)`                        | Note identity (the Anki guid). Minted by `marki fmt`; don't write it by hand |
| `#basic`                            | Front/back card. This is the default                                    |
| `#cloze` / `#cloze(mode)`           | Cloze card; see [Cloze](#cloze)                                         |
| `#model(name)`                      | Custom card type from `.marki/models/name.lua`; see [models/](models/README.md) |
| `#deck(a::b)`                       | Put the note in deck `a::b` instead of the one from its directory. Not an Anki tag |
| `#name(value)`                      | Parametric tag. Becomes an Anki tag, and models can read it with `note:tag("name")` |
| `#name`                             | Plain Anki tag. `::` makes a hierarchy: `#geo::europe`                  |

A tag name must start with a letter and can contain letters, digits, `_`, `-`
and `:`. A malformed tag, such as `#cloze(` with no closing paren, stays in the
text and marki prints a warning.

### Cloze

Don't write `{{c1::...}}` by hand. Mark the answers with **bold** or *italic*,
then add `#cloze`:

| Mode                 | Numbering                                                 |
| -------------------- | --------------------------------------------------------- |
| `#cloze(increment)`  | Every bold or italic span gets the next number: c1, c2, c3 ... |
| `#cloze(duo)`        | Bold -> c1, italic -> c2                                   |
| `#cloze(auto)`       | `duo` if the note uses both bold and italic, otherwise `increment` |
| `#cloze`             | Same as `auto`                                             |

```markdown
The three largest countries are **Russia**, **Canada** and **China**.

#cloze
```

gives `{{c1::Russia}}`, `{{c2::Canada}}` and `{{c3::China}}`.

### Decks

The deck comes from the file's directory, relative to `cards_dir`, unless the
note has a `#deck(...)` tag:

```
geography/europe/france.md  ->  geography::europe
france.md                   ->  Default
```

Moving a file moves the note to the new deck and keeps its review history,
because the note is identified by its `#id`.

### Changing a note's type

Switching a note between `basic`, `cloze` and custom models (e.g. adding
`#cloze`) changes it in place, like Anki's "Change Note Type": cards whose
card type exists in both keep their review history, the rest are replaced.
Between basic and cloze, the first card carries over as `c1`.

This is a schema change: the next sync on every device asks for a full sync.
Choose **download** there, or the device overwrites what marki just pushed.

### Code blocks

| Fence                  | Renders as                                                              |
| ---------------------- | ----------------------------------------------------------------------- |
| ` ```map `             | SVG map, with an answer layer revealed on flip. [marki-map](crates/marki-map/README.md) |
| ` ```media `           | Image or audio from a media source. [marki-media](crates/marki-media/README.md) |
| ` ```typst `           | Typst compiled to SVG. Needs `typst_binary`. [marki-typst](crates/marki-typst/README.md) |
| ` ```math ` / ` ```latex ` | Wrapped in `\[...\]` for Anki's MathJax                             |
| ` ```<anything else> ` | Syntax-highlighted with inline styles, so no extra CSS is needed        |
| ` ```_map ` etc.       | A leading `_` skips the renderer and just shows the highlighted source  |

If a block fails to render, the error appears in a red box on the card and the
rest of the note still syncs.

Other markdown works as usual, including tables and ~~strikethrough~~.
`$x$` is inline math and `$$x$$` display math (write `\$` for a literal
dollar).

## Formatting rules

`marki fmt` puts every card into canonical form. It only touches files on disk
and never opens Anki:

- A new note gets a random 128-bit `#id(...)`. An existing id is never changed.
- All tags move to one trailing line, with `#id` first and the rest in source
  order, without duplicates.
- Line endings become LF and trailing whitespace is removed.
- Runs of blank lines collapse to one, and blank lines at the start and end of
  the file are removed.
- The file ends in exactly one newline.
- Running it twice changes nothing.
- A duplicate `#id` across files is an error, which usually comes from copying
  a card. Delete the `#id` from the copy and run `fmt` again.

`marki status` lists files that `fmt` would change.

## Config

`.marki/config.toml`. marki finds it by walking up from the current directory,
the way git finds `.git`. Every key is optional. String values support `$VAR`,
`${VAR}`, `${VAR:-default}` and a leading `~`. Relative paths are resolved from
the directory that contains `.marki/`.

| Key             | Default              | Purpose                                                     |
| --------------- | -------------------- | ----------------------------------------------------------- |
| `sync`          | none                 | `endpoint`, `username` and `password_file` of the Anki sync server. Without it, pushes only write the local collection |
| `collection`    | state dir            | marki's own collection; media go in the sibling `<name>.media/`. Default `$XDG_STATE_HOME/marki/<repo>-<hash>/collection.anki2` |
| `cards_dir`     | project root         | Where to look for cards                                     |
| `models_dir`    | `.marki/models`      | Lua card types                                              |
| `lib_dir`       | `.marki/lib`         | Shared Lua modules for `require`                            |
| `media_sources` | `{}`                 | Named directories for ` ```media ` blocks; `.marki/media` is always searched first |
| `typst_binary`  | none                 | `typst` executable. If unset, typst blocks are only highlighted |
| `map`           | none                 | `[map.defaults]` and `[[map.rules]]` for map blocks, merged under each card's own block |
| `sync_interval` | `300`                | `watch` heartbeat in seconds, or `"5m"`, `"1h"`, `"1d"`     |
| `debounce_ms`   | `250`                | How long `watch` waits after a file change                  |

```toml
typst_binary = "${TYPST_BIN:-typst}"

[sync]
endpoint = "http://127.0.0.1:27701/"
username = "me"
password_file = "${MARKI_SYNC_PASSWORD_FILE:-~/.config/marki/anki-password}"

[media_sources]
flags = "${HAYLEOX_FLAGS}/share/hayleox-flags"

[[map.rules]]
match = "geography/**"
[map.rules.defaults.viewport]
cluster_factor = 0.3
```

Files are found the same way ripgrep finds them: only `*.md` and `*.markdown`,
respecting `.gitignore`, and skipping hidden files.

## Commands

| Command                       | Does                                                                |
| ----------------------------- | ------------------------------------------------------------------- |
| `marki init`                  | Create `.marki/`. Safe to re-run; it never overwrites anything      |
| `marki fmt`                   | Mint ids and normalize files on disk                                |
| `marki status`                | Offline diff against the last-synced copy: every note that would be added, updated, moved or orphaned |
| `marki push` (or `marki`)     | Pull, write media then the collection, sync up. Stops at the first failed step; a failed sync keeps the writes pending for the next push. Notes whose file is gone are suspended and tagged `marki::orphan` |
| `marki push --prune`          | Same, but deletes orphans outright                                  |
| `marki push --simulate`       | Pull, push into a throwaway copy, check it, and list what would change; uploads nothing |
| `marki mcp`                   | Serve the card-authoring tools over MCP; see [MCP server](#mcp-server) |
| `marki check`                 | Render every card and check the collection's structure, without writing |
| `marki prune [--dry-run]`     | Delete notes previously tagged `marki::orphan` (pulls and syncs like a push) |
| `marki watch`                 | Push on every file change and on the heartbeat interval             |
| `marki render <file>`         | Write `./out/preview.html` (every card, front and back, with model CSS) and assets, without touching Anki; `--stdout` dumps raw assets |

Global flags: `--config`, `--cards-dir`, `--collection`, `--media-dir` and
`--typst-binary`, with env equivalents `MARKI_CONFIG`, `MARKI_COLLECTION`,
`MARKI_MEDIA_DIR` and `MARKI_TYPST`. Add `-v` or `-vv` for more logging.

Every note marki manages carries the `marki` tag, plus a `marki::hash:...` tag
it uses to detect changes. Leave both alone.

The files win for tags as they do for fields: a push sets a note's Anki tags
to exactly its file's tags, so tags added in Anki (including `leech`) are
dropped. A tag-only edit in a file is a normal update.

Changing a model's card types changes the collection's schema. The push then
replaces the server's copy with marki's (a full upload, right after pulling,
so nothing is lost), and other devices download it on their next sync. The
push report says so (`full_sync_required`).

## MCP server

`marki mcp --listen 127.0.0.1:3047` serves the repo to LLM agents at `/mcp`
(streamable HTTP). It has no authentication and only accepts loopback `Host`
headers, so put an auth proxy on the same host in front of it (the NixOS
module uses mcp-auth-proxy).

Tools: `marki_context`, `marki_docs`, `marki_search_cards`, `marki_read_card`,
`marki_preview`, `marki_write_card`, `marki_write_cards`, `marki_move_card`,
`marki_delete_card`, `marki_add_media`, `marki_read_model`,
`marki_write_model`, `marki_status`, `marki_push`, `marki_query`,
`marki_map_render`. Plus docs, cards and models as resources and a
`make-cards` prompt.

`marki_preview` also returns a PNG (max 512 px) of every SVG figure (maps,
typst) on each card side, and `marki_map_render` renders a bare map block's
front and back, so an agent can see what it drew.

Block renderers add their own: each ships its README as `marki_docs("<block>")`
and may offer tools named `marki_<block>_<name>` (`marki_map_units`,
`marki_map_find`, `marki_map_define`, `marki_map_list`, `marki_map_get`, `marki_media_list`),
through `docs()` and `tools()` on the
`Renderer` trait. They are registered when the server starts, so enabling a
block (e.g. setting `typst_binary`) needs a restart.

The guard rails:

- Paths are confined to the cards dir; files under `.marki/` are only
  reachable through the model and media tools.
- `marki_write_card` formats and renders a card before saving, and only
  overwrites a card when given its current `#id`.
- `marki_write_model` needs `M.describe()` and must render every note that
  uses the model. The model reference is the `marki://docs/models` resource.
- `marki_push` without `confirm` only simulates. Pushing needs `confirm` plus
  the `plan_hash` from that simulation, so an agent can't push anything the
  user hasn't seen. After a push the cards repo is committed (if it's a git
  repo).
- `marki_query` runs one read-only statement on marki's copy of the
  collection as of its last sync.
- `marki_delete_card` only removes the file (given its `#id`). The next push
  suspends the note's cards; deleting the note and its reviews needs
  `delete_orphans=true` on both the simulation and the confirm.
- `marki_move_card` renames a file (given its `#id`), which is how a card
  changes deck; the push moves the note and keeps its reviews.
- A push that changes a note clears the flags on its cards (shown as `unflag`
  in the plan): fixing a flagged card is what the flag asked for.

The server rereads `.marki/config.toml` when it changes. If the file stops
parsing, every tool fails with the parse error until it's fixed.

On NixOS, `modules/marki-mcp.nix` runs it as a service, with the collection
in its state directory and the sync password as a credential
(`MARKI_SYNC_PASSWORD_FILE`).

## Layout

| Crate                                            | Role                                                        |
| ------------------------------------------------ | ----------------------------------------------------------- |
| `crates/marki`                                   | CLI: parsing, fmt, Lua models, sync engine                  |
| [`crates/marki-render`](crates/marki-render/README.md) | The `Renderer` trait that every block renderer implements |
| [`crates/marki-map`](crates/marki-map/README.md) | ` ```map ` blocks                                           |
| [`crates/marki-media`](crates/marki-media/README.md) | ` ```media ` blocks                                     |
| [`crates/marki-typst`](crates/marki-typst/README.md) | ` ```typst ` blocks                                     |
| [`crates/marki-anki`](crates/marki-anki/README.md) | SQLite access to the Anki collection, writing like an Anki client |

- `models/`: an example Lua card type (`geographic-location`). Copy it into
  your project's `.marki/models/`.
- `docs/ANKI-SCHEMA.md`: reference for the Anki collection schema.
- `docs/REDESIGN.md`: the rewrite plan and its status.

For development, direnv (`.envrc`) loads the dev shell, which sets
`NATURAL_EARTH_DATA` and `GEOBOUNDARIES_DATA` for the map tests.

## Known gaps

- There's no `examples/` directory. The map fixtures in
  `crates/marki-map/tests/fixtures/` have no golden-test harness (phase 10).

## Testing

`cargo test --workspace` runs the unit tests. `tests/e2e-anki.sh` pushes real
cards into a collection created by Anki's own library, and checks Check
Database and review history after each risky change (cloze edits, type
changes, card renames, reorders and removals). `tests/e2e-mcp.sh` starts
`marki mcp` and drives every tool over HTTP. `tests/e2e-server.sh` runs a real
anki-sync-server with a second client (a phone) and checks that notes, media
and deletions reach it and that its reviews survive a card type change. All
need `cargo build` first.

`marki` runs `crates/marki/src/sync/sync.py` with `$MARKI_PYTHON`, a Python
that can import Anki's `anki` library. The Nix package and the dev shell set
it to Anki's library from the same nixpkgs as anki-sync-server.
