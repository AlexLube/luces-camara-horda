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
	for t in ["t_data", "t_stats", "t_save", "t_clauses", "t_weapons", "t_levelup", "t_chest_evolution", "t_union", "t_relics", "t_modifiers", "t_music", "t_death", "t_portraits", "t_saga", "t_cursed", "t_secrets", "t_relic_powers", "t_access", "t_balance", "t_bestiary", "t_achievements", "t_bosses", "t_perf"]:
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
	ok(Data.passive_list.size() == 27, "27 passives (got %d)" % Data.passive_list.size())
	ok(Data.weapon_list.size() == 55, "55 weapons (got %d)" % Data.weapon_list.size())
	ok(Data.unions.size() == 8, "8 unions")
	ok(Data.clauses.size() == 22, "22 clauses")
	ok(Data.characters.size() == 100, "100 characters (96 + 4 from the Modo Saga)")
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
	for c in Data.characters: ok(ResourceLoader.exists("res://assets/sprites/characters/%s/run.png" % c.id) or c.id == "max_rios", "sprite for " + c.id)
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
	Save.data.unlocked.relics.append("silla_del_director")
	Save.data.mods_on = ["maraton"]
	var r5 := new_run()
	ok(not r5.has_mod("maraton"), "Maratón stays locked until a Director's Cut run is beaten")
	r5.queue_free()
	Save.data.stats.dc_completed = ["bosque_de_la_cabana"]
	var r4 := new_run()
	r4.time = r4.duration - 0.05
	r4.director.done.clear()
	for k in 3: r4.step(0.05)
	ok(r4.cycle == 1 and r4.completed and r4.state != "over" and r4.time < 1.0, "Maratón: a new cycle instead of the end")
	ok(r4.director.hp_mult() > 1.7, "Maratón: the second cycle is tougher")
	r4.queue_free()
	await get_tree().process_frame
	Save.data.mods_on = ["negativo"]
	var r2 := new_run()
	ok(r2.has_mod("negativo") and r2._filter != null, "Negativo puts a filter over the world")
	r2.queue_free()
	await get_tree().process_frame
	Save.data.mods_on = []
	Save.data.unlocked.relics.clear()

func t_secrets() -> void:
	Save.data = Save.defaults()
	# Director's Cut: a modifier opened by the Silla del Director; tougher horde, better loot
	Save.data.mods_on = ["directors_cut"]
	var r0 := new_run()
	ok(not r0.has_mod("directors_cut"), "Director's Cut needs the Silla del Director")
	r0.queue_free()
	Save.data.unlocked.relics.append("silla_del_director")
	var dc := new_run()
	var plain_hp: float
	Save.data.mods_on = []
	var pl := new_run()
	plain_hp = pl.director.hp_mult()
	ok(dc.has_mod("directors_cut") and dc.director.hp_mult() > plain_hp * 1.5 and dc.director.target_count() > pl.director.target_count(), "Director's Cut: stronger, more enemies")
	ok(absf(dc.mod_bonus() - 0.6) < 0.001, "Director's Cut: +60 % Taquilla")
	var hp0: float = dc.hp
	dc.iframes = 0.0
	dc.take_damage(10.0, true)
	var hp1: float = pl.hp
	pl.iframes = 0.0
	pl.take_damage(10.0, true)
	ok(hp0 - dc.hp > hp1 - pl.hp, "Director's Cut: hits hurt more")
	pl.queue_free()
	dc.completed = true
	dc.stage = Data.stage_by_id["estacion_orbital_zeta"]
	dc.record()
	ok(Save.is_unlocked("stages", "neon_2099"), "beating stage 3 in Director's Cut opens Neón 2099")
	ok(Data.modifier_unlocked(Data.modifiers.filter(func(m): return m.id == "maraton")[0]), "…and Maratón")
	dc.queue_free()
	await get_tree().process_frame
	# Atrezzo: crates move, barrels blow up, fires go out
	var r := new_run()
	r.director.acc = -99999.0
	var a: SetProps = r.atrezzo
	a.items = [{"k": "crate", "x": 30.0, "y": 0.0, "moved": 0.0, "counted": false}, {"k": "barrel", "x": -400.0, "y": 0.0, "fuse": -1.0},
		{"k": "barrel", "x": -480.0, "y": 0.0, "fuse": -1.0}, {"k": "fire", "x": 0.0, "y": 400.0, "stomp": 0.0, "tick": 0.5}]
	a.spawn_t = 999.0
	for f in 40:
		r.move_dir = Vector2.RIGHT
		r.player_pos.x += 4.0
		a.update(0.05)
	ok(a.crates_moved == 1 and a.items[0].x > 100.0, "walking into a crate pushes it")
	var e := r.enemies.spawn(EnemyPool.T.HORDE, -400.0, 10.0, 100.0)
	r.damage_enemy(e, 1.0, Vector2.ZERO, r.weapons.list[0])
	for f in 20: a.update(0.05)
	ok(a.barrels_broken == 2, "a hit near a barrel blows it up, and its neighbour goes too (%d)" % a.barrels_broken)
	r.player_pos = Vector2(0, 400)
	for f in 20: a.update(0.05)
	ok(a.fires_out == 1, "standing on a fire puts it out")
	for f in 80: a.update(0.05)
	ok(a.items.size() > 0, "the stage keeps some atrezzo around")
	r.time = 5.0
	r.trips = 12
	r.dist_px = 4000.0
	r.record()
	var st: Dictionary = Save.data.stats
	ok(int(st.crates) == 1 and int(st.barrels) == 2 and int(st.fires) == 1 and int(st.trips) == 12 and int(st.early_deaths) == 1, "atrezzo and feats are saved")
	r.queue_free()
	await get_tree().process_frame
	# hidden feats
	st.barrels = 500
	st.early_deaths = 3
	st.pets = 10
	st.completed_by = {"max_rios": 10}
	Save.data.unlocked.relics.append_array(["gabardina", "bobina_0", "gramofono"])
	Achievements.check({"chests": 5})
	for c in ["bill_mecha", "el_extra", "michi_del_estudio", "el_doble_del_doble", "sam_shade", "fotograma_0", "sully_pluma"]:
		ok(Save.is_unlocked("characters", c), "secret unlocked: " + c)
	ok(Save.is_unlocked("stages", "broadway_en_llamas"), "the Gramófono opens Broadway en Llamas")
	ok(not Save.is_unlocked("characters", "claqui"), "Claqui waits for its code")
	var m: Node = load("res://scripts/main.gd").new()
	m.enter_code("claqui")
	Achievements.check({})
	ok(Save.is_unlocked("characters", "claqui"), "the Claqui code works")
	var t0 := int(Save.data.taquilla)
	m.enter_code("palomitas")
	m.enter_code("palomitas")
	ok(int(Save.data.taquilla) == t0 + 1000, "the popcorn code pays once")
	m.enter_code("sepia")
	ok(Save.data.options.sepia, "sepia code toggles the filter")
	Save.data.options.sepia = false
	m.free()
	# La Sala de Montaje: a cut every minute to another film; El Montador cuts too
	var sm := new_run("max_rios", "la_sala_de_montaje")
	sm.director.acc = -99999.0
	var b := sm.enemies.spawn(EnemyPool.T.BOSS, 50.0, 0.0, 10.0)
	var art0: String = sm.art_key
	var boss_tex = sm.sheets.boss.tex
	for f in 61 * 20:
		sm.step(0.05)
		sm.hp = 999.0
	ok(sm.art_key != art0 and sm.scene_name != "", "¡Corte!: the scene changes after a minute (%s)" % sm.art_key)
	ok(sm.sheets.boss.tex == boss_tex, "El Montador keeps his look")
	sm.enemies.x[b] = sm.player_pos.x + 30.0
	sm.enemies.y[b] = sm.player_pos.y
	sm.montage_cut()
	ok(absf(Vector2(sm.enemies.x[b], sm.enemies.y[b]).distance_to(sm.player_pos) - 320.0) < 1.0, "El Montador cuts to another spot")
	sm.queue_free()
	await get_tree().process_frame
	Save.data = Save.defaults()

func t_relic_powers() -> void:
	Save.data = Save.defaults()
	# Entrada Dorada: +15 % Taquilla
	var r := new_run()
	r.coins = 1000.0
	var plain: int = r.record().earned
	Save.data.unlocked.relics.append("entrada_dorada")
	var gold: int = r.record().earned
	ok(gold == int(round(plain * Data.GOLDEN_TICKET)), "Entrada Dorada: +15 %% Taquilla (%d → %d)" % [plain, gold])
	r.queue_free()
	# Carrete de tomas falsas: looks only with the relic
	Data.next_skin("max_rios")
	ok(Data.skin_tint("max_rios") == Color.WHITE, "no alternative takes without the Carrete")
	Save.data.unlocked.relics.append("carrete_de_tomas_falsas")
	Data.next_skin("max_rios")
	ok(Data.skin_tint("max_rios") != Color.WHITE, "the Carrete gives alternative takes")
	for k in Data.SKINS.size(): Data.next_skin("max_rios")
	ok(Data.skin_index("max_rios") == 1, "takes cycle round")
	# Tarjeta del Sindicato: sealed items never show up
	Data.toggle_seal("piel_de_platano")
	ok(not Data.is_sealed("piel_de_platano"), "no sealing without the Tarjeta")
	Save.data.unlocked.relics.append("tarjeta_del_sindicato")
	ok(Data.is_sealed("piel_de_platano"), "the Tarjeta seals")
	for id in ["ego_de_estrella", "cafe_solo"]: Data.toggle_seal(id)
	var r2 := new_run()
	var seen := false
	for k in 300:
		for o in Upgrades.roll(r2, 4):
			if Data.is_sealed(o.id) and o.kind.ends_with("_new"): seen = true
	ok(not seen, "sealed weapons and passives never appear in level-ups")
	r2.queue_free()
	# Gafas 3D: invisible enemies
	var n := new_run("max_rios", "ciudad_noir")
	var far := n.enemies.spawn(EnemyPool.T.HORDE, 600.0, 0.0)
	var near := n.enemies.spawn(EnemyPool.T.HORDE, 100.0, 0.0)
	ok(n.visibility(far) == 0.0 and n.visibility(near) == 1.0, "Ciudad Noir: enemies hide outside your light")
	Save.data.unlocked.relics.append("gafas_3d")
	ok(n.visibility(far) == 1.0, "the Gafas 3D show them")
	n.queue_free()
	# Llave del Archivo: the Catálogo (and El Cinéfilo) need it
	Save.data.unlocked.relics.erase("gafas_3d")
	for st in Data.stages: Save.data.stats.bestiary[st.id] = {"boss": 1}
	ok(not Achievements.secret_met("unlock_el_cinefilo"), "El Cinéfilo needs the Llave del Archivo")
	Save.data.unlocked.relics.append("llave_del_archivo")
	ok(Achievements.secret_met("unlock_el_cinefilo"), "…and a full Catálogo")
	await get_tree().process_frame
	Save.data = Save.defaults()

func t_access() -> void:
	for n in ["coin", "eat", "relic", "evolve", "clap", "fire_out", "cut", "warn", "ui_move", "reel"]:
		ok(Sfx._streams.get(n) != null, "sound effect loads: " + n)
	var o: Dictionary = Save.data.options
	ok(Access.cycle(Access.MODES, "off") == "protan" and Access.cycle(Access.MODES, "tritan") == "off", "colour-blind modes cycle")
	o.colorblind = "deutan"
	o.text_size = 1.3
	Save.apply_options()
	ok(Access._rect.visible and UIKit.text_scale == 1.3, "options apply the filter and the text size")
	ok(UIKit.label("x", 20).get_theme_font_size("font_size") == 26, "menu text grows")
	o.colorblind = "off"
	o.text_size = 1.0
	Save.apply_options()
	ok(not Access._rect.visible and UIKit.text_scale == 1.0, "and back to normal")
	o.game_speed = 0.7
	var r := new_run()
	r.set_process(true)
	var t0: float = r.time
	r._process(0.05)
	ok(absf((r.time - t0) - 0.035) < 0.001, "game speed 70 %% slows the run (%.4f)" % (r.time - t0))
	o.game_speed = 1.0
	r.queue_free()
	await get_tree().process_frame

func t_balance() -> void:
	var a := new_run("max_rios", "bosque_de_la_cabana")
	var b := new_run("max_rios", "archivo_de_cine_mudo")
	var c := new_run("max_rios", "templo_de_la_selva")
	ok(b.director.stage_k() > c.director.stage_k() and c.director.stage_k() > a.director.stage_k(), "challenge films are harder, and base films grow harder one after another")
	ok(b.director.hp_mult() > a.director.hp_mult() * 1.3, "challenge enemies are tougher")
	ok(Run.xp_for(100) - Run.xp_for(99) > Run.xp_for(50) - Run.xp_for(49), "late levels cost more")
	# Exposición Total: the screen freeze has a pause between uses
	a.weapons.list.clear()
	var w: Dictionary = a.weapons.add("camara_de_flash")
	a.weapons.evolve("camara_de_flash")
	var frozen := 0.0
	for f in 20 * 40:
		a.step(0.05)
		a.hp = 999.0
		if a.freeze_t > 0.0: frozen += 0.05
	ok(frozen < 40.0 * 0.6, "Exposición Total never keeps the horde frozen for good (%.0f of 40 s)" % frozen)
	for r in [a, b, c]: r.queue_free()
	await get_tree().process_frame

func t_bestiary() -> void:
	var r := new_run()
	r.bot = true
	for k in 3:
		var i := r.enemies.spawn(EnemyPool.T.HORDE, 100.0, 0.0)
		r.kill(i)
	var b := r.enemies.spawn(EnemyPool.T.BOSS, 100.0, 0.0)
	r.kill(b)
	ok(int(r.beasts.get("enemy", 0)) == 3 and int(r.beasts.get("boss", 0)) == 1, "bestiary counts kills by kind")
	r.bot = false
	r.record()
	ok(int(Save.data.stats.bestiary[r.stage.id].boss) == 1, "bestiary saved per stage")
	ok(Data.first_frame("res://assets/sprites/stages/forest/boss.png", 6) != null, "bestiary picture")
	r.queue_free()
	await get_tree().process_frame

func t_music() -> void:
	for k in Music.BY_GENRE.keys() + ["titulo", "jefe", "creditos"]: ok(ResourceLoader.exists("res://assets/music/%s.ogg" % k), "music track " + k)
	for st in Data.stages:
		var found := false
		for k in Music.BY_GENRE: found = found or st.genre in Music.BY_GENRE[k]
		ok(found, "stage genre has a track: %s (%s)" % [st.id, st.genre])
	Music.play("western")
	ok(Music.current == "western" and Music._players.size() >= 1, "music starts")
	Music.play("jefe")
	ok(Music.current == "jefe" and Music._players[-1][2] == 1.0 and Music._players[0][2] == 0.0, "crossfade to the boss theme")
	await get_tree().create_timer(1.2).timeout
	ok(Music._players.size() == 1, "old track freed after the fade")
	Music.stop()

func t_death() -> void:
	var r := new_run()
	r.bot = false
	r.take_damage(5.0, true)
	ok(r.hurt_t == 1.0 and r.hurt_flash == 1.0, "a hit starts the hurt recoil")
	r.step(0.1)
	ok(r.hurt_t < 1.0 and r.hurt_t > 0.0, "hurt recoil fades")
	var deaths: int = Save.data.stats.deaths
	r.hp = 0.0
	r._on_death()
	ok(r.state == "dying", "dying plays «¡Corten!» before the results")
	r.step(0.5)
	ok(r.state == "dying" and float(r.death_pose()[0]) > 0.0, "the hero tips over")
	for i in 40: r.step(0.05)
	ok(r.state == "over" and int(Save.data.stats.deaths) == deaths + 1, "results after the death animation (%s, %d→%d)" % [r.state, deaths, int(Save.data.stats.deaths)])
	r.queue_free()
	await get_tree().process_frame
	var b := new_run()
	b.hp = 0.0
	b._on_death()
	ok(b.state == "over", "bot runs skip the death animation")
	b.queue_free()
	await get_tree().process_frame
	Save.data = Save.defaults()

func t_portraits() -> void:
	var n := 0
	for c in Data.characters:
		if Data.has_portrait(c.id):
			n += 1
			var t := Data.portrait(c.id)
			ok(t != null and t.get_width() >= 128, "portrait " + c.id)
	ok(n == Data.characters.size(), "every character has a portrait (%d/%d)" % [n, Data.characters.size()])
	ok(Data.sprite_frame("max_rios") != null, "sprite frame fallback")

func saga_run(saga_id: String, phase := 0, char_id := "max_rios") -> Run:
	var sg: Dictionary = Data.saga_by_id[saga_id]
	var r := Run.new()
	r.setup(Data.char_by_id[char_id], Data.stage_by_id[sg.phases[phase].stage])
	r.setup_saga(sg, phase)
	r.bot = true
	add_child(r)
	r.set_process(false)
	return r

func t_saga() -> void:
	Save.data = Save.defaults()
	ok(not Data.weapon_pool(Data.characters[0]).has("espada_de_plasma"), "the Espada de Plasma waits for its saga")
	ok(not Save.is_unlocked("characters", "la_ultima_chica"), "saga characters start locked")
	ok(Data.sagas.size() == 9, "9 sagas")
	var n := 0
	for sg in Data.sagas:
		n += sg.phases.size()
		ok(sg.rule in ["secuela", "naves", "superpoder", "combo", "sigilo", "grupo", "coche", "desastre", "mezcla"], "saga rule " + sg.id)
		for ph in sg.phases: ok(Data.stage_by_id.has(ph.stage), "saga stage %s / %s" % [sg.id, ph.stage])
		for id in sg.get("party", []): ok(Data.char_by_id.has(id), "party member " + id)
	ok(n == 51, "51 saga phases (got %d)" % n)
	ok(not Data.saga_mode_open(), "saga mode closed before the Bobina Dorada")
	Save.unlock("relics", "bobina_dorada")
	ok(Data.saga_open(Data.saga_by_id.leyenda_del_puno) and not Data.saga_open(Data.saga_by_id.retrospectiva_director), "sagas open, the Retrospectiva waits")
	# every rule survives a minute of autoplay
	for sg in Data.sagas:
		var r := saga_run(sg.id, 1)
		for k in 600: r.step(0.1)
		ok(r.time >= 59.0 and r.saga_rules != null and r.duration == SagaRules.PHASE_SECONDS, "saga %s plays (%d kills)" % [sg.id, r.kills])
		r.queue_free()
		await get_tree().process_frame
	var c := saga_run("leyenda_del_puno")
	for k in 30: c.saga_rules.on_kill()
	ok(c.saga_rules.damage_mult() > 1.05, "combo raises damage")
	c.take_damage(5.0, true)
	ok(c.saga_rules.combo == 0, "a hit breaks the combo")
	c.queue_free()
	var st := saga_run("agente_00_nadie")
	var calm: float = st.saga_rules.spawn_mult()
	st.take_damage(5.0, true)
	ok(calm < 1.0 and st.saga_rules.spawn_mult() > 1.0, "stealth: the alarm brings more extras")
	st.queue_free()
	var sp := saga_run("liga_heroes_barrio")
	sp.saga_rules.power_t = 0.0
	sp.saga_rules.update(0.1)
	ok(sp.saga_rules.power != "", "a superpower falls from the sky")
	sp.saga_rules.power = "shield"
	var hp0: float = sp.hp
	sp.take_damage(50.0, true)
	ok(sp.hp == hp0, "invulnerable superpower")
	sp.queue_free()
	var car := saga_run("nitro_y_familia")
	car.saga_rules.car_dir = Vector2.RIGHT
	var v: Vector2 = car.saga_rules.move_car(0.1, Vector2.LEFT)
	ok(v.x > 0.0 and car.saga_rules.car_dir.angle() != 0.0, "the car turns slowly")
	car.queue_free()
	var ds := saga_run("dia_de_desastre")
	ds.saga_rules.hazard_t = 0.0
	ds.saga_rules.update(0.1)
	ok(ds.saga_rules.hazards.size() >= 2, "disaster zones appear")
	for k in 20: ds.saga_rules.update(0.1)
	ok(ds.saga_rules.hazards.is_empty(), "disaster zones go off")
	ds.queue_free()
	var nv := saga_run("opera_galactica")
	var y0: float = nv.saga_rules.scroll_y
	nv.saga_rules.update(1.0)
	ok(nv.saga_rules.scroll_y < y0, "the scroll moves up")
	nv.queue_free()
	var g := saga_run("odisea_anillo_roto", 0, "max_rios")
	ok(g.saga_rules.party.size() == 3, "party of three")
	g.saga_rules.swap()
	ok(g.character.id == "brann", "swap to the next hero")
	g.hp = 0.0
	g._on_death()
	ok(g.state != "dying" and g.character.id == "elowen" and g.hp > 0.0, "the next hero steps in when one falls")
	g.queue_free()
	await get_tree().process_frame
	# progress and reward
	var last := saga_run("leyenda_del_puno", 4)
	last.bot = false
	Save.data.saga["leyenda_del_puno"] = 4
	last.completed = true
	var sum: Dictionary = last.record()
	ok(int(Save.data.saga.leyenda_del_puno) == 5 and sum.saga_done and Save.is_unlocked("relics", "cinturon_negro"), "finishing a saga gives its reward")
	for sg in Data.sagas:
		var r: Dictionary = sg.reward
		Data.grant_saga_reward(sg)
		match r.kind:
			"character": ok(Save.is_unlocked("characters", r.id) and Save.is_unlocked("hired", r.id) and Data.char_by_id.has(r.id), "saga reward character " + r.id)
			"weapon": ok(Data.weapons.has(r.id) and r.id in Data.weapon_pool(Data.characters[0]), "saga reward weapon " + r.id)
			"passive": ok(Data.passives.has(r.id) and Save.is_unlocked("passives", r.id), "saga reward passive " + r.id)
			"relic": ok(Save.is_unlocked("relics", r.id), "saga reward relic " + r.id)
	var tb := Stats.build(Data.characters[0], {"turbo": 5}, {}, 1)
	var t0 := Stats.build(Data.characters[0], {}, {}, 1)
	ok(tb.move_speed > t0.move_speed and tb.cooldown < t0.cooldown, "Turbo: faster and shorter cooldowns")
	last.queue_free()
	await get_tree().process_frame
	var w := new_run("kenji_arata")
	var arc: Array = w.weapons.list.filter(func(x): return x.data.archetype in ["arc", "cone"])
	ok(arc.is_empty() or int(arc[0].p.amount) >= 2, "Cinturón Negro: +1 to melee weapons")
	w.queue_free()
	await get_tree().process_frame
	Save.data = Save.defaults()

func t_cursed() -> void:
	Save.data = Save.defaults()
	ok(CursedGuiones.READY.size() == 12 and Data.guiones.filter(func(g): return g.cursed).size() == 12, "12 Guiones Malditos")
	ok(Data.relics_at(Data.stage_by_id.archivo_de_cine_mudo).any(func(r): return r.id == "bobina_perdida_1"), "lost reel 1 hides in challenge stage 13")
	for k in range(1, 8): Save.unlock("relics", "bobina_perdida_%d" % k)
	Achievements.check({})
	ok(Save.is_unlocked("stages", "la_sala_de_montaje"), "the 7 lost reels open the Sala de Montaje")
	ok(Data.relics_at(Data.stage_by_id.la_sala_de_montaje).any(func(r): return r.id == "baraja_maldita"), "the Baraja Maldita hides in the Sala de Montaje")
	# without the deck no cursed card is offered
	var r0 := new_run()
	r0.mods = ["guiones"]
	for k in 20:
		r0.guion_offers = 0
		r0.guiones.clear()
		r0.offer_guion()
	ok(not r0.guiones.any(func(id): return id.begins_with("gm_")), "no cursed cards before the Baraja Maldita")
	r0.queue_free()
	Save.unlock("relics", "baraja_maldita")
	# every cursed card plays for a minute
	for id in CursedGuiones.READY:
		var r := new_run()
		r.mods = ["guiones"]
		r.guion_offers = 3
		r.pick_guion(id)
		for k in 600: r.step(0.1)
		ok(r.time >= 59.0 and r.curse != null, "cursed %s plays (%d kills)" % [id, r.kills])
		r.queue_free()
		await get_tree().process_frame
	var a := new_run()
	a.guion_offers = 3
	var p0: float = a.stats.power
	a.pick_guion("gm_iv")
	ok(a.stats.power > p0 + 0.25 and a.curse.taquilla_mult() == 0.0, "El Fracaso de Taquilla: +30 % but no Taquilla")
	a.pick_guion("gm_ix")
	ok(a.duration == 900.0 and a.director.calendar[-1][0] == 900.0, "El Final Cortado: 15-minute run")
	a.curse.on_hurt()
	ok(a.curse.ghosts.is_empty(), "no ghosts without El Rodaje Maldito")
	a.pick_guion("gm_ii")
	a.curse.on_hurt()
	ok(a.curse.ghosts.size() == 3, "El Rodaje Maldito: three ghosts on a hit")
	a.pick_guion("gm_i")
	var w0: String = a.weapons.list[0].id
	a.curse.swap_t = 0.0
	a.curse.update(0.1)
	ok(a.weapons.list.size() == 1 and a.weapons.list[0].id != w0 and a.guion_damage() >= 2.0, "La Película Perdida: the weapon changes, ×2 damage")
	a.pick_guion("gm_vii")
	var w: Dictionary = a.weapons.list[0]
	w.evolved = true
	a.weapons.recompute(w)
	var dmg0: float = w.p.damage
	ok(a.curse.remaster(w) and w.p.damage > dmg0 * 1.4, "El Remake Innecesario remasters an evolution")
	a.queue_free()
	await get_tree().process_frame
	Save.data = Save.defaults()

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
	# a strong bot keeps the screen clean, so the horde also counts as grown when it fed 20 000+ kills
	ok(max_enemies > 600 or r.kills > 20000, "horde grows (%d max on screen, %d kills)" % [max_enemies, r.kills])
	var sum := r.record()
	ok(sum.completed and int(Save.data.stats.runs) >= 1, "run recorded in profile")
	r.queue_free()
	await get_tree().process_frame
