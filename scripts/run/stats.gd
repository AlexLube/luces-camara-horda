class_name Stats
extends RefCounted
## Player statistics for a run: base values + character bonus + Cláusulas + passive items.
## Percent stats are stored as multipliers (1.0 = base); flat stats as numbers.

const BASE := {
	"max_hp": 1.0, "armor": 0.0, "regen": 0.0, "power": 1.0, "cooldown": 1.0, "area": 1.0, "speed": 1.0,
	"duration": 1.0, "amount": 0.0, "magnet": 1.0, "luck": 1.0, "growth": 1.0, "greed": 1.0, "curse": 1.0,
	"proj_speed": 1.0, "revival": 0.0, "lifesteal": 0.0, "crit": 0.03, "freeze_time": 1.0, "boss_damage": 1.0,
	"rerolls": 0.0, "skips": 0.0, "banishes": 0.0, "charm": 0.0, "harmless": 0.0, "seals": 0.0,
}
const FLAT := ["armor", "regen", "amount", "revival", "lifesteal", "crit", "rerolls", "skips", "banishes", "charm", "harmless", "seals"]
const BASE_HP := 100.0
const BASE_SPEED := 210.0
const BASE_MAGNET := 100.0

static func add(s: Dictionary, stat: String, v: float) -> void:
	if not s.has(stat): return
	s[stat] += v  # multipliers add percentages (+0.1 => 1.1), flat stats add numbers

## passive_levels: id -> level. player_level: for items that scale with level.
static func build(character: Dictionary, passive_levels: Dictionary, clause_bonus: Dictionary, player_level := 1, extra := {}) -> Dictionary:
	var s := BASE.duplicate()
	for k in clause_bonus: add(s, k, float(clause_bonus[k]))
	for k in character.get("mods", {}): add(s, k, float(character.mods[k]))
	for id in passive_levels:
		var p: Dictionary = Data.passives.get(id, {})
		var lvl := int(passive_levels[id])
		if p.is_empty() or lvl <= 0: continue
		match p.stat:
			"shield", "union_part": pass
			"turbo":   # Modo Saga reward
				s.speed += 0.08 * lvl
				s.cooldown -= 0.04 * lvl
			"rerolls_skips":
				s.rerolls += lvl
				s.skips += lvl
			"max_hp_per_level": s.max_hp += 0.01 * player_level * lvl
			"regen_per_level": s.regen += 0.01 * player_level * lvl
			"all_then_curse":
				var up: int = min(lvl, 7)
				for k in ["power", "area", "speed", "duration", "luck", "growth", "greed", "magnet"]: s[k] += 0.02 * up
				if lvl > 7: s.curse += 0.1 * (lvl - 7)
			_:
				if p.per_level != null: add(s, p.stat, float(p.per_level) * lvl)
	for k in extra: add(s, k, float(extra[k]))   # Guiones and other run-wide effects
	s.hp_max = 100.0 * max(0.1, s.max_hp)
	s.cooldown = max(0.2, s.cooldown)
	s.move_speed = BASE_SPEED * s.speed
	s.magnet_radius = BASE_MAGNET * s.magnet
	return s
