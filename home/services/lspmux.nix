{self, ...}: {
  imports = [
    self.homeModules.lspmux
  ];
  services.lspmux.settings = {
    instance_timeout = 3600; # 1 hour
    pass_environment = [
      # Core identity / basic runtime
      "HOME"
      "PATH"

      # Rust / Cargo
      # (keep even if some aren't currently set; harmless)
      "RUST_SRC_PATH"
      "RUSTUP_HOME"
      "CARGO_HOME"

      "RUSTFLAGS"
      "CARGO_BUILD_RUSTFLAGS"
      "CARGO_ENCODED_RUSTFLAGS"
      "CARGO_PROFILE"
      "CARGO_TERM_COLOR"

      "CARGO_BUILD_TARGET"
      "RA_TARGET"

      "SQLX_OFFLINE"
      "DATABASE_URL"

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

      "NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"
      "NIX_BINTOOLS_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"
      "NIX_PKG_CONFIG_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"

      "NIX_STORE"
      "NIX_SSL_CERT_FILE"
      "NIX_PATH"
      "NIX_PROFILES"
      "NIX_USER_PROFILE_DIR"
      "IN_NIX_SHELL"
    ];
  };
}
