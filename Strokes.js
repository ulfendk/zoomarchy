.pragma library

// Annotation geometry. A stroke is a plain object kept in image coordinates:
//   { kind, color, width, alpha, polylines: [[{x, y}, ...], ...] }
//   { kind: "text", color, size, x, y, text }
// Every shape tool reduces to polylines so the renderer needs one primitive.

var TOOLS = ["pen", "highlighter", "line", "arrow", "rect", "ellipse", "text"]

var TOOL_KEYS = {
  p: "pen",
  h: "highlighter",
  l: "line",
  a: "arrow",
  r: "rect",
  o: "ellipse",
  t: "text"
}

var TOOL_LABELS = {
  pen: "Pen",
  highlighter: "Highlighter",
  line: "Line",
  arrow: "Arrow",
  rect: "Rectangle",
  ellipse: "Ellipse",
  text: "Text"
}

var ELLIPSE_SEGMENTS = 72
var HIGHLIGHTER_ALPHA = 0.38
var HIGHLIGHTER_WIDTH_FACTOR = 4

function distance(a, b) {
  var dx = b.x - a.x
  var dy = b.y - a.y
  return Math.sqrt(dx * dx + dy * dy)
}

// Shift while dragging: lines and arrows snap to 45 degree steps, boxes and
// ellipses become squares and circles.
function constrain(tool, a, b) {
  var dx = b.x - a.x
  var dy = b.y - a.y
  if (tool === "rect" || tool === "ellipse") {
    var side = Math.max(Math.abs(dx), Math.abs(dy))
    return { x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side) }
  }
  var length = Math.sqrt(dx * dx + dy * dy)
  if (length === 0) return { x: b.x, y: b.y }
  var step = Math.PI / 4
  var angle = Math.round(Math.atan2(dy, dx) / step) * step
  return { x: a.x + Math.cos(angle) * length, y: a.y + Math.sin(angle) * length }
}

// Head size grows with the line width but never swamps a short arrow.
function arrowHead(a, b, width) {
  var length = distance(a, b)
  if (length === 0) return []
  var size = Math.min(Math.max(width * 4, 10), length * 0.6)
  var angle = Math.atan2(b.y - a.y, b.x - a.x)
  var spread = Math.PI / 7
  return [
    { x: b.x - size * Math.cos(angle - spread), y: b.y - size * Math.sin(angle - spread) },
    { x: b.x, y: b.y },
    { x: b.x - size * Math.cos(angle + spread), y: b.y - size * Math.sin(angle + spread) }
  ]
}

function rectangle(a, b) {
  return [
    { x: a.x, y: a.y },
    { x: b.x, y: a.y },
    { x: b.x, y: b.y },
    { x: a.x, y: b.y },
    { x: a.x, y: a.y }
  ]
}

function ellipse(a, b) {
  var cx = (a.x + b.x) / 2
  var cy = (a.y + b.y) / 2
  var rx = Math.abs(b.x - a.x) / 2
  var ry = Math.abs(b.y - a.y) / 2
  var points = []
  for (var i = 0; i <= ELLIPSE_SEGMENTS; i++) {
    var t = (i / ELLIPSE_SEGMENTS) * Math.PI * 2
    points.push({ x: cx + rx * Math.cos(t), y: cy + ry * Math.sin(t) })
  }
  return points
}

// Freehand input arrives once per pointer event; dropping points closer than
// `minDistance` keeps long strokes cheap without visible faceting.
function appendPoint(points, p, minDistance) {
  if (points.length > 0 && distance(points[points.length - 1], p) < minDistance) return false
  points.push({ x: p.x, y: p.y })
  return true
}

// `points` is the raw drag: every sample for freehand tools, otherwise the
// start and current point. Returns the polylines to render.
function polylinesFor(tool, points, width, constrained) {
  if (points.length === 0) return []
  var a = points[0]
  var b = points[points.length - 1]
  if (constrained && tool !== "pen" && tool !== "highlighter") b = constrain(tool, a, b)

  switch (tool) {
  case "pen":
  case "highlighter":
    if (constrained) return [[a, constrain("line", a, b)]]
    // A click without movement still leaves a dot.
    if (points.length === 1) return [[a, { x: a.x + 0.01, y: a.y }]]
    return [points.slice()]
  case "line":
    return [[a, b]]
  case "arrow":
    var head = arrowHead(a, b, width)
    return head.length ? [[a, b], head] : [[a, b]]
  case "rect":
    return [rectangle(a, b)]
  case "ellipse":
    return [ellipse(a, b)]
  }
  return []
}

function makeStroke(tool, points, color, width, constrained) {
  var highlighter = tool === "highlighter"
  var strokeWidth = highlighter ? width * HIGHLIGHTER_WIDTH_FACTOR : width
  return {
    kind: tool,
    color: String(color),
    width: strokeWidth,
    alpha: highlighter ? HIGHLIGHTER_ALPHA : 1,
    polylines: polylinesFor(tool, points, strokeWidth, constrained)
  }
}

function makeText(x, y, text, color, size) {
  return { kind: "text", color: String(color), size: size, x: x, y: y, text: String(text) }
}

function isEmpty(stroke) {
  if (!stroke) return true
  if (stroke.kind === "text") return String(stroke.text || "").trim() === ""
  return !stroke.polylines || stroke.polylines.length === 0
}
