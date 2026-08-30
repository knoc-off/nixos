# Modpack distribution -- self-hosted packwiz remote.
#
# Serves the client side of inkwell so players install and
# update it from here and nowhere else:
#
#   https://mc.niko.ink/pack/inkwell.zip  <- import into Prism
#   https://mc.niko.ink/pack/pack.toml                     <- packwiz remote
#   https://mc.niko.ink/pack/jars/*.jar                    <- the mods
#
# The zip is a bare Prism instance (~90 KB, no jars) whose pre-launch hook runs
# packwiz-installer against pack.toml. First launch pulls the mods; every
# launch after that pulls only what changed. packwiz-installer-bootstrap.jar is
# served from here too, so a client never contacts Modrinth or GitHub.
#
# This shares the mc.niko.ink name with Gate, which is unrelated: Gate is a raw
# TCP listener on 25565 (see minecraft-gate.nix) and this is HTTP on 443. The
# name carries no HTTP record of its own -- headscale.nix deliberately omits
# mc.niko.ink from extra_records -- so tailnet and WAN clients both resolve it
# to this host and get the same pack.
#
# IMPORTANT -- deploy optiplex and this host together.
# The served pack and the server's own mods both come from the pinned
# minecraft-modpack input. Deploying only this host publishes mods the server
# does not have, and NeoForge disconnects clients whose mod set does not match
# during the CONFIG-phase registry sync. After `nix flake update
# minecraft-modpack`, rebuild optiplex and hetzner from the same lock.
{
  inputs,
  pkgs,
  ...
}:
let
  packSite = inputs.minecraft-modpack.packages.${pkgs.stdenv.hostPlatform.system}.packSite;
in
{
  services.caddy.virtualHosts."mc.niko.ink".extraConfig = ''
    import security-headers

    handle_path /pack/* {
      root * ${packSite}

      # Jar filenames carry their version, so a given URL's bytes never
      # change and the client can keep them indefinitely. The two TOMLs are
      # the opposite: they are how a client learns an update exists, so a
      # cached copy would pin players to a stale mod set.
      header /jars/* Cache-Control "public, max-age=31536000, immutable"
      header /pack.toml Cache-Control "no-cache"
      header /index.toml Cache-Control "no-cache"

      file_server
    }
  '';
}
