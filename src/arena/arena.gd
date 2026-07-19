class_name Arena
extends Node2D
## Otteluruutu: rakentaa kentän, sankarit, reliikin, kameran ja HUDin,
## sekä pyörittää erät alusta loppuun (intro -> peli -> erän loppu -> tulokset).

enum State { INTRO, PLAY, ROUND_END, MATCH_END }

const ROUND_TARGET := 40.0        # sekuntia reliikin hallussapitoa
const ROUND_TIME := 150.0
const SUDDEN_DEATH_HOLD := 1.5
const SUDDEN_DEATH_MAX := 45.0

# Lumipallo­efektin torjunta: jäljessä oleva joukkue kerää pisteitä nopeammin,
# ja liian kauan yhtäjaksoisesti hallussa pidetty reliikki alkaa polttaa
# kantajaansa -> pakottaa vaihtoja eikä johtoa voi vain lukita.
const COMEBACK_MAX := 0.85        # jäljessä oleva kerää enintään +85 % nopeammin
const HEAT_GRACE := 6.0           # armonaika ennen kuin reliikki alkaa polttaa
const HEAT_TICK := 0.7            # kirousvahingon väli sekunteina
const HEAT_BASE := 6.0            # kirouksen perusvahinko per tick
const HEAT_RAMP := 1.6            # lisävahinko per sekunti armonajan jälkeen

# Ydinvalta-pelimuoto
const KOTH_TARGET := 60.0         # sekuntia ydinalueen hallintaa
const KOTH_RADIUS := 175.0
const KOTH_RELOCATE := 20.0       # kuinka usein ydin siirtyy

# Viidakko-pelimuoto: 5 min ottelu, eniten pisteitä voittaa. Pisteitä saa
# viidakko-olennoista (leirit, pomo) ja vihollisten tyrmäämisestä.
const JUNGLE_TIME := 300.0        # ottelun kesto sekunteina (5 min)
const BOSS_FIRST := 60.0          # pomon ensimmäinen ilmestyminen (s pelin alusta)
const DMG_CAMP_POINTS := 2.0      # sivuleirin kaadosta
const POINTS_CAMP_POINTS := 8.0   # pistereirin kaadosta
const BOSS_POINTS := 14.0         # pomon kaadosta
const KO_POINTS := 3.0            # vihollisen tyrmäyksestä
const DMG_CAMP_BUFF := 18.0       # vahinkobuffin kesto (s) kaatajan tiimille
const BOSS_BOOST := 45.0          # pomobuffin kesto (s) koko tiimille

var mode := "relic"               # "relic", "koth" tai "jungle"
var score_target := ROUND_TARGET

var critters: Array = []          # viidakko-olennot (neutraali joukkue 2)
var _boss_critter = null
var _boss_timer := BOSS_FIRST
var _boss_spawned_once := false
var _last_point_team := -1

# MOBA-pelimuoto: viidakko yläpuolella + linja alapuolella, minioniaallot,
# tornit ja nexus. Voitto = tuhoa vihollisen nexus (tornit ensin).
const MOBA_TIME := 1500.0         # varakatto (s) jos nexusta ei tuhota (25 min)
const SIM_MOBA_TIME := 480.0      # simulaation lyhyempi varakatto (8 min)
const WAVE_INTERVAL := 24.0       # minioniaallon väli
const WAVE_FIRST := 10.0          # ensimmäinen aalto pelin alusta
const WAVE_SIZE := 4              # minionia per aalto per joukkue
const MINION_CAP := 40            # yhtäaikaisten minionien katto (suorituskyky)

var minions: Array = []
var structures: Array = []
var _nexus: Array = [null, null]      # per joukkue
var _towers: Array = [[], []]          # per joukkue
var _wave_timer := WAVE_FIRST

# Simulaatiotelemetria (kerätään kun Game.simulating). match_elapsed = pelattu
# aika sekunteina; sim_events = tapahtumaloki aikaleimoineen.
var match_elapsed := 0.0
var sim_events: Array = []
var _end_reason := ""
var _first_blood := false

# Kykytelemetrian aktiivikonteksti: kuka/mikä kykypaikka juuri aiheuttaa
# vahinkoa/CC:tä/parannusta. Hero._act asettaa, kohteen apply_*/heal_hp lukevat.
var _act_hero = null
var _act_slot := ""

var state: int = State.INTRO
var round_number := 1
var time_left := ROUND_TIME
var relic_points := [0.0, 0.0]
var sudden_death := false

var _koth_relocate_timer := 0.0
var _koth_spots: Array = []

# Kenttäbuffit (blue/red) ovat harvinainen power spike -työkalu: niitä tulee
# harvoin, ja HUD näyttää laskurin seuraavaan aaltoon.
const BUFF_INTERVAL := 70.0
const BUFF_FIRST := 40.0
var _buff_timer := BUFF_FIRST

var map: MapBase = null
var relic: Relic = null
var camera: GameCamera = null
var hud = null                    # HudLayer
var heroes: Array = []
var zones: Array = []
var buffs: Array = []              # aktiiviset FieldBuffit (botit lukevat näitä)
var blackboards: Array = []

var _sd_hold := 0.0
var _sd_elapsed := 0.0
var _last_holder_team := -1
var _pause_layer: CanvasLayer = null

# Jaettu ruutu: kun SplitView isännöi areenaa, se luo kamerat ja HUDin itse
# (areena ei tee omaa GameCameraa/HUDia). Tärinä reititetään sinne.
var hosted := false
var split_view = null

# Reliikin "kuumeneminen": kuinka kauan sama joukkue on pitänyt yhtäjaksoisesti.
var _hold_streak_team := -1
var _hold_streak := 0.0
var _heat_tick := 0.0
var _heat_warned := false


func _ready() -> void:
	map = _make_map()
	add_child(map)

	relic = Relic.new()
	relic.setup(self, map.relic_home())
	add_child(relic)

	mode = Game.mode_id
	if mode == "koth":
		_setup_koth()

	for profile in Game.roster:
		var hero := _make_hero(profile.hero_id)
		var controller
		if profile.is_bot:
			# Simulaatiossa kullakin botilla voi olla oma taso (profile.bot_level).
			var lvl: int = profile.bot_level if profile.bot_level >= 0 else Game.bot_level
			controller = BotBrain.new(lvl)
		else:
			controller = DeviceInput.new(profile.device)
		hero.setup(self, profile, controller)
		hero.global_position = map.spawn_point(profile.team, profile.index)
		add_child(hero)
		heroes.append(hero)

	# Viidakko-olennot (leirit) luodaan pelaajien jälkeen, jotta heroes[0]
	# pysyy pelaajana. Pomo ilmestyy myöhemmin ajastimella.
	if mode == "jungle":
		_setup_jungle()
	elif mode == "moba":
		_setup_moba()

	blackboards = [TeamBlackboard.new(), TeamBlackboard.new()]
	blackboards[0].setup(self, 0)
	blackboards[1].setup(self, 1)

	# Jaetussa ruudussa SplitView luo kamerat ja HUDin. Muuten oma GameCamera.
	if not hosted:
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
	elif split_view != null:
		split_view.on_arena_ready()

	_start_round_intro()


func _make_map() -> MapBase:
	# Viidakko- ja MOBA-pelimuodot käyttävät omia isoja karttojaan.
	if Game.mode_id == "moba":
		return MapMoba.new()
	if Game.mode_id == "jungle":
		return MapJungle.new()
	match Game.map_id:
		"moonstone":
			return MapMoon.new()
		"splashport":
			return MapSplash.new()
		"sparkring":
			return MapSpark.new()
		"dustcanyon":
			return MapDust.new()
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
		"prism":
			return Prism.new()
		"rift":
			return Rift.new()
		"titan":
			return Titan.new()
	return Hero.new()


func _physics_process(delta: float) -> void:
	zones = zones.filter(func(z): return is_instance_valid(z))
	buffs = buffs.filter(func(b): return is_instance_valid(b))
	for blackboard in blackboards:
		blackboard.update(delta)

	if state != State.PLAY:
		return
	match_elapsed += delta

	# Viidakko- ja MOBA-pelimuodoilla on oma logiikkansa (ei reliikkiä/buffeja).
	if mode == "jungle":
		_jungle_physics(delta)
		return
	if mode == "moba":
		_moba_physics(delta)
		return

	# Kenttäbuffit ilmestyvät reliikki- ja ydinvaltapeleissä.
	_buff_timer -= delta
	if _buff_timer <= 0.0:
		_buff_timer = BUFF_INTERVAL
		_spawn_buff_wave()

	if mode == "koth":
		_koth_physics(delta)
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
			# Takaa-ajobonus: jäljessä oleva joukkue kerää nopeammin.
			relic_points[team] += _comeback_gain(team, delta)
			_apply_carrier_heat(carrier, team, delta)
		carrier.profile.stats.carry_time += delta
		carrier.profile.add_score(delta * 2.0)
		carrier.add_ult(delta * 3.0)
		if relic_points[team] >= ROUND_TARGET:
			_round_over(team)
			return
	else:
		_sd_hold = 0.0
		_cool_hold_streak(delta)

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
			AudioMgr.play("round_start", 0.05, -5.0)
		else:
			_round_over(0 if relic_points[0] > relic_points[1] else 1)


# --- Ydinvalta-pelimuoto ---

func _setup_koth() -> void:
	score_target = KOTH_TARGET
	relic.koth = true
	relic.zone_radius = KOTH_RADIUS
	relic.z_index = -2
	var half: Vector2 = map.size() / 2.0
	_koth_spots = [
		Vector2.ZERO,
		Vector2(-half.x * 0.45, -half.y * 0.4),
		Vector2(half.x * 0.45, -half.y * 0.4),
		Vector2(-half.x * 0.45, half.y * 0.4),
		Vector2(half.x * 0.45, half.y * 0.4),
	]
	for i in range(_koth_spots.size()):
		_koth_spots[i] = map.clamp_to_field(_koth_spots[i], KOTH_RADIUS + 40.0)
	relic.global_position = _koth_spots[0]
	_koth_relocate_timer = KOTH_RELOCATE


## Kumpi joukkue hallitsee ydinaluetta: enemmistö alueella olevista sankareista
## hallitsee. Tasapeli (myös 0–0) on kiistelty -> -1, kukaan ei kerää pisteitä.
func _koth_control() -> int:
	var core: Vector2 = relic.global_position
	var blue: int = heroes_in_circle(core, KOTH_RADIUS, 0).size()
	var orange: int = heroes_in_circle(core, KOTH_RADIUS, 1).size()
	if blue > orange:
		return 0
	if orange > blue:
		return 1
	return -1


func _koth_physics(delta: float) -> void:
	var holder := _koth_control()
	relic.control_team = holder
	if holder >= 0:
		_last_holder_team = holder
		for hero in heroes_in_circle(relic.global_position, KOTH_RADIUS, holder):
			hero.profile.stats.carry_time += delta
			hero.profile.add_score(delta * 1.5)
			hero.add_ult(delta * 2.0)

	if sudden_death:
		if holder >= 0:
			_sd_hold += delta
			if _sd_hold >= SUDDEN_DEATH_HOLD:
				_round_over(holder)
				return
		else:
			_sd_hold = 0.0
		_sd_elapsed += delta
		if _sd_elapsed >= SUDDEN_DEATH_MAX:
			var leader := 0 if relic_points[0] >= relic_points[1] else 1
			if _last_holder_team >= 0 and relic_points[0] == relic_points[1]:
				leader = _last_holder_team
			_round_over(leader)
		return

	if holder >= 0:
		relic_points[holder] += _comeback_gain(holder, delta)
		if relic_points[holder] >= score_target:
			_round_over(holder)
			return
	else:
		_sd_hold = 0.0

	_koth_relocate_timer -= delta
	if _koth_relocate_timer <= 0.0:
		_koth_relocate()

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		if absf(relic_points[0] - relic_points[1]) < 0.5:
			sudden_death = true
			_sd_elapsed = 0.0
			hud.show_banner("RATKAISUHETKI!", "Seuraava ytimen valtaus voittaa erän", 2.5)
			AudioMgr.play("round_start", 0.05, -5.0)
		else:
			_round_over(0 if relic_points[0] > relic_points[1] else 1)


func _koth_relocate() -> void:
	_koth_relocate_timer = KOTH_RELOCATE
	if _koth_spots.is_empty():
		return
	var current: Vector2 = relic.global_position
	var choice: Vector2 = current
	for _try in range(6):
		var spot: Vector2 = _koth_spots[randi() % _koth_spots.size()]
		if spot.distance_to(current) > 60.0:
			choice = spot
			break
	relic.global_position = choice
	relic.control_team = -1
	if hud != null:
		hud.show_banner("YDIN SIIRTYY", "Valtaa uusi ydinalue", 1.6)
	AudioMgr.play("round_start", 0.05, -7.0)
	Fx.ring(self, choice, Palette.glow(Palette.GOLD, 1.5), KOTH_RADIUS, 0.8, 6.0)


# --- Viidakko-pelimuoto ---

## Luo sivuvahinkoleirit ja pistereirin. Pomo ilmestyy myöhemmin ajastimella.
func _setup_jungle() -> void:
	score_target = 999999.0        # ei pisteraja-voittoa; aika ratkaisee
	# Reliikki ei ole käytössä viidakossa: piilota ja estä poiminta. Jätetään
	# keskelle (0,0), jottei GameCamera venytä näkymää sen sijaintiin.
	relic.koth = true
	relic.visible = false
	var jm := map as MapJungle
	if jm == null:
		return
	for cpos in jm.damage_camps():
		_spawn_camp(Critter.Kind.DAMAGE_CAMP, cpos)
	_spawn_camp(Critter.Kind.POINTS_CAMP, jm.points_camp())
	_boss_timer = BOSS_FIRST
	_boss_spawned_once = false


func _spawn_camp(kind: int, pos: Vector2) -> void:
	var c := Critter.new()
	c.setup_critter(self, kind, pos)
	add_child(c)
	heroes.append(c)
	critters.append(c)


func _map_boss_spot() -> Vector2:
	var jm := map as MapJungle
	if jm != null:
		return jm.boss_spot()
	var mm := map as MapMoba
	if mm != null:
		return mm.boss_spot()
	return Vector2.ZERO


func _spawn_boss() -> void:
	var pos: Vector2 = _map_boss_spot()
	var b := Critter.new()
	b.setup_critter(self, Critter.Kind.BOSS, pos)
	add_child(b)
	heroes.append(b)
	critters.append(b)
	_boss_critter = b
	_boss_spawned_once = true
	hud.show_banner("VIIDAKKOPOMO HERÄÄ!",
		"Kaada pomo keskellä — voittaja saa ison boostin", 2.4)
	AudioMgr.play("dome_up", 0.05, -3.0)
	Fx.ring(self, pos, Palette.glow(Color("b64ad6"), 1.6), 220.0, 0.9, 9.0)
	shake(0.4)


func _jungle_physics(delta: float) -> void:
	# Pomon ensimmäinen ilmestyminen ajastimella (sen jälkeen se herää itse
	# uudelleen Heron respawn-koneiston kautta).
	if not _boss_spawned_once:
		_boss_timer -= delta
		if _boss_timer <= 0.0:
			_spawn_boss()

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_end_jungle()


## Viidakko-olennon kaato: palkitse kaatajan joukkue tyypin mukaan.
func on_critter_ko(critter, source) -> void:
	var team := -1
	if source != null and is_instance_valid(source) and source.team <= 1:
		team = source.team
	var c := critter as Critter
	if c == null:
		return
	if team < 0:
		return   # ympäristön/olennon tappama -> ei palkintoa
	match c.kind:
		Critter.Kind.DAMAGE_CAMP:
			relic_points[team] += DMG_CAMP_POINTS
			_grant_damage_buff(source)
			popup(critter.global_position + Vector2(0, -90),
				"VAHINKOBUFFI!", Palette.glow(Color("e08a3c"), 1.4), 20)
			hud.ko_feed("%s kaatoi vahinkoleirin (+%d)" % [Game.team_name(team), int(DMG_CAMP_POINTS)])
		Critter.Kind.POINTS_CAMP:
			relic_points[team] += POINTS_CAMP_POINTS
			_last_point_team = team
			popup(critter.global_position + Vector2(0, -90),
				"+%d PISTETTÄ" % int(POINTS_CAMP_POINTS), Palette.glow(Color("e0c23c"), 1.4), 20)
			hud.ko_feed("%s kaatoi pistereirin (+%d)" % [Game.team_name(team), int(POINTS_CAMP_POINTS)])
		Critter.Kind.BOSS:
			relic_points[team] += BOSS_POINTS
			_last_point_team = team
			_grant_boss_boost(team)
			hud.show_banner("%s KAATOI POMON!" % Game.team_name(team),
				"Iso boosti koko joukkueelle (+%d pistettä)" % int(BOSS_POINTS), 2.8)
			# Pomon kaato: raskas möräys, ei voittosointi (ottelu jatkuu).
			AudioMgr.play("quake", 0.05, -1.0)
			AudioMgr.play("inferno", 0.05, -6.0)
			_sim_event("Pomo kaadettu: %s" % Game.team_name(team))


func on_critter_respawn(critter) -> void:
	var c := critter as Critter
	if c != null and c.kind == Critter.Kind.BOSS:
		hud.show_banner("VIIDAKKOPOMO PALASI!", "Pomo on taas keskellä", 2.0)
		AudioMgr.play("dome_up", 0.05, -5.0)
		Fx.ring(self, critter.global_position, Palette.glow(Color("b64ad6"), 1.5), 200.0, 0.8, 8.0)


## Vahinkobuffi (punainen) kaatajalle ja lähellä oleville liittolaisille.
func _grant_damage_buff(source) -> void:
	if source == null or not is_instance_valid(source):
		return
	source.red_buff = maxf(source.red_buff, DMG_CAMP_BUFF)
	for ally in alive_allies(source.team):
		if ally.global_position.distance_to(source.global_position) < 420.0:
			ally.red_buff = maxf(ally.red_buff, DMG_CAMP_BUFF)


## Pomobuffi: iso ja pitkä boosti koko joukkueelle.
func _grant_boss_boost(team: int) -> void:
	for ally in alive_allies(team):
		ally.red_buff = maxf(ally.red_buff, BOSS_BOOST)
		ally.blue_buff = maxf(ally.blue_buff, BOSS_BOOST)
		ally.apply_haste(1.2, BOSS_BOOST)
		ally.add_shield(60.0, BOSS_BOOST, ally)
		Fx.ring(self, ally.global_position, Palette.glow(Palette.GOLD, 1.5), ally.radius + 26.0, 0.6, 6.0)


## Aika loppui: eniten pisteitä voittaa ottelun (viidakko on yksieräinen).
func _end_jungle() -> void:
	var winner := 0
	if relic_points[1] > relic_points[0]:
		winner = 1
	elif relic_points[0] == relic_points[1] and _last_point_team >= 0:
		winner = _last_point_team
	state = State.MATCH_END
	Game.last_winner_team = winner
	if winner == 0:
		Game.blue_rounds = 1
	else:
		Game.orange_rounds = 1
	for hero in heroes:
		if hero.team == winner:
			hero.profile.add_score(50.0)
	AudioMgr.play("match_win", 0.05, -6.0)
	shake(0.5)
	hud.show_banner("%s VOITTAA VIIDAKON!" % Game.team_name(winner),
		"Pisteet  %d – %d" % [int(relic_points[0]), int(relic_points[1])], 3.4)
	await get_tree().create_timer(3.6).timeout
	if is_inside_tree():
		Game.match_finished()


# --- MOBA-pelimuoto ---

## Luo viidakon (leirit + pomo ajastimella) sekä linjan rakennukset
## (2 tornia + nexus per joukkue). Minioniaallot alkavat myöhemmin.
func _setup_moba() -> void:
	score_target = 999999.0
	relic.koth = true
	relic.visible = false
	var mm := map as MapMoba
	if mm == null:
		return
	# Viidakko yläpuolella.
	for cpos in mm.damage_camps():
		_spawn_camp(Critter.Kind.DAMAGE_CAMP, cpos)
	_spawn_camp(Critter.Kind.POINTS_CAMP, mm.points_camp())
	_boss_timer = BOSS_FIRST
	_boss_spawned_once = false
	# Rakennukset: nexus + 2 tornia per joukkue.
	for t in range(2):
		var nx := Structure.new()
		nx.setup_structure(self, Structure.Kind.NEXUS, t, mm.nexus_spot(t))
		add_child(nx)
		heroes.append(nx)
		structures.append(nx)
		_nexus[t] = nx
		for tpos in mm.tower_spots(t):
			var tw := Structure.new()
			tw.setup_structure(self, Structure.Kind.TOWER, t, tpos)
			add_child(tw)
			heroes.append(tw)
			structures.append(tw)
			_towers[t].append(tw)
	_wave_timer = WAVE_FIRST


func _moba_physics(delta: float) -> void:
	_cleanup_minions()
	# Viidakon pomo ajastimella (kuten jungle-moodissa).
	if not _boss_spawned_once:
		_boss_timer -= delta
		if _boss_timer <= 0.0:
			_spawn_boss()
	# Minioniaallot molemmille joukkueille.
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = WAVE_INTERVAL
		_spawn_wave(0)
		_spawn_wave(1)
		# Hienovarainen vihjeääni uudesta aallosta (rytmittää peliä).
		if not Game.simulating:
			AudioMgr.play("drop", 0.1, -12.0)
	# Varakatto: jos nexusta ei tuhota, ratkaise vähemmän vaurioituneen nexuksen
	# eduksi.
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_end_reason = "aikakatto"
		_end_moba(_moba_leader())


## Poistaa kaatuneet minionit heroes-listasta ja vapauttaa ne (turvallisesti,
## areenan omassa vaiheessa ennen taistelulogiikkaa).
func _cleanup_minions() -> void:
	if minions.is_empty():
		return
	var live: Array = []
	for m in minions:
		if not is_instance_valid(m):
			continue
		if m.alive:
			live.append(m)
		else:
			heroes.erase(m)
			m.queue_free()
	minions = live


## Yksi minioniaalto: WAVE_SIZE minionia tukikohdasta linjaa pitkin. Sininen
## kulkee reittiä eteenpäin, oranssi käänteisesti.
func _spawn_wave(team: int) -> void:
	# Katto per joukkue (ei jaettu), ettei aikaisemmin luotu joukkue nälkiinnytä
	# toista lähellä kattoa. Kumpikin saa enintään puolet globaalista katosta.
	var team_count := 0
	for m in minions:
		if is_instance_valid(m) and m.alive and m.team == team:
			team_count += 1
	if team_count >= MINION_CAP / 2:
		return
	var mm := map as MapMoba
	if mm == null:
		return
	var path: Array = mm.lane_path()
	if team == 1:
		path = path.duplicate()
		path.reverse()
	var base: Vector2 = path[0] if not path.is_empty() else Vector2.ZERO
	for i in range(WAVE_SIZE):
		var m := Minion.new()
		var offset := Vector2(0.0, 8.0 + i * 26.0)   # etelään, ei nexuksen alustan päälle
		m.setup_minion(self, team, base + offset, path)
		add_child(m)
		heroes.append(m)
		minions.append(m)


## Rakennus tuhottu: torni avaa nexuksen kun molemmat kaatuneet; nexus = voitto.
func on_structure_destroyed(structure, source) -> void:
	var s := structure as Structure
	if s == null:
		return
	if s.kind == Structure.Kind.TOWER:
		_towers[s.team].erase(s)
		popup(structure.global_position + Vector2(0, -90), "TORNI TUHOTTU!",
			Palette.glow(Palette.team(1 - s.team), 1.4), 20)
		hud.ko_feed("%s menetti tornin" % Game.team_name(s.team))
		_sim_event("%s torni kaatui (%d jäljellä)" % [Game.team_name(s.team), _towers[s.team].size()])
		if _towers[s.team].is_empty():
			var nx := _nexus[s.team] as Structure
			if nx != null and is_instance_valid(nx):
				nx.set_vulnerable()
			hud.show_banner("NEXUS AVOINNA!",
				"%s nexus on nyt haavoittuvainen" % Game.team_name(s.team), 2.6)
			AudioMgr.play("dome_up", 0.05, -3.0)
			_sim_event("%s nexus avattu" % Game.team_name(s.team))
	else:
		_end_reason = "nexus tuhottu"
		_sim_event("%s nexus tuhottu" % Game.team_name(s.team))
		_end_moba(1 - s.team)


## Aikakaton ratkaisu ilman sokeaa sinisen suosintaa. Järjestys:
##  1) suurempi oma nexus-hp, 2) enemmän vihollistorneja kaadettu,
##  3) enemmän pisteitä (leirit/pomo), muuten aito tasapeli (-1).
func _moba_leader() -> int:
	var h0: float = _nexus_hp(0)
	var h1: float = _nexus_hp(1)
	if absf(h0 - h1) > 1.0:
		return 0 if h0 > h1 else 1
	var orange_towers: int = _towers[1].size()   # jäljellä -> sininen kaatanut vähemmän
	var blue_towers: int = _towers[0].size()
	if orange_towers != blue_towers:
		return 0 if orange_towers < blue_towers else 1
	var p0: float = relic_points[0]
	var p1: float = relic_points[1]
	if absf(p0 - p1) > 0.5:
		return 0 if p0 > p1 else 1
	return -1   # aito tasapeli


func _nexus_hp(team: int) -> float:
	var nx := _nexus[team] as Structure
	if nx != null and is_instance_valid(nx) and nx.alive:
		return nx.hp
	return 0.0


func nexus_fraction(team: int) -> float:
	var nx := _nexus[team] as Structure
	if nx != null and is_instance_valid(nx) and nx.alive:
		return clampf(nx.hp / nx.max_hp, 0.0, 1.0)
	return 0.0


func nexus_hp_int(team: int) -> int:
	return int(_nexus_hp(team))


func _end_moba(winner: int) -> void:
	if state == State.MATCH_END:
		return   # estä kaksinkertainen päättyminen samalla fysiikkaruudulla
	var by_nexus: bool = _end_reason == "nexus tuhottu"
	state = State.MATCH_END
	Game.last_winner_team = winner
	if winner == 0:
		Game.blue_rounds = 1
	elif winner == 1:
		Game.orange_rounds = 1
	# winner < 0 -> tasapeli: ei kierrosvoittoa kummallekaan.
	if winner >= 0:
		for hero in heroes:
			if hero.team == winner and not hero.is_unit:
				hero.profile.add_score(80.0)
	if _end_reason == "":
		_end_reason = "nexus"
	if winner < 0:
		_end_reason = "tasapeli (aikakatto)"
	var who: String = "TASAPELI" if winner < 0 else "%s VOITTAA" % Game.team_name(winner)
	_sim_event("%s (%s)" % [who, _end_reason])
	AudioMgr.play("match_win", 0.05, -6.0)
	shake(0.6)
	var title: String
	var sub: String
	if winner < 0:
		title = "TASAPELI!"
		sub = "Aikakatto — nexukset tasan"
	elif by_nexus:
		title = "%s TUHOSI NEXUKSEN!" % Game.team_name(winner)
		sub = "Voitto!"
	else:
		title = "%s JOHTAA!" % Game.team_name(winner)
		sub = "Aikakatto ratkaisi ottelun"
	hud.show_banner(title, sub, 3.4)
	if Game.simulating:
		# Ottelu päättyi kesken fysiikkaruudun (kutsuttu take_damagesta) ->
		# lykätään arenan vaihto turvallisesti ruudun ulkopuolelle.
		Game.call_deferred("match_finished")
		return
	await get_tree().create_timer(3.6).timeout
	if is_inside_tree():
		Game.match_finished()


## Telemetria: kirjaa tapahtuma aikaleiman kanssa (sekä simulaatiossa että
## pelaajien otteluissa, jotta raportin voi tuottaa molemmista).
func _sim_event(text: String) -> void:
	sim_events.append({"t": match_elapsed, "text": text})


## Ottelun tilannekuva simulaatioraporttiin (kutsutaan ennen seuraavaa ottelua).
func sim_snapshot() -> Dictionary:
	var heroes_data: Array = []
	for h in heroes:
		if not is_instance_valid(h) or h.is_unit:
			continue
		var p: PlayerProfile = h.profile
		var lvl: int = -1
		if h.controller != null and h.controller.is_bot():
			lvl = int(h.controller.level)
		heroes_data.append({
			"hero_id": h.hero_id, "team": h.team, "level": lvl,
			"human": h.profile.is_human(),
			"kos": int(p.stats.kos), "deaths": int(p.stats.deaths),
			"assists": int(p.stats.assists), "damage": float(p.stats.damage),
			"taken": float(p.stats.taken),
			"structure_damage": float(p.stats.structure_damage),
			"jungle_damage": float(p.stats.jungle_damage),
			"mitigated": float(p.stats.prevented),
			"minion_kills": int(p.stats.minion_kills), "healing": float(p.stats.healing),
			"slots": p.stats.slots.duplicate(true),
		})
	return {
		"elapsed": match_elapsed, "winner": Game.last_winner_team,
		"reason": _end_reason, "events": sim_events,
		"heroes": heroes_data,
	}


func holder_team() -> int:
	if mode == "koth":
		return relic.control_team
	if relic.carrier != null and is_instance_valid(relic.carrier):
		return relic.carrier.team
	return -1


# --- Lumipallo­efektin torjunta ---

## Pistekertymä takaa-ajobonuksella: mitä enemmän joukkue on jäljessä, sitä
## nopeammin se kerää pisteitä pitäessään. Johtava joukkue kerää normaalisti.
func _comeback_gain(team: int, base: float) -> float:
	var behind: float = relic_points[1 - team] - relic_points[team]
	if behind <= 0.0:
		return base
	return base * (1.0 + minf(behind / score_target, 1.0) * COMEBACK_MAX)


## Reliikin kuumeneminen: kun sama joukkue pitää yhtäjaksoisesti liian kauan,
## reliikki alkaa polttaa kantajaansa kiihtyvällä vahingolla -> pakottaa
## vaihtoja. Kantajan vaihto omassa joukkueessa ei nollaa (koko joukkueen
## hallussapito ratkaisee), vain reliikin menetys viholliselle/vapaaksi.
func _apply_carrier_heat(carrier: Hero, team: int, delta: float) -> void:
	if team != _hold_streak_team:
		_hold_streak_team = team
		_hold_streak = 0.0
		_heat_tick = 0.0
		_heat_warned = false
	_hold_streak += delta
	if _hold_streak < HEAT_GRACE:
		return
	if not _heat_warned:
		_heat_warned = true
		popup(carrier.global_position + Vector2(0, -100), "RELIIKKI POLTTAA!", Palette.BAD, 18)
		if hud != null:
			hud.show_banner("RELIIKKI POLTTAA",
				"Liian pitkä yhtäjaksoinen pito vahingoittaa kantajaa — vaihtakaa hallintaa", 2.0)
		AudioMgr.play("fire", 0.05, -2.0)
	_heat_tick -= delta
	if _heat_tick > 0.0:
		return
	_heat_tick = HEAT_TICK
	var dmg: float = HEAT_BASE + (_hold_streak - HEAT_GRACE) * HEAT_RAMP
	carrier.take_damage(dmg, null)
	if is_instance_valid(carrier) and carrier.alive:
		Fx.ring(self, carrier.global_position, Palette.glow(Palette.BAD, 1.3),
			carrier.radius + 8.0, 0.28, 3.0)


## Kun reliikki on vapaana, hallussapito­putki jäähtyy vähitellen (lyhyt pudotus
## ei nollaa täysin, mutta pidempi vapaana­olo palauttaa reliikin viileäksi).
func _cool_hold_streak(delta: float) -> void:
	_hold_streak = maxf(_hold_streak - delta * 1.5, 0.0)
	if _hold_streak <= 0.0:
		_hold_streak_team = -1
		_heat_warned = false


# --- Kenttäbuffit ---

func _spawn_buff_wave() -> void:
	var half: Vector2 = map.size() / 2.0
	var bx := half.x * 0.42
	var by := half.y * 0.5
	# Kummallekin tiimille oma blue ja red, peilatusti -> tasapuolinen.
	_spawn_buff("blue", 0, map.clamp_to_field(Vector2(-bx, -by), 80.0))
	_spawn_buff("red", 0, map.clamp_to_field(Vector2(-bx, by), 80.0))
	_spawn_buff("blue", 1, map.clamp_to_field(Vector2(bx, -by), 80.0))
	_spawn_buff("red", 1, map.clamp_to_field(Vector2(bx, by), 80.0))
	if hud != null:
		hud.show_banner("BUFFIT ILMESTYIVÄT", "Murskaa oman tiimisi buffi napataksesi sen", 1.8)
	AudioMgr.play("ult_ready", 0.05, -5.0)


func _spawn_buff(type: String, team: int, pos: Vector2) -> void:
	var buff := FieldBuff.new()
	buff.setup(self, type, team, pos)
	add_child(buff)
	buffs.append(buff)


## Aika seuraavaan buffiaaltoon sekunneissa (HUD-laskuri). -1 = ei näytetä.
func next_buff_in() -> float:
	if state != State.PLAY or mode == "jungle" or mode == "moba":
		return -1.0   # viidakossa/MOBAssa ei ole kenttäbuffeja -> ei laskuria
	return maxf(_buff_timer, 0.0)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == State.PLAY:
		_toggle_pause()


# --- Erien kulku ---

func _start_round_intro() -> void:
	state = State.INTRO
	relic_points = [0.0, 0.0]
	if mode == "moba":
		# Simulaatiossa lyhyempi varakatto ettei pattitilanne veny (ottelut
		# päättyvät yleensä nexuksen tuhoon jo paljon ennen tätä).
		time_left = SIM_MOBA_TIME if Game.simulating else MOBA_TIME
	elif mode == "jungle":
		time_left = JUNGLE_TIME
	else:
		time_left = ROUND_TIME
	sudden_death = false
	_sd_hold = 0.0
	_sd_elapsed = 0.0
	_hold_streak_team = -1
	_hold_streak = 0.0
	_heat_tick = 0.0
	_heat_warned = false
	_buff_timer = BUFF_FIRST
	for child in get_children():
		if child is FieldBuff:
			child.queue_free()
	buffs.clear()
	relic.reset_to_home()
	if mode == "koth":
		relic.control_team = -1
		relic.global_position = _koth_spots[0] if not _koth_spots.is_empty() else Vector2.ZERO
		_koth_relocate_timer = KOTH_RELOCATE
	for hero in heroes:
		hero.reset_for_round()
	_run_intro()


func _run_intro() -> void:
	# Uusi taistelubiisi joka erälle -> vaihtelua erien välillä.
	AudioMgr.play_music_pool("battle")
	# Simulaatiossa ohitetaan lähtölaskenta ja mennään suoraan peliin.
	if Game.simulating:
		state = State.PLAY
		return
	var wins_needed := Game.rounds_to_win
	var objective := ""
	if mode == "moba":
		objective = "Tuhoa vihollisen nexus! Kaada tornit, työnnä minioneilla ja hallitse viidakkoa."
	elif mode == "jungle":
		objective = "Kerää eniten pisteitä 5 minuutissa — kaada leirejä, keskustan pomo ja vihollisia"
	elif mode == "koth":
		objective = "Hallitse ydinaluetta — %d s hallintaa voittaa erän (voitot: %d/%d – %d/%d)" % [
			int(KOTH_TARGET), Game.blue_rounds, wins_needed, Game.orange_rounds, wins_needed]
	else:
		objective = "Pidä reliikkiä — %d pistettä voittaa erän (voitot: %d/%d – %d/%d)" % [
			int(ROUND_TARGET), Game.blue_rounds, wins_needed, Game.orange_rounds, wins_needed]
	hud.show_banner("ERÄ %d" % round_number, objective, 2.2)
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
	AudioMgr.play("count_go", 0.05, -4.0)
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

	AudioMgr.play("round_win", 0.05, -4.0)
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
		AudioMgr.play("match_win", 0.05, -6.0)
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
	# Viidakko: vihollisen tyrmäys tuo joukkueelle pisteitä.
	if mode == "jungle" and source != null and is_instance_valid(source) \
			and source.team <= 1 and source.team != hero.team:
		relic_points[source.team] += KO_POINTS
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
		if not _first_blood:
			_first_blood = true
			_sim_event("Ensiveri: %s (%s) tyrmäsi %s (%s)" % [
				Game.team_name(source.team), source.hero_id,
				Game.team_name(hero.team), hero.hero_id])
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


func heroes_in_circle(pos: Vector2, r: float, team := -1, only_alive := true,
		exclude_units := false) -> Array:
	var result: Array = []
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		if only_alive and not hero.alive:
			continue
		if exclude_units and hero.is_unit:
			continue
		if team >= 0 and hero.team != team:
			continue
		if hero.global_position.distance_to(pos) <= r + hero.radius:
			result.append(hero)
	return result


func alive_enemies(team: int) -> Array:
	return heroes.filter(func(h): return is_instance_valid(h) and h.alive and h.team != team)


## Vain oikeat vihollissankarit (ei yksiköitä) — botin uhka-arvioon ja
## keskitettyyn tuleen, jottei minioneja/rakennuksia lasketa vihollispelaajiksi.
func enemy_heroes(team: int) -> Array:
	return heroes.filter(func(h): return is_instance_valid(h) and h.alive \
		and h.team != team and not h.is_unit)


func alive_allies(team: int) -> Array:
	# Vain oikeat sankarit (ei olentoja/minioneja/rakennuksia) — muodostelma- ja
	# tukilogiikka koskee pelaajia, ei yksiköitä.
	return heroes.filter(func(h): return is_instance_valid(h) and h.alive \
		and h.team == team and not h.is_unit)


func team_points(team: int) -> float:
	return relic_points[team]


func popup(pos: Vector2, text: String, color: Color, size := 20) -> void:
	PopupText.spawn(self, pos, text, color, size)


func shake(amount: float) -> void:
	if camera != null:
		camera.add_shake(amount)
	if split_view != null:
		split_view.add_shake(amount)


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
