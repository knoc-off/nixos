# Adding and installing a system

A bit of a sloppy AI runbook. but good as a todo list.
for standing up a new host in `systems/` and taking it all the way to
Secure Boot with TPM2 auto-unlock. Every step here was verified on `optiplex`
(Dell OptiPlex 7080, NVMe, UEFI); the gotchas called out are ones that actually
bit, not theoretical ones.

Read this top to bottom the first time. Phases 3 to 6 are optional hardening --
a host is perfectly usable after phase 2.

## 1. Define the host

Create `systems/<hostname>.nix` and register it in `flake.nix`:

```nix
(mkHost "<hostname>" "x86_64-linux")
```

Modules are auto-discovered, so nothing else needs registering. Compose the host
from `self.nixosModules.*` using the inline-config pattern (import and its
config block co-located in `imports`).

Existing hosts worth copying from:

- `optiplex.nix` -- encrypted btrfs, lanzaboote, measured boot, TPM2 unlock.
  The most complete example.
- `home-server-pc.nix` -- same disk module, unencrypted, headless.
- `hetzner.nix`, `nuci5.nix` -- the older `hardware/disks/simple-disk.nix`
  layout (LVM/ext4). Prefer `btrfs-luks` for anything new.

### Disk layout

`self.nixosModules.btrfs-luks` owns partitioning through disko. A machine with
no hardware scan needs no `hardware-configuration.nix`: the module declares
`fileSystems`, the flake sets `hostPlatform`, and
`boot.initrd.includeDefaultModules` already covers nvme/ahci/xhci/usbhid.

```nix
disks.btrfsLuks = {
  enable = true;
  device = "/dev/nvme0n1";
  encryption = true;
  swapSize = "8G";
  extraSubvolumes."/media".mountpoint = "/srv/media";
};
```

Size the ESP deliberately. The 512M default is fine for systemd-boot, but
lanzaboote UKIs bundle kernel and initrd at roughly 100 MB each, so a host that
will get Secure Boot wants `espSize = "2G"`. Growing it later means
repartitioning.

Put data that should survive a root rollback on its own subvolume via
`extraSubvolumes`, since snapshots are taken per subvolume.

## 2. Install with nixos-anywhere

Boot the target from a NixOS minimal ISO and note its IP.

### Use this flake's nixos-anywhere, not the upstream one

```sh
nix run .#nixos-anywhere -- \
  --flake .#<hostname> \
  --disk-encryption-keys /tmp/secret.key /tmp/luks.key \
  --build-on local \
  root@<ip>
```

`nix run github:nix-community/nixos-anywhere` does not work here. It prepends
its own bundled upstream Nix to `PATH`, and that binary is what evaluates the
flake. `lib/color-lib.nix` calls `builtins.wasm`, which only exists in
Determinate Nix, so evaluation dies with `attribute 'wasm' missing` before
partitioning starts. `--build-on local` does not help -- it moves the build, not
the eval. `pkgs/nixos-anywhere.nix` overrides the bundled Nix with Determinate's
`nix-cli` to fix this.

Two related traps:

- **`git add` new files first.** Flakes on a git tree ignore untracked files, so
  a new `pkgs/*.nix` or `systems/*.nix` is invisible and you get a confusing
  `does not provide attribute` error. Staging is enough; no commit needed.
- **Do not `mkForce` `nix.settings.experimental-features` in a host.**
  `modules/nix.nix` adds `wasm-builtin` to that list; replacing the list drops
  it and breaks evaluation of this flake on that host.

### Generating the LUKS passphrase

```sh
(umask 077; openssl rand -hex 32 > /tmp/luks.key)
```

Use hex, not raw bytes. disko runs `cryptsetup luksFormat --key-file <(echo -n
"$(cat file)")`, and command substitution strips trailing newlines and silently
drops NUL bytes, so `openssl rand 32` can enroll a different key than the one in
your file. Hex also survives being typed at a console under any keymap.

In `--disk-encryption-keys <remote> <local>`, the first path is where the file
lands on the target (must match `disks.btrfsLuks.luksPasswordFile`, default
`/tmp/secret.key`) and the second is the local file you just created. Save the
key to a password manager before rebooting, then `shred -u /tmp/luks.key`.

Add `--vm-test` for a dry run of the partitioning without touching the target.

## 3. First boot

Installation ending in `### Done! ###` does not mean the machine booted into
your system. Check what it actually booted:

```sh
ssh root@<ip> 'hostname; findmnt -n -o SOURCE,FSTYPE /'
```

A hostname of `nixos` or `minimal-nix` and a squashfs root means it came back up
on the installer. Firmware boot order is the usual cause -- installer USB and
leftover OEM entries can both outrank the new install:

```sh
efibootmgr                 # find the "Linux Boot Manager" entry number
efibootmgr -b 0000 -B      # delete stale entries (e.g. a wiped Windows install)
efibootmgr -o 0001         # put Linux Boot Manager first
```

Remove the USB stick before rebooting. An encrypted host prompts for the
passphrase on the physical console; there is no initrd SSH unless you configure
`boot.initrd.network.ssh`.

Once up, add a memorable second passphrase. The machine-generated hex key stays
in slot 0 as permanent recovery, and you get something typeable for the reboots
in the phases below:

```sh
cryptsetup luksAddKey /dev/nvme0n1p2
```

Now commit the working configuration before hardening further.

## 4. Secure Boot with lanzaboote

Deploy from your workstation with:

```sh
nixos-rebuild boot --flake .#<hostname> --target-host root@<ip>
```

Use `boot` rather than `switch` for bootloader changes, then reboot.

### Put the firmware into Setup Mode

This must happen in the BIOS. If `DeployedMode=1`, the UEFI spec forbids
transitioning out of it from the OS.

BIOS -> Secure Boot -> Secure Boot Enable **On** -> Expert Key Management ->
Custom Mode -> **Delete All Keys**.

Verify:

```sh
bootctl status | head -8
for v in SetupMode SecureBoot AuditMode DeployedMode; do
  f=$(ls /sys/firmware/efi/efivars/${v}-8be4df61* 2>/dev/null)
  [ -n "$f" ] && printf '%-13s %s\n' "$v" "$(od -An -tu1 -j4 -N1 "$f" | tr -d ' ')"
done
```

`Secure Boot: disabled (setup)` is what you expect. `disabled (audit)`
(`SetupMode=1, AuditMode=1`) is equally fine -- systemd-boot accepts both for
enrollment (`src/boot/boot.c`, `secure_boot_discover_keys`). Note that enrolling
a PK from Audit Mode lands in Deployed Mode rather than User Mode, so redoing
enrollment later means another BIOS key wipe.

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

`sbctl` only stages `PK/KEK/db.auth` onto the ESP; systemd-boot writes them to
firmware on the following boot. The reboot is part of the mechanism, so
`autoReboot` is doing real work rather than saving you a command.

Leave `includeMicrosoftKeys` at its `true` default. Some option ROMs (GPU, NIC)
are Microsoft-signed and will not load without those keys. The alternative is
gated behind an option named `allowBrickingMyMachine`, which is honest
signposting.

Older hosts in this repo carry a comment saying to enroll keys with `sbctl`
manually before switching to lanzaboote. That predates `autoGenerateKeys` and
`autoEnrollKeys`; use the declarative path above.

Success looks like:

```
Secure Boot: enabled (user)       # or (deployed) if you came from Audit Mode
Measured UKI: yes
```

## 5. Measured boot

Preflight -- if this prints anything but `yes`, stop here, the TPM is not
supported by systemd-pcrlock:

```sh
/run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
```

```nix
boot.lanzaboote.measuredBoot = {
  enable = true;
  pcrs = [ 0 4 7 ];
};
```

PCR 0 is firmware code, 4 the boot loader and UKI, 7 the Secure Boot policy.
PCRs 1, 2 and 3 cover firmware configuration and option ROMs and are documented
as flaky, so they stay out. Including PCR 0 means a BIOS update invalidates the
policy and drops to the passphrase prompt until you re-enroll -- a fallback, not
a lockout.

`configurationLimit` must be 1 to 8 when `measuredBoot` is on; systemd-pcrlock
will not build a policy for more than 8 variants (systemd/systemd#41526). There
is an assertion for this.

`nixos-rebuild boot`, reboot, then confirm the policy was generated for the
current boot:

```sh
stat -c '%y  %n' /var/lib/systemd/pcrlock.json
ls /var/lib/pcrlock.d/
```

## 6. TPM2 auto-unlock

Enroll once, by hand. The sealed key lives in the LUKS2 header, not the Nix
store, so this step is deliberately not declarative:

```sh
systemd-cryptenroll --tpm2-device=auto \
  --tpm2-pcrlock=/var/lib/systemd/pcrlock.json /dev/nvme0n1p2
```

It prompts for an existing passphrase. Add `--tpm2-with-pin=true` for an
attended machine -- without a PIN, physical possession of the box is enough to
reach the desktop, which matters more if the host also has autologin or
passwordless sudo. Confirm with:

```sh
cryptsetup luksDump /dev/nvme0n1p2 | grep -A4 '^Tokens'
```

You want a `systemd-tpm2` token. Then let the initrd actually try it:

```nix
disks.btrfsLuks.tpm2Unlock = true;
```

That sets `crypttabExtraOpts = [ "tpm2-device=auto" ]` and pulls `tpm_crb` and
`tpm_tis` into the initrd. Neither module is in the nixpkgs default initrd set,
and without them systemd-cryptsetup silently falls through to the passphrase
prompt. `tpm2Unlock` requires systemd stage 1, which `boot.custom.initrdSystemd`
enables by default; `crypttabExtraOpts` is ignored by the scripted initrd.

`nixos-rebuild boot`, reboot. Verify the unlock came from the TPM rather than a
fast passphrase path:

```sh
journalctl -b 0 -u systemd-cryptsetup@crypted.service | grep -iE 'tpm2|unlocked'
```

Do not use `measuredBoot.autoCryptenroll` for this. It runs
`--unlock-tpm2-device=auto` and therefore needs a TPM2 slot to already exist; it
is the migration path for volumes bound to static PCRs, not initial enrollment.

After this the system is self-maintaining: lanzaboote regenerates the pcrlock
policy and updates the TPM NV index in place on every `nixos-rebuild`, so kernel
and bootloader updates will not lock you out.

## Recovery

Passphrase keyslots are never touched by any of the above, so every failure mode
degrades to a passphrase prompt rather than a lockout.

| Symptom                                          | Cause                                      | Fix                                                                                           |
| ------------------------------------------------ | ------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Passphrase prompt returns after a BIOS update    | PCR 0 changed                              | Re-run the phase 6 `systemd-cryptenroll`                                                      |
| Passphrase prompt returns after clearing the TPM | Sealed key gone                            | `systemd-cryptenroll --wipe-slot=tpm2 <dev>`, then re-enroll                                  |
| Boot fails after enabling Secure Boot            | Unsigned binary or missing option ROM keys | BIOS -> Delete All Keys to return to Setup Mode, re-enroll with `includeMicrosoftKeys = true` |
| `nixos-rebuild` fails on PCR policy violation    | Changed `measuredBoot.pcrs`                | See lanzaboote's `docs/explanation/troubleshooting.md`                                        |
| ESP full                                         | UKIs at ~100 MB each                       | Lower `configurationLimit`, or grow the ESP                                                   |

Keep the slot 0 recovery key somewhere that does not depend on this machine
booting.
