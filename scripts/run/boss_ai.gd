class_name BossAI
extends RefCounted
## Attacks and phases for bosses, Estrellas Invitadas and El Productor Ejecutivo (plan A4 and A5).
## Every attack is telegraphed first (red marks on the floor), then lands.
## Phase 2 starts at 50 % health (faster, more bullets); phase 3 at 25 % (enraged).

const T := EnemyPool.T
## Attack set per art set; other stages pick two from the list by their id.
const SETS := {
	"forest": ["charge", "slam"],      # El Leñador: embestida y hachazo
	"west": ["ring", "summon"],        # pistolero: ráfaga en círculo y forajidos
	"station": ["spiral", "charge"],   # coloso de cromo: espiral láser y embestida
	"noir": ["fan", "summon"],         # el capo: abanico de balas y matones
	"jungle": ["slam", "spiral"],      # el ídolo: pisotón y espiral de dardos
}
const ALL := ["charge", "slam", "ring", "summon", "spiral", "fan"]

var run
var state := {}          # enemy slot -> {cd, attack, phase}
var warnings: Array = [] # {kind, x, y, r, t, life, a?, len?}
var pattern: Array = []

func _init(r) -> void:
	run = r
	pattern = SETS.get(run.art_key, [])
	if not SETS.has(run.stage.get("art", "")):
		var h: int = abs(hash(run.stage.get("id", "")))
		pattern = [ALL[h % ALL.size()], ALL[(h / 7 + 1) % ALL.size()]]
		if pattern[0] == pattern[1]: pattern[1] = ALL[(h + 3) % ALL.size()]

func phase(i: int) -> int:
	var f: float = run.enemies.hp[i] / max(1.0, run.enemies.hp_max[i])
	return 3 if f < 0.25 else (2 if f < 0.5 else 1)

func update(dt: float) -> void:
	var e: EnemyPool = run.enemies
	for i in state.keys():
		if e.alive[i] == 0 or not _is_special(e.type[i]): state.erase(i)
	for i in e.names:
		if e.alive[i] == 0 or state.has(i): continue
		if _is_special(e.type[i]): state[i] = {"cd": 3.0, "next": 0, "phase": 1}
	if run.freeze_t > 0.0: return
	for i in state:
		var s: Dictionary = state[i]
		var t := e.type[i]
		if t == T.PRODUCTOR:
			_productor(i, s, dt)
			continue
		var ph := phase(i)
		if ph != s.phase:
			s.phase = ph
			e.sp[i] *= 1.15
			if t == T.BOSS: run.announce(Loc.t("boss_phase", [e.names.get(i, "")]))
		s.cd -= dt * (1.0 + 0.35 * (ph - 1))
		if s.cd <= 0.0:
			var atk: String = "charge" if t != T.BOSS else pattern[s.next % pattern.size()]
			s.next += 1
			s.cd = (4.5 if t == T.BOSS else 6.0)
			_start(i, atk, ph)
	_update_warnings(dt)

func _is_special(t: int) -> bool:
	return t == T.BOSS or t == T.GUEST or t == T.PRODUCTOR

func _pos(i: int) -> Vector2:
	return Vector2(run.enemies.x[i], run.enemies.y[i])

func _start(i: int, atk: String, ph: int) -> void:
	var at := _pos(i)
	var pl: Vector2 = run.player_pos
	match atk:
		"charge":
			var dir := (pl - at).normalized()
			warnings.append({"kind": "line", "x": at.x, "y": at.y, "a": dir.angle(), "len": 360.0, "r": run.enemies.r[i], "t": 0.0, "life": 0.8, "src": i, "atk": "charge"})
			run.enemies.stun[i] = 0.8
		"slam":
			for k in (1 if ph == 1 else ph):
				var off := Vector2.ZERO if k == 0 else Vector2.RIGHT.rotated(randf() * TAU) * 130.0
				warnings.append({"kind": "circle", "x": pl.x + off.x, "y": pl.y + off.y, "r": 110.0, "t": 0.0, "life": 1.1, "src": i, "atk": "slam"})
		"ring":
			_bullets(at, 12 + 4 * ph, randf() * TAU, TAU, 170.0)
		"spiral":
			warnings.append({"kind": "spiral", "x": at.x, "y": at.y, "r": 0.0, "t": 0.0, "life": 1.6 + 0.4 * ph, "src": i, "atk": "spiral", "acc": 0.0})
		"fan":
			var a := (pl - at).angle()
			for w in ph:
				_bullets(at, 7, a - 0.6, 1.2, 230.0 + 30.0 * w)
		"summon":
			var n := 6 + 3 * ph
			for k in n:
				var p := at + Vector2.RIGHT.rotated(TAU * k / n) * 70.0
				run.enemies.spawn(T.HORDE, p.x, p.y, run.director.hp_mult() * 1.5, 20.0)
			run.fx_ring(at, 90.0, Color("b070ff"))
	Sfx.play("boss", 1.3)

func _bullets(at: Vector2, n: int, a0: float, spread: float, speed: float) -> void:
	for k in n:
		var a = a0 + (spread * k / n if spread >= TAU else spread * k / max(1, n - 1))
		if run.ebullets.size() < 160:
			run.ebullets.append({"x": at.x, "y": at.y, "vx": cos(a) * speed, "vy": sin(a) * speed, "life": 4.0, "boss": true})

func _update_warnings(dt: float) -> void:
	var keep: Array = []
	for w in warnings:
		w.t += dt
		var src: int = w.src
		var alive: bool = run.enemies.alive[src] == 1
		if w.atk == "spiral" and alive:
			w.acc += dt
			while w.acc > 0.09:
				w.acc -= 0.09
				var a: float = w.t * 7.0
				_bullets(_pos(src), 2, a, PI, 200.0)
		if w.t >= w.life:
			if alive: _land(w)
			continue
		keep.append(w)
	warnings = keep

func _land(w: Dictionary) -> void:
	match w.atk:
		"charge":
			var d := Vector2.RIGHT.rotated(w.a)
			run.enemies.kx[w.src] = d.x * 2900.0
			run.enemies.ky[w.src] = d.y * 2900.0
			run.shake = max(run.shake, 0.2)
		"slam":
			var c := Vector2(w.x, w.y)
			if run.player_pos.distance_to(c) < w.r: run.take_damage(18.0 + run.time / 60.0, true)
			run.fx_ring(c, w.r, Color("ff5030"))
			run.shake = max(run.shake, 0.35)
			Sfx.play("explode", 0.8)

## El Productor Ejecutivo: cannot be frozen, always gets faster, and when you run too far
## he "reschedules" and appears right next to you.
func _productor(i: int, s: Dictionary, dt: float) -> void:
	s.cd -= dt
	var d: float = _pos(i).distance_to(run.player_pos)
	if s.cd <= 0.0 and d > 520.0:
		s.cd = 5.0
		var a := randf() * TAU
		var to: Vector2 = run.player_pos + Vector2(cos(a), sin(a)) * 330.0
		run.fx_ring(_pos(i), 80.0, Color(0.2, 0.15, 0.1))
		run.enemies.x[i] = to.x
		run.enemies.y[i] = to.y
		run.fx_ring(to, 120.0, Color(0.3, 0.05, 0.05))
		run.announce(Loc.t("productor_tp"))
		Sfx.play("boss", 0.5)

func draw(c: CanvasItem) -> void:
	for w in warnings:
		var k: float = w.t / w.life
		var col := Color(1, 0.15, 0.1, 0.25 + 0.35 * k)
		match w.kind:
			"circle":
				c.draw_circle(Vector2(w.x, w.y), w.r * k, Color(1, 0.1, 0.05, 0.18))
				c.draw_arc(Vector2(w.x, w.y), w.r, 0, TAU, 40, col, 3.0)
			"line":
				var src: int = w.src
				var from := _pos(src)
				var to = from + Vector2.RIGHT.rotated(w.a) * w.len
				c.draw_line(from, to, Color(1, 0.1, 0.05, 0.18), w.r * 2.0)
				c.draw_line(from, from + (to - from) * k, col, 4.0)
