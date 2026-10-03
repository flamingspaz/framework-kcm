# CI and releases

See [Packaging](packaging.md) for local package build commands and an overview
of the Fedora, Arch, and Ubuntu packaging workflows.

GitHub Actions (`.github/workflows/build.yml`) builds and install-tests the
project in an Arch container on every push to `main` and on every pull
request. It also warns if `po/` is out of date with the source.

## Cutting a release

1. Bump the version in `CMakeLists.txt` (`project(framework-kcm VERSION ...)`), `daemon/Cargo.toml`, and `packaging/fedora/framework-kcm.spec` then commit.
2. Tag the commit and push the tag:

   ```sh
   git tag -a v0.2.0 -m "framework-kcm 0.2.0"
   git push origin v0.2.0
   ```

On a `v*` tag, the workflow:

1. Checks that the tag matches both versions, and stops if it doesn't.
2. Builds the packages in parallel:

   | Distribution | Package                                        | Built with                              |
   | ------------ | ---------------------------------------------- | --------------------------------------- |
   | Arch Linux   | `framework-kcm-<version>-1-x86_64.pkg.tar.zst` | `packaging/arch/PKGBUILD` and `makepkg` |
   | Ubuntu 26.04 | `framework-kcm_<version>_amd64.deb`            | CPack (`packaging/cpack.cmake`)         |

3. Creates a GitHub release for the tag, attaches both packages, and writes
   release notes from the commits since the last tag.

## Packaging notes

- **Arch:** CI builds the `PKGBUILD` from a `git archive` tarball and fills in
  `pkgver` and `url`. LTO is turned off (`options=('!lto')`) because GCC LTO
  objects from hidapi's bundled C code can't be read by the linker cargo
  uses. The `-debug` split package isn't attached to releases.
  `framework-kcm.install` reminds the user to enable the service.
- **Ubuntu:** `dpkg-shlibdeps` works out the library dependencies. The QML
  modules and services needed only at runtime are listed by hand in
  `packaging/cpack.cmake`. The maintainer scripts in `packaging/debian/`
  enable the service on install, disable it on removal, and delete
  `/var/lib/frameworkd` on purge.
