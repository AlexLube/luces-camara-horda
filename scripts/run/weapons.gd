class_name WeaponSystem
extends RefCounted
## Data-driven weapons. Every one of the 54 weapons is one of 11 behaviour archetypes
## (arc, orbit, projectile, beam, screen, zone, cone, aura, companion, car, mark) with its own numbers
## from data/weapons.json, 8 levels, and an evolution that boosts numbers and switches on flags.

const MULT_KEYS := ["area", "duration", "size", "cooldown", "range"]
const COLORS := {"arc": Color("fff3c8"), "orbit": Color("d8d8e8"), "projectile": Color("ffd36b"), "beam": Color("fff6a0"),
	"screen": Color.WHITE, "zone": Color("ff7a4a"), "cone": Color("9fd8ff"), "aura": Color("c8b4ff"),
	"companion": Color("8ff0c0"), "car": Color("ff5050"), "mark": Color("b070ff")}

var run  # the Run node: damage_enemy(), stats, player position, fx
var list: Array = []          # weapon instances
var shots: Array = []         # player projectiles
var zones: Array = []         # ground effects, delayed strikes, moving cars
var orbiters: Array = []      # for drawing
var _q := PackedInt32Array()

func _init(r) -> void:
	run = r

func has(id: String) -> bool:
	return get_w(id) != null

func get_w(id: String):
	for w in list:
		if w.id == id: return w
	return null

func add(id: String) -> Dictionary:
	var data: Dictionary = Data.weapons[id]
	var w := {"id": id, "data": data, "level": 1, "evolved": false, "cd": 0.3, "state": {"hits": {}, "phase": 0.0, "on": true, "ang": 0.0, "grow": 0.0}, "p": {}}
	list.append(w)
	recompute(w)
	return w

func level_up(id: String) -> void:
	var w = get_w(id)
	if w and w.level < run.weapon_cap(w):
		w.level += 1
		recompute(w)

func evolve(id: String) -> void:
	var w = get_w(id)
	if w:
		w.evolved = true
		recompute(w)

func recompute_all() -> void:
	for w in list: recompute(w)

## Final numbers: base -> level table -> evolution -> player stats.
func recompute(w: Dictionary) -> void:
	var p: Dictionary = w.data.base.duplicate()
	for k in ["damage", "cooldown", "area", "amount", "duration", "pierce", "stun", "size", "range", "speed"]:
		if not p.has(k): p[k] = {"damage": 5, "cooldown": 1.0, "area": 60, "amount": 1, "duration": 1.0, "pierce": 0, "stun": 0.0, "size": 10, "range": 400, "speed": 400}[k]
	var ups: Array = w.data.levels
	for l in range(w.level - 1):
		var up: Dictionary = ups[min(l, ups.size() - 1)]
		for k in up:
			if k in MULT_KEYS: p[k] = p[k] * (1.0 + float(up[k]))
			else: p[k] = p.get(k, 0) + up[k]
	if w.evolved:
		var m: Dictionary = w.data.evolution.mods
		p.damage *= float(m.get("damage", 1.4))
		p.area *= float(m.get("area", 1.0))
		p.cooldown *= float(m.get("cooldown", 1.0))
		p.amount += int(m.get("amount_add", 0))
		for k in m:
			if k not in ["damage", "area", "cooldown", "amount_add"]: p[k] = m[k]
	var s: Dictionary = run.stats
	p.damage *= s.power
	p.cooldown = max(0.08, p.cooldown * s.cooldown)
	p.area *= s.area
	p.size *= sqrt(s.area)
	p.amount = int(p.amount) + int(s.amount)
	p.speed *= s.proj_speed
	p.duration *= s.duration
	w.p = p

func update(dt: float) -> void:
	var pl: Vector2 = run.player_pos
	for w in list:
		var p: Dictionary = w.p
		var arch: String = w.data.archetype
		match arch:
			"orbit": _orbit(w, dt)
			"aura": _aura_tick(w, dt)
			"cone":
				if p.has("rotate"): w.state.ang += dt * float(p.rotate)
		w.cd -= dt
		if w.cd <= 0.0 and arch != "orbit":
			w.cd = p.cooldown
			_fire(w)
	_update_shots(dt)
	_update_zones(dt)
	# forget old per-enemy hit timers now and then
	if Engine.get_process_frames() % 120 == 0:
		for w in list: w.state.hits.clear()

func _can_hit(w: Dictionary, i: int, gap: float) -> bool:
	var now: float = run.time
	var key: int = i
	if float(w.state.hits.get(key, -9.0)) > now: return false
	w.state.hits[key] = now + gap
	return true

func _dmg(w: Dictionary, i: int, amount: float, from: Vector2, kb := 0.0) -> void:
	var dir := (Vector2(run.enemies.x[i], run.enemies.y[i]) - from).normalized()
	run.damage_enemy(i, amount, dir * kb, w)
	var p: Dictionary = w.p
	if p.get("stun", 0.0) > 0.0: run.enemies.stun[i] = max(run.enemies.stun[i], float(p.stun) * run.stats.freeze_time)
	if p.get("slow", 0.0) > 0.0: run.enemies.slow[i] = max(run.enemies.slow[i], float(p.slow))
	if p.has("pull"): run.enemies.kx[i] -= dir.x * float(p.pull); run.enemies.ky[i] -= dir.y * float(p.pull)
	if p.has("lifesteal"): run.heal(amount * float(p.lifesteal) * 0.05)

func _fire(w: Dictionary) -> void:
	var p: Dictionary = w.p
	var pl: Vector2 = run.player_pos
	var face: Vector2 = run.facing
	match w.data.archetype:
		"arc":
			var shape: String = p.get("shape", "arc")
			for k in int(p.amount):
				var dir := face if k % 2 == 0 else -face
				if shape == "cross": dir = Vector2.RIGHT.rotated(PI / 2 * k + PI / 4)
				var c := pl + dir * float(p.area) * (0.55 if shape != "spin" else 0.0)
				var rad := float(p.area) * (0.6 if shape in ["arc", "slam", "cross"] else 1.0)
				if shape == "horizontal":
					c = pl + Vector2(sign(dir.x) if dir.x != 0 else 1.0, 0) * float(p.area) * 0.6
					rad = float(p.area) * 0.55
				for i in run.enemies.query_circle(c.x, c.y, rad, _q):
					_dmg(w, i, p.damage, pl, float(p.get("knockback", 0)))
				run.fx_slash(c, dir.angle(), rad / 60.0, w.evolved)
			if p.has("heal_on_kill"): pass
		"projectile": _shoot(w)
		"beam":
			for k in int(p.amount):
				var tgt = run.enemies.nearest(pl.x, pl.y, float(p.area))
				var dir := face
				if p.get("direction", "") != "facing" and tgt >= 0:
					dir = (Vector2(run.enemies.x[tgt], run.enemies.y[tgt]) - pl).normalized().rotated(0.15 * k)
				_beam(w, pl, dir, float(p.area), int(p.get("chain", 0)))
		"screen":
			var rect: Rect2 = run.view_rect()
			for i in run.enemies.n:
				if run.enemies.alive[i] == 1 and rect.has_point(Vector2(run.enemies.x[i], run.enemies.y[i])):
					_dmg(w, i, p.damage, pl)
			run.fx_flash(1.0)
			if p.has("freeze"): run.freeze_t = max(run.freeze_t, float(p.freeze) * run.stats.freeze_time)
		"zone":
			for k in int(p.amount): _place_zone(w)
		"cone":
			var base_ang = face.angle() if not p.has("rotate") else w.state.ang
			var dirs := [base_ang]
			if p.has("double"): dirs.append(base_ang + PI)
			for a in dirs:
				for i in run.enemies.query_circle(pl.x, pl.y, float(p.area), _q):
					var v := Vector2(run.enemies.x[i], run.enemies.y[i]) - pl
					if abs(wrapf(v.angle() - a, -PI, PI)) <= float(p.get("angle", 0.6)):
						_dmg(w, i, p.damage, pl, float(p.get("knockback", 0)))
				run.fx_cone(pl, a, float(p.area), float(p.get("angle", 0.6)), COLORS.cone)
		"aura":
			if p.get("pulse", false):
				var rad = float(p.area) * (1.0 + w.state.grow)
				for i in run.enemies.query_circle(pl.x, pl.y, rad, _q): _dmg(w, i, p.damage, pl, float(p.get("knockback", 0)))
				run.fx_ring(pl, rad, COLORS.aura)
		"companion":
			for k in int(p.amount):
				var a = run.time * 1.5 + TAU * k / max(1, int(p.amount))
				var from: Vector2 = pl + Vector2(cos(a), sin(a)) * 46.0
				var tgt = run.enemies.nearest(from.x, from.y, float(p.range))
				if tgt >= 0:
					var dir := (Vector2(run.enemies.x[tgt], run.enemies.y[tgt]) - from).normalized()
					_add_shot(w, from, dir)
		"car":
			for k in int(p.amount):
				var side := -1.0 if randf() < 0.5 else 1.0
				var vr: Rect2 = run.view_rect()
				var yy := pl.y + randf_range(-vr.size.y * 0.35, vr.size.y * 0.35)
				var sx := pl.x - side * (vr.size.x * 0.6)
				zones.append({"w": w, "x": sx, "y": yy, "vx": side * float(p.speed), "vy": 0.0, "r": float(p.size), "life": vr.size.x * 1.2 / float(p.speed), "tick": 0.2, "t": 0.0, "delay": 0.0, "dmg": p.damage, "kind": "car", "kb": 300.0})
		"mark":
			var rect: Rect2 = run.view_rect()
			var picked := 0
			for i in run.enemies.n:
				if picked >= int(p.amount): break
				if run.enemies.alive[i] == 1 and run.enemies.mark[i] <= 0.0 and rect.has_point(Vector2(run.enemies.x[i], run.enemies.y[i])) and randf() < 0.3:
					run.enemies.mark[i] = float(p.get("delay", 7.0))
					zones.append({"w": w, "target": i, "x": 0.0, "y": 0.0, "r": 0.0, "life": float(p.get("delay", 7.0)) + 0.05, "t": 0.0, "delay": float(p.get("delay", 7.0)), "dmg": p.damage, "kind": "mark", "tick": 99.0})
					picked += 1

# ---------- projectiles ----------
func _shoot(w: Dictionary) -> void:
	var p: Dictionary = w.p
	var pl: Vector2 = run.player_pos
	var mode: String = p.get("mode", "nearest")
	var n := int(p.amount)
	if mode == "rain":
		var vr: Rect2 = run.view_rect()
		for k in n:
			var at := vr.position + Vector2(randf() * vr.size.x, randf() * vr.size.y)
			zones.append({"w": w, "x": at.x, "y": at.y, "r": float(p.size) * 3.0, "life": 0.3, "tick": 1.0, "t": 0.0, "delay": 0.5, "dmg": p.damage, "kind": "strike"})
		return
	for k in n:
		var dir: Vector2
		match mode:
			"radial": dir = Vector2.RIGHT.rotated(TAU * k / n + run.time)
			"random": dir = Vector2.RIGHT.rotated(randf() * TAU)
			"facing": dir = run.facing.rotated((k - (n - 1) / 2.0) * 0.12)
			_:
				var tgt = run.enemies.nearest(pl.x, pl.y, float(p.range))
				dir = (Vector2(run.enemies.x[tgt], run.enemies.y[tgt]) - pl).normalized() if tgt >= 0 else run.facing
				dir = dir.rotated((k - (n - 1) / 2.0) * 0.18)
		var burst := int(p.get("burst", 1))
		for b in burst:
			_add_shot(w, pl, dir.rotated(randf_range(-0.05, 0.05) * b), b * float(p.get("burst_gap", 0.07)))
	Sfx.play("shoot", randf_range(0.9, 1.15))

func _add_shot(w: Dictionary, from: Vector2, dir: Vector2, delay := 0.0) -> void:
	var p: Dictionary = w.p
	if shots.size() > 600: return
	shots.append({"w": w, "x": from.x, "y": from.y, "vx": dir.x * float(p.speed), "vy": dir.y * float(p.speed),
		"life": float(p.range) / max(1.0, float(p.speed)), "pierce": int(p.get("pierce", 0)), "hits": {}, "size": float(p.size),
		"boomerang": p.get("boomerang", false), "back": false, "bounce": int(p.get("bounce", 0)), "delay": delay, "homing": p.get("mode", "") == "homing"})

func _update_shots(dt: float) -> void:
	var pl: Vector2 = run.player_pos
	var keep: Array = []
	for s in shots:
		if s.delay > 0.0:
			s.delay -= dt
			s.x = pl.x; s.y = pl.y
			keep.append(s)
			continue
		var w: Dictionary = s.w
		var p: Dictionary = w.p
		if s.homing:
			var tgt = run.enemies.nearest(s.x, s.y, 500.0)
			if tgt >= 0:
				var want := (Vector2(run.enemies.x[tgt], run.enemies.y[tgt]) - Vector2(s.x, s.y)).normalized() * float(p.speed)
				var v := Vector2(s.vx, s.vy).lerp(want, min(1.0, dt * 5.0))
				s.vx = v.x; s.vy = v.y
		if s.boomerang and s.back:
			var v2 := (pl - Vector2(s.x, s.y)).normalized() * float(p.speed)
			s.vx = v2.x; s.vy = v2.y
		s.x += s.vx * dt; s.y += s.vy * dt
		s.life -= dt
		if s.life <= 0.0:
			if s.boomerang and not s.back:
				s.back = true; s.life = 3.0; s.hits.clear()
			elif p.has("splash") and not s.boomerang: _splash(w, Vector2(s.x, s.y))
			if not (s.boomerang and s.back and s.life > 0.0): continue
		if s.boomerang and s.back and Vector2(s.x, s.y).distance_to(pl) < 24.0: continue
		var dead := false
		for i in run.enemies.query_circle(s.x, s.y, s.size, _q):
			if s.hits.has(i): continue
			s.hits[i] = true
			var mult := 1.0
			if p.has("undead_bonus"): mult += float(p.undead_bonus)
			_dmg(w, i, float(p.damage) * mult, Vector2(s.x - s.vx, s.y - s.vy), 60.0)
			if p.has("splash"): _splash(w, Vector2(s.x, s.y))
			if p.has("shards"):
				for k in int(p.shards): _add_shot_raw(w, Vector2(s.x, s.y), Vector2.RIGHT.rotated(TAU * k / int(p.shards)))
			if s.bounce > 0:
				s.bounce -= 1
				var nx = run.enemies.nearest(s.x, s.y, 400.0, i)
				if nx >= 0:
					var d := (Vector2(run.enemies.x[nx], run.enemies.y[nx]) - Vector2(s.x, s.y)).normalized() * float(p.speed)
					s.vx = d.x; s.vy = d.y; s.life = 1.0
				continue
			if s.pierce <= 0 and not s.boomerang:
				dead = true
				break
			s.pierce -= 1
		if not dead: keep.append(s)
	shots = keep

func _add_shot_raw(w: Dictionary, from: Vector2, dir: Vector2) -> void:
	if shots.size() > 600: return
	shots.append({"w": w, "x": from.x, "y": from.y, "vx": dir.x * 300.0, "vy": dir.y * 300.0, "life": 0.4, "pierce": 0, "hits": {}, "size": 5.0,
		"boomerang": false, "back": false, "bounce": 0, "delay": 0.0, "homing": false, "shard": true})

func _splash(w: Dictionary, at: Vector2) -> void:
	var rad = float(w.p.splash) * run.stats.area
	for i in run.enemies.query_circle(at.x, at.y, rad, _q): _dmg(w, i, float(w.p.damage) * 0.5, at, 40.0)
	run.fx_ring(at, rad, COLORS.projectile)

func _beam(w: Dictionary, from: Vector2, dir: Vector2, length: float, chain: int) -> void:
	var width := float(w.p.get("width", 10))
	var to := from + dir * length
	var mid := (from + to) / 2.0
	var last := -1
	for i in run.enemies.query_circle(mid.x, mid.y, length / 2.0 + width, _q):
		var e := Vector2(run.enemies.x[i], run.enemies.y[i])
		var t: float = clamp((e - from).dot(dir), 0.0, length)
		if e.distance_to(from + dir * t) <= width + run.enemies.r[i]:
			_dmg(w, i, w.p.damage, from, 30.0)
			last = i
	run.fx_line(from, to, width, COLORS.beam)
	if chain > 0 and last >= 0:
		var e2 := Vector2(run.enemies.x[last], run.enemies.y[last])
		var nx = run.enemies.nearest(e2.x, e2.y, 260.0, last)
		if nx >= 0:
			var d := Vector2(run.enemies.x[nx], run.enemies.y[nx]) - e2
			_beam(w, e2, d.normalized(), d.length() + 10.0, chain - 1)

# ---------- orbit and aura ----------
func _orbit(w: Dictionary, dt: float) -> void:
	var p: Dictionary = w.p
	var st: Dictionary = w.state
	st.phase += dt
	var on_t := float(p.duration)
	var off_t := float(p.get("pause", 0.0))
	if p.get("duration_inf", false) or off_t <= 0.0: st.on = true
	elif st.on and st.phase > on_t:
		st.on = false; st.phase = 0.0
	elif not st.on and st.phase > off_t:
		st.on = true; st.phase = 0.0
	if not st.on: return
	st.ang += dt * float(p.get("speed", 3.0))
	var pl: Vector2 = run.player_pos
	var n := int(p.amount)
	for k in n:
		var a: float = st.ang + TAU * k / n
		var at := pl + Vector2(cos(a), sin(a)) * float(p.area)
		orbiters.append({"x": at.x, "y": at.y, "w": w, "a": a})
		for i in run.enemies.query_circle(at.x, at.y, float(p.size), _q):
			if _can_hit(w, i, 0.45): _dmg(w, i, p.damage, pl, 90.0)
		if p.get("block", false): run.block_bullets(at, float(p.size) + 8.0)

func _aura_tick(w: Dictionary, dt: float) -> void:
	var p: Dictionary = w.p
	if p.get("pulse", false): return
	var pl: Vector2 = run.player_pos
	var rad := float(p.area)
	for i in run.enemies.query_circle(pl.x, pl.y, rad, _q):
		if _can_hit(w, i, float(p.cooldown)): _dmg(w, i, p.damage, pl, float(p.get("knockback", 0)))

func on_kill() -> void:
	for w in list:
		if w.p.has("grow_on_kill"): w.state.grow = min(2.0 if not w.p.get("grow_forever", false) else 20.0, w.state.grow + float(w.p.grow_on_kill))
		if w.p.has("heal_on_kill"): run.heal(float(w.p.heal_on_kill))

# ---------- zones ----------
func _place_zone(w: Dictionary) -> void:
	var p: Dictionary = w.p
	var pl: Vector2 = run.player_pos
	var at := pl
	match p.get("place", "under_player"):
		"random_near": at = pl + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 220.0)
		"nearest_enemy", "random_enemy":
			var tgt = run.enemies.nearest(pl.x, pl.y, 500.0) if p.place == "nearest_enemy" else run.random_visible_enemy()
			if tgt >= 0: at = Vector2(run.enemies.x[tgt], run.enemies.y[tgt])
			else: at = pl + Vector2.RIGHT.rotated(randf() * TAU) * 160.0
		"trail": at = pl
	var z := {"w": w, "x": at.x, "y": at.y, "r": float(p.area), "life": float(p.duration) + float(p.get("delay", 0.0)), "tick": float(p.get("tick", 0.5)),
		"t": 0.0, "delay": float(p.get("delay", 0.0)), "dmg": p.damage, "kind": "zone"}
	if p.get("follow", false): z.follow = true
	zones.append(z)

func _update_zones(dt: float) -> void:
	var keep: Array = []
	var pl: Vector2 = run.player_pos
	for z in zones:
		z.life -= dt
		if z.has("vx"):
			z.x += z.vx * dt; z.y += z.vy * dt
		if z.get("follow", false):
			z.x = lerp(float(z.x), pl.x, dt * 1.5); z.y = lerp(float(z.y), pl.y, dt * 1.5)
		if z.kind == "mark":
			var i: int = z.target
			if run.enemies.alive[i] == 0:
				continue
			if z.life <= 0.05:
				_dmg(z.w, i, z.dmg, Vector2(run.enemies.x[i], run.enemies.y[i]))
				run.fx_ring(Vector2(run.enemies.x[i], run.enemies.y[i]), 30.0, COLORS.mark)
				continue
			keep.append(z)
			continue
		if z.delay > 0.0:
			z.delay -= dt
			if z.delay <= 0.0:
				z.t = 0.0
				Sfx.play("explode", randf_range(0.9, 1.1))
			keep.append(z)
			continue
		z.t -= dt
		if z.t <= 0.0:
			z.t = z.tick
			for i in run.enemies.query_circle(z.x, z.y, z.r, _q):
				_dmg(z.w, i, z.dmg, Vector2(z.x, z.y), float(z.get("kb", 30.0)))
			if z.w.p.get("chain", 0) > 0 and z.kind == "zone" and z.tick >= 1.0 and randf() < 0.5:
				z.w.p.chain = int(z.w.p.chain)
		if z.life > 0.0: keep.append(z)
	zones = keep
