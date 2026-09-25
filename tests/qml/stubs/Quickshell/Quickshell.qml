pragma Singleton
import QtQuick

// Stand-in for Quickshell's singleton. env() reads the runner's testEnv.
QtObject {
  function env(name) {
    return (typeof testEnv !== "undefined" && testEnv[name] !== undefined) ? testEnv[name] : ""
  }
  function execDetached(argv) {}
}
