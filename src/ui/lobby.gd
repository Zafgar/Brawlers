class_name Lobby
extends Control
## Pelaajien liittyminen, joukkuevalinta ja sankarivalinta.
## Jokainen laite (näppäimistö + jokainen ohjain) pollataan erikseen,
## joten kaikki paikallispelaajat toimivat itsenäisesti yhtä aikaa.

enum Phase { JOIN, HEROES, STARTING }

# Ruudukko mitoitettu 15 sankarille: 5 saraketta = 3 riviä, mahtuu pelaaja-
# chippien (y=830) ja kykypaneelin (x=1160) väliin ilman päällekkäisyyttä.
const COLS := 5
const TILE_W := 202.0
const TILE_H := 196.0
const TILE_GAP := 18.0

var phase: int = Phase.JOIN

# players: [{profile, ready, cursor, locked}], vain ihmiset
var players: Array = []
var bots: Array = []

var _prev := {}
var _time := 0.0
var _deny := {"tile": -1, "t": 0.0}
var _bot_pick_timer := 0.0
var _start_timer := 0.0
var _bot_counter := 0
var _detail_index := 0     # mitä sankaria kykypaneeli näyttää (viimeksi liikutettu kursori)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AudioMgr.play_music_pool("lobby")
	var backdrop := MenuBackdrop.new()
	backdrop.team_glow = true
	add_child(backdrop)


func _process(delta: float) -> void:
	_time += delta
	_deny.t = maxf(_deny.t - delta, 0.0)

	var devices: Array = [-1]
	for pad in Input.get_connected_joypads():
		devices.append(pad)
	for device in devices:
		var now := _poll_device(device)
		if not _prev.has(device):
			_prev[device] = now
			continue
		var edge := {}
		for key in now:
			edge[key] = now[key] and not _prev[device][key]
		_prev[device] = now
		_handle_input(device, edge)

	if phase == Phase.HEROES:
		_tick_bot_picks(delta)
	elif phase == Phase.STARTING:
		_start_timer -= delta
		if _start_timer <= 0.0:
			phase = Phase.JOIN  # estä tuplakäynnistys
			var roster: Array = []
			for entry in players:
				roster.append(entry.profile)
			roster.append_array(bots)
			Game.roster = roster
			Game.start_match()
			return

	queue_redraw()


func _poll_device(device: int) -> Dictionary:
	if device == -1:
		return {
			"accept": Input.is_physical_key_pressed(KEY_ENTER) \
				or Input.is_physical_key_pressed(KEY_KP_ENTER),
			"cancel": Input.is_physical_key_pressed(KEY_ESCAPE),
			"left": Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT),
			"right": Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT),
			"up": Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP),
			"down": Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN),
		}
	var lx := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	return {
		"accept": Input.is_joy_button_pressed(device, JOY_BUTTON_A) \
			or Input.is_joy_button_pressed(device, JOY_BUTTON_START),
		"cancel": Input.is_joy_button_pressed(device, JOY_BUTTON_B),
		"left": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) or lx < -0.6,
		"right": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) or lx > 0.6,
		"up": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP) or ly < -0.6,
		"down": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN) or ly > 0.6,
	}


func _handle_input(device: int, edge: Dictionary) -> void:
	match phase:
		Phase.JOIN:
			_handle_join_input(device, edge)
		Phase.HEROES:
			_handle_heroes_input(device, edge)


# --- JOIN-vaihe ---

func _player_by_device(device: int) -> Dictionary:
	for entry in players:
		if entry.profile.device == device:
			return entry
	return {}


func _team_human_count(team: int) -> int:
	var count := 0
	for entry in players:
		if entry.profile.team == team:
			count += 1
	return count


func _handle_join_input(device: int, edge: Dictionary) -> void:
	var entry := _player_by_device(device)

	if edge.accept:
		if entry.is_empty():
			if players.size() < Game.team_size * 2:
				_join(device)
		else:
			entry.ready = not entry.ready
			AudioMgr.play("ui_ok" if entry.ready else "ui_back")
			_check_all_ready()
		return

	if edge.cancel:
		if entry.is_empty():
			if players.is_empty():
				AudioMgr.play("ui_back")
				if Game.practice:
					Game.go_menu()
				else:
					Game.go_setup(false)
		elif entry.ready:
			entry.ready = false
			AudioMgr.play("ui_back")
		else:
			players.erase(entry)
			for i in range(players.size()):
				players[i].profile.index = i
			AudioMgr.play("ui_back")
		return

	if entry.is_empty() or entry.ready:
		return
	if edge.left and entry.profile.team == 1 and _team_human_count(0) < Game.team_size:
		entry.profile.team = 0
		AudioMgr.play("ui_move")
	elif edge.right and entry.profile.team == 0 and _team_human_count(1) < Game.team_size:
		entry.profile.team = 1
		AudioMgr.play("ui_move")


func _join(device: int) -> void:
	var profile := PlayerProfile.new()
	profile.index = players.size()
	profile.device = device
	profile.is_bot = false
	profile.display_name = "Pelaaja %d" % (players.size() + 1)
	var blue_count := _team_human_count(0)
	var orange_count := _team_human_count(1)
	if blue_count <= orange_count and blue_count < Game.team_size:
		profile.team = 0
	elif orange_count < Game.team_size:
		profile.team = 1
	else:
		profile.team = 0
	players.append({"profile": profile, "ready": false, "cursor": 0, "locked": false})
	AudioMgr.play("ui_ok")


func _check_all_ready() -> void:
	if players.is_empty():
		return
	for entry in players:
		if not entry.ready:
			return
	_enter_heroes()


func _enter_heroes() -> void:
	phase = Phase.HEROES
	AudioMgr.play("count_tick")
	_bot_counter = 0
	bots.clear()
	for i in range(players.size()):
		players[i].cursor = i % HeroDef.ORDER.size()
		players[i].locked = false
		players[i].profile.hero_id = ""
	for team in [0, 1]:
		while _team_total_count(team) < Game.team_size:
			_bot_counter += 1
			var bot := PlayerProfile.new()
			bot.index = players.size() + bots.size()
			bot.device = -2
			bot.is_bot = true
			bot.team = team
			bot.display_name = "Botti %d" % _bot_counter
			bots.append(bot)


func _team_total_count(team: int) -> int:
	var count := _team_human_count(team)
	for bot in bots:
		if bot.team == team:
			count += 1
	return count


# --- HEROES-vaihe ---

func _team_hero_ids(team: int) -> Array:
	var ids: Array = []
	for entry in players:
		if entry.profile.team == team and entry.locked and entry.profile.hero_id != "":
			ids.append(entry.profile.hero_id)
	for bot in bots:
		if bot.team == team and bot.hero_id != "":
			ids.append(bot.hero_id)
	return ids


func _handle_heroes_input(device: int, edge: Dictionary) -> void:
	var entry := _player_by_device(device)
	if entry.is_empty():
		return

	if not entry.locked:
		var rows := int(ceil(float(HeroDef.ORDER.size()) / COLS))
		var col: int = entry.cursor % COLS
		var row: int = entry.cursor / COLS
		var moved := false
		if edge.left:
			col = (col + COLS - 1) % COLS
			moved = true
		elif edge.right:
			col = (col + 1) % COLS
			moved = true
		elif edge.up:
			row = (row + rows - 1) % rows
			moved = true
		elif edge.down:
			row = (row + 1) % rows
			moved = true
		if moved:
			entry.cursor = mini(row * COLS + col, HeroDef.ORDER.size() - 1)
			_detail_index = entry.cursor
			AudioMgr.play("ui_move")

	if edge.accept and not entry.locked:
		var hero_id: String = HeroDef.ORDER[entry.cursor]
		if hero_id in _team_hero_ids(entry.profile.team):
			_deny = {"tile": entry.cursor, "t": 0.5}
			AudioMgr.play("ui_back")
		else:
			entry.locked = true
			entry.profile.hero_id = hero_id
			_detail_index = entry.cursor
			AudioMgr.play("ui_ok")
			if _all_humans_locked():
				_bot_pick_timer = 0.5
		return

	if edge.cancel:
		if entry.locked:
			entry.locked = false
			entry.profile.hero_id = ""
			for bot in bots:
				bot.hero_id = ""
			AudioMgr.play("ui_back")
		else:
			phase = Phase.JOIN
			bots.clear()
			for other in players:
				other.ready = false
				other.locked = false
				other.profile.hero_id = ""
			AudioMgr.play("ui_back")


func _all_humans_locked() -> bool:
	for entry in players:
		if not entry.locked:
			return false
	return true


func _tick_bot_picks(delta: float) -> void:
	if not _all_humans_locked():
		return
	var next_bot: PlayerProfile = null
	for bot in bots:
		if bot.hero_id == "":
			next_bot = bot
			break
	if next_bot == null:
		phase = Phase.STARTING
		_start_timer = 1.4
		AudioMgr.play("count_go")
		return
	_bot_pick_timer -= delta
	if _bot_pick_timer > 0.0:
		return
	_bot_pick_timer = 0.45
	_bot_pick(next_bot)
	AudioMgr.play("ui_ok")


func _bot_pick(bot: PlayerProfile) -> void:
	var taken := _team_hero_ids(bot.team)
	var candidates: Array = []
	for hero_id in HeroDef.ORDER:
		if not hero_id in taken:
			candidates.append(hero_id)
	if candidates.is_empty():
		candidates = HeroDef.ORDER.duplicate()
	# Suosi puuttuvia avainrooleja (tankki, tuki).
	var roles_present: Array = []
	for hero_id in taken:
		roles_present.append(HeroDef.get_def(hero_id)["role"])
	var preferred: Array = []
	for hero_id in candidates:
		var role: String = HeroDef.get_def(hero_id)["role"]
		if role in ["Tankki", "Tuki"] and not role in roles_present:
			preferred.append(hero_id)
	var pool := preferred if not preferred.is_empty() else candidates
	bot.hero_id = pool[randi() % pool.size()]


# --- Piirto ---

func _draw() -> void:
	match phase:
		Phase.JOIN:
			_draw_join()
		Phase.HEROES:
			_draw_heroes()
		Phase.STARTING:
			_draw_heroes()
			UiKit.draw_text(self, Vector2(960, 1000), "OTTELU ALKAA...", 44,
				Palette.glow(Palette.GOLD, 1.3), true, 6)


func _panel_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.85)
	sb.set_corner_radius_all(20)
	sb.border_color = border
	sb.set_border_width_all(3)
	return sb


## Pyöristetty kortti (täyttö + reunus).
func _card(rect: Rect2, bg: Color, border: Color, border_w: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(border_w))
	sb.set_corner_radius_all(int(radius))
	sb.draw(get_canvas_item(), rect)


## Otsikko hehkuvalla joukkuevärialaviivalla.
func _draw_title(text: String, y: float) -> void:
	UiKit.draw_text(self, Vector2(960, y), text, 64, Palette.TEXT_MAIN, true, 8)
	var w := 440.0
	var uy := y + 46.0
	var pulse := 0.5 + 0.5 * sin(_time * 1.5)
	draw_rect(Rect2(960 - w / 2.0, uy, w / 2.0, 6.0), Palette.glow(Palette.TEAM_BLUE, 1.3))
	draw_rect(Rect2(960, uy, w / 2.0, 6.0), Palette.glow(Palette.TEAM_ORANGE, 1.3))
	draw_circle(Vector2(960, uy + 3.0), 8.0 + pulse * 2.0, Palette.glow(Palette.GOLD, 1.5))


## Tyhjä (botti täyttää) paikka.
func _draw_seat_empty(rect: Rect2) -> void:
	_card(rect, Color(0, 0, 0, 0.22), Palette.with_alpha(Palette.TEXT_DIM, 0.25), 2, 16)
	var bp := rect.position + Vector2(66, rect.size.y / 2.0)
	draw_circle(bp, 30.0, Palette.with_alpha(Palette.TEXT_DIM, 0.15))
	draw_rect(Rect2(bp + Vector2(-16, -14), Vector2(32, 28)), Palette.with_alpha(Palette.TEXT_DIM, 0.4), false, 2.0)
	draw_circle(bp + Vector2(-7, -2), 3.5, Palette.with_alpha(Palette.TEXT_DIM, 0.5))
	draw_circle(bp + Vector2(7, -2), 3.5, Palette.with_alpha(Palette.TEXT_DIM, 0.5))
	draw_line(bp + Vector2(0, -14), bp + Vector2(0, -22), Palette.with_alpha(Palette.TEXT_DIM, 0.4), 2.0)
	UiKit.draw_text(self, rect.position + Vector2(128, rect.size.y / 2.0 - 8.0),
		"BOTTI TÄYTTÄÄ", 24, Palette.with_alpha(Palette.TEXT_DIM, 0.6), false)
	UiKit.draw_text(self, rect.position + Vector2(128, rect.size.y / 2.0 + 22.0),
		"tai liity tähän paikkaan", 15, Palette.with_alpha(Palette.TEXT_DIM, 0.45), false)


func _draw_join() -> void:
	_draw_title("PELAAJAT", 78)
	UiKit.draw_text(self, Vector2(960, 150),
		"Paina X (ohjain) tai Enter (näppäimistö) liittyäksesi", 24, Palette.TEXT_DIM, true)

	for team in [0, 1]:
		var panel_x := 150.0 if team == 0 else 990.0
		var tc: Color = Palette.team(team)
		var rect := Rect2(panel_x, 210, 780, 720)
		# Hehku paneelin taakse
		draw_circle(rect.get_center(), 320.0, Palette.with_alpha(tc, 0.05))
		_card(rect, Palette.with_alpha(Palette.UI_PANEL, 0.85), Palette.with_alpha(tc, 0.6), 3, 22)
		# Otsikkopalkki
		UiKit.draw_text(self, Vector2(panel_x + 390, 254), Game.team_name(team), 34, tc, true, 5)
		UiKit.draw_text(self, Vector2(panel_x + 710, 254),
			"%d/%d" % [_team_human_count(team), Game.team_size], 22,
			Palette.with_alpha(tc, 0.85), true)
		draw_line(Vector2(panel_x + 40, 288), Vector2(panel_x + 740, 288),
			Palette.with_alpha(tc, 0.35), 2.0)

		var seat := 0
		for entry in players:
			if entry.profile.team != team:
				continue
			_draw_seat_human(Rect2(panel_x + 34, 306 + seat * 150.0, 712, 132), entry)
			seat += 1
		while seat < Game.team_size:
			_draw_seat_empty(Rect2(panel_x + 34, 306 + seat * 150.0, 712, 132))
			seat += 1

	UiKit.draw_text(self, Vector2(960, 990),
		"X/Enter: liity ja valmis · ristiohjain tai A/D: vaihda joukkuetta · O/Esc: poistu", 22,
		Palette.TEXT_DIM, true)
	UiKit.draw_text(self, Vector2(960, 1030),
		"Kun kaikki ovat valmiita, tyhjät paikat täytetään boteilla", 18,
		Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)


func _draw_seat_human(rect: Rect2, entry: Dictionary) -> void:
	var profile: PlayerProfile = entry.profile
	var pc: Color = profile.color()
	_card(rect, Palette.with_alpha(pc, 0.10), Palette.with_alpha(pc, 0.9), 3, 16)

	# Pelaajamedaljonki
	var badge := rect.position + Vector2(66, rect.size.y / 2.0)
	draw_circle(badge, 40.0, Palette.with_alpha(Color.BLACK, 0.3))
	draw_circle(badge, 36.0, pc)
	draw_circle(badge + Vector2(-11, -11), 9.0, Palette.with_alpha(Color.WHITE, 0.35))
	UiKit.draw_text(self, badge + Vector2(0, 2), str(profile.index + 1), 34, Palette.TEXT_DARK, true)

	UiKit.draw_text(self, rect.position + Vector2(128, rect.size.y / 2.0 - 14.0),
		profile.display_name, 28, Palette.TEXT_MAIN, false)
	_draw_device_icon(rect.position + Vector2(128, rect.size.y / 2.0 + 22.0), profile.device)

	# Valmiustila
	var rp := rect.position + Vector2(rect.size.x - 84, rect.size.y / 2.0)
	if entry.ready:
		draw_circle(rp, 30.0, Palette.with_alpha(Palette.GOOD, 0.25))
		draw_circle(rp, 24.0, Palette.GOOD)
		draw_line(rp + Vector2(-11, 0), rp + Vector2(-3, 10), Palette.TEXT_DARK, 5.0)
		draw_line(rp + Vector2(-3, 10), rp + Vector2(13, -10), Palette.TEXT_DARK, 5.0)
		UiKit.draw_text(self, rect.position + Vector2(rect.size.x - 84, rect.size.y - 18.0),
			"VALMIS", 12, Palette.GOOD, true)
	else:
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_arc(rp, 24.0, 0.0, TAU, 24, Palette.with_alpha(pc, 0.4 + pulse * 0.3), 3.0)
		UiKit.draw_text(self, rp + Vector2(0, 1), "X", 22, Palette.with_alpha(pc, 0.6 + pulse * 0.4), true)
		UiKit.draw_text(self, rect.position + Vector2(rect.size.x - 84, rect.size.y - 18.0),
			"= VALMIS", 12, Palette.TEXT_DIM, true)


func _draw_device_icon(pos: Vector2, device: int) -> void:
	if device == -1:
		draw_rect(Rect2(pos + Vector2(0, -10), Vector2(44, 20)), Palette.TEXT_DIM, false, 2.0)
		for i in range(3):
			draw_rect(Rect2(pos + Vector2(5 + i * 12, -5), Vector2(8, 4)), Palette.TEXT_DIM)
		draw_rect(Rect2(pos + Vector2(10, 3), Vector2(24, 4)), Palette.TEXT_DIM)
		UiKit.draw_text(self, pos + Vector2(70, 0), "Näppäimistö", 15, Palette.TEXT_DIM, false)
	else:
		draw_circle(pos + Vector2(8, 0), 9.0, Palette.TEXT_DIM)
		draw_circle(pos + Vector2(34, 0), 9.0, Palette.TEXT_DIM)
		draw_rect(Rect2(pos + Vector2(4, -9), Vector2(34, 12)), Palette.TEXT_DIM)
		UiKit.draw_text(self, pos + Vector2(70, 0), "Ohjain %d" % (device + 1), 15,
			Palette.TEXT_DIM, false)


func _draw_heroes() -> void:
	_draw_title("VALITSE SANKARI", 72)

	# Ruudukko vasemmalle, kykypaneeli oikealle (kaksipalstainen asettelu).
	var x0 := 58.0
	var y0 := 176.0
	for i in range(HeroDef.ORDER.size()):
		var col := i % COLS
		var row := i / COLS
		var rect := Rect2(x0 + col * (TILE_W + TILE_GAP), y0 + row * (TILE_H + TILE_GAP),
			TILE_W, TILE_H)
		_draw_hero_tile(rect, i)

	_draw_hero_detail(_detail_index)

	# Pelaajachipit alareunassa
	var all_profiles: Array = []
	for entry in players:
		all_profiles.append(entry)
	for bot in bots:
		all_profiles.append({"profile": bot, "locked": bot.hero_id != "", "cursor": -1, "ready": true})
	var chip_w := 214.0
	var total_w: float = all_profiles.size() * (chip_w + 10.0) - 10.0
	var chip_x := 960.0 - total_w / 2.0
	for entry in all_profiles:
		_draw_player_chip(Rect2(chip_x, 830, chip_w, 70), entry)
		chip_x += chip_w + 10.0

	UiKit.draw_text(self, Vector2(960, 950),
		"Ristiohjain/tatti tai WASD: liiku · X/Enter: lukitse · O/Esc: peru", 22,
		Palette.TEXT_DIM, true)
	UiKit.draw_text(self, Vector2(960, 990),
		"Saman joukkueen pelaajilla ei voi olla samaa sankaria", 18,
		Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)


func _draw_hero_tile(rect: Rect2, tile_index: int) -> void:
	var hero_id: String = HeroDef.ORDER[tile_index]
	var def := HeroDef.get_def(hero_id)
	var c1: Color = def["color"]
	var c2: Color = def["color_b"]

	var hovered := false
	var any_locked := false
	for entry in players:
		if entry.cursor == tile_index:
			hovered = true
			if entry.locked:
				any_locked = true

	if hovered:
		draw_circle(rect.get_center(), rect.size.x * 0.62, Palette.with_alpha(c1, 0.06))
	var border: Color = Palette.with_alpha(c1, 0.8) if hovered else Palette.with_alpha(c2, 0.7)
	_card(rect, Palette.with_alpha(Palette.UI_PANEL, 0.88), border, 2, 18)

	# Medaljonki hehkukehineen
	var med := rect.position + Vector2(rect.size.x / 2.0, 60.0)
	draw_arc(med, 42.0, _time, _time + TAU * 0.8, 24, Palette.with_alpha(Palette.glow(c1, 1.3), 0.5), 2.0)
	draw_circle(med, 38.0, Palette.darker(c2, 0.55))
	draw_circle(med, 34.0, c1)
	draw_circle(med + Vector2(0, 12), 24.0, Palette.with_alpha(c2, 0.35))
	HeroIcon.draw_symbol(self, hero_id, med, 22.0)

	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 126.0),
		def["name"], 25, Palette.TEXT_MAIN, true, 4)
	var stars := ""
	for i in range(3):
		stars += "★" if i < int(def["difficulty"]) else "☆"
	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 154.0),
		"%s  %s" % [def["role"], stars], 17, c1, true)
	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 178.0),
		def["weapon"], 13, Palette.TEXT_DIM, true)

	# Lukituksen tummennus (tekstien päälle, ennen kehyksiä)
	if any_locked:
		_card(rect, Color(0.03, 0.04, 0.1, 0.42), Color(0, 0, 0, 0), 0, 18)

	# Kursorikehykset (jokaisen pelaajan oma väri, pinottu)
	var inset := 0.0
	for entry in players:
		if entry.cursor != tile_index:
			continue
		var alpha := 0.55 if entry.locked else (0.75 + 0.25 * sin(_time * 5.0))
		draw_rect(rect.grow(-inset), Palette.with_alpha(entry.profile.color(), alpha), false,
			4.0 if not entry.locked else 3.0)
		inset += 6.0

	# Lukitus-check päälle
	if any_locked:
		var lc := rect.get_center()
		draw_circle(lc, 30.0, Palette.with_alpha(Palette.GOOD, 0.25))
		draw_circle(lc, 23.0, Palette.GOOD)
		draw_line(lc + Vector2(-10, 0), lc + Vector2(-2, 9), Palette.TEXT_DARK, 5.0)
		draw_line(lc + Vector2(-2, 9), lc + Vector2(12, -9), Palette.TEXT_DARK, 5.0)

	if _deny.tile == tile_index and _deny.t > 0.0:
		draw_rect(rect, Palette.with_alpha(Palette.BAD, _deny.t), false, 5.0)


## Kykypaneeli oikealle: näyttää kursorin alla olevan sankarin kaikki kyvyt
## ja mitä ne tekevät. Näin näkee pelivalikossa mihin sankari pystyy.
func _draw_hero_detail(index: int) -> void:
	var hero_id: String = HeroDef.ORDER[index]
	var def := HeroDef.get_def(hero_id)
	var c1: Color = def["color"]
	var panel := Rect2(1160, 176, 690, 646)
	_card(panel, Palette.with_alpha(Palette.UI_PANEL, 0.92), Palette.with_alpha(c1, 0.55), 2, 18)

	var px := panel.position.x
	var cx := px + panel.size.x / 2.0

	# Medaljonki, nimi ja rooli
	var med := Vector2(cx, panel.position.y + 64.0)
	draw_arc(med, 48.0, _time, _time + TAU * 0.8, 24, Palette.with_alpha(Palette.glow(c1, 1.3), 0.5), 2.0)
	draw_circle(med, 44.0, Palette.darker(def["color_b"], 0.55))
	draw_circle(med, 40.0, c1)
	draw_circle(med + Vector2(0, 14), 27.0, Palette.with_alpha(def["color_b"], 0.35))
	HeroIcon.draw_symbol(self, hero_id, med, 25.0)
	UiKit.draw_text(self, Vector2(cx, panel.position.y + 132.0), str(def["name"]), 32, c1, true, 5)
	var stars := ""
	for i in range(3):
		stars += "★" if i < int(def["difficulty"]) else "☆"
	UiKit.draw_text(self, Vector2(cx, panel.position.y + 164.0),
		"%s   %s   ·   %s" % [def["role"], stars, def["weapon"]], 16, Palette.TEXT_DIM, true)
	draw_line(Vector2(px + 26.0, panel.position.y + 186.0),
		Vector2(panel.end.x - 26.0, panel.position.y + 186.0), Palette.with_alpha(c1, 0.3), 2.0)

	# Kyvyt kuvauksineen
	var slots := [
		["basic", "PERUS", "R2 / hiiri vas."],
		["a1", "KYKY 1", "R1 / hiiri oik."],
		["a2", "KYKY 2", "L1 / Q"],
		["dodge", "VÄISTÖ", "X / väli"],
		["ult", "ULTI", "L2 / E"],
	]
	var font := ThemeDB.fallback_font
	var lx := px + 28.0
	var y := panel.position.y + 214.0
	for slot in slots:
		var ab: Dictionary = def["abilities"][slot[0]]
		UiKit.draw_text(self, Vector2(lx, y - 2.0), str(slot[1]), 11, Palette.with_alpha(c1, 0.85), false)
		UiKit.draw_text(self, Vector2(lx + 84.0, y), str(ab["name"]), 20, Palette.TEXT_MAIN, false)
		UiKit.draw_text(self, Vector2(panel.end.x - 150.0, y), str(slot[2]), 12, Palette.TEXT_DIM, false)
		font.draw_multiline_string(get_canvas_item(), Vector2(lx + 84.0, y + 22.0),
			str(ab["desc"]), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 128.0, 15, -1, Palette.TEXT_DIM)
		y += 78.0


func _draw_player_chip(rect: Rect2, entry: Dictionary) -> void:
	var profile: PlayerProfile = entry.profile
	var tc: Color = Palette.team(profile.team)
	var locked: bool = entry.get("locked", false)
	_card(rect, Palette.with_alpha(tc, 0.16), Palette.with_alpha(tc, 0.6), 2, 12)

	# Pelaajatunnus vasemmalle
	if profile.is_human():
		draw_circle(rect.position + Vector2(24, rect.size.y / 2.0), 15.0, profile.color())
		UiKit.draw_text(self, rect.position + Vector2(24, rect.size.y / 2.0 + 1),
			str(profile.index + 1), 16, Palette.TEXT_DARK, true)
	else:
		UiKit.draw_text(self, rect.position + Vector2(24, rect.size.y / 2.0), "BOT", 13,
			Palette.TEXT_DIM, true)

	UiKit.draw_text(self, rect.position + Vector2(48, 22), profile.display_name, 16,
		Palette.TEXT_MAIN, false)
	var pick_text := "..."
	if profile.hero_id != "":
		pick_text = HeroDef.get_def(profile.hero_id)["name"]
	UiKit.draw_text(self, rect.position + Vector2(48, 48), pick_text, 16,
		Palette.GOLD if locked else Palette.TEXT_DIM, false)

	# Valitun sankarin medaljonki oikealle
	if profile.hero_id != "":
		var hdef := HeroDef.get_def(profile.hero_id)
		var med := rect.position + Vector2(rect.size.x - 28.0, rect.size.y / 2.0)
		draw_circle(med, 21.0, Palette.darker(hdef["color_b"], 0.55))
		draw_circle(med, 17.0, hdef["color"])
		HeroIcon.draw_symbol(self, profile.hero_id, med, 11.0)
		if locked:
			draw_circle(med + Vector2(13, -13), 8.0, Palette.GOOD)
			draw_line(med + Vector2(9, -13), med + Vector2(12, -10), Palette.TEXT_DARK, 2.0)
			draw_line(med + Vector2(12, -10), med + Vector2(17, -16), Palette.TEXT_DARK, 2.0)
