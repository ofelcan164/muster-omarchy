pragma Singleton
import QtQuick

// What the stand-ins saw, for the harness to inspect.
QtObject {
  property var processes: []
  property var fileViews: []
  function started(p) { processes.push(p) }
  function watched(f) { fileViews.push(f) }
}
