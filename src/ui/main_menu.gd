class_name MainMenu
extends Control
## MOBA-päävalikko: kilpailullinen 4v4-formaatti, taktinen karttatausta,
## sankariesittely ja ohjainlähtöinen navigaatio.

var _settings_overlay: Control = null
var _settings_return_focus: Control = null
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("menu")
	add_child(MenuBackdrop.new())
	AudioMgr.play("ui_open", 0.02, -5.0)

	# Nappisarake vasemmalle
	var box := UiKit.vbox(12)
	box.position = Vector2(230, 430)
	box.custom_minimum_size = Vector2(480, 0)
	add_child(box)

	var play_btn := _menu_button(box, "RANKED — KIIPEÄ SARJASSA", func(): Game.go_ranked(), true)
	_menu_button(box, "OMA OTTELU (EI RANKED)", func(): Game.go_setup(false))
	_menu_button(box, "HARJOITTELU + AI", func(): Game.go_setup(true))
	_menu_button(box, "SANKARIT & KYVYT", func(): Game.go_gallery())
	_menu_button(box, "SIMULAATIO & META", func(): Game.go_sim())
	_menu_button(box, "ASETUKSET", func(): _open_settings())
	_menu_button(box, "LOPETA PELI", func(): get_tree().quit())

	# Sankariesittely oikealle
	var showcase := HeroShowcase.new()
	showcase.position = Vector2(1080, 390)
	showcase.custom_minimum_size = Vector2(650, 470)
	showcase.size = Vector2(650, 470)
	add_child(showcase)

	play_btn.call_deferred("grab_focus")


func _menu_button(parent: Control, text: String, action: Callable, primary := false) -> Button:
	var btn := UiKit.button(text, action, 34)
	btn.custom_minimum_size = Vector2(480, 62)
	if primary:
		btn.add_theme_color_override("font_color", Palette.GOLD)
		btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
		btn.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	parent.add_child(btn)
	return btn


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# Otsikon hehku ja kilpailullinen MOBA-logo.
	var tc := Vector2(960, 122)
	var glow_pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(tc, 330.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.045 + glow_pulse * 0.02))
	draw_circle(tc + Vector2(130, 0), 300.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.04))

	UiKit.draw_text(self, tc, "PROJECT ARENA", 96, Palette.TEXT_MAIN, true, 12,
		Color(0.05, 0.08, 0.18, 0.95))
	UiKit.draw_text(self, Vector2(960, 188), "TWIN LANE MOBA", 25, Palette.GOLD, true, 4)

	# Hehkuva joukkuevärialaviiva
	var uw := 660.0
	var uy := 218.0
	draw_rect(Rect2(960 - uw / 2.0, uy, uw / 2.0, 8.0), Palette.glow(Palette.TEAM_BLUE, 1.3))
	draw_rect(Rect2(960, uy, uw / 2.0, 8.0), Palette.glow(Palette.TEAM_ORANGE, 1.3))
	draw_circle(Vector2(960, uy + 4.0), 10.0 + glow_pulse * 2.0, Palette.glow(Palette.GOLD, 1.6))

	UiKit.draw_text(self, Vector2(960, 258),
		"Paikallinen 4v4-joukkuetaistelu — top, bottom, jungle ja suuret objectivet",
		22, Palette.TEXT_DIM, true)

	# Ominaisuusmerkit
	_draw_badges(306.0)
	_draw_match_card()

	# Alareunan vihjeet
	UiKit.draw_text(self, Vector2(960, 1010),
		"PS5: X valitsee • O palaa • vasen tatti / ristiohjain liikkuu valikoissa",
		20, Palette.TEXT_DIM, true)
	UiKit.draw_text(self, Vector2(960, 1044), "MOBA PRE-ALPHA  •  LOCAL 1–4  •  AI TÄYTTÄÄ 4V4-JOUKKUEET",
		15, Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)


func _draw_badges(cy: float) -> void:
	var badges := [
		["4V4 MOBA", Palette.TEAM_BLUE],
		["2 LINJAA + JUNGLE", Palette.GOOD],
		["20 MIN", Palette.TEAM_ORANGE],
		["%d SANKARIA" % HeroDef.ORDER.size(), Palette.GOLD],
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


func _draw_match_card() -> void:
	var rect := Rect2(230, 354, 480, 58)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.075, 0.055, 0.92)
	sb.border_color = Palette.with_alpha(Palette.GOLD, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.draw(get_canvas_item(), rect)
	draw_circle(rect.position + Vector2(28, rect.size.y / 2.0), 7.0,
		Palette.glow(Palette.GOOD, 1.35))
	UiKit.draw_text(self, rect.position + Vector2(50, 22), "ETERNAL DIVIDE", 18,
		Palette.TEXT_MAIN, false)
	UiKit.draw_text(self, rect.position + Vector2(50, 43), "VAKIOFORMAATTI  •  4V4  •  20:00", 12,
		Palette.TEXT_DIM, false)
	UiKit.draw_text(self, rect.position + Vector2(400, 30), "VALMIS", 12,
		Palette.GOOD, true)


# --- Asetukset ---

func _open_settings() -> void:
	if _settings_overlay != null:
		return
	_settings_return_focus = get_viewport().gui_get_focus_owner()
	AudioMgr.play("ui_open", 0.02, -2.0)
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.z_index = 100

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(dim)

	var center := UiKit.fullscreen_center(_settings_overlay)
	var panel := UiKit.panel(Vector2(1120, 700))
	center.add_child(panel)
	var box := UiKit.vbox(12)
	panel.add_child(box)

	box.add_child(UiKit.title("ASETUKSET", 48))
	var sub := UiKit.dim_label("Äänimaailma, paikallinen split screen ja kuvan tuntuma", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(UiKit.spacer(8))

	var columns := UiKit.hbox(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	var audio_panel := UiKit.panel(Vector2(530, 430))
	columns.add_child(audio_panel)
	var audio_box := UiKit.vbox(12)
	audio_panel.add_child(audio_box)
	audio_box.add_child(UiKit.label("ÄÄNI", 27, Palette.GOLD))
	audio_box.add_child(UiKit.dim_label("Erota musiikki, taisteluäänet ja kokonaisvoimakkuus.", 15))
	# Kolme miksausväylää: pääväylä, musiikkiväylä ja tehosteväylät
	# (SFX + panorointiväylät + UI + hälytykset + ympäristö).
	_settings_slider(audio_box, "PÄÄÄÄNI", float(Game.options.volume), func(v):
		Game.options.volume = v
		AudioMgr.set_master_volume(v))
	_settings_slider(audio_box, "MUSIIKKI", float(Game.options.music_volume), func(v):
		Game.options.music_volume = v
		AudioMgr.set_music_volume(v))
	_settings_slider(audio_box, "TEHOSTEET", float(Game.options.sfx_volume), func(v):
		Game.options.sfx_volume = v
		AudioMgr.set_sfx_volume(v))
	var music_toggle := _settings_toggle("Musiikki käytössä", bool(Game.options.music), func(on):
		Game.options.music = on
		AudioMgr.set_music_enabled(on))
	audio_box.add_child(music_toggle)
	var test_audio := UiKit.button("TESTAA VALIKKOÄÄNET", func():
		AudioMgr.play("ui_open", 0.0, -2.0)
		AudioMgr.play("ui_lock", 0.0, -1.0), 18)
	test_audio.custom_minimum_size = Vector2(470, 44)
	audio_box.add_child(test_audio)

	var video_panel := UiKit.panel(Vector2(530, 430))
	columns.add_child(video_panel)
	var video_box := UiKit.vbox(16)
	video_panel.add_child(video_box)
	video_box.add_child(UiKit.label("KUVA & PAIKALLINEN PELI", 27, Palette.GOLD))
	var video_desc := UiKit.dim_label(
		"Pelaajakohtainen kamera seuraa aina omaa sankaria (1–4 paikallista pelaajaa).", 15)
	video_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	video_desc.custom_minimum_size = Vector2(470, 48)
	video_box.add_child(video_desc)
	var camera_lock := _settings_toggle("Pelaajakohtainen split screen", true, Callable())
	camera_lock.disabled = true
	video_box.add_child(camera_lock)
	video_box.add_child(_settings_toggle("Ruudun tärinä", bool(Game.options.shake), func(on):
		Game.options.shake = on))
	video_box.add_child(_settings_toggle("Koko ruutu (F11)", bool(Game.options.fullscreen), func(on):
		Game.options.fullscreen = on
		Game.apply_options()))
	video_box.add_child(UiKit.spacer(16))
	var format := UiKit.dim_label("VAKIOFORMAATTI", 14)
	video_box.add_child(format)
	video_box.add_child(UiKit.label("4V4  •  ETERNAL DIVIDE  •  20:00", 20, Palette.GOOD))
	var input_hint := UiKit.dim_label("PS5: X valitsee, O palaa, tatti/ristiohjain navigoi", 14)
	input_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	video_box.add_child(input_hint)

	box.add_child(UiKit.spacer(4))
	var done_btn := UiKit.button("TALLENNA JA PALAA", func(): _close_settings(), 24)
	done_btn.custom_minimum_size = Vector2(520, 52)
	done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(done_btn)

	add_child(_settings_overlay)
	done_btn.grab_focus()


func _settings_slider(parent: Control, label_text: String, value: float,
		on_change: Callable) -> void:
	var header := UiKit.hbox(8)
	var name := UiKit.label(label_text, 18)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name)
	var pct := UiKit.label("%d %%" % int(round(value * 100.0)), 17, Palette.GOLD)
	pct.custom_minimum_size = Vector2(72, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(pct)
	parent.add_child(header)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(470, 28)
	slider.value_changed.connect(func(v):
		pct.text = "%d %%" % int(round(v * 100.0))
		on_change.call(v))
	slider.drag_ended.connect(func(_changed):
		Game.save_options()
		AudioMgr.play("ui_lock", 0.02, -7.0))
	slider.focus_entered.connect(func(): AudioMgr.play("ui_move", 0.02, -7.0))
	parent.add_child(slider)


func _settings_toggle(text: String, active: bool, on_change: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = active
	toggle.add_theme_font_size_override("font_size", 20)
	toggle.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	toggle.add_theme_color_override("font_focus_color", Color.WHITE)
	toggle.custom_minimum_size = Vector2(470, 44)
	toggle.toggled.connect(func(on):
		on_change.call(on)
		Game.save_options()
		AudioMgr.play("ui_lock" if on else "ui_back", 0.02, -5.0))
	toggle.focus_entered.connect(func(): AudioMgr.play("ui_move", 0.02, -7.0))
	return toggle


func _close_settings() -> void:
	if _settings_overlay == null:
		return
	Game.save_options()
	_settings_overlay.queue_free()
	_settings_overlay = null
	AudioMgr.play("ui_back")
	if _settings_return_focus != null and is_instance_valid(_settings_return_focus):
		_settings_return_focus.call_deferred("grab_focus")
	_settings_return_focus = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_overlay != null:
		_close_settings()


## Automaattisesti kaikki sankarit kiertävä esittelykortti.
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
		UiKit.draw_text(self, Vector2(cx, 34), "MOBA ROSTER  •  %d / %d" % [_idx + 1, HeroDef.ORDER.size()],
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
		# Taistelun identiteetti: perushyökkäys + ratkaiseva ulti.
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
