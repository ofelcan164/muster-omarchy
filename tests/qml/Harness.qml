import QtQuick
import Quickshell.Io
import qs.Ui

// Drives the real BarWidget.qml, Panel.qml, Data.qml and Actions.qml through
// the stand-ins in stubs/. run.py sets the context: pluginDir, dirs (one
// state dir per case), testEnv, fixtureQuiet (a snapshot to write mid-run)
// and files (which writes it). Every check that fails logs "FAIL"; the last
// line is "DONE".
Item {
  id: harness

  property int checks: 0
  property int failures: 0
  property var widgets: ({})

  function check(ok, what) {
    checks++
    if (!ok) {
      failures++
      console.log("FAIL: " + what)
    }
  }

  function eq(actual, expected, what) {
    var a = JSON.stringify(actual), e = JSON.stringify(expected)
    check(a === e, what + ": got " + a + ", want " + e)
  }

  QtObject {
    id: stubBar
    property color foreground: "#cacccc"
    property color barForeground: "#cacccc"
    property color background: "#101315"
    property color urgent: "#a55555"
    property string fontFamily: "monospace"
    property string position: "top"
    property bool vertical: false
    property int barSize: 26
    property bool foregroundAnimationEnabled: true
    property var activePopout: null
    property var clickTargets: []
    property var tooltips: []
    function showTooltip(target, text) { tooltips.push(text) }
    function hideTooltip(target) {}
    function registerClickTarget(target) { clickTargets.push(target) }
    function unregisterClickTarget(target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(owner, direction) { return false }
    function moduleWidgets(id) { return [] }
    function run(command) {}
  }

  function widget(name, settings) {
    var component = Qt.createComponent(pluginDir + "/BarWidget.qml")
    if (component.status !== Component.Ready) {
      check(false, "BarWidget.qml did not load: " + component.errorString())
      return null
    }
    var w = component.createObject(harness, { bar: stubBar, settings: settings })
    widgets[name] = w
    return w
  }

  // The Panel a widget loaded, found through the keyboard panel it made.
  function panelOf(w) {
    for (var i = 0; i < StubUi.panels.length; i++)
      if (StubUi.panels[i].owner === w) return StubUi.panels[i].parent
    return null
  }

  function keysOf(w) {
    for (var i = 0; i < StubUi.panels.length; i++)
      if (StubUi.panels[i].owner === w) return StubUi.panels[i].focusTarget
    return null
  }

  function lastProcess() {
    return StubLog.processes.length ? StubLog.processes[StubLog.processes.length - 1] : null
  }

  function fileView(path) {
    for (var i = 0; i < StubLog.fileViews.length; i++)
      if (StubLog.fileViews[i].path === path) return StubLog.fileViews[i]
    return null
  }

  // ------------------------------------------------------------------ steps

  property var steps: [
    function create() {
      widget("fresh", { stateDir: dirs.fresh, muster: "" })
      widget("stale", { stateDir: dirs.stale })
      widget("missing", { stateDir: dirs.missing })
      widget("newer", { stateDir: dirs.newer })
      widget("broken", { stateDir: dirs.broken })
      widget("home", {})
      widget("tilde", { stateDir: "~/elsewhere/" })
    },

    function barStates() {
      var w = widgets.fresh
      check(w.visible, "a fresh snapshot shows the widget")
      eq(w.view.cls, "landed", "fresh class")
      eq(w.view.text, "◆ 4", "fresh text, one row dismissed in ui.json")
      eq(w.view.color, "#fe8019", "fresh colour follows the top undismissed row")
      eq(w.view.tooltip.split("\n")[0], "LANDED web/login · api#412 landed, nobody moved", "fresh tooltip")

      eq(widgets.stale.view.cls, "stale", "stale class")
      eq(widgets.stale.view.text, "◇", "stale text carries no count")
      check(!widgets.missing.visible, "no snapshot hides the widget")
      eq(widgets.missing.view.cls, "missing", "missing class")
      eq(widgets.newer.view.cls, "update", "newer class")
      eq(widgets.broken.view.cls, "error", "broken class")

      eq(panelOf(widgets.home).muster.stateDir, testEnv.HOME + "/.local/state/herdr/plugins/muster",
         "an empty stateDir is Muster's default")
      eq(panelOf(widgets.tilde).muster.stateDir, testEnv.HOME + "/elsewhere", "~ and a trailing slash")
      eq(panelOf(widgets.fresh).muster.musterCommand, "muster", "an empty muster setting is muster")
    },

    function openPanel() {
      var w = widgets.fresh
      w.open()
      check(w.opened, "open() opens the panel")
      var p = panelOf(w)
      eq(p.ribbon.length, 4, "the panel's ribbon")
      eq(p.ribbon[0].paneId, "w2:p1", "the dismissed row is gone")
      eq(p.moreRows, 0, "nothing beyond the ribbon")
      eq(p.orch.found, true, "orchestrator found")
      eq(p.orch.who, "API", "orchestrator named by its repo")
      eq(p.orch.color, "#fb4934", "the colour picked in ui.json wins")
      eq(p.repos.length, 3, "one row per repo")
      eq(p.targetKeys, ["ribbon:w2:p1", "ribbon:w1:p9", "ribbon:w2:p2", "ribbon:w1:p1", "orch"], "what j/k walk")
      eq(p.muster.problem, "", "no problem to report")
    },

    function keys() {
      var w = widgets.fresh
      var p = panelOf(w)
      var k = keysOf(w)
      k.press(Qt.Key_Down, "", 0)
      eq(p.selectedKey, "ribbon:w2:p1", "down selects the first row")
      for (var i = 0; i < 6; i++) k.press(0, "j", 0)
      eq(p.selectedKey, "orch", "j stops at the orchestrator")
      k.press(0, "k", 0)
      eq(p.selectedKey, "ribbon:w1:p1", "k moves back up")

      k.press(Qt.Key_Return, "", 0)
      var run = lastProcess()
      check(run !== null, "enter starts a process")
      eq(run.command, ["bash", "-lc", "exec bash \"$@\"", "bash", pluginDir + "/bin/muster-omarchy",
                       "--muster", "muster", "--state-dir", dirs.fresh, "jump", "w1:p1"], "the jump command")
      check(p.jumping, "jumping while it runs")
      k.press(Qt.Key_Return, "", 0)
      eq(StubLog.processes.length, 1, "a second enter waits for the first jump")

      run.process.finish(1, "", "starting\nmuster jump: pane gone")
      eq(p.notice, "muster jump: pane gone", "a failed jump shows stderr's last line")
      check(w.opened, "a failed jump keeps the panel open")
      check(!p.jumping, "not jumping once it ends")
    },

    function jumpClosesPanel() {
      var w = widgets.fresh
      var p = panelOf(w)
      p.selectedKey = "orch"
      keysOf(w).press(Qt.Key_Return, "", 0)
      var run = lastProcess()
      eq(run.command[run.command.length - 1], "w1:p1", "the orchestrator row jumps to its pane")
      run.process.finish(0, "", "")
      check(!w.opened, "a jump that worked closes the panel")
      eq(p.notice, "", "and clears the notice")
    },

    function reopenResets() {
      var w = widgets.fresh
      var p = panelOf(w)
      w.open()
      eq(p.selectedKey, "", "reopening clears the selection")
      keysOf(w).press(Qt.Key_Return, "", 0)
      eq(lastProcess().command[lastProcess().command.length - 1], "w2:p1", "enter with nothing selected takes the top row")
      lastProcess().process.finish(0, "", "")
      keysOf(w).press(Qt.Key_Escape, "", 0)
      check(!w.opened, "escape closes")
    },

    function snapshotChanges() {
      files.write(dirs.fresh + "/snapshot.json", fixtureQuiet)
      var fv = fileView(dirs.fresh + "/snapshot.json")
      check(fv !== null, "the snapshot is watched")
      check(fv.watchChanges, "with watchChanges on")
      fv.fileChanged()
    },

    function afterChange() {
      var w = widgets.fresh
      eq(w.view.cls, "working", "a change on disk reaches the bar")
      eq(w.view.text, "◆", "no count when nothing needs you")
      check(w.view.dimmed, "dim when nothing needs you")
      w.open()
      var p = panelOf(w)
      eq(p.ribbon.length, 0, "an empty ribbon")
      eq(p.targetKeys, ["orch"], "only the orchestrator to walk")
      w.close()
    },

    function stalePanel() {
      var w = widgets.stale
      w.open()
      var p = panelOf(w)
      check(p.readable, "a stale snapshot is still drawn")
      check(p.muster.problem.indexOf("musterd is not running") !== -1, "and says why it is old")
      w.close()

      widgets.newer.open()
      eq(panelOf(widgets.newer).ribbon.length, 0, "a newer snapshot draws nothing")
      check(panelOf(widgets.newer).muster.problem.indexOf("omarchy plugin update") !== -1, "and asks for an update")
      widgets.newer.close()
    }
  ]

  property int step: 0

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      if (harness.step >= harness.steps.length) {
        stop()
        console.log("DONE " + harness.checks + " checks, " + harness.failures + " failures")
        return
      }
      try {
        harness.steps[harness.step]()
      } catch (e) {
        harness.check(false, "step " + harness.step + " threw: " + e + "\n" + e.stack)
      }
      harness.step++
    }
  }
}
