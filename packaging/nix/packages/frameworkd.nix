{
  lib,
  pkg-config,
  rustPlatform,
  udev,

  version,
}:

rustPlatform.buildRustPackage {
  pname = "frameworkd";
  src = ../../../daemon;
  inherit version;

  __structuredAttrs = true;
  strictDeps = true;

  cargoLock = {
    lockFile = ../../../daemon/Cargo.lock;
    outputHashes = {
      "framework_lib-0.6.6" = "sha256-AcATahEiCiXUNC4k9dCW6doGchjdvg6Kc7VjaOYyFGk=";
    };
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ udev ];

  meta = {
    description = "DBus daemon for framework configuration";
    homepage = "https://github.com/flamingspaz/framework-settings";
    license = lib.licenses.gpl3Plus;
    mainProgram = "frameworkd";
    platforms = lib.platforms.linux;
  };
}
