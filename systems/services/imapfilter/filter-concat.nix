# systems/services/imapfilter/filter-concat.nix
{ pkgs }:

let
  # Helper function to extract priority from a file
  getPriority = pkgs.writeShellScript "get-priority.sh" ''
    priority=$(sed -n 's/^-- Priority: \([0-9]\+\)$/\1/p' "$1" | head -n 1)
    if [ -z "$priority" ]; then
      echo "9999"  # Default priority for files without a priority specified
    else
      echo "$priority"
    fi
  '';
in
pkgs.stdenv.mkDerivation {
  name = "concatenated-filter-configs";
  src = ./filters;  # Directory containing the .lua files
  buildInputs = [ pkgs.bash ];

  buildPhase = ''
    echo "Debugging: Contents of src directory:"
    ls -la $src

    # Create a temporary file to store file names and priorities
    touch file_priorities.txt

    # Get priorities for all .lua files
    for file in $src/*.lua; do
      if [ -f "$file" ]; then
        priority=$(${getPriority} "$file")
        echo "Processing file: $file with priority: $priority"
        echo "$priority $(basename "$file")" >> file_priorities.txt
      fi
    done

    echo "Debugging: Contents of file_priorities.txt:"
    cat file_priorities.txt

    # Sort files by priority
    sort -n file_priorities.txt > sorted_files.txt

    echo "Debugging: Contents of sorted_files.txt:"
    cat sorted_files.txt
  '';

  installPhase = ''
    mkdir -p $out
    echo "-- Auto-generated concatenated filter configs" > $out/concatenated_filters.lua
    echo "-- Files are ordered by priority (lower numbers first)" >> $out/concatenated_filters.lua
    echo >> $out/concatenated_filters.lua

    while read -r priority filename; do
      file="$src/$filename"
      echo "Processing: $file"
      echo "do -- Start of scope for $filename (Priority: $priority)" >> $out/concatenated_filters.lua
      echo "  -- Contents of $filename:" >> $out/concatenated_filters.lua
      sed 's/^/  /' "$file" >> $out/concatenated_filters.lua  # Indent the contents
      echo "end -- End of scope for $filename" >> $out/concatenated_filters.lua
      echo >> $out/concatenated_filters.lua
    done < sorted_files.txt

    echo "Debugging: Contents of output file:"
    cat $out/concatenated_filters.lua
  '';
}
