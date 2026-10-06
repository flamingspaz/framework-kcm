{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.framework-settings;
  packages = import ../packages { inherit pkgs; };
in
{
  options.programs.framework-settings = {
    enable = lib.mkEnableOption "framework-settings";
    package = lib.mkPackageOption packages "framework-settings" { };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "programs" "framework-kcm" "enable" ] [ "programs" "framework-settings" "enable" ])
    (lib.mkRenamedOptionModule [ "programs" "framework-kcm" "package" ] [ "programs" "framework-settings" "package" ])
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.dbus.packages = [ cfg.package ];
    security.polkit.enable = true;
    systemd.packages = [ cfg.package ];
    # Reapply write-only hardware settings after reboot.
    systemd.services.frameworkd.wantedBy = [ "multi-user.target" ];
  };
}
