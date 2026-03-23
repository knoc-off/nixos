{
  lib,
  stdenv,
  fetchFromGitLab,
  meson,
  ninja,
  pkg-config,
  glib,
  libfprint,
  linux-pam,
  polkit,
  dbus,
  systemd,
  perl,
  libxslt,
  libxml2,
  libpam-wrapper,
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
    perl # needed by pod2man check even if man=false
    libxslt # needed by xsltproc check even if gtk_doc=false
  ];

  buildInputs = [
    glib # required by top-level meson.build configure step
    libfprint # required by top-level meson.build configure step
    linux-pam # the actual PAM library linked by the module
    polkit # required by top-level meson.build configure step
    dbus # required by top-level meson.build configure step
    systemd # provides libsystemd, linked by the PAM module
    libxml2 # xmllint check
    libpam-wrapper # required by meson configure (pam_wrapper dependency)
  ];

  mesonFlags = [
    "-Dpam=true"
    "-Dman=false"
    "-Dsystemd=false"
    "-Dgtk_doc=false"
    "-Dpam_modules_dir=${placeholder "out"}/lib/security"
  ];

  meta = with lib; {
    description = "PAM module for simultaneous fingerprint and password authentication";
    homepage = "https://gitlab.com/mishakmak/pam-fprint-grosshack";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
  };
}
