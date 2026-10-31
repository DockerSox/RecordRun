class_name Groove
extends Node2D
## Draws the record groove in faked 3D, the needle (the player) and the scratches, all in code.
##
## The record is a flat disc turning at a constant speed, so distance along the groove is song time:
## a scratch sits at its beat's time and reaches the needle exactly on that beat.
## The groove is a circle around the record's centre (off to the right), so it bends steadily,
## and scratches further ahead appear around the bend about view_ahead seconds before their beat.
## The record's rim and the turntable beyond it show near the top of the screen.
## Floor marks: four per beat from the beat map (bar starts strongest), so every scratch sits on a beat mark.
##
## Everything is drawn back to front (painter's method), so nearer walls hide what is behind them.
## World units: sideways and up are in pixels as seen at the needle; forward is seconds of song.

@export_group("View")
## How many seconds of song are visible ahead of the needle. About 8 beats at the main tempo.
@export_range(1.0, 8.0, 0.1, "suffix:s") var view_ahead: float = 3.4
## Where the horizon sits, as a fraction of the screen height from the top.
@export_range(0.05, 0.6, 0.01) var horizon: float = 0.26
## Where the needle sits, as a fraction of the screen height from the top.
## Kept above the bottom quarter of a portrait phone, where the player's thumbs rest.
@export_range(0.5, 0.95, 0.01) var needle_height: float = 0.74
## How far behind the needle the eye is, in seconds of groove. Smaller = stronger perspective.
@export_range(0.1, 2.0, 0.05, "suffix:s") var eye_distance: float = 0.8
## How many slices the groove is drawn in. Fewer is faster on old phones.
@export_range(16, 160, 1) var slices: int = 64

@export_group("Shape")
## How sharply the groove bends to the right. Scaled to the screen, so it looks the same on any device.
@export_range(0.0, 400.0, 1.0) var curve: float = 110.0
## Half the width of the groove floor, as a fraction of the screen's shorter side.
@export_range(0.02, 0.4, 0.005) var floor_half_width: float = 0.12
## How far each wall reaches sideways, as a fraction of the screen's shorter side.
@export_range(0.02, 0.6, 0.005) var wall_width: float = 0.11
## Wall height compared with the eye's height above the floor. Higher walls hide more.
@export_range(0.1, 0.95, 0.01) var wall_height: float = 0.7

@export_group("Scratches")
## How far ahead (in seconds) a scratch reaches the top of the wall.
@export_range(0.02, 1.0, 0.01, "suffix:s") var scratch_lead: float = 0.22
## Thickness of a scratch, in seconds of groove.
@export_range(0.005, 0.2, 0.005, "suffix:s") var scratch_thickness: float = 0.035
## 0 = the scratch crosses the floor square, parallel to the beat marks. 1 = leaning ahead.
@export_range(0.0, 1.0, 0.05) var scratch_floor_lean: float = 0.0

@export_group("Record")
## How far ahead (seconds) the record's rim crosses the view, straight ahead of the needle.
@export_range(1.0, 10.0, 0.1, "suffix:s") var rim_ahead: float = 2.4
## Radius of the groove the needle is in, in screen widths. Sets how the bend becomes a circle.
@export_range(2.0, 30.0, 0.5) var groove_radius: float = 6.0
## Floor marks: 0 = a plain line every quarter second, 1 = four per beat from the beat map.
@export_range(0, 1) var floor_marks: int = 1

@export_group("Colours")
@export var col_space: Color = Color("0c0d11")
@export var col_surface: Color = Color("1b1e25")
@export var col_ridge: Color = Color("4a5160")
@export var col_wall_lit: Color = Color("2c313b")
@export var col_wall_shade: Color = Color("20242c")
@export var col_floor: Color = Color("15171c")
@export var col_line: Color = Color("2f3540")
@export var col_scratch: Color = Color("eef3fb")
@export var col_guide: Color = Color("8fa9ff")
@export var col_needle: Color = Color("f2b24c")
@export var col_mistake: Color = Color("ff6b5e")
## The turntable platter beyond the record's rim. Set it the same as Space to hide it.
@export var col_platter: Color = Color("262a31")

var conductor: Conductor
var chart: Chart

var _w: float
var _h: float
var _cx: float
var _hy: float
var _eye_h: float
var _hw: float
var _ww: float
var _wh: float
var _bend: float
var _marks: PackedFloat64Array = PackedFloat64Array()
var _mark_level: PackedByteArray = PackedByteArray()   # 0 between beats, 1 beat, 2 bar start
var _t_far: float = 4.0
var _rg: float
var _u: float
var _re: float
var _now: float = 0.0
var _last_now: float = 0.0
var _next_note: int = 0
var _hit_flash: float = 0.0
var _hit_dir: int = 0
var _pulse: float = 0.0
var _miss_flash: float = 0.0
var _popup: String = ""
var _popup_col: Color = Color.WHITE
var _popup_t: float = 0.0


## Called by the game after each judgement: flashes the needle and shows the result above it.
func show_result(result: int, dir: int) -> void:
	_popup = Judge.NAMES[result]
	_popup_t = 1.0
	if result == Judge.Result.HIT:
		_hit_flash = 1.0
		_hit_dir = dir
		_popup_col = col_scratch
	else:
		_miss_flash = 1.0
		_popup_col = col_mistake


## Called by the game on every beat; pulses the needle during rhythm-guide sections.
func on_beat(beat_index: int) -> void:
	if chart != null and chart.is_guide(beat_index):
		_pulse = 1.0


func _process(delta: float) -> void:
	_now = conductor.song_time if conductor != null else 0.0
	if _now < _last_now - 0.25:   # the song restarted
		_next_note = 0
	_last_now = _now
	if chart != null:
		while _next_note < chart.notes.size() and chart.notes[_next_note].time <= _now:
			_next_note += 1
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
	_miss_flash = maxf(0.0, _miss_flash - delta * 3.0)
	_popup_t = maxf(0.0, _popup_t - delta * 1.6)
	_pulse = maxf(0.0, _pulse - delta * 3.5)
	queue_redraw()


# ---------- projection ----------

## The groove is a circle around the record's centre, which lies off to the right.
## _u converts seconds ahead into pixels, chosen so the bend matches the "curve" setting near the needle.
func _centre(t: float) -> float:
	var z := _u * t
	return _rg - sqrt(maxf(_rg * _rg - z * z, 0.0))


## Sideways position (relative to the groove) of the record's rim on the left, or INF past the record.
func _rim_left(t: float) -> float:
	var z := _u * t
	var r2 := _re * _re - z * z
	return INF if r2 <= 0.0 else _rg - sqrt(r2) - _centre(t)


func _rim_right(t: float) -> float:
	var z := _u * t
	var r2 := _re * _re - z * z
	return -INF if r2 <= 0.0 else _rg + sqrt(r2) - _centre(t)


## World point (sideways x, height y, t seconds ahead) to screen.
func _p(x: float, y: float, t: float) -> Vector2:
	var s := eye_distance / (eye_distance + t)
	return Vector2(_cx + (x + _centre(t)) * s, _hy + (_eye_h - y) * s)


func _fog(c: Color, t: float) -> Color:
	var f := smoothstep(view_ahead * 0.5, _t_far, t) * 0.8
	return c.lerp(col_space, f)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	# draw_primitive draws four corners directly, which is faster than a polygon and never fails on thin shapes.
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([col, col, col, col]), PackedVector2Array())


# ---------- drawing ----------

func _draw() -> void:
	var size := get_viewport_rect().size
	_w = size.x
	_h = size.y
	_cx = _w * 0.5
	_hy = _h * horizon
	_eye_h = _h * needle_height - _hy
	var base := minf(_w, _h)
	_hw = base * floor_half_width
	_ww = base * wall_width
	_wh = _eye_h * wall_height
	_bend = curve * base / 648.0   # the same bend on any screen size
	_rg = groove_radius * base
	_u = sqrt(_bend * _rg)
	_re = sqrt(_rg * _rg + pow(_u * rim_ahead, 2.0))
	_t_far = maxf(view_ahead, rim_ahead) * 1.25
	var t_exit := _t_far
	while t_exit < 60.0 and _p(-(_hw + _ww), _wh, t_exit).x < _w + 4.0:
		t_exit += 0.1
	_t_far = maxf(_t_far, t_exit)
	if _marks.is_empty():
		_build_marks()

	draw_rect(Rect2(Vector2.ZERO, size), col_space)
	# The turntable platter, a little below the record surface, visible past the rim.
	if _wh < _eye_h:
		var big := _w * 6.0
		var ph := _wh - _eye_h * 0.08
		var pc := col_platter.lerp(col_space, 0.35)
		_quad(_p(-big, ph, _t_far * 3.0), _p(big, ph, _t_far * 3.0), _p(big, ph, 0.0), _p(-big, ph, 0.0), pc)

	# Slices are spaced evenly on screen rather than in time, so near and far look equally smooth.
	var s_far := eye_distance / (eye_distance + _t_far)
	var s_near := (_h - _hy) / maxf(_eye_h - _wh, 1.0) * 1.05   # until the ridge tops pass the bottom edge
	var t_prev := eye_distance / s_far - eye_distance
	var scratch_list := _visible_scratches()
	var guide_list := _visible_guide_beats()
	var ticks_from := floorf(_now / 0.25) * 0.25

	for i in range(1, slices + 1):
		var s := lerpf(s_far, s_near, float(i) / slices)
		var ta := t_prev                                # far edge of this band
		var tb := eye_distance / s - eye_distance       # near edge
		t_prev = tb
		_draw_band(ta, tb)

		if floor_marks == 0 or _marks.is_empty():
			# Record texture: a fine line across the floor every quarter second of song, so the record visibly turns.
			var tick := ticks_from + ceilf((_now + tb - ticks_from) / 0.25) * 0.25
			while tick - _now <= ta:
				var t := tick - _now
				draw_line(_p(-_hw, 0, t), _p(_hw, 0, t), _fog(col_line, t), 1.0)
				tick += 0.25
		else:
			_draw_marks(ta, tb)

		for g: float in guide_list:
			var t := g - _now
			if t <= ta and t > tb:
				var c := _fog(col_guide, t)
				_quad(_p(-_hw, 0, t - 0.02), _p(_hw, 0, t - 0.02), _p(_hw, 0, t + 0.02), _p(-_hw, 0, t + 0.02), c)

		for note: Chart.Note in scratch_list:
			var t := note.time - _now - scratch_thickness
			if t <= ta and t > tb and note.result != Judge.Result.HIT:   # hit scratches vanish
				_draw_scratch(note.time - _now, note.dir, Judge.is_mistake(note.result))

	_draw_needle()


## Four marks per beat from the beat map: the beat itself, then three evenly between it and the next beat.
## Untapped stretches (gaps much longer than the beats around them) get only the beat mark.
func _build_marks() -> void:
	if conductor == null or conductor.beat_map == null:
		return
	var map := conductor.beat_map
	var b := map.beats
	for i in b.size():
		_marks.append(b[i])
		_mark_level.append(2 if map.is_bar_start(i) else 1)
		if i + 1 >= b.size():
			break
		var gap: float = b[i + 1] - b[i]
		var near: Array[float] = []
		for j in range(maxi(1, i - 4), mini(b.size(), i + 6)):
			if j != i + 1:
				near.append(b[j] - b[j - 1])
		near.sort()
		var typical := near[near.size() >> 1] if not near.is_empty() else gap
		if gap > typical * 1.6:
			continue
		for k in range(1, 4):
			_marks.append(b[i] + gap * k / 4.0)
			_mark_level.append(0)


func _draw_marks(ta: float, tb: float) -> void:
	var lo := _now + tb
	var hi := _now + ta
	var i := _marks.bsearch(lo)
	while i < _marks.size() and _marks[i] <= hi:
		var t := _marks[i] - _now
		var lvl := _mark_level[i]
		# Bar starts strongest, beats clear, the three marks between beats faint.
		var c: Color = [Color(col_line, 0.8), col_line.lightened(0.3), col_ridge.lightened(0.25)][lvl]
		var width: float = [1.0, 2.0, 3.0][lvl]
		draw_line(_p(-_hw, 0, t), _p(_hw, 0, t), _fog(c, t), width)
		i += 1


func _draw_band(ta: float, tb: float) -> void:
	var far_edge := _w * 4.0
	var hw := _hw
	var rw := _hw + _ww

	# The record surface either side of the groove, at ridge height. It hides the groove behind the bend.
	var eye_above_ridge := _wh < _eye_h
	var surf := _fog(col_surface, tb)
	var la := clampf(_rim_left(ta), -far_edge, -rw)
	var lb := clampf(_rim_left(tb), -far_edge, -rw)
	var ra := clampf(_rim_right(ta), rw, far_edge)
	var rb := clampf(_rim_right(tb), rw, far_edge)
	if eye_above_ridge:
		_quad(_p(la, _wh, ta), _p(-rw, _wh, ta), _p(-rw, _wh, tb), _p(lb, _wh, tb), surf)
		_quad(_p(rw, _wh, ta), _p(ra, _wh, ta), _p(rb, _wh, tb), _p(rw, _wh, tb), surf)
		# The rim: the record's outer edge, catching the light.
		if la > -far_edge and lb > -far_edge and la < -rw:
			draw_line(_p(la, _wh, ta), _p(lb, _wh, tb), _fog(col_ridge.lightened(0.35), tb), 2.0)
	# Neighbouring grooves on the record surface, as faint lines.
	for k in range(1, 6 if eye_above_ridge else 1):
		var off := rw + k * (rw * 1.15)
		var lc := _fog(col_line, tb)
		if -off > la and -off > lb:
			draw_line(_p(-off, _wh, ta), _p(-off, _wh, tb), lc, 1.0)
		if off < ra and off < rb:
			draw_line(_p(off, _wh, ta), _p(off, _wh, tb), lc, 1.0)

	# The two sloping walls of the V-shaped groove, lit from the left.
	_quad(_p(-rw, _wh, ta), _p(-hw, 0, ta), _p(-hw, 0, tb), _p(-rw, _wh, tb), _fog(col_wall_lit, tb))
	_quad(_p(hw, 0, ta), _p(rw, _wh, ta), _p(rw, _wh, tb), _p(hw, 0, tb), _fog(col_wall_shade, tb))
	# The floor.
	_quad(_p(-hw, 0, ta), _p(hw, 0, ta), _p(hw, 0, tb), _p(-hw, 0, tb), _fog(col_floor, tb))
	# Ridge tops catch the light.
	var rc := _fog(col_ridge, tb)
	draw_line(_p(-rw, _wh, ta), _p(-rw, _wh, tb), rc, 2.0)
	draw_line(_p(rw, _wh, ta), _p(rw, _wh, tb), rc, 2.0)


## A scratch starts at the middle of the floor at its beat and cuts across the floor and up the wall
## on its side (left or right), leaning slightly ahead, like a gouge leading out of the groove.
func _draw_scratch(t: float, dir: int, failed: bool) -> void:
	var th := scratch_thickness
	var side := float(dir)
	var t_edge := t + scratch_lead * 0.6 * scratch_floor_lean
	var t_top := t + scratch_lead
	var c := _fog(col_mistake if failed else col_scratch, maxf(t, 0.0))
	c.a = smoothstep(view_ahead, view_ahead * 0.85, t)   # scratches appear about view_ahead seconds early
	if t < 0.0:
		c.a = clampf(1.0 + t * 4.0, 0.0, 1.0)   # fades out just after passing the needle
	# Across the floor...
	_quad(_p(0, 0, t + th), _p(side * _hw, 0, t_edge + th), _p(side * _hw, 0, t_edge - th), _p(0, 0, t - th), c)
	# ...and up the wall.
	_quad(_p(side * _hw, 0, t_edge + th), _p(side * (_hw + _ww), _wh, t_top + th), _p(side * (_hw + _ww), _wh, t_top - th), _p(side * _hw, 0, t_edge - th), c)


func _draw_needle() -> void:
	var tip := _p(0, 0, 0)
	var base := minf(_w, _h)
	var hw := base * 0.022
	var tall := base * 0.10
	# Shadow on the floor.
	draw_circle(tip + Vector2(0, base * 0.006), hw * 1.3, Color(0, 0, 0, 0.45))
	# Rhythm-guide pulse and hit flash.
	if _pulse > 0.0:
		draw_arc(tip, hw * (1.6 + (1.0 - _pulse) * 2.5), 0.0, TAU, 32, Color(col_guide, _pulse), 3.0)
	if _miss_flash > 0.0:
		draw_arc(tip, hw * (1.4 + (1.0 - _miss_flash) * 1.5), 0.0, TAU, 32, Color(col_mistake, _miss_flash), 4.0)
	if _popup_t > 0.0:
		var font := ThemeDB.fallback_font
		var size := int(base * 0.055)
		var rise := (1.0 - _popup_t) * base * 0.06
		var pos := tip + Vector2(-base * 0.3, -tall * 1.6 - rise)
		draw_string(font, pos, _popup, HORIZONTAL_ALIGNMENT_CENTER, base * 0.6, size, Color(_popup_col, minf(1.0, _popup_t * 2.0)))
	if _hit_flash > 0.0:
		var c := Color(col_scratch, _hit_flash)
		draw_arc(tip, hw * (1.4 + (1.0 - _hit_flash) * 3.0), 0.0, TAU, 32, c, 3.0)
		var spark := tip + Vector2(_hit_dir * hw * (2.0 + (1.0 - _hit_flash) * 4.0), -hw * 0.6)
		draw_circle(spark, hw * 0.45 * _hit_flash + 1.0, c)
	# No tonearm for now: just the headshell and the stylus.
	var head := tip + Vector2(hw * 0.4, -tall * 0.55)
	# Headshell (the cartridge body).
	_quad(head + Vector2(-hw * 1.4, -hw * 0.9), head + Vector2(hw * 1.8, -hw * 0.6), head + Vector2(hw * 1.8, hw * 0.9), head + Vector2(-hw * 1.4, hw * 0.6), col_needle.darkened(0.2))
	# The stylus: a narrow cone with its tip in the groove.
	draw_colored_polygon(PackedVector2Array([tip, head + Vector2(-hw * 0.7, hw * 0.6), head + Vector2(hw * 0.7, hw * 0.75)]), col_needle)


func _visible_scratches() -> Array[Chart.Note]:
	var out: Array[Chart.Note] = []
	if chart == null:
		return out
	for k in range(maxi(0, _next_note - 4), chart.notes.size()):
		var t := chart.notes[k].time - _now
		if t > view_ahead * 1.05:
			break
		if t > -0.3:
			out.append(chart.notes[k])
	return out


func _visible_guide_beats() -> Array[float]:
	var out: Array[float] = []
	if chart == null or conductor == null or conductor.beat_map == null:
		return out
	var beats := conductor.beat_map.beats
	for b in beats.size():
		var t := beats[b] - _now
		if t > view_ahead * 1.05:
			break
		if t > -0.1 and chart.is_guide(b):
			out.append(beats[b])
	return out
