class_name Upgrades
extends RefCounted
## Level-up choices (weighted by Suerte), reroll/skip/banish, and latas de película (chests)
## that give 1, 3 or 5 rewards, evolutions and Uniones.

const MAX_WEAPONS := 6
const MAX_PASSIVES := 6
const STAT_TEXT := {"damage": "daño", "amount": "proyectil", "area": "área", "cooldown": "enfriamiento", "duration": "duración",
	"pierce": "perforación", "speed": "velocidad", "size": "tamaño", "range": "alcance", "stun": "aturdimiento", "chain": "rebote", "knockback": "empuje"}

## Text for what the next level of a weapon adds, e.g. "+4 daño".
static func describe_up(w: Dictionary, next_level: int) -> String:
	var ups: Array = w.levels
	if next_level - 2 >= ups.size() or next_level < 2: return w.desc
	var up: Dictionary = ups[next_level - 2]
	var parts: Array = []
	for k in up:
		var v = up[k]
		var name: String = STAT_TEXT.get(k, k)
		if k in WeaponSystem.MULT_KEYS: parts.append("%+d %% %s" % [roundi(float(v) * 100.0), name])
		else: parts.append("%+d %s" % [roundi(float(v)), name] if float(v) == roundf(float(v)) else "%+.1f %s" % [float(v), name])
	return ", ".join(parts)

## A list of n options. Each option: {kind, id, name, desc, level_text, icon_id}.
static func roll(run, n: int) -> Array:
	var cands: Array = []   # [option, weight]
	var ws: WeaponSystem = run.weapons
	for w in ws.list:
		if w.level < run.weapon_cap(w) and not run.banished.has(w.id):
			cands.append([{"kind": "weapon_up", "id": w.id, "name": w.data.name, "desc": describe_up(w.data, w.level + 1), "level_text": Loc.t("lvl_n", [w.level + 1])}, 1.3])
	if ws.list.size() < MAX_WEAPONS:
		for id in Data.weapon_pool(run.character):
			if ws.has(id) or run.banished.has(id): continue
			if run.union_parts_used.has(id): continue
			var d: Dictionary = Data.weapons[id]
			cands.append([{"kind": "weapon_new", "id": id, "name": d.name, "desc": d.desc, "level_text": Loc.t("new")}, 0.9])
	for id in run.passives:
		var p: Dictionary = Data.passives[id]
		if int(run.passives[id]) < int(p.max_level) and not run.banished.has(id):
			cands.append([{"kind": "passive_up", "id": id, "name": p.name, "desc": p.desc, "level_text": Loc.t("lvl_n", [int(run.passives[id]) + 1])}, 1.0])
	if run.passives.size() < MAX_PASSIVES:
		for p in Data.passive_list:
			if run.passives.has(p.id) or run.banished.has(p.id): continue
			if p.get("saga", false) and not Save.is_unlocked("passives", p.id): continue   # won in the Modo Saga
			# rarer items (those with 9 levels or special effects) show up more with luck
			var wgt := 0.8 if int(p.max_level) <= 5 else 0.35 * float(run.stats.luck)
			cands.append([{"kind": "passive_new", "id": p.id, "name": p.name, "desc": p.desc, "level_text": Loc.t("new")}, wgt])
	var out: Array = []
	while out.size() < n and cands.size() > 0:
		var total := 0.0
		for c in cands: total += c[1]
		var r := randf() * total
		for k in cands.size():
			r -= cands[k][1]
			if r <= 0.0 or k == cands.size() - 1:
				out.append(cands[k][0])
				cands.remove_at(k)
				break
	if out.is_empty():
		out.append({"kind": "heal", "id": "catering", "name": Loc.t("opt_heal"), "desc": Loc.t("opt_heal_d"), "level_text": ""})
		out.append({"kind": "coins", "id": "coin", "name": Loc.t("opt_coins"), "desc": Loc.t("opt_coins_d"), "level_text": ""})
	return out

## How many choices: 3, sometimes 4 with good luck.
static func option_count(run) -> int:
	return 4 if randf() < (float(run.stats.luck) - 1.0) * 0.8 + 0.05 else 3

static func apply(run, o: Dictionary) -> void:
	match o.kind:
		"weapon_up": run.weapons.level_up(o.id)
		"weapon_new": run.weapons.add(o.id)
		"passive_up", "passive_new":
			run.passives[o.id] = int(run.passives.get(o.id, 0)) + 1
			run.rebuild_stats()
			if Data.passives[o.id].stat == "max_hp": run.heal(20.0)
		"heal": run.heal(30.0)
		"coins": run.add_coins(25)

# ---------- latas de película ----------
## Number of rewards in a lata: 1, 3 or 5 (better odds with Suerte).
static func chest_size(run) -> int:
	var l := float(run.stats.luck)
	var r := randf()
	if r < 0.04 * l: return 5
	if r < 0.04 * l + 0.18 * l: return 3
	return 1

static func can_evolve(run, w: Dictionary) -> bool:
	if w.evolved or w.data.source == "union": return false
	if w.level < int(w.data.max_level): return false
	if run.time < 600.0 and not run.debug_evolve_anytime: return false   # minute 10 or later, as in the genre
	var req: String = w.data.evolution.get("requires", "")
	return req == "" or run.passives.has(req)

## Union ready when every weapon of it is maxed (or evolved) and its passives are owned.
static func ready_union(run) -> Dictionary:
	for u in Data.unions:
		if run.weapons.has(u.id): continue
		var ok := true
		for wid in u.weapons:
			var w = run.weapons.get_w(wid)
			if w == null or (w.level < int(w.data.max_level) and not w.evolved): ok = false
		for pid in u.passives:
			if not run.passives.has(pid): ok = false
		if ok and (run.time >= 600.0 or run.debug_evolve_anytime): return u
	return {}

## Open a lata: returns the list of rewards given (for the reveal screen).
static func open_chest(run, n: int) -> Array:
	var got: Array = []
	for k in n:
		var u := ready_union(run)
		if not u.is_empty():
			for wid in u.weapons:
				var w = run.weapons.get_w(wid)
				run.weapons.list.erase(w)
				run.union_parts_used[wid] = true
			var nw: Dictionary = run.weapons.add(u.id)
			nw.level = int(nw.data.max_level)
			nw.evolved = true
			run.weapons.recompute(nw)
			run.evolutions += 1
			run.evolved_ids.append(u.id)
			got.append({"kind": "union", "id": u.id, "name": u.name, "desc": u.desc})
			continue
		var evolved := false
		for w in run.weapons.list:
			if can_evolve(run, w):
				run.weapons.evolve(w.id)
				run.evolutions += 1
				run.evolved_ids.append(w.id)
				got.append({"kind": "evolve", "id": w.id, "icon": w.data.evolution.id, "name": w.data.evolution.name, "desc": w.data.evolution.desc})
				evolved = true
				break
		if evolved: continue
		if run.curse:
			for w in run.weapons.list:
				if run.curse.remaster(w):
					got.append({"kind": "evolve", "id": w.id, "icon": w.data.evolution.id, "name": Loc.t("gm_remaster", [w.data.evolution.name]), "desc": Loc.t("gm_remaster_desc")})
					evolved = true
					break
		if evolved: continue
		var ups: Array = []
		for w in run.weapons.list:
			if w.level < run.weapon_cap(w): ups.append({"kind": "weapon_up", "id": w.id, "name": w.data.name, "desc": describe_up(w.data, w.level + 1)})
		for id in run.passives:
			if int(run.passives[id]) < int(Data.passives[id].max_level): ups.append({"kind": "passive_up", "id": id, "name": Data.passives[id].name, "desc": Data.passives[id].desc})
		if ups.is_empty():
			run.add_coins(50)
			got.append({"kind": "coins", "id": "coin", "name": Loc.t("opt_coins"), "desc": "+50"})
		else:
			var o: Dictionary = ups[randi() % ups.size()]
			apply(run, o)
			got.append(o)
	return got
