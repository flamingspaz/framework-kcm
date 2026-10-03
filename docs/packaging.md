# Packaging

Framework settings is packaged with distro-native tools. Fedora, Arch, and
Debian produce a `framework-settings` meta-package plus separate `framework-gui`,
`framework-kcm`, and `framework-kcmd` packages. The GUI package has no KDE
dependency; both interfaces depend on the service package for hardware access.

## Fedora RPMs

Fedora RPM builds are defined by `anda.hcl` and the specs in
`packaging/fedora/`.

To install Anda, first set up [Terra](https://terrapkg.com), then you can just install it using `dnf install anda`. To avoid running Anda as root, run `sudo usermod -aG mock $USER`

You'll also need Terra's mock configs, which you can get by installing `terra-mock-configs`.

Then, run this command from the repository root:

```sh
anda build -c terra-44-x86_64 kcm-git
```

This builds the Git package from the current source revision using
`framework-kcm-git.spec`. To build the versioned package from its release tag, run:

```sh
anda build -c terra-44-x86_64 kcm
```

The versioned spec uses the `v%{version}` source archive. Both specs produce
`framework-settings` as a meta-package, with separate GUI, KCM, and daemon
packages; installing `framework-gui` alone avoids the KDE dependencies. They
use Fedora's KF6 RPM macros (`%cmake_kf6`, `%cmake_build`, and
`%cmake_install`) and install the plugin under `%{_kf6_qtplugindir}`. They set
`INSTALL_PACKAGE_DOCS=OFF` so RPM's `%license` and `%doc` macros own the docs
and license files. The CI workflow for the Git RPM is
`.github/workflows/package-git.yml`.

## Arch Linux

Arch packages are described by `packaging/arch/PKGBUILD`, with service
install/removal messages in `packaging/arch/framework-kcmd.install`. The
`framework-settings` meta-package installs all three components. Install
`framework-gui` and `framework-kcmd` directly for a non-KDE desktop, or
`framework-kcm` and `framework-kcmd` for the System Settings module. The release
workflow creates a versioned source archive, stages these packaging files,
sets the repository URL and version, and runs `makepkg`. The PKGBUILD expects
that staged archive next to it, so it is not a direct `makepkg` invocation from
the repository root. See `.github/workflows/build.yml` for the CI staging steps.

The package manager installs the service but does not enable it automatically.
To apply write-only touchpad and charge-rate settings at boot, enable the
service after installation:

```sh
sudo systemctl enable --now framework-kcmd.service
```

## Debian and Ubuntu packages

Debian packages use CPack settings from `packaging/cpack.cmake` and maintainer
scripts in `packaging/debian/`. Install the build and Debian packaging
requirements first:

```sh
sudo apt install build-essential cmake git ca-certificates pkgconf gettext \
  dpkg-dev file rustc cargo extra-cmake-modules qt6-base-dev \
  qt6-declarative-dev libkf6kcmutils-dev libkf6i18n-dev \
  libkf6coreaddons-dev libudev-dev
```

Then configure, build, and package from the repository root:

```sh
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
cmake --build build --parallel
(cd build && cpack -G DEB)
```

CPack writes four `.deb` files into `build/`: the `framework-settings`
meta-package and the `framework-gui`, `framework-kcm`, and `framework-kcmd`
components. Install all four local files together:

```sh
sudo apt install ./framework-*.deb
```

Alternatively, install the meta-package from a configured repository.
CPack uses `dpkg-shlibdeps` for shared-library dependencies and lists QML
runtime dependencies explicitly in `packaging/cpack.cmake`. The daemon package
owns the D-Bus, PolicyKit, and systemd files; its maintainer scripts reload
D-Bus/systemd and enable the service on install.

## Releases and CI

A release tag must match the versions in `CMakeLists.txt` and
`daemon/Cargo.toml`. Pushing a `v*` tag triggers `.github/workflows/build.yml`,
which builds the Arch and Ubuntu packages and attaches them to the GitHub
release. Fedora Git RPM builds run separately through
`.github/workflows/package-git.yml` on pushes to `main` or by manual workflow
dispatch; they are not currently part of the tagged-release artifacts.

For release steps and package-specific notes, see [Releasing](releasing.md).
