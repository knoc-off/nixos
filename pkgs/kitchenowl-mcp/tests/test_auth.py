"""Tests for the OAuth gate.

These cover the two things that actually restrict access: the GitHub login
allowlist, and the redirect URI allowlist. Both fail open if they regress --
GitHub itself authenticates every account on the site -- so they are worth
pinning down.
"""

from __future__ import annotations

import asyncio

import pytest
from fastmcp.server.auth.providers.github import GitHubProvider
from key_value.aio.stores.memory import MemoryStore
from mcp.server.auth.provider import RegistrationError
from mcp.shared.auth import OAuthClientInformationFull

from kitchenowl_mcp.auth import AllowlistGitHubProvider


def make_provider(logins=("allowed",), redirects=("https://claude.ai/api/mcp/auth_callback",)):
    return AllowlistGitHubProvider(
        allowed_logins=tuple(logins),
        allowed_client_redirect_uris=list(redirects),
        client_id="test-client-id",
        client_secret="test-client-secret",
        base_url="https://mcp.example.com",
        client_storage=MemoryStore(),
    )


class FakeToken:
    """Stands in for the AccessToken the upstream verifier returns."""

    def __init__(self, login):
        self.claims = {"login": login}


def verify_with_upstream_login(provider, login, monkeypatch):
    """Run verify_token with the upstream GitHub check stubbed to `login`.

    Patching the parent class is what lets `super().verify_token(...)` inside
    the provider resolve to this stub, so no GitHub API call is made.
    """

    async def fake_verify(self, token):
        return None if login is None else FakeToken(login)

    monkeypatch.setattr(GitHubProvider, "verify_token", fake_verify, raising=True)
    return asyncio.run(provider.verify_token("irrelevant"))


def test_allowed_login_is_admitted(monkeypatch):
    provider = make_provider(logins=("allowed",))
    assert verify_with_upstream_login(provider, "allowed", monkeypatch) is not None


def test_unlisted_login_is_rejected(monkeypatch):
    """The whole point: a valid GitHub account is not enough."""
    provider = make_provider(logins=("allowed",))
    assert verify_with_upstream_login(provider, "stranger", monkeypatch) is None


def test_login_match_is_case_insensitive(monkeypatch):
    """GitHub logins are case-insensitive; the allowlist must not be stricter."""
    provider = make_provider(logins=("Allowed",))
    assert verify_with_upstream_login(provider, "aLLoWeD", monkeypatch) is not None


def test_failed_upstream_verification_stays_rejected(monkeypatch):
    provider = make_provider()
    assert verify_with_upstream_login(provider, None, monkeypatch) is None


def test_empty_allowlist_refuses_to_construct():
    with pytest.raises(ValueError, match="allowed_logins is empty"):
        make_provider(logins=())


def test_empty_redirect_list_refuses_to_construct():
    with pytest.raises(ValueError, match="allowed_client_redirect_uris is empty"):
        make_provider(redirects=())


def register(provider, redirect_uri):
    return asyncio.run(
        provider.register_client(
            OAuthClientInformationFull(
                client_id="some-client",
                redirect_uris=[redirect_uri],
                grant_types=["authorization_code", "refresh_token"],
                response_types=["code"],
                client_name="test",
            )
        )
    )


def test_registration_accepts_allowed_redirect():
    provider = make_provider()
    register(provider, "https://claude.ai/api/mcp/auth_callback")


def test_registration_rejects_foreign_redirect():
    provider = make_provider()
    with pytest.raises(RegistrationError) as excinfo:
        register(provider, "https://evil.example.com/steal")
    assert excinfo.value.error == "invalid_redirect_uri"
