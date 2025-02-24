"""
File-to-XML converter with automatic .gitignore support.

Usage:
  python3 file_to_xml.py [OPTIONS] [FILE_PATTERNS...]

Examples:
  python3 file_to_xml.py math.nix default.nix "color-lib/*.nix"
  python3 file_to_xml.py

OPTIONS:
  -i, --ignore <pattern>
       Add a pattern to exclude (e.g. .git)
  -f, --filetype <exts>=<lang>
       Define custom filetype overrides. e.g. "nix=none" or "tpl,html=twig"

If no search pattern is given, the program recursively searches the current directory.
"""

import os
import sys
import glob
import argparse
import datetime
from xml.sax.saxutils import escape as xml_escape

try:
    import pathspec
except ImportError:
    sys.stderr.write("Please install pathspec (pip install pathspec)\n")
    sys.exit(1)

try:
    from pygments.lexers import get_lexer_for_filename
    from pygments.util import ClassNotFound
except ImportError:
    get_lexer_for_filename = None
    # You could fallback to a manual mapping if desired
    sys.stderr.write("Warning: Pygments not installed, "
                     "custom filetypes will be required for language detection.\n")


def load_ignore_spec(extra_ignores):
    """
    Load ignore rules from .gitignore (if present) and extra ignores;
    compile them into a pathspec matcher.
    """
    ignore_patterns = list(extra_ignores)  # from -i/--ignore options

    # Always ignore .git by default.
    if ".git" not in ignore_patterns:
        ignore_patterns.append(".git")

    # If a .gitignore exists in the current working directory, load it.
    gitignore_path = os.path.join(os.getcwd(), ".gitignore")
    if os.path.exists(gitignore_path):
        try:
            with open(gitignore_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        ignore_patterns.append(line)
        except Exception as exc:
            sys.stderr.write(f"Error reading .gitignore: {exc}\n")
    return pathspec.PathSpec.from_lines("gitwildmatch", ignore_patterns)


def build_custom_filetypes(mappings):
    """
    Build a dictionary mapping file extensions (without the dot, lowercased)
    to language names as defined by the -f/--filetype options.
    Each mapping should be provided in the form: ext1,ext2=language
    """
    custom = {}
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
    Try to detect the file language using the custom mapping first.
    If not specified, use Pygments (if available) to guess the file type.
    If no language can be determined, returns None.
    """
    _base, ext = os.path.splitext(file_path)
    ext = ext.lstrip(".").lower()

    if ext in custom_filetypes:
        return custom_filetypes[ext]

    if get_lexer_for_filename:
        try:
            lexer = get_lexer_for_filename(file_path)
            # Use the lexer name as the language indicator.
            return lexer.name.lower()
        except ClassNotFound:
            # Fall through to skip the file if unknown.
            pass
    # If no language detected, indicate that file should be ignored.
    return None


def process_file(file_path, custom_filetypes):
    """
    Process a file: if a language is detected, output an XML block containing
    the file metadata and contents wrapped in a CDATA section.
    """
    language = detect_language(file_path, custom_filetypes)
    if language is None:
        return  # Skip files with unknown file type

    try:
        statinfo = os.stat(file_path)
    except Exception as e:
        sys.stderr.write(f"Could not stat file {file_path}: {e}\n")
        return

    mod_time_str = datetime.datetime.fromtimestamp(
        statinfo.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    file_size = statinfo.st_size

    esc_name = xml_escape(file_path)
    esc_mod_time = xml_escape(mod_time_str)
    esc_file_size = xml_escape(str(file_size))

    print(f'  <file name="{esc_name}" language="{language} >" ')
          #f'modified="{esc_mod_time}" size="{esc_file_size}">')
    print("    <![CDATA[")

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                # Remove newline, indent and replace any "]]>" occurrence.
                line = line.rstrip("\n").replace("]]>", "]]]]><![CDATA[>")
                print("      " + line)
    except Exception as e:
        print("      Error reading file: " + str(e))

    print("    ]]>")
    print("  </file>")


def collect_files(search_patterns, ignore_spec):
    """
    Based on the user-provided search patterns (or a default of '.'),
    collect all files which are not matched by ignore_spec.
    """
    files = set()

    if not search_patterns:
        # If no patterns provided, search recursively from the current directory.
        for root, dirs, filenames in os.walk("."):
            for fname in filenames:
                fullpath = os.path.join(root, fname)
                rel = os.path.relpath(fullpath, os.getcwd())
                if ignore_spec.match_file(rel):
                    continue
                files.add(fullpath)
    else:
        for pattern in search_patterns:
            if os.path.isfile(pattern):
                rel = os.path.relpath(os.path.abspath(pattern), os.getcwd())
                if ignore_spec.match_file(rel):
                    continue
                files.add(pattern)
            elif os.path.isdir(pattern):
                for root, dirs, filenames in os.walk(pattern):
                    for fname in filenames:
                        fullpath = os.path.join(root, fname)
                        rel = os.path.relpath(os.path.abspath(fullpath), os.getcwd())
                        if ignore_spec.match_file(rel):
                            continue
                        files.add(fullpath)
            else:
                # Expand wildcard/glob patterns.
                for f in glob.glob(pattern, recursive=True):
                    if os.path.isfile(f):
                        rel = os.path.relpath(os.path.abspath(f), os.getcwd())
                        if ignore_spec.match_file(rel):
                            continue
                        files.add(f)
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(
        description=("Convert files to XML with embedded code blocks. "
                     "Automatically follows .gitignore."))
    parser.add_argument(
        "-i",
        "--ignore",
        action="append",
        default=[],
        help="Add a pattern to exclude (e.g. .git)")
    parser.add_argument(
        "-f",
        "--filetype",
        action="append",
        default=[],
        help=("Custom filetype overrides in the form ext1,ext2=lang. "
              "For example: --filetype 'nix=none' or '--filetype "
              "tpl,html=twig'"))
    parser.add_argument(
        "patterns",
        nargs="*",
        help="File or directory search patterns (e.g. *.py).")
    args = parser.parse_args()

    custom_filetypes = build_custom_filetypes(args.filetype)
    ignore_spec = load_ignore_spec(args.ignore)
    files = collect_files(args.patterns, ignore_spec)

    print("<src>")
    for file_path in files:
        try:
            process_file(file_path, custom_filetypes)
        except Exception as exc:
            sys.stderr.write(f"Error processing {file_path}: {exc}\n")
    print("</src>")


if __name__ == "__main__":
    main()

