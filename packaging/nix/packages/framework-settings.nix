{
  cmake,
  kdePackages,
  lib,
  qt6,
  stdenv,

  version,
  frameworkd,

  withGui ? true,
  withKcm ? true,
}:

stdenv.mkDerivation {
  pname = "framework-settings";
  inherit version;
  src = ../../..;
  dontWrapQtApps = !withGui;

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    cmake
  ]
  ++ (lib.optional withGui qt6.wrapQtAppsHook)
  ++ (lib.optional withKcm kdePackages.extra-cmake-modules);

  buildInputs = with qt6; [
    qtbase
    qtdeclarative
  ]
  ++ (lib.optionals withKcm (with kdePackages; [
    kcoreaddons
    ki18n
    kcmutils
  ]));

  cmakeFlags = [
    (lib.cmakeBool "BUILD_GUI" withGui)
    (lib.cmakeBool "BUILD_KCM" withKcm)
    (lib.cmakeBool "BUILD_DAEMON" false)
    (lib.cmakeFeature "DAEMON_PATH" (lib.getExe frameworkd))
    (lib.cmakeBool "KDE_INSTALL_USE_QT_SYS_PATHS" true)
  ];

  meta = {
    description = "Framework Laptop settings GUI, KDE module, and system service";
    homepage = "https://github.com/flamingspaz/framework-settings";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  } // lib.optionalAttrs withGui {
    mainProgram = "framework-settings";
  };
}
