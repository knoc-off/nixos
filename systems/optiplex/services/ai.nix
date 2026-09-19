# Anthropic/OpenAI-compatible endpoint over the tailnet, backed by this
# host's own Claude Code subscription (see modules/compat-proxy.nix for the
# actual service, credential handling and usage-window session pings).
#
# Two paths on the same vhost, both tailnet-only:
#   /ai      -> LiteLLM (services/misc/litellm.nix), OpenAI *and* Anthropic
#               shaped requests both work here.
#   /ai-raw  -> compat-proxy directly. For native Anthropic clients (opencode,
#               Zed, anything setting ANTHROPIC_BASE_URL) that don't need
#               LiteLLM's translation layer, which can drop Anthropic-only
#               request fields on the way through.
#
# No API-key check at any layer -- compat-proxy never reads inbound headers,
# and LiteLLM has no master_key configured, so it accepts any bearer token as
# valid. Anything that can reach the tailnet can spend this host's Claude
# subscription quota; the Caddy tailnet-only firewall rule (default.nix) is
# the only access control.
{ config, ... }:
{
  services.compat-proxy = {
    enable = true;
    ntfyTokenFile = config.sops.secrets."services/ntfy/publish-token".path;
    # `claude setup-token` mints a 1y token; re-set alongside re-minting the
    # services/compat-proxy/oauth-token secret in shared-secrets.yaml.
    token.expiresAt = 1821299396000; # 2027-09-18T20:29:56Z (minted 2026-09-18)
  };

  services.caddy.virtualHosts."optiplex.tail.niko.ink" = {
    useACMEHost = "optiplex.tail.niko.ink";
    extraConfig = ''
      handle_path /ai/* {
        reverse_proxy localhost:${toString config.services.compat-proxy.litellmPort}
      }
      handle_path /ai-raw/* {
        reverse_proxy localhost:${toString config.services.compat-proxy.port}
      }
    '';
  };
}
