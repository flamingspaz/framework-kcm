%global _version 0.1.1

Name:           framework-settings
Version:        %{_version}^%{autogitversion}
Release:        1%{?dist}
Summary:        Framework laptop settings and hardware service (git)

License:        GPL-3.0-or-later
URL:            https://github.com/flamingspaz/framework-kcm
Source0:        %{url}/archive/%{autogitcommit}.tar.gz

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

Requires:       framework-gui%{?_isa} = %{evr}
Requires:       framework-kcm%{?_isa} = %{evr}
Requires:       framework-kcmd%{?_isa} = %{evr}

Packager:       Cypress Reed <cypress@fyralabs.com>

%description
Meta-package for Framework laptop settings. Installs the standalone Qt
application, the KDE System Settings module, and the hardware service.

%package -n framework-gui
Summary:        Standalone Qt settings application for Framework laptops
Requires:       framework-kcmd%{?_isa} = %{evr}
Requires:       hicolor-icon-theme
Requires:       qt6-qtdeclarative

%description -n framework-gui
Standalone Qt application for configuring Framework laptop battery charging,
fans, touchpad, LEDs, firmware information, and USB-C ports. It does not
require KDE.

%package -n framework-kcm
Summary:        KDE System Settings module for Framework laptops
Requires:       framework-kcmd%{?_isa} = %{evr}
Requires:       plasma-systemsettings
Requires:       kf6-kcmutils
Requires:       kf6-kirigami
Requires:       qt6-qtdeclarative
Requires:       hicolor-icon-theme

%description -n framework-kcm
KDE System Settings module for configuring Framework laptop battery charging,
fans, touchpad, LEDs, firmware information, and USB-C ports.

%package -n framework-kcmd
Summary:        System service for Framework laptop hardware settings
Requires:       dbus
Requires:       polkit
Requires:       systemd

%description -n framework-kcmd
System service that provides privileged hardware access for the Framework
laptop settings interfaces.

%prep
%autosetup -n framework-kcm-%{autogitcommit}

%conf
%cmake_kf6 -DINSTALL_PACKAGE_DOCS=OFF

%build
%cmake_build

%install
%cmake_install
%find_lang kcm_framework

%post -n framework-kcmd
%systemd_post framework-kcmd.service

%preun -n framework-kcmd
%systemd_preun framework-kcmd.service

%postun -n framework-kcmd
%systemd_postun_with_restart framework-kcmd.service

%files
%license LICENSE
%doc README.md

%files -n framework-gui
%license LICENSE
%{_bindir}/framework-settings
%{_appsdir}/io.github.frameworkkcm.desktop
%{_datadir}/icons/hicolor/scalable/apps/framework-gui.svg

%files -n framework-kcm -f kcm_framework.lang
%license LICENSE
%{_kf6_qtplugindir}/plasma/kcms/systemsettings/kcm_framework.so
%{_appsdir}/kcm_framework.desktop
%{_datadir}/icons/hicolor/scalable/apps/framework-kcm.svg

%files -n framework-kcmd
%license LICENSE
%{_datadir}/dbus-1/system.d/io.github.frameworkkcm.Daemon1.conf
%{_datadir}/dbus-1/system-services/io.github.frameworkkcm.Daemon1.service
%{_unitdir}/framework-kcmd.service
%{_libexecdir}/framework-kcmd
%{_datadir}/polkit-1/actions/io.github.frameworkkcm.policy

%changelog
* Fri Oct 02 2026 Cypress Reed <cypress@fyralabs.com>
- Split GUI, KCM, and hardware service into independent subpackages
