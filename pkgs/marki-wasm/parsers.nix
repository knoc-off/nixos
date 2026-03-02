# Auto-generated from syntastica's languages.toml for the "most" feature set.
# Each entry maps a parser name to its git source at a pinned revision.
# The build script expects: $SYNTASTICA_PARSERS_CLONE_DIR/<name>/<rev>/...
{ pkgs }:
let
  fetchParser = { url, rev, sha256 }: pkgs.fetchgit {
    inherit url rev sha256;
    fetchSubmodules = false;
  };

  # Shared repos (multiple parsers reference the same repo at the same rev)
  typescript-repo = fetchParser {
    url = "https://github.com/tree-sitter/tree-sitter-typescript";
    rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f";
    sha256 = "sha256-A0M6IBoY87ekSV4DfGHDU5zzFWdLjGqSyVr6VENgA+s=";
  };
  markdown-repo = fetchParser {
    url = "https://github.com/MDeiml/tree-sitter-markdown";
    rev = "7462bb66ac7e90312082269007fac2772fe5efd1";
    sha256 = "sha256-TvGTKsna1NS31/Tp9gBpndG1hNCRCEErBq1DK3pQHkU=";
  };
  php-repo = fetchParser {
    url = "https://github.com/tree-sitter/tree-sitter-php";
    rev = "b2278dbac9d58b02653fe6a8530ccebc492e4ed4";
    sha256 = "sha256-xvUUw+532j49MhEgAeEDfLo+bqN0U65s/uV9BPbsVt4=";
  };

  parsers = {
    # "some" group
    bash = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-bash";
        rev = "56b54c61fb48bce0c63e3dfa2240b5d274384763";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "56b54c61fb48bce0c63e3dfa2240b5d274384763";
    };
    c = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-c";
        rev = "7fa1be1b694b6e763686793d97da01f36a0e5c12";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "7fa1be1b694b6e763686793d97da01f36a0e5c12";
    };
    cpp = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-cpp";
        rev = "56455f4245baf4ea4e0881c5169de69d7edd5ae7";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "56455f4245baf4ea4e0881c5169de69d7edd5ae7";
    };
    css = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-css";
        rev = "6e327db434fec0ee90f006697782e43ec855adf5";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "6e327db434fec0ee90f006697782e43ec855adf5";
    };
    go = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-go";
        rev = "5e73f476efafe5c768eda19bbe877f188ded6144";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "5e73f476efafe5c768eda19bbe877f188ded6144";
    };
    html = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-html";
        rev = "cbb91a0ff3621245e890d1c50cc811bffb77a26b";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "cbb91a0ff3621245e890d1c50cc811bffb77a26b";
    };
    java = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-java";
        rev = "a7db5227ec40fcfe94489559d8c9bc7c8181e25a";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "a7db5227ec40fcfe94489559d8c9bc7c8181e25a";
    };
    javascript = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-javascript";
        rev = "6fbef40512dcd9f0a61ce03a4c9ae7597b36ab5c";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "6fbef40512dcd9f0a61ce03a4c9ae7597b36ab5c";
    };
    json = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-json";
        rev = "46aa487b3ade14b7b05ef92507fdaa3915a662a3";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "46aa487b3ade14b7b05ef92507fdaa3915a662a3";
    };
    kotlin = {
      src = fetchParser {
        url = "https://github.com/fwcd/tree-sitter-kotlin";
        rev = "57fb4560ba8641865bc0baa6b3f413b236112c4c";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "57fb4560ba8641865bc0baa6b3f413b236112c4c";
    };
    lua = {
      src = fetchParser {
        url = "https://github.com/muniftanjim/tree-sitter-lua";
        rev = "4fbec840c34149b7d5fe10097c93a320ee4af053";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "4fbec840c34149b7d5fe10097c93a320ee4af053";
    };
    python = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-python";
        rev = "710796b8b877a970297106e5bbc8e2afa47f86ec";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "710796b8b877a970297106e5bbc8e2afa47f86ec";
    };
    rust = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-rust";
        rev = "3691201b01cacb2f96ffca4c632c4e938bfacd88";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "3691201b01cacb2f96ffca4c632c4e938bfacd88";
    };
    toml = {
      src = fetchParser {
        url = "https://github.com/Mathspy/tree-sitter-toml";
        rev = "ae4cdb5d27bf876a432b6c30b6a88f56c9b3e761";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "ae4cdb5d27bf876a432b6c30b6a88f56c9b3e761";
    };
    tsx = {
      src = typescript-repo;
      rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f";
    };
    typescript = {
      src = typescript-repo;
      rev = "75b3874edb2dc714fb1fd77a32013d0f8699989f";
    };
    yaml = {
      src = fetchParser {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-yaml";
        rev = "3431ec21da1dde751bab55520963cf3a4f1121f3";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "3431ec21da1dde751bab55520963cf3a4f1121f3";
    };

    # "most" group (additional)
    asm = {
      src = fetchParser {
        url = "https://github.com/rush-rs/tree-sitter-asm";
        rev = "04962e15f6b464cf1d75eada59506dc25090e186";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "04962e15f6b464cf1d75eada59506dc25090e186";
    };
    c_sharp = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-c-sharp";
        rev = "b5eb5742f6a7e9438bee22ce8026d6b927be2cd7";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "b5eb5742f6a7e9438bee22ce8026d6b927be2cd7";
    };
    clojure = {
      src = fetchParser {
        url = "https://github.com/sogaiu/tree-sitter-clojure";
        rev = "40c5fc2e2a0f511a802a82002553c5de00feeaf4";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "40c5fc2e2a0f511a802a82002553c5de00feeaf4";
    };
    cmake = {
      src = fetchParser {
        url = "https://github.com/uyha/tree-sitter-cmake";
        rev = "cf9799600b2ba5e6620fdabddec3b2db8306bc46";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "cf9799600b2ba5e6620fdabddec3b2db8306bc46";
    };
    comment = {
      src = fetchParser {
        url = "https://github.com/stsewd/tree-sitter-comment";
        rev = "689be73775bd2dd57b938b8e12bf50fec35a6ca3";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "689be73775bd2dd57b938b8e12bf50fec35a6ca3";
    };
    dart = {
      src = fetchParser {
        url = "https://github.com/UserNobody14/tree-sitter-dart";
        rev = "80e23c07b64494f7e21090bb3450223ef0b192f4";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "80e23c07b64494f7e21090bb3450223ef0b192f4";
    };
    diff = {
      src = fetchParser {
        url = "https://github.com/the-mikedavis/tree-sitter-diff";
        rev = "e42b8def4f75633568f1aecfe01817bf15164928";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "e42b8def4f75633568f1aecfe01817bf15164928";
    };
    elixir = {
      src = fetchParser {
        url = "https://github.com/elixir-lang/tree-sitter-elixir";
        rev = "b848e63e9f2a68accff0332392f07582c046295a";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "b848e63e9f2a68accff0332392f07582c046295a";
    };
    haskell = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-haskell";
        rev = "0975ef72fc3c47b530309ca93937d7d143523628";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "0975ef72fc3c47b530309ca93937d7d143523628";
    };
    jsdoc = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-jsdoc";
        rev = "a417db5dbdd869fccb6a8b75ec04459e1d4ccd2c";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "a417db5dbdd869fccb6a8b75ec04459e1d4ccd2c";
    };
    json5 = {
      src = fetchParser {
        url = "https://github.com/Joakker/tree-sitter-json5";
        rev = "ab0ba8229d639ec4f3fa5f674c9133477f4b77bd";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "ab0ba8229d639ec4f3fa5f674c9133477f4b77bd";
    };
    jsonc = {
      src = fetchParser {
        url = "https://gitlab.com/WhyNotHugo/tree-sitter-jsonc";
        rev = "02b01653c8a1c198ae7287d566efa86a135b30d5";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "02b01653c8a1c198ae7287d566efa86a135b30d5";
    };
    luap = {
      src = fetchParser {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-luap";
        rev = "c134aaec6acf4fa95fe4aa0dc9aba3eacdbbe55a";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "c134aaec6acf4fa95fe4aa0dc9aba3eacdbbe55a";
    };
    make = {
      src = fetchParser {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-make";
        rev = "5e9e8f8ff3387b0edcaa90f46ddf3629f4cfeb1d";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "5e9e8f8ff3387b0edcaa90f46ddf3629f4cfeb1d";
    };
    markdown = {
      src = markdown-repo;
      rev = "7462bb66ac7e90312082269007fac2772fe5efd1";
    };
    markdown_inline = {
      src = markdown-repo;
      rev = "7462bb66ac7e90312082269007fac2772fe5efd1";
    };
    nix = {
      src = fetchParser {
        url = "https://github.com/nix-community/tree-sitter-nix";
        rev = "cfc53fd287d23ab7281440a8526c73542984669b";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "cfc53fd287d23ab7281440a8526c73542984669b";
    };
    php = {
      src = php-repo;
      rev = "b2278dbac9d58b02653fe6a8530ccebc492e4ed4";
    };
    php_only = {
      src = php-repo;
      rev = "b2278dbac9d58b02653fe6a8530ccebc492e4ed4";
    };
    printf = {
      src = fetchParser {
        url = "https://github.com/ObserverOfTime/tree-sitter-printf";
        rev = "df6b69967db7d74ab338a86a9ab45c0966c5ee3c";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "df6b69967db7d74ab338a86a9ab45c0966c5ee3c";
    };
    regex = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-regex";
        rev = "b638d29335ef41215b86732dd51be34c701ef683";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "b638d29335ef41215b86732dd51be34c701ef683";
    };
    ruby = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-ruby";
        rev = "89bd7a8e5450cb6a942418a619d30469f259e5d6";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "89bd7a8e5450cb6a942418a619d30469f259e5d6";
    };
    scala = {
      src = fetchParser {
        url = "https://github.com/tree-sitter/tree-sitter-scala";
        rev = "2d55e74b0485fe05058ffe5e8155506c9710c767";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "2d55e74b0485fe05058ffe5e8155506c9710c767";
    };
    scss = {
      src = fetchParser {
        url = "https://github.com/serenadeai/tree-sitter-scss";
        rev = "c478c6868648eff49eb04a4df90d703dc45b312a";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "c478c6868648eff49eb04a4df90d703dc45b312a";
    };
    sql = {
      src = fetchParser {
        url = "https://github.com/derekstride/tree-sitter-sql";
        rev = "b1ec2aa5091624e4729f0a771a6d631afebf1ed4";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "b1ec2aa5091624e4729f0a771a6d631afebf1ed4";
    };
    swift = {
      src = fetchParser {
        url = "https://github.com/alex-pinkus/tree-sitter-swift";
        rev = "d64a733eee0f55dcc9790491e0d534e8a559c20a";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "d64a733eee0f55dcc9790491e0d534e8a559c20a";
    };
    typst = {
      src = fetchParser {
        url = "https://github.com/uben0/tree-sitter-typst";
        rev = "46cf4ded12ee974a70bf8457263b67ad7ee0379d";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "46cf4ded12ee974a70bf8457263b67ad7ee0379d";
    };
    zig = {
      src = fetchParser {
        url = "https://github.com/tree-sitter-grammars/tree-sitter-zig";
        rev = "b670c8df85a1568f498aa5c8cae42f51a90473c0";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      rev = "b670c8df85a1568f498aa5c8cae42f51a90473c0";
    };
  };

  # Assemble into the directory layout expected by syntastica-parsers-git:
  # $CLONE_DIR/<parser-name>/<rev>/...
  cloneDir = pkgs.runCommand "syntastica-parsers-clone" {} (
    ''mkdir -p $out\n'' +
    builtins.concatStringsSep "" (
      builtins.attrValues (
        builtins.mapAttrs (name: parser: ''
          mkdir -p $out/${name}
          ln -s ${parser.src} $out/${name}/${parser.rev}
        '') parsers
      )
    )
  );
in
cloneDir
