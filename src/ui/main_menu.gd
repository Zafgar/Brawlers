class_name MainMenu
extends Control
## Päävalikko: Pelaa, Harjoittelu, Sankarit, Asetukset, Lopeta peli.

var _settings_overlay: Control = null
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())

	var center := UiKit.fullscreen_center(self)
	var box := UiKit.vbox(10)
	center.add_child(box)

	var title := UiKit.title("PROJECT ARENA", 110)
	box.add_child(title)

	var underline := TitleUnderline.new()
	underline.custom_minimum_size = Vector2(700, 14)
	underline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(underline)

	var subtitle := UiKit.dim_label("Paikallinen areenataistelu 1–8 pelaajalle", 28)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(subtitle)
	box.add_child(UiKit.spacer(36))

	var play_btn := _menu_button(box, "Pelaa", func(): Game.go_setup(false))
	_menu_button(box, "Harjoittelu", func(): Game.go_setup(true))
	_menu_button(box, "Sankarit", func(): Game.go_gallery())
	_menu_button(box, "Asetukset", func(): _open_settings())
	_menu_button(box, "Lopeta peli", func(): get_tree().quit())

	box.add_child(UiKit.spacer(30))
	var hint := UiKit.dim_label("Liitä PS5-ohjain ja paina X — tai pelaa näppäimistöllä ja hiirellä", 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(hint)
	var version := UiKit.dim_label("Versio 0.1 — ensimmäinen prototyyppi", 16)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(version)

	play_btn.call_deferred("grab_focus")


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var btn := UiKit.button(text, action, 32)
	btn.custom_minimum_size = Vector2(440, 0)
	parent.add_child(btn)
	return btn


func _process(delta: float) -> void:
	_time += delta


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


## Otsikon alle piirtyvä hehkuva joukkueväriviiva.
class TitleUnderline:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := 8.0
		draw_rect(Rect2(0, 3, w / 2.0, h), Palette.glow(Palette.TEAM_BLUE, 1.3))
		draw_rect(Rect2(w / 2.0, 3, w / 2.0, h), Palette.glow(Palette.TEAM_ORANGE, 1.3))
		draw_circle(Vector2(w / 2.0, 3 + h / 2.0), 9.0, Palette.glow(Palette.GOLD, 1.6))
