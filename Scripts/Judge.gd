class_name Judge
extends RefCounted
## Decides how well each press matches the chart, and notices scratches that pass with no press.
##
## Timing, measured from the scratch's beat:
##   within hit_window              on time: a hit if the direction is right
##   between hit_window and judge_window   early or late (a mistake)
##   further than judge_window from every scratch   a stray press (a mistake)
## A wrong-direction press anywhere inside judge_window is a mistake and uses up that scratch.
## Keep judge_window under half the gap between the closest scratches (about 0.21 s at the peak),
## so a press can never be claimed by two scratches.

enum Result { NONE, HIT, WRONG, EARLY, LATE, MISSED, STRAY }
const NAMES: Array[String] = ["", "Hit", "Wrong way", "Early", "Late", "Missed", "Stray"]

## Sent for every judgement. note_index is -1 for a stray press. offset_ms is negative when early.
signal judged(result: int, note_index: int, offset_ms: float)

var hit_window: float
var judge_window: float
## How many of each result so far, by Result value.
var counts: PackedInt32Array = PackedInt32Array()

var _notes: Array[Chart.Note]
var _first_open: int = 0


func _init(chart: Chart, hit_window_ms: float = 100.0, judge_window_ms: float = 200.0) -> void:
	_notes = chart.notes
	hit_window = hit_window_ms / 1000.0
	judge_window = judge_window_ms / 1000.0
	reset()


## Clears every judgement, for a restart.
func reset() -> void:
	for n in _notes:
		n.result = Result.NONE
	counts.resize(Result.size())
	counts.fill(0)
	_first_open = 0


## True if this result is a mistake.
static func is_mistake(result: int) -> bool:
	return result != Result.NONE and result != Result.HIT


## Judges a press. dir is Chart.LEFT or Chart.RIGHT; time is the song time of the press.
func press(dir: int, time: float) -> void:
	var best := -1
	var best_gap := INF
	for i in range(_first_open, _notes.size()):
		var n := _notes[i]
		if n.time - time > judge_window:
			break
		if n.result != Result.NONE:
			continue
		var gap := absf(time - n.time)
		if gap <= judge_window and gap < best_gap:
			best = i
			best_gap = gap
	if best < 0:
		_record(Result.STRAY, -1, 0.0)
		return

	var note := _notes[best]
	var offset := time - note.time
	var result: int
	if note.dir != dir:
		result = Result.WRONG
	elif absf(offset) <= hit_window:
		result = Result.HIT
	elif offset < 0.0:
		result = Result.EARLY
	else:
		result = Result.LATE
	note.result = result
	_record(result, best, offset * 1000.0)


## Call every frame: any scratch more than judge_window past the needle with no press is missed.
func update(time: float) -> void:
	while _first_open < _notes.size():
		var n := _notes[_first_open]
		if n.result == Result.NONE:
			if time - n.time <= judge_window:
				return
			n.result = Result.MISSED
			_record(Result.MISSED, _first_open, 0.0)
		_first_open += 1


func _record(result: int, note_index: int, offset_ms: float) -> void:
	counts[result] += 1
	judged.emit(result, note_index, offset_ms)
