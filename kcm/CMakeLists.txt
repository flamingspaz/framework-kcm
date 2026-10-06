add_definitions(-DTRANSLATION_DOMAIN=\"kcm_framework\")

kcmutils_add_qml_kcm(kcm_framework SOURCES
    frameworkkcm.cpp
    frameworkkcm.h
    plugin.cpp
)

target_link_libraries(kcm_framework PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Quick
    KF6::CoreAddons
    KF6::I18n
    KF6::KCMUtilsQuick
)
