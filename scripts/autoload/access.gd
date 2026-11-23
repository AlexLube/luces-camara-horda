extends CanvasLayer
## Accessibility: a colour filter for colour-blind players (daltonization, drawn over everything)
## and the text size of the menus. Options live in Save.data.options.

const MODES := ["off", "protan", "deutan", "tritan"]
const TEXT_SIZES := [1.0, 1.15, 1.3]
const SPEEDS := [1.0, 0.85, 0.7]

var _rect: ColorRect

func _ready() -> void:
	layer = 128
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform int mode = 1;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	// RGB -> LMS
	float L = 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b;
	float M = 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b;
	float S = 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b;
	float l = L; float m = M; float s = S;
	if (mode == 1) { l = 2.02344 * M - 2.52581 * S; }
	else if (mode == 2) { m = 0.494207 * L + 1.24827 * S; }
	else { s = -0.395913 * L + 0.801109 * M; }
	// LMS -> RGB (what the player sees)
	vec3 sim = vec3(0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
		-0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
		-0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s);
	// move the lost difference into channels the player can tell apart
	vec3 err = c - sim;
	vec3 fix = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(c + fix, 0.0, 1.0), 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_rect.material = mat
	add_child(_rect)
	apply()

## Read the options and update the filter and the menu text size.
func apply() -> void:
	if _rect == null: return
	var o: Dictionary = Save.data.get("options", {})
	var mode := MODES.find(String(o.get("colorblind", "off")))
	_rect.visible = mode > 0
	if mode > 0: (_rect.material as ShaderMaterial).set_shader_parameter("mode", mode)
	UIKit.set_text_scale(float(o.get("text_size", 1.0)))

func game_speed() -> float:
	return float(Save.data.options.get("game_speed", 1.0))

## Next value in a list of choices (wraps round).
static func cycle(list: Array, v) -> Variant:
	var i := list.find(v)
	return list[(i + 1) % list.size()]
