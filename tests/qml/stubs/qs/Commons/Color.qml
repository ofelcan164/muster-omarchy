pragma Singleton
import QtQuick

// Stand-in for Omarchy's Color: the palette roles and the popups surface.
QtObject {
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"

  readonly property QtObject bar: QtObject {
    property color background: "#101315"
    property color text: "#cacccc"
    property color active: "#a55555"
  }
  readonly property QtObject popups: QtObject {
    property color background: "#101315"
    property color text: "#cacccc"
    property color border: "#cacccc"
  }
}
