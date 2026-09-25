import QtQuick
import Quickshell.Io
import qs.Commons

// Stand-in for Omarchy's Panel: open state, lifecycle and the IPC target.
Item {
  id: root
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property alias controller: panelController
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  readonly property bool opened: panelController.open
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { popoutSwitchClosing = true; close(); popoutSwitchClosing = false }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(root, direction)
    return false
  }
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  PanelController { id: panelController }

  IpcHandler {
    enabled: root.manageIpc && root.ipcTarget !== ""
    target: root.ipcTarget
  }
}
