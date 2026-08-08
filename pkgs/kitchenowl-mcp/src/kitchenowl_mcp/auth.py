"""OAuth for MCP clients that cannot send a custom Authorization header.

Claude's web connector speaks OAuth and offers no field to paste a bearer
token into, so the shared-secret gate in `server.py` is unusable there.
FastMCP's OAuthProxy bridges the gap: MCP clients register with us dynamically
(DCR), while upstream we present one fixed GitHub OAuth app credential, which
is all GitHub supports.

The security-relevant part is what GitHub does *not* give us. A successful
GitHub login only proves the caller holds some GitHub account -- every account
on the site passes. Authentication is therefore not authorization here, and
`AllowlistGitHubProvider` supplies the missing half by rejecting any login that
is not explicitly named. It is the only thing standing between the public
internet and this household.
"""

from __future__ import annotations

from mcp.server.auth.provider import RegistrationError
from mcp.shared.auth import OAuthClientInformationFull

from fastmcp.server.auth.auth import AccessToken
from fastmcp.server.auth.providers.github import GitHubProvider
from fastmcp.server.auth.redirect_validation import validate_redirect_uri
from fastmcp.utilities.logging import get_logger

logger = get_logger(__name__)

# Anthropic's connector callbacks. Kept as the built-in default because
# OAuthProxy's own default is "allow every redirect URI", which turns the
# authorization endpoint into an open redirector for stolen auth codes.
DEFAULT_REDIRECT_URIS = (
    "https://claude.ai/api/mcp/auth_callback",
    "https://claude.com/api/mcp/auth_callback",
)


class AllowlistGitHubProvider(GitHubProvider):
    """GitHubProvider that admits only named GitHub logins.

    The check lives in `verify_token` rather than in the callback so it is
    re-applied on every single request: removing someone from the allowlist
    locks them out immediately, even if they still hold a live token issued
    before the change.
    """

    def __init__(
        self,
        *,
        allowed_logins: tuple[str, ...],
        allowed_client_redirect_uris: list[str],
        **kwargs,
    ) -> None:
        super().__init__(allowed_client_redirect_uris=allowed_client_redirect_uris, **kwargs)
        self._allowed_logins = {login.strip().lower() for login in allowed_logins if login.strip()}
        # Kept rather than read back off the base class: this is the list the
        # registration check below enforces, and it must not silently become
        # None (which upstream reads as "allow everything").
        self._allowed_redirects = list(allowed_client_redirect_uris)
        if not self._allowed_logins:
            # Refuse to start rather than fall open to all of GitHub.
            raise ValueError("allowed_logins is empty; refusing to admit every GitHub account.")
        if not self._allowed_redirects:
            raise ValueError("allowed_client_redirect_uris is empty; no client could ever connect.")

    async def register_client(self, client_info: OAuthClientInformationFull) -> None:
        """Reject bad redirect URIs at registration instead of at /authorize.

        The base class stores any redirect URI a client asks for and only
        rejects it later, when authorization is attempted. That is safe --
        no code is ever issued to an unlisted URI -- but it means the server
        hands out credentials to clients it will never serve, and the refusal
        surfaces mid-flow rather than at setup. Failing here keeps rejected
        clients out of storage entirely.
        """
        for uri in client_info.redirect_uris or []:
            if not validate_redirect_uri(uri, self._allowed_redirects):
                logger.warning(
                    "Refusing client registration for %r: redirect_uri %s is not allowed.",
                    client_info.client_name or "<unnamed>",
                    uri,
                )
                raise RegistrationError(
                    error="invalid_redirect_uri",
                    error_description=f"Redirect URI {uri} is not allowed by this server.",
                )

        await super().register_client(client_info)

    async def verify_token(self, token: str) -> AccessToken | None:
        access = await super().verify_token(token)
        if access is None:
            return None

        login = str(access.claims.get("login") or "").lower()
        if login not in self._allowed_logins:
            logger.warning(
                "Denying MCP access to GitHub user %r: not in allowed_logins.",
                login or "<unknown>",
            )
            return None

        return access


def build_auth_provider(config) -> AllowlistGitHubProvider | None:
    """Construct the OAuth provider, or None when the bearer token is in use."""
    if not config.oauth_enabled:
        return None

    return AllowlistGitHubProvider(
        allowed_logins=config.oauth_allowed_users,
        allowed_client_redirect_uris=list(
            config.oauth_allowed_redirect_uris or DEFAULT_REDIRECT_URIS
        ),
        client_id=config.oauth_client_id,
        client_secret=config.oauth_client_secret,
        base_url=config.oauth_base_url,
        # Read-only view of the profile: all we consume is `login`, and the
        # broader "user" scope that GitHubProvider defaults to also carries
        # write access to profile data we have no use for.
        required_scopes=["read:user"],
        # Cheap protection against a malicious client silently obtaining a
        # token in the user's name; also re-confirms which client is being
        # authorized. Costs one click per client registration.
        require_authorization_consent=True,
        # Bounds how long a revoked GitHub token keeps working, at the price
        # of one GitHub API call per request beyond the window.
        cache_ttl_seconds=300,
    )
