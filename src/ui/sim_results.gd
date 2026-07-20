class_name SimResults
extends Control
## Näyttää simulaatioraportin, tallentaa sen tiedostoon (user://sim_report.txt)
## ja tulostaa konsoliin. Raportin voi kopioida ja liittää kehittäjälle.

var report_text := ""

const SAVE_PATH := "user://sim_report.txt"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("lobby")
	add_child(MenuBackdrop.new())

	# Tallenna tiedostoon ja tulosta konsoliin. Näytetään OIKEA absoluuttinen
	# polku (globalize_path) — "user://" on virtuaalipolku jota ei löydä käsin.
	var abs_path := ProjectSettings.globalize_path(SAVE_PATH)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(report_text)
		f.close()
	print("\n===== SIMULAATIORAPORTTI =====")
	print("Tallennettu: %s" % abs_path)
	print("(Editorissa: Project -> Open User Data Folder)\n")
	print(report_text + "\n")

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40.0
	root.offset_right = -40.0
	root.offset_top = 28.0
	root.offset_bottom = -28.0
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(UiKit.title("RAPORTTI", 44))
	var saved := UiKit.dim_label(
		"Tallennettu: %s  ·  myös Godotin konsolissa." % abs_path, 15)
	saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(saved)

	# Vieritettävä raporttinäkymä monospace-fontilla.
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.05, 0.1, 0.92)
	pstyle.set_corner_radius_all(10)
	pstyle.content_margin_left = 16.0
	pstyle.content_margin_right = 16.0
	pstyle.content_margin_top = 12.0
	pstyle.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", pstyle)
	root.add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var label := Label.new()
	label.text = report_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Courier New", "Consolas"])
	label.add_theme_font_override("font", mono)
	scroll.add_child(label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	root.add_child(row)
	var copy := UiKit.button("Kopioi raportti", _copy_report, 26)
	copy.custom_minimum_size = Vector2(320, 52)
	row.add_child(copy)
	var again := UiKit.button("Uusi simulaatio", func(): Game.go_sim(), 26)
	again.custom_minimum_size = Vector2(320, 52)
	row.add_child(again)
	var back := UiKit.button("Päävalikkoon", func(): Game.go_menu(), 26)
	back.custom_minimum_size = Vector2(320, 52)
	row.add_child(back)


## Kopioi koko raportti leikepöydälle — ei tarvitse etsiä tiedostoa lainkaan.
func _copy_report() -> void:
	DisplayServer.clipboard_set(report_text)
	AudioMgr.play("ui_ok")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()
