extends Node2D
## Stage 1 test: plays the song and flashes a square on every beat in the beat map.
## Beat 1 of each bar (as marked in Groove Tapper) flashes gold, the rest blue.
## Keys: [ and ] shift the timing 5 ms earlier or later. R restarts the song.

@onready var conductor: Conductor = $Conductor
@onready var info: Label = $Info

var _flash: float = 0.0
var _last_beat: int = -1
var _done: bool = false


func _ready() -> void:
	conductor.beat_passed.connect(_on_beat_passed)
	conductor.song_finished.connect(_on_song_finished)
	conductor.start_song()


func _on_beat_passed(beat_index: int) -> void:
	_last_beat = beat_index
	_flash = 1.0


func _on_song_finished() -> void:
	_done = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				conductor.audio_offset_ms -= 5.0
			KEY_BRACKETRIGHT:
				conductor.audio_offset_ms += 5.0
			KEY_R:
				_last_beat = -1
				_done = false
				conductor.start_song()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 6.0)
	queue_redraw()

	if conductor.beat_map == null:
		info.text = "No beat map loaded. Check the Output panel for the reason."
		return
	info.text = "Time   %.3f s\nBeat   %d of %d\nOffset %+.0f ms   ([ and ] to adjust, R to restart)%s" % [
		conductor.song_time,
		_last_beat + 1,
		conductor.beat_map.count(),
		conductor.audio_offset_ms,
		"\nSong finished." if _done else "",
	]


func _draw() -> void:
	var box := 160.0
	var centre := get_viewport_rect().size / 2.0
	var base := Color(0.22, 0.26, 0.34)
	var bar_start := conductor.beat_map != null and conductor.beat_map.is_bar_start(_last_beat)
	var lit := Color(1.0, 0.8, 0.3) if bar_start else Color(0.55, 0.72, 1.0)
	draw_rect(Rect2(centre - Vector2(box, box) / 2.0, Vector2(box, box)), base.lerp(lit, _flash))
