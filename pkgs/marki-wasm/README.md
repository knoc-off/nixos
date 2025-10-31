# Marki - Markdown to Anki Flashcard Generator

Convert Markdown files to Anki flashcards (.apkg) with syntax highlighting and cloze deletions.

## Features

- **One File = One Card**: Each markdown file becomes one flashcard
- **Two Note Types**: Basic (front/back) and Cloze (with deletions)
- **Tag Support**: Use `#tags` to organize and categorize cards
- **Syntax Highlighting**: Code blocks are syntax-highlighted with syntect (100+ languages)
- **Cloze Deletions**: Bold (`**text**`) and italic (`*text*`) create cloze markers
- **HTML Output**: All content rendered as HTML for rich formatting

## Installation

```bash
cargo build --release
```

## Usage

### Basic Usage

```bash
# Single file
marki card.md -o output.apkg

# Directory (all .md files)
marki my_notes/ -o my_deck.apkg

# Recursive directory processing
marki my_notes/ -r -o all_notes.apkg

# Custom deck name
marki notes/ -o deck.apkg -d "My Study Deck"
```

## Card Format

### Structure

**One markdown file = One card**

The first `---` horizontal rule divides front from back:

```markdown
Front content here

---

Back content here (optional context/answer)
```

### Basic Cards

Use `#basic` tag (or omit type tag, basic is default):

```markdown
What is a closure in JavaScript? #javascript #basic

---

A function that has access to variables from its outer scope.
```

### Cloze Cards

Use `#cloze` tag and `**bold**` or `*italic*` for deletions:

```markdown
**Closures** capture variables from their *lexical scope*. #cloze #javascript

---

This is common in callbacks and event handlers.
```

This creates:
- `{{c1::Closures}}` capture variables from their `{{c2::lexical scope}}`.
- Back shows the context after answering

### Code Blocks

Works in both basic and cloze cards:

````markdown
A **decorator** modifies a *function*. #cloze #python

```python
def my_decorator(func):
    def wrapper():
        print("Before")
        func()
    return wrapper
```

---

Decorators use the `@` syntax.
````

### Images

Embed images using standard markdown syntax:

```markdown
![Alt text](image.jpg) #basic

---

Back content here.
```

**Important:**
- Image files must be in the same directory as the markdown file
- Use relative paths (basename only): `image.jpg` not `../image.jpg`
- Images are automatically packaged into the .apkg file
- Supported formats: JPG, PNG, GIF, etc.

Example with image:

```markdown
# Visual Learning Card

![Cat photo](cat.jpg) #biology

This is a domestic cat (Felis catus).

---

Cats are obligate carnivores with retractable claws.
```

## Command Line Options

- `<INPUT>` - Input file or directory (required)
- `-o, --output <OUTPUT>` - Output .apkg file (default: output.apkg)
- `-r, --recursive` - Process directories recursively
- `-d, --deck-name <DECK_NAME>` - Custom deck name (defaults to input name)
- `-h, --help` - Print help
- `-V, --version` - Print version

## Tags

Tags are extracted from `#word` patterns in your markdown:

- `#cloze` - Sets note type to Cloze (removed from final tags)
- `#basic` - Sets note type to Basic (removed from final tags)
- All other tags (e.g., `#javascript`, `#programming`) are preserved and added to the card

**Note**: Tag support in genanki-rs is currently limited. Tags are extracted and tracked but may not appear in generated decks yet.

## Examples

See `test_cards/` directory for examples:
- **basic1.md** - Basic Q&A card with tags
- **basic2.md** - Basic card with code block
- **cloze1.md** - Cloze card with deletions
- **cloze2.md** - Cloze card with Rust example
- **cloze_with_code.md** - Cloze card with syntax-highlighted code

## How It Works

1. **Parse**: One markdown file = one card
2. **Extract Tags**: Find all `#tags` and determine note type
3. **Split Content**: First `---` divides front/back
4. **Apply Cloze**: For cloze cards, convert `**bold**` → `{{c1::}}`, `*italic*` → `{{c2::}}`
5. **Highlight Code**: Syntax highlight code blocks with syntect
6. **Generate**: Create Anki notes with proper models
7. **Package**: Bundle into .apkg file

## Supported Markdown Features

Marki supports comprehensive markdown rendering:

- ✅ **Headings** (H1-H6)
- ✅ **Lists** (ordered, unordered, nested)
- ✅ **Text formatting** (bold, italic, inline code)
- ✅ **Code blocks** (syntax highlighted, 100+ languages)
- ✅ **Links and images** (images auto-packaged into .apkg)
- ✅ **Blockquotes**
- ✅ **Paragraphs and line breaks**

See `MARKDOWN_FEATURES.md` for complete details and examples.

## Dependencies

- `pulldown-cmark` - Markdown parsing
- `syntect` - Syntax highlighting
- `genanki-rs` - Anki package generation
- `clap` - CLI argument parsing
- `walkdir` - Directory traversal
- `regex` - Tag extraction
- `anyhow` - Error handling
