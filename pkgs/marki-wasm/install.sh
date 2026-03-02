#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory this script lives in (works from nix build output or repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find WASM artifacts — either alongside this script (nix build) or in pkg/ (local build)
if [[ -f "$SCRIPT_DIR/_marki.js" ]]; then
    WASM_JS="$SCRIPT_DIR/_marki.js"
    WASM_BG="$SCRIPT_DIR/_marki_bg.wasm"
elif [[ -f "$SCRIPT_DIR/pkg/marki.js" ]]; then
    WASM_JS="$SCRIPT_DIR/pkg/marki.js"
    WASM_BG="$SCRIPT_DIR/pkg/marki_bg.wasm"
else
    echo "Error: Cannot find WASM artifacts."
    echo "Run 'wasm-pack build --target no-modules' or 'nix build' first."
    exit 1
fi

# Find templates directory
if [[ -d "$SCRIPT_DIR/templates" ]]; then
    TEMPLATES_DIR="$SCRIPT_DIR/templates"
else
    echo "Warning: templates/ directory not found. Skipping template display."
    TEMPLATES_DIR=""
fi

# Detect Anki data directory
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

# List profiles
PROFILES=()
while IFS= read -r dir; do
    name="$(basename "$dir")"
    # Skip non-profile directories
    [[ "$name" == "addons21" || "$name" == "crash.log" || "$name" == "prefs21.db" ]] && continue
    [[ -d "$dir/collection.media" ]] && PROFILES+=("$name")
done < <(find "$ANKI_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo "Error: No Anki profiles found in: $ANKI_BASE"
    echo "Open Anki at least once to create a profile."
    exit 1
fi

# Select profile
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

echo ""
echo "Installing WASM files to: $MEDIA_DIR"

# Copy with underscore prefix and ensure Anki-friendly permissions
cp "$WASM_JS" "$MEDIA_DIR/_marki.js"
cp "$WASM_BG" "$MEDIA_DIR/_marki_bg.wasm"
chmod 644 "$MEDIA_DIR/_marki.js"
chmod 644 "$MEDIA_DIR/_marki_bg.wasm"

echo "  _marki.js      OK"
echo "  _marki_bg.wasm OK"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Open Anki"
echo "2. Go to: Tools -> Manage Note Types -> Add"
echo ""
echo "--- Marki Basic ---"
echo "  Fields: Front, Back"
echo "  Copy the template HTML from:"
if [[ -n "$TEMPLATES_DIR" ]]; then
    echo "    Front template:  $TEMPLATES_DIR/basic-front.html"
    echo "    Back template:   $TEMPLATES_DIR/basic-back.html"
    echo "    Styling (CSS):   $TEMPLATES_DIR/basic-style.css"
else
    echo "    (templates directory not found — see the repo's templates/ folder)"
fi
echo ""
echo "--- Marki Cloze ---"
echo "  Fields: Text, Extra"
echo "  Note type: must be Cloze type (select 'Clone: Cloze' when adding)"
echo "  Copy the template HTML from:"
if [[ -n "$TEMPLATES_DIR" ]]; then
    echo "    Front template:  $TEMPLATES_DIR/cloze-front.html"
    echo "    Back template:   $TEMPLATES_DIR/cloze-back.html"
    echo "    Styling (CSS):   $TEMPLATES_DIR/cloze-style.css"
else
    echo "    (templates directory not found — see the repo's templates/ folder)"
fi
echo ""
echo "Done! Write markdown in your card fields and it will render live."
