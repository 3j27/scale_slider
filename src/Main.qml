import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 520; height: 320
    minimumWidth: 240; minimumHeight: 140
    visible: true
    title: qsTr("Scale Slider")
    color: "#141416"
    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    property bool helpVisible: false
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: win.close() }
    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; onActivated: slider.forceActiveFocus() }
    Shortcut { sequences: [StandardKey.Undo]; context: Qt.ApplicationShortcut; onActivated: backend.undo() }
    Shortcut { sequences: [StandardKey.Redo]; context: Qt.ApplicationShortcut; onActivated: backend.redo() }
    onClosing: backend.flush()
    Connections {
        target: backend
        function onChanged() {
            if (!slider.pressed) slider.value = backend.scale
            if (!scaleInput.activeFocus) scaleInput.syncValue()
        }
    }
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true
        ScrollView {
            id: viewport
            anchors.fill: parent
            anchors.margins: win.width < 400 || win.height < 260 ? 12 : 28
            clip: true
            contentWidth: availableWidth
            contentHeight: content.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
            id: content
            width: viewport.availableWidth
            spacing: win.height < 260 ? 6 : 14
            RowLayout {
                Layout.fillWidth: true
                Label {
                    objectName: "scaleHeading"
                    text: win.width < 400 ? qsTr("Scale") : qsTr("Display scale")
                    font.pixelSize: win.width < 400 ? 18 : 22
                    font.bold: true
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
                TextField {
                    id: scaleInput
                    objectName: "scaleInput"
                    Layout.preferredWidth: win.width < 400 ? 88 : 110
                    Layout.minimumWidth: win.width < 400 ? 88 : 110
                    Layout.maximumWidth: Layout.preferredWidth
                    font.pixelSize: win.width < 400 ? 20 : 26
                    color: acceptableInput ? theme.accent : "#ff9090"
                    horizontalAlignment: TextInput.AlignRight
                    selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    Accessible.name: qsTr("Display scale, from 1.0 to 2.0")
                    validator: DoubleValidator {
                        bottom: 1.0; top: 2.0; decimals: 2
                        notation: DoubleValidator.StandardNotation
                        locale: Qt.locale().name
                    }
                    function syncValue() {
                        text = slider.value.toLocaleString(Qt.locale(), 'f', 2)
                    }
                    Component.onCompleted: syncValue()
                    onEditingFinished: {
                        if (acceptableInput) {
                            backend.requestScale(Number.fromLocaleString(Qt.locale(), text))
                            backend.flush()
                        }
                        syncValue()
                    }
                    Keys.onEscapePressed: { syncValue(); slider.forceActiveFocus() }
                }
                Label { text: "×"; color: theme.accent; font.pixelSize: 26 }
            }
            Label { visible: win.height >= 260; text: qsTr("Drag the slider or type a scale and press Enter."); color: "#a9a9b1"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Slider {
                id: slider; objectName: "scaleSlider"
                Layout.fillWidth: true; from: 1; to: 2; stepSize: 0.01
                value: backend.scale
                focus: true
                onValueChanged: if (!scaleInput.activeFocus) scaleInput.syncValue()
                onMoved: backend.requestScale(value)
                onPressedChanged: if (!pressed) backend.flush()
                WheelHandler {
                    onWheel: function(event) {
                        slider.value = Math.max(1, Math.min(2, slider.value + (event.angleDelta.y > 0 ? 0.01 : -0.01)))
                        backend.requestScale(slider.value)
                        event.accepted = true
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("More space · 1.0×"); color: "#a9a9b1"
                    font.pixelSize: win.width < 400 ? 11 : 14
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: qsTr("Bigger · 2.0×"); color: "#a9a9b1"
                    font.pixelSize: win.width < 400 ? 11 : 14
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight; wrapMode: Text.WordWrap
                }
            }
            Label {
                text: backend.status
                color: backend.failed ? "#ff9090" : "#bfc0c7"
                font.pixelSize: 12; Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Label { visible: win.height >= 260 || win.helpVisible; text: win.helpVisible ? qsTr("← / → Adjust   ·   Scroll Adjust   ·   Ctrl+Z Undo\nCtrl+Shift+Z Redo   ·   Space Focus slider   ·   Q Close") : qsTr("Changes save live. Press ? for shortcuts."); color: "#888891"; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }
}
