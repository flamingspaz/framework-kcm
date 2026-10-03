// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 800
    height: 760
    minimumWidth: 600
    minimumHeight: 560
    visible: true
    title: qsTr("Framework Settings")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: qsTr("Framework Settings")
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }
            Label {
                text: qsTr("Manage charging, cooling, and input hardware.")
                color: palette.mid
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !kcm.daemonAvailable
            wrapMode: Text.Wrap
            color: "#b3261e"
            text: qsTr("Cannot connect to the Framework hardware service (framework-kcmd). Make sure it is installed and running.")
        }
        Label {
            Layout.fillWidth: true
            visible: kcm.errorMessage.length > 0
            wrapMode: Text.Wrap
            color: "#b3261e"
            text: kcm.errorMessage
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width
            TabButton { width: (window.width - 48) / 4; text: qsTr("Battery") }
            TabButton { width: (window.width - 48) / 4; text: qsTr("Fans and Thermals") }
            TabButton { width: (window.width - 48) / 4; text: qsTr("Touchpad and LED") }
            TabButton { width: (window.width - 48) / 4; text: qsTr("System") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            enabled: kcm.daemonAvailable && !kcm.busy

            ScrollView {
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Charging")
                        ColumnLayout {
                            anchors.fill: parent
                            RowLayout {
                                Label { Layout.fillWidth: true; text: qsTr("Charge limit") }
                                Slider {
                                    id: chargeLimitSlider
                                    Layout.fillWidth: true
                                    from: 25; to: 100; stepSize: 5; snapMode: Slider.SnapAlways
                                    value: kcm.chargeLimit
                                    onMoved: kcm.chargeLimit = value
                                }
                                Label { text: qsTr("%1%").arg(chargeLimitSlider.value) }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: qsTr("Stops charging at this level. Keeping the battery below 100% helps it age more slowly.")
                            }
                            RowLayout {
                                Button {
                                    visible: !kcm.chargeLimitOverridden
                                    enabled: kcm.chargeLimit < 100
                                    text: qsTr("Override charge limit")
                                    onClicked: kcm.overrideChargeLimit()
                                }
                                Label {
                                    Layout.fillWidth: true
                                    visible: kcm.chargeLimitOverridden
                                    wrapMode: Text.Wrap
                                    text: qsTr("Charging to 100% until the computer restarts.")
                                }
                                Button {
                                    visible: kcm.chargeLimitOverridden
                                    text: qsTr("Restore now")
                                    onClicked: kcm.cancelChargeLimitOverride()
                                }
                            }
                        }
                    }
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Charge speed")
                        ColumnLayout {
                            anchors.fill: parent
                            CheckBox {
                                id: chargeSpeedCheck
                                text: qsTr("Limit charging speed")
                                checked: kcm.chargeRateLimit < 1.0
                                onToggled: kcm.chargeRateLimit = checked ? 0.5 : 1.0
                            }
                            RowLayout {
                                visible: chargeSpeedCheck.checked
                                Label { text: qsTr("Speed") }
                                Slider {
                                    id: chargeRateSlider
                                    Layout.fillWidth: true
                                    from: 0.1; to: 0.9; stepSize: 0.1; snapMode: Slider.SnapAlways
                                    value: kcm.chargeRateLimit
                                    onMoved: kcm.chargeRateLimit = Math.round(value * 10) / 10
                                }
                                Label { text: qsTr("%1×").arg(Number(chargeRateSlider.value).toFixed(1)) }
                            }
                            RowLayout {
                                visible: chargeSpeedCheck.checked
                                CheckBox {
                                    id: socCheck
                                    text: qsTr("Only above battery level")
                                    checked: kcm.chargeRateSoc >= 0
                                    onToggled: kcm.chargeRateSoc = checked ? 80 : -1
                                }
                                SpinBox {
                                    enabled: socCheck.checked
                                    from: 0; to: 100; stepSize: 5
                                    value: Math.max(0, kcm.chargeRateSoc)
                                    onValueModified: kcm.chargeRateSoc = value
                                    textFromValue: value => qsTr("%1%").arg(value)
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: chargeSpeedCheck.checked
                                wrapMode: Text.Wrap
                                text: qsTr("Slower charging produces less heat and can reduce battery wear. The service reapplies this setting after restart.")
                            }
                        }
                    }
                }
            }

            ScrollView {
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Temperatures")
                        ColumnLayout {
                            anchors.fill: parent
                            Repeater {
                                model: kcm.sensors
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Label { Layout.fillWidth: true; text: modelData.name || modelData.location || qsTr("Sensor") }
                                    Label { text: modelData.status === "ok" ? qsTr("%1 °C").arg(modelData.temp) : (modelData.status || qsTr("Error")) }
                                }
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
                        title: qsTr("Fans")
                        ColumnLayout {
                            anchors.fill: parent
                            Repeater {
                                model: kcm.fans
                                delegate: Label {
                                    required property var modelData
                                    text: qsTr("%1: %2 RPM").arg(modelData.name || modelData.position || qsTr("Fan")).arg(modelData.rpm)
                                }
                            }
                            RowLayout {
                                Label { Layout.fillWidth: true; text: qsTr("Fan control") }
                                ComboBox {
                                    model: [qsTr("Automatic"), qsTr("Fixed duty cycle"), qsTr("Fixed speed")]
                                    currentIndex: kcm.fanMode === "duty" ? 1 : kcm.fanMode === "rpm" ? 2 : 0
                                    onActivated: kcm.fanMode = ["auto", "duty", "rpm"][currentIndex]
                                }
                            }
                            RowLayout {
                                visible: kcm.fanMode === "duty"
                                Label { Layout.fillWidth: true; text: qsTr("Fan duty") }
                                Slider {
                                    id: dutySlider
                                    Layout.fillWidth: true
                                    from: 0; to: 100; stepSize: 5; snapMode: Slider.SnapAlways
                                    value: kcm.fanDuty
                                    onMoved: kcm.fanDuty = value
                                }
                                Label { text: qsTr("%1%").arg(dutySlider.value) }
                            }
                            RowLayout {
                                visible: kcm.fanMode === "rpm"
                                Label { Layout.fillWidth: true; text: qsTr("Fan speed") }
                                SpinBox {
                                    from: 0; to: 8000; stepSize: 100
                                    value: kcm.fanRpm
                                    onValueModified: kcm.fanRpm = value
                                    textFromValue: value => qsTr("%1 RPM").arg(value)
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: kcm.fanMode !== "auto"
                                wrapMode: Text.Wrap
                                color: "#8a4b08"
                                text: qsTr("A fixed fan speed can let the system run hot and throttle. Fans return to automatic when the service stops or the laptop reboots.")
                            }
                        }
                    }
                }
            }

            ScrollView {
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Fingerprint reader LED")
                        RowLayout {
                            anchors.fill: parent
                            Label { Layout.fillWidth: true; text: qsTr("Brightness") }
                            ComboBox {
                                enabled: kcm.fpLedSupported
                                model: [qsTr("Automatic"), qsTr("High"), qsTr("Medium"), qsTr("Low"), qsTr("Ultra low")]
                                currentIndex: ["auto", "high", "medium", "low", "ultra-low"].indexOf(kcm.fpLedLevel)
                                onActivated: kcm.fpLedLevel = ["auto", "high", "medium", "low", "ultra-low"][currentIndex]
                            }
                        }
                    }
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Haptic touchpad")
                        ColumnLayout {
                            anchors.fill: parent
                            RowLayout {
                                Label { Layout.fillWidth: true; text: qsTr("Feedback intensity") }
                                ComboBox {
                                    model: [qsTr("Not set"), qsTr("Off"), "25%", "50%", "75%", "100%"]
                                    currentIndex: kcm.hapticIntensity < 0 ? 0 : kcm.hapticIntensity === 0 ? 1 : Math.round(kcm.hapticIntensity / 25) + 1
                                    onActivated: kcm.hapticIntensity = [ -1, 0, 25, 50, 75, 100 ][currentIndex]
                                }
                            }
                            RowLayout {
                                Label { Layout.fillWidth: true; text: qsTr("Click force") }
                                ComboBox {
                                    model: [qsTr("Not set"), qsTr("Light"), qsTr("Medium"), qsTr("Firm")]
                                    currentIndex: ["", "low", "medium", "high"].indexOf(kcm.clickForce)
                                    onActivated: kcm.clickForce = ["", "low", "medium", "high"][currentIndex]
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: qsTr("Only for haptic touchpads. The touchpad cannot report these settings; the service reapplies them when it starts.")
                            }
                        }
                    }
                }
            }

            ScrollView {
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("Device and firmware")
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 12
                            Label { text: qsTr("Model"); color: palette.mid }
                            Label { Layout.fillWidth: true; text: kcm.systemInfo.product || qsTr("Unknown") }
                            Label { text: qsTr("BIOS"); color: palette.mid }
                            Label { Layout.fillWidth: true; text: kcm.systemInfo.biosVersion || qsTr("Unknown") }
                            Label { text: qsTr("EC"); color: palette.mid }
                            Label { Layout.fillWidth: true; text: kcm.systemInfo.ecVersion || qsTr("Unknown") }
                            Label { text: qsTr("Service"); color: palette.mid }
                            Label { Layout.fillWidth: true; text: kcm.systemInfo.daemonVersion || qsTr("Unknown") }
                            Label { text: qsTr("Camera"); color: palette.mid }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: kcm.systemInfo.privacyKnown ? (kcm.systemInfo.cameraEnabled ? qsTr("Enabled") : qsTr("Disabled by privacy switch")) : qsTr("Unknown")
                            }
                            Label { text: qsTr("Microphone"); color: palette.mid }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: kcm.systemInfo.privacyKnown ? (kcm.systemInfo.micEnabled ? qsTr("Enabled") : qsTr("Disabled by privacy switch")) : qsTr("Unknown")
                            }
                        }
                    }
                    GroupBox {
                        Layout.fillWidth: true
                        title: qsTr("USB-C ports")
                        ColumnLayout {
                            anchors.fill: parent
                            Repeater {
                                model: kcm.ports
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Label { Layout.fillWidth: true; text: modelData.position || qsTr("Port") }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        text: {
                                            const p = modelData;
                                            if (!p.ok) return qsTr("Unavailable");
                                            if (p.role === "disconnected") return qsTr("Nothing connected");
                                            if (p.role === "source") return qsTr("Powering a device");
                                            if (p.role === "sink" || p.role === "sink-not-charging") return qsTr("%1 W, %2 V").arg(Math.round(p.maxPower / 1e6)).arg((p.voltageNow / 1000).toFixed(1));
                                            return qsTr("Unknown");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: palette.mid
            opacity: 0.25
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                color: kcm.busy ? palette.mid : palette.text
                text: kcm.busy ? qsTr("Applying settings…") : kcm.needsSave ? qsTr("Changes not applied") : ""
            }
            Button {
                text: qsTr("Defaults")
                enabled: !kcm.busy
                onClicked: kcm.defaults()
            }
            Button {
                text: qsTr("Apply")
                enabled: kcm.needsSave && !kcm.busy && kcm.daemonAvailable
                highlighted: true
                onClicked: kcm.save()
            }
        }
    }

    Binding {
        target: kcm
        property: "liveData"
        value: tabs.currentIndex === 1 ? "thermal" : tabs.currentIndex === 3 ? "ports" : ""
    }
}
