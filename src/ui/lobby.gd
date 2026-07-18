class_name Lobby
extends Control
## Pelaajien liittyminen, joukkuevalinta ja sankarivalinta.
## Jokainen laite (näppäimistö + jokainen ohjain) pollataan erikseen,
## joten kaikki paikallispelaajat toimivat itsenäisesti yhtä aikaa.

enum Phase { JOIN, HEROES, STARTING }

const COLS := 4
const TILE_W := 250.0
const TILE_H := 200.0
const TILE_GAP := 20.0

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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
			AudioMgr.play("ui_move")

	if edge.accept and not entry.locked:
		var hero_id: String = HeroDef.ORDER[entry.cursor]
		if hero_id in _team_hero_ids(entry.profile.team):
			_deny = {"tile": entry.cursor, "t": 0.5}
			AudioMgr.play("ui_back")
		else:
			entry.locked = true
			entry.profile.hero_id = hero_id
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


func _draw_join() -> void:
	UiKit.draw_text(self, Vector2(960, 80), "PELAAJAT", 64, Palette.TEXT_MAIN, true, 8)
	UiKit.draw_text(self, Vector2(960, 140),
		"Paina X (ohjain) tai Enter (näppäimistö) liittyäksesi", 24, Palette.TEXT_DIM, true)

	for team in [0, 1]:
		var panel_x := 150.0 if team == 0 else 990.0
		var rect := Rect2(panel_x, 210, 780, 720)
		_panel_style(Palette.with_alpha(Palette.team(team), 0.6))\
			.draw(get_canvas_item(), rect)
		UiKit.draw_text(self, Vector2(panel_x + 390, 250),
			Game.team_name(team), 34, Palette.team(team), true, 5)

		var seat := 0
		for entry in players:
			if entry.profile.team != team:
				continue
			_draw_seat_human(Rect2(panel_x + 40, 290 + seat * 155.0, 700, 140), entry)
			seat += 1
		while seat < Game.team_size:
			var seat_rect := Rect2(panel_x + 40, 290 + seat * 155.0, 700, 140)
			draw_rect(seat_rect, Color(0, 0, 0, 0.28))
			UiKit.draw_text(self, seat_rect.get_center() + Vector2(0, -12), "BOTTI", 26,
				Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)
			UiKit.draw_text(self, seat_rect.get_center() + Vector2(0, 22),
				"tai vapaa paikka pelaajalle", 16, Palette.with_alpha(Palette.TEXT_DIM, 0.5), true)
			seat += 1

	UiKit.draw_text(self, Vector2(960, 990),
		"X/Enter: liity ja valmis · ristiohjain tai A/D: vaihda joukkuetta · O/Esc: poistu", 22,
		Palette.TEXT_DIM, true)
	UiKit.draw_text(self, Vector2(960, 1030),
		"Kun kaikki ovat valmiita, tyhjät paikat täytetään boteilla", 18,
		Palette.with_alpha(Palette.TEXT_DIM, 0.7), true)


func _draw_seat_human(rect: Rect2, entry: Dictionary) -> void:
	var profile: PlayerProfile = entry.profile
	draw_rect(rect, Color(0, 0, 0, 0.4))
	draw_rect(rect, Palette.with_alpha(profile.color(), 0.9), false, 3.0)

	var badge := rect.position + Vector2(70, rect.size.y / 2.0)
	draw_circle(badge, 36.0, profile.color())
	UiKit.draw_text(self, badge + Vector2(0, 2), str(profile.index + 1), 34,
		Palette.TEXT_DARK, true)

	UiKit.draw_text(self, rect.position + Vector2(150, rect.size.y / 2.0 - 16.0),
		profile.display_name, 28, Palette.TEXT_MAIN, false)
	_draw_device_icon(rect.position + Vector2(150, rect.size.y / 2.0 + 22.0), profile.device)

	if entry.ready:
		var check := rect.position + Vector2(rect.size.x - 70, rect.size.y / 2.0)
		draw_circle(check, 26.0, Palette.GOOD)
		draw_line(check + Vector2(-10, 0), check + Vector2(-3, 9), Palette.TEXT_DARK, 5.0)
		draw_line(check + Vector2(-3, 9), check + Vector2(12, -9), Palette.TEXT_DARK, 5.0)
	else:
		UiKit.draw_text(self, rect.position + Vector2(rect.size.x - 90, rect.size.y / 2.0),
			"VALMIS?", 20, Palette.with_alpha(Palette.TEXT_DIM, 0.6 + 0.3 * sin(_time * 3.0)), true)


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
	UiKit.draw_text(self, Vector2(960, 80), "VALITSE SANKARI", 64, Palette.TEXT_MAIN, true, 8)

	var x0 := (1920.0 - (COLS * TILE_W + (COLS - 1) * TILE_GAP)) / 2.0
	var y0 := 150.0
	for i in range(HeroDef.ORDER.size()):
		var col := i % COLS
		var row := i / COLS
		var rect := Rect2(x0 + col * (TILE_W + TILE_GAP), y0 + row * (TILE_H + TILE_GAP),
			TILE_W, TILE_H)
		_draw_hero_tile(rect, i)

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
	_panel_style(Palette.with_alpha(def["color_b"], 0.7)).draw(get_canvas_item(), rect)

	var med := rect.position + Vector2(rect.size.x / 2.0, 62.0)
	draw_circle(med, 38.0, Palette.darker(def["color_b"], 0.55))
	draw_circle(med, 34.0, def["color"])
	draw_circle(med + Vector2(0, 12), 24.0, Palette.with_alpha(def["color_b"], 0.35))
	HeroIcon.draw_symbol(self, hero_id, med, 22.0)

	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 126.0),
		def["name"], 25, Palette.TEXT_MAIN, true, 4)
	var stars := ""
	for i in range(3):
		stars += "★" if i < int(def["difficulty"]) else "☆"
	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 154.0),
		"%s  %s" % [def["role"], stars], 17, def["color"], true)
	UiKit.draw_text(self, rect.position + Vector2(rect.size.x / 2.0, 178.0),
		def["weapon"], 13, Palette.TEXT_DIM, true)

	# Kursorit: jokaisen pelaajan oma värikehys, sisennettynä pinottuna
	var inset := 0.0
	for entry in players:
		if entry.cursor != tile_index:
			continue
		var alpha := 0.5 if entry.locked else (0.75 + 0.25 * sin(_time * 5.0))
		draw_rect(rect.grow(-inset), Palette.with_alpha(entry.profile.color(), alpha), false,
			4.0 if not entry.locked else 2.0)
		inset += 6.0

	if _deny.tile == tile_index and _deny.t > 0.0:
		draw_rect(rect, Palette.with_alpha(Palette.BAD, _deny.t), false, 5.0)


func _draw_player_chip(rect: Rect2, entry: Dictionary) -> void:
	var profile: PlayerProfile = entry.profile
	draw_rect(rect, Palette.with_alpha(Palette.team(profile.team), 0.16))
	draw_rect(rect, Palette.with_alpha(Palette.team(profile.team), 0.6), false, 2.0)

	if profile.is_human():
		draw_circle(rect.position + Vector2(26, rect.size.y / 2.0), 15.0, profile.color())
		UiKit.draw_text(self, rect.position + Vector2(26, rect.size.y / 2.0 + 1),
			str(profile.index + 1), 16, Palette.TEXT_DARK, true)
	else:
		UiKit.draw_text(self, rect.position + Vector2(26, rect.size.y / 2.0), "BOT", 13,
			Palette.TEXT_DIM, true)

	UiKit.draw_text(self, rect.position + Vector2(52, 24), profile.display_name, 17,
		Palette.TEXT_MAIN, false)
	var pick_text := "..."
	if profile.hero_id != "":
		pick_text = HeroDef.get_def(profile.hero_id)["name"]
	var locked: bool = entry.get("locked", false)
	UiKit.draw_text(self, rect.position + Vector2(52, 50), pick_text, 17,
		Palette.GOLD if locked else Palette.TEXT_DIM, false)
