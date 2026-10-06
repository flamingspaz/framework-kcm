{ pkgs ? import <nixpkgs> { } }:

let
  version = "0.1.2";
in
rec {
  frameworkd = pkgs.callPackage ./frameworkd.nix { inherit version; };
  framework-settings = pkgs.callPackage ./framework-settings.nix { inherit version frameworkd; };

  default = framework-settings;
  framework-kcm = pkgs.lib.warnOnInstantiate "framework-kcm has been renamed to framework-settings" framework-settings;
  framework-kcmd = pkgs.lib.warnOnInstantiate "framework-kcmd has been renamed to frameworkd" frameworkd;
}
