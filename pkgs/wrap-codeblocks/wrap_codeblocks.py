"""
File-to-XML Converter with Cascading .gitignore Support

This script will recursively search a repository (or provided paths)
and convert files to an XML representation. It automatically collects
ignore rules from all .gitignore files distributed throughout the
repository (emulating Git's cascading behavior) and combines them
with any extra ignore patterns passed via the command line.

Usage:
  python3 wrap-codeblocks.py [OPTIONS] [FILE_PATTERNS...]

Examples:
  python3 wrap-codeblocks.py math.nix default.nix "color-lib/*.nix"
  python3 wrap-codeblocks.py

OPTIONS:
  -i, --ignore <pattern>
       Add an extra pattern to exclude (e.g., 'build/**').
  -f, --filetype <exts>=<lang>
       Define custom filetype overrides (e.g., --filetype 'nix=none'
       or '--filetype tpl,html=twig').

If no search pattern is given, the program searches recursively from
the current repository root.

Configuration:
  The script supports a configuration file at ~/.config/wrap-codeblocks.yaml
  with the following structure:

  ignore:
    - .direnv/
    - .gitignore
    - .envrc
    - Cargo.lock
  filetypes:
    nix: nix
    rs: rust
"""

import os
import sys
import glob
import argparse
import datetime
from xml.sax.saxutils import escape as xml_escape
from pathlib import Path

# We'll use posix-style paths when matching ignore files.
import posixpath


import pathspec

import yaml

from pygments.lexers import get_lexer_for_filename
from pygments.util import ClassNotFound



def load_config_file():
    """
    Load the configuration file from ~/.config/wrap-codeblocks.yaml if it exists.
    Returns a dictionary with the configuration or an empty dict if the file doesn't exist.
    """
    config_path = Path.home() / ".config" / "wrap-codeblocks.yaml"
    if not config_path.exists():
        return {}

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        sys.stderr.write(f"Error loading config file {config_path}: {e}\n")
        return {}


def transform_gitignore_pattern(dir_rel, pattern):
    """
    Transform a single line from a .gitignore file located in 'dir_rel'
    (the directory relative to the repository root) into a pattern
    relative to the repository root.

    The transformation is as follows:
    - If the pattern starts with "!", it is an exception rule.
    - If the pattern starts with "/" (anchored), then we remove that slash
      and prepend the directory.
    - If the pattern does not contain a slash (i.e. it is a bare filename),
      then we prepend '**/' so it will match in any subdirectory of the
      directory containing the .gitignore file.
    - Otherwise, simply prefix the pattern with the directory path,
      unless the directory is "." (the repo root).

    Returns the transformed pattern as a string (or None to ignore blank/comment lines).
    """
    pat = pattern.strip()
    if not pat or pat.startswith("#"):
        return None

    negative = False
    if pat.startswith("!"):
        negative = True
        pat = pat[1:].strip()
        if not pat:
            return None

    anchored = False
    if pat.startswith("/"):
        anchored = True
        pat = pat[1:]  # Remove the leading slash

    if anchored:
        # Anchored patterns are relative to the .gitignore directory.
        if dir_rel != ".":
            pat = f"{dir_rel}/{pat}"
    else:
        if "/" in pat:
            # If a slash is present, pattern is relative to the .gitignore directory.
            if dir_rel != ".":
                pat = f"{dir_rel}/{pat}"
        else:
            # Bare filename: match anywhere below the .gitignore directory.
            if dir_rel != ".":
                pat = f"{dir_rel}/**/{pat}"
            else:
                pat = f"**/{pat}"

    return "!" + pat if negative else pat


def load_cascading_gitignores(repo_root):
    """
    Recursively traverse the repository starting at repo_root, looking
    for .gitignore files. Read and transform each valid pattern so that
    it becomes relative to the repository root.

    Returns a list of patterns.
    """
    patterns = []
    for root, dirs, files in os.walk(repo_root):
        # Compute the directory relative to the repo root in POSIX style.
        rel_dir = os.path.relpath(root, repo_root)
        rel_dir = rel_dir.replace(os.path.sep, "/")
        if rel_dir == "" or rel_dir == ".":  # at repo root
            rel_dir = "."
        if ".gitignore" in files:
            gitignore_path = os.path.join(root, ".gitignore")
            try:
                with open(gitignore_path, "r", encoding="utf-8") as f:
                    for line in f:
                        transformed = transform_gitignore_pattern(rel_dir, line)
                        if transformed:
                            patterns.append(transformed)
            except Exception as e:
                sys.stderr.write(f"Error reading {gitignore_path}: {e}\n")
    return patterns


def load_cascading_gitignore_spec(repo_root, extra_ignores):
    """
    Combine extra ignore patterns with the distributed .gitignore patterns
    collected across the repository. Returns a pathspec matcher.
    """
    all_patterns = []
    # Incorporate extra ignore patterns passed via the command line.
    for pat in extra_ignores:
        if pat:
            all_patterns.append(pat)
    # Always ignore .git directories.
    all_patterns.append("**/.git")
    # Append patterns from all .gitignore files.
    all_patterns.extend(load_cascading_gitignores(repo_root))
    return pathspec.PathSpec.from_lines("gitwildmatch", all_patterns)


def build_custom_filetypes(mappings, config_filetypes=None):
    """
    Build a dictionary mapping file extensions (without the dot) to language
    names from custom mappings specified with the -f/--filetype option and the config file.
    """
    custom = {}

    # First add filetypes from config
    if config_filetypes:
        for ext, lang in config_filetypes.items():
            ext = ext.lstrip(".").strip().lower()
            if ext:
                custom[ext] = lang

    # Then add command-line filetypes (which can override config)
    for mapping in mappings:
        if "=" not in mapping:
            sys.stderr.write(f"Invalid filetype mapping: {mapping}\n")
            sys.exit(1)
        exts, lang = mapping.split("=", 1)
        for ext in exts.split(","):
            ext = ext.lstrip(".").strip().lower()
            if ext:
                custom[ext] = lang

    return custom


def detect_language(file_path, custom_filetypes):
    """
    First try to detect the language using custom filetype mappings. If not
    defined and Pygments is available, attempt to guess the language.
    Returns the language name (string) or None to indicate no match.
    """
    _base, ext = os.path.splitext(file_path)
    ext = ext.lstrip(".").lower()
    if ext in custom_filetypes:
        return custom_filetypes[ext]
    if get_lexer_for_filename:
        try:
            lexer = get_lexer_for_filename(file_path)
            return lexer.name.lower()
        except ClassNotFound:
            pass
    return None


def process_file(file_path, custom_filetypes):
    """
    Process a single file: if the language is detected, output an XML block
    with file metadata and the file's contents wrapped in a CDATA section.
    """
    language = detect_language(file_path, custom_filetypes)
    if language is None:
        return False

    try:
        statinfo = os.stat(file_path)
    except Exception as e:
        sys.stderr.write(f"Could not stat file {file_path}: {e}\n")
        return False

    mod_time_str = datetime.datetime.fromtimestamp(
        statinfo.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    file_size = statinfo.st_size
    esc_name = xml_escape(file_path)
    esc_mod_time = xml_escape(mod_time_str)
    esc_file_size = xml_escape(str(file_size))

    print(f'  <file name="{esc_name}" language="{language}" modified="{esc_mod_time}" size="{esc_file_size}">')
    print("    <![CDATA[")
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                # Ensure that any occurrence of ']]>' gets split,
                # so that the CDATA section remains valid.
                line = line.rstrip("\n").replace("]]>", "]]]]><![CDATA[>")
                print("      " + line)
    except Exception as e:
        print(f"      Error reading file: {e}")
    print("    ]]>")
    print("  </file>")
    return True


def collect_files(search_patterns, ignore_spec, repo_root):
    """
    Collect files from the repository by walking the directory tree, or use
    the provided file and directory patterns. Files that match the ignore
    spec are skipped.

    All files are checked against the ignore matcher using their path relative
    to the repository root (in POSIX format).
    """
    collected = set()
    if not search_patterns:
        for root, dirs, filenames in os.walk(repo_root):
            for fname in filenames:
                fullpath = os.path.join(root, fname)
                rel = os.path.relpath(fullpath, repo_root).replace(
                    os.path.sep, "/")
                if ignore_spec.match_file(rel):
                    continue
                collected.add(fullpath)
    else:
        for pattern in search_patterns:
            if os.path.isfile(pattern):
                rel = os.path.relpath(os.path.abspath(pattern), repo_root)
                rel = rel.replace(os.path.sep, "/")
                if ignore_spec.match_file(rel):
                    continue
                collected.add(pattern)
            elif os.path.isdir(pattern):
                for root, dirs, filenames in os.walk(pattern):
                    for fname in filenames:
                        fullpath = os.path.join(root, fname)
                        rel = os.path.relpath(os.path.abspath(fullpath), repo_root)
                        rel = rel.replace(os.path.sep, "/")
                        if ignore_spec.match_file(rel):
                            continue
                        collected.add(fullpath)
            else:
                for f in glob.glob(pattern, recursive=True):
                    if os.path.isfile(f):
                        rel = os.path.relpath(os.path.abspath(f), repo_root)
                        rel = rel.replace(os.path.sep, "/")
                        if ignore_spec.match_file(rel):
                            continue
                        collected.add(f)
    return sorted(collected)


def build_directory_tree(files, repo_root):
    """
    Build a directory tree structure from the list of files.
    Returns a nested dictionary representing the directory structure.
    """
    tree = {}
    for file_path in files:
        # Get the path relative to repo_root
        rel_path = os.path.relpath(file_path, repo_root)
        parts = rel_path.split(os.sep)

        # Navigate the tree
        current = tree
        for i, part in enumerate(parts):
            if i == len(parts) - 1:  # This is a file
                if "__files__" not in current:
                    current["__files__"] = []
                current["__files__"].append(file_path)
            else:  # This is a directory
                if part not in current:
                    current[part] = {}
                current = current[part]

    return tree


def print_directory_tree_xml(tree, indent=2, level=0):
    """
    Print the directory tree as XML.
    """
    spaces = " " * (indent * level)

    # Print files at this level
    if "__files__" in tree:
        for file_path in tree["__files__"]:
            print(f"{spaces}<file path=\"{xml_escape(file_path)}\" />")

    # Print directories and their contents
    for name, contents in sorted(tree.items()):
        if name == "__files__":
            continue

        print(f"{spaces}<directory name=\"{xml_escape(name)}\">")
        print_directory_tree_xml(contents, indent, level + 1)
        print(f"{spaces}</directory>")


def main():
    # Load configuration file
    config = load_config_file()
    config_ignores = config.get('ignore', [])
    config_filetypes = config.get('filetypes', {})

    parser = argparse.ArgumentParser(
        description=("Convert files to XML with embedded code blocks. "
                     "Automatically follows cascading .gitignore patterns."))
    parser.add_argument(
        "-i",
        "--ignore",
        action="append",
        default=[],
        help="Add an extra pattern to exclude (e.g., 'build/**').")
    parser.add_argument(
        "-f",
        "--filetype",
        action="append",
        default=[],
        help=("Custom filetype overrides in the form ext1,ext2=lang. "
              "Example: --filetype 'nix=none' or '--filetype tpl,html=twig'"))
    parser.add_argument(
        "patterns",
        nargs="*",
        help="File or directory search patterns (e.g., *.py).")
    args = parser.parse_args()

    # Combine config and command-line ignores
    all_ignores = config_ignores + args.ignore

    custom_filetypes = build_custom_filetypes(args.filetype, config_filetypes)
    repo_root = os.getcwd()
    ignore_spec = load_cascading_gitignore_spec(repo_root, all_ignores)
    files = collect_files(args.patterns, ignore_spec, repo_root)

    print("<src>")
    processed_files = []
    for file_path in files:
        try:
            if process_file(file_path, custom_filetypes):
                processed_files.append(file_path)
        except Exception as exc:
            sys.stderr.write(f"Error processing {file_path}: {exc}\n")

    # Add the directory tree structure with only processed files
    print("  <filetree>")
    directory_tree = build_directory_tree(processed_files, repo_root)
    print_directory_tree_xml(directory_tree, level=2)
    print("  </filetree>")

    print("</src>")


if __name__ == "__main__":
    main()

