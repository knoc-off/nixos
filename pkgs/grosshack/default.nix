{ lib
, stdenv
, fetchFromGitLab
, meson
, ninja
, pkg-config
, glib
, pam
, libfprint
, polkit
, dbus
, systemd
, perl
, libxslt
, libpam-wrapper
, libxml2
}:

stdenv.mkDerivation rec {
  pname = "pam-fprint-grosshack";
  version = "0.3.0";

  src = fetchFromGitLab {
    owner = "mishakmak";
    repo = "pam-fprint-grosshack";
    rev = "v${version}";
    hash = "sha256-obczZbf/oH4xGaVvp3y3ZyDdYhZnxlCWvL0irgEYIi0=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    perl
    libxslt
  ];

  buildInputs = [
    glib
    pam
    libfprint
    polkit
    dbus
    systemd
    libpam-wrapper
    libxml2
  ];

  # Configure Meson to install PAM modules within the Nix store and disable man pages
  mesonFlags = [
    "-Dman=false"  # Disable man page generation
    "-Dpam_modules_dir=lib/security"  # Redirect installation path
    # Removed "-Dtests=false" as it's an unknown option
  ];

  # Attempt to patch meson.build if the pattern exists
  postPatch = ''
    # Use --replace-warn to suppress deprecation warning
    substituteInPlace meson.build \
      --replace "pammoddir = join_paths(get_option('libdir'), 'security')" \
                "pammoddir = get_option('pam_modules_dir')" || true
  '';

  meta = with lib; {
    description = "PAM module for fingerprint authentication";
    homepage = "https://gitlab.com/mishakmak/pam-fprint-grosshack";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
}
