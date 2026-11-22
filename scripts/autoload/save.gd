extends Node
## Persistent profile: Taquilla, Cláusulas del Contrato, unlocks, lifetime stats, achievements and options.
## Written to user://save.json with a backup copy; saved after every run and every menu change.

const PATH := "user://save.json"
const BACKUP := "user://save.bak.json"
const VERSION := 1

var data := {}

func _ready() -> void:
	load_game()

func defaults() -> Dictionary:
	var chars: Array = []
	for c in Data.characters:
		if c.unlock == "Inicial": chars.append(c.id)
	return {
		"version": VERSION,
		"taquilla": 0,
		"clauses": {},          # id -> level bought
		"clauses_off": {},      # id -> true when the player switched a maxed clause off
		"unlocked": {"characters": chars, "hired": chars.duplicate(), "stages": [Data.stages[0].id], "relics": [], "weapons": []},
		"stats": {"kills": 0, "deaths": 0, "runs": 0, "chests": 0, "coins": 0, "food": 0, "evolutions": 0, "evolved": [],
			"bosses": 0, "max_level": 0, "taquilla_total": 0, "time": 0.0, "survived": {}, "completed": [], "played": [], "productor": 0},
		"achievements": [],
		"options": {"lang": "es", "sfx": 0.8, "music": 0.7, "fullscreen": false, "shake": true, "flashes": true, "damage_numbers": true, "binds": {}},
		"last": {"character": chars[0] if chars.size() > 0 else "max_rios", "stage": Data.stages[0].id},
	}

func load_game() -> void:
	data = defaults()
	for p in [PATH, BACKUP]:
		if not FileAccess.file_exists(p): continue
		var f := FileAccess.open(p, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_merge(data, d)
			break
	apply_options()

## Keep new default keys when loading an older save.
func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary and k not in ["clauses", "clauses_off", "survived", "binds"]:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]

func save_game() -> void:
	var txt := JSON.stringify(data, "\t")
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(BACKUP))
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(txt)

func apply_options() -> void:
	var o: Dictionary = data.options
	Loc.set_lang(o.lang)
	Sfx.volume = o.sfx
	Music.volume = o.music
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if o.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

# ---------- Cláusulas del Contrato ----------
func clause_level(id: String) -> int:
	return int(data.clauses.get(id, 0))

func total_clause_levels() -> int:
	var n := 0
	for k in data.clauses: n += int(data.clauses[k])
	return n

func clause_price(c: Dictionary) -> int:
	# price grows with the clause's own level and with everything bought so far, as in the genre
	return int(c.base_price * (clause_level(c.id) + 1) + 20 * total_clause_levels())

func buy_clause(c: Dictionary) -> bool:
	var lvl := clause_level(c.id)
	var price := clause_price(c)
	if lvl >= int(c.max_level) or int(data.taquilla) < price: return false
	data.taquilla = int(data.taquilla) - price
	data.clauses[c.id] = lvl + 1
	data.spent = int(data.get("spent", 0)) + price
	save_game()
	return true

func refund_clauses() -> void:
	data.taquilla = int(data.taquilla) + int(data.get("spent", 0))
	data.spent = 0
	data.clauses = {}
	data.clauses_off = {}
	save_game()

func toggle_clause(id: String) -> void:
	data.clauses_off[id] = not data.clauses_off.get(id, false)
	save_game()

## Sum of active clause bonuses, by stat name.
func clause_bonus() -> Dictionary:
	var b := {}
	for c in Data.clauses:
		var l := clause_level(c.id)
		if l == 0 or data.clauses_off.get(c.id, false): continue
		b[c.stat] = b.get(c.stat, 0.0) + float(c.per_level) * l
	return b

# ---------- unlocks ----------
func is_unlocked(kind: String, id: String) -> bool:
	return id in data.unlocked[kind]

func unlock(kind: String, id: String) -> bool:
	if id in data.unlocked[kind]: return false
	data.unlocked[kind].append(id)
	return true

func hire_price(c: Dictionary) -> int:
	return 0 if c.unlock == "Inicial" else 300 + 60 * int(c.num)

func hire(c: Dictionary) -> bool:
	if not is_unlocked("characters", c.id) or is_unlocked("hired", c.id): return false
	var p := hire_price(c)
	if int(data.taquilla) < p: return false
	data.taquilla = int(data.taquilla) - p
	data.unlocked.hired.append(c.id)
	save_game()
	return true
