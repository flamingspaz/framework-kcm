{
  description = "Framework Laptop settings module for KDE System Settings";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          packageSet = import ./packaging/nix/package.nix { inherit pkgs; };
        in
        {
          default = packageSet.framework-kcm;
          inherit (packageSet) framework-kcm frameworkd framework-kcmd;
        });
    };
}
