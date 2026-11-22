extends Node
## Headless test runner:
##   godot --headless --path . res://tests/tests.tscn
## Checks data, stats, save, shop, every weapon, level-up, chests, evolutions, unions, achievements,
## a 1000+ enemy performance budget and a full simulated 30-minute run. Exit code 1 on any failure.

var fails := 0
var passes := 0
var saved_profile := {}

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("  FAIL: ", what)

func _ready() -> void:
	saved_profile = Save.data.duplicate(true)
	Save.data = Save.defaults()
	Sfx.volume = 0.0
	var quick := "--quick" in OS.get_cmdline_user_args()
	for t in ["t_data", "t_stats", "t_save", "t_clauses", "t_weapons", "t_levelup", "t_chest_evolution", "t_union", "t_relics", "t_modifiers", "t_achievements", "t_bosses", "t_perf"]:
		print("· ", t)
		await call(t)
	if not quick:
		print("· t_full_run")
		await t_full_run()
	Save.data = saved_profile
	Save.save_game()
	print("\n%d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func new_run(char_id := "max_rios", stage_id := "bosque_de_la_cabana") -> Run:
	var r := Run.new()
	r.setup(Data.char_by_id[char_id], Data.stage_by_id[stage_id])
	r.bot = true
	add_child(r)
	r.set_process(false)
	return r

func t_data() -> void:
	ok(Data.passive_list.size() == 26, "26 passives (got %d)" % Data.passive_list.size())
	ok(Data.weapon_list.size() == 54, "54 weapons (got %d)" % Data.weapon_list.size())
	ok(Data.unions.size() == 8, "8 unions")
	ok(Data.clauses.size() == 22, "22 clauses")
	ok(Data.characters.size() == 96, "96 characters")
	ok(Data.stages.size() == 34, "34 stages")
	ok(Data.achievements.size() >= 100, "achievements list")
	for w in Data.weapon_list:
		ok(int(w.max_level) == 8 and w.levels.size() == 7, "8 levels: " + w.id)
		ok(Data.passives.has(w.evolution.requires) or w.evolution.requires == "", "evolution passive exists: " + w.id)
	for s in Data.stages: ok(Data.art_sets.has(s.get("art", "")), "art set for " + s.id)
	var with_art := 0
	for k in Data.art_sets:
		var a: Dictionary = Data.art_sets[k]
		var base := "res://assets/sprites/stages/%s/" % k
		var files := ["enemy.png", "tank.png", "boss.png", "ground.jpg", str(a.get("land", "")) + ".png"]
		for p in a.props: files.append(str(p[0]) + ".png")
		var all_ok := true
		for f in files: all_ok = all_ok and ResourceLoader.exists(base + f)
		ok(all_ok, "all sprites for art set " + k)
	for s in Data.stages: if s.get("art", "forest") != "forest" or s.num == 1: with_art += 1
	ok(with_art >= 12, "stages 1-12 have their own art (%d)" % with_art)
	ok(ResourceLoader.exists("res://assets/sprites/productor/productor.png"), "productor sprite")
	for id in weapons_and_items(): ok(Data.icon_for(id) != null, "icon for " + id)
	for c in Data.characters.slice(0, 96): ok(ResourceLoader.exists("res://assets/sprites/characters/%s/run.png" % c.id) or c.id == "max_rios", "sprite for " + c.id)
	for k in Loc._s: ok(Loc._s[k].has("en") and Loc._s[k].has("es"), "ES/EN string " + k)

func weapons_and_items() -> Array:
	return Data.weapons.keys() + Data.passives.keys()

func t_stats() -> void:
	var s := Stats.build(Data.char_by_id.max_rios, {}, {}, 1)
	ok(is_equal_approx(s.hp_max, 120.0), "Max Ríos +20%% hp → 120 (got %s)" % s.hp_max)
	ok(is_equal_approx(s.armor, 1.0), "Max Ríos +1 armor")
	var s2 := Stats.build(Data.characters[0], {"ego_de_estrella": 5, "cafe_solo": 5}, {"power": 0.25}, 1)
	ok(is_equal_approx(s2.power, 1.75), "power stacks: 1 + 0.5 + 0.25")
	ok(is_equal_approx(s2.cooldown, 0.6), "cooldown -40%%")
	var s3 := Stats.build(Data.characters[0], {"caja_de_atrezo_maldita": 9}, {}, 1)
	ok(s3.curse > 1.0 and s3.power > 1.0, "atrezo maldito: everything up, then curse")

func t_save() -> void:
	Save.data.taquilla = 1234
	Save.data.stats.kills = 77
	Save.save_game()
	Save.data = {}
	Save.load_game()
	ok(int(Save.data.taquilla) == 1234 and int(Save.data.stats.kills) == 77, "save round trip")
	ok(FileAccess.file_exists(Save.BACKUP), "backup written")

func t_clauses() -> void:
	Save.data = Save.defaults()
	Save.data.taquilla = 5000
	var c: Dictionary = Data.clauses[0]
	var p1 := Save.clause_price(c)
	ok(Save.buy_clause(c), "buy clause")
	ok(Save.clause_price(c) > p1, "price grows")
	ok(is_equal_approx(float(Save.clause_bonus().get(c.stat, 0.0)), float(c.per_level)), "bonus applied")
	Save.refund_clauses()
	ok(int(Save.data.taquilla) == 5000, "refund gives everything back")
	var hire_me: Dictionary = {}
	for ch in Data.characters:
		if ch.unlock != "Inicial":
			hire_me = ch
			break
	ok(not Save.hire(hire_me), "cannot hire a locked character")
	Save.unlock("characters", hire_me.id)
	ok(Save.hire(hire_me), "hire after unlock")

func t_weapons() -> void:
	var r := new_run()
	for k in 80: r.director.spawn(EnemyPool.T.HORDE, r.player_pos + Vector2(randf_range(-400, 400), randf_range(-300, 300)))
	var ids: Array = Data.weapons.keys()
	for id in ids:
		r.weapons.list.clear()
		var w: Dictionary = r.weapons.add(id)
		for l in 7: r.weapons.level_up(id)
		ok(w.level == 8, "level 8: " + id)
		var d0: float = w.p.damage
		r.weapons.evolve(id)
		ok(w.p.damage >= d0 or w.data.source == "union", "evolution not weaker: " + id)
		for f in 40:
			r.step(1.0 / 30.0)
			r.hp = 9999.0
		while r.enemies.count < 80: r.director.spawn(EnemyPool.T.HORDE)
	ok(r.kills > 0, "weapons kill enemies (%d kills)" % r.kills)
	r.queue_free()
	await get_tree().process_frame

func t_levelup() -> void:
	var r := new_run()
	var o := Upgrades.roll(r, 4)
	ok(o.size() == 4, "4 options")
	var ids := {}
	for x in o: ids[x.id] = true
	ok(ids.size() == 4, "options are distinct")
	r.bot = false
	r.stats.banishes = 1
	r.stats.rerolls = 1
	r.stats.skips = 1
	r.pending_levels = 3
	r.open_levelup()
	ok(r.state == "levelup", "level-up opens")
	r.do_banish(o[0])
	ok(r.banished.has(o[0].id) and r.banishes_left() == 0, "banish")
	r.do_reroll()
	ok(r.rerolls_left() == 0, "reroll spent")
	r.do_skip()
	ok(r.pending_levels == 2, "skip consumes a level")
	r.choose(Upgrades.roll(r, 3)[0])
	r.choose(Upgrades.roll(r, 3)[0])
	ok(r.state == "play", "back to play after choices")
	for k in 30:
		Upgrades.apply(r, Upgrades.roll(r, 3)[0])
	ok(r.weapons.list.size() <= 6 and r.passives.size() <= 6, "6 weapon and 6 item slots")
	r.queue_free()
	await get_tree().process_frame

func t_chest_evolution() -> void:
	var r := new_run()
	var w: Dictionary = r.weapons.list[0]
	for l in 7: r.weapons.level_up(w.id)
	r.passives[w.data.evolution.requires] = 1
	r.rebuild_stats()
	r.time = 300.0
	ok(not Upgrades.can_evolve(r, w), "no evolution before minute 10")
	r.time = 601.0
	ok(Upgrades.can_evolve(r, w), "evolution ready at lvl 8 + passive + minute 10")
	var got := Upgrades.open_chest(r, 1)
	ok(got[0].kind == "evolve" and w.evolved, "lata evolves the weapon")
	var sizes := {1: 0, 3: 0, 5: 0}
	for k in 2000: sizes[Upgrades.chest_size(r)] += 1
	ok(sizes[1] > sizes[3] and sizes[3] > sizes[5] and sizes[5] > 0, "latas 1/3/5 odds %s" % str(sizes))
	r.queue_free()
	await get_tree().process_frame

func t_union() -> void:
	var r := new_run()
	r.weapons.list.clear()
	var u: Dictionary = Data.unions[0]
	for wid in u.weapons:
		r.weapons.add(wid)
		for l in 7: r.weapons.level_up(wid)
	r.time = 700.0
	var got := Upgrades.open_chest(r, 1)
	ok(got[0].kind == "union" and r.weapons.has(u.id), "union created: " + u.id)
	for wid in u.weapons: ok(not r.weapons.has(wid), "union consumed " + wid)
	r.queue_free()
	await get_tree().process_frame

func t_relics() -> void:
	for w in Data.weapon_list: ok(ResourceLoader.exists("res://assets/sprites/icons/%s.png" % w.evolution.id), "evolution icon " + w.evolution.id)
	for u in Data.unions: ok(ResourceLoader.exists("res://assets/sprites/icons/%s.png" % u.id), "union icon " + u.id)
	for r in Data.relics: ok(ResourceLoader.exists("res://assets/sprites/icons/%s.png" % r.id), "relic icon " + r.id)
	ok(Data.relics_at(Data.stage_by_id.bosque_de_la_cabana).any(func(x): return x.id == "mapa_de_localizaciones"), "the map hides in the first stage")
	ok(Data.relics_for_completions(4).is_empty() and Data.relics_for_completions(5).size() == 1, "director's chair after 5 stages")
	var r := new_run()
	var rel: Array = r.relic_pickups()
	ok(rel.size() == 1 and Vector2(rel[0].x, rel[0].y).length() > 1300.0, "relic placed far from the start")
	r.bot = false
	r._collect(rel[0])
	ok(Save.is_unlocked("relics", "mapa_de_localizaciones") and r.found_relics == ["mapa_de_localizaciones"], "picking a relic saves it")
	r.queue_free()
	await get_tree().process_frame
	var r2 := new_run()
	r2.bot = false
	r2._place_relics()
	ok(r2.relic_pickups().size() == 1, "found relics are not placed again (bot run still places its own)")
	r2.queue_free()
	await get_tree().process_frame
	Save.data.unlocked.relics.clear()

func t_modifiers() -> void:
	var toma: Dictionary = Data.modifiers.filter(func(m): return m.id == "toma_rapida")[0]
	ok(not Data.modifier_unlocked(toma), "Toma Rápida locked without its relic")
	Save.data.unlocked.relics.append_array(["claqueta_de_oro", "llave_del_cine_infinito", "dado_del_productor", "espejo_de_camerino"])
	ok(Data.modifier_unlocked(toma), "Claqueta de Oro unlocks Toma Rápida")
	Save.data.mods_on = ["sin_limite", "imprevistos_de_rodaje", "fuera_de_plazo"]
	var r := new_run()
	ok(r.has_mod("sin_limite") and r.has_mod("imprevistos_de_rodaje") and not r.has_mod("fuera_de_plazo"), "only unlocked modifiers apply")
	var w: Dictionary = r.weapons.list[0]
	for l in 12: r.weapons.level_up(w.id)
	ok(w.level == 13, "Sin Límite: weapons go past level 8 (got %d)" % w.level)
	ok(absf(r.mod_bonus() - 0.75) < 0.001, "taquilla bonus adds up")
	r._update_events(121.0)
	ok(r.event_left > 0.0 and r.event_name != "", "an Imprevisto starts after two minutes")
	var chests_before: int = r.pickups.filter(func(p): return p.k == "chest").size()
	r._update_events(21.0)
	ok(r.pickups.filter(func(p): return p.k == "chest").size() == chests_before + 1, "an Imprevisto ends with a lata")
	r.queue_free()
	await get_tree().process_frame
	Save.data.unlocked.relics.append("baraja_del_guionista")
	Save.data.mods_on = ["guiones"]
	var r3 := new_run()
	r3.step(0.05)
	for k in 25: r3.step(0.05)
	ok(r3.guiones.size() == 1 and r3.guiones[0] in Run.GUION_READY, "Guiones: a card is chosen at the start")
	r3.guiones.clear()
	r3.rebuild_stats()
	var hp0: float = r3.stats.max_hp
	var pw0: float = r3.stats.power
	r3.pick_guion("g_v")
	ok(absf(float(r3.stats.max_hp) - (hp0 - 0.2)) < 0.001 and absf(float(r3.stats.power) - (pw0 + 0.4)) < 0.001, "El Pacto con el Diablo: -20 % vida, +40 % poder")
	r3.pick_guion("g_x")
	ok(r3.weapon_cap(r3.weapons.list[0]) == 9, "La Secuela: one level more")
	for g in Data.guiones: ok(ResourceLoader.exists("res://assets/sprites/guiones/%s.png" % g.id), "card art " + g.id)
	r3.guiones = Run.GUION_READY.duplicate()
	r3.guion_offers = 3
	r3.rebuild_stats()
	var t0 := Time.get_ticks_msec()
	while r3.time < 240.0:
		r3.step(0.05)
		r3.hp = max(r3.hp, 50.0)
	ok(r3.kills > 50 and r3.state != "over", "4 min with every Guion at once (%d kills, %d ms)" % [r3.kills, Time.get_ticks_msec() - t0])
	r3.queue_free()
	await get_tree().process_frame
	Save.data.mods_on = ["negativo"]
	var r2 := new_run()
	ok(r2.has_mod("negativo") and r2._filter != null, "Negativo puts a filter over the world")
	r2.queue_free()
	await get_tree().process_frame
	Save.data.mods_on = []
	Save.data.unlocked.relics.clear()

func t_achievements() -> void:
	Save.data = Save.defaults()
	Achievements.check({})
	var n0: int = Save.data.achievements.size()
	Save.data.stats.kills = 100000
	Save.data.stats.survived["bosque_de_la_cabana"] = 30
	Achievements.check({})
	ok(Save.data.achievements.size() > n0, "kill/survive achievements unlock")
	ok(Save.is_unlocked("stages", "pueblo_polvoriento"), "survive 10 min in stage 1 unlocks stage 2")

func t_bosses() -> void:
	for st in ["bosque_de_la_cabana", "pueblo_polvoriento", "estacion_orbital_zeta", "ciudad_noir", "templo_de_la_selva", "broadway_en_llamas"]:
		var r := new_run("max_rios", st)
		r.director.acc = -99999.0
		var b := r.enemies.spawn(EnemyPool.T.BOSS, 300.0, 0.0, 50.0)
		r.enemies.names[b] = "Jefe"
		var attacks := 0
		var bullets := 0
		for f in 600:
			r.step(1.0 / 30.0)
			r.hp = 9999.0
			attacks = max(attacks, r.boss_ai.warnings.size())
			bullets = max(bullets, r.ebullets.size())
		ok(r.boss_ai.pattern.size() == 2, "two attacks for " + st)
		ok(attacks > 0 or bullets > 0, "boss attacks in %s (%s)" % [st, str(r.boss_ai.pattern)])
		r.enemies.hp[b] = r.enemies.hp_max[b] * 0.2
		r.step(0.1)
		ok(r.boss_ai.state[b].phase == 3, "phase 3 under 25 %% in " + st)
		r.queue_free()
	var r2 := new_run()
	var p := r2.enemies.spawn(EnemyPool.T.PRODUCTOR, 2000.0, 0.0, 1.0)
	r2.enemies.names[p] = "Productor"
	for f in 150: r2.step(1.0 / 30.0)
	ok(Vector2(r2.enemies.x[p], r2.enemies.y[p]).distance_to(r2.player_pos) < 600.0, "El Productor appears next to you when far")
	r2.queue_free()
	await get_tree().process_frame

func t_perf() -> void:
	var r := new_run()
	r.weapons.add("palomitas")
	r.weapons.add("rollo_de_pelicula")
	r.weapons.add("foco")
	for k in 1200:
		var a := randf() * TAU
		r.enemies.spawn(EnemyPool.T.HORDE, cos(a) * randf_range(150, 900), sin(a) * randf_range(150, 700), 1000.0)
	r.director.done = {}
	r.director.acc = -99999.0
	var times: Array = []
	for f in 240:
		var t0 := Time.get_ticks_usec()
		r.step(1.0 / 60.0)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		r.hp = 9999.0
	times.sort()
	var avg := 0.0
	for t in times: avg += t
	avg /= times.size()
	print("  %d enemies: step avg %.2f ms, p95 %.2f ms" % [r.enemies.count, avg, times[int(times.size() * 0.95)]])
	ok(r.enemies.count >= 1000, "1000+ enemies alive")
	ok(avg < 10.0, "logic under 10 ms per frame with 1000+ enemies (avg %.2f)" % avg)
	r.queue_free()
	await get_tree().process_frame

func t_full_run() -> void:
	var r := new_run()
	var dt := 1.0 / 20.0
	var max_enemies := 0
	var t0 := Time.get_ticks_msec()
	var saw_productor := false
	while r.time < r.duration + 3.0 and r.state != "over":
		r.step(dt)
		r.hp = max(r.hp, 50.0)   # keep the bot alive so the whole calendar plays
		max_enemies = max(max_enemies, r.enemies.count)
		for i in r.enemies.names:
			if r.enemies.type[i] == EnemyPool.T.PRODUCTOR: saw_productor = true
	print("  30 min simulated in %.1f s: level %d, %d kills, %d max enemies, %d weapons, %d items" % [(Time.get_ticks_msec() - t0) / 1000.0, r.level, r.kills, max_enemies, r.weapons.list.size(), r.passives.size()])
	ok(r.completed, "run reaches 30:00")
	ok(saw_productor, "El Productor Ejecutivo appears at 30:00")
	ok(r.director.done.size() == r.director.calendar.size(), "all calendar events fired")
	ok(r.level > 20, "levels up through the run")
	ok(max_enemies > 600, "horde grows")
	var sum := r.record()
	ok(sum.completed and int(Save.data.stats.runs) >= 1, "run recorded in profile")
	r.queue_free()
	await get_tree().process_frame
