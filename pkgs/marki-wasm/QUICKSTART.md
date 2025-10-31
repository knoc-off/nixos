# Marki Quickstart Guide

Quick reference for creating Anki flashcards from Markdown.

## Basic Card Structure

```markdown
# Card Title

Front content goes here

---

Back content goes here
```

The `---` separator divides the front from the back of the card.

## Note Types

### Basic Cards (default)

Standard question/answer cards.

```markdown
What is the capital of France?

---

Paris
```

### Cloze Cards

Use `#cloze` tag with optional algorithm to create cloze deletions:

#### Increment Mode (default)

Each emphasis gets its own cloze number:

```markdown
#cloze

The capitals are **Paris**, **Berlin**, and **Madrid**.
```

Result: `{{c1::Paris}}`, `{{c2::Berlin}}`, `{{c3::Madrid}}`

#### Duo Mode

Bold = c1, Italic = c2 (useful for paired concepts):

```markdown
#cloze:duo

**France** is in _Europe_, **Japan** is in _Asia_.
```

Result: Bold items are c1, Italic items are c2

#### Auto Mode

Automatically chooses between Increment and Duo:

```markdown
#cloze:auto

Smart detection based on formatting used
```

- If both **bold** and _italic_ exist → uses Duo mode
- If only one type exists → uses Increment mode

## Code Blocks

### Syntax Highlighting (default)

````markdown
```python
def hello():
    print("Hello, world!")
```
````

### Math Rendering

Use `math` or `latex` language for MathJax rendering:

````markdown
```math
x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}
```
````

### Force Syntax Highlighting

Prefix language with `_` to show highlighted code instead of rendering:

````markdown
```_math
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
```
````

This displays syntax-highlighted LaTeX instead of rendered math.

### KaTeX Pre-rendering (optional)

Use `katex` language when building with `--features katex`:

````markdown
```katex
E = mc^2
```
````

## Images

```markdown
![Alt text](path/to/image.png)
```

Images are automatically collected and included in the Anki package. Paths are relative to the markdown file's directory.

## Tags

Add tags with `#tag_name`:

```markdown
#geography #europe

What is the capital of France?

---

Paris
```

**Special tags:**

- `#cloze` - Creates a cloze deletion card
- `#basic` - Creates a basic card (default, optional)

## Markdown Features

All standard Markdown is supported:

- **Bold**, _italic_, `inline code`
- Headings (H1-H6)
- Lists (ordered and unordered)
- Links: `[text](url)`
- Blockquotes
- And more...

## Directory Structure

```
input_directory/
├── deck_name/
│   ├── subdeck/
│   │   └── card1.md
│   └── card2.md
└── another_deck/
    └── card3.md
```

**Deck naming:**

- Single file: Uses parent directory name
- Recursive directory: Creates hierarchical decks with `::`
  - `input/physics/mechanics/card.md` → `physics::mechanics`

## Usage Examples

### Basic Command

```bash
marki input.md -o output.apkg
marki input_directory/ -r -o output.apkg
```

## Complete Example

````markdown
#physics #mechanics

## Kinematic Equation

The equation for velocity is:

```math
v = v_0 + at
```

Where:

- $v$ = final velocity
- $v_0$ = initial velocity
- $a$ = acceleration
- $t$ = time

---

This is one of the **fundamental equations** of kinematics used to calculate velocity under constant acceleration.

Additional code example:

```python
def calculate_velocity(v0, a, t):
    return v0 + a * t
```
````

## Tips

1. **One file = one card**: Each markdown file creates exactly one flashcard
2. **Media files**: Place images in the same directory or subdirectories relative to your markdown files
3. **Syntax highlighting**: Unrecognized code block languages automatically fall back to syntax highlighting
4. **Math rendering**: Use ` ```math ` for display math, inline math support coming soon
5. **Preview**: Import the `.apkg` file into Anki to see your cards
