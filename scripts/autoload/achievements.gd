extends Node
## "Premios de la Academia del Juego": checks achievement conditions against lifetime stats and
## a finished run, grants their rewards (characters, stages) and mirrors them to Steam when present.

signal unlocked(ach: Dictionary)

func has(id: String) -> bool:
	return id in Save.data.achievements

## Check every locked achievement. `run` is the summary of the run that just ended (may be empty).
func check(run: Dictionary = {}) -> Array:
	var got: Array = []
	for a in Data.achievements:
		if has(a.id): continue
		if _met(a.cond, run):
			Save.data.achievements.append(a.id)
			if a.reward.has("character"): Save.unlock("characters", a.reward.character)
			if a.reward.has("stage"): Save.unlock("stages", a.reward.stage)
			got.append(a)
			unlocked.emit(a)
			_steam(a.id)
	if got.size() > 0: Save.save_game()
	return got

func _met(c: Dictionary, run: Dictionary) -> bool:
	var s: Dictionary = Save.data.stats
	match c.type:
		"initial": return true
		"survive":
			if c.stage == null:
				var best := 0.0
				for k in s.survived: best = max(best, float(s.survived[k]))
				return best >= c.minutes
			return float(s.survived.get(c.stage, 0)) >= c.minutes
		"level": return int(s.max_level) >= c.value
		"evolutions": return int(s.evolutions) >= c.value
		"evolve": return c.weapon in s.evolved
		"kills": return int(s.kills) >= c.value
		"bosses": return int(s.bosses) >= c.value
		"deaths": return int(s.deaths) >= c.value
		"chests": return int(s.chests) >= c.value
		"coins": return int(s.coins) >= c.value
		"food": return int(s.food) >= c.value
		"taquilla_total": return int(s.taquilla_total) >= c.value
		"complete": return c.stage in s.completed
		"play": return c.stage in s.played
		"weapons_unlocked": return Save.data.unlocked.weapons.size() >= c.value
		"productor": return int(s.productor) > 0
	if c.type == "manual" and String(c.get("text", "")).begins_with("Recoger las 7 bobinas perdidas"):
		for k in range(1, 8):
			if not Save.is_unlocked("relics", "bobina_perdida_%d" % k): return false
		return true
	return false  # "manual": needs content from later phases (relics, secrets)

func _steam(id: String) -> void:
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		steam.setAchievement(id)
		steam.storeStats()
