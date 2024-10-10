{ theme, firefox-csshacks, colorLib }:
let
  # Convert hex to OKLCH
  hexToOklch = hexColor: colorLib.hexStrToOklch hexColor;

  # Modify OKLCH colors
  setLightness = value: color: colorLib.oklchmod.setLightness value color;
  setChroma = value: color: colorLib.oklchmod.setChroma value color;

  # Convert OKLCH back to hex
  oklchToHex = oklchColor: colorLib.oklchToHex oklchColor;

  # Theme colors in OKLCH
  primary = hexToOklch theme.primary;
  neutral = hexToOklch theme.neutral;
in
''
  /* Sidebar customization */
  #sidebar-box {
    --uc-autohide-sidebar-delay: 100ms;
    --uc-autohide-transition-duration: 215ms;
    --uc-sidebar-width: var(--sidebar-width);
    --uc-sidebar-hover-width: 25vw;
    --uc-autohide-transition-type: ease-in-out;
    background-color: ${oklchToHex (setLightness 0.3 primary)} !important;
    foreground-color: ${oklchToHex (setLightness 0.95 neutral)} !important;
  }

  /* URL bar and panel options */
  :root {
    --sidebar-width: 40px;
    --panel-width: 100vw; /* URL bar width */
    --panel-hide-offset: -30px;
    --opacity-when-hidden: 0.0;
  }

  /* Remove the sidebar header */
  #sidebar-header {
    display: none;
  }

  /* Sidebar color settings */
  #sidebar-header,
  #sidebar-search-container,
  #bookmarks-view-children,
  #historyTree {
    color: ${oklchToHex (setLightness 0.95 neutral)} !important;
    background-color: ${oklchToHex (setLightness 0.35 primary)} !important;
    foreground-color: ${oklchToHex (setLightness 0.95 neutral)} !important;
    -moz-appearance: none !important;
    border-color: transparent !important;
  }

  /* Search box in the sidebar */
  .sidebar-panel #search-box {
    background-color: ${oklchToHex (setLightness 0.25 primary)} !important;
    foreground-color: ${oklchToHex (setLightness 0.95 neutral)} !important;
    color: ${oklchToHex (setLightness 0.95 neutral)} !important;
  }

  /* Sidebar and header background settings */
  #sidebar,
  #sidebar-header {
    background-color: ${oklchToHex (setLightness 0.3 primary)} !important;
    foreground-color: ${oklchToHex (setLightness 0.95 neutral)} !important;
    color: ${oklchToHex (setLightness 0.95 neutral)} !important;
    border-bottom: none !important;
    background-image: var(--lwt-additional-images);
    background-position: auto;
    background-size: auto;
    background-repeat: no-repeat;
  }
''
