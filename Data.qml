import QtQuick
import Quickshell
import Quickshell.Io
import "lib/muster.js" as Muster

// Muster's files, read and kept current. The widget holds no herdr connection
// and no state of its own: musterd writes snapshot.json, the overlay writes
// ui.json, and this only watches the two. Everything worked out from them
// lives in lib/muster.js.
Item {
  id: root
  visible: false

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""

  // Muster's state dir for the default herdr session. An empty setting means
  // the path herdr gives the plugin; herdr never tells anyone else.
  readonly property string stateDir: {
    var s = String((settings && settings.stateDir) || "").trim()
    if (s === "") return home + "/.local/state/herdr/plugins/muster"
    if (s === "~") return home
    if (s.indexOf("~/") === 0) s = home + s.slice(1)
    return s.length > 1 ? s.replace(/\/+$/, "") : s
  }
  readonly property string musterCommand: String((settings && settings.muster) || "").trim() || "muster"
  readonly property string snapshotPath: stateDir + "/snapshot.json"
  readonly property string uiPath: stateDir + "/ui.json"

  // "missing", "unreadable" or "loaded": whether there is a snapshot to draw.
  property string fileState: "missing"
  property string fileError: ""
  property var snapshot: null
  property var ui: Muster.parseUi("")

  // Ages are measured against this rather than Date.now(), so the bar and
  // panel keep telling the truth between snapshots.
  property double nowMs: Date.now()

  readonly property bool newer: fileState === "loaded" && Muster.isNewer(snapshot)
  readonly property bool stale: fileState === "loaded" && !newer && Muster.isStale(snapshot, nowMs)
  // Anything to draw at all: a snapshot this widget can read.
  readonly property bool readable: fileState === "loaded" && !newer

  readonly property var barView: Muster.barView(fileState, snapshot, ui, nowMs)
  // What the panel draws, piece by piece as the overlay does: the title
  // line, the ribbon and its rule's colour, the grid's tiles, the strip.
  readonly property var header: readable ? Muster.headerView(snapshot, ui) : ({ counts: "", needsYou: 0 })
  readonly property var ribbon: readable ? Muster.ribbonView(snapshot, ui) : []
  readonly property string accent: readable ? Muster.attentionAccent(snapshot, ui) : Muster.DIM
  readonly property int needsYou: readable ? Muster.needsYou(snapshot, ui) : 0
  readonly property var tiles: readable ? Muster.tilesView(snapshot, ui, nowMs) : []
  readonly property var orchestrator: readable ? Muster.orchestratorView(snapshot, ui, nowMs) : ({ found: false })

  // Why there is nothing, or nothing trustworthy, to show. Empty when the
  // snapshot is current.
  readonly property string problem: {
    if (fileState === "missing")
      return "No snapshot at " + snapshotPath + ". musterd writes it once Muster is installed in herdr and herdr is running."
    if (fileState === "unreadable")
      return snapshotPath + " could not be read: " + fileError
    if (newer) return Muster.updateText(snapshot)
    if (stale) return Muster.staleText(snapshot, nowMs)
    return ""
  }

  function applySnapshot(text) {
    var parsed = Muster.parseSnapshot(text)
    if (parsed.ok) {
      snapshot = parsed.snapshot
      fileError = ""
      fileState = "loaded"
    } else {
      snapshot = null
      fileError = parsed.error
      fileState = "unreadable"
    }
    nowMs = Date.now()
  }

  function snapshotGone() {
    snapshot = null
    fileError = ""
    fileState = "missing"
  }

  function refresh() {
    snapshotFile.reload()
    uiFile.reload()
  }

  // musterd replaces the file by renaming a new one over it on every
  // reconcile, which is how Omarchy's own shell.json is written and watched.
  FileView {
    id: snapshotFile
    path: root.snapshotPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySnapshot(text())
    onLoadFailed: root.snapshotGone()
  }

  FileView {
    id: uiFile
    path: root.uiPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.ui = Muster.parseUi(text())
    onLoadFailed: root.ui = Muster.parseUi("")
  }

  // Ticks the clock the stale rule reads. It is also the fallback if a watch
  // ever misses a rename: musterd rewrites every five seconds, so a snapshot
  // older than two of those, or none at all, is read again. When the watch
  // works, this costs nothing beyond the clock.
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.fileState !== "loaded" || !(root.nowMs - root.snapshot.generatedAtMs < 12000))
        root.refresh()
    }
  }
}
