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

- the theme generator uses a nix implementation of OkLAB/ OkHSL color space. for perceptually uniform colors.

## Structure

the structure is constantly changing, but something I valued was avoiding backlinks (IE: ../../important_thing).

I find them very distracting when reading other peoples configs, as you have the natural tree structure of files/directories, and then you mess that up with backlinks causing confusion on what is related.

Most of the time when I want to use a backlink I find that I would rather create a module/package to reference in nix, using self.packages.${system}.xyz

---

I also find overlays distracting when reading a Config, as most of the time you use an input for a single package/feature, and I much prefer to reference it directly, as when reading my config later i know exactly what supplied the package and how.

So whenever I want to reference my own work, I use "self" to refer to my own flake. This may look a little strange but I find it to be much clearer in intention. And other people can easily take snippets from my config just by replacing the "self" with something like: "inputs.knoff-flake."

---

Portability is valued, but I have made it less portable as of late, with the addition of dependencies on things like my color-lib. I might try to make this more flexible soon.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This configuration is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

# installing:

Boot from NixOS minimal ISO, note ip address.

Create a file with your LUKS passphrase
IE:
`echo -n "your-luks-passphrase" > /tmp/luks.key`

> just an example, you should not have your encryption key in your history.

```sh
nix run github:nix-community/nixos-anywhere -- \
 --flake .#framework13 \
 --disk-encryption-keys /tmp/secret.key /tmp/luks.key \
 root@<ip-address>
```

nixos-anywhere will:

1. SSH into the target
2. Copy the LUKS passphrase file
3. Run disko to partition, encrypt (LUKS), and format (btrfs) /dev/nvme0n1
4. Install the NixOS configuration
5. Reboot
   After reboot, the system will prompt for the LUKS passphrase interactively on every boot.
   Post-install TODO

After the first successful boot:

1. Enroll secure boot keys: `sudo sbctl create-keys` & `sudo sbctl enroll-keys`
2. change boot type from systemd-boot to lanzaboote.
3. Set up sops age key from SSH host key, create secrets file, uncomment the sops block
4. Rebuild
