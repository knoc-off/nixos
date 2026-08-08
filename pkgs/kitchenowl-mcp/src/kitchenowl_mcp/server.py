"""FastMCP server: transport/auth at the edge, curated tools inside.

Reads return compact projections; KitchenOwl's own `obj_to_full_dict` carries a
lot of noise that would be paid for on every call. Writes go through the
validator in `validator.py`, which reports every violation at once.
"""

from __future__ import annotations

import hmac
from importlib import resources
from pathlib import Path
from typing import Annotated, Any

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import BaseModel, Field
from starlette.middleware import Middleware
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from .auth import build_auth_provider
from .client import KitchenOwlClient, KitchenOwlError
from .config import Config
from .validator import (
    RecipeDraft,
    RecipeItemDraft,
    ValidationResult,
    validate_recipe,
)


class BearerAuthMiddleware:
    """Constant-time shared-secret check, applied before anything else.

    Kept out here so no tool ever has to think about who is calling. FastMCP's
    built-in verifiers target JWT and OAuth; for one fixed token this is less
    indirection.
    """

    def __init__(self, app: ASGIApp, token: str) -> None:
        self.app = app
        self._token = token.encode()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        header = ""
        for key, value in scope.get("headers", []):
            if key == b"authorization":
                header = value.decode("latin-1")
                break

        scheme, _, presented = header.partition(" ")
        if scheme.lower() != "bearer" or not hmac.compare_digest(
            presented.strip().encode(), self._token
        ):
            response = JSONResponse({"error": "unauthorized"}, status_code=401)
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)


class RecipeItemInput(BaseModel):
    name: str = Field(
        description=(
            "Generic ingredient name, matched case-insensitively against the "
            "household catalogue. A name that does not exist is created."
        )
    )
    description: str = Field(
        default="",
        description="Amount, e.g. '200 g'. Scales with servings. Not part of the name.",
    )
    optional: bool = Field(
        default=False,
        description="True only if the recipe works without this ingredient.",
    )


def _project_item(item: dict[str, Any]) -> dict[str, Any]:
    category = item.get("category") or {}
    return {
        "id": item.get("id"),
        "name": item.get("name"),
        "icon": item.get("icon"),
        "category": category.get("name"),
    }


def _project_recipe(recipe: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": recipe.get("id"),
        "name": recipe.get("name"),
        "yields": recipe.get("yields"),
        "time": recipe.get("time"),
        "prep_time": recipe.get("prep_time"),
        "cook_time": recipe.get("cook_time"),
        "tags": [t.get("name") for t in recipe.get("tags") or []],
    }


def _load_style_guide(config: Config) -> str:
    if config.style_guide_path:
        return Path(config.style_guide_path).read_text(encoding="utf-8")
    return resources.files(__package__).joinpath("style_guide.md").read_text(encoding="utf-8")


def _drafts(items: list[RecipeItemInput]) -> list[RecipeItemDraft]:
    return [
        RecipeItemDraft(name=i.name, description=i.description, optional=i.optional)
        for i in items
    ]


def _payload(draft: RecipeDraft, source: str) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "name": draft.name.strip(),
        "description": draft.description,
        "yields": draft.yields,
        "prep_time": draft.prep_time,
        "cook_time": draft.cook_time,
        "time": draft.prep_time + draft.cook_time,
        "tags": list(draft.tags),
        # `optional` defaults to True in KitchenOwl's marshmallow schema, so it
        # is always sent explicitly.
        "items": [
            {"name": i.name.strip(), "description": i.description, "optional": i.optional}
            for i in draft.items
        ],
    }
    if source:
        payload["source"] = source
    return payload


def _preview(draft: RecipeDraft, result: ValidationResult, source: str) -> dict[str, Any]:
    return {
        "dry_run": True,
        "would_send": _payload(draft, source),
        "new_items": sorted(result.new_items),
        "warnings": [v.render() for v in result.warnings],
        "resolved_pills": sorted(set(result.resolved_pills)),
    }


def build_server(config: Config, client: KitchenOwlClient, auth: Any = None) -> FastMCP:
    mcp: FastMCP = FastMCP(
        name="kitchenowl",
        auth=auth,
        instructions=(
            "Recipe management for a single KitchenOwl household. Call "
            "get_style_guide before writing a recipe, and list_items before "
            "naming ingredients. create_recipe and update_recipe validate the "
            "draft and refuse to write if it would render incorrectly; use "
            "dry_run=true to iterate."
        ),
    )

    async def _validate(
        draft: RecipeDraft, force_new_items: bool, recipe_id: int | None
    ) -> ValidationResult:
        return validate_recipe(
            draft,
            catalogue=await client.catalogue(),
            existing_recipes=await client.existing_recipes(),
            force_new_items=force_new_items,
            recipe_id=recipe_id,
        )

    @mcp.tool
    async def list_items() -> list[dict[str, Any]]:
        """List the household's item catalogue: id, name, icon and category.

        Recipe ingredients are matched by name against this list. Reuse an
        existing name rather than inventing a variant.
        """
        try:
            return [_project_item(i) for i in await client.raw_items()]
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

    @mcp.tool
    async def list_recipes() -> list[dict[str, Any]]:
        """List all recipes in the household, without their descriptions."""
        try:
            return [_project_recipe(r) for r in await client.raw_recipes()]
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

    @mcp.tool
    async def get_recipe(recipe_id: int) -> dict[str, Any]:
        """Fetch one recipe in full, including its markdown description and items."""
        try:
            return await client.recipe(recipe_id)
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

    @mcp.tool
    async def get_style_guide() -> str:
        """The house style for recipes: how to name items, write `@item` pills,
        place quantities so they scale, and structure the method. Read this
        before creating or updating a recipe."""
        return _load_style_guide(config)

    if config.enable_raw_get:

        @mcp.tool
        async def kitchenowl_get(path: str) -> Any:
            """GET an arbitrary KitchenOwl API path, for reads the other tools
            do not cover.

            `path` is relative to `/api`, e.g. `/household/1/planner`,
            `/household/1/shoppinglist`, `/recipe/12`, `/household/1/tag`.
            Read-only; there is no corresponding write escape hatch.
            """
            if not path.startswith("/") or "://" in path or ".." in path:
                raise ToolError(
                    f"path must be an /api-relative path such as '/household/"
                    f"{config.household_id}/planner'; got {path!r}"
                )
            try:
                return await client.get(path)
            except KitchenOwlError as exc:
                raise ToolError(str(exc)) from exc

    @mcp.tool
    async def create_recipe(
        name: str,
        description: Annotated[
            str, Field(description="Markdown method, referencing items as @item_name.")
        ],
        items: list[RecipeItemInput],
        yields: Annotated[int, Field(description="Servings the amounts are written for.")] = 1,
        tags: list[str] | None = None,
        prep_time: Annotated[int, Field(description="Minutes.")] = 0,
        cook_time: Annotated[int, Field(description="Minutes.")] = 0,
        source: str = "",
        force_new_items: Annotated[
            bool,
            Field(description="Create items that look like near-duplicates anyway."),
        ] = False,
        dry_run: Annotated[
            bool, Field(description="Validate and preview without writing.")
        ] = False,
    ) -> dict[str, Any]:
        """Create a recipe, after checking it renders and scales correctly.

        Validates that every `@pill` resolves to a declared item, that every
        item is referenced, that quantities are placed where they scale, that
        ingredient names are not near-duplicates of existing catalogue items,
        and that no recipe of this name already exists. All violations are
        reported together.
        """
        draft = RecipeDraft(
            name=name,
            description=description,
            items=_drafts(items),
            yields=yields,
            tags=tuple(tags or ()),
            prep_time=prep_time,
            cook_time=cook_time,
        )
        try:
            result = await _validate(draft, force_new_items, recipe_id=None)
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

        if not result.ok:
            raise ToolError(f"Recipe was not created.\n{result.report()}")
        if dry_run:
            return _preview(draft, result, source)

        try:
            created = await client.create_recipe(_payload(draft, source))
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc
        return {
            "created": _project_recipe(created),
            "new_items": sorted(result.new_items),
            "warnings": [v.render() for v in result.warnings],
        }

    @mcp.tool
    async def update_recipe(
        recipe_id: int,
        name: str | None = None,
        description: str | None = None,
        items: list[RecipeItemInput] | None = None,
        yields: int | None = None,
        tags: list[str] | None = None,
        prep_time: int | None = None,
        cook_time: int | None = None,
        source: str | None = None,
        force_new_items: bool = False,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Update a recipe. Omitted fields keep their current value.

        The validator runs against the merged result, not just the fields you
        passed, so changing the description alone still checks it against the
        recipe's existing items.

        Note that KitchenOwl replaces the item and tag lists wholesale: passing
        `items` drops any item not in the list.
        """
        try:
            current = await client.recipe(recipe_id)
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

        current_items = [
            RecipeItemDraft(
                name=i.get("name", ""),
                description=i.get("description") or "",
                optional=bool(i.get("optional", False)),
            )
            for i in current.get("items") or []
        ]
        merged = RecipeDraft(
            name=current["name"] if name is None else name,
            description=(current.get("description") or "") if description is None else description,
            items=current_items if items is None else _drafts(items),
            yields=(current.get("yields") or 1) if yields is None else yields,
            tags=(
                tuple(t.get("name") for t in current.get("tags") or [])
                if tags is None
                else tuple(tags)
            ),
            prep_time=(current.get("prep_time") or 0) if prep_time is None else prep_time,
            cook_time=(current.get("cook_time") or 0) if cook_time is None else cook_time,
        )
        effective_source = (current.get("source") or "") if source is None else source

        try:
            result = await _validate(merged, force_new_items, recipe_id=recipe_id)
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc

        if not result.ok:
            raise ToolError(f"Recipe {recipe_id} was not updated.\n{result.report()}")
        if dry_run:
            return _preview(merged, result, effective_source)

        try:
            updated = await client.update_recipe(recipe_id, _payload(merged, effective_source))
        except KitchenOwlError as exc:
            raise ToolError(str(exc)) from exc
        return {
            "updated": _project_recipe(updated),
            "new_items": sorted(result.new_items),
            "warnings": [v.render() for v in result.warnings],
        }

    return mcp


def main() -> None:
    import uvicorn

    config = Config.from_env()
    client = KitchenOwlClient(config)
    auth = build_auth_provider(config)
    mcp = build_server(config, client, auth=auth)

    # With OAuth the provider is the gate, and it must not sit behind the
    # bearer middleware: the OAuth endpoints themselves (discovery, consent,
    # callback) are reached without a token by definition.
    middleware = (
        []
        if auth is not None
        else [Middleware(BearerAuthMiddleware, token=config.mcp_token)]
    )

    app = mcp.http_app(
        path="/mcp",
        stateless_http=True,
        middleware=middleware,
    )
    uvicorn.run(app, host=config.host, port=config.port, access_log=False)
