class_name Chart
extends RefCounted
## The scratches for the song: which beat each one lands on and which way it goes.
## Built every time the game starts from the section table (charts/sections.json) and the beat map,
## so to try a change you edit the table and press F5.
##
## Section table fields. Beat numbers start at 1, the same as Groove Tapper and the on-screen label.
##   name     Shown on screen and in the Output panel.
##   from, to First and last beat of the section.
##   guide    true = no scratches, rhythm guide only.
##   every    A scratch every N beats, counted from each bar start: 1, 2, 4, 8, 12 or 16.
##   level    How the left/right pattern is chosen, 1 to 5:
##              1 same direction for 2-4 scratches, then switch   L L L R R L L L L
##              2 strict alternation                               L R L R
##              3 pairs                                            L L R R
##              4 short mixed motifs                               L L R . L R R
##              5 irregular                                        L L R L R R L R L L
##   pattern  Optional, e.g. "LLRLR": an exact pattern that repeats. Replaces level.
##   beats    Optional, e.g. [13, 17]: exact beats to use. Replaces every.
##   seed     (top of the file) Change it to get different patterns for levels 1-5.

const LEFT := -1
const RIGHT := 1


class Note:
	## Index into the beat map (0 = first beat).
	var beat: int
	## LEFT or RIGHT.
	var dir: int
	## When the scratch should be hit, in seconds.
	var time: float
	## Index into Chart.sections.
	var section: int


## Every scratch, in order.
var notes: Array[Note] = []
## The sections as read from the table.
var sections: Array[Dictionary] = []

var _section_of: PackedInt32Array = PackedInt32Array()
var _guide: PackedByteArray = PackedByteArray()


## Builds the chart. Returns null (and prints why in the Output panel) if the table can't be read.
static func build(path: String, map: BeatMap) -> Chart:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Chart: couldn't open %s (error code %d)." % [path, FileAccess.get_open_error()])
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Chart: %s has a mistake on line %d: %s. Check for a missing comma or bracket." % [path, json.get_error_line(), json.get_error_message()])
		return null
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("sections")) != TYPE_ARRAY:
		push_error("Chart: %s needs a \"sections\" list." % path)
		return null

	var chart := Chart.new()
	var n := map.count()
	chart._section_of.resize(n)
	chart._section_of.fill(-1)
	chart._guide.resize(n)
	chart._guide.fill(0)
	var base_seed := int(data.get("seed", 1))
	var taken := {}

	for raw: Variant in data["sections"]:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("Chart: every entry in \"sections\" must be { ... }.")
			continue
		var sec: Dictionary = raw
		var idx := chart.sections.size()
		var label := str(sec.get("name", "Section %d" % (idx + 1)))
		sec["name"] = label
		if not (sec.has("from") and sec.has("to")):
			push_error("Chart: section \"%s\" needs \"from\" and \"to\"." % label)
			continue
		var lo := int(sec["from"]) - 1
		var hi := mini(int(sec["to"]) - 1, n - 1)
		if lo < 0 or lo > hi:
			push_error("Chart: section \"%s\" has from/to outside the song (it has %d beats)." % [label, n])
			continue
		chart.sections.append(sec)
		for b in range(lo, hi + 1):
			if chart._section_of[b] != -1:
				push_warning("Chart: section \"%s\" overlaps \"%s\" at beat %d." % [label, chart.sections[chart._section_of[b]]["name"], b + 1])
			chart._section_of[b] = idx
			if sec.get("guide", false):
				chart._guide[b] = 1
		if sec.get("guide", false):
			continue

		var spots := _positions(sec, lo, hi, map)
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed * 1000 + idx   # each section has its own sequence, so editing one leaves the rest alone
		var dirs := _directions(sec, spots.size(), rng)
		for k in spots.size():
			var b: int = spots[k]
			if taken.has(b):
				continue
			taken[b] = true
			var note := Note.new()
			note.beat = b
			note.dir = dirs[k]
			note.time = map.beats[b]
			note.section = idx
			chart.notes.append(note)

	chart.notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	return chart


## True if this beat (0-based) is in a rhythm-guide section.
func is_guide(beat: int) -> bool:
	return beat >= 0 and beat < _guide.size() and _guide[beat] == 1


## The section this beat (0-based) belongs to, or -1 if none.
func section_at(beat: int) -> int:
	return _section_of[beat] if beat >= 0 and beat < _section_of.size() else -1


## A short description of a section for the screen, e.g. "Step 3 · every 4 · level 3".
func describe(idx: int) -> String:
	if idx < 0:
		return "Between sections"
	var sec := sections[idx]
	if sec.get("guide", false):
		return "%s · rhythm guide" % sec["name"]
	var how := "every %d" % int(sec.get("every", 4))
	if sec.has("beats"):
		var list := PackedStringArray()
		for b: Variant in sec["beats"]:
			list.append(str(int(b)))
		how = "beats " + ", ".join(list)
	var pat := "pattern %s" % sec["pattern"] if sec.has("pattern") else "level %d" % int(sec.get("level", 2))
	return "%s · %s · %s" % [sec["name"], how, pat]


## Prints every section and its scratches to the Output panel.
func print_summary() -> void:
	print("Chart: %d scratches" % notes.size())
	for idx in sections.size():
		var seq := ""
		var count := 0
		var first := -1
		for note in notes:
			if note.section == idx:
				seq += "L" if note.dir == LEFT else "R"
				count += 1
				if first < 0:
					first = note.beat
		var sec := sections[idx]
		print("  %-10s beats %3d-%3d  %-28s %3d  %s" % [sec["name"], int(sec["from"]), int(sec["to"]), describe(idx).trim_prefix(str(sec["name"]) + " · "), count, seq])


static func _positions(sec: Dictionary, lo: int, hi: int, map: BeatMap) -> Array[int]:
	var out: Array[int] = []
	if sec.has("beats"):
		for b: Variant in sec["beats"]:
			var i := int(b) - 1
			if i >= lo and i <= hi:
				out.append(i)
			else:
				push_warning("Chart: beat %d in \"%s\" is outside the section, so it's skipped." % [int(b), sec["name"]])
		out.sort()
		return out

	var every := int(sec.get("every", 4))
	if every < 1:
		every = 1
	if every > 4 and every % 4 != 0:
		push_warning("Chart: \"every\" in \"%s\" should be 1, 2, 4 or a multiple of 4. Using %d." % [sec["name"], (every / 4) * 4])
		every = (every / 4) * 4

	var bars: Array[int] = []
	for b in map.bar_starts:
		if b >= lo and b <= hi:
			bars.append(b)
	if bars.is_empty():
		push_warning("Chart: section \"%s\" has no bar starts in it, so it gets no scratches." % sec["name"])
		return out

	if every >= 4:
		var step := every / 4
		for k in range(0, bars.size(), step):
			out.append(bars[k])
	else:
		for k in bars.size():
			var bar_end := hi + 1
			var next := map.bar_starts.find(bars[k]) + 1
			if next > 0 and next < map.bar_starts.size():
				bar_end = mini(bar_end, map.bar_starts[next])
			var i := bars[k]
			while i < bar_end:
				out.append(i)
				i += every
	return out


static func _directions(sec: Dictionary, count: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	if count == 0:
		return out
	if sec.has("pattern") and str(sec["pattern"]).length() > 0:
		var p := str(sec["pattern"]).to_upper()
		for k in count:
			out.append(LEFT if p[k % p.length()] == "L" else RIGHT)
		return out

	var level := clampi(int(sec.get("level", 2)), 1, 5)
	var d := LEFT if rng.randi() % 2 == 0 else RIGHT
	match level:
		1:
			while out.size() < count:
				# Runs of 2-4, but never more than half the section, so short sections still switch.
				var run := mini(rng.randi_range(2, 4), maxi(2, (count + 1) / 2))
				for k in run:
					out.append(d)
				d = -d
		2:
			for k in count:
				out.append(d if k % 2 == 0 else -d)
		3:
			for k in count:
				out.append(d if (k / 2) % 2 == 0 else -d)
		4:
			var motifs := ["LLR", "LRR", "RLL", "RRL", "LR", "RL"]
			var last := ""
			while out.size() < count:
				var m: String = motifs[rng.randi() % motifs.size()]
				if m == last or _run_after(out.slice(-3), m) > 2:
					continue
				last = m
				for ch in m:
					out.append(LEFT if ch == "L" else RIGHT)
		5:
			# Irregular: never 3 the same in a row, never more than 4 strictly alternating.
			for k in count:
				var options: Array[int] = []
				for c: int in [LEFT, RIGHT]:
					if _ok_irregular(out, c):
						options.append(c)
				out.append(options[rng.randi() % options.size()] if not options.is_empty() else -out[-1])
	out.resize(count)
	return out


static func _run_after(seq: Array[int], motif: String) -> int:
	var tail := seq.duplicate()
	for ch in motif:
		tail.append(LEFT if ch == "L" else RIGHT)
	var best := 1
	var run := 1
	for k in range(1, tail.size()):
		run = run + 1 if tail[k] == tail[k - 1] else 1
		best = maxi(best, run)
	return best


static func _ok_irregular(seq: Array[int], c: int) -> bool:
	var n := seq.size()
	if n >= 2 and seq[n - 1] == c and seq[n - 2] == c:
		return false
	if n >= 4 and seq[n - 1] != c and seq[n - 2] != seq[n - 1] and seq[n - 3] != seq[n - 2] and seq[n - 4] != seq[n - 3]:
		return false
	return true
