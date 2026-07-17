class_name MenuBackdrop
extends Control
## Valikoiden yhteinen animoitu tausta: pehmeä gradientti, hitaasti
## pyörivät hammasrattaat ja ylöspäin ajelehtivat hehkupisteet.

var team_glow := false   # lobby: joukkuevärien hehkut reunoille

var _time := 0.0
var _dots: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tausta piirtyy aina vanhemman oman piirron taakse (esim. Lobby piirtää
	# sisältönsä suoraan omaan _draw()-metodiinsa).
	show_behind_parent = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 715517
	for i in range(46):
		_dots.append({
			"x": rng.randf_range(0.0, 1920.0),
			"y": rng.randf_range(0.0, 1080.0),
			"speed": rng.randf_range(12.0, 46.0),
			"r": rng.randf_range(1.5, 4.5),
			"drift": rng.randf_range(-12.0, 12.0),
			"tint": rng.randf(),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920, 1080), Palette.BG_DARK)
	draw_circle(Vector2(960, 420), 760.0, Palette.with_alpha(Palette.BG_MID, 0.75))
	draw_circle(Vector2(960, 460), 480.0, Palette.with_alpha(Palette.BG_LIGHT, 0.4))
	draw_circle(Vector2(240, 940), 420.0, Palette.with_alpha(Palette.BG_MID, 0.5))
	draw_circle(Vector2(1700, 160), 380.0, Palette.with_alpha(Palette.BG_MID, 0.5))

	if team_glow:
		draw_circle(Vector2(220, 540), 470.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.06))
		draw_circle(Vector2(1700, 540), 470.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.06))

	_draw_gear(Vector2(180, 200), 150.0, _time * 0.12, 10)
	_draw_gear(Vector2(1760, 880), 190.0, -_time * 0.09, 12)
	_draw_gear(Vector2(1500, 300), 90.0, _time * 0.2, 8)

	for dot in _dots:
		var y: float = fmod(dot.y - _time * dot.speed, 1080.0)
		if y < 0.0:
			y += 1080.0
		var x: float = dot.x + sin(_time * 0.4 + dot.tint * TAU) * dot.drift
		var alpha: float = 0.12 + 0.1 * sin(_time * 1.5 + dot.tint * TAU)
		var color := Palette.TEAM_BLUE if dot.tint < 0.5 else Palette.GOLD
		draw_circle(Vector2(x, y), dot.r, Palette.with_alpha(color, alpha))


func _draw_gear(pos: Vector2, r: float, angle: float, teeth: int) -> void:
	var pts := PackedVector2Array()
	var steps := teeth * 4
	for i in range(steps):
		var a: float = angle + TAU * i / steps
		var phase := i % 4
		var rr: float = r if phase < 2 else r * 0.82
		pts.append(pos + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Palette.with_alpha(Palette.BG_LIGHT, 0.28))
	draw_circle(pos, r * 0.52, Palette.with_alpha(Palette.BG_DARK, 0.6))
	draw_circle(pos, r * 0.18, Palette.with_alpha(Palette.BG_LIGHT, 0.4))
