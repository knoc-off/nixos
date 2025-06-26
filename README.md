# NixOS Configuration

This repository contains my personal NixOS configuration for various systems, including a Framework laptop, desktop, and Raspberry Pi. It includes a wide range of customizations and configurations for various programs and services.

## Some things

- Uses Hyprland as the window manager, configured with custom keybindings and animations
- Implements secure boot using Lanzaboote
- Utilizes Disko for declarative disk partitioning
- Manages secrets using sops-nix for encrypted configuration
- Sets up a custom Neovim configuration using nixvim
- Configures Steam with a UI scaling fix
- Uses home-manager for user-specific configurations
- Uses a custom wrapper around nix-minecraft for Minecraft server setup w/ Port forwarding with gate

## things im proud of

- reimplemented a *lot* of math functions, and some equations, that get used for my pure-nix theme generator.
- the theme generator itself uses a nix implementation of OkLAB/ OkHSL color space. for perceptually uniform colors.
- Git hook to auto update the Boot-entry with the commit message, and hash.

## Structure
the structure is constantly changing, but something I valued was avoiding backlinks (IE: ../../important_thing).

I find them very distracting when reading other peoples configs, as you have the natural tree structure of files/directories, and then you mess that up with backlinks causing confusion on what is related.

Most of the time when I want to use a backlink I find that I would rather create a module/package to reference in nix, using self.packages.${system}.xyz


_________
I also find overlays distracting when reading a Config, as most of the time you use an input for a single package/feature, and I much prefer to reference it directly, as when reading my config later i know exactly what supplied the package and how.

So whenever I want to reference my own work, I use "self" to refer to my own flake. This may look a little strange but I find it to be much clearer in intention. And other people can easily take snippets from my config just by replacing the "self" with something like: "inputs.knoff-flake."


_________
Portability is valued, but I have made it less portable as of late, with the addition of dependencies on things like my color-lib. I might try to make this more flexible soon.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This configuration is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
