# NixOS Configuration

This repository contains my personal NixOS configuration for various systems, including a Framework laptop, desktop, and Raspberry Pi. It includes a wide range of customizations and configurations for various programs and services.

## Key Features

- **Window Manager:** Hyprland
- **Terminal:** Kitty with Fish shell
- **Editor:** Neovim (custom configuration)
- **Browser:** Firefox with custom theming and add-ons
- **Audio:** PipeWire
- **Secure Boot:** Lanzaboote
- **Disk Partitioning:** Disko
- **Containerization:** Podman
- **Custom Applications:** Steam (with scaling fix), Spotify (with ad-blocking)

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
