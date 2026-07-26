class_name UserSelect
extends Control
## Ranked-tilan käyttäjävalinta: samalla koneella voi olla useita pelaajatilejä,
## joista jokainen kiipeää omaa tikapuutaan. Tässä luodaan, nimetään, poistetaan
## ja valitaan aktiivinen tili.
##
## TOIMINNALLINEN POHJA — Phase B korvaa ulkoasun (tier-tunnukset, tikapuunäkymä
## ja ylennysanimaatiot). Rakenne noudattaa talon tapaa: kaikki koodissa,
## UiKitin napit ja ohjainystävällinen fokusnavigaatio. Nimen voi joko kirjoittaa
## tai poimia arvotuista ehdotuksista, jotta pelin voi aloittaa pelkällä
## ohjaimella ilman näppäimistöä.

const SUGGESTIONS := 6

var _selected_id := ""
var _root: MarginContainer = null
var _overlay: Control = null
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("menu")
	AudioMgr.play("ui_open", 0.02, -4.0)
	var backdrop := MenuBackdrop.new()
	backdrop.team_glow = true
	add_child(backdrop)
	_selected_id = RankedDB.active_user_id()
	_rebuild()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# --- Näkymän rakentaminen ---

## Koko näkymä rakennetaan uudelleen jokaisen muutoksen jälkeen: yksinkertaista
## ja varmaa, ja lista on aina synkassa tallennuksen kanssa.
func _rebuild() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("margin_left", 150)
	_root.add_theme_constant_override("margin_right", 150)
	_root.add_theme_constant_override("margin_top", 40)
	_root.add_theme_constant_override("margin_bottom", 40)
	add_child(_root)

	var page := UiKit.vbox(10)
	_root.add_child(page)
	page.add_child(UiKit.title("RANKED — VALITSE PELAAJA", 58))
	var subtitle := UiKit.dim_label(
		"Jokainen tili kiipeää omaa tikapuutaan. Sama kone, useampi kiipeäjä.", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(subtitle)
	page.add_child(UiKit.spacer(6))

	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	var list_panel := UiKit.panel(Vector2(880, 560))
	columns.add_child(list_panel)
	var list_box := UiKit.vbox(8)
	list_panel.add_child(list_box)
	list_box.add_child(UiKit.label("PELAAJATILIT", 27, Palette.GOLD))

	var users: Array = RankedDB.users()
	var first_button: Button = null
	if users.is_empty():
		list_box.add_child(UiKit.dim_label(
			"Ei vielä yhtään tiliä. Luo ensimmäinen — Wood IV odottaa.", 18))
	for entry in users:
		var user: Dictionary = entry
		var button := _user_button(user)
		list_box.add_child(button)
		if first_button == null:
			first_button = button

	var create_btn := UiKit.button("LUO UUSI PELAAJA", func(): _open_name_dialog(""), 22)
	create_btn.custom_minimum_size = Vector2(820, 50)
	list_box.add_child(create_btn)
	if first_button == null:
		first_button = create_btn

	columns.add_child(_detail_panel())

	page.add_child(UiKit.spacer(4))
	var buttons := UiKit.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(buttons)
	var play_btn := UiKit.button("PELAA RANKED", func(): _play(), 26)
	play_btn.custom_minimum_size = Vector2(430, 56)
	play_btn.add_theme_color_override("font_color", Palette.GOLD)
	play_btn.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
	play_btn.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	play_btn.disabled = _current().is_empty()
	buttons.add_child(play_btn)
	var rename_btn := UiKit.button("NIMEÄ UUDELLEEN", func(): _open_name_dialog(_selected_id), 20)
	rename_btn.custom_minimum_size = Vector2(300, 56)
	rename_btn.disabled = _current().is_empty()
	buttons.add_child(rename_btn)
	var delete_btn := UiKit.button("POISTA", func(): _delete_selected(), 20)
	delete_btn.custom_minimum_size = Vector2(210, 56)
	delete_btn.disabled = _current().is_empty()
	buttons.add_child(delete_btn)
	var back_btn := UiKit.button("TAKAISIN", func(): Game.go_menu(), 20)
	back_btn.custom_minimum_size = Vector2(240, 56)
	buttons.add_child(back_btn)

	var hint := UiKit.dim_label(
		"X/Enter valitsee  •  O/Esc palaa  •  tatti tai ristiohjain liikkuu", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(hint)

	if not _current().is_empty():
		play_btn.call_deferred("grab_focus")
	elif first_button != null:
		first_button.call_deferred("grab_focus")


## Yksi tilirivi: nimi, rank + LP ja voitot/tappiot.
func _user_button(user: Dictionary) -> Button:
	var id: String = str(user.get("id", ""))
	var rank: int = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	var promo: Dictionary = {}
	var promo_raw: Variant = user.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	var label := "%s          %s          %dV / %dH" % [
		str(user.get("name", "?")),
		RankedRules.rank_label(rank, int(user.get("lp", 0)), promo),
		int(user.get("wins", 0)), int(user.get("losses", 0))]
	var button := UiKit.button(label, func(): _select(id), 21)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(820, 52)
	if id == _selected_id:
		button.add_theme_color_override("font_color", Palette.GOLD)
	return button


## Valitun tilin tiedot: rank, putki, huippu ja viimeisimmät ottelut.
func _detail_panel() -> PanelContainer:
	var panel := UiKit.panel(Vector2(560, 560))
	var box := UiKit.vbox(8)
	panel.add_child(box)
	var user: Dictionary = _current()
	if user.is_empty():
		box.add_child(UiKit.label("EI VALINTAA", 27, Palette.GOLD))
		box.add_child(UiKit.dim_label(
			"Valitse tili listalta tai luo uusi aloittaaksesi kiipeämisen.", 17))
		return panel

	var rank: int = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	var promo: Dictionary = {}
	var promo_raw: Variant = user.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	box.add_child(UiKit.label(str(user.get("name", "?")), 34, Palette.GOLD))
	box.add_child(UiKit.label(BotRank.rank_name(rank), 44, Palette.TEXT_MAIN))
	if RankedRules.promo_active(promo):
		box.add_child(UiKit.label("PROMO-SARJA %s — paras kolmesta" %
			RankedRules.promo_score(promo), 20, Palette.GOOD))
		box.add_child(UiKit.dim_label("Vastassa %s — voita kaksi ja tier vaihtuu." %
			BotRank.rank_name(RankedRules.promo_band(rank)), 16))
	else:
		box.add_child(UiKit.label("%d / 100 LP" % int(user.get("lp", 0)), 24, Palette.GOOD))
	box.add_child(UiKit.spacer(6))

	var wins: int = int(user.get("wins", 0))
	var losses: int = int(user.get("losses", 0))
	box.add_child(UiKit.dim_label("Otteluita %d  •  %d voittoa, %d tappiota" %
		[wins + losses, wins, losses], 17))
	box.add_child(UiKit.dim_label("Korkein saavutettu: %s" %
		BotRank.rank_name(int(user.get("peak_rank", rank))), 17))
	var streak: int = int(user.get("streak", 0))
	var streak_text := "Ei putkea käynnissä"
	if streak > 0:
		streak_text = "Voittoputki: %d" % streak
	elif streak < 0:
		streak_text = "Tappioputki: %d" % absi(streak)
	box.add_child(UiKit.dim_label(streak_text, 17))
	box.add_child(UiKit.spacer(6))

	box.add_child(UiKit.label("VIIMEISIMMÄT", 20, Palette.GOLD))
	var history: Array = []
	var history_raw: Variant = user.get("history", [])
	if history_raw is Array:
		history = history_raw
	if history.is_empty():
		box.add_child(UiKit.dim_label("Ei vielä otteluita.", 16))
	var shown := 0
	for i in range(history.size() - 1, -1, -1):
		if shown >= 6:
			break
		var row: Dictionary = history[i]
		var won: bool = bool(row.get("win", false))
		var delta: int = int(row.get("delta", 0))
		var text := "%s   %+d LP   →   %s %d LP" % [
			"VOITTO" if won else "TAPPIO", delta,
			BotRank.rank_name(int(row.get("rank", 0))), int(row.get("lp", 0))]
		box.add_child(UiKit.label(text, 16, Palette.GOOD if won else Palette.BAD))
		shown += 1
	return panel


# --- Toiminnot ---

func _current() -> Dictionary:
	return RankedDB.get_user(_selected_id)


func _select(id: String) -> void:
	_selected_id = id
	RankedDB.set_active_user(id)
	_rebuild()


func _play() -> void:
	var user: Dictionary = _current()
	if user.is_empty():
		AudioMgr.play("ui_deny")
		return
	Game.start_ranked(_selected_id)


func _delete_selected() -> void:
	var user: Dictionary = _current()
	if user.is_empty():
		AudioMgr.play("ui_deny")
		return
	RankedDB.delete_user(_selected_id)
	_selected_id = RankedDB.active_user_id()
	AudioMgr.play("ui_back")
	_rebuild()


# --- Nimen syöttö ---

## Nimidialogi. Tyhjä user_id = uusi tili, muuten uudelleennimeäminen.
## Nimen voi kirjoittaa tai poimia arvotuista ehdotuksista (ohjainpeli ilman
## näppäimistöä).
func _open_name_dialog(user_id: String) -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	AudioMgr.play("ui_open", 0.02, -2.0)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 100

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := UiKit.fullscreen_center(_overlay)
	var panel := UiKit.panel(Vector2(900, 620))
	center.add_child(panel)
	var box := UiKit.vbox(12)
	panel.add_child(box)

	var is_new: bool = user_id == ""
	box.add_child(UiKit.title("UUSI PELAAJA" if is_new else "NIMEÄ UUDELLEEN", 42))
	var help := UiKit.dim_label(
		"Kirjoita nimi tai poimi ehdotus alta. Nimeä voi vaihtaa myöhemmin.", 17)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)

	var edit := UiKit.line_edit("PELAAJAN NIMI", RankedDB.NAME_MAX, 30)
	edit.custom_minimum_size = Vector2(820, 56)
	if not is_new:
		var user: Dictionary = RankedDB.get_user(user_id)
		edit.text = str(user.get("name", ""))
	box.add_child(edit)
	box.add_child(UiKit.spacer(4))

	box.add_child(UiKit.label("EHDOTUKSIA", 22, Palette.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	_fill_suggestions(grid, edit)

	box.add_child(UiKit.spacer(4))
	var buttons := UiKit.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var shuffle_btn := UiKit.button("ARVO UUDET", func(): _fill_suggestions(grid, edit), 20)
	shuffle_btn.custom_minimum_size = Vector2(260, 52)
	buttons.add_child(shuffle_btn)
	var confirm_btn := UiKit.button("VAHVISTA", func(): _confirm_name(user_id, edit.text), 22)
	confirm_btn.custom_minimum_size = Vector2(300, 52)
	confirm_btn.add_theme_color_override("font_color", Palette.GOLD)
	buttons.add_child(confirm_btn)
	var cancel_btn := UiKit.button("PERUUTA", func(): _close_dialog(), 20)
	cancel_btn.custom_minimum_size = Vector2(240, 52)
	buttons.add_child(cancel_btn)

	add_child(_overlay)
	confirm_btn.call_deferred("grab_focus")


## Täyttää ehdotusruudukon tuoreilla nimillä (sama generaattori kuin boteilla).
func _fill_suggestions(grid: GridContainer, edit: LineEdit) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for entry in BotNames.suggestions(SUGGESTIONS):
		var suggestion: String = str(entry)
		var button := UiKit.button(suggestion, func(): edit.text = suggestion, 19)
		button.custom_minimum_size = Vector2(260, 46)
		grid.add_child(button)


func _confirm_name(user_id: String, raw_name: String) -> void:
	var clean := raw_name.strip_edges()
	if clean == "":
		AudioMgr.play("ui_deny")
		return
	if user_id == "":
		var user: Dictionary = RankedDB.create_user(clean)
		_selected_id = str(user.get("id", ""))
	else:
		RankedDB.rename_user(user_id, clean)
		_selected_id = user_id
	RankedDB.set_active_user(_selected_id)
	AudioMgr.play("ui_lock")
	_close_dialog()
	_rebuild()


func _close_dialog() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	_overlay.queue_free()
	_overlay = null
	AudioMgr.play("ui_back")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _overlay != null and is_instance_valid(_overlay):
		_close_dialog()
	else:
		AudioMgr.play("ui_back")
		Game.go_menu()


# --- Tausta ---

func _draw() -> void:
	# Kevyt kultahehku otsikon taakse — Phase B tuo tier-taiteen tilalle.
	var pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(Vector2(960, 90), 300.0, Palette.with_alpha(Palette.GOLD, 0.04 + pulse * 0.02))
