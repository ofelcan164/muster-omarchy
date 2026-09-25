import QtQuick
import qs.Commons
import qs.Ui

// The bar entry point: Muster's diamond, the count of what needs you coloured
// by the most urgent reason, and the panel it opens. The panel is loaded next
// to the button and handed the bar context and the one Data instance, the way
// Hypr Rules Studio does it.
BarWidget {
  id: root
  moduleName: "io.github.ofelcan164.muster"

  readonly property var view: muster.barView

  // The shell toggles a bar widget through these three (`omarchy-shell shell
  // toggle io.github.ofelcan164.muster`), so they live on the entry point.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.muster = muster
  }

  // Hidden only while there is no snapshot at all. Once Muster has written
  // one the diamond stays, dim when nothing needs you, so the panel is always
  // a click away.
  visible: view.visible
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Data {
    id: muster
    settings: root.settings
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.view.text
    foreground: root.view.color !== "" ? root.view.color : (root.bar ? root.bar.barForeground : Color.foreground)
    dimmed: root.view.dimmed
    tooltipText: root.view.tooltip
    onPressed: function(buttonCode) { root.toggle() }
  }
}
