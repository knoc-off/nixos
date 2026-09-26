# Adding and installing a host

Standing up a new host in `systems/`, from install through Secure Boot and TPM2
auto-unlock. Tested on `optiplex` (Dell OptiPlex 7080, NVMe, UEFI).

A host is usable after phase 3. Phases 4 to 6 are optional hardening.

## 1. Define the host

Create `systems/<hostname>/default.nix` and add it to `hosts` in `flake.nix`:

```nix
hosts = {
  "<hostname>" = "x86_64-linux";
};
```

Modules are auto-discovered, so nothing else needs registering. Compose the host
from `self.nixosModules.*`, keeping each import next to its config in `imports`.

```
systems/<hostname>/
  default.nix     the host config
  secrets.yaml    sops secrets (add a path_regex to .sops.yaml)
  services/       config that exists only because of this host's role
  disk.nix        only if not using self.nixosModules.btrfs-luks
```

`modules/` holds capabilities any host could switch on. `systems/<hostname>/`
holds identity: this machine's role, domains, IPs, and cross-host references.

Good hosts to copy from:

- `optiplex/` -- encrypted btrfs, lanzaboote, measured boot, TPM2 unlock.
- `hetzner/` -- older hand-written `disk.nix` (LVM/ext4). Use `btrfs-luks` for new hosts.

### Disk layout

`self.nixosModules.btrfs-luks` handles partitioning through disko and declares
`fileSystems`, so a host without a hardware scan needs no
`hardware-configuration.nix`.

```nix
disks.btrfsLuks = {
  enable = true;
  device = "/dev/nvme0n1";
  encryption = true;
  swapSize = "8G";
  espSize = "2G";
  extraSubvolumes."/media".mountpoint = "/srv/media";
};
```

The default `espSize` is 512M, which is fine for systemd-boot. lanzaboote UKIs
are about 100 MB each, so use `2G` if the host will get Secure Boot. Growing it
later means repartitioning.

Snapshots are per subvolume, so put data that should survive a root rollback in
`extraSubvolumes`.

## 2. Install with nixos-anywhere

Boot the target from a NixOS minimal ISO and note its IP. Generate the LUKS key:

```sh
(umask 077; openssl rand -hex 32 > /tmp/luks.key)
```

Use hex, not raw bytes. disko feeds the key through `"$(cat file)"`, which strips
trailing newlines and NUL bytes, so a binary key can differ from what gets
enrolled. Hex is also easy to type at a console.

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<hostname> \
  --disk-encryption-keys /tmp/secret.key /tmp/luks.key \
  --build-on local \
  root@<ip>
```

`--disk-encryption-keys <remote> <local>`: the remote path must match
`disks.btrfsLuks.luksPasswordFile` (default `/tmp/secret.key`). Add `--vm-test`
to dry-run the partitioning.

Save the key to a password manager, then `shred -u /tmp/luks.key`.

`git add` new files first. Flakes ignore untracked files, so a new host shows up
as a confusing `does not provide attribute` error. Staging is enough.

## 3. First boot

`### Done! ###` does not mean it booted your system. Check:

```sh
ssh root@<ip> 'hostname; findmnt -n -o SOURCE,FSTYPE /'
```

A hostname of `nixos` and a squashfs root means it booted the installer again.
Fix the firmware boot order:

```sh
efibootmgr                 # find "Linux Boot Manager"
efibootmgr -b 0000 -B      # delete stale entries
efibootmgr -o 0001         # put Linux Boot Manager first
```

Remove the USB stick. The LUKS prompt is on the physical console; there is no
initrd SSH unless you set `boot.initrd.network.ssh`.

Add a typeable second passphrase. The hex key stays in slot 0 for recovery:

```sh
cryptsetup luksAddKey /dev/nvme0n1p2
```

Commit the working config before going further.

## 4. Secure Boot with lanzaboote

Deploy bootloader changes with `boot`, not `switch`, then reboot:

```sh
nixos-rebuild boot --flake .#<hostname> --target-host root@<ip>
```

### Put the firmware into Setup Mode

This has to be done in the BIOS:

BIOS -> Secure Boot -> Secure Boot Enable **On** -> Expert Key Management ->
Custom Mode -> **Delete All Keys**.

Verify:

```sh
bootctl status | head -8
```

Expect `Secure Boot: disabled (setup)`. `disabled (audit)` also works, but
enrolling from Audit Mode ends in Deployed Mode, so re-enrolling later needs
another BIOS key wipe.

### Enable lanzaboote

```nix
boot.custom = {
  enable = true;
  type = "lanzaboote";
  efiSupport = true;
  configurationLimit = 8;
};

boot.lanzaboote = {
  autoGenerateKeys.enable = true;
  autoEnrollKeys = {
    enable = true;
    autoReboot = true;
  };
};
```

The keys are written to firmware on the next boot, which is why `autoReboot` is
needed. Leave `autoEnrollKeys.includeMicrosoftKeys` at its default `true`; some
GPU and NIC option ROMs are Microsoft-signed and won't load without it.

`thinkpad-work` still says to enroll keys manually with `sbctl`. That predates
`autoGenerateKeys` and `autoEnrollKeys`; use the config above instead.

Success:

```
Secure Boot: enabled (user)       # or (deployed) from Audit Mode
Measured UKI: yes
```

## 5. Measured boot

Check TPM support first. Stop if this prints anything but `yes`:

```sh
/run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
```

```nix
boot.lanzaboote.measuredBoot = {
  enable = true;
  pcrs = [ 0 4 7 ];
};
```

PCR 0 is firmware, 4 is the boot loader and UKI, 7 is the Secure Boot policy.
PCRs 1 to 3 are known to be flaky. Because PCR 0 is included, a BIOS update drops
you to the passphrase prompt until you re-enroll.

`configurationLimit` must be 1 to 8 with measured boot (systemd/systemd#41526).
lanzaboote asserts this.

`nixos-rebuild boot`, reboot, then check the policy exists:

```sh
stat -c '%y  %n' /var/lib/systemd/pcrlock.json
ls /var/lib/pcrlock.d/
```

## 6. TPM2 auto-unlock

Enroll once, by hand. The sealed key lives in the LUKS header, not the Nix store:

```sh
systemd-cryptenroll --tpm2-device=auto \
  --tpm2-pcrlock=/var/lib/systemd/pcrlock.json /dev/nvme0n1p2
```

Add `--tpm2-with-pin=true` if you don't want physical access alone to unlock the
disk. Check for a `systemd-tpm2` token:

```sh
cryptsetup luksDump /dev/nvme0n1p2 | grep -A4 '^Tokens'
```

Then enable it in the initrd:

```nix
disks.btrfsLuks.tpm2Unlock = true;
```

This adds `tpm2-device=auto` to crypttab and loads `tpm_crb`/`tpm_tis` in the
initrd. It needs systemd stage 1, which `boot.custom.initrdSystemd` enables by
default.

`nixos-rebuild boot`, reboot, and confirm the TPM did the unlock:

```sh
journalctl -b 0 -u systemd-cryptsetup@crypted.service | grep -iE 'tpm2|unlocked'
```

Don't use `measuredBoot.autoCryptenroll` for this. It needs an existing TPM2 slot
and is for migrating from static PCRs.

From here lanzaboote updates the pcrlock policy on every `nixos-rebuild`, so
kernel and bootloader updates won't lock you out.

## Recovery

Passphrase slots are never touched, so every failure falls back to a passphrase
prompt.

| Symptom                                  | Cause                         | Fix                                                                  |
| ---------------------------------------- | ----------------------------- | -------------------------------------------------------------------- |
| Passphrase prompt after a BIOS update    | PCR 0 changed                 | Re-run the phase 6 `systemd-cryptenroll`                             |
| Passphrase prompt after clearing the TPM | Sealed key gone               | `systemd-cryptenroll --wipe-slot=tpm2 <dev>`, then re-enroll         |
| Boot fails after enabling Secure Boot    | Unsigned binary or option ROM | BIOS -> Delete All Keys, re-enroll with `includeMicrosoftKeys = true` |
| `nixos-rebuild` fails on PCR policy      | Changed `measuredBoot.pcrs`   | See lanzaboote's `docs/explanation/troubleshooting.md`               |
| ESP full                                 | UKIs are ~100 MB each         | Lower `configurationLimit` or grow the ESP                           |

Keep the slot 0 recovery key somewhere that doesn't depend on this machine.
