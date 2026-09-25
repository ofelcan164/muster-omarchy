// Tests for bin/muster-omarchy, run against fake muster, hyprctl, ps and
// omarchy-launch-terminal-herdr binaries that record how they were called.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")

const SCRIPT = path.join(__dirname, "..", "bin", "muster-omarchy")

// A fake prints nothing but its own name and arguments, one call per line,
// into the log, plus whatever the test asks of it through the environment.
const FAKES = {
  muster: `echo "muster $*" >> "$LOG"
if [ -n "$MUSTER_FAIL" ]; then echo "warming up" >&2; echo "$MUSTER_FAIL" >&2; exit 1; fi
if [ -n "$MUSTER_OUT" ]; then echo "$MUSTER_OUT"; fi`,
  hyprctl: `echo "hyprctl $*" >> "$LOG"
if [ "$1" = clients ]; then cat "$CLIENTS"; fi`,
  ps: `cat "$PS_OUT"`,
  "omarchy-launch-terminal-herdr": `echo "launch" >> "$LOG"`
}

function sandbox(options = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "muster-omarchy-"))
  const bin = path.join(dir, "bin")
  fs.mkdirSync(bin)
  const omit = options.omit || []
  for (const [name, body] of Object.entries(FAKES)) {
    if (omit.includes(name)) continue
    fs.writeFileSync(path.join(bin, name), "#!/bin/sh\n" + body + "\n", { mode: 0o755 })
  }
  fs.writeFileSync(path.join(dir, "clients.json"), JSON.stringify(options.clients || []))
  fs.writeFileSync(path.join(dir, "ps.txt"), (options.ps || []).join("\n") + "\n")
  const log = path.join(dir, "log")
  fs.writeFileSync(log, "")

  // The real tools the script leans on, and nothing else from this machine,
  // so a muster installed here cannot stand in for a fake one.
  const tools = path.join(dir, "tools")
  fs.mkdirSync(tools)
  for (const tool of ["bash", "jq", "grep", "sed", "head", "tail", "setsid", "cat"]) {
    const real = spawnSync("bash", ["-c", `command -v ${tool}`]).stdout.toString().trim()
    if (real) fs.symlinkSync(real, path.join(tools, tool))
  }

  function run(args, env = {}) {
    const res = spawnSync("bash", [SCRIPT, ...args], {
      env: {
        PATH: bin + ":" + tools,
        HOME: path.join(dir, "home"),
        XDG_CONFIG_HOME: path.join(dir, "config"),
        LOG: log,
        CLIENTS: path.join(dir, "clients.json"),
        PS_OUT: path.join(dir, "ps.txt"),
        ...env
      }
    })
    return { status: res.status, stdout: res.stdout.toString(), stderr: res.stderr.toString() }
  }

  function calls() {
    return fs.readFileSync(log, "utf8").split("\n").filter(Boolean)
  }

  // The launcher runs in the background; give it a moment to write.
  function waitForCalls(n) {
    const end = Date.now() + 3000
    while (calls().length < n && Date.now() < end) spawnSync("sleep", ["0.05"])
    return calls()
  }

  return { dir, bin, run, calls, waitForCalls }
}

// A terminal window at pid 100 running a shell (200) running herdr (300), and
// the herdr server (400), whose panes are not windows.
const CLIENTS = [
  { pid: 100, address: "0xabc", workspace: { name: "3" }, focusHistoryID: 2 },
  { pid: 900, address: "0xfff", workspace: { name: "1" }, focusHistoryID: 0 }
]
const PS = [
  "  100     1 foot",
  "  200   100 bash",
  "  300   200 herdr",
  "  400     1 herdr server",
  "  900     1 firefox"
]

test("jump runs muster jump with the state dir, then focuses herdr's window", () => {
  const s = sandbox({ clients: CLIENTS, ps: PS })
  const res = s.run(["--state-dir", "/state", "jump", "w1:p2"])
  assert.equal(res.status, 0, res.stderr)
  assert.deepEqual(s.calls(), [
    "muster --state-dir /state jump w1:p2",
    "hyprctl clients -j",
    "hyprctl dispatch hl.dsp.focus({ workspace = '3' })",
    "hyprctl dispatch hl.dsp.focus({ window = 'address:0xabc' })"
  ])
})

test("jump expands ~ in the state dir", () => {
  const s = sandbox({ clients: CLIENTS, ps: PS })
  s.run(["--state-dir", "~/.local/state/herdr/plugins/muster", "jump", "orchestrator"])
  assert.equal(s.calls()[0],
    "muster --state-dir " + path.join(s.dir, "home") + "/.local/state/herdr/plugins/muster jump orchestrator")
})

test("jump without a state dir leaves it to muster", () => {
  const s = sandbox({ clients: CLIENTS, ps: PS })
  s.run(["jump", "w1:p2"])
  assert.equal(s.calls()[0], "muster jump w1:p2")
})

test("a failed jump reports muster's last line and raises nothing", () => {
  const s = sandbox({ clients: CLIENTS, ps: PS })
  const res = s.run(["jump", "w1:p2"], { MUSTER_FAIL: "muster jump: no orchestrator marked" })
  assert.equal(res.status, 1)
  assert.equal(res.stderr.trim(), "muster jump: no orchestrator marked")
  assert.deepEqual(s.calls(), ["muster jump w1:p2"])
})

// What muster prints when herdr's socket is not there: the server is down.
const DIAL = "muster jump: dial /home/x/.config/herdr/herdr.sock: dial unix /home/x/.config/herdr/herdr.sock: connect: no such file or directory"

test("a jump with herdr not running starts herdr and says the jump did not happen", () => {
  const s = sandbox({ clients: CLIENTS, ps: PS })
  const res = s.run(["jump", "w1:p2"], { MUSTER_FAIL: DIAL })
  assert.equal(res.status, 1)
  assert.equal(res.stderr.trim(), "herdr was not running, so it is starting. Jump again once your agents are back.")
  assert.deepEqual(s.waitForCalls(2), ["muster jump w1:p2", "launch"])
})

test("tell, report and dismiss pass through to muster and print what it said", () => {
  const s = sandbox()
  let res = s.run(["--state-dir", "/state", "tell", "pull main; rerun $(id)"], { MUSTER_OUT: "sent to the orchestrator" })
  assert.equal(res.status, 0, res.stderr)
  assert.equal(res.stdout.trim(), "sent to the orchestrator")
  res = s.run(["--state-dir", "/state", "report", "w3:p1"], { MUSTER_OUT: "told the orchestrator api landed" })
  assert.equal(res.stdout.trim(), "told the orchestrator api landed")
  res = s.run(["--state-dir", "/state", "dismiss", "w2:p1"])
  assert.equal(res.status, 0, res.stderr)
  assert.deepEqual(s.calls(), [
    "muster --state-dir /state tell pull main; rerun $(id)",
    "muster --state-dir /state report w3:p1",
    "muster --state-dir /state dismiss w2:p1"
  ])
})

test("tell refuses an empty message, report and dismiss refuse a bad pane", () => {
  const s = sandbox()
  assert.match(s.run(["tell", "  "]).stderr, /nothing to send/)
  assert.match(s.run(["report", "-h"]).stderr, /not a pane id/)
  assert.match(s.run(["dismiss", ""]).stderr, /not a pane id/)
  assert.deepEqual(s.calls(), [])
})

test("an action on a muster too old for it asks for an update", () => {
  const s = sandbox()
  const res = s.run(["tell", "hi"], { MUSTER_FAIL: 'muster: unknown command "tell"\nmuster — the Muster client\n\nusage:' })
  assert.equal(res.status, 1)
  assert.equal(res.stderr.trim(), "this needs a newer Muster than the one installed: run the Update Muster action in herdr")
})

test("an action with herdr not running says so and starts nothing", () => {
  const s = sandbox()
  const res = s.run(["report", "w3:p1"], { MUSTER_FAIL: DIAL.replace("jump", "report") })
  assert.equal(res.status, 1)
  assert.equal(res.stderr.trim(), "herdr is not running")
  assert.deepEqual(s.waitForCalls(2), ["muster report w3:p1"])
})

test("an action that fails otherwise shows muster's last line", () => {
  const s = sandbox()
  const res = s.run(["dismiss", "w9:p1"], { MUSTER_FAIL: "muster dismiss: w9:p1 has no row in the ribbon to dismiss" })
  assert.equal(res.stderr.trim(), "muster dismiss: w9:p1 has no row in the ribbon to dismiss")
})

test("jump refuses anything that is not a pane id", () => {
  const s = sandbox()
  for (const bad of ["", "-h", "--state-dir", "a b", "$(id)", "x".repeat(65)]) {
    const res = s.run(["jump", bad])
    assert.equal(res.status, 1, bad)
    assert.match(res.stderr, /not a pane id/)
  }
  assert.deepEqual(s.calls(), [])
})

test("the most recently focused herdr window wins", () => {
  const s = sandbox({
    clients: [
      { pid: 100, address: "0xabc", workspace: { name: "3" }, focusHistoryID: 4 },
      { pid: 110, address: "0xdef", workspace: { name: "5" }, focusHistoryID: 1 }
    ],
    ps: ["  100     1 foot", "  300   100 herdr", "  110     1 alacritty", "  310   110 /usr/bin/herdr"]
  })
  s.run(["raise"])
  assert.equal(s.calls().at(-1), "hyprctl dispatch hl.dsp.focus({ window = 'address:0xdef' })")
})

test("named sessions, remote sessions, the server and CLI calls are not the default window", () => {
  const s = sandbox({
    clients: [
      { pid: 100, address: "0x1", workspace: { name: "1" }, focusHistoryID: 0 },
      { pid: 101, address: "0x2", workspace: { name: "2" }, focusHistoryID: 0 },
      { pid: 102, address: "0x3", workspace: { name: "3" }, focusHistoryID: 0 },
      { pid: 103, address: "0x4", workspace: { name: "4" }, focusHistoryID: 0 }
    ],
    ps: [
      "  300   100 herdr --session work",
      "  301   101 herdr --remote box",
      "  302   102 herdr server",
      "  303   103 herdr pane list"
    ]
  })
  s.run(["raise"])
  assert.deepEqual(s.waitForCalls(2), ["hyprctl clients -j", "launch"])
})

test("with no herdr window, raise opens one on the default session", () => {
  const s = sandbox({ clients: [CLIENTS[1]], ps: ["  900     1 firefox"] })
  const res = s.run(["raise"])
  assert.equal(res.status, 0, res.stderr)
  assert.deepEqual(s.waitForCalls(2), ["hyprctl clients -j", "launch"])
})

test("with no window and no launcher, raise says so", () => {
  const s = sandbox({ clients: [], ps: [], omit: ["omarchy-launch-terminal-herdr"] })
  const res = s.run(["raise"])
  assert.equal(res.status, 1)
  assert.match(res.stderr, /omarchy-launch-terminal-herdr is not installed/)
})

test("a window address or workspace of the wrong shape is never spliced into Lua", () => {
  const s = sandbox({
    clients: [{ pid: 100, address: "0xabc'})--", workspace: { name: "x' })" }, focusHistoryID: 0 }],
    ps: ["  300   100 herdr"]
  })
  s.run(["raise"])
  const calls = s.waitForCalls(2)
  assert.ok(calls.every((c) => !c.startsWith("hyprctl dispatch")), calls.join("\n"))
  assert.deepEqual(calls, ["hyprctl clients -j", "launch"])
})

test("a special workspace is switched to by name", () => {
  const s = sandbox({
    clients: [{ pid: 100, address: "0xabc", workspace: { name: "special:term" }, focusHistoryID: 0 }],
    ps: ["  300   100 herdr"]
  })
  s.run(["raise"])
  assert.ok(s.calls().includes("hyprctl dispatch hl.dsp.focus({ workspace = 'special:term' })"))
})

test("which finds muster on PATH", () => {
  const s = sandbox()
  const res = s.run(["which"])
  assert.equal(res.status, 0)
  assert.equal(res.stdout.trim(), path.join(s.bin, "muster"))
})

test("which falls back to the path muster install wrote into herdr's tab bar", () => {
  const s = sandbox({ omit: ["muster"] })
  const plugin = path.join(s.dir, "herdr-plugins", "muster", "bin")
  fs.mkdirSync(plugin, { recursive: true })
  fs.writeFileSync(path.join(plugin, "muster"), "#!/bin/sh\n", { mode: 0o755 })
  fs.mkdirSync(path.join(s.dir, "config", "herdr"), { recursive: true })
  fs.writeFileSync(path.join(s.dir, "config", "herdr", "config.toml"), [
    "[ui]",
    `tab_bar_right = [{ type = "command", command = "'${plugin}/muster' --state-dir '/state' badge m", interval_seconds = 5 }, { type = "zoom" }]`,
    ""
  ].join("\n"))
  const res = s.run(["which"])
  assert.equal(res.status, 0, res.stderr)
  assert.equal(res.stdout.trim(), path.join(plugin, "muster"))
})

test("an explicit muster path is used as given, and must exist", () => {
  const s = sandbox({ omit: ["muster"] })
  const res = s.run(["--muster", "/nowhere/muster", "jump", "w1:p2"])
  assert.equal(res.status, 1)
  assert.match(res.stderr, /muster not found/)

  const other = path.join(s.dir, "other-muster")
  fs.writeFileSync(other, `#!/bin/sh\necho "other $*" >> "$LOG"\n`, { mode: 0o755 })
  s.run(["--muster", other, "jump", "w1:p2"])
  assert.equal(s.calls()[0], "other jump w1:p2")
})

test("an empty --muster keeps the default", () => {
  const s = sandbox()
  const res = s.run(["--muster", "", "which"])
  assert.equal(res.stdout.trim(), path.join(s.bin, "muster"))
})
