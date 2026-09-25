pragma Singleton
import QtQuick

// The keyboard panels created, for the harness to drive their key catchers.
QtObject {
  property var panels: []
  function created(p) { panels.push(p) }
}
