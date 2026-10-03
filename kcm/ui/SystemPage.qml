// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    readonly property var info: kcm.systemInfo

    function orUnknown(s) {
        return s && s.length > 0 ? s : i18n("Unknown");
    }

    function portName(position) {
        switch (position) {
        case "right-back": return i18nc("USB-C port location", "Right back");
        case "right-front": return i18nc("USB-C port location", "Right front");
        case "right-middle": return i18nc("USB-C port location", "Right middle");
        case "left-front": return i18nc("USB-C port location", "Left front");
        case "left-middle": return i18nc("USB-C port location", "Left middle");
        case "left-back": return i18nc("USB-C port location", "Left back");
        default: return position;
        }
    }

    function chargerType(type) {
        switch (type) {
        case "pd": return i18nc("charger type", "USB Power Delivery");
        case "type-c": return i18nc("charger type", "USB-C");
        case "proprietary": return i18nc("charger type", "a proprietary charger");
        case "bc12-dcp": case "bc12-cdp": case "bc12-sdp": return i18nc("charger type", "USB battery charging");
        case "vbus": return i18nc("charger type", "USB bus power");
        default: return i18nc("charger type", "an unknown charger");
        }
    }

    function pdVersion(pd) {
        switch (pd.side) {
        case "right": return i18nc("PD controller firmware version", "Right: %1", pd.version);
        case "left": return i18nc("PD controller firmware version", "Left: %1", pd.version);
        default:
            return (info.pdVersions.length > 1) ? i18nc("PD controller number, firmware version", "PD %1: %2", pd.index, pd.version) : pd.version;
        }
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Device")
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Model:")
        text: orUnknown(info.product)
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: info.isFramework === false
        type: Kirigami.MessageType.Warning
        text: i18n("This does not look like a Framework laptop. Most settings will not work.")
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Camera:")
        visible: info.privacyKnown === true
        text: info.cameraEnabled ? i18n("Enabled") : i18n("Disabled by privacy switch")
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Microphone:")
        visible: info.privacyKnown === true
        text: info.micEnabled ? i18n("Enabled") : i18n("Disabled by privacy switch")
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Firmware")
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("BIOS:")
        text: info.biosDate ? i18nc("version (date)", "%1 (%2)", orUnknown(info.biosVersion), info.biosDate) : orUnknown(info.biosVersion)
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("EC:")
        text: orUnknown(info.ecVersion)
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("EC image:")
        visible: (info.ecRoVersion ?? "") !== (info.ecRwVersion ?? "")
        text: i18nc("EC firmware images; RO and RW are the read-only and read-write copies",
                    "RO %1, RW %2 (running %3)", info.ecRoVersion, info.ecRwVersion,
                    info.ecCurrentImage === "ro" ? "RO" : info.ecCurrentImage === "rw" ? "RW" : i18n("Unknown"))
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("PD controllers:")
        text: (info.pdVersions ?? []).length > 0 ? info.pdVersions.map(pdVersion).join("\n") : i18n("Unknown")
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Service:")
        visible: !!info.daemonVersion
        text: i18n("frameworkd %1", info.daemonVersion)
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("USB-C Ports")
    }

    Repeater {
        // Count, not the list: a list model rebuilds every row whenever any value
        // changes, and FormLayout trips over the destroyed rows
        model: kcm.ports.length
        delegate: QQC2.Label {
            required property int index
            readonly property var modelData: kcm.ports[index] ?? ({})
            Kirigami.FormData.label: i18nc("port name", "%1:", portName(modelData.position))
            text: {
                const p = modelData;
                if (!p.ok) {
                    return i18n("Unavailable");
                }
                switch (p.role) {
                case "disconnected":
                    return i18n("Nothing connected");
                case "source":
                    return i18n("Powering a device");
                case "sink":
                case "sink-not-charging": {
                    const watts = Number(p.maxPower / 1e6).toLocaleString(Qt.locale(), "f", 0);
                    const volts = Number(p.voltageNow / 1000).toLocaleString(Qt.locale(), "f", 1);
                    const state = p.role === "sink" ? i18nc("USB-C port state", "Charging") : i18nc("USB-C port state", "Connected, not charging");
                    return i18nc("state, charger type, watts, volts", "%1 via %2, up to %3 W (%4 V)", state, chargerType(p.chargingType), watts, volts);
                }
                default:
                    return i18n("Unknown");
                }
            }
        }
    }
}
