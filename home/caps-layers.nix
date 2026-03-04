# Declarative per-window caps remapping.
#
# When caps (rmet via kanata) is held, keys can be remapped to send
# different modifiers, different keys, commands, or raw kanata actions.
# Unlisted keys pass through as Super_R+key (triggering Hyprland WM binds).
#
# "base" is the wildcard fallback for windows not matching any other class.
#
# Each layer supports two forms that merge together (keys takes priority):
#
#   Bulk shorthand:  ctrl = ["a" "b" "c"];   alt = ["1" "2" "3"];
#   Per-key actions: keys = { a = "ctrl"; b = { mod = "shift"; key = "z"; }; };
#
# Per-key action values:
#   "ctrl" / "shift" / "alt"        -> modifier + same key  (shorthand string)
#   { mod = "ctrl"; }               -> modifier + same key  (explicit)
#   { key = "z"; }                  -> bare key, no modifier
#   { mod = "shift"; key = "z"; }   -> modifier + different key
#   { cmd = "some-command"; }       -> run a command
#   { raw = "(tap-hold 200 ...)"; } -> raw kanata action (escape hatch)
#
# Example:
#   result = mkCapsLayers {
#     base = {
#       ctrl = ["a" "b" "c" "h" "j" "k" "l"];
#       keys = {
#         F5  = { cmd = "notify-send hello"; };
#         x   = { raw = "(tap-hold 200 200 C-x C-S-x)"; };
#       };
#     };
#     browser = {
#       classes = ["firefox" "chromium-browser"];
#       ctrl = ["a" "c" "f" "h" "j" "k" "l" "t" "v" "w"];
#       alt = ["1" "2" "3" "4" "5"];
#     };
#     terminal = {
#       classes = ["com.mitchellh.ghostty" "foot"];
#       ctrl = ["h" "j" "k"];
#     };
#   };
#
#   result.hyprkanRules   -- list of hyprkan rule attrsets
#   result.kanataConfig   -- function: extraAliases string -> kanata config string
{lib}: let
  modPrefix = {
    ctrl = "C";
    shift = "S";
    alt = "A";
  };
  modNames = builtins.attrNames modPrefix;

  # Normalize a per-key action value into a canonical attrset
  normalizeAction = keyName: action:
    if builtins.isString action
    then
      # String shorthand: "ctrl" -> { mod = "ctrl"; }
      {mod = action;}
    else if action ? raw
    then action
    else if action ? cmd
    then action
    else
      # Attrset with mod and/or key
      action;

  # Compile a normalized action into a kanata expression
  compileAction = keyName: action:
    if action ? raw
    then action.raw
    else if action ? cmd
    then "(cmd ${action.cmd})"
    else let
      targetKey = action.key or keyName;
      modded =
        if action ? mod
        then "${modPrefix.${action.mod}}-${targetKey}"
        else targetKey;
    in "(multi (release-key rmet) ${modded})";

  # Expand a layer's bulk lists + per-key overrides into a flat { key = action; } map
  normalizeLayer = layer: let
    # Expand bulk modifier lists: ctrl = ["a" "b"] -> { a = { mod = "ctrl"; }; b = { mod = "ctrl"; }; }
    bulkEntries =
      lib.foldl' (
        acc: mod:
          if layer ? ${mod}
          then acc // lib.genAttrs layer.${mod} (_: {inherit mod;})
          else acc
      ) {}
      modNames;

    # Per-key overrides (normalized)
    keyEntries = lib.mapAttrs normalizeAction (layer.keys or {});
  in
    # keys takes priority over bulk
    bulkEntries // keyEntries;
in
  layers: let
    layerNames = builtins.attrNames layers;

    # Normalize all layers into { layerName = { key = canonicalAction; }; }
    normalized = lib.mapAttrs (_: normalizeLayer) layers;

    # Collect all unique compiled actions for alias generation
    # Each alias is a unique (keyName, compiledAction) pair
    allAliases = let
      pairs = lib.concatLists (lib.mapAttrsToList (
          _: keyMap:
            lib.mapAttrsToList (keyName: action: {
              inherit keyName action;
              compiled = compileAction keyName action;
            })
            keyMap
        )
        normalized);
    in
      lib.foldl' (
        acc: pair: let
          name = "caps-${pair.keyName}-${builtins.hashString "md5" pair.compiled}";
        in
          if acc ? ${name}
          then acc
          else acc // {${name} = pair;}
      ) {}
      pairs;

    getAliasName = keyName: action: let
      compiled = compileAction keyName action;
    in "caps-${keyName}-${builtins.hashString "md5" compiled}";

    # Generate alias definitions
    aliasLines = lib.concatStringsSep "\n      " (
      lib.mapAttrsToList (name: pair: "${name} ${pair.compiled}") allAliases
    );

    # Generate deflayermap entries for a normalized layer
    mkLayermap = keyMap:
      lib.concatStringsSep "  " (
        lib.mapAttrsToList (
          keyName: action: "${keyName} @${getAliasName keyName action}"
        )
        keyMap
      );
  in {
    hyprkanRules =
      (lib.concatLists (lib.mapAttrsToList (
        name: layer:
          map (class: {
            inherit class;
            layer = name;
          }) (layer.classes or [])
      ) (lib.filterAttrs (n: _: n != "base") layers)))
      ++ [
        {
          class = "*";
          title = "*";
          layer = "base";
        }
      ];

    kanataConfig = extraAliases: ''
      (defalias
        ${extraAliases}

        ${lib.concatStringsSep "\n      " (map (n: "cap-${n} (multi rmet @dbl (layer-while-held shortcuts-${n}))") layerNames)}

        ${aliasLines}
      )

      (defsrc caps)
      ${lib.concatStringsSep "\n    " (map (n: "(deflayer ${n} @cap-${n})") layerNames)}

      ${lib.concatStringsSep "\n    " (map (n: "(deflayermap (shortcuts-${n})\n      ${mkLayermap normalized.${n}}\n    )") layerNames)}
    '';
  }
