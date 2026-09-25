import QtQuick
import qs.Commons

// Stand-in for Omarchy's PanelHero: title and meta, same properties.
Item {
  id: root
  property Component iconComponent: null
  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real iconSize: Style.font.display
  property real iconOpacity: 1.0
  property Component trailingControl: null
  readonly property color dim: Qt.darker(foreground, 1.4)

  width: parent ? parent.width : implicitWidth
  implicitHeight: labels.implicitHeight

  Column {
    id: labels
    width: parent.width
    Text { text: root.title; textFormat: Text.PlainText; color: root.foreground; font.pixelSize: Style.font.title }
    Text { text: root.meta.toUpperCase(); textFormat: Text.PlainText; color: root.dim; font.pixelSize: Style.font.caption }
  }
}
