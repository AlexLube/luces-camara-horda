class_name CursedGuiones
extends RefCounted
## Los 12 Guiones Malditos: strong cards with a price. They join the Guion offers once the
## Baraja Maldita relic is found (one slot in three may be a cursed card).

const READY := ["gm_i", "gm_ii", "gm_iii", "gm_iv", "gm_v", "gm_vi", "gm_vii", "gm_viii", "gm_ix", "gm_x", "gm_xi", "gm_xii"]
const SIGHT := 300.0          # El Metraje Encontrado: what the camera still sees
const SHORT_CUT := 900.0      # El Final Cortado: 15-minute runs

var run
var swap_t := 60.0            # La Película Perdida
var hell_t := 60.0            # Infierno de Producción
var ghosts: Array = []        # El Rodaje Maldito: {x, y, t}
var allies: Array = []        # El Actor Poseído: {x, y, t, hit}
var productor_called := false # El Productor Ejecutivo

func _init(r) -> void:
	run = r

## Called once when a cursed card is picked.
func on_pick(id: String) -> void:
	match id:
		"gm_ix":
			run.duration = minf(run.duration, SHORT_CUT)
			run.director.build_calendar()
		"gm_x": Sfx.volume = 0.0

## Stats added while the card is in play (see Run._guion_stats).
func stats(e: Dictionary) -> void:
	if run.has_guion("gm_iii"):
		e.power = float(e.get("power", 0.0)) + 0.05 * run.used_banishes
		e.banishes = float(e.get("banishes", 0.0)) + 3.0
	if run.has_guion("gm_iv"):
		for k in ["power", "area", "speed", "duration", "max_hp", "luck", "growth", "magnet", "proj_speed"]: e[k] = float(e.get(k, 0.0)) + 0.3
		e.cooldown = float(e.get("cooldown", 0.0)) - 0.15
	if run.has_guion("gm_x"):
		e.power = float(e.get("power", 0.0)) + 2.0      # ×3 damage...
		e.cooldown = float(e.get("cooldown", 0.0)) + 0.6  # ...but only on the beat

func enemy_speed() -> float:
	return 1.25 if run.has_guion("gm_xi") else 1.0

func taquilla_mult() -> float:
	var k := 1.0
	if run.has_guion("gm_iv"): k = 0.0
	if run.has_guion("gm_ix"): k *= 2.0
	if run.has_guion("gm_xii") and run.productor_killed: k *= 2.0
	return k

func on_hurt() -> void:
	if not run.has_guion("gm_ii") or ghosts.size() >= 12: return
	for k in 3:
		var a := TAU * k / 3.0 + randf()
		ghosts.append({"x": run.player_pos.x + cos(a) * 30.0, "y": run.player_pos.y + sin(a) * 30.0, "t": 5.0})

func on_kill(at: Vector2, boss: bool) -> void:
	if run.has_guion("gm_v") and not boss and allies.size() < 12 and randf() < 0.05:
		allies.append({"x": at.x, "y": at.y, "t": 15.0, "hit": 0.0})

## El Remake Innecesario: a maxed, evolved weapon gets remastered by a lata.
func remaster(w: Dictionary) -> bool:
	if not run.has_guion("gm_vii") or not w.evolved or w.get("remastered", false) or w.data.source == "union": return false
	w.remastered = true
	run.weapons.recompute(w)
	return true

func update(dt: float) -> void:
	if run.has_guion("gm_i"): _lost_film(dt)
	if run.has_guion("gm_viii"): _production_hell(dt)
	if run.has_guion("gm_xi"):
		for p in run.pickups:
			if p.k == "chest": p.pull = true
	if run.has_guion("gm_xii") and not productor_called and run.time >= 900.0:
		productor_called = true
		var i = run.enemies.spawn(EnemyPool.T.PRODUCTOR, run.player_pos.x + 700.0, run.player_pos.y, 1.0, 0.0)
		if i >= 0: run.enemies.names[i] = Loc.t("productor")
		run.announce(Loc.t("gm_productor"))
	_ghosts(dt)
	_allies(dt)

func _lost_film(dt: float) -> void:
	swap_t -= dt
	if swap_t > 0.0: return
	swap_t = 60.0
	var mine: Array = run.weapons.list.filter(func(w): return not w.evolved and w.data.source != "union")
	if mine.is_empty(): return
	var old: Dictionary = mine[randi() % mine.size()]
	var pool: Array = Data.weapon_pool(run.character).filter(func(id): return not run.weapons.has(id) and not run.union_parts_used.has(id))
	if pool.is_empty(): return
	var nid: String = pool[randi() % pool.size()]
	var lvl: int = old.level
	run.weapons.list.erase(old)
	var nw: Dictionary = run.weapons.add(nid)
	nw.level = mini(lvl, int(nw.data.max_level))
	run.weapons.recompute(nw)
	run.announce(Loc.t("gm_swap", [old.data.name, nw.data.name]))

func _production_hell(dt: float) -> void:
	hell_t -= dt
	if hell_t > 0.0: return
	hell_t = 60.0
	if not run.passives.is_empty():
		var ids: Array = run.passives.keys()
		var pid: String = ids[randi() % ids.size()]
		run.passives[pid] = int(run.passives[pid]) - 1
		if int(run.passives[pid]) <= 0: run.passives.erase(pid)
	var ups: Array = run.weapons.list.filter(func(w): return w.level < run.weapon_cap(w))
	if not ups.is_empty():
		var w: Dictionary = ups[randi() % ups.size()]
		w.level += 1
		run.weapons.recompute(w)
	run.rebuild_stats()
	run.announce(Loc.t("gm_hell"))

func _ghosts(dt: float) -> void:
	var keep: Array = []
	for g in ghosts:
		g.t -= dt
		var e: int = run.enemies.nearest(g.x, g.y, 500.0)
		if e >= 0:
			var to := Vector2(run.enemies.x[e], run.enemies.y[e]) - Vector2(g.x, g.y)
			if to.length() < 22.0:
				run.burst(Vector2(g.x, g.y), 70.0, 15.0 + run.level * 2.0)
				continue
			var v := to.normalized() * 320.0 * dt
			g.x += v.x
			g.y += v.y
		if g.t > 0.0: keep.append(g)
	ghosts = keep

func _allies(dt: float) -> void:
	var keep: Array = []
	for a in allies:
		a.t -= dt
		a.hit -= dt
		var e: int = run.enemies.nearest(a.x, a.y, 600.0)
		if e >= 0:
			var to := Vector2(run.enemies.x[e], run.enemies.y[e]) - Vector2(a.x, a.y)
			if to.length() > 20.0:
				var v := to.normalized() * 230.0 * dt
				a.x += v.x
				a.y += v.y
			elif a.hit <= 0.0:
				a.hit = 0.4
				run.damage_enemy(e, 8.0 + run.level * 1.5, to.normalized() * 150.0, null)
		if a.t > 0.0: keep.append(a)
	allies = keep

func draw_world(c: CanvasItem) -> void:
	for g in ghosts:
		var p := Vector2(g.x, g.y + sin(run.time * 8.0 + g.x) * 3.0)
		c.draw_circle(p, 11.0, Color(0.85, 0.95, 1.0, 0.55))
		c.draw_rect(Rect2(p.x - 11.0, p.y, 22.0, 10.0), Color(0.85, 0.95, 1.0, 0.45))
		c.draw_circle(p + Vector2(-4, -2), 2.0, Color(0.1, 0.1, 0.2, 0.9))
		c.draw_circle(p + Vector2(4, -2), 2.0, Color(0.1, 0.1, 0.2, 0.9))
	var sh: Dictionary = run.sheets.get("enemy", {})
	for a in allies:
		run._draw_sheet(sh, int(run.time * 10.0), Vector2(a.x, a.y), 0.9, 1.0, Color(0.55, 1.0, 0.6, 0.9))
