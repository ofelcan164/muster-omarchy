import QtQuick
import qs.Commons

// Stand-in for Omarchy's KeyboardPanel. The real one is a layer-shell window;
// this is an Item with the same API that registers itself with StubUi.
Item {
  id: root
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property bool centerOnBar: false
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: contentHolder.children

  readonly property real availableCardWidth: 1920 - margin * 2
  readonly property real availableCardHeight: 1080 - margin * 2
  readonly property real verticalContentInset: padding * 2

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    return Math.round(Math.min(desired, root.availableCardHeight))
  }

  width: contentWidth
  height: contentHeight

  Item {
    id: contentHolder
    anchors.fill: parent
    anchors.margins: root.padding
  }

  Component.onCompleted: StubUi.created(root)
}
