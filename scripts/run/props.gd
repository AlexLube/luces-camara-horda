class_name SetProps
extends RefCounted
## Atrezzo: crates you can push, pyrotechnic barrels that blow up and small set fires you put out.
## They feed the hidden feats of the Premios (Grip Martínez, Bill Mecha, Toni Nitrato).

const SPAWN_EVERY := 3.0
const FAR := 1700.0
const HIT_R := 46.0           # a weapon hit this close to a barrel sets it off
const STOMP := 0.8            # seconds standing on a fire to put it out

var run
var items: Array = []         # {k, x, y, ...}
var debris: Array = []        # {k, x, y, t}
var spawn_t := 1.0
var crates_moved := 0
var barrels_broken := 0
var fires_out := 0
var tex := {}

func _init(r) -> void:
	run = r
	for n in ["crate", "barrel", "fire1", "fire2", "smoke", "barrel_broken"]:
		tex[n] = Data.tex("res://assets/sprites/props/%s.png" % n)

## How many of each prop the stage keeps around the player.
func _wanted() -> Dictionary:
	var a: String = run.stage.get("art", "")
	var fires := 3 if a in ["broadway", "wasteland", "doom", "dragon", "bunker"] else 1
	return {"crate": 3, "barrel": 4, "fire": fires}

func update(dt: float) -> void:
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = SPAWN_EVERY
		_spawn()
	var pp: Vector2 = run.player_pos
	var keep: Array = []
	var blow: Array = []
	for it in items:
		var at := Vector2(it.x, it.y)
		var d := at.distance_to(pp)
		if d > FAR: continue
		match it.k:
			"crate": _push(it, at, d, dt)
			"barrel":
				if it.fuse < 0.0 and d < 34.0: it.fuse = 0.5
				if it.fuse >= 0.0:
					it.fuse -= dt
					if it.fuse <= 0.0:
						blow.append(it)
						continue
			"fire":
				it.tick -= dt
				if it.tick <= 0.0:
					it.tick = 0.5
					for i in run.enemies.query_circle(at.x, at.y, 40.0, run._q):
						run.damage_enemy(i, 6.0 + run.level * 0.6, Vector2.ZERO, null)
				if d < 40.0:
					it.stomp += dt
					if run.character.get("id", "") != "toni_nitrato": run.take_damage(5.0 * dt, false)
					if it.stomp >= STOMP:
						_put_out(it)
						continue
		keep.append(it)
	items = keep
	for it in blow: _explode(it)
	var dk: Array = []
	for d in debris:
		d.t -= dt
		if d.t > 0.0: dk.append(d)
	debris = dk

func _spawn() -> void:
	var want := _wanted()
	var have := {}
	for it in items: have[it.k] = int(have.get(it.k, 0)) + 1
	for k in want:
		if int(have.get(k, 0)) >= int(want[k]): continue
		var at: Vector2 = run.director.edge_point() + (run.director.edge_point() - run.player_pos).normalized() * 120.0
		var it := {"k": k, "x": at.x, "y": at.y}
		match k:
			"crate":
				it.moved = 0.0
				it.counted = false
			"barrel": it.fuse = -1.0
			"fire":
				it.stomp = 0.0
				it.tick = 0.5
		items.append(it)
		return

## Walk into a crate to push it; once it has travelled a bit it counts as moved.
func _push(it: Dictionary, at: Vector2, d: float, dt: float) -> void:
	if d > 38.0 or run.move_dir.length() < 0.1: return
	var away: Vector2 = (at - run.player_pos).normalized()
	if away.dot(run.move_dir.normalized()) < 0.2: return
	var step: float = float(run.stats.move_speed) * run.move_dir.length() * dt
	it.x += away.x * step
	it.y += away.y * step
	it.moved += step
	if not it.counted and it.moved >= 48.0:
		it.counted = true
		crates_moved += 1

## A weapon struck an enemy here: barrels close by catch the blast.
func on_hit(at: Vector2) -> void:
	for it in items:
		if it.k == "barrel" and it.fuse < 0.0 and absf(it.x - at.x) < HIT_R and absf(it.y - at.y) < HIT_R: it.fuse = 0.25

func _explode(it: Dictionary) -> void:
	var at := Vector2(it.x, it.y)
	barrels_broken += 1
	for i in run.enemies.query_circle(at.x, at.y, 110.0, run._q):
		run.damage_enemy(i, 30.0 + run.level * 3.0, (Vector2(run.enemies.x[i], run.enemies.y[i]) - at).normalized() * 260.0, null)
	for o in items:   # chain reaction
		if o.k == "barrel" and o.fuse < 0.0 and at.distance_to(Vector2(o.x, o.y)) < 140.0: o.fuse = 0.2
	run.fx_ring(at, 110.0, Color("ff8a3a"))
	run.shake = maxf(run.shake, 0.15)
	Sfx.play("explode", 1.1)
	debris.append({"k": "barrel_broken", "x": at.x, "y": at.y, "t": 4.0})
	var r := randf()
	if r < 0.15: run.pickups.append({"k": "food", "x": at.x, "y": at.y})
	elif r < 0.75: run.pickups.append({"k": "coin", "x": at.x, "y": at.y, "v": float(randi_range(2, 6))})

func _put_out(it: Dictionary) -> void:
	fires_out += 1
	debris.append({"k": "smoke", "x": it.x, "y": it.y, "t": 1.5})
	run.pickups.append({"k": "coin", "x": it.x, "y": it.y + 20.0, "v": 3.0})
	Sfx.play("pickup", 0.5)

func draw_world(c: CanvasItem) -> void:
	var vr: Rect2 = run.view_rect().grow(80.0)
	for d in debris:
		if not vr.has_point(Vector2(d.x, d.y)): continue
		var a: float = clampf(d.t, 0.0, 1.0)
		_blit(c, tex[d.k], Vector2(d.x, d.y), 0.7, Color(1, 1, 1, a))
	for it in items:
		var at := Vector2(it.x, it.y)
		if not vr.has_point(at): continue
		match it.k:
			"crate": _blit(c, tex.crate, at, 0.7, Color.WHITE)
			"barrel":
				var m := Color.WHITE
				if it.fuse >= 0.0 and int(run.time * 16.0) % 2 == 0: m = Color(2.0, 1.4, 1.2)
				_blit(c, tex.barrel, at, 0.62, m)
			"fire":
				var k := 1.0 - clampf(it.stomp / STOMP, 0.0, 0.7)
				_blit(c, tex.fire1 if int(run.time * 6.0 + it.x) % 2 == 0 else tex.fire2, at, 0.75 * k, Color.WHITE)

func _blit(c: CanvasItem, t: Texture2D, at: Vector2, sc: float, m: Color) -> void:
	if t == null: return
	var s := t.get_size() * sc
	c.draw_texture_rect(t, Rect2(at - Vector2(s.x / 2.0, s.y * 0.8), s), false, m)
