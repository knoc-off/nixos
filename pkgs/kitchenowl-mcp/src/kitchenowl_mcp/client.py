"""Thin async wrapper over the KitchenOwl REST API.

One shared httpx client, the long-lived KitchenOwl token as a default header,
and the household id pinned from config so it never appears in a tool signature.
The token never crosses the MCP boundary.

Routes used here are stable across v0.7.4..v0.7.10 (verified by diffing
`backend/app/controller/{recipe,item}/`).
"""

from __future__ import annotations

import time
from typing import Any

import httpx

from .config import Config
from .validator import CatalogueItem, ExistingRecipe


class KitchenOwlError(RuntimeError):
    pass


class KitchenOwlClient:
    def __init__(self, config: Config) -> None:
        self._config = config
        self._client = httpx.AsyncClient(
            base_url=f"{config.api_base}/api",
            headers={"Authorization": f"Bearer {config.api_token}"},
            timeout=httpx.Timeout(20.0),
        )
        self._items_cache: tuple[float, list[dict[str, Any]]] | None = None
        self._recipes_cache: tuple[float, list[dict[str, Any]]] | None = None

    @property
    def household(self) -> int:
        return self._config.household_id

    async def aclose(self) -> None:
        await self._client.aclose()

    def invalidate(self) -> None:
        """Drop caches. Called after every write, because the model creates an
        item and then immediately needs to reference it."""
        self._items_cache = None
        self._recipes_cache = None

    def _fresh(self, cache: tuple[float, Any] | None) -> Any | None:
        if cache is None:
            return None
        stamp, value = cache
        if time.monotonic() - stamp > self._config.cache_ttl:
            return None
        return value

    async def request(self, method: str, path: str, **kwargs: Any) -> Any:
        try:
            response = await self._client.request(method, path, **kwargs)
        except httpx.HTTPError as exc:
            raise KitchenOwlError(f"{method} {path} failed: {exc}") from exc
        if response.status_code >= 400:
            raise KitchenOwlError(
                f"{method} {path} returned {response.status_code}: {response.text[:500]}"
            )
        if not response.content:
            return None
        try:
            return response.json()
        except ValueError:
            return response.text

    async def get(self, path: str) -> Any:
        return await self.request("GET", path)

    async def post(self, path: str, payload: dict[str, Any]) -> Any:
        return await self.request("POST", path, json=payload)

    # --- reads -----------------------------------------------------------

    async def raw_items(self) -> list[dict[str, Any]]:
        cached = self._fresh(self._items_cache)
        if cached is not None:
            return cached
        items = await self.get(f"/household/{self.household}/item")
        self._items_cache = (time.monotonic(), items)
        return items

    async def raw_recipes(self) -> list[dict[str, Any]]:
        cached = self._fresh(self._recipes_cache)
        if cached is not None:
            return cached
        recipes = await self.get(f"/household/{self.household}/recipe")
        self._recipes_cache = (time.monotonic(), recipes)
        return recipes

    async def catalogue(self) -> list[CatalogueItem]:
        return [CatalogueItem(id=i["id"], name=i["name"]) for i in await self.raw_items()]

    async def existing_recipes(self) -> list[ExistingRecipe]:
        return [ExistingRecipe(id=r["id"], name=r["name"]) for r in await self.raw_recipes()]

    async def recipe(self, recipe_id: int) -> dict[str, Any]:
        return await self.get(f"/recipe/{recipe_id}")

    # --- writes ----------------------------------------------------------

    async def create_recipe(self, payload: dict[str, Any]) -> dict[str, Any]:
        result = await self.post(f"/household/{self.household}/recipe", payload)
        self.invalidate()
        return result

    async def update_recipe(self, recipe_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        result = await self.post(f"/recipe/{recipe_id}", payload)
        self.invalidate()
        return result
