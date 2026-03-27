# Builder: creates a nushell script wrapped as an executable.
# Usage: writeNuScript "name" "script content"
{
  nushell,
  writeTextFile,
}: name: script:
writeTextFile rec {
  inherit name;
  text = "#!${nushell}/bin/nu" + "\n" + script;
  executable = true;
  destination = "/bin/${name}";
}
