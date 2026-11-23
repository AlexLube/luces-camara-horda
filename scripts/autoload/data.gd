extends Node
## Game content loaded from data/*.json (built from the design catalogue by tools/data/build_data.py).

var weapons := {}
var weapon_list: Array = []
var passives := {}
var passive_list: Array = []
var unions: Array = []
var clauses: Array = []
var characters: Array = []
var char_by_id := {}
var stages: Array = []
var stage_by_id := {}
var relics: Array = []
var guiones: Array = []
var modifiers: Array = []
var achievements: Array = []
var art_sets := {}
var evolution_of := {}             # evolution id -> base weapon id
var relic_by_id := {}
var sagas: Array = []
var saga_by_id := {}
var _tex := {}

func _ready() -> void:
	weapon_list = _load("weapons")
	for w in weapon_list: weapons[w.id] = w
	passive_list = _load("passives")
	for p in passive_list: passives[p.id] = p
	unions = _load("unions")
	clauses = _load("clauses")
	characters = _load("characters")
	for c in characters: char_by_id[c.id] = c
	stages = _load("stages")
	for s in stages: stage_by_id[s.id] = s
	relics = _load("relics")
	for r in relics: relic_by_id[r.id] = r
	for w in weapon_list:
		if w.has("evolution"): evolution_of[w.evolution.id] = w.id
	guiones = _load("guiones")
	modifiers = _load("modifiers")
	achievements = _load("achievements")
	art_sets = _load("art_sets")
	sagas = _load("sagas")
	for sg in sagas: saga_by_id[sg.id] = sg
	_make_union_weapons()

## Each Unión becomes a weapon of its own: the first weapon's behaviour, evolved numbers of both,
## and it replaces the weapons that formed it (see Upgrades.try_union).
func _make_union_weapons() -> void:
	for u in unions:
		var parts: Array = []
		for wid in u.weapons:
			if weapons.has(wid): parts.append(weapons[wid])
		if parts.is_empty(): continue
		var first: Dictionary = parts[0]
		var base: Dictionary = first.base.duplicate()
		for extra in parts.slice(1):
			for k in extra.base:
				if not base.has(k) and k not in ["damage", "cooldown", "area", "amount"]: base[k] = extra.base[k]
		var mods: Dictionary = first.evolution.mods.duplicate()
		mods["damage"] = float(mods.get("damage", 1.4)) * 1.5
		mods["amount_add"] = int(mods.get("amount_add", 0)) + 1
		var w := {"id": u.id, "name": u.name, "desc": u.desc, "archetype": first.archetype, "base": base,
			"levels": first.levels, "max_level": first.max_level, "source": "union", "parts": u.weapons, "parts_passives": u.passives,
			"evolution": {"id": u.id, "name": u.name, "desc": u.desc, "requires": "", "mods": mods}}
		weapons[u.id] = w

## Taquilla bonus of each modifier (fraction), the ones that can be switched on, and what unlocks each.
const MOD_BONUS := {"maraton": 0.0, "guiones": 0.0, "toma_rapida": 0.5, "fuera_de_plazo": 0.5, "sin_limite": 0.5, "negativo": 1.0, "imprevistos_de_rodaje": 0.25, "cine_mudo": 0.3}

func modifier_ready(m: Dictionary) -> bool:
	return MOD_BONUS.has(m.id)

func modifier_unlocked(m: Dictionary) -> bool:
	if m.id == "cine_mudo": return "archivo_de_cine_mudo" in Save.data.stats.completed
	if m.id == "maraton": return Save.is_unlocked("relics", "silla_del_director")
	for r in relics:
		if r.name == m.relic: return Save.is_unlocked("relics", r.id)
	return false

func guion_icon(id: String) -> Texture2D:
	return tex("res://assets/sprites/guiones/%s.png" % id)

## Relics hidden in a stage (their "where" is the stage name).
func relics_at(stage: Dictionary) -> Array:
	var out: Array = []
	for r in relics:
		if r.where == stage.get("name", ""): out.append(r)
	return out

## Relics earned by finishing a number of stages ("Completar N escenarios").
func relics_for_completions(done: int) -> Array:
	var out: Array = []
	for r in relics:
		var m := RegEx.create_from_string("^Completar (\\d+) escenarios$").search(r.where)
		if m and done >= int(m.get_string(1)): out.append(r)
	return out

## Modo Saga opens with the Bobina Dorada. The Retrospectiva needs every other saga finished.
func saga_mode_open() -> bool:
	return Save.is_unlocked("relics", "bobina_dorada")

func saga_progress(sg: Dictionary) -> int:
	return int(Save.data.saga.get(sg.id, 0))

func saga_open(sg: Dictionary) -> bool:
	if not saga_mode_open(): return false
	if sg.rule != "mezcla": return true
	for o in sagas:
		if o.rule != "mezcla" and saga_progress(o) < o.phases.size(): return false
	return true

## Give the saga's reward once: a relic, a weapon, a passive or a character (hired for free).
func grant_saga_reward(sg: Dictionary) -> String:
	var r: Dictionary = sg.reward
	match r.kind:
		"relic": Save.unlock("relics", r.id)
		"weapon": Save.unlock("weapons", r.id)
		"passive": Save.unlock("passives", r.id)
		"character":
			Save.unlock("characters", r.id)
			Save.unlock("hired", r.id)
	if r.id not in Save.data.saga_rewards: Save.data.saga_rewards.append(r.id)
	return r.name

func _load(name: String) -> Variant:
	var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
	if f == null:
		push_error("Missing data file: " + name)
		return []
	return JSON.parse_string(f.get_as_text())

## Cached texture by res:// path; null if missing.
func tex(path: String) -> Texture2D:
	if _tex.has(path): return _tex[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[path] = t
	return t

func icon_for(id: String) -> Texture2D:
	var map := {"claqueta":"i_clap", "rollo_de_pelicula":"i_reel", "palomitas":"i_pop", "foco":"i_spot", "camara_de_flash":"i_camera",
		"ego_de_estrella":"i_ego", "cafe_solo":"i_cafe", "zapatillas_de_claque":"i_shoes", "microfono_inalambrico":"i_mic",
		"batido_de_proteinas":"i_shake", "guion_anotado":"i_script"}
	if map.has(id): return tex("res://assets/sprites/icons/%s.png" % map[id])
	var path := "res://assets/sprites/icons/%s.png" % id
	if ResourceLoader.exists(path): return tex(path)
	# a Unión shows the icon of its first weapon
	if weapons.has(id) and weapons[id].has("parts"): return icon_for(weapons[id].parts[0])
	if evolution_of.has(id): return icon_for(evolution_of[id])
	return null

## Weapons that can appear in level-up for this profile: base list, unlocked festival weapons, the character's own.
func weapon_pool(character: Dictionary) -> Array:
	var out: Array = []
	for w in weapon_list:
		if w.source == "base" or Save.is_unlocked("weapons", w.id) or w.id == character.get("weapon", ""): out.append(w.id)
	return out

## First frame of a character's idle animation, for menus (falls back to Max Ríos).
## Full-body casting portrait (Gemini art); falls back to the first idle frame.
func portrait(id: String) -> Texture2D:
	var pp := "res://assets/sprites/characters/%s/portrait.png" % id
	if ResourceLoader.exists(pp): return tex(pp)
	return sprite_frame(id)

func has_portrait(id: String) -> bool:
	return ResourceLoader.exists("res://assets/sprites/characters/%s/portrait.png" % id)

## First idle frame of a character's sprite sheet.
func sprite_frame(id: String) -> Texture2D:
	var path := "res://assets/sprites/characters/%s/idle.png" % id
	var t: Texture2D = tex(path) if ResourceLoader.exists(path) else tex("res://assets/sprites/player/player_idle.png")
	if t == null: return null
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Rect2(0, 0, t.get_width() / 4, t.get_height())
	return a

## First frame of a sprite sheet (bestiary pictures).
func first_frame(path: String, frames: int) -> Texture2D:
	var t := tex(path)
	if t == null: return null
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Rect2(0, 0, t.get_width() / max(1, frames), t.get_height())
	return a

func stage_art(stage: Dictionary) -> Dictionary:
	return art_sets.get(stage.get("art", "forest"), art_sets["forest"])
