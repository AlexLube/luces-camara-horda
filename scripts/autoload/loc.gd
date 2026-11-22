extends Node
## UI strings in Spanish and English (i18n/ui.json). Content names stay in Spanish until the English pass (phase 6).

signal changed
var lang := "es"
var _s := {}

func _ready() -> void:
	var f := FileAccess.open("res://i18n/ui.json", FileAccess.READ)
	_s = JSON.parse_string(f.get_as_text())

func t(key: String, args: Array = []) -> String:
	var e: Dictionary = _s.get(key, {})
	var s: String = e.get(lang, e.get("es", key))
	return s % args if args.size() > 0 else s

func set_lang(l: String) -> void:
	if l == lang: return
	lang = l
	changed.emit()
