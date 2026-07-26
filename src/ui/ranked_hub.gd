class_name RankedHub
extends Control
## Ranked-tilan aula: pelin varsinainen kotinäkymä. Täällä nähdään oma tunnus
## isona, LP:n eteneminen, ottelusaldo, putki, huippurank ja viimeisimmät
## ottelut — sekä TIKAPUUT eli nimetyt kilpakumppanit oman sijoituksen
## ympäriltä. Kiipeäminen on pelin suola, joten seuraavaksi ohitettava nimi
## nostetaan omalla merkinnällään esiin.
##
## Kaikki piirretään koodilla; napit ovat lapsisolmuja jotta ohjainnavigointi
## toimii talon tapaan.

const LADDER_ROWS := 11              # näkyvät tikapuurivit (oma sijoitus keskellä)
const HISTORY_SHOWN := 10            # viimeisten otteluiden merkit
const ROW_H := 56.0
const PANEL_L := Rect2(90, 170, 740, 620)
const PANEL_H := Rect2(90, 802, 740, 110)
const PANEL_R := Rect2(870, 170, 960, 742)

var _time := 0.0
var _lp_shown := 0.0                 # animoitu LP-palkin täyttö
var _ladder: Array = []              # koko tikapuu (botit + oma tili) järjestettynä
var _my_index := -1                  # oma sijoitus tikapuulla (0 = kärki)
var _top_name := ""
var _top_rank := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("menu")
	AudioMgr.play("rank_hub_open", 0.02, -4.0)
	var backdrop := MenuBackdrop.new()
	backdrop.team_glow = true
	add_child(backdrop)
	_build_ladder()
	_build_buttons()


func _process(delta: float) -> void:
	_time += delta
	var target: float = float(int(_user().get("lp", 0)))
	var before: float = _lp_shown
	_lp_shown = lerpf(_lp_shown, target, clampf(delta * 4.0, 0.0, 1.0))
	# LP-palkin täyttyminen tikittää (rekisterin toistoraja hoitaa tiheyden).
	if absf(_lp_shown - before) > 0.25:
		AudioMgr.play("rank_hub_lp", 0.6, -6.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()


# --- Tiedot ---

func _user() -> Dictionary:
	return RankedDB.active_user()


func _promo() -> Dictionary:
	var promo: Dictionary = {}
	var raw: Variant = _user().get("promo", {})
	if raw is Dictionary:
		promo = raw
	return promo


## Koko tikapuu: bottipopulaatio + oma tili samaan listaan, paras ensin.
## Näin oma sijoitus on aito luku eikä arvio.
func _build_ladder() -> void:
	var user: Dictionary = _user()
	var entries: Array = []
	for entry in RankedDB.ensure_bots():
		var bot: Dictionary = entry
		entries.append({
			"name": str(bot.get("name", "?")),
			"rank": clampi(int(bot.get("rank", 0)), 0, BotRank.MAX_RANK),
			"lp": int(bot.get("lp", 0)), "me": false,
		})
	if not user.is_empty():
		entries.append({
			"name": str(user.get("name", "?")),
			"rank": clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK),
			"lp": int(user.get("lp", 0)), "me": true,
		})
	entries.sort_custom(func(a, b):
		var rank_a: int = int(a.get("rank", 0))
		var rank_b: int = int(b.get("rank", 0))
		if rank_a == rank_b:
			return int(a.get("lp", 0)) > int(b.get("lp", 0))
		return rank_a > rank_b)
	_ladder = entries
	_my_index = -1
	for i in range(entries.size()):
		var row: Dictionary = entries[i]
		if bool(row.get("me", false)):
			_my_index = i
			break
	var top: Array = RankedDB.leaderboard(1)
	if not top.is_empty():
		var best: Dictionary = top[0]
		_top_name = str(best.get("name", ""))
		_top_rank = clampi(int(best.get("rank", 0)), 0, BotRank.MAX_RANK)


# --- Napit ---

func _build_buttons() -> void:
	var row := UiKit.hbox(16)
	row.position = Vector2(960.0 - 530.0, 936.0)
	add_child(row)

	var play := UiKit.button("PELAA RANKED", func(): _play(), 28)
	play.focus_entered.connect(func(): AudioMgr.play("rank_hub_move", 0.05, -8.0))
	play.custom_minimum_size = Vector2(430, 58)
	play.add_theme_color_override("font_color", Palette.GOLD)
	play.add_theme_color_override("font_hover_color", Palette.glow(Palette.GOLD, 1.3))
	play.add_theme_color_override("font_focus_color", Palette.glow(Palette.GOLD, 1.3))
	row.add_child(play)

	var swap := UiKit.button("VAIHDA KÄYTTÄJÄ", func(): Game.go_user_select(), 22)
	swap.custom_minimum_size = Vector2(340, 58)
	row.add_child(swap)

	var back := UiKit.button("TAKAISIN", func(): Game.go_menu(), 22)
	back.custom_minimum_size = Vector2(260, 58)
	row.add_child(back)

	play.call_deferred("grab_focus")


func _play() -> void:
	var user: Dictionary = _user()
	if user.is_empty():
		AudioMgr.play("ui_deny")
		Game.go_user_select()
		return
	AudioMgr.play("rank_hub_confirm", 0.02, -3.0)
	Game.start_ranked(str(user.get("id", "")))


# --- Piirto ---

func _card(rect: Rect2, bg: Color, border: Color, bw: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(maxf(bw, 0.0)))
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.draw(get_canvas_item(), rect)


func _draw() -> void:
	var user: Dictionary = _user()
	if user.is_empty():
		UiKit.draw_text(self, Vector2(960, 500), "EI VALITTUA PELAAJAA", 46,
			Palette.TEXT_DIM, true, 5)
		return
	var rank: int = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	var tint: Color = BotRank.rank_color(rank)

	# Otsikko
	var pulse: float = 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(Vector2(960, 96), 340.0, Palette.with_alpha(tint, 0.05 + pulse * 0.02))
	UiKit.draw_text(self, Vector2(960, 72), "RANKED", 62, Palette.TEXT_MAIN, true, 8)
	UiKit.draw_text(self, Vector2(960, 124),
		"SARJAPELI  •  KIIPEÄ TIKAPUITA  •  VASTASSA NIMETYT HAASTAJAT", 20,
		Palette.GOLD, true)

	_draw_profile(user, rank, tint)
	_draw_history(user)
	_draw_ladder()

	UiKit.draw_text(self, Vector2(960, 1034),
		"X/Enter valitsee  •  O/Esc palaa päävalikkoon  •  tatti tai ristiohjain liikkuu",
		16, Palette.with_alpha(Palette.TEXT_DIM, 0.75), true)


# --- Profiili ---

func _draw_profile(user: Dictionary, rank: int, tint: Color) -> void:
	draw_circle(PANEL_L.get_center(), 380.0, Palette.with_alpha(tint, 0.045))
	_card(PANEL_L, Palette.with_alpha(Palette.UI_PANEL, 0.88),
		Palette.with_alpha(tint, 0.55), 3, 22)
	var cx: float = PANEL_L.get_center().x
	UiKit.draw_text(self, Vector2(cx, PANEL_L.position.y + 34.0),
		str(user.get("name", "?")).to_upper(), 28, Palette.GOLD, true, 3)

	RankEmblem.draw(self, rank, Vector2(cx, PANEL_L.position.y + 208.0), 138.0, _time)

	UiKit.draw_text(self, Vector2(cx, PANEL_L.position.y + 428.0), BotRank.rank_name(rank),
		46, Palette.glow(tint, 1.15), true, 6)

	var promo: Dictionary = _promo()
	if RankedRules.promo_active(promo):
		_draw_promo_card(Vector2(cx, PANEL_L.position.y + 494.0), promo, rank)
	else:
		_draw_lp_bar(Vector2(cx, PANEL_L.position.y + 486.0), 560.0, 38.0, _lp_shown, tint)

	var wins: int = int(user.get("wins", 0))
	var losses: int = int(user.get("losses", 0))
	var games: int = wins + losses
	var winrate: String = "—"
	if games > 0:
		winrate = "%d %%" % int(round(100.0 * float(wins) / float(games)))
	UiKit.draw_text(self, Vector2(cx, PANEL_L.position.y + 540.0),
		"%d ottelua  •  %d voittoa  •  %d tappiota  •  %s" % [games, wins, losses, winrate],
		19, Palette.TEXT_MAIN, true)

	var streak: int = int(user.get("streak", 0))
	var streak_text: String = "Ei putkea käynnissä"
	var streak_col: Color = Palette.TEXT_DIM
	if streak > 0:
		streak_text = "VOITTOPUTKI %d" % streak
		streak_col = Palette.GOOD
	elif streak < 0:
		streak_text = "TAPPIOPUTKI %d" % absi(streak)
		streak_col = Palette.BAD
	UiKit.draw_text(self, Vector2(cx, PANEL_L.position.y + 570.0), streak_text, 20,
		streak_col, true, 2)
	UiKit.draw_text(self, Vector2(cx, PANEL_L.position.y + 598.0),
		"Korkein saavutettu: %s" % BotRank.rank_name(int(user.get("peak_rank", rank))),
		17, Palette.with_alpha(Palette.TEXT_DIM, 0.9), true)


func _draw_lp_bar(center: Vector2, w: float, h: float, value: float, col: Color) -> void:
	var rect := Rect2(center.x - w / 2.0, center.y - h / 2.0, w, h)
	_card(rect, Color(0.02, 0.03, 0.07, 0.9), Palette.with_alpha(col, 0.5), 2, h / 2.0)
	var f: float = clampf(value / float(RankedRules.LP_MAX), 0.0, 1.0)
	if f > 0.004:
		var inner := Rect2(rect.position.x + 4.0, rect.position.y + 4.0,
			(w - 8.0) * f, h - 8.0)
		_card(inner, Palette.glow(col, 1.2), Color(0, 0, 0, 0), 0, (h - 8.0) / 2.0)
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.4)
		draw_circle(Vector2(inner.end.x, rect.get_center().y), h * (0.42 + 0.10 * pulse),
			Palette.with_alpha(Palette.glow(col, 1.5), 0.30))
	UiKit.draw_text(self, center, "%d / %d LP" % [int(round(value)), RankedRules.LP_MAX],
		int(h * 0.52), Palette.TEXT_MAIN, true, 3)


## Kesken oleva promootiosarja: kolme ruutua ja vastustajakaista.
func _draw_promo_card(center: Vector2, promo: Dictionary, rank: int) -> void:
	var target: int = clampi(int(promo.get("target_rank", rank + 1)), 0, BotRank.MAX_RANK)
	var games: Array = []
	var raw: Variant = promo.get("games", [])
	if raw is Array:
		games = raw
	UiKit.draw_text(self, center + Vector2(0, -38.0),
		"PROMOOTIOSARJA %s — PARAS KOLMESTA" % RankedRules.promo_score(promo), 20,
		Palette.GOLD, true, 2)
	var box := 46.0
	var gap := 18.0
	var total: float = 3.0 * box + 2.0 * gap
	for i in range(3):
		var pos := Vector2(center.x - total / 2.0 + box * 0.5 + float(i) * (box + gap),
			center.y + 4.0)
		var played: bool = i < games.size()
		var won: bool = played and bool(games[i])
		var tint: Color = Palette.TEXT_DIM
		if played:
			tint = Palette.GOLD if won else Palette.BAD
		_card(Rect2(pos.x - box / 2.0, pos.y - box / 2.0, box, box),
			Color(0.02, 0.03, 0.08, 0.9), Palette.with_alpha(tint, 0.9), 3, 12)
		if not played:
			continue
		var m := box * 0.26
		if won:
			draw_line(pos + Vector2(-m, 0), pos + Vector2(-m * 0.25, m * 0.72),
				Palette.glow(Palette.GOLD, 1.3), 5.0, true)
			draw_line(pos + Vector2(-m * 0.25, m * 0.72), pos + Vector2(m, -m * 0.7),
				Palette.glow(Palette.GOLD, 1.3), 5.0, true)
		else:
			draw_line(pos + Vector2(-m, -m), pos + Vector2(m, m), Palette.BAD, 5.0, true)
			draw_line(pos + Vector2(m, -m), pos + Vector2(-m, m), Palette.BAD, 5.0, true)
	UiKit.draw_text(self, center + Vector2(0, 48.0),
		"Vastassa %s — voita kaksi ja taso vaihtuu." % BotRank.rank_name(target), 17,
		Palette.TEXT_DIM, true)


# --- Viimeisimmät ottelut ---

func _draw_history(user: Dictionary) -> void:
	_card(PANEL_H, Palette.with_alpha(Palette.UI_PANEL, 0.86),
		Palette.with_alpha(Palette.UI_STROKE, 0.5), 2, 18)
	UiKit.draw_text(self, PANEL_H.position + Vector2(24.0, 26.0), "VIIMEISET OTTELUT", 18,
		Palette.GOLD, false, 2)

	var history: Array = []
	var raw: Variant = user.get("history", [])
	if raw is Array:
		history = raw
	if history.is_empty():
		UiKit.draw_text(self, PANEL_H.get_center() + Vector2(0, 16.0),
			"Ei vielä otteluita — ensimmäinen kiipeäminen odottaa.", 17,
			Palette.TEXT_DIM, true)
		return

	var shown: int = mini(history.size(), HISTORY_SHOWN)
	var gap: float = 68.0
	var x0: float = PANEL_H.get_center().x - gap * (float(shown) - 1.0) / 2.0
	for i in range(shown):
		var row: Dictionary = history[history.size() - shown + i]
		var won: bool = bool(row.get("win", false))
		var delta: int = int(row.get("delta", 0))
		var col: Color = Palette.GOOD if won else Palette.BAD
		var pos := Vector2(x0 + float(i) * gap, PANEL_H.position.y + 62.0)
		draw_circle(pos, 15.0, Palette.with_alpha(col, 0.18))
		draw_circle(pos, 11.0, Palette.with_alpha(col, 0.9))
		UiKit.draw_text(self, pos + Vector2(0, 1.0), "V" if won else "H", 15,
			Palette.TEXT_DARK, true)
		var label: String = "%+d" % delta
		if delta == 0:
			label = "PROMO"
		UiKit.draw_text(self, pos + Vector2(0, 28.0), label, 14,
			Palette.with_alpha(col, 0.85), true)


# --- Tikapuut ---

func _draw_ladder() -> void:
	_card(PANEL_R, Palette.with_alpha(Palette.UI_PANEL, 0.88),
		Palette.with_alpha(Palette.GOLD, 0.45), 3, 22)
	var cx: float = PANEL_R.get_center().x
	UiKit.draw_text(self, Vector2(PANEL_R.position.x + 30.0, PANEL_R.position.y + 36.0),
		"TIKAPUUT", 30, Palette.GOLD, false, 3)
	var total: int = _ladder.size()
	if _my_index >= 0:
		UiKit.draw_text(self, Vector2(PANEL_R.end.x - 30.0, PANEL_R.position.y + 36.0),
			"SIJA %d / %d" % [_my_index + 1, total], 24, Palette.TEXT_MAIN, false, 2)
	if _top_name != "":
		UiKit.draw_text(self, Vector2(PANEL_R.position.x + 30.0, PANEL_R.position.y + 68.0),
			"Kärjessä %s — %s" % [_top_name, BotRank.rank_name(_top_rank)], 16,
			Palette.with_alpha(Palette.TEXT_DIM, 0.9), false)
	draw_line(PANEL_R.position + Vector2(24.0, 86.0),
		Vector2(PANEL_R.end.x - 24.0, PANEL_R.position.y + 86.0),
		Palette.with_alpha(Palette.GOLD, 0.3), 2.0)

	if _ladder.is_empty():
		return
	var start: int = clampi(_my_index - LADDER_ROWS / 2, 0,
		maxi(_ladder.size() - LADDER_ROWS, 0))
	var y: float = PANEL_R.position.y + 100.0
	for i in range(LADDER_ROWS):
		var idx: int = start + i
		if idx >= _ladder.size():
			break
		var row: Dictionary = _ladder[idx]
		var rect := Rect2(PANEL_R.position.x + 20.0, y, PANEL_R.size.x - 40.0, ROW_H - 6.0)
		_draw_ladder_row(rect, row, idx, idx == _my_index,
			_my_index > 0 and idx == _my_index - 1)
		y += ROW_H


func _draw_ladder_row(rect: Rect2, row: Dictionary, place: int, is_me: bool,
		is_target: bool) -> void:
	var rank: int = clampi(int(row.get("rank", 0)), 0, BotRank.MAX_RANK)
	var tint: Color = BotRank.rank_color(rank)
	var cy: float = rect.get_center().y
	if is_me:
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
		_card(rect, Palette.with_alpha(Palette.GOLD, 0.16),
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.2), 0.6 + pulse * 0.3), 3, 12)
	elif is_target:
		_card(rect, Palette.with_alpha(tint, 0.10), Palette.with_alpha(tint, 0.7), 2, 12)
	else:
		_card(rect, Color(0.03, 0.05, 0.10, 0.55),
			Palette.with_alpha(Palette.UI_STROKE, 0.22), 1, 12)

	UiKit.draw_text(self, Vector2(rect.position.x + 46.0, cy), "#%d" % (place + 1), 17,
		Palette.with_alpha(Palette.TEXT_DIM, 0.9), true)
	RankEmblem.draw_chip(self, rank, Vector2(rect.position.x + 86.0, cy), 28.0, _time)

	var name_col: Color = Palette.GOLD if is_me else Palette.TEXT_MAIN
	var name_y: float = cy - (9.0 if is_target else 0.0)
	UiKit.draw_text(self, Vector2(rect.position.x + 300.0, name_y),
		str(row.get("name", "?")), 21, name_col, false, 2)
	if is_target:
		UiKit.draw_text(self, Vector2(rect.position.x + 300.0, cy + 14.0),
			"SEURAAVAKSI OHITETTAVA", 13, Palette.glow(Palette.GOLD, 1.2), false)
	if is_me:
		UiKit.draw_text(self, Vector2(rect.end.x - 190.0, cy), "SINÄ", 15,
			Palette.GOLD, true, 2)
	UiKit.draw_text(self, Vector2(rect.end.x - 60.0, cy),
		"%d LP" % int(row.get("lp", 0)), 18, Palette.with_alpha(tint, 0.95), true, 2)
