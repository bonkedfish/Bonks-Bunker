# CellGrid — pure maths for the streamed map's square cells (D-039, D-048). cells_x x cells_z cells of cell_size
# metres; `origin` = world x/z of cell (0, 0)'s north-west corner (default: grid centred on the map centre).
# The import config's "area" {x_min_m, z_min_m, cells_x, cells_z} sets an off-centre rectangle (from_config).
# Positions use game space (+X east, +Z south). No nodes.
class_name CellGrid
extends RefCounted

var cell_size := 256.0
var cells_x := 8
var cells_z := 8
var origin := Vector2.ZERO  # world x/z of cell (0, 0)'s north-west corner


func _init(size: float, count_x: int, count_z := -1, corner := Vector2.INF) -> void:
	cell_size = size
	cells_x = count_x
	cells_z = count_z if count_z > 0 else count_x
	origin = corner if corner != Vector2.INF else -Vector2(cells_x, cells_z) * size * 0.5


# Grid from data/map/import_config.json: "area" rectangle if present, else the old centred square.
static func from_config(cfg: Dictionary) -> CellGrid:
	var size := float(cfg.cell_size_m)
	var area: Dictionary = cfg.get("area", {})
	if area.is_empty():
		return CellGrid.new(size, int(cfg.cells_per_side))
	return CellGrid.new(size, int(area.cells_x), int(area.cells_z), Vector2(float(area.x_min_m), float(area.z_min_m)))


# The whole map in world x/z, grown by `margin` metres on every side.
func area_rect(margin := 0.0) -> Rect2:
	return Rect2(origin - Vector2.ONE * margin, Vector2(cells_x, cells_z) * cell_size + Vector2.ONE * margin * 2.0)


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - origin.x) / cell_size), floori((pos.z - origin.y) / cell_size))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cells_x and c.y < cells_z


func rect_of(c: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(c) * cell_size, Vector2.ONE * cell_size)


func key(c: Vector2i) -> String:
	return "%d_%d" % [c.x, c.y]


# Adds every in-bounds cell within `radius` cells (a square ring) of `center` to `out` as keys.
func add_square(out: Dictionary, center: Vector2i, radius: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dz)
			if in_bounds(c):
				out[c] = true
