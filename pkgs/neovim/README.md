# Neovim Configuration

This repository contains a Neovim configuration using the Nix package manager and the nixvim framework.

## Features

- Language Server Protocol (LSP) support
- Autocompletion
- Syntax highlighting with Treesitter
- Telescope for fuzzy finding
- Custom keymappings
- OneDark color scheme
- Various productivity plugins

## Structure

- `configurations/`: Main configuration directory
  - `default.nix`: Entry point for the configuration
  - `plugins/`: Plugin-specific configurations
  - `settings/`: General Neovim settings
  - `themes/`: Color scheme configuration

## Key Plugins

- LSP
- Telescope
- Treesitter
- Which-key
- Bufferline
- Completion (cmp)

## Usage

can be run with the command:

`# nix run github:knoc-off/nixos/#neovim-nix.default`
