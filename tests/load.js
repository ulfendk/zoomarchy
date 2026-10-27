// Loads the plugin's QML JavaScript libraries (".pragma library" files with
// ".import" lines) into plain Node objects for testing.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const root = path.join(__dirname, "..")
const cache = {}

function load(file) {
  if (cache[file]) return cache[file]
  const source = fs.readFileSync(path.join(root, file), "utf8")
  const context = vm.createContext({ Math, JSON, Number, String, Object, Array, isFinite, Infinity })
  const body = source.split("\n").map(line => {
    const imp = line.match(/^\.import\s+"([^"]+)"\s+as\s+(\w+)/)
    if (imp) {
      context[imp[2]] = load(imp[1])
      return ""
    }
    return line.startsWith(".pragma") ? "" : line
  }).join("\n")
  vm.runInContext(body, context, { filename: file })
  cache[file] = context
  return context
}

module.exports = load
