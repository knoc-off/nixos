---
name: windows-vm
description: Run commands on, or copy files to/from, the local QEMU Windows VM (windows-vm-ssh / windows-vm-scp). Use ONLY when the user explicitly asks you to interact with the Windows VM.
---

# Windows VM helpers

- `windows-vm-ssh [cmd...]` — run a command on (or open a shell into) the local
  Windows VM over SSH. Thin wrapper around `sshpass + ssh` to 127.0.0.1:2223.
- `windows-vm-scp <src> <dst>` — copy files to/from the VM. Thin wrapper around
  `sshpass + scp`; args pass straight through, so supply the full destination:
  `windows-vm-scp ./app.exe vmadmin@127.0.0.1:'C:/Users/vmadmin.TEMPLATE--XXXX/Desktop/'`

Only use these when the user explicitly asks you to interact with the Windows VM.
