extends Node2D
## Stage 5: the groove, the needle and the scratches, with input and judging.
## Press left or right as each scratch reaches the needle, on its beat:
##   tap the left or right half of the screen, or press A / D or the arrow keys.
## Each press is judged Hit, Wrong way, Early or Late; scratches with no press are Missed,
## and presses with no scratch nearby are Stray. (Penalties come in Stage 6.)
## Keys: [ and ] shift the timing 5 ms earlier or later. R restarts the song. F1 shows or hides the info.

## The section table the chart is built from.
@export_file("*.json") var sections_path: String = "res://charts/sections.json"
## A press this close to a scratch's beat counts as on time.
@export_range(20.0, 200.0, 5.0, "suffix:ms") var hit_window_ms: float = 100.0
## A press within this of a scratch is judged early or late; further away, it's a stray press.
@export_range(50.0, 210.0, 5.0, "suffix:ms") var judge_window_ms: float = 200.0

@onready var conductor: Conductor = $Conductor
@onready var groove: Groove = $Groove
@onready var info: Label = $Info

var chart: Chart
var judge: Judge
var _last_beat: int = -1
var _last_result: String = ""


func _ready() -> void:
	if conductor.beat_map != null:
		chart = Chart.build(sections_path, conductor.beat_map)
	if chart != null:
		judge = Judge.new(chart, hit_window_ms, judge_window_ms)
		judge.judged.connect(_on_judged)
	_add_key_actions()
	groove.conductor = conductor
	groove.chart = chart
	conductor.beat_passed.connect(_on_beat_passed)
	conductor.start_song()


## Left and right as input actions, so the keys can be changed later in Project Settings > Input Map.
func _add_key_actions() -> void:
	for pair: Array in [["scratch_left", [KEY_A, KEY_LEFT]], ["scratch_right", [KEY_D, KEY_RIGHT]]]:
		var action: String = pair[0]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code: int in pair[1]:
			var key := InputEventKey.new()
			key.physical_keycode = code as Key
			InputMap.action_add_event(action, key)


func _press(dir: int) -> void:
	if judge != null:
		judge.press(dir, conductor.current_time())


func _on_judged(result: int, note_index: int, offset_ms: float) -> void:
	var dir := chart.notes[note_index].dir if note_index >= 0 else 0
	groove.show_result(result, dir)
	_last_result = Judge.NAMES[result]
	if result != Judge.Result.MISSED and result != Judge.Result.STRAY:
		_last_result += " (%+.0f ms)" % offset_ms


func _on_beat_passed(beat_index: int) -> void:
	_last_beat = beat_index
	groove.on_beat(beat_index)


func _unhandled_input(event: InputEvent) -> void:
	# Touch: left or right half of the screen. With "Emulate Touch From Mouse" on, a click counts too.
	if event is InputEventScreenTouch and event.pressed:
		_press(Chart.LEFT if event.position.x < get_viewport_rect().size.x * 0.5 else Chart.RIGHT)
		return
	if event.is_action_pressed("scratch_left", false, true):
		_press(Chart.LEFT)
		return
	if event.is_action_pressed("scratch_right", false, true):
		_press(Chart.RIGHT)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				conductor.audio_offset_ms -= 5.0
			KEY_BRACKETRIGHT:
				conductor.audio_offset_ms += 5.0
			KEY_R:
				_last_beat = -1
				_last_result = ""
				if judge != null:
					judge.reset()
				conductor.start_song()
			KEY_F1:
				info.visible = not info.visible


func _process(_delta: float) -> void:
	if judge != null:
		judge.update(conductor.current_time())
	if not info.visible:
		return
	if conductor.beat_map == null:
		info.text = "No beat map loaded. Check the Output panel for the reason."
		return
	var section := "No chart loaded. Check the Output panel." if chart == null else chart.describe(chart.section_at(_last_beat))
	var c := judge.counts if judge != null else PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	info.text = "Beat %d of %d  ·  %s\nHit %d  ·  Wrong %d  ·  Early %d  ·  Late %d  ·  Missed %d  ·  Stray %d\nLast: %s\nOffset %+.0f ms  ([ ] adjust · R restart · F1 hide)" % [
		_last_beat + 1, conductor.beat_map.count(), section,
		c[Judge.Result.HIT], c[Judge.Result.WRONG], c[Judge.Result.EARLY], c[Judge.Result.LATE],
		c[Judge.Result.MISSED], c[Judge.Result.STRAY],
		_last_result, conductor.audio_offset_ms]
