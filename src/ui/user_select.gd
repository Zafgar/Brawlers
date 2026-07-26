class_name UserSelect
extends Control
## Ranked-tilan käyttäjävalinta: samalla koneella voi olla useita pelaajatilejä,
## joista jokainen kiipeää omaa tikapuutaan. Tässä luodaan, nimetään, poistetaan
## ja valitaan aktiivinen tili.
##
## Jokainen tili näkyy omana korttinaan: tason tunnus, nimi, sarjamerkki,
## LP-palkki (tai kesken oleva promootiosarja) ja ottelusaldo. Kortit ovat
## oikeita nappeja, jotta ohjainnavigaatio toimii talon tapaan — koristelu
## piirretään nappien PÄÄLLE omalla läpinäkyvällä kerroksella.
##
## Nimen voi joko kirjoittaa tai poimia arvotuista ehdotuksista, jotta pelin voi
## aloittaa pelkällä ohjaimella ilman näppäimistöä.

const SUGGESTIONS := 6
const ROW_W := 820.0
const ROW_H := 78.0

var _selected_id := ""
var _root: MarginContainer = null
var _deco: Control = null            # koristekerros nappien päällä
var _overlay: Control = null
var _rows: Array = []                # [{button, user}]
var _detail: PanelContainer = null
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
	if _deco != null and is_instance_valid(_deco):
		_deco.queue_redraw()


# --- Näkymän rakentaminen ---

## Koko näkymä rakennetaan uudelleen jokaisen muutoksen jälkeen: yksinkertaista
## ja varmaa, ja lista on aina synkassa tallennuksen kanssa.
func _rebuild() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	if _deco != null and is_instance_valid(_deco):
		remove_child(_deco)
		_deco.queue_free()
	_rows = []
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
	create_btn.custom_minimum_size = Vector2(ROW_W, 50)
	list_box.add_child(create_btn)
	if first_button == null:
		first_button = create_btn

	_detail = _detail_panel()
	columns.add_child(_detail)

	page.add_child(UiKit.spacer(4))
	var buttons := UiKit.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(buttons)
	var play_btn := UiKit.button("VALITSE JA JATKA", func(): _confirm(), 26)
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

	# Koristekerros lisätään VIIMEISENÄ, jotta se piirtyy nappien päälle.
	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_decorations)
	add_child(_deco)

	if not _current().is_empty():
		play_btn.call_deferred("grab_focus")
	elif first_button != null:
		first_button.call_deferred("grab_focus")


## Yksi tilirivi. Nappi on tarkoituksella tyhjä: sisältö piirretään
## koristekerroksessa, jolloin tunnukset ja palkit mahtuvat riville.
func _user_button(user: Dictionary) -> Button:
	var id: String = str(user.get("id", ""))
	var button := UiKit.button("", func(): _select(id), 21)
	button.custom_minimum_size = Vector2(ROW_W, ROW_H)
	_rows.append({"button": button, "user": user})
	return button


## Valitun tilin tiedot: iso tunnus, rank, putki, huippu ja viimeisimmät ottelut.
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
	# Tila isolle tunnukselle, joka piirretään koristekerroksessa.
	box.add_child(UiKit.spacer(210))
	var name_label := UiKit.label(str(user.get("name", "?")), 32, Palette.GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var rank_label := UiKit.label(BotRank.rank_name(rank), 40, BotRank.rank_color(rank))
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rank_label)
	if RankedRules.promo_active(promo):
		var promo_label := UiKit.label("PROMOOTIOSARJA %s — paras kolmesta" %
			RankedRules.promo_score(promo), 19, Palette.GOOD)
		promo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(promo_label)
		box.add_child(UiKit.dim_label("Vastassa %s — voita kaksi ja taso vaihtuu." %
			BotRank.rank_name(RankedRules.promo_band(rank)), 15))
	else:
		var lp_label := UiKit.label("%d / %d LP" %
			[int(user.get("lp", 0)), RankedRules.LP_MAX], 22, Palette.GOOD)
		lp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lp_label)

	var wins: int = int(user.get("wins", 0))
	var losses: int = int(user.get("losses", 0))
	box.add_child(UiKit.dim_label("Otteluita %d  •  %d voittoa, %d tappiota" %
		[wins + losses, wins, losses], 16))
	box.add_child(UiKit.dim_label("Korkein saavutettu: %s" %
		BotRank.rank_name(int(user.get("peak_rank", rank))), 16))
	var streak: int = int(user.get("streak", 0))
	var streak_text := "Ei putkea käynnissä"
	if streak > 0:
		streak_text = "Voittoputki: %d" % streak
	elif streak < 0:
		streak_text = "Tappioputki: %d" % absi(streak)
	box.add_child(UiKit.dim_label(streak_text, 16))

	box.add_child(UiKit.label("VIIMEISIMMÄT", 19, Palette.GOLD))
	var history: Array = []
	var history_raw: Variant = user.get("history", [])
	if history_raw is Array:
		history = history_raw
	if history.is_empty():
		box.add_child(UiKit.dim_label("Ei vielä otteluita.", 15))
	var shown := 0
	for i in range(history.size() - 1, -1, -1):
		if shown >= 4:
			break
		var row: Dictionary = history[i]
		var won: bool = bool(row.get("win", false))
		var delta: int = int(row.get("delta", 0))
		var text := "%s   %+d LP   →   %s %d LP" % [
			"VOITTO" if won else "TAPPIO", delta,
			BotRank.rank_name(int(row.get("rank", 0))), int(row.get("lp", 0))]
		box.add_child(UiKit.label(text, 15, Palette.GOOD if won else Palette.BAD))
		shown += 1
	return panel


# --- Koristekerros ---

func _card(canvas: CanvasItem, rect: Rect2, bg: Color, border: Color, bw: float,
		radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(maxf(bw, 0.0)))
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.draw(canvas.get_canvas_item(), rect)


## Piirtää tilikorttien sisällön ja valitun tilin ison tunnuksen nappien päälle.
func _draw_decorations() -> void:
	if _deco == null or not is_instance_valid(_deco):
		return
	for entry in _rows:
		var row: Dictionary = entry
		var button: Button = row.get("button")
		if button == null or not is_instance_valid(button) or button.size.x < 40.0:
			continue
		var user: Dictionary = {}
		var user_raw: Variant = row.get("user", {})
		if user_raw is Dictionary:
			user = user_raw
		_draw_user_row(_deco, button.get_global_rect(), user)
	_draw_detail_emblem(_deco)


func _draw_user_row(canvas: CanvasItem, rect: Rect2, user: Dictionary) -> void:
	if user.is_empty():
		return
	var id: String = str(user.get("id", ""))
	var rank: int = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	var tint: Color = BotRank.rank_color(rank)
	var selected: bool = id == _selected_id
	var cy: float = rect.get_center().y

	if selected:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
		_card(canvas, rect, Palette.with_alpha(Palette.GOLD, 0.10),
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.2), 0.55 + pulse * 0.3), 3, 14)

	RankEmblem.draw(canvas, rank, Vector2(rect.position.x + 54.0, cy - 2.0), 24.0, _time)
	UiKit.draw_text(canvas, Vector2(rect.position.x + 100.0, cy - 17.0),
		str(user.get("name", "?")), 24, Palette.GOLD if selected else Palette.TEXT_MAIN,
		false, 2)
	RankEmblem.draw_chip(canvas, rank, Vector2(rect.position.x + 100.0, cy + 16.0), 24.0, _time)

	# LP-palkki tai kesken oleva promootiosarja.
	var promo: Dictionary = {}
	var promo_raw: Variant = user.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	var bar_x: float = rect.position.x + 386.0
	if RankedRules.promo_active(promo):
		UiKit.draw_text(canvas, Vector2(bar_x, cy - 16.0),
			"PROMOOTIOSARJA %s" % RankedRules.promo_score(promo), 16, Palette.GOLD, false)
		var games: Array = []
		var games_raw: Variant = promo.get("games", [])
		if games_raw is Array:
			games = games_raw
		for i in range(3):
			var pos := Vector2(bar_x + 12.0 + float(i) * 30.0, cy + 14.0)
			var played: bool = i < games.size()
			var won: bool = played and bool(games[i])
			var col: Color = Palette.TEXT_DIM
			if played:
				col = Palette.GOLD if won else Palette.BAD
			canvas.draw_circle(pos, 10.0, Palette.with_alpha(col, 0.20))
			canvas.draw_arc(pos, 10.0, 0.0, TAU, 18, Palette.with_alpha(col, 0.9), 2.0)
			if played:
				canvas.draw_circle(pos, 5.0, col)
	else:
		var bar := Rect2(bar_x, cy - 16.0, 250.0, 16.0)
		_card(canvas, bar, Color(0.02, 0.03, 0.07, 0.9),
			Palette.with_alpha(tint, 0.5), 1, 8)
		var f: float = clampf(float(int(user.get("lp", 0))) / float(RankedRules.LP_MAX),
			0.0, 1.0)
		if f > 0.01:
			_card(canvas, Rect2(bar.position.x + 2.0, bar.position.y + 2.0,
				(bar.size.x - 4.0) * f, bar.size.y - 4.0),
				Palette.glow(tint, 1.2), Color(0, 0, 0, 0), 0, 6)
		UiKit.draw_text(canvas, Vector2(bar_x, cy + 16.0),
			"%d / %d LP" % [int(user.get("lp", 0)), RankedRules.LP_MAX], 15,
			Palette.TEXT_DIM, false)

	var wins: int = int(user.get("wins", 0))
	var losses: int = int(user.get("losses", 0))
	UiKit.draw_text(canvas, Vector2(rect.end.x - 96.0, cy - 15.0),
		"%d V / %d H" % [wins, losses], 19, Palette.TEXT_MAIN, true, 2)
	var streak: int = int(user.get("streak", 0))
	var streak_text: String = "—"
	var streak_col: Color = Palette.TEXT_DIM
	if streak > 0:
		streak_text = "putki %d" % streak
		streak_col = Palette.GOOD
	elif streak < 0:
		streak_text = "putki -%d" % absi(streak)
		streak_col = Palette.BAD
	UiKit.draw_text(canvas, Vector2(rect.end.x - 96.0, cy + 16.0), streak_text, 15,
		streak_col, true)
	if selected:
		UiKit.draw_text(canvas, Vector2(rect.end.x - 22.0, cy), "★", 22, Palette.GOLD, true)


## Valitun tilin iso tunnus tietopaneelin yläosaan.
func _draw_detail_emblem(canvas: CanvasItem) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	var user: Dictionary = _current()
	if user.is_empty():
		return
	var rect: Rect2 = _detail.get_global_rect()
	if rect.size.x < 80.0:
		return
	var rank: int = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	var center := Vector2(rect.get_center().x, rect.position.y + 118.0)
	canvas.draw_circle(center, 150.0, Palette.with_alpha(BotRank.rank_color(rank), 0.06))
	RankEmblem.draw(canvas, rank, center, 76.0, _time)


# --- Toiminnot ---

func _current() -> Dictionary:
	return RankedDB.get_user(_selected_id)


func _select(id: String) -> void:
	_selected_id = id
	RankedDB.set_active_user(id)
	_rebuild()


## Valinta vahvistetaan ja siirrytään ranked-aulaan, josta ottelu käynnistyy.
func _confirm() -> void:
	var user: Dictionary = _current()
	if user.is_empty():
		AudioMgr.play("ui_deny")
		return
	RankedDB.set_active_user(_selected_id)
	Game.go_ranked_hub()


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
	# Valitun tilin tason värinen hehku otsikon taakse.
	var user: Dictionary = _current()
	var tint: Color = Palette.GOLD
	if not user.is_empty():
		tint = BotRank.rank_color(clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK))
	var pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(Vector2(960, 90), 320.0, Palette.with_alpha(tint, 0.05 + pulse * 0.025))
