class_name HudLayer
extends CanvasLayer
## Ottelun HUD: pelaajakortit ylä- ja alareunassa, tulospaneeli keskellä
## ylhäällä, bannerit, laskurit ja tyrmäyssyöte.

const CARD_SLOT := 240.0

var arena = null

var _root: Control = null
var _score_panel: Control = null
var _feed_box: VBoxContainer = null


func setup(p_arena) -> void:
	arena = p_arena
	layer = 10

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Pelaajakortit: sininen ylös, oranssi alas. Enintään kolme korttia
	# rivissä, jotta ne eivät osu keskellä olevaan tulospaneeliin.
	var counts := [0, 0]
	for profile in Game.roster:
		var card := PlayerCard.new()
		card.setup(arena, profile)
		var slot: int = counts[profile.team]
		counts[profile.team] += 1
		var x := 16.0 + (slot % 3) * CARD_SLOT
		var row_offset := (slot / 3) * 130.0
		if profile.team == 0:
			card.position = Vector2(x, 14.0 + row_offset)
		else:
			card.position = Vector2(x, 1080.0 - card.size.y - 14.0 - row_offset)
		_root.add_child(card)

	_score_panel = ScorePanel.new()
	_score_panel.arena = arena
	_score_panel.position = Vector2(960.0 - 300.0, 10.0)
	_score_panel.size = Vector2(600.0, 96.0)
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_score_panel)

	_feed_box = UiKit.vbox(4)
	_feed_box.position = Vector2(1920.0 - 420.0, 120.0)
	_feed_box.size = Vector2(400.0, 300.0)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed_box)


## Iso banneri ruudun yläkolmanteen: "ERÄ 1", "SININEN VOITTAA ERÄN!" jne.
func show_banner(big: String, small := "", dur := 2.0) -> void:
	var box := UiKit.vbox(6)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(960.0 - 600.0, 250.0)
	box.size = Vector2(1200.0, 200.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var big_label := UiKit.title(big, 68)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big_label)
	if small != "":
		var small_label := UiKit.label(small, 26, Palette.TEXT_DIM)
		small_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(small_label)
	_root.add_child(box)

	box.modulate = Color(1, 1, 1, 0)
	box.scale = Vector2(1.12, 1.12)
	box.pivot_offset = Vector2(600.0, 60.0)
	var tween := box.create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "modulate:a", 1.0, 0.18)
	tween.tween_property(box, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(maxf(dur - 0.5, 0.1))
	tween.chain().tween_property(box, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(box.queue_free)


## Valtava keskinumero: lähtölaskenta ja "PELIIN!".
func show_big_number(text: String) -> void:
	var label := UiKit.title(text, 150)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(960.0 - 500.0, 400.0)
	label.size = Vector2(1000.0, 220.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.pivot_offset = Vector2(500.0, 110.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)

	label.scale = Vector2(1.5, 1.5)
	label.modulate = Color(1, 1, 1, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.25)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(label.queue_free)


## Pieni tapahtumarivi oikeaan yläkulmaan.
func ko_feed(text: String) -> void:
	if _feed_box.get_child_count() >= 4:
		_feed_box.get_child(_feed_box.get_child_count() - 1).queue_free()
	var label := UiKit.label(text, 18, Palette.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_box.add_child(label)
	_feed_box.move_child(label, 0)
	var tween := label.create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


## Tulospaneeli: reliikkipisteet, aika, erävoitot ja reliikin tila.
class ScorePanel:
	extends Control

	var arena = null
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if arena == null:
			return
		var w := size.x
		var bg := StyleBoxFlat.new()
		bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.85)
		bg.set_corner_radius_all(16)
		bg.border_color = Palette.UI_STROKE
		bg.set_border_width_all(2)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		var target: float = arena.score_target
		var blue_frac: float = clampf(arena.team_points(0) / target, 0.0, 1.0)
		var orange_frac: float = clampf(arena.team_points(1) / target, 0.0, 1.0)

		# Reliikkipistepalkit: sininen vasemmalta, oranssi oikealta.
		var bar_y := 16.0
		var bar_h := 20.0
		var bar_half := w / 2.0 - 74.0
		draw_rect(Rect2(12, bar_y, bar_half, bar_h), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(w - 12 - bar_half, bar_y, bar_half, bar_h), Color(0, 0, 0, 0.5))
		var blue_color := Palette.TEAM_BLUE
		var orange_color := Palette.TEAM_ORANGE
		var holder: int = arena.holder_team()
		if holder == 0:
			blue_color = Palette.glow(Palette.TEAM_BLUE, 1.3 + 0.2 * sin(_time * 8.0))
		elif holder == 1:
			orange_color = Palette.glow(Palette.TEAM_ORANGE, 1.3 + 0.2 * sin(_time * 8.0))
		draw_rect(Rect2(12, bar_y, bar_half * blue_frac, bar_h), blue_color)
		draw_rect(Rect2(w - 12 - bar_half * orange_frac, bar_y, bar_half * orange_frac, bar_h),
			orange_color)
		UiKit.draw_text(self, Vector2(12 + 30, bar_y + bar_h / 2.0),
			str(int(arena.team_points(0))), 16, Palette.TEXT_MAIN, true, 3)
		UiKit.draw_text(self, Vector2(w - 12 - 30, bar_y + bar_h / 2.0),
			str(int(arena.team_points(1))), 16, Palette.TEXT_MAIN, true, 3)

		# Aika tai äkkikuolema
		if arena.sudden_death:
			var blink_alpha := 0.6 + 0.4 * sin(_time * 7.0)
			UiKit.draw_text(self, Vector2(w / 2.0, bar_y + 10.0), "RATKAISU!",
				24, Palette.with_alpha(Palette.GOLD, blink_alpha), true, 4)
		else:
			var secs := int(maxf(arena.time_left, 0.0))
			var text := "%d:%02d" % [secs / 60, secs % 60]
			var time_color := Palette.TEXT_MAIN
			if secs <= 30:
				time_color = Palette.with_alpha(Palette.BAD, 0.7 + 0.3 * sin(_time * 5.0))
			UiKit.draw_text(self, Vector2(w / 2.0, bar_y + 10.0), text, 30, time_color, true, 4)

		# Erävoittopisteet
		var pip_y := 62.0
		var wins_needed: int = Game.rounds_to_win
		for i in range(wins_needed):
			var blue_pip := Vector2(w / 2.0 - 40.0 - i * 22.0, pip_y)
			var filled_blue: bool = Game.blue_rounds > i
			draw_circle(blue_pip, 8.0, Palette.TEAM_BLUE if filled_blue else Color(0, 0, 0, 0.5))
			draw_arc(blue_pip, 8.0, 0.0, TAU, 20, Palette.with_alpha(Palette.TEAM_BLUE, 0.7), 1.5)
			var orange_pip := Vector2(w / 2.0 + 40.0 + i * 22.0, pip_y)
			var filled_orange: bool = Game.orange_rounds > i
			draw_circle(orange_pip, 8.0, Palette.TEAM_ORANGE if filled_orange else Color(0, 0, 0, 0.5))
			draw_arc(orange_pip, 8.0, 0.0, TAU, 20, Palette.with_alpha(Palette.TEAM_ORANGE, 0.7), 1.5)

		# Reliikin tila pieni timantti keskellä pippujen välissä
		var gem_center := Vector2(w / 2.0, pip_y)
		var gem_color := Palette.glow(Palette.GOLD, 1.5)
		var gem_holder: int = arena.holder_team()
		if gem_holder >= 0:
			gem_color = Palette.glow(Palette.team(gem_holder), 1.5)
		var pulse := 1.0 + 0.1 * sin(_time * 5.0)
		var gem := PackedVector2Array([
			gem_center + Vector2(0, -10) * pulse, gem_center + Vector2(8, 0) * pulse,
			gem_center + Vector2(0, 10) * pulse, gem_center + Vector2(-8, 0) * pulse])
		draw_colored_polygon(gem, gem_color)
