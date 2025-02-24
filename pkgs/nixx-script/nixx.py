"""
A Python port of a Nushell-based nix wrapper.

Usage examples:
  nixx sudo package-name -- arg1 arg2
  nixx bg package-name -- arg1 arg2

Arguments before "--" are parsed as follows:
  - "sudo": run the command under sudo
  - "bg": run the command in background using pueue
  - The first argument not equal to "sudo" or "bg" is taken as the package name

Arguments following "--" are passed to the generated command.
"""

import sys
import subprocess
import re

def main():
    args = sys.argv[1:]

    # Locate the separator "--" if present.
    try:
        separator_index = args.index("--")
    except ValueError:
        separator_index = None

    if separator_index is not None:
        nixx_args = args[:separator_index]
        program_args = args[separator_index + 1:]
    else:
        nixx_args = args
        program_args = []

    # Process nixx arguments.
    package = ""
    sudo = False
    bg = False

    for arg in nixx_args:
        if arg == "sudo":
            sudo = True
        elif arg == "bg":
            bg = True
        elif package == "":
            package = arg

    if sudo and bg:
        print("Warning: Using sudo with background tasks may require manual authentication")

    command = []

    # If background, pre-pend with pueue add.
    if bg:
        command.extend(["pueue", "add"])

    # Build the base command.
    base_command = [
        "env",
        "NIXPKGS_ALLOW_UNFREE=1",
        "nix",
        "shell",
        "--impure",
        f"nixpkgs#{package}",
        "--command"
    ]
    command.extend(base_command)

    if sudo:
        command.append("sudo")

    # Append the package as well as any extra arguments.
    command.append(package)
    command.extend(program_args)

    # Join the command list into a single string.
    command_str = " ".join(command)

    if bg:
        try:
            # Run the command using nu (assumed to be in PATH) for background tasks.
            res = subprocess.run(
                ["nu", "-c", command_str],
                capture_output=True,
                text=True,
                check=True
            )
        except subprocess.CalledProcessError as e:
            print("Error running background command:", e.stderr)
            sys.exit(e.returncode)

        pueue_output = res.stdout.strip()
        # Parse output like: "New task added (id X)."
        match = re.search(r"New task added \(id (\d+)\)\.", pueue_output)
        if match:
            task_id = match.group(1)
            print(f"Task added with ID: {task_id}")
            # Optionally, uncomment the following line to follow the task:
            # subprocess.run(["pueue", "follow", task_id])
        else:
            print("Failed to parse task ID. Pueue output:")
            print(pueue_output)
    else:
        # Run as a foreground process using bash.
        subprocess.run(["bash", "-c", command_str])

if __name__ == "__main__":
    main()

