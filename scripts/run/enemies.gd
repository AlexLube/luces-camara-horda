class_name EnemyPool
extends RefCounted
## All enemies of a run in flat packed arrays (no node per enemy), a hashed spatial grid for
## collisions and weapon queries, and the ten behaviour families of the catalogue.

enum T { HORDE, SWARM, TANK, SHOOTER, KAMIKAZE, JUMPER, ELITE, STAR, GUEST, BOSS, PRODUCTOR, WALL }
const TYPES := {
	T.HORDE:     {"sprite": "enemy", "hp": 10.0,  "sp": 62.0,  "dmg": 8.0,  "r": 16.0, "sc": 0.82, "xp": 1,  "tint": Color(1, 1, 1)},
	T.SWARM:     {"sprite": "enemy", "hp": 4.0,   "sp": 118.0, "dmg": 5.0,  "r": 11.0, "sc": 0.55, "xp": 1,  "tint": Color(1.0, 0.85, 0.85)},
	T.TANK:      {"sprite": "tank",  "hp": 70.0,  "sp": 44.0,  "dmg": 15.0, "r": 26.0, "sc": 0.82, "xp": 10, "tint": Color(1, 1, 1)},
	T.SHOOTER:   {"sprite": "enemy", "hp": 14.0,  "sp": 58.0,  "dmg": 8.0,  "r": 16.0, "sc": 0.8,  "xp": 2,  "tint": Color(0.75, 0.85, 1.0)},
	T.KAMIKAZE:  {"sprite": "enemy", "hp": 8.0,   "sp": 145.0, "dmg": 18.0, "r": 15.0, "sc": 0.72, "xp": 2,  "tint": Color(1.0, 0.6, 0.55)},
	T.JUMPER:    {"sprite": "enemy", "hp": 12.0,  "sp": 70.0,  "dmg": 9.0,  "r": 16.0, "sc": 0.8,  "xp": 2,  "tint": Color(0.85, 0.75, 1.0, 0.85)},
	T.ELITE:     {"sprite": "enemy", "hp": 40.0,  "sp": 70.0,  "dmg": 12.0, "r": 18.0, "sc": 0.92, "xp": 10, "tint": Color(1, 1, 1), "outline": true, "chest": 1},
	T.STAR:      {"sprite": "tank",  "hp": 300.0, "sp": 50.0,  "dmg": 18.0, "r": 28.0, "sc": 0.95, "xp": 30, "tint": Color(1, 1, 1), "spot": true, "chest": 3},
	T.GUEST:     {"sprite": "tank",  "hp": 900.0, "sp": 56.0,  "dmg": 22.0, "r": 32.0, "sc": 1.15, "xp": 50, "tint": Color(1, 0.95, 0.8), "spot": true, "chest": 3},
	T.BOSS:      {"sprite": "boss",  "hp": 4000.0,"sp": 64.0,  "dmg": 25.0, "r": 46.0, "sc": 1.0,  "xp": 100,"tint": Color(1, 1, 1), "chest": 5, "boss": true},
	T.PRODUCTOR: {"sprite": "boss",  "hp": 655350.0,"sp": 70.0,"dmg": 99999.0,"r": 60.0,"sc": 1.45,"xp": 0, "tint": Color(0.35, 0.3, 0.25), "boss": true},
	T.WALL:      {"sprite": "enemy", "hp": 12.0,  "sp": 50.0,  "dmg": 8.0,  "r": 16.0, "sc": 0.82, "xp": 1,  "tint": Color(0.95, 0.95, 0.8)},
}
const MAX := 1600
const CELL := 64.0
const NB := 4096

var n := 0                      # highest used slot + 1
var alive := PackedByteArray()
var type := PackedInt32Array()
var x := PackedFloat32Array(); var y := PackedFloat32Array()
var hp := PackedFloat32Array(); var hp_max := PackedFloat32Array()
var sp := PackedFloat32Array(); var dmg := PackedFloat32Array(); var r := PackedFloat32Array(); var sc := PackedFloat32Array()
var kx := PackedFloat32Array(); var ky := PackedFloat32Array()      # knockback velocity
var stun := PackedFloat32Array(); var slow := PackedFloat32Array(); var flash := PackedFloat32Array()
var anim := PackedFloat32Array(); var face := PackedFloat32Array(); var timer := PackedFloat32Array()
var mark := PackedFloat32Array()   # Cinta de Vídeo Maldita countdown
var free_slots: Array[int] = []
var count := 0
var names := {}                    # slot -> display name (guests, bosses)

# spatial grid (counting sort into hashed buckets, rebuilt every frame)
var cell_start := PackedInt32Array(); var cell_count := PackedInt32Array(); var order := PackedInt32Array()
var _cell_of := PackedInt32Array()

func _init() -> void:
	for a in [alive]: a.resize(MAX)
	for a in [type, order, _cell_of]: a.resize(MAX)
	for a in [x, y, hp, hp_max, sp, dmg, r, sc, kx, ky, stun, slow, flash, anim, face, timer, mark]: a.resize(MAX)
	cell_start.resize(NB); cell_count.resize(NB)

func spawn(t: int, px: float, py: float, hp_mult := 1.0, sp_add := 0.0) -> int:
	var i: int
	if free_slots.size() > 0: i = free_slots.pop_back()
	elif n < MAX:
		i = n; n += 1
	else: return -1
	var d: Dictionary = TYPES[t]
	alive[i] = 1; type[i] = t; x[i] = px; y[i] = py
	hp[i] = d.hp * hp_mult; hp_max[i] = hp[i]; sp[i] = d.sp + sp_add; dmg[i] = d.dmg; r[i] = d.r; sc[i] = d.sc
	kx[i] = 0; ky[i] = 0; stun[i] = 0; slow[i] = 0; flash[i] = 0; anim[i] = randf() * 8.0; face[i] = 1; timer[i] = randf() * 2.0; mark[i] = 0
	count += 1
	return i

func remove(i: int) -> void:
	if alive[i] == 0: return
	alive[i] = 0; count -= 1; free_slots.append(i); names.erase(i)

func clear() -> void:
	for i in n: alive[i] = 0
	n = 0; count = 0; free_slots.clear(); names.clear()

static func _h(cx: int, cy: int) -> int:
	return ((cx * 73856093) ^ (cy * 19349663)) & (NB - 1)

func rebuild_grid() -> void:
	cell_count.fill(0)
	for i in n:
		if alive[i] == 0:
			_cell_of[i] = -1
			continue
		var c := _h(floori(x[i] / CELL), floori(y[i] / CELL))
		_cell_of[i] = c
		cell_count[c] += 1
	var acc := 0
	for c in NB:
		cell_start[c] = acc
		acc += cell_count[c]
	var fill := cell_start.duplicate()
	for i in n:
		var c := _cell_of[i]
		if c < 0: continue
		order[fill[c]] = i
		fill[c] += 1

## Indices of living enemies whose body touches the circle.
func query_circle(cx: float, cy: float, rad: float, out: PackedInt32Array) -> PackedInt32Array:
	out.clear()
	var x0 := floori((cx - rad - 64.0) / CELL); var x1 := floori((cx + rad + 64.0) / CELL)
	var y0 := floori((cy - rad - 64.0) / CELL); var y1 := floori((cy + rad + 64.0) / CELL)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > NB:  # huge query: scan everything
		for i in n:
			if alive[i] == 1:
				var rr := rad + r[i]
				if (x[i] - cx) ** 2 + (y[i] - cy) ** 2 <= rr * rr: out.append(i)
		return out
	var seen := {}
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var c := _h(gx, gy)
			if seen.has(c): continue
			seen[c] = true
			var s := cell_start[c]
			for k in range(s, s + cell_count[c]):
				var i := order[k]
				var rr := rad + r[i]
				if (x[i] - cx) ** 2 + (y[i] - cy) ** 2 <= rr * rr: out.append(i)
	return out

func nearest(px: float, py: float, max_d := 99999.0, skip := -1) -> int:
	var best := -1; var bd := max_d * max_d
	for i in n:
		if alive[i] == 0 or i == skip: continue
		var d := (x[i] - px) ** 2 + (y[i] - py) ** 2
		if d < bd:
			bd = d; best = i
	return best

## Movement, knockback, behaviours. Returns contact damage dealt to the player this frame.
func update(dt: float, px: float, py: float, prad: float, freeze: bool, on_shoot: Callable, on_explode: Callable) -> float:
	var hurt := 0.0
	for i in n:
		if alive[i] == 0: continue
		flash[i] = max(0.0, flash[i] - dt)
		if mark[i] > 0.0: mark[i] -= dt
		var t := type[i]
		var dx := px - x[i]; var dy := py - y[i]
		var d := sqrt(dx * dx + dy * dy) + 0.001
		if freeze and t != T.PRODUCTOR:
			continue
		if stun[i] > 0.0:
			stun[i] -= dt
		else:
			var speed := sp[i] * (1.0 - slow[i])
			var vx := dx / d * speed; var vy := dy / d * speed
			match t:
				T.SHOOTER:
					if d < 240.0:
						vx = -vx * 0.5; vy = -vy * 0.5
					timer[i] -= dt
					if timer[i] <= 0.0 and d < 520.0:
						timer[i] = 3.6
						on_shoot.call(x[i], y[i], dx / d, dy / d)
				T.JUMPER:
					timer[i] -= dt
					if timer[i] <= 0.0 and d < 600.0:
						timer[i] = 4.0
						var a := randf() * TAU
						x[i] = px + cos(a) * 140.0; y[i] = py + sin(a) * 140.0
				T.PRODUCTOR:
					sp[i] += dt * 2.0
			x[i] += (vx + kx[i]) * dt; y[i] += (vy + ky[i]) * dt
			anim[i] += dt * speed * 0.15
		kx[i] *= max(0.0, 1.0 - dt * 8.0); ky[i] *= max(0.0, 1.0 - dt * 8.0)
		slow[i] = max(0.0, slow[i] - dt * 0.5)
		if abs(dx) > 2.0: face[i] = sign(dx)
		var reach := prad + r[i] * 0.7
		if d < reach:
			if t == T.KAMIKAZE:
				on_explode.call(x[i], y[i])
				hurt += dmg[i]
				remove(i)
				continue
			hurt += dmg[i] * dt * 2.0
		# far behind the camera: bring them back ahead of the player (keeps the horde around you)
		if d > 1400.0 and t != T.BOSS and t != T.PRODUCTOR and t != T.GUEST:
			var a2 := atan2(dy, dx) + randf_range(-0.6, 0.6)
			x[i] = px + cos(a2) * 760.0; y[i] = py + sin(a2) * 760.0
	return hurt

## Push overlapping enemies apart (one pass over the grid; cheap enough for ~1500 bodies).
func separate(dt: float) -> void:
	for c in NB:
		var cnt := cell_count[c]
		if cnt < 2: continue
		var s := cell_start[c]
		for a in range(s, s + cnt):
			var i := order[a]
			for b in range(a + 1, min(s + cnt, a + 6)):
				var j := order[b]
				var dx := x[j] - x[i]; var dy := y[j] - y[i]
				var rr := (r[i] + r[j]) * 0.8
				var d2 := dx * dx + dy * dy
				if d2 < rr * rr and d2 > 0.01:
					var d := sqrt(d2)
					var push = (rr - d) * 0.5 * min(1.0, dt * 12.0)
					var hi := 0.15 if type[i] >= T.STAR else 1.0
					var hj := 0.15 if type[j] >= T.STAR else 1.0
					x[i] -= dx / d * push * hi; y[i] -= dy / d * push * hi
					x[j] += dx / d * push * hj; y[j] += dy / d * push * hj
