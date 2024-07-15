## Nixvim Configuration
This repository contains my Nixvim configurations.

### Features/Plugins

- **Modular Structure:**  The configuration is organized into modules.
- **Plugin Management:**  Leverages Nix's package management capabilities install and manage plugins.
- **Comprehensive Settings:**  keymappings, autocommands, and highlights.
- **LSP Support:**  Language Server Protocol (LSP) support for intelligent code completion, diagnostics, and more.
- **LuaSnip Integration:**  Incorporates LuaSnip for powerful and flexible snippet management.
- **TabNine Integration:**  TabNine for AI-powered code completion.

### Installation
You can include this repo as an input flake, and then use its output neovim package

### Customization

The configuration is designed for easy customization. You can modify the settings in the `configurations` directory to suit your preferences.

For example, to change the `mapleader` key:

1. Open `configurations/settings/keymappings.nix`.
2. Modify the `mapleader` value to your desired key.

### Contributing

Contributions are welcome! If you have any suggestions, bug reports, or feature requests, please open an issue or submit a pull request.
