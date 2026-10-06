rec {
  framework-settings = import ./framework-settings.nix;

  default = framework-settings;
  framework-kcm = import ./framework-kcm.nix;
}
