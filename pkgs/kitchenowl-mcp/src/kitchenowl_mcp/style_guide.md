# KitchenOwl recipe style guide

Recipes are stored as markdown in the `description` field. KitchenOwl renders
that markdown and turns `@item` tokens into tappable ingredient chips. Follow
these rules and the recipe will render correctly and scale with servings.

## Ingredients

Declare every ingredient as a recipe item. Items are matched **by name**, and a
name that does not already exist is created silently — so a typo does not fail,
it quietly adds a near-duplicate to the household catalogue. Call `list_items`
and reuse an existing name whenever one fits.

Put the amount in the item's `description` field, not in the item name:

```
{"name": "flour", "description": "200 g"}
```

Item names are the generic ingredient ("flour", "spring onion"), singular where
natural. Amounts, preparation and brand never belong in the name.

Mark an item `optional: true` only if the recipe genuinely works without it.

## Referencing ingredients in the method

Write `@item_name` — underscores stand in for spaces, matching is
case-insensitive:

```
Fold the @spring_onion through the @creme_fraiche.
```

Every declared item must be referenced at least once, and every `@` token must
resolve to a declared item. An unresolved token is **not** an error in the app;
it renders as literal text, so it fails silently and looks like a typo to the
reader.

To show an amount inline, use the brace form. Its contents scale with servings:

```
Whisk @flour{200 g} into the @milk{300 ml}.
```

Never write a bare number in front of a pill:

```
BAD   Add 200 g @flour
GOOD  Add @flour{200 g}
```

Prose numbers do not scale. When the user changes the serving count the amount
stays stale, which is worse than having no amount at all.

## Structure

Write the method as a numbered list, one step per line. The cooking view steps
through these one at a time, so a step should be a single coherent action.

Use `##` headings only when a recipe has genuinely separate components (a sauce
and a base, say). Do not use a heading for a single-part recipe.

Keep timings and temperatures in the step text. They do not scale, and they
should not.

## Metadata

- `yields` is the number of servings the quantities are written for. Always set it.
- `prep_time` and `cook_time` are minutes.
- Tag every recipe with a meal slot: `breakfast`, `lunch` or `dinner`. The
  meal-plan notifier reads these to pick a reminder time; untagged recipes are
  treated as dinner.
- Add cuisine or diet tags beyond that as useful, lowercase.
- `source` is a URL when the recipe came from somewhere.
