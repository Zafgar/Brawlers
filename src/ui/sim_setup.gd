class_name SimSetup
extends Control
## Simulaation asetukset: aja bot vs bot -otteluita MOBA-kartalla ja kerää
## telemetria tekoälyn ja tasapainon kehitykseen. Käyttää MatchSetupin
## OptionRow-rivejä.
##
## Kaksi tilaa:
##   Manuaali — N ottelua satunnaisilla/peilatuilla kokoonpanoilla.
##   Sweep    — käy läpi kaikki kokoonpanotyyppien parit (täysvahinko, täystuki,
##              täystankki, kaukotaisto, sukellus, tasapaino) toistoineen.

var _team_size := 4       # Projektin virallinen ja ainoa ottelumuoto
# Oletustaso 5 (Mestari): paras EI-huijaava taso. Tasapainon mittaamiseen
# halutaan korkea, puhdas taso — taso 6 (Epäreilu) huijaa (enemmän vahinkoa,
# vähemmän otettua) ja vääristäisi tulokset.
var _blue_level := 4
var _orange_level := 4
var _comp := 0            # 0 = satunnainen, 1 = peilattu
var _count := 3
var _speed := 32
var _show_visuals := false
var _sweep := false
var _repeats := 1

const COUNTS := [1, 3, 5, 10]
const SPEEDS := [4, 8, 16, 32, 64]
const REPEATS := [1, 2, 3]

var _note: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("lobby")
	AudioMgr.play("ui_open")
	add_child(MenuBackdrop.new())

	var center := UiKit.fullscreen_center(self)
	var box := UiKit.vbox(8)
	center.add_child(box)

	box.add_child(UiKit.title("MOBA-SIMULAATIOLABRA", 60))
	box.add_child(UiKit.dim_label(
		"Aja 4v4-botit Eternal Dividella ja analysoi roolit, resurssit ja tavoitteet.", 20))
	box.add_child(UiKit.spacer(18))

	var panel := UiKit.panel()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(panel)
	var inner := UiKit.vbox(12)
	panel.add_child(inner)

	_add(inner, MatchSetup.OptionRow.new("Tila", ["Manuaali", "Sweep (kaikki tyypit)"],
		0, func(i): _sweep = i == 1; _update_note()))
	var format_row := MatchSetup.OptionRow.new("Virallinen formaatti", ["4v4 MOBA"], 0, Callable())
	format_row.locked = true
	_add(inner, format_row)
	_add(inner, MatchSetup.OptionRow.new("Sininen taso", Game.BOT_LEVEL_NAMES,
		_blue_level, func(i): _blue_level = i))
	_add(inner, MatchSetup.OptionRow.new("Oranssi taso", Game.BOT_LEVEL_NAMES,
		_orange_level, func(i): _orange_level = i))
	_add(inner, MatchSetup.OptionRow.new("Kokoonpanot (vain manuaali)", ["Satunnainen", "Peilattu"],
		_comp, func(i): _comp = i))
	_add(inner, MatchSetup.OptionRow.new("Otteluita (vain manuaali)", ["1", "3", "5", "10"],
		1, func(i): _count = COUNTS[i]; _update_note()))
	_add(inner, MatchSetup.OptionRow.new("Sweep-toistot (per tyyppipari)", ["1", "2", "3"],
		0, func(i): _repeats = REPEATS[i]; _update_note()))
	_add(inner, MatchSetup.OptionRow.new("Nopeus",
		["4x", "8x", "16x", "32x (suositus)", "64x (tehokone)"],
		3, func(i): _speed = SPEEDS[i]; _update_note()))
	_add(inner, MatchSetup.OptionRow.new("Näkymä",
		["Turbo (ei taisteluvisuaaleja)", "Näytä ottelut"],
		0, func(i): _show_visuals = i == 1; _update_note()))

	box.add_child(UiKit.spacer(18))
	var run_btn := UiKit.button("▶  AJA 4V4-SIMULAATIO", _run)
	run_btn.custom_minimum_size = Vector2(560, 56)
	run_btn.add_theme_color_override("font_color", Palette.GOLD)
	run_btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
	box.add_child(run_btn)
	var back_btn := UiKit.button("TAKAISIN PÄÄVALIKKOON", func(): Game.go_menu(), 24)
	back_btn.custom_minimum_size = Vector2(560, 0)
	box.add_child(back_btn)
	box.add_child(UiKit.spacer(6))
	_note = UiKit.dim_label("", 16)
	box.add_child(_note)
	_update_note()


func _update_note() -> void:
	if _note == null:
		return
	var cheat := " · HUOM: taso 6 (Epäreilu) huijaa — käytä tasapainotestiin sama, ei-huijaava taso molemmilla."
	var view_note := "Turbo: efektit ja taistelun piirto pois" if not _show_visuals \
		else "ottelut piirretään ruudulle"
	var speed_note := " · 64x vaatii paljon prosessorilta; 32x on yleensä tasaisin." \
		if _speed >= 64 else ""
	if _sweep:
		var pairs: int = 36                       # 6 tyyppiä × 6
		var total: int = pairs * _repeats
		_note.text = ("Sweep: %d tyyppiparia × %d toistoa = %d ottelua %dv%d, %dx. "
			+ "%s. Raportti tallentuu ja tulostuu konsoliin.%s%s") % [
			pairs, _repeats, total, _team_size, _team_size, _speed,
			view_note, speed_note, cheat]
	else:
		_note.text = ("Manuaali: %d ottelua %dv%d, %dx. %s. "
			+ "Raportti tallentuu ja tulostuu konsoliin.%s%s") % [
			_count, _team_size, _team_size, _speed, view_note, speed_note, cheat]


func _add(parent: Control, row: Control) -> void:
	row.custom_minimum_size = Vector2(760, 0)
	parent.add_child(row)


func _run() -> void:
	AudioMgr.play("ui_ok")
	var runner := SimRunner.new()
	runner.team_size = _team_size
	runner.blue_level = _blue_level
	runner.orange_level = _orange_level
	runner.comp_mode = _comp
	runner.match_count = _count
	runner.speed = _speed
	runner.show_visuals = _show_visuals
	runner.sweep = _sweep
	runner.repeats = _repeats
	runner.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()
