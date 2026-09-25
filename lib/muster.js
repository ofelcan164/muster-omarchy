.pragma library

// Everything the widget and panel know about Muster's files, as plain
// functions. No QML types here, so the tests can load this file in Node and
// drive it with snapshots shaped like the ones musterd writes.
//
// Muster's Go sources are the reference for every rule below, and each
// function names the one it mirrors. When the two disagree, Muster is right.

// The snapshot_version values this widget can read. A snapshot from before
// Muster wrote the field has none, and reads as 0: its shape is version 1's,
// less the field. (model.Snapshot)
var SNAPSHOT_VERSION = 1

// A snapshot this old means musterd is not running: it rewrites every five
// seconds. (model.StaleAfter)
var STALE_AFTER_MS = 30 * 1000

// The overlay draws at most this many ribbon rows. (triage.RibbonMax)
var RIBBON_MAX = 4

// Repo colours, by the snapshot's color_index. (identity.Palette)
var PALETTE = [
  "#fb4934", "#ff6b6b", "#fe8019", "#fab387", "#fabd2f",
  "#f9e2af", "#b8bb26", "#a6e3a1", "#8ec07c", "#94e2d5",
  "#89dceb", "#74c7ec", "#89b4fa", "#b4befe", "#cba6f7",
  "#d3869b", "#f5c2e7", "#ff79c6", "#83a598", "#d5c4a1"
]

// A workspace with no repository. (identity.NeutralColor, NeutralSigil)
var NEUTRAL_COLOR = "#928374"
var NEUTRAL_SIGIL = "○"

// The overlay's own accents, so a row reads the same in both places.
// (ui/theme.go)
var RED = "#fb4934"
var ORANGE = "#fe8019"
var YELLOW = "#fabd2f"
var GREEN = "#b8bb26"
var DIM = "#928374"
var FAINT = "#665c54"

// ------------------------------------------------------------------ reading

// parseSnapshot reads snapshot.json's text. It returns { ok, snapshot, error };
// a snapshot that parses but is not the shape musterd writes is an error, not
// an empty screen.
function parseSnapshot(text) {
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return { ok: false, snapshot: null, error: "snapshot.json is not JSON" }
  }
  if (!isObject(raw)) return { ok: false, snapshot: null, error: "snapshot.json is not an object" }

  var version = raw.snapshot_version === undefined ? 0 : raw.snapshot_version
  if (typeof version !== "number" || version !== Math.floor(version) || version < 0)
    return { ok: false, snapshot: null, error: "snapshot_version is not a number" }

  var orch = isObject(raw.orchestrator) ? raw.orchestrator : {}
  return {
    ok: true,
    error: "",
    snapshot: {
      version: version,
      generatedAtMs: parseTime(raw.generated_at),
      daemonPid: Number(raw.daemon_pid) || 0,
      repos: arrayOf(raw.repos),
      workspaces: arrayOf(raw.workspaces),
      attention: arrayOf(raw.attention),
      orchestrator: {
        found: orch.found === true,
        paneId: String(orch.pane_id || ""),
        name: String(orch.name || ""),
        status: String(orch.status || ""),
        lastSaid: String(orch.last_said || ""),
        saidAtMs: parseTime(orch.said_at),
        statusSinceMs: parseTime(orch.status_since)
      },
      counts: isObject(raw.counts) ? raw.counts : {}
    }
  }
}

// parseUi reads ui.json's text. A missing or broken file is the overlay's
// defaults, never an error: that is how Muster reads it too. (state.LoadUI)
function parseUi(text) {
  var out = { dismissed: {}, colors: {} }
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return out
  }
  if (!isObject(raw)) return out
  if (isObject(raw.dismissed)) {
    for (var pane in raw.dismissed)
      if (typeof raw.dismissed[pane] === "string") out.dismissed[pane] = raw.dismissed[pane]
  }
  if (isObject(raw.colors)) {
    for (var key in raw.colors)
      if (typeof raw.colors[key] === "number") out.colors[key] = raw.colors[key]
  }
  return out
}

// parseTime reads a Go time.Time as JSON writes it: RFC 3339 with up to nine
// fractional digits and a zone. Date.parse is not trusted with that many
// digits in every engine, so the fields are taken apart by hand. Go's zero
// time (year 1) is "never" and comes back as NaN, like anything unreadable.
function parseTime(value) {
  var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$/.exec(String(value || ""))
  if (!m) return NaN
  var year = Number(m[1])
  if (year <= 1) return NaN
  var ms = m[7] ? Number((m[7] + "00").slice(0, 3)) : 0
  var t = Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), ms)
  if (m[8] !== "Z") {
    var sign = m[8][0] === "-" ? -1 : 1
    var offset = Number(m[8].slice(1, 3)) * 60 + Number(m[8].slice(4, 6))
    t -= sign * offset * 60 * 1000
  }
  return t
}

// ---------------------------------------------------------------- the state

// isNewer says the snapshot was written by a Muster that has moved past what
// this widget reads. The fix is updating the widget, not Muster.
function isNewer(snap) {
  return !!snap && snap.version > SNAPSHOT_VERSION
}

// isStale says nobody is keeping the snapshot current. An unreadable
// timestamp counts: a count nobody vouches for is worse than none.
// (ui.Badge: time.Since(GeneratedAt) >= StaleAfter)
function isStale(snap, nowMs) {
  if (!snap || isNaN(snap.generatedAtMs)) return true
  return nowMs - snap.generatedAtMs >= STALE_AFTER_MS
}

// undismissed is the attention rows less any dismissed at their current
// status: a status change is what makes a row news again. (ui.undismissed)
function undismissed(attention, dismissed) {
  var out = []
  var d = dismissed || {}
  for (var i = 0; i < (attention || []).length; i++) {
    var a = attention[i]
    if (!a) continue
    if (d[a.pane_id] === a.status) continue
    out.push(a)
  }
  return out
}

// ribbon is what the overlay's ribbon draws: undismissed, then capped, so
// dismissing a row promotes the next one. (ui.ribbonRows)
function ribbon(snap, ui) {
  if (!snap) return []
  return undismissed(snap.attention, ui ? ui.dismissed : null).slice(0, RIBBON_MAX)
}

// needsYou is every undismissed row, not just the ones that fit: the count
// the overlay's header and herdr's tab bar badge both show.
function needsYou(snap, ui) {
  if (!snap) return 0
  return undismissed(snap.attention, ui ? ui.dismissed : null).length
}

// ------------------------------------------------------------------ words

// reasonLabel says why a row is there, not what state the agent is in.
// (ui.reasonLabel)
function reasonLabel(reason, status) {
  switch (reason) {
  case "landed": return "LANDED"
  case "process_stopped": return "STOPPED"
  case "idle_never_done": return "STALE"
  case "blocked": return "BLOCKED"
  case "done_unseen": return "DONE"
  }
  return String(status || "").toUpperCase()
}

// reasonColor is the accent a ribbon row is keyed to. (ui.reasonAccent)
function reasonColor(reason) {
  switch (reason) {
  case "blocked": return RED
  case "landed": return ORANGE
  case "process_stopped": return YELLOW
  case "done_unseen": return GREEN
  }
  return DIM
}

// statusColor colours an agent by what it needs from you. (ui.statusStyle)
function statusColor(status) {
  switch (status) {
  case "blocked": return RED
  case "done": return GREEN
  case "working": return YELLOW
  case "idle": return DIM
  }
  return FAINT
}

// statusIcon is the overlay's resting frame for each status. (ui.statusIcon)
function statusIcon(status) {
  switch (status) {
  case "blocked": return "▲"
  case "done": return "●"
  case "working": return "◐"
  case "idle": return "○"
  }
  return "◌"
}

// ageText is a duration in the overlay's one-unit form: 42s, 7m, 3h, 2d. An
// age the daemon never measured is "-". (ui.ageText)
function ageText(ms, known) {
  if (known === false || isNaN(ms)) return "-"
  var s = Math.max(0, Math.floor(ms / 1000))
  if (s < 60) return s + "s"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  return Math.floor(s / 86400) + "d"
}

// ------------------------------------------------------------------- repos

function repoByKey(snap, key) {
  var repos = snap ? snap.repos : []
  for (var i = 0; i < repos.length; i++)
    if (repos[i] && repos[i].key === key) return repos[i]
  return null
}

// repoColor is a colour picked with c in the overlay when there is one, else
// the hashed one. A scratch workspace stays neutral. (ui.applyColors,
// ui.repoStyle)
function repoColor(repo, colors) {
  if (!repo) return NEUTRAL_COLOR
  var picked = colors ? colors[repo.key] : undefined
  if (repo.is_git && typeof picked === "number" && picked >= 0 && picked < PALETTE.length)
    return PALETTE[picked]
  var i = Number(repo.color_index)
  if (!(i >= 0 && i < PALETTE.length)) return NEUTRAL_COLOR
  return PALETTE[i]
}

function repoSigil(repo) {
  return repo && repo.sigil ? String(repo.sigil) : NEUTRAL_SIGIL
}

// repoName is what the overlay draws: display, widened only on a clash.
// (ui.shortRepo)
function repoName(repo) {
  if (!repo) return ""
  return String(repo.display || repo.name || repo.key || "")
}

// paneHome finds the repo and workspace a pane lives in, agent or not.
function paneHome(snap, paneId) {
  var repos = snap ? snap.repos : []
  for (var i = 0; i < repos.length; i++) {
    var r = repos[i] || {}
    var lists = [r.agents || [], r.other_panes || []]
    for (var l = 0; l < lists.length; l++) {
      for (var j = 0; j < lists[l].length; j++) {
        var p = lists[l][j]
        if (p && p.pane_id === paneId)
          return { repo: r, pane: p, workspace: workspaceById(snap, p.workspace_id) }
      }
    }
  }
  return { repo: null, pane: null, workspace: null }
}

function workspaceById(snap, id) {
  var list = snap ? snap.workspaces : []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].id === id) return list[i]
  return null
}

// ------------------------------------------------------------------- views

// barView is everything the bar button draws, from the snapshot file's state.
// fileState is "missing", "unreadable" or "loaded".
//
// The widget is hidden only when there is no snapshot at all: Muster is not
// installed, or herdr has never run it. Once there is one it stays, so the
// panel is a click away even when nothing needs you.
function barView(fileState, snap, ui, nowMs) {
  if (fileState === "missing" || (fileState !== "loaded" && fileState !== "unreadable"))
    return { visible: false, cls: "missing", text: "", color: "", dimmed: true, tooltip: "" }
  if (fileState === "unreadable" || !snap)
    return { visible: true, cls: "error", text: "◆ !", color: RED, dimmed: false,
             tooltip: "Muster: snapshot.json could not be read" }
  if (isNewer(snap))
    return { visible: true, cls: "update", text: "◆ !", color: ORANGE, dimmed: false,
             tooltip: updateText(snap) }
  if (isStale(snap, nowMs))
    return { visible: true, cls: "stale", text: "◇", color: "", dimmed: true,
             tooltip: staleText(snap, nowMs) }

  var rows = undismissed(snap.attention, ui ? ui.dismissed : null)
  var working = Number(snap.counts.working) || 0
  if (rows.length === 0) {
    return { visible: true, cls: working > 0 ? "working" : "idle", text: "◆", color: "", dimmed: true,
             tooltip: working > 0 ? "Muster · " + working + " working" : "Muster · nothing needs you" }
  }

  var landed = false
  for (var i = 0; i < rows.length; i++) if (rows[i].reason === "landed") landed = true

  var lines = []
  for (var k = 0; k < Math.min(rows.length, RIBBON_MAX); k++) lines.push(tooltipLine(snap, rows[k]))
  if (rows.length > RIBBON_MAX) lines.push("and " + (rows.length - RIBBON_MAX) + " more")

  return {
    visible: true,
    cls: landed ? "landed" : "needs-you",
    text: "◆ " + rows.length,
    color: reasonColor(rows[0].reason),
    dimmed: false,
    tooltip: lines.join("\n")
  }
}

// tooltipLine is one ribbon row as M0's badge --json formats it:
// REASON repo/agent · detail.
function tooltipLine(snap, a) {
  var repo = repoByKey(snap, a.repo_key)
  var who = (repo ? repoName(repo) : String(a.repo_key || "")) + "/" + String(a.agent || "")
  var line = reasonLabel(a.reason, a.status) + " " + who
  if (a.detail) line += " · " + oneLine(a.detail)
  return line
}

function updateText(snap) {
  return "Muster writes snapshot v" + snap.version + " and this widget reads up to v" +
    SNAPSHOT_VERSION + ". Update it: omarchy plugin update io.github.ofelcan164.muster"
}

function staleText(snap, nowMs) {
  if (!snap || isNaN(snap.generatedAtMs)) return "Muster's snapshot has no time on it. Is musterd running?"
  return "Muster's snapshot is " + ageText(nowMs - snap.generatedAtMs, true) +
    " old: musterd is not running. It starts with herdr."
}

// ribbonView is the ribbon rows the panel draws, each with everything its
// delegate needs, in snapshot order. (ui.ribbonLines)
function ribbonView(snap, ui) {
  var rows = ribbon(snap, ui)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var a = rows[i]
    var home = paneHome(snap, a.pane_id)
    var repo = repoByKey(snap, a.repo_key) || home.repo
    var ws = home.workspace
    out.push({
      paneId: String(a.pane_id || ""),
      index: i + 1,
      reason: String(a.reason || ""),
      label: reasonLabel(a.reason, a.status),
      accent: reasonColor(a.reason),
      hot: Number(a.rank) <= 2,
      workspace: ws && ws.label ? ws.number + " " + ws.label : "",
      sigil: repoSigil(repo),
      repo: repo ? repoName(repo) : String(a.repo_key || ""),
      repoColor: repoColor(repo, ui ? ui.colors : null),
      agent: String(a.agent || ""),
      age: ageText(Number(a.age_ns) / 1e6, a.age_known !== false),
      detail: oneLine(a.detail),
      dependents: arrayOf(a.dependents)
    })
  }
  return out
}

// orchestratorView is the strip: who, what state and for how long, and what
// it last said. (ui.stripLines, ui.orchWho, ui.saidLines)
function orchestratorView(snap, ui, nowMs) {
  var o = snap ? snap.orchestrator : null
  if (!o || !o.found) return { found: false }
  var home = paneHome(snap, o.paneId)
  var who, color, sigil
  if (home.repo && home.pane) {
    who = repoName(home.repo).toUpperCase()
    sigil = repoSigil(home.repo)
    color = repoColor(home.repo, ui ? ui.colors : null)
  } else {
    who = (o.name || "orchestrator").toUpperCase()
    sigil = ""
    color = ""
  }
  var said = String(o.lastSaid || "").trim()
  return {
    found: true,
    paneId: o.paneId,
    who: who,
    sigil: sigil,
    color: color,
    status: o.status || "unknown",
    statusIcon: statusIcon(o.status),
    statusColor: statusColor(o.status),
    age: ageText(nowMs - o.statusSinceMs, !isNaN(o.statusSinceMs)),
    said: said,
    saidAge: said !== "" && !isNaN(o.saidAtMs) ? ageText(nowMs - o.saidAtMs, true) : ""
  }
}

// STATUS_ORDER is the order counts are listed in: what needs you first.
var STATUS_ORDER = ["blocked", "done", "working", "idle", "unknown"]

// reposView is one row per repo with its agents counted by status, in
// snapshot order.
function reposView(snap, ui) {
  var repos = snap ? snap.repos : []
  var out = []
  for (var i = 0; i < repos.length; i++) {
    var r = repos[i]
    if (!r) continue
    var tally = {}
    var agents = arrayOf(r.agents)
    for (var j = 0; j < agents.length; j++) {
      var s = agents[j] ? String(agents[j].status || "unknown") : "unknown"
      if (STATUS_ORDER.indexOf(s) === -1) s = "unknown"
      tally[s] = (tally[s] || 0) + 1
    }
    var counts = []
    for (var k = 0; k < STATUS_ORDER.length; k++) {
      var st = STATUS_ORDER[k]
      if (tally[st]) counts.push({ status: st, count: tally[st], icon: statusIcon(st), color: statusColor(st) })
    }
    out.push({
      key: String(r.key || ""),
      sigil: repoSigil(r),
      name: repoName(r),
      color: repoColor(r, ui ? ui.colors : null),
      branch: String(r.branch || ""),
      agents: agents.length,
      counts: counts
    })
  }
  return out
}

// headerMeta is the panel's one-line summary under its title.
function headerMeta(fileState, snap, ui, nowMs) {
  if (fileState === "missing") return "no snapshot yet"
  if (fileState !== "loaded" || !snap) return "snapshot unreadable"
  if (isNewer(snap)) return "update this widget"
  if (isStale(snap, nowMs)) return "stale · " + ageText(nowMs - snap.generatedAtMs, !isNaN(snap.generatedAtMs)) + " old"
  var parts = []
  var n = needsYou(snap, ui)
  if (n > 0) parts.push(n + " need" + (n === 1 ? "s" : "") + " you")
  var agents = Number(snap.counts.agents) || 0
  parts.push(agents + " agent" + (agents === 1 ? "" : "s"))
  var repos = snap.repos.length
  parts.push(repos + " repo" + (repos === 1 ? "" : "s"))
  return parts.join(" · ")
}

// ----------------------------------------------------------------- helpers

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function arrayOf(v) {
  return Array.isArray(v) ? v : []
}

// oneLine folds a pane's text onto one line: details and questions are read
// off a terminal and can carry its line breaks.
function oneLine(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}
