"""Configuration, read once from the environment at startup.

Tokens are read from files (systemd LoadCredential) in preference to plain
environment variables, matching how the other KitchenOwl services on this host
get their secrets.

This server authenticates nobody. mcp-auth-proxy runs in front of it and is the
only gate, so `host` must stay on loopback: binding it publicly exposes the
whole household to anyone who can reach the port.
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


@dataclass(frozen=True)
class Config:
    api_base: str
    api_token: str
    household_id: int
    host: str
    port: int
    style_guide_path: str | None
    enable_raw_get: bool
    cache_ttl: float

    @classmethod
    def from_env(cls) -> "Config":
        api_token = _read_secret("KITCHENOWL_API_TOKEN")
        if not api_token:
            raise SystemExit("KITCHENOWL_API_TOKEN (or _FILE) is unset.")

        return cls(
            api_base=os.environ.get("KITCHENOWL_API_BASE", "http://127.0.0.1:3043").rstrip("/"),
            api_token=api_token,
            household_id=int(os.environ.get("KITCHENOWL_HOUSEHOLD_ID", "1")),
            host=os.environ.get("KITCHENOWL_MCP_HOST", "127.0.0.1"),
            port=int(os.environ.get("KITCHENOWL_MCP_PORT", "3044")),
            style_guide_path=os.environ.get("KITCHENOWL_MCP_STYLE_GUIDE") or None,
            enable_raw_get=_flag("KITCHENOWL_MCP_ENABLE_RAW_GET", True),
            cache_ttl=float(os.environ.get("KITCHENOWL_MCP_CACHE_TTL", "60")),
        )
