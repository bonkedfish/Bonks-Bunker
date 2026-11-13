# TiffReader — minimal GeoTIFF reader for the elevation step of the map pipeline (D-039).
# Reads one 32-bit float band (what USGS 3DEP exportImage returns with pixelType=F32), strips or tiles,
# little- or big-endian, uncompressed or Deflate, with no predictor or the floating-point predictor (3).
# Pure: bytes in, { width, height, values (row 0 = north) } out, or { error }.
class_name TiffReader
extends RefCounted

const TAG_WIDTH := 256
const TAG_HEIGHT := 257
const TAG_BITS := 258
const TAG_COMPRESSION := 259
const TAG_STRIP_OFFSETS := 273
const TAG_SAMPLES := 277
const TAG_ROWS_PER_STRIP := 278
const TAG_STRIP_BYTES := 279
const TAG_PREDICTOR := 317
const TAG_TILE_WIDTH := 322
const TAG_TILE_HEIGHT := 323
const TAG_TILE_OFFSETS := 324
const TAG_TILE_BYTES := 325
const TAG_SAMPLE_FORMAT := 339
const TYPE_SIZES := {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8, 16: 8}


static func read_f32(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:
		return {"error": "file too short"}
	var le := bytes[0] == 0x49 and bytes[1] == 0x49
	if not le and not (bytes[0] == 0x4D and bytes[1] == 0x4D):
		return {"error": "not a TIFF (got '%s')" % bytes.slice(0, 64).get_string_from_utf8().left(60)}
	if _u16(bytes, 2, le) != 42:
		return {"error": "not a classic TIFF (BigTIFF is not supported)"}
	var ifd := _u32(bytes, 4, le)
	var tags := {}
	for i in _u16(bytes, ifd, le):
		var e := ifd + 2 + i * 12
		tags[_u16(bytes, e, le)] = _values(bytes, _u16(bytes, e + 2, le), _u32(bytes, e + 4, le), e + 8, le)
	var w := _tag(tags, TAG_WIDTH, 0)
	var h := _tag(tags, TAG_HEIGHT, 0)
	var comp := _tag(tags, TAG_COMPRESSION, 1)
	var pred := _tag(tags, TAG_PREDICTOR, 1)
	if _tag(tags, TAG_BITS, 0) != 32 or _tag(tags, TAG_SAMPLE_FORMAT, 1) != 3 or _tag(tags, TAG_SAMPLES, 1) != 1:
		return {"error": "expected one 32-bit float band"}
	if not comp in [1, 8, 32946]:
		return {"error": "compression %d not supported (ask for compression=None)" % comp}
	if not pred in [1, 3]:
		return {"error": "predictor %d not supported" % pred}
	var out := PackedFloat32Array()
	out.resize(w * h)
	var tiled := tags.has(TAG_TILE_WIDTH)
	var cw := _tag(tags, TAG_TILE_WIDTH, w) if tiled else w
	var ch := _tag(tags, TAG_TILE_HEIGHT, h) if tiled else _tag(tags, TAG_ROWS_PER_STRIP, h)
	var offsets: Array = tags.get(TAG_TILE_OFFSETS if tiled else TAG_STRIP_OFFSETS, [])
	var counts: Array = tags.get(TAG_TILE_BYTES if tiled else TAG_STRIP_BYTES, [])
	var across := ceili(float(w) / cw) if tiled else 1
	for k in offsets.size():
		var x0 := (k % across) * cw
		var y0 := floori(float(k) / across) * ch
		var rows := ch if tiled else mini(ch, h - y0)
		var raw := bytes.slice(int(offsets[k]), int(offsets[k]) + int(counts[k]))
		var chunk := raw if comp == 1 else raw.decompress(cw * rows * 4, FileAccess.COMPRESSION_DEFLATE)
		if chunk.size() < cw * rows * 4:
			return {"error": "chunk %d decoded to %d bytes, expected %d" % [k, chunk.size(), cw * rows * 4]}
		var floats := _to_floats(chunk, cw, rows, pred, le)
		for y in rows:
			if y0 + y >= h:
				break
			for x in cw:
				if x0 + x < w:
					out[(y0 + y) * w + x0 + x] = floats[y * cw + x]
	return {"width": w, "height": h, "values": out}


static func _to_floats(chunk: PackedByteArray, cols: int, rows: int, pred: int, le: bool) -> PackedFloat32Array:
	var floats := PackedFloat32Array()
	floats.resize(cols * rows)
	if pred == 3:
		# Floating-point predictor: undo byte-wise differencing per row, then the bytes of each sample
		# are spread across the row most-significant first.
		var row := PackedByteArray()
		row.resize(cols * 4)
		for y in rows:
			var base := y * cols * 4
			for i in range(1, cols * 4):
				chunk[base + i] = (chunk[base + i] + chunk[base + i - 1]) & 0xFF
			for c in cols:
				for b in 4:
					row[c * 4 + 3 - b] = chunk[base + b * cols + c]  # into little-endian order
			for c in cols:
				floats[y * cols + c] = row.decode_float(c * 4)
		return floats
	if le:
		for i in cols * rows:
			floats[i] = chunk.decode_float(i * 4)
		return floats
	var tmp := PackedByteArray()
	tmp.resize(4)
	for i in cols * rows:
		for b in 4:
			tmp[b] = chunk[i * 4 + 3 - b]
		floats[i] = tmp.decode_float(0)
	return floats


static func _values(bytes: PackedByteArray, typ: int, count: int, field: int, le: bool) -> Array:
	var size: int = TYPE_SIZES.get(typ, 0)
	if not typ in [3, 4]:
		return []
	var at := field if size * count <= 4 else _u32(bytes, field, le)
	var out := []
	for i in count:
		out.append(_u16(bytes, at + i * 2, le) if typ == 3 else _u32(bytes, at + i * 4, le))
	return out


static func _tag(tags: Dictionary, tag: int, fallback: int) -> int:
	var v: Array = tags.get(tag, [])
	return int(v[0]) if not v.is_empty() else fallback


static func _u16(b: PackedByteArray, at: int, le: bool) -> int:
	return b[at] | (b[at + 1] << 8) if le else (b[at] << 8) | b[at + 1]


static func _u32(b: PackedByteArray, at: int, le: bool) -> int:
	if le:
		return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
