# MapProjection — pure lat/lon <-> game-space conversion around a cell's center (equirectangular;
# accurate to centimetres over a few km). Godot axes: +X = east, -Z = north, Y up. 1 unit = 1 metre.
# Shared by the map import pipeline (build_cell.gd) and LandmarkLoader so both land in the same place.
class_name MapProjection
extends RefCounted

const METERS_PER_DEG_LAT := 110540.0
const METERS_PER_DEG_LON_AT_EQUATOR := 111320.0

var center_lat := 0.0
var center_lon := 0.0
var _lon_scale := 1.0


func _init(lat: float, lon: float) -> void:
	center_lat = lat
	center_lon = lon
	_lon_scale = METERS_PER_DEG_LON_AT_EQUATOR * cos(deg_to_rad(lat))


# Returns Vector2(x east, z south) in metres.
func to_local(lat: float, lon: float) -> Vector2:
	return Vector2((lon - center_lon) * _lon_scale, -(lat - center_lat) * METERS_PER_DEG_LAT)


func to_world(lat: float, lon: float, y: float = 0.0) -> Vector3:
	var p := to_local(lat, lon)
	return Vector3(p.x, y, p.y)


func to_lat_lon(x: float, z: float) -> Vector2:
	return Vector2(center_lat - z / METERS_PER_DEG_LAT, center_lon + x / _lon_scale)
