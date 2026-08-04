# lspmux - LSP multiplexer
# NixOS side: systemd service + system package
# HM side: config file generation (TOML)
{ inputs, self }: let
  lspmuxPkg = system: self.packages.${system}.lspmux;

  # Environment passed through to spawned language servers.
  #
  # lspmux keys each server instance on (server, args, env, workspace_root), so
  # this list is doing double duty: it decides what the server can see *and*
  # how many instances get spawned. Two rules follow from that:
  #
  #   1. Never pass session-scoped vars (WAYLAND_DISPLAY, STARSHIP_SESSION_KEY,
  #      HYPRLAND_INSTANCE_SIGNATURE, ...). They differ per terminal, so each
  #      editor would get its own rust-analyzer -- defeating the multiplexer.
  #   2. Never pass secrets. This is why it's an allowlist rather than
  #      ["*" "!VOLATILE_*"]: a nix devshell environment routinely contains
  #      sops-provided API keys.
  #
  # Patterns are globs; a leading "!" negates. Matching is "at least one
  # positive and no negatives", so negatives always win regardless of order.
  # Consumers may append their own entries -- the list type concatenates.
  defaultPassEnvironment = [
    # Basic runtime
    "HOME"
    "PATH"
    "CONFIG_SHELL"
    "SOURCE_DATE_EPOCH"

    # Rust / Cargo. CARGO_* also covers the per-triple
    # CARGO_TARGET_<TRIPLE>_{LINKER,RUSTFLAGS,RUNNER} overrides that cross
    # devshells set, which cross-target rust-analyzer instances need.
    #
    # CARGO_TARGET_DIR is excluded on purpose: rust-analyzer has its own
    # targetDir (see the rustaceanvim config) and must not share a build
    # directory with interactive cargo invocations.
    "CARGO_*"
    "!CARGO_TARGET_DIR"
    "RUSTFLAGS"
    "RUSTUP_HOME"
    "RUST_SRC_PATH"

    # Selects the cargo target for cross-target rust-analyzer instances.
    # Set by :RustTarget in the neovim config; its presence in the env is
    # what makes lspmux spawn a separate instance per target.
    "RA_TARGET"

    "SQLX_OFFLINE"
    "DATABASE_URL"

    # Native toolchain
    "CC"
    "CXX"
    "AR"
    "AS"
    "LD"
    "RANLIB"
    "NM"
    "OBJCOPY"
    "OBJDUMP"
    "READELF"
    "STRIP"
    "SIZE"
    "STRINGS"

    "CFLAGS"
    "CXXFLAGS"
    "CPPFLAGS"
    "LDFLAGS"
    "CL_FLAGS"

    # Per-triple compiler/flag overrides, e.g. CC_x86_64_pc_windows_gnu,
    # CFLAGS_x86_64_pc_windows_gnu. Deliberately no "LD_*" glob -- it would
    # match LD_PRELOAD; LD_LIBRARY_PATH is listed explicitly below.
    "CC_*"
    "CXX_*"
    "CFLAGS_*"
    "CXXFLAGS_*"
    "LDFLAGS_*"
    "AR_*"
    "RANLIB_*"
    "WINDRES*"
    "DLLTOOL*"

    # Build-platform counterparts (CC_FOR_BUILD, AR_FOR_BUILD,
    # NIX_CFLAGS_COMPILE_FOR_BUILD, ...) set by cross stdenvs.
    "*_FOR_BUILD"
    "HOST_CC"
    "HOST_PATH"

    "PKG_CONFIG"
    "PKG_CONFIG_PATH"
    "PKG_CONFIG_LIBDIR"
    "PKG_CONFIG_SYSROOT_DIR"

    "CMAKE_INCLUDE_PATH"
    "CMAKE_LIBRARY_PATH"
    "NIXPKGS_CMAKE_PREFIX_PATH"

    "LD_LIBRARY_PATH"
    "NIX_LD"
    "NIX_LD_LIBRARY_PATH"

    "NIX_CC"
    "NIX_BINTOOLS"
    "NIX_CFLAGS_COMPILE"
    "NIX_LDFLAGS"
    "NIX_HARDENING_ENABLE"
    "NIX_ENFORCE_NO_NATIVE"

    # Wrapper setup markers. Globbed rather than pinned to a single triple so
    # cross devshells' _BUILD_ variants (e.g. ..._TARGET_BUILD_x86_64_w64_mingw32)
    # come along too -- without them the cc wrapper skips its flag injection.
    "NIX_CC_WRAPPER_TARGET_*"
    "NIX_BINTOOLS_WRAPPER_TARGET_*"
    "NIX_PKG_CONFIG_WRAPPER_TARGET_*"

    "NIX_STORE"
    "NIX_SSL_CERT_FILE"
    "NIX_PATH"
    "NIX_PROFILES"
    "NIX_USER_PROFILE_DIR"
    "IN_NIX_SHELL"

    # Project build scripts (AWS-LC, windows DLL staging)
    "AWS_LC_SYS_PREBUILT_NASM"
    "LINK_DLL_FOLDERS"
  ];
in {
  nixos = { config, lib, pkgs, ... }: let
    cfg = config.services.lspmux;
  in {
    options.services.lspmux = {
      enable = lib.mkEnableOption "lspmux LSP multiplexer";

      package = lib.mkOption {
        type = lib.types.package;
        default = lspmuxPkg pkgs.stdenv.hostPlatform.system;
        description = "The lspmux package to use";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.user.services.lspmux = {
        description = "Language server multiplexer";
        wantedBy = ["default.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/lspmux server";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      environment.systemPackages = [cfg.package];
    };
  };

  home = { config, lib, pkgs, ... }: let
    cfg = config.services.lspmux;
    tomlFormat = pkgs.formats.toml {};
    configFile = tomlFormat.generate "lspmux-config" cfg.settings;
  in {
    options.services.lspmux = {
      settings = lib.mkOption {
        type = tomlFormat.type;
        default = {};
        description = ''
          lspmux configuration options (converted to TOML).
          See https://codeberg.org/p2502/lspmux for available options.

          `instance_timeout` and `pass_environment` have module-provided
          defaults. Entries added to `pass_environment` here are concatenated
          with the defaults rather than replacing them.
        '';
        example = lib.literalExpression ''
          {
            gc_interval = 10;
            listen = ["127.0.0.1" 27631];
            log_filters = "info";
            pass_environment = ["MY_PROJECT_VAR" "!NOISY_VAR"];
          }
        '';
      };
    };

    config = {
      services.lspmux.settings = {
        instance_timeout = lib.mkDefault 3600; # 1 hour
        pass_environment = defaultPassEnvironment;
      };

      # The `directories` crate uses platform-native config paths
      home.file = lib.mkIf pkgs.stdenv.isDarwin {
        "Library/Application Support/lspmux/config.toml".source = configFile;
      };
      xdg.configFile = lib.mkIf (!pkgs.stdenv.isDarwin) {
        "lspmux/config.toml".source = configFile;
      };
    };
  };
}
