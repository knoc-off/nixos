#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate artifacts

# nix build output: files are alongside this script
# local build: files are in pkg/ and vendor/
if [[ -f "$SCRIPT_DIR/_marki.js" ]]; then
    WASM_JS="$SCRIPT_DIR/_marki.js"
    WASM_BG="$SCRIPT_DIR/_marki_bg.wasm"
    HLJS="$SCRIPT_DIR/_hljs.js"
elif [[ -f "$SCRIPT_DIR/pkg/marki.js" ]]; then
    WASM_JS="$SCRIPT_DIR/pkg/marki.js"
    WASM_BG="$SCRIPT_DIR/pkg/marki_bg.wasm"
    HLJS="$SCRIPT_DIR/vendor/highlight.min.js"
else
    echo "Error: Cannot find WASM artifacts."
    echo "Run 'wasm-pack build --target no-modules' or 'nix build' first."
    exit 1
fi

if [[ ! -f "$HLJS" ]]; then
    echo "Error: Cannot find highlight.js at: $HLJS"
    exit 1
fi

TEMPLATES_DIR=""
if [[ -d "$SCRIPT_DIR/templates" ]]; then
    TEMPLATES_DIR="$SCRIPT_DIR/templates"
fi

# Detect Anki

if [[ "$(uname)" == "Darwin" ]]; then
    ANKI_BASE="$HOME/Library/Application Support/Anki2"
else
    ANKI_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/Anki2"
fi

if [[ ! -d "$ANKI_BASE" ]]; then
    echo "Error: Anki data directory not found at: $ANKI_BASE"
    echo "Is Anki installed?"
    exit 1
fi

# Select profile

PROFILES=()
while IFS= read -r dir; do
    name="$(basename "$dir")"
    [[ "$name" == "addons21" || "$name" == "crash.log" || "$name" == "prefs21.db" ]] && continue
    [[ -d "$dir/collection.media" ]] && PROFILES+=("$name")
done < <(find "$ANKI_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo "Error: No Anki profiles found in: $ANKI_BASE"
    echo "Open Anki at least once to create a profile."
    exit 1
fi

if [[ ${#PROFILES[@]} -eq 1 ]]; then
    PROFILE="${PROFILES[0]}"
    echo "Using Anki profile: $PROFILE"
else
    echo "Available Anki profiles:"
    for i in "${!PROFILES[@]}"; do
        echo "  $((i + 1))) ${PROFILES[$i]}"
    done
    printf "Select profile [1]: "
    read -r choice
    choice="${choice:-1}"
    idx=$((choice - 1))
    if [[ $idx -lt 0 || $idx -ge ${#PROFILES[@]} ]]; then
        echo "Error: Invalid selection."
        exit 1
    fi
    PROFILE="${PROFILES[$idx]}"
fi

MEDIA_DIR="$ANKI_BASE/$PROFILE/collection.media"

# Install files

echo ""
echo "Installing to: $MEDIA_DIR"

cp "$WASM_JS" "$MEDIA_DIR/_marki.js"
cp "$WASM_BG" "$MEDIA_DIR/_marki_bg.wasm"
cp "$HLJS"    "$MEDIA_DIR/_hljs.js"

# Anki needs read/write access to media files
chmod 644 "$MEDIA_DIR/_marki.js"
chmod 644 "$MEDIA_DIR/_marki_bg.wasm"
chmod 644 "$MEDIA_DIR/_hljs.js"

echo "  _marki.js       OK"
echo "  _marki_bg.wasm  OK"
echo "  _hljs.js        OK"

# Print setup instructions

echo ""
echo "=== Note Type Setup ==="
echo ""
echo "In Anki: Tools -> Manage Note Types -> Add"
echo ""
echo "--- Marki Basic ---"
echo "  Clone from: Basic"
echo "  Fields: Front, Back"
if [[ -n "$TEMPLATES_DIR" ]]; then
    echo "  Front template:  $TEMPLATES_DIR/basic-front.html"
    echo "  Back template:   $TEMPLATES_DIR/basic-back.html"
    echo "  Styling (CSS):   $TEMPLATES_DIR/basic-style.css"
fi
echo ""
echo "--- Marki Cloze ---"
echo "  Clone from: Cloze"
echo "  Fields: Text, Back Extra"
if [[ -n "$TEMPLATES_DIR" ]]; then
    echo "  Front template:  $TEMPLATES_DIR/cloze-front.html"
    echo "  Back template:   $TEMPLATES_DIR/cloze-back.html"
    echo "  Styling (CSS):   $TEMPLATES_DIR/cloze-style.css"
fi
echo ""
echo "Copy the contents of each file into the corresponding"
echo "section in Anki's card template editor."
echo ""
echo "Done!"
