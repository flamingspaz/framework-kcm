# Framework KCM

Framework laptop settings in KDE System Settings: battery charge limits,
fans and temperatures, fingerprint LED and haptic touchpad settings, and
firmware and USB-C port information.

| Battery                                  | Fans & Thermals                           |
| ---------------------------------------- | ----------------------------------------- |
| ![Battery tab](docs/battery.png)         | ![Fans & Thermals tab](docs/thermals.png) |
| **Touchpad & LED**                       | **System**                                |
| ![Touchpad & LED tab](docs/touchpad.png) | ![System tab](docs/system.png)            |

## Features

- **Overview:** a read-only summary of battery, thermals, fans, and firmware,
  with hardware controls kept on their dedicated tabs.
- **Battery:** set a charge limit, charge to 100% once with _Override Charge
  Limit_ (the limit comes back after the next restart), and slow down
  charging to reduce heat and battery wear.
- **Schedule:** apply different charge limits on selected weekdays and times
  using user systemd timers. Scheduling requires `framework_tool` from
  `framework-system`.
- **Fans & Thermals:** live temperatures, fan speed and throttling status.
  Leave the fans on automatic, or fix their speed.
- **Touchpad & LED:** fingerprint reader LED brightness, and haptic touchpad
  feedback strength and click force.
- **System:** model, BIOS, EC and PD controller firmware versions, camera and
  microphone privacy switches, and what's connected to each USB-C port.

It's built on Framework's own
[`framework_lib`](https://github.com/FrameworkComputer/framework-system).

## Supported hardware

Developed and tested on the **Framework Laptop 13 Pro (Intel Core Ultra
Series 3)**. Other Framework laptops use the same embedded controller
interface, so most features should work there too, but they haven't been
tested.

The System Settings module requires KDE Plasma 6. A separate desktop app,
`framework-settings`, is also provided for other desktop environments; it is
built with Qt Quick Controls and has no KDE runtime dependency.
It follows Qt Quick Controls' configured style (including KDE's); on Linux
with no style configured, Qt defaults to the desktop-oriented Fusion style.

## Install

Download the package for your distribution from the
[latest release](https://github.com/flamingspaz/framework-settings/releases/latest).

### NixOS (Flakes)

This project can be used by adding this repository as a flakes input
and using the provided NixOS module. Below is a basic `flake.nix` example:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    framework-settings = {
      url = "github:flamingspaz/framework-settings/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { nixpkgs, framework-settings, ... }: {
    nixosConfigurations = {
      yourHost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix
          framework-settings.nixosModules.framework-settings
          { programs.framework-settings.enable = true; }
          # rest of your system configuration here.
        ];
      };
    };
  };
}
```

If you wish to only install the the GUI application or KCM, you can override
the framework-settings package in a system module:

```nix
let
  packages = framework-settings.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.framework-settings.package = packages.framework-settings.override {
    withGui = true;
    withKcm = true;
  }
}
```

### NixOS (nix-channel)

For non-Flake configs, you can add this repository as a channel on your system.

```bash
$ sudo nix-channel --add https://github.com/flamingspaz/framework-settings/archive/main.tar.gz framework-settings
$ sudo nix-channel --update
```

After adding the channel, you can add the following to your `configuration.nix`:

```nix
{ config, pkgs, ...}:
let
  framework-settings = import <framework-settings> { inherit pkgs; };
in
{
  imports = [
    ./hardware-configuration.nix
    framework-settings.nixosModules.framework-settings
  ];
  programs.framework-settings.enable = true;
  # rest of your system configuration here.
}
```

If you wish to only install the the GUI application or KCM, you can override
the framework-settings package in your `configuration.nix`:

```nix
programs.framework-settings.package = framework-settings.packages.framework-settings.override {
  withGui = true;
  withKcm = true;
};
```

### Arch Linux

```sh
sudo pacman -U framework-*.pkg.tar.zst
sudo systemctl enable --now frameworkd
```

The Arch `framework-settings` meta-package installs the GUI, KCM, and service.
For a non-KDE desktop, install `framework-gui` instead; it brings in
`frameworkd` without the KCM.

### Ubuntu 26.04

```sh
sudo apt install ./framework-*.deb
```

This installs the `framework-settings` meta-package and its GUI, KCM, and
service packages. From a repository, install `framework-gui` alone for a
non-KDE setup; it pulls in the daemon but not the KCM. The daemon package
configures and enables the background service.

### Fedora

The `framework-settings` meta-package is available in [Terra](https://terrapkg.com).

```sh
sudo dnf install framework-settings
```

For a non-KDE desktop, install only `framework-gui`; it pulls in the service
without installing the KCM.

Then open **System Settings → System → Framework Laptop**, or run
`kcmshell6 kcm_framework`. On non-KDE desktops, launch **Framework Settings**
or run `framework-settings`.

The `frameworkd` service starts on its own when you open the settings
page. Enabling it also starts it at boot, so settings the hardware forgets
(touchpad feedback, click force, charge speed) are applied again after a
restart.

To uninstall the full suite, remove the `framework-settings` meta-package. If
installed separately, remove the packages you chose (`framework-gui`,
`framework-kcm`, and/or `frameworkd`). On Arch,
`sudo pacman -Rns framework-settings` also removes unneeded subpackages; on
Debian-based systems, use `sudo apt remove framework-settings` and optionally
`sudo apt autoremove`.

## Fixture mode

To preview either UI without Framework hardware or the daemon, launch it with
fixture mode enabled. Readings are simulated, setting changes stay in memory,
and scheduling does not create systemd units:

```sh
FRAMEWORK_KCM_FIXTURE=1 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 ./build-qt/gui/framework-settings
```

The Overview tab lets you choose a hardware profile for testing model-specific
controls. You can also pick a profile at launch:

```sh
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-12 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-12-gen2 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-13 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-13-pro kcmshell6 kcm_framework
```

The same `FRAMEWORK_KCM_FIXTURE_MODEL` values work with the standalone GUI.

## Permissions

Changing hardware settings needs root, so a small system service does it on
the settings page's behalf. Whether you're asked for a password:

| Setting                      | Password?                              |
| ---------------------------- | -------------------------------------- |
| Battery charging             | No                                     |
| Touchpad and fingerprint LED | No                                     |
| Fan control                  | Yes, then remembered for a few minutes |

Fan control asks because a fixed fan speed can let the laptop run hot. The
embedded controller still shuts the laptop down before it overheats, and the
fans go back to automatic when the service stops or the laptop restarts.

When you're logged in remotely (over SSH, for example), every change asks
for an administrator password.

## Things to know

- **The charge limit slider is temporary.** Plasma's Power Management page
  doesn't expose the Framework 13 Pro charge limit correctly yet, so this
  module provides one for now. Once Plasma does, the slider will be removed
  from here. Until then, both write the same EC setting, so set the limit in
  only one place.
- Haptic and click force settings only apply to the haptic touchpads found
  on the 13 Pro Input Cover.
- Keyboard backlight is left to Plasma, which drives it through `cros_kbd_led_backlight`.
- USB-C port names follow `framework_tool --pdports`.

## Languages

The KCM follows your System Settings language and is available in English,
Dutch, German, Spanish and French. The standalone `framework-settings` app is
English-only for now. The non-English KCM translations were machine-generated
and haven't been reviewed by native speakers yet, so corrections are welcome.
See [docs/translations.md](docs/translations.md).

## Documentation

- [How it works](docs/architecture.md): the settings page, the system
  service, and its D-Bus API
- [Building from source](docs/building.md), and debugging the service
- [Packaging](docs/packaging.md): local RPM builds with Anda and distro
  packaging workflows
- [Releasing](docs/releasing.md): CI and cutting a release
- [Translations](docs/translations.md): updating or adding a language

## License

Framework KCM is free software, licensed under the GNU General Public
License version 3 or (at your option) any later version. See
[LICENSE](LICENSE).

It uses [`framework_lib`](https://github.com/FrameworkComputer/framework-system),
which is BSD-3-Clause licensed. The icon is the cog from the Framework
Computer logo. The logo itself is in the public domain, but "Framework" is a
trademark of Framework Computer Inc., and this project isn't affiliated with
them.
