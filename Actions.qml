import QtQuick
import Quickshell.Io

// Every command the panel runs, one at a time, in the order asked. Each goes
// through bin/muster-omarchy, which runs the muster CLI and raises herdr's
// window, so what a click does here is what the same key does in Muster's
// overlay.
Item {
  id: root
  visible: false

  property string musterCommand: "muster"
  property string stateDir: ""

  property var queue: []
  property var current: null
  readonly property bool busy: current !== null

  function scriptPath() {
    var url = String(Qt.resolvedUrl("bin/muster-omarchy"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  // run queues one call. onDone(ok, message) gets the last line of stderr on
  // a failure, and of stdout on success: what went wrong, or what was done.
  function run(args, onDone) {
    queue.push({ args: args, onDone: onDone })
    queue = queue
    pump()
  }

  function jump(target, onDone) { run(["jump", String(target)], onDone) }
  function tell(text, onDone) { run(["tell", String(text)], onDone) }
  function report(pane, onDone) { run(["report", String(pane)], onDone) }
  function dismiss(pane, onDone) { run(["dismiss", String(pane)], onDone) }
  function mark(pane, onDone) { run(["mark-orchestrator", String(pane)], onDone) }

  function pump() {
    if (current !== null || queue.length === 0) return
    current = queue.shift()
    queue = queue
    // A login shell, so muster is found on the PATH the user's terminal has
    // rather than the shell's. The arguments reach the script as "$@" and are
    // never parsed as shell; the script runs through bash so a copy that lost
    // its exec bit still works.
    proc.command = ["bash", "-lc", "exec bash \"$@\"", "bash", scriptPath(),
                    "--muster", root.musterCommand, "--state-dir", root.stateDir].concat(current.args)
    proc.running = true
  }

  Process {
    id: proc

    stdout: StdioCollector { id: procOut; waitForEnd: true }
    stderr: StdioCollector { id: procErr; waitForEnd: true }

    onExited: function(exitCode, exitStatus) {
      var call = root.current
      root.current = null
      var out = String((exitCode === 0 ? procOut.text : procErr.text) || "").trim().split("\n")
      var message = out[out.length - 1] || (exitCode === 0 ? "" : "exited with " + exitCode)
      if (call && call.onDone) call.onDone(exitCode === 0, message)
      root.pump()
    }
  }
}
