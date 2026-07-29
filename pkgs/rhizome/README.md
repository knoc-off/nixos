# rhizome

Trilium notes as Neovim buffers, over ETAPI, with honest lossy-by-exception
HTML/Markdown round-tripping.

## The problem

Trilium stores text notes as CKEditor HTML. There is no Markdown representation
that round-trips arbitrary CKEditor output: admonitions, nested lists in tables,
inline styles, sized images, math and relation links have no faithful Markdown
form. Making conversion generically lossless is the trap.

So the container is lossless and conversion is allowed to be incomplete, as long
as it is honest about what it could not handle.

## Core rule: transparent by proof

A note is an ordered list of blocks, each either:

- **transparent** — shown as editable Markdown
- **opaque** — shown as a verbatim HTML fence, never reinterpreted

A block is only transparent if the engine can *prove*, for that specific block,
that converting it to Markdown and back reproduces an equivalent DOM. Everything
else stays opaque.

This inverts the usual arrangement, where a converter tries its best and the
damage is found later or never. Here losslessness is a checked invariant on
every block on every open, and an incomplete rule set costs transparency rather
than content. The measured cost on Trilium's own User Guide is **6.4% of blocks
opaque**; the remaining 93.6% are editable prose.

Two consequences worth stating plainly:

- Adding a conversion rule can only ever move blocks *into* transparency. A
  wrong rule is caught by verification and the block stays opaque.
- The only content that can degrade is content the user actively edited and can
  see. Untouched blocks are re-emitted from their original bytes.

## Why not pandoc

The obvious design is to let pandoc's HTML reader do the segmenting: it emits
`RawBlock (Format "html")` for anything it cannot map, so the transparent/opaque
partition ought to come out for free from something with far better HTML
coverage than anything hand-rolled.

Measured against 274 real Trilium notes, that does not hold:

| Measurement | Result |
| --- | --- |
| `RawBlock` nodes emitted across 4 524 blocks | **0** |
| Notes losing DOM elements through HTML→MD→HTML | **111 / 274 (40.5%)** |
| Most common casualty | `<aside>` admonitions, in 88 notes |

Pandoc's HTML reader is *absorbing*, not *preserving*. It maps unknown elements
onto the nearest AST node and drops the wrapper and its attributes silently.
There is no partition to harvest.

Worse, the natural verification strategy — read both sides with pandoc and
compare ASTs — is blind to exactly this failure:

```
<aside class="admonition important"><p>hello world</p></aside>
```

reads to the *same* pandoc AST as a bare `<p>hello world</p>`, because the
reader drops the wrapper on both sides. A verifier built on it reports "no loss"
at the moment it destroys the admonition.

Hence `dom.rs`: rhizome keeps its own tree and compares that. The regression is
pinned by `dom::tests::dropping_an_admonition_wrapper_is_detected`.

Trilium itself reaches the same conclusion from the other direction — its
exporter (`services/export/markdown.ts`) is a curated Turndown rule set with
`keep([...])` and `outerHTML` fallbacks, not a general converter.

## Byte-identical writes

Re-serialising a parsed tree normalises attribute order, entity spelling and
whitespace. Doing that on save would rewrite every note on first open, make
every sync diff meaningless, and expand the blast radius of a bad rule from one
block to the whole vault.

So blocks are split at the level of the *source bytes* (`source.rs`), each block
keeps the exact substring it came from, and splicing is concatenation. Blocks
absent from the edit set go back unchanged.

Enforced by `every_note_splices_back_byte_identical`, which passes on 274/274
notes.

## Buffer format

Transparent blocks are plain Markdown. Opaque blocks are fenced and carry their
block id:

````markdown
Ordinary prose, edited as Markdown.

```=html b7-1a2b3c4d
<figure class="image"><img style="aspect-ratio:959/547;" src="x.png"></figure>
```
````

Fences rather than extmarks: extmarks do not survive a buffer reload, do not
survive being yanked into another buffer, and leave the user looking at content
they can see but cannot address. A fence is debuggable, survives a crash, folds
away, and doubles as the escape hatch for hand-editing the HTML.

Internal note references use wiki-link syntax, because CKEditor distinguishes a
reference link (which renders the target's title) from a plain link to the same
note, and Markdown link syntax cannot:

```markdown
See [[_help_KC1HB96bqqHX|Templates]] for details.
```

### Lists

Plain lists and CKEditor's two-state todo list both edit as ordinary Markdown,
including nested lists, multi-paragraph items and CKEditor's per-`<li>`
bookkeeping id (`data-list-item-id`, which is not semantic and does not block
transparency):

```markdown
- [ ] unchecked
- [x] checked

  a continuation paragraph

  - [ ] a nested item
```

CKEditor's schema has no construct for a single list mixing plain bullets and
checkboxes (writing Trilium's own "any task item makes the whole list a
todo-list" form back would get silently normalised the next time the note is
opened in the web UI), so a mixed Markdown list is written back as two
adjacent lists instead, one plain and one todo, which is a shape CKEditor is
perfectly happy with:

```markdown
- a plain item
- [ ] a checked item
```

writes back as `<ul><li>a plain item</li></ul><ul class="todo-list">...`.

One shape genuinely has nowhere to go: an **ordered task list** (`1. [ ] a`).
`listType` is `bulleted | numbered | todo` -- mutually exclusive, so there is
no numbered todo list to write. It still saves safely: the surrounding list
stays a plain Markdown list and the checkbox itself is written out as literal
`[ ]`/`[x]` text instead of being dropped or left as invalid HTML, with an LSP
warning at the spot where it happened.

**A markdown formatter attached to the buffer can corrupt an `=html` fence.**
Note buffers are `filetype = "markdown"`, so a formatter that reindents or
rewraps text will also reach inside `=html` fences and reformat the HTML they
carry verbatim. That HTML is compared byte-for-byte against the block's
original source to decide whether anything changed; a reformatted fence reads
as an edit and gets written back to Trilium on save, turning a no-op save into
a real diff. Disable autoformatting for rhizome note buffers, or review a
fence's diff before saving if one looks unexpectedly large.

Two lists of the same *flavour* (`ul`/`ul`, `ol`/`ol`, or
`ul.todo-list`/`ul.todo-list`) with nothing between them would concatenate
into a single Markdown chunk when the buffer is re-split, so the second of
any such pair is held opaque instead -- otherwise an *unedited* save could
silently merge them. Lists of *different* flavours (a plain list next to a
todo list) don't need this: a merged chunk there is exactly the mixed-list
shape described above, so it splits straight back into both original lists
losslessly. This is rare enough in practice that a more permissive fix for
the same-flavour case (grouping adjacent lists into one block, so both stay
editable) has been deferred pending real usage data; `rhizome spike <vault>`
reports the count as `ambiguous`.

## Concurrency

ETAPI exposes no `ETag` and honours no `If-Match`; `PUT /notes/:id/content` is
unconditional last-write-wins. Optimistic concurrency is therefore only
available client-side: rhizome compares `blobId` before writing and prompts,
which converts silent clobbering into a decision. A narrow race remains and
cannot be closed from this side of the protocol.

`POST /notes/:id/revision` *is* unconditional, unlike Trilium's automatic
`saveRevisionIfNeeded` (debounced by `revisionSnapshotTimeInterval`, and so not
dependable as a safety net). rhizome forces one snapshot per note per session
before its first write, so recovery does not depend on rhizome being correct.

## Layout

| Path | Role |
| --- | --- |
| `crates/rhizome-core/src/dom.rs` | Canonical DOM, normalisation, equivalence |
| `crates/rhizome-core/src/source.rs` | Byte-exact top-level block splitting |
| `crates/rhizome-core/src/convert/` | HTML↔Markdown rules |
| `crates/rhizome-core/src/segment.rs` | Segment list, verification, splice |
| `crates/rhizome-core/src/buffer.rs` | Buffer text render/parse |
| `crates/rhizome-etapi/` | Blocking ETAPI client |
| `crates/rhizomed/` | CLI + LSP server |
| `lua/rhizome/` | Neovim plugin |

## Usage

```vim
lua require("rhizome").setup({ url = "https://trilium.example", token_cmd = { "pass", "trilium/etapi" } })
:Rhizome           " pick a note
:Rhizome <noteId>  " open one directly
:RhizomeSearch <query>
:Rhizome browse    " walk the note hierarchy one level at a time
:Rhizome browse .  " ...starting at the current note's own children
:Rhizome move      " move the current note to a different parent
```

`:w` writes back. On a `blobId` mismatch you are asked before anything is
overwritten. `:checkhealth rhizome` diagnoses configuration and connectivity.

The engine speaks LSP over stdio, so completion on `[[`, hover, goto-definition,
document symbols and diagnostics come from Neovim's built-in LSP client with no
extra plugin code.

`:Rhizome pick`/`:Rhizome search` are flat, fuzzy-matched over every note's
title and path -- fastest when you roughly know what you're looking for.
`:Rhizome browse` is the complement: no query, just Trilium's own tree,
picked one level at a time (`mini.pick` if present, else `vim.ui.select`,
same as every other rhizome picker). Selecting a note with children drills
into it; a leaf opens directly; `.` opens whatever you have drilled into
without descending further; `..` retraces the path back out. A note cloned
into more than one place is shown under every parent that has it, marked
`(clone)` rather than picked arbitrarily -- Trilium's tree is a DAG, not a
strict hierarchy, and the browser does not pretend otherwise. The trail is
kept client-side rather than asking the server for "the parent", since that
question has no single answer for a clone. `:Rhizome browse .` starts
drilled into the current note's own children instead of root; `:Rhizome
browse ..` starts at its siblings; `:Rhizome browse <noteId>` starts
anywhere. `#archived` notes are hidden by default, matching Trilium's own
tree, behind a "show archived" item rather than a separate toggle command.

Every mutation -- `:Rhizome move`, `clone`, `unlink`, `delete`, `archive`,
`unarchive`, plus creating a note -- acts on the current buffer's note and is
also reachable without leaving `browse`: `<C-a>` under `mini.pick` opens an
action menu for whichever row the cursor is on, a child or `.` (the note
currently being browsed) itself, so acting on the level you're in needs no
extra drilling. `vim.ui.select` has no notion of a key bound to the cursor,
so it gets an ordinary "act on a note..." item instead, offered only when
`mini.pick` isn't available -- under `mini.pick`, `<C-a>` already covers the
same ground without a permanent extra row in the list. "new child note..."
lives in the action menu for the same reason; the one exception is a
root-level "new top-level note" item, since there is no `.` row at the top
to act on. `move`/`clone` reuse `browse` itself to pick a destination --
drilling to where a note belongs is the same motion as drilling to read it.
`move`/`unlink` ask which parent to act relative to only when the note is a
clone with more than one; a single parent is used without asking. `delete`
removes a note everywhere (every clone at once) and does not prompt -- it is
soft on Trilium's side (`:Rhizome reindex` will not bring it back, but
Trilium's own trash/undelete will, until erase runs). `unlink` refuses
instead of prompting when it would remove a note's last placement, since
ETAPI would otherwise delete the note outright; use `delete` when that is
actually what you want.

### Metadata

Title, labels and relations are not part of a note's content, so they are
edited in a separate pop-out rather than spliced into the buffer. Putting
them inline would place lines in the buffer with no corresponding block in
the note, which is precisely what the byte-identity guarantee rests on not
happening.

```vim
:Rhizome meta          " open the pop-out; :w applies it, q closes it
:Rhizome rename New title
```

The pop-out is YAML -- `title`, then `labels:` and `relations:` sections,
always present even when empty so there is somewhere for completion to
anchor to -- attached to the same LSP client as note buffers. `marked-yaml`
never resolves a scalar's type, so `draft: yes` round-trips as the string
`"yes"`, not a boolean; quoting a value is only ever a YAML-syntax concern,
never needed to stop coercion. A name with no value is a bare label
(`todo:`); a name repeated as a YAML list gives it several values; a value
that needs `inheritable: true` is written as `{value: x, inheritable: true}`.
`g?` opens this reference along with the label/relation definitions and
vocabulary actually in scope for the note being edited.

Completion on a name suggests every `label:`/`relation:` definition in scope
plus every name seen anywhere else in the vault; completion on a value offers
values observed for that name, or for a relation, notes already used for that
same name (nothing typed yet) or a note search (once something is). All of
this works the same on a multivalued name's own list items as it does on a
single `name: value` line. Hover shows a name's definition or a relation's
target note, on a list item the same as a bare value. Every resolvable
relation value gets its target's title as an inlay hint, so a value never has
to be looked up by eye. Diagnostics catch invalid YAML and values that
violate a definition's type or single/multi constraint, anchored at the
actual line the offending value is on. `gf`/`gd` on a relation's value --
list item or not -- closes the float and jumps straight to that note. A code
action offers "convert to list" on a single-valued name (to add a second
value without hand-restructuring the YAML) and "create note" on a relation
value that does not resolve to one. `:w` diffs the edited text against the
live note and issues only the ETAPI calls needed to close the gap.

### On NixOS

The nixvim module wires the plugin to its own engine build, so the binary is
never expected on `$PATH`:

```nix
imports = [ ../plugins/rhizome/module.nix ];
plugins.rhizome = {
  enable = true;
  url = "https://trilium.example.com";
  tokenEnv = "RHIZOME_TOKEN";
};
```

The token is named, not embedded. How that variable gets into the environment is
deliberately outside the editor's configuration -- sops, direnv, a password
manager, or a plain `export` all work, and none of them become a dependency of
the nixvim build. Never set `token` to a literal: the Nix store is
world-readable.

On a host using `modules/shell.nix`, declaring the secret is enough, since every
`shell_environment/` secret is exported automatically:

```nix
sops.secrets."shell_environment/RHIZOME_TOKEN" = { mode = "0644"; };
```

`:checkhealth rhizome` reports which variable it looked at and whether the
server accepted the token.

## Auditing a vault

Before trusting the write path with a vault, point the tooling at its note HTML:

```console
$ rhizome spike ./notes          # how much is editable as prose, and what is not
$ rhizome check ./notes          # assert every note splices back byte-identical
$ rhizome diff  ./notes          # show blocks where a rule claimed a block and got it wrong
$ rhizome roundtrip ./note.html  # trace one note through render → parse
$ rhizome doctor                 # check the server is reachable and the token works
```

`spike` ranks the constructs keeping blocks opaque, which is the list of rules
worth writing next.

## Tests

```console
$ cargo test --workspace
$ RHIZOME_CORPUS=…/apps/server/src/assets/doc_notes/en cargo test -p rhizome-core
```

The corpus tests run against real Trilium note HTML and are skipped when
`RHIZOME_CORPUS` is unset. They assert byte-identical splicing, buffer
round-tripping, and that transparency has not regressed below 96%.

## Status

Read and write paths work against real notes. Text notes are editable as
Markdown, code notes as plain text, and every other type opens read-only.

Beyond editing, the LSP surface covers navigation: goto-definition and `gf`
on a `[[noteId|Title]]`, references for backlinks (backed by Trilium's own
`~internalLink` relation, not a text search), workspace-symbol search, folding
and diagnostics driven by the server rather than a hand-maintained regex, and
hover with a short content preview of the linked note. None of these bind a
key of their own -- they use whatever your Neovim config already wires up to
the standard LSP methods (`vim.lsp.buf.definition`, `references`, `hover`,
...). `[[noteId|Title]]` links render with the note's *current* title as
virtual text; the text stored in the link is display-only and Trilium itself
overwrites it on every render, so rhizome never rewrites it either. A link's
target is not always a bare noteId -- Trilium sometimes writes a full notePath
(`ancestor/ancestor/id`) instead, even linking the same note both ways from
different pages of its own User Guide. Every navigation and completion
feature resolves the path down to its target note, so this is transparent;
a code action, "Simplify link target", is offered to rewrite the path down to
a bare id in the buffer, but this is opt-in, since the path form is not
actually broken. `:Rhizome` is a single dispatcher (`:Rhizome today`,
`:Rhizome new <title>`, `:Rhizome actions` to browse); `:wq` blocks until a
pending save is confirmed so quitting cannot outrun the write.

`[[` completion is served from a local index of every note's title and
ancestor path -- one bulk fetch on startup, cached to `$XDG_CACHE_HOME/rhizome/`
so a restart isn't a cold start, refreshed in the background and kept current
in place on any rename or create rhizome itself performs (`:Rhizome reindex`
forces a full refresh). Matching happens instantly, with no round trip per
keystroke, and falls back to a live server search (Trilium's own `fastSearch`)
for the brief window before the first index load completes. A query is split
on word boundaries and matched as a sequence of prefixes against the note's
own title *and* its ancestor path, in order, with no separator required --
`waystonepeople` matches a note filed under Waystone > People, and
`waypeoplejohn` matches "John Doe" filed there, without typing any of
"Waystone", "People" or "John" in full. `-`/`_` work as optional, readable
separators (`waystone-people`) without changing the match, since blink.cmp
treats both as ordinary keyword characters and so never closes the menu on
them the way it would on a space. Each item's `filterText` is the same path
reduced to a lowercase, dash-joined slug (`waystone-people-john-doe`) rather
than its title or breadcrumb, since blink.cmp fuzzy-matches and ranks against
that field using its own matcher, not the server's -- measured directly
against blink's matcher, this is the one shape that lets a full-path query
actually match: a title-first breadcrumb puts the path out of order, and a
plain title alone is invisible to any query that also names a path segment.
Multi-token path search with a literal space ("work proj alpha") only works
in a picker (`:Rhizome notes`, or the "Search all notes..." item at the
bottom of the `[[` menu) rather than inline, because blink.cmp closes its
own completion popup on a space regardless of `filterText`.

`:Rhizome` with no query, `:Rhizome search`/`:RhizomeSearch` with a query, and
`pick`/`insert_link` in Lua all read from the same local index rather than
hitting Trilium on every keystroke. A bare `:Rhizome` opens the picker over
the whole index and lets it fuzzy-filter live, the same as `:Rhizome notes`;
a query narrows against the index first and only falls back to a live
`fastSearch` request if the index is still cold (before the first load
completes) or genuinely has zero matches for that query -- a query that
matches nothing locally might still match content Trilium's own search
looks inside notes for, which the index does not index. Either way each
result shows its ancestor path (`Waystone > People > John Doe`) rather than
just a title, so entries with the same title in different places stay
distinguishable.

Buffers are named `trilium://<noteId>/<title>` once a note's title is known
(bare `trilium://<noteId>` until the fetch lands), so bufferline, `:t`, and
the tabline show something readable with no configuration of their own.
Buffers are also marked listed (`bufadd`, used to create them, does not do
this on its own), so a note shows up as its own entry in a bufferline/tabline
running in "buffers" mode the moment it opens, same as any other file. The
LSP document map is keyed by noteId alone -- every standard request
(`didChange`, hover, completion, ...) canonicalizes the buffer's current name
back down to its id before touching it, so a rename mid-session or a title
containing an oddball character never desyncs diagnostics or save-conflict
detection from what the buffer actually shows. Opening the same note twice
(a link, the picker, a `gd` jump) reuses the existing buffer rather than
creating a second one, keyed by noteId rather than by name.

Opening a note (`:Rhizome search`, `pick`, `today`, `new`, ...) never
overwrites whatever the current window happens to be showing purely because
of timing: with no explicit `:split`/`:vsplit`/`:tab` modifier on the
command it switches the current window to the note's buffer by default
(`open_mode` in `setup()`, also `"vsplit"`, `"split"`, or `"tab"` for a real
new tabpage), and if the note is already open and visible somewhere -- a
split, another tab -- it jumps there instead of opening a second view of it.
An explicit modifier always overrides the default: `:vsplit Rhizome search
foo` splits regardless of `open_mode`. `gd`/references jumps are Neovim's own
LSP navigation and follow whatever split/tab keymaps you already use for
those, not `open_mode`.

Not yet built: a raw/parsed toggle and note deletion.
