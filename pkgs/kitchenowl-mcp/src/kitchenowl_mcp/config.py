"""Configuration, read once from the environment at startup.

Tokens are read from files (systemd LoadCredential) in preference to plain
environment variables, matching how the other KitchenOwl services on this host
get their secrets.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _read_secret(env_name: str) -> str:
    """Read a secret from `<ENV>_FILE` if set, else from `<ENV>`."""
    path = os.environ.get(f"{env_name}_FILE")
    if path:
        return Path(path).read_text(encoding="utf-8").strip()
    return os.environ.get(env_name, "").strip()


def _flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _list(name: str) -> tuple[str, ...]:
    """Split a comma- or whitespace-separated env var into entries."""
    raw = os.environ.get(name, "").replace(",", " ")
    return tuple(part for part in raw.split() if part)


@dataclass(frozen=True)
class Config:
    api_base: str
    api_token: str
    mcp_token: str
    household_id: int
    host: str
    port: int
    style_guide_path: str | None
    enable_raw_get: bool
    cache_ttl: float
    oauth_base_url: str
    oauth_client_id: str
    oauth_client_secret: str
    oauth_allowed_users: tuple[str, ...]
    oauth_allowed_redirect_uris: tuple[str, ...]

    @property
    def oauth_enabled(self) -> bool:
        return bool(self.oauth_base_url)

    @classmethod
    def from_env(cls) -> "Config":
        mcp_token = _read_secret("KITCHENOWL_MCP_TOKEN")
        api_token = _read_secret("KITCHENOWL_API_TOKEN")

        oauth_base_url = os.environ.get("KITCHENOWL_MCP_OAUTH_BASE_URL", "").strip().rstrip("/")
        oauth_client_id = _read_secret("KITCHENOWL_MCP_OAUTH_CLIENT_ID")
        oauth_client_secret = _read_secret("KITCHENOWL_MCP_OAUTH_CLIENT_SECRET")
        oauth_allowed_users = _list("KITCHENOWL_MCP_OAUTH_ALLOWED_USERS")
        oauth_redirect_uris = _list("KITCHENOWL_MCP_OAUTH_REDIRECT_URIS")

        # Any one of these implies OAuth was meant to be on; a half-configured
        # provider must fail loudly rather than quietly fall back to a token.
        oauth_intended = bool(oauth_base_url or oauth_client_id or oauth_client_secret)

        if oauth_intended:
            if mcp_token:
                raise SystemExit(
                    "Both OAuth and KITCHENOWL_MCP_TOKEN are configured. The static token "
                    "would bypass the GitHub allowlist entirely; pick one."
                )
            if not (oauth_base_url and oauth_client_id and oauth_client_secret):
                raise SystemExit(
                    "OAuth needs KITCHENOWL_MCP_OAUTH_BASE_URL, _CLIENT_ID and "
                    "_CLIENT_SECRET (or their _FILE forms)."
                )
            if not oauth_allowed_users:
                raise SystemExit(
                    "KITCHENOWL_MCP_OAUTH_ALLOWED_USERS is empty. GitHub authenticates "
                    "every account on the site, so an empty allowlist would expose this "
                    "household to anyone with a GitHub login."
                )
            if not oauth_base_url.startswith("https://"):
                # Auth codes and the consent flow ride on this URL.
                raise SystemExit(
                    f"KITCHENOWL_MCP_OAUTH_BASE_URL must be https, got {oauth_base_url!r}."
                )
        elif not mcp_token:
            raise SystemExit(
                "Neither OAuth nor KITCHENOWL_MCP_TOKEN (or _FILE) is configured; "
                "refusing to start an unauthenticated MCP server."
            )

        if not api_token:
            raise SystemExit("KITCHENOWL_API_TOKEN (or _FILE) is unset.")

        return cls(
            api_base=os.environ.get("KITCHENOWL_API_BASE", "http://127.0.0.1:3043").rstrip("/"),
            api_token=api_token,
            mcp_token=mcp_token,
            household_id=int(os.environ.get("KITCHENOWL_HOUSEHOLD_ID", "1")),
            host=os.environ.get("KITCHENOWL_MCP_HOST", "127.0.0.1"),
            port=int(os.environ.get("KITCHENOWL_MCP_PORT", "3044")),
            style_guide_path=os.environ.get("KITCHENOWL_MCP_STYLE_GUIDE") or None,
            enable_raw_get=_flag("KITCHENOWL_MCP_ENABLE_RAW_GET", True),
            cache_ttl=float(os.environ.get("KITCHENOWL_MCP_CACHE_TTL", "60")),
            oauth_base_url=oauth_base_url,
            oauth_client_id=oauth_client_id,
            oauth_client_secret=oauth_client_secret,
            oauth_allowed_users=oauth_allowed_users,
            oauth_allowed_redirect_uris=oauth_redirect_uris,
        )
