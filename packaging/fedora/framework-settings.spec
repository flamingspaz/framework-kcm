%global appid com.github.framework-settings

Name:           framework-settings
Version:        0.1.2
Release:        1%{?dist}
Summary:        Framework laptop settings and hardware service

License:        GPL-3.0-or-later
URL:            https://github.com/flamingspaz/framework-settings
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz

BuildRequires:  cmake >= 3.22
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  git
BuildRequires:  pkgconf-pkg-config
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  kf6-kcmutils-devel
BuildRequires:  kf6-kcoreaddons-devel
BuildRequires:  kf6-ki18n-devel
BuildRequires:  kf6-rpm-macros
BuildRequires:  hidapi-devel
BuildRequires:  libusb1-devel
BuildRequires:  systemd-devel
BuildRequires:  libudev-devel
BuildRequires:  systemd-rpm-macros
BuildRequires:  terra-appstream-helper
BuildRequires:  cargo-rpm-macros
BuildRequires:  anda-srpm-macros

Suggests:       framework-gui%{?_isa} = %{evr}
Suggests:       framework-kcm%{?_isa} = %{evr}
Recommends:     frameworkd%{?_isa} = %{evr}

Packager:       Cypress Reed <cypress@fyralabs.com>

%description
Meta-package for Framework laptop settings. Installs the standalone Qt
application, the KDE System Settings module, and the hardware service.

%package -n framework-gui
Summary:        Standalone Qt settings application for Framework laptops
Requires:       framework-settings%{?_isa} = %{evr}
Requires:       frameworkd%{?_isa} = %{evr}
Requires:       hicolor-icon-theme
Requires:       qt6-qtdeclarative

%description -n framework-gui
Standalone Qt application for configuring Framework laptop battery charging,
fans, touchpad, LEDs, firmware information, and USB-C ports. It does not
require KDE.

%package -n framework-kcm
Summary:        KDE System Settings module for Framework laptops
Requires:       framework-settings%{?_isa} = %{evr}
Requires:       frameworkd%{?_isa} = %{evr}
Requires:       plasma-systemsettings
Requires:       kf6-kcmutils
Requires:       kf6-kirigami
Requires:       qt6-qtdeclarative
Requires:       hicolor-icon-theme

%description -n framework-kcm
KDE System Settings module for configuring Framework laptop battery charging,
fans, touchpad, LEDs, firmware information, and USB-C ports.

%package -n frameworkd
Summary:        System service for Framework laptop hardware settings
Requires:       framework-settings%{?_isa} = %{evr}
Provides:       framework-kcmd = %{evr}
Obsoletes:      framework-kcmd <= %{evr}
Requires:       dbus
Requires:       polkit
Requires:       systemd
SourceLicense:  GPL-3.0-or-later
License:        %{sourcelicense} AND (Apache-2.0 OR MIT) AND MIT AND ((MIT OR Apache-2.0) AND Unicode-3.0) AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND GPL-3.0-or-later AND MPL-2.0 AND (BSD-2-Clause OR Apache-2.0 OR MIT) AND BSD-3-Clause AND (MIT OR Apache-2.0 OR LGPL-2.1-or-later) AND (Unlicense OR MIT)

%description -n frameworkd
System service that provides privileged hardware access for the Framework
laptop settings interfaces.

%prep
%autosetup -n framework-settings-%{version}

%conf
%cmake_kf6 -DINSTALL_PACKAGE_DOCS=OFF

%build
%cmake_build
cd daemon
%{cargo_license_summary_online}
%{cargo_license_online} > ../LICENSE.dependencies
cd ..

%install
%cmake_install
%find_lang kcm_framework

%terra_appstream

%pre -n frameworkd
# Up to 0.1.1 the daemon was called framework-kcmd. Its unit file is still
# installed at this point, so disable it here (otherwise the enable symlink
# is left dangling), remember whether it was enabled, and move its state.
if [ -e %{_unitdir}/framework-kcmd.service ]; then
    if systemctl is-enabled --quiet framework-kcmd.service 2>/dev/null; then
        touch %{_rundir}/frameworkd-migrate-enable
    fi
    systemctl disable --now framework-kcmd.service >/dev/null 2>&1 || :
    if [ -d %{_sharedstatedir}/framework-kcmd ] && [ ! -e %{_sharedstatedir}/frameworkd ]; then
        mv %{_sharedstatedir}/framework-kcmd %{_sharedstatedir}/frameworkd
    fi
fi

%post -n frameworkd
%systemd_post frameworkd.service
if [ -e %{_rundir}/frameworkd-migrate-enable ]; then
    rm -f %{_rundir}/frameworkd-migrate-enable
    systemctl daemon-reload >/dev/null 2>&1 || :
    systemctl enable --now frameworkd.service >/dev/null 2>&1 || :
fi

%preun -n frameworkd
%systemd_preun frameworkd.service

%postun -n frameworkd
%systemd_postun_with_restart frameworkd.service

%files
%license LICENSE
%doc README.md docs/*.md

%files -n framework-gui
%{_bindir}/framework-settings
%{_appsdir}/io.github.frameworkkcm.desktop
%{_scalableiconsdir}/framework-gui.svg
%{_metainfodir}/%{appid}.metainfo.xml

%files -n framework-kcm -f kcm_framework.lang
%{_kf6_qtplugindir}/plasma/kcms/systemsettings/kcm_framework.so
%{_appsdir}/kcm_framework.desktop
%{_scalableiconsdir}/framework-kcm.svg

%files -n frameworkd
%license LICENSE.dependencies
%{_datadir}/dbus-1/system.d/io.github.frameworkkcm.Daemon1.conf
%{_datadir}/dbus-1/system-services/io.github.frameworkkcm.Daemon1.service
%{_unitdir}/frameworkd.service
%{_libexecdir}/frameworkd
%{_datadir}/polkit-1/actions/io.github.frameworkkcm.policy

%changelog
* Mon Oct 05 2026 Cypress Reed <cypress@fyralabs.com>
- handle desktop GUI split

* Sun Oct 04 2026 Cypress Reed <cypress@fyralabs.com>
- handle frameworkd rename

* Fri Oct 02 2026 Cypress Reed <cypress@fyralabs.com>
- Initial package
