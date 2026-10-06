// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import ".."

Item {
    width: 800
    height: 200

    TabBar {
        id: tabs
        width: parent.width
        SettingsTabButton { text: "Overview" }
        SettingsTabButton { text: "Battery" }
        SettingsTabButton { text: "Schedule" }
    }

    TestCase {
        name: "SettingsTabs"
        when: windowShown

        function init() {
            tabs.setCurrentIndex(0);
        }

        function verifySelection(index) {
            compare(tabs.currentIndex, index);
            for (let i = 0; i < tabs.count; ++i) {
                const tab = tabs.itemAt(i);
                compare(tab.selected, i === index);
                compare(tab.background.children[0].visible, i === index);
            }
        }

        function test_initialSelection() {
            verifySelection(0);
        }

        function test_mouseSelection() {
            mouseClick(tabs.itemAt(1));
            verifySelection(1);
            mouseClick(tabs.itemAt(2));
            verifySelection(2);
            mouseClick(tabs.itemAt(0));
            verifySelection(0);
            mouseClick(tabs.itemAt(0));
            verifySelection(0);
        }

        function test_keyboardSelection() {
            tabs.itemAt(0).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Right);
            verifySelection(1);
            keyClick(Qt.Key_Left);
            verifySelection(0);
        }

        function test_selectionWithoutFocusOrCheckedState() {
            tabs.setCurrentIndex(1);
            tabs.itemAt(1).checked = false;
            verifySelection(1);
        }
    }
}
