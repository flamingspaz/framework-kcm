// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    clip: true
    contentWidth: availableWidth

    property double clock: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.clock = Date.now()
    }

    function nextScheduleSummary() {
        if (!kcm.scheduleEnabled) {
            return "";
        }

        const now = new Date(root.clock);
        const weekdayNumber = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 0};
        let nextTime = null;
        let nextLimit = 0;
        for (let i = 0; i < kcm.schedules.length; ++i) {
            const entry = kcm.schedules[i];
            const match = /^(?:([01]\d|2[0-3])):([0-5]\d)$/.exec(entry.time);
            if (!match) {
                continue;
            }
            for (let j = 0; j < entry.days.length; ++j) {
                const dayNumber = weekdayNumber[entry.days[j]];
                if (dayNumber === undefined) {
                    continue;
                }
                const daysUntil = (dayNumber - now.getDay() + 7) % 7;
                const candidate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysUntil,
                                           Number(match[1]), Number(match[2]), 0, 0);
                if (candidate <= now) {
                    candidate.setDate(candidate.getDate() + 7);
                }
                if (nextTime === null || candidate < nextTime) {
                    nextTime = candidate;
                    nextLimit = entry.limit;
                }
            }
        }
        if (nextTime === null) {
            return "";
        }
        const time = Qt.formatDateTime(nextTime, "HH:mm");
        let relativeTime;
        if (nextTime.getFullYear() === now.getFullYear()
            && nextTime.getMonth() === now.getMonth()
            && nextTime.getDate() === now.getDate()) {
            relativeTime = qsTr("at %1").arg(time);
        } else {
            const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
            if (nextTime.getFullYear() === tomorrow.getFullYear()
                && nextTime.getMonth() === tomorrow.getMonth()
                && nextTime.getDate() === tomorrow.getDate()) {
                relativeTime = qsTr("tomorrow at %1").arg(time);
            } else {
                relativeTime = qsTr("%1 at %2").arg(Qt.formatDateTime(nextTime, "dddd")).arg(time);
            }
        }
        return qsTr("Next scheduled change: %1% %2").arg(nextLimit).arg(relativeTime);
    }

    ColumnLayout {
        width: root.availableWidth
        spacing: 12

        Label {
            Layout.fillWidth: true
            visible: kcm.fixtureMode
            wrapMode: Text.Wrap
            color: palette.text
            text: qsTr("Fixture mode is active. Readings are simulated, changes stay in memory, and no hardware service is contacted.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            GroupBox {
                Layout.fillWidth: true
                visible: kcm.fixtureMode
                title: qsTr("Test hardware profile")
                ColumnLayout {
                    anchors.fill: parent
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Choose a profile to preview model-specific controls.")
                        wrapMode: Text.Wrap
                    }
                    ComboBox {
                        Layout.fillWidth: true
                        textRole: "name"
                        valueRole: "id"
                        model: kcm.fixtureModels
                        Component.onCompleted: currentIndex = indexOfValue(kcm.fixtureModel)
                        onActivated: kcm.setFixtureModel(currentValue)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Keyboard backlight: %1 · Fingerprint LED: %2 · Input deck: %3 · Touchscreen: %4 · Tablet mode: %5")
                              .arg(kcm.supportsKeyboardBacklight ? qsTr("Yes") : qsTr("No"))
                              .arg(kcm.fpLedSupported ? qsTr("Yes") : qsTr("No"))
                              .arg(kcm.supportsInputDeck ? qsTr("Yes") : qsTr("No"))
                              .arg(kcm.supportsTouchscreen ? qsTr("Yes") : qsTr("No"))
                              .arg(kcm.supportsTabletMode ? qsTr("Yes") : qsTr("No"))
                        wrapMode: Text.Wrap
                        color: palette.text
                    }
                }
            }

            GroupBox {
                Layout.fillWidth: true
                title: qsTr("Battery")
                ColumnLayout {
                    anchors.fill: parent
                    Label {
                        Layout.fillWidth: true
                        text: {
                            const power = kcm.powerInfo;
                            if (!power.batteryPresent) return qsTr("Battery status unavailable");
                            if (power.charging) return qsTr("Charging");
                            if (power.discharging) return qsTr("Discharging");
                            return qsTr("Not charging");
                        }
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: kcm.powerInfo.batteryPresent && kcm.powerInfo.percentage >= 0
                              ? qsTr("%1% · %2").arg(kcm.powerInfo.percentage)
                                    .arg(kcm.powerInfo.acPresent ? qsTr("AC power connected") : qsTr("Running on battery"))
                              : qsTr("Battery readings unavailable")
                        wrapMode: Text.Wrap
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        visible: kcm.powerInfo.batteryPresent && kcm.powerInfo.percentage >= 0
                        from: 0
                        to: 100
                        value: kcm.powerInfo.percentage ?? 0
                    }
                    Label {
                        Layout.fillWidth: true
                        text: kcm.chargeLimit > 0 ? qsTr("Charge limit: %1%").arg(kcm.chargeLimit)
                                                  : qsTr("Charge limit unavailable")
                        color: palette.text
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.nextScheduleSummary().length > 0
                        text: root.nextScheduleSummary()
                        color: palette.text
                        wrapMode: Text.Wrap
                    }
                }
            }

            GroupBox {
                Layout.fillWidth: true
                title: qsTr("Thermals and fans")
                ColumnLayout {
                    anchors.fill: parent
                    Label {
                        Layout.fillWidth: true
                        text: kcm.sensors.length > 0
                              ? kcm.sensors.filter(sensor => sensor.status === "ok")
                                    .map(sensor => qsTr("%1: %2 °C").arg(sensor.name || sensor.location).arg(sensor.temp))
                                    .join(" · ")
                              : qsTr("Temperature readings unavailable")
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: kcm.fans.length > 0
                              ? kcm.fans.map(fan => qsTr("%1: %2 RPM").arg(fan.name || fan.position).arg(fan.rpm)).join(" · ")
                              : qsTr("Fan readings unavailable")
                        color: palette.text
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: {
                            const t = kcm.throttle;
                            if (!t.known) return qsTr("Throttling: unknown");
                            if (t.hard) return qsTr("Throttling: yes (PROCHOT)");
                            return t.soft ? qsTr("Throttling: yes (soft limit)") : qsTr("Not throttling");
                        }
                    }
                }
            }

            GroupBox {
                Layout.fillWidth: true
                title: qsTr("Device and firmware")
                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 6
                    Label { text: qsTr("Model"); color: palette.text }
                    Label { Layout.fillWidth: true; text: kcm.systemInfo.product || qsTr("Unknown"); wrapMode: Text.Wrap }
                    Label { text: qsTr("BIOS"); color: palette.text }
                    Label { Layout.fillWidth: true; text: kcm.systemInfo.biosVersion || qsTr("Unknown"); wrapMode: Text.Wrap }
                    Label { text: qsTr("EC"); color: palette.text }
                    Label { Layout.fillWidth: true; text: kcm.systemInfo.ecVersion || qsTr("Unknown"); wrapMode: Text.Wrap }
                }
            }
        }
    }
}
