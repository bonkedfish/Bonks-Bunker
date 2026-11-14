# GroundPaintCheck — dev check for tools/map_import/ground_paint.gd (D-080): paints the country club's course onto a
# flat stand-in ground for the four 256 m cells around the clubhouse and prints the triangle count per cell and the
# time taken. Writes tests/_look/ground_paint_check.txt. Depends on: GroundPaint, data/map/landmarks.json.
extends Node

const GroundPaint := preload("res://tools/map_import/ground_paint.gd")


func _ready() -> void:
	var lm: Dictionary = DataLoader.load_json("res://data/map/landmarks.json").country_club
	var proj := MapProjection.new(40.6825183, -99.1036165)
	var pos := proj.to_local(float(lm.lat), float(lm.lon))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://paint_check"))
	var paint := GroundPaint.new("user://paint_check")
	paint.add(DataLoader.load_json(str(lm.ground_paint)), "country_club", pos, 0.0)
	var lines := PackedStringArray()
	var t0 := Time.get_ticks_msec()
	var total := 0
	var ox := floorf(pos.x / 256.0) * 256.0
	var oz := floorf(pos.y / 256.0) * 256.0
	for dz in range(-3, 2):
		for dx in range(-3, 3):
			var root := Node3D.new()
			var n := paint.add_cell(Rect2(ox + dx * 256.0, oz + dz * 256.0, 256.0, 256.0), root, func(_x: float, _z: float) -> float: return 0.0, 4.0)
			total += n
			if n > 0:
				lines.append("cell %d,%d: %d tris, %d meshes" % [dx, dz, n, root.get_child_count()])
			root.free()
	lines.append("total %d tris in %d ms" % [total, Time.get_ticks_msec() - t0])
	print("\n".join(lines))
	var f := FileAccess.open("res://tests/_look/ground_paint_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
