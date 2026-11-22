extends Node
## Game flow: title → casting (character) → stage → run → results, plus Cláusulas del Contrato (shop),
## Premios (achievements), options and credits. Menus are built in code with UIKit.

var ui: CanvasLayer
var root: Control
var run: Run
var sel_char := ""
var sel_stage := ""
var waiting_bind := ""

func _ready() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	Loc.changed.connect(func(): if run == null: show_title())
	Achievements.check({})
	sel_char = Save.data.last.character
	sel_stage = Save.data.last.stage
	var args := OS.get_cmdline_user_args()
	var opt := {}
	for a in args:
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		opt[kv[0]] = kv[1] if kv.size() > 1 else ""
	if opt.has("char"): sel_char = opt.char
	if opt.has("stage"): sel_stage = opt.stage
	if opt.has("demo"):
		start_run(true)
		# fast-forward the simulation (for screenshots and soak tests)
		var skip := float(opt.get("skip", "0"))
		run.set_process(false)
		await get_tree().process_frame
		while run.time < skip: run.step(1.0 / 20.0); run.hp = max(run.hp, 50.0)
		run.set_process(true)
	else:
		match opt.get("screen", "title"):
			"characters": show_characters()
			"stages": show_stages()
			"clauses": show_clauses()
			"options": show_options()
			"awards": show_achievements()
			"credits": show_credits()
			"collection": show_collection(opt.get("tab", "weapons"))
			"splash": show_splash()
			_: show_title() if opt.has("screen") or opt.has("shot") else show_splash()
	if opt.has("shot"): _shot(opt.shot, float(opt.get("wait", "1.5")), opt.get("panel", ""))

## Save a screenshot and quit (used by tools/shots.sh to check every screen).
func _shot(path: String, wait: float, panel: String) -> void:
	if run and panel == "boss":
		var b := run.enemies.spawn(EnemyPool.T.BOSS, run.player_pos.x + 260.0, run.player_pos.y - 40.0, 30.0)
		run.enemies.names[b] = run.stage.boss
	if run and panel.begins_with("ev_"):   # show an Imprevisto (blackout, rain...)
		run.event_name = panel.trim_prefix("ev_")
		run.event_left = 20.0
	if run and panel == "relic" and not run.relic_pickups().is_empty():
		var rp: Dictionary = run.relic_pickups()[0]
		run.player_pos = Vector2(rp.x - 300.0, rp.y + 60.0)
		run.cam.position = run.player_pos
	await get_tree().create_timer(wait).timeout
	if run and panel == "levelup":
		run.bot = false
		run.pending_levels = 1
		run.open_levelup()
	elif run and panel == "pause": run.toggle_pause()
	elif run and panel == "guion":
		run.bot = false
		run.guion_offers = 0
		run.offer_guion()
	elif run and panel == "results":
		run.bot = false
		run.finish(false)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _clear() -> VBoxContainer:
	if root: root.queue_free()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	ui.add_child(root)
	var bg := TextureRect.new()
	bg.texture = Data.tex("res://assets/ui/curtain.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, 28)
	root.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v

func _header(v: VBoxContainer, text: String) -> void:
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UIKit.button(Loc.t("back"), show_title, 140))
	var t := UIKit.title(text, 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UIKit.label("$ %d" % int(Save.data.taquilla), 24, UIKit.GOLD, UIKit.pixel_font))

func _scroll(v: VBoxContainer) -> Container:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(s)
	return s

# ---------- «Macacaweke Studio presenta» (L2) ----------
var _splash_done := true

func show_splash() -> void:
	var v := _clear()
	root.get_child(0).hide()   # plain black, no curtain
	root.get_child(1).color = Color.BLACK
	var c := CenterContainer.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(c)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(col)
	col.add_child(UIKit.title("Macacaweke Studio", 60))
	var p := UIKit.label(Loc.t("presents"), 26, UIKit.CREAM)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(p)
	col.modulate.a = 0.0
	_splash_done = false
	var tw := create_tween()
	tw.tween_property(col, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.4)
	tw.tween_property(col, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_end_splash)

func _end_splash() -> void:
	if _splash_done: return
	_splash_done = true
	show_title()

# ---------- title ----------
func show_title() -> void:
	var v := _clear()
	var art := TextureRect.new()
	art.texture = Data.tex("res://assets/ui/keyart.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(art)
	v.add_child(UIKit.title(Loc.t("game_title"), 64))
	var c := CenterContainer.new()
	v.add_child(c)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	c.add_child(col)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	col.add_child(row1)
	row1.add_child(UIKit.button(Loc.t("play"), show_characters, 240))
	row1.add_child(UIKit.button(Loc.t("clauses"), show_clauses, 240))
	row1.add_child(UIKit.button(Loc.t("awards"), show_achievements, 240))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	col.add_child(row2)
	row2.add_child(UIKit.button(Loc.t("collection"), show_collection, 240))
	row2.add_child(UIKit.button(Loc.t("options"), show_options, 240))
	row2.add_child(UIKit.button(Loc.t("credits"), show_credits, 240))
	if not OS.has_feature("web"): row2.add_child(UIKit.button(Loc.t("quit"), func(): get_tree().quit(), 240))
	UIKit.focus_first(col)

# ---------- casting ----------
func show_characters() -> void:
	var v := _clear()
	_header(v, Loc.t("casting"))
	var info := UIKit.label("", 20)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll(v).add_child(grid)
	for c in Data.characters:
		var unlocked := Save.is_unlocked("characters", c.id)
		var hired := Save.is_unlocked("hired", c.id)
		var text: String = c.name if unlocked else "???"
		if unlocked and not hired: text += "  ($%d)" % Save.hire_price(c)
		var b := UIKit.button(text, _on_char.bind(c), 290)
		b.disabled = not unlocked
		b.set_meta("id", c.id)
		b.tooltip_text = "%s — %s\n%s\n%s" % [c.name, c.title, c.bonus, Loc.t("unlock_by", [c.unlock])] if unlocked else Loc.t("unlock_by", [c.unlock])
		if c.id == sel_char: b.modulate = UIKit.GOLD.lightened(0.4)
		b.focus_entered.connect(func(): info.text = b.tooltip_text)
		b.mouse_entered.connect(func(): info.text = b.tooltip_text)
		grid.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(110, 120)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = Data.portrait(sel_char)
	bottom.add_child(pic)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(info)
	for b in grid.get_children():
		var cid: String = b.get_meta("id")
		b.focus_entered.connect(func(): pic.texture = Data.portrait(cid) if Save.is_unlocked("characters", cid) else null)
		b.mouse_entered.connect(func(): pic.texture = Data.portrait(cid) if Save.is_unlocked("characters", cid) else null)
	UIKit.focus_first(grid)

func _on_char(c: Dictionary) -> void:
	if not Save.is_unlocked("hired", c.id):
		if not Save.hire(c):
			return
	sel_char = c.id
	show_stages()

# ---------- stages ----------
func show_stages() -> void:
	var v := _clear()
	_header(v, Loc.t("stages"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var info := UIKit.label("", 20)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll(v).add_child(grid)
	for s in Data.stages:
		var unlocked := Save.is_unlocked("stages", s.id)
		var b := UIKit.button(s.name if unlocked else "???", _on_stage.bind(s), 390)
		b.disabled = not unlocked
		b.tooltip_text = "%s · %s · %d min\n%s\n%s" % [s.name, s.genre, s.minutes, s.mechanic, Loc.t("boss_is", [s.boss])] if unlocked else Loc.t("unlock_by", [s.unlock])
		b.focus_entered.connect(func(): info.text = b.tooltip_text)
		b.mouse_entered.connect(func(): info.text = b.tooltip_text)
		grid.add_child(b)
	v.add_child(info)
	_modifier_row(v)
	UIKit.focus_first(grid)

## Modificadores: switches for the next run, each unlocked by a relic.
func _modifier_row(v: VBoxContainer) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	row.add_child(UIKit.label(Loc.t("modifiers") + ":", 20, UIKit.GOLD))
	var on: Array = Save.data.mods_on
	for m in Data.modifiers:
		var ready := Data.modifier_ready(m) and Data.modifier_unlocked(m)
		var is_on: bool = ready and m.id in on
		var bonus := "  +%d %%" % roundi(Data.MOD_BONUS.get(m.id, 0.0) * 100.0) if Data.MOD_BONUS.get(m.id, 0.0) > 0.0 else ""
		var b := UIKit.button(("✔ " if is_on else "") + (m.name + bonus if ready else "🔒 " + m.name), _toggle_mod.bind(m.id), 200)
		b.disabled = not ready
		if is_on: b.modulate = UIKit.GOLD.lightened(0.4)
		b.tooltip_text = m.desc + "\n" + (m.reward if ready else (Loc.t("mod_soon") if not Data.modifier_ready(m) else Loc.t("mod_locked", [m.relic])))
		row.add_child(b)

func _toggle_mod(id: String) -> void:
	var on: Array = Save.data.mods_on
	if id in on: on.erase(id)
	else: on.append(id)
	Save.save_game()
	show_stages()

func _on_stage(s: Dictionary) -> void:
	sel_stage = s.id
	start_run()

# ---------- run ----------
func start_run(demo := false) -> void:
	if root: root.queue_free()
	root = null
	if run: run.queue_free()
	run = Run.new()
	var c: Dictionary = Data.char_by_id.get(sel_char, Data.characters[0])
	var s: Dictionary = Data.stage_by_id.get(sel_stage, Data.stages[0])
	run.setup(c, s)
	run.bot = demo
	run.exit_to_menu.connect(_end_run.bind(false))
	run.retry.connect(_end_run.bind(true))
	add_child(run)

func _end_run(again: bool) -> void:
	run.queue_free()
	run = null
	if again: start_run()
	else: show_title()

# ---------- Cláusulas del Contrato ----------
func show_clauses() -> void:
	var v := _clear()
	_header(v, Loc.t("clauses"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll(v).add_child(grid)
	for c in Data.clauses:
		var lvl := Save.clause_level(c.id)
		var maxed := lvl >= int(c.max_level)
		var off: bool = Save.data.clauses_off.get(c.id, false)
		var tag := "%d/%d" % [lvl, c.max_level]
		var desc := "%s — %s" % [c.desc, Loc.t("off") if off else (Loc.t("maxed") if maxed else "$%d" % Save.clause_price(c))]
		var card := UIKit.card(null, c.name, tag, desc, _on_clause.bind(c), 560)
		if not maxed and Save.clause_price(c) > int(Save.data.taquilla) and lvl == 0: card.modulate = Color(0.75, 0.7, 0.7)
		grid.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UIKit.button(Loc.t("refund"), func(): Save.refund_clauses(); show_clauses(), 260))
	row.add_child(UIKit.label(Loc.t("clause_help"), 18))
	UIKit.focus_first(grid)

func _on_clause(c: Dictionary) -> void:
	if Save.clause_level(c.id) >= int(c.max_level): Save.toggle_clause(c.id)
	elif not Save.buy_clause(c): return
	Sfx.play("chest")
	show_clauses()

# ---------- Premios ----------
func show_achievements() -> void:
	var v := _clear()
	_header(v, Loc.t("awards") + "  %d/%d" % [Save.data.achievements.size(), Data.achievements.size()])
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll(v).add_child(list)
	for a in Data.achievements:
		var got := Achievements.has(a.id)
		var l := UIKit.label(("» " if got else "·  ") + a.name + "  —  " + a.desc, 19, UIKit.GOLD if got else UIKit.CREAM.darkened(0.35))
		list.add_child(l)
	UIKit.focus_first(v)

# ---------- Colección ----------
func show_collection(tab := "weapons") -> void:
	var v := _clear()
	var found: int = Save.data.unlocked.relics.size()
	_header(v, Loc.t("collection"))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["weapons", Loc.t("col_weapons")], ["unions", Loc.t("col_unions")], ["passives", Loc.t("col_passives")], ["guiones", Loc.t("col_guiones")], ["relics", Loc.t("col_relics") + "  %d/%d" % [found, Data.relics.size()]]]:
		var b := UIKit.button(t[1], show_collection.bind(t[0]), 200)
		if t[0] == tab: b.modulate = UIKit.GOLD.lightened(0.4)
		tabs.add_child(b)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll(v).add_child(grid)
	var evolved: Array = Save.data.stats.evolved
	var book := Save.is_unlocked("relics", "libro_de_montaje")
	match tab:
		"weapons":
			for w in Data.weapon_list:
				var avail: bool = w.source == "base" or Save.is_unlocked("weapons", w.id)
				grid.add_child(_col_card(Data.icon_for(w.id), w.name, w.desc, avail))
				var e: Dictionary = w.evolution
				var known: bool = w.id in evolved
				var req: String = Data.passives[e.requires].name if Data.passives.has(e.requires) else ""
				var how := Loc.t("col_evo_req", [w.name, req]) if req != "" else ""
				var desc: String = (e.desc + ("\n" if e.desc != "" else "") + how) if known or book else Loc.t("col_evo_hidden")
				grid.add_child(_col_card(Data.icon_for(e.id), e.name if known or book else "???", desc, known, "★"))
		"unions":
			for u in Data.unions:
				var known: bool = u.id in evolved
				var parts: Array = []
				for id in u.weapons + u.passives:
					parts.append(Data.weapons[id].name if Data.weapons.has(id) else Data.passives.get(id, {}).get("name", id))
				grid.add_child(_col_card(Data.icon_for(u.id), u.name if known or book else "???", u.desc + "\n" + " + ".join(parts) if known or book else Loc.t("col_union_hidden", [" + ".join(parts)]), known, "★★"))
		"passives":
			for p in Data.passive_list:
				grid.add_child(_col_card(Data.icon_for(p.id), p.name, p.desc, true))
		"guiones":
			var deck := Save.is_unlocked("relics", "baraja_del_guionista")
			for g in Data.guiones:
				var playable: bool = g.id in Run.GUION_READY
				var known: bool = deck and not g.cursed
				var text: String = g.desc if known else (Loc.t("col_hint", [g.get("how", Data.relic_by_id.baraja_del_guionista.name)]))
				if known and not playable: text += "  (" + Loc.t("mod_soon") + ")"
				grid.add_child(_col_card(Data.guion_icon(g.id), g.name if known else "???", text, known, ("☠ " if g.cursed else "") + g.num))
		"relics":
			for r in Data.relics:
				var got := Save.is_unlocked("relics", r.id)
				grid.add_child(_col_card(Data.icon_for(r.id), r.name if got else "???", r.unlocks if got else Loc.t("col_hint", [r.where]), got))
	UIKit.focus_first(tabs)

## One entry of the Colección: icon (a dark silhouette while undiscovered), name and text.
func _col_card(icon: Texture2D, name: String, desc: String, known: bool, tag := "") -> Control:
	var c := UIKit.card(icon, name, tag, desc, func(): pass, 600)
	c.custom_minimum_size.y = 104
	c.focus_mode = Control.FOCUS_NONE
	if not known:
		for n in c.find_children("*", "TextureRect", true, false): n.modulate = Color(0.05, 0.03, 0.08, 0.9)
	return c

# ---------- options ----------
func show_options() -> void:
	var v := _clear()
	_header(v, Loc.t("options"))
	var o: Dictionary = Save.data.options
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll(v).add_child(grid)
	grid.add_child(UIKit.label(Loc.t("language"), 22))
	grid.add_child(UIKit.button("Español" if o.lang == "es" else "English", func(): o.lang = "en" if o.lang == "es" else "es"; _save_opts(); show_options()))
	for k in ["sfx", "music"]:
		grid.add_child(UIKit.label(Loc.t("vol_" + k), 22))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(o[k])
		sl.custom_minimum_size = Vector2(280, 32)
		sl.value_changed.connect(func(val): o[k] = val; _save_opts())
		grid.add_child(sl)
	for k in ["fullscreen", "shake", "flashes", "damage_numbers"]:
		grid.add_child(UIKit.label(Loc.t("opt_" + k), 22))
		grid.add_child(UIKit.button(Loc.t("on") if o[k] else Loc.t("off"), func(): o[k] = not o[k]; _save_opts(); show_options()))
	grid.add_child(UIKit.label(Loc.t("controls"), 24, UIKit.GOLD))
	grid.add_child(UIKit.label(Loc.t("pad_touch"), 18))
	for a in Controls.REBINDABLE:
		grid.add_child(UIKit.label(Loc.t("act_" + a), 20))
		var b := UIKit.button(Loc.t("press_key") if waiting_bind == a else Controls.key_name(a), func(): waiting_bind = a; show_options())
		grid.add_child(b)
	grid.add_child(UIKit.label("", 10))
	grid.add_child(UIKit.button(Loc.t("reset_keys"), func(): Controls.reset(); show_options()))
	UIKit.focus_first(grid)

func _save_opts() -> void:
	Save.apply_options()
	Save.save_game()

func _input(e: InputEvent) -> void:
	if not _splash_done and (e is InputEventKey or e is InputEventJoypadButton or e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed():
		_end_splash()
		return
	if waiting_bind != "" and e is InputEventKey and e.pressed:
		if e.physical_keycode != KEY_ESCAPE: Controls.rebind(waiting_bind, e.physical_keycode)
		waiting_bind = ""
		get_viewport().set_input_as_handled()
		show_options()

# ---------- credits ----------
func show_credits() -> void:
	var v := _clear()
	_header(v, Loc.t("credits"))
	var text := UIKit.label(Loc.t("credits_text"), 22)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll(v).add_child(text)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.focus_first(v)
