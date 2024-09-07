{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs-unstable }:
    let
      pkgs = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; };

      # This is something we might use if we wanted to cross-compile easier via
      # nix. References:
      # - https://nixos.wiki/wiki/Cross_Compiling
      # - https://nixos.org/manual/nixpkgs/stable/#chap-cross
      # - https://discourse.nixos.org/t/cross-compilation-with-nix-shell-and-cmake/2611
      # - https://discourse.nixos.org/t/use-buildinputs-or-nativebuildinputs-for-nix-shell/8464
      # - https://discourse.nixos.org/t/how-do-i-get-a-shell-nix-with-cross-compiler-and-qemu/7658
      #
      # aarch64-multiplatform-pkgs = import nixpkgs-unstable {
      #   system = "x86_64-linux";
      #   config = { allowUnfree = true; };
      #   crossSystem = pkgs.lib.systems.examples.aarch64-multiplatform;
      # };

      mkShell = args: pkgs.mkShell ({
        # Disable default hardening flags. These are very confusing when doing
        # development and they break builds of packages/systems that don't
        # expect these flags to be on. Automatically enables stuff like
        # FORTIFY_SOURCE, -Werror=format-security, -fPIE, etc. See:
        # - https://nixos.org/manual/nixpkgs/stable/#sec-hardening-in-nixpkgs
        # - https://nixos.wiki/wiki/C#Hardening_flags
        hardeningDisable = ["all"];
      } // args);
    in {
      devShells.x86_64-linux.default = mkShell {
        nativeBuildInputs = with pkgs; [
          # Java, to run nand2tetris tools
          jre

          # Rust
          cargo
          rustc
          clippy
          rustfmt
          rust-analyzer

          # C
          gcc
          gcc.man
          gdb
          valgrind
          bear # Generates compile_commands.json
          cmake

          # Zig
          zig
          zls # LSP

          # Cross-compilation to ARM (glibc static conflicts with native
          # glibc.static once ld runs because of weird nix wrapper scripts)
          # pkgsCross.aarch64-multiplatform.buildPackages.gcc
          # pkgsCross.aarch64-multiplatform.glibc.static

          # ASM
          nasm
          # N.B. We use yasm instead of nasm because nasm 2.15.05 (Aug 28 2020)
          # and gdb 12.1 (May 2022) don't play nice together. There doesn't seem
          # to be any source location information included in the resulting
          # binary. Specifically, we have to use "ni" instead of "n" for
          # stepping, and any command that tries to inspect the source (like
          # layout src, or TUI mode), says "[No Source Available]".
          yasm

          # Python
          python3

          # Misc
          unzip

          # Kernel tools
          coccinelle
          sparse
        ];
      };

      devShells.x86_64-linux.ebpf = mkShell {
        nativeBuildInputs = with pkgs; [
          bcc
          bpftrace
          bpftools
          libbpf
          pkgs.llvmPackages_15.tools.llvm # e.g. llvm-objdump
          pkgs.llvmPackages_15.clang
        ];
      };

      devShells.x86_64-linux.os-dev-64-bit = mkShell {
        nativeBuildInputs = with pkgs; [
          # C
          binutils
          gcc
          gcc.man
          gdb

          # LLVM
          pkgs.llvmPackages_15.tools.llvm # e.g. llvm-objdump
          pkgs.llvmPackages_15.clang
          pkgs.llvmPackages_15.lld

          # Assembly
          nasm

          # OS stuff
          grub2
          xorriso
          qemu
        ];
      };

      devShells.x86_64-linux.i686-cross-compile = mkShell {
        nativeBuildInputs = with pkgs; [
          # C
          binutils
          gcc
          gcc.man
          gdb

          # OS stuff
          grub2
          xorriso
          qemu

          # Cross compilation packages
          pkgsCross.i686-embedded.buildPackages.gcc
        ];
      };

      devShells.x86_64-linux.armv7-cross-compile = mkShell {
        nativeBuildInputs = with pkgs; [
          # C
          gcc
          gcc.man
          gdb
          bear # Generates compile_commands.json

          # Cross compilation packages
          pkgsCross.armv7l-hf-multiplatform.buildPackages.gcc
          pkgsCross.armv7l-hf-multiplatform.glibc.static
        ];
      };

      devShells.x86_64-linux.avr-cross-compile = mkShell {
        nativeBuildInputs = with pkgs; [
          # C
          gcc
          gcc.man
          gdb
          bear # Generates compile_commands.json

          # Cross compilation packages
          avrdude # To upload to board
          pkgsCross.avr.buildPackages.gcc
          pkgsCross.avr.buildPackages.gdb
          pkgsCross.avr.avrlibc
        ];
      };

      devShells.x86_64-linux.stm32-c = mkShell {
        nativeBuildInputs = with pkgs; [
          # C
          gcc
          gcc.man
          gdb
          bear # Generates compile_commands.json
          cmake

          # Cross compilation packages. N.B. We don't use e.g.
          # pkgsCross.arm-embedded.buildPackages.gcc. When I tried to use that
          # on my STM32, newlib was super funky (objdump said memcpy was using
          # 32 bit instructions, but gdb said they were thumb, and we were
          # jumping to weird memory locations). See
          # https://github.com/NixOS/nixpkgs/issues/51907
          #
          # Note that gcc-arm-embedded is the upstream ARM fork of gcc, and
          # includes newlib-nano.
          gcc-arm-embedded
          stlink # To flash to board
        ];
      };
    };
}
