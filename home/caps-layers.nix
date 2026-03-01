# Declarative per-window caps behavior.
# When caps (rmet via kanata) is held, listed keys send the specified
# modifier instead of Super_R. Unlisted keys pass through as Super_R+key
# (triggering Hyprland WM binds).
#
# "base" is the wildcard fallback for windows not matching any other class.
# Supports: ctrl, shift, alt as target modifiers.
#
# Usage:
#   capsLayers = {
#     terminal = {
#       classes = ["com.mitchellh.ghostty" "foot"];
#       ctrl = ["h" "j" "k"];
#     };
#     browser = {
#       classes = ["firefox" "chromium-browser"];
#       ctrl = ["a" "b" "c" "f" "h" "i" "j" "k" "l"];
#       alt = ["1" "2" "3"];  # caps+1 → Alt+1 in browsers
#     };
#     base = {
#       ctrl = ["a" "b" "c" "f" "h" "i" "j" "k" "l"];
#     };
#   };
#
#   result = mkCapsLayers { inherit lib; layers = capsLayers; };
#   result.hyprkanRules   -- list of hyprkan rule attrsets
#   result.kanataConfig   -- kanata config string
{ lib }:
let
  modPrefix = { ctrl = "C"; shift = "S"; alt = "A"; };
  modNames = builtins.attrNames modPrefix;
in
layers:
let
  layerNames = builtins.attrNames layers;

  # Extract only modifier attrs from a layer (filter out "classes")
  layerMods = layer: lib.filterAttrs (n: _: builtins.elem n modNames) layer;

  # Collect every unique (mod, key) pair across all layers for alias generation
  allPairs = lib.unique (lib.concatLists (lib.mapAttrsToList (_: layer:
    lib.concatLists (lib.mapAttrsToList (mod: keys:
      map (k: { inherit mod k; }) keys
    ) (layerMods layer))
  ) layers));

  aliasName = mod: k: "r${modPrefix.${mod}}-${k}";
  mkAlias = { mod, k }: "${aliasName mod k} (multi (release-key rmet) ${modPrefix.${mod}}-${k})";
  mkLayermap = layer: lib.concatStringsSep "  " (
    lib.concatLists (lib.mapAttrsToList (mod: keys:
      map (k: "${k} @${aliasName mod k}") keys
    ) (layerMods layer))
  );
in {
  hyprkanRules =
    (lib.concatLists (lib.mapAttrsToList (name: layer:
      map (class: { inherit class; layer = name; }) (layer.classes or [])
    ) (lib.filterAttrs (n: _: n != "base") layers)))
    ++ [{ class = "*"; title = "*"; layer = "base"; }];

  kanataConfig = extraAliases: ''
    (defalias
      ${extraAliases}

      ${lib.concatStringsSep "\n      " (map (n: "cap-${n} (multi rmet @dbl (layer-while-held shortcuts-${n}))") layerNames)}

      ${lib.concatStringsSep "\n      " (map mkAlias allPairs)}
    )

    (defsrc caps)
    ${lib.concatStringsSep "\n    " (map (n: "(deflayer ${n} @cap-${n})") layerNames)}

    ${lib.concatStringsSep "\n    " (map (n: "(deflayermap (shortcuts-${n})\n      ${mkLayermap layers.${n}}\n    )") layerNames)}
  '';
}
