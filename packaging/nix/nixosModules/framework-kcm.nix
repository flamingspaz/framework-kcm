{
  imports = [ ./framework-settings.nix ];
  config.warnings = [
    "The framework-kcm module has been renamed to framework-settings"
  ];
}
