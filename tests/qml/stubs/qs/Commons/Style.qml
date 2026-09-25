pragma Singleton
import QtQuick

// Stand-in for Omarchy's Style at its defaults (scale 1, base size 12).
QtObject {
  id: root
  property string fontFamily: "monospace"
  property int cornerRadius: 0
  property int gapsOut: 10

  function space(px) { return Math.round(px) }
  function spaceReal(px) { return px }

  function hoverFillFor(foreground, accent, urgent) { return Qt.rgba(accent.r, accent.g, accent.b, 0.12) }
  function selectedFillFor(foreground, accent, urgent) { return Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08) }

  readonly property QtObject font: QtObject {
    readonly property string family: root.fontFamily
    readonly property int caption: 10
    readonly property int bodySmall: 11
    readonly property int body: 12
    readonly property int subtitle: 13
    readonly property int title: 14
    readonly property int heading: 16
    readonly property int display: 24
    readonly property int displayLarge: 28
    readonly property int iconSmall: 11
    readonly property int icon: 14
    readonly property int iconLarge: 18
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: 26
    readonly property int sizeVertical: 28
    readonly property int iconSlot: 27
    readonly property int iconCanvas: 16
    readonly property int iconFont: 13
    readonly property int statusSlot: 21
  }

  readonly property QtObject spacing: QtObject {
    readonly property int popupPadding: 14
    readonly property int panelGap: 12
    readonly property int panelPadding: 16
  }
}
