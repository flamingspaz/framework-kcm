{ pkgs ? import <nixpkgs> { } }:

let
  version = "0.1.1";

  frameworkd = import ./frameworkd.nix { inherit pkgs version; };

  framework-kcm = import ./framework-kcm.nix {
    inherit pkgs version frameworkd;
  };
in
{
  default = framework-kcm;
  inherit framework-kcm frameworkd;
  framework-kcmd = frameworkd;
}
