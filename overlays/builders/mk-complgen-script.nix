# Builder: script + auto-generated {bash,fish,zsh} completions via complgen.
#
# Usage (bash script):
#   mkComplgenScript { name = "foo"; text = "..."; grammar = "foo <PATH>;"; runtimeInputs = [ ]; }
#
# Usage (any pre-built script package, e.g. Python):
#   mkComplgenScript { name = "foo"; package = writers.writePython3Bin "foo" { } "..."; grammar = "..."; }
{
  lib,
  symlinkJoin,
  writeShellApplication,
  runCommand,
  complgen,
}:
{
  name,
  grammar,
  text ? null,
  runtimeInputs ? [ ],
  package ? writeShellApplication { inherit name runtimeInputs text; },
}:
symlinkJoin {
  inherit name;
  paths = [
    package
    (runCommand "${name}-completions"
      {
        inherit grammar;
        passAsFile = [ "grammar" ];
        nativeBuildInputs = [ complgen ];
      }
      ''
        mkdir -p $out/share/bash-completion/completions \
                 $out/share/fish/vendor_completions.d \
                 $out/share/zsh/site-functions

        # complgen 0.11 accepts exactly one shell flag per invocation
        complgen "$grammarPath" --bash $out/share/bash-completion/completions/${name}
        complgen "$grammarPath" --fish $out/share/fish/vendor_completions.d/${name}.fish
        complgen "$grammarPath" --zsh $out/share/zsh/site-functions/_${name}

        for f in $out/share/bash-completion/completions/${name} \
                 $out/share/fish/vendor_completions.d/${name}.fish \
                 $out/share/zsh/site-functions/_${name}; do
          [ -s "$f" ] || { echo "error: empty completion script: $f" >&2; exit 1; }
        done
      ''
    )
  ];
  meta.description = "Script '${name}' with multi-shell completions via complgen";
}
