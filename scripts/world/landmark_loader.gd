# LandmarkLoader — places hand-built landmark scenes (Bonk's house, the bunker, later UNK, the Archway...)
# on the generated map from data/map/landmarks.json (lat/lon + rotation), using the same MapProjection
# as the map importer so they line up with the real streets. Runs at load on every peer in the same
# (sorted) order with the landmark key as node name, so node paths for containers/synchronizers match.
# Height comes from the generated cell index (terrain under each landmark, D-039); 0 if there's no index.
# Depends on: DataLoader, MapProjection, data/map/import_config.json, data/map/landmarks.json, data/map/pois.json, data/map/streaming.json.
extends Node3D

const CONFIG_PATH := "res://data/map/import_config.json"
const LANDMARKS_PATH := "res://data/map/landmarks.json"
const POIS_PATH := "res://data/map/pois.json"
const STREAMING_PATH := "res://data/map/streaming.json"


func _ready() -> void:
	var cfg := DataLoader.load_json(CONFIG_PATH)
	var landmarks := DataLoader.load_json(LANDMARKS_PATH)
	landmarks.merge(DataLoader.load_json(POIS_PATH).get("pois", {}))  # small generated POIs (D-056)
	if cfg.is_empty():
		return
	var proj := MapProjection.new(float(cfg.center_lat), float(cfg.center_lon))
	var index := DataLoader.load_json(str(DataLoader.load_json(STREAMING_PATH).get("index_path", "")))
	var heights: Dictionary = index.get("landmarks", {})
	var keys := landmarks.keys()
	keys.sort()
	for key: String in keys:
		var lm: Dictionary = landmarks[key]
		var scene := load(str(lm.get("scene", ""))) as PackedScene
		if scene == null:
			push_error("LandmarkLoader: cannot load scene for '%s'" % key)
			continue
		var node := scene.instantiate() as Node3D
		node.name = key
		node.position = proj.to_world(float(lm.lat), float(lm.lon), float(heights.get(key, 0.0)))
		node.rotation.y = deg_to_rad(float(lm.get("rotation_deg", 0.0)))
		add_child(node)
