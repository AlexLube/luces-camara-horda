extends CanvasLayer
## In-run interface: XP bar, timer, kills, coins, weapon and item slots, boss bar, announcements,
## screen effects (flash, fog, rain, hurt), and the level-up, lata, pause and results panels.

var run
var overlay: Control
var panel_root: Control
var opts: Array = []
var banish_mode := false
var rain: Array = []
var vignette: Texture2D

func _ready() -> void:
	layer = 5
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_root.theme = UIKit.theme()
	add_child(panel_root)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 1))
	g.add_point(0.45, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	vignette = gt
	for k in 140: rain.append(Vector2(randf() * 1400.0, randf() * 800.0))

func _process(_dt: float) -> void:
	overlay.queue_redraw()

# ---------- overlay drawing ----------
func _draw_overlay() -> void:
	var size := overlay.size
	var font: Font = UIKit.pixel_font if UIKit.pixel_font else ThemeDB.fallback_font
	var tfont: Font = UIKit.title_font if UIKit.title_font else ThemeDB.fallback_font
	# weather and stage moods
	if run.art.get("rain", false):
		for k in rain.size():
			var p: Vector2 = rain[k]
			p.y = fmod(p.y + run.time * 900.0, size.y + 40.0) - 20.0
			p.x = fmod(p.x - run.time * 200.0 + 4000.0, size.x + 40.0)
			overlay.draw_line(p, p + Vector2(-5, 18), Color(0.8, 0.85, 1.0, 0.35), 1.0)
	if run.art_key == "forest":
		var night := _night_amount()
		if night > 0.0: overlay.draw_texture_rect(vignette, Rect2(Vector2(-size.x * 0.25, -size.y * 0.6), Vector2(size.x * 1.5, size.y * 2.2)), false, Color(1, 1, 1, night * 0.92))
	# Imprevistos de Rodaje: blackout (only light around the player) and artificial rain
	if run.event_active("blackout"):
		var lit := Rect2(size / 2.0 - Vector2(340, 340), Vector2(680, 680))
		overlay.draw_texture_rect(vignette, lit, false, Color.WHITE)
		for r in [Rect2(0, 0, size.x, lit.position.y), Rect2(0, lit.end.y, size.x, size.y), Rect2(0, 0, lit.position.x, size.y), Rect2(lit.end.x, 0, size.x, size.y)]:
			overlay.draw_rect(r, Color.BLACK)
	if run.curse and run.has_guion("gm_vi"):   # El Metraje Encontrado: only a small circle is seen
		var r2 := CursedGuiones.SIGHT
		var lit2 := Rect2(size / 2.0 - Vector2(r2, r2) * 1.15, Vector2(r2, r2) * 2.3)
		overlay.draw_texture_rect(vignette, lit2, false, Color(1, 1, 1, 0.97))
		for r in [Rect2(0, 0, size.x, lit2.position.y), Rect2(0, lit2.end.y, size.x, size.y), Rect2(0, 0, lit2.position.x, size.y), Rect2(lit2.end.x, 0, size.x, size.y)]:
			overlay.draw_rect(r, Color(0, 0, 0, 0.97))
	if run.event_active("rain"):
		var t: float = run.time
		for k in 140:
			var x := fmod(k * 97.31 + t * 260.0, size.x + 80.0) - 40.0
			var y := fmod(k * 53.7 + t * 900.0 + k * 13.0, size.y + 60.0) - 30.0
			overlay.draw_line(Vector2(x, y), Vector2(x - 6, y + 18), Color(0.7, 0.8, 1.0, 0.45), 1.5)
		overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.3, 0.5, 0.12))
	if run.hurt_flash > 0.0:
		overlay.draw_texture_rect(vignette, Rect2(Vector2.ZERO, size), false, Color(1, 0.1, 0.1, run.hurt_flash * 0.5))
	if run.flash > 0.0: overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 0.95, min(0.8, run.flash)))
	if run.freeze_t > 0.0: overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.6, 1.0, 0.12))
	# XP bar
	var need: float = Run.xp_for(run.level)
	overlay.draw_rect(Rect2(0, 0, size.x, 18), Color(0, 0, 0, 0.75))
	overlay.draw_rect(Rect2(2, 2, (size.x - 4) * clamp(run.xp / need, 0.0, 1.0), 14), Color("3fa0ff"))
	overlay.draw_string(font, Vector2(size.x - 120, 14), "LV %d" % run.level, HORIZONTAL_ALIGNMENT_RIGHT, 110, 12, Color.WHITE)
	# timer, kills, coins
	var left: float = max(0.0, run.duration - run.time)
	overlay.draw_string(font, Vector2(0, 52), UIKit.fmt_time(run.time), HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE if left > 60.0 else Color("ff6060"))
	if run.saga_rules:
		var st: String = run.saga_rules.hud_text()
		overlay.draw_string(font, Vector2(1, 81), st, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0, 0, 0, 0.8))
		overlay.draw_string(font, Vector2(0, 80), st, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color("ffe08a"))
	overlay.draw_string(font, Vector2(size.x - 230, 46), "☠ %d" % run.kills, HORIZONTAL_ALIGNMENT_RIGHT, 210, 14, UIKit.CREAM)
	overlay.draw_string(font, Vector2(size.x - 230, 70), "$ %d" % int(round(run.coins)), HORIZONTAL_ALIGNMENT_RIGHT, 210, 14, UIKit.GOLD)
	# slots: weapons on top row, items below
	var x0 := 10.0
	for k in 6:
		var r := Rect2(x0 + k * 40.0, 26, 36, 36)
		overlay.draw_rect(r, Color(0, 0, 0, 0.55))
		overlay.draw_rect(r, UIKit.GOLD.darkened(0.4), false, 1.0)
		if k < run.weapons.list.size():
			var w: Dictionary = run.weapons.list[k]
			_slot(r, w.data.evolution.id if w.evolved else w.id, w.data.name, w.level, w.evolved, font)
	var pk: Array = run.passives.keys()
	for k in 6:
		var r := Rect2(x0 + k * 40.0, 66, 36, 36)
		overlay.draw_rect(r, Color(0, 0, 0, 0.45))
		if k < pk.size(): _slot(r, pk[k], Data.passives[pk[k]].name, int(run.passives[pk[k]]), false, font)
	# Mapa de Localizaciones: arrows to the relics still hidden in this stage
	if Save.is_unlocked("relics", "mapa_de_localizaciones"):
		var c := size / 2.0
		for p in run.relic_pickups():
			var d: Vector2 = Vector2(p.x, p.y) - run.player_pos
			if d.length() < 420.0: continue
			var dir := d.normalized()
			var at: Vector2 = c + dir * (minf(size.x, size.y) / 2.0 - 46.0)
			overlay.draw_colored_polygon(PackedVector2Array([at + dir * 14.0, at + dir.orthogonal() * 9.0 - dir * 6.0, at - dir.orthogonal() * 9.0 - dir * 6.0]), UIKit.GOLD)
	# boss bar
	var boss := -1
	var best := 0.0
	for i in run.enemies.names:
		if run.enemies.alive[i] == 1 and run.enemies.hp_max[i] > best:
			best = run.enemies.hp_max[i]
			boss = i
	if boss >= 0:
		var bw := size.x * 0.5
		var bx := (size.x - bw) / 2.0
		overlay.draw_rect(Rect2(bx, size.y - 46, bw, 16), Color(0, 0, 0, 0.75))
		overlay.draw_rect(Rect2(bx + 2, size.y - 44, (bw - 4) * clamp(run.enemies.hp[boss] / run.enemies.hp_max[boss], 0.0, 1.0), 12), UIKit.RED.lightened(0.2))
		overlay.draw_string(tfont, Vector2(bx, size.y - 52), run.enemies.names[boss], HORIZONTAL_ALIGNMENT_CENTER, bw, 22, UIKit.GOLD)
	# announcement
	if run.announce_t > 0.0:
		var a: float = clamp(run.announce_t, 0.0, 1.0)
		overlay.draw_string(tfont, Vector2(0, size.y * 0.3) + Vector2(3, 3), run.announce_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, Color(0, 0, 0, a * 0.8))
		overlay.draw_string(tfont, Vector2(0, size.y * 0.3), run.announce_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, Color(UIKit.GOLD, a))

func _slot(r: Rect2, id: String, name: String, lvl: int, evolved: bool, font: Font) -> void:
	var ic: Texture2D = Data.icon_for(id)
	if ic: overlay.draw_texture_rect(ic, r.grow(-3), false)
	else: overlay.draw_string(font, r.position + Vector2(4, 22), name.substr(0, 2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.CREAM)
	overlay.draw_string(font, r.position + Vector2(r.size.x - 14, r.size.y - 2), str(lvl) if not evolved else "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIKit.GOLD if evolved else Color.WHITE)
	if evolved: overlay.draw_rect(r, UIKit.GOLD, false, 2.0)

## Forest fog: one minute of night every five minutes.
func _night_amount() -> float:
	var m: float = fmod(run.time, 300.0)
	if run.time < 240.0: return 0.0
	if m > 240.0: return clamp((m - 240.0) / 8.0, 0.0, 1.0)
	if m < 10.0: return clamp(1.0 - m / 10.0, 0.0, 1.0)
	return 0.0

# ---------- panels ----------
func hide_panels() -> void:
	for c in panel_root.get_children(): c.queue_free()

func show_levelup(options: Array) -> void:
	hide_panels()
	opts = options
	banish_mode = false
	var v := UIKit.centered_panel(panel_root, Vector2(600, 0))
	v.add_child(UIKit.title(Loc.t("level_up"), 46))
	for k in options.size():
		var o: Dictionary = options[k]
		v.add_child(UIKit.card(Data.icon_for(o.id), "%d. %s" % [k + 1, o.name], o.level_text, o.desc, _pick.bind(k)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var rb := UIKit.button(Loc.t("reroll", [run.rerolls_left()]), run.do_reroll, 170)
	rb.disabled = run.rerolls_left() <= 0
	row.add_child(rb)
	var sb := UIKit.button(Loc.t("skip", [run.skips_left()]), run.do_skip, 170)
	sb.disabled = run.skips_left() <= 0
	row.add_child(sb)
	var bb := UIKit.button(Loc.t("banish", [run.banishes_left()]), func(): banish_mode = not banish_mode; bb_text(), 170)
	bb.name = "Banish"
	bb.disabled = run.banishes_left() <= 0
	row.add_child(bb)
	UIKit.focus_first(v)

func bb_text() -> void:
	var b := panel_root.find_child("Banish", true, false)
	if b: b.text = Loc.t("banish_pick") if banish_mode else Loc.t("banish", [run.banishes_left()])

func _pick(k: int) -> void:
	if k >= opts.size(): return
	if banish_mode:
		run.do_banish(opts[k])
		return
	run.choose(opts[k])

func levelup_key(e: InputEvent) -> void:
	for k in 4:
		if e.is_action_pressed("pick_%d" % (k + 1)): _pick(k)
	if e.is_action_pressed("reroll"): run.do_reroll()
	elif e.is_action_pressed("skip"): run.do_skip()
	elif e.is_action_pressed("banish") and run.banishes_left() > 0:
		banish_mode = not banish_mode
		bb_text()

func show_chest(got: Array, gold: int) -> void:
	hide_panels()
	var v := UIKit.centered_panel(panel_root, Vector2(600, 0))
	v.add_child(UIKit.title(Loc.t("chest_title", [got.size()]), 42))
	var ic := TextureRect.new()
	ic.texture = Data.tex("res://assets/sprites/pickups/can_gold.png")
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(0, 70)
	v.add_child(ic)
	for o in got:
		var tag := Loc.t("evolved") if o.kind == "evolve" else (Loc.t("union") if o.kind == "union" else "")
		var c := UIKit.card(Data.icon_for(o.get("icon", o.id)), o.name, tag, o.desc, func(): pass)
		c.focus_mode = Control.FOCUS_NONE
		v.add_child(c)
	v.add_child(UIKit.label("+ %d $" % gold, 22, UIKit.GOLD))
	v.add_child(UIKit.button(Loc.t("continue"), run.close_chest))
	UIKit.focus_first(v)

## Choose one Guion card (modifier «Guiones»): at the start and after each boss.
func show_guion(opts: Array) -> void:
	hide_panels()
	var v := UIKit.centered_panel(panel_root, Vector2(640, 0))
	v.add_child(UIKit.title(Loc.t("guion_pick"), 42))
	for g in opts:
		var c := UIKit.card(Data.guion_icon(g.id), g.name, ("☠ " + Loc.t("gm_curse_tag") + " " if g.cursed else "") + g.num, g.desc, run.pick_guion.bind(g.id), 600)
		c.custom_minimum_size.y = 100
		if g.cursed: c.modulate = Color(1.0, 0.82, 0.85)
		v.add_child(c)
	UIKit.focus_first(v)

func show_pause() -> void:
	hide_panels()
	var v := UIKit.centered_panel(panel_root, Vector2(560, 0))
	v.add_child(UIKit.title(Loc.t("paused"), 50))
	v.add_child(UIKit.label("%s · %s" % [run.character.name, run.stage.name], 20))
	var s: Dictionary = run.stats
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	v.add_child(grid)
	for k in ["power", "armor", "max_hp", "regen", "cooldown", "area", "speed", "duration", "amount", "magnet", "luck", "growth", "greed", "curse", "revival", "crit"]:
		grid.add_child(UIKit.label(Loc.t("st_" + k), 17, UIKit.CREAM.darkened(0.15)))
		var val: float = s[k]
		var txt := ("%+d %%" % roundi((val - 1.0) * 100.0)) if k not in Stats.FLAT else ("%d %%" % roundi(val * 100.0) if k == "crit" else str(snappedf(val, 0.1)))
		if k == "max_hp": txt = str(int(s.hp_max))
		grid.add_child(UIKit.label(txt, 17, UIKit.GOLD))
	v.add_child(UIKit.button(Loc.t("resume"), run.toggle_pause))
	v.add_child(UIKit.button(Loc.t("give_up"), run.quit_run))
	UIKit.focus_first(v)

func show_results(r: Dictionary) -> void:
	hide_panels()
	if r.completed: Music.play("creditos")
	var v := UIKit.centered_panel(panel_root, Vector2(640, 0))
	v.add_child(UIKit.title(Loc.t("wrap") if r.completed else Loc.t("cut_fail"), 50))
	v.add_child(UIKit.label("%s · %s" % [r.character, r.stage], 20))
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 28)
	v.add_child(top)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(150, 150)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = Data.portrait(r.get("character_id", ""))
	if not r.completed: pic.modulate = Color(0.75, 0.72, 0.78)   # a bad take looks a bit washed out
	top.add_child(pic)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	top.add_child(grid)
	for row in [[Loc.t("r_time"), UIKit.fmt_time(r.time)], [Loc.t("r_kills"), str(r.kills)], [Loc.t("r_level"), str(r.level)], [Loc.t("r_coins"), str(r.coins)], [Loc.t("r_taquilla"), "+%d" % r.earned]]:
		grid.add_child(UIKit.label(row[0], 20))
		grid.add_child(UIKit.label(row[1], 20, UIKit.GOLD))
	v.add_child(UIKit.label(Loc.t("r_damage"), 20, UIKit.GOLD))
	for w in r.weapons:
		v.add_child(UIKit.label("%s  (%s)  —  %d" % [w[0], Loc.t("lvl_n", [w[1]]), w[2]], 17))
	for a in r.achievements:
		v.add_child(UIKit.label("» " + a.name, 18, UIKit.GOLD.lightened(0.2)))
	if r.get("saga", "") != "":
		v.add_child(UIKit.label(Loc.t("saga_done", [r.saga_reward]) if r.saga_done else (Loc.t("saga_phase_done", [r.saga]) if r.completed else r.saga), 18, UIKit.GOLD.lightened(0.2)))
	for n in r.get("relics", []):
		v.add_child(UIKit.label(Loc.t("relic_found", [n]), 18, UIKit.GOLD.lightened(0.2)))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	v.add_child(row2)
	row2.add_child(UIKit.button(Loc.t("retry"), func(): run.retry.emit(), 220))
	row2.add_child(UIKit.button(Loc.t("to_menu"), func(): run.exit_to_menu.emit(), 220))
	UIKit.focus_first(v)
