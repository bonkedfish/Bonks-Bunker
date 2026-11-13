# GraphicsRules — pure quality-tier logic (D-038): validate the tier data and pick a tier for a GPU.
# No nodes, no rendering calls (the Graphics autoload applies the numbers).
# Depends on: DataLoader, data/tuning/graphics.json.
class_name GraphicsRules
extends RefCounted

const DATA_PATH := "res://data/tuning/graphics.json"
const FILE_SCHEMA := {"tiers": TYPE_DICTIONARY, "auto": TYPE_DICTIONARY, "budgets": TYPE_DICTIONARY, "perf_log": TYPE_DICTIONARY}
const TIER_SCHEMA := {
	"render_scale": TYPE_FLOAT, "shadows": TYPE_BOOL, "shadow_distance": TYPE_FLOAT, "shadow_atlas": TYPE_FLOAT,
	"msaa": TYPE_FLOAT, "fxaa": TYPE_BOOL, "ssao": TYPE_BOOL, "view_distance": TYPE_FLOAT, "max_fps": TYPE_FLOAT,
}
const TIER_ORDER := ["low", "medium", "high"]

static var _data: Dictionary = {}


static func load_data() -> Dictionary:
	if _data.is_empty():
		var d := DataLoader.load_validated(DATA_PATH, FILE_SCHEMA)
		var ok := not d.is_empty()
		for t: String in TIER_ORDER:
			ok = ok and d.tiers.has(t) and DataLoader.validate(d.tiers[t], TIER_SCHEMA, "%s:%s" % [DATA_PATH, t])
		_data = d if ok else {}
	return _data


# Integrated GPU -> integrated_tier; discrete GPU whose name has a high-end keyword -> high_tier;
# other discrete/unknown GPUs -> discrete_tier.
static func pick_tier(adapter_name: String, integrated: bool, auto: Dictionary) -> String:
	if integrated:
		return str(auto.get("integrated_tier", "low"))
	var upper := adapter_name.to_upper()
	for kw in auto.get("high_gpu_keywords", []):
		if upper.contains(str(kw).to_upper()):
			return str(auto.get("high_tier", "high"))
	return str(auto.get("discrete_tier", "medium"))
