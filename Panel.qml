import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The panel that drops from the diamond: the ribbon of what needs you, the
// orchestrator's strip, and one line per repo. A click or enter lands on the
// row's pane and brings herdr's window forward, and i, t, x and M do what they
// do in Muster's overlay, through the same muster commands.
//
// It draws what Data works out from Muster's files and nothing else, so it
// shows the same ribbon, orchestrator and counts as Muster's overlay.
Panel {
  id: musterPanel // not `root`: inside a Component, `root` would resolve to that
  moduleName: "io.github.ofelcan164.muster"
  ipcTarget: "io.github.ofelcan164.muster"
  manageIpc: true

  // Injected by BarWidget.
  property var anchorItem: null
  property var hostWidget: null
  property var muster: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)
  // Text on a reason badge: the overlay's own background, since the accents
  // are the overlay's too and are bright on any theme.
  readonly property color badgeText: "#1d2021"

  readonly property bool readable: !!muster && muster.readable
  readonly property var ribbon: muster ? muster.ribbon : []
  readonly property var orch: muster ? muster.orchestrator : ({ found: false })
  readonly property var repos: muster ? muster.repos : []
  readonly property int moreRows: muster ? Math.max(0, muster.needsYou - ribbon.length) : 0

  // What j/k walk and enter lands on: the ribbon rows, then the orchestrator.
  // The selection is kept by key, not by position, so a snapshot that arrives
  // while the panel is open does not move it onto another row.
  readonly property var targetKeys: {
    var keys = []
    for (var i = 0; i < ribbon.length; i++) keys.push("ribbon:" + ribbon[i].paneId)
    if (orch.found) keys.push("orch")
    return keys
  }
  property string selectedKey: ""
  readonly property int selectedIndex: targetKeys.indexOf(selectedKey)

  property string notice: ""
  // Whether the notice is a failure, drawn urgent, or what an action did.
  property bool noticeIsError: true
  property bool jumping: false
  // The i input is open, and every key is text until enter or esc.
  property bool composing: false
  readonly property Item composeInput: composeField

  function paneFor(key) {
    if (key === "orch") return orch.found ? orch.paneId : ""
    return key.indexOf("ribbon:") === 0 ? key.slice(7) : ""
  }

  function say(ok, message) {
    noticeIsError = !ok
    notice = message
  }

  // The ribbon row the selection is on, or null.
  function selectedRow() {
    var pane = selectedKey.indexOf("ribbon:") === 0 ? selectedKey.slice(7) : ""
    for (var i = 0; i < ribbon.length; i++)
      if (ribbon[i].paneId === pane) return ribbon[i]
    return null
  }

  // The landed row t reports, the overlay's rule: the selection when it is on
  // one, else the only one there is. With several and none selected it picks
  // nothing, because picking for you would send the wrong report.
  function reportTarget() {
    var landed = []
    for (var i = 0; i < ribbon.length; i++)
      if (ribbon[i].reason === "landed") landed.push(ribbon[i])
    var sel = selectedRow()
    if (sel && sel.reason === "landed") return sel
    return landed.length === 1 ? landed[0] : null
  }

  function textKey(text) {
    if (text === "i") startCompose()
    else if (text === "t") report()
    else if (text === "M") {
      if (orch.found) jumpTo("orchestrator")
      else say(false, "no orchestrator marked, so there is nowhere to go")
    }
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

  function report() {
    var row = reportTarget()
    if (!row) {
      say(false, "nothing to report: no landed row is selected")
      return
    }
    if (!orch.found) {
      say(false, "no orchestrator marked, so there is nobody to tell")
      return
    }
    actions.report(row.paneId, say)
  }

  // x takes the row off the ribbon until its status changes. The row goes
  // when Muster rewrites ui.json and the watch sees it, not before, so the
  // panel never shows a dismissal that did not happen.
  function dismiss() {
    var row = selectedRow()
    if (!row) {
      say(false, "x dismisses a row that needs you: select one first")
      return
    }
    actions.dismiss(row.paneId, function(ok, message) { if (!ok) say(false, message) })
  }

  function move(dy) {
    if (targetKeys.length === 0) return
    var i = selectedIndex
    if (i < 0) i = dy > 0 ? 0 : targetKeys.length - 1
    else i = Math.max(0, Math.min(targetKeys.length - 1, i + dy))
    selectedKey = targetKeys[i]
  }

  // Enter with nothing selected takes the top row: the thing that most needs
  // you is the thing you most likely opened this for.
  function activate() {
    var key = selectedIndex >= 0 ? selectedKey : (targetKeys.length > 0 ? targetKeys[0] : "")
    if (key !== "") jumpTo(paneFor(key))
  }

  function jumpTo(pane) {
    if (pane === "" || jumping) return
    jumping = true
    notice = ""
    actions.jump(pane, function(ok, message) {
      musterPanel.jumping = false
      if (ok) musterPanel.close()
      else musterPanel.say(false, message)
    })
  }

  onOpenedChanged: if (opened) {
    selectedKey = ""
    notice = ""
    composing = false
    if (muster) {
      muster.nowMs = Date.now()
      muster.refresh()
    }
    flick.contentY = 0
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
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: musterPanel.composing

      onMoveRequested: function(dx, dy) { if (dy !== 0) musterPanel.move(dy) }
      onActivateRequested: musterPanel.activate()
      onCloseRequested: musterPanel.close()
      onTabRequested: function(direction) { musterPanel.switchPanel(direction) }
      onDeleteRequested: musterPanel.dismiss()
      onTextKey: function(text) { musterPanel.textKey(text) }

      Flickable {
        id: flick
        anchors.fill: parent
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
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "Muster"
            meta: musterPanel.muster ? musterPanel.muster.headerMeta : ""
            foreground: musterPanel.foreground
            fontFamily: musterPanel.fontFamily
          }

          // Why there is nothing to show, or why what is shown is old.
          Text {
            width: parent.width
            visible: text !== ""
            text: musterPanel.muster ? musterPanel.muster.problem : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: musterPanel.muster && (musterPanel.muster.newer || musterPanel.muster.fileState === "unreadable")
              ? musterPanel.urgent : musterPanel.dim
            font.family: musterPanel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            id: content
            width: parent.width
            spacing: Style.space(10)
            visible: musterPanel.readable
            // A stale snapshot is still worth reading, but not at a glance.
            opacity: musterPanel.muster && musterPanel.muster.stale ? 0.55 : 1

            // ---------------------------------------------- the ribbon
            PanelSectionHeader {
              text: "NEEDS YOU"
              foreground: musterPanel.foreground
              fontFamily: musterPanel.fontFamily
            }

            Text {
              visible: musterPanel.ribbon.length === 0
              text: "Nothing needs you."
              textFormat: Text.PlainText
              color: musterPanel.dim
              font.family: musterPanel.fontFamily
              font.pixelSize: Style.font.body
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: musterPanel.ribbon

                delegate: Rectangle {
                  id: ribbonRow
                  required property var modelData
                  readonly property string key: "ribbon:" + modelData.paneId
                  readonly property bool selected: musterPanel.selectedKey === key

                  width: parent.width
                  implicitHeight: ribbonText.implicitHeight + Style.space(10)
                  radius: Style.cornerRadius
                  // The top two ranks keep a warm tint even unselected, as in
                  // the overlay, so what most needs you reads first.
                  color: selected ? musterPanel.selectedFill
                    : ribbonMouse.containsMouse ? musterPanel.hoverFill
                    : modelData.hot ? Util.alpha(modelData.accent, 0.10) : "transparent"

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(3)
                    width: Style.space(3)
                    radius: width / 2
                    color: ribbonRow.modelData.accent
                  }

                  Column {
                    id: ribbonText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(6)

                      Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: badgeLabel.implicitWidth + Style.space(8)
                        implicitHeight: badgeLabel.implicitHeight + Style.space(2)
                        radius: Style.space(3)
                        color: ribbonRow.modelData.accent

                        Text {
                          id: badgeLabel
                          anchors.centerIn: parent
                          text: ribbonRow.modelData.label
                          textFormat: Text.PlainText
                          color: musterPanel.badgeText
                          font.family: musterPanel.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      // The workspace leads, faint, the way every tile in the
                      // overlay's grid does.
                      Text {
                        visible: text !== ""
                        text: ribbonRow.modelData.workspace
                        textFormat: Text.PlainText
                        color: musterPanel.dim
                        font.family: musterPanel.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        text: ribbonRow.modelData.sigil + " " + ribbonRow.modelData.repo
                        textFormat: Text.PlainText
                        color: ribbonRow.modelData.repoColor
                        font.family: musterPanel.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }

                      Text {
                        Layout.fillWidth: true
                        text: "/" + ribbonRow.modelData.agent
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: musterPanel.foreground
                        font.family: musterPanel.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }

                      Text {
                        text: ribbonRow.modelData.age
                        textFormat: Text.PlainText
                        color: musterPanel.dim
                        font.family: musterPanel.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    // The detail is the sentence you actually read: the
                    // question, or what landed with nobody moving on it.
                    Text {
                      width: parent.width
                      visible: text !== ""
                      text: ribbonRow.modelData.detail
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      color: musterPanel.foreground
                      font.family: musterPanel.fontFamily
                      font.pixelSize: Style.font.bodySmall
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
            }

            Text {
              visible: musterPanel.moreRows > 0
              text: "and " + musterPanel.moreRows + " more in Muster"
              textFormat: Text.PlainText
              color: musterPanel.dim
              font.family: musterPanel.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            PanelSeparator { foreground: musterPanel.foreground }

            // ------------------------------------------ the orchestrator
            PanelSectionHeader {
              text: "ORCHESTRATOR"
              foreground: musterPanel.foreground
              fontFamily: musterPanel.fontFamily
            }

            Text {
              width: parent.width
              visible: !musterPanel.orch.found
              text: "None marked. Press o on the agent in charge in Muster, or name its pane orchestrator."
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: musterPanel.dim
              font.family: musterPanel.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              id: orchRow
              readonly property bool selected: musterPanel.selectedKey === "orch"

              visible: musterPanel.orch.found
              width: parent.width
              implicitHeight: orchText.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: selected ? musterPanel.selectedFill
                : orchMouse.containsMouse ? musterPanel.hoverFill : "transparent"

              Column {
                id: orchText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    text: "⌂"
                    textFormat: Text.PlainText
                    color: "#fabd2f"
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: musterPanel.orch.found
                      ? (musterPanel.orch.sigil !== "" ? musterPanel.orch.sigil + " " : "") + musterPanel.orch.who : ""
                    textFormat: Text.PlainText
                    color: musterPanel.orch.color || musterPanel.foreground
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: musterPanel.orch.found ? musterPanel.orch.statusIcon + " " + musterPanel.orch.status : ""
                    textFormat: Text.PlainText
                    color: musterPanel.orch.statusColor || musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    Layout.fillWidth: true
                    text: musterPanel.orch.age || ""
                    textFormat: Text.PlainText
                    color: musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                // What it last said back, and how long ago the daemon read it.
                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    Layout.alignment: Qt.AlignTop
                    text: "↓"
                    textFormat: Text.PlainText
                    color: musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    Layout.fillWidth: true
                    text: musterPanel.orch.said ? musterPanel.orch.said : "nothing said yet"
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: musterPanel.orch.said ? musterPanel.foreground : musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    Layout.alignment: Qt.AlignTop
                    visible: text !== ""
                    text: musterPanel.orch.saidAge || ""
                    textFormat: Text.PlainText
                    color: musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              MouseArea {
                id: orchMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  musterPanel.selectedKey = "orch"
                  musterPanel.jumpTo(musterPanel.orch.paneId)
                }
              }
            }

            PanelSeparator { foreground: musterPanel.foreground }

            // ------------------------------------------------ the repos
            PanelSectionHeader {
              text: "REPOS"
              foreground: musterPanel.foreground
              fontFamily: musterPanel.fontFamily
            }

            Text {
              visible: musterPanel.repos.length === 0
              text: "No workspaces discovered yet."
              textFormat: Text.PlainText
              color: musterPanel.dim
              font.family: musterPanel.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: musterPanel.repos

                delegate: RowLayout {
                  id: repoRow
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    text: repoRow.modelData.sigil + " " + repoRow.modelData.name
                    textFormat: Text.PlainText
                    color: repoRow.modelData.color
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    Layout.fillWidth: true
                    text: repoRow.modelData.branch
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    visible: repoRow.modelData.counts.length === 0
                    text: "no agents"
                    textFormat: Text.PlainText
                    color: musterPanel.dim
                    font.family: musterPanel.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Repeater {
                    model: repoRow.modelData.counts

                    delegate: Text {
                      required property var modelData
                      text: modelData.icon + " " + modelData.count
                      textFormat: Text.PlainText
                      color: modelData.color
                      font.family: musterPanel.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }

          // i: a message for the orchestrator. Enter sends it, esc drops it.
          TextField {
            id: composeField
            width: parent.width
            visible: musterPanel.composing
            placeholderText: "message the orchestrator"
            color: musterPanel.foreground
            font.family: musterPanel.fontFamily
            font.pixelSize: Style.font.body
            onAccepted: musterPanel.sendCompose()
            Keys.onEscapePressed: function(event) {
              event.accepted = true
              musterPanel.endCompose()
            }
          }

          // The overlay's notice line: why a command failed, or what it did.
          Text {
            width: parent.width
            visible: text !== ""
            text: musterPanel.notice
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: musterPanel.noticeIsError ? musterPanel.urgent : musterPanel.dim
            font.family: musterPanel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: musterPanel.targetKeys.length > 0
            text: musterPanel.composing ? "enter sends · esc cancels"
              : "j/k move · enter jumps · i tell · t report · x dismiss · M orchestrator · esc closes"
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: Qt.darker(musterPanel.foreground, 2)
            font.family: musterPanel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
