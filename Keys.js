.pragma library

// Hyprland key-combo handling for the settings screen: parsing the
// "SUPER + SHIFT + Z" strings Omarchy's o.bind() takes, turning a captured
// Qt key event into one, and checking it against the binds Hyprland reports
// through `hyprctl binds -j`.

// Hyprland modmask bits.
var MOD_BITS = {
  SHIFT: 1,
  CAPS: 2,
  CTRL: 4,
  ALT: 8,
  MOD2: 16,
  MOD3: 32,
  SUPER: 64,
  MOD5: 128
}

var MOD_ALIASES = {
  CONTROL: "CTRL",
  WIN: "SUPER",
  LOGO: "SUPER",
  META: "SUPER",
  MOD4: "SUPER",
  MOD1: "ALT"
}

// Lock-style modifiers never decide whether two binds collide.
var IGNORED_MODS = MOD_BITS.CAPS | MOD_BITS.MOD2

var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT", "MOD3", "MOD5"]

// xkb keycodes of the number row. Omarchy binds some of these as code:N, and
// they are layout independent, so captured digits are compared by keycode.
var DIGIT_KEYCODES = { "1": 10, "2": 11, "3": 12, "4": 13, "5": 14, "6": 15, "7": 16, "8": 17, "9": 18, "0": 19 }
var KEYCODE_NAMES = { 10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0", 20: "minus", 21: "equal" }

// Qt::Key values (stable across Qt 6) to xkb keysym names Hyprland accepts.
var QT_KEY_NAMES = {}
QT_KEY_NAMES[0x20] = "space"
QT_KEY_NAMES[0x27] = "apostrophe"
QT_KEY_NAMES[0x2c] = "comma"
QT_KEY_NAMES[0x2d] = "minus"
QT_KEY_NAMES[0x2e] = "period"
QT_KEY_NAMES[0x2f] = "slash"
QT_KEY_NAMES[0x3b] = "semicolon"
QT_KEY_NAMES[0x3d] = "equal"
QT_KEY_NAMES[0x5b] = "bracketleft"
QT_KEY_NAMES[0x5c] = "backslash"
QT_KEY_NAMES[0x5d] = "bracketright"
QT_KEY_NAMES[0x60] = "grave"
QT_KEY_NAMES[0x01000001] = "Tab"
QT_KEY_NAMES[0x01000003] = "BackSpace"
QT_KEY_NAMES[0x01000004] = "Return"
QT_KEY_NAMES[0x01000005] = "Return"
QT_KEY_NAMES[0x01000006] = "Insert"
QT_KEY_NAMES[0x01000007] = "Delete"
QT_KEY_NAMES[0x01000009] = "Print"
QT_KEY_NAMES[0x01000010] = "Home"
QT_KEY_NAMES[0x01000011] = "End"
QT_KEY_NAMES[0x01000012] = "Left"
QT_KEY_NAMES[0x01000013] = "Up"
QT_KEY_NAMES[0x01000014] = "Right"
QT_KEY_NAMES[0x01000015] = "Down"
QT_KEY_NAMES[0x01000016] = "Prior"
QT_KEY_NAMES[0x01000017] = "Next"

var QT_MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025, 0x01000053, 0x01000054, 0x01001103]
var QT_KEY_ESCAPE = 0x01000000
var QT_KEY_F1 = 0x01000030
var QT_KEY_F35 = 0x01000052

var QT_SHIFT = 0x02000000
var QT_CTRL = 0x04000000
var QT_ALT = 0x08000000
var QT_META = 0x10000000

function canonicalMod(name) {
  var upper = String(name || "").trim().toUpperCase()
  upper = MOD_ALIASES[upper] || upper
  return MOD_BITS[upper] !== undefined ? upper : ""
}

// Comparison form of a key: lower-cased keysym name, digits and code:N
// folded onto their keycode so "1" and "code:10" collide.
function keyIdentity(key, keycode) {
  var k = String(key || "").trim()
  var code = Number(keycode || 0)
  var codeMatch = k.match(/^code:(\d+)$/i)
  if (codeMatch) code = Number(codeMatch[1])
  if (code > 0) return "code:" + code
  if (DIGIT_KEYCODES[k] !== undefined) return "code:" + DIGIT_KEYCODES[k]
  return k.toLowerCase()
}

// "SUPER + SHIFT + Z" -> { valid, mods, key, error }. Hyprland also accepts
// spaces between modifiers ("SUPER SHIFT"), so both separators are handled.
function parse(combo) {
  var text = String(combo || "").trim()
  if (text === "") return { valid: false, empty: true, mods: 0, key: "", error: "" }
  var parts = text.split("+").map(function(part) { return part.trim() }).filter(function(part) { return part !== "" })
  if (parts.length === 0) return { valid: false, mods: 0, key: "", error: "No key" }
  var key = parts.pop()
  var mods = 0
  var tokens = []
  parts.forEach(function(part) { tokens = tokens.concat(part.split(/\s+/)) })
  for (var i = 0; i < tokens.length; i++) {
    var mod = canonicalMod(tokens[i])
    if (!mod) return { valid: false, mods: 0, key: key, error: "Unknown modifier " + tokens[i] }
    mods |= MOD_BITS[mod]
  }
  if (canonicalMod(key)) return { valid: false, mods: mods, key: "", error: "Missing a key after the modifiers" }
  return { valid: true, mods: mods, key: key, error: "" }
}

function displayKey(key) {
  var k = String(key || "")
  return k.length === 1 ? k.toUpperCase() : k
}

function format(mods, key) {
  var parts = []
  for (var i = 0; i < MOD_ORDER.length; i++) {
    if (mods & MOD_BITS[MOD_ORDER[i]]) parts.push(MOD_ORDER[i])
  }
  parts.push(displayKey(key))
  return parts.join(" + ")
}

function normalize(combo) {
  var parsed = parse(combo)
  return parsed.valid ? format(parsed.mods, parsed.key) : String(combo || "").trim()
}

function modsFromQt(modifiers) {
  var mods = 0
  if (modifiers & QT_META) mods |= MOD_BITS.SUPER
  if (modifiers & QT_CTRL) mods |= MOD_BITS.CTRL
  if (modifiers & QT_ALT) mods |= MOD_BITS.ALT
  if (modifiers & QT_SHIFT) mods |= MOD_BITS.SHIFT
  return mods
}

function isModifierKey(qtKey) {
  return QT_MODIFIER_KEYS.indexOf(qtKey) !== -1
}

function isEscape(qtKey) {
  return qtKey === QT_KEY_ESCAPE
}

// Key name for a captured key event. The number row goes by keycode, since
// Shift+1 reports "!" (or a layout-specific symbol) as its Qt key.
function keyNameFromQt(qtKey, nativeScanCode) {
  if (KEYCODE_NAMES[nativeScanCode] !== undefined) return KEYCODE_NAMES[nativeScanCode]
  if (qtKey >= 0x41 && qtKey <= 0x5a) return String.fromCharCode(qtKey)
  if (qtKey >= 0x30 && qtKey <= 0x39) return String.fromCharCode(qtKey)
  if (qtKey >= QT_KEY_F1 && qtKey <= QT_KEY_F35) return "F" + (qtKey - QT_KEY_F1 + 1)
  if (QT_KEY_NAMES[qtKey] !== undefined) return QT_KEY_NAMES[qtKey]
  return ""
}

function comboFromQt(qtKey, modifiers, nativeScanCode) {
  if (isModifierKey(qtKey)) return ""
  var key = keyNameFromQt(qtKey, nativeScanCode)
  return key ? format(modsFromQt(modifiers), key) : ""
}

// Hyprland names scroll binds by direction: wheel down is mouse_down.
function comboFromWheel(angleDeltaY, modifiers) {
  if (!angleDeltaY) return ""
  return format(modsFromQt(modifiers), angleDeltaY < 0 ? "mouse_down" : "mouse_up")
}

function sameCombo(a, b) {
  return (a.mods & ~IGNORED_MODS) === (b.mods & ~IGNORED_MODS) && keyIdentity(a.key) === keyIdentity(b.key)
}

// Parses plain `hyprctl binds` output. Its JSON form drops the key of
// keycode binds (key "" and keycode 0 for Omarchy's "SUPER + code:10"), while
// the text form keeps it, as the full combo string.
function parseBindsText(text) {
  var out = []
  var blocks = String(text || "").split(/\n\s*\n|\n(?=\S)/)
  for (var i = 0; i < blocks.length; i++) {
    var record = {}
    var lines = blocks[i].split("\n")
    for (var j = 0; j < lines.length; j++) {
      var m = lines[j].match(/^\s+(\w+):\s?(.*)$/)
      if (m) record[m[1]] = m[2]
    }
    if (record.modmask === undefined || record.key === undefined) continue
    var key = String(record.key)
    if (key.indexOf("+") !== -1) key = key.split("+").pop().trim()
    out.push({
      modmask: Number(record.modmask) || 0,
      key: key,
      keycode: Number(record.keycode) || 0,
      submap: String(record.submap || "").trim(),
      description: String(record.description || ""),
      dispatcher: String(record.dispatcher || ""),
      arg: String(record.arg || "")
    })
  }
  return out
}

// Binds Hyprland already has for `combo`. `binds` is `hyprctl binds -j`;
// entries whose description starts with `ownPrefix` are this tool's own and
// never count. Submap binds only fire inside their submap, so they are
// skipped too.
function conflicts(combo, binds, ownPrefix) {
  var parsed = parse(combo)
  if (!parsed.valid) return []
  var out = []
  var list = Array.isArray(binds) ? binds : []
  for (var i = 0; i < list.length; i++) {
    var b = list[i]
    if (!b || (b.submap && b.submap !== "")) continue
    var description = String(b.description || "")
    if (ownPrefix && description.indexOf(ownPrefix) === 0) continue
    var other = { mods: Number(b.modmask || 0), key: keyIdentity(b.key, b.keycode) }
    if ((other.mods & ~IGNORED_MODS) !== (parsed.mods & ~IGNORED_MODS)) continue
    if (other.key !== keyIdentity(parsed.key)) continue
    out.push(description || (b.dispatcher + " " + (b.arg || "")).trim())
  }
  return out
}

// Ids of actions in `bindings` ({ id: combo }) that share a combo with
// another action. Empty combos are unbound and never clash.
function duplicates(bindings) {
  var seen = {}
  var dupes = {}
  for (var id in bindings) {
    var parsed = parse(bindings[id])
    if (!parsed.valid) continue
    var identity = (parsed.mods & ~IGNORED_MODS) + "|" + keyIdentity(parsed.key)
    if (seen[identity] !== undefined) {
      dupes[id] = true
      dupes[seen[identity]] = true
    } else {
      seen[identity] = id
    }
  }
  return Object.keys(dupes)
}

// A bare key without modifiers would be taken from every application.
function warning(combo) {
  var parsed = parse(combo)
  if (!parsed.valid) return parsed.error || ""
  if ((parsed.mods & ~(IGNORED_MODS | MOD_BITS.SHIFT)) === 0 && !/^F\d+$|^Print$/i.test(parsed.key))
    return "Without SUPER, CTRL or ALT this key is taken from every app"
  return ""
}

function luaString(value) {
  return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""
}
