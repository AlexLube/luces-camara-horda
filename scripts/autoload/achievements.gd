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
		if _met(a.cond, run) or (a.cond.type == "manual" and secret_met(a.id, run)):
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
	return false  # "manual": see secret_met

## The hidden feats behind the «manual» Premios (secret characters and stages).
func secret_met(id: String, run: Dictionary = {}) -> bool:
	var s: Dictionary = Save.data.stats
	var relic := func(r): return Save.is_unlocked("relics", r)
	match id:
		"unlock_sam_shade": return relic.call("gabardina")
		"unlock_cutter_vega": return relic.call("tijeras_de_plata")
		"unlock_broadway_en_llamas": return relic.call("gramofono")
		"unlock_fotograma_0": return relic.call("bobina_0")
		"unlock_coco_banana": return int(s.get("trips", 0)) >= 1000
		"unlock_jack_nitro": return int(s.get("distance", 0)) >= 50000 * PX_PER_M
		"unlock_sully_pluma": return int(run.get("chests", 0)) >= 5
		"unlock_grip_martinez": return int(s.get("crates", 0)) >= 100
		"unlock_bill_mecha": return int(s.get("barrels", 0)) >= 500
		"unlock_toni_nitrato": return int(s.get("fires", 0)) >= 100
		"unlock_archie_polvo", "unlock_la_sala_de_montaje":
			var n := 0
			for k in range(1, 8): n += int(relic.call("bobina_perdida_%d" % k))
			return n >= (3 if id == "unlock_archie_polvo" else 7)
		"unlock_sor_melodia": return s.get("flawless_broadway", false)
		"unlock_el_extra": return int(s.get("early_deaths", 0)) >= 3
		"unlock_el_montador": return int(s.get("bestiary", {}).get("la_sala_de_montaje", {}).get("boss", 0)) > 0
		"unlock_claqui": return "claqui" in s.get("codes", [])
		"unlock_michi_del_estudio": return int(s.get("pets", 0)) >= 10
		"unlock_el_doble_del_doble": return int(s.get("completed_by", {}).get("max_rios", 0)) >= 10
		"unlock_el_cinefilo": return bestiary_done()
		"unlock_neon_2099": return "estacion_orbital_zeta" in s.get("dc_completed", [])
	return false

const PX_PER_M := 20

## The Catálogo is complete when every jefe of the base game (festivals aside) has fallen.
func bestiary_done() -> bool:
	var b: Dictionary = Save.data.stats.get("bestiary", {})
	for st in Data.stages:
		if st.kind == "festival": continue
		if int(b.get(st.id, {}).get("boss", 0)) <= 0: return false
	return true

func _steam(id: String) -> void:
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		steam.setAchievement(id)
		steam.storeStats()
