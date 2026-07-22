class_name MatchSetup
extends Control
## MOBA-ottelun valmistelu. Vanhoja areenamoodeja tai karttavalintaa ei enää
## näytetä: kilpailullinen formaatti on aina 4v4 Eternal Divide -kartalla.

var _desc_label: Label = null

const DESCRIPTIONS := {
	"bots": "AI-taso vaikuttaa reaktioon, tähtäykseen, farmaukseen, objective-päätöksiin ja turvatornien kunnioittamiseen. Taso 6 on tarkoituksella epäreilu.",
	"split": "Jokaisella paikallisella pelaajalla on oma sankaria seuraava näkymä. Myös yhden pelaajan peli käyttää tätä kameraa.",
	"format": "Vakioformaatti: 4v4, yksi top, yksi jungle ja kaksi bottom. Vapaat pelaajapaikat täytetään AI-sankareilla.",
	"map": "Eternal Divide: kaksi kaartuvaa linjaa, niiden välinen jungle, Red/Blue-buffit, Dragon, Baron, kolme tornia per linja ja Nexus.",
	"time": "Ottelu kestää enintään 20 minuuttia. Nexus-voitto voi ratkaista ottelun aikaisemmin.",
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game._apply_moba_format()
	AudioMgr.play_music_pool("lobby")
	AudioMgr.play("ui_open", 0.02, -4.0)
	var backdrop := MenuBackdrop.new()
	backdrop.team_glow = true
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var page := UiKit.vbox(10)
	margin.add_child(page)
	page.add_child(UiKit.title("VALMISTELE MOBA-OTTELU", 62))
	var underline := Underline.new()
	underline.custom_minimum_size = Vector2(620, 12)
	underline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(underline)
	var subtitle := UiKit.dim_label(
		"Yksi kilpailullinen formaatti — säädä vain AI ja paikallisen pelin näkymä", 19)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(subtitle)
	page.add_child(UiKit.spacer(8))

	var content := UiKit.hbox(22)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(content)

	var map_panel := UiKit.panel(Vector2(650, 590))
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(map_panel)
	var map_box := UiKit.vbox(8)
	map_panel.add_child(map_box)
	var map_header := UiKit.hbox(10)
	map_box.add_child(map_header)
	var map_name := UiKit.label("ETERNAL DIVIDE", 29, Palette.GOLD)
	map_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_header.add_child(map_name)
	map_header.add_child(UiKit.label("4V4  •  20:00", 18, Palette.GOOD))
	var map_sub := UiKit.dim_label("TWIN LANE BATTLEGROUND", 14)
	map_box.add_child(map_sub)
	var preview := MobaPreview.new()
	preview.custom_minimum_size = Vector2(610, 390)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_box.add_child(preview)
	var objective := UiKit.dim_label(
		"TYÖNNÄ MOLEMMAT LINJAT  •  TUHOA BASE-TORNIT  •  AVAA JA KAADA NEXUS", 14)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_box.add_child(objective)

	var settings_panel := UiKit.panel(Vector2(780, 590))
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_panel)
	var settings := UiKit.vbox(10)
	settings_panel.add_child(settings)
	settings.add_child(UiKit.label("OTTELUASETUKSET", 29, Palette.GOLD))
	settings.add_child(UiKit.dim_label("Lukitut rivit ovat pelin virallinen MOBA-formaatti.", 15))

	var format_row := OptionRow.new("Formaatti", ["4v4 MOBA"], 0, Callable())
	format_row.locked = true
	format_row.desc_key = "format"
	_add_row(settings, format_row)
	var map_row := OptionRow.new("Kenttä", ["Eternal Divide"], 0, Callable())
	map_row.locked = true
	map_row.desc_key = "map"
	_add_row(settings, map_row)
	var time_row := OptionRow.new("Aikaraja", ["20 minuuttia"], 0, Callable())
	time_row.locked = true
	time_row.desc_key = "time"
	_add_row(settings, time_row)

	var bots_row := OptionRow.new("AI-vaikeus", Game.BOT_LEVEL_NAMES, Game.bot_level,
		func(i): Game.bot_level = i)
	bots_row.desc_key = "bots"
	_add_row(settings, bots_row)
	var split_row := OptionRow.new("Paikallinen näkymä", ["Pelaajakohtainen split screen"],
		0, Callable())
	split_row.locked = true
	split_row.desc_key = "split"
	_add_row(settings, split_row)

	_desc_label = UiKit.dim_label(DESCRIPTIONS["format"], 17)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_label.custom_minimum_size = Vector2(700, 68)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings.add_child(_desc_label)

	page.add_child(UiKit.spacer(4))
	var buttons := UiKit.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(buttons)
	var back_btn := UiKit.button("TAKAISIN", func(): Game.go_menu(), 22)
	back_btn.custom_minimum_size = Vector2(330, 54)
	buttons.add_child(back_btn)
	var continue_btn := UiKit.button("JATKA PELAAJIIN", func(): Game.go_lobby(), 25)
	continue_btn.custom_minimum_size = Vector2(520, 54)
	continue_btn.add_theme_color_override("font_color", Palette.GOLD)
	continue_btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
	continue_btn.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	buttons.add_child(continue_btn)
	var hint := UiKit.dim_label("A/D tai ‹ › säätää  •  X/Enter valitsee  •  O/Esc palaa", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)

	bots_row.call_deferred("grab_focus")


func _add_row(parent: Control, row: OptionRow) -> void:
	row.custom_minimum_size = Vector2(720, 48)
	parent.add_child(row)
	row.focus_entered.connect(func():
		if _desc_label != null:
			_desc_label.text = DESCRIPTIONS.get(row.desc_key, ""))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()


class OptionRow:
	extends Button

	var row_label := ""
	var values: Array = []
	var idx := 0
	var on_change := Callable()
	var locked := false
	var desc_key := ""

	func _init(p_label: String, p_values: Array, p_idx: int, p_on_change: Callable) -> void:
		row_label = p_label
		values = p_values
		idx = clampi(p_idx, 0, values.size() - 1)
		on_change = p_on_change
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_theme_font_size_override("font_size", 21)
		add_theme_color_override("font_color", Palette.TEXT_MAIN)
		add_theme_color_override("font_hover_color", Color.WHITE)
		add_theme_color_override("font_focus_color", Color.WHITE)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Palette.UI_PANEL
		normal.set_corner_radius_all(12)
		normal.content_margin_left = 24.0
		normal.content_margin_right = 24.0
		normal.content_margin_top = 9.0
		normal.content_margin_bottom = 9.0
		add_theme_stylebox_override("normal", normal)
		var focus: StyleBoxFlat = normal.duplicate()
		focus.bg_color = Palette.UI_PANEL_LIGHT
		focus.border_color = Palette.with_alpha(Palette.GOLD, 0.82)
		focus.set_border_width_all(2)
		add_theme_stylebox_override("focus", focus)
		add_theme_stylebox_override("hover", focus)
		add_theme_stylebox_override("pressed", normal)
		pressed.connect(func(): _cycle(1))
		focus_entered.connect(func(): AudioMgr.play("ui_move", 0.02, -7.0))
		_sync_text()

	func _ready() -> void:
		if locked:
			modulate = Color(1, 1, 1, 0.68)
			focus_mode = Control.FOCUS_ALL
		_sync_text()

	func _gui_input(event: InputEvent) -> void:
		if locked:
			return
		if event.is_action_pressed("ui_left"):
			_cycle(-1)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			_cycle(1)
			accept_event()

	func _cycle(dir: int) -> void:
		if locked or values.size() <= 1:
			AudioMgr.play("ui_deny", 0.02, -8.0)
			return
		idx = (idx + dir + values.size()) % values.size()
		_sync_text()
		AudioMgr.play("ui_team", 0.02, -6.0)
		if on_change.is_valid():
			on_change.call(idx)

	func _sync_text() -> void:
		var value := str(values[idx])
		text = "%s     %s" % [row_label, value] if locked \
			else "%s     ‹  %s  ›" % [row_label, value]


class Underline:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var pulse := 0.5 + 0.5 * sin(_t * 1.5)
		draw_rect(Rect2(0, 3, w / 2.0, 6.0), Palette.glow(Palette.TEAM_BLUE, 1.3))
		draw_rect(Rect2(w / 2.0, 3, w / 2.0, 6.0), Palette.glow(Palette.TEAM_ORANGE, 1.3))
		draw_circle(Vector2(w / 2.0, 6.0), 8.0 + pulse * 2.0, Palette.glow(Palette.GOLD, 1.5))


class MobaPreview:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(8, 8, size.x - 16, size.y - 16)
		draw_rect(rect, Color(0.015, 0.065, 0.04, 0.92))
		var center := rect.get_center()
		# River
		draw_rect(Rect2(center.x - 16, rect.position.y + 10, 32, rect.size.y - 20),
			Color(0.10, 0.38, 0.45, 0.48))
		var top := _path(rect, true)
		var bottom := _path(rect, false)
		for path in [top, bottom]:
			draw_polyline(path, Color(0.36, 0.29, 0.18, 0.9), 28.0, true)
			draw_polyline(path, Color(0.68, 0.52, 0.27, 0.42), 3.0, true)
		_draw_base(Vector2(rect.position.x + 28, center.y), Palette.TEAM_BLUE)
		_draw_base(Vector2(rect.end.x - 28, center.y), Palette.TEAM_ORANGE)
		for path in [top, bottom]:
			for i in [1, 2, 3]: _tower(path[i], Palette.TEAM_BLUE)
			for i in [5, 6, 7]: _tower(path[i], Palette.TEAM_ORANGE)
		_objective(Vector2(center.x, center.y - 72), Color("bd60e5"), "BARON")
		_objective(Vector2(center.x, center.y + 72), Color("49d7c5"), "DRAGON")
		UiKit.draw_text(self, Vector2(center.x, rect.position.y + 26), "TOP", 11,
			Palette.with_alpha(Palette.TEXT_DIM, 0.8), true)
		UiKit.draw_text(self, Vector2(center.x, rect.end.y - 22), "BOTTOM", 11,
			Palette.with_alpha(Palette.TEXT_DIM, 0.8), true)

	func _path(rect: Rect2, top: bool) -> PackedVector2Array:
		var y_outer := rect.position.y + 58.0 if top else rect.end.y - 58.0
		var y_base := rect.get_center().y
		return PackedVector2Array([
			Vector2(rect.position.x + 30, y_base), Vector2(rect.position.x + 80, y_outer + 30),
			Vector2(rect.position.x + 180, y_outer), Vector2(rect.position.x + 300, y_outer + 6),
			Vector2(rect.get_center().x, y_outer + 18), Vector2(rect.end.x - 300, y_outer + 6),
			Vector2(rect.end.x - 180, y_outer), Vector2(rect.end.x - 80, y_outer + 30),
			Vector2(rect.end.x - 30, y_base),
		])

	func _tower(pos: Vector2, col: Color) -> void:
		draw_circle(pos, 9.0, Color(0.01, 0.03, 0.02, 0.9))
		draw_circle(pos, 5.0, col)

	func _draw_base(pos: Vector2, col: Color) -> void:
		draw_circle(pos, 20.0, Palette.with_alpha(col, 0.18))
		draw_circle(pos, 11.0, col)

	func _objective(pos: Vector2, col: Color, text: String) -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 1.6 + pos.y)
		draw_circle(pos, 17.0 + pulse * 2.0, Palette.with_alpha(col, 0.13))
		draw_arc(pos, 14.0, -_t * 0.2, -_t * 0.2 + TAU * 0.8, 18, col, 2.0)
		UiKit.draw_text(self, pos + Vector2(27, 0), text, 9, Palette.with_alpha(col, 0.9), false)
