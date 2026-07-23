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
const DRAGON_POINTS := 10.0
const KO_POINTS := 3.0            # vihollisen tyrmäyksestä
const DMG_CAMP_BUFF := 18.0       # vahinkobuffin kesto (s) kaatajan tiimille
const BOSS_BOOST := 45.0          # pomobuffin kesto (s) koko tiimille

var mode := "relic"               # "relic", "koth" tai "jungle"
var score_target := ROUND_TARGET

var critters: Array = []          # viidakko-olennot (neutraali joukkue 2)
var _boss_critter = null
var _boss_timer := BOSS_FIRST
var _boss_spawned_once := false
var _boss_warned := false             # T-3s äänivaroitus ammuttu (kerran)
var _last_point_team := -1

# MOBA-pelimuoto: viidakko yläpuolella + linja alapuolella, minioniaallot,
# tornit ja nexus. Voitto = tuhoa vihollisen nexus (tornit ensin).
const MOBA_TIME := 1200.0         # 20 minuutin 4v4-ottelu
const SIM_MOBA_TIME := 1200.0
const WAVE_INTERVAL := 18.0       # lyhyempi tyhjä jakso edellisen aallon jälkeen
const WAVE_FIRST := 1.5           # ensimmäinen aalto lähtee lähes heti
const WAVE_SIZE := 5              # 3 melee + 2 ranged per linja per joukkue
# Loppupelin työntöapu: 14 min jälkeen joka aalto saa +1 etuvartion. Kolmen
# tornin ketju per linja (aiemmin kaksi) pidensi piirityksiä niin, että ottelut
# päättyivät aikakattoon nexustuhon sijaan — isompi loppuaalto crashaa torneille
# useammin ja vie pelit maaliin.
const LATE_WAVE_TIME := 840.0
const MINION_CAP := 96
# Kristallikello (LoL-inhibiittori käänteisenä): base-tornin kaaduttua murtaja
# saa +1 superminionin per aalto sillä linjalla, kunnes puolustajan kristalli
# nousee tornin paikalle (FIRST_RISE-viive). Elossa oleva kristalli pysäyttää
# superminionit JA toimii linjan base-tornina nexuksen suojaketjussa. Murrettu
# kristalli nousee RESPAWN-ajan kuluttua uudelleen — sykli jatkuu.
# 45 s respawn oli aivan liian nopea: hyökkääjä juoksi kristallilta toiselle
# eikä nexus ehtinyt koskaan auki, ja simissä kaikki matsit venyivät aikakattoon.
const CRYSTAL_FIRST_RISE := 75.0     # superminionit puskevat tämän ajan ennen 1. kristallia
const CRYSTAL_RESPAWN := 180.0       # murskattu kristalli: kunnon hyökkäysikkuna (3 min)
const DRAGON_FIRST := 90.0
const BARON_FIRST := 180.0
const PASSIVE_GOLD_PER_SEC := 1.5
const MINION_REWARD_RADIUS := 850.0
# Last hit on taito joka erottaa pelaajat: viimeistelijä saa kunnon kulta-
# bonuksen JA osuuden XP:tä päälle. Pelkkä läheisyys-XP tasoitti kaikki samalle
# tasokäyrälle, jolloin farmitaito ei muuttunut voimaeroksi (ladder-testi).
const MINION_PROXIMITY_GOLD := 9
const MINION_LAST_HIT_BONUS := 14
const MINION_LAST_HIT_XP_SHARE := 0.35   # osuus minionin xp_valuesta viimeistelijälle
const JUNGLE_XP_ASSIST_RADIUS := 720.0
const JUNGLE_XP_ASSIST_SHARE := 0.35
const MAJOR_XP_ASSIST_SHARE := 0.55
const TOWER_XP_ASSIST_RADIUS := 1050.0
const HERO_KO_XP_BASE := 120.0
# Tappopalkkio: 150 + 12 * uhrin taso kultaa tappajalle; avustajat jakavat
# 40 % palkkiosta (jako hoidetaan Hero._knockoutissa avustuslistan kanssa).
const KO_GOLD_BASE := 150
const RED_CAMP_BUFF := 90.0
const BLUE_CAMP_BUFF := 90.0

var minions: Array = []
var structures: Array = []
var _nexus: Array = [null, null]      # per joukkue
var _towers: Array = [[], []]          # per joukkue
var _lane_towers: Array = [{}, {}]     # team -> lane -> outer/inner/base
var _wave_timer := WAVE_FIRST
var _moba_camp_queue: Array = []
var _moba_camps_active := false
var _crystal_lanes: Dictionary = {}    # "team:lane" -> {team, lane, spot, timer, crystal}
var super_minions_spawned := [0, 0]    # telemetria: superminionit per joukkue
var crystals_broken := [0, 0]          # telemetria: murskatut kristallit per murtajajoukkue
var first_wave_crash_time := -1.0
var _dragon_critter = null
var _dragon_timer := DRAGON_FIRST
var _dragon_spawned_once := false
var _dragon_warned := false
var _moba_audio: MobaAudioDirector = null

# Simulaatiotelemetria (kerätään kun Game.simulating). match_elapsed = pelattu
# aika sekunteina; sim_events = tapahtumaloki aikaleimoineen.
var match_elapsed := 0.0
var sim_events: Array = []
var tower_events: Array = []
var jungle_clear_events: Array = []
var objective_events: Array = []
var _moba_telemetry_accum := 0.0
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
var _buff_warned := false             # T-3s äänivaroitus ammuttu (nollataan joka syklissä)

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


## Keskitetty näkyvyystesti visuaaleille. Tämä ei koskaan pysäytä AI:ta,
## fysiikkaa, vahinkoa tai telemetriaa — se kertoo vain kannattaako kyseisen
## maailman pisteen CanvasItem/FX rakentaa aktiivisille kameroille.
func visual_position_active(world_pos: Vector2, margin := 320.0) -> bool:
	if Game.simulating and not Game.sim_visuals:
		return false
	if split_view != null and split_view.has_method("is_position_visible"):
		return split_view.is_position_visible(world_pos, margin)
	if camera != null and is_instance_valid(camera):
		var vp_size := get_viewport_rect().size
		var zoom: float = maxf(camera.zoom.x, 0.001)
		var half := vp_size / (zoom * 2.0) + Vector2.ONE * margin
		return Rect2(camera.global_position - half, half * 2.0).has_point(world_pos)
	return true


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
			# Simulaatiossa kullakin botilla voi olla oma taso (profile.bot_level)
			# tai suora rank (profile.bot_rank, ladder-testi). Pelaajan ottelussa
			# rank tulee valitusta ranking-tieristä (Game.match_bot_rank).
			var lvl: int = profile.bot_level if profile.bot_level >= 0 else Game.bot_level
			var rk: int = profile.bot_rank
			if rk < 0 and profile.bot_level < 0:
				rk = Game.match_bot_rank()
			controller = BotBrain.new(lvl, rk)
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
		"hush":
			return Hush.new()
		"obsidian":
			return Obsidian.new()
		"lance":
			return Lance.new()
		"salvo":
			return Salvo.new()
		"kaira":
			return Kaira.new()
		"vesper":
			return Vesper.new()
		"myria":
			return Myria.new()
		"torq":
			return Torq.new()
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
	if _buff_timer <= 3.0 and not _buff_warned:
		_buff_warned = true
		if not Game.simulating:
			AudioMgr.play("count_tick", 0.0, -9.0)   # buffiaalto lähestyy
	if _buff_timer <= 0.0:
		_buff_timer = BUFF_INTERVAL
		_buff_warned = false
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
	_boss_warned = false


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


## Pomon ensimmäisen ilmestymisen ajastin + T-3s äänivaroitus (matala pomo­jyrinä),
## jotta joukkueet ehtivät kiertää kiistelemään pelin isoimmasta voimapiikistä.
func _advance_boss_timer(delta: float) -> void:
	if _boss_spawned_once:
		return
	_boss_timer -= delta
	if _boss_timer <= 3.0 and not _boss_warned:
		_boss_warned = true
		if not Game.simulating:
			AudioMgr.play("baron_warning" if mode == "moba" else "dome_up",
				0.03, -3.0 if mode == "moba" else -10.0)
	if _boss_timer <= 0.0:
		_spawn_boss()


func _spawn_boss() -> void:
	var pos: Vector2 = _map_boss_spot()
	var b := Critter.new()
	b.setup_critter(self, Critter.Kind.BOSS, pos)
	add_child(b)
	heroes.append(b)
	critters.append(b)
	_boss_critter = b
	_boss_spawned_once = true
	if mode == "moba":
		hud.show_banner("BARON HERÄÄ!", "Yläviidakon voimakkain tavoite on aktiivinen", 2.4)
	else:
		hud.show_banner("VIIDAKKOPOMO HERÄÄ!",
			"Kaada pomo keskellä — voittaja saa ison boostin", 2.4)
	AudioMgr.play("baron_spawn" if mode == "moba" else "dome_up", 0.03, -2.0)
	Fx.ring(self, pos, Palette.glow(Color("b64ad6"), 1.6), 220.0, 0.9, 9.0)
	shake(0.4)


func _jungle_physics(delta: float) -> void:
	# Pomon ensimmäinen ilmestyminen ajastimella (sen jälkeen se herää itse
	# uudelleen Heron respawn-koneiston kautta).
	_advance_boss_timer(delta)

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
	var clear_time: float = c.clear_duration()
	var active_clear: float = c.active_clear_duration()
	var killer_name := "?"
	if source != null and is_instance_valid(source) and not source.is_unit:
		killer_name = source.hero_id
		var clear_kinds: Dictionary = source.profile.stats.jungle_clear_kinds
		var clear_key := c.telemetry_kind()
		if not clear_kinds.has(clear_key):
			clear_kinds[clear_key] = {"count": 0, "time": 0.0, "active": 0.0}
		var clear_rec: Dictionary = clear_kinds[clear_key]
		clear_rec["count"] += 1
		clear_rec["time"] += clear_time
		clear_rec["active"] += active_clear
		source.profile.stats.jungle_clears += 1
		source.profile.stats.jungle_clear_time += clear_time
		source.profile.stats.jungle_active_clear_time += active_clear
	var clear_event := {
		"t": match_elapsed, "kind": c.telemetry_kind(), "team": team,
		"hero": killer_name, "clear": clear_time, "active": active_clear,
		"gold": c.gold_value, "xp": c.xp_value,
	}
	jungle_clear_events.append(clear_event)
	if source != null and is_instance_valid(source) and not source.is_unit:
		source.profile.stats.gold += c.gold_value
		source.profile.stats.jungle_gold += c.gold_value
		_grant_moba_xp(source, float(c.xp_value), "jungle")
		_record_buff_economy(source, c.gold_value, 0.0)
		_update_economy_milestones(source)
		if source.has_method("on_jungle_camp_defeated"):
			source.on_jungle_camp_defeated(c)
	# Lähellä auttanut support/top saa pienen osuuden eikä menetä koko roam-aikaa.
	# Palkinto ei vähennä junglerin omaa XP:tä; major-objective jakaa enemmän.
	if mode == "moba":
		var assist_share := MAJOR_XP_ASSIST_SHARE if c.is_major_objective() \
			else JUNGLE_XP_ASSIST_SHARE
		for ally in heroes:
			if not is_instance_valid(ally) or not ally.alive or ally.is_unit \
					or ally is Structure or ally == source or ally.team != team:
				continue
			if ally.global_position.distance_to(c.global_position) <= JUNGLE_XP_ASSIST_RADIUS:
				_grant_moba_xp(ally, float(c.xp_value) * assist_share, "jungle", true)
	match c.kind:
		Critter.Kind.DAMAGE_CAMP:
			relic_points[team] += DMG_CAMP_POINTS
			_grant_damage_buff(source)
			popup(critter.global_position + Vector2(0, -90),
				"VAHINKOBUFFI!", Palette.glow(Color("e08a3c"), 1.4), 20)
			hud.ko_feed("%s kaatoi vahinkoleirin (+%d)" % [Game.team_name(team), int(DMG_CAMP_POINTS)])
			AudioMgr.play("blessing", 0.05, -4.0)   # positiivinen vahvistus buffista
		Critter.Kind.POINTS_CAMP:
			relic_points[team] += POINTS_CAMP_POINTS
			_last_point_team = team
			popup(critter.global_position + Vector2(0, -90),
				"+%d PISTETTÄ" % int(POINTS_CAMP_POINTS), Palette.glow(Color("e0c23c"), 1.4), 20)
			hud.ko_feed("%s kaatoi pistereirin (+%d)" % [Game.team_name(team), int(POINTS_CAMP_POINTS)])
			AudioMgr.play("pickup", 0.05, -3.0)   # pistekilahdus
		Critter.Kind.BOSS:
			relic_points[team] += BOSS_POINTS
			_last_point_team = team
			_grant_boss_boost(team)
			objective_events.append({"t": match_elapsed, "kind": "baron", "team": team,
				"hero": killer_name, "duration": BOSS_BOOST, "clear": clear_time,
				"active": active_clear})
			var boss_name := "BARONIN" if mode == "moba" else "POMON"
			hud.show_banner("%s KAATOI %s!" % [Game.team_name(team), boss_name],
				"Iso boosti koko joukkueelle (+%d pistettä)" % int(BOSS_POINTS), 2.8)
			# Baron-kaato on globaali strateginen hetki. Olento itse soittaa
			# positionaalisen romahduksen; tämä cue kertoo palkinnosta koko kartalle.
			if not Game.simulating:
				AudioMgr.duck_music(8.0, 1.15)
			AudioMgr.play("baron_defeat", 0.02, -1.0)
			_sim_event("Pomo kaadettu: %s" % Game.team_name(team))
		Critter.Kind.DRAGON:
			relic_points[team] += DRAGON_POINTS
			_last_point_team = team
			_grant_dragon_boost(team)
			objective_events.append({"t": match_elapsed, "kind": "dragon", "team": team,
				"hero": killer_name, "duration": 35.0, "clear": clear_time,
				"active": active_clear})
			hud.show_banner("%s KAATOI DRAGONIN!" % Game.team_name(team),
				"Liikenopeus ja latausvoima koko joukkueelle", 2.6)
			if not Game.simulating:
				AudioMgr.duck_music(6.0, 0.9)
			AudioMgr.play("dragon_defeat", 0.02, -2.0)
			_sim_event("Dragon kaadettu: %s" % Game.team_name(team))
		Critter.Kind.RED_CAMP:
			_grant_red_buff(source)
			objective_events.append({"t": match_elapsed, "kind": "red", "team": team,
				"hero": killer_name, "duration": RED_CAMP_BUFF, "clear": clear_time,
				"active": active_clear})
			popup(critter.global_position + Vector2(0, -90),
				"RED: VOIMA + HP REGEN", Palette.glow(Color("df4938"), 1.35), 18)
			if not Game.simulating:
				hud.ko_feed("%s otti Red-buffin" % Game.team_name(team))
			AudioMgr.play("red_buff", 0.04, -3.0, critter.global_position)
		Critter.Kind.BLUE_CAMP:
			_grant_blue_buff(source)
			objective_events.append({"t": match_elapsed, "kind": "blue", "team": team,
				"hero": killer_name, "duration": BLUE_CAMP_BUFF, "clear": clear_time,
				"active": active_clear})
			popup(critter.global_position + Vector2(0, -90),
				"BLUE: SPELL POWER + REGEN", Palette.glow(Color("4e8ee8"), 1.35), 18)
			if not Game.simulating:
				hud.ko_feed("%s otti Blue-buffin" % Game.team_name(team))
			AudioMgr.play("blue_buff", 0.04, -3.0, critter.global_position)
		Critter.Kind.SMALL_CAMP:
			if not Game.simulating:
				popup(critter.global_position + Vector2(0, -76),
					"+%dG  +%dXP" % [c.gold_value, c.xp_value], Color("b9d884"), 15)


func on_critter_respawn(critter) -> void:
	var c := critter as Critter
	if c != null and c.kind == Critter.Kind.BOSS:
		hud.show_banner("BARON PALASI!" if mode == "moba" else "VIIDAKKOPOMO PALASI!",
			"Yläviidakon tavoite on taas aktiivinen" if mode == "moba" else "Pomo on taas keskellä", 2.0)
		AudioMgr.play("baron_spawn" if mode == "moba" else "dome_up", 0.03, -4.0)
		Fx.ring(self, critter.global_position, Palette.glow(Color("b64ad6"), 1.5), 200.0, 0.8, 8.0)
	elif c != null and c.kind == Critter.Kind.DRAGON:
		hud.show_banner("DRAGON PALASI!", "Alaviidakon tavoite on taas aktiivinen", 2.0)
		AudioMgr.play("dragon_spawn", 0.03, -5.0)
		Fx.ring(self, critter.global_position, Palette.glow(Color("37cdbb"), 1.5), 190.0, 0.8, 8.0)


## Vahinkobuffi (punainen) kaatajalle ja lähellä oleville liittolaisille.
func _grant_damage_buff(source) -> void:
	if source == null or not is_instance_valid(source):
		return
	source.red_buff = maxf(source.red_buff, DMG_CAMP_BUFF)
	for ally in alive_allies(source.team):
		if ally.global_position.distance_to(source.global_position) < 420.0:
			ally.red_buff = maxf(ally.red_buff, DMG_CAMP_BUFF)


## Pomobuffi: iso ja pitkä boosti koko joukkueelle.
func _grant_red_buff(source) -> void:
	if source == null or not is_instance_valid(source) or source.is_unit:
		return
	source.red_buff = maxf(source.red_buff, RED_CAMP_BUFF)
	source.red_camp_buff = maxf(source.red_camp_buff, RED_CAMP_BUFF)
	source.profile.stats.red_pickups += 1


func _grant_blue_buff(source) -> void:
	if source == null or not is_instance_valid(source) or source.is_unit:
		return
	source.blue_buff = maxf(source.blue_buff, BLUE_CAMP_BUFF)
	source.blue_camp_buff = maxf(source.blue_camp_buff, BLUE_CAMP_BUFF)
	source.profile.stats.blue_pickups += 1


func _grant_boss_boost(team: int) -> void:
	for ally in alive_allies(team):
		ally.red_buff = maxf(ally.red_buff, BOSS_BOOST)
		ally.blue_buff = maxf(ally.blue_buff, BOSS_BOOST)
		ally.baron_buff = maxf(ally.baron_buff, BOSS_BOOST)
		ally.profile.stats.baron_buffs += 1
		# record=false: pomobuffi on neutraali palkinto, ei kirjata kyvyn ansioksi
		# (muuten se kirjautuisi pomon viime hetkellä tappaneen sankarin kyvylle).
		ally.apply_haste(1.2, BOSS_BOOST, false)
		ally.add_shield(60.0, BOSS_BOOST, ally, false)
		Fx.ring(self, ally.global_position, Palette.glow(Palette.GOLD, 1.5), ally.radius + 26.0, 0.6, 6.0)


func _grant_dragon_boost(team: int) -> void:
	for ally in alive_allies(team):
		ally.blue_buff = maxf(ally.blue_buff, 35.0)
		ally.dragon_buff = maxf(ally.dragon_buff, 35.0)
		ally.profile.stats.dragon_buffs += 1
		ally.apply_haste(1.14, 35.0, false)
		ally.add_shield(35.0, 35.0, ally, false)
		Fx.ring(self, ally.global_position, Palette.glow(Color("37cdbb"), 1.5), ally.radius + 22.0, 0.55, 6.0)


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
## (3 tornia per linja + nexus per joukkue). Minioniaallot alkavat myöhemmin.
func _setup_moba() -> void:
	score_target = 999999.0
	relic.koth = true
	relic.visible = false
	var mm := map as MapMoba
	if mm == null:
		return
	# Jungle herää vasta kun ensimmäiset vastakkaiset minioniaallot todella
	# kohtaavat. Näin top/bottom eivät karkaa level 1:llä campeille ja laning
	# määrittää ottelun ensimmäisen rytmin.
	_moba_camp_queue.clear()
	_moba_camps_active = false
	first_wave_crash_time = -1.0
	_crystal_lanes.clear()
	super_minions_spawned = [0, 0]
	crystals_broken = [0, 0]
	for cpos in mm.red_camps():
		_moba_camp_queue.append([Critter.Kind.RED_CAMP, cpos])
	for cpos in mm.blue_camps():
		_moba_camp_queue.append([Critter.Kind.BLUE_CAMP, cpos])
	for cpos in mm.small_camps():
		_moba_camp_queue.append([Critter.Kind.SMALL_CAMP, cpos])
	for cpos in mm.lane_wildlife_spots():
		_moba_camp_queue.append([Critter.Kind.SMALL_CAMP, cpos])
	_boss_timer = BARON_FIRST
	_boss_spawned_once = false
	_boss_warned = false
	_dragon_timer = DRAGON_FIRST
	_dragon_spawned_once = false
	_dragon_warned = false
	# Nexus ja kolme tornia kummallakin linjalla.
	for t in range(2):
		var nx := Structure.new()
		nx.setup_structure(self, Structure.Kind.NEXUS, t, mm.nexus_spot(t))
		add_child(nx)
		heroes.append(nx)
		structures.append(nx)
		_nexus[t] = nx
		for lane_id in mm.lane_ids():
			_lane_towers[t][lane_id] = []
			var spots: Array = mm.tower_spots(t, lane_id)
			for tier in range(spots.size()):
				var tw := Structure.new()
				tw.setup_structure(self, Structure.Kind.TOWER, t, spots[tier], lane_id, tier)
				add_child(tw)
				heroes.append(tw)
				structures.append(tw)
				_towers[t].append(tw)
				_lane_towers[t][lane_id].append(tw)
			_chain_lane_towers(t, lane_id)
	_wave_timer = WAVE_FIRST
	_moba_audio = MobaAudioDirector.new()
	_moba_audio.setup(self, mm)
	add_child(_moba_audio)


## Kytkee joukkueen tornit immuniteettiketjuun: uloin (kauimpana nexuksesta)
## on heti haavoittuva, sisemmät suojattuja kunnes edellinen kaatuu. Pakottaa
## hyökkäysjärjestyksen (uloin -> sisin -> nexus), kuten oikeassa MOBAssa.
func _chain_lane_towers(t: int, lane_id: String) -> void:
	var list: Array = _lane_towers[t].get(lane_id, [])
	for i in range(list.size()):
		var tw := list[i] as Structure
		tw.set_guard(null if i == 0 else list[i - 1])


func _advance_moba_objectives(delta: float) -> void:
	_advance_boss_timer(delta)
	if _dragon_spawned_once:
		return
	_dragon_timer -= delta
	if _dragon_timer <= 3.0 and not _dragon_warned:
		_dragon_warned = true
		if not Game.simulating:
			AudioMgr.play("dragon_warning", 0.03, -4.0)
	if _dragon_timer <= 0.0:
		_spawn_dragon()


func _spawn_dragon() -> void:
	var mm := map as MapMoba
	if mm == null:
		return
	var pos := mm.dragon_spot()
	var d := Critter.new()
	d.setup_critter(self, Critter.Kind.DRAGON, pos)
	add_child(d)
	heroes.append(d)
	critters.append(d)
	_dragon_critter = d
	_dragon_spawned_once = true
	hud.show_banner("DRAGON SAAPUU!", "Alaviidakon objective on nyt vallattavissa", 2.2)
	AudioMgr.play("dragon_spawn", 0.03, -2.0)
	Fx.ring(self, pos, Palette.glow(Color("37cdbb"), 1.6), 205.0, 0.8, 9.0)
	shake(0.3)


func _moba_physics(delta: float) -> void:
	_update_moba_base_rules(delta)
	_tick_moba_economy(delta)
	_tick_moba_telemetry(delta)
	_cleanup_minions()
	_check_first_wave_crash()
	_advance_moba_objectives(delta)
	_tick_crystals(delta)
	# Minioniaallot molemmille joukkueille.
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = WAVE_INTERVAL
		for lane_id in [MapMoba.TOP, MapMoba.BOTTOM]:
			_spawn_wave(0, lane_id)
			_spawn_wave(1, lane_id)
		# Oma pieni sotatorvi rytmittää laning-vaihetta ilman UI-piippausta.
		if not Game.simulating:
			AudioMgr.play("minion_wave", 0.025, -8.0)
	# Varakatto: jos nexusta ei tuhota, ratkaise vähemmän vaurioituneen nexuksen
	# eduksi.
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_end_reason = "aikakatto"
		_end_moba(_moba_leader())


## Aktivoi jungle campit täsmälleen ensimmäisen top- tai bottom-aallon
## kontaktissa. Etäisyys vastaa minionien aggroa, joten kyse on oikeasta
## crashista eikä pelkästä keskiviivan ylityksestä.
func _check_first_wave_crash() -> void:
	if _moba_camps_active or minions.is_empty():
		return
	for lane_id in [MapMoba.TOP, MapMoba.BOTTOM]:
		var blue: Array = []
		var orange: Array = []
		for minion in minions:
			if not is_instance_valid(minion) or not minion.alive or minion.lane_id != lane_id:
				continue
			(blue if minion.team == 0 else orange).append(minion)
		for left in blue:
			for right in orange:
				if left.global_position.distance_squared_to(right.global_position) <= 270.0 * 270.0:
					_activate_moba_camps(lane_id)
					return


func _activate_moba_camps(crash_lane: String) -> void:
	_moba_camps_active = true
	first_wave_crash_time = match_elapsed
	for spec in _moba_camp_queue:
		_spawn_camp(int(spec[0]), spec[1])
	_moba_camp_queue.clear()
	_sim_event("Jungle camps active at first %s wave crash" % crash_lane)
	if hud != null and not Game.simulating:
		hud.show_banner("JUNGLE HERÄÄ", "Ensimmäiset aallot kohtasivat — campit ovat aktiivisia", 1.6)


func _tick_moba_economy(delta: float) -> void:
	for h in heroes:
		if not is_instance_valid(h) or h.is_unit or h is Structure or h.team > 1:
			continue
		if h.profile == null:
			continue
		var income := PASSIVE_GOLD_PER_SEC * delta
		h.profile.stats.gold += income
		h.profile.stats.passive_gold += income
		_record_buff_economy(h, income, 0.0)
		_update_economy_milestones(h)


## Kevyt 2 Hz strateginen näyte. Aikaluokat ovat toisensa poissulkevia, joten
## niiden summasta näkee myös puuttuvan ajan (kuolleena/ottelun introssa).
func _tick_moba_telemetry(delta: float) -> void:
	_moba_telemetry_accum += delta
	if _moba_telemetry_accum < 0.5:
		return
	var sample := _moba_telemetry_accum
	_moba_telemetry_accum = 0.0
	for h in heroes:
		if not is_instance_valid(h) or not h.alive or h.is_unit or h is Structure \
				or h.team > 1 or h.profile == null:
			continue
		var pos: Vector2 = h.global_position
		var mm := map as MapMoba
		if absf(pos.x) >= 2550.0 and absf(pos.y) < 1450.0:
			h.profile.stats.time_base += sample
		elif mm != null and mm.distance_to_lane(pos, MapMoba.TOP) <= 360.0:
			h.profile.stats.time_top += sample
		elif mm != null and mm.distance_to_lane(pos, MapMoba.BOTTOM) <= 360.0:
			h.profile.stats.time_bottom += sample
		else:
			h.profile.stats.time_jungle += sample


## Raportti- ja XP-rooli. Bottomin tuki erotetaan carrysta, jotta duon sisäinen
## eteneminen näkyy eikä kahden eri talouden keskiarvo peitä sitä.
func _progression_role(hero: Hero) -> String:
	if hero == null or not is_instance_valid(hero):
		return "unknown"
	# Nimenomainen positiovalinta (lobby) menee kaiken päättelyn ohi: pelaaja voi
	# pelata mitä tahansa sankaria missä tahansa positiossa (esim. mage-tuki).
	if hero.profile != null:
		match str(hero.profile.moba_position):
			"top":
				return "top"
			"jungle":
				return "jungle"
			"carry":
				return "bottom"
			"support":
				return "support"
	var job := ""
	var duty := ""
	if hero.controller is BotBrain:
		job = str(hero.controller._moba_job)
		duty = str(hero.controller._moba_duty)
	var hero_role := str(HeroDef.get_def(hero.hero_id).get("role", ""))
	if job == "bottom":
		# Botin työnjako (carry/support) ratkaisee ennen sankariroolia.
		if duty == "support":
			return "support"
		if duty == "carry":
			return "bottom"
		if hero_role == "Tuki":
			return "support"
	if job != "":
		return job
	if hero_role == HeroDef.ROLE_JUNGLER:
		return "jungle"
	if hero_role == "Tuki":
		return "support"
	# Ihmispelaajan lane päätellään tähän mennessä kertyneestä alueajasta.
	if hero.profile != null and float(hero.profile.stats.time_top) > \
			float(hero.profile.stats.time_bottom):
		return "top"
	return "bottom"


func _xp_role_multiplier(hero: Hero, source_kind: String, shared: bool) -> float:
	if mode != "moba":
		return 1.0
	var role := _progression_role(hero)
	match source_kind:
		"lane":
			if role == "support":
				return 0.82
			if role == "jungle":
				return 0.70
		"jungle":
			if role == "jungle":
				return 2.25
			if role == "support" and shared:
				return 1.0
			return 0.72
	return 1.0


## Kaikki XP kulkee tämän kautta: roolikerroin, lähdekohtainen telemetria,
## level-up ja talousrajapyykit pysyvät varmasti samassa tahdissa.
func _grant_moba_xp(hero: Hero, raw_amount: float, source_kind: String,
		shared := false) -> float:
	if hero == null or not is_instance_valid(hero) or hero.is_unit \
			or hero.profile == null or raw_amount <= 0.0:
		return 0.0
	var awarded := raw_amount * _xp_role_multiplier(hero, source_kind, shared)
	hero.gain_xp(awarded)
	match source_kind:
		"lane": hero.profile.stats.lane_xp += awarded
		"jungle": hero.profile.stats.jungle_xp += awarded
		"tower": hero.profile.stats.tower_xp += awarded
		"hero": hero.profile.stats.hero_xp += awarded
	_record_buff_economy(hero, 0.0, awarded)
	_update_economy_milestones(hero)
	return awarded


func _record_buff_economy(hero, gold_gain: float, xp_gain: float) -> void:
	if hero == null or not is_instance_valid(hero) or hero.profile == null:
		return
	for entry in [
		["red", hero.red_camp_buff], ["blue", hero.blue_camp_buff],
		["baron", hero.baron_buff], ["dragon", hero.dragon_buff],
	]:
		if float(entry[1]) <= 0.0:
			continue
		hero.profile.stats["gold_during_%s" % str(entry[0])] += gold_gain
		hero.profile.stats["xp_during_%s" % str(entry[0])] += xp_gain


func _update_economy_milestones(hero) -> void:
	if hero == null or not is_instance_valid(hero) or hero.profile == null:
		return
	for threshold in [500, 1000, 2000, 3000]:
		var key := str(threshold)
		if float(hero.profile.stats.gold) >= threshold \
				and not hero.profile.stats.gold_milestones.has(key):
			hero.profile.stats.gold_milestones[key] = match_elapsed
		if float(hero.profile.stats.xp) >= threshold \
				and not hero.profile.stats.xp_milestones.has(key):
			hero.profile.stats.xp_milestones[key] = match_elapsed


func on_minion_ko(minion: Minion, source: Hero) -> void:
	if minion == null:
		return
	var reward_team := 1 - minion.team
	var recipients: Array = []
	for h in heroes:
		if not is_instance_valid(h) or not h.alive or h.is_unit or h is Structure:
			continue
		if h.team == reward_team and h.global_position.distance_to(minion.global_position) <= MINION_REWARD_RADIUS:
			recipients.append(h)
	var valid_last_hit := source != null and is_instance_valid(source) \
		and not source.is_unit and not (source is Structure) and source.team == reward_team
	if valid_last_hit and not recipients.has(source):
		recipients.append(source)
	if recipients.is_empty():
		return
	var share_mult := 1.0 if recipients.size() == 1 else (0.75 if recipients.size() == 2 else 0.60)
	var xp_share: float = float(minion.xp_value) * share_mult
	for h in recipients:
		if h.profile == null:
			continue
		h.profile.stats.gold += MINION_PROXIMITY_GOLD
		h.profile.stats.proximity_gold += MINION_PROXIMITY_GOLD
		_grant_moba_xp(h, xp_share, "lane", recipients.size() > 1)
		_record_buff_economy(h, MINION_PROXIMITY_GOLD, 0.0)
		_update_economy_milestones(h)
	if valid_last_hit and source.profile != null:
		source.profile.stats.gold += MINION_LAST_HIT_BONUS
		source.profile.stats.last_hit_gold += MINION_LAST_HIT_BONUS
		source.profile.stats.minion_kills += 1
		# Viimeistely-XP: farmitaito kertautuu tasoiksi (rankit/statit), eikä
		# pelkkä linjalla seisoskelu riitä samaan tasokäyrään.
		_grant_moba_xp(source, float(minion.xp_value) * MINION_LAST_HIT_XP_SHARE, "lane")
		_record_buff_economy(source, MINION_LAST_HIT_BONUS, 0.0)
		_update_economy_milestones(source)
		if not Game.simulating and source.profile.is_human():
			popup(minion.global_position + Vector2(0, -54),
				"+%dG  LAST HIT" % (MINION_PROXIMITY_GOLD + MINION_LAST_HIT_BONUS),
				Palette.GOLD, 14)


func _update_moba_base_rules(_delta: float) -> void:
	var mm := map as MapMoba
	if mm == null:
		return
	for h in heroes:
		if not is_instance_valid(h) or not h.alive or h.team > 1 or h is Structure:
			continue
		var corrected: Vector2 = mm.enforce_base_boundaries(
			h.global_position, h.team, h.radius, h.velocity)
		if corrected != h.global_position:
			h.global_position = corrected
			h.velocity = Vector2.ZERO
			h.kb_velocity = Vector2.ZERO
		if h.is_unit or not mm.is_in_own_sanctuary(h.global_position, h.team):
			continue
		# Fountain on oikea respawn-turva: haavoittumaton alue. Nopea HP- ja
		# resurssipalautus tapahtuu Hero._fountain_regenissä (lähderegen), jossa
		# on myös visuaalinen tikki — täällä pidetään vain suojaruudut yllä.
		h.iframes = maxf(h.iframes, 0.16)


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
func _spawn_wave(team: int, lane_id: String = MapMoba.BOTTOM) -> void:
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
	var path: Array = mm.lane_path(lane_id)
	if team == 1:
		path = path.duplicate()
		path.reverse()
	var base: Vector2 = path[0] if not path.is_empty() else Vector2.ZERO
	# Hajota minionit linjaa pitkin KOHTI KESKUSTAA (etelä on nyt eteläseinä).
	# Näin ne eivät synny nexuksen päälle eivätkä seinän sisään.
	var lead: Vector2 = Vector2.RIGHT
	if path.size() > 1:
		var p1: Vector2 = path[1]
		if p1 != base:
			lead = (p1 - base).normalized()
	var side: Vector2 = lead.orthogonal()
	# Loppupelissä (LATE_WAVE_TIME) aalto kasvaa yhdellä etuvartiolla: piiritys-
	# paine nousee ja base-tornit murtuvat ennen aikakattoa (ks. vakion selitys).
	var wave_size := WAVE_SIZE
	var melee_count := 3
	if match_elapsed >= LATE_WAVE_TIME:
		wave_size += 1
		melee_count += 1
	for i in range(wave_size):
		var m := Minion.new()
		# Kilpisoturit muodostavat oikean etulinjan, kaksi sädevahtia jää
		# taakse. Viiden(+1) yksikön aalto on uhka, jota ei voi vain sivuuttaa.
		var m_kind := Minion.Kind.MELEE if i < melee_count else Minion.Kind.RANGED
		var rank_i := i if m_kind == Minion.Kind.MELEE else i - melee_count
		var forward_offset := (182.0 + float(rank_i % 2) * 28.0) \
			if m_kind == Minion.Kind.MELEE else (105.0 + float(rank_i) * 28.0)
		var side_offset := (-34.0 + float(rank_i) * 34.0) \
			if m_kind == Minion.Kind.MELEE else (-24.0 + float(rank_i) * 48.0)
		var offset: Vector2 = lead * forward_offset + side * side_offset
		m.setup_minion(self, team, base + offset, path, lane_id, m_kind)
		add_child(m)
		heroes.append(m)
		minions.append(m)
	# Superminioni: kun vihollisen base-torni tällä linjalla on murrettu eikä
	# suojaava kristalli seiso, joka aalto saa yhden kruunatun kärkiyksikön.
	if _lane_super_active(team, lane_id):
		var sm := Minion.new()
		sm.setup_minion(self, team, base + lead * 60.0, path, lane_id, Minion.Kind.SUPER)
		add_child(sm)
		heroes.append(sm)
		minions.append(sm)
		super_minions_spawned[team] += 1


## Rakennus tuhottu: torni avaa nexuksen kun molemmat kaatuneet; nexus = voitto.
func on_structure_destroyed(structure, source) -> void:
	var s := structure as Structure
	if s == null:
		return
	if s.kind == Structure.Kind.TOWER:
		_towers[s.team].erase(s)
		var attacker_team := 1 - s.team
		if source != null and is_instance_valid(source) and source.team <= 1:
			attacker_team = source.team
		var killer_name := "minion/other"
		if source != null and is_instance_valid(source) and not source.is_unit:
			killer_name = source.hero_id
		tower_events.append({
			"t": match_elapsed, "lost_team": s.team, "attacker_team": attacker_team,
			"lane": s.lane_id, "tier": s.lane_tier + 1, "hero": killer_name,
			"baron": _team_has_active_buff(attacker_team, "baron"),
			"dragon": _team_has_active_buff(attacker_team, "dragon"),
		})
		if source != null and is_instance_valid(source) and not source.is_unit:
			source.profile.stats.gold += s.gold_value
			source.profile.stats.tower_gold += s.gold_value
			_record_buff_economy(source, s.gold_value, 0.0)
			_update_economy_milestones(source)
		# Tornin XP palkitsee myös lähellä piirityksessä olleet. Viimeistelijä saa
		# täyden osuuden; muut 55 %, eikä minionin viimeinen osuma kadota palkintoa.
		for ally in heroes:
			if not is_instance_valid(ally) or not ally.alive or ally.is_unit \
					or ally is Structure or ally.team != attacker_team:
				continue
			if ally.global_position.distance_to(s.global_position) > TOWER_XP_ASSIST_RADIUS:
				continue
			var tower_share := 1.0 if ally == source else 0.55
			_grant_moba_xp(ally, float(s.xp_value) * tower_share, "tower", ally != source)
		popup(structure.global_position + Vector2(0, -90), "TORNI TUHOTTU!",
			Palette.glow(Palette.team(1 - s.team), 1.4), 20)
		hud.ko_feed("%s menetti %s-linjan tornin" % [Game.team_name(s.team), s.lane_id])
		_sim_event("%s %s T%d kaatui (%d jäljellä)" % [Game.team_name(s.team),
			s.lane_id, s.lane_tier + 1, _towers[s.team].size()])
		# Uloomman tornin kaaduttua sen suojaama sisätorni avautuu (ei enää immuuni).
		for other in _towers[s.team]:
			var ot := other as Structure
			if ot != null and ot._guard == s:
				popup(ot.global_position + Vector2(0, -90), "TORNI AVATTU",
					Palette.glow(Palette.team(1 - s.team), 1.3), 18)
		if s.lane_tier == 2:
			hud.show_banner("%s BASE-TORNI KAATUI!" % s.lane_id.to_upper(),
				"%s saa superminioneja — kristalli nousee suojaksi %d s kuluttua" % [
					Game.team_name(attacker_team), int(CRYSTAL_FIRST_RISE)], 2.4)
			# Käynnistä kristallisykli: viiveen jälkeen puolustajan kristalli nousee
			# tornin paikalle ja pysäyttää superminionit + suojaa nexuksen.
			_crystal_lanes["%d:%s" % [s.team, s.lane_id]] = {
				"team": s.team, "lane": s.lane_id,
				"spot": s.global_position, "timer": CRYSTAL_FIRST_RISE, "crystal": null,
			}
		_refresh_nexus_protection(s.team)
	elif s.kind == Structure.Kind.CRYSTAL:
		var attacker_team := 1 - s.team
		if source != null and is_instance_valid(source) and source.team <= 1:
			attacker_team = source.team
		crystals_broken[attacker_team] += 1
		if source != null and is_instance_valid(source) and not source.is_unit:
			source.profile.stats.gold += s.gold_value
			source.profile.stats.tower_gold += s.gold_value
			_grant_moba_xp(source, float(s.xp_value), "tower")
			_record_buff_economy(source, s.gold_value, 0.0)
			_update_economy_milestones(source)
		# Sykli jatkuu: sama solmu kierrätetään respawnissa 45 s kuluttua.
		var entry_v = _crystal_lanes.get("%d:%s" % [s.team, s.lane_id])
		if entry_v != null:
			var entry: Dictionary = entry_v
			entry["crystal"] = s
			entry["timer"] = CRYSTAL_RESPAWN
		popup(s.global_position + Vector2(0, -90), "KRISTALLI MURSKATTU!",
			Palette.glow(Palette.team(attacker_team), 1.4), 20)
		hud.show_banner("%s KRISTALLI MURSKATTU!" % s.lane_id.to_upper(),
			"Superminionit jatkavat — kristalli nousee uudelleen %d s kuluttua" % int(CRYSTAL_RESPAWN), 2.2)
		hud.ko_feed("%s menetti %s-kristallin" % [Game.team_name(s.team), s.lane_id])
		_sim_event("%s %s kristalli murskattu" % [Game.team_name(s.team), s.lane_id])
		_refresh_nexus_protection(s.team)
	else:
		_end_reason = "nexus tuhottu"
		_sim_event("%s nexus tuhottu" % Game.team_name(s.team))
		_end_moba(1 - s.team)


func _team_has_active_buff(team: int, kind: String) -> bool:
	for h in heroes:
		if not is_instance_valid(h) or h.is_unit or h is Structure or h.team != team:
			continue
		if kind == "baron" and h.baron_buff > 0.0:
			return true
		if kind == "dragon" and h.dragon_buff > 0.0:
			return true
	return false


## Nexuksen suojaehto: molempien linjojen base-tornit murrettu EIKÄ yhtään
## elossa olevaa kristallia kummallakaan linjalla (kristalli toimii linjan
## base-tornina suojaketjussa).
func _base_turrets_destroyed(team: int) -> bool:
	for lane_id in [MapMoba.TOP, MapMoba.BOTTOM]:
		var lane_list: Array = _lane_towers[team].get(lane_id, [])
		if lane_list.size() < 3:
			return false
		var base_tower := lane_list[2] as Structure
		if base_tower != null and is_instance_valid(base_tower) and base_tower.alive:
			return false
		if _lane_crystal(team, lane_id) != null:
			return false
	return true


## Kristallisyklien eteneminen: kun linjan kristalli on murrettu (tai sitä ei
## ole vielä noussut), ajastin laskee ja nollassa kristalli nousee (uudelleen).
func _tick_crystals(delta: float) -> void:
	for key in _crystal_lanes:
		var entry: Dictionary = _crystal_lanes[key]
		var cs := entry.get("crystal") as Structure
		if cs != null and is_instance_valid(cs) and cs.alive:
			continue
		entry["timer"] = float(entry["timer"]) - delta
		if entry["timer"] <= 0.0:
			_spawn_crystal(entry)


## Nostaa (tai herättää) puolustajan kristallin base-tornin paikalle: pysäyttää
## superminionit sillä linjalla ja palauttaa nexuksen suojaketjuun.
func _spawn_crystal(entry: Dictionary) -> void:
	var team: int = int(entry["team"])
	var lane: String = str(entry["lane"])
	var spot: Vector2 = entry["spot"]
	var cs := entry.get("crystal") as Structure
	if cs != null and is_instance_valid(cs):
		cs.reset_for_round()   # kierrätä sama solmu: täysi HP, törmäys, fysiikka
	else:
		cs = Structure.new()
		cs.setup_structure(self, Structure.Kind.CRYSTAL, team, spot, lane, 2)
		add_child(cs)
		heroes.append(cs)
		structures.append(cs)
		entry["crystal"] = cs
	entry["timer"] = CRYSTAL_RESPAWN
	_refresh_nexus_protection(team)
	popup(spot + Vector2(0, -90), "KRISTALLI SUOJAA NEXUSTA — TUHOA SE",
		Palette.glow(Palette.team(team), 1.35), 18)
	hud.show_banner("%s KRISTALLI NOUSI!" % lane.to_upper(),
		"Kristalli suojaa %s nexusta ja pysäyttää superminionit — tuhoa se" % Game.team_name(team), 2.4)
	hud.ko_feed("%s sai %s-kristallin suojakseen" % [Game.team_name(team), lane])
	if not Game.simulating:
		AudioMgr.play("tower_guard", 0.03, -4.0, spot)
	Fx.ring(self, spot, Palette.glow(Palette.team(team), 1.5), 150.0, 0.8, 7.0)
	_sim_event("%s %s kristalli nousi" % [Game.team_name(team), lane])


## Linjan elossa oleva kristalli (tai null).
func _lane_crystal(team: int, lane_id: String) -> Structure:
	var entry_v = _crystal_lanes.get("%d:%s" % [team, lane_id])
	if entry_v == null:
		return null
	var cs := (entry_v as Dictionary).get("crystal") as Structure
	if cs != null and is_instance_valid(cs) and cs.alive:
		return cs
	return null


## Saako joukkue superminionin tälle linjalle? Kyllä, jos vihollisen base-torni
## linjalla on murrettu EIKÄ suojaava kristalli seiso pystyssä.
func _lane_super_active(team: int, lane_id: String) -> bool:
	var foe := 1 - team
	var lane_list: Array = _lane_towers[foe].get(lane_id, [])
	if lane_list.size() < 3:
		return false
	var base_tower := lane_list[2] as Structure
	if base_tower != null and is_instance_valid(base_tower) and base_tower.alive:
		return false
	return _lane_crystal(foe, lane_id) == null


## Nexuksen suojaketju yhdestä paikasta: nexus on haavoittuva vain kun molempien
## linjojen base-tornit on murrettu EIKÄ yhtään kristallia seiso. Kristallin
## nousu palauttaa suojan (ja laserin); murtuminen avaa nexuksen uudelleen.
func _refresh_nexus_protection(team: int) -> void:
	var nx := _nexus[team] as Structure
	if nx == null or not is_instance_valid(nx) or not nx.alive:
		return
	var was_protected: bool = nx.is_protected()
	var open := _base_turrets_destroyed(team)
	nx.set_protected(not open)
	if open and was_protected:
		hud.show_banner("NEXUS AVOINNA!",
			"%s nexus on nyt haavoittuvainen" % Game.team_name(team), 2.6)
		# Uhkaava oma Nexus-cue kuuluu aina ja musiikki siirtyy loppupeliin.
		AudioMgr.play("nexus_exposed", 0.02, -1.0)
		if not Game.simulating:
			AudioMgr.duck_music(7.0, 0.9)    # musiikki dippaa iskun alta
			AudioMgr.play_music("battle4")   # raju huipennus loppupeliin
		_sim_event("%s nexus avattu" % Game.team_name(team))
	elif not open and not was_protected:
		hud.show_banner("NEXUS SUOJATTU",
			"Kristalli suojaa %s nexusta — tuhoa se ensin" % Game.team_name(team), 2.2)
		_sim_event("%s nexus suojattu (kristalli)" % Game.team_name(team))


## Aikakaton ratkaisu ilman sokeaa sinisen suosintaa. Järjestys:
##  1) suurempi oma nexus-hp, 2) enemmän vihollistorneja kaadettu,
##  3) enemmän pisteitä (leirit/pomo), 4) enemmän tienattua kultaa
##  (CS + tapot + objektiivit = "pelasi paremmin"), 5) enemmän tappoja.
## Aito tasapeli on tämän jälkeen käytännössä mahdoton — pelkkä tornilaskuri
## teki tasaväkisistä aikakattopeleistä kolikonheittoa ladder-testissä.
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
	var g0 := _team_stat_sum(0, "gold")
	var g1 := _team_stat_sum(1, "gold")
	if absf(g0 - g1) > 5.0:
		return 0 if g0 > g1 else 1
	var k0 := _team_stat_sum(0, "kos")
	var k1 := _team_stat_sum(1, "kos")
	if absf(k0 - k1) > 0.5:
		return 0 if k0 > k1 else 1
	return -1   # aito tasapeli


## Joukkueen sankarien statin summa (ei yksiköitä/rakenteita).
func _team_stat_sum(team: int, key: String) -> float:
	var total := 0.0
	for h in heroes:
		var hero := h as Hero
		if hero == null or not is_instance_valid(hero) or hero.is_unit \
				or hero is Structure or hero.team != team or hero.profile == null:
			continue
		total += float(hero.profile.stats.get(key, 0))
	return total


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
		var ai_level: int = -1
		var moba_role := "unknown"
		if h.controller != null and h.controller.is_bot():
			ai_level = int(h.controller.level)
			if h.controller is BotBrain:
				moba_role = str(h.controller._moba_job)
		var hd := {
			"hero_id": h.hero_id, "team": h.team,
			"level": h.level, "ai_level": ai_level,
			"role": moba_role,
			"progression_role": _progression_role(h),
			"human": h.profile.is_human(),
			"kos": int(p.stats.kos), "deaths": int(p.stats.deaths),
			"assists": int(p.stats.assists), "damage": float(p.stats.damage),
			"taken": float(p.stats.taken),
			"taken_hero": float(p.stats.taken_hero),
			"taken_tower": float(p.stats.taken_tower),
			"taken_minion": float(p.stats.taken_minion),
			"taken_neutral": float(p.stats.taken_neutral),
			"deaths_tower": int(p.stats.deaths_tower),
			"deaths_neutral": int(p.stats.deaths_neutral),
			"cc_suffered": float(p.stats.cc_suffered),
			"time_dead": float(p.stats.time_dead),
			"structure_damage": float(p.stats.structure_damage),
			"jungle_damage": float(p.stats.jungle_damage),
			"mitigated": float(p.stats.prevented),
			"minion_kills": int(p.stats.minion_kills), "healing": float(p.stats.healing),
			"gold": float(p.stats.gold), "xp": float(p.stats.xp),
			"passive_gold": float(p.stats.passive_gold),
			"proximity_gold": int(p.stats.proximity_gold),
			"last_hit_gold": int(p.stats.last_hit_gold),
			"jungle_gold": int(p.stats.jungle_gold),
			"jungle_xp": int(p.stats.jungle_xp),
			"lane_xp": float(p.stats.lane_xp),
			"tower_gold": int(p.stats.tower_gold),
			"tower_xp": int(p.stats.tower_xp),
			"hero_xp": float(p.stats.hero_xp),
			"gold_spent": int(p.stats.get("gold_spent", 0)),
			"items": h.items.duplicate(),
			"gold_milestones": p.stats.gold_milestones.duplicate(true),
			"xp_milestones": p.stats.xp_milestones.duplicate(true),
			"level_times": p.stats.level_times.duplicate(true),
			"jungle_clear_kinds": p.stats.jungle_clear_kinds.duplicate(true),
			"slots": p.stats.slots.duplicate(true),
		}
		for key in [
			"time_top", "time_bottom", "time_jungle", "time_base",
			"jungle_clears", "jungle_clear_time", "jungle_active_clear_time",
			"kill_gold", "assist_gold_earned",
			"red_pickups", "blue_pickups", "baron_buffs", "dragon_buffs",
			"red_buff_time", "blue_buff_time", "baron_buff_time", "dragon_buff_time",
			"red_bonus_damage", "blue_bonus_damage", "red_healing",
			"damage_during_red", "damage_during_blue", "damage_during_baron", "damage_during_dragon",
			"structure_during_red", "structure_during_blue", "structure_during_baron", "structure_during_dragon",
			"kos_during_red", "kos_during_blue", "kos_during_baron", "kos_during_dragon",
			"gold_during_red", "gold_during_blue", "gold_during_baron", "gold_during_dragon",
			"xp_during_red", "xp_during_blue", "xp_during_baron", "xp_during_dragon",
		]:
			hd[key] = p.stats.get(key, 0.0)
		heroes_data.append(hd)
	return {
		"elapsed": match_elapsed, "winner": Game.last_winner_team,
		"reason": _end_reason, "events": sim_events,
		"first_wave_crash": first_wave_crash_time,
		"tower_events": tower_events,
		"jungle_clear_events": jungle_clear_events,
		"objective_events": objective_events,
		"super_minions": super_minions_spawned.duplicate(),
		"crystals_broken": crystals_broken.duplicate(),
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
	_buff_warned = false
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
	hud.show_banner("ETERNAL DIVIDE" if mode == "moba" else "ERÄ %d" % round_number,
		objective, 2.2)
	AudioMgr.play("moba_start" if mode == "moba" else "round_start")
	await get_tree().create_timer(2.2).timeout
	for n in [3, 2, 1]:
		if not is_inside_tree():
			return
		hud.show_big_number(str(n))
		AudioMgr.play("count_tick", 0.0)   # tasainen pitch -> vakaa metronomi
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
	if mode == "moba" and source != null and is_instance_valid(source) \
			and not source.is_unit and source.team <= 1 and source.team != hero.team:
		var ko_xp := HERO_KO_XP_BASE + float(maxi(hero.level - 1, 0)) * 12.0
		_grant_moba_xp(source, ko_xp, "hero")
		# Tappopalkkio: kulta tappajalle (avustajien osuus jaetaan Herossa).
		var bounty: int = KO_GOLD_BASE + 12 * hero.level
		source.profile.stats.gold += bounty
		source.profile.stats.kill_gold = int(source.profile.stats.kill_gold) + bounty
		_record_buff_economy(source, float(bounty), 0.0)
		_update_economy_milestones(source)
		if not Game.simulating and source.profile.is_human():
			popup(hero.global_position + Vector2(0, -70), "+%dG" % bounty,
				Palette.GOLD, 18)
		for ally in heroes:
			if not is_instance_valid(ally) or not ally.alive or ally.is_unit \
					or ally is Structure or ally == source or ally.team != source.team:
				continue
			if ally.global_position.distance_to(hero.global_position) <= 760.0:
				_grant_moba_xp(ally, ko_xp * 0.45, "hero", true)
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
			hud.show_banner("ENSIVERI!",
				"%s avasi tyrmäystilin" % source.profile.display_name, 1.8)
			if not Game.simulating:
				AudioMgr.play("crescendo", 0.05, -5.0)
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
	if Game.simulating and not Game.sim_visuals:
		return
	PopupText.spawn(self, pos, text, color, size)


func shake(amount: float) -> void:
	if Game.simulating and not Game.sim_visuals:
		return
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
	# Jaetussa näytössä areena elää SubViewportissa (jonka container ei välitä
	# hiiri-/UI-syötettä), joten taukovalikko lisätään PÄÄRUUDULLE (SplitView).
	# Muuten areenaan. Näin hiiri ja ohjain pääsevät nappeihin.
	var host = split_view if split_view != null else self
	host.add_child(_pause_layer)


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
		AudioMgr.play("ui_open")
		var dim := ColorRect.new()
		dim.color = Color(0.008, 0.025, 0.028, 0.86)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)

		var panel := UiKit.panel()
		panel.custom_minimum_size = Vector2(620, 440)
		center.add_child(panel)
		var box := UiKit.vbox(18)
		panel.add_child(box)
		box.add_child(UiKit.title("OTTELU TAUOLLA", 54))
		var format := UiKit.label("ETERNAL DIVIDE  •  4V4 MOBA", 22, Palette.GOLD)
		format.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(format)
		var objective := UiKit.dim_label(
			"MURRA MOLEMMAT LINJAT  •  TUHOA BASE-TORNIT  •  KAADA NEXUS", 16)
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(objective)
		box.add_child(UiKit.spacer(12))
		var resume_btn := UiKit.button("▶  JATKA OTTELUA", func(): arena._toggle_pause())
		resume_btn.custom_minimum_size = Vector2(500, 58)
		box.add_child(resume_btn)
		var menu_btn := UiKit.button("POISTU PÄÄVALIKKOON", func():
			get_tree().paused = false
			Game.go_menu())
		menu_btn.custom_minimum_size = Vector2(500, 52)
		box.add_child(menu_btn)
		box.add_child(UiKit.spacer(8))
		var controls := UiKit.dim_label(
			"PS5  •  R2 PERUSHYÖKKÄYS  •  R1 / L1 KYVYT  •  L2 ULT  •  OPTIONS JATKA", 15)
		controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(controls)
		resume_btn.grab_focus()

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			arena._toggle_pause()
