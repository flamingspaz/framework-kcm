# .deb packaging through CPack; used by CI on Ubuntu (`cpack -G DEB`)

set(CPACK_PACKAGE_NAME "framework-kcm")
set(CPACK_PACKAGE_CONTACT "Yousef <github-viral8565@pxdmail.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "System Settings module for Framework laptops")
set(CPACK_PACKAGE_DESCRIPTION "Charge limit, fans, touchpad, LEDs and firmware information for Framework laptops in KDE System Settings, with a small root D-Bus service built on framework_lib.")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "/usr")
set(CPACK_STRIP_FILES ON)

set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SECTION "kde")
# Library dependencies are found with dpkg-shlibdeps; QML modules and
# services the module needs at runtime aren't, so list those
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_DEPENDS
    "dbus, polkitd, qml6-module-org-kde-kirigami, qml6-module-org-kde-kcmutils, qml6-module-qtquick-controls, qml6-module-qtquick-layouts")
set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA
    "${CMAKE_CURRENT_LIST_DIR}/debian/preinst;${CMAKE_CURRENT_LIST_DIR}/debian/postinst;${CMAKE_CURRENT_LIST_DIR}/debian/prerm;${CMAKE_CURRENT_LIST_DIR}/debian/postrm")
set(CPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION ON)

include(CPack)
