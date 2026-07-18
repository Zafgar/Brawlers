class_name Results
extends Control
## Ottelun loppuruutu: voittaja, MVP-nosto ja tulostaulukko.
## MVP painottaa tavoitepeliä (40 %) — myös tankki tai tuki voi olla paras.
## Piirretään kokonaan koodilla (napit ovat lapsisolmuja).

const ROW_H := 44.0

var _mvp: PlayerProfile = null
var _mvp_reason := ""
var _sorted: Array = []
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	AudioMgr.play_music("menu")
	AudioMgr.play("match_win")

	_compute_mvp()
	_sorted = Game.roster.duplicate()
	_sorted.sort_custom(func(a, b): return a.stats.score > b.stats.score)
	_build_confetti()
	_build_buttons()


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


func _build_confetti() -> void:
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(960, -20)
	confetti.amount = 80
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


func _build_buttons() -> void:
	var buttons := UiKit.hbox(24)
	buttons.position = Vector2(960 - 312.0, 902.0)
	add_child(buttons)
	var rematch_btn := UiKit.button("Uusinta", func(): Game.rematch())
	rematch_btn.custom_minimum_size = Vector2(300, 58)
	buttons.add_child(rematch_btn)
	var menu_btn := UiKit.button("Päävalikkoon", func(): Game.go_menu())
	menu_btn.custom_minimum_size = Vector2(300, 58)
	buttons.add_child(menu_btn)
	rematch_btn.call_deferred("grab_focus")


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# --- Piirto ---

func _card(rect: Rect2, bg: Color, border: Color, bw: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	sb.draw(get_canvas_item(), rect)


func _draw() -> void:
	var winner: int = Game.last_winner_team
	var wc: Color = Game.team_color(winner)

	# Voittajahehku otsikon taakse
	var pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(Vector2(960, 110), 380.0, Palette.with_alpha(wc, 0.06 + pulse * 0.03))
	for i in range(8):
		var ang := _time * 0.2 + TAU * i / 8.0
		draw_line(Vector2(960, 110), Vector2(960, 110) + Vector2(cos(ang), sin(ang)) * 320.0,
			Palette.with_alpha(wc, 0.03), 3.0)

	UiKit.draw_text(self, Vector2(960, 100), "%s VOITTAA!" % Game.team_name(winner), 80,
		Palette.glow(wc, 1.2), true, 9)
	UiKit.draw_text(self, Vector2(960, 168),
		"Erät:  sininen %d – %d oranssi" % [Game.blue_rounds, Game.orange_rounds], 26,
		Palette.TEXT_DIM, true)

	_draw_mvp_card(214.0)
	_draw_table(408.0)


func _draw_mvp_card(y: float) -> void:
	if _mvp == null:
		return
	var rect := Rect2(510, y, 900, 150)
	var glow_pulse := 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(rect.get_center(), 400.0, Palette.with_alpha(Palette.GOLD, 0.03))
	_card(rect, Palette.with_alpha(Palette.UI_PANEL_LIGHT, 0.95),
		Palette.glow(Palette.GOLD, 1.0 + glow_pulse * 0.3), 3, 20)

	# Medaljonki + kruunu
	var def := HeroDef.get_def(_mvp.hero_id)
	var c1: Color = def["color"]
	var c2: Color = def["color_b"]
	var med := Vector2(rect.position.x + 90.0, rect.get_center().y + 6.0)
	draw_arc(med, 62.0, _time, _time + TAU * 0.85, 28, Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4), 0.6), 3.0)
	draw_circle(med, 55.0, Palette.darker(c2, 0.55))
	draw_circle(med, 50.0, c1)
	draw_circle(med + Vector2(0, 18), 34.0, Palette.with_alpha(c2, 0.35))
	HeroIcon.draw_symbol(self, _mvp.hero_id, med, 32.0)
	_draw_crown(med + Vector2(0, -66.0))

	# Teksti
	var tx := rect.position.x + 180.0
	UiKit.draw_text(self, Vector2(tx, y + 34.0), "OTTELUN MVP", 20, Palette.GOLD, false, 3)
	UiKit.draw_text(self, Vector2(tx, y + 74.0), "%s — %s" % [_mvp.display_name, _mvp.hero_name()],
		36, Palette.TEXT_MAIN, false, 4)
	UiKit.draw_text(self, Vector2(tx, y + 116.0), _mvp_reason, 20, Palette.TEXT_DIM, false)


func _draw_crown(pos: Vector2) -> void:
	var crown := PackedVector2Array([
		pos + Vector2(-16, 8), pos + Vector2(-16, -8), pos + Vector2(-8, -2),
		pos + Vector2(0, -12), pos + Vector2(8, -2), pos + Vector2(16, -8),
		pos + Vector2(16, 8)])
	draw_colored_polygon(crown, Palette.glow(Palette.GOLD, 1.5))
	for dx in [-16.0, 0.0, 16.0]:
		draw_circle(pos + Vector2(dx, -10), 3.0, Palette.glow(Color("fff2c0"), 1.4))


# Sarakkeet: [avain, leveys, otsikko, keskitetty]
func _columns() -> Array:
	return [
		["name", 360.0, "Pelaaja", false],
		["hero", 170.0, "Sankari", false],
		["score", 120.0, "Pisteet", true],
		["kos", 120.0, "Tyrmäykset", true],
		["assists", 130.0, "Avustukset", true],
		["carry", 120.0, "Kanto s", true],
		["damage", 120.0, "Vahinko", true],
		["healing", 130.0, "Parannettu", true],
		["prevented", 110.0, "Estetty", true],
	]


func _draw_table(y0: float) -> void:
	var cols := _columns()
	var total := 0.0
	for col in cols:
		total += col[1]
	var tx0 := 960.0 - total / 2.0

	# Otsikkorivi
	var cx := tx0
	for col in cols:
		var w: float = col[1]
		var label: String = col[2]
		var centered: bool = col[3]
		var px := cx + (w / 2.0 if centered else 12.0)
		UiKit.draw_text(self, Vector2(px, y0), label, 16, Palette.TEXT_DIM, centered)
		cx += w
	draw_line(Vector2(tx0, y0 + 18.0), Vector2(tx0 + total, y0 + 18.0),
		Palette.with_alpha(Palette.UI_STROKE, 0.4), 2.0)

	# Datarivit
	for r in range(_sorted.size()):
		var profile: PlayerProfile = _sorted[r]
		var ry := y0 + 34.0 + r * ROW_H
		var row_alpha: float = clampf((_time - (0.15 + r * 0.07)) / 0.3, 0.0, 1.0)
		if row_alpha <= 0.0:
			continue
		_draw_row(profile, Rect2(tx0, ry, total, ROW_H - 4.0), cols, row_alpha)


func _draw_row(profile: PlayerProfile, rect: Rect2, cols: Array, a: float) -> void:
	var is_mvp: bool = profile == _mvp
	var winner: int = Game.last_winner_team
	# Rivin tausta
	var bg := Palette.with_alpha(Palette.team(profile.team), 0.10)
	if profile.team == winner:
		bg = Palette.with_alpha(Palette.team(profile.team), 0.16)
	if is_mvp:
		bg = Palette.with_alpha(Palette.GOLD, 0.14)
	_card(rect, Palette.with_alpha(bg, bg.a * a),
		Palette.with_alpha(Palette.GOLD if is_mvp else Palette.team(profile.team), 0.35 * a),
		2 if is_mvp else 1, 10)

	var s: Dictionary = profile.stats
	var cy := rect.get_center().y
	var cx := rect.position.x
	for col in cols:
		var key: String = col[0]
		var w: float = col[1]
		var centered: bool = col[3]
		var px := cx + (w / 2.0 if centered else 44.0)
		match key:
			"name":
				var pc: Color = profile.color() if profile.is_human() \
					else Palette.with_alpha(Palette.team(profile.team), 0.7)
				draw_circle(Vector2(cx + 22.0, cy), 9.0, Palette.with_alpha(pc, a))
				var nm: String = profile.display_name
				var col_txt: Color = Palette.GOLD if is_mvp else Palette.TEXT_MAIN
				if not profile.is_human():
					col_txt = Palette.with_alpha(col_txt, 0.7)
				UiKit.draw_text(self, Vector2(px, cy), nm, 19, Palette.with_alpha(col_txt, a), false)
				if is_mvp:
					UiKit.draw_text(self, Vector2(cx + w - 46.0, cy), "★MVP", 14,
						Palette.with_alpha(Palette.GOLD, a), false)
			"hero":
				var hdef := HeroDef.get_def(profile.hero_id)
				var med := Vector2(cx + 20.0, cy)
				draw_circle(med, 15.0, Palette.with_alpha(Palette.darker(hdef["color_b"], 0.55), a))
				draw_circle(med, 12.0, Palette.with_alpha(hdef["color"], a))
				HeroIcon.draw_symbol(self, profile.hero_id, med, 8.0)
				UiKit.draw_text(self, Vector2(cx + 42.0, cy), profile.hero_name(), 15,
					Palette.with_alpha(Palette.TEXT_DIM, a), false)
			_:
				var val := ""
				match key:
					"score": val = str(int(s.score))
					"kos": val = str(s.kos)
					"assists": val = str(s.assists)
					"carry": val = str(int(s.carry_time))
					"damage": val = str(int(s.damage))
					"healing": val = str(int(s.healing))
					"prevented": val = str(int(s.prevented))
				UiKit.draw_text(self, Vector2(px, cy), val, 19, Palette.with_alpha(Palette.TEXT_MAIN, a), true)
		cx += w
