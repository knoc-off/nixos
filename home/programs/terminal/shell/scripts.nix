{ pkgs, lib, ... }:
let
  nu =
  (name:
    (script:
      pkgs.writeTextFile rec {
        inherit name;
        text = ( "#!${pkgs.nushell}/bin/nu" + "\n" + script);

        executable = true;
        destination = "/bin/${name}";
      }
    )
  );
in
{

  home.packages = with pkgs; [
    (nu "nxx"
     ''
        def main [text: string] {

        }
      ''
    )
  ];
}
