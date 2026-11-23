class_name SagaRules
extends RefCounted
## Modo Saga: the special rule of a saga phase (see data/sagas.json).
## secuela · naves · superpoder · combo · sigilo · grupo · coche · desastre (mezcla picks one per phase).

const POWERS := ["speed", "might", "shield", "magnet", "freeze"]
const PHASE_SECONDS := 480.0

var run
var saga: Dictionary
var phase := 0
var rule := ""
# combo
var combo := 0
var best_combo := 0
# sigilo
var alarm_t := 0.0
# superpoder
var power := ""
var power_left := 0.0
var power_t := 20.0
# coche
var car_dir := Vector2.RIGHT
var car_speed := 0.0
var ram_t := 0.0
# desastre: [x, y, r, fuse]
var hazards: Array = []
var hazard_t := 4.0
# naves: the scroll line below the player climbs up the map
var scroll_y := 0.0
# grupo: party of three, each with its own health
var party: Array = []
var party_hp: Array = []
var cur := 0
var swap_cd := 0.0

func _init(r, s: Dictionary, p: int) -> void:
	run = r
	saga = s
	phase = p
	rule = String(s.phases[p].get("rule", s.rule))

## Called once the run is built (stats, weapons, director exist).
func start() -> void:
	scroll_y = run.player_pos.y + 320.0
	if rule == "grupo":
		party = [run.character]
		for id in saga.get("party", []):
			if party.size() < 3 and id != run.character.id and Data.char_by_id.has(id): party.append(Data.char_by_id[id])
		for c in party: party_hp.append(-1.0)
		party_hp[0] = run.hp
	run.announce("%s · %s" % [saga.name, saga.phases[phase].title])

# ---------- numbers the run and the director ask for ----------
## Extra minutes of difficulty: later phases start harder.
func minute_offset() -> float:
	return 3.0 + phase * 1.5

func hp_mult() -> float:
	var k := 1.0 + 0.1 * phase
	if rule == "secuela": k *= 1.0 + 0.2 * phase
	return k

func spawn_mult() -> float:
	var k := 1.0
	if rule == "secuela": k *= 1.0 + 0.1 * phase
	if rule == "sigilo": k *= 1.6 if alarm_t > 0.0 else 0.55
	return k

func damage_mult() -> float:
	var k := 1.0
	if rule == "combo": k *= 1.0 + minf(1.0, floorf(combo / 25.0) * 0.1)
	if power == "might": k *= 1.8
	return k

func speed_mult() -> float:
	return 1.6 if power == "speed" else 1.0

func magnet_mult() -> float:
	return 6.0 if power == "magnet" else 1.0

# ---------- events ----------
func on_kill() -> void:
	if rule != "combo": return
	combo += 1
	best_combo = max(best_combo, combo)
	if combo % 100 == 0: run.announce(Loc.t("saga_combo", [combo]))

## Returns false when the hit is ignored (superpoder shield).
func on_hurt(burst: bool) -> bool:
	if power == "shield": return false
	if rule == "combo" and burst and combo >= 25:
		run.announce(Loc.t("saga_combo_lost", [combo]))
		combo = 0
	elif rule == "combo" and burst: combo = 0
	if rule == "sigilo":
		if alarm_t <= 0.0: run.announce(Loc.t("saga_alarm"))
		alarm_t = 15.0
	return true

## Grupo: when the active hero falls, the next one steps in. Returns true if the run goes on.
func on_death() -> bool:
	if rule != "grupo": return false
	party_hp[cur] = 0.0
	for k in range(1, party.size()):
		var n := (cur + k) % party.size()
		if party_hp[n] != 0.0:
			_switch_to(n)
			run.iframes = 2.0
			run.announce(Loc.t("saga_party_down", [party[(n + party.size() - 1) % party.size()].name, party[n].name]))
			return true
	return false

func swap() -> void:
	if rule != "grupo" or swap_cd > 0.0 or party.size() < 2: return
	for k in range(1, party.size()):
		var n := (cur + k) % party.size()
		if party_hp[n] != 0.0:
			_switch_to(n)
			return

func _switch_to(n: int) -> void:
	party_hp[cur] = run.hp
	cur = n
	run.character = party[n]
	run._load_sheets()
	run.rebuild_stats()
	run.hp = run.stats.hp_max if party_hp[n] < 0.0 else party_hp[n]
	party_hp[n] = run.hp
	swap_cd = 2.0
	run.fx_ring(run.player_pos, 70.0, Color("ffe08a"))

# ---------- per frame ----------
func update(dt: float) -> void:
	alarm_t = max(0.0, alarm_t - dt)
	swap_cd = max(0.0, swap_cd - dt)
	match rule:
		"superpoder": _powers(dt)
		"desastre": _hazards(dt)
		"naves": _scroll(dt)
		"coche": _ram(dt)
	if rule == "grupo": party_hp[cur] = run.hp

func _powers(dt: float) -> void:
	power_left -= dt
	if power_left <= 0.0: power = ""
	power_t -= dt
	if power_t <= 0.0:
		power_t = 60.0
		power = POWERS[randi() % POWERS.size()]
		power_left = 20.0
		if power == "freeze":
			run.freeze_t = 6.0
			power_left = 6.0
		run.announce(Loc.t("saga_power_" + power))
		run.fx_ring(run.player_pos, 120.0, Color("7fd4ff"))

func _hazards(dt: float) -> void:
	hazard_t -= dt
	if hazard_t <= 0.0:
		hazard_t = maxf(2.5, 6.0 - phase * 0.5)
		for k in 2 + int(run.time / 120.0):
			var a := randf() * TAU
			var d := randf_range(0.0, 260.0)
			hazards.append([run.player_pos.x + cos(a) * d, run.player_pos.y + sin(a) * d, randf_range(70.0, 120.0), 1.8])
	var keep: Array = []
	for h in hazards:
		h[3] -= dt
		if h[3] > 0.0:
			keep.append(h)
			continue
		var at := Vector2(h[0], h[1])
		for i in run.enemies.query_circle(at.x, at.y, h[2], run._q):
			run.damage_enemy(i, 40.0 + run.level * 4.0, (Vector2(run.enemies.x[i], run.enemies.y[i]) - at).normalized() * 200.0, null)
		if run.player_pos.distance_to(at) < h[2]:
			run.iframes = 0.0
			run.take_damage(18.0, true)
		run.fx_ring(at, h[2], Color("ff6a3a"))
		run.shake = maxf(run.shake, 0.2)
	hazards = keep

func _scroll(dt: float) -> void:
	scroll_y = minf(scroll_y - (45.0 + phase * 5.0) * dt, run.player_pos.y + 520.0)
	if run.player_pos.y > scroll_y:
		run.take_damage(30.0 * dt, false)
		run.player_pos.y -= 60.0 * dt

## Coche: always driving forward; the input only steers.
func move_car(dt: float, want: Vector2) -> Vector2:
	if want.length() > 0.1:
		var diff := wrapf(want.angle() - car_dir.angle(), -PI, PI)
		car_dir = car_dir.rotated(clampf(diff, -2.4 * dt, 2.4 * dt))
		car_speed = minf(1.0, car_speed + dt * 1.5)
	else:
		car_speed = maxf(0.35, car_speed - dt * 0.8)
	return car_dir * car_speed * 1.7

func _ram(dt: float) -> void:
	ram_t -= dt
	if ram_t > 0.0: return
	ram_t = 0.12
	for i in run.enemies.query_circle(run.player_pos.x, run.player_pos.y, 34.0, run._q):
		run.damage_enemy(i, 12.0 + run.level * 1.5, car_dir * 420.0, null)

# ---------- drawing ----------
func draw_world(c: CanvasItem) -> void:
	for h in hazards:
		var k: float = 1.0 - h[3] / 1.8
		c.draw_circle(Vector2(h[0], h[1]), h[2], Color(1, 0.3, 0.15, 0.08 + 0.18 * k))
		c.draw_arc(Vector2(h[0], h[1]), h[2], 0, TAU, 40, Color(1, 0.4, 0.2, 0.5 + 0.5 * k), 3.0)
		c.draw_arc(Vector2(h[0], h[1]), h[2] * k, 0, TAU, 40, Color(1, 0.8, 0.3, 0.7), 2.0)
	if rule == "naves":
		var vr: Rect2 = run.view_rect().grow(40.0)
		c.draw_rect(Rect2(vr.position.x, scroll_y, vr.size.x, vr.end.y - scroll_y + 200.0), Color(0.9, 0.2, 0.3, 0.22))
		c.draw_line(Vector2(vr.position.x, scroll_y), Vector2(vr.end.x, scroll_y), Color(1, 0.4, 0.5, 0.9), 4.0)
	if rule == "coche":
		c.draw_line(run.player_pos, run.player_pos + car_dir * 46.0, Color(1, 0.9, 0.3, 0.6), 3.0)

## One line for the HUD under the timer.
func hud_text() -> String:
	match rule:
		"combo": return Loc.t("saga_hud_combo", [combo, roundi((damage_mult() - 1.0) * 100.0)])
		"sigilo": return Loc.t("saga_hud_alarm", [ceili(alarm_t)]) if alarm_t > 0.0 else Loc.t("saga_hud_hidden")
		"superpoder": return Loc.t("saga_power_" + power) + " %d" % ceili(power_left) if power != "" else Loc.t("saga_hud_next_power", [ceili(power_t)])
		"grupo":
			var parts: Array = []
			for k in party.size():
				var h: float = party_hp[k]
				parts.append(("> " if k == cur else "") + party[k].name + (" (KO)" if h == 0.0 else ""))
			return "  ·  ".join(parts) + "   [" + Controls.key_name("swap") + "]"
		"naves": return Loc.t("saga_hud_scroll")
		"coche": return Loc.t("saga_hud_car")
		"desastre": return Loc.t("saga_hud_disaster")
		"secuela": return saga.phases[phase].title
	return ""
