extends Node
## Small pool of players for the placeholder sound effects (assets/sfx). Music lives in music.gd.

var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var _last := {}
var volume := 0.8

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for n in ["hit", "pickup", "levelup", "chest", "boss", "hurt", "death", "select", "shoot", "explode"]:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)

func play(name: String, pitch := 1.0) -> void:
	if volume <= 0.0 or not _streams.has(name): return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, 0)) < 45: return  # avoid stacking the same sound in one frame burst
	_last[name] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(volume)
			p.pitch_scale = pitch
			p.play()
			return
