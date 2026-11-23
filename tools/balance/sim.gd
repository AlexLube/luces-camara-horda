extends Node
## Balance simulator: plays one run with the autopilot (no health cheats) and prints a JSON line.
##   godot --headless --path . res://tools/balance/sim.tscn -- --stage=<id> --char=<id> [--clauses=max] [--mods=a,b]

func _ready() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		opt[kv[0]] = kv[1] if kv.size() > 1 else ""
	Save.data = Save.defaults()
	if opt.get("clauses", "") == "max":
		for c in Data.clauses: Save.data.clauses[c.id] = int(c.max_level)
	Save.data.unlocked.relics.append_array(["silla_del_director", "claqueta_de_oro", "espejo_de_camerino"])
	Save.data.mods_on = Array(opt.get("mods", "").split(",", false))
	var r := Run.new()
	r.setup(Data.char_by_id[opt.get("char", "max_rios")], Data.stage_by_id[opt.get("stage", "bosque_de_la_cabana")])
	r.bot = true
	add_child(r)
	r.set_process(false)
	var marks := {}
	var dt := 1.0 / 20.0
	var low_hp := 1.0
	while r.time < r.duration + 2.0 and r.state != "over":
		r.step(dt)
		low_hp = minf(low_hp, r.hp / float(r.stats.hp_max))
		if opt.has("trace") and r.hp < float(r.stats.hp_max) * 0.5 and not marks.has(-999):
			marks[-999] = true
			var near := {}
			for i in r.enemies.query_circle(r.player_pos.x, r.player_pos.y, 60.0, r._q): near[r.enemies.type[i]] = int(near.get(r.enemies.type[i], 0)) + 1
			print("T half hp at %.1f s, touching types %s, bullets %d, warnings %d" % [r.time, str(near), r.ebullets.size(), r.boss_ai.warnings.size()])
		var m := int(r.time / 60.0)
		if opt.has("trace") and m % 2 == 0 and not marks.has(-m - 1):
			marks[-m - 1] = true
			print("T m%d lvl %d st %s kills %d en %d gems %d xp %d hp %d pos %s w %s" % [m, r.level, r.state, r.kills, r.enemies.count, r.gem_count, int(r.xp), int(r.hp), str(r.player_pos.round()), str(r.weapons.list.map(func(w): return "%s%d" % [w.id, w.level]))])
		if m % 5 == 0 and not marks.has(m): marks[m] = {"lvl": r.level, "kills": r.kills, "enemies": r.enemies.count, "w": r.weapons.list.size(), "p": r.passives.size()}
	var coins := int(round(r.coins))
	var earned: int = r.taquilla_earned()
	print("BAL " + JSON.stringify({"stage": r.stage.id, "char": r.character.id, "clauses": opt.get("clauses", "0"), "mods": opt.get("mods", ""),
		"time": snappedf(r.time, 1.0), "done": r.completed, "level": r.level, "kills": r.kills, "coins": coins, "earned": earned,
		"chests": r.chests, "evo": r.evolutions, "low_hp": snappedf(low_hp, 0.01), "marks": marks.keys().filter(func(k): return k >= 0).reduce(func(acc, k): acc[str(k)] = marks[k]; return acc, {})}))
	get_tree().quit()
