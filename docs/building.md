# Building from source

Framework KCM consists of a KDE/Qt 6 System Settings module and a Rust
system service. The default build builds both; set `BUILD_DAEMON=OFF` to work
on the UI without building the service.

## Requirements

- CMake 3.22 or newer and a C++20 compiler
- Extra CMake Modules, Qt 6.6 or newer (Core, DBus, Qml and Quick), and KF6
  (CoreAddons, I18n and KCMUtils)
- Rust and Cargo (the service is built with `cargo build --release --locked`)
- The native development libraries used by `framework_lib` (including hidapi,
  libusb and systemd)

On Fedora, install the build dependencies with:

```sh
sudo dnf install cmake extra-cmake-modules gcc-c++ cargo rust git pkgconf-pkg-config \
  qt6-qtbase-devel qt6-qtdeclarative-devel \
  kf6-kcmutils-devel kf6-kcoreaddons-devel kf6-ki18n-devel \
  hidapi-devel libusb1-devel systemd-devel
```

On Arch Linux:

```sh
sudo pacman -S --needed cmake extra-cmake-modules gcc rust git \
  qt6-base qt6-declarative kcmutils kcoreaddons ki18n kirigami \
  hidapi libusb systemd-libs
```

## Build Fedora RPMs locally with Anda

From the repository root, run the Git RPM build with Anda:

```sh
anda build -c terra-44-x86_64 kcm-git
```

The `kcm-git` project in `anda.hcl` uses
`packaging/fedora/framework-kcm-git.spec` and packages the current Git source.
For the versioned RPM spec, use `anda build -c terra-44-x86_64 kcm`; that spec
builds the tagged source matching its `Version`. See
[Packaging](packaging.md) for the distro packaging overview.

The first daemon build downloads Rust crates and the `framework_lib` Git
repository, so it needs network access. Subsequent builds use Cargo's cache.

## Native build with CMake

Run these commands from the repository root. They use CMake directly; no
project-specific build wrapper is required.

```sh
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
cmake --build build --parallel
```

To install into a temporary staging directory instead of the live system:

```sh
DESTDIR="$PWD/stage" cmake --install build
```

The staged files are under `stage/usr/`. To install directly to the system,
use `sudo cmake --install build` instead. If you install directly, reload the
service and D-Bus configuration and enable the daemon:

```sh
sudo systemctl daemon-reload
sudo systemctl reload dbus
sudo systemctl enable --now frameworkd
```

`KDE_INSTALL_USE_QT_SYS_PATHS=ON` installs the module under Qt's plugin
path, which is where Plasma 6 searches for KCMs. On Fedora this should place
the plugin at `/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_framework.so`.

For UI-only work, configure with `-DBUILD_DAEMON=OFF`; that build will not
produce or install `frameworkd`, so skip the service commands above.

## With Docker

`build.sh` is an optional wrapper that builds inside an Arch-based container,
so a host Rust toolchain is not needed. It uses the same CMake configure and
build steps and leaves the build directory mounted at the same path:

```sh
./build.sh
sudo cmake --install build
```

Pass CMake options through to the script, for example `./build.sh
-DBUILD_DAEMON=OFF`. The resulting binaries link against the libraries in the
container, so use a container matching the target distribution for packages
intended for distribution.

## Useful options

- `-DBUILD_DAEMON=OFF`: build only the KCM, for example while working on QML.
- `-DCMAKE_BUILD_TYPE=Debug`: make a debug build; `Release` or
  `RelWithDebInfo` are suitable for packaging.
- The daemon uses `cargo build --release --locked`. After changing Rust
  dependencies, run `cargo update` in `daemon/` to refresh `Cargo.lock`.

## Debugging the service

Talk to it directly:

```sh
busctl introspect io.github.frameworkkcm.Daemon1 /io/github/frameworkkcm/Daemon1
busctl call io.github.frameworkkcm.Daemon1 /io/github/frameworkkcm/Daemon1 \
    io.github.frameworkkcm.Daemon1 GetThermal
busctl call io.github.frameworkkcm.Daemon1 /io/github/frameworkkcm/Daemon1 \
    io.github.frameworkkcm.Daemon1 SetChargeLimit i 80
journalctl -u frameworkd
```

Run it in the foreground with more logging (stop the service first):

```sh
sudo systemctl stop frameworkd
sudo RUST_LOG=debug build/cargo/release/frameworkd
```

See [architecture.md](architecture.md) for the full D-Bus API.
