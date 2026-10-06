{
  description = "Framework Laptop settings GUI, KDE module, and system service";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        import ./packaging/nix/packages { inherit pkgs; }
      );
      nixosModules = import ./packaging/nix/nixosModules;
    };
}
