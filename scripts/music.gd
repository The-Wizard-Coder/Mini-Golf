extends AudioStreamPlayer
## Background music. Registered as an autoload so it keeps playing across
## scene changes (menu <-> game).

const TRACK := "res://assets/audio/bgm.ogg"


func _ready() -> void:
	var s := load(TRACK) as AudioStreamOggVorbis
	if s != null:
		s.loop = true
		stream = s
	volume_db = -6.0
	play()
