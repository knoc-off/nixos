# Supported Markdown Features

Marki supports comprehensive markdown rendering with proper HTML conversion.

## ✅ Fully Supported

### Headings
All heading levels are converted to HTML tags:
```markdown
# H1 Heading
## H2 Heading
### H3 Heading
#### H4 Heading
##### H5 Heading
###### H6 Heading
```

Output: `<h1>`, `<h2>`, `<h3>`, `<h4>`, `<h5>`, `<h6>`

### Lists

**Unordered lists:**
```markdown
- Item A
- Item B
- Item C
```
Output: `<ul><li>Item A</li><li>Item B</li><li>Item C</li></ul>`

**Ordered lists:**
```markdown
1. First
2. Second
3. Third
```
Output: `<ol><li>First</li><li>Second</li><li>Third</li></ol>`

**Nested lists:**
```markdown
- Top level
  - Nested item 1
  - Nested item 2
- Back to top
```
Output: Properly nested `<ul>` tags

### Text Formatting

```markdown
**Bold text**
*Italic text*
***Bold and italic***
`inline code`
```

Output:
- `<strong>Bold text</strong>`
- `<em>Italic text</em>`
- `<em><strong>Bold and italic</strong></em>`
- `<code>inline code</code>`

### Code Blocks

**Fenced code blocks with syntax highlighting:**

````markdown
```rust
fn main() {
    println!("Hello!");
}
```
````

Output: Syntax-highlighted HTML with CSS classes for 100+ languages

### Links

```markdown
[Link text](https://example.com)
```

Output: `<a href="https://example.com">Link text</a>`

### Images

```markdown
![Alt text](image.png)
```

Output: `<img src="image.png" alt="Alt text">`

**Media Packaging:**
- Images are automatically detected and packaged into the .apkg file
- Image files must exist in the same directory as the markdown file
- Use basename only (not full paths): `cat.jpg` ✅ not `../images/cat.jpg` ❌
- Multiple cards can reference the same image (deduplicated automatically)
- Supported formats: JPG, PNG, GIF, SVG, etc.

**Example:**
```markdown
# Anatomy Quiz

![Human heart diagram](heart.jpg) #biology

Identify the parts of the human heart.

---

The four chambers are: right atrium, right ventricle, left atrium, left ventricle.
```

When you run `marki anatomy.md -o quiz.apkg`, the `heart.jpg` file will be automatically included in the package.

### Blockquotes

```markdown
> This is a quote
> spanning multiple lines
```

Output: `<blockquote><p>...</p></blockquote>`

### Horizontal Rules

```markdown
---
```

**Special behavior:** The first `---` in a file divides front from back. Additional `---` rules in either section are treated as thematic breaks (not currently rendered, but could be added).

### Paragraphs

Text separated by blank lines becomes paragraphs:

```markdown
First paragraph.

Second paragraph.
```

Output: `<p>First paragraph.</p><p>Second paragraph.</p>`

### Line Breaks

Soft breaks (single newline) and hard breaks (two spaces + newline) are converted to `<br>` tags.

## 🔄 Cloze Deletions (Cloze Cards Only)

When using `#cloze` tag:

```markdown
**Bold text** becomes {{c1::Bold text}}
*Italic text* becomes {{c2::Italic text}}
```

Cloze counters increment for each deletion.

## ⚠️ Not Yet Supported

- Tables (HTML tables would need to be added)
- Task lists (`- [ ]` and `- [x]`)
- Strikethrough (`~~text~~`)
- Footnotes
- Definition lists
- Custom HTML passthrough

## Testing

See `test_cards/comprehensive_test.md` for a complete example demonstrating all supported features.

Run with:
```bash
cargo run -- test_cards/comprehensive_test.md -o test.apkg
```

## Implementation

All markdown is parsed using `pulldown-cmark` and converted to HTML. Code blocks are syntax-highlighted using `syntect` with the base16-ocean.dark theme.
