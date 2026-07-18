class_name MainMenu
extends Control
## Näyttävä päävalikko: hehkuva otsikko, ominaisuusmerkit, kaikki 12 sankaria
## kiertävä esittelykortti ja ajelehtiva taustatunnelma.

var _settings_overlay: Control = null
var _time := 0.0
var _orbs: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music("menu")
	add_child(MenuBackdrop.new())

	# Ajelehtivat sankariväri-orbit taustalle
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in range(9):
		_orbs.append({
			"pos": Vector2(rng.randf_range(0, 1920), rng.randf_range(0, 1080)),
			"vel": Vector2(rng.randf_range(-16, 16), rng.randf_range(-10, 10)),
			"r": rng.randf_range(60, 130),
			"color": Palette.player(i % Palette.PLAYER_COLORS.size())})

	# Nappisarake vasemmalle
	var box := UiKit.vbox(12)
	box.position = Vector2(330, 452)
	box.custom_minimum_size = Vector2(440, 0)
	add_child(box)

	var play_btn := _menu_button(box, "Pelaa", func(): Game.go_setup(false), true)
	_menu_button(box, "Harjoittelu", func(): Game.go_setup(true))
	_menu_button(box, "Sankarit", func(): Game.go_gallery())
	_menu_button(box, "Asetukset", func(): _open_settings())
	_menu_button(box, "Lopeta peli", func(): get_tree().quit())

	# Sankariesittely oikealle
	var showcase := HeroShowcase.new()
	showcase.position = Vector2(1140, 356)
	showcase.custom_minimum_size = Vector2(650, 470)
	showcase.size = Vector2(650, 470)
	add_child(showcase)

	play_btn.call_deferred("grab_focus")


func _menu_button(parent: Control, text: String, action: Callable, primary := false) -> Button:
	var btn := UiKit.button(text, action, 34)
	btn.custom_minimum_size = Vector2(450, 62)
	if primary:
		btn.add_theme_color_override("font_color", Palette.GOLD)
		btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
		btn.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	parent.add_child(btn)
	return btn


func _process(delta: float) -> void:
	_time += delta
	for orb in _orbs:
		orb.pos += orb.vel * delta
		if orb.pos.x < -150:
			orb.pos.x = 2070
		elif orb.pos.x > 2070:
			orb.pos.x = -150
		if orb.pos.y < -150:
			orb.pos.y = 1230
		elif orb.pos.y > 1230:
			orb.pos.y = -150
	queue_redraw()


func _draw() -> void:
	# Ajelehtivat orbit (pehmeät sankarivärit)
	for orb in _orbs:
		var pos: Vector2 = orb.pos
		var r: float = orb.r
		var col: Color = orb.color
		draw_circle(pos, r, Palette.with_alpha(col, 0.05))
		draw_circle(pos, r * 0.62, Palette.with_alpha(col, 0.05))
		draw_arc(pos, r, 0.0, TAU, 32, Palette.with_alpha(col, 0.09), 2.0)

	# Otsikon hehku
	var tc := Vector2(960, 150)
	var glow_pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(tc, 340.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.05 + glow_pulse * 0.03))
	draw_circle(tc + Vector2(120, 0), 300.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.05))

	# Otsikko
	UiKit.draw_text(self, tc, "PROJECT ARENA", 108, Palette.TEXT_MAIN, true, 12,
		Color(0.05, 0.08, 0.18, 0.95))

	# Hehkuva joukkuevärialaviiva
	var uw := 660.0
	var uy := 218.0
	draw_rect(Rect2(960 - uw / 2.0, uy, uw / 2.0, 8.0), Palette.glow(Palette.TEAM_BLUE, 1.3))
	draw_rect(Rect2(960, uy, uw / 2.0, 8.0), Palette.glow(Palette.TEAM_ORANGE, 1.3))
	draw_circle(Vector2(960, uy + 4.0), 10.0 + glow_pulse * 2.0, Palette.glow(Palette.GOLD, 1.6))

	# Alaotsikko
	UiKit.draw_text(self, Vector2(960, 262), "Värikäs paikallinen areenataistelu 1–8 pelaajalle",
		27, Palette.TEXT_DIM, true)

	# Ominaisuusmerkit
	_draw_badges(316.0)

	# Alareunan vihjeet
	UiKit.draw_text(self, Vector2(960, 1010),
		"Liitä PS5-ohjain ja paina X — tai pelaa näppäimistöllä ja hiirellä",
		20, Palette.TEXT_DIM, true)
	UiKit.draw_text(self, Vector2(960, 1044), "Versio 0.2 — prototyyppi",
		15, Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)


func _draw_badges(cy: float) -> void:
	var badges := [
		["12 SANKARIA", Palette.TEAM_BLUE],
		["5 KENTTÄÄ", Palette.GOOD],
		["1–8 PELAAJAA", Palette.TEAM_ORANGE],
		["CO-OP & BOTIT", Palette.GOLD],
	]
	var font := ThemeDB.fallback_font
	var fs := 18
	var gap := 16.0
	var widths := []
	var total := 0.0
	for b in badges:
		var w: float = font.get_string_size(b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40.0
		widths.append(w)
		total += w
	total += gap * (badges.size() - 1)

	var x := 960.0 - total / 2.0
	for i in range(badges.size()):
		var w: float = widths[i]
		var col: Color = badges[i][1]
		var rect := Rect2(x, cy - 19.0, w, 38.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.85)
		sb.set_corner_radius_all(19)
		sb.border_color = Palette.with_alpha(col, 0.7)
		sb.set_border_width_all(2)
		sb.draw(get_canvas_item(), rect)
		draw_circle(Vector2(x + 20.0, cy), 4.0, Palette.glow(col, 1.4))
		UiKit.draw_text(self, Vector2(x + w / 2.0 + 8.0, cy), badges[i][0], fs, col, true)
		x += w + gap


# --- Asetukset ---

func _open_settings() -> void:
	if _settings_overlay != null:
		return
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(dim)

	var center := UiKit.fullscreen_center(_settings_overlay)
	var panel := UiKit.panel(Vector2(560, 0))
	center.add_child(panel)
	var box := UiKit.vbox(20)
	panel.add_child(box)

	box.add_child(UiKit.title("ASETUKSET", 52))
	box.add_child(UiKit.spacer(8))

	box.add_child(UiKit.label("Äänenvoimakkuus", 24))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Game.options.volume
	slider.custom_minimum_size = Vector2(460, 32)
	slider.value_changed.connect(func(v):
		Game.options.volume = v
		Game.apply_options())
	box.add_child(slider)

	var music_check := CheckButton.new()
	music_check.text = "Musiikki"
	music_check.button_pressed = Game.options.music
	music_check.add_theme_font_size_override("font_size", 24)
	music_check.toggled.connect(func(on):
		Game.options.music = on
		Game.apply_options())
	box.add_child(music_check)

	var shake_check := CheckButton.new()
	shake_check.text = "Ruudun tärinä"
	shake_check.button_pressed = Game.options.shake
	shake_check.add_theme_font_size_override("font_size", 24)
	shake_check.toggled.connect(func(on):
		Game.options.shake = on)
	box.add_child(shake_check)

	box.add_child(UiKit.spacer(10))
	var done_btn := UiKit.button("Valmis", func(): _close_settings())
	box.add_child(done_btn)

	add_child(_settings_overlay)
	done_btn.grab_focus()


func _close_settings() -> void:
	if _settings_overlay == null:
		return
	Game.save_options()
	_settings_overlay.queue_free()
	_settings_overlay = null
	AudioMgr.play("ui_back")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_overlay != null:
		_close_settings()


## Automaattisesti kaikki 12 sankaria kiertävä esittelykortti.
class HeroShowcase:
	extends Control

	const HOLD := 3.6

	var _idx := 0
	var _t := 0.0
	var _time := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		_time += delta
		if _t >= HOLD:
			_t = 0.0
			_idx = (_idx + 1) % HeroDef.ORDER.size()
			AudioMgr.play("ui_move", 0.05, -8.0)
		queue_redraw()

	func _draw() -> void:
		var hero_id: String = HeroDef.ORDER[_idx]
		var def := HeroDef.get_def(hero_id)
		var c1: Color = def["color"]
		var c2: Color = def["color_b"]
		var w := size.x
		var cx := w / 2.0

		# Paneeli
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.9)
		sb.set_corner_radius_all(22)
		sb.border_color = Palette.with_alpha(c1, 0.65)
		sb.set_border_width_all(2)
		sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		# Sisällön sisääntulohäivytys
		var fade: float = clampf(_t / 0.35, 0.0, 1.0)
		if _t > HOLD - 0.3:
			fade = minf(fade, (HOLD - _t) / 0.3)
		var slide := (1.0 - fade) * 20.0

		# Otsikkorivi
		UiKit.draw_text(self, Vector2(cx, 34), "SANKARIT — %d / %d" % [_idx + 1, HeroDef.ORDER.size()],
			16, Palette.TEXT_DIM, true)

		# Medaljongin hehkukehä
		var med := Vector2(cx, 130.0 - slide)
		var ring_r := 74.0 + sin(_time * 3.0) * 3.0
		draw_arc(med, ring_r + 8.0, _time, _time + TAU * 0.8, 32,
			Palette.with_alpha(Palette.glow(c1, 1.4), 0.5 * fade), 3.0)
		draw_circle(med, ring_r, Palette.with_alpha(c1, 0.12 * fade))
		draw_circle(med, 64.0, Palette.with_alpha(Palette.darker(c2, 0.55), fade))
		draw_circle(med, 60.0, Palette.with_alpha(c1, fade))
		draw_circle(med + Vector2(0, 22), 42.0, Palette.with_alpha(c2, 0.35 * fade))
		HeroIcon.draw_symbol(self, hero_id, med, 40.0)

		# Nimi + rooli
		UiKit.draw_text(self, Vector2(cx, 232.0), def["name"], 46,
			Palette.with_alpha(c1, fade), true, 5)
		var stars := ""
		for i in range(3):
			stars += "★" if i < int(def["difficulty"]) else "☆"
		UiKit.draw_text(self, Vector2(cx, 268.0), "%s   %s" % [def["role"], stars], 20,
			Palette.with_alpha(c1, 0.9 * fade), true)
		UiKit.draw_text(self, Vector2(cx, 296.0), def["weapon"], 16,
			Palette.with_alpha(Palette.TEXT_DIM, fade), true)

		# Tilastopalkit
		var stats := ["kesto", "liike", "vahinko", "tuki"]
		var bx := 90.0
		var by := 322.0
		for i in range(stats.size()):
			var sy := by + i * 24.0
			UiKit.draw_text(self, Vector2(bx + 26.0, sy), stats[i].capitalize(), 13,
				Palette.with_alpha(Palette.TEXT_DIM, fade), false)
			var cell := 5
			var val: int = int(def["ratings"][stats[i]])
			for c in range(cell):
				var rect := Rect2(bx + 120.0 + c * 18.0, sy - 7.0, 14.0, 14.0)
				var filled: bool = c < val
				draw_rect(rect, Palette.with_alpha(c1 if filled else Color(0, 0, 0, 0.4), fade))
		# Kyvyt (perus + ulti)
		var abilities: Dictionary = def["abilities"]
		UiKit.draw_text(self, Vector2(cx, 428.0),
			"%s  ·  %s" % [abilities["basic"]["name"], abilities["ult"]["name"]],
			15, Palette.with_alpha(Palette.GOLD, fade), true)

		# Sivupisteet
		var dots := HeroDef.ORDER.size()
		var dot_w := 14.0
		var start_x := cx - (dots * dot_w) / 2.0 + dot_w / 2.0
		for i in range(dots):
			var active: bool = i == _idx
			draw_circle(Vector2(start_x + i * dot_w, size.y - 20.0), 4.0 if active else 2.5,
				Palette.glow(c1, 1.3) if active else Palette.with_alpha(Palette.TEXT_DIM, 0.5))
