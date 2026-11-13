# HeightField — terrain height in game metres from an elevation grid over a lat/lon box (D-039).
# y = elevation - datum (datum = elevation at the map centre, so the centre sits at y 0).
# Flat pads (landmark lots) override the terrain inside a rect and blend back over `blend` metres.
# Pure: no nodes. Depends on: MapProjection.
class_name HeightField
extends RefCounted

var width := 0
var height := 0
var datum := 0.0

var _values := PackedFloat32Array()
var _bbox := PackedFloat64Array()  # lon_min, lat_min, lon_max, lat_max
var _proj: MapProjection
var _pads: Array = []  # [Rect2, height, blend]


# values: row 0 = north edge, w x h, covering bbox [lon_min, lat_min, lon_max, lat_max].
func _init(w: int, h: int, values: PackedFloat32Array, bbox: Array, projection: MapProjection) -> void:
	width = w
	height = h
	_values = values
	_bbox = PackedFloat64Array(bbox)
	_proj = projection
	_fill_no_data()
	datum = raw(0.0, 0.0)


# Elevation above sea level at game (x, z), bilinear between pixel centres, clamped at the edges.
func raw(x: float, z: float) -> float:
	var ll := _proj.to_lat_lon(x, z)
	var px := (ll.y - _bbox[0]) / (_bbox[2] - _bbox[0]) * width - 0.5
	var py := (_bbox[3] - ll.x) / (_bbox[3] - _bbox[1]) * height - 0.5
	px = clampf(px, 0.0, width - 1.001)
	py = clampf(py, 0.0, height - 1.001)
	var x0 := int(px)
	var y0 := int(py)
	var fx := px - x0
	var fy := py - y0
	var a := _values[y0 * width + x0]
	var b := _values[y0 * width + x0 + 1]
	var c := _values[(y0 + 1) * width + x0]
	var d := _values[(y0 + 1) * width + x0 + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


# Game-space terrain height (relative to the datum) including pads.
func sample(x: float, z: float) -> float:
	var h := raw(x, z) - datum
	for pad in _pads:
		var r: Rect2 = pad[0]
		var dx := maxf(maxf(r.position.x - x, 0.0), x - r.end.x)
		var dz := maxf(maxf(r.position.y - z, 0.0), z - r.end.y)
		var d := sqrt(dx * dx + dz * dz)
		var blend: float = pad[2]
		if d <= 0.0:
			h = pad[1]
		elif d < blend:
			h = lerpf(pad[1], h, smoothstep(0.0, blend, d))
	return h


func add_pad(rect: Rect2, pad_height: float, blend: float) -> void:
	_pads.append([rect, pad_height, blend])


# USGS marks missing cells with huge negatives; replace them with the mean of the valid ones.
func _fill_no_data() -> void:
	var total := 0.0
	var n := 0
	for v in _values:
		if v > -1000.0 and v < 10000.0:
			total += v
			n += 1
	var mean := total / maxf(n, 1)
	for i in _values.size():
		if not (_values[i] > -1000.0 and _values[i] < 10000.0):
			_values[i] = mean
