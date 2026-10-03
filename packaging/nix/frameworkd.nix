{ pkgs ? import <nixpkgs> { }, version ? "0.1.1" }:

pkgs.rustPlatform.buildRustPackage {
  pname = "frameworkd";
  inherit version;
  src = ../../daemon;

  cargoLock = {
    lockFile = ../../daemon/Cargo.lock;
    # A supplied hash selects nixpkgs' shallow fetchgit instead of fetchGit.
    outputHashes = {
      "framework_lib-0.6.6" = "sha256-AcATahEiCiXUNC4k9dCW6doGchjdvg6Kc7VjaOYyFGk=";
    };
  };

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.hidapi pkgs.libusb1 pkgs.systemd ];
}
