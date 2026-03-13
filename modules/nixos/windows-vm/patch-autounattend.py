#!/usr/bin/env python3
"""Patch a Windows autounattend.xml for VM use.

Builds a complete VM-ready answer file from scratch, then optionally
merges in extra commands and elements from an overlay XML (e.g.
UnattendedWinstall for debloating).

Phase 1 -- ensure VM base (always runs):
  Creates all required elements if missing, updates if present.
  windowsPE:   locale, product key, disk layout, image install,
               hardware bypasses, VirtIO driver paths
  specialize:  BypassNRO
  oobeSystem:  locale, OOBE hide, local user, auto-logon,
               FirstLogonCommands (network re-enable + post-install)

Phase 2 -- merge overlay (if --merge given):
  Imports from the overlay XML into our base:
  - Extra RunSynchronous commands (dedup by Path text)
  - Extra FirstLogonCommands (dedup by CommandLine text)
  - Components we don't manage (imported entirely)
  - Non-unattend-namespace elements (e.g. Extensions with scripts)
  Skips: non-amd64 components, network-disable commands (conflict
  with our post-install network requirements).

Uses xml.etree.ElementTree for namespace-aware manipulation.
"""

import argparse
import xml.etree.ElementTree as ET

NS = "urn:schemas-microsoft-com:unattend"
WCM = "http://schemas.microsoft.com/WMIConfig/2002/State"

ET.register_namespace("", NS)
ET.register_namespace("wcm", WCM)

COMPONENT_ATTRS = {
    "processorArchitecture": "amd64",
    "publicKeyToken": "31bf3856ad364e35",
    "language": "neutral",
    "versionScope": "nonSxS",
}

# Components we fully manage -- overlay cannot override these
MANAGED_COMPONENTS = {
    "Microsoft-Windows-International-Core-WinPE",
    "Microsoft-Windows-Setup",
    "Microsoft-Windows-PnpCustomizationsWinPE",
    "Microsoft-Windows-Deployment",
    "Microsoft-Windows-International-Core",
    "Microsoft-Windows-Shell-Setup",
}

# Commands containing these strings are skipped during merge
# (they conflict with our post-install network requirements)
BLOCKED_CMD_PATTERNS = [
    "Disable-NetAdapter",
]


# -- helpers --------------------------------------------------------

def _tag(name):
    """Return a namespace-qualified tag."""
    return f"{{{NS}}}{name}"


def _ensure_settings(root, pass_name):
    """Find or create a <settings pass="..."> element."""
    for s in root.findall(_tag("settings")):
        if s.get("pass") == pass_name:
            return s
    s = ET.SubElement(root, _tag("settings"))
    s.set("pass", pass_name)
    return s


def _ensure_component(settings, comp_name):
    """Find or create a <component name="..."> inside a settings pass."""
    for c in settings.findall(_tag("component")):
        if c.get("name") == comp_name:
            return c
    c = ET.SubElement(settings, _tag("component"))
    c.set("name", comp_name)
    for k, v in COMPONENT_ATTRS.items():
        c.set(k, v)
    return c


def _ensure_child(parent, tag_name):
    """Find or create a direct child element by unqualified tag name."""
    t = _tag(tag_name)
    el = parent.find(t)
    if el is None:
        el = ET.SubElement(parent, t)
    return el


def _set_text(parent, tag_name, text):
    """Ensure a child element exists and set its text content."""
    el = _ensure_child(parent, tag_name)
    el.text = text
    return el


def _next_order(container, child_tag):
    """Return the next order number for a list of ordered commands."""
    max_order = 0
    for cmd in container.findall(_tag(child_tag)):
        order_el = cmd.find(_tag("Order"))
        if order_el is not None and order_el.text:
            max_order = max(max_order, int(order_el.text))
    return max_order + 1


def _has_run_cmd(container, child_tag, description):
    """Check if a command with a given Description already exists."""
    for cmd in container.findall(_tag(child_tag)):
        desc = cmd.find(_tag("Description"))
        if desc is not None and desc.text == description:
            return True
    return False


def _get_cmd_text(cmd, field):
    """Get the text of Path or CommandLine from a command element."""
    for tag in [field, f"{{{NS}}}{field}"]:
        el = cmd.find(tag)
        if el is not None and el.text:
            return el.text
    return ""


def _cmd_is_blocked(cmd):
    """Return True if a command matches a blocked pattern."""
    for field in ["Path", "CommandLine"]:
        text = _get_cmd_text(cmd, field)
        for pattern in BLOCKED_CMD_PATTERNS:
            if pattern in text:
                return True
    return False


def _collect_existing_paths(container, child_tag, field):
    """Collect all Path/CommandLine text values from existing commands."""
    paths = set()
    for cmd in container.findall(_tag(child_tag)):
        text = _get_cmd_text(cmd, field)
        if text:
            paths.add(text)
    return paths


# -- windowsPE pass -------------------------------------------------

def ensure_winpe_locale(root, locale):
    """Ensure International-Core-WinPE with locale settings."""
    settings = _ensure_settings(root, "windowsPE")
    comp = _ensure_component(
        settings, "Microsoft-Windows-International-Core-WinPE")
    sui = _ensure_child(comp, "SetupUILanguage")
    _set_text(sui, "UILanguage", locale)
    for field in ["InputLocale", "SystemLocale", "UILanguage",
                  "UserLocale"]:
        _set_text(comp, field, locale)


def ensure_winpe_setup(root):
    """Ensure Microsoft-Windows-Setup has UserData with product key."""
    settings = _ensure_settings(root, "windowsPE")
    comp = _ensure_component(settings, "Microsoft-Windows-Setup")

    ud = _ensure_child(comp, "UserData")
    pk = _ensure_child(ud, "ProductKey")
    # Generic Win11 Pro KMS key -- selects edition without activation
    _set_text(pk, "Key", "W269N-WFGWX-YVC9B-4J6C9-T83GX")
    _set_text(pk, "WillShowUI", "OnError")
    _set_text(ud, "AcceptEula", "true")


def ensure_disk_config(root):
    """Ensure DiskConfiguration with EFI + MSR + Windows partitions."""
    settings = _ensure_settings(root, "windowsPE")
    comp = _ensure_component(settings, "Microsoft-Windows-Setup")

    # Always replace -- we are the authority on disk layout
    dc = comp.find(_tag("DiskConfiguration"))
    if dc is not None:
        comp.remove(dc)

    dc = ET.SubElement(comp, _tag("DiskConfiguration"))
    disk = ET.SubElement(dc, _tag("Disk"))
    disk.set(f"{{{WCM}}}action", "add")
    _set_text(disk, "DiskID", "0")
    _set_text(disk, "WillWipeDisk", "true")

    cp = ET.SubElement(disk, _tag("CreatePartitions"))
    for order, ptype, size, extend in [
        (1, "EFI", "100", False),
        (2, "MSR", "16", False),
        (3, "Primary", None, True),
    ]:
        p = ET.SubElement(cp, _tag("CreatePartition"))
        p.set(f"{{{WCM}}}action", "add")
        _set_text(p, "Order", str(order))
        _set_text(p, "Type", ptype)
        if size:
            _set_text(p, "Size", size)
        if extend:
            _set_text(p, "Extend", "true")

    mp = ET.SubElement(disk, _tag("ModifyPartitions"))
    for order, pid, fmt, label, letter in [
        (1, "1", "FAT32", "System", None),
        (2, "2", None, None, None),
        (3, "3", "NTFS", "Windows", "C"),
    ]:
        m = ET.SubElement(mp, _tag("ModifyPartition"))
        m.set(f"{{{WCM}}}action", "add")
        _set_text(m, "Order", str(order))
        _set_text(m, "PartitionID", pid)
        if fmt:
            _set_text(m, "Format", fmt)
        if label:
            _set_text(m, "Label", label)
        if letter:
            _set_text(m, "Letter", letter)


def ensure_image_install(root):
    """Ensure ImageInstall points to partition 3 on disk 0."""
    settings = _ensure_settings(root, "windowsPE")
    comp = _ensure_component(settings, "Microsoft-Windows-Setup")

    # Always replace
    ii = comp.find(_tag("ImageInstall"))
    if ii is not None:
        comp.remove(ii)

    ii = ET.SubElement(comp, _tag("ImageInstall"))
    osi = ET.SubElement(ii, _tag("OSImage"))
    it = ET.SubElement(osi, _tag("InstallTo"))
    _set_text(it, "DiskID", "0")
    _set_text(it, "PartitionID", "3")


def ensure_hw_bypasses(root):
    """Ensure hardware requirement bypasses for VM use."""
    settings = _ensure_settings(root, "windowsPE")
    comp = _ensure_component(settings, "Microsoft-Windows-Setup")
    rs = _ensure_child(comp, "RunSynchronous")

    bypasses = [
        "BypassTPMCheck",
        "BypassSecureBootCheck",
        "BypassRAMCheck",
        "BypassCPUCheck",
        "BypassStorageCheck",
        "BypassDiskCheck",
    ]

    for name in bypasses:
        desc = f"Bypass {name}"
        if _has_run_cmd(rs, "RunSynchronousCommand", desc):
            continue
        path = (
            f'reg.exe add "HKLM\\SYSTEM\\Setup\\LabConfig" '
            f"/v {name} /t REG_DWORD /d 1 /f"
        )
        cmd = ET.SubElement(rs, _tag("RunSynchronousCommand"))
        cmd.set(f"{{{WCM}}}action", "add")
        _set_text(cmd, "Order",
                  str(_next_order(rs, "RunSynchronousCommand")))
        _set_text(cmd, "Description", desc)
        _set_text(cmd, "Path", path)


def ensure_driver_paths(root, driver_dirs, drive_letters):
    """Ensure PnpCustomizationsWinPE with VirtIO driver paths."""
    settings = _ensure_settings(root, "windowsPE")

    # Remove any existing to rebuild cleanly
    for c in list(settings.findall(_tag("component"))):
        if c.get("name") == "Microsoft-Windows-PnpCustomizationsWinPE":
            settings.remove(c)

    comp = _ensure_component(
        settings, "Microsoft-Windows-PnpCustomizationsWinPE")
    paths_el = ET.SubElement(comp, _tag("DriverPaths"))
    key = 1
    for letter in drive_letters:
        for d in driver_dirs:
            entry = ET.SubElement(paths_el, _tag("PathAndCredentials"))
            entry.set(f"{{{WCM}}}action", "add")
            entry.set(f"{{{WCM}}}keyValue", str(key))
            _set_text(entry, "Path", f"{letter}:\\{d}")
            key += 1


# -- specialize pass ------------------------------------------------

def ensure_bypass_nro(root):
    """Ensure BypassNRO registry key in the specialize pass."""
    settings = _ensure_settings(root, "specialize")
    comp = _ensure_component(settings, "Microsoft-Windows-Deployment")
    rs = _ensure_child(comp, "RunSynchronous")

    desc = "Allow local account creation (bypass MS account)"
    if _has_run_cmd(rs, "RunSynchronousCommand", desc):
        return

    path = (
        'reg.exe add "HKLM\\SOFTWARE\\Microsoft\\Windows\\'
        'CurrentVersion\\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f'
    )
    cmd = ET.SubElement(rs, _tag("RunSynchronousCommand"))
    cmd.set(f"{{{WCM}}}action", "add")
    _set_text(cmd, "Order",
              str(_next_order(rs, "RunSynchronousCommand")))
    _set_text(cmd, "Description", desc)
    _set_text(cmd, "Path", path)


# -- oobeSystem pass ------------------------------------------------

def ensure_oobe_locale(root, locale):
    """Ensure International-Core with locale in oobeSystem."""
    settings = _ensure_settings(root, "oobeSystem")
    comp = _ensure_component(
        settings, "Microsoft-Windows-International-Core")
    for field in ["InputLocale", "SystemLocale", "UILanguage",
                  "UserLocale"]:
        _set_text(comp, field, locale)


def ensure_oobe_settings(root):
    """Ensure OOBE section hides all prompts."""
    settings = _ensure_settings(root, "oobeSystem")
    comp = _ensure_component(settings, "Microsoft-Windows-Shell-Setup")
    oobe = _ensure_child(comp, "OOBE")
    _set_text(oobe, "HideEULAPage", "true")
    _set_text(oobe, "HideOEMRegistrationScreen", "true")
    _set_text(oobe, "HideOnlineAccountScreens", "true")
    _set_text(oobe, "HideWirelessSetupInOOBE", "true")
    if oobe.find(_tag("ProtectYourPC")) is None:
        _set_text(oobe, "ProtectYourPC", "3")


def ensure_user_account(root, username):
    """Ensure a local administrator account with no password."""
    settings = _ensure_settings(root, "oobeSystem")
    comp = _ensure_component(settings, "Microsoft-Windows-Shell-Setup")

    ua = _ensure_child(comp, "UserAccounts")
    la_list = _ensure_child(ua, "LocalAccounts")

    existing = None
    for la in la_list.findall(_tag("LocalAccount")):
        existing = la
        break

    if existing is None:
        existing = ET.SubElement(la_list, _tag("LocalAccount"))
        existing.set(f"{{{WCM}}}action", "add")

    _set_text(existing, "Name", username)
    _set_text(existing, "Group", "Administrators")
    pw = _ensure_child(existing, "Password")
    val = _ensure_child(pw, "Value")
    if not val.text:
        val.text = ""
    _set_text(pw, "PlainText", "true")


def ensure_autologon(root, username):
    """Ensure AutoLogon so FirstLogonCommands fire automatically."""
    settings = _ensure_settings(root, "oobeSystem")
    comp = _ensure_component(settings, "Microsoft-Windows-Shell-Setup")
    al = _ensure_child(comp, "AutoLogon")
    _set_text(al, "Enabled", "true")
    _set_text(al, "Username", username)
    _set_text(al, "LogonCount", "1")
    pw = _ensure_child(al, "Password")
    val = _ensure_child(pw, "Value")
    if not val.text:
        val.text = ""
    _set_text(pw, "PlainText", "true")


def ensure_first_logon_commands(root, script_name):
    """Ensure FirstLogonCommands with network re-enable + post-install."""
    settings = _ensure_settings(root, "oobeSystem")
    comp = _ensure_component(settings, "Microsoft-Windows-Shell-Setup")
    flc = _ensure_child(comp, "FirstLogonCommands")

    net_desc = "Re-enable network adapters"
    if not _has_run_cmd(flc, "SynchronousCommand", net_desc):
        cmd = ET.SubElement(flc, _tag("SynchronousCommand"))
        cmd.set(f"{{{WCM}}}action", "add")
        _set_text(cmd, "Order",
                  str(_next_order(flc, "SynchronousCommand")))
        _set_text(cmd, "Description", net_desc)
        _set_text(
            cmd, "CommandLine",
            'powershell.exe -NoProfile -WindowStyle Hidden '
            '-Command "Get-NetAdapter | Enable-NetAdapter '
            '-Confirm:$false"')

    ps_desc = "VM post-install: VirtIO guest tools, WinFSP, virtiofs"
    if not _has_run_cmd(flc, "SynchronousCommand", ps_desc):
        scan = (
            "powershell.exe -NoProfile -WindowStyle Hidden "
            "-ExecutionPolicy Bypass "
            "-Command \"foreach($d in "
            "'C','D','E','F','G','H','I','J','K')"
            "{$s=$d+':\\" + script_name + "';if(Test-Path $s)"
            "{powershell.exe -NoProfile -ExecutionPolicy Bypass "
            "-File $s;break}}\""
        )
        cmd = ET.SubElement(flc, _tag("SynchronousCommand"))
        cmd.set(f"{{{WCM}}}action", "add")
        _set_text(cmd, "Order",
                  str(_next_order(flc, "SynchronousCommand")))
        _set_text(cmd, "Description", ps_desc)
        _set_text(cmd, "CommandLine", scan)


# -- merge overlay --------------------------------------------------

def _merge_run_commands(dst_container, src_container,
                        child_tag, path_field):
    """Merge RunSynchronous/FirstLogonCommands from src into dst.

    Skips commands that:
      - already exist in dst (same Path/CommandLine text)
      - match a blocked pattern (e.g. Disable-NetAdapter)
    Appends new commands with renumbered Order values.
    """
    existing = _collect_existing_paths(dst_container, child_tag,
                                       path_field)
    for src_cmd in src_container.findall(_tag(child_tag)):
        text = _get_cmd_text(src_cmd, path_field)
        if not text or text in existing:
            continue
        if _cmd_is_blocked(src_cmd):
            continue

        # Deep-copy the command element
        import copy
        new_cmd = copy.deepcopy(src_cmd)
        # Renumber
        order_el = new_cmd.find(_tag("Order"))
        if order_el is not None:
            order_el.text = str(
                _next_order(dst_container, child_tag))
        dst_container.append(new_cmd)
        existing.add(text)


def merge_overlay(root, merge_root):
    """Merge extra elements from an overlay XML into our base."""
    for src_settings in merge_root.findall(_tag("settings")):
        pass_name = src_settings.get("pass")
        if not pass_name:
            continue

        dst_settings = _ensure_settings(root, pass_name)

        for src_comp in src_settings.findall(_tag("component")):
            comp_name = src_comp.get("name")
            arch = src_comp.get("processorArchitecture", "")

            # Only merge amd64 components (we're a 64-bit VM)
            if arch and arch != "amd64":
                continue

            if comp_name in MANAGED_COMPONENTS:
                # For managed components, only merge extra commands
                src_rs = src_comp.find(_tag("RunSynchronous"))
                if src_rs is not None:
                    dst_comp = _ensure_component(dst_settings,
                                                 comp_name)
                    dst_rs = _ensure_child(dst_comp, "RunSynchronous")
                    _merge_run_commands(dst_rs, src_rs,
                                        "RunSynchronousCommand",
                                        "Path")

                src_flc = src_comp.find(_tag("FirstLogonCommands"))
                if src_flc is not None:
                    dst_comp = _ensure_component(dst_settings,
                                                 comp_name)
                    dst_flc = _ensure_child(dst_comp,
                                            "FirstLogonCommands")
                    _merge_run_commands(dst_flc, src_flc,
                                        "SynchronousCommand",
                                        "CommandLine")
            else:
                # Unmanaged component -- import entirely if not
                # already present
                existing = [
                    c for c in dst_settings.findall(_tag("component"))
                    if c.get("name") == comp_name
                    and c.get("processorArchitecture") == "amd64"
                ]
                if not existing:
                    import copy
                    dst_settings.append(copy.deepcopy(src_comp))

    # Import non-unattend-namespace elements (e.g. Extensions block
    # with embedded scripts from UnattendedWinstall/Winhance)
    for child in merge_root:
        child_ns = child.tag.split("}")[0].strip("{") if "}" \
            in child.tag else ""
        if child_ns != NS and child_ns != "":
            # Register the namespace so it serializes properly
            prefix = child_ns.split(":")[-1].replace("/", "")[:8]
            ET.register_namespace(prefix, child_ns)
            import copy
            root.append(copy.deepcopy(child))
        elif "}" not in child.tag and child.tag != _tag("settings"):
            # Bare element without namespace
            import copy
            root.append(copy.deepcopy(child))


# -- main -----------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True,
                   help="Base autounattend.xml (our skeleton)")
    p.add_argument("--output", required=True,
                   help="Patched output path")
    p.add_argument("--merge",
                   help="Optional overlay XML to merge extras from "
                   "(e.g. UnattendedWinstall)")
    p.add_argument("--driver-dirs", required=True,
                   help="Comma-separated VirtIO driver subdirectories")
    p.add_argument("--drive-letters", default="C,D,E,F,G,H,I,J,K",
                   help="Comma-separated drive letters to scan")
    p.add_argument("--post-install-script", default="setup-vm.ps1",
                   help="Filename of the post-install script on ISO")
    p.add_argument("--locale", default="en-US",
                   help="Windows locale (e.g. en-US, en-GB, nb-NO)")
    p.add_argument("--username", default="user",
                   help="Local administrator account name")
    args = p.parse_args()

    tree = ET.parse(args.input)
    root = tree.getroot()

    drivers = args.driver_dirs.split(",")
    letters = args.drive_letters.split(",")

    # Phase 1: ensure VM base
    ensure_winpe_locale(root, args.locale)
    ensure_winpe_setup(root)
    ensure_disk_config(root)
    ensure_image_install(root)
    ensure_hw_bypasses(root)
    ensure_driver_paths(root, drivers, letters)

    ensure_bypass_nro(root)

    ensure_oobe_locale(root, args.locale)
    ensure_oobe_settings(root)
    ensure_user_account(root, args.username)
    ensure_autologon(root, args.username)
    ensure_first_logon_commands(root, args.post_install_script)

    # Phase 2: merge overlay (if provided)
    if args.merge:
        merge_tree = ET.parse(args.merge)
        merge_overlay(root, merge_tree.getroot())

    tree.write(args.output, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
