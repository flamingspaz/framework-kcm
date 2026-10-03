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

Requires KDE Plasma 6.

## Install

Download the package for your distribution from the
[latest release](https://github.com/flamingspaz/framework-kcm/releases/latest).

**Nix**

Build from a checkout with:

```sh
nix build
```

The `framework-kcm` package includes the KCM and points its D-Bus and systemd
service files at the daemon in the Nix store. Build the daemon by itself with:

```sh
nix build .#framework-kcmd
```

The underlying package expression is in `packaging/nix/package.nix`.

**Arch Linux**

```sh
sudo pacman -U framework-kcm-*.pkg.tar.zst
sudo systemctl enable --now framework-kcmd
```

**Ubuntu 26.04**

```sh
sudo apt install ./framework-kcm_*.deb
```

The Ubuntu package enables the background service for you.

**Fedora**

`framework-kcm` is available in [Terra](https://terrapkg.com).

```sh
sudo dnf install framework-kcm
```

Then open **System Settings → System → Framework Laptop**, or run
`kcmshell6 kcm_framework`.

The `framework-kcmd` service starts on its own when you open the settings
page. Enabling it also starts it at boot, so settings the hardware forgets
(touchpad feedback, click force, charge speed) are applied again after a
restart.

### Fixture mode

To preview the pages without Framework hardware or the daemon, launch the KCM
with fixture mode enabled. All readings are simulated, setting changes stay in
memory, and scheduling does not create systemd units:

```sh
FRAMEWORK_KCM_FIXTURE=1 kcmshell6 kcm_framework
```

The Overview tab then lets you choose a profile for testing model-specific
controls. You can also pick a profile at launch:

```sh
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-12 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-12-gen2 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-13 kcmshell6 kcm_framework
FRAMEWORK_KCM_FIXTURE=1 FRAMEWORK_KCM_FIXTURE_MODEL=framework-13-pro kcmshell6 kcm_framework
```

To uninstall, run `sudo pacman -R framework-kcm` or `sudo apt remove framework-kcm`.

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

The module follows your System Settings language. It's available in
English, Dutch, German, Spanish and French. The non-English translations
were machine-generated and haven't been reviewed by native speakers yet,
so corrections are welcome. See [docs/translations.md](docs/translations.md).

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
