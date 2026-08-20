# Builder: creates a lua script wrapped as an executable.
# Usage: writeLuaScript "name" "script content"
{
  lua,
  writeTextFile,
}: name: script:
writeTextFile {
  inherit name;
  text = ''
    #!${lua}/bin/lua
    ${script}
  '';
  executable = true;
  destination = "/bin/${name}";
}
