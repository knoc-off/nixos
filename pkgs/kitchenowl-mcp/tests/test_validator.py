"""Unit tests for the validator. No KitchenOwl instance required."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from kitchenowl_mcp.validator import (
    CatalogueItem,
    ExistingRecipe,
    RecipeDraft,
    RecipeItemDraft,
    clean_item_name,
    extract_pills,
    normalise_pill,
    validate_recipe,
)

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="session")
def catalogue() -> list[CatalogueItem]:
    raw = json.loads((FIXTURES / "catalogue.json").read_text(encoding="utf-8"))
    return [CatalogueItem(id=e["id"], name=e["name"]) for e in raw]


def codes(result) -> set[str]:
    return {v.code for v in result.violations}


def good_draft(**overrides) -> RecipeDraft:
    base = dict(
        name="Spring onion omelette",
        description=(
            "1. Beat the @egg{3} with a pinch of @salt.\n"
            "2. Melt the @butter{10 g} in a pan and soften the @spring_onion.\n"
            "3. Pour in the eggs and cook until just set.\n"
        ),
        items=[
            RecipeItemDraft("egg", "3"),
            RecipeItemDraft("salt", "1 pinch"),
            RecipeItemDraft("butter", "10 g"),
            RecipeItemDraft("spring onion", "2"),
        ],
        yields=1,
        tags=("breakfast",),
        prep_time=5,
        cook_time=5,
    )
    base.update(overrides)
    return RecipeDraft(**base)


# --- grammar transcription -------------------------------------------------


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("spring_onion", "spring onion"),
        ("SPRING_ONION", "spring onion"),
        ("  egg  ", "egg"),
        ("crème_fraîche", "crème fraîche"),
    ],
)
def test_normalise_pill(raw: str, expected: str) -> None:
    assert normalise_pill(raw) == expected


def test_clean_item_name_strips_the_same_characters_as_the_renderer() -> None:
    assert clean_item_name("Crème fraîche (full fat)") == "crème fraîche full fat"
    assert clean_item_name("Salt, flaky") == "salt flaky"
    # `$` and `^` are anchors inside the upstream alternation, so the literal
    # characters survive. This is a quirk worth pinning.
    assert clean_item_name("a$b^c") == "a$b^c"


def test_extract_pills_handles_brace_form() -> None:
    pills = extract_pills("Whisk @flour{200 g} into the @milk.")
    assert [(p.name, p.description) for p in pills] == [
        ("flour", "200 g"),
        ("milk", None),
    ]


def test_extract_pills_stops_at_terminator_characters() -> None:
    assert [p.name for p in extract_pills("add @salt, then @pepper.")] == ["salt", "pepper"]


def test_extract_pills_ignores_code() -> None:
    markdown = "Use `@flour` here.\n\n```\n@milk\n```\n\nBut @egg counts."
    assert [p.name for p in extract_pills(markdown)] == ["egg"]


# --- happy path ------------------------------------------------------------


def test_valid_recipe_passes(catalogue) -> None:
    result = validate_recipe(good_draft(), catalogue=catalogue)
    assert result.ok, result.report()
    assert result.new_items == []


# --- pills -----------------------------------------------------------------


def test_unresolved_pill_is_an_error_with_suggestions(catalogue) -> None:
    draft = good_draft(
        description="1. Beat the @egg{3} with @slat.\n2. Fry in @butter and @spring_onion.\n"
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "unresolved_pill" in codes(result)
    message = next(v.message for v in result.violations if v.code == "unresolved_pill")
    assert "salt" in message


def test_declared_but_unreferenced_item_is_an_error(catalogue) -> None:
    draft = good_draft(
        items=[
            RecipeItemDraft("egg", "3"),
            RecipeItemDraft("salt", "1 pinch"),
            RecipeItemDraft("butter", "10 g"),
            RecipeItemDraft("spring onion", "2"),
            RecipeItemDraft("parmesan", "20 g"),
        ]
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "unreferenced_item" in codes(result)
    assert not result.ok


def test_multi_word_item_is_referenced_with_underscores(catalogue) -> None:
    draft = good_draft(
        description="1. Soften the @spring_onion in @butter{10 g}, add @egg{3} and @salt.\n"
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert result.ok, result.report()


# --- quantities ------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "1. Add 200 g @flour to the bowl.",
        "1. Add 2 large @egg to the bowl.",
        "1. Add ½ @onion to the bowl.",
    ],
)
def test_inline_quantity_is_flagged(catalogue, text: str) -> None:
    draft = good_draft(description=text, items=[RecipeItemDraft("flour", "200 g")])
    result = validate_recipe(draft, catalogue=catalogue)
    assert "inline_quantity" in codes(result)


def test_inline_quantity_is_a_warning_not_an_error(catalogue) -> None:
    draft = good_draft(
        description="1. Add 200 g @flour and stir.\n",
        items=[RecipeItemDraft("flour", "200 g")],
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert result.ok
    assert {v.code for v in result.warnings} >= {"inline_quantity"}


def test_step_numbers_are_not_mistaken_for_quantities(catalogue) -> None:
    draft = good_draft(
        description="1. Beat @egg{3}, @salt, @butter{10 g} and @spring_onion together.\n"
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "inline_quantity" not in codes(result)


def test_brace_quantity_is_not_flagged(catalogue) -> None:
    draft = good_draft(
        description="1. Whisk @flour{200 g} in.\n", items=[RecipeItemDraft("flour", "200 g")]
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "inline_quantity" not in codes(result)


# --- catalogue dedup -------------------------------------------------------


def test_near_duplicate_item_is_refused_with_candidates(catalogue) -> None:
    draft = good_draft(
        description="1. Slice the @spring_onions and fry.\n",
        items=[RecipeItemDraft("spring onions", "2")],
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "possible_duplicate_item" in codes(result)
    message = next(v.message for v in result.violations if v.code == "possible_duplicate_item")
    assert "spring onion" in message
    assert not result.ok


def test_force_new_items_allows_the_near_duplicate(catalogue) -> None:
    draft = good_draft(
        description="1. Slice the @spring_onions and fry.\n",
        items=[RecipeItemDraft("spring onions", "2")],
    )
    result = validate_recipe(draft, catalogue=catalogue, force_new_items=True)
    assert result.ok, result.report()
    assert result.new_items == ["spring onions"]


def test_genuinely_new_item_is_only_a_warning(catalogue) -> None:
    draft = good_draft(
        description="1. Toast the @nori and crumble over.\n",
        items=[RecipeItemDraft("nori", "1 sheet")],
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert result.ok, result.report()
    assert "new_item" in codes(result)
    assert result.new_items == ["nori"]


def test_case_and_accent_insensitive_catalogue_match(catalogue) -> None:
    draft = good_draft(
        description="1. Stir the @crème_fraîche through.\n",
        items=[RecipeItemDraft("Crème Fraîche", "2 tbsp")],
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert result.new_items == []
    assert result.ok, result.report()


# --- structural ------------------------------------------------------------


def test_duplicate_recipe_name_is_refused(catalogue) -> None:
    existing = [ExistingRecipe(id=7, name="spring onion OMELETTE")]
    result = validate_recipe(good_draft(), catalogue=catalogue, existing_recipes=existing)
    assert "duplicate_recipe" in codes(result)


def test_update_does_not_collide_with_itself(catalogue) -> None:
    existing = [ExistingRecipe(id=7, name="Spring onion omelette")]
    result = validate_recipe(
        good_draft(), catalogue=catalogue, existing_recipes=existing, recipe_id=7
    )
    assert result.ok, result.report()


def test_duplicate_declared_item_is_refused(catalogue) -> None:
    draft = good_draft(
        description="1. Beat @egg{3} and @salt, fry in @butter{10 g} with @spring_onion.\n",
        items=[
            RecipeItemDraft("egg", "3"),
            RecipeItemDraft("Egg", "1"),
            RecipeItemDraft("salt", "1 pinch"),
            RecipeItemDraft("butter", "10 g"),
            RecipeItemDraft("spring onion", "2"),
        ],
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "duplicate_item" in codes(result)


def test_name_over_128_characters_is_refused(catalogue) -> None:
    result = validate_recipe(good_draft(name="x" * 129), catalogue=catalogue)
    assert "name_too_long" in codes(result)


def test_zero_yields_is_refused(catalogue) -> None:
    result = validate_recipe(good_draft(yields=0), catalogue=catalogue)
    assert "no_yields" in codes(result)


def test_empty_description_is_refused(catalogue) -> None:
    result = validate_recipe(good_draft(description="   "), catalogue=catalogue)
    assert "empty_description" in codes(result)


def test_missing_tags_and_times_are_warnings(catalogue) -> None:
    result = validate_recipe(good_draft(tags=(), prep_time=0, cook_time=0), catalogue=catalogue)
    assert result.ok, result.report()
    assert {"no_tags", "no_times"} <= codes(result)


def test_unstructured_description_is_a_warning(catalogue) -> None:
    draft = good_draft(
        description="Beat @egg{3} with @salt, fry in @butter{10 g} with @spring_onion."
    )
    result = validate_recipe(draft, catalogue=catalogue)
    assert "unstructured_description" in codes(result)
    assert result.ok


# --- reporting -------------------------------------------------------------


def test_all_violations_are_reported_together(catalogue) -> None:
    draft = good_draft(
        name="",
        description="Add 200 g @flur and @slat.",
        items=[RecipeItemDraft("flour", "200 g"), RecipeItemDraft("nori", "1")],
        yields=0,
        tags=(),
    )
    result = validate_recipe(draft, catalogue=catalogue)
    found = codes(result)
    assert {
        "empty_name",
        "no_yields",
        "unresolved_pill",
        "unreferenced_item",
        "inline_quantity",
        "no_tags",
    } <= found, found
    report = result.report()
    assert report.count("\n") >= 5
