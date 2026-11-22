class_name Director
extends RefCounted
## Spawns the horde minute by minute and runs the stage calendar:
## 5 Estrella Invitada · 10 jefe débil · 15 oleada especial · 20 jefe · 25 dos invitadas · final-2 jefe final · final El Productor Ejecutivo.

const T := EnemyPool.T
var run
var acc := 0.0
var elite_t := 55.0
var star_t := 170.0
var done := {}
var calendar: Array = []   # [second, event]

func _init(r) -> void:
	run = r
	var total: float = run.duration
	calendar = [[300.0, "guest"], [600.0, "boss_weak"], [900.0, "wave"], [1200.0, "boss"], [1500.0, "guests"], [total - 120.0, "boss_final"], [total, "productor"]]
	if total < 1800.0:  # bonus stages (20 min): compressed calendar
		calendar = [[300.0, "guest"], [600.0, "boss_weak"], [900.0, "wave"], [total - 120.0, "boss_final"], [total, "productor"]]

func minute() -> float:
	return run.time / 60.0

## Health multiplier for normal enemies: grows with time and Maldición.
func hp_mult() -> float:
	var neg := 1.5 if run.has_mod("negativo") else 1.0
	return (1.0 + minute() * 0.11 + pow(minute() / 10.0, 2.0) * 0.6) * (0.5 + 0.5 * float(run.stats.curse)) * neg

func target_count() -> int:
	var m := minute()
	return int(min(1450.0, (28.0 + m * 40.0 + m * m * 0.55) * float(run.stats.curse)))

func _pick_type() -> int:
	var m := minute()
	var opts := [[T.HORDE, 10.0]]
	if m >= 1.5: opts.append([T.SWARM, 4.0 + m * 0.2])
	if m >= 3.0: opts.append([T.TANK, 0.7 + m * 0.05])
	if m >= 4.0: opts.append([T.SHOOTER, 0.7])
	if m >= 6.0: opts.append([T.KAMIKAZE, 1.0])
	if m >= 8.0: opts.append([T.JUMPER, 0.8])
	var tot := 0.0
	for o in opts: tot += o[1]
	var r := randf() * tot
	for o in opts:
		r -= o[1]
		if r <= 0.0: return o[0]
	return T.HORDE

## Spawn point just outside the screen, a bit biased to where the player walks.
func edge_point() -> Vector2:
	var vr: Rect2 = run.view_rect()
	var half: Vector2 = vr.size / 2.0
	var a := randf() * TAU
	if run.move_dir.length() > 0.1 and randf() < 0.35: a = run.move_dir.angle() + randf_range(-0.9, 0.9)
	var d := Vector2(cos(a), sin(a))
	var k: float = min(half.x / max(0.001, abs(d.x)), half.y / max(0.001, abs(d.y))) + 50.0
	return run.player_pos + d * k

func spawn(t: int, at := Vector2.INF, hp_k := 1.0) -> int:
	if at == Vector2.INF: at = edge_point()
	return run.enemies.spawn(t, at.x, at.y, hp_mult() * hp_k, minute() * 0.8)

func update(dt: float) -> void:
	if run.freeze_t > 0.0 or run.event_active("strike"): return
	var m := minute()
	acc += dt * (5.0 + m * 2.6) * float(run.stats.curse)
	var want := target_count()
	while acc >= 1.0:
		acc -= 1.0
		if run.enemies.count >= want: break
		spawn(_pick_type())
	acc = min(acc, 40.0)
	elite_t -= dt
	if elite_t <= 0.0:
		elite_t = 60.0
		spawn(T.ELITE)
	star_t -= dt
	if star_t <= 0.0:
		star_t = 180.0
		_named(T.STAR, Loc.t("star"), 1.0 + m * 0.15)
	for ev in calendar:
		if run.time >= ev[0] and not done.has(ev[0]):
			done[ev[0]] = true
			_event(ev[1])

func _named(t: int, name: String, hp_k: float) -> int:
	var i := spawn(t, Vector2.INF, hp_k)
	if i >= 0: run.enemies.names[i] = name
	return i

func _event(ev: String) -> void:
	var boss_name: String = run.stage.get("boss", "Jefe")
	var lvl_k: float = 1.0 + run.level * 0.04
	match ev:
		"guest":
			_named(T.GUEST, Loc.t("guest"), lvl_k)
			run.announce(Loc.t("ev_guest"))
		"guests":
			_named(T.GUEST, Loc.t("guest"), lvl_k * 1.3)
			_named(T.GUEST, Loc.t("guest"), lvl_k * 1.3)
			run.announce(Loc.t("ev_guests"))
		"boss_weak":
			_named(T.BOSS, boss_name, 0.35 * lvl_k)
			run.announce(Loc.t("ev_boss", [boss_name]))
			Sfx.play("boss")
		"boss":
			_named(T.BOSS, boss_name, 0.9 * lvl_k)
			run.announce(Loc.t("ev_boss", [boss_name]))
			Sfx.play("boss")
		"boss_final":
			_named(T.BOSS, boss_name + " (" + Loc.t("final_cut") + ")", 1.8 * lvl_k)
			run.announce(Loc.t("ev_final", [boss_name]))
			Sfx.play("boss")
		"wave":
			# a ring of extras closing in from every side
			for k in 70:
				var a := TAU * k / 70.0
				run.enemies.spawn(T.WALL, run.player_pos.x + cos(a) * 620.0, run.player_pos.y + sin(a) * 620.0, hp_mult() * 2.0, 0.0)
			run.announce(Loc.t("ev_wave"))
		"productor":
			run.reach_end()
			for k in 1:
				var i = run.enemies.spawn(T.PRODUCTOR, run.player_pos.x + 700.0, run.player_pos.y, 1.0, 0.0)
				if i >= 0: run.enemies.names[i] = Loc.t("productor")
			run.announce(Loc.t("ev_productor"))
			Sfx.play("boss", 0.6)
