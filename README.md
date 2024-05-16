## NixOS Configuration for Framework Laptop

This repository contains a NixOS configuration for a Framework laptop. It includes a variety of customizations and configurations for various programs and services, including:

* **Window Manager:** Hyprland
* **Terminal:** Kitty
* **Shell:** Fish, Nushell
* **Editor:** Neovim
* **Browser:** Firefox
* **Audio:** Pipewire
* **Power Management:** Light
* **Secure Boot:** Lanzaboote
* **Disk Partitioning:** Disko
* **Docker:** Podman
* **Bluetooth:** Blueman
* **Custom Applications:** Steam, Lutris, Bottles, etc.

### Custom Applications
* **Steam Scaling Fix:** Passes a argument to force the scaling to be 1.0
* **Abba23 spotify-adblock:** Ive packaged [abba23's](https://github.com/abba23/spotify-adblock) adblocker
* **Spotify Adblock:** the official spotify package gets packaged and then i shim the launch arguments to LD_PRELOAD the adblocker

### Structure

The configuration is organized into a series of Nix files, each responsible for a specific aspect of the system.
The main configuration file is `configuration.nix`, which imports and combines all the other files.

I've tried to keep the number of 'back-links' (../xyz) to a minimal, because I feel that obscures the meaning of certain modules.
so it should be more straightforward for an outsider to figure out how this works.

### Installation

I dont recommend installing my exact configuration. just take what looks interesting, and adapt it to your own

1. **Install NixOS:** Follow the instructions on the NixOS website to install NixOS.
2. **Clone this repository:**
   ```bash
   git clone https://github.com/knoc-off/nixos-config.git
   ```
3. **Configure NixOS:**
   * **Copy the configuration files:** Copy the contents of this repository to `/etc/nixos` on your NixOS system.
   * **Edit `configuration.nix`:** Customize the configuration to your liking.
4. **Rebuild the system:**
   ```bash
   sudo nixos-rebuild switch
   ```

### Usage

This configuration includes a number of helpful scripts and functions:

* **`nx`:** A Nushell script for running Nix commands easily.
* **`nixcommit`:** A Nushell script for creating a commit message and updating the system label.
* **`nixx`:** A Nushell script for running Nix packages in the background with Pueue.
* **`qr`:** A Bash function for generating QR codes.
* **`findLocalDevices`:** A Fish function for finding local devices on the network.
* **`brightness`:** A Nushell script for adjusting screen brightness.
* **`volume`:** A Nushell script for adjusting system volume.
* **`mute`:** A Nushell script for muting/unmuting the system audio.

### Customization

* **Customize the theme:** Use a different color scheme or create your own.
* **Configure services:** Enable or disable services based on your needs.

### Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

### License

This configuration is licensed under the MIT License.
