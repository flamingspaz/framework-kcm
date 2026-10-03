// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    header: ColumnLayout {
        spacing: 0

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: !kcm.daemonAvailable
            type: Kirigami.MessageType.Error
            text: i18n("Could not reach the Framework hardware service (framework-kcmd). Make sure it is installed and that D-Bus activation or the systemd unit is enabled.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: kcm.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: kcm.errorMessage
            showCloseButton: true
            onVisibleChanged: if (!visible) kcm.clearError()
        }

        QQC2.TabBar {
            id: tabBar
            Layout.fillWidth: true

            QQC2.TabButton { text: i18n("Overview") }
            QQC2.TabButton { text: i18n("Battery") }
            QQC2.TabButton { text: i18n("Schedule") }
            QQC2.TabButton { text: i18n("Fans & Thermals") }
            QQC2.TabButton { text: i18n("Touchpad & LED") }
            QQC2.TabButton { text: i18n("System") }
        }
    }

    // Only poll what the visible tab shows
    Binding {
        target: kcm
        property: "liveData"
        value: ["", "", "", "thermal", "", "ports"][tabBar.currentIndex]
    }

    Loader {
        width: parent.width
        enabled: (kcm.daemonAvailable || kcm.fixtureMode) && !kcm.busy
        source: ["OverviewPage.qml", "BatteryPage.qml", "SchedulePage.qml", "ThermalPage.qml", "InputPage.qml", "SystemPage.qml"][tabBar.currentIndex]
    }
}
