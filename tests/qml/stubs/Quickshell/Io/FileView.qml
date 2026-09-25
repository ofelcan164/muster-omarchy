import QtQuick

// Stand-in for Quickshell's FileView: the same properties and signals, with
// the file read by a synchronous XHR on load and on reload(). A change on
// disk is simulated by the harness emitting fileChanged().
QtObject {
  id: fv
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true
  property bool atomicWrites: false
  property bool blockLoading: false
  property string _text: ""

  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)

  function text() { return _text }

  function reload() {
    if (path === "") return
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "file://" + path, false)
    try {
      xhr.send()
    } catch (e) {
      _text = ""
      loadFailed(1)
      return
    }
    var body = xhr.responseText
    if (!body) {
      _text = ""
      loadFailed(1)
      return
    }
    _text = body
    loaded()
  }

  onPathChanged: Qt.callLater(fv.reload)
  Component.onCompleted: {
    StubLog.watched(fv)
    Qt.callLater(fv.reload)
  }
}
