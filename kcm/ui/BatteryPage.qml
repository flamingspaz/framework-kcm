// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    RowLayout {
        Kirigami.FormData.label: i18n("Battery:")
        spacing: Kirigami.Units.largeSpacing

        Item {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 9

            Rectangle {
                id: batteryBody
                anchors.centerIn: parent
                width: Kirigami.Units.gridUnit * 4
                height: Kirigami.Units.gridUnit * 7
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                border.width: 3
                border.color: Kirigami.Theme.textColor
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 3
                    anchors.rightMargin: 3
                    anchors.bottomMargin: 3
                    height: (parent.height - 6) * Math.max(0, Math.min(100, kcm.powerInfo.percentage ?? 0)) / 100
                    color: (kcm.powerInfo.percentage ?? 100) <= 20
                        ? Kirigami.Theme.negativeTextColor
                        : Kirigami.Theme.highlightColor
                }

                QQC2.Label {
                    anchors.centerIn: parent
                    text: kcm.powerInfo.batteryPresent && (kcm.powerInfo.percentage ?? -1) >= 0
                        ? i18nc("percent", "%1%", kcm.powerInfo.percentage)
                        : "--"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
                }
            }

            Rectangle {
                anchors.horizontalCenter: batteryBody.horizontalCenter
                anchors.bottom: batteryBody.top
                width: Kirigami.Units.smallSpacing * 2
                height: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.textColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: {
                    const power = kcm.powerInfo;
                    if (!power.batteryPresent) return i18n("Battery unavailable");
                    if (power.charging) return i18n("Charging");
                    if (power.discharging) return i18n("Discharging");
                    return i18n("Not charging");
                }
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            }
            QQC2.Label {
                text: kcm.powerInfo.acPresent === undefined
                    ? i18n("Power status unavailable")
                    : kcm.powerInfo.acPresent ? i18n("AC power connected") : i18n("Running on battery")
                color: Kirigami.Theme.disabledTextColor
            }
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: kcm.chargeLimit > 0 ? i18n("Charge limit: %1%", kcm.chargeLimit) : i18n("Charge limit unavailable")
            }
        }
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Charging")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Charge limit:")
        enabled: !kcm.chargeLimitOverridden
        QQC2.Slider {
            id: limitSlider
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            from: 25
            to: 100
            stepSize: 5
            snapMode: QQC2.Slider.SnapAlways
            value: kcm.chargeLimit
            onMoved: kcm.chargeLimit = value
        }
        QQC2.Label {
            text: i18nc("percent", "%1%", limitSlider.value)
        }
    }

    HintLabel {
        text: i18n("Stops charging at this level. Keeping the battery below 100% helps it age slower. Plasma's Power Management page can set the same limit through the kernel driver; use only one of them.")
    }

    QQC2.Button {
        visible: !kcm.chargeLimitOverridden
        enabled: kcm.chargeLimit < 100
        icon.name: "battery-full-charging"
        text: i18n("Override Charge Limit")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        QQC2.ToolTip.text: i18n("Charge to 100% once. The limit goes back to %1% the next time the computer starts.", kcm.chargeLimit)
        onClicked: kcm.overrideChargeLimit()
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: kcm.chargeLimitOverridden
        type: Kirigami.MessageType.Information
        text: i18n("Charging to 100% until the computer restarts. The limit then goes back to %1%.", kcm.chargeLimit)
        actions: Kirigami.Action {
            icon.name: "edit-undo"
            text: i18n("Restore Now")
            onTriggered: kcm.cancelChargeLimitOverride()
        }
    }

    QQC2.CheckBox {
        id: rateCheck
        Kirigami.FormData.label: i18n("Charge speed:")
        text: i18n("Limit charging speed")
        checked: kcm.chargeRateLimit < 1.0
        onToggled: kcm.chargeRateLimit = checked ? 0.5 : 1.0
    }

    RowLayout {
        visible: rateCheck.checked
        QQC2.Slider {
            id: rateSlider
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            from: 0.1
            to: 0.9
            stepSize: 0.1
            snapMode: QQC2.Slider.SnapAlways
            value: kcm.chargeRateLimit
            onMoved: kcm.chargeRateLimit = Math.round(value * 10) / 10
        }
        QQC2.Label {
            // Hours from empty to full, without a trailing ".0"
            readonly property real hours: Math.round(10 / rateSlider.value) / 10

            // Charging current as a multiple of full speed (the battery's C-rate)
            text: i18nc("charge speed multiplier, hours to charge from empty", "%1× (about %2 h from empty)",
                        Number(rateSlider.value).toLocaleString(Qt.locale(), "f", 1),
                        Number(hours).toLocaleString(Qt.locale(), "f", Number.isInteger(hours) ? 0 : 1))
        }
    }

    RowLayout {
        visible: rateCheck.checked
        QQC2.CheckBox {
            id: socCheck
            text: i18n("Only above battery level:")
            checked: kcm.chargeRateSoc >= 0
            onToggled: kcm.chargeRateSoc = checked ? 80 : -1
        }
        QQC2.SpinBox {
            enabled: socCheck.checked
            from: 0
            to: 100
            stepSize: 5
            value: Math.max(0, kcm.chargeRateSoc)
            onValueModified: kcm.chargeRateSoc = value
            textFromValue: (v) => i18nc("percent", "%1%", v)
        }
    }

    HintLabel {
        visible: rateCheck.checked
        text: i18n("Relative to full charging speed. Slower charging produces less heat and wears the battery less; times are approximate. The EC forgets this limit on reset, so the service re-applies it when it starts.")
    }
}
