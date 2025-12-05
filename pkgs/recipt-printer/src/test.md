# Markdown

KitchenOwl supports GitHub-flavored Markdown in recipe descriptions, with additional custom features specifically designed for recipe management.

## Custom KitchenOwl Features

### Ingredient Pills

Ingredient pills allow you to reference ingredients from inside your recipe description and automatically link them to your ingredient list. When you reference an ingredient using this syntax, it becomes interactive and can display amounts, scale with recipe yield changes, and highlight which ingredients are needed for specific cooking steps.

**Basic syntax:**

```
@ingredient_name{quantity}
@ingredient_name{quantity, type/descriptor}
```

**Best Practice - Always Include Quantity:**

While the basic `@ingredient_name` syntax works, you should **always include the quantity** inside curly braces for clarity and better recipe scaling. Include the type or descriptor only when it matters:

```
@flour{500g, self rising}
@olive_oil{2 tbsp}
@tomatoes{400g, diced}
@eggs{3}
@butter{100g, softened}
```

**Features:**

- Case-insensitive matching (e.g., `@Flour` matches "flour" in your ingredient list)
- Use underscores for spaces (e.g., `@olive_oil` to reference "olive oil")
- Only works for ingredients that exist in your recipe's ingredient list
- Quantities automatically scale when recipe yield is adjusted

**Examples with quantity (and optional type):**

```
Mix @flour{500g, self rising} with @water{300ml} and knead the dough.
Add @butter{100g, softened} and @sugar{200g} until creamy.
Fold in @chocolate_chips{200g, dark}.
Drizzle with @olive_oil{2 tbsp}.
```

**Different amounts in different steps:**

You can reference the same ingredient multiple times with different quantities for different steps:

```
Add @tomatoes{200g, diced} to the pan, then add the remaining @tomatoes{200g, sliced} as garnish.
```

**How ingredient pills work:**

- In **recipe view**: Ingredient pills appear as highlighted text that links to your ingredient list
- In **cooking mode**: The app extracts which ingredients are needed for each step and highlights them
- With **recipe scaling**: When you adjust recipe yield, ingredient amounts in pills are automatically recalculated

### Images

KitchenOwl supports two image syntaxes:

**Short syntax (KitchenOwl custom):**

```
![image_url]
```

**Standard markdown syntax:**

```
![alt text](image_url)
```

Both syntaxes work the same way and display images inline within your recipe description.

**Special behavior in numbered lists:**
If an image appears as the first item in a numbered step, it will be extracted and displayed separately alongside the step text in a special layout.

## Text Formatting

**Bold text:**

```
**Bold text**
```

**Italic text:**

```
_Italic text_
```

**Strikethrough:**

```
~~Strikethrough text~~
```

**Inline code:**

```
Use `code` for technical terms or measurements.
```

**Combination:**

```
***Bold and italic***
**_Also bold and italic_**
```

## Headings

```
# Heading level 1
## Heading level 2
### Heading level 3
#### Heading level 4
##### Heading level 5
###### Heading level 6
```

Headings help organize your recipe into sections like "Preparation," "Cooking," "Serving," etc.

## Lists

### Bulleted Lists

```
- First item
- Second item
- Third item
  - Nested item
  - Another nested item
```

### Numbered Lists

```
1. First step
2. Second step
3. Third step
```

**Special behavior in recipes:**

Numbered lists in recipe descriptions receive special treatment:

- Each step is displayed with a circular numbered badge
- Steps are visually separated for easier reading
- In cooking mode, you can navigate through steps one at a time
- If a step begins with an image, it's extracted and displayed separately

**Example:**

```
1. Preheat oven to 180°C
2. Mix @flour{500g, self rising}, @sugar{200g}, and @eggs{3} in a bowl
3. Pour batter into a greased pan
4. Bake for 30 minutes
```

### Checklists

```
- [ ] Incomplete task
- [x] Completed task
- [ ] Another task
```

Checklists are great for preparation steps, shopping lists within recipes, or equipment needed.

## Blockquotes

Blockquotes are displayed in a colored rectangle, perfect for notes, tips, or warnings:

```
> Tip: Let the dough rest for at least 30 minutes before rolling.
```

```
> Warning: Do not overmix the batter or it will become tough.
```

## Code Blocks

**Inline code:**

```
Add `2 tsp` of salt
```

**Fenced code blocks:**

````
```
Temperature: 180°C
Time: 25-30 minutes
Internal temp: 75°C
```
````

Code blocks can be useful for precise measurements, timing charts, or technical cooking instructions.

## Tables

Tables are perfect for organizing cooking times, temperatures, or ingredient alternatives:

```
| Ingredient | Amount | Alternative |
| ---------- | ------ | ----------- |
| Flour      | 500g   | Almond flour |
| Sugar      | 200g   | Honey        |
| Eggs       | 3      | Flax eggs    |
```

**Column alignment:**

```
| Left-aligned | Center-aligned | Right-aligned |
| :----------- | :------------: | ------------: |
| Text         | Text           | Text          |
```

## Links

**Basic link:**

```
[Link text](https://example.com)
```

**Link with title:**

```
[Link text](https://example.com "Hover title")
```

**Automatic links:**

```
https://example.com
```

**Example:**

```
Recipe adapted from [Chef John's website](https://foodwishes.com)
```

## Horizontal Rules

Create visual separators between sections:

```
---
```

or

```
***
```

## Line Breaks

**Soft line break:**
Just press Enter once (creates a space but keeps text in the same paragraph)

**Hard line break:**
End a line with two spaces, then press Enter
Or use an empty line between paragraphs

## Complete Example

Here's a complete recipe using various markdown features:

```markdown
# Chocolate Chip Cookies

> This recipe makes the best chewy chocolate chip cookies!

## Ingredients

Already listed in your ingredient list, reference them with @ingredient_name{quantity} or @ingredient_name{quantity, type} when the type matters

## Instructions

1. Preheat your oven to **180°C (350°F)**
2. Mix @butter{115g, softened} with @sugar{200g} until creamy
3. Add @eggs{2, beaten} and @vanilla_extract{1 tsp}
4. In a separate bowl, combine @flour{280g, self rising}, @baking_soda{1 tsp}, and @salt{1/2 tsp}
5. Gradually mix dry ingredients into wet ingredients
6. Fold in @chocolate_chips{200g, dark}
7. Drop rounded tablespoons onto baking sheet
8. Bake for 10-12 minutes until edges are golden

> Tip: Don't overbake! Cookies will continue cooking on the hot pan.

## Storage

Store in an airtight container for up to:

- **Room temperature:** 3-4 days
- **Refrigerator:** 1 week
- **Freezer:** 3 months

---

Recipe adapted from [Grandma's cookbook](https://example.com)
```

## How Markdown is Interpreted

### Recipe View Mode

When viewing a recipe:

- All markdown is rendered normally
- Numbered lists show step numbers in circular badges
- Ingredient pills are interactive and link to your ingredient list
- Images are displayed inline (or separately for step images)

### Cooking Mode

When in cooking mode:

- The recipe is parsed into individual steps (from numbered lists)
- You navigate through one step at a time
- The app extracts and highlights which ingredients are needed for the current step
- Step images are displayed prominently alongside instructions
- Text can be scaled larger for easier reading while cooking

### Recipe Scaling

When you adjust the recipe yield:

- Ingredient pills with amounts are automatically recalculated
- Both regular ingredient references and descriptions with quantities are scaled
- Example: If you double a recipe, `@flour{500g, self rising}` becomes `@flour{1000g, self rising}`

## Supported Markdown Standard

KitchenOwl uses the **GitHub Web** markdown flavor, which includes all GitHub-flavored Markdown features plus HTML support (though HTML is disabled for security). The custom extensions for ingredient pills and short image syntax are added on top of this standard.
