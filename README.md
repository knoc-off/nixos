# My NixOS configuration.



# highlights:
- my firefox config
    - im going to try and turn this into a module, or similar.
    - sets up theming, for auto-collapsing sidebar. installs extensions, like sideberry, ublock origin, bitwarden, etc.
    - sets some user.js variables to minimize telemetry and to improve usability.
    - sets up a bunch of custom search engines, letting you easily search github, stack overflow, nix pkgs/wiki/options/home-manager.
    - sets dark mode options, removes white flash. sets custom colors. (WIP) still a bit ugly.
- my neovim configuration.
    - has migrated to its own repo/flake.
        - lets you install it anywhere super easy
    - using nixvim, still need to go through it and make it more usable.

- my hyprland configuration.
    - not many novel ideas, but i think the implementation is quite clean.
    - swaylock, set up so that its somewhat modular
    - many packages, are referenced declaratively. so no need to have them 'installed'
    - eww - very much a WIP, the goal is to make a module, that is much more declarative than existing modules, that just create a symlink to a folder.

- laptop system.
    - uses secure boot.
    - uses disko for declarative drive config.
    - need to clean thins up.

