# Declarative per-window key remapping for kanata + hyprkan.
#
# When caps (rmet via kanata) is held, keys can be remapped via capsbinds.
# Keys can also be unconditionally remapped per-window via binds.
# Unlisted keys pass through as Super_R+key (triggering Hyprland WM binds).
#
# "base" is the wildcard fallback for windows not matching any other class/title.
#
# Layers can match windows by class, title, or both:
#   classes  = ["firefox" "chromium-browser"];
#   titles   = ["DevTools" "Inspector"];
#   matchers = [{ class = "firefox"; title = "DevTools"; }];
#
# capsbinds: keys remapped when caps is held
#   Bulk shorthand:  ctrl = ["a" "b" "c"];   alt = ["1" "2" "3"];
#   Per-key actions:  keys = { a = "ctrl"; b = { mod = "shift"; key = "z"; }; };
#
#   Per-key action values (string = modifier shorthand):
#     "ctrl" / "shift" / "alt"        -> modifier + same key
#     { mod = "ctrl"; }               -> modifier + same key  (explicit)
#     { key = "z"; }                  -> bare key, no modifier
#     { mod = "shift"; key = "z"; }   -> modifier + different key
#     { cmd = "some-command"; }       -> run a command
#     { raw = "(tap-hold 200 ...)"; } -> raw kanata action (escape hatch)
#
# binds: keys remapped unconditionally (no caps required)
#   Simple values (string = target key):
#     tab = "down";                         -> remap tab to down
#     esc = "nop";                          -> disable esc (kanata's nop)
#   Action attrsets:
#     f1 = { key = "f2"; };                -> explicit remap
#     f3 = { mod = "ctrl"; key = "t"; };   -> emit ctrl+t when f3 pressed
#     f5 = { cmd = "notify-send hi"; };    -> run a command
#     f6 = { raw = "(tap-hold ...)"; };    -> raw kanata (escape hatch)
#   Forks (conditional on held modifiers):
#     tab = { default = "down"; shift = "up"; };
#     tab = { default = { mod = "ctrl"; key = "t"; }; shift = { raw = "..."; }; };
#
#   Fork fields: default, shift, ctrl, alt, ctrl_shift, alt_ctrl,
#                alt_shift, alt_ctrl_shift
#   Fork values accept the same action types as simple binds.
#   Priority: shift > ctrl > alt (unspecified compounds inherit from
#   the highest-priority matching single modifier).
#
# Example:
#   result = mkKeyLayers {
#     base = {
#       capsbinds = {
#         ctrl = ["a" "b" "c"];
#         keys = {
#           h = { key = "left"; };
#           F5 = { cmd = "notify-send hello"; };
#         };
#       };
#     };
#     browser = {
#       classes = ["firefox" "chromium-browser"];
#       capsbinds = {
#         ctrl = ["a" "c" "f" "t" "v" "w"];
#       };
#       binds = {
#         tab = { default = "down"; shift = "up"; };
#       };
#     };
#     terminal = {
#       classes = ["com.mitchellh.ghostty" "foot"];
#       capsbinds = {
#         alt = ["e"];
#         keys = { h = { key = "left"; }; };
#       };
#     };
#   };
#
#   result.hyprkanRules   -- list of hyprkan rule attrsets
#   result.kanataConfig   -- function: extraAliases string -> kanata config string
{lib}: let
  # --- Modifier configuration ---
  modPrefix = {
    ctrl = "C";
    shift = "S";
    alt = "A";
  };
  modNames = builtins.attrNames modPrefix;

  # --- Fork configuration ---
  # Check order determines priority: shift > ctrl > alt
  modCheckOrder = ["shift" "ctrl" "alt"];
  modForkKeys = {
    shift = "(lsft rsft)";
    ctrl = "(lctl rctl)";
    alt = "(lalt ralt)";
  };
  forkFields = [
    "default"
    "shift"
    "ctrl"
    "alt"
    "alt_ctrl"
    "alt_shift"
    "ctrl_shift"
    "alt_ctrl_shift"
  ];

  # --- Detection ---
  # An attrset is a fork if it has fork fields and NO simple action fields.
  isFork = value:
    builtins.isAttrs value
    && !(value ? raw)
    && !(value ? cmd)
    && !(value ? key)
    && !(value ? mod)
    && builtins.any (field: value ? ${field}) forkFields;

  # --- Shared key expression compilation ---
  # Core compilation used by both capsbinds and binds.
  compileKeyExpr = keyName: action:
    if action ? raw
    then action.raw
    else if action ? cmd
    then "(cmd ${action.cmd})"
    else let
      targetKey = action.key or keyName;
    in
      if action ? mod
      then "${modPrefix.${action.mod}}-${targetKey}"
      else targetKey;

  # Caps: wraps non-raw/cmd expressions with (multi (release-key rmet) ...)
  # because caps/rmet is physically held during these actions.
  compileCapsAction = keyName: action: let
    base = compileKeyExpr keyName action;
  in
    if action ? raw || action ? cmd
    then base
    else "(multi (release-key rmet) ${base})";

  # --- Normalization ---
  # In capsbinds, string shorthand = modifier name: "ctrl" -> { mod = "ctrl"; }
  normalizeCapsAction = keyName: action:
    if builtins.isString action
    then {mod = action;}
    else action;

  # In binds, string shorthand = target key name: "down" -> { key = "down"; }
  normalizeBindAction = keyName: action:
    if builtins.isString action
    then {key = action;}
    else action;

  # --- Fork compilation ---
  # Canonical name for a set of held modifiers (sorted alphabetically).
  modComboName = mods:
    if mods == []
    then "default"
    else lib.concatStringsSep "_" (builtins.sort (a: b: a < b) mods);

  # Build a kanata fork expression from a fork definition.
  # Generates a nested fork tree checking shift, then ctrl, then alt.
  # Unspecified compounds fall back to the highest-priority matching
  # single modifier (priority: shift > ctrl > alt), then to default,
  # then to passthrough (the base key).
  compileFork = keyName: forkDef: let
    # Resolve the action for a specific set of held modifiers.
    # Falls back by removing the lowest-priority held modifier until a match.
    resolveAction = heldMods: let
      tryMatch = mods: let
        name = modComboName mods;
      in
        if forkDef ? ${name}
        then forkDef.${name}
        else let
          reversed = lib.reverseList modCheckOrder;
          lowest = lib.findFirst (m: builtins.elem m mods) null reversed;
        in
          if lowest == null
          then null
          else tryMatch (builtins.filter (m: m != lowest) mods);
      actionValue = tryMatch heldMods;
    in
      if actionValue == null
      then keyName
      else compileKeyExpr keyName (normalizeBindAction keyName actionValue);

    # Recursively build the fork tree.
    # At each level, check one modifier. If both branches produce
    # the same output, the fork is optimized away.
    buildTree = heldMods: remainingMods:
      if remainingMods == []
      then resolveAction heldMods
      else let
        mod = builtins.head remainingMods;
        rest = builtins.tail remainingMods;
        withoutMod = buildTree heldMods rest;
        withMod = buildTree (heldMods ++ [mod]) rest;
      in
        if withoutMod == withMod
        then withoutMod
        else "(fork ${withoutMod} ${withMod} ${modForkKeys.${mod}})";
  in
    buildTree [] modCheckOrder;

  # --- Bind compilation (dispatches to simple or fork) ---
  compileBind = keyName: value:
    if isFork value
    then compileFork keyName value
    else compileKeyExpr keyName (normalizeBindAction keyName value);

  # --- Capsbinds normalization ---
  # Expands bulk modifier lists + per-key overrides into { key = action; }
  normalizeCapsBinds = capsbinds: let
    bulkEntries =
      lib.foldl' (
        acc: mod:
          if capsbinds ? ${mod}
          then acc // lib.genAttrs capsbinds.${mod} (_: {inherit mod;})
          else acc
      ) {}
      modNames;

    keyEntries = lib.mapAttrs normalizeCapsAction (capsbinds.keys or {});
  in
    # keys takes priority over bulk
    bulkEntries // keyEntries;
in
  layers: let
    layerNames = builtins.attrNames layers;

    # --- Normalize capsbinds for all layers ---
    normalizedCaps =
      lib.mapAttrs (
        _: layer:
          normalizeCapsBinds (layer.capsbinds or {})
      )
      layers;

    # --- Caps alias generation ---
    allCapsAliases = let
      pairs = lib.concatLists (lib.mapAttrsToList (
          _: keyMap:
            lib.mapAttrsToList (keyName: action: {
              inherit keyName action;
              compiled = compileCapsAction keyName action;
            })
            keyMap
        )
        normalizedCaps);
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

    getCapsAliasName = keyName: action: let
      compiled = compileCapsAction keyName action;
    in "caps-${keyName}-${builtins.hashString "md5" compiled}";

    capsAliasLines =
      lib.mapAttrsToList (name: pair: "${name} ${pair.compiled}") allCapsAliases;

    # --- Bind alias generation ---
    allBindAliases = let
      pairs = lib.concatLists (lib.mapAttrsToList (
          _: layer:
            lib.mapAttrsToList (keyName: value: {
              inherit keyName value;
              compiled = compileBind keyName value;
            })
            (layer.binds or {})
        )
        layers);
    in
      lib.foldl' (
        acc: pair: let
          name = "remap-${pair.keyName}-${builtins.hashString "md5" pair.compiled}";
        in
          if acc ? ${name}
          then acc
          else acc // {${name} = pair;}
      ) {}
      pairs;

    getBindAliasName = keyName: value: let
      compiled = compileBind keyName value;
    in "remap-${keyName}-${builtins.hashString "md5" compiled}";

    bindAliasLines =
      lib.mapAttrsToList (name: pair: "${name} ${pair.compiled}") allBindAliases;

    # Combined alias lines
    allAliasLines = capsAliasLines ++ bindAliasLines;

    # --- Layermap generation ---
    mkCapsLayermap = keyMap:
      lib.concatStringsSep "  " (
        lib.mapAttrsToList (
          keyName: action: "${keyName} @${getCapsAliasName keyName action}"
        )
        keyMap
      );

    mkBindEntries = layer:
      lib.concatStringsSep "\n      " (
        lib.mapAttrsToList (
          keyName: value: "${keyName} @${getBindAliasName keyName value}"
        )
        (layer.binds or {})
      );
  in {
    hyprkanRules = let
      nonBase = lib.filterAttrs (n: _: n != "base") layers;
    in
      (lib.concatLists (lib.mapAttrsToList (
          name: layer: let
            classRules = map (class: {
              inherit class;
              layer = name;
            }) (layer.classes or []);

            titleRules = map (title: {
              inherit title;
              layer = name;
            }) (layer.titles or []);

            matcherRules = map (m:
              {layer = name;}
              // lib.optionalAttrs (m ? class) {inherit (m) class;}
              // lib.optionalAttrs (m ? title) {inherit (m) title;})
            (layer.matchers or []);
          in
            matcherRules ++ classRules ++ titleRules
        )
        nonBase))
      ++ [
        {
          class = "*";
          title = "*";
          layer = "base";
        }
      ];

    kanataConfig = extraAliases: let
      hasBinds = n: (layers.${n}.binds or {}) != {};
      bindEntries = n: mkBindEntries layers.${n};
    in ''
      (defalias
        ${extraAliases}

        ${lib.concatStringsSep "\n      " (map (n: "cap-${n} (multi rmet @dbl (layer-while-held shortcuts-${n}))") layerNames)}

        ${lib.concatStringsSep "\n      " allAliasLines}
      )

      (defsrc caps)
      ${lib.concatStringsSep "\n    " (map (
          n:
            "(deflayermap (${n})\n      caps @cap-${n}"
            + lib.optionalString (hasBinds n) "\n      ${bindEntries n}"
            + "\n    )"
        )
        layerNames)}

      ${lib.concatStringsSep "\n    " (map (n: "(deflayermap (shortcuts-${n})\n      ${mkCapsLayermap normalizedCaps.${n}}\n    )") layerNames)}
    '';
  }
