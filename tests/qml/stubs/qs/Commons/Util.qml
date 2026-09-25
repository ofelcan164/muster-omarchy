pragma Singleton
import QtQuick

// Stand-in for Omarchy's Util: the helpers the widget calls.
QtObject {
  function clampAlpha(value) { return Math.max(0, Math.min(1, Number(value))) }

  function alpha(c, opacity) {
    var a = clampAlpha(opacity)
    if (!c) return Qt.rgba(0, 0, 0, a)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }
}
