import QtQuick

// Omarchy's PanelController, which is all state.
QtObject {
  property bool open: false
  function toggle() { open = !open }
  function show() { if (!open) open = true }
  function hide() { open = false }
}
