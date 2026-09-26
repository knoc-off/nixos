# NixOS Configuration

My personal NixOS flake for my laptops, a home server, a VPS, and a Raspberry Pi.

## Hosts

| Host            | Hardware           | Role                                        |
| --------------- | ------------------ | ------------------------------------------- |
| `framework13`   | Framework 13 (AMD) | Main laptop                                 |
| `thinkpad-work` | Lenovo ThinkPad    | Work laptop                                 |
| `optiplex`      | Dell OptiPlex 7080 | Home server: Minecraft, nix cache, services |
| `hetzner`       | Hetzner VPS        | Public web services, Gate ingress           |
| `rpi-4b-plus`   | Raspberry Pi 4     | Home Assistant, MQTT                        |

## Highlights

- Hyprland with custom keybindings and animations
- Secure Boot via lanzaboote, with measured boot and TPM2 auto-unlock on `optiplex`
- Declarative disk layout with disko (encrypted btrfs)
- Secrets with sops-nix
- home-manager for user config
- Neovim built with nixvim
- Minecraft via nix-minecraft on `optiplex`, exposed through Gate on `hetzner` over the tailnet
- A theme generator built on a pure-Nix OkLab/OkHSL implementation, for perceptually uniform colors

## Layout

```
flake.nix   hosts and outputs
systems/    one directory per host
modules/    reusable NixOS and home-manager modules (auto-discovered)
pkgs/       custom packages (auto-discovered)
lib/        color-lib and other helpers
theme.nix   theme generator
```

## Conventions

- I avoid backlinks like `../../thing`. They break the natural file tree when reading a config, so I'd rather expose it as a module or package and use `self.packages.${system}.thing`.
- I reference inputs directly instead of pulling them in through overlays, so it's always clear what supplied a package. Using `self` for my own flake also means you can lift a snippet by swapping `self` for `inputs.<this-flake>`.
- Portability is a goal, but some modules now depend on things like `color-lib`.

## Installing

See [systems/README.md](systems/README.md) for adding a host and installing it with nixos-anywhere, through Secure Boot and TPM2 unlock.

## License

MIT. See [LICENSE](LICENSE).
