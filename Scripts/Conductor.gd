class_name Conductor
extends AudioStreamPlayer
## Plays the song and keeps track of exactly where we are in it, in seconds and in beats.
## Every other part of the game asks the Conductor "what time is it?" rather than counting frames,
## so nothing can drift out of sync with the music.

## Sent once each time the song passes a beat. beat_index starts at 0.
signal beat_passed(beat_index: int)
## Sent when the song reaches its end.
signal song_finished

## The beat map pasted from Groove Tapper.
@export_file("*.json") var beat_map_path: String = "res://charts/beatmap.json"
## Shifts all timing to suit your speakers or headphones.
## Raise it if the beats look early, lower it if they look late.
@export_range(-300.0, 300.0, 1.0, "suffix:ms") var audio_offset_ms: float = 0.0

var beat_map: BeatMap
## Where the song is right now, in seconds, as you hear it.
var song_time: float = 0.0
## Where the song is right now, in beats. 12.5 means halfway between beats 12 and 13.
var song_beat: float = -1.0

var _running: bool = false
var _last_whole_beat: int = -1


func _ready() -> void:
	beat_map = BeatMap.load_from_file(beat_map_path)
	finished.connect(_on_finished)


## Starts the song from the beginning.
func start_song() -> void:
	if beat_map == null:
		push_error("Conductor: no beat map loaded, so the song won't start.")
		return
	if stream == null:
		push_error("Conductor: no song set. Drag the song into the Conductor's Stream property.")
		return
	song_time = 0.0
	song_beat = beat_map.beat_at_time(0.0)
	_last_whole_beat = floori(song_beat)
	_running = true
	play()


func _process(_delta: float) -> void:
	if not _running or not playing:
		return

	# Godot's recommended way to get the time as heard: the playback position,
	# plus time since the last audio chunk was mixed, minus the delay to the speakers.
	var t := get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	t += audio_offset_ms / 1000.0
	# The reading can wobble backwards by a few milliseconds. Never let time run backwards.
	song_time = maxf(song_time, t)
	song_beat = beat_map.beat_at_time(song_time)

	var whole := floori(song_beat)
	while _last_whole_beat < whole:
		_last_whole_beat += 1
		if _last_whole_beat >= 0 and _last_whole_beat < beat_map.count():
			beat_passed.emit(_last_whole_beat)


func _on_finished() -> void:
	_running = false
	song_finished.emit()
