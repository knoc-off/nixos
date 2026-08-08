"""Recipe validation, ported from KitchenOwl's own markdown/item rules.

This module is deliberately pure: it takes a recipe draft plus a snapshot of the
household catalogue and returns a list of violations. No I/O, no KitchenOwl
instance required. It is the only part of this server where bugs are expensive,
so it is the only part that is unit tested.

The pill grammar and the item-name normalisation below are transcribed from
`kitchenowl/lib/helpers/recipe_item_markdown_extension.dart`
(class `RecipeExplicitItemMarkdownSyntax`). If that file changes upstream, this
one has to change with it.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass, field
from typing import Iterable, Sequence

# Verbatim from RecipeExplicitItemMarkdownSyntax._pattern. Matched
# case-insensitively, exactly as the Dart InlineSyntax is constructed.
#
# Note that `}` is *not* excluded from the name class upstream, and neither `$`
# nor `^` are anchors here (inside a character class they are literals). Both
# quirks are reproduced rather than tidied up, because the goal is to predict
# what the app will render, not to define a nicer grammar.
PILL_PATTERN = re.compile(
    r'@([^ \n.()\\/?*+,!%$#@^;:"=~{]+)(\{([^}]*)\})?',
    re.IGNORECASE,
)

# Applied to *item names* before comparison, from the same file. In Dart `$` and
# `^` are zero-width anchors inside this alternation, so they are no-ops and the
# corresponding literal characters survive. Python behaves identically, so the
# pattern is kept as-is.
_ITEM_NAME_STRIP = re.compile(r'\n|\.|\(|\)|\\|/|\?|\*|\+|,|!|%|$|#|@|^|;|:|"|=|~|\{')

# Fenced blocks and inline code spans are stripped before scanning: the Dart
# InlineSyntax runs inside the markdown inline parser, so it never sees them.
_FENCED_CODE = re.compile(r"^```.*?^```", re.MULTILINE | re.DOTALL)
_INLINE_CODE = re.compile(r"`[^`\n]*`")

_NUMBER = r"(?:\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[\u00bc-\u00be\u2150-\u215e])"
# A bare amount sitting immediately before a pill: "200 g @flour", "2 large @onions".
# Up to two intervening words so unit + adjective still trips it.
_INLINE_QUANTITY = re.compile(
    rf"(?P<qty>\b{_NUMBER}(?:\s+[^\W\d_]+){{0,2}})\s+(?=@)",
    re.IGNORECASE,
)

_ORDERED_STEP = re.compile(r"^\s*(?:\d+\.|[-*])\s+\S", re.MULTILINE)
_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+\S", re.MULTILINE)

# KitchenOwl truncates recipe names to 128 characters server-side, silently.
NAME_MAX_LENGTH = 128

ERROR = "error"
WARNING = "warning"


@dataclass(frozen=True)
class Violation:
    code: str
    severity: str
    message: str

    def render(self) -> str:
        return f"[{self.severity}] {self.code}: {self.message}"


@dataclass(frozen=True)
class RecipeItemDraft:
    name: str
    description: str = ""
    optional: bool = False


@dataclass(frozen=True)
class CatalogueItem:
    id: int
    name: str


@dataclass(frozen=True)
class ExistingRecipe:
    id: int
    name: str


@dataclass(frozen=True)
class RecipeDraft:
    name: str
    description: str
    items: Sequence[RecipeItemDraft]
    yields: int = 1
    tags: Sequence[str] = ()
    prep_time: int = 0
    cook_time: int = 0


@dataclass
class ValidationResult:
    violations: list[Violation] = field(default_factory=list)
    # Items in the draft that do not yet exist in the household catalogue and
    # would therefore be created as a side effect of saving the recipe.
    new_items: list[str] = field(default_factory=list)
    resolved_pills: list[str] = field(default_factory=list)

    @property
    def errors(self) -> list[Violation]:
        return [v for v in self.violations if v.severity == ERROR]

    @property
    def warnings(self) -> list[Violation]:
        return [v for v in self.violations if v.severity == WARNING]

    @property
    def ok(self) -> bool:
        return not self.errors

    def report(self) -> str:
        """Every violation at once, so the model can fix them in one round trip."""
        lines = [v.render() for v in self.violations]
        if self.new_items:
            lines.append(
                "[info] new_items: saving would create these catalogue items: "
                + ", ".join(sorted(self.new_items))
            )
        return "\n".join(lines)


def clean_item_name(name: str) -> str:
    """Normalise an item name the way the renderer does before comparing."""
    return _ITEM_NAME_STRIP.sub("", name.lower())


def normalise_pill(raw: str) -> str:
    """Normalise a captured pill token the way `onMatch` does."""
    return raw.replace("_", " ").strip().lower()


def strip_code(markdown: str) -> str:
    return _INLINE_CODE.sub("", _FENCED_CODE.sub("", markdown))


@dataclass(frozen=True)
class Pill:
    raw: str
    name: str
    description: str | None


def extract_pills(markdown: str) -> list[Pill]:
    """All `@token` / `@token{description}` occurrences outside code."""
    pills: list[Pill] = []
    for match in PILL_PATTERN.finditer(strip_code(markdown)):
        pills.append(
            Pill(
                raw=match.group(0),
                name=normalise_pill(match.group(1)),
                description=match.group(3),
            )
        )
    return pills


def _suggest(target: str, candidates: Iterable[str], limit: int = 3) -> list[str]:
    pool = list(dict.fromkeys(candidates))
    matches = difflib.get_close_matches(target, pool, n=limit, cutoff=0.72)
    if matches:
        return matches
    # difflib is unforgiving about short strings and plural/singular pairs, so
    # fall back to containment either way round.
    return [c for c in pool if target in c or c in target][:limit]


def validate_recipe(
    draft: RecipeDraft,
    *,
    catalogue: Sequence[CatalogueItem] = (),
    existing_recipes: Sequence[ExistingRecipe] = (),
    force_new_items: bool = False,
    recipe_id: int | None = None,
) -> ValidationResult:
    """Check a recipe draft against KitchenOwl's rules and the house style.

    Every check runs; nothing short-circuits. `recipe_id` excludes a recipe from
    its own duplicate-name check when updating.
    """
    result = ValidationResult()
    add = result.violations.append

    declared = {clean_item_name(i.name): i for i in draft.items if i.name.strip()}
    catalogue_by_clean = {clean_item_name(c.name): c for c in catalogue}

    # --- structural -----------------------------------------------------
    if not draft.name.strip():
        add(Violation("empty_name", ERROR, "Recipe name is empty."))
    elif len(draft.name.strip()) > NAME_MAX_LENGTH:
        add(
            Violation(
                "name_too_long",
                ERROR,
                f"Recipe name is {len(draft.name.strip())} characters; KitchenOwl "
                f"silently truncates to {NAME_MAX_LENGTH}. Shorten it yourself so "
                "the stored name is the one you intended.",
            )
        )

    if not draft.items:
        add(Violation("no_items", ERROR, "Recipe has no items."))

    if not draft.description.strip():
        add(Violation("empty_description", ERROR, "Recipe description is empty."))

    if draft.yields <= 0:
        add(
            Violation(
                "no_yields",
                ERROR,
                "yields must be at least 1; scaling item quantities depends on it.",
            )
        )

    seen: set[str] = set()
    for item in draft.items:
        key = clean_item_name(item.name)
        if not item.name.strip():
            add(Violation("empty_item_name", ERROR, "An item has an empty name."))
        elif key in seen:
            add(
                Violation(
                    "duplicate_item",
                    ERROR,
                    f"Item {item.name!r} is declared more than once. KitchenOwl keys "
                    "recipe items by item id, so the second one overwrites the first.",
                )
            )
        seen.add(key)

    # --- duplicate recipe ------------------------------------------------
    for existing in existing_recipes:
        if existing.id == recipe_id:
            continue
        if existing.name.strip().lower() == draft.name.strip().lower():
            add(
                Violation(
                    "duplicate_recipe",
                    ERROR,
                    f"A recipe named {existing.name!r} already exists (id {existing.id}). "
                    "Use update_recipe, or pick a different name.",
                )
            )

    # --- pills -----------------------------------------------------------
    pills = extract_pills(draft.description)
    referenced: set[str] = set()

    for pill in pills:
        if pill.name in declared:
            referenced.add(pill.name)
            result.resolved_pills.append(pill.name)
            continue
        hints = _suggest(pill.name, declared.keys())
        detail = f" Declared items that look similar: {', '.join(hints)}." if hints else ""
        add(
            Violation(
                "unresolved_pill",
                ERROR,
                f"{pill.raw!r} does not resolve to any declared recipe item, so "
                "KitchenOwl will render it as literal text instead of a chip."
                + detail,
            )
        )

    for key, item in declared.items():
        if key not in referenced:
            add(
                Violation(
                    "unreferenced_item",
                    ERROR,
                    f"Item {item.name!r} is declared but never referenced in the "
                    f"description. Add @{key.replace(' ', '_')} where it is used, "
                    "or drop the item.",
                )
            )

    # --- quantities ------------------------------------------------------
    # Heuristic, hence a warning: amounts must live where they can scale, which
    # means the item's description field or the pill's `{...}` override. A bare
    # number in prose stays fixed when the user changes servings.
    for match in _INLINE_QUANTITY.finditer(strip_code(draft.description)):
        qty = match.group("qty").strip()
        add(
            Violation(
                "inline_quantity",
                WARNING,
                f"{qty!r} sits immediately before a pill. Numbers in prose do not "
                f"scale with servings; write @item{{{qty}}} or move the amount into "
                "the item's description field.",
            )
        )

    # --- catalogue / dedup -----------------------------------------------
    for key, item in declared.items():
        if key in catalogue_by_clean:
            continue
        result.new_items.append(item.name)
        near = _suggest(key, catalogue_by_clean.keys())
        if near and not force_new_items:
            add(
                Violation(
                    "possible_duplicate_item",
                    ERROR,
                    f"{item.name!r} is not in the catalogue, but these existing items "
                    f"look similar: {', '.join(near)}. Recipe items are matched by "
                    "name, so a near-miss silently creates a second catalogue entry. "
                    "Reuse one of the above, or pass force_new_items=true.",
                )
            )
        elif not near:
            add(
                Violation(
                    "new_item",
                    WARNING,
                    f"{item.name!r} will be created as a new catalogue item.",
                )
            )

    # --- house style -----------------------------------------------------
    if not draft.tags:
        add(
            Violation(
                "no_tags",
                WARNING,
                "Recipe has no tags. The meal-plan notifier uses breakfast/lunch/"
                "dinner tags to pick a reminder slot; untagged recipes default to dinner.",
            )
        )

    body = strip_code(draft.description)
    if draft.description.strip() and not (_ORDERED_STEP.search(body) or _HEADING.search(body)):
        add(
            Violation(
                "unstructured_description",
                WARNING,
                "Description has no numbered steps, bullets or headings. Write the "
                "method as a numbered list so the cooking view can step through it.",
            )
        )

    if draft.prep_time <= 0 and draft.cook_time <= 0:
        add(
            Violation(
                "no_times",
                WARNING,
                "Neither prep_time nor cook_time is set (both are in minutes).",
            )
        )

    return result
