class_name Run
extends Node2D
## One run ("rodaje"): player, horde, weapons, pickups, level-ups, latas, calendar and results.
## Everything in the world is drawn by this node in one _draw pass (y-sorted), so 1000+ enemies
## cost one canvas item instead of 1000 nodes.

signal exit_to_menu
signal retry

const T := EnemyPool.T
const PLAYER_R := 16.0
const PLAYER_SCALE := 0.82
const CHUNK := 640.0
const MAX_GEMS := 380

# --- setup ---
var character: Dictionary
var stage: Dictionary
var art: Dictionary
var art_key := "forest"
var duration := 1800.0
var bot := false                    # autoplay for tests and the attract demo
var debug_evolve_anytime := false

# --- systems (the API weapons.gd relies on) ---
var stats: Dictionary = {}
var enemies := EnemyPool.new()
var weapons: WeaponSystem
var director: Director
var boss_ai: BossAI
var hud
var player_pos := Vector2.ZERO
var facing := Vector2.RIGHT
var move_dir := Vector2.ZERO
var time := 0.0
var freeze_t := 0.0

# --- player state ---
var hp := 100.0
var level := 1
var xp := 0.0
var passives := {}
var banished := {}
var union_parts_used := {}
var used_rerolls := 0
var used_skips := 0
var used_banishes := 0
var revivals_used := 0
var iframes := 0.0
var hurt_flash := 0.0
var pending_levels := 0
var state := "play"                 # play, levelup, chest, pause, over
var completed := false

# --- run counters for results / saves ---
var kills := 0
var coins := 0.0
var chests := 0
var food := 0
var bosses_killed := 0
var evolutions := 0
var evolved_ids: Array = []
var productor_killed := false
var dmg_by_weapon := {}

# --- world objects ---
var pickups: Array = []
var gem_count := 0
var vip_gem = null
var ebullets: Array = []
var fx: Array = []
var numbers: Array = []
var corpses: Array = []
var props := {}                     # chunk key -> Array of [name, x, y, scale]
var flash := 0.0
var shake := 0.0
var announce_text := ""
var announce_t := 0.0

# --- input ---
var touch_id := -1
var touch_origin := Vector2.ZERO
var touch_vec := Vector2.ZERO

# --- drawing ---
var sheets := {}
var cam: Camera2D
var font: Font
var _q := PackedInt32Array()
var _keys := PackedInt64Array()
var _vis_props: Array = []
var _hit_sfx_t := 0.0

func setup(char_data: Dictionary, stage_data: Dictionary) -> void:
	character = char_data
	stage = stage_data
	art = Data.stage_art(stage)
	art_key = stage.get("art", "forest")
	if not Data.art_sets.has(art_key): art_key = "forest"
	duration = float(stage.get("minutes", 30)) * 60.0

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	if character.is_empty(): setup(Data.characters[0], Data.stages[0])
	_load_sheets()
	Music.play(Music.track_for(stage))
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	weapons = WeaponSystem.new(self)
	director = Director.new(self)
	boss_ai = BossAI.new(self)
	rebuild_stats()
	hp = stats.hp_max
	var wid: String = character.get("weapon", "claqueta")
	if wid == "random" or not Data.weapons.has(wid):
		var pool := Data.weapon_pool(character)
		wid = pool[randi() % pool.size()]
	weapons.add(wid)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.run = self
	add_child(hud)
	for p in art.get("start", []):
		props[Vector2i(99999, 0)] = props.get(Vector2i(99999, 0), []) + [[p[0], float(p[1]), float(p[2]), art.get("land_scale", 1.0) if p[0] == art.get("land", "") else 0.8]]

# ---------- assets ----------
func _sheet(path: String, frames: int) -> Dictionary:
	var t: Texture2D = Data.tex(path)
	if t == null: return {}
	return {"tex": t, "white": _white(t), "n": frames, "fw": t.get_width() / frames, "fh": t.get_height()}

## White silhouette of a sprite sheet (hit flash and elite outline), made once per stage.
static func _white(t: Texture2D) -> Texture2D:
	var src := t.get_image()
	if src == null: return t
	if src.is_compressed(): src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var white := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(white, src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(out)

func _load_sheets() -> void:
	var base := "res://assets/sprites/stages/%s/" % art_key
	sheets.enemy = _sheet(base + "enemy.png", int(art.enemy))
	sheets.tank = _sheet(base + "tank.png", int(art.tank))
	sheets.boss = _sheet(base + "boss.png", int(art.boss))
	sheets.productor = _sheet("res://assets/sprites/productor/productor.png", 6)
	if art.has("die"): sheets.die = _sheet(base + art.die + ".png", int(art.die_frames))
	var cdir := "res://assets/sprites/characters/%s/" % character.get("id", "")
	sheets.run = _sheet(cdir + "run.png", 8) if ResourceLoader.exists(cdir + "run.png") else _sheet("res://assets/sprites/player/player_run.png", 8)
	sheets.idle = _sheet(cdir + "idle.png", 4) if ResourceLoader.exists(cdir + "idle.png") else _sheet("res://assets/sprites/player/player_idle.png", 4)
	sheets.slash = _sheet("res://assets/sprites/fx/fxs_slash.png", 6)
	sheets.hit = _sheet("res://assets/sprites/fx/fxs_hit.png", 6)
	sheets.fxflash = _sheet("res://assets/sprites/fx/fxs_flash.png", 6)
	sheets.ground = Data.tex(base + "ground.jpg")
	for p in art.props: sheets["p_" + p[0]] = Data.tex(base + p[0] + ".png")
	if art.has("land"): sheets["p_" + art.land] = Data.tex(base + art.land + ".png")
	for n in ["t_blue", "t_green", "t_red", "donut", "popcorn", "coin", "can_gold", "reel"]:
		sheets[n] = Data.tex("res://assets/sprites/pickups/%s.png" % n)
	sheets.smoke = Data.tex("res://assets/sprites/fx/fx_smoke.png")
	for n in ["i_mic", "i_clap", "i_reel"]: sheets[n] = Data.tex("res://assets/sprites/icons/%s.png" % n)

# ---------- stats ----------
func rebuild_stats() -> void:
	var old_max: float = stats.get("hp_max", 0.0)
	stats = Stats.build(character, passives, Save.clause_bonus(), level)
	if old_max > 0.0 and stats.hp_max > old_max: hp += stats.hp_max - old_max
	hp = min(hp, stats.hp_max)
	if weapons: weapons.recompute_all()

func rerolls_left() -> int: return int(stats.rerolls) - used_rerolls
func skips_left() -> int: return int(stats.skips) - used_skips
func banishes_left() -> int: return int(stats.banishes) - used_banishes

static func xp_for(l: int) -> float:
	if l < 20: return 5.0 + (l - 1) * 10.0
	if l < 40: return 195.0 + (l - 20) * 13.0
	return 455.0 + (l - 40) * 16.0

# ---------- API for weapons ----------
func view_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	return Rect2(player_pos - size / 2.0, size)

func random_visible_enemy() -> int:
	var vr := view_rect()
	for tries in 12:
		if enemies.n == 0: return -1
		var i := randi() % enemies.n
		if enemies.alive[i] == 1 and vr.has_point(Vector2(enemies.x[i], enemies.y[i])): return i
	return enemies.nearest(player_pos.x, player_pos.y, 600.0)

func heal(v: float) -> void:
	hp = min(stats.hp_max, hp + v)

func add_coins(v: float) -> void:
	coins += v * float(stats.greed)

func block_bullets(at: Vector2, r: float) -> void:
	for b in ebullets:
		if Vector2(b.x, b.y).distance_squared_to(at) < r * r: b.life = 0.0

func damage_enemy(i: int, amount: float, kb: Vector2, w) -> void:
	if enemies.alive[i] == 0: return
	var t := enemies.type[i]
	var crit := randf() < float(stats.crit)
	if crit: amount *= 2.0
	if t == T.BOSS or t == T.GUEST or t == T.STAR: amount *= float(stats.boss_damage)
	enemies.hp[i] -= amount
	enemies.flash[i] = 0.09
	var heavy := t >= T.STAR
	enemies.kx[i] += kb.x * (0.15 if heavy else 1.0)
	enemies.ky[i] += kb.y * (0.15 if heavy else 1.0)
	if w != null: dmg_by_weapon[w.id] = float(dmg_by_weapon.get(w.id, 0.0)) + amount
	if Save.data.options.damage_numbers and numbers.size() < 90:
		numbers.append({"x": enemies.x[i] + randf_range(-8, 8), "y": enemies.y[i] - enemies.r[i] * 2.2, "v": amount, "t": 0.0, "crit": crit})
	if _hit_sfx_t <= 0.0:
		Sfx.play("hit", randf_range(0.85, 1.2))
		_hit_sfx_t = 0.06
	if enemies.hp[i] <= 0.0: kill(i)

func kill(i: int, drops := true) -> void:
	var t := enemies.type[i]
	var d: Dictionary = EnemyPool.TYPES[t]
	var at := Vector2(enemies.x[i], enemies.y[i])
	if drops:
		kills += 1
		weapons.on_kill()
		if float(stats.lifesteal) > 0.0: heal(float(stats.lifesteal) * 2.0)
		if int(d.xp) > 0: drop_gem(at, float(d.xp))
		if d.has("chest"): pickups.append({"k": "chest", "x": at.x, "y": at.y, "boss": d.get("boss", false)})
		if t == T.BOSS: _boss_music_after(i)
		if d.get("boss", false) or t == T.GUEST:
			bosses_killed += 1
			shake = 0.5
			Sfx.play("explode", 0.7)
		if t == T.PRODUCTOR:
			productor_killed = true
			enemies.remove(i)
			finish(true)
			return
		var r := randf()
		if r < 0.006: pickups.append({"k": "food", "x": at.x, "y": at.y})
		elif r < 0.021: pickups.append({"k": "coin", "x": at.x, "y": at.y, "v": float(randi_range(1, 5))})
		elif r < 0.0218: pickups.append({"k": "magnet", "x": at.x, "y": at.y})
		elif r < 0.0223: pickups.append({"k": "cut", "x": at.x, "y": at.y})
		elif r < 0.0228: pickups.append({"k": "freeze", "x": at.x, "y": at.y})
	if corpses.size() < 70 and d.sprite == "enemy":
		corpses.append({"x": at.x, "y": at.y, "face": enemies.face[i], "t": 0.0, "sc": enemies.sc[i], "fi": int(enemies.anim[i])})
	elif d.sprite != "enemy":
		fx.append({"k": "smoke", "x": at.x, "y": at.y - 20.0, "t": 0.0, "life": 0.6, "s": enemies.sc[i] * 1.4})
	enemies.remove(i)

## Back to the stage theme once the last jefe on screen falls.
func _boss_music_after(dead: int) -> void:
	for j in enemies.n:
		if j != dead and enemies.alive[j] == 1 and enemies.type[j] == T.BOSS: return
	Music.play(Music.track_for(stage))

func drop_gem(at: Vector2, v: float) -> void:
	if gem_count >= MAX_GEMS:
		# too many tickets on the floor: merge into one VIP ticket
		if vip_gem == null or not pickups.has(vip_gem):
			vip_gem = {"k": "xp", "x": at.x, "y": at.y, "v": 0.0, "vip": true}
			pickups.append(vip_gem)
			gem_count += 1
		vip_gem.v += v
		return
	pickups.append({"k": "xp", "x": at.x, "y": at.y, "v": v})
	gem_count += 1

# ---------- fx API ----------
func fx_slash(pos: Vector2, ang: float, sc: float, gold: bool) -> void:
	if fx.size() < 160: fx.append({"k": "slash", "x": pos.x, "y": pos.y, "a": ang, "s": sc, "gold": gold, "t": 0.0, "life": 0.22})
	Sfx.play("shoot", randf_range(0.7, 0.9))

func fx_flash(v: float) -> void:
	if Save.data.options.flashes: flash = max(flash, v * 0.6)

func fx_cone(pos: Vector2, ang: float, r: float, half: float, color: Color) -> void:
	if fx.size() < 160: fx.append({"k": "cone", "x": pos.x, "y": pos.y, "a": ang, "r": r, "h": half, "c": color, "t": 0.0, "life": 0.2})

func fx_ring(pos: Vector2, r: float, color: Color) -> void:
	if fx.size() < 160: fx.append({"k": "ring", "x": pos.x, "y": pos.y, "r": r, "c": color, "t": 0.0, "life": 0.3})

func fx_line(a: Vector2, b: Vector2, w: float, color: Color) -> void:
	if fx.size() < 160: fx.append({"k": "line", "a": a, "b": b, "w": w, "c": color, "t": 0.0, "life": 0.15})

func announce(text: String) -> void:
	announce_text = text
	announce_t = 3.5

# ---------- flow ----------
func reach_end() -> void:
	completed = true

func open_levelup() -> void:
	state = "levelup"
	Sfx.play("levelup")
	var opts := Upgrades.roll(self, Upgrades.option_count(self))
	if bot:
		choose(opts[0])
		return
	hud.show_levelup(opts)

func choose(o: Dictionary) -> void:
	Upgrades.apply(self, o)
	Sfx.play("select")
	_after_choice()

func _after_choice() -> void:
	pending_levels -= 1
	if pending_levels > 0: open_levelup()
	else:
		state = "play"
		hud.hide_panels()

func do_reroll() -> void:
	if rerolls_left() <= 0: return
	used_rerolls += 1
	hud.show_levelup(Upgrades.roll(self, Upgrades.option_count(self)))

func do_skip() -> void:
	if skips_left() <= 0: return
	used_skips += 1
	xp += xp_for(level) * 0.1   # skipping gives a little back
	_after_choice()

func do_banish(o: Dictionary) -> void:
	if banishes_left() <= 0: return
	used_banishes += 1
	banished[o.id] = true
	hud.show_levelup(Upgrades.roll(self, Upgrades.option_count(self)))

func open_chest(is_boss: bool) -> void:
	chests += 1
	var n := Upgrades.chest_size(self)
	if is_boss: n = max(n, 3)
	var got := Upgrades.open_chest(self, n)
	var gold := 30.0 * n
	add_coins(gold)
	Sfx.play("chest")
	if bot: return
	state = "chest"
	hud.show_chest(got, int(gold * float(stats.greed)))

func close_chest() -> void:
	state = "play"
	hud.hide_panels()
	if pending_levels > 0: open_levelup()

func toggle_pause() -> void:
	if state == "play":
		state = "pause"
		hud.show_pause()
	elif state == "pause":
		state = "play"
		hud.hide_panels()

func quit_run() -> void:
	finish(completed)

func finish(won: bool) -> void:
	if state == "over": return
	state = "over"
	Sfx.play("death" if not won else "levelup", 1.0 if not won else 0.8)
	if bot: return   # demo and tests never touch the profile
	var summary := record()
	summary.won = won
	hud.show_results(summary)

## Write this run into the profile and check achievements. Returns the summary for the results screen.
func record() -> Dictionary:
	var s: Dictionary = Save.data.stats
	var earned := int(round(coins)) + (300 if completed else 0) + kills / 50
	s.kills += kills
	s.deaths += 0 if completed else 1
	s.runs += 1
	s.chests += chests
	s.coins += int(round(coins))
	s.food += food
	s.evolutions += evolutions
	for id in evolved_ids:
		if id not in s.evolved: s.evolved.append(id)
	s.bosses += bosses_killed
	s.max_level = max(int(s.max_level), level)
	s.time += time
	s.taquilla_total += earned
	s.survived[stage.id] = max(float(s.survived.get(stage.id, 0.0)), floor(time / 60.0))
	if completed and stage.id not in s.completed: s.completed.append(stage.id)
	if stage.id not in s.played: s.played.append(stage.id)
	if productor_killed: s.productor += 1
	Save.data.taquilla = int(Save.data.taquilla) + earned
	Save.data.last = {"character": character.id, "stage": stage.id}
	Save.save_game()
	var new_ach: Array = Achievements.check({})
	var dmg: Array = []
	for w in weapons.list: dmg.append([w.data.name if not w.evolved or w.data.source == "union" else w.data.evolution.name, w.level, int(dmg_by_weapon.get(w.id, 0.0))])
	return {"time": time, "kills": kills, "level": level, "coins": int(round(coins)), "earned": earned, "completed": completed,
		"achievements": new_ach, "weapons": dmg, "character": character.name, "stage": stage.name}

# ---------- update ----------
func _process(delta: float) -> void:
	if state == "pause" or state == "levelup" or state == "chest":
		queue_redraw()
		return
	if state == "over":
		queue_redraw()
		return
	step(min(delta, 1.0 / 20.0))
	queue_redraw()

func step(dt: float) -> void:
	time += dt
	_hit_sfx_t -= dt
	freeze_t = max(0.0, freeze_t - dt)
	flash = max(0.0, flash - dt * 2.0)
	shake = max(0.0, shake - dt)
	announce_t -= dt
	iframes -= dt
	hurt_flash = max(0.0, hurt_flash - dt * 3.0)
	_move_player(dt)
	if float(stats.regen) > 0.0: heal(float(stats.regen) * dt)
	director.update(dt)
	enemies.rebuild_grid()
	var hurt := enemies.update(dt, player_pos.x, player_pos.y, PLAYER_R, freeze_t > 0.0, _enemy_shoot, _enemy_explode)
	enemies.separate(dt)
	boss_ai.update(dt)
	weapons.orbiters.clear()
	weapons.update(dt)
	_update_bullets(dt)
	if hurt > 0.0: take_damage(hurt, false)
	_update_pickups(dt)
	_update_fx(dt)
	if time >= duration and not completed: reach_end()
	if hp <= 0.0: _on_death()

func _move_player(dt: float) -> void:
	var v := Controls.move_vector()
	if touch_vec.length() > 0.1: v = touch_vec
	if bot: v = _bot_dir()
	if v.length() > 1.0: v = v.normalized()
	move_dir = v
	if v.length() > 0.1: facing = v.normalized()
	if bot:
		var e := enemies.nearest(player_pos.x, player_pos.y, 400.0)
		if e >= 0: facing = (Vector2(enemies.x[e], enemies.y[e]) - player_pos).normalized()
	player_pos += v * float(stats.move_speed) * dt
	cam.position = player_pos
	if Save.data.options.shake and shake > 0.0:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0 * shake
	else: cam.offset = Vector2.ZERO

## Simple autopilot for tests and the demo: dodge what is close, collect tickets, stay near the horde.
func _bot_dir() -> Vector2:
	var push := Vector2.ZERO
	for i in enemies.query_circle(player_pos.x, player_pos.y, 110.0, _q):
		var d := player_pos - Vector2(enemies.x[i], enemies.y[i])
		push += d.normalized() / max(16.0, d.length())
	if push.length() > 0.004: return push.normalized()
	var best = null
	var bd := 380.0 * 380.0
	for p in pickups:
		if p.k == "food" and hp > stats.hp_max * 0.7: continue
		var dd := Vector2(p.x, p.y).distance_squared_to(player_pos)
		if dd < bd:
			bd = dd
			best = p
	if best != null: return (Vector2(best.x, best.y) - player_pos).normalized()
	var e := enemies.nearest(player_pos.x, player_pos.y, 900.0)
	if e >= 0:
		var to := Vector2(enemies.x[e], enemies.y[e]) - player_pos
		if to.length() > 150.0: return to.normalized() * 0.8
		return to.normalized().orthogonal() * 0.6 + to.normalized() * 0.3
	return Vector2(cos(time * 0.3), sin(time * 0.21))

func take_damage(amount: float, burst: bool) -> void:
	if iframes > 0.0 and burst: return
	var armor := float(stats.armor)
	var dmg = amount * max(0.25, 1.0 - armor * 0.06)
	if burst: dmg = max(1.0, amount - armor)
	hp -= dmg
	hurt_flash = 1.0
	if burst:
		iframes = 0.4
		shake = 0.25
		Sfx.play("hurt")

func _on_death() -> void:
	if revivals_used < int(stats.revival):
		revivals_used += 1
		hp = stats.hp_max * 0.5
		iframes = 2.0
		for i in enemies.query_circle(player_pos.x, player_pos.y, 380.0, _q):
			if enemies.type[i] < T.STAR: kill(i, false)
		fx_ring(player_pos, 380.0, Color.WHITE)
		fx_flash(1.0)
		announce(Loc.t("revive"))
		return
	finish(completed)

func _enemy_shoot(x: float, y: float, dx: float, dy: float) -> void:
	if ebullets.size() < 90:
		ebullets.append({"x": x, "y": y, "vx": dx * 190.0, "vy": dy * 190.0, "life": 4.0})

func _enemy_explode(x: float, y: float) -> void:
	fx_ring(Vector2(x, y), 60.0, Color("ff8a3a"))
	Sfx.play("explode")
	iframes = 0.0
	take_damage(0.0, true)

func _update_bullets(dt: float) -> void:
	var keep: Array = []
	var dmg := 8.0 + time / 60.0 * 0.5
	for b in ebullets:
		if freeze_t <= 0.0:
			b.x += b.vx * dt; b.y += b.vy * dt
		b.life -= dt
		if b.life <= 0.0: continue
		if Vector2(b.x, b.y).distance_squared_to(player_pos) < 18.0 * 18.0:
			take_damage(dmg, true)
			continue
		keep.append(b)
	ebullets = keep

func _update_pickups(dt: float) -> void:
	var mr := float(stats.magnet_radius)
	var keep: Array = []
	for p in pickups:
		var d := Vector2(p.x, p.y) - player_pos
		var dist := d.length()
		if p.get("pull", false) or (dist < mr and p.k in ["xp", "coin", "food"]):
			p.pull = true
			p.sp = float(p.get("sp", -120.0)) + dt * 1400.0
			var mv: float = min(dist, max(0.0, p.sp) * dt)
			p.x -= d.x / max(dist, 0.01) * mv
			p.y -= d.y / max(dist, 0.01) * mv
			if p.sp < 0.0:   # small hop away first, as in the genre
				p.x += d.x / max(dist, 0.01) * 60.0 * dt
				p.y += d.y / max(dist, 0.01) * 60.0 * dt
		if dist < PLAYER_R + 12.0:
			_collect(p)
			continue
		keep.append(p)
	pickups = keep
	while xp >= xp_for(level):
		xp -= xp_for(level)
		level += 1
		pending_levels += 1
		rebuild_stats()
		fx_ring(player_pos, 120.0, Color("f2b83b"))
	if pending_levels > 0 and state == "play": open_levelup()

func _collect(p: Dictionary) -> void:
	match p.k:
		"xp":
			gem_count -= 1
			if p == vip_gem: vip_gem = null
			xp += float(p.v) * float(stats.growth)
			Sfx.play("pickup", randf_range(1.0, 1.3))
		"coin":
			add_coins(float(p.v))
			Sfx.play("pickup", 0.8)
		"food":
			food += 1
			heal(30.0)
			Sfx.play("pickup", 0.6)
		"chest": open_chest(p.get("boss", false))
		"magnet":
			for q in pickups:
				if q.k == "xp": q.pull = true
			Sfx.play("levelup", 1.4)
		"cut":
			var vr := view_rect().grow(60.0)
			for i in enemies.n:
				if enemies.alive[i] == 1 and enemies.type[i] < T.STAR and vr.has_point(Vector2(enemies.x[i], enemies.y[i])): kill(i)
			fx_flash(1.5)
			announce(Loc.t("cut"))
		"freeze":
			freeze_t = 10.0 * float(stats.freeze_time)
			announce(Loc.t("freeze"))

func _update_fx(dt: float) -> void:
	var keep: Array = []
	for f in fx:
		f.t += dt
		if f.t < f.life: keep.append(f)
	fx = keep
	var nk: Array = []
	for n in numbers:
		n.t += dt
		n.y -= dt * 40.0
		if n.t < 0.7: nk.append(n)
	numbers = nk
	var ck: Array = []
	for c in corpses:
		c.t += dt
		if c.t < 0.75: ck.append(c)
	corpses = ck

# ---------- input (touch stick, pause, level-up keys) ----------
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if state == "levelup": hud.levelup_key(e)
	if e is InputEventScreenTouch:
		if e.pressed and touch_id < 0 and state == "play":
			touch_id = e.index
			touch_origin = e.position
			touch_vec = Vector2.ZERO
		elif not e.pressed and e.index == touch_id:
			touch_id = -1
			touch_vec = Vector2.ZERO
	elif e is InputEventScreenDrag and e.index == touch_id:
		touch_vec = ((e.position - touch_origin) / 60.0).limit_length(1.0)

# ---------- props ----------
func _chunk_props(c: Vector2i) -> Array:
	if props.has(c): return props[c]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.x, c.y, stage.get("id", "")])
	var out: Array = []
	if abs(c.x) + abs(c.y) > 0 or true:
		var n := rng.randi_range(2, 5)
		var tot := 0.0
		for p in art.props: tot += float(p[1])
		for k in n:
			var r := rng.randf() * tot
			var name: String = art.props[0][0]
			for p in art.props:
				r -= float(p[1])
				if r <= 0.0:
					name = p[0]
					break
			var px := (c.x + rng.randf()) * CHUNK
			var py := (c.y + rng.randf()) * CHUNK
			if Vector2(px, py).length() < 260.0: continue
			out.append([name, px, py, rng.randf_range(0.7, 0.9)])
		if art.has("land") and rng.randf() < 0.12 and Vector2(c).length() > 1.0:
			out.append([art.land, (c.x + 0.5) * CHUNK, (c.y + 0.5) * CHUNK, float(art.get("land_scale", 1.0))])
	props[c] = out
	return out

# ---------- drawing ----------
func _draw() -> void:
	var vr := view_rect().grow(160.0)
	# ground
	var g: Texture2D = sheets.ground
	if g:
		var ts := g.get_size()
		var o := (vr.position / ts).floor() * ts
		draw_texture_rect(g, Rect2(o, vr.size + ts * 2.0), true)
	# zones on the floor
	for z in weapons.zones:
		if z.kind == "zone" or z.kind == "strike":
			var col: Color = WeaponSystem.COLORS.zone
			if z.delay > 0.0:
				draw_arc(Vector2(z.x, z.y), z.r, 0, TAU, 32, Color(col, 0.7), 2.0)
			else:
				draw_circle(Vector2(z.x, z.y), z.r, Color(col, 0.22))
				draw_arc(Vector2(z.x, z.y), z.r, 0, TAU, 32, Color(col, 0.6), 2.0)
	boss_ai.draw(self)
	# pickups
	for p in pickups:
		if not vr.has_point(Vector2(p.x, p.y)): continue
		var tx: Texture2D
		match p.k:
			"xp": tx = sheets.t_red if p.get("vip", false) or p.v >= 25.0 else (sheets.t_green if p.v >= 5.0 else sheets.t_blue)
			"coin": tx = sheets.coin
			"food": tx = sheets.donut
			"chest": tx = sheets.can_gold
			"magnet": tx = sheets.i_mic
			"cut": tx = sheets.i_clap
			"freeze": tx = sheets.i_reel
		if tx:
			var s := tx.get_size() * (0.6 if p.k in ["magnet", "cut", "freeze"] else 1.0)
			var bob := sin(time * 4.0 + p.x) * 2.0 if p.k != "xp" else 0.0
			draw_texture_rect(tx, Rect2(Vector2(p.x, p.y + bob) - s / 2.0, s), false)
	# corpses
	for c in corpses: _draw_corpse(c)
	# y-sorted: props, enemies, player
	_keys.clear()
	_vis_props.clear()
	for i in enemies.n:
		if enemies.alive[i] == 1 and vr.has_point(Vector2(enemies.x[i], enemies.y[i])):
			_keys.append((int(enemies.y[i]) + 1000000) * 1048576 + i)
	var c0 := Vector2i(floori(vr.position.x / CHUNK), floori(vr.position.y / CHUNK))
	var c1 := Vector2i(floori(vr.end.x / CHUNK), floori(vr.end.y / CHUNK))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for p in _chunk_props(Vector2i(cx, cy)):
				_vis_props.append(p)
	for p in props.get(Vector2i(99999, 0), []): _vis_props.append(p)
	for k in _vis_props.size():
		_keys.append((int(_vis_props[k][2]) + 1000000) * 1048576 + 600000 + k)
	_keys.append((int(player_pos.y) + 1000000) * 1048576 + 1000000)
	_keys.sort()
	for key in _keys:
		var id := key % 1048576
		if id == 1000000: _draw_player()
		elif id >= 600000: _draw_prop(_vis_props[id - 600000])
		else: _draw_enemy(id)
	# weapons in the air
	for o in weapons.orbiters:
		draw_circle(Vector2(o.x, o.y), float(o.w.p.size), Color(WeaponSystem.COLORS.orbit, 0.9))
		draw_arc(Vector2(o.x, o.y), float(o.w.p.size), 0, TAU, 16, Color(0.2, 0.2, 0.25), 2.0)
	for s in weapons.shots:
		if s.delay > 0.0: continue
		var col: Color = WeaponSystem.COLORS.get(s.w.data.archetype, Color.WHITE)
		if s.w.evolved: col = Color("f2b83b")
		draw_circle(Vector2(s.x, s.y), s.size * 0.6, col)
		draw_line(Vector2(s.x, s.y), Vector2(s.x - s.vx * 0.03, s.y - s.vy * 0.03), Color(col, 0.5), s.size * 0.6)
	for z in weapons.zones:
		if z.kind == "car":
			draw_rect(Rect2(z.x - 34.0, z.y - 16.0, 68.0, 30.0), WeaponSystem.COLORS.car)
			draw_rect(Rect2(z.x - 20.0, z.y - 26.0, 40.0, 12.0), Color("ffd0d0"))
		elif z.kind == "mark" and enemies.alive[z.target] == 1:
			draw_arc(Vector2(enemies.x[z.target], enemies.y[z.target]), 14.0, -PI / 2, -PI / 2 + TAU * (z.life / z.delay), 16, WeaponSystem.COLORS.mark, 3.0)
	for b in ebullets:
		draw_circle(Vector2(b.x, b.y), 6.0, Color("ff4a5a"))
		draw_circle(Vector2(b.x, b.y), 3.0, Color.WHITE)
	_draw_fx()
	if Save.data.options.damage_numbers:
		for n in numbers:
			var a: float = 1.0 - n.t / 0.7
			draw_string(font, Vector2(n.x, n.y), str(int(n.v)), HORIZONTAL_ALIGNMENT_CENTER, -1, 10 if not n.crit else 14, Color(1, 0.85 if n.crit else 1, 0.3 if n.crit else 1, a))
	# player hp bar
	var bw := 46.0
	draw_rect(Rect2(player_pos + Vector2(-bw / 2, 10), Vector2(bw, 5)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(player_pos + Vector2(-bw / 2, 10), Vector2(bw * max(0.0, hp / stats.hp_max), 5)), Color("e83a3a"))
	if touch_id >= 0:
		var org := get_canvas_transform().affine_inverse() * touch_origin
		draw_arc(org, 60.0, 0, TAU, 32, Color(1, 1, 1, 0.4), 3.0)
		draw_circle(org + touch_vec * 60.0, 22.0, Color(1, 1, 1, 0.35))

func _draw_sheet(sh: Dictionary, fi: int, pos: Vector2, sc: float, face: float, mod := Color.WHITE, white := false, dy := 0.0) -> void:
	if sh.is_empty(): return
	var fw: float = sh.fw
	var fh: float = sh.fh
	var src := Rect2((fi % int(sh.n)) * fw, 0, fw, fh)
	var w := fw * sc
	var h := fh * sc
	var dst := Rect2(pos.x - w / 2.0, pos.y - h + 4.0 + dy, w, h)
	if face < 0.0: dst = Rect2(pos.x + w / 2.0, pos.y - h + 4.0 + dy, -w, h)
	draw_texture_rect_region(sh.white if white else sh.tex, dst, src, mod)

func _draw_enemy(i: int) -> void:
	var t := enemies.type[i]
	var d: Dictionary = EnemyPool.TYPES[t]
	var sh: Dictionary = sheets[d.sprite]
	var pos := Vector2(enemies.x[i], enemies.y[i])
	var fi := int(enemies.anim[i])
	var sc := enemies.sc[i]
	var face := enemies.face[i]
	if d.get("spot", false) or d.get("boss", false):
		draw_set_transform(pos, 0, Vector2(1, 0.35))
		draw_circle(Vector2.ZERO, enemies.r[i] * 2.4, Color(1, 0.95, 0.7, 0.18))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_set_transform(pos + Vector2(0, 2), 0, Vector2(1, 0.35))
		draw_circle(Vector2.ZERO, enemies.r[i] * 0.9, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
	if d.get("outline", false):
		for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
			_draw_sheet(sh, fi, pos + o, sc, face, Color("f2b83b"), true)
	var mod: Color = d.tint
	if enemies.mark[i] > 0.0: mod = mod * Color(0.85, 0.7, 1.0)
	if freeze_t > 0.0: mod = mod * Color(0.6, 0.8, 1.2)
	_draw_sheet(sh, fi, pos, sc, face, mod)
	if enemies.flash[i] > 0.0: _draw_sheet(sh, fi, pos, sc, face, Color(1, 1, 1, 0.85), true)
	elif enemies.stun[i] > 0.0: _draw_sheet(sh, fi, pos, sc, face, Color(0.7, 0.85, 1, 0.4), true)

func _draw_player() -> void:
	draw_set_transform(player_pos + Vector2(0, 2), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 16.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	var moving := move_dir.length() > 0.1
	var sh: Dictionary = sheets.run if moving else sheets.idle
	var fi := int(time * (12.0 if moving else 6.0))
	var face := -1.0 if facing.x < -0.1 else 1.0
	var mod := Color.WHITE
	if iframes > 0.0 and int(time * 20.0) % 2 == 0: mod.a = 0.5
	_draw_sheet(sh, fi, player_pos, PLAYER_SCALE, face, mod)
	if hurt_flash > 0.0: _draw_sheet(sh, fi, player_pos, PLAYER_SCALE, face, Color(1, 0.2, 0.25, hurt_flash * 0.55), true)

func _draw_prop(p: Array) -> void:
	var tx: Texture2D = sheets.get("p_" + p[0])
	if tx == null: return
	var s: Vector2 = tx.get_size() * float(p[3])
	draw_set_transform(Vector2(p[1], p[2] + 2), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, s.x * 0.4, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(tx, Rect2(p[1] - s.x / 2.0, p[2] - s.y + 6.0, s.x, s.y), false)

func _draw_corpse(c: Dictionary) -> void:
	var sh: Dictionary = sheets.get("die", {})
	var a = 1.0 if c.t < 0.5 else max(0.0, (0.75 - c.t) / 0.25)
	if not sh.is_empty():
		var fi := mini(int(sh.n) - 1, int(c.t / 0.75 * sh.n))
		_draw_sheet(sh, fi, Vector2(c.x, c.y), c.sc, c.face, Color(1, 1, 1, a))
		return
	var e: Dictionary = sheets.enemy
	var k: float = min(1.0, c.t / 0.32)
	var fall := k * k * (PI / 2.0) * 0.95
	draw_set_transform(Vector2(c.x - c.face * e.fw * c.sc * 0.15, c.y + 4.0), -c.face * fall)
	_draw_sheet(e, c.fi, Vector2.ZERO, c.sc, c.face, Color(1, 1, 1, a), c.t < 0.12, -4.0)
	draw_set_transform(Vector2.ZERO)

func _draw_fx() -> void:
	for f in fx:
		var k: float = f.t / f.life
		match f.k:
			"slash":
				var sh: Dictionary = sheets.slash
				draw_set_transform(Vector2(f.x, f.y), f.a, Vector2.ONE * f.s)
				var fi := mini(5, int(k * 6.0))
				var src := Rect2(fi * sh.fw, 0, sh.fw, sh.fh)
				draw_texture_rect_region(sh.tex, Rect2(-sh.fw / 2.0, -sh.fh / 2.0, sh.fw, sh.fh), src, Color("f2b83b") if f.gold else Color.WHITE)
				draw_set_transform(Vector2.ZERO)
			"ring":
				draw_arc(Vector2(f.x, f.y), f.r * (0.6 + 0.4 * k), 0, TAU, 48, Color(f.c, 1.0 - k), 4.0 * (1.0 - k) + 1.0)
			"cone":
				var pts := PackedVector2Array([Vector2(f.x, f.y)])
				for s in 9:
					var a: float = f.a - f.h + 2.0 * f.h * s / 8.0
					pts.append(Vector2(f.x, f.y) + Vector2(cos(a), sin(a)) * f.r)
				draw_colored_polygon(pts, Color(f.c, 0.35 * (1.0 - k)))
			"line":
				draw_line(f.a, f.b, Color(f.c, 0.9 * (1.0 - k)), f.w * (1.0 - k * 0.5))
				draw_line(f.a, f.b, Color(1, 1, 1, 1.0 - k), f.w * 0.35)
			"smoke":
				var tx: Texture2D = sheets.smoke
				var s: Vector2 = tx.get_size() * f.s * (0.6 + k * 0.6)
				draw_texture_rect(tx, Rect2(Vector2(f.x, f.y) - s / 2.0, s), false, Color(1, 1, 1, 1.0 - k))
