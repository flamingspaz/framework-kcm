cmake_minimum_required(VERSION 3.22)
project(framework-kcm VERSION 0.1.1)

set(QT_MIN_VERSION "6.6.0")
set(KF_MIN_VERSION "6.0.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus Qml Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)

option(BUILD_DAEMON "Build the frameworkd system service with cargo" ON)

set(DAEMON_PATH "${KDE_INSTALL_FULL_LIBEXECDIR}/frameworkd" CACHE FILEPATH "Path to the Daemon build to use if BUILD_DAEMON=OFF")
if(BUILD_DAEMON AND NOT DAEMON_PATH STREQUAL "${KDE_INSTALL_FULL_LIBEXECDIR}/frameworkd")
    message(FATAL_ERROR "Do not modify DAEMON_PATH if BUILD_DAEMON=ON")
endif()

if(BUILD_DAEMON)
    find_program(CARGO cargo REQUIRED)
    set(CARGO_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo")
    add_custom_target(frameworkd ALL
        COMMAND ${CARGO} build --release --locked
            --manifest-path "${CMAKE_SOURCE_DIR}/daemon/Cargo.toml"
            --target-dir "${CARGO_TARGET_DIR}"
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/daemon"
        USES_TERMINAL
        COMMENT "Building frameworkd with cargo")
    install(PROGRAMS "${CARGO_TARGET_DIR}/release/frameworkd" DESTINATION ${KDE_INSTALL_LIBEXECDIR})
endif()

configure_file(data/io.github.frameworkkcm.Daemon1.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/io.github.frameworkkcm.Daemon1.service @ONLY)
configure_file(data/frameworkd.service.in
               ${CMAKE_CURRENT_BINARY_DIR}/frameworkd.service @ONLY)

install(FILES data/io.github.frameworkkcm.Daemon1.conf DESTINATION ${KDE_INSTALL_DBUSDIR}/system.d)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/io.github.frameworkkcm.Daemon1.service
        DESTINATION ${KDE_INSTALL_DBUSSYSTEMSERVICEDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/frameworkd.service
        DESTINATION ${KDE_INSTALL_SYSTEMDUNITDIR}/system)
install(FILES data/io.github.frameworkkcm.policy DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions)
install(FILES data/icons/framework-kcm.svg DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

add_subdirectory(kcm)
ki18n_install(po)

include(packaging/cpack.cmake)

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
