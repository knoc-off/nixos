{
  lib,
  php,
  fetchFromGitHub,
}:
let
  # gd and apcu are not in the default set; the rest (opcache, mbstring,
  # dom, xml, filter, curl) are already enabled by default in nixpkgs PHP.
  phpWithExtensions = php.withExtensions ({ enabled, all }:
    enabled
    ++ [
      all.gd
      all.apcu
    ]);
in
phpWithExtensions.buildComposerProject2 (finalAttrs: {
  pname = "upvote-rss";
  version = "1.8.1";

  src = fetchFromGitHub {
    owner = "johnwarne";
    repo = "upvote-rss";
    tag = "v${finalAttrs.version}";
    hash = "sha256-8YaUQiqp6D2LNrjqp5lWyzPy2FvPwc8t4AC/YjnDl5A=";
  };

  composerStrictValidation = false;

  vendorHash = "sha256-R28rEshhDH2HpYHzK4SPF2UPONPmSjmJz2OEUV43R3U=";

  php = phpWithExtensions;

  # The app is not a CLI tool — it's a web application.
  # We need to install the entire source tree, not just vendor/bin.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/upvote-rss
    cp -r . $out/share/upvote-rss/

    # Remove Docker/dev files that aren't needed at runtime
    rm -rf $out/share/upvote-rss/docker
    rm -rf $out/share/upvote-rss/node_modules
    rm -rf $out/share/upvote-rss/.github
    rm -rf $out/share/upvote-rss/gulpfile.js
    rm -rf $out/share/upvote-rss/package.json
    rm -rf $out/share/upvote-rss/package-lock.json

    # Remove mutable directories — the NixOS module will symlink
    # these from the state directory at runtime
    rm -rf $out/share/upvote-rss/cache
    rm -rf $out/share/upvote-rss/logs

    runHook postInstall
  '';

  meta = {
    description = "Generate RSS feeds from Reddit, Hacker News, Lobsters, Lemmy, and more with optional AI summaries";
    homepage = "https://github.com/johnwarne/upvote-rss";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
