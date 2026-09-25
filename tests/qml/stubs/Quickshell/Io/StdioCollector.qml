import QtQuick

// Stand-in for Quickshell's StdioCollector.
QtObject {
  property bool waitForEnd: false
  property string text: ""
  signal streamFinished()
}
