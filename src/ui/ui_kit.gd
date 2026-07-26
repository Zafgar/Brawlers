class_name UiKit
## Käyttöliittymän rakennusapurit: yhtenäiset napit, paneelit ja tekstit.
## Kaikki valikot rakennetaan koodissa näiden avulla, jotta tyyli pysyy samana.


static func title(text: String, size := 72) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.18, 0.9))
	label.add_theme_constant_override("outline_size", int(size / 6.0))
	return label


static func label(text: String, size := 26, color := Palette.TEXT_MAIN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func dim_label(text: String, size := 22) -> Label:
	return label(text, size, Palette.TEXT_DIM)


static func button(text: String, on_pressed: Callable, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Palette.GOLD)

	var normal := _stylebox(Palette.UI_PANEL, Color(0, 0, 0, 0))
	var hover := _stylebox(Palette.UI_PANEL_LIGHT, Palette.UI_STROKE)
	var focus := _stylebox(Palette.UI_PANEL_LIGHT, Color(1, 1, 1, 0.85), 3)
	var pressed := _stylebox(Palette.darker(Palette.UI_PANEL_LIGHT, 0.8), Palette.GOLD, 3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", pressed)

	b.pressed.connect(on_pressed)
	b.pressed.connect(func(): AudioMgr.play("ui_ok"))
	b.focus_entered.connect(func(): AudioMgr.play("ui_move"))
	b.mouse_entered.connect(func(): b.grab_focus())
	return b


## Tekstikenttä valikkotyylillä (ranked-tilin nimi). Ohjaimella pelaava voi
## ohittaa kirjoittamisen ja poimia valmiin nimiehdotuksen.
static func line_edit(placeholder := "", max_length := 18, size := 26) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", size)
	edit.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	edit.add_theme_color_override("font_placeholder_color", Palette.TEXT_DIM)
	edit.add_theme_stylebox_override("normal", _stylebox(Palette.UI_PANEL, Palette.UI_STROKE))
	edit.add_theme_stylebox_override("focus",
		_stylebox(Palette.UI_PANEL_LIGHT, Palette.GOLD, 3))
	edit.focus_entered.connect(func(): AudioMgr.play("ui_move", 0.02, -7.0))
	return edit


static func _stylebox(bg: Color, border: Color, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _stylebox(Palette.UI_PANEL, Palette.UI_STROKE, 2)
	sb.set_corner_radius_all(18)
	p.add_theme_stylebox_override("panel", sb)
	if min_size != Vector2.ZERO:
		p.custom_minimum_size = min_size
	return p


static func vbox(separation := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(height := 20) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## Koko ruudun keskitetty asettelu: palauttaa CenterContainerin joka on
## lisätty rootiin ja täyttää ruudun.
static func fullscreen_center(root: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	return center


## Piirtoapuri _draw-konteksteihin: keskitetty teksti ääriviivalla.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size := 24,
		color := Palette.TEXT_MAIN, centered := true, outline := 0,
		outline_color := Color(0.05, 0.08, 0.18, 0.9)) -> void:
	var font := ThemeDB.fallback_font
	var width := 2000.0
	var draw_pos := pos
	var align := HORIZONTAL_ALIGNMENT_LEFT
	if centered:
		align = HORIZONTAL_ALIGNMENT_CENTER
		draw_pos = pos + Vector2(-width / 2.0, size * 0.36)
	if outline > 0:
		ci.draw_string_outline(font, draw_pos, text, align, width, size, outline, outline_color)
	ci.draw_string(font, draw_pos, text, align, width, size, color)
