extends Node
## Original soundtrack (made by tools/audio/compose.py): one looping track per film genre,
## the title theme in the menus and a boss theme while a jefe is on screen. Tracks crossfade.

const BY_GENRE := {
	"terror": ["Terror clásico", "Terror de serie B", "Slasher adolescente", "Terror psicológico", "Oculto", "Gótico",
		"Vampiros clásicos de cine", "Fantasía oscura", "Terror oriental", "Serie B años 50"],
	"western": ["Western"],
	"scifi": ["Ciencia ficción", "Cyberpunk", "Espías de la Guerra Fría", "Postapocalíptico", "Monstruos gigantes"],
	"noir": ["Cine negro en blanco y negro", "Thriller en tren"],
	"aventura": ["Aventuras", "Piratas", "Fantasía", "Cine de romanos", "Artes marciales", "Dinosaurios"],
	"comedia": ["Dibujos animados", "Animación artesanal", "Cine mudo", "Musical", "Melodrama"],
	"accion": ["Bélico", "Cine de catástrofes", "Boss rush", "Práctica"],
}
const FADE := 0.9

var volume := 0.7
var current := ""
var _players: Array = []     # [player, gain, target]; the last one is the current track

func track_for(stage: Dictionary) -> String:
	for k in BY_GENRE:
		if stage.get("genre", "") in BY_GENRE[k]: return k
	return "aventura"

func play(id: String) -> void:
	if id == current: return
	current = id
	var path := "res://assets/music/%s.ogg" % id
	if not ResourceLoader.exists(path): return
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis: s.loop = true
	for e in _players: e[2] = 0.0
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = _db(0.0)
	add_child(p)
	p.play()
	_players.append([p, 0.0, 1.0])

func stop() -> void:
	current = ""
	for e in _players: e[2] = 0.0

## Crossfade: every player moves its gain towards its target; silent old ones are freed.
func _process(dt: float) -> void:
	var keep: Array = []
	for e in _players:
		e[1] = move_toward(e[1], e[2], dt / FADE)
		e[0].volume_db = _db(e[1])
		if e[1] <= 0.0 and e[2] <= 0.0: e[0].queue_free()
		else: keep.append(e)
	_players = keep

func _db(k: float) -> float:
	return linear_to_db(max(0.0001, volume * k))
