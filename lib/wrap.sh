#!/usr/bin/env bash
#
# Enhanced file-to-XML converter with custom ignores and filetype handling.
# Wraps the entire output in a <src> tag (with a timestamp) and each file in a
# <file> tag that includes attributes (filename, language, modTime, size).
#
# Usage: script.sh [OPTIONS] [FILE_PATTERNS...]
#
# Examples:
#   ./script.sh math.nix default.nix "color-lib/*.nix"
#
# OPTIONS:
#   -i|--ignore <pattern>     Add a pattern to exclude (e.g. .git)
#   -f|--filetype <exts>=<lang> Define custom filetype overrides

# Initialize variables
declare -A CUSTOM_FILETYPES
declare -a EXCLUDE_PATTERNS=('.git')  # Exclude .git by default
declare -a SEARCH_PATTERNS=()

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--ignore)
      EXCLUDE_PATTERNS+=("$2")
      shift 2
      ;;
    -f|--filetype)
      IFS='=' read -r exts lang <<< "$2"
      for ext in ${exts//,/ }; do
        CUSTOM_FILETYPES["$ext"]="$lang"
      done
      shift 2
      ;;
    -*)
      echo "Invalid option: $1" >&2
      exit 1
      ;;
    *)
      SEARCH_PATTERNS+=("$1")
      shift
      ;;
  esac
done

# Function to escape XML attribute values
escape_xml() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  echo "$s"
}

# Filetype detection function with custom overrides
get_filetype() {
  local filename="$1"
  local extension="${filename##*.}"

  # Check custom filetypes first
  for pattern in "${!CUSTOM_FILETYPES[@]}"; do
    if [[ "$filename" == $pattern ]]; then
      echo "${CUSTOM_FILETYPES[$pattern]}"
      return
    fi
  done

  # Built-in type detection
  case "$filename" in
    *.*)
      case ".${filename##*.}" in
        .sh)           echo "bash" ;;
        .py)           echo "python" ;;
        .mcfunction)   echo "mcfunction" ;;
        .js)           echo "javascript" ;;
        .ts)           echo "typescript" ;;
        .json)         echo "json" ;;
        .md)           echo "markdown" ;;
        .txt)          echo "plaintext" ;;
        .html|.htm)    echo "html" ;;
        .css)          echo "css" ;;
        .scss)         echo "scss" ;;
        .less)         echo "less" ;;
        .java)         echo "java" ;;
        .c)            echo "c" ;;
        .cpp|.hpp|.hxx)
          echo "cpp" ;;
        .h)            echo "c" ;;
        .cs)           echo "csharp" ;;
        .rb)           echo "ruby" ;;
        .php)          echo "php" ;;
        .rs)           echo "rust" ;;
        .go)           echo "go" ;;
        .nix)          echo "nix" ;;
        .patch)        echo "patch" ;;
        .yaml|.yml)    echo "yaml" ;;
        .toml)         echo "toml" ;;
        .xml)          echo "xml" ;;
        .vue)          echo "vue" ;;
        .kt)           echo "kotlin" ;;
        .dart)         echo "dart" ;;
        .pl|.pm)       echo "perl" ;;
        .r)            echo "r" ;;
        .jl)           echo "julia" ;;
        .lua)          echo "lua" ;;
        .sql)          echo "sql" ;;
        .swift)        echo "swift" ;;
        .scala)        echo "scala" ;;
        .groovy)       echo "groovy" ;;
        .ini)          echo "ini" ;;
        .bat)          echo "batch" ;;
        .ps1)          echo "powershell" ;;
        .vbs)          echo "vbscript" ;;
        .tex)          echo "latex" ;;
        .rmd)          echo "rmarkdown" ;;
        .erl)          echo "erlang" ;;
        .ex|.exs)      echo "elixir" ;;
        .hs)           echo "haskell" ;;
        .clj)          echo "clojure" ;;
        .cljs)         echo "clojurescript" ;;
        .coffee)       echo "coffeescript" ;;
        .f90|.f95)     echo "fortran" ;;
        .m)            echo "objectivec" ;;
        .mm)           echo "objectivecpp" ;;
        .rkt)          echo "racket" ;;
        .scm)          echo "scheme" ;;
        .lisp)         echo "lisp" ;;
        .asm|.s)       echo "assembly" ;;
        *)             echo "IGNORE" ;;
      esac
      ;;
    *)
      # Handle extensionless files using custom overrides
      for pattern in "${!CUSTOM_FILETYPES[@]}"; do
        if [[ "$filename" == $pattern ]]; then
          echo "${CUSTOM_FILETYPES[$pattern]}"
          return
        fi
      done
      echo "IGNORE" ;;
  esac
}

# Build find exclusion arguments from EXCLUDE_PATTERNS
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  EXCLUDE_ARGS+=( -not -path "*${pattern}*" )
done

# Process a single file and output XML-wrapped content
process_file() {
  local file="$1"
  local filetype
  filetype=$(get_filetype "$file")
  [[ "$filetype" == "IGNORE" ]] && return

  # Obtain file metadata (using GNU or BSD stat)
  local modTime fileSize
  modTime=$(stat -c '%y' "$file" 2>/dev/null)
  if [[ -z "$modTime" ]]; then
    modTime=$(stat -f '%Sm' "$file" 2>/dev/null)
  fi
  fileSize=$(stat -c '%s' "$file" 2>/dev/null)
  if [[ -z "$fileSize" ]]; then
    fileSize=$(stat -f '%z' "$file" 2>/dev/null)
  fi

  # Escape values for safe XML attribute inclusion
  local esc_file esc_modTime esc_fileSize
  esc_file=$(escape_xml "$file")
  esc_modTime=$(escape_xml "$modTime")
  esc_fileSize=$(escape_xml "$fileSize")

  echo "  <file name=\"${esc_file}\" language=\"${filetype}\""
  printf "    <![CDATA[\n    \`\`\`\n"
  # Output file content. Replace any occurrence of ']]>' to ensure valid XML.
  sed 's/]]>/]]]]><![CDATA[>/g' "$file" |
    sed 's/^/      /'
  printf "\n    \`\`\`\n    ]]>"
  echo "  </file>"
}

# Output the top-level XML tag with a timestamp attribute.
echo "<src>"

# Main processing: If no search pattern is given, search the current directory.
if [[ ${#SEARCH_PATTERNS[@]} -eq 0 ]]; then
  while IFS= read -r -d '' file; do
    process_file "$file"
  done < <(find . -type f "${EXCLUDE_ARGS[@]}" -print0)
else
  for pattern in "${SEARCH_PATTERNS[@]}"; do
    if [[ -f "$pattern" ]]; then
      process_file "$pattern"
    elif [[ -d "$pattern" ]]; then
      while IFS= read -r -d '' file; do
        process_file "$file"
      done < <(find "$pattern" -type f "${EXCLUDE_ARGS[@]}" -print0)
    elif [[ "$pattern" == *"*"* || "$pattern" == *"?"* || "$pattern" == *"["* ]]; then
      # If the pattern contains wildcards, use find in the parent directory.
      dir=$(dirname "$pattern")
      base=$(basename "$pattern")
      while IFS= read -r -d '' file; do
        process_file "$file"
      done < <(find "$dir" -type f -name "$base" "${EXCLUDE_ARGS[@]}" -print0)
    else
      echo "Warning: Pattern '$pattern' does not match a file or directory." >&2
    fi
  done
fi

echo "</src>"

