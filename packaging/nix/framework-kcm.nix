{
  pkgs ? import <nixpkgs> { },
  version ? "0.1.1",
  frameworkd ? import ./frameworkd.nix { inherit pkgs version; },
}:

pkgs.stdenv.mkDerivation {
  pname = "framework-kcm";
  inherit version;
  src = ../..;
  dontWrapQtApps = true;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.kdePackages.extra-cmake-modules
    pkgs.ninja
    pkgs.pkg-config
  ];

  buildInputs = [
    pkgs.qt6.qtbase
    pkgs.qt6.qtdeclarative
    pkgs.kdePackages.kcoreaddons
    pkgs.kdePackages.ki18n
    pkgs.kdePackages.kcmutils
    pkgs.kdePackages.kirigami
    pkgs.polkit
  ];

  cmakeFlags = [
    "-DKDE_INSTALL_USE_QT_SYS_PATHS=ON"
    "-DBUILD_DAEMON=OFF"
    "-DDAEMON_PATH=${frameworkd}/bin/frameworkd"
  ];
}
