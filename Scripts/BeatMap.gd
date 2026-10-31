class_name BeatMap
extends RefCounted
## The time, in seconds, of every beat in the song.
## Loaded from the JSON file that Groove Tapper's "Copy beat map for Godot" button produces.
## Beat numbers start at 0, so beat 0 is the first beat you tapped.

var song_name: String = ""
var beats: PackedFloat64Array = PackedFloat64Array()
## The beat numbers that are beat 1 of a bar, as marked in Groove Tapper.
var bar_starts: PackedInt32Array = PackedInt32Array()

var _is_bar_start: PackedByteArray = PackedByteArray()


## Reads a beat map file. Returns null (and prints the reason in the Output panel) if it can't.
static func load_from_file(path: String) -> BeatMap:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("BeatMap: couldn't open %s (error code %d). Check the file exists and the path is right." % [path, FileAccess.get_open_error()])
		return null

	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not data.has("beats") or typeof(data["beats"]) != TYPE_ARRAY:
		push_error("BeatMap: %s isn't a Groove Tapper beat map. Paste the copied text in again." % path)
		return null

	var map := BeatMap.new()
	map.song_name = str(data.get("song", ""))
	for t: Variant in data["beats"]:
		map.beats.append(float(t))
	map.beats.sort()

	if map.beats.size() < 2:
		push_error("BeatMap: %s has fewer than 2 beats in it." % path)
		return null

	map._is_bar_start.resize(map.beats.size())
	map._is_bar_start.fill(0)
	if data.has("bar_starts") and typeof(data["bar_starts"]) == TYPE_ARRAY:
		for b: Variant in data["bar_starts"]:
			var i := int(b)
			if i >= 0 and i < map.beats.size():
				map.bar_starts.append(i)
				map._is_bar_start[i] = 1
	else:
		push_warning("BeatMap: %s has no bar starts, so every 4th beat is treated as beat 1. Copy the beat map from Groove Tapper again to include them." % path)
		for i in range(0, map.beats.size(), 4):
			map.bar_starts.append(i)
			map._is_bar_start[i] = 1
	return map


## How many beats are in the map.
func count() -> int:
	return beats.size()


## True if this beat is beat 1 of a bar.
func is_bar_start(beat: int) -> bool:
	return beat >= 0 and beat < _is_bar_start.size() and _is_bar_start[beat] == 1


## The time (seconds) of a beat. Fractions are allowed: beat 10.5 is halfway between beats 10 and 11.
## Before the first beat or after the last, it carries on at the nearest interval.
func time_of_beat(beat: float) -> float:
	var n := beats.size()
	if beat <= 0.0:
		return beats[0] + beat * (beats[1] - beats[0])
	if beat >= n - 1:
		return beats[n - 1] + (beat - (n - 1)) * (beats[n - 1] - beats[n - 2])
	var i := floori(beat)
	return lerpf(beats[i], beats[i + 1], beat - i)


## The reverse of time_of_beat: which beat (with a fraction) a moment in the song falls on.
## Negative before the first beat.
func beat_at_time(time: float) -> float:
	var n := beats.size()
	if time <= beats[0]:
		return (time - beats[0]) / (beats[1] - beats[0])
	if time >= beats[n - 1]:
		return (n - 1) + (time - beats[n - 1]) / (beats[n - 1] - beats[n - 2])
	var i: int = beats.bsearch(time) - 1   # the last beat at or before this time
	return i + (time - beats[i]) / (beats[i + 1] - beats[i])
