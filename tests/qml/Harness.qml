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
      eq(p.header, { counts: "3 workspaces · 5 agents", needsYou: 4 }, "the title line counts what is undismissed")
      eq(p.muster.accent, "#fe8019", "the NEEDS YOU rule takes the top undismissed row's colour")
      eq(p.orch.found, true, "orchestrator found")
      eq(p.orch.who, "API", "orchestrator named by its repo")
      eq(p.orch.color, "#fb4934", "the colour picked in ui.json wins")
      // ui.json sorts a-z: api's agents by name, then web's, the empty
      // workspace last.
      eq(p.tiles.map(function(t) { return t.key }),
         ["pane:w1:p3", "pane:w1:p2", "pane:w1:p1", "pane:w2:p1", "pane:w2:p2", "ws:w3"], "one tile per agent and empty workspace")
      eq(p.targetKeys, ["ribbon:w2:p1", "ribbon:w1:p9", "ribbon:w2:p2", "ribbon:w1:p1",
                        "tile:pane:w1:p3", "tile:pane:w1:p2", "tile:pane:w1:p1", "tile:pane:w2:p1",
                        "tile:pane:w2:p2", "tile:ws:w3", "orch"], "what j/k walk: ribbon, tiles, strip")
      eq(p.muster.problem, "", "no problem to report")
    },

    function keys() {
      var w = widgets.fresh
      var p = panelOf(w)
      var k = keysOf(w)
      k.press(Qt.Key_Down, "", 0)
      eq(p.selectedKey, "ribbon:w2:p1", "down selects the first row")
      for (var i = 0; i < 10; i++) k.press(0, "j", 0)
      eq(p.selectedKey, "orch", "j reaches the orchestrator last")
      k.press(0, "j", 0)
      eq(p.selectedKey, "ribbon:w2:p1", "and wraps round to the top")
      k.press(0, "k", 0)
      eq(p.selectedKey, "orch", "k wraps back")
      k.press(0, "G", 0)
      eq(p.selectedKey, "orch", "G is the last target")
      k.press(0, "g", 0)
      eq(p.selectedKey, "ribbon:w2:p1", "g is the first")
      for (var n = 0; n < 6; n++) k.press(0, "j", 0)
      eq(p.selectedKey, "tile:pane:w1:p1", "j walks into the tiles")

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
      var before = StubLog.processes.length
      keysOf(w).press(Qt.Key_Return, "", 0)
      eq(StubLog.processes.length, before, "enter with nothing selected goes nowhere, as in the overlay")
      keysOf(w).press(0, "2", 0)
      eq(lastProcess().command[lastProcess().command.length - 1], "w1:p9", "a digit jumps to that ribbon row")
      lastProcess().process.finish(1, "", "muster jump: pane gone")

      p.selectedKey = "tile:ws:w3"
      keysOf(w).press(Qt.Key_Return, "", 0)
      eq(lastProcess().command.slice(-2), ["jump", "ws:w3"], "an empty workspace's tile focuses the workspace")
      lastProcess().process.finish(1, "", "muster jump: gone")

      keysOf(w).press(0, "e", 0)
      check(p.sayMore, "e expands what the orchestrator said")
      keysOf(w).press(Qt.Key_Escape, "", 0)
      check(!p.sayMore && w.opened, "esc folds it first")
      keysOf(w).press(Qt.Key_Escape, "", 0)
      check(!w.opened, "then closes")
    },

    function actionKeys() {
      var w = widgets.fresh
      w.open()
      var p = panelOf(w)
      var k = keysOf(w)
      var before = StubLog.processes.length

      k.press(0, "t", 0)
      var run = lastProcess()
      eq(StubLog.processes.length, before + 1, "t starts a process")
      eq(run.command.slice(-2), ["report", "w2:p1"], "t with nothing selected reports the only landed row")
      run.process.finish(0, "told the orchestrator api landed\n", "")
      eq(p.notice, "told the orchestrator api landed", "t shows what it told")
      check(w.opened, "reporting keeps the panel open")

      k.press(0, "x", 0)
      check(p.notice.indexOf("select one first") !== -1, "x with nothing selected says so")
      eq(StubLog.processes.length, before + 1, "and runs nothing")

      k.press(Qt.Key_Down, "", 0)
      k.press(0, "x", 0)
      run = lastProcess()
      eq(run.command.slice(-2), ["dismiss", "w2:p1"], "x dismisses the selected row")
      run.process.finish(1, "", "muster dismiss: w2:p1 has no row in the ribbon to dismiss")
      eq(p.notice, "muster dismiss: w2:p1 has no row in the ribbon to dismiss", "a failed dismiss says why")

      p.selectedKey = "tile:pane:w2:p1"
      k.press(0, "x", 0)
      check(p.notice.indexOf("select one first") !== -1, "x on a tile says it takes a ribbon row")
      k.press(0, "t", 0)
      eq(lastProcess().command.slice(-2), ["report", "w2:p1"], "t on the landed agent's tile reports it")
      lastProcess().process.finish(0, "told the orchestrator api landed\n", "")

      var runs = StubLog.processes.length
      p.selectedKey = "ribbon:w1:p9"
      k.press(0, "o", 0)
      check(p.notice.indexOf("select one first") !== -1, "o on a pane with no agent says so")
      p.selectedKey = "tile:pane:w1:p1"
      k.press(0, "o", 0)
      eq(p.notice, "already the orchestrator", "o on the orchestrator says so")
      eq(StubLog.processes.length, runs, "and neither runs anything")
      p.selectedKey = "tile:pane:w2:p1"
      k.press(0, "o", 0)
      run = lastProcess()
      eq(run.command.slice(-2), ["mark-orchestrator", "w2:p1"], "o marks the selected agent")
      run.process.finish(0, "marked w2:p1 as the orchestrator\n", "")
      eq(p.notice, "marked as the orchestrator", "and says it did")
      k.press(0, "o", 0)
      lastProcess().process.finish(1, "", "muster: rename: no such pane")
      eq(p.notice, "could not mark: muster: rename: no such pane", "a failed mark says why")

      k.press(0, "M", 0)
      run = lastProcess()
      eq(run.command.slice(-2), ["jump", "orchestrator"], "M jumps to the orchestrator")
      run.process.finish(0, "", "")
      check(!w.opened, "and closes once there")
    },

    function compose() {
      var w = widgets.fresh
      w.open()
      var p = panelOf(w)
      var k = keysOf(w)
      var before = StubLog.processes.length

      k.press(0, "i", 0)
      check(p.composing, "i opens the message input")
      check(k.blocked, "the panel's keys stand aside while it is open")
      k.press(0, "j", 0)
      eq(p.selectedKey, "", "j typed into the input does not move the selection")

      p.composeInput.text = "  pull main and rerun  "
      p.composeInput.accepted()
      check(!p.composing, "enter closes the input")
      check(!k.blocked, "and gives the keys back")
      var run = lastProcess()
      eq(run.command.slice(-2), ["tell", "pull main and rerun"], "enter sends the message, trimmed")
      run.process.finish(0, "sent to the orchestrator\n", "")
      eq(p.notice, "sent to the orchestrator", "and says it was sent")

      k.press(0, "i", 0)
      p.composeInput.text = "never mind"
      p.endCompose()
      check(!p.composing, "esc closes the input")
      eq(StubLog.processes.length, before + 1, "without sending")

      k.press(0, "i", 0)
      p.composeInput.accepted()
      eq(StubLog.processes.length, before + 1, "an empty message is not sent")
      w.close()
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
      eq(p.targetKeys[0], "tile:pane:w1:p3", "the walk starts at the tiles")
      eq(p.header.needsYou, 0, "nothing in the title line")
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
