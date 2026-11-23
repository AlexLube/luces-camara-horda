class_name UIKit
extends RefCounted
## Shared look for menus and in-run panels: velvet red, gold trim, cinema fonts.
## Every screen is built in code from these helpers, so buttons work the same with mouse, touch and gamepad.

const GOLD := Color("f2b83b")
const RED := Color("8e1426")
const DARK := Color("140a0e")
const CREAM := Color("f6ead2")

static var _theme: Theme
static var text_scale := 1.0      # accessibility: bigger menu text
static var title_font: Font
static var pixel_font: Font

static func theme() -> Theme:
	if _theme: return _theme
	title_font = load("res://assets/fonts/Limelight-Regular.ttf")
	pixel_font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	var t := Theme.new()
	t.default_font = load("res://assets/fonts/ArchivoNarrow.ttf")
	t.default_font_size = int(round(22 * text_scale))
	var normal := _box(Color(0.24, 0.05, 0.09, 0.95), GOLD.darkened(0.45), 2)
	var hover := _box(Color(0.42, 0.08, 0.14, 0.98), GOLD, 3)
	var pressed := _box(Color(0.55, 0.1, 0.16, 1.0), GOLD.lightened(0.3), 3)
	var disabled := _box(Color(0.15, 0.1, 0.1, 0.8), Color(0.3, 0.25, 0.2), 2)
	for s in [["normal", normal], ["hover", hover], ["pressed", pressed], ["focus", hover], ["disabled", disabled]]:
		t.set_stylebox(s[0], "Button", s[1])
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.4))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.08, 0.03, 0.05, 0.94), GOLD, 3, 14))
	t.set_color("font_color", "Label", CREAM)
	var grab := _box(GOLD, GOLD, 0, 6)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	t.set_stylebox("slider", "HSlider", _box(Color(0.3, 0.2, 0.2), Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("panel", "TooltipPanel", _box(DARK, GOLD, 2))
	_theme = t
	return t

static func set_text_scale(k: float) -> void:
	text_scale = k
	if _theme: _theme.default_font_size = int(round(22 * k))

static func _box(bg: Color, border: Color, bw: int, pad := 10) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(6)
	b.content_margin_left = pad + 4
	b.content_margin_right = pad + 4
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b

static func label(text: String, size := 22, color := CREAM, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(round(size * text_scale)))
	l.add_theme_color_override("font_color", color)
	if font: l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func title(text: String, size := 54) -> Label:
	theme()
	var l := label(text, size, GOLD, title_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l

static func button(text: String, cb: Callable, min_w := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.pressed.connect(func(): Sfx.play("select"); cb.call())
	b.focus_entered.connect(func(): Sfx.play("ui_move"))
	return b

## A wide card button: icon, title line, level tag and a description underneath.
static func card(icon: Texture2D, name: String, tag: String, desc: String, cb: Callable, w := 520.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, 86)
	b.pressed.connect(cb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	h.add_theme_constant_override("separation", 14)
	b.add_child(h)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(56, 56)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = icon
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var n := label(name, 24, GOLD)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	if tag != "": top.add_child(label(tag, 18, CREAM))
	var d := label(desc, 18, CREAM.darkened(0.1))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = w - 110.0
	v.add_child(d)
	return b

static func centered_panel(parent: Node, min_size := Vector2(600, 300)) -> VBoxContainer:
	theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v

static func fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

## Focus the first button found under n, so gamepads and keyboards can navigate right away.
static func focus_first(n: Node) -> bool:
	for c in n.get_children():
		if c is Button and not c.disabled:
			c.call_deferred("grab_focus")
			return true
		if focus_first(c): return true
	return false
