class_name HeroGallery
extends Control
## Sankarigalleria: kaikkien kuuden sankarin roolit, tilastot ja kyvyt.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var box := UiKit.vbox(16)
	margin.add_child(box)

	var title := UiKit.title("SANKARIT", 64)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	for hero_id in HeroDef.ORDER:
		grid.add_child(_hero_card(hero_id))

	var back_btn := UiKit.button("Takaisin", func(): Game.go_menu())
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.custom_minimum_size = Vector2(360, 0)
	box.add_child(back_btn)
	back_btn.call_deferred("grab_focus")


func _hero_card(hero_id: String) -> Control:
	var def := HeroDef.get_def(hero_id)
	var panel := UiKit.panel(Vector2(540, 250))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := UiKit.hbox(16)
	panel.add_child(row)

	# Vasen palsta: medaljonki + tilastopalkit
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(150, 0)
	row.add_child(left)

	var medallion := Medallion.new()
	medallion.hero_id = hero_id
	medallion.custom_minimum_size = Vector2(110, 110)
	medallion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(medallion)

	var stars := ""
	for i in range(3):
		stars += "★" if i < int(def["difficulty"]) else "☆"
	var role_label := UiKit.label("%s  %s" % [def["role"], stars], 18, def["color"])
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(role_label)

	for stat_name in ["kesto", "liike", "vahinko", "tuki"]:
		var stat_row := UiKit.hbox(6)
		var stat_label := UiKit.dim_label(stat_name.capitalize(), 13)
		stat_label.custom_minimum_size = Vector2(62, 0)
		stat_row.add_child(stat_label)
		var bar := RatingBar.new()
		bar.value = int(def["ratings"][stat_name])
		bar.color = def["color"]
		bar.custom_minimum_size = Vector2(76, 14)
		stat_row.add_child(bar)
		left.add_child(stat_row)

	# Oikea palsta: nimi, ase, kuvaus, kyvyt
	var right := UiKit.vbox(3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	right.add_child(UiKit.label(def["name"], 30, def["color"]))
	right.add_child(UiKit.dim_label("%s — %s" % [def["weapon"], def["desc"]], 14))
	right.add_child(UiKit.spacer(4))

	var slot_keys := [
		["basic", "R2 / hiiri vasen"],
		["a1", "R1 / hiiri oikea"],
		["a2", "L1 / Q"],
		["dodge", "X / välilyönti"],
		["ult", "△ / E"],
	]
	for entry in slot_keys:
		var ability: Dictionary = def["abilities"][entry[0]]
		var line := UiKit.label("%s  —  %s" % [ability["name"], ability["desc"]], 13,
			Palette.TEXT_MAIN)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(line)
		var key_hint := UiKit.dim_label("      %s" % entry[1], 11)
		right.add_child(key_hint)

	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()


## Pyöreä sankarikuvake gallerian kortteihin.
class Medallion:
	extends Control

	var hero_id := ""

	func _draw() -> void:
		var def := HeroDef.get_def(hero_id)
		var center := size / 2.0
		var r: float = minf(size.x, size.y) / 2.0 - 4.0
		draw_circle(center, r + 4.0, Palette.darker(def["color_b"], 0.55))
		draw_circle(center, r, def["color"])
		draw_circle(center + Vector2(0, r * 0.35), r * 0.7,
			Palette.with_alpha(def["color_b"], 0.35))
		UiKit.draw_text(self, center + Vector2(0, 2), def["name"].substr(0, 1),
			int(r * 1.1), Color.WHITE, true, 4)


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
