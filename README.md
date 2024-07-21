# NixOS Configuration

This repository contains my personal NixOS configuration for various systems, including a Framework laptop, desktop, and Raspberry Pi. It includes a wide range of customizations and configurations for various programs and services.

## Key Features

• Uses Hyprland as the window manager, configured with custom keybindings and animations
• Implements secure boot using Lanzaboote
• Utilizes Disko for declarative disk partitioning
• Manages secrets using sops-nix for encrypted configuration
• Configures Pipewire for audio handling
• Sets up a custom Neovim configuration using nixvim
• Implements a custom Firefox configuration with specific add-ons and themes
• Configures Steam with a scaling fix
• Uses home-manager for user-specific configurations
• Implements a custom GTK theme using a NixOS module
• Sets up OCI containers for services like WordPress
• Configures Nginx as a reverse proxy with automatic HTTPS using ACME
• Implements a custom resume builder using Yew and Rust
• Uses nix-minecraft for Minecraft server setup
• Configures multiple systems including a desktop, laptop, and Raspberry Pi
• Implements fingerprint authentication
• Sets up Yubikey support
• Uses podman for container management
• Configures Traefik as a reverse proxy with automatic HTTPS
• Implements a custom volume interpolation script for smooth volume changes
• Sets up Octoprint for 3D printer management with custom plugins
• Uses compose2nix to convert Docker Compose files to Nix configurations
• Implements a custom portfolio website using Yew and Rust
• Configures multiple programming languages and development environments

## Highlights

- **Sops** for secrets management
- **Remote-Deploy/Install** script for system deployment
- **NuShell scripting** integration
- **Commit messages in boot menu** (Work in Progress)
- **Git hooks** for automatic OS message updates

## Structure

The configuration is organized into a series of Nix files, each responsible for a specific aspect of the system. The main configuration files are located in the `systems` directory.

## Usage

1. Clone this repository:

   ```
   git clone https://github.com/knoc-off/nixos.git
   ```

2. Navigate to the repository directory:

   ```
   cd nixos
   ```

3. Set up the git hooks:

   ```
   git config core.hooksPath .githooks
   ```

4. Customize the configuration files as needed.

5. Build and switch to the new configuration:

   ```
   sudo nixos-rebuild switch --flake .#<hostname>
   ```

   Replace `<hostname>` with the appropriate hostname for your system.

## Git Hooks

This repository includes a git hook that automatically updates the OS message in the boot menu when you make a commit. The hook is located in the `.githooks` directory and can be enabled by setting the git hooks path as shown in the usage instructions above.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This configuration is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
