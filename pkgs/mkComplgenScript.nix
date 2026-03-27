# Builder: creates a script with auto-generated shell completions via complgen.
# Usage: mkComplgenScript { name = "foo"; scriptContent = "..."; grammar = "..."; runtimeDeps = []; }
{
  lib,
  stdenv,
  complgen,
  makeWrapper,
}: {
  name,
  scriptContent,
  grammar,
  runtimeDeps ? [],
}:
stdenv.mkDerivation {
  pname = name;
  version = "0.1.0";

  nativeBuildInputs = [
    complgen
    makeWrapper
  ];

  buildInputs = runtimeDeps;

  env.grammar = grammar;
  env.scriptContent = scriptContent;

  src = lib.cleanSource ./.;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/share/bash-completion/completions
    mkdir -p $out/share/fish/vendor_completions.d
    mkdir -p $out/share/zsh/site-functions

    echo -n "$scriptContent" > $out/bin/${name}
    chmod +x $out/bin/${name}

    echo -n "$grammar" > grammar.usage

    echo "Generating completions for ${name}..."
    ${complgen}/bin/complgen grammar.usage --bash $out/share/bash-completion/completions/${name}
    ${complgen}/bin/complgen grammar.usage --fish $out/share/fish/vendor_completions.d/${name}.fish
    ${complgen}/bin/complgen grammar.usage --zsh $out/share/zsh/site-functions/_${name}

    if [ ! -s "$out/share/fish/vendor_completions.d/${name}.fish" ]; then
        echo "Error: Fish completion generation likely failed for ${name} (output file empty or missing)."
    fi

    rm grammar.usage

    local rt_path="${lib.makeBinPath runtimeDeps}"
    echo "Wrapping ${name} with PATH: $rt_path"
    wrapProgram $out/bin/${name} --prefix PATH : "$rt_path"

    runHook postInstall
  '';

  meta = {
    description = "Script '${name}' with multi-shell completions via complgen";
    platforms = lib.platforms.all;
  };
}
