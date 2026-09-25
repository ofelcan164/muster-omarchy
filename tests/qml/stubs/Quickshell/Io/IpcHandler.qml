import QtQuick

// Stand-in for Quickshell's IpcHandler: holds the target, routes nothing.
QtObject {
  property string target: ""
  property bool enabled: true
}
