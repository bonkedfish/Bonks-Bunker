# DiscCatalogTest — D-119 disc catalog, pure (no map): 15+ catalog discs in base and premium plastic, each an item,
# each sold by John Pork for 50-150 bottle caps and flying a sensible full-power distance; the bag order runs
# fastest first; the course box only hands out the starters; premium slips less than base; wear beats a disc in
# (more turn, less fade) faster for base plastic and tree hits; every disc builds a mesh.
# Results: tests/_look/disc_catalog_result.txt (ends with the failure count).
# Depends on: DiscFlightRules, DiscMesh, ItemDB, data/dialogue/john_pork.json, data/tuning/disc_golf.json.
extends Node

const DiscMesh := preload("res://scripts/discgolf/disc_mesh.gd")

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	var discs := DiscFlightRules.discs()
	var t := DiscFlightRules.tuning()
	var starters: Array = t.get("starter_discs", [])
	var catalog: Array[String] = []
	for id: String in discs:
		if not starters.has(id):
			catalog.append(id)
	_check(catalog.size() >= 15, "%d catalog discs (+%d starters)" % [catalog.size(), starters.size()])
	var tiers := {"base": 0, "premium": 0}
	for id: String in catalog:
		var tier := str(discs[id].get("tier", ""))
		tiers[tier] = int(tiers.get(tier, 0)) + 1
	_check(int(tiers.base) > 0 and int(tiers.premium) > 0 and tiers.size() == 2, "plastic tiers %s" % tiers)
	# Shop: every catalog disc is sold for bottle caps, 50..150, and the sale gives that disc.
	var nodes: Dictionary = DataLoader.load_json("res://data/dialogue/john_pork.json").trees.john_pork_talk.nodes
	var price := {}
	for n: String in nodes:
		for c: Dictionary in nodes[n].get("choices", []):
			var cost: Dictionary = c.get("cost", {})
			var sold: Dictionary = nodes.get(str(c.get("next", "")), {})
			for gid: String in sold.get("give", {}):
				if discs.has(gid) and cost.has("bottle_cap"):
					price[gid] = int(cost.bottle_cap)
	var shop_ok := true
	var items_ok := true
	for id: String in catalog:
		shop_ok = shop_ok and price.has(id) and int(price[id]) >= 50 and int(price[id]) <= 150
		items_ok = items_ok and ItemDB.has_item(id)
	_check(shop_ok, "John Pork sells every catalog disc for 50-150 caps (%d priced)" % price.size())
	_check(items_ok, "every disc is an item")
	var cheapest := 999
	var dearest := 0
	for id: String in price:
		cheapest = mini(cheapest, int(price[id]))
		dearest = maxi(dearest, int(price[id]))
	_log.append("  prices %d .. %d caps" % [cheapest, dearest])
	# Flight: full-power backhand distances.
	var far_ok := true
	for id: String in DiscFlightRules.bag_order():
		var m := DiscFlightRules.flat_distance(discs[id], 1.0, t)
		far_ok = far_ok and m > 35.0 and m < 140.0
		_log.append("  %-26s %s  %5.1f m full power" % [ItemDB.get_item(id).name, "%d|%d|%d|%d" % [roundi(float(discs[id].speed)),
			roundi(float(discs[id].glide)), roundi(float(discs[id].turn)), roundi(float(discs[id].fade))], m])
	_check(far_ok, "every disc flies 35-140 m at full power")
	var order := DiscFlightRules.bag_order()
	var sorted_ok := true
	for i in range(1, order.size()):
		sorted_ok = sorted_ok and float(discs[order[i - 1]].speed) >= float(discs[order[i]].speed)
	_check(sorted_ok and order.size() == discs.size(), "3 steps through the bag fastest first (%s .. %s)" % [order[0], order[order.size() - 1]])
	_check(starters.size() == 3 and not starters.has(catalog[0]), "the course box hands out only the starters %s" % [starters])
	# Grip: premium slips less.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base_s := _spread(discs.disc_comet_base, t, rng)
	var prem_s := _spread(discs.disc_comet_premium, t, rng)
	_check(prem_s < base_s * 0.5 and base_s > 0.5, "aim slip (1 sigma): base %.2f deg, premium %.2f deg" % [base_s, prem_s])
	# Wear.
	var d: Dictionary = discs.disc_crane_base
	var w_base := 0.0
	var w_prem := 0.0
	for i in 20:
		w_base = DiscFlightRules.wear_after(w_base, d, 0, t)
		w_prem = DiscFlightRules.wear_after(w_prem, discs.disc_crane_premium, 0, t)
	_check(w_base > w_prem * 2.0, "20 throws: base beaten in %.0f%%, premium %.0f%%" % [w_base * 100.0, w_prem * 100.0])
	_check(DiscFlightRules.wear_after(0.0, d, 2, t) > DiscFlightRules.wear_after(0.0, d, 0, t), "tree hits wear a disc faster")
	_check(is_equal_approx(DiscFlightRules.wear_after(0.99, d, 10, t), 1.0), "wear stops at 100%")
	var worn := DiscFlightRules.worn(d, 1.0, t)
	_check(float(worn.turn) < float(d.turn) and float(worn.fade) < float(d.fade) and float(d.turn) == -1.0,
		"fully beaten in: turn %.1f -> %.1f, fade %.1f -> %.1f" % [float(d.turn), float(worn.turn), float(d.fade), float(worn.fade)])
	var side_new := _side(d, t)
	var side_worn := _side(worn, t)
	_check(side_worn < side_new - 1.0, "a beaten-in disc ends further right (%.1f m vs %.1f m)" % [side_worn, side_new])
	# Looks.
	var mesh_ok := true
	for id: String in discs:
		mesh_ok = mesh_ok and DiscMesh.mesh(id) != null and DiscMesh.mesh(id).get_surface_count() > 0
	_check(mesh_ok, "every disc builds a mesh")
	_log.append("%d failure(s)" % _fails)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/disc_catalog_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _spread(disc: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> float:
	var sum := 0.0
	for i in 400:
		sum += pow(rad_to_deg(DiscFlightRules.slip(disc, t, rng).x), 2.0)
	return sqrt(sum / 400.0)


# Where a full-power flat backhand ends sideways (+ = left).
func _side(disc: Dictionary, t: Dictionary) -> float:
	var f := DiscFlightRules.launch(disc, 1.0, Vector3(0, 1.4, 0), 0.0, DiscFlightRules.launch_pitch(0.0, t), 0.0, {}, t)
	for i in 4000:
		DiscFlightRules.step(f, 1.0 / float(t.step_hz), t)
		if f.pos.y <= 0.0:
			break
	return -f.pos.x


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
