import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Scale Slider: bar widget for Hyprland display scale.
//
// The bar shows the current scale ("1.60x"). Left click opens a popup panel
// with a 1.00-2.00 slider; every settled value is applied through the
// scale-slider CLI (`scale-slider set <value> --json`), which atomically edits
// ~/.config/hypr/monitors.lua and runs `hyprctl reload`. Right click opens the
// full Qt app instead; scrolling the bar button steps the slider one notch.
//
// Min, max and step come from the widget's own inline shell.json entry via
// setting(), with the app's 1.00-2.00 range as defaults.
Panel {
  id: root
  moduleName: "admin.scale-slider"
  ipcTarget: "admin.scale-slider"

  // ---- Widget settings (inline shell.json entry) ----
  readonly property real minScale: setting("min", 1.0)
  readonly property real maxScale: setting("max", 2.0)
  readonly property real stepSize: setting("step", 0.01) > 0 ? setting("step", 0.01) : 0.01
  readonly property string binPath: {
    var p = setting("binPath", "")
    p = String(p).trim()
    return p === "" ? "scale-slider" : p
  }
  readonly property int decimals: {
    var s = String(stepSize)
    var dot = s.indexOf(".")
    return dot < 0 ? 0 : s.length - dot - 1
  }

  // ---- Bar / style ----
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dimColor: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real wheelStep: 0.05  // Util.wheelSteps unit when not zooming

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---- Scale state ----
  // `scale` mirrors the most recently applied value; each `set` result
  // overwrites it, and `check --json` runs at startup and whenever the panel
  // opens, so externally applied changes show up too. While the slider is
  // being dragged nothing is applied at all: dragging only moves
  // previewScale (a local, display-only value) and the panel stays put.
  // Dragging applied changes live, and each hyprctl reload re-maps every
  // window, yanking the popup out from under the cursor — so changes commit
  // on release (and Enter in the value field) instead.
  property real scale: 1.0
  property real previewScale: NaN
  property bool scaleKnown: false
  property bool pending: false
  property real nextValue: NaN
  property real wheelAccumulator: 0
  property string errorText: ""

  function snap(v) {
    var steps = Math.round((v - root.minScale) / root.stepSize)
    var next = root.minScale + steps * root.stepSize
    next = Math.max(root.minScale, Math.min(root.maxScale, next))
    return parseFloat(next.toFixed(root.decimals))
  }

  function formatScale(v) {
    return Commons.I18n.formatNumber(v, root.decimals) + "×"
  }

  // Dragging fires many `moved` events; only the last value matters but each
  // apply spawns the CLI (file write + hyprctl reload), so coalesce trailing
  // values while the slider is hot and flush on release. While a process is
  // in flight a newer value queues and restarts from onExited.
  function apply(v) {
    var value = root.snap(v)
    if (isNaN(value)) return
    root.scale = value
    root.scaleKnown = true
    root.nextValue = value
    if (setProc.running) { root.pending = true; return }
    root.pending = false
    root.errorText = ""
    setProc.running = true
  }

  onOpenedChanged: if (opened) Qt.callLater(root.checkScale)

  function checkScale() {
    if (checkProc.running) return
    checkProc.running = true
  }

  Component.onCompleted: root.checkScale()

  Process {
    id: checkProc
    command: [root.binPath, "check", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var out = JSON.parse(text)
          if (out.scale !== undefined) {
            root.scale = out.scale
            root.scaleKnown = true
          }
        } catch (e) {}
      }
    }
    stderr: StdioCollector {
      id: checkStderr
      waitForEnd: true
      onStreamFinished: {}
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.scaleKnown)
        root.errorText = (String(checkStderr.text || "").trim().split("\n").join(" — ") || "scale-slider check failed").substring(0, 120)
    }
  }

  Process {
    id: setProc
    command: [root.binPath, "set", String(root.nextValue), "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var out = JSON.parse(text)
          if (out.ok === false) {
            root.errorText = String(out.message || "").trim().split("\n").join(" — ").substring(0, 120)
          } else if (out.scale !== undefined) {
            root.scale = out.scale
            root.scaleKnown = true
          }
        } catch (e) {}
      }
    }
    stderr: StdioCollector {
      id: setStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.errorText === "")
        root.errorText = (String(setStderr.text || "").trim().split("\n").join(" — ") || "scale-slider set failed").substring(0, 120)
      if (root.pending) {
        // nextValue already holds the newest request; rerun with it.
        root.pending = false
        root.errorText = ""
        setProc.running = true
      }
    }
  }

  // ---- Bar button: the scale readout itself ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.scaleKnown ? root.formatScale(root.scale) : "…"
    labelVisible: true
    fixedHeight: -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    dimmed: !root.scaleKnown || root.errorText !== ""
    tooltipText: strings.t("scale.tooltip")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        Quickshell.execDetached([root.binPath, "open"])
      } else if (b === Qt.LeftButton) {
        root.toggle()
      }
    }

    onWheelMoved: function(delta) {
      if (!root.scaleKnown) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.apply(root.scale + wheel.steps * root.stepSize)
    }
  }

  // ---- Popup panel ----
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(320))

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.apply(root.scale + dx * root.stepSize)
      }
      onActivateRequested: { /* nothing extra to activate */ }
      onCloseRequested: root.close()

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        // ---- Hero: title · editable value readout ----
        Item {
          width: parent.width
          implicitHeight: Math.max(titleLabel.implicitHeight, valueInput.bgImplicitHeight, valueInput.implicitHeight)

          Column {
            id: titleLabel
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("scale.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              visible: root.errorText !== ""
              textFormat: Text.PlainText
              text: root.errorText
              color: root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: Math.min(implicitWidth, panelColumn.width - valueInput.implicitWidth - Style.space(12))
              elide: Text.ElideRight
            }
          }

          // Editable current scale, like the app's scale field: click to
          // type, Enter or focus-out applies, Escape backs out. Only untinted
          // characters of "0.01" style are accepted, comma or dot.
          Rectangle {
            id: valueInput
            property bool editing: valueText.activeFocus
            readonly property real bgImplicitHeight: valueText.implicitHeight + Style.space(10)
            readonly property string display: root.scaleKnown
              ? root.formatScale(isNaN(root.previewScale) ? root.scale : root.previewScale)
              : "…"
            function sync() { valueText.text = display }
            function commit() {
              var parsed = parseFloat(String(valueText.text).replace(",", "."))
              if (!isFinite(parsed)) { sync(); return }
              var next = root.snap(parsed)
              if (next !== root.scale) root.apply(next)
              else sync()
            }

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: valueText.width + Style.space(18)
            height: bgImplicitHeight
            radius: Math.min(Style.space(6), height / 2)
            color: valueInput.editing ? Util.alpha(root.foreground, 0.08) : "transparent"

            TextInput {
              id: valueText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              clip: true
              validator: RegularExpressionValidator { regularExpression: /[0-9]+([.,][0-9]{0,2})?/ }
              anchors.verticalCenter: parent.verticalCenter
              anchors.horizontalCenter: parent.horizontalCenter
              cursorVisible: valueInput.editing
              onAccepted: {
                valueInput.commit()
                root.previewScale = NaN
                valueText.focus = false
              }
              Keys.onEscapePressed: {
                valueInput.sync()
                root.previewScale = NaN
                valueText.focus = false
              }
              onActiveFocusChanged: if (!activeFocus) { valueInput.sync() }
              Component.onCompleted: valueInput.sync()
            }

            Connections {
              target: root
              function onScaleChanged() { if (!valueInput.editing) valueInput.sync() }
              function onPreviewScaleChanged() { if (!valueInput.editing) valueInput.sync() }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.IBeamCursor
              onPressed: function(mouse) {
                valueText.forceActiveFocus()
                valueText.selectAll()
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- The slider itself ----
        // Dragging is deliberately local: nothing applies until release, so
        // the rescaling of every window on the screen can never yank the
        // popup out from under the cursor mid-drag. The wheel goes through
        // the same release path (PanelSlider emits moved+released per notch)
        // and the coalescing pipeline in apply() keeps bursts cheap.
        PanelSlider {
          id: scaleSlider
          bar: root.bar
          width: parent.width
          minimum: root.minScale
          maximum: root.maxScale
          step: root.stepSize
          tickCount: 11
          value: root.scale

          onMoved: function(v) { root.previewScale = root.snap(v) }
          onReleased: function(v) {
            root.previewScale = NaN
            root.apply(v)
          }
        }

        // ---- Range end labels ----
        Item {
          width: parent.width
          implicitHeight: Math.max(scaleMinLabel.implicitHeight, scaleMaxLabel.implicitHeight)

          Text {
            id: scaleMinLabel
            textFormat: Text.PlainText
            text: root.formatScale(root.minScale)
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.left: parent.left
          }

          Text {
            id: scaleMaxLabel
            textFormat: Text.PlainText
            text: root.formatScale(root.maxScale)
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
          }
        }
      }
    }
  }
}
