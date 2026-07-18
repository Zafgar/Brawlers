class_name HeroGallery
extends Control
## Sankarigalleria: sankarilista vasemmalla, valitun sankarin täydet tiedot
## isossa paneelissa oikealla. Toimii ohjaimella (fokus vaihtaa sankaria),
## näppäimistöllä ja hiirellä. Kaikki mahtuu ruudulle ilman vieritystä.

var _detail_holder: PanelContainer = null
var _selected := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music("menu")
	add_child(MenuBackdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var box := UiKit.vbox(18)
	margin.add_child(box)

	var title := UiKit.title("SANKARIT", 64)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(title)

	var row := UiKit.hbox(28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	# Vasen palsta: sankarinapit kahdessa sarakkeessa
	var list := UiKit.vbox(10)
	list.custom_minimum_size = Vector2(400, 0)
	row.add_child(list)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)

	var first_button: Button = null
	for hero_id in HeroDef.ORDER:
		var def := HeroDef.get_def(hero_id)
		var btn := UiKit.button("%s" % def["name"], func(): pass, 22)
		btn.add_theme_color_override("font_color", def["color"])
		btn.add_theme_color_override("font_hover_color", Palette.glow(def["color"], 1.2))
		btn.add_theme_color_override("font_focus_color", Palette.glow(def["color"], 1.2))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(195, 0)
		var id: String = hero_id
		btn.focus_entered.connect(func(): _select(id))
		btn.mouse_entered.connect(func(): _select(id))
		btn.pressed.connect(func(): _select(id))
		grid.add_child(btn)
		if first_button == null:
			first_button = btn

	list.add_child(UiKit.spacer(14))
	var try_btn := UiKit.button("▶  Kokeile tätä sankaria", func(): Game.try_hero(_selected), 24)
	try_btn.custom_minimum_size = Vector2(400, 0)
	try_btn.add_theme_color_override("font_color", Palette.GOLD)
	try_btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
	try_btn.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	list.add_child(try_btn)
	var back_btn := UiKit.button("Takaisin", func(): Game.go_menu(), 24)
	back_btn.custom_minimum_size = Vector2(400, 0)
	list.add_child(back_btn)

	# Oikea palsta: tietopaneeli
	_detail_holder = UiKit.panel(Vector2(1150, 640))
	_detail_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_detail_holder)

	_select(HeroDef.ORDER[0])
	first_button.call_deferred("grab_focus")


func _select(hero_id: String) -> void:
	if hero_id == _selected:
		return
	_selected = hero_id
	AudioMgr.play("ui_move", 0.05, -6.0)
	for child in _detail_holder.get_children():
		_detail_holder.remove_child(child)
		child.queue_free()

	var def := HeroDef.get_def(hero_id)
	var content := UiKit.hbox(34)
	_detail_holder.add_child(content)

	# Vasemmalla iso medaljonki ja tilastopalkit
	var left := UiKit.vbox(12)
	left.custom_minimum_size = Vector2(220, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(left)

	var medallion := Medallion.new()
	medallion.hero_id = hero_id
	medallion.custom_minimum_size = Vector2(190, 190)
	medallion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(medallion)

	var stars := ""
	for i in range(3):
		stars += "★" if i < int(def["difficulty"]) else "☆"
	var role_label := UiKit.label("%s  %s" % [def["role"], stars], 24, def["color"])
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(role_label)
	left.add_child(UiKit.spacer(4))

	for stat_name in ["kesto", "liike", "vahinko", "tuki"]:
		var stat_row := UiKit.hbox(10)
		var stat_label := UiKit.dim_label(stat_name.capitalize(), 18)
		stat_label.custom_minimum_size = Vector2(90, 0)
		stat_row.add_child(stat_label)
		var bar := RatingBar.new()
		bar.value = int(def["ratings"][stat_name])
		bar.color = def["color"]
		bar.custom_minimum_size = Vector2(120, 20)
		stat_row.add_child(bar)
		left.add_child(stat_row)

	# Oikealla nimi, kuvaus ja kyvyt
	var right := UiKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)

	right.add_child(UiKit.label(def["name"], 46, def["color"]))
	var desc := UiKit.dim_label("%s — %s" % [def["weapon"], def["desc"]], 21)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(800, 0)
	right.add_child(desc)
	right.add_child(UiKit.spacer(10))

	var slot_keys := [
		["basic", "R2 / hiiren vasen"],
		["a1", "R1 / hiiren oikea"],
		["a2", "L1 / Q"],
		["dodge", "X / välilyönti"],
		["ult", "△ / E"],
	]
	for entry in slot_keys:
		var ability: Dictionary = def["abilities"][entry[0]]
		var ability_row := UiKit.hbox(14)
		var name_label := UiKit.label(ability["name"], 22, Palette.TEXT_MAIN)
		name_label.custom_minimum_size = Vector2(250, 0)
		ability_row.add_child(name_label)
		var key_label := UiKit.dim_label(str(entry[1]), 15)
		key_label.custom_minimum_size = Vector2(170, 0)
		ability_row.add_child(key_label)
		right.add_child(ability_row)
		var ability_desc := UiKit.dim_label(ability["desc"], 17)
		ability_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ability_desc.custom_minimum_size = Vector2(800, 0)
		right.add_child(ability_desc)
		right.add_child(UiKit.spacer(2))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()


## Pyöreä sankarikuvake.
class Medallion:
	extends Control

	var hero_id := ""

	func _draw() -> void:
		var def := HeroDef.get_def(hero_id)
		var center := size / 2.0
		var r: float = minf(size.x, size.y) / 2.0 - 6.0
		draw_circle(center, r + 6.0, Palette.darker(def["color_b"], 0.55))
		draw_circle(center, r, def["color"])
		draw_circle(center + Vector2(0, r * 0.35), r * 0.7,
			Palette.with_alpha(def["color_b"], 0.35))
		HeroIcon.draw_symbol(self, hero_id, center, r * 0.62)


## Viisiportainen tilastopalkki.
class RatingBar:
	extends Control

	var value := 3
	var color := Color.WHITE

	func _draw() -> void:
		var cell_w := (size.x - 4.0 * 3.0) / 5.0
		for i in range(5):
			var rect := Rect2(i * (cell_w + 3.0), 0, cell_w, size.y)
			if i < value:
				draw_rect(rect, color)
			else:
				draw_rect(rect, Color(0, 0, 0, 0.45))
