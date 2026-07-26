class_name Results
extends Control
## Ottelun loppuruutu: voittaja, MVP-nosto ja tulostaulukko.
## MVP painottaa MOBA-tavoitepeliä — tornipaine, jungle, farmi, tankkaus ja tuki
## voivat nostaa muunkin kuin eniten tappoja saaneen sankarin parhaaksi.
## Piirretään kokonaan koodilla (napit ovat lapsisolmuja).

const ROW_H := 44.0
# Sivukaistat: tulostaulu on 1290 px leveä ja keskitetty (315..1605), joten
# ranked-paneelit mahtuvat sen molemmin puolin ilman päällekkäisyyttä.
const RANKED_X := 1608.0
const RANKED_W := 300.0
const RANKED_TOP := 200.0
const RANKED_BOTTOM := 880.0

var _mvp: PlayerProfile = null
var _mvp_reason := ""
var _sorted: Array = []
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	AudioMgr.play_music_pool("menu")
	AudioMgr.play("match_win")

	_compute_mvp()
	_sorted = Game.roster.duplicate()
	_sorted.sort_custom(func(a, b): return a.stats.score > b.stats.score)
	_build_confetti()
	_build_buttons()


# --- MVP-laskenta ---

func _compute_mvp() -> void:
	var components := {}
	for profile in Game.roster:
		var s: Dictionary = profile.stats
		components[profile] = {
			"obj": s.structure_damage * 1.5 + s.jungle_damage * 0.22 \
				+ s.minion_kills * 18.0 + s.xp * 0.12,
			"atk": s.damage + s.kos * 40.0 + s.assists * 20.0,
			"sup": s.healing + s.prevented,
			"def": s.prevented * 0.5 + s.taken * 0.22,
			"spec": s.gold * 0.15 + s.assists * 18.0 - s.deaths * 12.0,
		}
	var maxes := {"obj": 0.0, "atk": 0.0, "sup": 0.0, "def": 0.0, "spec": 0.0}
	for profile in components:
		for key in maxes:
			maxes[key] = maxf(maxes[key], components[profile][key])

	var best_score := -1.0
	for profile in Game.roster:
		var c: Dictionary = components[profile]
		var score := 0.0
		var weights := {"obj": 0.32, "atk": 0.28, "sup": 0.16, "def": 0.12, "spec": 0.12}
		for key in weights:
			if maxes[key] > 0.0:
				score += weights[key] * c[key] / maxes[key]
		if score > best_score:
			best_score = score
			_mvp = profile

	if _mvp != null:
		var s: Dictionary = _mvp.stats
		var parts: Array = []
		if s.structure_damage >= 100.0:
			parts.append("%d rakennusvahinkoa" % int(s.structure_damage))
		if s.jungle_damage >= 500.0:
			parts.append("%d jungle-vahinkoa" % int(s.jungle_damage))
		if s.minion_kills > 0:
			parts.append("%d CS" % int(s.minion_kills))
		if s.kos > 0:
			parts.append("%d tyrmäystä" % s.kos)
		if int(s.healing) > 0:
			parts.append("%d parannettu" % int(s.healing))
		if int(s.prevented) > 0:
			parts.append("%d estetty" % int(s.prevented))
		if parts.is_empty():
			parts.append("tasaista tekemistä kaikkialla")
		_mvp_reason = " · ".join(PackedStringArray(parts))


func _build_confetti() -> void:
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(960, -20)
	confetti.amount = 80
	confetti.lifetime = 5.0
	confetti.preprocess = 1.5
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(960, 10)
	confetti.direction = Vector2.DOWN
	confetti.spread = 20.0
	confetti.gravity = Vector2(0, 140)
	confetti.initial_velocity_min = 60.0
	confetti.initial_velocity_max = 160.0
	confetti.angular_velocity_min = -180.0
	confetti.angular_velocity_max = 180.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 8.0
	confetti.color = Palette.glow(Game.team_color(Game.last_winner_team), 1.2)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Game.team_color(Game.last_winner_team), Palette.GOLD, Color(1, 1, 1, 0.0)])
	confetti.color_ramp = gradient
	add_child(confetti)


func _build_buttons() -> void:
	var buttons := UiKit.hbox(20)
	buttons.position = Vector2(960 - 480.0, 902.0)
	add_child(buttons)
	var rematch_btn := UiKit.button("UUSI 4V4", func(): Game.rematch())
	rematch_btn.custom_minimum_size = Vector2(280, 58)
	buttons.add_child(rematch_btn)
	if Game.last_report != "":
		var report_btn := UiKit.button("MOBA-RAPORTTI", func(): Game.go_report())
		report_btn.custom_minimum_size = Vector2(300, 58)
		buttons.add_child(report_btn)
	var menu_btn := UiKit.button("PÄÄVALIKKOON", func(): Game.go_menu())
	menu_btn.custom_minimum_size = Vector2(280, 58)
	buttons.add_child(menu_btn)
	rematch_btn.call_deferred("grab_focus")


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# --- Piirto ---

func _card(rect: Rect2, bg: Color, border: Color, bw: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(int(radius))
	sb.draw(get_canvas_item(), rect)


func _draw() -> void:
	var winner: int = Game.last_winner_team
	var is_draw: bool = winner < 0
	var wc: Color = Palette.GOLD if is_draw else Game.team_color(winner)

	# Voittajahehku otsikon taakse
	var pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_circle(Vector2(960, 110), 380.0, Palette.with_alpha(wc, 0.06 + pulse * 0.03))
	for i in range(8):
		var ang := _time * 0.2 + TAU * i / 8.0
		draw_line(Vector2(960, 110), Vector2(960, 110) + Vector2(cos(ang), sin(ang)) * 320.0,
			Palette.with_alpha(wc, 0.03), 3.0)

	var title: String = "TASAPELI!" if is_draw else "%s VOITTAA!" % Game.team_name(winner)
	UiKit.draw_text(self, Vector2(960, 100), title, 80,
		Palette.glow(wc, 1.2), true, 9)
	UiKit.draw_text(self, Vector2(960, 168),
		"4V4 MOBA  •  ETERNAL DIVIDE  •  NEXUS RATKAISEE", 22, Palette.GOLD, true)

	_draw_mvp_card(214.0)
	_draw_table(408.0)
	_draw_ranked_panel()
	_draw_enemy_panel()


## Ranked-saldo omana paneelinaan tulostaulun oikealle puolelle (taulukko on
## 1290 px leveä ja keskitetty, joten sivukaistat jäävät vapaiksi).
## Jokaiselle ihmispelaajalle: tason tunnus, rank ennen ja jälkeen, animoituva
## LP-palkki, LP-muutos kertoimen perusteluineen ja putken tila.
func _draw_ranked_panel() -> void:
	if Game.last_ranked_results.is_empty():
		return
	var count: int = Game.last_ranked_results.size()
	var rect := Rect2(RANKED_X, RANKED_TOP, RANKED_W, RANKED_BOTTOM - RANKED_TOP)
	_card(rect, Palette.with_alpha(Palette.UI_PANEL, 0.92),
		Palette.with_alpha(Palette.GOLD, 0.5), 2, 18)
	var cx := rect.get_center().x
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 32.0), "RANKED — LP", 26,
		Palette.GOLD, true, 3)
	draw_line(rect.position + Vector2(20.0, 52.0),
		Vector2(rect.end.x - 20.0, rect.position.y + 52.0),
		Palette.with_alpha(Palette.GOLD, 0.3), 2.0)

	var block_h: float = clampf((rect.size.y - 70.0) / float(count), 132.0, 300.0)
	var compact: bool = block_h < 210.0
	var y: float = rect.position.y + 62.0
	for entry in Game.last_ranked_results:
		var res: Dictionary = entry
		_draw_ranked_block(Rect2(rect.position.x + 10.0, y, rect.size.x - 20.0,
			block_h - 8.0), res, compact)
		y += block_h


## LP-muutoksen kerroin ihmiskielellä: kuinka paljon vastustajajoukkue oli
## omaa rankia edellä tai jäljessä.
func _mult_reason(res: Dictionary) -> String:
	var enemy: float = float(res.get("enemy_avg_rank", 0.0))
	var own: int = int(res.get("rank_before", 0))
	var mult: float = float(res.get("mult", 1.0))
	var diff: float = enemy - float(own)
	if diff >= 0.5:
		return "vastustajat +%.1f rankia → ×%.2f" % [diff, mult]
	if diff <= -0.5:
		return "vastustajat %.1f rankia → ×%.2f" % [diff, mult]
	return "tasaväkinen ottelu → ×%.2f" % mult


func _draw_ranked_block(rect: Rect2, res: Dictionary, compact: bool) -> void:
	var rank_before: int = int(res.get("rank_before", 0))
	var rank_after: int = int(res.get("rank_after", 0))
	var lp_before: float = float(int(res.get("lp_before", 0)))
	var lp_after: float = float(int(res.get("lp_after", 0)))
	var delta: int = int(res.get("delta", 0))
	var tint: Color = BotRank.rank_color(rank_after)
	var accent: Color = Palette.GOOD if delta > 0 else \
		(Palette.BAD if delta < 0 else Palette.GOLD)
	if str(res.get("promoted", "")) != "":
		accent = Palette.glow(Palette.GOLD, 1.3)
	elif bool(res.get("demoted", false)):
		accent = Palette.BAD

	# LP-palkki ja lukema kiipeävät paikoilleen ottelun jälkeen.
	var anim: float = 1.0 - pow(1.0 - clampf((_time - 0.45) / 1.0, 0.0, 1.0), 3.0)
	var lp_now: float = lerpf(lp_before, lp_after, anim)
	var delta_now: int = int(round(lerpf(0.0, float(delta), anim)))

	var cx: float = rect.get_center().x
	var ranks: String = "%s → %s" % [BotRank.rank_name(rank_before),
		BotRank.rank_name(rank_after)]
	var delta_text: String = "%+d LP" % delta_now
	if delta == 0:
		delta_text = RankedRules.result_headline(res)

	if compact:
		var cy: float = rect.get_center().y
		RankEmblem.draw(self, rank_after, Vector2(rect.position.x + 40.0, cy - 12.0),
			24.0, _time)
		UiKit.draw_text(self, Vector2(rect.position.x + 78.0, rect.position.y + 18.0),
			str(res.get("name", "")), 19, Palette.TEXT_MAIN, false, 2)
		UiKit.draw_text(self, Vector2(rect.position.x + 78.0, rect.position.y + 40.0),
			ranks, 13, tint, false)
		_draw_lp_bar(Rect2(rect.position.x + 78.0, rect.position.y + 54.0,
			rect.size.x - 88.0, 16.0), lp_now, tint)
		UiKit.draw_text(self, Vector2(rect.position.x + 78.0, rect.position.y + 88.0),
			delta_text, 19, accent, false, 2)
		UiKit.draw_text(self, Vector2(rect.position.x + 78.0, rect.position.y + 110.0),
			_mult_reason(res), 12, Palette.TEXT_DIM, false)
		return

	RankEmblem.draw(self, rank_after, Vector2(cx, rect.position.y + 48.0), 34.0, _time)
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 116.0), str(res.get("name", "")),
		22, Palette.TEXT_MAIN, true, 3)
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 142.0), ranks, 15, tint, true)
	_draw_lp_bar(Rect2(rect.position.x + 20.0, rect.position.y + 160.0,
		rect.size.x - 40.0, 20.0), lp_now, tint)
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 206.0), delta_text, 26, accent,
		true, 3)
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 232.0), _mult_reason(res), 13,
		Palette.TEXT_DIM, true)
	var bonus: int = int(res.get("streak_bonus", 0))
	var streak: int = int(res.get("streak_after", 0))
	var tail: String = "Ei putkea"
	var tail_col: Color = Palette.TEXT_DIM
	if bonus > 0:
		tail = "voittoputki %d — putkibonus +%d LP" % [streak, bonus]
		tail_col = Palette.GOOD
	elif streak > 0:
		tail = "voittoputki %d" % streak
		tail_col = Palette.GOOD
	elif streak < 0:
		tail = "tappioputki %d" % absi(streak)
		tail_col = Palette.BAD
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 256.0), tail, 14, tail_col, true)


func _draw_lp_bar(rect: Rect2, value: float, col: Color) -> void:
	_card(rect, Color(0.02, 0.03, 0.07, 0.9), Palette.with_alpha(col, 0.5), 1,
		rect.size.y / 2.0)
	var f: float = clampf(value / float(RankedRules.LP_MAX), 0.0, 1.0)
	if f > 0.01:
		_card(Rect2(rect.position.x + 2.0, rect.position.y + 2.0,
			(rect.size.x - 4.0) * f, rect.size.y - 4.0), Palette.glow(col, 1.2),
			Color(0, 0, 0, 0), 0, (rect.size.y - 4.0) / 2.0)
	UiKit.draw_text(self, rect.get_center(), "%d / %d LP" %
		[int(round(value)), RankedRules.LP_MAX], int(rect.size.y * 0.62),
		Palette.TEXT_MAIN, true, 2)


## Vastustajajoukkueen nimetyt haastajat rankeineen tulostaulun vasemmalle
## puolelle: ottelu näyttää oikealta sarjaottelulta eikä nimettömältä botilta.
func _draw_enemy_panel() -> void:
	if not Game.ranked_mode or Game.last_ranked_results.is_empty():
		return
	var human_team := -1
	for profile in Game.roster:
		if not profile.is_bot:
			human_team = profile.team
			break
	if human_team < 0:
		return
	var enemy: int = 1 - human_team
	var members: Array = Game.team_members(enemy)
	if members.is_empty():
		return

	var rect := Rect2(12, RANKED_TOP, RANKED_W, 78.0 + float(members.size()) * 84.0)
	_card(rect, Palette.with_alpha(Palette.UI_PANEL, 0.92),
		Palette.with_alpha(Palette.team(enemy), 0.55), 2, 18)
	var cx := rect.get_center().x
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 32.0), "VASTASSA", 26,
		Palette.team(enemy), true, 3)
	var avg: float = 0.0
	for entry in members:
		var profile: PlayerProfile = entry
		avg += float(maxi(profile.ranked_rank, 0))
	avg /= float(members.size())
	UiKit.draw_text(self, Vector2(cx, rect.position.y + 58.0),
		"keskirank %s" % BotRank.rank_name(int(round(avg))), 15, Palette.TEXT_DIM, true)
	draw_line(rect.position + Vector2(20.0, 72.0),
		Vector2(rect.end.x - 20.0, rect.position.y + 72.0),
		Palette.with_alpha(Palette.team(enemy), 0.3), 2.0)

	var y: float = rect.position.y + 82.0
	for entry in members:
		var profile: PlayerProfile = entry
		var cy: float = y + 34.0
		var def := HeroDef.get_def(profile.hero_id)
		var med := Vector2(rect.position.x + 36.0, cy - 8.0)
		draw_circle(med, 19.0, Palette.darker(def["color_b"], 0.55))
		draw_circle(med, 15.0, def["color"])
		HeroIcon.draw_symbol(self, profile.hero_id, med, 10.0)
		UiKit.draw_text(self, Vector2(rect.position.x + 62.0, cy - 20.0),
			profile.display_name, 18, Palette.TEXT_MAIN, false, 2)
		if profile.ranked_rank >= 0:
			RankEmblem.draw_chip(self, profile.ranked_rank,
				Vector2(rect.position.x + 62.0, cy + 12.0), 22.0, _time)
		else:
			UiKit.draw_text(self, Vector2(rect.position.x + 62.0, cy + 12.0),
				profile.hero_name(), 14, Palette.TEXT_DIM, false)
		y += 84.0


func _draw_mvp_card(y: float) -> void:
	if _mvp == null:
		return
	var rect := Rect2(510, y, 900, 150)
	var glow_pulse := 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(rect.get_center(), 400.0, Palette.with_alpha(Palette.GOLD, 0.03))
	_card(rect, Palette.with_alpha(Palette.UI_PANEL_LIGHT, 0.95),
		Palette.glow(Palette.GOLD, 1.0 + glow_pulse * 0.3), 3, 20)

	# Medaljonki + kruunu
	var def := HeroDef.get_def(_mvp.hero_id)
	var c1: Color = def["color"]
	var c2: Color = def["color_b"]
	var med := Vector2(rect.position.x + 90.0, rect.get_center().y + 6.0)
	draw_arc(med, 62.0, _time, _time + TAU * 0.85, 28, Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4), 0.6), 3.0)
	draw_circle(med, 55.0, Palette.darker(c2, 0.55))
	draw_circle(med, 50.0, c1)
	draw_circle(med + Vector2(0, 18), 34.0, Palette.with_alpha(c2, 0.35))
	HeroIcon.draw_symbol(self, _mvp.hero_id, med, 32.0)
	_draw_crown(med + Vector2(0, -66.0))

	# Teksti
	var tx := rect.position.x + 180.0
	UiKit.draw_text(self, Vector2(tx, y + 34.0), "OTTELUN MVP", 20, Palette.GOLD, false, 3)
	UiKit.draw_text(self, Vector2(tx, y + 74.0), "%s — %s" % [_mvp.display_name, _mvp.hero_name()],
		36, Palette.TEXT_MAIN, false, 4)
	UiKit.draw_text(self, Vector2(tx, y + 116.0), _mvp_reason, 20, Palette.TEXT_DIM, false)


func _draw_crown(pos: Vector2) -> void:
	var crown := PackedVector2Array([
		pos + Vector2(-16, 8), pos + Vector2(-16, -8), pos + Vector2(-8, -2),
		pos + Vector2(0, -12), pos + Vector2(8, -2), pos + Vector2(16, -8),
		pos + Vector2(16, 8)])
	draw_colored_polygon(crown, Palette.glow(Palette.GOLD, 1.5))
	for dx in [-16.0, 0.0, 16.0]:
		draw_circle(pos + Vector2(dx, -10), 3.0, Palette.glow(Color("fff2c0"), 1.4))


# Sarakkeet: [avain, leveys, otsikko, keskitetty]
func _columns() -> Array:
	return [
		["name", 250.0, "Pelaaja", false],
		["hero", 150.0, "Sankari", false],
		["kda", 140.0, "K / D / A", true],
		["damage", 120.0, "Vahinko", true],
		["structure", 120.0, "Torneihin", true],
		["jungle", 120.0, "Jungle", true],
		["cs", 75.0, "CS", true],
		["gold", 95.0, "Kulta", true],
		["healing", 115.0, "Parannettu", true],
		["prevented", 105.0, "Estetty", true],
	]


func _draw_table(y0: float) -> void:
	var cols := _columns()
	var total := 0.0
	for col in cols:
		total += col[1]
	var tx0 := 960.0 - total / 2.0

	# Otsikkorivi
	var cx := tx0
	for col in cols:
		var w: float = col[1]
		var label: String = col[2]
		var centered: bool = col[3]
		var px := cx + (w / 2.0 if centered else 12.0)
		UiKit.draw_text(self, Vector2(px, y0), label, 16, Palette.TEXT_DIM, centered)
		cx += w
	draw_line(Vector2(tx0, y0 + 18.0), Vector2(tx0 + total, y0 + 18.0),
		Palette.with_alpha(Palette.UI_STROKE, 0.4), 2.0)

	# Datarivit
	for r in range(_sorted.size()):
		var profile: PlayerProfile = _sorted[r]
		var ry := y0 + 34.0 + r * ROW_H
		var row_alpha: float = clampf((_time - (0.15 + r * 0.07)) / 0.3, 0.0, 1.0)
		if row_alpha <= 0.0:
			continue
		_draw_row(profile, Rect2(tx0, ry, total, ROW_H - 4.0), cols, row_alpha)


func _draw_row(profile: PlayerProfile, rect: Rect2, cols: Array, a: float) -> void:
	var is_mvp: bool = profile == _mvp
	var winner: int = Game.last_winner_team
	# Rivin tausta
	var bg := Palette.with_alpha(Palette.team(profile.team), 0.10)
	if profile.team == winner:
		bg = Palette.with_alpha(Palette.team(profile.team), 0.16)
	if is_mvp:
		bg = Palette.with_alpha(Palette.GOLD, 0.14)
	_card(rect, Palette.with_alpha(bg, bg.a * a),
		Palette.with_alpha(Palette.GOLD if is_mvp else Palette.team(profile.team), 0.35 * a),
		2 if is_mvp else 1, 10)

	var s: Dictionary = profile.stats
	var cy := rect.get_center().y
	var cx := rect.position.x
	for col in cols:
		var key: String = col[0]
		var w: float = col[1]
		var centered: bool = col[3]
		var px := cx + (w / 2.0 if centered else 44.0)
		match key:
			"name":
				var pc: Color = profile.color() if profile.is_human() \
					else Palette.with_alpha(Palette.team(profile.team), 0.7)
				draw_circle(Vector2(cx + 22.0, cy), 9.0, Palette.with_alpha(pc, a))
				var nm: String = profile.display_name
				var col_txt: Color = Palette.GOLD if is_mvp else Palette.TEXT_MAIN
				if not profile.is_human():
					col_txt = Palette.with_alpha(col_txt, 0.7)
				UiKit.draw_text(self, Vector2(px, cy), nm, 19, Palette.with_alpha(col_txt, a), false)
				if is_mvp:
					UiKit.draw_text(self, Vector2(cx + w - 46.0, cy), "★MVP", 14,
						Palette.with_alpha(Palette.GOLD, a), false)
			"hero":
				var hdef := HeroDef.get_def(profile.hero_id)
				var med := Vector2(cx + 20.0, cy)
				draw_circle(med, 15.0, Palette.with_alpha(Palette.darker(hdef["color_b"], 0.55), a))
				draw_circle(med, 12.0, Palette.with_alpha(hdef["color"], a))
				HeroIcon.draw_symbol(self, profile.hero_id, med, 8.0)
				UiKit.draw_text(self, Vector2(cx + 42.0, cy), profile.hero_name(), 15,
					Palette.with_alpha(Palette.TEXT_DIM, a), false)
			_:
				var val := ""
				match key:
					"kda": val = "%d / %d / %d" % [s.kos, s.deaths, s.assists]
					"damage": val = str(int(s.damage))
					"structure": val = str(int(s.structure_damage))
					"jungle": val = str(int(s.jungle_damage))
					"cs": val = str(int(s.minion_kills))
					"gold": val = str(int(s.gold))
					"healing": val = str(int(s.healing))
					"prevented": val = str(int(s.prevented))
				UiKit.draw_text(self, Vector2(px, cy), val, 19, Palette.with_alpha(Palette.TEXT_MAIN, a), true)
		cx += w
