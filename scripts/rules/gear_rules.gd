# GearRules — weapons and armor as rolled instances (D-087). Pure: no nodes. Reads data/weapons/weapons.json (via
# WeaponDB), data/gear/rarity.json, armor.json, mods.json and items.json (via ItemDB).
# An instance is a Dictionary {uid, id, rarity, cond 0-1, mods: [mod item ids], perk: "" or perk id, mag: rounds}:
#   roll()          a new instance (tier by weight, condition in the tier's range, maybe a free mod, legendary perk)
#   weapon_stats()  the WeaponDB definition with rarity, perk, mods and condition applied (same keys + "name",
#                   "zoom", "pellets", "spread_deg", "auto", "mesh") - what WeaponHolder and CombatWorld use
#   armor_dr() / total_resist()  share of incoming damage blocked, capped
#   armor_wear()    condition lost by each armor piece for blocking `blocked` damage
#   repair_cost()   scrap to bring an instance back to full condition
# Equip slots: gun1, gun2 (guns), melee (melee + thrown), head, chest, legs (armor).
class_name GearRules
extends RefCounted

const RARITY_PATH := "res://data/gear/rarity.json"
const ARMOR_PATH := "res://data/gear/armor.json"
const MODS_PATH := "res://data/gear/mods.json"
const SLOTS := ["gun1", "gun2", "melee", "head", "chest", "legs"]
const WEAPON_SLOTS := ["gun1", "gun2", "melee"]
const ARMOR_SLOTS := ["head", "chest", "legs"]
const TIER_ORDER := ["worn", "standard", "pristine", "legendary"]

static var _rarity: Dictionary = {}
static var _armor: Dictionary = {}
static var _mods: Dictionary = {}


static func rarity_data() -> Dictionary:
	if _rarity.is_empty():
		_rarity = DataLoader.load_json(RARITY_PATH)
	return _rarity


static func armor_data() -> Dictionary:
	if _armor.is_empty():
		_armor = DataLoader.load_json(ARMOR_PATH)
		_armor.erase("note")
	return _armor


static func mod_data() -> Dictionary:
	if _mods.is_empty():
		_mods = DataLoader.load_json(MODS_PATH)
		_mods.erase("note")
	return _mods


# --- what an item is ---------------------------------------------------------------------

static func is_weapon(id: String) -> bool:
	return ItemDB.has_item(id) and str(ItemDB.get_item(id).get("category", "")) == "weapon"


static func is_armor(id: String) -> bool:
	return armor_data().has(id)


static func is_gear(id: String) -> bool:
	return is_weapon(id) or is_armor(id)


static func is_mod(id: String) -> bool:
	return mod_data().has(id)


# "gun", "melee" (melee and thrown weapons), "head", "chest" or "legs"; "" for anything else.
static func kind_of(id: String) -> String:
	if is_armor(id):
		return str(armor_data()[id].slot)
	if is_weapon(id):
		return "gun" if str(WeaponDB.get_weapon(id).get("kind", "")) == "gun" else "melee"
	return ""


# The equip slots this item can go in.
static func slots_for(id: String) -> Array:
	var k := kind_of(id)
	if k == "gun":
		return ["gun1", "gun2"]
	return [k] if k != "" else []


# --- rolling -------------------------------------------------------------------------------

static func roll(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var r := rarity_data()
	var tiers: Dictionary = r.tiers
	var tier := str(ItemDB.get_item(id).get("fixed_rarity", ""))
	if not tiers.has(tier):
		var total := 0.0
		for t: String in TIER_ORDER:
			total += float(tiers[t].weight)
		var pick := rng.randf() * total
		tier = TIER_ORDER[0]
		for t: String in TIER_ORDER:
			pick -= float(tiers[t].weight)
			if pick <= 0.0:
				tier = t
				break
	var td: Dictionary = tiers[tier]
	var inst := {"uid": 0, "id": id, "rarity": tier, "cond": snappedf(rng.randf_range(float(td.cond[0]), float(td.cond[1])), 0.01),
		"mods": [], "perk": "", "mag": 0}
	if is_weapon(id) and rng.randf() < float(td.mod_chance):
		var slots: Array = WeaponDB.get_weapon(id).get("mod_slots", [])
		if not slots.is_empty():
			var want: String = slots[rng.randi() % slots.size()]
			var fits := []
			for m: String in mod_data():
				if str(mod_data()[m].slot) == want:
					fits.append(m)
			if not fits.is_empty():
				inst.mods.append(fits[rng.randi() % fits.size()])
	if tier == "legendary":
		var perks: Dictionary = r.perks.get(_perk_group(id), {})
		if not perks.is_empty():
			var keys := perks.keys()
			inst.perk = str(keys[rng.randi() % keys.size()])
	return inst


static func _perk_group(id: String) -> String:
	if is_armor(id):
		return "armor"
	return kind_of(id)


# --- names ---------------------------------------------------------------------------------

# "Legendary Brutal Fire Axe", "Worn 9mm Pistol", "Platte Pump Shotgun" (standard has no prefix).
static func display_name(inst: Dictionary) -> String:
	var base := str(ItemDB.get_item(str(inst.id)).get("name", inst.id))
	var parts: Array[String] = []
	var tier := str(rarity_data().tiers.get(str(inst.rarity), {}).get("name", ""))
	if tier != "":
		parts.append(tier)
	if str(inst.get("perk", "")) != "":
		parts.append(str(rarity_data().perks.get(_perk_group(str(inst.id)), {}).get(inst.perk, {}).get("name", "")))
	parts.append(base)
	return " ".join(parts)


static func rarity_color(rarity: String) -> Color:
	var c: Array = rarity_data().tiers.get(rarity, {}).get("color", [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]))


# --- weapons -------------------------------------------------------------------------------

# Effective weapon definition for an instance (or the plain definition for id with no instance data).
static func weapon_stats(inst: Dictionary) -> Dictionary:
	var id := str(inst.id)
	var w: Dictionary = WeaponDB.get_weapon(id).duplicate()
	if w.is_empty():
		return w
	w["id"] = id
	var r := rarity_data()
	var mult := float(r.tiers.get(str(inst.get("rarity", "standard")), {}).get("mult", 1.0))
	var cond_floor := float(r.get("cond_floor_weapon", 0.6))
	var cond := clampf(float(inst.get("cond", 1.0)), 0.0, 1.0)
	w.damage = float(w.damage) * mult * lerpf(cond_floor, 1.0, cond)
	var changes: Array = []
	if str(inst.get("perk", "")) != "":
		changes.append(r.perks.get(_perk_group(id), {}).get(inst.perk, {}))
	for m: String in inst.get("mods", []):
		changes.append(mod_data().get(m, {}))
	for ch: Dictionary in changes:
		for key: String in ch:
			if key == "zoom":
				w["zoom"] = maxf(float(w.get("zoom", 1.0)), float(ch.zoom))
			elif key in ["damage", "fire_interval", "spread_deg", "mag_size", "reload_time", "range", "noise_radius",
					"swing_interval", "windup"] and w.has(key):
				w[key] = float(w[key]) * float(ch[key])
	if w.has("mag_size"):
		w.mag_size = float(maxi(1, roundi(float(w.mag_size))))
	w["name"] = display_name(inst)
	w["rarity"] = str(inst.get("rarity", "standard"))
	w["cond"] = cond
	return w


# True if `mod_id` fits a free slot on this weapon instance.
static func can_attach(inst: Dictionary, mod_id: String) -> bool:
	if not is_mod(mod_id) or not is_weapon(str(inst.id)):
		return false
	var slot := str(mod_data()[mod_id].slot)
	if not slot in WeaponDB.get_weapon(str(inst.id)).get("mod_slots", []):
		return false
	for m: String in inst.get("mods", []):
		if str(mod_data().get(m, {}).get("slot", "")) == slot:
			return false
	return true


# --- armor ---------------------------------------------------------------------------------

static func armor_dr(inst: Dictionary) -> float:
	var a: Dictionary = armor_data().get(str(inst.id), {})
	if a.is_empty():
		return 0.0
	var r := rarity_data()
	var dr := float(a.dr) * float(r.tiers.get(str(inst.get("rarity", "standard")), {}).get("mult", 1.0))
	dr *= lerpf(float(r.get("cond_floor_armor", 0.5)), 1.0, clampf(float(inst.get("cond", 1.0)), 0.0, 1.0))
	if str(inst.get("perk", "")) != "":
		dr *= float(r.perks.armor.get(inst.perk, {}).get("dr", 1.0))
	return dr


static func total_resist(pieces: Array) -> float:
	var total := 0.0
	for p: Dictionary in pieces:
		total += armor_dr(p)
	return minf(total, float(rarity_data().get("resist_cap", 0.7)))


# New condition for each piece after blocking `blocked` damage, shared out by what each piece blocks.
static func armor_wear(pieces: Array, blocked: float) -> Array[float]:
	var out: Array[float] = []
	var total := 0.0
	for p: Dictionary in pieces:
		total += armor_dr(p)
	for p: Dictionary in pieces:
		var share := armor_dr(p) / total if total > 0.0 else 0.0
		var wear := float(armor_data().get(str(p.id), {}).get("wear", 0.0))
		if str(p.get("perk", "")) != "":
			wear *= float(rarity_data().perks.armor.get(p.perk, {}).get("wear", 1.0))
		out.append(maxf(float(p.get("cond", 1.0)) - blocked * share * wear, 0.0))
	return out


# --- upkeep --------------------------------------------------------------------------------

static func repair_cost(inst: Dictionary) -> int:
	var missing := 1.0 - clampf(float(inst.get("cond", 1.0)), 0.0, 1.0)
	if missing <= 0.001:
		return 0
	return maxi(1, ceili(missing * float(rarity_data().get("repair_scrap_per_cond", 6.0))))


static func weight(inst: Dictionary) -> float:
	var w := CarryRules.item_weight(ItemDB.get_item(str(inst.id)))
	for m: String in inst.get("mods", []):
		w += CarryRules.item_weight(ItemDB.get_item(m))
	return w
