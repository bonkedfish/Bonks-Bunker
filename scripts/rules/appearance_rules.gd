# AppearanceRules — the character creator's looks (D-096), pure (no nodes). A look is a small Dictionary saved with
# the character and synced as Player.net_look: {body, skin, hair, hair_color, beard, shirt, pants, shoes, hat, extra,
# accent} (keys or colour indexes into data/art/appearance.json). sanitize() turns anything (old saves, a client's
# request) into a valid look; random_look() gives a new character a starting look; model_of() / dress() turn a
# look into the base model id and the CharacterAnimator overrides (outfit colours, hair parts, hair colour, gear
# pieces on bones). Depends on: DataLoader, data/art/appearance.json.
class_name AppearanceRules
extends RefCounted

const DATA_PATH := "res://data/art/appearance.json"
const COLOR_KEYS := {"skin": "skin_tones", "hair_color": "hair_colors", "shirt": "cloth_colors", "pants": "cloth_colors",
	"shoes": "cloth_colors", "accent": "cloth_colors"}
const PICK_KEYS := {"body": "bodies", "hair": "hair_styles", "hat": "hats", "extra": "extras"}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataLoader.load_json(DATA_PATH)
	return _data


# Option keys for a pick ("body", "hair", "hat", "extra") in data order, or the colour count for a colour key.
static func choices(key: String) -> Array:
	var d := data()
	if PICK_KEYS.has(key):
		return (d[PICK_KEYS[key]] as Dictionary).keys()
	if COLOR_KEYS.has(key):
		return range((d[COLOR_KEYS[key]] as Array).size())
	return [false, true] if key == "beard" else []


static func color_of(key: String, index: int) -> Color:
	var list: Array = data()[COLOR_KEYS[key]]
	var c: Array = list[clampi(index, 0, list.size() - 1)]
	return Color(c[0], c[1], c[2])


# Display name of a pick option ("Ball cap").
static func label(key: String, value: Variant) -> String:
	if PICK_KEYS.has(key):
		return str((data()[PICK_KEYS[key]] as Dictionary).get(str(value), {}).get("name", str(value)))
	if key == "beard":
		return "Yes" if bool(value) else "No"
	return "%d" % (int(value) + 1)


static func default_look() -> Dictionary:
	return {"body": "male", "skin": 2, "hair": "parted", "hair_color": 1, "beard": false, "shirt": 0, "pants": 1, "shoes": 2,
		"hat": "none", "extra": "none", "accent": 4}


# Any Dictionary -> a valid look (unknown keys dropped, bad values back to the default; beards only on men).
static func sanitize(raw: Variant) -> Dictionary:
	var look := default_look()
	if typeof(raw) != TYPE_DICTIONARY:
		return look
	var r: Dictionary = raw
	for k: String in PICK_KEYS:
		if r.has(k) and (data()[PICK_KEYS[k]] as Dictionary).has(str(r[k])):
			look[k] = str(r[k])
	for k: String in COLOR_KEYS:
		if r.has(k) and (typeof(r[k]) == TYPE_INT or typeof(r[k]) == TYPE_FLOAT):
			var n: int = (data()[COLOR_KEYS[k]] as Array).size()
			if int(r[k]) >= 0 and int(r[k]) < n:
				look[k] = int(r[k])
	look.beard = bool(r.get("beard", false)) and look.body == "male"
	return look


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for k: String in PICK_KEYS:
		var opts := choices(k)
		look[k] = opts[rng.randi() % opts.size()]
	for k: String in COLOR_KEYS:
		look[k] = rng.randi() % choices(k).size()
	look.beard = rng.randf() < 0.35
	if rng.randf() < 0.5:
		look.hat = "none"
	if rng.randf() < 0.5:
		look.extra = "none"
	return sanitize(look)


# The base model (character_models.json id) a look is built on.
static func model_of(look: Dictionary) -> String:
	return str((data().bodies as Dictionary).get(str(look.get("body", "male")), data().bodies.male).model)


# CharacterAnimator overrides for a look: outfit colours, hair parts (+ eyebrows, beard), hair colour, gear pieces.
static func dress(look: Dictionary) -> Dictionary:
	var d := data()
	var l := sanitize(look)
	var outfit := {}
	for k: String in ["skin", "shirt", "pants", "shoes"]:
		var c := color_of(k, int(l[k]))
		outfit[k] = [c.r, c.g, c.b]
	var hair: Array = (d.hair_styles[l.hair].parts as Array).duplicate()
	if l.beard:
		hair.append(str(d.beard))
	hair.append(str(d.bodies[l.body].eyebrows))
	var hc := color_of("hair_color", int(l.hair_color))
	var accent := color_of("accent", int(l.accent))
	var gear: Array = []
	for part: Dictionary in (d.hats[l.hat].parts as Array) + (d.extras[l.extra].parts as Array):
		var g := part.duplicate(true)
		match typeof(g.get("color")):
			TYPE_STRING:
				g.color = [accent.r, accent.g, accent.b] if str(g.color) == "accent" else d.dark
		gear.append(g)
	return {"outfit": outfit, "hair": hair, "hair_color": [hc.r, hc.g, hc.b], "gear": gear}
