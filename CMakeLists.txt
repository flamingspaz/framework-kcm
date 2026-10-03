cmake_minimum_required(VERSION 3.22)
project(framework-kcm VERSION 0.1.1)

set(QT_MIN_VERSION "6.6.0")
set(KF_MIN_VERSION "6.0.0")

option(BUILD_KCM "Build the KDE System Settings module" ON)
option(BUILD_GUI "Build the standalone Qt settings application" ON)
option(BUILD_DAEMON "Build the framework-kcmd system service with cargo" ON)
option(INSTALL_PACKAGE_DOCS "Install the license and README through CMake" ON)

if(BUILD_KCM)
  find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
  set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

  include(KDEInstallDirs)
  include(KDECMakeSettings)
  include(KDECompilerSettings NO_POLICY_SCOPE)
  find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)
else()
  include(GNUInstallDirs)
  set(KDE_INSTALL_BINDIR "${CMAKE_INSTALL_BINDIR}")
  set(KDE_INSTALL_LIBEXECDIR "${CMAKE_INSTALL_LIBEXECDIR}")
  set(KDE_INSTALL_FULL_LIBEXECDIR "${CMAKE_INSTALL_FULL_LIBEXECDIR}")
  set(KDE_INSTALL_DATADIR "${CMAKE_INSTALL_DATADIR}")
  set(KDE_INSTALL_DBUSDIR "${CMAKE_INSTALL_DATADIR}/dbus-1/system.d")
  set(KDE_INSTALL_DBUSSYSTEMSERVICEDIR "${CMAKE_INSTALL_DATADIR}/dbus-1/system-services")
  set(KDE_INSTALL_SYSTEMDUNITDIR "${CMAKE_INSTALL_LIBDIR}/systemd/system")
  set(KDE_INSTALL_ICONDIR "${CMAKE_INSTALL_DATADIR}/icons")
endif()

include(FeatureSummary)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus Qml Quick)
if(BUILD_GUI)
  find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS QuickControls2)
endif()
qt_policy(SET QTP0001 NEW)

set(DAEMON_PATH "${KDE_INSTALL_FULL_LIBEXECDIR}/framework-kcmd" CACHE FILEPATH "Path to the Daemon build to use if BUILD_DAEMON=OFF")
if(BUILD_DAEMON AND NOT DAEMON_PATH STREQUAL "${KDE_INSTALL_FULL_LIBEXECDIR}/framework-kcmd")
  message(FATAL_ERROR "Do not modify DAEMON_PATH if BUILD_DAEMON=ON")
endif()

if(BUILD_DAEMON)
  find_program(CARGO cargo REQUIRED)
  set(CARGO_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo")
  add_custom_target(framework-kcmd ALL
        COMMAND ${CARGO} build --release --locked
            --manifest-path "${CMAKE_SOURCE_DIR}/daemon/Cargo.toml"
            --target-dir "${CARGO_TARGET_DIR}"
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/daemon"
        USES_TERMINAL
        COMMENT "Building framework-kcmd with cargo")
  install(PROGRAMS "${CARGO_TARGET_DIR}/release/framework-kcmd" DESTINATION ${KDE_INSTALL_LIBEXECDIR} COMPONENT kcmd)
endif()

configure_file(data/io.github.frameworkkcm.Daemon1.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/io.github.frameworkkcm.Daemon1.service @ONLY)
configure_file(data/framework-kcmd.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/framework-kcmd.service @ONLY)

if(BUILD_KCM OR BUILD_DAEMON)
  install(FILES data/io.github.frameworkkcm.Daemon1.conf DESTINATION ${KDE_INSTALL_DBUSDIR}/system.d COMPONENT kcmd)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/io.github.frameworkkcm.Daemon1.service
            DESTINATION ${KDE_INSTALL_DBUSSYSTEMSERVICEDIR} COMPONENT kcmd)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/framework-kcmd.service
            DESTINATION ${KDE_INSTALL_SYSTEMDUNITDIR}/system COMPONENT kcmd)
  install(FILES data/io.github.frameworkkcm.policy DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions COMPONENT kcmd)
endif()
if(BUILD_KCM)
  install(FILES data/icons/framework-kcm.svg
          DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps COMPONENT kcm)
endif()
if(BUILD_GUI)
  install(FILES data/icons/framework-kcm.svg
          DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps
          RENAME framework-gui.svg COMPONENT gui)
endif()

if(INSTALL_PACKAGE_DOCS)
  install(FILES LICENSE README.md
          DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/doc/framework-settings COMPONENT meta)
endif()

if(BUILD_KCM)
  set(_install_default_component "${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}")
  set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME kcm)
  add_subdirectory(kcm)
  ki18n_install(po)
  set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME "${_install_default_component}")
  unset(_install_default_component)
endif()

if(BUILD_GUI)
  add_subdirectory(gui)
endif()

include(packaging/cpack.cmake)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
