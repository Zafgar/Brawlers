class_name Results
extends Control
## Ottelun loppuruutu: voittaja, MVP ja koko tulostaulukko.
## MVP painottaa tavoitepeliä (40 %), ei pelkkiä tyrmäyksiä — myös tankki
## tai tukisankari voi olla ottelun paras.

var _mvp: PlayerProfile = null
var _mvp_reason := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	AudioMgr.play("match_win")

	_compute_mvp()
	_build_confetti()
	_build_layout()


# --- MVP-laskenta ---

func _compute_mvp() -> void:
	var components := {}
	for profile in Game.roster:
		var s: Dictionary = profile.stats
		components[profile] = {
			"obj": s.carry_time * 2.0 + s.pickups * 10.0 + s.carrier_stops * 20.0,
			"atk": s.damage + s.kos * 40.0 + s.assists * 20.0,
			"sup": s.healing + s.prevented,
			"def": s.prevented * 0.5 + s.saves * 25.0,
			"spec": (s.carrier_stops + s.saves + s.pickups) * 10.0,
		}
	var maxes := {"obj": 0.0, "atk": 0.0, "sup": 0.0, "def": 0.0, "spec": 0.0}
	for profile in components:
		for key in maxes:
			maxes[key] = maxf(maxes[key], components[profile][key])

	var best_score := -1.0
	for profile in Game.roster:
		var c: Dictionary = components[profile]
		var score := 0.0
		var weights := {"obj": 0.40, "atk": 0.20, "sup": 0.20, "def": 0.10, "spec": 0.10}
		for key in weights:
			if maxes[key] > 0.0:
				score += weights[key] * c[key] / maxes[key]
		if score > best_score:
			best_score = score
			_mvp = profile

	if _mvp != null:
		var s: Dictionary = _mvp.stats
		var parts: Array = []
		if s.carry_time >= 1.0:
			parts.append("reliikkiä %d s" % int(s.carry_time))
		if s.kos > 0:
			parts.append("%d tyrmäystä" % s.kos)
		if int(s.healing) > 0:
			parts.append("%d parannettu" % int(s.healing))
		if int(s.prevented) > 0:
			parts.append("%d estetty" % int(s.prevented))
		if parts.is_empty():
			parts.append("tasaista tekemistä kaikkialla")
		_mvp_reason = " · ".join(PackedStringArray(parts))


# --- Ulkoasu ---

func _build_confetti() -> void:
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(960, -20)
	confetti.amount = 70
	confetti.lifetime = 5.0
	confetti.preprocess = 1.5
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(960, 10)
	confetti.direction = Vector2.DOWN
	confetti.spread = 20.0
	confetti.gravity = Vector2(0, 140)
	confetti.initial_velocity_min = 60.0
	confetti.initial_velocity_max = 160.0
	confetti.angular_velocity_min = -180.0
	confetti.angular_velocity_max = 180.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 8.0
	confetti.color = Palette.glow(Game.team_color(Game.last_winner_team), 1.2)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Game.team_color(Game.last_winner_team), Palette.GOLD, Color(1, 1, 1, 0.0)])
	confetti.color_ramp = gradient
	add_child(confetti)


func _build_layout() -> void:
	var winner: int = Game.last_winner_team
	var box := UiKit.vbox(10)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(160, 40)
	box.size = Vector2(1600, 1000)
	add_child(box)

	var title := UiKit.title("%s VOITTAA!" % Game.team_name(winner), 84)
	title.add_theme_color_override("font_color", Palette.glow(Game.team_color(winner), 1.2))
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(title)

	var rounds := UiKit.label("Erät: sininen %d – %d oranssi" % [Game.blue_rounds, Game.orange_rounds],
		28, Palette.TEXT_DIM)
	rounds.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rounds)
	box.add_child(UiKit.spacer(6))

	# MVP-paneeli
	if _mvp != null:
		var mvp_panel := UiKit.panel()
		var mvp_style := StyleBoxFlat.new()
		mvp_style.bg_color = Palette.with_alpha(Palette.UI_PANEL_LIGHT, 0.95)
		mvp_style.border_color = Palette.GOLD
		mvp_style.set_border_width_all(3)
		mvp_style.set_corner_radius_all(18)
		mvp_style.content_margin_left = 40.0
		mvp_style.content_margin_right = 40.0
		mvp_style.content_margin_top = 14.0
		mvp_style.content_margin_bottom = 14.0
		mvp_panel.add_theme_stylebox_override("panel", mvp_style)
		mvp_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var mvp_box := UiKit.vbox(2)
		mvp_panel.add_child(mvp_box)
		var mvp_title := UiKit.label("OTTELUN MVP", 20, Palette.GOLD)
		mvp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mvp_box.add_child(mvp_title)
		var mvp_name := UiKit.label("%s — %s" % [_mvp.display_name, _mvp.hero_name()], 36,
			Palette.TEXT_MAIN)
		mvp_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mvp_box.add_child(mvp_name)
		var mvp_stats := UiKit.dim_label(_mvp_reason, 20)
		mvp_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mvp_box.add_child(mvp_stats)
		box.add_child(mvp_panel)

	box.add_child(UiKit.spacer(10))

	# Tulostaulukko
	var table_panel := UiKit.panel()
	table_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(table_panel)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	table_panel.add_child(grid)

	for header in ["Pelaaja", "Sankari", "Pisteet", "Tyrmäykset", "Avustukset",
			"Kanto (s)", "Vahinko", "Parannettu", "Estetty"]:
		var head := UiKit.label(header, 18, Palette.TEXT_DIM)
		grid.add_child(head)

	var sorted_roster: Array = Game.roster.duplicate()
	sorted_roster.sort_custom(func(a, b): return a.stats.score > b.stats.score)

	var delay := 0.0
	for profile in sorted_roster:
		var row_color: Color = Palette.TEXT_MAIN if profile.is_human() \
			else Palette.with_alpha(Palette.TEXT_MAIN, 0.6)
		var name_row := UiKit.hbox(8)
		var dot := ColorDot.new()
		dot.color = profile.color() if profile.is_human() \
			else Palette.with_alpha(Palette.team(profile.team), 0.6)
		dot.custom_minimum_size = Vector2(18, 18)
		name_row.add_child(dot)
		var name_text := profile.display_name
		if profile == _mvp:
			name_text += "  ★MVP"
		name_row.add_child(UiKit.label(name_text, 20,
			Palette.GOLD if profile == _mvp else row_color))
		grid.add_child(name_row)

		var s: Dictionary = profile.stats
		var cells := [
			profile.hero_name(),
			str(int(s.score)),
			str(s.kos),
			str(s.assists),
			str(int(s.carry_time)),
			str(int(s.damage)),
			str(int(s.healing)),
			str(int(s.prevented)),
		]
		var row_nodes: Array = [name_row]
		for cell in cells:
			var cell_label := UiKit.label(cell, 20, row_color)
			grid.add_child(cell_label)
			row_nodes.append(cell_label)

		# Rivien pehmeä sisääntulo
		for node in row_nodes:
			node.modulate = Color(1, 1, 1, 0)
			var tween := node.create_tween()
			tween.tween_interval(0.15 + delay)
			tween.tween_property(node, "modulate:a", 1.0, 0.3)
		delay += 0.08

	box.add_child(UiKit.spacer(12))

	var buttons := UiKit.hbox(20)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(buttons)
	var rematch_btn := UiKit.button("Uusinta", func(): Game.rematch())
	rematch_btn.custom_minimum_size = Vector2(300, 0)
	buttons.add_child(rematch_btn)
	var menu_btn := UiKit.button("Päävalikkoon", func(): Game.go_menu())
	menu_btn.custom_minimum_size = Vector2(300, 0)
	buttons.add_child(menu_btn)
	rematch_btn.call_deferred("grab_focus")


## Pieni pyöreä värimerkki tulostaulukkoon.
class ColorDot:
	extends Control

	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(size / 2.0, minf(size.x, size.y) / 2.0, color)
