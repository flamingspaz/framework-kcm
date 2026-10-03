// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root
    spacing: Kirigami.Units.largeSpacing
    property double scheduleNow: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.scheduleNow = Date.now()
    }

    function nextScheduleSummary() {
        if (!kcm.scheduleEnabled) {
            return "";
        }

        const now = new Date(root.scheduleNow);
        const weekdayNumber = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 0};
        let nextTime = null;
        let nextLimit = 0;
        for (let i = 0; i < kcm.schedules.length; ++i) {
            const entry = kcm.schedules[i];
            const match = /^(?:([01]\d|2[0-3])):([0-5]\d)$/.exec(entry.time);
            if (!match) {
                continue;
            }
            const days = entry.days;
            for (let j = 0; j < days.length; ++j) {
                const dayNumber = weekdayNumber[days[j]];
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
            relativeTime = i18n("at %1", time);
        } else {
            const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
            if (nextTime.getFullYear() === tomorrow.getFullYear()
                && nextTime.getMonth() === tomorrow.getMonth()
                && nextTime.getDate() === tomorrow.getDate()) {
                relativeTime = i18n("tomorrow at %1", time);
            } else {
                relativeTime = i18n("%1 at %2", Qt.formatDateTime(nextTime, "dddd"), time);
            }
        }
        return i18n("Next scheduled change: %1% %2", nextLimit, relativeTime);
    }

    Kirigami.Heading {
        level: 1
        text: i18n("Framework Laptop")
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    QQC2.Label {
        Layout.fillWidth: true
        text: kcm.systemInfo.product || i18n("Framework hardware overview")
        color: Kirigami.Theme.disabledTextColor
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: kcm.fixtureMode
        type: Kirigami.MessageType.Information
        text: i18n("Fixture mode is active. Values are simulated, and changes stay in memory; no hardware service is contacted.")
    }

    ControlsFrame {
        Layout.fillWidth: true
        title: i18n("Battery")
        detail: {
            const power = kcm.powerInfo;
            const percent = power.percentage ?? -1;
            if (!power.batteryPresent || percent < 0) {
                return i18n("Battery status unavailable");
            }
            const state = power.charging ? i18n("Charging") : power.discharging ? i18n("Discharging") : i18n("Not charging");
            const source = power.acPresent ? i18n("AC power connected") : i18n("Running on battery");
            return i18n("%1% · %2 · %3", percent, state, source);
        }
        secondary: kcm.chargeLimit > 0 ? i18n("Charge limit: %1%", kcm.chargeLimit) : i18n("Charge limit unavailable")
        tertiary: root.nextScheduleSummary()
    }

    ControlsFrame {
        Layout.fillWidth: true
        title: i18n("Thermals")
        detail: {
            if (kcm.sensors.length === 0) {
                return i18n("Temperature readings unavailable");
            }
            return kcm.sensors.filter(sensor => sensor.status === "ok").map(sensor => i18n("%1: %2 °C", sensor.name, sensor.temp)).join(" · ");
        }
        secondary: {
            if (kcm.fans.length === 0) {
                return i18n("Fan readings unavailable");
            }
            return kcm.fans.map(fan => i18n("%1: %2 RPM", fan.name, fan.rpm)).join(" · ");
        }
    }

    ControlsFrame {
        Layout.fillWidth: true
        title: i18n("System")
        detail: kcm.systemInfo.product || i18n("Model information unavailable")
        secondary: kcm.systemInfo.biosVersion ? i18n("BIOS %1 · EC %2", kcm.systemInfo.biosVersion, kcm.systemInfo.ecVersion || i18n("Unknown")) : i18n("Firmware information unavailable")
    }

    ControlsFrame {
        Layout.fillWidth: true
        visible: kcm.fixtureMode
        title: i18n("Test fixture")
        detail: i18n("Choose a hardware profile to preview model-specific controls.")
        secondary: i18n("Keyboard backlight: %1 · Fingerprint LED: %2 · Input deck: %3 · Touchscreen: %4 · Tablet mode: %5", kcm.supportsKeyboardBacklight ? i18n("yes") : i18n("no"), kcm.fpLedSupported ? i18n("yes") : i18n("no"), kcm.supportsInputDeck ? i18n("yes") : i18n("no"), kcm.supportsTouchscreen ? i18n("yes") : i18n("no"), kcm.supportsTabletMode ? i18n("yes") : i18n("no"))

        content: QQC2.ComboBox
        {
            id: fixtureModelSelector
            Layout.fillWidth: true
            textRole: "name"
            valueRole: "id"
            model: kcm.fixtureModels
            Component.onCompleted: currentIndex = indexOfValue(kcm.fixtureModel)
            onActivated: kcm.setFixtureModel(currentValue)
        }
    }

    component
    ControlsFrame: QQC2.Frame
    {
        id: frame
        property string title
        property string detail
        property string secondary
        property string tertiary
        property Component content

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: frame.title
                font.bold: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: frame.detail
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: frame.secondary.length > 0
                text: frame.secondary
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: frame.tertiary.length > 0
                text: frame.tertiary
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
            }
            Loader {
                Layout.fillWidth: true
                sourceComponent: frame.content
            }
        }
    }
}
