class_name Arena
extends Node2D
## Otteluruutu: rakentaa kentän, sankarit, reliikin, kameran ja HUDin,
## sekä pyörittää erät alusta loppuun (intro -> peli -> erän loppu -> tulokset).

enum State { INTRO, PLAY, ROUND_END, MATCH_END }

const ROUND_TARGET := 40.0        # sekuntia reliikin hallussapitoa
const ROUND_TIME := 150.0
const SUDDEN_DEATH_HOLD := 1.5
const SUDDEN_DEATH_MAX := 45.0

var state: int = State.INTRO
var round_number := 1
var time_left := ROUND_TIME
var relic_points := [0.0, 0.0]
var sudden_death := false

var map: MapBase = null
var relic: Relic = null
var camera: GameCamera = null
var hud = null                    # HudLayer
var heroes: Array = []
var zones: Array = []
var blackboards: Array = []

var _sd_hold := 0.0
var _sd_elapsed := 0.0
var _last_holder_team := -1
var _pause_layer: CanvasLayer = null


func _ready() -> void:
	map = _make_map()
	add_child(map)

	relic = Relic.new()
	relic.setup(self, map.relic_home())
	add_child(relic)

	for profile in Game.roster:
		var hero := _make_hero(profile.hero_id)
		var controller
		if profile.is_bot:
			controller = BotBrain.new(Game.bot_level)
		else:
			controller = DeviceInput.new(profile.device)
		hero.setup(self, profile, controller)
		hero.global_position = map.spawn_point(profile.team, profile.index)
		add_child(hero)
		heroes.append(hero)

	blackboards = [TeamBlackboard.new(), TeamBlackboard.new()]
	blackboards[0].setup(self, 0)
	blackboards[1].setup(self, 1)

	camera = GameCamera.new()
	camera.arena = self
	# Kamera ei koskaan näytä areenan ulkopuolista tyhjää.
	var map_half: Vector2 = map.size() / 2.0
	camera.limit_left = int(-map_half.x - MapBase.WALL_THICKNESS)
	camera.limit_right = int(map_half.x + MapBase.WALL_THICKNESS)
	camera.limit_top = int(-map_half.y - MapBase.WALL_THICKNESS)
	camera.limit_bottom = int(map_half.y + MapBase.WALL_THICKNESS)
	add_child(camera)

	hud = HudLayer.new()
	hud.setup(self)
	add_child(hud)

	_start_round_intro()


func _make_map() -> MapBase:
	match Game.map_id:
		"moonstone":
			return MapMoon.new()
		"splashport":
			return MapSplash.new()
		_:
			return MapGear.new()


func _make_hero(id: String) -> Hero:
	match id:
		"bastion":
			return Bastion.new()
		"ember":
			return Ember.new()
		"luma":
			return Luma.new()
		"blink":
			return Blink.new()
		"bramble":
			return Bramble.new()
		"quill":
			return Quill.new()
		"boulder":
			return Boulder.new()
		"volt":
			return Volt.new()
		"shade":
			return Shade.new()
		"tide":
			return Tide.new()
		"scout":
			return Scout.new()
		"maestro":
			return Maestro.new()
	return Hero.new()


func _physics_process(delta: float) -> void:
	zones = zones.filter(func(z): return is_instance_valid(z))
	for blackboard in blackboards:
		blackboard.update(delta)

	if state != State.PLAY:
		return

	# Reliikin pisteet
	if relic.carrier != null and is_instance_valid(relic.carrier):
		var carrier := relic.carrier
		var team := carrier.team
		_last_holder_team = team
		if sudden_death:
			_sd_hold += delta
			if _sd_hold >= SUDDEN_DEATH_HOLD:
				_round_over(team)
				return
		else:
			relic_points[team] += delta
		carrier.profile.stats.carry_time += delta
		carrier.profile.add_score(delta * 2.0)
		carrier.add_ult(delta * 3.0)
		if relic_points[team] >= ROUND_TARGET:
			_round_over(team)
			return
	else:
		_sd_hold = 0.0

	if sudden_death:
		_sd_elapsed += delta
		if _sd_elapsed >= SUDDEN_DEATH_MAX:
			var leader := 0 if relic_points[0] >= relic_points[1] else 1
			if _last_holder_team >= 0 and relic_points[0] == relic_points[1]:
				leader = _last_holder_team
			_round_over(leader)
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		if absf(relic_points[0] - relic_points[1]) < 0.5:
			sudden_death = true
			_sd_elapsed = 0.0
			hud.show_banner("RATKAISUHETKI!", "Seuraava reliikin pito voittaa erän", 2.5)
			AudioMgr.play("round_start")
		else:
			_round_over(0 if relic_points[0] > relic_points[1] else 1)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == State.PLAY:
		_toggle_pause()


# --- Erien kulku ---

func _start_round_intro() -> void:
	state = State.INTRO
	relic_points = [0.0, 0.0]
	time_left = ROUND_TIME
	sudden_death = false
	_sd_hold = 0.0
	_sd_elapsed = 0.0
	relic.reset_to_home()
	for hero in heroes:
		hero.reset_for_round()
	_run_intro()


func _run_intro() -> void:
	var wins_needed := Game.rounds_to_win
	hud.show_banner("ERÄ %d" % round_number,
		"Pidä reliikkiä — %d pistettä voittaa erän (voitot: %d/%d – %d/%d)" % [
			int(ROUND_TARGET), Game.blue_rounds, wins_needed, Game.orange_rounds, wins_needed],
		2.2)
	AudioMgr.play("round_start")
	await get_tree().create_timer(2.2).timeout
	for n in [3, 2, 1]:
		if not is_inside_tree():
			return
		hud.show_big_number(str(n))
		AudioMgr.play("count_tick")
		await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	hud.show_big_number("PELIIN!")
	AudioMgr.play("count_go")
	state = State.PLAY


func _round_over(winner_team: int) -> void:
	state = State.ROUND_END
	if winner_team == 0:
		Game.blue_rounds += 1
	else:
		Game.orange_rounds += 1
	for hero in heroes:
		if hero.team == winner_team:
			hero.profile.add_score(50.0)
	relic.drop_from_carrier(false)

	AudioMgr.play("round_win")
	shake(0.4)
	Fx.ring(self, relic.global_position, Palette.glow(Palette.team(winner_team), 1.6), 240.0, 0.8)

	var blue_wins := Game.blue_rounds
	var orange_wins := Game.orange_rounds
	var match_over: bool = blue_wins >= Game.rounds_to_win or orange_wins >= Game.rounds_to_win
	var winner_name := Game.team_name(winner_team)

	if match_over:
		state = State.MATCH_END
		Game.last_winner_team = winner_team
		hud.show_banner("%s VOITTAA OTTELUN!" % winner_name,
			"Erät %d – %d" % [blue_wins, orange_wins], 3.4)
		AudioMgr.play("match_win")
		await get_tree().create_timer(3.5).timeout
		if is_inside_tree():
			Game.match_finished()
	else:
		hud.show_banner("%s VOITTAA ERÄN %d!" % [winner_name, round_number],
			"Erät: sininen %d – %d oranssi" % [blue_wins, orange_wins], 3.0)
		await get_tree().create_timer(3.6).timeout
		if is_inside_tree():
			round_number += 1
			_start_round_intro()


# --- Tapahtumakoukut ---

func on_hero_ko(hero: Hero, source: Hero) -> void:
	if relic.carrier == hero:
		relic.drop_from_carrier(true)
		if source != null and is_instance_valid(source):
			source.profile.stats.carrier_stops += 1
			source.profile.add_score(25.0)
	if source != null and is_instance_valid(source):
		# Pelastus: tyrmäys lähellä hädässä olevaa liittolaista
		for ally in heroes:
			if ally == source or ally.team != source.team:
				continue
			if not is_instance_valid(ally) or not ally.alive:
				continue
			if (ally.carrying or ally.is_threatened()) \
					and ally.global_position.distance_to(hero.global_position) < 340.0:
				source.profile.stats.saves += 1
				source.profile.add_score(20.0)
				break
		hud.ko_feed("%s tyrmäsi %s" % [source.profile.display_name, hero.profile.display_name])
	else:
		hud.ko_feed("%s poistui hetkeksi" % hero.profile.display_name)


func on_hero_respawn(_hero: Hero) -> void:
	pass


func on_relic_taken(hero: Hero) -> void:
	blackboards[hero.team].on_relic_taken(hero)
	blackboards[1 - hero.team].on_enemy_has_relic(hero)


func on_relic_dropped(_hero: Hero) -> void:
	for blackboard in blackboards:
		blackboard.on_relic_free()


# --- Apurit kyvyille, boteille ja HUDille ---

func add_projectile(p: Projectile) -> void:
	add_child(p)


func add_zone(z: Zone) -> void:
	add_child(z)
	zones.append(z)


func heroes_in_circle(pos: Vector2, r: float, team := -1, only_alive := true) -> Array:
	var result: Array = []
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		if only_alive and not hero.alive:
			continue
		if team >= 0 and hero.team != team:
			continue
		if hero.global_position.distance_to(pos) <= r + hero.radius:
			result.append(hero)
	return result


func alive_enemies(team: int) -> Array:
	return heroes.filter(func(h): return is_instance_valid(h) and h.alive and h.team != team)


func alive_allies(team: int) -> Array:
	return heroes.filter(func(h): return is_instance_valid(h) and h.alive and h.team == team)


func team_points(team: int) -> float:
	return relic_points[team]


func popup(pos: Vector2, text: String, color: Color, size := 20) -> void:
	PopupText.spawn(self, pos, text, color, size)


func shake(amount: float) -> void:
	if camera != null:
		camera.add_shake(amount)


func blackboard(team: int) -> TeamBlackboard:
	return blackboards[team]


# --- Pause ---

func _toggle_pause() -> void:
	if _pause_layer != null:
		_pause_layer.queue_free()
		_pause_layer = null
		get_tree().paused = false
		return
	get_tree().paused = true
	_pause_layer = PauseMenuLayer.new(self)
	add_child(_pause_layer)


## Taukovalikko omana kerroksenaan: pysyy aktiivisena pausen aikana,
## jotta Esc/Start sulkee sen (pausattu Arena ei saa syötteitä).
class PauseMenuLayer:
	extends CanvasLayer

	var arena = null

	func _init(p_arena) -> void:
		arena = p_arena
		layer = 90
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _ready() -> void:
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.03, 0.08, 0.72)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)

		var panel := UiKit.panel()
		center.add_child(panel)
		var box := UiKit.vbox(18)
		panel.add_child(box)
		box.add_child(UiKit.title("TAUKO", 54))
		var resume_btn := UiKit.button("Jatka peliä", func(): arena._toggle_pause())
		box.add_child(resume_btn)
		box.add_child(UiKit.button("Päävalikkoon", func():
			get_tree().paused = false
			Game.go_menu()))
		resume_btn.grab_focus()

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			arena._toggle_pause()
