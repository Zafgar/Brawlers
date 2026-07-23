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
	var _time := 0.0
	var _redraw_accum := 0.0

	var _banner_big := ""
	var _banner_small := ""
	var _banner_start := -100.0
	var _banner_until := -100.0
	var _big_number := ""
	var _big_start := -100.0
	var _big_until := -100.0
	var _feed: Array = []


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
		_draw_edge_shading()
		_draw_pane_frame()
		_draw_match_panel()
		_draw_player_badge()
		_draw_team_status()
		_draw_feed()
		if bound_hero != null and is_instance_valid(bound_hero):
			_draw_ability_dock()
			_draw_minimap()
			_draw_shop_prompt()
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
		var out: Array = []
		for hero in arena.heroes:
			if is_instance_valid(hero) and not hero.is_unit and hero.profile != null \
					and hero.team == team:
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
		var slot_size := 48.0 if narrow else (56.0 if compact else 64.0)
		var gap := 7.0 if narrow else (14.0 if compact else 16.0)
		var total := slots.size() * slot_size + (slots.size() - 1) * gap
		var sx := left + (right - left - total) / 2.0
		var sy := rect.position.y + (54.0 if compact and not narrow else (52.0 if narrow else 70.0))
		for i in range(slots.size()):
			_draw_ability_slot(Rect2(sx + i * (slot_size + gap), sy, slot_size, slot_size),
				slots[i], not narrow)

		# MOBA: lompakko kykyrivin vasemmalla puolella ja 6 itemin minirivi
		# oikealla puolella (kauppa täyttää; ikonit ItemIconista).
		if arena != null and arena.mode == "moba":
			var mini_y := sy + slot_size / 2.0
			var wx := left + 8.0
			_draw_diamond(Vector2(wx, mini_y), 5.0, Palette.glow(Palette.GOLD, 1.2))
			UiKit.draw_text(self, Vector2(wx + 11.0, mini_y + 4.0),
				str(hero.profile.wallet()), 12 if compact else 15,
				Palette.glow(Palette.GOLD, 1.1), false, 2)
			var items_arr: Array = hero.items
			var ir := 7.0 if narrow else 10.0
			var avail := right - (sx + total) - 8.0
			var istep := minf(ir * 2.0 + 4.0, (avail - ir * 2.0) / 5.0)
			var ix0 := sx + total + 8.0 + ir
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
			var hint := "KEHITÄ: PIDÄ D-PAD YLÖS + KYKYNAPPI" if pad_hint \
				else "KEHITÄ: PIDÄ T + KYKYNAPPI"
			UiKit.draw_text(self, Vector2(rect.get_center().x, rect.position.y - 12.0), hint,
				10 if compact else 12,
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.2), 0.7 + 0.3 * sin(_time * 5.0)),
				true, 2)

		if hero.carrying:
			var gem := rect.position + Vector2(18, 18)
			_draw_diamond(gem, 8.0 + sin(_time * 6.0), Palette.glow(Palette.GOLD, 1.5))

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


	func _slot_data(hero) -> Array:
		var pad: bool = hero.profile.device >= 0
		var spend: bool = bool(hero._spend_mode_active())
		var abilities: Dictionary = HeroDef.get_def(hero.hero_id)["abilities"]
		var keys := {
			"basic": "R2" if pad else "M1",
			"a1": "R1" if pad else "M2",
			"a2": "L1" if pad else "Q",
			"ult": "L2" if pad else "E",
			"dodge": "X" if pad else "SPACE",
		}
		var out: Array = []
		for slot in ["basic", "a1", "a2", "ult", "dodge"]:
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
				"hero_id": hero.hero_id, "slot": slot, "name": str(abilities[slot]["name"]), "key": str(keys[slot]),
				"frac": frac, "cd": cd, "color": col,
				"rank": int(hero.ability_ranks[slot]), "can_rank": bool(hero.can_rank(slot)),
				"locked": slot == "ult" and not bool(hero.ult_unlocked()), "spend": spend,
				"lock_level": (int(hero.ULT_RANK_LEVELS[0]) if slot == "ult" else 0),
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
		if show_name:
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
				if slot == "a1":
					draw_line(center - Vector2.RIGHT * r, center + Vector2.RIGHT * r * 0.62, col, 2.8)
					draw_polyline(PackedVector2Array([
						center + Vector2(r, 0), center + Vector2(r * 0.45, -r * 0.38),
						center + Vector2(r * 0.62, 0), center + Vector2(r * 0.45, r * 0.38)]), col, 2.8)
				elif slot == "dodge":
					draw_line(center + Vector2(0, -r), center + Vector2(0, r * 0.7), col, 4.0)
					draw_line(center + Vector2(-r * 0.75, r * 0.7), center + Vector2(r * 0.75, r * 0.7), col, 3.0)
				else:
					_draw_rotor_glyph(center, r, col, 10 if slot == "ult" else 6)
			"vesper":
				if slot == "a2":
					for i in range(-1, 2):
						draw_line(center + Vector2(-r, i * r * 0.45),
							center + Vector2(r, -i * r * 0.45), col, 2.0)
				elif slot == "dodge":
					for i in range(3):
						var d := Vector2.RIGHT.rotated(TAU * i / 3.0)
						draw_colored_polygon(PackedVector2Array([
							center + d * r * 0.2, center + d * r + d.orthogonal() * r * 0.25,
							center + d * r - d.orthogonal() * r * 0.25]), col)
				else:
					draw_arc(center, r * 0.65, 0.0, TAU, 18, col, 2.4)
					for i in range(4):
						var d := Vector2.RIGHT.rotated(TAU * i / 4.0)
						draw_line(center + d * r * 0.25, center + d * r, col, 2.2)
			"myria":
				var count := 4 if slot in ["dodge", "ult"] else 3
				for i in range(count):
					var d := Vector2.RIGHT.rotated(TAU * i / count - PI * 0.5)
					draw_circle(center + d * r * 0.68, r * 0.16, col)
					draw_line(center + d * r * 0.18, center + d * r * 0.55, col, 1.8)
				draw_circle(center, r * 0.22, col)
			"torq":
				var hex := PackedVector2Array()
				for i in range(7):
					hex.append(center + Vector2.RIGHT.rotated(TAU * i / 6.0) * r * 0.72)
				draw_polyline(hex, col, 3.0 if slot in ["dodge", "ult"] else 2.2)
				if slot == "a2":
					for i in range(4):
						var d := Vector2.RIGHT.rotated(TAU * i / 4.0)
						draw_line(center + d * r * 0.18, center + d * r, col, 2.3)
				else:
					draw_circle(center, r * 0.22, col)


	func _draw_rotor_glyph(center: Vector2, r: float, col: Color, teeth: int) -> void:
		for i in range(teeth):
			var d := Vector2.RIGHT.rotated(TAU * i / teeth)
			draw_line(center + d * r * 0.32, center + d * r, col, 2.4)
		draw_circle(center, r * 0.28, col)


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
		var rect := _dock_rect()
		var pad: bool = hero.profile.device >= 0
		# Kykypistevihje käyttää saman kohdan -> nosta kauppavihje sen ylle.
		var y := rect.position.y - (30.0 if int(hero.skill_points) > 0 else 12.0)
		UiKit.draw_text(self, Vector2(rect.get_center().x, y),
			"KAUPPA: YMPYRÄ" if pad else "KAUPPA: F", 10 if _compact() else 12,
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.15),
				0.65 + 0.35 * sin(_time * 4.0)), true, 2)


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


	func _draw_minimap() -> void:
		if arena.map == null:
			return
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
		if arena.map.has_method("brush_zones"):
			for brush in arena.map.brush_zones():
				var br := brush as Rect2
				var ba := _map_point(br.position, map_origin, world_size, scale_map)
				var bb := _map_point(br.end, map_origin, world_size, scale_map)
				draw_rect(Rect2(ba, bb - ba), Color("245b3477"))
				draw_rect(Rect2(ba, bb - ba), Color("70b87866"), false, 1.0)

		# Viidakon pääväylät: leirit -> risteykset -> Dragon/Baron/gank-portit.
		if arena.map.has_method("jungle_paths"):
			for raw_path in arena.map.jungle_paths():
				var jungle_pts := PackedVector2Array()
				for wp in raw_path:
					jungle_pts.append(_map_point(wp, map_origin, world_size, scale_map))
				if jungle_pts.size() >= 2:
					draw_polyline(jungle_pts, Color("477b4d77"), 3.0)
		if arena.map.has_method("jungle_choke_points"):
			for choke in arena.map.jungle_choke_points():
				var ch := _map_point(choke, map_origin, world_size, scale_map)
				draw_circle(ch, 1.8 if compact else 2.4, Color("a3d98a"))
		if arena.map.has_method("lane_alcove_paths"):
			for raw_path in arena.map.lane_alcove_paths():
				var alcove_pts := PackedVector2Array()
				for wp in raw_path:
					alcove_pts.append(_map_point(wp, map_origin, world_size, scale_map))
				if alcove_pts.size() >= 2:
					draw_polyline(alcove_pts, Color("d0ad5477"), 2.0)

		# MOBA-reitit tulevat kartalta: uusi kenttä piirtää topin ja bottomin.
		var paths: Array = []
		if arena.map.has_method("lane_paths"):
			for path in arena.map.lane_paths().values():
				paths.append(path)
		elif arena.map.has_method("lane_path"):
			paths.append(arena.map.lane_path())
		for path in paths:
			var lane_pts := PackedVector2Array()
			for wp in path:
				lane_pts.append(_map_point(wp, map_origin, world_size, scale_map))
			if lane_pts.size() >= 2:
				draw_polyline(lane_pts, Color(0.3, 0.42, 0.55, 0.5), 5.0)
				draw_polyline(lane_pts, Color(0.65, 0.75, 0.84, 0.55), 1.5)

		# Leirit ja major objectivet ovat näkyvissä jo ennen spawnia, jotta
		# suurta viidakkoa voi lukea nopeasti myös kahden pelaajan splitissä.
		if arena.map.has_method("camp_markers"):
			for marker in arena.map.camp_markers():
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
				draw_circle(cp, cr, ccol)
				draw_arc(cp, cr + 1.5, 0, TAU, 14, Palette.with_alpha(Color.WHITE, 0.55), 1.0)

		# Base: fountain/sanctuary, tuleva shop ja oman tiimin jungle-oikotiet.
		if arena.map.has_method("sanctuary_rect"):
			for team in range(2):
				var sr: Rect2 = arena.map.sanctuary_rect(team)
				var sa := _map_point(sr.position, map_origin, world_size, scale_map)
				var sb := _map_point(sr.end, map_origin, world_size, scale_map)
				var tcol := Palette.team(team)
				draw_rect(Rect2(sa, sb - sa), Palette.with_alpha(tcol, 0.22))
				draw_rect(Rect2(sa, sb - sa), Palette.with_alpha(tcol, 0.62), false, 1.0)
				var shop_pos := _map_point(arena.map.shop_spot(team), map_origin, world_size, scale_map)
				draw_circle(shop_pos, 3.2 if compact else 4.2, Color("e7c34b"))
				for door_id in arena.map.jungle_door_ids():
					var gr: Rect2 = arena.map.jungle_door_rect(team, door_id)
					var gc := _map_point(gr.get_center(), map_origin, world_size, scale_map)
					var arrow_dir := 1.0 if team == 0 else -1.0
					draw_line(gc - Vector2(arrow_dir * 3.5, 0),
						gc + Vector2(arrow_dir * 3.5, 0), Palette.with_alpha(tcol, 0.9), 2.0)
					_draw_diamond(gc + Vector2(arrow_dir * 3.5, 0), 2.2,
						Palette.with_alpha(tcol, 0.9))

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

		# Oman kameran alue ja oma suuntanuoli tekevät neljästä kartasta aidosti
		# pelaajakohtaisia.
		var view_half := Vector2(540.0, 540.0)
		var view_a := _map_point(bound_hero.global_position - view_half,
			map_origin, world_size, scale_map)
		var view_b := _map_point(bound_hero.global_position + view_half,
			map_origin, world_size, scale_map)
		draw_rect(Rect2(view_a, view_b - view_a), Palette.with_alpha(pcol, 0.48), false, 1.0)

		for hero in arena.heroes:
			if not is_instance_valid(hero) or not hero.alive or hero.is_unit or hero.profile == null:
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
			else:
				_draw_diamond(hp, 4.0 if compact else 5.5, Palette.team(hero.team))

		if arena.relic != null and is_instance_valid(arena.relic):
			var rp := _map_point(arena.relic.global_position, map_origin, world_size, scale_map)
			_draw_diamond(rp, 3.5 if compact else 5.0, Palette.GOLD)
		draw_rect(world_rect, Palette.with_alpha(Palette.UI_STROKE, 0.55), false, 1.0)


	func _map_point(world_pos: Vector2, origin: Vector2, world_size: Vector2,
			scale_map: float) -> Vector2:
		return origin + (world_pos + world_size / 2.0) * scale_map


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
