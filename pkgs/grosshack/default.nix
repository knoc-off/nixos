{ lib
, stdenv
, fetchFromGitLab
, meson
, ninja
, pkg-config
, fprintd
, glib
, libfprint
, polkit
, dbus
, dbus-glib
, systemd
, systemdLibs
, linux-pam
, pam
, cmake
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
    cmake
  ];

  buildInputs = [
    pam
    fprintd
    glib
    libfprint
    polkit
    dbus
    dbus-glib
    systemd
    systemdLibs
    linux-pam
  ];

  mesonFlags = [
    "-Dpam_modules_dir=${placeholder "out"}/lib/security"
  ];

  NIX_CFLAGS_COMPILE = "-I${linux-pam}/include/security";

  preConfigure = ''
    echo "Debugging information:"
    echo "PAM path: ${linux-pam}"
    echo "PAM include path: ${linux-pam}/include/security"
    echo "PAM headers location:"
    ls -R ${linux-pam}/include/security
    echo "Current directory contents:"
    ls -R
  '';

  configurePhase = ''
    runHook preConfigure
    meson setup build --prefix=$out $mesonFlags
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    ninja -C build install
    runHook postInstall
  '';

  meta = with lib; {
    description = "PAM module enabling simultaneous fingerprint (fprintd) and password authentication";
    homepage = "https://gitlab.com/mishakmak/pam-fprint-grosshack";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
  };
}
