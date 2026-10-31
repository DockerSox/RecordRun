extends Node2D
## Stage 2 test: plays the song, flashes the square on every beat, and shows each scratch
## from the chart as an arrow (left or right) on the beat it lands on.
## Beat 1 of each bar flashes gold, the rest blue. In rhythm-guide sections the square is outlined.
## Keys: [ and ] shift the timing 5 ms earlier or later. R restarts the song.

## The section table the chart is built from.
@export_file("*.json") var sections_path: String = "res://charts/sections.json"

@onready var conductor: Conductor = $Conductor
@onready var info: Label = $Info

var chart: Chart

var _flash: float = 0.0
var _arrow: float = 0.0
var _arrow_dir: int = 0
var _last_beat: int = -1
var _next_note: int = 0
var _done: bool = false


func _ready() -> void:
	conductor.beat_passed.connect(_on_beat_passed)
	conductor.song_finished.connect(_on_song_finished)
	if conductor.beat_map != null:
		chart = Chart.build(sections_path, conductor.beat_map)
		if chart != null:
			chart.print_summary()
	conductor.start_song()


func _on_beat_passed(beat_index: int) -> void:
	_last_beat = beat_index
	_flash = 1.0
	if chart == null:
		return
	while _next_note < chart.notes.size() and chart.notes[_next_note].beat < beat_index:
		_next_note += 1
	if _next_note < chart.notes.size() and chart.notes[_next_note].beat == beat_index:
		_arrow_dir = chart.notes[_next_note].dir
		_arrow = 1.0
		_next_note += 1


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
				_next_note = 0
				_arrow = 0.0
				_done = false
				conductor.start_song()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 6.0)
	_arrow = maxf(0.0, _arrow - delta * 3.0)
	queue_redraw()

	if conductor.beat_map == null:
		info.text = "No beat map loaded. Check the Output panel for the reason."
		return
	var section := "No chart loaded. Check the Output panel." if chart == null else chart.describe(chart.section_at(_last_beat))
	var next := "none"
	if chart != null and _next_note < chart.notes.size():
		var n: Chart.Note = chart.notes[_next_note]
		next = "%s on beat %d, in %.1f s" % ["Left" if n.dir == Chart.LEFT else "Right", n.beat + 1, maxf(0.0, n.time - conductor.song_time)]
	info.text = "Time   %.3f s\nBeat   %d of %d\nSection  %s\nNext scratch  %s\nOffset %+.0f ms   ([ and ] to adjust, R to restart)%s" % [
		conductor.song_time,
		_last_beat + 1,
		conductor.beat_map.count(),
		section,
		next,
		conductor.audio_offset_ms,
		"\nSong finished." if _done else "",
	]


func _draw() -> void:
	var box := 160.0
	var centre := get_viewport_rect().size / 2.0
	var base := Color(0.22, 0.26, 0.34)
	var bar_start := conductor.beat_map != null and conductor.beat_map.is_bar_start(_last_beat)
	var lit := Color(1.0, 0.8, 0.3) if bar_start else Color(0.55, 0.72, 1.0)
	var rect := Rect2(centre - Vector2(box, box) / 2.0, Vector2(box, box))
	draw_rect(rect, base.lerp(lit, _flash))
	if chart != null and chart.is_guide(_last_beat):
		draw_rect(rect.grow(10.0), Color(0.55, 0.72, 1.0, 0.6), false, 3.0)

	if _arrow > 0.0 and _arrow_dir != 0:
		var colour := Color(1.0, 0.45, 0.35, _arrow) if _arrow_dir == Chart.LEFT else Color(0.35, 0.9, 0.6, _arrow)
		var tip := centre + Vector2(_arrow_dir * (box / 2.0 + 120.0), 0.0)
		var back := tip - Vector2(_arrow_dir * 80.0, 0.0)
		draw_colored_polygon(PackedVector2Array([tip, back + Vector2(0, -55), back + Vector2(0, 55)]), colour)
