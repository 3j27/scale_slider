import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 520; height: 320
    minimumWidth: 420; minimumHeight: 300
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
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 28; spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Display scale"); font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
                TextField {
                    id: scaleInput
                    objectName: "scaleInput"
                    Layout.preferredWidth: 110
                    font.pixelSize: 26
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
            Label { text: qsTr("Drag the slider or type a scale and press Enter."); color: "#a9a9b1"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
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
                Label { text: qsTr("More space · 1.0×"); color: "#a9a9b1"; Layout.fillWidth: true }
                Label { text: qsTr("Bigger · 2.0×"); color: "#a9a9b1" }
            }
            Label {
                text: backend.status
                color: backend.failed ? "#ff9090" : "#bfc0c7"
                font.pixelSize: 12; Layout.fillWidth: true; Layout.fillHeight: true
                wrapMode: Text.WordWrap
            }
            Label { text: win.helpVisible ? qsTr("← / → Adjust   ·   Scroll Adjust   ·   Ctrl+Z Undo\nCtrl+Shift+Z Redo   ·   Space Focus slider   ·   Q Close") : qsTr("Changes save live. Press ? for shortcuts."); color: "#888891"; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }
}
