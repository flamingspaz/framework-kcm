# Packaging

Framework KCM is packaged with distro-native tools. The packages include the
System Settings module, its D-Bus and polkit configuration, translations, and
the `frameworkd` service.

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

The versioned spec uses the `v%{version}` source archive. The Fedora specs use
Fedora's KF6 RPM macros (`%cmake_kf6`, `%cmake_build`, and `%cmake_install`)
and install the plugin under `%{_kf6_qtplugindir}`. The CI workflow for the
Git RPM is `.github/workflows/package-git.yml`.

## Arch Linux

The Arch package is described by `packaging/arch/PKGBUILD`, with service
install/removal messages in `packaging/arch/framework-kcm.install`. The release
workflow creates a versioned source archive, stages these packaging files,
sets the repository URL and version, and runs `makepkg`. The PKGBUILD expects
that staged archive next to it, so it is not a direct `makepkg` invocation from
the repository root. See `.github/workflows/build.yml` for the CI staging steps.

The package manager installs the service but does not enable it automatically.
To apply write-only touchpad and charge-rate settings at boot, enable the
service after installation:

```sh
sudo systemctl enable --now frameworkd.service
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

The `.deb` is written into `build/`. CPack uses `dpkg-shlibdeps` for shared
library dependencies; QML runtime dependencies are listed explicitly in
`packaging/cpack.cmake`. The maintainer scripts reload D-Bus and systemd,
enable the service on installation, and remove its state on purge.

## Releases and CI

A release tag must match the versions in `CMakeLists.txt` and
`daemon/Cargo.toml`. Pushing a `v*` tag triggers `.github/workflows/build.yml`,
which builds the Arch and Ubuntu packages and attaches them to the GitHub
release. Fedora Git RPM builds run separately through
`.github/workflows/package-git.yml` on pushes to `main` or by manual workflow
dispatch; they are not currently part of the tagged-release artifacts.

For release steps and package-specific notes, see [Releasing](releasing.md).
