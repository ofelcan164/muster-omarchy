// Unit tests for lib/muster.js. Run with `node --test tests/`.
//
// fixtures/snapshot.json is marshalled from Muster's own model.Snapshot (see
// fixtures/README.md), so these tests read the exact shape musterd writes.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const load = require("./load")

const M = load()
const FIXTURE = fs.readFileSync(path.join(__dirname, "fixtures", "snapshot.json"), "utf8")

// The fixture's generated_at, 2026-09-25T12:00:00.123+02:00.
const GENERATED = Date.UTC(2026, 8, 25, 10, 0, 0, 123)

function snapshot(edit) {
  const raw = JSON.parse(FIXTURE)
  if (edit) edit(raw)
  const parsed = M.parseSnapshot(JSON.stringify(raw))
  assert.equal(parsed.ok, true, parsed.error)
  return parsed.snapshot
}

// JSON round trip, so results from the library's context compare cleanly
// with literals from this one.
function plain(v) {
  return JSON.parse(JSON.stringify(v))
}

// ------------------------------------------------------------------ parsing

test("parseTime reads Go's RFC 3339 with nanoseconds and an offset", () => {
  assert.equal(M.parseTime("2026-09-25T12:00:00.123456789+02:00"), GENERATED)
  assert.equal(M.parseTime("2026-09-25T10:00:00Z"), Date.UTC(2026, 8, 25, 10, 0, 0))
  assert.equal(M.parseTime("2026-09-25T05:30:00.5-04:30"), Date.UTC(2026, 8, 25, 10, 0, 0, 500))
})

test("parseTime treats Go's zero time and garbage as never", () => {
  assert.ok(Number.isNaN(M.parseTime("0001-01-01T00:00:00Z")))
  assert.ok(Number.isNaN(M.parseTime("")))
  assert.ok(Number.isNaN(M.parseTime(undefined)))
  assert.ok(Number.isNaN(M.parseTime("yesterday")))
})

test("parseSnapshot reads the fixture", () => {
  const s = snapshot()
  assert.equal(s.version, 1, "Muster 0.3.0 writes snapshot_version 1")
  assert.equal(s.generatedAtMs, GENERATED)
  assert.equal(s.repos.length, 3)
  assert.equal(s.attention.length, 5)
  assert.equal(s.orchestrator.found, true)
  assert.equal(s.orchestrator.paneId, "w1:p1")
})

test("a snapshot from before Muster 0.3.0, with no snapshot_version, reads as 0", () => {
  const s = snapshot((r) => { delete r.snapshot_version })
  assert.equal(s.version, 0)
  assert.equal(M.isNewer(s), false, "and is drawn, not refused")
})

test("parseSnapshot refuses what musterd never writes", () => {
  assert.equal(M.parseSnapshot("{").ok, false)
  assert.equal(M.parseSnapshot("[]").ok, false)
  assert.equal(M.parseSnapshot("null").ok, false)
  assert.equal(M.parseSnapshot('{"snapshot_version":"1"}').ok, false)
  assert.equal(M.parseSnapshot('{"snapshot_version":1.5}').ok, false)
})

test("parseSnapshot fills in missing lists rather than failing on them", () => {
  const parsed = M.parseSnapshot('{"generated_at":"2026-09-25T10:00:00Z"}')
  assert.equal(parsed.ok, true)
  assert.equal(parsed.snapshot.repos.length, 0)
  assert.equal(parsed.snapshot.attention.length, 0)
  assert.equal(parsed.snapshot.orchestrator.found, false)
})

test("parseUi keeps only well-formed dismissals and colours", () => {
  const ui = M.parseUi(JSON.stringify({
    sort: 2,
    dismissed: { "w1:p2": "blocked", "bad": 3 },
    colors: { "acme/api": 7, "bad": "red" },
    say_rows: 3
  }))
  assert.deepEqual(plain(ui), { dismissed: { "w1:p2": "blocked" }, colors: { "acme/api": 7 }, sort: 2 })
  assert.equal(M.parseUi(JSON.stringify({ sort: 4 })).sort, 0, "a sort past herdr's is first seen")
  assert.equal(M.parseUi(JSON.stringify({ sort: 1.5 })).sort, 0)
})

test("parseUi treats a missing or broken file as the defaults", () => {
  for (const text of ["", "{", "[]", "null"]) {
    assert.deepEqual(plain(M.parseUi(text)), { dismissed: {}, colors: {}, sort: 0 })
  }
})

// ----------------------------------------------------------------- versions

test("version 0 and 1 are read, anything newer asks for an update", () => {
  assert.equal(M.isNewer(snapshot()), false)
  assert.equal(M.isNewer(snapshot((r) => { r.snapshot_version = 1 })), false)
  const newer = snapshot((r) => { r.snapshot_version = 2 })
  assert.equal(M.isNewer(newer), true)
  const bar = M.barView("loaded", newer, M.parseUi(""), GENERATED)
  assert.equal(bar.cls, "update")
  assert.match(bar.tooltip, /omarchy plugin update io\.github\.ofelcan164\.muster/)
})

// ------------------------------------------------------------------ staleness

test("a snapshot goes stale at 30 seconds, as Muster's badge says", () => {
  const s = snapshot()
  assert.equal(M.isStale(s, GENERATED + 29999), false)
  assert.equal(M.isStale(s, GENERATED + 30000), true)
})

test("a snapshot with no readable time is stale", () => {
  const s = snapshot((r) => { r.generated_at = "0001-01-01T00:00:00Z" })
  assert.equal(M.isStale(s, GENERATED), true)
})

test("a stale snapshot shows the stale glyph and never a count", () => {
  const bar = M.barView("loaded", snapshot(), M.parseUi(""), GENERATED + 3 * 60 * 1000)
  assert.equal(bar.cls, "stale")
  assert.equal(bar.text, "◇")
  assert.doesNotMatch(bar.text, /\d/)
  assert.match(bar.tooltip, /3m old/)
})

// ----------------------------------------------------------------- dismissals

test("a row dismissed at its current status leaves the ribbon", () => {
  const s = snapshot()
  const ui = M.parseUi(JSON.stringify({ dismissed: { "w1:p2": "blocked" } }))
  const panes = plain(M.ribbon(s, ui).map((a) => a.pane_id))
  assert.deepEqual(panes, ["w2:p1", "w1:p9", "w2:p2", "w1:p1"])
  assert.equal(M.needsYou(s, ui), 4)
})

test("a row dismissed at another status is news again", () => {
  const s = snapshot()
  const ui = M.parseUi(JSON.stringify({ dismissed: { "w1:p2": "working" } }))
  assert.equal(M.ribbon(s, ui)[0].pane_id, "w1:p2")
  assert.equal(M.needsYou(s, ui), 5)
})

test("the ribbon is capped at four after dismissals, the count is not", () => {
  const s = snapshot()
  assert.equal(M.ribbon(s, M.parseUi("")).length, 4)
  assert.equal(M.needsYou(s, M.parseUi("")), 5)
})

// ----------------------------------------------------------------- bar classes

function barFor(edit, uiJson) {
  return M.barView("loaded", snapshot(edit), M.parseUi(uiJson || ""), GENERATED)
}

test("bar: no snapshot file hides the widget", () => {
  const bar = M.barView("missing", null, M.parseUi(""), GENERATED)
  assert.equal(bar.visible, false)
})

test("bar: an unreadable snapshot says so", () => {
  const bar = M.barView("unreadable", null, M.parseUi(""), GENERATED)
  assert.equal(bar.visible, true)
  assert.equal(bar.cls, "error")
})

test("bar: landed wins over needs-you, coloured by the top row", () => {
  const bar = barFor()
  assert.equal(bar.cls, "landed")
  assert.equal(bar.text, "◆ 5")
  assert.equal(bar.color, M.RED, "the top row is blocked")
  assert.equal(bar.dimmed, false)
})

test("bar: needs-you when nothing landed", () => {
  const bar = barFor((r) => { r.attention = r.attention.filter((a) => a.reason !== "landed") })
  assert.equal(bar.cls, "needs-you")
  assert.equal(bar.text, "◆ 4")
})

test("bar: the colour follows the top undismissed row", () => {
  const bar = barFor(null, JSON.stringify({ dismissed: { "w1:p2": "blocked" } }))
  assert.equal(bar.color, M.ORANGE)
  assert.equal(bar.text, "◆ 4")
})

test("bar: working when nothing needs you but something runs", () => {
  const bar = barFor((r) => { r.attention = [] })
  assert.equal(bar.cls, "working")
  assert.equal(bar.text, "◆")
  assert.equal(bar.dimmed, true)
  assert.match(bar.tooltip, /1 working/)
})

test("bar: idle when nothing needs you and nothing runs", () => {
  const bar = barFor((r) => { r.attention = []; r.counts.working = 0 })
  assert.equal(bar.cls, "idle")
  assert.equal(bar.visible, true, "a snapshot keeps the widget in the bar")
})

test("bar: the tooltip is one line per ribbon row, then the overflow", () => {
  const lines = barFor().tooltip.split("\n")
  assert.deepEqual(lines, [
    "BLOCKED api/fixer · Allow rm -rf build/?",
    "LANDED web/login · api#412 landed, nobody moved",
    "STOPPED api/dev server · npm run dev exited",
    "DONE web/styles",
    "and 1 more"
  ])
})

// ------------------------------------------------------------------- panel

test("ribbonView carries what each row draws", () => {
  const rows = plain(M.ribbonView(snapshot(), M.parseUi("")))
  assert.equal(rows.length, 4)
  assert.deepEqual(rows[0], {
    paneId: "w1:p2",
    index: 1,
    reason: "blocked",
    label: "BLOCKED",
    accent: M.RED,
    hot: true,
    workspace: "1 api",
    sigil: "✦",
    repo: "api",
    repoColor: M.PALETTE[12],
    agent: "fixer",
    age: "1m",
    detail: "Allow rm -rf build/?",
    dependents: []
  })
  assert.deepEqual(rows[1].dependents, ["web/login"])
  assert.equal(rows[2].age, "-", "an age the daemon never measured")
  assert.equal(rows[2].workspace, "", "a stopped process leads with no workspace, as in the overlay")
  assert.equal(rows[2].detail, "npm run dev exited")
  assert.equal(rows[3].hot, false)
})

test("a colour picked with c beats the hashed one", () => {
  const ui = M.parseUi(JSON.stringify({ colors: { "acme/api": 0 } }))
  assert.equal(M.ribbonView(snapshot(), ui)[0].repoColor, M.PALETTE[0])
})

test("a picked colour never lands on a scratch workspace, or off the palette", () => {
  const s = snapshot()
  const scratch = M.repoByKey(s, "/tmp/scratch")
  assert.equal(M.repoColor(scratch, { "/tmp/scratch": 3 }), M.NEUTRAL_COLOR)
  const api = M.repoByKey(s, "acme/api")
  assert.equal(M.repoColor(api, { "acme/api": 20 }), M.PALETTE[12])
  assert.equal(M.repoColor(api, { "acme/api": -1 }), M.PALETTE[12])
})

test("orchestratorView names it by its repo and ages it from now", () => {
  const o = plain(M.orchestratorView(snapshot(), M.parseUi(""), GENERATED + 15000))
  assert.deepEqual(o, {
    found: true,
    paneId: "w1:p1",
    who: "API",
    sigil: "✦",
    color: M.PALETTE[12],
    status: "idle",
    statusIcon: "○",
    statusColor: M.DIM,
    age: "3m",
    said: "api#412 is merged.\nTelling web to pick it up next.",
    saidAge: "1m"
  })
})

test("orchestratorView falls back to its name off the repo map", () => {
  const o = M.orchestratorView(snapshot((r) => { r.orchestrator.pane_id = "gone" }), M.parseUi(""), GENERATED)
  assert.equal(o.who, "ORCHESTRATOR")
  assert.equal(o.sigil, "")
})

test("orchestratorView says when none is marked", () => {
  const o = M.orchestratorView(snapshot((r) => { r.orchestrator = { found: false } }), M.parseUi(""), GENERATED)
  assert.deepEqual(plain(o), { found: false })
})

test("orchestratorView leaves the said age off when nothing was said", () => {
  const o = M.orchestratorView(snapshot((r) => { r.orchestrator.last_said = "" }), M.parseUi(""), GENERATED)
  assert.equal(o.said, "")
  assert.equal(o.saidAge, "")
})

test("headerView is the overlay's title line", () => {
  const ui = M.parseUi(JSON.stringify({ dismissed: { "w1:p2": "blocked" } }))
  assert.deepEqual(plain(M.headerView(snapshot(), ui)), { counts: "3 workspaces · 5 agents", needsYou: 4 })
  const one = snapshot((r) => { r.counts.workspaces = 1; r.counts.agents = 1 })
  assert.equal(M.headerView(one, M.parseUi("")).counts, "1 workspace · 1 agent")
})

test("the NEEDS YOU rule takes the top undismissed row's colour", () => {
  assert.equal(M.attentionAccent(snapshot(), M.parseUi("")), M.RED)
  const ui = M.parseUi(JSON.stringify({ dismissed: { "w1:p2": "blocked" } }))
  assert.equal(M.attentionAccent(snapshot(), ui), M.ORANGE)
  assert.equal(M.attentionAccent(snapshot((r) => { r.attention = [] }), ui), M.DIM)
})

test("tilesView is the overlay's grid: one tile per agent, one per empty workspace", () => {
  const tiles = plain(M.tilesView(snapshot(), M.parseUi(""), GENERATED + 60000))
  // First seen: by the repo's slot, agents by pane, empty workspaces last.
  assert.deepEqual(tiles.map((t) => t.key),
    ["pane:w1:p1", "pane:w1:p2", "pane:w1:p3", "pane:w2:p1", "pane:w2:p2", "ws:w3"])
  assert.deepEqual(tiles[1], {
    key: "pane:w1:p2", jump: "w1:p2", isAgent: true, paneId: "w1:p2", workspaceId: "w1",
    barColor: M.PALETTE[12],
    num: "▸1", label: "api", chip: "[p2]",
    sigil: "✦", repo: "api", repoColor: M.PALETTE[12], branch: "main",
    orchestrator: false, status: "blocked", name: "fixer", kind: "codex",
    age: tiles[1].age,
    task: "? Allow rm -rf build/?", taskColor: M.FG,
    dependsOn: null,
    neededBy: [{ sigil: "◆", repo: "web", color: M.PALETTE[4] }],
    footer: "3 agents · 1 pane · dev server"
  })
  assert.equal(tiles[0].orchestrator, true, "the orchestrator's tile carries its mark")
  assert.equal(tiles[3].num, " 2", "only the focused workspace is marked")
  assert.equal(tiles[3].task, "wire the login form")
  assert.equal(tiles[3].taskColor, M.DIM)
  assert.deepEqual(tiles[3].dependsOn, { sigil: "✦", repo: "api", color: M.PALETTE[12], when: tiles[3].dependsOn.when })
  assert.match(tiles[3].dependsOn.when, /^landed \d+[smhd] ago$/)
  assert.deepEqual(tiles[5], {
    key: "ws:w3", jump: "ws:w3", isAgent: false, paneId: "", workspaceId: "w3",
    barColor: M.FAINT, num: " 3", label: "scratch",
    sigils: [{ sigil: "○", color: M.NEUTRAL_COLOR }], detail: "scratch"
  })
})

test("tilesView with a / query keeps what every term hits, best first", () => {
  const keys = (q) => plain(M.tilesView(snapshot(), M.parseUi(""), GENERATED, q).map((t) => t.key))
  assert.deepEqual(keys("web"), ["pane:w2:p1", "pane:w2:p2"], "workspace and repo")
  assert.deepEqual(keys("log"), ["pane:w2:p1", "pane:w2:p2"], "the branch")
  assert.deepEqual(keys("api p2"), ["pane:w1:p2"], "every term has to hit, the pane chip included")
  assert.deepEqual(keys("scr"), ["ws:w3"], "an empty workspace by its label")
  assert.deepEqual(keys("zzz"), [])
  assert.deepEqual(keys("   "), keys(""), "blank is no query")
})

test("scoreTerm ranks a prefix over a substring over the letters in order", () => {
  assert.equal(M.scoreTerm("con", "Contracts"), 100)
  assert.equal(M.scoreTerm("tra", "contracts"), 60)
  assert.equal(M.scoreTerm("cnt", "contracts"), 20)
  assert.equal(M.scoreTerm("tnc", "contracts"), 0)
  assert.equal(M.scoreTerm("a", ""), 0)
})

test("tilesView follows the sort ui.json holds", () => {
  const keys = (sort) => M.tilesView(snapshot(), M.parseUi(JSON.stringify({ sort })), GENERATED).map((t) => t.key)
  assert.deepEqual(plain(keys(1)), ["pane:w1:p3", "pane:w1:p2", "pane:w1:p1", "pane:w2:p1", "pane:w2:p2", "ws:w3"], "a-z")
  assert.deepEqual(plain(keys(2)), ["pane:w1:p2", "pane:w2:p1", "pane:w2:p2", "pane:w1:p1", "pane:w1:p3", "ws:w3"], "attention")
  assert.deepEqual(plain(keys(3)), ["pane:w1:p1", "pane:w1:p2", "pane:w1:p3", "pane:w2:p1", "pane:w2:p2", "ws:w3"], "herdr")
})

test("a stale task is marked, and none draws no line", () => {
  const s = snapshot((r) => {
    r.repos[1].agents[0].task_source = "orchestrator_stale"
    r.repos[1].agents[1].task = "x"
    r.repos[1].agents[1].task_source = "none"
  })
  const tiles = M.tilesView(s, M.parseUi(""), GENERATED)
  assert.equal(tiles[3].task, "(stale) wire the login form")
  assert.equal(tiles[3].taskColor, M.FAINT)
  assert.equal(tiles[4].task, "")
})

test("reportTarget and the strip's hint follow the overlay's rule", () => {
  const s = snapshot()
  assert.equal(M.reportTarget(s, "").pane_id, "w2:p1", "the only landed row")
  assert.equal(M.reportTarget(s, "w1:p2").pane_id, "w2:p1", "whatever else is selected")
  assert.equal(M.stripHint(s, ""), " › i tells it something · t tells it api landed")
  const two = snapshot((r) => { r.attention.push(Object.assign({}, r.attention[1], { pane_id: "w2:p2" })) })
  assert.equal(M.reportTarget(two, ""), null, "two landed and none selected picks nothing")
  assert.equal(M.reportTarget(two, "w2:p2").pane_id, "w2:p2")
  assert.equal(M.stripHint(two, ""), " › press i to tell it something")
})

test("working spins and blocked pulses, resting on frame 0", () => {
  assert.equal(M.statusIcon("working"), "◐")
  assert.equal(M.statusIcon("working", 1), "◓")
  assert.equal(M.statusColor("blocked", 0), M.RED)
  assert.equal(M.statusColor("blocked", M.PULSE_FRAMES), M.RED_DIM)
  assert.equal(M.statusColor("blocked", M.PULSE_FRAMES * 2), M.RED)
})

test("ageText matches the overlay's units", () => {
  assert.equal(M.ageText(0, true), "0s")
  assert.equal(M.ageText(59999, true), "59s")
  assert.equal(M.ageText(60000, true), "1m")
  assert.equal(M.ageText(3600000, true), "1h")
  assert.equal(M.ageText(86400000 * 3, true), "3d")
  assert.equal(M.ageText(5000, false), "-")
  assert.equal(M.ageText(NaN, true), "-")
})
