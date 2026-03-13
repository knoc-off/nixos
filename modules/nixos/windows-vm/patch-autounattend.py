#!/usr/bin/env python3
"""Patch a Windows autounattend.xml for VM use.

Injects into the parsed XML tree:
  1. VirtIO driver paths in the windowsPE pass so Windows Setup
     auto-loads storage/network drivers without manual intervention.
  2. A FirstLogonCommands entry in the oobeSystem pass to run a
     post-install script (VirtIO guest tools, WinFSP, virtiofs).
  3. Locale values across all International-Core components.
  4. Username into UserAccounts and AutoLogon elements.

Uses xml.etree.ElementTree for proper namespace-aware parsing --
no regex or line-matching fragility.
"""

import argparse
import xml.etree.ElementTree as ET

NS = "urn:schemas-microsoft-com:unattend"
WCM = "http://schemas.microsoft.com/WMIConfig/2002/State"

ET.register_namespace("", NS)
ET.register_namespace("wcm", WCM)

# Locale fields present in International-Core components
LOCALE_TAGS = ["InputLocale", "SystemLocale", "UILanguage", "UserLocale"]


def set_locale(root, locale):
    """Set all locale fields in International-Core components."""
    for settings in root.findall(f"{{{NS}}}settings"):
        for comp in settings.findall(f"{{{NS}}}component"):
            name = comp.get("name", "")
            if "International-Core" not in name:
                continue

            for tag in LOCALE_TAGS:
                el = comp.find(f"{{{NS}}}{tag}")
                if el is not None:
                    el.text = locale

            # WinPE also has SetupUILanguage/UILanguage
            sui = comp.find(f"{{{NS}}}SetupUILanguage")
            if sui is not None:
                ui = sui.find(f"{{{NS}}}UILanguage")
                if ui is not None:
                    ui.text = locale


def set_username(root, username):
    """Set the local account name and AutoLogon username."""
    for settings in root.findall(f"{{{NS}}}settings"):
        for comp in settings.findall(f"{{{NS}}}component"):
            # LocalAccounts -> LocalAccount -> Name
            ua = comp.find(f"{{{NS}}}UserAccounts")
            if ua is not None:
                for la in ua.iter(f"{{{NS}}}LocalAccount"):
                    name_el = la.find(f"{{{NS}}}Name")
                    if name_el is not None:
                        name_el.text = username

            # AutoLogon -> Username
            al = comp.find(f"{{{NS}}}AutoLogon")
            if al is not None:
                u_el = al.find(f"{{{NS}}}Username")
                if u_el is not None:
                    u_el.text = username


def add_driver_paths(root, driver_dirs, drive_letters):
    """Add a PnpCustomizationsWinPE component to the windowsPE pass."""
    for settings in root.findall(f"{{{NS}}}settings"):
        if settings.get("pass") != "windowsPE":
            continue

        comp = ET.SubElement(settings, f"{{{NS}}}component")
        comp.set("name", "Microsoft-Windows-PnpCustomizationsWinPE")
        comp.set("processorArchitecture", "amd64")
        comp.set("publicKeyToken", "31bf3856ad364e35")
        comp.set("language", "neutral")
        comp.set("versionScope", "nonSxS")

        paths_el = ET.SubElement(comp, f"{{{NS}}}DriverPaths")
        key = 1
        for letter in drive_letters:
            for d in driver_dirs:
                entry = ET.SubElement(paths_el, f"{{{NS}}}PathAndCredentials")
                entry.set(f"{{{WCM}}}action", "add")
                entry.set(f"{{{WCM}}}keyValue", str(key))
                path_el = ET.SubElement(entry, f"{{{NS}}}Path")
                path_el.text = f"{letter}:\\{d}"
                key += 1
        break  # only one windowsPE pass


def add_post_install_cmd(root, script_name):
    """Append a SynchronousCommand to FirstLogonCommands in oobeSystem.

    Scans drive letters to find the script (it lives on the deploy ISO
    whose letter is not known in advance).
    """
    scan = (
        f"powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass "
        f"-Command \"foreach($d in 'C','D','E','F','G','H','I','J','K')"
        f"{{$s=$d+':\\{script_name}';if(Test-Path $s)"
        f"{{powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s;break}}}}\""
    )

    for settings in root.findall(f"{{{NS}}}settings"):
        if settings.get("pass") != "oobeSystem":
            continue
        for component in settings.findall(f"{{{NS}}}component"):
            flc = component.find(f"{{{NS}}}FirstLogonCommands")
            if flc is None:
                continue

            # Determine next order number
            max_order = 0
            for cmd in flc.findall(f"{{{NS}}}SynchronousCommand"):
                order_el = cmd.find(f"{{{NS}}}Order")
                if order_el is not None and order_el.text:
                    max_order = max(max_order, int(order_el.text))

            cmd = ET.SubElement(flc, f"{{{NS}}}SynchronousCommand")
            ET.SubElement(cmd, f"{{{NS}}}Order").text = str(max_order + 1)
            ET.SubElement(cmd, f"{{{NS}}}Description").text = (
                "VM post-install: VirtIO guest tools, WinFSP, virtiofs"
            )
            ET.SubElement(cmd, f"{{{NS}}}CommandLine").text = scan


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="Source autounattend.xml")
    p.add_argument("--output", required=True, help="Patched output path")
    p.add_argument(
        "--driver-dirs",
        required=True,
        help="Comma-separated VirtIO driver subdirectories",
    )
    p.add_argument(
        "--drive-letters",
        default="C,D,E,F,G,H,I,J,K",
        help="Comma-separated drive letters to scan",
    )
    p.add_argument(
        "--post-install-script",
        default="setup-vm.ps1",
        help="Filename of the post-install script on the ISO",
    )
    p.add_argument(
        "--locale",
        default="en-US",
        help="Windows locale (e.g. en-US, en-GB, nb-NO)",
    )
    p.add_argument(
        "--username",
        default="user",
        help="Local account name to create",
    )
    args = p.parse_args()

    tree = ET.parse(args.input)
    root = tree.getroot()

    set_locale(root, args.locale)
    set_username(root, args.username)
    add_driver_paths(root, args.driver_dirs.split(","), args.drive_letters.split(","))
    add_post_install_cmd(root, args.post_install_script)

    tree.write(args.output, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
