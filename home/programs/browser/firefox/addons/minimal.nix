{ inputs, pkgs }:
let
  addons = inputs.firefox-addons.packages.${pkgs.system};
in
with addons; [
  # Privacy and Security
  ublock-origin
  bitwarden

  # Appearance / functionality
  darkreader
  nighttab

  # Privacy / Security
  smart-referer

  # Quality of life
  translate-web-pages

  # remove tabs completely
  adsum-notabs

  violentmonkey
]
