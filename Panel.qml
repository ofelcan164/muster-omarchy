pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "lib/muster.js" as Muster

// The panel that drops from the diamond: Muster's overlay, drawn the way the
// overlay draws it. The title line, the ribbon of what needs you, one tile per
// agent and per empty workspace, and the orchestrator strip pinned to the
// bottom, on the overlay's own dark surface and in its colours, so the panel
// and the popup in herdr read as the same screen.
//
// A click or enter lands on the selection, and i, t, x, e, M, g, G and 1-9 do
// what they do in the overlay, through the same muster commands.
Panel {
  id: musterPanel // not `root`: inside a Component, `root` would resolve to that
  moduleName: "io.github.ofelcan164.muster"
  // Nested in a bar widget: the shell reaches it through BarWidget.qml's
  // open(), close() and toggle(), so it registers no IPC target of its own.
  manageIpc: false

  // Injected by BarWidget.
  property var anchorItem: null
  property var hostWidget: null
  property var muster: null

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property font mono: Qt.font({ family: fontFamily, pixelSize: Style.font.body })
  readonly property font monoBold: Qt.font({ family: fontFamily, pixelSize: Style.font.body, bold: true })
  // One terminal cell, which the overlay's half-block bars and indents are
  // measured in, and one terminal line.
  readonly property real cell: cellMetrics.advanceWidth
  readonly property real lineHeight: cellMetrics.height

  readonly property bool readable: !!muster && muster.readable
  readonly property var ribbon: muster ? muster.ribbon : []
  readonly property var tiles: muster ? muster.tiles : []
  readonly property var orch: muster ? muster.orchestrator : ({ found: false })
  readonly property var header: muster ? muster.header : ({ counts: "", needsYou: 0 })

  // What j/k walk and enter lands on, in the overlay's order: the ribbon rows,
  // the tiles, then the strip. The selection is kept by key, not position, so
  // a snapshot that arrives while the panel is open does not move it.
  readonly property var targetKeys: {
    var keys = []
    for (var i = 0; i < ribbon.length; i++) keys.push("ribbon:" + ribbon[i].paneId)
    for (var j = 0; j < tiles.length; j++) keys.push("tile:" + tiles[j].key)
    if (orch.found) keys.push("orch")
    return keys
  }
  // Nothing is selected on open, as in the overlay: the first thing lit is
  // the thing you arrowed or pointed to.
  property string selectedKey: ""
  readonly property int selectedIndex: targetKeys.indexOf(selectedKey)
  readonly property string selectedPane: paneFor(selectedKey)

  property string notice: ""
  // The i input is open, and every key is text until enter or esc.
  property bool composing: false
  readonly property Item composeInput: composeField
  // e: the orchestrator's last message, whole.
  property bool sayMore: false
  property bool jumping: false

  // Working spins and blocked pulses, and nothing else moves.
  property int frame: 0
  readonly property bool animating: {
    for (var i = 0; i < tiles.length; i++)
      if (tiles[i].status === "working" || tiles[i].status === "blocked") return true
    return orch.found === true && (orch.status === "working" || orch.status === "blocked")
  }

  function paneFor(key) {
    if (key === "orch") return orch.found ? orch.paneId : ""
    if (key.indexOf("ribbon:") === 0) return key.slice(7)
    if (key.indexOf("tile:pane:") === 0) return key.slice(10)
    return ""
  }

  // What muster jump takes for a key: a pane, or ws:<id> for an empty tile.
  function jumpFor(key) {
    if (key.indexOf("tile:ws:") === 0) return key.slice(5)
    return paneFor(key)
  }

  // Selected and hovered draw the same: the pointer lights up exactly what a
  // click would take.
  function isActive(key, hovered) {
    return hovered || selectedKey === key
  }

  function say(ok, message) {
    notice = message
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(hostWidget || musterPanel, direction)
    return false
  }

  function textKey(text) {
    if (text === "i") startCompose()
    else if (text === "t") report()
    else if (text === "e") { if (orch.found && orch.said !== "") sayMore = !sayMore }
    else if (text === "g") { if (targetKeys.length > 0) selectedKey = targetKeys[0] }
    else if (text === "G") { if (targetKeys.length > 0) selectedKey = targetKeys[targetKeys.length - 1] }
    else if (text === "M") {
      if (orch.found) jumpTo("orchestrator")
      else say(false, "no orchestrator marked, so there is nowhere to go")
    } else if (text.length === 1 && text >= "1" && text <= "9") {
      // A digit lands straight on that ribbon row.
      var n = Number(text) - 1
      if (n < ribbon.length) jumpTo(ribbon[n].paneId)
    }
  }

  // esc folds the message first, then closes, never both at once.
  function escapeKey() {
    if (sayMore) sayMore = false
    else close()
  }

  function startCompose() {
    if (!orch.found) {
      say(false, "no orchestrator marked, so there is nobody to tell")
      return
    }
    notice = ""
    composeField.text = ""
    composing = true
    composeField.forceActiveFocus()
  }

  function endCompose() {
    composing = false
    keyCatcher.forceActiveFocus()
  }

  function sendCompose() {
    var text = composeField.text.trim()
    endCompose()
    if (text === "") return
    actions.tell(text, say)
  }

  // t reports the landed row the selection is on, or the only one there is.
  function report() {
    var row = Muster.reportTarget(muster ? muster.snapshot : null, selectedPane)
    if (!row) {
      say(false, "nothing to report: no landed row is selected")
      return
    }
    if (!orch.found) {
      say(false, "no orchestrator marked, so there is nobody to tell")
      return
    }
    actions.report(row.pane_id, say)
  }

  // x takes a ribbon row off until its status changes. The row goes when
  // Muster rewrites ui.json and the watch sees it, not before, so the panel
  // never shows a dismissal that did not happen.
  function dismiss() {
    if (selectedKey.indexOf("ribbon:") !== 0) {
      say(false, "x dismisses a row that needs you: select one first")
      return
    }
    actions.dismiss(selectedPane, function(ok, message) { if (!ok) say(false, message) })
  }

  // Up and down wrap, so holding a key never dead-ends. Nothing selected yet:
  // the first move lands on the end you came from.
  function move(dy) {
    var n = targetKeys.length
    if (n === 0) return
    var i = selectedIndex
    if (i < 0) i = dy > 0 ? 0 : n - 1
    else i = ((i + dy) % n + n) % n
    selectedKey = targetKeys[i]
  }

  function activate() {
    if (selectedIndex >= 0) jumpTo(jumpFor(selectedKey))
  }

  function jumpTo(target) {
    if (target === "" || jumping) return
    jumping = true
    notice = ""
    actions.jump(target, function(ok, message) {
      musterPanel.jumping = false
      if (ok) musterPanel.close()
      else musterPanel.say(false, message)
    })
  }

  // Keeps the selection on screen, the way the overlay scrolls to it.
  function reveal(item) {
    if (!item) return
    var p = item.mapToItem(column, 0, 0)
    if (p.y < flick.contentY) flick.contentY = p.y
    else if (p.y + item.height > flick.contentY + flick.height)
      flick.contentY = Math.min(p.y + item.height - flick.height, Math.max(0, flick.contentHeight - flick.height))
  }

  onOpenedChanged: if (opened) {
    selectedKey = ""
    notice = ""
    composing = false
    sayMore = false
    frame = 0
    if (muster) {
      muster.nowMs = Date.now()
      muster.refresh()
    }
    flick.contentY = 0
  }

  TextMetrics {
    id: cellMetrics
    font: musterPanel.mono
    text: "M"
  }

  Timer {
    interval: Muster.FRAME_MS
    repeat: true
    running: musterPanel.opened && musterPanel.animating
    onTriggered: musterPanel.frame = (musterPanel.frame + 1) % 64
    onRunningChanged: if (!running) musterPanel.frame = 0
  }

  Actions {
    id: actions
    musterCommand: musterPanel.muster ? musterPanel.muster.musterCommand : "muster"
    stateDir: musterPanel.muster ? musterPanel.muster.stateDir : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: musterPanel.anchorItem
    owner: musterPanel.hostWidget || musterPanel
    bar: musterPanel.bar
    open: musterPanel.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + strip.implicitHeight + Style.space(16), Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: musterPanel.composing

      onMoveRequested: function(dx, dy) { if (dy !== 0) musterPanel.move(dy) }
      onActivateRequested: musterPanel.activate()
      onCloseRequested: musterPanel.escapeKey()
      onTabRequested: function(direction) { musterPanel.switchPanel(direction) }
      onDeleteRequested: musterPanel.dismiss()
      onTextKey: function(text) { musterPanel.textKey(text) }

      // The overlay's own surface, in Muster's colours whatever the Omarchy
      // theme, as the popup in herdr is.
      Rectangle {
        id: screen
        anchors.fill: parent
        color: Muster.BG
        radius: Style.cornerRadius
        clip: true

        Flickable {
          id: flick
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: strip.top
          anchors.topMargin: Style.space(8)
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: column
            width: flick.width

            // ------------------------------------------------ the title line
            Row {
              x: musterPanel.cell
              height: musterPanel.lineHeight

              Text {
                text: "MUSTER"
                textFormat: Text.PlainText
                color: Muster.YELLOW
                font: musterPanel.monoBold
              }
              Text {
                text: musterPanel.header.counts !== "" ? "  " + musterPanel.header.counts : ""
                textFormat: Text.PlainText
                color: Muster.DIM
                font: musterPanel.mono
              }
              Text {
                visible: musterPanel.readable && musterPanel.header.needsYou > 0
                text: "  " + musterPanel.header.needsYou + " need you"
                textFormat: Text.PlainText
                color: Muster.RED
                font: musterPanel.mono
              }
            }

            // The overlay's warning: why there is nothing to show, or why
            // what is shown is old.
            Text {
              x: musterPanel.cell
              width: parent.width - musterPanel.cell * 2
              visible: text !== ""
              text: musterPanel.muster && musterPanel.muster.problem !== "" ? "! " + musterPanel.muster.problem : ""
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: Muster.ORANGE
              font: musterPanel.mono
            }

            Item { width: 1; height: musterPanel.lineHeight }

            // ---------------------------------------------------- the ribbon
            Column {
              width: parent.width
              visible: musterPanel.readable && musterPanel.ribbon.length > 0

              // The rule carries the count and the colour of the most urgent
              // row, so the section says how bad things are before any row.
              Item {
                width: parent.width
                height: musterPanel.lineHeight

                Rectangle {
                  id: needsBadge
                  height: parent.height
                  width: needsLabel.implicitWidth
                  color: musterPanel.muster ? musterPanel.muster.accent : Muster.DIM

                  Text {
                    id: needsLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: " NEEDS YOU " + musterPanel.header.needsYou + " "
                    textFormat: Text.PlainText
                    color: Muster.BG
                    font: musterPanel.monoBold
                  }
                }

                Rectangle {
                  anchors.left: needsBadge.right
                  anchors.right: parent.right
                  anchors.rightMargin: musterPanel.cell
                  anchors.verticalCenter: parent.verticalCenter
                  height: 1
                  color: needsBadge.color
                }
              }

              Repeater {
                model: musterPanel.ribbon

                delegate: Rectangle {
                  id: ribbonRow
                  required property var modelData
                  readonly property string key: "ribbon:" + modelData.paneId
                  readonly property bool selected: musterPanel.selectedKey === key

                  width: parent.width
                  implicitHeight: ribbonLines.implicitHeight
                  // The top two ranks keep a warm background even unselected,
                  // so what most needs you reads first. The rest sit on a
                  // panel so the ribbon reads as one block.
                  color: musterPanel.isActive(key, ribbonMouse.containsMouse) ? Muster.SEL_BG
                    : modelData.hot ? Muster.HOT_BG : Muster.PANEL_BG

                  onSelectedChanged: if (selected) musterPanel.reveal(ribbonRow)

                  Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(musterPanel.cell / 2)
                    color: ribbonRow.modelData.accent
                  }

                  Column {
                    id: ribbonLines
                    x: musterPanel.cell * 2
                    width: parent.width - x - musterPanel.cell

                    RowLayout {
                      width: parent.width
                      spacing: 0

                      Text {
                        text: ribbonRow.modelData.index + " "
                        textFormat: Text.PlainText
                        color: ribbonRow.modelData.accent
                        font: musterPanel.monoBold
                      }

                      Rectangle {
                        implicitWidth: badgeLabel.implicitWidth
                        implicitHeight: musterPanel.lineHeight
                        color: ribbonRow.modelData.accent

                        Text {
                          id: badgeLabel
                          anchors.verticalCenter: parent.verticalCenter
                          text: " " + ribbonRow.modelData.label + " "
                          textFormat: Text.PlainText
                          color: Muster.BG
                          font: musterPanel.monoBold
                        }
                      }

                      // The workspace leads, faint, the way every tile does:
                      // the ribbon and the grid read as the same map.
                      Text {
                        text: " " + (ribbonRow.modelData.workspace !== "" ? ribbonRow.modelData.workspace + " " : "")
                        textFormat: Text.PlainText
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }

                      Text {
                        text: ribbonRow.modelData.sigil + " " + ribbonRow.modelData.repo
                        textFormat: Text.PlainText
                        color: ribbonRow.modelData.repoColor
                        font: musterPanel.monoBold
                      }

                      Text {
                        text: "/"
                        textFormat: Text.PlainText
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }

                      Text {
                        Layout.fillWidth: true
                        text: ribbonRow.modelData.agent
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.FG
                        font: musterPanel.monoBold
                      }

                      Text {
                        text: " " + ribbonRow.modelData.age
                        textFormat: Text.PlainText
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                    }

                    // The detail is the sentence you actually read, so it
                    // gets the bright foreground.
                    Text {
                      x: musterPanel.cell * 4
                      width: parent.width - x
                      visible: text !== ""
                      text: ribbonRow.modelData.detail
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: Muster.FG
                      font: musterPanel.mono
                    }
                  }

                  MouseArea {
                    id: ribbonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      musterPanel.selectedKey = ribbonRow.key
                      musterPanel.jumpTo(ribbonRow.modelData.paneId)
                    }
                  }
                }
              }

              Item { width: 1; height: musterPanel.lineHeight }
            }

            // ------------------------------------------------------ the grid
            Item {
              width: parent.width
              height: musterPanel.lineHeight
              visible: musterPanel.readable

              Text {
                id: gridLabel
                anchors.verticalCenter: parent.verticalCenter
                text: " AGENTS & WORKSPACES "
                textFormat: Text.PlainText
                color: Muster.DIM
                font: musterPanel.mono
              }

              Rectangle {
                anchors.left: gridLabel.right
                anchors.right: parent.right
                anchors.rightMargin: musterPanel.cell
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Muster.FAINT
              }
            }

            Text {
              visible: musterPanel.readable && musterPanel.tiles.length === 0
              text: "  no workspaces discovered yet"
              textFormat: Text.PlainText
              color: Muster.DIM
              font: musterPanel.mono
            }

            Repeater {
              model: musterPanel.readable ? musterPanel.tiles : []

              delegate: Column {
                id: tileBlock
                required property var modelData
                required property int index
                width: parent.width

                // A blank line between tiles, which belongs to neither.
                Item { width: 1; height: tileBlock.index > 0 ? musterPanel.lineHeight : 0 }

                Rectangle {
                  id: tile
                  readonly property var t: tileBlock.modelData
                  readonly property string key: "tile:" + t.key
                  readonly property bool selected: musterPanel.selectedKey === key

                  width: parent.width
                  implicitHeight: tileLines.implicitHeight
                  color: musterPanel.isActive(key, tileMouse.containsMouse) ? Muster.SEL_BG : "transparent"

                  onSelectedChanged: if (selected) musterPanel.reveal(tile)

                  // The repo's bar, or a faint one for a workspace with no agent.
                  Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(musterPanel.cell / 2)
                    color: tile.t.barColor
                  }

                  Column {
                    id: tileLines
                    x: musterPanel.cell * 2
                    width: parent.width - x - musterPanel.cell

                    // Where: the workspace, marked when it is the one you are
                    // in, and the pane enter lands on.
                    RowLayout {
                      width: parent.width
                      spacing: 0

                      Text {
                        text: tile.t.num
                        textFormat: Text.PlainText
                        color: Muster.FG
                        font: musterPanel.mono
                      }
                      Text {
                        Layout.fillWidth: !tile.t.isAgent
                        text: (tile.t.isAgent ? " " : "   ") + tile.t.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                      Text {
                        Layout.fillWidth: true
                        visible: tile.t.isAgent
                        text: " " + (tile.t.chip || "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }
                    }

                    // An empty workspace: what its panes sit in.
                    RowLayout {
                      visible: !tile.t.isAgent
                      width: parent.width
                      spacing: 0

                      Text {
                        text: "    "
                        textFormat: Text.PlainText
                        font: musterPanel.mono
                      }
                      Repeater {
                        model: tile.t.isAgent ? [] : tile.t.sigils
                        delegate: Text {
                          required property var modelData
                          text: modelData.sigil
                          textFormat: Text.PlainText
                          color: modelData.color
                          font: musterPanel.mono
                        }
                      }
                      Text {
                        Layout.fillWidth: true
                        text: (tile.t.isAgent || tile.t.sigils.length === 0 ? "" : " ") + (tile.t.detail || "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }
                    }

                    // Which checkout: the repo in its colour, the branch faint.
                    RowLayout {
                      visible: tile.t.isAgent
                      width: parent.width
                      spacing: 0

                      Text {
                        text: (tile.t.sigil || "") + " " + (tile.t.repo || "")
                        textFormat: Text.PlainText
                        color: tile.t.repoColor || Muster.FG
                        font: musterPanel.monoBold
                      }
                      Text {
                        Layout.fillWidth: true
                        text: tile.t.branch ? " · " + tile.t.branch : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }
                    }

                    // Who: the orchestrator's mark, status, name and kind, and
                    // how long it has held that status.
                    RowLayout {
                      visible: tile.t.isAgent
                      width: parent.width
                      spacing: 0

                      Text {
                        text: tile.t.orchestrator ? "⌂" : " "
                        textFormat: Text.PlainText
                        color: Muster.FG
                        font: musterPanel.mono
                      }
                      Text {
                        text: Muster.statusIcon(tile.t.status, musterPanel.frame) + " "
                        textFormat: Text.PlainText
                        color: Muster.statusColor(tile.t.status, musterPanel.frame)
                        font: musterPanel.mono
                      }
                      Text {
                        text: tile.t.name || ""
                        textFormat: Text.PlainText
                        color: Muster.FG
                        font: musterPanel.monoBold
                      }
                      Text {
                        Layout.fillWidth: true
                        text: tile.t.kind ? " [" + tile.t.kind + "]" : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.FAINT
                        font: musterPanel.mono
                      }
                      Text {
                        text: " " + (tile.t.age || "")
                        textFormat: Text.PlainText
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                    }

                    // What it says: the question, or the task.
                    Text {
                      x: musterPanel.cell * 4
                      width: parent.width - x
                      visible: tile.t.isAgent && !!tile.t.task
                      text: tile.t.task || ""
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: tile.t.taskColor || Muster.DIM
                      font: musterPanel.mono
                    }

                    // What it depends on. Never "blocked", which means waiting
                    // on you.
                    RowLayout {
                      x: musterPanel.cell * 4
                      width: parent.width - x
                      visible: tile.t.isAgent && !!tile.t.dependsOn
                      spacing: 0

                      Text {
                        text: "⧗ depends on "
                        textFormat: Text.PlainText
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                      Text {
                        text: tile.t.dependsOn ? (tile.t.dependsOn.sigil ? tile.t.dependsOn.sigil + " " : "") + tile.t.dependsOn.repo : ""
                        textFormat: Text.PlainText
                        color: tile.t.dependsOn ? tile.t.dependsOn.color : Muster.DIM
                        font: musterPanel.mono
                      }
                      Text {
                        Layout.fillWidth: true
                        text: tile.t.dependsOn ? " · " + tile.t.dependsOn.when : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                    }

                    // Which repos have agents that depend on this one.
                    Row {
                      x: musterPanel.cell * 4
                      visible: tile.t.isAgent && !!tile.t.neededBy && tile.t.neededBy.length > 0

                      Text {
                        text: "▸ needed by "
                        textFormat: Text.PlainText
                        color: Muster.DIM
                        font: musterPanel.mono
                      }
                      Repeater {
                        model: tile.t.isAgent ? tile.t.neededBy : []
                        delegate: Text {
                          required property var modelData
                          required property int index
                          text: (index > 0 ? ", " : "") + modelData.sigil + " " + modelData.repo
                          textFormat: Text.PlainText
                          color: modelData.color
                          font: musterPanel.mono
                        }
                      }
                    }

                    // The workspace's other panes, shared by its agent tiles.
                    Text {
                      x: musterPanel.cell * 4
                      width: parent.width - x
                      visible: tile.t.isAgent && !!tile.t.footer
                      text: tile.t.footer || ""
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: Muster.FAINT
                      font: musterPanel.mono
                    }
                  }

                  MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      musterPanel.selectedKey = tile.key
                      musterPanel.jumpTo(tile.t.jump)
                    }
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------ the orchestrator
        // Pinned to the bottom edge, as in the overlay: it is how you reach
        // the orchestrator, and scrolling it away would leave you blind.
        Column {
          id: strip
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          visible: musterPanel.readable

          Item { width: 1; height: musterPanel.lineHeight }

          Item {
            width: parent.width
            height: musterPanel.lineHeight

            Text {
              id: stripLabel
              anchors.verticalCenter: parent.verticalCenter
              text: " ORCHESTRATOR "
              textFormat: Text.PlainText
              color: Muster.DIM
              font: musterPanel.mono
            }

            Rectangle {
              anchors.left: stripLabel.right
              anchors.right: parent.right
              anchors.rightMargin: musterPanel.cell
              anchors.verticalCenter: parent.verticalCenter
              height: 1
              color: Muster.FAINT
            }
          }

          // None marked: say how to mark one rather than guess.
          Text {
            x: musterPanel.cell * 2
            width: parent.width - x - musterPanel.cell
            visible: !musterPanel.orch.found
            text: "none marked · press o on the agent in charge, or name its pane orchestrator"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Muster.FAINT
            font: musterPanel.mono
          }

          Rectangle {
            id: orchRow
            readonly property string key: "orch"
            readonly property bool selected: musterPanel.selectedKey === key

            visible: musterPanel.orch.found === true
            width: parent.width
            implicitHeight: orchLines.implicitHeight
            color: musterPanel.isActive(key, orchMouse.containsMouse) ? Muster.SEL_BG : "transparent"

            // The whole strip is one target: a click anywhere on it jumps to
            // the orchestrator. Under the lines, so the more link takes its
            // own clicks.
            MouseArea {
              id: orchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                musterPanel.selectedKey = orchRow.key
                musterPanel.jumpTo(musterPanel.orch.paneId)
              }
            }

            Column {
              id: orchLines
              x: musterPanel.cell
              width: parent.width - x - musterPanel.cell

              // Who, named by the repo it works in, its status, and M.
              RowLayout {
                width: parent.width
                spacing: 0

                Text {
                  text: "⌂ "
                  textFormat: Text.PlainText
                  color: Muster.YELLOW
                  font: musterPanel.monoBold
                }
                Text {
                  text: musterPanel.orch.found
                    ? (musterPanel.orch.sigil !== "" ? musterPanel.orch.sigil + " " : "") + musterPanel.orch.who : ""
                  textFormat: Text.PlainText
                  color: musterPanel.orch.color || Muster.FG
                  font: musterPanel.monoBold
                }
                Text {
                  text: musterPanel.orch.found
                    ? " " + Muster.statusIcon(musterPanel.orch.status, musterPanel.frame) + " " + musterPanel.orch.status : ""
                  textFormat: Text.PlainText
                  color: Muster.statusColor(musterPanel.orch.status, musterPanel.frame)
                  font: musterPanel.mono
                }
                Text {
                  Layout.fillWidth: true
                  text: " " + (musterPanel.orch.age || "")
                  textFormat: Text.PlainText
                  color: Muster.DIM
                  font: musterPanel.mono
                }
                Text {
                  text: "M jumps"
                  textFormat: Text.PlainText
                  color: Muster.FAINT
                  font: musterPanel.mono
                }
              }

              // What it last said, and how long ago. One line, with e more
              // when that cuts it; e shows it whole.
              RowLayout {
                width: parent.width
                spacing: 0

                Text {
                  Layout.alignment: Qt.AlignTop
                  text: "  ↓ "
                  textFormat: Text.PlainText
                  color: musterPanel.orch.said ? Muster.DIM : Muster.FAINT
                  font: musterPanel.mono
                }
                Text {
                  id: saidText
                  Layout.fillWidth: true
                  text: musterPanel.orch.said
                    ? (musterPanel.sayMore ? musterPanel.orch.said : musterPanel.orch.said.replace(/\s+/g, " "))
                    : "nothing said yet"
                  textFormat: Text.PlainText
                  wrapMode: musterPanel.sayMore ? Text.Wrap : Text.NoWrap
                  elide: musterPanel.sayMore ? Text.ElideNone : Text.ElideRight
                  color: musterPanel.orch.said ? Muster.FG : Muster.FAINT
                  font: musterPanel.mono
                }
                Text {
                  Layout.alignment: Qt.AlignTop
                  visible: saidText.truncated && !musterPanel.sayMore
                  text: " e more"
                  textFormat: Text.PlainText
                  color: Muster.FAINT
                  font: musterPanel.mono

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musterPanel.sayMore = true
                  }
                }
                Text {
                  Layout.alignment: Qt.AlignTop
                  visible: text !== ""
                  text: musterPanel.orch.saidAge ? " " + musterPanel.orch.saidAge : ""
                  textFormat: Text.PlainText
                  color: Muster.DIM
                  font: musterPanel.mono
                }
              }

              Text {
                x: musterPanel.cell * 4
                visible: musterPanel.sayMore
                text: "e less"
                textFormat: Text.PlainText
                color: Muster.FAINT
                font: musterPanel.mono

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: musterPanel.sayMore = false
                }
              }
            }
          }

          // The strip's last line: the input while it is open, then whatever
          // just happened, then the keys.
          RowLayout {
            x: musterPanel.cell
            width: parent.width - x - musterPanel.cell
            visible: musterPanel.composing
            spacing: 0

            Text {
              text: "› "
              textFormat: Text.PlainText
              color: Muster.YELLOW
              font: musterPanel.monoBold
            }

            // i: a message for the orchestrator. Enter sends it, esc drops it.
            TextField {
              id: composeField
              Layout.fillWidth: true
              padding: 0
              background: null
              color: Muster.FG
              selectionColor: Muster.SEL_BG
              placeholderText: "message the orchestrator"
              placeholderTextColor: Muster.FAINT
              font: musterPanel.mono
              onAccepted: musterPanel.sendCompose()
              Keys.onEscapePressed: function(event) {
                event.accepted = true
                musterPanel.endCompose()
              }
            }

            Text {
              text: "  enter sends · esc cancels"
              textFormat: Text.PlainText
              color: Muster.FAINT
              font: musterPanel.mono
            }
          }

          Text {
            x: musterPanel.cell
            width: parent.width - x - musterPanel.cell
            visible: !musterPanel.composing && musterPanel.notice !== ""
            text: "· " + musterPanel.notice
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Muster.ORANGE
            font: musterPanel.mono
          }

          Text {
            width: parent.width - musterPanel.cell
            visible: !musterPanel.composing && musterPanel.notice === "" && musterPanel.orch.found === true
            text: Muster.stripHint(musterPanel.muster ? musterPanel.muster.snapshot : null, musterPanel.selectedPane)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Muster.FAINT
            font: musterPanel.mono
          }
        }
      }
    }
  }
}
