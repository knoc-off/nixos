{ lib, theme, colorLib}:

{ enableSmoothScroll ? false
, enableDarkTheme ? false
, enablePrivacy ? false
, enablePerformance ? false
, enableCustomUI ? false
, extraSettings ? {}
}:

let
  baseSettings = import ./base.nix;
  smoothScrollSettings = import ./smooth_scroll.nix;
  themeSettings = import ./theme.nix { inherit theme colorLib; };
  privacySettings = import ./privacy.nix;
  performanceSettings = import ./performance.nix;
  uiCustomizationSettings = import ./ui_customization.nix;
in
lib.mkMerge ([
  baseSettings
] ++
  lib.optional enableSmoothScroll smoothScrollSettings ++
  lib.optional enableDarkTheme themeSettings ++
  lib.optional enablePrivacy privacySettings ++
  lib.optional enablePerformance performanceSettings ++
  lib.optional enableCustomUI uiCustomizationSettings ++
  [ extraSettings ]
)
