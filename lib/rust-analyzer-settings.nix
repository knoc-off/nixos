# rust-analyzer settings, shared by every client that may open an lspmux
# session.
#
# lspmux hands the *first* client's `initializationOptions` to the language
# server and replays the resulting initialize response to everyone who joins
# later -- later clients' settings are discarded (see instance.rs, the
# `initialize_handshake` comment). Once neovim and the sandboxed opencode share
# one instance, whichever connects first decides the configuration for both, so
# they have to propose the same thing or the result depends on a race.
#
# Consumed by:
#   * pkgs/neovim/configurations/modules/languages/rust.nix (rustaceanvim
#     `server.default_settings`)
#   * modules/opencode.nix (`lsp.rust.initialization`)
#
# `cargo.target` is deliberately absent: it is per-session and neovim injects it
# at startup from the session metadata. opencode's config is static JSON and
# can't, so if opencode wins the race a cross session indexes for the native
# target. Recover with `lspmux-session kill <name>` and reattach from neovim.
{
  rust-analyzer = {
    imports = {
      granularity.group = "module";
      prefix = "self";
    };

    cargo = {
      allFeatures = false;
      allTargets = false;
      buildScripts.enable = true;
      loadOutDirsFromCheck = true;
      # Separate target dir prevents cargo build from invalidating RA cache
      targetDir = "target/rust-analyzer";
    };

    # Exclude directories from file watching (reduces inotify load)
    files = {
      excludeDirs = [
        ".direnv"
        ".git"
        "target"
        "node_modules"
        ".cargo"
      ];
    };

    lru.capacity = 256;

    checkOnSave = true;
    # check.allTargets is separate from cargo.allTargets above and
    # defaults true, expanding checks to `--all-targets` + one rustc per core.
    check = {
      allTargets = false;
      extraArgs = [ "-j4" ];
    };
    # Defaults to core count.
    numThreads = 8;
    diagnostics = {
      enable = true;
      enableExperimental = false;
    };

    inlayHints = {
      enable = true;
      typeHints = {
        enable = true;
        hideClosureInitialization = false;
        hideNamedConstructor = false;
      };
      parameterHints.enable = true;
      chainingHints.enable = true;
      closingBraceHints = {
        enable = true;
        minLines = 25;
      };
      lifetimeElisionHints = {
        enable = "skip_trivial";
        useParameterNames = true;
      };
    };

    completion = {
      addCallArgumentSnippets = true;
      addCallParenthesis = true;
      postfix.enable = true;
      autoimport.enable = true;
      fullFunctionSignatures.enable = true;
    };

    procMacro.enable = true;

    typing.continueCommentsOnNewline = false;

    lens = {
      enable = true;
      references = {
        adt.enable = true;
        enumVariant.enable = true;
        method.enable = true;
        trait.enable = true;
      };
      run.enable = true;
      debug.enable = true;
      implementations.enable = true;
    };

    hover = {
      actions = {
        enable = true;
        references.enable = true;
        run.enable = true;
        debug.enable = true;
        gotoTypeDef.enable = true;
        implementations.enable = true;
      };
      documentation.enable = true;
      links.enable = true;
    };

    semanticHighlighting = {
      operator.specialization.enable = true;
      punctuation = {
        enable = true;
        specialization.enable = true;
      };
    };
  };
}
