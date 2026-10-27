// node tests/run.js
const assert = require("assert")
const load = require("./load")

const Z = load("ZoomMath.js")
const S = load("Strokes.js")
const K = load("Keys.js")
const C = load("Config.js")

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) }
  catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}
// Values built inside the vm context carry its prototypes; compare plain copies.
const plain = v => JSON.parse(JSON.stringify(v))
const same = (a, b) => assert.deepStrictEqual(plain(a), plain(b))
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-6, `${msg || ""} expected ${b}, got ${a}`)

// ---------------------------------------------------------------- ZoomMath
test("image point under the anchor stays fixed at every zoom", () => {
  for (const zoom of [1, 1.5, 2, 4, 16]) {
    near(Z.toImage(700, 700, zoom), 700, "zoom " + zoom)
    near(Z.toScreen(700, 700, zoom), 700, "zoom " + zoom)
  }
})
test("anchor at a screen edge shows that edge of the image", () => {
  const width = 1500
  for (const zoom of [2, 3, 8]) {
    near(Z.toImage(0, 0, zoom), 0)
    near(Z.toImage(width, width, zoom), width)
    // The visible image span is width / zoom wide.
    near(Z.toImage(width, 0, zoom) - Z.toImage(0, 0, zoom), width / zoom)
  }
})
test("toImage and toScreen are inverses", () => {
  near(Z.toScreen(Z.toImage(123, 400, 2.5), 400, 2.5), 123)
})
test("zoom clamps and snaps to 1", () => {
  assert.strictEqual(Z.stepZoom(1, -1, 1.25), 1)
  assert.strictEqual(Z.stepZoom(1.25, -1, 1.25), 1)
  near(Z.stepZoom(2, 1, 1.25), 2.5)
  assert.strictEqual(Z.stepZoom(15, 5, 1.25), 16)
  assert.strictEqual(Z.clampZoom(NaN), 1)
})
test("screenIndexAt picks the containing or nearest monitor", () => {
  // This machine: eDP-1 1500x1000 logical at 0,0 and DP-1 3440x1440 at 1500,0.
  const screens = [{ x: 0, y: 0, width: 1500, height: 1000 }, { x: 1500, y: 0, width: 3440, height: 1440 }]
  assert.strictEqual(Z.screenIndexAt(screens, 10, 10), 0)
  assert.strictEqual(Z.screenIndexAt(screens, 1500, 10), 1)
  assert.strictEqual(Z.screenIndexAt(screens, 4009, 1242), 1)
  assert.strictEqual(Z.screenIndexAt(screens, 100, 1200), 0)
  assert.strictEqual(Z.screenIndexAt([], 0, 0), -1)
})

// ---------------------------------------------------------------- Strokes
test("shift snaps lines to 45 degrees and boxes to squares", () => {
  const b = S.constrain("line", { x: 0, y: 0 }, { x: 100, y: 10 })
  near(b.y, 0); near(b.x, Math.sqrt(100 * 100 + 10 * 10))
  const sq = S.constrain("rect", { x: 0, y: 0 }, { x: 50, y: -20 })
  same({ x: sq.x, y: sq.y }, { x: 50, y: -50 })
})
test("arrow has a shaft and a head ending at the tip", () => {
  const lines = S.polylinesFor("arrow", [{ x: 0, y: 0 }, { x: 100, y: 0 }], 4, false)
  assert.strictEqual(lines.length, 2)
  same(lines[1][1], { x: 100, y: 0 })
  assert.ok(lines[1][0].x < 100 && lines[1][2].x < 100)
})
test("zero-length arrow degrades to a line", () => {
  assert.strictEqual(S.polylinesFor("arrow", [{ x: 5, y: 5 }], 4, false).length, 1)
})
test("rectangle and ellipse close their outline", () => {
  const rect = S.polylinesFor("rect", [{ x: 0, y: 0 }, { x: 10, y: 20 }], 2, false)[0]
  assert.strictEqual(rect.length, 5)
  same(rect[0], rect[4])
  const ellipse = S.polylinesFor("ellipse", [{ x: 0, y: 0 }, { x: 10, y: 20 }], 2, false)[0]
  near(ellipse[0].x, ellipse[ellipse.length - 1].x); near(ellipse[0].y, ellipse[ellipse.length - 1].y)
  near(ellipse[0].x, 10); near(ellipse[0].y, 10)
})
test("freehand drops points closer than the minimum distance", () => {
  const pts = []
  assert.ok(S.appendPoint(pts, { x: 0, y: 0 }, 1))
  assert.ok(!S.appendPoint(pts, { x: 0.5, y: 0 }, 1))
  assert.ok(S.appendPoint(pts, { x: 2, y: 0 }, 1))
  assert.strictEqual(pts.length, 2)
})
test("a pen click leaves a dot", () => {
  const stroke = S.makeStroke("pen", [{ x: 3, y: 3 }], "#ff0000", 4, false)
  assert.strictEqual(stroke.polylines[0].length, 2)
  assert.ok(!S.isEmpty(stroke))
})
test("highlighter is wide and translucent", () => {
  const stroke = S.makeStroke("highlighter", [{ x: 0, y: 0 }, { x: 9, y: 0 }], "#ffff00", 4, false)
  assert.strictEqual(stroke.width, 16)
  assert.ok(stroke.alpha < 1)
})
test("blank text is empty", () => {
  assert.ok(S.isEmpty(S.makeText(0, 0, "   ", "#fff", 20)))
  assert.ok(!S.isEmpty(S.makeText(0, 0, "hi", "#fff", 20)))
})

// ---------------------------------------------------------------- Keys
test("parse and format round-trip with aliases and either separator", () => {
  assert.strictEqual(K.normalize("super + shift + z"), "SUPER + SHIFT + Z")
  assert.strictEqual(K.normalize("CONTROL + SUPER + 1"), "SUPER + CTRL + 1")
  assert.strictEqual(K.normalize("SUPER SHIFT + mouse_down"), "SUPER + SHIFT + mouse_down")
  assert.ok(!K.parse("SUPER + HYPER + Z").valid)
  assert.ok(!K.parse("SUPER + SHIFT").valid)
  assert.ok(K.parse("").empty)
})
const binds = [
  { modmask: 68, key: "Z", keycode: 0, description: "Zoom in", submap: "" },
  { modmask: 68, key: "", keycode: 10, description: "Bar panel 1", submap: "" },
  { modmask: 72, key: "mouse_down", keycode: 0, description: "Next window in group", submap: "" },
  { modmask: 64, key: "Z", keycode: 0, description: "Zoomarchy: Still zoom", submap: "" },
  { modmask: 64, key: "Z", keycode: 0, description: "Other submap", submap: "resize" },
  { modmask: 64 | 16, key: "x", keycode: 0, description: "Numlock variant", submap: "" }
]
test("conflicts match keysyms case-insensitively", () => {
  same(K.conflicts("SUPER + CTRL + Z", binds, "Zoomarchy: "), ["Zoom in"])
})
test("digits collide with code:N binds", () => {
  same(K.conflicts("SUPER + CTRL + 1", binds, "Zoomarchy: "), ["Bar panel 1"])
})
test("own binds and submap binds never conflict", () => {
  same(K.conflicts("SUPER + Z", binds, "Zoomarchy: "), [])
})
test("lock modifiers are ignored and mouse binds compare", () => {
  same(K.conflicts("SUPER + X", binds, "Zoomarchy: "), ["Numlock variant"])
  same(K.conflicts("SUPER + ALT + mouse_down", binds, "Zoomarchy: "), ["Next window in group"])
  same(K.conflicts("SUPER + CTRL + mouse_down", binds, "Zoomarchy: "), [])
})
test("duplicates finds actions sharing a combo", () => {
  const d = K.duplicates({ a: "SUPER + Z", b: "super + z", c: "SUPER + X", d: "" })
  same(d.slice().sort(), ["a", "b"])
})
test("captured events map to Hyprland names", () => {
  const META = 0x10000000, SHIFT = 0x02000000, CTRL = 0x04000000
  assert.strictEqual(K.comboFromQt(0x5a, META, 52), "SUPER + Z")
  // Shift+1 reports "!" as the key; the number-row keycode wins.
  assert.strictEqual(K.comboFromQt(0x21, META | SHIFT, 10), "SUPER + SHIFT + 1")
  assert.strictEqual(K.comboFromQt(0x01000030 + 4, CTRL, 0), "CTRL + F5")
  assert.strictEqual(K.comboFromQt(0x01000022, META, 133), "")
  assert.strictEqual(K.comboFromWheel(-120, META | CTRL), "SUPER + CTRL + mouse_down")
  assert.strictEqual(K.comboFromWheel(120, META | CTRL), "SUPER + CTRL + mouse_up")
})
test("bare keys warn, function keys do not", () => {
  assert.ok(K.warning("SHIFT + Z") !== "")
  assert.strictEqual(K.warning("F8"), "")
  assert.strictEqual(K.warning("SUPER + Z"), "")
})

test("text bind output keeps keycode binds", () => {
  const text = [
    "bindd", "\tmodmask: 68", "\tsubmap: ", "\tkey: SUPER + CTRL + code:10", "\tkeycode: 0",
    "\tcatchall: false", "\tdescription: Bar panel 1", "\tdispatcher: __lua", "\targ: 247",
    "bindd", "\tmodmask: 68", "\tsubmap: ", "\tkey: Z", "\tkeycode: 0",
    "\tcatchall: false", "\tdescription: Zoom in", "\tdispatcher: __lua", "\targ: 264", ""
  ].join("\n")
  const parsed = K.parseBindsText(text)
  assert.strictEqual(parsed.length, 2)
  same(K.conflicts("SUPER + CTRL + 1", parsed, "Zoomarchy: "), ["Bar panel 1"])
  same(K.conflicts("SUPER + CTRL + Z", parsed, "Zoomarchy: "), ["Zoom in"])
})

// ---------------------------------------------------------------- Config
test("merge tolerates garbage and clamps values", () => {
  same(C.merge("not json"), C.defaults())
  const m = C.merge({ penWidth: 999, zoomDefault: "3", bindings: { zoom: "super+x", bogus: "A" }, extra: 1 })
  assert.strictEqual(m.penWidth, 40)
  assert.strictEqual(m.zoomDefault, 3)
  assert.strictEqual(m.bindings.zoom, "SUPER + X")
  assert.strictEqual(m.bindings.bogus, undefined)
  assert.strictEqual(m.extra, undefined)
})
test("lua file binds every valid action and unbinds overrides", () => {
  const s = C.defaults()
  s.bindings.draw = ""
  s.bindings.zoom = "SUPER + CTRL + 1"
  s.overrides.zoom = true
  const lua = C.luaFile(s)
  assert.ok(lua.includes('hl.unbind("SUPER + CTRL + 1")\no.bind("SUPER + CTRL + 1", "Zoomarchy: Still zoom", "omarchy-shell -q zoomarchy zoom")'))
  assert.ok(!lua.includes("zoomarchy draw"))
  assert.ok(lua.includes('"SUPER + CTRL + mouse_up", "Zoomarchy: Live zoom in"'))
  assert.ok(lua.includes("layer_rule"))
})
test("lua strings are escaped", () => {
  assert.strictEqual(K.luaString('a"b\\c'), '"a\\"b\\\\c"')
})

if (failed) { console.log(`\n${failed} failed`); process.exit(1) }
console.log("\nall passed")
