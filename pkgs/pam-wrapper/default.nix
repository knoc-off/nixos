{ lib
, stdenv
, fetchFromGitLab
, cmake
, python3
, pam
, cmocka
, autoPatchelfHook
}:

stdenv.mkDerivation rec {
  pname = "pam-wrapper";
  version = "1.1.7";

  src = fetchFromGitLab {
    owner = "cwrap";
    repo = "pam_wrapper";
    rev = "pam_wrapper-${version}";
    hash = "sha256-KAlZI3uS7ETyN/7JgUyquDsEfvKGvcXL9S/BMxNSwoo=";
  };

  nativeBuildInputs = [ cmake python3 autoPatchelfHook ];
  buildInputs = [ pam cmocka ];

  cmakeFlags = [
    "-DUNIT_TESTING=ON"
    "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
    "-DCMAKE_INSTALL_LIBDIR=${placeholder "out"}/lib"
  ];

  dontInstall = true;

  postBuild = ''
    mkdir -p $out/lib
    mkdir -p $out/${python3.sitePackages}
    mkdir -p $out/include
    mkdir -p $out/lib/pkgconfig
    mkdir -p $out/lib/cmake/pam_wrapper

    cp -r src/libpam_wrapper.so* $out/lib/
    cp -r src/libpamtest.so* $out/lib/
    cp -r src/modules/pam_* $out/lib/
    cp src/python/python3/pypamtest.so $out/${python3.sitePackages}/
    cp -r include/* $out/include/
    cp pam_wrapper.pc $out/lib/pkgconfig/
    cp libpamtest.pc $out/lib/pkgconfig/

    #cp -r src/cmake/* $out/lib/cmake/pam_wrapper/
  '';

  preFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ stdenv.cc.cc pam python3 ]}" $out/${python3.sitePackages}/pypamtest.so
  '';

  meta = with lib; {
    description = "A tool to test PAM applications and PAM modules. https://cwrap.org";
    homepage = "https://gitlab.com/cwrap/pam_wrapper/";
    changelog = "https://gitlab.com/cwrap/pam_wrapper/-/blob/${src.rev}/CHANGELOG";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ ];
    mainProgram = "pam-wrapper";
    platforms = platforms.all;
  };
}
