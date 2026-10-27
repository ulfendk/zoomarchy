.pragma library

// Zoom geometry. Everything is in one monitor's logical coordinates, and the
// frozen frame has exactly the monitor's logical size, so a screen point and
// an image point share one coordinate space at zoom 1.
//
// The view is anchored on a screen point `anchor`: the image point under the
// anchor stays under it at every zoom. While zooming the anchor follows the
// pointer, which gives the usual magnifier feel (the pixel under the pointer
// never moves) and still reaches every edge, because a pointer at the screen
// edge anchors the image edge.

var MIN_ZOOM = 1
var MAX_ZOOM = 16

function clamp(value, lo, hi) {
  return Math.max(lo, Math.min(hi, value))
}

function clampZoom(zoom) {
  if (!isFinite(zoom)) return MIN_ZOOM
  return clamp(zoom, MIN_ZOOM, MAX_ZOOM)
}

// One wheel notch (or arrow key) multiplies the zoom by `factor`; negative
// steps divide. Snaps to exactly 1 so "zoomed out" is a stable state.
function stepZoom(zoom, steps, factor) {
  var next = clampZoom(zoom * Math.pow(factor > 1 ? factor : 1.25, steps))
  return Math.abs(next - 1) < 0.01 ? 1 : next
}

// Content translation for a scale applied around the top-left corner.
function offset(anchor, zoom) {
  return anchor * (1 - zoom)
}

function toImage(screenCoord, anchor, zoom) {
  return (screenCoord - offset(anchor, zoom)) / zoom
}

function toScreen(imageCoord, anchor, zoom) {
  return offset(anchor, zoom) + imageCoord * zoom
}

function toImagePoint(sx, sy, ax, ay, zoom) {
  return { x: toImage(sx, ax, zoom), y: toImage(sy, ay, zoom) }
}

// Index of the screen whose logical rectangle contains the global point, or
// the nearest one when the point falls in a gap between monitors.
function screenIndexAt(screens, x, y) {
  var best = -1
  var bestDistance = Infinity
  for (var i = 0; i < screens.length; i++) {
    var s = screens[i]
    if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return i
    var dx = Math.max(s.x - x, 0, x - (s.x + s.width))
    var dy = Math.max(s.y - y, 0, y - (s.y + s.height))
    var distance = dx * dx + dy * dy
    if (distance < bestDistance) {
      bestDistance = distance
      best = i
    }
  }
  return best
}
