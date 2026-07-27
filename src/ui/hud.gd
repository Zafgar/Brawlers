class_name HudLayer
extends CanvasLayer
## Responsiivinen ottelu-HUD 1–4 paikallispelaajalle. Jokainen peliruutu saa
## oman, pelaajaan sidotun HUDin: ottelutilanne, sankari, resurssit, kyvyt,
## joukkueiden tila, tapahtumat ja minikartta pysyvät aina oikeassa ruudussa.

const MAX_LOCAL_PANES := 4

var arena = null
var _root: Control = null
var _panes: Array = []
var _scoreboard: Control = null


func setup(p_arena) -> void:
	arena = p_arena
	layer = 10

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	for i in range(MAX_LOCAL_PANES):
		var pane := PaneHud.new()
		pane.arena = arena
		pane.pane_index = i
		pane.visible = false
		pane.set_process(false)
		pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pane.clip_contents = true
		_root.add_child(pane)
		_panes.append(pane)

	# Tulostaulu (pidä Tab / PS5-ohjaimen touchpad tai Create): koko ruudun
	# jaettu overlay ruutujen PÄÄLLÄ — sama taulu kaikille paikallispelaajille.
	_scoreboard = Scoreboard.new()
	_scoreboard.arena = arena
	_scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.visible = false
	_root.add_child(_scoreboard)

	# Tavallisessa yhden viewportin pelissä SplitView ei asemoi HUDia.
	if not arena.hosted:
		_layout_single.call_deferred()


## Tulostaulu näkyy niin kauan kuin nappia pidetään pohjassa (LoL-tyyli).
## PS5 (pääohjain): touchpadin painallus tai Create; näppäimistö: Tab.
func _process(_delta: float) -> void:
	if _scoreboard == null:
		return
	var held := Input.is_physical_key_pressed(KEY_TAB)
	if not held:
		for pad in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_TOUCHPAD) \
					or Input.is_joy_button_pressed(pad, JOY_BUTTON_BACK):
				held = true
				break
	_scoreboard.visible = held and arena != null and not Game.simulating
	# Tulostaulu on koko ruudun overlay ruutujen PÄÄLLÄ: kerrotaan tila
	# paneeleille, jotta tietonäkymä väistyy eikä piirry sen alle.
	for pane in _panes:
		pane.scoreboard_open = held


func _layout_single() -> void:
	if _root == null:
		return
	var full: Vector2 = _root.size
	if full.x < 1.0 or full.y < 1.0:
		full = _root.get_viewport_rect().size
	layout_panes([Rect2(Vector2.ZERO, full)], [_first_local_hero()])


func _first_local_hero():
	var fallback = null
	for hero in arena.heroes:
		if not is_instance_valid(hero) or hero.is_unit:
			continue
		if fallback == null:
			fallback = hero
		if hero.profile != null and not hero.profile.is_bot:
			return hero
	return fallback


## SplitView kutsuu tätä aina kun ruutujako muuttuu. HUD-elementit käyttävät
## paneelin sisäisiä koordinaatteja, joten mikään ei voi valua naapuriruutuun.
func layout_panes(rects: Array, heroes: Array) -> void:
	for i in range(_panes.size()):
		var pane: Control = _panes[i]
		var active: bool = i < rects.size()
		pane.visible = active
		# Piilotettuja varapaneeleita ei päivitetä taustalla.
		pane.set_process(active)
		if not active:
			continue
		var rect: Rect2 = rects[i]
		pane.position = rect.position
		pane.size = rect.size
		pane.bind_hero(heroes[i] if i < heroes.size() else null, rects.size())


## Bannerit, lähtölaskenta ja tapahtumat kopioidaan jokaiseen aktiiviseen
## pelaajaruutuun. Näin teksti ei koskaan osu jaetun näytön saumaan.
func show_banner(big: String, small := "", dur := 2.0) -> void:
	for pane in _panes:
		pane.show_banner(big, small, dur)


func show_big_number(text: String) -> void:
	for pane in _panes:
		pane.show_big_number(text)


func ko_feed(text: String) -> void:
	for pane in _panes:
		pane.push_feed(text)


class PaneHud:
	extends Control

	var arena = null
	var bound_hero = null
	var pane_index := 0
	var pane_count := 1
	var scoreboard_open := false     # HudLayer kertoo: tulostaulu pohjassa
	var _time := 0.0
	var _redraw_accum := 0.0
	# Tietonäkymä (pidä D-pad oikea / C). Kapeassa ruudussa kykykortteja
	# näytetään yksi kerrallaan, joten kierrätysajastin muistaa vuoron.
	var _inspect_cycle := 0.0
	var _hints: Array = []           # telakan ylle pinottavat vihjerivit

	var _banner_big := ""
	var _banner_small := ""
	var _banner_start := -100.0
	var _banner_until := -100.0
	var _big_number := ""
	var _big_start := -100.0
	var _big_until := -100.0
	var _feed: Array = []

	# Minikartan staattinen karttadata (seinät, reitit, leirit, puskat eivät
	# muutu ottelun aikana): haetaan kartalta KERRAN eikä rakenneta uusia
	# taulukoita/sanakirjoja 30-45 kertaa sekunnissa jokaiseen ruutuun.
	var _mm_ready := false
	var _mm_brushes: Array = []
	var _mm_jungle_paths: Array = []
	var _mm_chokes: Array = []
	var _mm_alcoves: Array = []
	var _mm_lane_paths: Array = []
	var _mm_camps: Array = []
	var _mm_sancta: Array = []     # [{rect, shop, team}]
	var _mm_doors: Array = []      # [{center, team}]
	# Leirien elävä tila haetaan olennoilta, mutta itse olento etsitään VAIN
	# kerran: _mm_camp_nodes on _mm_camps:n rinnakkaistaulukko (Critter tai null).
	# Sen jälkeen ruutupäivitys on pelkkiä kenttälukuja eikä uusia taulukoita tai
	# sanakirjoja synny lainkaan — tärkeää 32x simunopeudella.
	var _mm_camp_nodes: Array = []
	var _mm_camp_unbound := true   # onko vielä leirejä joita ei ole sidottu
	var _mm_camp_bind_at := 0.0    # seuraavan sidontayrityksen ajanhetki


	func bind_hero(hero, count: int) -> void:
		bound_hero = hero
		pane_count = count
		queue_redraw()


	func show_banner(big: String, small: String, dur: float) -> void:
		_banner_big = big
		_banner_small = small
		_banner_start = _time
		_banner_until = _time + dur


	func show_big_number(text: String) -> void:
		_big_number = text
		_big_start = _time
		_big_until = _time + 0.72


	func push_feed(text: String) -> void:
		_feed.push_front({"text": text, "until": _time + 4.2})
		if _feed.size() > 3:
			_feed.resize(3)


	func _process(delta: float) -> void:
		_time += delta
		# Kykykorttien kierto kapeassa ruudussa käy vain kun nappi on pohjassa;
		# vapautus nollaa vuoron, jotta luku alkaa aina perushyökkäyksestä.
		if _inspect_active():
			_inspect_cycle += delta
		else:
			_inspect_cycle = 0.0
		for i in range(_feed.size() - 1, -1, -1):
			if float(_feed[i]["until"]) <= _time:
				_feed.remove_at(i)
		# CanvasItem säilyttää edellisen täyden HUD-piirron. Päivitämme vain sen
		# komentolistan 30–45 Hz:llä; itse viewport renderöi edelleen täydellä
		# ruutunopeudella ja kaikki tekstit, ikonit sekä minimap pysyvät ennallaan.
		_redraw_accum += delta
		var interval := 1.0 / (45.0 if pane_count == 1 else 30.0)
		if _redraw_accum >= interval:
			_redraw_accum = fmod(_redraw_accum, interval)
			queue_redraw()


	func _draw() -> void:
		if arena == null or size.x < 2.0 or size.y < 2.0:
			return
		_hints.clear()
		_draw_edge_shading()
		_draw_pane_frame()
		_draw_match_panel()
		_draw_player_badge()
		_draw_team_status()
		_draw_feed()
		if bound_hero != null and is_instance_valid(bound_hero):
			_draw_ability_dock()
			_draw_minimap()
			_draw_inspect()
			_draw_shop_prompt()
			_draw_inspect_hint()
			_draw_hints()
			if bool(bound_hero.shop_open):
				_draw_shop()
		_draw_banner()
		_draw_big_number()


	func _compact() -> bool:
		return size.y < 720.0


	func _narrow() -> bool:
		return size.x < 1200.0


	func _margin() -> float:
		return 12.0 if _compact() else 18.0


	func _draw_edge_shading() -> void:
		# Hento tumma kehys parantaa tekstien kontrastia peittämättä pelikuvaa.
		for i in range(4):
			var a: float = 0.12 - float(i) * 0.022
			draw_rect(Rect2(0, i * 12.0, size.x, 12.0), Color(0.01, 0.02, 0.06, a))
			draw_rect(Rect2(0, size.y - (i + 1) * 14.0, size.x, 14.0),
				Color(0.01, 0.02, 0.06, a))


	func _draw_pane_frame() -> void:
		var col := Palette.UI_STROKE
		if bound_hero != null and is_instance_valid(bound_hero) and bound_hero.profile != null:
			col = bound_hero.profile.color()
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Color(0, 0, 0, 0.78), false, 5.0)
		draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), Palette.with_alpha(col, 0.62), false, 2.0)


	func _draw_player_badge() -> void:
		if bound_hero == null or not is_instance_valid(bound_hero) or bound_hero.profile == null:
			return
		var compact := _compact()
		var rect := Rect2(_margin(), _margin(), 212.0 if compact else 264.0,
			48.0 if compact else 62.0)
		var pcol: Color = bound_hero.profile.color()
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.9), Palette.with_alpha(pcol, 0.72),
			12.0, 2.0)
		draw_rect(Rect2(rect.position, Vector2(6.0, rect.size.y)), Palette.glow(pcol, 1.2))

		var chip := rect.position + Vector2(28.0, rect.size.y / 2.0)
		draw_circle(chip, 17.0 if compact else 22.0, Palette.darker(pcol, 0.5))
		draw_circle(chip, 14.0 if compact else 18.0, pcol)
		UiKit.draw_text(self, chip + Vector2(0, 1), "P%d" % (bound_hero.profile.index + 1),
			11 if compact else 14, Palette.TEXT_DARK, true, 2)

		var def: Dictionary = HeroDef.get_def(bound_hero.hero_id)
		var tx := rect.position.x + 54.0
		UiKit.draw_text(self, Vector2(tx, rect.position.y + (19.0 if compact else 23.0)),
			str(def["name"]).to_upper(), 16 if compact else 20, Palette.TEXT_MAIN, false, 3)
		var subtitle := "%s | %s" % [str(def["role"]).to_upper(), Game.team_name(bound_hero.team)]
		if arena != null and arena.mode == "moba":
			if bound_hero.level >= Hero.MAX_LEVEL:
				subtitle = "LV12 MAX | %s | %dG" % [str(def["role"]).to_upper(),
					int(bound_hero.profile.stats.gold)]
			else:
				subtitle = "LV%d | %s | %dG | %d/%d XP" % [bound_hero.level,
					str(def["role"]).to_upper(), int(bound_hero.profile.stats.gold),
					int(bound_hero.xp_in_current_level()),
					int(bound_hero.xp_needed_for_next_level())]
		UiKit.draw_text(self, Vector2(tx, rect.position.y + (38.0 if compact else 48.0)),
			subtitle, 8 if compact else 11,
			Palette.with_alpha(Palette.team(bound_hero.team), 0.92), false, 2)
		if arena != null and arena.mode == "moba":
			var xp_rect := Rect2(tx, rect.end.y - (4.0 if compact else 6.0),
				rect.end.x - tx - 9.0, 3.0 if compact else 4.0)
			draw_rect(xp_rect, Color(0.01, 0.02, 0.04, 0.82))
			draw_rect(Rect2(xp_rect.position,
				Vector2(xp_rect.size.x * bound_hero.xp_level_fraction(), xp_rect.size.y)),
				Palette.glow(Palette.GOLD, 1.15))


	func _score_rect() -> Rect2:
		var compact := _compact()
		var w: float
		if compact:
			w = 390.0 if _narrow() else 444.0
		else:
			w = 620.0
		return Rect2((size.x - w) / 2.0, _margin(), w, 62.0 if compact else 86.0)


	func _draw_match_panel() -> void:
		var rect := _score_rect()
		var compact := _compact()
		_panel(Rect2(rect.position + Vector2(0, 4), rect.size), Color(0, 0, 0, 0.42),
			Color(0, 0, 0, 0), 15.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.93), Palette.UI_STROKE, 15.0, 2.0)

		var blue_value: int = _objective_value(0)
		var orange_value: int = _objective_value(1)
		var blue_frac: float = _objective_fraction(0)
		var orange_frac: float = _objective_fraction(1)
		var center := rect.position + Vector2(rect.size.x / 2.0, rect.size.y / 2.0)
		var label_y := rect.position.y + (16.0 if compact else 22.0)
		var value_y := rect.position.y + (35.0 if compact else 47.0)

		if not compact:
			UiKit.draw_text(self, Vector2(rect.position.x + 82.0, label_y), "SININEN",
				11, Palette.with_alpha(Palette.TEAM_BLUE, 0.9), true, 2)
			UiKit.draw_text(self, Vector2(rect.end.x - 82.0, label_y), "ORANSSI",
				11, Palette.with_alpha(Palette.TEAM_ORANGE, 0.9), true, 2)
		UiKit.draw_text(self, Vector2(rect.position.x + (64.0 if compact else 82.0), value_y),
			str(blue_value), 19 if compact else 25, Palette.TEXT_MAIN, true, 3)
		UiKit.draw_text(self, Vector2(rect.end.x - (64.0 if compact else 82.0), value_y),
			str(orange_value), 19 if compact else 25, Palette.TEXT_MAIN, true, 3)

		# Keskellä kellomedaljonki ja pelimuoto.
		var clock_r := 25.0 if compact else 34.0
		draw_circle(center, clock_r, Color(0.025, 0.04, 0.09, 0.98))
		draw_arc(center, clock_r, 0.0, TAU, 36, Palette.with_alpha(Palette.GOLD, 0.5), 2.0)
		UiKit.draw_text(self, center + Vector2(0, -12.0 if compact else -17.0),
			str(arena.mode).to_upper(), 8 if compact else 10, Palette.GOLD, true, 2)
		var secs := int(maxf(arena.time_left, 0.0))
		var time_text := "%d:%02d" % [secs / 60, secs % 60]
		var time_col := Palette.TEXT_MAIN
		if arena.sudden_death:
			time_text = "OT"
			time_col = Palette.glow(Palette.GOLD, 1.2 + 0.15 * sin(_time * 7.0))
		elif secs <= 30:
			time_col = Palette.with_alpha(Palette.BAD, 0.75 + 0.25 * sin(_time * 5.0))
		UiKit.draw_text(self, center + Vector2(0, 7.0 if compact else 10.0), time_text,
			22 if compact else 30, time_col, true, 4)

		# Tavoitepalkit lähestyvät keskustaa omilta reunoiltaan.
		var bar_y := rect.end.y - (8.0 if compact else 11.0)
		var half_w := rect.size.x / 2.0 - clock_r - 18.0
		var bar_h := 5.0 if compact else 7.0
		draw_rect(Rect2(rect.position.x + 10.0, bar_y, half_w, bar_h), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(rect.end.x - 10.0 - half_w, bar_y, half_w, bar_h), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(rect.position.x + 10.0, bar_y, half_w * blue_frac, bar_h),
			Palette.glow(Palette.TEAM_BLUE, 1.15))
		draw_rect(Rect2(rect.end.x - 10.0 - half_w * orange_frac, bar_y,
			half_w * orange_frac, bar_h), Palette.glow(Palette.TEAM_ORANGE, 1.15))

		var buff_time: float = arena.next_buff_in()
		if buff_time >= 0.0:
			var bw := 210.0 if compact else 260.0
			var br := Rect2(center.x - bw / 2.0, rect.end.y + 6.0, bw, 24.0 if compact else 30.0)
			_panel(br, Palette.with_alpha(Palette.UI_PANEL, 0.86),
				Palette.with_alpha(Palette.GOLD, 0.34), 10.0, 1.0)
			var bsecs := int(ceil(buff_time))
			UiKit.draw_text(self, br.get_center(), "BUFFIT  %d:%02d" % [bsecs / 60, bsecs % 60],
				11 if compact else 14, Palette.GOLD if buff_time <= 8.0 else Palette.TEXT_DIM, true, 2)


	func _objective_value(team: int) -> int:
		if arena.mode == "moba":
			return arena.nexus_hp_int(team)
		return int(arena.team_points(team))


	func _objective_fraction(team: int) -> float:
		if arena.mode == "moba":
			return arena.nexus_fraction(team)
		if arena.mode == "jungle":
			var lead := maxf(maxf(arena.team_points(0), arena.team_points(1)), 1.0)
			return clampf(arena.team_points(team) / lead, 0.0, 1.0)
		return clampf(arena.team_points(team) / maxf(arena.score_target, 1.0), 0.0, 1.0)


	func _draw_team_status() -> void:
		var compact := _compact()
		var rect := Rect2(size.x - _margin() - (190.0 if compact else 234.0), _margin(),
			190.0 if compact else 234.0, 62.0 if compact else 78.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.88), Palette.UI_STROKE, 12.0, 1.5)
		_draw_team_row(rect, 0, rect.position.y + rect.size.y * 0.31)
		_draw_team_row(rect, 1, rect.position.y + rect.size.y * 0.72)


	func _draw_team_row(rect: Rect2, team: int, y: float) -> void:
		var compact := _compact()
		var tc := Palette.team(team)
		var label_x := rect.position.x + (18.0 if compact else 22.0)
		draw_circle(Vector2(label_x, y), 6.0 if compact else 7.0, tc)
		UiKit.draw_text(self, Vector2(label_x + 14.0, y), "B" if team == 0 else "O",
			8 if compact else 10, Palette.with_alpha(tc, 0.95), true, 1)

		var heroes := _team_heroes(team)
		var step := 34.0 if compact else 41.0
		var radius := 10.0 if compact else 13.0
		var x := rect.position.x + (56.0 if compact else 68.0)
		for i in range(mini(heroes.size(), 4)):
			var hero = heroes[i]
			var center := Vector2(x + i * step, y)
			var hc: Color = hero.hero_color()
			draw_circle(center, radius + 2.0, Color(0, 0, 0, 0.65))
			draw_circle(center, radius, Palette.darker(hc, 0.52))
			HeroIcon.draw_symbol(self, hero.hero_id, center, radius * 0.58)
			var hp_frac: float = clampf(hero.hp / maxf(hero.max_hp, 1.0), 0.0, 1.0)
			draw_arc(center, radius + 2.0, -PI * 0.5, -PI * 0.5 + TAU * hp_frac,
				20, Palette.GOOD if hp_frac > 0.3 else Palette.BAD, 2.0)
			if hero == bound_hero:
				draw_arc(center, radius + 4.0, 0.0, TAU, 24,
					Palette.glow(hero.profile.color(), 1.35), 2.0)
			if not hero.alive:
				draw_circle(center, radius + 1.0, Color(0.02, 0.03, 0.08, 0.72))
				draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), Palette.BAD, 2.0)
				draw_line(center + Vector2(5, -5), center + Vector2(-5, 5), Palette.BAD, 2.0)


	func _team_heroes(team: int) -> Array:
		# Vain pelaajasankarit (välimuisti) — kutsutaan joka HUD-piirrolla.
		var out: Array = []
		for hero in arena.player_heroes:
			if is_instance_valid(hero) and hero.profile != null and hero.team == team:
				out.append(hero)
		out.sort_custom(func(a, b): return a.profile.index < b.profile.index)
		return out


	func _draw_feed() -> void:
		if _feed.is_empty():
			return
		var compact := _compact()
		var w := 300.0 if compact else 360.0
		var x := size.x - _margin() - w
		var y := _margin() + (72.0 if compact else 90.0)
		for i in range(_feed.size()):
			var alpha := clampf((float(_feed[i]["until"]) - _time) / 0.6, 0.0, 1.0)
			var rect := Rect2(x, y + i * (27.0 if compact else 34.0), w,
				23.0 if compact else 29.0)
			_panel(rect, Color(0.035, 0.055, 0.11, 0.74 * alpha),
				Palette.with_alpha(Palette.UI_STROKE, 0.35 * alpha), 8.0, 1.0)
			UiKit.draw_text(self, rect.get_center(), str(_feed[i]["text"]),
				11 if compact else 14, Palette.with_alpha(Palette.TEXT_MAIN, alpha), true, 2)


	func _dock_rect() -> Rect2:
		var compact := _compact()
		var w: float
		var h: float
		var x: float
		if not compact:
			w = 900.0
			h = 170.0
			x = (size.x - w) / 2.0
		elif _narrow():
			w = minf(600.0, size.x - 340.0)
			h = 114.0
			# Ryhmitä kykypalkki ja leveä minikartta yhdeksi tasapainoiseksi
			# alareunan kokonaisuudeksi neljän pelaajan ruudussa.
			x = maxf(_margin(), (size.x - 220.0 - 24.0 - w) / 2.0)
		else:
			w = 760.0
			h = 128.0
			x = (size.x - w) / 2.0
		return Rect2(x, size.y - _margin() - h, w, h)


	func _draw_ability_dock() -> void:
		var hero = bound_hero
		var rect := _dock_rect()
		var compact := _compact()
		var narrow := _narrow()
		var hc: Color = hero.hero_color()
		var pcol: Color = hero.profile.color()

		_panel(Rect2(rect.position + Vector2(0, 5), rect.size), Color(0, 0, 0, 0.5),
			Color(0, 0, 0, 0), 17.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.94), Palette.with_alpha(hc, 0.68),
			17.0, 2.0)
		draw_rect(Rect2(rect.position + Vector2(12, 0), Vector2(rect.size.x - 24.0, 3.0)),
			Palette.glow(hc, 1.25))

		var portrait_r := 34.0 if narrow else (39.0 if compact else 50.0)
		var portrait := rect.position + Vector2(47.0 if narrow else (53.0 if compact else 66.0),
			rect.size.y / 2.0 - (4.0 if compact else 2.0))
		draw_circle(portrait, portrait_r + 5.0, Palette.darker(hc, 0.32))
		draw_arc(portrait, portrait_r + 5.0, _time * 0.45,
			_time * 0.45 + TAU * 0.78, 36, Palette.with_alpha(Palette.glow(hc, 1.4), 0.78), 3.0)
		draw_circle(portrait, portrait_r, Palette.darker(hc, 0.58))
		draw_circle(portrait + Vector2(0, portrait_r * 0.28), portrait_r * 0.8,
			Palette.with_alpha(hc, 0.35))
		HeroIcon.draw_symbol(self, hero.hero_id, portrait, portrait_r * 0.62)

		var chip := portrait + Vector2(-portrait_r * 0.72, -portrait_r * 0.72)
		draw_circle(chip, 11.0 if compact else 14.0, pcol)
		UiKit.draw_text(self, chip + Vector2(0, 1), str(hero.profile.index + 1),
			10 if compact else 12, Palette.TEXT_DARK, true, 2)

		var stat_y := portrait.y + portrait_r + (12.0 if compact else 17.0)
		var stats: Dictionary = hero.profile.stats
		UiKit.draw_text(self, Vector2(portrait.x, stat_y), "%d / %d / %d" % [
			int(stats.get("kos", 0)), int(stats.get("deaths", 0)), int(stats.get("assists", 0))],
			9 if compact else 12, Palette.TEXT_DIM, true, 2)

		var left := rect.position.x + (88.0 if narrow else (102.0 if compact else 126.0))
		var right := rect.end.x - 14.0
		var bar_y := rect.position.y + (10.0 if compact else 14.0)
		var bar_h := 18.0 if compact else 22.0
		var bar_rect := Rect2(left, bar_y, right - left, bar_h)
		var hp_frac: float = clampf(hero.hp / maxf(hero.max_hp, 1.0), 0.0, 1.0)
		draw_rect(bar_rect, Color(0.015, 0.025, 0.055, 0.9))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * hp_frac, bar_rect.size.y)),
			_hp_color(hp_frac))
		if hero.shield_hp > 0.0:
			var shield_frac: float = clampf(hero.shield_hp / maxf(hero.max_hp, 1.0),
				0.0, 1.0 - hp_frac)
			draw_rect(Rect2(bar_rect.position + Vector2(bar_rect.size.x * hp_frac, 0),
				Vector2(bar_rect.size.x * shield_frac, bar_rect.size.y)), Palette.SHIELD)
		var def: Dictionary = HeroDef.get_def(hero.hero_id)
		UiKit.draw_text(self, bar_rect.position + Vector2(8.0, bar_h / 2.0),
			str(def["name"]).to_upper(), 11 if compact else 14, Palette.TEXT_MAIN, false, 2)
		UiKit.draw_text(self, Vector2(bar_rect.end.x - (48.0 if compact else 58.0),
			bar_rect.position.y + bar_h / 2.0), "%d / %d" % [int(hero.hp), int(hero.max_hp)],
			10 if compact else 13, Palette.TEXT_MAIN, true, 2)

		var resource_y := bar_rect.end.y + 4.0
		if hero.res_type != "" and hero.res_max > 0.0:
			var resource_frac: float = clampf(hero.res / hero.res_max, 0.0, 1.0)
			draw_rect(Rect2(left, resource_y, right - left, 6.0 if compact else 8.0),
				Color(0.01, 0.02, 0.05, 0.86))
			draw_rect(Rect2(left, resource_y, (right - left) * resource_frac,
				6.0 if compact else 8.0), _resource_color(hero.res_type))
		resource_y += 10.0 if compact else 13.0
		var ult_frac: float = clampf(hero.ult_charge / 100.0, 0.0, 1.0)
		var ult_col := Palette.GOLD
		if not bool(hero.ult_unlocked()):
			# Lukittu ulti: lataus kertyy ja näkyy, mutta himmeänä ilman valmis-hehkua.
			ult_col = Palette.with_alpha(Palette.GOLD, 0.4)
		elif ult_frac >= 0.999:
			ult_col = Palette.glow(Palette.GOLD, 1.25 + 0.18 * sin(_time * 6.0))
		draw_rect(Rect2(left, resource_y, right - left, 5.0 if compact else 7.0),
			Color(0.01, 0.02, 0.05, 0.86))
		draw_rect(Rect2(left, resource_y, (right - left) * ult_frac,
			5.0 if compact else 7.0), ult_col)

		var slots := _slot_data(hero)
		var slot_rects := _slot_rects()
		var first_slot: Rect2 = slot_rects[0]
		var last_slot: Rect2 = slot_rects[slot_rects.size() - 1]
		for i in range(slots.size()):
			_draw_ability_slot(slot_rects[i], slots[i], not narrow)

		# MOBA: lompakko kykyrivin vasemmalla puolella ja 6 itemin minirivi
		# oikealla puolella (kauppa täyttää; ikonit ItemIconista).
		if arena != null and arena.mode == "moba":
			var mini_y := first_slot.get_center().y
			var wx := left + 8.0
			_draw_diamond(Vector2(wx, mini_y), 5.0, Palette.glow(Palette.GOLD, 1.2))
			UiKit.draw_text(self, Vector2(wx + 11.0, mini_y + 4.0),
				str(hero.profile.wallet()), 12 if compact else 15,
				Palette.glow(Palette.GOLD, 1.1), false, 2)
			# Itemiaktiivin jäähdytys (D-pad vasen / G) lompakon vieressä:
			# ikoni + täyttyvä kaari; valmis aktiivi hehkuu.
			var act_id := str(hero.first_active_item())
			if act_id != "":
				var act_c := Vector2(wx + (58.0 if compact else 72.0), mini_y)
				var act_r := 8.0 if compact else 10.0
				ItemIcon.draw(self, act_id, act_c, act_r)
				var act_left: float = float(hero.item_active_cd.get(act_id, 0.0))
				var act_max: float = float(Hero.ITEM_ACTIVE_CD.get(act_id, 45.0))
				var act_frac: float = 1.0 - clampf(act_left / maxf(act_max, 0.01), 0.0, 1.0)
				if act_frac < 1.0:
					draw_circle(act_c, act_r, Color(0, 0, 0, 0.55))
					draw_arc(act_c, act_r + 2.5, -PI / 2.0, -PI / 2.0 + TAU * act_frac,
						22, Palette.glow(Palette.GOLD, 1.2), 2.0)
					UiKit.draw_text(self, act_c + Vector2(0, 1),
						str(int(ceil(act_left))), 8 if compact else 10,
						Palette.TEXT_MAIN, true, 2)
				else:
					draw_arc(act_c, act_r + 2.5, 0.0, TAU, 22,
						Palette.glow(Palette.GOLD, 1.2 + 0.2 * sin(_time * 5.0)), 2.0)
				# Näppäinvihje: D-pad vasen (piirretty nuoli) tai G-kirjain.
				var key_c := act_c + Vector2(0, act_r + (8.0 if compact else 10.0))
				if hero.profile.device >= 0:
					draw_colored_polygon(PackedVector2Array([
						key_c + Vector2(-4, 0), key_c + Vector2(2, -4),
						key_c + Vector2(2, 4)]), Palette.TEXT_DIM)
				else:
					UiKit.draw_text(self, key_c, "G", 7 if compact else 8,
						Palette.TEXT_DIM, true, 1)
			var items_arr: Array = hero.items
			var ir := 7.0 if narrow else 10.0
			var avail := right - last_slot.end.x - 8.0
			var istep := minf(ir * 2.0 + 4.0, (avail - ir * 2.0) / 5.0)
			var ix0 := last_slot.end.x + 8.0 + ir
			for s in range(Hero.MAX_ITEMS):
				var ic := Vector2(ix0 + float(s) * istep, mini_y)
				if s < items_arr.size():
					ItemIcon.draw(self, str(items_arr[s]), ic, ir)
				else:
					draw_circle(ic, ir * 0.85, Color(0, 0, 0, 0.35))
					draw_arc(ic, ir * 0.85, 0.0, TAU, 14,
						Palette.with_alpha(Palette.TEXT_DIM, 0.3), 1.0)

		# Käyttämättömät kykypisteet: sykkivä kultamerkki muotokuvan kulmassa ja
		# lyhyt kehitysohje telakan yllä (piilossa simulaatiossa).
		if int(hero.skill_points) > 0 and hero.alive and not Game.simulating:
			var badge := portrait + Vector2(portrait_r * 0.72, -portrait_r * 0.72)
			draw_circle(badge, 11.0 if compact else 14.0,
				Palette.glow(Palette.GOLD, 1.05 + 0.25 * sin(_time * 5.0)))
			UiKit.draw_text(self, badge + Vector2(0, 1), "+%d" % int(hero.skill_points),
				10 if compact else 12, Palette.TEXT_DARK, true, 2)
			var pad_hint: bool = hero.profile.device >= 0
			_push_hint("KEHITÄ: PIDÄ D-PAD YLÖS + KYKYNAPPI" if pad_hint \
				else "KEHITÄ: PIDÄ T + KYKYNAPPI",
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.2),
					0.7 + 0.3 * sin(_time * 5.0)), 0)

		if hero.carrying:
			var gem := rect.position + Vector2(18, 18)
			_draw_diamond(gem, 8.0 + sin(_time * 6.0), Palette.glow(Palette.GOLD, 1.5))

		# Baron-artefakti hallussa: kultachippi muotokuvan yllä muistuttaa,
		# että legendaarinen esine on ostettavissa (ja menetettävissä kuollessa).
		if bool(hero.legendary_artifact):
			var art_chip := portrait + Vector2(0, -portrait_r - (8.0 if compact else 10.0))
			_draw_diamond(art_chip, (6.0 if compact else 7.5) + sin(_time * 5.0),
				Palette.glow(Palette.GOLD, 1.4))
			UiKit.draw_text(self, art_chip + Vector2(0, -(9.0 if compact else 12.0)),
				"ARTEFAKTI", 7 if compact else 9,
				Palette.glow(Palette.GOLD, 1.15), true, 2)

		if not hero.alive:
			_panel(rect, Color(0.025, 0.035, 0.075, 0.88), Palette.with_alpha(Palette.BAD, 0.72),
				17.0, 2.0)
			UiKit.draw_text(self, rect.get_center() + Vector2(0, -12),
				str(int(ceil(hero.respawn_timer))), 38 if compact else 52, Palette.TEXT_MAIN, true, 5)
			UiKit.draw_text(self, rect.get_center() + Vector2(0, 24), "PALAA TAISTELUUN",
				12 if compact else 16, Palette.BAD, true, 3)
			# Kuolleena voi käydä kaupassa (respawn on lähteellä).
			if arena != null and arena.mode == "moba" and not Game.simulating \
					and hero.profile.is_human() and not bool(hero.shop_open):
				var dead_pad: bool = hero.profile.device >= 0
				UiKit.draw_text(self, rect.get_center() + Vector2(0, 44.0 if compact else 48.0),
					"KAUPPA AUKI KUOLLEENA: YMPYRÄ" if dead_pad else "KAUPPA AUKI KUOLLEENA: F",
					9 if compact else 11,
					Palette.with_alpha(Palette.glow(Palette.GOLD, 1.15),
						0.65 + 0.35 * sin(_time * 4.0)), true, 2)


	## Kykypaikkojen järjestys telakassa ja korteissa (sama kaikkialla).
	const SLOT_ORDER := ["basic", "a1", "a2", "ult", "dodge"]


	## Kykypaikkojen nappilyhenteet pelaajan oman laitteen mukaan, SLOT_ORDERissa.
	func _slot_keys() -> Array:
		var pad: bool = bound_hero != null and is_instance_valid(bound_hero) \
			and bound_hero.profile != null and int(bound_hero.profile.device) >= 0
		if pad:
			return ["R2", "R1", "L1", "L2", "X"]
		return ["M1", "M2", "Q", "E", "SPACE"]


	## Miksi kyky ei tottele juuri nyt — yksi sana telakan ruudun alle. Tämä
	## näkyy AINA, ei vain tietonäkymässä: pelaajan pitää nähdä yhdellä
	## vilkaisulla onko syy lukko, vaimennus, jäähdytys vai resurssi.
	func _slot_block_reason(hero, slot: String, cd: float) -> String:
		if slot == "ult" and not bool(hero.ult_unlocked()):
			return "LUKOSSA"
		# Vaimennus estää a1/a2/ultin ja väistön, muttei perushyökkäystä.
		if slot != "basic" and float(hero.silence_timer) > 0.0:
			return "VAIMENNETTU"
		if slot != "ult" and cd > 0.05:
			return "JÄÄHDYLLÄ"
		var res_type := str(hero.res_type)
		if res_type == "":
			return ""
		var cost: float = float(hero.res_cost.get(slot, 0.0)) \
			* float(hero.resource_cost_mult())
		if cost > 0.0 and float(hero.res) < cost:
			match res_type:
				"energy":
					return "EI ENERGIAA"
				"rage":
					return "EI RAIVOA"
			return "EI MANAA"
		return ""


	## Kykytelakan viiden paikan ruudut. Sama laskenta telakan piirrossa ja
	## tietonäkymän korteissa, jottei kortti karkaa paikkansa päältä.
	func _slot_rects() -> Array:
		var rect := _dock_rect()
		var compact := _compact()
		var narrow := _narrow()
		var left := rect.position.x + (88.0 if narrow else (102.0 if compact else 126.0))
		var right := rect.end.x - 14.0
		var slot_size := 48.0 if narrow else (56.0 if compact else 64.0)
		var gap := 7.0 if narrow else (14.0 if compact else 16.0)
		var total := 5.0 * slot_size + 4.0 * gap
		var sx := left + (right - left - total) / 2.0
		var sy := rect.position.y \
			+ (54.0 if compact and not narrow else (52.0 if narrow else 70.0))
		var out: Array = []
		for i in range(5):
			out.append(Rect2(sx + float(i) * (slot_size + gap), sy, slot_size, slot_size))
		return out


	func _slot_data(hero) -> Array:
		var spend: bool = bool(hero._spend_mode_active())
		var abilities: Dictionary = HeroDef.get_def(hero.hero_id)["abilities"]
		var key_list := _slot_keys()
		var out: Array = []
		for i in range(SLOT_ORDER.size()):
			var slot := str(SLOT_ORDER[i])
			var frac: float
			var cd := 0.0
			var col: Color = hero.hero_color()
			if slot == "ult":
				frac = clampf(hero.ult_charge / 100.0, 0.0, 1.0)
				col = Palette.GOLD
			else:
				cd = float(hero.cd[slot])
				frac = clampf(1.0 - cd / maxf(float(hero.cd_max[slot]), 0.001), 0.0, 1.0)
				if slot == "dodge":
					col = Palette.glow(col, 1.18)
			out.append({
				"hero_id": hero.hero_id, "slot": slot,
				"name": str(abilities[slot]["name"]), "key": str(key_list[i]),
				"frac": frac, "cd": cd, "color": col,
				"rank": int(hero.ability_ranks[slot]), "can_rank": bool(hero.can_rank(slot)),
				"locked": slot == "ult" and not bool(hero.ult_unlocked()), "spend": spend,
				"lock_level": (int(hero.ULT_RANK_LEVELS[0]) if slot == "ult" else 0),
				"reason": _slot_block_reason(hero, slot, cd),
			})
		return out


	func _draw_ability_slot(rect: Rect2, data: Dictionary, show_name: bool) -> void:
		var col: Color = data["color"]
		var frac := clampf(float(data["frac"]), 0.0, 1.0)
		var ready := frac >= 0.999
		_panel(Rect2(rect.position + Vector2(0, 3), rect.size), Color(0, 0, 0, 0.45),
			Color(0, 0, 0, 0), 10.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.darker(col, 0.34), 0.94) if ready \
			else Color(0.035, 0.045, 0.085, 0.96),
			Palette.with_alpha(Palette.glow(col, 1.25), 0.9 if ready else 0.38), 10.0, 2.0)
		if not ready:
			var cover_h := rect.size.y * (1.0 - frac)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, cover_h)), Color(0, 0, 0, 0.48))
		var center := rect.get_center() + Vector2(0, -3.0)
		_draw_ability_glyph(str(data["hero_id"]), str(data["slot"]), center, rect.size.x * 0.23,
			Palette.glow(col, 1.35) if ready else Palette.with_alpha(Palette.TEXT_DIM, 0.7))
		if float(data["cd"]) > 0.25:
			UiKit.draw_text(self, center + Vector2(0, 2), str(int(ceil(float(data["cd"])))),
				16 if rect.size.x < 58.0 else 20, Palette.TEXT_MAIN, true, 4)
		var rank := int(data.get("rank", 0))
		var locked := bool(data.get("locked", false))
		var spend_mode := bool(data.get("spend", false))
		var rankable := bool(data.get("can_rank", false))
		if locked:
			# Ulti lukossa avaukseen asti: tumma peite, lukkosymboli ja tasovaatimus.
			_panel(rect, Color(0.02, 0.03, 0.06, 0.74),
				Palette.with_alpha(Palette.TEXT_DIM, 0.42), 10.0, 1.5)
			var lc := center + Vector2(0, -4.0)
			draw_arc(lc + Vector2(0, -3.0), 5.0, PI, TAU, 10, Palette.TEXT_DIM, 2.2)
			draw_rect(Rect2(lc + Vector2(-6.5, -3.0), Vector2(13.0, 10.0)), Palette.TEXT_DIM)
			UiKit.draw_text(self, Vector2(center.x, rect.end.y - 24.0),
				"TASO %d" % int(data.get("lock_level", 4)), 9, Palette.TEXT_DIM, true, 2)
		# Rankkipippurit: kolme lovea yläreunassa, otetut rankit täyttyvät kullalla.
		var pip_w := 9.0
		var pip_x := rect.end.x - 5.0 - 3.0 * pip_w - 2.0 * 2.0
		for p in range(3):
			var pr := Rect2(pip_x + float(p) * (pip_w + 2.0), rect.position.y + 4.0, pip_w, 3.5)
			if rank > p:
				draw_rect(pr, Palette.glow(Palette.GOLD, 1.2))
			else:
				draw_rect(pr, Color(1, 1, 1, 0.1))
		# Kehitystila (pidä ylös/T): rankattavat paikat hehkuvat, muut himmenevät.
		if spend_mode and rankable:
			_panel(rect.grow(3.0), Color(0, 0, 0, 0),
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4),
					0.6 + 0.4 * sin(_time * 7.0)), 12.0, 2.5)
		elif spend_mode:
			draw_rect(rect, Color(0, 0, 0, 0.35))
		var key_rect := Rect2(rect.position.x + 4.0, rect.end.y - 17.0,
			minf(rect.size.x - 8.0, 38.0), 14.0)
		_panel(key_rect, Color(0.015, 0.025, 0.055, 0.84), Palette.with_alpha(col, 0.45),
			5.0, 1.0)
		UiKit.draw_text(self, key_rect.get_center(), str(data["key"]),
			8 if rect.size.x < 58.0 else 10, Palette.TEXT_MAIN, true, 1)
		var reason := str(data.get("reason", ""))
		if reason != "":
			# Estosyy voittaa nimen: pelaaja näkee heti miksi nappi ei tottele.
			var rcol: Color = Palette.TEXT_DIM
			if reason == "VAIMENNETTU" or reason.begins_with("EI "):
				rcol = Palette.BAD
			UiKit.draw_text(self, Vector2(rect.get_center().x, rect.end.y + 10.0),
				reason, 8 if _compact() else 10, rcol, true, 2)
		elif show_name:
			UiKit.draw_text(self, Vector2(rect.get_center().x, rect.end.y + 10.0),
				_short_name(str(data["name"]), 11 if _compact() else 14),
				10 if _compact() else 11, Palette.TEXT_DIM, true, 2)


	func _draw_ability_glyph(hero_id: String, slot: String, center: Vector2, r: float, col: Color) -> void:
		if hero_id == "salvo":
			_draw_salvo_glyph(slot, center, r, col)
			return
		if hero_id in ["kaira", "vesper", "myria", "torq"]:
			_draw_jungler_glyph(hero_id, slot, center, r, col)
			return
		match slot:
			"basic":
				draw_circle(center, r * 0.38, col)
				draw_arc(center, r * 0.8, -0.8, 0.8, 12, col, 2.0)
			"a1":
				var star := PackedVector2Array()
				for i in range(8):
					var rr := r if i % 2 == 0 else r * 0.42
					star.append(center + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * i / 8.0) * rr)
				draw_colored_polygon(star, col)
			"a2":
				_draw_diamond(center, r, col)
			"ult":
				for i in range(8):
					var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
					draw_line(center + dir * r * 0.45, center + dir * r, col, 2.2)
				draw_circle(center, r * 0.34, col)
			"dodge":
				for k in range(2):
					var x := -r * 0.6 + k * r * 0.75
					draw_line(center + Vector2(x - r * 0.25, -r * 0.65),
						center + Vector2(x + r * 0.3, 0), col, 2.6)
					draw_line(center + Vector2(x + r * 0.3, 0),
						center + Vector2(x - r * 0.25, r * 0.65), col, 2.6)


	func _draw_salvo_glyph(slot: String, center: Vector2, r: float, col: Color) -> void:
		match slot:
			"basic":
				draw_circle(center, r * 0.58, col)
				draw_line(center + Vector2(-r * 0.75, 0), center + Vector2(r * 0.75, 0), col, 2.4)
				draw_line(center + Vector2(0, -r * 0.75), center + Vector2(0, r * 0.75), col, 2.4)
			"a1":
				draw_circle(center, r * 0.52, col)
				for i in range(6):
					var spike := Vector2.RIGHT.rotated(TAU * i / 6.0)
					draw_line(center + spike * r * 0.45, center + spike * r, col, 2.6)
				draw_circle(center, r * 0.16, Color(0.03, 0.04, 0.07, 0.9))
			"a2":
				# Korkea kaari ja maalin rengas kertovat suoraan morttarin toiminnan.
				var points := PackedVector2Array()
				for i in range(9):
					var f := float(i) / 8.0
					points.append(center + Vector2(lerpf(-r, r * 0.65, f),
						-r * 0.8 * sin(f * PI) + r * 0.2))
				draw_polyline(points, col, 2.4)
				var landing := center + Vector2(r * 0.72, r * 0.48)
				draw_arc(landing, r * 0.35, 0.0, TAU, 14, col, 2.0)
				draw_circle(landing, r * 0.10, col)
			"ult":
				# Panssarikupoli + ulos lähtevä raskas ohjus.
				draw_arc(center + Vector2(-r * 0.25, r * 0.2), r * 0.62, PI, TAU, 16, col, 3.0)
				draw_line(center + Vector2(-r * 0.92, r * 0.22),
					center + Vector2(r * 0.18, r * 0.22), col, 3.0)
				var nose := center + Vector2(r, -r * 0.45)
				draw_colored_polygon(PackedVector2Array([
					nose, center + Vector2(r * 0.25, -r * 0.78),
					center + Vector2(r * 0.2, -r * 0.18)]), col)
			"dodge":
				for side in [-1.0, 1.0]:
					draw_arc(center + Vector2(side * r * 0.25, 0), r * 0.72,
						-PI * 0.85, -PI * 0.15, 10, col, 2.5)


	func _draw_jungler_glyph(hero_id: String, slot: String, center: Vector2,
			r: float, col: Color) -> void:
		match hero_id:
			"kaira":
				match slot:
					"a1":
						# Sulasyöksy: nuoli eteen ja kolme laavalammikkoa vanaan.
						draw_line(center + Vector2(-r, 0), center + Vector2(r * 0.55, 0), col, 3.0)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, 0), center + Vector2(r * 0.42, -r * 0.42),
							center + Vector2(r * 0.42, r * 0.42)]), col)
						for k in range(3):
							draw_circle(center + Vector2(-r * 0.8 + k * r * 0.55, r * 0.62),
								r * 0.16, col)
					"a2":
						# Maanjyrä: piikkirengas ulospäin.
						for k in range(8):
							var ray := Vector2.RIGHT.rotated(TAU * k / 8.0)
							draw_line(center + ray * r * 0.3, center + ray * r, col, 2.6)
						draw_arc(center, r * 0.3, 0.0, TAU, 12, col, 2.0)
					"dodge":
						# Kaivautuminen: kaari maan alle ja purkaus ulos.
						draw_arc(center + Vector2(0, -r * 0.35), r * 0.8, PI * 0.1, PI * 0.9,
							14, col, 2.8)
						draw_line(center + Vector2(-r * 0.9, r * 0.7),
							center + Vector2(r * 0.9, r * 0.7), col, 2.4)
					"ult":
						# Sulakita: pitkä repeämä + purkautuvat kielekkeet.
						draw_line(center + Vector2(-r, r * 0.15), center + Vector2(r, -r * 0.15),
							col, 4.0)
						for k in range(3):
							var x := -r * 0.6 + k * r * 0.6
							draw_line(center + Vector2(x, 0), center + Vector2(x - r * 0.1, -r * 0.8),
								col, 2.4)
					_:
						# Poranterä: sivulle osoittava kartio hammastuksella.
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, 0), center + Vector2(-r * 0.5, -r * 0.62),
							center + Vector2(-r * 0.5, r * 0.62)]), col)
						for k in range(3):
							var f := 0.25 + k * 0.25
							draw_line(center + Vector2(lerpf(-r * 0.5, r, f), -r * 0.5 * (1.0 - f)),
								center + Vector2(lerpf(-r * 0.5, r, f), r * 0.5 * (1.0 - f)),
								Color(0.03, 0.04, 0.07, 0.75), 1.8)
			"vesper":
				match slot:
					"a1":
						# Fosforipiikki: läpäisevä piikki + merkkirengas kärjessä.
						draw_line(center + Vector2(-r, r * 0.3), center + Vector2(r * 0.4, -r * 0.2),
							col, 2.8)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r * 0.75, -r * 0.35),
							center + Vector2(r * 0.2, -r * 0.35),
							center + Vector2(r * 0.42, r * 0.1)]), col)
						draw_arc(center + Vector2(r * 0.5, -r * 0.35), r * 0.42, 0.0, TAU, 14, col, 1.8)
					"a2":
						# Teloitus: laskeva vahinkopalkki ja lävistävä keihäs.
						for k in range(3):
							var h := r * (0.85 - k * 0.28)
							draw_line(center + Vector2(-r * 0.8 + k * r * 0.4, r * 0.75),
								center + Vector2(-r * 0.8 + k * r * 0.4, r * 0.75 - h), col, 3.0)
						draw_line(center + Vector2(r * 0.05, r * 0.5),
							center + Vector2(r, -r * 0.6), col, 2.8)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, -r * 0.85), center + Vector2(r * 0.5, -r * 0.4),
							center + Vector2(r * 0.95, -r * 0.25)]), col)
					"dodge":
						# Fosforiloikka: kaari ja laskeutumisrengas.
						draw_arc(center + Vector2(0, r * 0.5), r * 0.9, PI * 1.05, PI * 1.95,
							14, col, 2.8)
						draw_arc(center + Vector2(r * 0.7, r * 0.55), r * 0.3, 0.0, TAU, 12, col, 2.0)
					"ult":
						# Fosforisalama: pitkä ohut kiskolaukaus.
						draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), col, 4.0)
						for k in [-1.0, 1.0]:
							draw_line(center + Vector2(-r * 0.85, k * r * 0.45),
								center + Vector2(r * 0.6, k * r * 0.45),
								Color(col.r, col.g, col.b, col.a * 0.55), 1.8)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, 0), center + Vector2(r * 0.3, -r * 0.42),
							center + Vector2(r * 0.3, r * 0.42)]), col)
					_:
						# Fosforipultti: yksinkertainen nuolikärki.
						draw_line(center + Vector2(-r * 0.9, 0), center + Vector2(r * 0.35, 0), col, 2.6)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, 0), center + Vector2(r * 0.25, -r * 0.42),
							center + Vector2(r * 0.25, r * 0.42)]), col)
			"myria":
				match slot:
					"a1":
						# Kukkaistutus: yksi orkidea varren päässä.
						_draw_petals(center + Vector2(0, -r * 0.2), r * 0.72, col, 6)
						draw_line(center + Vector2(0, r * 0.25), center + Vector2(0, r), col, 2.4)
					"a2":
						# Kukinta: kolme puhkeavaa kukkaa ulospäin.
						for i in range(3):
							var d := Vector2.RIGHT.rotated(TAU * i / 3.0 - PI * 0.5)
							_draw_petals(center + d * r * 0.55, r * 0.42, col, 5)
					"dodge":
						# Terälehtiliuku: kolme sivuun lentävää terälehteä.
						for i in range(3):
							var y := (float(i) - 1.0) * r * 0.5
							draw_colored_polygon(PackedVector2Array([
								center + Vector2(-r, y), center + Vector2(r * 0.2, y - r * 0.22),
								center + Vector2(r, y * 0.4), center + Vector2(r * 0.2, y + r * 0.22)]),
								Color(col.r, col.g, col.b, col.a * (0.5 + 0.25 * float(i))))
					"ult":
						# Orkideapuutarha: kehäkukat ja iso keskuskukka.
						for i in range(5):
							var d := Vector2.RIGHT.rotated(TAU * i / 5.0 - PI * 0.5)
							draw_circle(center + d * r * 0.82, r * 0.15, col)
						_draw_petals(center, r * 0.55, col, 6)
					_:
						# Siitepölysyöksy: itiöpallo ja pieni pölyvana.
						draw_circle(center + Vector2(r * 0.25, 0), r * 0.42, col)
						for k in range(3):
							draw_circle(center + Vector2(-r * 0.45 - k * r * 0.22, 0),
								r * (0.16 - k * 0.04),
								Color(col.r, col.g, col.b, col.a * (0.7 - 0.18 * float(k))))
			"torq":
				match slot:
					"a1":
						# Magneettikoukku: ketju ja tarttuva kynsi.
						draw_line(center + Vector2(-r, r * 0.4), center + Vector2(r * 0.3, -r * 0.2),
							col, 2.6)
						draw_arc(center + Vector2(r * 0.5, -r * 0.35), r * 0.42,
							-PI * 0.85, PI * 0.35, 12, col, 3.0)
					"a2":
						# Napalukko: nuolet sisäänpäin keskustaan.
						for i in range(4):
							var d := Vector2.RIGHT.rotated(TAU * i / 4.0 + PI * 0.25)
							draw_line(center + d * r, center + d * r * 0.32, col, 2.6)
							draw_colored_polygon(PackedVector2Array([
								center + d * r * 0.22,
								center + d * r * 0.58 + d.orthogonal() * r * 0.2,
								center + d * r * 0.58 - d.orthogonal() * r * 0.2]), col)
						draw_circle(center, r * 0.16, col)
					"dodge":
						# Magneettiliuku: kaksi vauhtiviivaa sivuun.
						for k in range(2):
							var y := (float(k) - 0.5) * r * 0.8
							draw_line(center + Vector2(-r, y), center + Vector2(r * 0.45, y),
								col, 2.6)
						draw_colored_polygon(PackedVector2Array([
							center + Vector2(r, 0), center + Vector2(r * 0.35, -r * 0.5),
							center + Vector2(r * 0.35, r * 0.5)]), col)
					"ult":
						# Napakenttä: sisäänpäin kaartuvat kenttäviivat.
						for i in range(6):
							var a := TAU * i / 6.0
							var pts := PackedVector2Array()
							for k in range(4):
								var kf := float(k) / 3.0
								pts.append(center + Vector2.RIGHT.rotated(a + kf * 1.0)
									* lerpf(r, r * 0.14, kf))
							draw_polyline(pts, col, 2.2)
						draw_circle(center, r * 0.2, col)
					_:
						# Magneettivasara: hevosenkenkä kaksine napoineen.
						draw_arc(center, r * 0.68, PI * 0.22, PI * 1.78, 18, col, 4.0)
						draw_circle(center + Vector2.RIGHT.rotated(PI * 0.22) * r * 0.68,
							r * 0.19, col)
						draw_circle(center + Vector2.RIGHT.rotated(PI * 1.78) * r * 0.68,
							r * 0.19, col)


	## Kuuden terälehden kukka Myrian glyfeihin.
	func _draw_petals(center: Vector2, r: float, col: Color, petals: int) -> void:
		for i in range(petals):
			var d := Vector2.RIGHT.rotated(TAU * i / float(petals) - PI * 0.5)
			draw_colored_polygon(PackedVector2Array([
				center + d * r * 0.16,
				center + d * r * 0.65 + d.orthogonal() * r * 0.3,
				center + d * r,
				center + d * r * 0.65 - d.orthogonal() * r * 0.3]), col)
		draw_circle(center, r * 0.22, Color(0.03, 0.04, 0.07, 0.85))


	func _short_name(text: String, max_chars: int) -> String:
		if text.length() <= max_chars:
			return text
		return text.substr(0, maxi(max_chars - 1, 1)) + "…"


	## Rivittää tekstin sanoittain enintään max_chars-merkkisiin riveihin.
	func _wrap_text(text: String, max_chars: int) -> Array:
		var out: Array = []
		if text.strip_edges() == "":
			return out
		var line := ""
		for word_v in text.split(" "):
			var word := str(word_v)
			var candidate := word if line == "" else line + " " + word
			if candidate.length() > max_chars and line != "":
				out.append(line)
				line = word
			else:
				line = candidate
		if line != "":
			out.append(line)
		return out


	## Sykkivä kauppavihje kun kauppa on käytettävissä muttei auki: elossa
	## omassa sanctuaryssa. (Kuolleen vihje piirretään telakan kuolinpeitteeseen.)
	func _draw_shop_prompt() -> void:
		var hero = bound_hero
		if arena == null or arena.mode != "moba" or Game.simulating:
			return
		if hero.profile == null or hero.profile.is_bot or bool(hero.shop_open):
			return
		if not hero.alive:
			return
		if arena.map == null or not arena.map.has_method("is_in_own_sanctuary"):
			return
		if not bool(arena.map.is_in_own_sanctuary(hero.global_position, hero.team)):
			return
		var pad: bool = hero.profile.device >= 0
		_push_hint("KAUPPA: YMPYRÄ" if pad else "KAUPPA: F",
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.15),
				0.65 + 0.35 * sin(_time * 4.0)), 1)


	## Koko ruudun kauppa-overlay TÄLLE pelaajalle (per-pane, kuten spend-tila).
	## Tila ja syötteet elävät hero.shop:ssa (ShopMenu); tämä vain piirtää.
	func _draw_shop() -> void:
		var hero = bound_hero
		var menu = hero.shop
		if menu == null:
			return
		var compact := _compact()
		var pcol: Color = hero.profile.color()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.022, 0.055, 0.86))
		var w: float = minf(size.x - (30.0 if compact else 60.0), 1440.0)
		var h: float = minf(size.y - (26.0 if compact else 50.0), 850.0)
		var px := (size.x - w) / 2.0
		var py := (size.y - h) / 2.0
		# Osto-/estopalaute värjää kehyksen hetkeksi (vihreä/punainen välähdys).
		var border: Color = Palette.with_alpha(pcol, 0.75)
		if float(menu.flash_t) > 0.0:
			border = Palette.with_alpha(Palette.GOOD, 0.5 + float(menu.flash_t))
		elif float(menu.flash_t) < 0.0:
			border = Palette.with_alpha(Palette.BAD, 0.5 - float(menu.flash_t))
		_panel(Rect2(px, py, w, h), Palette.with_alpha(Palette.UI_PANEL, 0.97),
			border, 16.0, 2.0)

		# Otsikko: KAUPPA + lompakko (kultatimantti + saldo).
		UiKit.draw_text(self, Vector2(px + 24.0, py + (24.0 if compact else 32.0)),
			"KAUPPA", 18 if compact else 26, Palette.glow(Palette.GOLD, 1.15), false, 3)
		var wallet := int(hero.profile.wallet())
		var wpos := Vector2(px + w - (150.0 if compact else 190.0),
			py + (18.0 if compact else 24.0))
		_draw_diamond(wpos, 6.0 if compact else 8.0, Palette.glow(Palette.GOLD, 1.3))
		UiKit.draw_text(self, wpos + Vector2(12.0, 6.0), str(wallet),
			16 if compact else 22, Palette.glow(Palette.GOLD, 1.15), false, 3)

		# Välilehdet (L1/R1 tai Q/E).
		var ty := py + (34.0 if compact else 48.0)
		var tab_count: int = ShopMenu.TABS.size()
		var tw := (w - 40.0) / float(tab_count)
		for t in range(tab_count):
			var tx := px + 20.0 + tw * float(t)
			var active: bool = t == int(menu.tab)
			if active:
				draw_rect(Rect2(tx + 4.0, ty + (20.0 if compact else 26.0), tw - 8.0, 2.5),
					Palette.glow(Palette.GOLD, 1.25))
			UiKit.draw_text(self, Vector2(tx + tw / 2.0, ty + (11.0 if compact else 14.0)),
				str(ShopMenu.TABS[t]), 9 if compact else 13,
				Palette.TEXT_MAIN if active else Palette.TEXT_DIM, true, 2)

		# Alarivin (inventaario) ja vihjerivin mitat ensin -> ruudukon korkeus.
		var hint_y := py + h - (14.0 if compact else 20.0)
		var inv_h := 46.0 if compact else 62.0
		var iy := hint_y - (10.0 if compact else 14.0) - inv_h

		# Ruudukko: tier-sarakkeet Common | Rare | Epic | Legendary.
		var gx := px + 16.0
		var gy := ty + (26.0 if compact else 36.0)
		var gw := w * 0.63
		var cw := gw / 4.0
		var rh := 22.0 if compact else 30.0
		var rows_top := gy + (18.0 if compact else 24.0)
		var max_rows := int((iy - 8.0 - rows_top) / rh)
		var owned: Array = hero.items
		for ci in range(4):
			var cx := gx + cw * float(ci)
			var tier := str(ShopMenu.TIER_ORDER[ci])
			UiKit.draw_text(self, Vector2(cx + cw / 2.0, gy + 6.0),
				str(ShopMenu.TIER_LABELS[tier]), 8 if compact else 11,
				ItemIcon.tier_color(tier), true, 2)
			var colc: Array = (menu.columns as Array)[ci]
			for ri in range(mini(colc.size(), max_rows)):
				var id := str(colc[ri])
				var ry := rows_top + rh * float(ri)
				var rrect := Rect2(cx + 2.0, ry, cw - 6.0, rh - 2.0)
				var selected: bool = not bool(menu.in_inventory) \
					and int(menu.col) == ci and int(menu.row) == ri
				if selected:
					_panel(rrect, Palette.with_alpha(pcol, 0.14),
						Palette.glow(pcol, 1.3), 6.0, 1.5)
				var icx := Vector2(rrect.position.x + rh * 0.55, ry + rh / 2.0 - 2.0)
				ItemIcon.draw(self, id, icx, 7.0 if compact else 9.0)
				var item := ItemDef.get_item(id)
				UiKit.draw_text(self,
					Vector2(icx.x + (11.0 if compact else 15.0), ry + rh / 2.0 + 2.0),
					_short_name(str(item.get("name", id)), 9 if compact else 13),
					9 if compact else 12,
					Palette.GOOD if owned.has(id) else Palette.TEXT_MAIN, false, 1)
				var price := ItemDef.combine_cost(id, owned)
				UiKit.draw_text(self,
					Vector2(rrect.end.x - (16.0 if compact else 22.0), ry + rh / 2.0 + 2.0),
					str(price), 9 if compact else 11,
					Palette.glow(Palette.GOLD, 1.05) if price <= wallet else Palette.BAD,
					true, 1)

		# Detaljipaneeli: valitun itemin hinta, statit, kuvaus ja buildipuu.
		var dx0 := gx + gw + 12.0
		var dw := px + w - 16.0 - dx0
		var drect := Rect2(dx0, gy, dw, iy - 8.0 - gy)
		_panel(drect, Palette.with_alpha(Palette.UI_PANEL_LIGHT, 0.6),
			Palette.with_alpha(Palette.UI_STROKE, 0.5), 10.0, 1.0)
		var sel := str(menu.selected_id(hero))
		var ly := gy + (18.0 if compact else 26.0)
		var step := 14.0 if compact else 19.0
		if sel != "":
			var sitem := ItemDef.get_item(sel)
			var stier := str(sitem.get("tier", "common"))
			ItemIcon.draw(self, sel, Vector2(dx0 + (20.0 if compact else 28.0), ly - 2.0),
				11.0 if compact else 16.0)
			UiKit.draw_text(self, Vector2(dx0 + (38.0 if compact else 52.0), ly + 4.0),
				str(sitem.get("name", sel)), 13 if compact else 18,
				ItemIcon.tier_color(stier), false, 2)
			UiKit.draw_text(self, Vector2(dx0 + (38.0 if compact else 52.0), ly + step + 2.0),
				str(ShopMenu.TIER_LABELS.get(stier, "")), 8 if compact else 10,
				Palette.TEXT_DIM, false, 1)
			ly += step * 2.2
			var total_cost := int(sitem.get("cost", 0))
			var combine := ItemDef.combine_cost(sel, owned)
			UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0), "HINTA %d" % total_cost,
				10 if compact else 13, Palette.glow(Palette.GOLD, 1.1), false, 2)
			if combine != total_cost:
				ly += step
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0),
					"SINULLE %d (osat hyvitetty)" % combine, 10 if compact else 13,
					Palette.GOOD if combine <= wallet else Palette.BAD, false, 2)
			ly += step * 1.3
			for line_v in ShopMenu.stat_lines(sitem):
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0), str(line_v),
					9 if compact else 12, Palette.TEXT_MAIN, false, 1)
				ly += step * 0.9
			var desc := str(sitem.get("desc", ""))
			if str(sitem.get("passive", "")) != "" or str(sitem.get("active", "")) != "":
				ly += step * 0.4
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0),
					"AKTIIVI" if str(sitem.get("active", "")) != "" else "PASSIIVI",
					8 if compact else 10, Palette.glow(Palette.GOLD, 1.05), false, 1)
				ly += step * 0.8
				for dl in _wrap_text(desc, 34 if compact else 38):
					UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0), str(dl),
						8 if compact else 11, Palette.TEXT_DIM, false, 1)
					ly += step * 0.8
			var comps: Array = sitem.get("builds_from", [])
			if not comps.is_empty():
				ly += step * 0.5
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0), "RAKENTUU:",
					8 if compact else 10, Palette.TEXT_DIM, false, 1)
				ly += step * 0.85
				for comp_v in comps:
					var comp := str(comp_v)
					var comp_owned: bool = owned.has(comp)
					if comp_owned:
						# Piirretty väkänen (glyffi ei ole varmasti fontissa).
						var chk := Vector2(dx0 + 20.0, ly - 1.0)
						draw_line(chk + Vector2(-4, 0), chk + Vector2(-1, 3),
							Palette.GOOD, 2.0)
						draw_line(chk + Vector2(-1, 3), chk + Vector2(5, -4),
							Palette.GOOD, 2.0)
					UiKit.draw_text(self, Vector2(dx0 + 30.0, ly + 2.0),
						str(ItemDef.get_item(comp).get("name", comp)),
						9 if compact else 12,
						Palette.GOOD if comp_owned else Palette.TEXT_MAIN, false, 1)
					ly += step * 0.85
			if bool(sitem.get("require_artifact", false)):
				ly += step * 0.5
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0),
					"VAATII: LEGENDAARINEN ARTEFAKTI", 9 if compact else 12,
					Palette.GOOD if bool(hero.legendary_artifact) else Palette.BAD,
					false, 2)
				ly += step * 0.85
			if bool(menu.in_inventory):
				ly += step * 0.5
				UiKit.draw_text(self, Vector2(dx0 + 14.0, ly + 2.0),
					"MYYNTI: +%dG" % ShopMenu.sell_value(sel), 9 if compact else 12,
					Palette.glow(Palette.GOLD, 1.1), false, 2)
		if str(menu.flash_msg) != "" and float(menu.flash_t) < 0.0:
			UiKit.draw_text(self, Vector2(drect.get_center().x, drect.end.y - 14.0),
				str(menu.flash_msg), 10 if compact else 13, Palette.BAD, true, 2)

		# Oma inventaario (6 paikkaa): valinta alas ruudukosta, Kolmio/T myy.
		UiKit.draw_text(self, Vector2(px + 24.0, iy + inv_h / 2.0 + 4.0), "TAVARAT",
			10 if compact else 13, Palette.TEXT_DIM, false, 2)
		var cell := 36.0 if compact else 48.0
		var inv_x := px + (86.0 if compact else 110.0)
		for i in range(Hero.MAX_ITEMS):
			var crect := Rect2(inv_x + float(i) * (cell + 8.0),
				iy + (inv_h - cell) / 2.0, cell, cell)
			draw_rect(crect, Color(0, 0, 0, 0.4))
			var sel_inv: bool = bool(menu.in_inventory) and int(menu.inv_index) == i
			draw_rect(crect, Palette.glow(pcol, 1.3) if sel_inv \
				else Palette.with_alpha(Palette.TEXT_DIM, 0.3), false,
				2.0 if sel_inv else 1.0)
			if i < owned.size():
				ItemIcon.draw(self, str(owned[i]), crect.get_center(), cell * 0.3)
		UiKit.draw_text(self, Vector2(inv_x + 6.0 * (cell + 8.0) + (54.0 if compact else 80.0),
			iy + inv_h / 2.0 + 3.0), "MYYNTI 70 %", 9 if compact else 12,
			Palette.TEXT_DIM, true, 1)

		# Ohjevihjeet laitteen mukaan.
		var pad: bool = hero.profile.device >= 0
		var hint := "L1/R1 VÄLILEHTI    RISTI OSTA    KOLMIO MYY    YMPYRÄ SULJE" if pad \
			else "Q/E VÄLILEHTI    ENTER OSTA    T MYY    F SULJE"
		UiKit.draw_text(self, Vector2(px + w / 2.0, hint_y), hint,
			9 if compact else 13, Palette.TEXT_DIM, true, 2)


	# --- Tietonäkymä: statipaneeli ja kykykortit (pidä D-pad oikea / C) ---

	## Pitääkö TÄMÄN ruudun pelaaja tietonappia pohjassa? Luetaan suoraan
	## ohjaimelta kuten kehitystila. Pelkkä UI-luku: taistelulogiikka ei tunne
	## nappia lainkaan, ja has_method-vartija pitää botit ja vanhat ohjaimet
	## ulkona (BotBrain ei toteuta inspect_held-metodia).
	func _inspect_held() -> bool:
		var hero = bound_hero
		if hero == null or not is_instance_valid(hero) or hero.profile == null:
			return false
		if not bool(hero.profile.is_human()):
			return false
		var ctrl = hero.controller
		if ctrl == null or not ctrl.has_method("inspect_held"):
			return false
		if ctrl.has_method("is_bot") and bool(ctrl.is_bot()):
			return false
		return bool(ctrl.inspect_held())


	## Näytetäänkö tietonäkymä juuri nyt. Poissulkeva kaikkien muiden
	## päällysten kanssa: simulaatio, kauppa ja tulostaulu voittavat aina.
	func _inspect_active() -> bool:
		if arena == null or Game.simulating or scoreboard_open:
			return false
		var hero = bound_hero
		if hero == null or not is_instance_valid(hero) or hero.profile == null:
			return false
		if bool(hero.shop_open):
			return false
		return _inspect_held()


	## Tietonäkymän näppäinvihje pelaajan oman laitteen mukaan.
	func _inspect_key_hint() -> String:
		if bound_hero != null and is_instance_valid(bound_hero) \
				and bound_hero.profile != null and int(bound_hero.profile.device) >= 0:
			return "PIDÄ D-PAD OIKEA"
		return "PIDÄ C"


	## Tietonäkymän vapaa alue: telakan yläpuolelta ylös, minikartan VASEMMALLE
	## puolelle ja KO-syötteen alle. Näin paneeli ei koskaan peitä minikarttaa,
	## tapahtumia eikä yläreunan mittareita missään ruutujaossa.
	func _inspect_band() -> Rect2:
		var dock := _dock_rect()
		var mini := _minimap_rect()
		var compact := _compact()
		var left := _margin()
		var right: float = minf(size.x - _margin(), mini.position.x - 10.0)
		var top: float = _margin() + (96.0 if compact else 132.0)
		var feed_w := 300.0 if compact else 360.0
		if not _feed.is_empty() and right > size.x - _margin() - feed_w:
			top = maxf(top, _margin() + (72.0 if compact else 90.0)
				+ float(_feed.size()) * (27.0 if compact else 34.0) + 6.0)
		var bottom := dock.position.y - 8.0
		return Rect2(left, top, maxf(right - left, 20.0), maxf(bottom - top, 20.0))


	## "itemit +18 %" -lähdemerkintä; tyhjä jos itemeistä ei tule mitään.
	func _item_note(value: float) -> String:
		if absf(value) < 0.005:
			return ""
		return "itemit +%d %%" % int(round(value * 100.0))


	func _resource_name(type: String) -> String:
		match type:
			"mana":
				return "Mana"
			"energy":
				return "Energia"
			"rage":
				return "Raivo"
		return "Resurssi"


	## Yksi statirivi: nimi, luku ja valinnainen lähde ("mistä tämä tulee").
	func _stat_row(label: String, value: String, note := "",
			color := Palette.TEXT_MAIN) -> Dictionary:
		return {"kind": "row", "label": label, "value": value, "note": note,
			"color": color}


	## Kykypaikan rankkirivi: kolme pipsua + paikan voimakerroin.
	func _rank_row(label: String, rank: int, value: String,
			color := Palette.TEXT_MAIN) -> Dictionary:
		return {"kind": "rank", "label": label, "value": value, "note": "",
			"rank": rank, "color": color}


	## Kaikki elävät statit sarakkeiksi. wide = mahtuuko neljäs sarake; kapeassa
	## ruudussa YLLÄPITO putoaa omana sarakkeenaan ja sen rivit siirtyvät
	## PUOLUSTUKSEN perään, jottei mikään luku katoa kokonaan.
	func _stat_columns(hero, wide: bool) -> Array:
		var attack: float = hero.item_stat("attack")
		var ap: float = hero.item_stat("ap")
		var crit: float = hero.item_stat("crit")
		var pen: float = clampf(hero.item_stat("armor_pen"), 0.0, 1.0)
		var armor: float = maxf(hero.item_stat("armor"), 0.0)
		var mr: float = maxf(hero.item_stat("mr"), 0.0)
		var cdr: float = minf(hero.item_stat("cdr"), 0.4)
		var ms: float = hero.item_stat("ms")
		var lifesteal: float = hero.item_stat("lifesteal")
		var spellvamp: float = hero.item_stat("spellvamp")
		var hp_regen: float = hero.item_stat("hp_regen")
		var mana_regen: float = hero.item_stat("mana_regen")
		var heal_power: float = hero.item_stat("heal_power")
		var lvl_dmg: float = hero.level_damage_mult
		var lvl_spell: float = hero.level_spell_mult
		var lvl_melee: float = hero.level_melee_mult

		# Yhteiskertoimet = se luku jolla sankari oikeasti lyö (Hero.combat_damage_mult):
		# perus = tasokasvu * lähikasvu * (1 + itemien attack) * paikan ranki,
		# kyky  = tasokasvu * loitsukasvu * (1 + itemien ap); paikan ranki on
		# ETENEMINEN-sarakkeen omalla rivillä, koska se on paikkakohtainen.
		var basic_mult: float = lvl_dmg * lvl_melee * (1.0 + attack) \
			* float(hero.rank_power("basic"))
		var spell_mult: float = lvl_dmg * lvl_spell * (1.0 + ap)

		# Hyökkäysnopeus luetaan perusjäähdytyksen pohjan ja nykyarvon suhteesta
		# (Hero._recompute_cooldowns jakaa pohjan attack_speedillä).
		var basic_cd: float = float(hero.cd_max.get("basic", 0.0))
		var base_cd := 0.0
		var base_map = hero.get("_base_cd_max")
		if base_map is Dictionary:
			base_cd = float((base_map as Dictionary).get("basic", 0.0))
		var as_mult := 1.0
		if base_cd > 0.0 and basic_cd > 0.0:
			as_mult = base_cd / basic_cd

		var off: Array = [
			_stat_row("Perusvahinko", "×%.2f" % basic_mult, _item_note(attack)),
			_stat_row("Kykyvahinko", "×%.2f" % spell_mult, _item_note(ap)),
			_stat_row("Hyökkäysnopeus", "×%.2f" % as_mult, "isku %.2f s" % basic_cd),
			_stat_row("Kriittinen", "%d %%" % int(round(crit * 100.0)), "osuma ×1.7",
				Palette.GOLD if crit > 0.0 else Palette.TEXT_MAIN),
			_stat_row("Panssarin läpäisy", "%d %%" % int(round(pen * 100.0)), ""),
			_stat_row("Jäähdytykset", "-%d %%" % int(round(cdr * 100.0)), "katto 40 %"),
		]

		# Panssari ja taikavastus vaimentavat kaavalla 100 / (100 + arvo).
		var armor_cut: float = 100.0 * (1.0 - 100.0 / (100.0 + armor))
		var mr_cut: float = 100.0 * (1.0 - 100.0 / (100.0 + mr))
		var move_mult := 1.0
		if hero.has_method("_move_speed_mult"):
			move_mult = float(hero._move_speed_mult())
		var speed_now: float = float(hero.base_speed) * float(hero.slow_factor) \
			* float(hero.haste_factor) * move_mult * (1.0 + ms)
		var deff: Array = [
			_stat_row("Elämä", "%d / %d" % [int(hero.hp), int(hero.max_hp)], ""),
			_stat_row("Panssari", str(int(round(armor))),
				"vaimennus %d %%" % int(round(armor_cut))),
			_stat_row("Taikavastus", str(int(round(mr))),
				"vaimennus %d %%" % int(round(mr_cut))),
			_stat_row("Liikenopeus", str(int(round(speed_now))), _item_note(ms)),
		]
		if float(hero.shield_hp) > 0.0:
			deff.append(_stat_row("Kilpi", str(int(hero.shield_hp)),
				"%.1f s jäljellä" % float(hero.shield_timer), Palette.SHIELD))
		if float(hero.slow_timer) > 0.0:
			deff.append(_stat_row("Hidastus",
				"-%d %%" % int(round((1.0 - float(hero.slow_factor)) * 100.0)),
				"", Palette.BAD))
		elif float(hero.haste_timer) > 0.0:
			deff.append(_stat_row("Kiihdytys",
				"+%d %%" % int(round((float(hero.haste_factor) - 1.0) * 100.0)),
				"", Palette.GOOD))

		var sus: Array = []
		if str(hero.res_type) != "" and float(hero.res_max) > 0.0:
			var regen_lvl := 1.0
			var regen_lvl_v = hero.get("_regen_level_mult")
			if regen_lvl_v != null:
				regen_lvl = float(regen_lvl_v)
			var per_sec: float = float(hero.res_regen) * regen_lvl * (1.0 + mana_regen)
			sus.append(_stat_row(_resource_name(str(hero.res_type)),
				"%d / %d" % [int(hero.res), int(hero.res_max)],
				"+%.1f /s" % per_sec if per_sec > 0.0 else "",
				_resource_color(str(hero.res_type))))
		sus.append(_stat_row("Elpyminen",
			"%.1f /s" % (Hero.REGEN_PER_SEC * (1.0 + hp_regen)), _item_note(hp_regen)))
		sus.append(_stat_row("Elämänimu", "%d %%" % int(round(lifesteal * 100.0)),
			"perusosumista"))
		sus.append(_stat_row("Loitsuimu", "%d %%" % int(round(spellvamp * 100.0)),
			"kyvyistä"))
		# Hoivateho: tukitavaroiden kerroin MUILLE annettuihin parannuksiin ja
		# kilpiin (Hero.heal_hp / Hero.add_shield). Oma paikkaus ei hyödy.
		sus.append(_stat_row("Hoivateho", "+%d %%" % int(round(heal_power * 100.0)),
			"parannukset ja kilvet",
			Palette.HEAL if heal_power > 0.0 else Palette.TEXT_MAIN))
		sus.append(_stat_row("Ultilataus", "%d %%" % int(round(float(hero.ult_charge))),
			"", Palette.GOLD if float(hero.ult_charge) >= 100.0 else Palette.TEXT_MAIN))

		var prog: Array = []
		var lvl: int = int(hero.level)
		var lvl_note := "täysi taso"
		if lvl < Hero.MAX_LEVEL:
			lvl_note = "XP %d / %d" % [int(hero.xp_in_current_level()),
				int(hero.xp_needed_for_next_level())]
		prog.append(_stat_row("Taso", "%d / %d" % [lvl, Hero.MAX_LEVEL], lvl_note,
			Palette.GOLD))
		prog.append(_stat_row("Tasokasvu", "×%.2f" % lvl_dmg,
			"lähi ×%.2f · kyvyt ×%.2f" % [lvl_melee, lvl_spell]))
		for slot_v in ["basic", "a1", "a2", "dodge", "ult"]:
			var slot := str(slot_v)
			var slot_rank: int = int(hero.ability_ranks.get(slot, 0))
			var slot_value := "×%.2f" % float(hero.rank_power(slot))
			var slot_color: Color = Palette.TEXT_MAIN
			if slot == "ult" and slot_rank <= 0:
				slot_value = "TASO %d" % int(Hero.ULT_RANK_LEVELS[0])
				slot_color = Palette.TEXT_DIM
			prog.append(_rank_row(str(Hero.SLOT_NAMES.get(slot, slot)), slot_rank,
				slot_value, slot_color))
		var points: int = int(hero.skill_points)
		prog.append(_stat_row("Kykypisteitä", str(points), "",
			Palette.GOLD if points > 0 else Palette.TEXT_MAIN))
		var gps: float = hero.item_stat("gold_per_sec")
		prog.append(_stat_row("Kulta", str(int(hero.profile.wallet())),
			"+%.1f /s itemeistä" % gps if gps > 0.0 else "", Palette.GOLD))
		var assist: float = hero.item_stat("assist_gold")
		if assist > 0.0:
			prog.append(_stat_row("Avustuskulta",
				"+%d %%" % int(round(assist * 100.0)), ""))
		var jungle: float = hero.item_stat("jungle_dmg")
		if jungle > 0.0:
			prog.append(_stat_row("Viidakkovahinko",
				"+%d %%" % int(round(jungle * 100.0)), ""))

		var cols: Array = [{"title": "HYÖKKÄYS", "rows": off}]
		if wide:
			cols.append({"title": "PUOLUSTUS", "rows": deff})
			cols.append({"title": "YLLÄPITO", "rows": sus})
		else:
			deff.append_array(sus)
			cols.append({"title": "PUOLUSTUS", "rows": deff})
		cols.append({"title": "ETENEMINEN", "rows": prog})
		return cols


	## Oikeaan reunaan tasattu teksti (UiKit tarjoaa vain vasemman ja keskityksen).
	func _draw_right_text(anchor: Vector2, text: String, font_size: int,
			color: Color, outline := 1) -> void:
		var font := ThemeDB.fallback_font
		var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x
		UiKit.draw_text(self, Vector2(anchor.x - text_w, anchor.y), text, font_size,
			color, false, outline)


	## Tietonäkymän piirto. Kutsutaan vasta minikartan jälkeen, mutta alue on
	## laskettu _inspect_bandissa niin ettei se osu siihen eikä syötteeseen.
	func _draw_inspect() -> void:
		if not _inspect_active():
			return
		var band := _inspect_band()
		if band.size.x < 240.0 or band.size.y < 90.0:
			return
		var compact := _compact()
		var wide: bool = band.size.x >= 720.0
		var cols := _stat_columns(bound_hero, wide)
		var max_rows := 1
		for col_v in cols:
			var col: Dictionary = col_v
			max_rows = maxi(max_rows, (col["rows"] as Array).size())
		var pad := 10.0 if compact else 14.0
		var title_h := 16.0 if compact else 22.0
		var head_h := 13.0 if compact else 18.0
		var foot_h := 24.0 if compact else 34.0
		var want_row := 13.0 if compact else 21.0
		var want_h: float = pad * 2.0 + title_h + head_h + foot_h \
			+ float(max_rows) * want_row
		var panel_h: float = minf(want_h, band.size.y)
		var stats_rect := Rect2(band.position.x, band.end.y - panel_h,
			band.size.x, panel_h)
		_draw_inspect_cards(stats_rect.position.y)
		_draw_stats_panel(stats_rect, cols, max_rows)


	## Statipaneeli: otsikko, 3-4 saraketta ja tavarapalkki. Rivikorkeus ja
	## fontit skaalataan käytettävissä olevasta korkeudesta, joten sama paneeli
	## on luettava sekä koko ruudussa että neljäsosaruudussa.
	func _draw_stats_panel(rect: Rect2, cols: Array, max_rows: int) -> void:
		var hero = bound_hero
		var compact := _compact()
		var hc: Color = hero.hero_color()
		var pcol: Color = hero.profile.color()
		_panel(Rect2(rect.position + Vector2(0, 5), rect.size), Color(0, 0, 0, 0.5),
			Color(0, 0, 0, 0), 15.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.96),
			Palette.with_alpha(hc, 0.72), 15.0, 2.0)
		draw_rect(Rect2(rect.position + Vector2(12.0, 0.0),
			Vector2(rect.size.x - 24.0, 3.0)), Palette.glow(hc, 1.25))

		var pad := 10.0 if compact else 14.0
		var title_h := 16.0 if compact else 22.0
		var head_h := 13.0 if compact else 18.0
		var foot_h := 24.0 if compact else 34.0
		var inner := Rect2(rect.position + Vector2(pad, pad),
			rect.size - Vector2(pad * 2.0, pad * 2.0))

		var hdef: Dictionary = HeroDef.get_def(hero.hero_id)
		UiKit.draw_text(self, Vector2(inner.position.x, inner.position.y + title_h * 0.6),
			"TIEDOT  •  %s  •  P%d" % [str(hdef["name"]).to_upper(),
			int(hero.profile.index) + 1], 11 if compact else 15,
			Palette.glow(pcol, 1.1), false, 2)
		_draw_right_text(Vector2(inner.end.x, inner.position.y + title_h * 0.6),
			_inspect_key_hint(), 8 if compact else 11, Palette.TEXT_DIM, 1)

		var grid_top: float = inner.position.y + title_h
		var grid_h: float = maxf(inner.size.y - title_h - foot_h, 20.0)
		var rows_h: float = maxf(grid_h - head_h, 12.0)
		var row_h: float = clampf(rows_h / float(maxi(max_rows, 1)), 9.0, 24.0)
		var label_size: int = clampi(int(row_h * 0.62), 8, 13)
		var value_size: int = clampi(label_size + 1, 8, 15)
		var note_size: int = clampi(label_size - 2, 7, 11)
		var col_w: float = inner.size.x / float(maxi(cols.size(), 1))
		var show_note: bool = col_w >= 190.0

		for ci in range(cols.size()):
			var col: Dictionary = cols[ci]
			var cx: float = inner.position.x + col_w * float(ci)
			if ci > 0:
				draw_line(Vector2(cx - 5.0, grid_top + 2.0),
					Vector2(cx - 5.0, grid_top + grid_h - 4.0),
					Palette.with_alpha(Palette.UI_STROKE, 0.32), 1.0)
			UiKit.draw_text(self, Vector2(cx + 5.0, grid_top + head_h * 0.62),
				str(col["title"]), 9 if compact else 12,
				Palette.with_alpha(Palette.glow(hc, 1.15), 0.95), false, 2)
			var rows: Array = col["rows"]
			for ri in range(rows.size()):
				var ry: float = grid_top + head_h + row_h * (float(ri) + 0.5)
				if ri % 2 == 1:
					draw_rect(Rect2(cx + 1.0, ry - row_h * 0.5, col_w - 9.0, row_h),
						Color(1, 1, 1, 0.03))
				_draw_stat_row(rows[ri], cx, ry, col_w, row_h, label_size,
					value_size, note_size, show_note)

		# Tavarapalkki: kuusi lokeroa nimineen — kauppa ei ole auki, joten
		# tämä on ainoa paikka jossa itemien nimet näkyvät kesken ottelun.
		var foot_y: float = inner.end.y - foot_h * 0.5
		draw_line(Vector2(inner.position.x, inner.end.y - foot_h),
			Vector2(inner.end.x, inner.end.y - foot_h),
			Palette.with_alpha(Palette.UI_STROKE, 0.3), 1.0)
		UiKit.draw_text(self, Vector2(inner.position.x, foot_y + 4.0), "TAVARAT",
			9 if compact else 12, Palette.TEXT_DIM, false, 2)
		var items_x: float = inner.position.x + (56.0 if compact else 76.0)
		var cell_w: float = maxf((inner.end.x - items_x) / float(Hero.MAX_ITEMS), 20.0)
		var icon_r: float = minf(foot_h * 0.30, 11.0)
		var name_chars: int = maxi(int((cell_w - icon_r * 2.0 - 12.0)
			/ (4.6 if compact else 6.0)), 3)
		var owned: Array = hero.items
		for si in range(Hero.MAX_ITEMS):
			var icon_c := Vector2(items_x + cell_w * float(si) + icon_r + 2.0, foot_y)
			if si < owned.size():
				var iid := str(owned[si])
				ItemIcon.draw(self, iid, icon_c, icon_r)
				UiKit.draw_text(self, Vector2(icon_c.x + icon_r + 5.0, foot_y + 4.0),
					_short_name(str(ItemDef.get_item(iid).get("name", iid)), name_chars),
					8 if compact else 11, Palette.TEXT_MAIN, false, 1)
			else:
				draw_arc(icon_c, icon_r * 0.8, 0.0, TAU, 14,
					Palette.with_alpha(Palette.TEXT_DIM, 0.3), 1.0)
				UiKit.draw_text(self, Vector2(icon_c.x + icon_r + 5.0, foot_y + 4.0),
					"vapaa", 8 if compact else 11,
					Palette.with_alpha(Palette.TEXT_DIM, 0.6), false, 1)


	## Yksi rivi statiruudukkoon: nimi vasemmalle, luku oikealle ja lähde
	## keskelle. Rankkirivi saa lähteen tilalle kolme pipsua.
	func _draw_stat_row(row: Dictionary, cx: float, cy: float, col_w: float,
			row_h: float, label_size: int, value_size: int, note_size: int,
			show_note: bool) -> void:
		var kind := str(row.get("kind", "row"))
		var value_col: Color = row.get("color", Palette.TEXT_MAIN)
		UiKit.draw_text(self, Vector2(cx + 5.0, cy + float(label_size) * 0.36),
			str(row["label"]), label_size, Palette.TEXT_DIM, false, 1)
		if kind == "rank":
			var rank := int(row.get("rank", 0))
			var pip_w: float = clampf(col_w * 0.05, 4.0, 8.0)
			var pip_x: float = cx + col_w * 0.50
			for p in range(3):
				draw_rect(Rect2(pip_x + float(p) * (pip_w + 2.0),
					cy - row_h * 0.13, pip_w, maxf(row_h * 0.26, 3.0)),
					Palette.glow(Palette.GOLD, 1.2) if rank > p else Color(1, 1, 1, 0.13))
		elif show_note and str(row.get("note", "")) != "":
			UiKit.draw_text(self, Vector2(cx + col_w * 0.50,
				cy + float(note_size) * 0.36), str(row["note"]), note_size,
				Palette.with_alpha(Palette.TEXT_DIM, 0.78), false, 1)
		_draw_right_text(Vector2(cx + col_w - 7.0, cy + float(value_size) * 0.36),
			str(row["value"]), value_size, value_col, 2)


	## Montako merkkiä mahtuu leveyteen: mitataan fontista, jotta rivitys osuu
	## oikein myös pienillä fonttikoolla.
	func _fit_chars(width: float, font_size: int) -> int:
		var font := ThemeDB.fallback_font
		var sample := "keskimaarainen kirjainleveys tassa"
		var sample_w: float = font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x
		if sample_w <= 0.0:
			return 24
		return maxi(int(width * float(sample.length()) / sample_w), 6)


	func _card_line(text: String, font_size: int, color: Color) -> Dictionary:
		return {"text": text, "size": font_size, "color": color}


	func _resource_partitive(type: String) -> String:
		match type:
			"mana":
				return "manaa"
			"energy":
				return "energiaa"
			"rage":
				return "raivoa"
		return "resurssia"


	## Mitä seuraava kykypiste antaa. Askeleet luetaan Heron vakioista, joten
	## teksti pysyy totuudessa vaikka tasapainoa säädettäisiin.
	func _next_rank_text(hero, slot: String) -> String:
		var rank: int = int(hero.ability_ranks.get(slot, 0))
		if rank >= Hero.RANK_CAP:
			return "RANKI TÄYNNÄ"
		if slot == "ult":
			var need: int = int(Hero.ULT_RANK_LEVELS[rank])
			if int(hero.level) < need:
				return "RANKI %d VAATII TASON %d" % [rank + 1, need]
			if rank == 0:
				return "RANKI 1 AVAA ULTIN"
			return "RANKI %d: +%d %% voimaa" % [rank + 1,
				int(round(Hero.ULT_RANK_POWER_STEP * 100.0))]
		if slot == "basic":
			return "RANKI %d: +%d %% voimaa" % [rank + 1,
				int(round(Hero.RANK_POWER_STEP * 100.0))]
		return "RANKI %d: +%d %% voimaa, -%d %% perusjäähdytystä" % [rank + 1,
			int(round(Hero.RANK_POWER_STEP * 100.0)),
			int(round(Hero.RANK_CD_STEP * 100.0))]


	## Kykykortin faktarivit: ranki, jäähdytys tai lataus, resurssihinta ja
	## seuraavan rankin tuotto. Lukossa oleva ulti kertoo avaustasonsa.
	func _ability_facts(hero, slot: String) -> Array:
		var out: Array = []
		out.append("RANKI %d / %d" % [int(hero.ability_ranks.get(slot, 0)),
			Hero.RANK_CAP])
		if slot == "ult":
			if not bool(hero.ult_unlocked()):
				out.append("LUKOSSA — AVAUTUU TASOLLA %d" % int(Hero.ULT_RANK_LEVELS[0]))
			out.append("LATAUS %d %%" % int(round(float(hero.ult_charge))))
		elif slot == "basic":
			out.append("ISKUVÄLI %.2f s" % float(hero.cd_max.get(slot, 0.0)))
		else:
			var left: float = float(hero.cd.get(slot, 0.0))
			var full: float = float(hero.cd_max.get(slot, 0.0))
			if left > 0.05:
				out.append("JÄÄHDYTYS %.1f / %.1f s" % [left, full])
			else:
				out.append("JÄÄHDYTYS %.1f s — VALMIS" % full)
		var res_type := str(hero.res_type)
		if res_type != "":
			var cost: float = float(hero.res_cost.get(slot, 0.0)) \
				* float(hero.resource_cost_mult())
			if cost > 0.0:
				out.append("HINTA %d %s (nyt %d)" % [int(round(cost)),
					_resource_partitive(res_type), int(hero.res)])
		out.append(_next_rank_text(hero, slot))
		return out


	## Kumpi kykykortti näytetään kun tilaa on vain yhdelle: tähtäyksessä oleva
	## paikka voittaa, muuten kortti kiertää paikasta toiseen pidon aikana.
	func _inspect_slot_index() -> int:
		var aiming := ""
		var aiming_v = bound_hero.get("_aiming_slot")
		if aiming_v != null:
			aiming = str(aiming_v)
		var idx: int = SLOT_ORDER.find(aiming)
		if idx >= 0:
			return idx
		return int(_inspect_cycle / 2.4) % SLOT_ORDER.size()


	## Kykykortit statipaneelin yllä. Alue saa nousta paneelia ylemmäs vapaan
	## pelikuvan päälle, mutta se pysyy ottelupaneelin ja buffikellon alapuolella,
	## KO-syötteen vasemmalla puolella eikä yletä koskaan minikartalle.
	func _draw_inspect_cards(stats_top: float) -> void:
		var compact := _compact()
		var edge := _margin()
		var left := edge
		var right: float = minf(size.x - edge, _minimap_rect().position.x - 10.0)
		if not _feed.is_empty():
			right = minf(right, size.x - edge - (300.0 if compact else 360.0) - 6.0)
		var top_limit: float = edge + (96.0 if compact else 130.0)
		var bottom: float = stats_top - 6.0
		var avail: float = bottom - top_limit
		if avail < 52.0 or right - left < 220.0:
			return
		var card_h: float = minf(avail, 260.0)
		var area := Rect2(left, bottom - card_h, right - left, card_h)
		var slot_rects := _slot_rects()
		var keys := _slot_keys()
		if card_h >= 110.0 and area.size.x >= 900.0:
			# Tilaa kaikille viidelle: kortti kunkin telakkapaikan ylle ja ohut
			# yhdysviiva kertoo kumpi kortti kuuluu kummalle napille.
			var gap := 10.0
			var card_w: float = (area.size.x - gap * 4.0) / 5.0
			for i in range(SLOT_ORDER.size()):
				var crect := Rect2(area.position.x + float(i) * (card_w + gap),
					area.position.y, card_w, card_h)
				_draw_ability_card(crect, str(SLOT_ORDER[i]), str(keys[i]), false, false)
				var srect: Rect2 = slot_rects[i]
				draw_line(Vector2(crect.get_center().x, crect.end.y),
					Vector2(srect.get_center().x, srect.position.y),
					Palette.with_alpha(Palette.UI_STROKE, 0.4), 1.5)
		else:
			# Kapea ruutu: yksi leveä kortti kerrallaan, ja telakan vastaava
			# paikka hehkuu, jottei lukija joudu arvaamaan mistä on kyse.
			var idx := _inspect_slot_index()
			_draw_ability_card(area, str(SLOT_ORDER[idx]), str(keys[idx]), true, true)
			var hl: Rect2 = slot_rects[idx]
			_panel(hl.grow(3.0), Color(0, 0, 0, 0),
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.35),
					0.55 + 0.35 * sin(_time * 6.0)), 12.0, 2.5)


	## Yksi kykykortti: paikka ja nappi, kyvyn nimi, faktarivit ja kuvaus.
	## single = yksi leveä kortti (faktat mahtuvat yhdelle riville).
	func _draw_ability_card(rect: Rect2, slot: String, key: String,
			highlight: bool, single: bool) -> void:
		var hero = bound_hero
		var abilities: Dictionary = HeroDef.get_def(hero.hero_id)["abilities"]
		var ability: Dictionary = abilities.get(slot, {})
		var compact := _compact()
		var acol: Color = Palette.GOLD if slot == "ult" else hero.hero_color()
		_panel(Rect2(rect.position + Vector2(0, 4), rect.size), Color(0, 0, 0, 0.45),
			Color(0, 0, 0, 0), 11.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.97),
			Palette.with_alpha(Palette.glow(acol, 1.2), 0.85 if highlight else 0.55),
			11.0, 2.0)
		draw_rect(Rect2(rect.position + Vector2(9.0, 0.0),
			Vector2(rect.size.x - 18.0, 2.5)), Palette.glow(acol, 1.2))

		var pad := 6.0 if compact else 9.0
		var inner := Rect2(rect.position + Vector2(pad, pad + 2.0),
			rect.size - Vector2(pad * 2.0, pad * 2.0 + 2.0))
		var head_size: int = 8 if compact else 10
		var name_size: int = 11 if compact else 15
		var body_size: int = 8 if compact else 11
		var facts := _ability_facts(hero, slot)
		var slot_label := str(Hero.SLOT_NAMES.get(slot, slot))

		var lines: Array = []
		if single:
			var facts_text := "%s  ·  %s" % [slot_label, key]
			for fact_v in facts:
				facts_text += "  ·  " + str(fact_v)
			lines.append(_card_line(facts_text, head_size,
				Palette.with_alpha(Palette.TEXT_MAIN, 0.96)))
			lines.append(_card_line(str(ability.get("name", "")), name_size,
				Palette.glow(acol, 1.15)))
		else:
			lines.append(_card_line("%s  ·  %s" % [slot_label, key], head_size,
				Palette.with_alpha(Palette.TEXT_DIM, 0.95)))
			lines.append(_card_line(str(ability.get("name", "")), name_size,
				Palette.glow(acol, 1.15)))
			for fi in range(facts.size()):
				lines.append(_card_line(str(facts[fi]), body_size,
					Palette.GOLD if fi == facts.size() - 1 else Palette.TEXT_MAIN))
		var chars := _fit_chars(inner.size.x, body_size)
		var desc_lines := _wrap_text(str(ability.get("desc", "")), chars)
		if single and desc_lines.size() > 2:
			desc_lines.resize(2)
			desc_lines[1] = str(desc_lines[1]) + " …"
		for desc_v in desc_lines:
			lines.append(_card_line(str(desc_v), body_size,
				Palette.with_alpha(Palette.TEXT_MAIN, 0.92)))
		# "tip" ja "scaling" ovat HeroDefin uudempia kenttiä: luetaan oletuksella,
		# joten kortti toimii sekä ennen niiden lisäystä että niiden jälkeen.
		var tip := str(ability.get("tip", ""))
		if tip != "":
			for tip_v in _wrap_text("VIHJE: " + tip, chars):
				lines.append(_card_line(str(tip_v), body_size,
					Palette.with_alpha(Palette.GOOD, 0.94)))
		var scaling := str(ability.get("scaling", ""))
		if scaling != "":
			for sc_v in _wrap_text("SKAALAUS: " + scaling, chars):
				lines.append(_card_line(str(sc_v), body_size,
					Palette.with_alpha(Palette.SHIELD, 0.94)))

		var ly: float = inner.position.y
		for line_v in lines:
			var line: Dictionary = line_v
			var fsize: int = int(line["size"])
			var step: float = float(fsize) + 3.0
			if ly + step > inner.end.y:
				break
			UiKit.draw_text(self, Vector2(inner.position.x, ly + float(fsize) * 0.86),
				str(line["text"]), fsize, line["color"], false, 1)
			ly += step
		if not single:
			# Rankkipipsut kortin oikeaan yläkulmaan (yksileveässä ranki on tekstissä).
			var rank: int = int(hero.ability_ranks.get(slot, 0))
			for p in range(3):
				draw_rect(Rect2(inner.end.x - 32.0 + float(p) * 10.0,
					inner.position.y + 2.0, 8.0, 3.5),
					Palette.glow(Palette.GOLD, 1.2) if rank > p else Color(1, 1, 1, 0.14))


	## Telakan ylle pinottava vihjerivi. prio 0 = lähimpänä telakkaa.
	func _push_hint(text: String, color: Color, prio: int) -> void:
		_hints.append({"text": text, "color": color, "prio": prio})


	## Löydettävyys: tietonäkymän nappi kerrotaan ottelun ensimmäiset 40 s ja
	## aina kun kykypisteitä on käyttämättä — juuri silloin kortit kannattaa
	## lukea ennen pisteen käyttöä.
	func _draw_inspect_hint() -> void:
		var hero = bound_hero
		if arena == null or Game.simulating or scoreboard_open:
			return
		if hero == null or not is_instance_valid(hero) or hero.profile == null:
			return
		if not bool(hero.profile.is_human()) or bool(hero.shop_open) or not hero.alive:
			return
		if _inspect_held():
			return
		if float(arena.match_elapsed) >= 40.0 and int(hero.skill_points) <= 0:
			return
		var pad: bool = int(hero.profile.device) >= 0
		_push_hint("PIDÄ D-PAD OIKEA = TIEDOT" if pad else "PIDÄ C = TIEDOT",
			Palette.with_alpha(Palette.TEXT_MAIN, 0.55 + 0.3 * sin(_time * 3.0)), 2)


	## Vihjerivit telakan yllä yhtenä pinona, jotta kauppa-, kykypiste- ja
	## tietovihje eivät koskaan piirry päällekkäin. Tietonäkymän ollessa auki
	## vihjeet vaikenevat: statipaneeli varaa saman kaistan telakan yltä.
	func _draw_hints() -> void:
		if _hints.is_empty() or _inspect_active():
			return
		var rect := _dock_rect()
		var step := 15.0 if _compact() else 18.0
		var row := 0
		for prio in range(3):
			for hint_v in _hints:
				var hint: Dictionary = hint_v
				if int(hint["prio"]) != prio:
					continue
				UiKit.draw_text(self, Vector2(rect.get_center().x,
					rect.position.y - 12.0 - float(row) * step),
					str(hint["text"]), 10 if _compact() else 12,
					hint["color"], true, 2)
				row += 1


	func _minimap_rect() -> Rect2:
		var map_size: Vector2
		if not _compact():
			map_size = Vector2(330.0, 188.0)
		elif _narrow():
			map_size = Vector2(220.0, 124.0)
		else:
			map_size = Vector2(276.0, 146.0)
		return Rect2(size.x - _margin() - map_size.x,
			size.y - _margin() - map_size.y, map_size.x, map_size.y)


	## Kerää minikartan staattisen karttadatan kerran (kartta ei muutu kesken
	## ottelun). Poistaa taulukko-/sanakirja-allokaatiot 30-45 Hz piirtopolulta.
	func _minimap_static_init() -> void:
		if _mm_ready or arena.map == null:
			return
		_mm_ready = true
		if arena.map.has_method("brush_zones"):
			_mm_brushes = arena.map.brush_zones()
		if arena.map.has_method("jungle_paths"):
			_mm_jungle_paths = arena.map.jungle_paths()
		if arena.map.has_method("jungle_choke_points"):
			_mm_chokes = arena.map.jungle_choke_points()
		if arena.map.has_method("lane_alcove_paths"):
			_mm_alcoves = arena.map.lane_alcove_paths()
		# MOBA-reitit tulevat kartalta: uusi kenttä piirtää topin ja bottomin.
		if arena.map.has_method("lane_paths"):
			for path in arena.map.lane_paths().values():
				_mm_lane_paths.append(path)
		elif arena.map.has_method("lane_path"):
			_mm_lane_paths.append(arena.map.lane_path())
		if arena.map.has_method("camp_markers"):
			_mm_camps = arena.map.camp_markers()
		if arena.map.has_method("sanctuary_rect"):
			for team in range(2):
				_mm_sancta.append({"rect": arena.map.sanctuary_rect(team),
					"shop": arena.map.shop_spot(team), "team": team})
				for door_id in arena.map.jungle_door_ids():
					var gr: Rect2 = arena.map.jungle_door_rect(team, door_id)
					_mm_doors.append({"center": gr.get_center(), "team": team})


	## Päivittää leirimerkkien elävän tilan paikan päällä: olemassa oleviin
	## sanakirjoihin kirjoitetaan vain uudet arvot, joten piirtopolulla ei
	## allokoida mitään. Baron ja Dragon luetaan Arenan laskurista, koska niillä
	## on ennen ensimmäistä heräämistä oma ilmestymisajastin.
	func _minimap_camps_sync() -> void:
		if _mm_camps.is_empty():
			return
		if _mm_camp_nodes.size() != _mm_camps.size():
			_mm_camp_nodes.resize(_mm_camps.size())
		# Leirit syntyvät vasta ensimmäisen aallon kohtaamisessa, joten sidontaa
		# yritetään uudelleen puolen sekunnin välein kunnes kaikki löytyvät.
		if _mm_camp_unbound and _time >= _mm_camp_bind_at:
			_mm_camp_bind_at = _time + 0.5
			_minimap_camps_bind()
		for i in range(_mm_camps.size()):
			var marker: Dictionary = _mm_camps[i]
			var kind: String = marker["kind"]
			if kind == "baron" or kind == "dragon":
				var timer: Vector2 = arena.objective_respawn_in(kind)
				marker["alive"] = timer.x <= 0.0
				marker["left"] = timer.x
				marker["total"] = timer.y
				continue
			var camp := _mm_camp_nodes[i] as Critter
			if camp == null or not is_instance_valid(camp):
				# Leiriä ei ole vielä olemassa: merkki piirtyy normaalisti, jotta
				# viidakon muoto näkyy jo ennen ensimmäistä spawnia.
				marker["alive"] = true
				marker["left"] = 0.0
				continue
			marker["alive"] = camp.alive
			marker["left"] = 0.0 if camp.alive else maxf(camp.respawn_timer, 0.0)
			marker["total"] = maxf(camp.respawn_delay, 1.0)


	## Sitoo jokaisen leirimerkin sitä vastaavaan olentoon kotipisteen perusteella.
	## Baron ja Dragon ohitetaan: ne tulevat Arenan laskurista.
	func _minimap_camps_bind() -> void:
		_mm_camp_unbound = false
		for i in range(_mm_camps.size()):
			var marker: Dictionary = _mm_camps[i]
			var kind: String = marker["kind"]
			if kind == "baron" or kind == "dragon":
				continue
			var bound := _mm_camp_nodes[i] as Critter
			if bound != null and is_instance_valid(bound):
				continue
			var home: Vector2 = marker["pos"]
			var found: Critter = null
			for c in arena.critters:
				var camp := c as Critter
				if camp == null or not is_instance_valid(camp):
					continue
				if camp.home.distance_squared_to(home) < 4.0:
					found = camp
					break
			_mm_camp_nodes[i] = found
			if found == null:
				_mm_camp_unbound = true


	func _draw_minimap() -> void:
		if arena.map == null:
			return
		_minimap_static_init()
		_minimap_camps_sync()
		var rect := _minimap_rect()
		var compact := _compact()
		var pcol: Color = bound_hero.profile.color()
		_panel(Rect2(rect.position + Vector2(0, 4), rect.size), Color(0, 0, 0, 0.48),
			Color(0, 0, 0, 0), 13.0, 0.0)
		_panel(rect, Palette.with_alpha(Palette.UI_PANEL, 0.95), Palette.with_alpha(pcol, 0.72),
			13.0, 2.0)
		UiKit.draw_text(self, Vector2(rect.get_center().x, rect.position.y + (11.0 if compact else 15.0)),
			"KARTTA  •  P%d" % (bound_hero.profile.index + 1),
			8 if compact else 11, Palette.with_alpha(pcol, 0.95), true, 2)

		var header := 20.0 if compact else 28.0
		var map_box := Rect2(rect.position + Vector2(7.0, header),
			rect.size - Vector2(14.0, header + 7.0))
		var world_size: Vector2 = arena.map.size()
		var scale_map := minf(map_box.size.x / world_size.x, map_box.size.y / world_size.y)
		var map_origin := map_box.position + (map_box.size - world_size * scale_map) / 2.0
		var world_rect := Rect2(map_origin, world_size * scale_map)
		draw_rect(world_rect, Color(0.018, 0.035, 0.058, 0.96))
		for i in range(1, 4):
			var gx := lerpf(world_rect.position.x, world_rect.end.x, float(i) / 4.0)
			var gy := lerpf(world_rect.position.y, world_rect.end.y, float(i) / 4.0)
			draw_line(Vector2(gx, world_rect.position.y), Vector2(gx, world_rect.end.y),
				Color(0.25, 0.38, 0.5, 0.12), 1.0)
			draw_line(Vector2(world_rect.position.x, gy), Vector2(world_rect.end.x, gy),
				Color(0.25, 0.38, 0.5, 0.12), 1.0)

		# Pitkat jungle-seinat ovat strategista informaatiota, joten ne piirretaan
		# minimapille ennen reitteja ja puskia. Muuten kaytavat nayttaisivat avoimilta.
		for wall in arena.map.rect_walls:
			var wr := wall as Rect2
			var wa := _map_point(wr.position, map_origin, world_size, scale_map)
			var wb := _map_point(wr.end, map_origin, world_size, scale_map)
			draw_rect(Rect2(wa, wb - wa), Color("193d2ddd"))
		for pillar in arena.map.pillars:
			var pp := _map_point(pillar.pos, map_origin, world_size, scale_map)
			var pr: float = maxf(1.0, pillar.radius * scale_map)
			draw_circle(pp, pr, Color("234d35cc"))

		# Puskat näkyvät tummanvihreinä taktisesti: pelaaja tietää missä gank-
		# katveet ovat, vaikka niiden sisällä oleva vihollinen ei myöhemmin näkyisi.
		for brush in _mm_brushes:
			var br := brush as Rect2
			var ba := _map_point(br.position, map_origin, world_size, scale_map)
			var bb := _map_point(br.end, map_origin, world_size, scale_map)
			draw_rect(Rect2(ba, bb - ba), Color("245b3477"))
			draw_rect(Rect2(ba, bb - ba), Color("70b87866"), false, 1.0)

		# Viidakon pääväylät: leirit -> risteykset -> Dragon/Baron/gank-portit.
		for raw_path in _mm_jungle_paths:
			var jungle_pts := PackedVector2Array()
			for wp in raw_path:
				jungle_pts.append(_map_point(wp, map_origin, world_size, scale_map))
			if jungle_pts.size() >= 2:
				draw_polyline(jungle_pts, Color("477b4d77"), 3.0)
		for choke in _mm_chokes:
			var ch := _map_point(choke, map_origin, world_size, scale_map)
			draw_circle(ch, 1.8 if compact else 2.4, Color("a3d98a"))
		for raw_path in _mm_alcoves:
			var alcove_pts := PackedVector2Array()
			for wp in raw_path:
				alcove_pts.append(_map_point(wp, map_origin, world_size, scale_map))
			if alcove_pts.size() >= 2:
				draw_polyline(alcove_pts, Color("d0ad5477"), 2.0)

		for path in _mm_lane_paths:
			var lane_pts := PackedVector2Array()
			for wp in path:
				lane_pts.append(_map_point(wp, map_origin, world_size, scale_map))
			if lane_pts.size() >= 2:
				draw_polyline(lane_pts, Color(0.3, 0.42, 0.55, 0.5), 5.0)
				draw_polyline(lane_pts, Color(0.65, 0.75, 0.84, 0.55), 1.5)

		# Leirit ja major objectivet ovat näkyvissä jo ennen spawnia, jotta
		# suurta viidakkoa voi lukea nopeasti myös kahden pelaajan splitissä.
		# Kaadetulta leiriltä piste katoaa ja tilalle jää täyttyvä herätysrengas.
		for marker in _mm_camps:
			var cp := _map_point(marker.pos, map_origin, world_size, scale_map)
			var kind: String = marker.kind
			var ccol := Color("d97139")
			var cr := 2.4 if compact else 3.2
			if kind == "red":
				ccol = Color("df4938")
			elif kind == "blue":
				ccol = Color("4e8ee8")
			elif kind == "small":
				ccol = Color("79b45e")
				cr -= 0.5
			elif kind == "lane":
				ccol = Color("e7c34b")
				cr += 0.5
			elif kind == "baron":
				ccol = Color("bd60e5")
				cr += 2.0
			elif kind == "dragon":
				ccol = Color("49d7c5")
				cr += 2.0
			var wait_left: float = marker.left
			if bool(marker.alive) or wait_left <= 0.0:
				draw_circle(cp, cr, ccol)
				draw_arc(cp, cr + 1.5, 0, TAU, 14, Palette.with_alpha(Color.WHITE, 0.55), 1.0)
			else:
				_draw_camp_respawn(cp, cr, ccol, kind, wait_left, float(marker.total), compact)

		# Base: fountain/sanctuary, tuleva shop ja oman tiimin jungle-oikotiet.
		for sanct in _mm_sancta:
			var sr := sanct.rect as Rect2
			var sa := _map_point(sr.position, map_origin, world_size, scale_map)
			var sb := _map_point(sr.end, map_origin, world_size, scale_map)
			var tcol: Color = Palette.team(int(sanct.team))
			draw_rect(Rect2(sa, sb - sa), Palette.with_alpha(tcol, 0.22))
			draw_rect(Rect2(sa, sb - sa), Palette.with_alpha(tcol, 0.62), false, 1.0)
			var shop_pos := _map_point(sanct.shop, map_origin, world_size, scale_map)
			draw_circle(shop_pos, 3.2 if compact else 4.2, Color("e7c34b"))
		for door in _mm_doors:
			var door_team := int(door.team)
			var dcol: Color = Palette.team(door_team)
			var gc := _map_point(door.center, map_origin, world_size, scale_map)
			var arrow_dir := 1.0 if door_team == 0 else -1.0
			draw_line(gc - Vector2(arrow_dir * 3.5, 0),
				gc + Vector2(arrow_dir * 3.5, 0), Palette.with_alpha(dcol, 0.9), 2.0)
			_draw_diamond(gc + Vector2(arrow_dir * 3.5, 0), 2.2,
				Palette.with_alpha(dcol, 0.9))

		for structure in arena.structures:
			if not is_instance_valid(structure) or not structure.alive:
				continue
			var sp := _map_point(structure.global_position, map_origin, world_size, scale_map)
			var scol := Palette.glow(Palette.team(structure.team), 1.2)
			if structure.kind == Structure.Kind.NEXUS:
				_draw_diamond(sp, 5.0 if compact else 7.0, scol)
			elif structure.kind == Structure.Kind.CRYSTAL:
				_draw_diamond(sp, 3.5 if compact else 4.5, Palette.glow(scol, 1.2))
			else:
				draw_rect(Rect2(sp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), scol)

		# Vartijat: OMAN joukkueen lyhdyt pieninä pisteinä (vihollisen
		# vartijat eivät paljastu kartalla).
		for w in arena.wards:
			if not is_instance_valid(w) or w.team != bound_hero.team:
				continue
			var wpos := _map_point(w.global_position, map_origin, world_size, scale_map)
			draw_circle(wpos, 2.0 if compact else 2.6, Palette.glow(Palette.GOLD, 1.2))
			draw_arc(wpos, 3.6 if compact else 4.4, 0.0, TAU, 12,
				Palette.with_alpha(Palette.team(w.team), 0.8), 1.0)

		# Maassa lojuvat Baron-artefaktit: sykkivä kultatimantti MOLEMMILLE
		# joukkueille (iso strateginen palkinto näkyy kaikille).
		for artifact in arena.artifacts:
			if not is_instance_valid(artifact):
				continue
			var art_p := _map_point(artifact.global_position, map_origin, world_size, scale_map)
			_draw_diamond(art_p, (3.6 if compact else 4.6) + 1.4 * sin(_time * 5.0),
				Palette.glow(Palette.GOLD, 1.4))
			draw_arc(art_p, 6.5 if compact else 8.0, 0.0, TAU, 14,
				Palette.with_alpha(Palette.GOLD, 0.45 + 0.3 * sin(_time * 5.0)), 1.0)

		# Oman kameran alue ja oma suuntanuoli tekevät neljästä kartasta aidosti
		# pelaajakohtaisia.
		var view_half := Vector2(540.0, 540.0)
		var view_a := _map_point(bound_hero.global_position - view_half,
			map_origin, world_size, scale_map)
		var view_b := _map_point(bound_hero.global_position + view_half,
			map_origin, world_size, scale_map)
		draw_rect(Rect2(view_a, view_b - view_a), Palette.with_alpha(pcol, 0.48), false, 1.0)

		# Vain pelaajasankarit (välimuisti): heroes-listalla olisi loppupelissä
		# myös ~100 minionia/rakennetta suodatettavana joka piirrolla.
		for hero in arena.player_heroes:
			if not is_instance_valid(hero) or not hero.alive or hero.profile == null:
				continue
			var hp := _map_point(hero.global_position, map_origin, world_size, scale_map)
			if hero == bound_hero:
				var direction: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.UP
				var side := direction.orthogonal()
				var arrow := PackedVector2Array([
					hp + direction * (8.0 if compact else 10.0),
					hp - direction * 5.0 + side * 5.0,
					hp - direction * 2.0,
					hp - direction * 5.0 - side * 5.0,
				])
				draw_colored_polygon(arrow, Palette.glow(pcol, 1.35))
				draw_arc(hp, 9.0 if compact else 12.0, 0.0, TAU, 22, Color.WHITE, 1.5)
			elif hero.team == bound_hero.team:
				draw_circle(hp, 3.5 if compact else 4.5, Palette.team(hero.team))
				draw_arc(hp, 5.0 if compact else 6.0, 0.0, TAU, 16,
					Palette.with_alpha(Color.WHITE, 0.72), 1.0)
			elif hero.stealth_timer > 0.0:
				# Häivetetty vihollinen katoaa kartalta (oma joukkue näkyy yllä).
				continue
			else:
				_draw_diamond(hp, 4.0 if compact else 5.5, Palette.team(hero.team))
				# Oman joukkueen vartijan tähystämä vihollinen korostuu hehkulla.
				for w in arena.wards:
					if is_instance_valid(w) and w.team == bound_hero.team \
							and bool(w.detected.has(hero)):
						draw_arc(hp, 7.5 if compact else 9.0, 0.0, TAU, 16,
							Palette.glow(Palette.team(hero.team),
								1.4 + 0.2 * sin(_time * 6.0)), 1.5)
						break

		if arena.relic != null and is_instance_valid(arena.relic):
			var rp := _map_point(arena.relic.global_position, map_origin, world_size, scale_map)
			_draw_diamond(rp, 3.5 if compact else 5.0, Palette.GOLD)
		draw_rect(world_rect, Palette.with_alpha(Palette.UI_STROKE, 0.55), false, 1.0)


	func _map_point(world_pos: Vector2, origin: Vector2, world_size: Vector2,
			scale_map: float) -> Vector2:
		return origin + (world_pos + world_size / 2.0) * scale_map


	## Kaadetun leirin herätysmittari minikartalla. Piste on poissa — tilalle jää
	## himmeä kehä, jonka päälle piirtyy leirin värinen kaari sitä pidemmälle mitä
	## lähempänä herätys on. Pienillä leireillä pelkkä rengas riittää, koska luku
	## ei olisi luettavissa jaetun ruudun minikartalla. Baron ja Dragon saavat
	## lisäksi sekuntilukeman, ja viimeisen 10 sekunnin ajan koko mittari
	## kirkastuu ja sykkii — ne ovat ne tavoitteet joiden ympäri peli kääntyy.
	func _draw_camp_respawn(cp: Vector2, cr: float, ccol: Color, kind: String,
			left: float, total: float, compact: bool) -> void:
		var major := kind == "baron" or kind == "dragon"
		var ring := cr + (1.6 if major else 1.2)
		var arc_w := 2.0 if major else 1.4
		var done := clampf(1.0 - left / maxf(total, 1.0), 0.0, 1.0)
		var urgent := left <= 10.0
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		var col := ccol
		if urgent:
			col = Palette.glow(ccol.lerp(Palette.GOLD, 0.45), 1.2)
		# Tyhjä kehä pitää leirin paikan luettavana vaikka piste on poissa.
		draw_arc(cp, ring, 0.0, TAU, 18, Palette.with_alpha(ccol, 0.28), arc_w)
		draw_arc(cp, ring, -PI / 2.0, -PI / 2.0 + TAU * done, 24,
			Palette.with_alpha(col, 0.95 if urgent else 0.7), arc_w)
		if urgent:
			var halo := ring + (1.2 + 1.6 * pulse) * (1.6 if major else 1.0)
			draw_arc(cp, halo, 0.0, TAU, 20,
				Palette.with_alpha(col, (0.6 if major else 0.4) * (1.0 - pulse)), 1.5)
		if not major:
			return
		# Baron ylös ja Dragon alas: lukemat eivät mene päällekkäin kapeallakaan
		# minikartalla, koska pitit ovat kartan keskellä vastakkain.
		var gap := ring + (6.0 if compact else 7.5)
		var label_y := -gap if kind == "baron" else gap
		var font := (9 if compact else 11) + (1 if urgent else 0)
		UiKit.draw_text(self, cp + Vector2(0, label_y), _respawn_clock(left), font,
			Palette.with_alpha(col, 1.0 if urgent else 0.92), true, 3)


	## Minikartan herätyslukema: yli minuutti "2:14", alle sen pelkät sekunnit.
	func _respawn_clock(left: float) -> String:
		var secs := int(ceil(maxf(left, 0.0)))
		if secs >= 60:
			return "%d:%02d" % [secs / 60, secs % 60]
		return str(secs)


	func _draw_banner() -> void:
		if _banner_big == "" or _time >= _banner_until:
			return
		var fade_in := clampf((_time - _banner_start) / 0.16, 0.0, 1.0)
		var fade_out := clampf((_banner_until - _time) / 0.32, 0.0, 1.0)
		var alpha := minf(fade_in, fade_out)
		var compact := _compact()
		var w := minf(size.x - 80.0, 600.0 if compact else 820.0)
		var h := 76.0 if compact else 108.0
		var rect := Rect2((size.x - w) / 2.0, size.y * (0.19 if compact else 0.23), w, h)
		_panel(rect, Color(0.025, 0.04, 0.09, 0.86 * alpha),
			Palette.with_alpha(Palette.GOLD, 0.65 * alpha), 16.0, 2.0)
		UiKit.draw_text(self, rect.get_center() + Vector2(0, -10.0 if _banner_small != "" else 2.0),
			_banner_big, 28 if compact else 44, Palette.with_alpha(Palette.TEXT_MAIN, alpha), true, 5)
		if _banner_small != "":
			UiKit.draw_text(self, rect.get_center() + Vector2(0, 22.0 if compact else 33.0),
				_banner_small, 12 if compact else 17, Palette.with_alpha(Palette.TEXT_DIM, alpha), true, 3)


	func _draw_big_number() -> void:
		if _big_number == "" or _time >= _big_until:
			return
		var fade_in := clampf((_time - _big_start) / 0.08, 0.0, 1.0)
		var fade_out := clampf((_big_until - _time) / 0.24, 0.0, 1.0)
		var alpha := minf(fade_in, fade_out)
		var center := Vector2(size.x / 2.0, size.y * 0.48)
		var pcol: Color = bound_hero.profile.color() if bound_hero != null \
			and is_instance_valid(bound_hero) and bound_hero.profile != null else Palette.GOLD
		draw_circle(center, 56.0 if _compact() else 82.0,
			Palette.with_alpha(Palette.UI_PANEL, 0.74 * alpha))
		draw_arc(center, 56.0 if _compact() else 82.0, 0.0, TAU, 48,
			Palette.with_alpha(Palette.glow(pcol, 1.2), alpha), 4.0)
		UiKit.draw_text(self, center + Vector2(0, 4), _big_number,
			66 if _compact() else 100, Palette.with_alpha(Palette.TEXT_MAIN, alpha), true, 8)


	func _panel(rect: Rect2, bg: Color, border: Color, radius: float, width: float) -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = bg
		style.border_color = border
		style.set_border_width_all(int(width))
		style.set_corner_radius_all(int(radius))
		style.draw(get_canvas_item(), rect)


	func _draw_diamond(center: Vector2, radius: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -radius), center + Vector2(radius, 0),
			center + Vector2(0, radius), center + Vector2(-radius, 0),
		]), col)


	func _hp_color(frac: float) -> Color:
		if frac > 0.5:
			return Color("55d982")
		if frac > 0.25:
			return Color("e2a541")
		return Palette.BAD


	func _resource_color(type: String) -> Color:
		match type:
			"mana":
				return Color("5f8fff")
			"energy":
				return Color("46ddf2")
			"rage":
				return Color("ff7048")
		return Palette.TEXT_DIM


## Pelinaikainen tulostaulu (pidä Tab / touchpad): molemmat joukkueet, per
## sankari taso, K/D/A, CS (last hitit), kulta, vahinko ja 6 tavaralokeroa
## (sankarin ostetut itemit kuvakkeina). Piirretään koko ruudun keskelle.
class Scoreboard:
	extends Control

	const ROW_H := 56.0
	const ITEM_SLOTS := 6

	var arena = null

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		if arena == null:
			return
		var pw: float = minf(size.x - 120.0, 1560.0)
		var ph := 96.0 + 2.0 * (44.0 + 4.0 * ROW_H) + 56.0
		var px: float = (size.x - pw) / 2.0
		var py: float = maxf((size.y - ph) / 2.0, 40.0)

		# Tumma tausta koko ruudulle + paneeli.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.07, 0.55))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.94)
		sb.set_corner_radius_all(18)
		sb.border_color = Palette.with_alpha(Palette.GOLD, 0.5)
		sb.set_border_width_all(2)
		sb.draw(get_canvas_item(), Rect2(px, py, pw, ph))

		# Otsikkorivi: kellonaika keskellä, tapposummat sivuilla.
		var kills := [0, 0]
		for h in arena.heroes:
			if is_instance_valid(h) and not h.is_unit and h.profile != null:
				kills[h.team] += int(h.profile.stats.kos)
		var mins := int(arena.match_elapsed) / 60
		var secs := int(arena.match_elapsed) % 60
		UiKit.draw_text(self, Vector2(px + pw / 2.0, py + 34.0), "%d:%02d" % [mins, secs],
			30, Palette.TEXT_MAIN, true, 4)
		UiKit.draw_text(self, Vector2(px + pw / 2.0 - 130.0, py + 34.0), str(kills[0]),
			34, Palette.glow(Palette.team(0), 1.2), true, 4)
		UiKit.draw_text(self, Vector2(px + pw / 2.0 + 130.0, py + 34.0), str(kills[1]),
			34, Palette.glow(Palette.team(1), 1.2), true, 4)
		UiKit.draw_text(self, Vector2(px + 24.0, py + 34.0), "TULOSTAULU", 24,
			Palette.TEXT_DIM, false, 3)

		var y := py + 72.0
		for team in [0, 1]:
			y = _team_block(px, y, pw, team)
		UiKit.draw_text(self, Vector2(px + pw / 2.0, py + ph - 22.0),
			"Pidä  TAB  /  ohjaimen touchpad", 16, Palette.TEXT_DIM, true)

	## Joukkuelohko: otsakerivi + sankaririvit. Palauttaa seuraavan y:n.
	func _team_block(px: float, y: float, pw: float, team: int) -> float:
		var tc: Color = Palette.team(team)
		draw_rect(Rect2(px + 14.0, y, pw - 28.0, 34.0), Palette.with_alpha(tc, 0.14))
		UiKit.draw_text(self, Vector2(px + 30.0, y + 17.0), Game.team_name(team), 20,
			Palette.glow(tc, 1.2), false, 3)
		# Sarakeotsikot.
		var cols := _columns(px, pw)
		var head := ["", "POS", "LVL", "K / D / A", "CS", "KULTA", "VAHINKO", "TAVARAT"]
		for i in range(1, head.size()):
			# cols[7] on tavaralohkon VASEN reuna -> keskitä otsikko lohkon ylle.
			var hx: float = float(cols[i]) if i < 7 else float(cols[7]) + ITEM_SLOTS * 46.0 / 2.0
			UiKit.draw_text(self, Vector2(hx, y + 17.0), str(head[i]), 15,
				Palette.TEXT_DIM, true)
		y += 44.0
		var members: Array = []
		for h in arena.heroes:
			if is_instance_valid(h) and not h.is_unit and h.team == team \
					and h.profile != null:
				members.append(h)
		members.sort_custom(func(a, b): return a.profile.index < b.profile.index)
		for h in members:
			_hero_row(px, y, pw, h)
			y += ROW_H
		return y + 8.0

	## Sarakkeiden keskikohdat: [nimi(vasen), POS, LVL, KDA, CS, KULTA, VAHINKO, TAVARAT(vasen)].
	func _columns(px: float, pw: float) -> Array:
		var items_w: float = ITEM_SLOTS * 46.0
		return [
			px + 40.0,
			px + pw * 0.30,
			px + pw * 0.36,
			px + pw * 0.45,
			px + pw * 0.53,
			px + pw * 0.60,
			px + pw * 0.68,
			px + pw - items_w - 30.0,
		]

	func _hero_row(px: float, y: float, pw: float, h) -> void:
		var cols := _columns(px, pw)
		var cy := y + ROW_H / 2.0
		var p: PlayerProfile = h.profile
		var def := HeroDef.get_def(h.hero_id)
		var c1: Color = def["color"]
		var human: bool = p.is_human()
		if human:
			draw_rect(Rect2(px + 14.0, y + 2.0, pw - 28.0, ROW_H - 4.0),
				Palette.with_alpha(p.color(), 0.08))
		if not h.alive:
			draw_rect(Rect2(px + 14.0, y + 2.0, pw - 28.0, ROW_H - 4.0),
				Color(0.02, 0.03, 0.08, 0.45))

		# Medaljonki + nimet.
		var med := Vector2(float(cols[0]), cy)
		draw_circle(med, 21.0, Palette.darker(c1, 0.55))
		draw_circle(med, 18.0, Palette.with_alpha(c1, 1.0 if h.alive else 0.5))
		HeroIcon.draw_symbol(self, h.hero_id, med, 12.0)
		if human:
			draw_arc(med, 23.0, 0.0, TAU, 26, p.color(), 2.5)
		UiKit.draw_text(self, med + Vector2(34.0, -10.0), str(p.display_name), 17,
			Palette.TEXT_MAIN, false, 2)
		# Ranked-ottelussa myös botit tunnetaan nimestään JA sarjastaan.
		if Game.ranked_mode and p.ranked_rank >= 0:
			var name_font := ThemeDB.fallback_font
			var name_w: float = name_font.get_string_size(str(p.display_name),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			RankEmblem.draw_chip(self, p.ranked_rank,
				med + Vector2(46.0 + name_w, -10.0), 22.0)
		UiKit.draw_text(self, med + Vector2(34.0, 12.0), str(def["name"]), 14,
			Palette.with_alpha(c1, 0.9), false)
		if not h.alive:
			UiKit.draw_text(self, med + Vector2(34.0, 12.0) + Vector2(120.0, 0.0),
				"%ds" % int(ceil(h.respawn_timer)), 14, Palette.BAD, false)

		# POS / LVL / KDA / CS / KULTA / VAHINKO.
		UiKit.draw_text(self, Vector2(float(cols[1]), cy), _pos_label(h), 15,
			Palette.TEXT_DIM, true)
		UiKit.draw_text(self, Vector2(float(cols[2]), cy), str(h.level), 20,
			Palette.glow(Palette.GOLD, 1.1), true, 2)
		UiKit.draw_text(self, Vector2(float(cols[3]), cy), "%d / %d / %d" % [
			int(p.stats.kos), int(p.stats.deaths), int(p.stats.assists)], 18,
			Palette.TEXT_MAIN, true, 2)
		UiKit.draw_text(self, Vector2(float(cols[4]), cy), str(int(p.stats.minion_kills)),
			18, Palette.TEXT_MAIN, true, 2)
		UiKit.draw_text(self, Vector2(float(cols[5]), cy), str(int(p.stats.gold)), 18,
			Palette.glow(Palette.GOLD, 1.15), true, 2)
		UiKit.draw_text(self, Vector2(float(cols[6]), cy), str(int(p.stats.damage)), 17,
			Palette.TEXT_MAIN, true, 2)

		# 6 tavaralokeroa: sankarin ostetut itemit ItemIcon-kuvakkeina.
		var ix := float(cols[7])
		var hero_items: Array = h.items
		for s in range(ITEM_SLOTS):
			var srect := Rect2(ix + s * 46.0, cy - 19.0, 38.0, 38.0)
			draw_rect(srect, Color(0, 0, 0, 0.4))
			draw_rect(srect, Palette.with_alpha(Palette.TEXT_DIM, 0.3), false, 1.5)
			if s < hero_items.size():
				ItemIcon.draw(self, str(hero_items[s]),
					srect.get_center() + Vector2(0, -1.5), 12.0)

	## Position lyhenne: lobbyn valinta ensin, botilla työnjako, muuten tyhjä.
	func _pos_label(h) -> String:
		var pos := str(h.profile.moba_position)
		if pos == "" and h.controller is BotBrain:
			var brain: BotBrain = h.controller
			match str(brain._moba_job):
				"jungle":
					pos = "jungle"
				"top":
					pos = "top"
				"bottom":
					pos = "support" if str(brain._moba_duty) == "support" \
						or (str(brain._moba_duty) == "" and str(HeroDef.get_def(h.hero_id).get("role", "")) == "Tuki") \
						else "carry"
		match pos:
			"top":
				return "TOP"
			"jungle":
				return "JGL"
			"carry":
				return "CAR"
			"support":
				return "SUP"
		return "—"
