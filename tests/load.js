// Loads lib/muster.js the way QML would: as a script whose top-level names are
// the library. `.pragma library` is QML syntax, not JavaScript, so it is cut
// before the rest runs in a fresh context.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const file = path.join(__dirname, "..", "lib", "muster.js")

module.exports = function load() {
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
  const context = vm.createContext({})
  vm.runInContext(source, context, { filename: file })
  return context
}
