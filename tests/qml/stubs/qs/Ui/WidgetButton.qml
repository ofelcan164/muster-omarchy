import QtQuick
import qs.Commons

// Stand-in for Omarchy's WidgetButton: the label, colours and press signal.
Item {
  id: root
  property var bar: null
  property string text: ""
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property real fontSize: Style.font.body
  property color foreground: bar ? bar.barForeground : Color.foreground
  property color activeColor: bar ? bar.urgent : Color.urgent
  property bool active: false
  property bool dimmed: false
  property bool interactive: true
  property bool pressable: true
  property bool labelVisible: true
  property bool hasVisualContent: text !== ""
  property string tooltipText: ""

  signal pressed(int button)
  signal wheelMoved(int delta)

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }

  readonly property string paintedText: label.text
  readonly property color paintedColor: label.color

  visible: hasVisualContent
  opacity: !hasVisualContent ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: Math.max(12, label.implicitWidth + 17)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Component.onCompleted: if (bar && bar.registerClickTarget) bar.registerClickTarget(root)

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root.text
    color: root.active ? root.activeColor : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }
}
