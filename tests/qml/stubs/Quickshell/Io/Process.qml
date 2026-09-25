import QtQuick

// Stand-in for Quickshell's Process. Nothing runs: starting one is recorded,
// and the harness ends it with finish(), which fills the collectors before
// exited fires, as Quickshell does.
QtObject {
  id: proc
  property var command: []
  property bool running: false
  property bool stdinEnabled: false
  property QtObject stdout: null
  property QtObject stderr: null

  signal started()
  signal exited(int exitCode, int exitStatus)

  function write(data) {}

  function finish(code, out, err) {
    if (stdout) { stdout.text = out || ""; stdout.streamFinished() }
    if (stderr) { stderr.text = err || ""; stderr.streamFinished() }
    running = false
    exited(code, 0)
  }

  onRunningChanged: if (running) {
    StubLog.started({ process: proc, command: proc.command.slice() })
    started()
  }
}
