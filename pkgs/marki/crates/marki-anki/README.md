# marki-anki

Reads and writes an Anki collection (`collection.anki2`, schema v18) directly
with SQLite, instead of going through AnkiConnect or rslib. It reproduces
Anki's own rules for note fields, checksums, deck names, card generation,
deletions (graves) and the `media.db` media store. Every write uses the
server-style USN (update sequence number), so the change syncs to other devices
like any other edit.

Close Anki while this runs. It takes an exclusive lock on the collection.

## API

- `Collection::open(path)`, then read helpers such as `managed_notes`,
  `notetype_configs`, `deck_kinds` and `count`, plus `backup()`.
- `Collection::transact(|w: &mut NoteWriter| ...)` runs a batch of writes in
  one transaction:
  - `ensure_model`
  - `add_note`, `update_note`, `remove_note`
  - `set_note_deck`, `deck_id_for`
  - `suspend_note_cards`, `add_tag_to_note`
- `notetype::ModelSpec` describes a note type: its fields, card templates and
  CSS.
- The `media` module writes files and `media.db` entries.

The only user is `crates/marki/src/sync/engine.rs`.

The schema details, including the `unicase` collation, the required pragmas,
USN handling and how `csum`/`sfld` are computed, are in
[docs/ANKI-SCHEMA.md](../../docs/ANKI-SCHEMA.md).
