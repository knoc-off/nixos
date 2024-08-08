# systems/services/imapfilter/filter-concat.nix
{ pkgs }:

pkgs.stdenv.mkDerivation {
  name = "concatenated-filter-configs";
  src = ./filters;  # Directory containing the .lua files
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    # Do nothing in build phase, we'll do everything in installPhase
  '';

  installPhase = ''
    mkdir -p $out
    echo "-- Auto-generated concatenated filter configs" > $out/concatenated_filters.lua
    echo "-- Each filter is wrapped in its own scope" >> $out/concatenated_filters.lua
    echo >> $out/concatenated_filters.lua

    for file in $src/*.lua; do
      if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "do -- Start of scope for $filename" >> $out/concatenated_filters.lua
        echo "  -- Contents of $filename:" >> $out/concatenated_filters.lua
        sed 's/^/  /' "$file" >> $out/concatenated_filters.lua  # Indent the contents
        echo "end -- End of scope for $filename" >> $out/concatenated_filters.lua
        echo >> $out/concatenated_filters.lua
      fi
    done
  '';
}
