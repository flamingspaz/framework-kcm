# Debian packages are split by install component. The meta package installs
# shared documentation and depends on the functional packages built here.
set(CPACK_PACKAGE_NAME "framework-settings")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_CONTACT "Yousef <github-viral8565@pxdmail.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Framework laptop hardware settings")
set(CPACK_PACKAGE_DESCRIPTION "Qt and KDE settings interfaces for Framework laptops and the system service that applies hardware settings.")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "/usr")
set(CPACK_STRIP_FILES ON)

set(CPACK_DEB_COMPONENT_INSTALL ON)
set(CPACK_COMPONENTS_GROUPING IGNORE)
set(CPACK_COMPONENTS_ALL meta)
set(_framework_meta_dependencies)
if(BUILD_GUI)
  list(APPEND CPACK_COMPONENTS_ALL gui)
  list(APPEND _framework_meta_dependencies "framework-gui (= ${PROJECT_VERSION})")
endif()
if(BUILD_KCM)
  list(APPEND CPACK_COMPONENTS_ALL kcm)
  list(APPEND _framework_meta_dependencies "framework-kcm (= ${PROJECT_VERSION})")
endif()
if(BUILD_DAEMON)
  list(APPEND CPACK_COMPONENTS_ALL kcmd)
  list(APPEND _framework_meta_dependencies "framework-kcmd (= ${PROJECT_VERSION})")
endif()
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION ON)

set(CPACK_DEBIAN_META_PACKAGE_NAME "framework-settings")
set(CPACK_DEBIAN_META_PACKAGE_ARCHITECTURE "all")
set(CPACK_DEBIAN_META_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_META_DESCRIPTION
    "Meta-package for Framework laptop hardware settings. Installs the Qt GUI, KDE System Settings module, and system service.")
if(_framework_meta_dependencies)
  list(JOIN _framework_meta_dependencies ", " CPACK_DEBIAN_META_PACKAGE_DEPENDS)
endif()

set(CPACK_DEBIAN_GUI_PACKAGE_NAME "framework-gui")
set(CPACK_DEBIAN_GUI_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_GUI_DESCRIPTION
    "Standalone Qt application for managing Framework laptop charging, fans, touchpad, LED, and firmware settings.")
set(CPACK_DEBIAN_GUI_PACKAGE_DEPENDS
    "framework-kcmd, hicolor-icon-theme, qml6-module-qtquick-controls, qml6-module-qtquick-layouts")

set(CPACK_DEBIAN_KCM_PACKAGE_NAME "framework-kcm")
set(CPACK_DEBIAN_KCM_PACKAGE_SECTION "kde")
set(CPACK_DEBIAN_KCM_DESCRIPTION
    "KDE System Settings module for Framework laptop charging, fans, touchpad, LED, and firmware settings.")
set(CPACK_DEBIAN_KCM_PACKAGE_DEPENDS
    "framework-kcmd, hicolor-icon-theme, systemsettings, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, qml6-module-qtquick-controls, qml6-module-qtquick-layouts")

set(CPACK_DEBIAN_KCMD_PACKAGE_NAME "framework-kcmd")
set(CPACK_DEBIAN_KCMD_PACKAGE_SECTION "admin")
set(CPACK_DEBIAN_KCMD_DESCRIPTION
    "System service providing privileged hardware access for Framework laptop settings.")
set(CPACK_DEBIAN_KCMD_PACKAGE_DEPENDS "dbus, polkitd, systemd")
set(CPACK_DEBIAN_KCMD_PACKAGE_CONTROL_EXTRA
    "${CMAKE_CURRENT_LIST_DIR}/debian/postinst;${CMAKE_CURRENT_LIST_DIR}/debian/prerm;${CMAKE_CURRENT_LIST_DIR}/debian/postrm")

include(CPack)
