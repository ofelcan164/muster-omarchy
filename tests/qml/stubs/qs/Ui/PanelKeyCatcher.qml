import QtQuick

// Omarchy's PanelKeyCatcher: keys in, semantic signals out. The mapping is
// kept identical so the harness can press keys through press().
Item {
  id: root
  property bool blocked: false

  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  // press(key, text, modifiers) runs the same mapping as Keys.onPressed.
  function press(key, text, modifiers) {
    if (blocked) return
    var mods = modifiers || 0
    text = text || ""
    if (key === Qt.Key_Escape) { closeRequested(); return }
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      tabRequested((mods & Qt.ShiftModifier) || key === Qt.Key_Backtab ? -1 : 1); return
    }
    if (key === Qt.Key_Down || text === "j") { moveRequested(0, 1); return }
    if (key === Qt.Key_Up || text === "k") { moveRequested(0, -1); return }
    if (key === Qt.Key_Right || text === "l") { moveRequested(1, 0); return }
    if (key === Qt.Key_Left || text === "h") { moveRequested(-1, 0); return }
    if (key === Qt.Key_Return || key === Qt.Key_Enter) { returnRequested(); activateRequested(); return }
    if (key === Qt.Key_Space) { activateRequested(); return }
    if (text === "x" || text === "X") { deleteRequested(); return }
    if (text && text.length === 1) textKey(text)
  }

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return
    root.press(event.key, event.text, event.modifiers)
    event.accepted = true
  }
}
