class_name BotBrain
extends RefCounted
## Botin aivot. Toteuttaa saman rajapinnan kuin DeviceInput, joten Hero ei
## erota bottia ihmisestä. Päätökset perustuvat sankarin ROOLIIN, joukkueen
## jaettuun TeamBlackboard-tilannekuvaan ja utility-arviointiin.
##
## Roolit ohjaavat käytöstä:
##   Tankki   — johtaa rintamaa, peelaa suojeltavan edestä
##   Tuki     — pysyy suojeltavan takana, parantaa ja buffaa, välttää etulinjaa
##   Assassin — kiertää takalinjaan, iskee heikoimpia, vetäytyy ajoissa
##   Fighter  — lähitaistelu keskietäisyydeltä, kestävä
##   Mage     — keskietäisyys, alueenhallinta
##   Ranger   — pitää etäisyyttä ja kitettää
##
## Vaikeustaso EI muuta vahinkoa tai kestoa — vain reaktioaikaa,
## tähtäysvirhettä, ennakointia, väistämistä ja kykyjen käyttötodennäköisyyttä.

enum Mode { GET_RELIC, ATTACK_CARRIER, ESCORT, CARRY, RETREAT, FIGHT, SUPPORT, GET_BUFF }

const BACKLINE_ROLES := ["Tuki", "Ranger", "Mage"]

var level := 1

# Vaikeustasoparametrit
var reaction := 0.28
var aim_error_deg := 9.0
var decision_interval := 0.4
var dodge_chance := 0.35
var ability_chance := 0.6
var ult_chance := 0.9
var prediction := 0.5
var aggression := 1.0           # kuinka suuren osan ajasta botti oikeasti hyökkää
var buff_focus := 0.5           # kuinka innokkaasti/kaukaa botti hakee buffeja
var buff_deny := 0.0            # kuinka herkästi botti rikkoo vihollisen buffin
var focus_fire := 0.0           # kuinka hyvin botti keskittää tulen joukkueen kohteeseen
var patience := 0.0             # assassiinin kärsivällisyys (odottaa hyvää avausta)
var self_preserve := 0.0        # kuinka herkästi botti pakenee kyvyillä vaarassa
var jungle_focus := 0.0         # kuinka aktiivisesti botti tunnistaa ja farmaa viidakon leirit/pomon
var farm_skill := 0.0           # linjafarmi: korkea taso hakee matalan HP:n last hitit
var combo_skill := 0.0          # muistaako avaajan kohteen ja käyttääkö oikean jatkokyvyn
var cooldown_discipline := 0.0  # säästääkö liikkuvuutta/pakoa ja välttääkö tuplakastit
var tower_judgement := 0.0      # kuinka tarkasti botti arvioi aallon, aggron ja poistumistien

# Taso 6 (epäreilu) huijaa: nämä poikkeavat 1.0:sta vain kyseisellä tasolla.
# Hero lukee kertoimet setup()issa ja soveltaa niitä.
var damage_mult := 1.0          # aiheutettu vahinko
var damage_taken_mult := 1.0    # otettu vahinko
var cooldown_mult := 1.0        # jäähdytysten kerroin
var ult_gain_mult := 1.0        # ultin latautuminen
var speed_mult := 1.0           # liikkumisnopeus

# Roolikohtaiset (asetetaan ensimmäisellä päivityksellä)
var _role := ""
var _pref_range := 300.0
var _basic_range := 420.0
var _is_tank := false
var _is_support := false
var _is_assassin := false
var _is_ranged := false
var _is_jungler_role := false
var _moba_job := ""
var _moba_lane := ""
var _moba_goal := Vector2.INF
var _lane_returning := false      # laner ajautui liian kauas omalta kaareltaan

var _hero: Hero = null
var _mode: int = Mode.FIGHT
var _target: Hero = null
var _buff_target = null          # tavoiteltu FieldBuff (GET_BUFF-tilassa)
var _jungle_target: Hero = null  # tavoiteltu viidakko-olento (leiri/pomo)
var _defend_pos := Vector2.INF   # MOBA: uhatun oman rakennuksen sijainti (jos nimetty puolustaja)
var _move := Vector2.ZERO
var _aim := Vector2.RIGHT

var _attack := false
var _attack_prev := false
var _flags := {"a1": false, "a2": false, "dodge": false, "ult": false}

var _time := 0.0
var _decision_timer := 0.0
var _reaction_left := 0.0
var _aim_err := 0.0
var _aim_err_timer := 0.0
var _dodge_check_timer := 0.0
var _strafe_dir := 1.0
var _avoid_turn := 0.0          # seinänseurannan kiertosuunta (-1 vasen, +1 oikea)
var _avoid_time := 0.0          # kuinka kauan samaa seinää on seurattu (jumitunnistus)
var _atk_phase := 0.0            # hyökkäyksen jaksotus (aggression-vaihtelu)
var _atk_firing := true
var _lurk := false              # assassin väijyy (odottaa avausta) sen sijaan että syöksyy

# Lyhyt hero-kohtainen kombomuisti. Se estää kohteen vaihtamisen kesken avauksen
# ja antaa seuraavalle päätökselle etusijan oikeaan jatkokykyyn.
var _combo_target: Hero = null
var _combo_followup := ""
var _combo_timer := 0.0

# Quillin lataus-ammunta
var _hold_timer := 0.0
var _hold_pause := 0.0


func _init(p_level: int) -> void:
	level = clampi(p_level, 0, 5)
	# Per-taso arvot (indeksi 0–5 = taso 1–6). Ylempi taso: nopeampi reagointi,
	# tarkempi tähtäys, tiheämmät päätökset, enemmän väistöjä ja kykyjä sekä
	# suurempi aggressio (kuinka suuren osan ajasta botti hyökkää).
	var reactions := [0.85, 0.6, 0.4, 0.25, 0.15, 0.06]
	var aims := [30.0, 22.0, 13.0, 8.0, 4.0, 1.2]
	var decisions := [0.75, 0.6, 0.45, 0.32, 0.22, 0.15]
	var dodges := [0.03, 0.12, 0.32, 0.52, 0.72, 0.95]
	var abilities := [0.25, 0.42, 0.62, 0.78, 0.9, 1.0]
	var predicts := [0.0, 0.15, 0.4, 0.62, 0.85, 1.0]
	var aggros := [0.45, 0.62, 0.8, 0.9, 1.0, 1.0]
	# Buffien haku ja vihollisen buffin rikkominen: ylemmät tasot osaavat ja
	# ehtivät hoitaa buffit paremmin ja denyaavat vihollisen buffit.
	var focuses := [0.05, 0.25, 0.5, 0.72, 0.9, 1.0]
	var denies := [0.0, 0.0, 0.2, 0.45, 0.72, 0.95]
	# Keskitetty tuli: ylemmät tasot iskevät yhdessä samaan kohteeseen.
	var focus_fires := [0.0, 0.15, 0.45, 0.7, 0.9, 1.0]
	# Assassiinin malttavuus (odottaa eristettyä/heikkoa kohdetta) ja
	# itsesuojelu (pakenee kyvyillä hädässä) — ylemmät tasot osaavat molemmat.
	var patiences := [0.0, 0.1, 0.35, 0.6, 0.82, 1.0]
	var preserves := [0.0, 0.12, 0.35, 0.6, 0.85, 1.0]
	# Viidakon objektiivitietoisuus: alemmat tasot taistelevat vain lähellä
	# olevia olentoja, ylemmät hakevat leirit ja pomon aktiivisesti kauempaakin.
	var jungle_foci := [0.0, 0.15, 0.45, 0.68, 0.88, 1.0]
	var farm_skills := [0.05, 0.2, 0.45, 0.68, 0.88, 1.0]
	# Vaikeustasot 1–2 osaavat kykyjen peruskäytön, mutta eivät vielä rakenna
	# luotettavia ketjuja. Tasot 3–5 oppivat resurssit, jatkokyvyt ja turvalliset
	# tornipäätökset. Taso 6 tekee tämän lähes virheettä (ja huijaa yllä kuvatusti).
	var combo_skills := [0.05, 0.18, 0.45, 0.68, 0.9, 1.0]
	var disciplines := [0.08, 0.22, 0.48, 0.72, 0.92, 1.0]
	var tower_judgements := [0.55, 0.68, 0.8, 0.9, 0.97, 1.0]
	reaction = reactions[level]
	aim_error_deg = aims[level]
	decision_interval = decisions[level]
	dodge_chance = dodges[level]
	ability_chance = abilities[level]
	prediction = predicts[level]
	aggression = aggros[level]
	buff_focus = focuses[level]
	buff_deny = denies[level]
	focus_fire = focus_fires[level]
	patience = patiences[level]
	self_preserve = preserves[level]
	jungle_focus = jungle_foci[level]
	farm_skill = farm_skills[level]
	combo_skill = combo_skills[level]
	cooldown_discipline = disciplines[level]
	tower_judgement = tower_judgements[level]
	# Ultimatet ovat arvokkaimpia — niitä käytetään kaikilla tasoilla,
	# heikommilla vain hieman huonommalla ajoituksella.
	ult_chance = clampf(ability_chance + 0.35, 0.0, 1.0)

	# Taso 6 (epäreilu) huijaa avoimesti: kovempi vahinko, vähemmän otettua,
	# nopeammat jäähdytykset ja ultin lataus sekä hieman lisää vauhtia.
	if level >= 5:
		damage_mult = 1.35
		damage_taken_mult = 0.7
		cooldown_mult = 0.6
		ult_gain_mult = 1.6
		speed_mult = 1.1


func _setup_role(hero: Hero) -> void:
	var hero_def := HeroDef.get_def(hero.hero_id)
	_role = hero_def["role"]
	var archetype: String = str(hero_def.get("archetype", ""))
	_is_tank = _role == "Tankki" or archetype == "Tankki"
	_is_support = _role == "Tuki"
	_is_assassin = _role == "Assassin"
	_is_ranged = _role in ["Mage", "Ranger"] or archetype in ["Mage", "Ranger"]
	_is_jungler_role = _role == HeroDef.ROLE_JUNGLER
	match _role:
		"Tankki":
			_pref_range = 75.0
		"Fighter":
			_pref_range = 110.0
		"Assassin":
			_pref_range = 95.0
		"Mage":
			_pref_range = 330.0
		"Ranger":
			_pref_range = 430.0
		"Tuki":
			_pref_range = 280.0
		HeroDef.ROLE_JUNGLER:
			_pref_range = 145.0
		_:
			_pref_range = 200.0

	# Rooli antaa käyttäytymisen, mutta aseen todellinen kantama määrää missä
	# sankari taistelee. Erityisesti Shade on etä-assa eikä saa juosta meleehen.
	match hero.hero_id:
		"bastion":
			_pref_range = 82.0
			_basic_range = 122.0
		"ember":
			_pref_range = 500.0
			_basic_range = 780.0
		"luma":
			_pref_range = 390.0
			_basic_range = 650.0
		"blink":
			_pref_range = 70.0
			_basic_range = 104.0
		"bramble":
			_pref_range = 112.0
			_basic_range = 158.0
		"quill":
			_pref_range = 560.0
			_basic_range = 1050.0
		"boulder":
			_pref_range = 82.0
			_basic_range = 125.0
		"volt":
			_pref_range = 410.0
			_basic_range = 630.0
		"maestro":
			_pref_range = 310.0
			_basic_range = 455.0
		"shade":
			_pref_range = 360.0
			_basic_range = 515.0
		"tide":
			_pref_range = 125.0
			_basic_range = 174.0
		"scout":
			_pref_range = 500.0
			_basic_range = 660.0
		"prism":
			_pref_range = 355.0
			_basic_range = 600.0
		"rift":
			_pref_range = 76.0
			_basic_range = 112.0
		"titan":
			_pref_range = 84.0
			_basic_range = 130.0
		"hush":
			_pref_range = 420.0
			_basic_range = 690.0
		"obsidian":
			_pref_range = 88.0
			_basic_range = 136.0
		"lance":
			_pref_range = 116.0
			_basic_range = 162.0
		"salvo":
			_pref_range = 470.0
			_basic_range = 690.0
		"kaira":
			_pref_range = 108.0
			_basic_range = 154.0
		"vesper":
			_pref_range = 500.0
			_basic_range = 760.0
		"myria":
			_pref_range = 420.0
			_basic_range = 680.0
		"torq":
			_pref_range = 92.0
			_basic_range = 152.0


func _ensure_moba_assignment(hero: Hero, arena) -> void:
	if _moba_job != "":
		return
	var team_heroes: Array = []
	for h in arena.heroes:
		if is_instance_valid(h) and not h.is_unit and h.team == hero.team:
			team_heroes.append(h)
	team_heroes.sort_custom(func(a, b): return a.profile.index < b.profile.index)
	var bots: Array = team_heroes.filter(func(h): return h.controller is BotBrain)
	var designated = null
	# Tuleva Jungleri-rooli saa paikan aina ensin, myös jos pelaaja valitsee sen.
	for h in team_heroes:
		if HeroDef.get_def(h.hero_id).get("role", "") == HeroDef.ROLE_JUNGLER:
			designated = h
			break
	if designated == null and not bots.is_empty():
		designated = bots[1] if bots.size() > 1 else bots[0]
	if hero == designated:
		_moba_job = "jungle"
		_moba_lane = ""
		return
	var bot_laners: Array = bots.filter(func(h): return h != designated)
	# Support kuuluu oletuksena bottom-duoon. Valitse topiksi ensimmäinen muu
	# sankari, jotta XP-roolit ja lane-käyttäytyminen vastaavat 1/1/2-jakoa.
	var top_laner = null
	for candidate in bot_laners:
		if str(HeroDef.get_def(candidate.hero_id).get("role", "")) != "Tuki":
			top_laner = candidate
			break
	if top_laner == null and not bot_laners.is_empty():
		top_laner = bot_laners[0]
	if hero == top_laner:
		_moba_job = "top"
		_moba_lane = MapMoba.TOP
	else:
		_moba_job = "bottom"
		_moba_lane = MapMoba.BOTTOM


func update(hero: Hero, delta: float) -> void:
	_hero = hero
	_time += delta
	_attack_prev = _attack
	for key in _flags:
		_flags[key] = false
	if _role == "":
		_setup_role(hero)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if _combo_timer <= 0.0 or _combo_target == null or not is_instance_valid(_combo_target) \
			or not _combo_target.alive:
		_clear_combo()

	var arena = hero.arena
	var bb: TeamBlackboard = arena.blackboard(hero.team)

	_reaction_left = maxf(_reaction_left - delta, 0.0)
	_aim_err_timer -= delta
	if _aim_err_timer <= 0.0:
		_aim_err_timer = 0.3
		_aim_err = deg_to_rad(randf_range(-aim_error_deg, aim_error_deg))

	var decided := false
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = decision_interval
		_decide(hero, arena, bb)
		decided = true

	_update_target(hero, arena, bb)
	if decided:
		_update_lurk(hero, arena)
	_update_movement(hero, arena, bb, delta)
	_update_aim(hero)
	_update_attack(hero, delta)
	_update_abilities(hero, arena, bb, decided)
	_update_dodge(hero, arena, delta)


## Assassiinin malttavuus: neutraalissa taistelussa väijy jos kohde ei ole
## tapettavissa (matala hp) tai eristyksissä. Ylemmät tasot odottavat avausta,
## alemmat syöksyvät heti (patience skaalaa).
func _update_lurk(hero: Hero, arena) -> void:
	if not _is_assassin or _mode != Mode.FIGHT or patience < 0.05:
		return
	if _assassin_should_dive(hero, arena):
		return
	if randf() < patience:
		_lurk = true


func _assassin_should_dive(hero: Hero, arena) -> bool:
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return true
	if _target.hp < _target.max_hp * 0.45:
		return true                     # tapettavissa -> syöksy kannattaa
	# Eristetty kohde (vain se itse lähellä) -> hyvä avaus.
	var guards: int = arena.heroes_in_circle(_target.global_position, 220.0, 1 - hero.team, true, true).size()
	return guards <= 1


## Valitsee toimintatilan roolin ja tilanteen mukaan.
func _decide(hero: Hero, arena, bb: TeamBlackboard) -> void:
	_lurk = false
	# Nollaa viidakko-objektiivi ja puolustuspiste joka päätöksessä; vain
	# _decide_* asettaa ne uudelleen (esim. vetäytyvä botti ei jää leirille).
	_jungle_target = null
	_defend_pos = Vector2.INF
	_moba_goal = Vector2.INF
	_lane_returning = false
	# Tornin lukitus ohittaa kaikki objektiivit ja jahdit. Päätöstahdin lisäksi
	# liike tarkistetaan joka framella, joten myös hitaat vaikeustasot poistuvat.
	if arena.mode == "moba" and (_tower_emergency(hero, arena) != null \
			or _protected_nexus_danger(hero, arena) != null):
		_mode = Mode.RETREAT
		return
	if hero.carrying:
		_mode = Mode.CARRY
		return
	# Assassinit ja tuet vetäytyvät aikaisemmin (hauraita).
	var retreat_hp := 0.3
	if _is_assassin or _is_support:
		retreat_hp = 0.4
	if hero.hp < hero.max_hp * retreat_hp:
		_mode = Mode.RETREAT
		return
	# Jatka vetäytymistä vain jos yhä matala JA vihollinen lähellä. Heti kun on
	# turvassa (ei vihollista lähellä), palaa peliin — ei jäädä seisomaan
	# nurkkaan/respawniin vaikka olisi tekemistä (esim. 1v1).
	if _mode == Mode.RETREAT and hero.hp < hero.max_hp * 0.5 \
			and _enemy_within(hero, arena, 300.0):
		return

	# Viidakko-pelimuoto: ei reliikkiä eikä kenttäbuffeja — botti tunnistaa ja
	# farmaa leirit ja pomon vaikeustason mukaan (jungle_focus).
	if arena.mode == "jungle":
		_decide_jungle(hero, arena)
		return

	# MOBA: taistele lähellä olevia vihollisia, muuten työnnä linjaa kohti
	# vihollisen tornia/nexusta (tai puolusta uhattua omaa rakennusta).
	if arena.mode == "moba":
		_decide_moba(hero, arena, bb)
		return

	# Kenttäbuffit: hae oman tiimin arvokas buffi tai riko vihollisen buffi.
	# Vaikeustaso päättää kuinka innokkaasti ja kaukaa (buff_focus/buff_deny).
	var buff: FieldBuff = _pick_buff(hero, arena)
	if buff != null:
		_mode = Mode.GET_BUFF
		_buff_target = buff
		return

	# Vapaa reliikki: lähin (ei-tuki) hakee sen, muut ottavat roolinsa.
	if arena.relic.is_free():
		var my_dist: float = hero.global_position.distance_to(arena.relic.global_position)
		var closest := true
		var someone_near := false
		for ally in arena.alive_allies(hero.team):
			if ally == hero:
				continue
			var ad: float = ally.global_position.distance_to(arena.relic.global_position)
			if ad < my_dist - 40.0:
				closest = false
			if ad < my_dist + 120.0:
				someone_near = true
		var grab := closest or randf() < 0.2
		# Tuki nappaa reliikin vain jos kukaan muu ei ole lähellä (kanto
		# estäisi sen kykyjä).
		if _is_support and someone_near:
			grab = false
		if grab:
			_mode = Mode.GET_RELIC
		else:
			_mode = Mode.SUPPORT if _is_support else Mode.FIGHT
		return

	# Vihollisella reliikki: koko joukkue kokoontuu kantajan kimppuun.
	if bb.enemy_carrier != null:
		_mode = Mode.ATTACK_CARRIER
		return

	# Omalla joukkueella reliikki: tankit ja tuet saattavat, muut peelaavat.
	if bb.own_carrier != null and bb.own_carrier != hero:
		if _is_support or _is_tank:
			_mode = Mode.ESCORT
		else:
			_mode = Mode.FIGHT
		return

	# Ei reliikkiä kentällä: tuet asemoivat, muut taistelevat.
	_mode = Mode.SUPPORT if _is_support else Mode.FIGHT


## Viidakon päätöksenteko: puolusta itseä lähellä olevaa vihollispelaajaa
## vastaan, muuten hae paras leiri/pomo-objektiivi vaikeustason mukaan. Tuki
## pysyy tukena (seuraa ja parantaa joukkuetta objektiiveille).
func _decide_jungle(hero: Hero, arena) -> void:
	_jungle_target = null
	if _is_support:
		_mode = Mode.SUPPORT
		return
	# Lähellä oleva vihollispelaaja -> taistele (KO-pisteet + itsepuolustus).
	var threat := _nearest_enemy_player(hero, arena, 300.0)
	if threat != null:
		_mode = Mode.FIGHT
		return
	# Objektiivien tunnistus vaikeustason mukaan.
	if jungle_focus >= 0.05:
		_jungle_target = _pick_jungle_objective(hero, arena)
	_mode = Mode.FIGHT


## Paras tavoiteltava viidakko-olento (arvo tyypin mukaan, etäisyys huomioiden).
## Matkan sietokyky ja pomon houkuttelevuus skaalautuvat vaikeustasolla.
func _pick_jungle_objective(hero: Hero, arena) -> Hero:
	if arena.critters.is_empty():
		return null
	var pos: Vector2 = hero.global_position
	var max_travel: float = 480.0 + jungle_focus * 1500.0
	var best: Hero = null
	var best_score := 0.0
	for c in arena.critters:
		var cr := c as Critter
		if cr == null or not cr.alive:
			continue
		var d: float = pos.distance_to(cr.global_position)
		if d > max_travel:
			continue
		var val: float = _jungle_value(hero, cr)
		if val <= 0.0:
			continue
		var score: float = val - d * 0.10
		if score > best_score:
			best_score = score
			best = cr
	return best


## Olennon arvo botille: pistereiri > pomo (jos vahva/ryhmässä) > vahinkoleiri.
func _jungle_value(hero: Hero, cr: Critter) -> float:
	match cr.kind:
		Critter.Kind.POINTS_CAMP:
			return 200.0
		Critter.Kind.DAMAGE_CAMP:
			# Arvokkaampi kun botti terve (ehtii hyödyntää vahinkobuffin).
			return 120.0 if hero.hp > hero.max_hp * 0.5 else 70.0
		Critter.Kind.RED_CAMP:
			return 165.0 if hero.hp > hero.max_hp * 0.45 else 85.0
		Critter.Kind.BLUE_CAMP:
			return 175.0 if hero.res_type != "" else 105.0
		Critter.Kind.SMALL_CAMP:
			return 95.0
		Critter.Kind.BOSS:
			# Pomo on iso palkinto mutta vaarallinen: mene vain terveenä ja
			# mieluiten ryhmässä; korkein taso uskaltaa yksinkin.
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 420.0) >= 1
			# Baron always requires a group; difficulty improves timing, not stats.
			# muuta pomoa yksinfarmaajaksi.
			if strong and grouped:
				return 260.0
			return 0.0
	return 0.0


## MOBA-päätöksenteko: lähellä oleva vihollinen -> taistele; muuten työnnä
## linjaa hyökkäämällä lähintä tuhottavissa olevaa vihollisrakennusta.
func _decide_moba(hero: Hero, arena, bb: TeamBlackboard) -> void:
	_jungle_target = null
	_ensure_moba_assignment(hero, arena)
	# PUOLUSTUS: jos oma rakennus on uhattu ja OLEN nimetty (lähin) puolustaja,
	# kääerry puolustamaan — taistele viholliset pois rakennuksen luota. Vain yksi
	# botti kerrallaan, joten koko joukkue ei hylkää linjaa.
	if bb.defender == hero and bb.threatened_structure != null \
			and is_instance_valid(bb.threatened_structure):
		_defend_pos = bb.threatened_structure.global_position
		_mode = Mode.FIGHT
		return
	var lane_map := arena.map as MapMoba
	if _moba_job != "jungle" and _moba_lane != "" and lane_map != null \
			and lane_map.distance_to_lane(hero.global_position, _moba_lane) > 520.0:
		# Katkaise pitkä jungle-jahti. Lähellä oleva uhka sallitaan vielä
		# itsepuolustuksena target-päivityksessä, muuten palataan omalle kaarelle.
		_lane_returning = true
		_moba_goal = _moba_lane_route_goal(hero, arena, hero.global_position)
		_mode = Mode.FIGHT
		return
	if _is_support and _moba_job == "bottom":
		_mode = Mode.SUPPORT
		return
	# Vain oikea vihollissankari laukaisee tiimitaistelun — minionit ja tornit
	# eivat (ne hoidetaan tyontologiikassa, ettei botti jaa jumiin aaltoon eika
	# hylkaa tyontoa minionin takia).
	# Havaitsemisetäisyys seuraa oman aseen/roolin järkevää taistelualuetta:
	# Quill/Scout/Ember eivät kävele melee-etäisyydelle ennen kuin "näkevät"
	# kohteen, mutta lähitaistelijoiden aggro ei myöskään kasva koko ruudun yli.
	var engage_scan: float = clampf(_pref_range + 180.0, 360.0, 700.0)
	var enemy_hero := _nearest_enemy_hero(hero, arena, engage_scan)
	if enemy_hero != null:
		_mode = Mode.FIGHT
		return
	# Viidakko-objektiivi (pomo = iso tiimibuffi, leirit = buffit) jos vaikeustaso
	# tunnistaa sen ja se on arvokas & lähellä — MUUTEN työnnä linjaa. Näin
	# jungle_focus vaikuttaa vihdoin MOBAssa: matalat tasot vain työntävät,
	# korkeat kiistävät pomon ja buffit (osa botteista, ei koko joukkue kerralla).
	_jungle_target = _pick_moba_objective(hero, arena)
	if _moba_job == "jungle":
		if _jungle_target == null:
			var mm := arena.map as MapMoba
			if mm != null:
				var cycle := fposmod(arena.match_elapsed + hero.profile.index * 3.7, 24.0)
				var phase := int(arena.match_elapsed / 24.0) + hero.profile.index
				if cycle < 5.0:
					var gank_lane := MapMoba.TOP if phase % 2 == 0 else MapMoba.BOTTOM
					_moba_goal = mm.gank_point(hero.team, gank_lane, phase % 4 >= 2)
				else:
					var patrol_step := int(arena.match_elapsed / 6.0) + hero.profile.index
					_moba_goal = mm.jungle_patrol(hero.team, patrol_step)
	else:
		if _jungle_target == null:
			_jungle_target = _pick_push_target(hero, arena)
		if _jungle_target == null and arena.map is MapMoba:
			_moba_goal = (arena.map as MapMoba).role_anchor(hero.team, _moba_lane)
	_mode = Mode.FIGHT


## Viidakko-objektiivin valinta MOBAssa: PAIKALLINEN (ei koko kartan yli), jottei
## botti hylkää linjaa. Pomo on iso palkinto (tiimibuffi) ja vaatii terveyden +
## ryhmän; leirit ovat opportunistisia lähibuffeja. jungle_focus (vaikeustaso)
## säätää sekä kantaman että sen uskaltaako pomon kimppuun.
func _pick_moba_objective(hero: Hero, arena) -> Hero:
	if arena.critters.is_empty():
		return null
	if _moba_job != "jungle" and jungle_focus < 0.05:
		return null
	var is_laner := _moba_job != "jungle"
	# Laner voi kiertää vain oikealle major-objectivelle ja vain kun oma aalto
	# on työnnetty. Tavalliset campit kuuluvat junglerille; niiden vuoksi ei
	# enää hylätä topia/bottomia kesken wave-rytmin.
	if is_laner and not _lane_rotation_safe(hero, arena):
		return null
	var pos: Vector2 = hero.global_position
	var max_travel: float = 2600.0 if not is_laner else 1050.0
	var best: Hero = null
	var best_score := 0.0
	for c in arena.critters:
		var cr := c as Critter
		if cr == null or not cr.alive:
			continue
		if is_laner and not cr.is_major_objective():
			continue
		var d: float = pos.distance_to(cr.global_position)
		if d > max_travel:
			continue
		var val: float = _moba_objective_value(hero, cr)
		if val <= 0.0:
			continue
		var score: float = val - d * (0.055 if _moba_job == "jungle" else 0.14)
		if score > best_score:
			best_score = score
			best = cr
	return best


func _lane_rotation_safe(hero: Hero, arena) -> bool:
	if _moba_lane == "":
		return false
	for minion in arena.minions:
		if not is_instance_valid(minion) or not minion.alive or minion.team == hero.team \
				or minion.lane_id != _moba_lane:
			continue
		# Vihollisaalto omalla kartanpuoliskolla pitää lanerin linjalla.
		if (hero.team == 0 and minion.global_position.x < 250.0) \
				or (hero.team == 1 and minion.global_position.x > -250.0):
			return false
	return true


func _moba_objective_value(hero: Hero, cr: Critter) -> float:
	match cr.kind:
		Critter.Kind.BOSS:
			# Iso tiimibuffi -> korkein prioriteetti, mutta vaarallinen: vain
			# terveenä ja mieluiten ryhmässä (vain korkein taso uskaltaa yksin).
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 460.0) >= 1
			if strong and grouped:
				return 300.0
			return 0.0
		Critter.Kind.DRAGON:
			var strong: bool = hero.hp > hero.max_hp * 0.5
			var grouped: bool = _allies_near(hero, cr.global_position, 460.0) >= 1
			var solo_ready := _moba_job == "jungle" and jungle_focus >= 0.72 \
				and hero.has_method("bot_can_solo_major") \
				and bool(hero.call("bot_can_solo_major", cr))
			if strong and (grouped or solo_ready):
				return 245.0
			return 0.0
		Critter.Kind.DAMAGE_CAMP:
			if _moba_job != "jungle": return 0.0
			return 110.0 if hero.hp > hero.max_hp * 0.5 else 0.0   # opportunistinen buffi
		Critter.Kind.POINTS_CAMP:
			if _moba_job != "jungle": return 0.0
			return 60.0   # pisteet vain 3. tason tiebreak -> matala prioriteetti
		Critter.Kind.RED_CAMP:
			if _moba_job != "jungle": return 0.0
			return 165.0 if hero.hp > hero.max_hp * 0.45 else 55.0
		Critter.Kind.BLUE_CAMP:
			if _moba_job != "jungle": return 0.0
			return 180.0 if hero.res_type != "" else 105.0
		Critter.Kind.SMALL_CAMP:
			return 105.0 if _moba_job == "jungle" else 0.0
	return 0.0


## Lähin tuhottavissa oleva vihollisrakennus (torni ensin, nexus vasta avattuna).
func _pick_push_target(hero: Hero, arena) -> Hero:
	var foe: int = 1 - hero.team
	var best: Hero = null
	var best_d := 1.0e20
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team != foe:
			continue
		# Ohita suojatut (immuunit) rakennukset: kohdista uloin torni ensin,
		# ettei botti kävele turhaan sisemmän tornin/nexuksen alueelle.
		if s.is_protected():
			continue
		if _moba_lane != "" and s.kind == Structure.Kind.TOWER and s.lane_id != _moba_lane:
			continue
		var d: float = hero.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


## Lähin vihollisyksikkö/-sankari (joukkue 0/1, ei neutraaleja) max_dist päässä.
## Ohittaa vielä suojatun nexuksen (siihen ei voi tehdä vahinkoa).
func _nearest_enemy(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for enemy in arena.alive_enemies(hero.team):
		if enemy.team > 1:
			continue
		var st := enemy as Structure
		if st != null and st.is_protected():
			continue   # suojattua nexusta/sisätornia ei voi vahingoittaa -> ohita
		var d: float = enemy.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Lähin vihollis*pelaaja*/-yksikkö max_dist päässä (sama suodatus).
func _nearest_enemy_player(hero: Hero, arena, max_dist: float) -> Hero:
	return _nearest_enemy(hero, arena, max_dist)


## Lähin vihollis*sankari* (ei yksiköitä: ei minioneja/torneja) max_dist päässä.
func _nearest_enemy_hero(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for e in arena.enemy_heroes(hero.team):
		if arena.mode == "moba" and not _moba_can_see(hero, e, arena):
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _moba_can_see(observer: Hero, target: Hero, arena) -> bool:
	var dist: float = observer.global_position.distance_to(target.global_position)
	if dist <= 190.0:
		return true
	var mm := arena.map as MapMoba
	if mm == null:
		return dist <= 760.0
	# Puskan ulkopuolelta näkee sisään vain lähietäisyydeltä. Samassa puskassa
	# olevat näkevät toisensa normaalisti. Tämä ei vielä piirrä pelaajan fogia,
	# mutta poistaa AI:n epäreilun seinän/pimeän läpi tietämisen.
	if mm.is_in_brush(target.global_position) \
			and not mm.same_brush(observer.global_position, target.global_position):
		return dist <= 235.0
	var sight: float = 610.0 if mm.is_dark_jungle(observer.global_position) else 760.0
	if dist > sight:
		return false
	var space := observer.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(observer.global_position,
		target.global_position, 1)
	return space.intersect_ray(query).is_empty()


func _moba_unit_relevant(hero: Hero, unit: Hero) -> bool:
	var d: float = hero.global_position.distance_to(unit.global_position)
	if _moba_job == "jungle":
		return d <= 420.0
	if unit is Minion:
		return (unit as Minion).lane_id == _moba_lane and d <= 620.0
	if unit is Structure:
		var s := unit as Structure
		return (s.kind == Structure.Kind.NEXUS or s.lane_id == _moba_lane) and d <= 850.0
	return d <= 520.0


## Lähin vihollisminioni max_dist päässä (vihollisaallon siivoamiseen).
func _nearest_enemy_minion(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	for e in arena.alive_enemies(hero.team):
		if not (e is Minion):
			continue
		if _moba_lane != "" and (e as Minion).lane_id != _moba_lane:
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d > max_dist:
			continue
		var hp_frac: float = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
		var score: float = d - farm_skill * (1.0 - hp_frac) * 280.0
		var estimated_hit: float = 18.0 + farm_skill * 38.0
		if e.hp <= estimated_hit:
			score -= farm_skill * 190.0
		if score < best_score:
			best_score = score
			best = e
	return best


## Montako omaa minionia on annetun pisteen lähellä (onko oma aalto paikalla?).
func _own_minions_near(hero: Hero, arena, pos: Vector2, r: float) -> int:
	var n := 0
	for m in arena.minions:
		if is_instance_valid(m) and m.alive and m.team == hero.team \
				and m.global_position.distance_to(pos) < r:
			n += 1
	return n


## Arvioi tornia suojaavan aallon laadun. Pelkkä "kaksi minionia jossain
## lähellä" ei riitä: tornin pitää oikeasti olla lukittunut elävään omaan
## minioniin (tai vasta valitsemassa vähintään kolmen terveen minionin aaltoa).
func _tower_wave_safe(hero: Hero, arena, tower: Structure) -> bool:
	var count := 0
	var health_equiv := 0.0
	for m in arena.minions:
		if not is_instance_valid(m) or not m.alive or m.team != hero.team:
			continue
		if m.global_position.distance_to(tower.global_position) > Structure.SHOT_RANGE - 12.0:
			continue
		count += 1
		health_equiv += clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	var lock := tower._target_lock
	if lock == hero:
		return false
	if lock is Minion and is_instance_valid(lock) and lock.alive and lock.team == hero.team:
		# Neljän minionin aallosta pitää olla vähintään kolme ja yhteensä noin
		# kahden täyden minionin HP. Näin hidas tankki lähtee ennen viimeistä laukausta.
		return count >= 3 and health_equiv >= 2.0
	if lock == null:
		return count >= 4 and health_equiv >= 2.7
	return false


func _enemy_tower_covering(hero: Hero, arena, point: Vector2, margin := 0.0) -> Structure:
	var best: Structure = null
	var best_d := 1.0e20
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team or s.kind != Structure.Kind.TOWER:
			continue
		var d: float = point.distance_to(s.global_position)
		if d <= Structure.SHOT_RANGE + margin and d < best_d:
			best_d = d
			best = s
	return best


## Torni on välitön hätä, jos se on lukinnut botin tai botti seisoo sen
## kantamalla ilman oikeasti kestävää minionisuojaa.
func _tower_emergency(hero: Hero, arena) -> Structure:
	if arena.mode != "moba":
		return null
	var pos: Vector2 = hero.global_position
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team or s.kind != Structure.Kind.TOWER:
			continue
		var d: float = pos.distance_to(s.global_position)
		if s._target_lock == hero and d < Structure.SHOT_RANGE + 110.0:
			return s
		if d < Structure.SHOT_RANGE and not _tower_wave_safe(hero, arena, s):
			return s
	return null


func _protected_nexus_danger(hero: Hero, arena) -> Structure:
	if arena.mode != "moba":
		return null
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != hero.team and s.kind == Structure.Kind.NEXUS \
				and s.is_protected() \
				and hero.global_position.distance_to(s.global_position) < Structure.NEXUS_LASER_RANGE + 70.0:
			return s
	return null


func _tower_escape_point(hero: Hero, arena, tower: Structure, hold_range: float) -> Vector2:
	var pos: Vector2 = hero.global_position
	var home: Vector2 = arena.map.spawn_point(hero.team, 0)
	var home_side: Vector2 = home - tower.global_position
	if home_side.length() < 1.0:
		home_side = pos - tower.global_position
	if home_side.length() < 1.0:
		home_side = Vector2.LEFT if hero.team == 0 else Vector2.RIGHT
	return arena.map.clamp_to_field(tower.global_position + home_side.normalized() * hold_range, 70.0)


func _moba_emergency_goal(hero: Hero, arena) -> Vector2:
	if arena.mode != "moba":
		return Vector2.INF
	var nexus := _protected_nexus_danger(hero, arena)
	if nexus != null:
		return _tower_escape_point(hero, arena, nexus, Structure.NEXUS_LASER_RANGE + 100.0)
	var tower := _tower_emergency(hero, arena)
	if tower != null:
		return _tower_escape_point(hero, arena, tower, Structure.SHOT_RANGE + 95.0)
	return Vector2.INF


## MOBA-työnnön kohteenvalinta: vihollissankari lähellä -> taistele; muuten
## siivoa vihollisaalto (jotta oma aalto crashaa tornille); muuten lyö rakennus.
func _moba_push_target(hero: Hero, arena) -> Hero:
	var hero_scan: float = clampf(_pref_range + 150.0, 280.0, 700.0)
	var enemy_hero := _nearest_enemy_hero(hero, arena, hero_scan)
	if enemy_hero != null:
		return enemy_hero
	var minion_scan := 420.0 if _moba_job == "jungle" else 950.0
	var minion := _nearest_enemy_minion(hero, arena, minion_scan)
	if minion != null:
		return minion
	return _jungle_target


func _allies_near(hero: Hero, pos: Vector2, r: float) -> int:
	var n := 0
	for ally in hero.arena.alive_allies(hero.team):
		if ally == hero:
			continue
		if ally.global_position.distance_to(pos) < r:
			n += 1
	return n


## Kohteenvalinta roolin mukaan.
func _update_target(hero: Hero, arena, bb: TeamBlackboard) -> void:
	var enemies: Array = arena.alive_enemies(hero.team)
	if enemies.is_empty():
		_target = null
		return
	if arena.mode == "moba" and _lane_returning:
		var local_threat := _nearest_enemy_hero(hero, arena, 240.0)
		if local_threat != _target:
			_target = local_threat
			_reaction_left = reaction
		return
	# Jatka samaan sankariin kombon lyhyen toteutusikkunan ajan. Muisti ei seuraa
	# koko kartan yli eikä pakota tornidiveä; turvallisuussäännöt ohittavat iskut.
	if _combo_timer > 0.0 and _combo_target != null and is_instance_valid(_combo_target) \
			and _combo_target.alive \
			and hero.global_position.distance_to(_combo_target.global_position) < 900.0:
		_target = _combo_target
		return

	var pos: Vector2 = hero.global_position
	var pick: Hero = null

	# Viidakko: jos on valittu leiri/pomo-objektiivi, hyökkää sitä — paitsi jos
	# vihollispelaaja tulee lähelle (silloin puolustaudu / KO-pisteet).
	if _jungle_target != null and is_instance_valid(_jungle_target) and _jungle_target.alive:
		var new_target: Hero = null
		if arena.mode == "moba":
			# MOBA: siivoa aalto ennen tornia, taistele sankaria lähellä.
			new_target = _moba_push_target(hero, arena)
		else:
			var near_player := _nearest_enemy_player(hero, arena, 240.0)
			new_target = near_player if near_player != null else _jungle_target
		# HUOM: reaktioaika nollataan VAIN kun kohde vaihtuu — muuten se
		# nollautuisi joka ruutu ja botti ei ikinä ehtisi lyödä (torni/aalto).
		if new_target != _target:
			_target = new_target
			_reaction_left = reaction
		return

	# Oikeat vihollissankarit ENSIN: MOBAssa "enemies" sisältää myös minionit ja
	# rakennukset, eikä botti (etenkään assassin) saa näykkiä aaltoa sankarin
	# sijaan taistelussa. Yksiköt jäävät varasyyksi jos sankaria ei ole lähellä.
	var hero_enemies: Array = arena.enemy_heroes(hero.team)
	if arena.mode == "moba":
		hero_enemies = hero_enemies.filter(func(e):
			if not _moba_can_see(hero, e, arena):
				return false
			if _moba_job == "jungle":
				# Jungleri ottaa taistelun lähellä reittiään/gankkia, ei lukitu
				# lähimpään sankariin toisella puolella koko karttaa.
				return e.global_position.distance_to(pos) <= 620.0
			if _moba_lane == "":
				return e.global_position.distance_to(pos) <= 520.0
			var mm := arena.map as MapMoba
			return e.global_position.distance_to(pos) < 360.0 or mm == null \
				or mm.nearest_lane(e.global_position) == _moba_lane)
	if _mode == Mode.ATTACK_CARRIER and bb.enemy_carrier != null \
			and is_instance_valid(bb.enemy_carrier):
		pick = bb.enemy_carrier
	elif _is_assassin:
		# Assassinit suosivat heikkoja takalinjan SANKAREITA (eivät minioneja).
		var best_score := -1e20
		for enemy in hero_enemies:
			var d: float = enemy.global_position.distance_to(pos)
			if d > 700.0:
				continue
			var score := -d
			if HeroDef.get_def(enemy.hero_id)["role"] in BACKLINE_ROLES:
				score += 260.0
			score += (1.0 - enemy.hp / enemy.max_hp) * 320.0
			if score > best_score:
				best_score = score
				pick = enemy
		if pick == null:
			pick = _nearest(hero_enemies, pos)
	else:
		# Tankki suojaa: jos joku uhkaa suojeltavaa, käännytään sitä vastaan.
		if _is_tank and bb.protect_ally != null and bb.protect_ally != hero:
			var threat := _nearest_to(hero_enemies, bb.protect_ally.global_position, 240.0)
			if threat != null:
				pick = threat
		if pick == null:
			# Keskitetty tuli: ylemmillä tasoilla iske samaan kohteeseen kuin
			# muut joukkueen botit (kunhan se on järkevän matkan päässä).
			if focus_fire >= 0.4 and bb.focus_target != null \
					and is_instance_valid(bb.focus_target) and bb.focus_target.alive \
					and pos.distance_to(bb.focus_target.global_position) < _pref_range + 380.0:
				pick = bb.focus_target
			else:
				pick = _nearest(hero_enemies, pos)

	# Varasyy: jos yhtään vihollissankaria ei ollut valittavissa (esim. puhdas
	# työntötilanne), iske lähintä EI-suojattua yksikköä/rakennusta.
	if pick == null:
		var attackables: Array = enemies
		if arena.mode == "moba":
			attackables = enemies.filter(func(e): return _moba_unit_relevant(hero, e))
		pick = _nearest_attackable(attackables, pos)

	if pick != _target:
		_target = pick
		_reaction_left = reaction


func _nearest(list: Array, from: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1e20
	for h in list:
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


func _nearest_to(list: Array, from: Vector2, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for h in list:
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


## Lähin lyötävä kohde: ohittaa suojatut (immuunit) rakennukset, ettei botti
## lukitu iskemään sisätornia/nexusta joka torjuu kaiken (0 vahinkoa).
func _nearest_attackable(list: Array, from: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1e20
	for h in list:
		if not is_instance_valid(h) or not h.alive:
			continue
		var s := h as Structure
		if s != null and s.is_protected():
			continue
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


## Paras tavoiteltava buffi (oma napattava tai vihollisen rikottava) tai null.
## Etäisyysraja ja denyaus skaalautuvat vaikeustasolla (buff_focus/buff_deny).
func _pick_buff(hero: Hero, arena) -> FieldBuff:
	if buff_focus < 0.06 or arena.buffs.is_empty():
		return null
	var pos: Vector2 = hero.global_position
	var max_divert := 320.0 + buff_focus * 950.0
	var best: FieldBuff = null
	var best_score := 45.0
	for b in arena.buffs:
		if not is_instance_valid(b):
			continue
		var d: float = pos.distance_to(b.global_position)
		if d > max_divert:
			continue
		var val := 0.0
		if b.owner_team == hero.team:
			# Oman tiimin buffi: nappaa. Sininen hyödyttää vain resurssisankaria.
			if b.type == "red":
				val = 110.0
			elif _has_resource(hero):
				val = 125.0
			else:
				val = 10.0
		else:
			# Vihollisen buffi: riko (deny) jos vaikeustaso sallii.
			if buff_deny < 0.06:
				continue
			val = buff_deny * 95.0
			if _is_assassin or _is_ranged:
				val += 25.0
		var score := val - d * 0.12
		if score > best_score:
			best_score = score
			best = b
	return best


func _has_resource(hero: Hero) -> bool:
	return hero.res_type != ""


func _update_movement(hero: Hero, arena, bb: TeamBlackboard, delta: float) -> void:
	var pos: Vector2 = hero.global_position
	var goal := pos

	match _mode:
		Mode.GET_BUFF:
			if _buff_target != null and is_instance_valid(_buff_target):
				goal = _buff_target.global_position
			else:
				goal = _combat_goal(hero, arena, bb, pos)  # buffi meni -> taistele
		Mode.GET_RELIC:
			goal = arena.relic.global_position
		Mode.RETREAT:
			goal = _retreat_goal(hero, arena, bb, pos)
		Mode.CARRY:
			goal = _carry_goal(arena, pos)
		Mode.ESCORT:
			goal = _escort_goal(hero, arena, bb, pos)
		Mode.SUPPORT:
			goal = _support_goal(hero, arena, bb, pos)
		Mode.FIGHT, Mode.ATTACK_CARRIER:
			goal = _combat_goal(hero, arena, bb, pos)

	# Framikohtainen turvaverkko: tornin aggro voi vaihtua heti sankariosuman
	# jälkeen, paljon ennen seuraavaa vaikeustason mukaista päätöshetkeä.
	var emergency_goal := _moba_emergency_goal(hero, arena)
	if is_finite(emergency_goal.x):
		goal = emergency_goal

	var desired: Vector2 = goal - pos
	if desired.length() < 24.0:
		desired = Vector2.ZERO
	else:
		desired = desired.normalized()

	# Sivuttaisliike taistelussa, ettei botti seiso maalitauluna.
	if _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER] and _target != null and desired.length() < 0.7:
		if randf() < 0.01:
			_strafe_dir = -_strafe_dir
		var to_t: Vector2 = (_target.global_position - pos).normalized()
		desired += to_t.orthogonal() * sin(_time * 2.5) * 0.5 * _strafe_dir

	# Erottelu ENSIN: ei tungeta liittolaisen päälle. Tehdään ennen esteenväistöä,
	# jotta seinänseuranta saa viimeisen sanan eikä erottelu työnnä takaisin seinään.
	for ally in arena.alive_allies(hero.team):
		if ally == hero:
			continue
		var diff: Vector2 = pos - ally.global_position
		if diff.length() < 70.0 and diff.length() > 0.01:
			desired += diff.normalized() * 0.6

	# Esteenväistö VIIMEISENÄ: seinänseuranta viuhkasäteillä (osaa liukua pitkää
	# seinää pitkin lähimmälle aukolle, esim. MOBA-kartan gank-aukoista).
	if desired.length() > 0.1:
		desired = _steer_around(hero, pos, desired, delta)

	_move = desired.limit_length(1.0)


## Seinänseuranta: jos eteenpäin on este, valitse kiertosuunta (avoimempi puoli,
## hystereesillä ettei värise) ja kokeile kasvavia kulmia kunnes löytyy vapaa
## suunta. Näin botti liukuu pitkää seinää pitkin lähimmälle aukolle sen sijaan
## että jää jumiin — ja osaa mennä esim. MOBA-kartan gank-aukoista.
func _steer_around(hero: Hero, pos: Vector2, desired: Vector2, delta: float) -> Vector2:
	var space := hero.get_world_2d().direct_space_state
	var look: float = 130.0 + hero.radius
	if _ray_clear(space, pos, desired, look):
		_avoid_turn = 0.0
		_avoid_time = 0.0
		return desired
	_avoid_time += delta
	# Valitse kiertosuunta kun väistö alkaa: avoimempi puoli (pidemmillä luotaimilla
	# jotta ne oikeasti havaitsevat edessä olevan seinän). Tasapelissä käytä botin
	# omaa strafe-suuntaa -> botit hajautuvat eri puolille eikä kaikki käänny samaan.
	if _avoid_turn == 0.0:
		var left_open: float = _open_dist(space, pos, desired.rotated(-0.6), look * 2.5)
		var right_open: float = _open_dist(space, pos, desired.rotated(0.6), look * 2.5)
		if left_open > right_open + 20.0:
			_avoid_turn = -1.0
		elif right_open > left_open + 20.0:
			_avoid_turn = 1.0
		else:
			_avoid_turn = _strafe_dir
	elif _avoid_time > 1.1:
		# Sama seinä liian kauan (mahd. väärä puoli tai umpikulma) -> vaihda puolta.
		_avoid_turn = -_avoid_turn
		_avoid_time = 0.0
	# Kokeile kasvavia kulmia valitulle puolelle.
	for mag in [0.5, 0.9, 1.3, 1.7, 2.2]:
		var cand: Vector2 = desired.rotated(_avoid_turn * mag)
		if _ray_clear(space, pos, cand, look):
			return cand
	# Valittu puoli täysin tukossa -> vaihda puolta ja kokeile.
	_avoid_turn = -_avoid_turn
	for mag2 in [0.5, 0.9, 1.3, 1.7]:
		var cand2: Vector2 = desired.rotated(_avoid_turn * mag2)
		if _ray_clear(space, pos, cand2, look):
			return cand2
	# Kaikki tukossa -> peräänny hieman (irrota kulmasta).
	return -desired * 0.4


func _ray_clear(space: PhysicsDirectSpaceState2D, pos: Vector2, dir: Vector2, dist: float) -> bool:
	var q := PhysicsRayQueryParameters2D.create(pos, pos + dir.normalized() * dist, 1)
	return space.intersect_ray(q).is_empty()


## Vapaan matkan pituus suuntaan (osumaan asti, tai koko dist jos vapaa).
func _open_dist(space: PhysicsDirectSpaceState2D, pos: Vector2, dir: Vector2, dist: float) -> float:
	var q := PhysicsRayQueryParameters2D.create(pos, pos + dir.normalized() * dist, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return dist
	var hp: Vector2 = hit["position"]
	return pos.distance_to(hp)


## Vetäytyminen: kite poispäin uhasta kohtuullinen matka (ei aivan nurkkaan).
## Kun uhkaa ei ole, liiku takaisin objektille — ei jäädä seisomaan respawniin.
func _retreat_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var away := Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		away = pos - _target.global_position
	elif bb.threat_center != Vector2.ZERO:
		away = pos - bb.threat_center
	# MOBA: vetäydy kohti OMAA tukikohtaa — ei reliikin piilopaikkaan (0,0) eikä
	# "pois uhasta" -suuntaan joka voi viedä SYVEMMÄLLE vihollisen alueelle.
	# Sekoita pako + kotisuunta -> palaa käytävää pitkin kotiin.
	if arena.mode == "moba":
		if _moba_job != "jungle" and _moba_lane != "":
			return _moba_lane_route_goal(hero, arena, pos, false)
		var home: Vector2 = arena.map.spawn_point(hero.team, 0)
		var to_home: Vector2 = home - pos
		var dir: Vector2 = to_home
		if away.length() > 1.0 and to_home.length() > 1.0:
			dir = away.normalized() * 0.5 + to_home.normalized()
		if dir.length() < 1.0:
			dir = to_home
		if dir.length() < 1.0:
			return home
		return arena.map.clamp_to_field(pos + dir.normalized() * 300.0, 100.0)
	if away.length() < 1.0:
		# Ei uhkaa: palaa peliin (reliikki/keskusta), älä jää nurkkaan.
		return arena.relic.global_position
	return arena.map.clamp_to_field(pos + away.normalized() * 280.0, 100.0)


func _enemy_within(hero: Hero, arena, dist: float) -> bool:
	for e in arena.alive_enemies(hero.team):
		if e.global_position.distance_to(hero.global_position) < dist:
			return true
	return false


## Kantaja kiertää keskustaa ja pakoilee lähintä vihollista.
func _carry_goal(arena, pos: Vector2) -> Vector2:
	var flee := Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		var away: Vector2 = pos - _target.global_position
		if away.length() < 420.0:
			flee = away.normalized() * 300.0
	var orbit: Vector2 = (pos - Vector2.ZERO).orthogonal().normalized() * 120.0 * _strafe_dir
	return arena.map.clamp_to_field(pos + flee + orbit, 160.0)


## Saatto: tankki asettuu kantajan eteen, tuki taakse.
func _escort_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var anchor: Hero = bb.own_carrier
	if anchor == null:
		return _combat_goal(hero, arena, bb, pos)
	var to_threat := Vector2.RIGHT
	if bb.threat_center != Vector2.ZERO:
		to_threat = (bb.threat_center - anchor.global_position).normalized()
	if _is_tank:
		# Tankki rintaman puolelle, valmiina blokkaamaan.
		return anchor.global_position + to_threat * 150.0
	# Tuki suojaan kantajan taakse.
	return anchor.global_position - to_threat * 110.0


## Tuki pysyy suojeltavan takana ja pakenee jos vihollinen pääsee lähelle.
func _support_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var pocket: Hero = bb.protect_ally
	if arena.mode == "moba" and _moba_lane != "":
		var lane_partner := _moba_lane_partner(hero, arena)
		if lane_partner != null:
			pocket = lane_partner
	if pocket == null or pocket == hero:
		pocket = bb.frontline_ally
	if pocket == null or pocket == hero:
		# MOBA: ei jäädä keskustaan — seuraa linjan työntöä oman aallon takana.
		if arena.mode == "moba":
			return _moba_support_goal(hero, arena, pos)
		# Ei suojeltavaa: pysy lähellä keskustaa mutta poissa vihollisista.
		var base: Vector2 = arena.relic.global_position
		if _target != null and is_instance_valid(_target) \
				and _target.global_position.distance_to(pos) < 240.0:
			return pos + (pos - _target.global_position).normalized() * 200.0
		return base
	var back := Vector2.ZERO
	if bb.threat_center != Vector2.ZERO:
		back = (pocket.global_position - bb.threat_center).normalized()
	var goal: Vector2 = pocket.global_position + back * 120.0
	# Väistä jos vihollinen liian lähellä (tuki ei kestä etulinjaa).
	if _target != null and is_instance_valid(_target):
		var d: float = _target.global_position.distance_to(pos)
		if d < 200.0:
			goal = pos + (pos - _target.global_position).normalized() * 200.0
	# MOBA: älä seuraa sukeltavaa etulinjaa vihollistornin kantamalle (tuki kestää
	# huonosti torni-iskuja) — sama kantamaklamppi kuin muullakin liikkeellä.
	if arena.mode == "moba":
		goal = _moba_tower_safe(hero, arena, pos, goal)
	return goal


## Bottom-tuki valitsee oman laneparinsa, ei globaalin blackboardin jungleria
## tai top-laneria. Tämä estää tukibottia seuraamasta sattumalta heikointä
## liittolaista junglen läpi usean campin ajaksi.
func _moba_lane_partner(hero: Hero, arena) -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	var mm := arena.map as MapMoba
	for ally in arena.alive_allies(hero.team):
		if ally == hero:
			continue
		var same_lane := false
		if ally.controller is BotBrain:
			same_lane = (ally.controller as BotBrain)._moba_lane == _moba_lane
		elif mm != null:
			same_lane = mm.nearest_lane(ally.global_position) == _moba_lane
		if not same_lane:
			continue
		var score: float = ally.global_position.distance_to(hero.global_position)
		if HeroDef.get_def(ally.hero_id).get("role", "") == "Tuki":
			score += 300.0
		if score < best_score:
			best_score = score
			best = ally
	return best


## MOBA-tuki ilman selvää suojeltavaa: seuraa työntävää liittolaista (pysy
## hänen takanaan vihollisen puolelle nähden), tai etene painostettavaa
## rakennusta kohti — ei ajauta keskustan jokivyöhykkeeseen.
func _moba_support_goal(hero: Hero, arena, pos: Vector2) -> Vector2:
	var push := _pick_push_target(hero, arena)
	var aim_pos: Vector2 = push.global_position if push != null else pos
	var lead := _moba_frontline_ally(hero, arena, aim_pos)
	var goal: Vector2 = pos
	if lead != null:
		# Asetu työntävän liittolaisen taakse (omalle puolelle päin).
		var back: Vector2 = (pos - aim_pos).normalized()
		goal = lead.global_position + back * 120.0
	else:
		# Yksin jäänyt tuki: älä sukella yksin linjaa pitkin — vetäydy omalle
		# puolelle (tukikohtaan) turvaan.
		goal = arena.map.spawn_point(hero.team, 0)
	return _moba_tower_safe(hero, arena, pos, goal)


## Liittolainen, joka on lähimpänä painostettavaa rakennusta (työnnön kärki).
func _moba_frontline_ally(hero: Hero, arena, aim_pos: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1.0e20
	for a in arena.alive_allies(hero.team):
		if a == hero:
			continue
		if a.controller is BotBrain and (a.controller as BotBrain)._moba_lane != _moba_lane:
			continue
		var d: float = a.global_position.distance_to(aim_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


## Seuraa Eternal Dividen kaarevaa lanea waypointilta seuraavalle. Jos botti
## on ajautunut jungleen, ensimmäinen tavoite on lähin kohta omalla linjalla;
## vasta linjalle palattuaan se etenee kohti vihollisen basea.
func _moba_lane_route_goal(hero: Hero, arena, pos: Vector2,
		toward_enemy := true) -> Vector2:
	var mm := arena.map as MapMoba
	if mm == null or _moba_lane == "":
		return pos
	var path: Array = mm.lane_path(_moba_lane)
	if hero.team == 1:
		path = path.duplicate()
		path.reverse()
	if path.size() < 2:
		return pos
	var closest: Vector2 = path[0]
	var best_sq := INF
	var best_segment := 0
	var best_t := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		var point := a + ab * t
		var d_sq := pos.distance_squared_to(point)
		if d_sq < best_sq:
			best_sq = d_sq
			closest = point
			best_segment = i
			best_t = t
	var on_jungle_side := (pos.y > -1250.0) if _moba_lane == MapMoba.TOP \
		else (pos.y < 1250.0)
	if best_sq > 260.0 * 260.0 and on_jungle_side:
		return mm.nearest_lane_entry(pos, _moba_lane)
	if best_sq > 175.0 * 175.0:
		return closest
	if toward_enemy:
		var advance := best_segment + (2 if best_t > 0.72 else 1)
		return path[mini(advance, path.size() - 1)]
	var retreat := best_segment - (1 if best_t < 0.25 else 0)
	return path[maxi(retreat, 0)]


## Taisteluasemointi: lähesty kohdetta roolin ihannematkalle. Tankki peelaa.
func _combat_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	# PUOLUSTUS (MOBA): pysy uhatun oman rakennuksen luona. Taistele kohdetta vain
	# jos se on lähellä rakennusta; muuten asetu rakennuksen ja uhkasuunnan väliin
	# (odota hyökkääjää siellä, älä lähde perään syvälle).
	if is_finite(_defend_pos.x):
		var enemy_at_base: bool = _target != null and is_instance_valid(_target) \
			and _target.global_position.distance_to(_defend_pos) < 520.0
		if not enemy_at_base:
			var d2: Vector2 = bb.threat_center - _defend_pos
			if d2.length() < 1.0:
				d2 = Vector2.ZERO - _defend_pos   # kohti keskustaa jos ei uhkapistettä
			if d2.length() < 1.0:
				return _defend_pos
			return _defend_pos + d2.normalized() * 140.0

	# Tankin peel: jos vihollinen uhkaa suojeltavaa, asetu väliin. Ei rakennuksia
	# vastaan (tornia ei "peelata" — sitä työnnetään).
	if _is_tank and bb.protect_ally != null and bb.protect_ally != hero \
			and _target != null and is_instance_valid(_target) and not (_target is Structure):
		var pd: float = _target.global_position.distance_to(bb.protect_ally.global_position)
		if pd < 220.0:
			return bb.protect_ally.global_position \
				+ (_target.global_position - bb.protect_ally.global_position).normalized() * 60.0

	if _target == null or not is_instance_valid(_target):
		if bb.own_carrier != null and is_instance_valid(bb.own_carrier):
			return bb.own_carrier.global_position
		if arena.mode == "moba":
			if is_finite(_moba_goal.x):
				return _moba_goal
			var mm := arena.map as MapMoba
			if mm != null:
				if _moba_job == "jungle":
					var step := int(arena.match_elapsed / 8.0) + hero.profile.index
					return mm.jungle_patrol(hero.team, step)
				return mm.role_anchor(hero.team, _moba_lane)
			return arena.map.spawn_point(hero.team, 0)
		return arena.relic.global_position

	var dist: float = pos.distance_to(_target.global_position)
	if arena.mode == "moba" and _moba_job != "jungle" and _moba_lane != "":
		var lane_objective := false
		var behind := false
		if _target is Minion:
			lane_objective = (_target as Minion).lane_id == _moba_lane
			behind = (_target.global_position.x < pos.x) if hero.team == 0 \
				else (_target.global_position.x > pos.x)
		elif _target is Structure:
			var structure := _target as Structure
			lane_objective = structure.kind == Structure.Kind.NEXUS \
				or structure.lane_id == _moba_lane
		# Kaukaiseen waveen/torniin ei juosta suoraa viivaa junglen läpi.
		if lane_objective and not behind and dist > 620.0:
			return _moba_lane_route_goal(hero, arena, pos)
	var to_target: Vector2 = (_target.global_position - pos).normalized()
	var goal: Vector2 = pos
	if _lurk:
		# Väijy keskietäisyydeltä: älä syöksy sisään ennen avausta (assassin).
		var lurk_range := 360.0
		if dist < lurk_range - 60.0:
			goal = pos - to_target * 160.0
		elif dist > lurk_range + 140.0:
			goal = _target.global_position - to_target * lurk_range
		else:
			goal = pos
	elif dist > _pref_range + 40.0:
		goal = _target.global_position - to_target * _pref_range
	elif dist < _pref_range - 60.0:
		# Liian lähellä (etenkin kaukotaistelijat): peräänny.
		goal = pos - to_target * 120.0
	# Keep ranged jungle movement inside the camp leash. Otherwise a ranged bot
	# can repeatedly reset the same camp to full health while kiting it.
	if _target is Critter:
		var camp := _target as Critter
		var leash_limit := maxf(float(camp.controller.leash) - 90.0, 150.0)
		var from_home: Vector2 = goal - camp.home
		if from_home.length() > leash_limit:
			goal = camp.home + from_home.normalized() * leash_limit
	# MOBA: älä astu vihollistornin kantamalle ilman omaa aaltoa — riippumatta
	# siitä onko kohde torni vai sitä vartioiva minioni (torni ampuu minioneja
	# ensin, joten oman aallon on annettava crashata). Kaukotaistelijat ohitetaan.
	return _moba_tower_safe(hero, arena, pos, goal)


## Leikkaa maalipisteen tornin ulkopuolelle, ellei torni ole oikeasti lukittunut
## kestävään minioniaaltoon. Jos aggro on jo botissa, poistumispuoli valitaan
## oman tukikohdan suunnasta eikä satunnaisesti tornin toiselta puolelta.
func _moba_tower_safe(hero: Hero, arena, pos: Vector2, goal: Vector2) -> Vector2:
	if arena.mode != "moba":
		return goal
	var tower_hold: float = Structure.SHOT_RANGE + 85.0
	var out: Vector2 = goal
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team:
			continue
		if s.kind == Structure.Kind.NEXUS:
			# Suojattu nexus polttaa laserilla (tappaa nopeasti) -> pysy AINA kaukana,
			# myös kaukotaistelijana. Haavoittuvana laser sammuu -> saa lähestyä (tuho).
			if not s.is_protected():
				continue
			var nhold: float = Structure.NEXUS_LASER_RANGE + 100.0
			if out.distance_to(s.global_position) >= nhold:
				continue
			out = _tower_escape_point(hero, arena, s, nhold)
			continue
		# Jo lukittu sankari vetäytyy kotiin päin, vaikka sen nykyinen maalipiste
		# olisi sattumalta kantaman ulkopuolella.
		if s._target_lock == hero and pos.distance_to(s.global_position) < tower_hold + 70.0:
			out = _tower_escape_point(hero, arena, s, tower_hold + 20.0)
			continue
		if out.distance_to(s.global_position) >= tower_hold:
			continue
		var min_hp_ratio: float = 0.67 - tower_judgement * 0.22
		var healthy: bool = hero.hp > hero.max_hp * min_hp_ratio
		if healthy and _tower_wave_safe(hero, arena, s):
			continue
		out = _tower_escape_point(hero, arena, s, tower_hold)
	return out


## Onko sankarikohteen jahtaaminen tornin alla kielletty? Minioniaalto ei tee
## vihollissankarin lyömisestä turvallista: torni siirtää aggron välittömästi
## hyökkääjään. Vain korkeat tasot saavat tehdä tarkasti rajatun execute-diven.
func _tower_diving(hero: Hero, arena) -> bool:
	if arena.mode != "moba":
		return false
	if _target == null or not is_instance_valid(_target) or not _target.alive or _target.is_unit:
		return false
	var tower := _enemy_tower_covering(hero, arena, _target.global_position)
	if tower == null:
		return false
	# Ulkopuolelta ampuva ranger/mage saa pokettaa tornin alla olevaa kohdetta;
	# puolustusaggro ei valitse kantaman ulkopuolella olevaa hyökkääjää.
	if hero.global_position.distance_to(tower.global_position) > Structure.SHOT_RANGE + 12.0:
		return false
	return not _calculated_tower_execute(hero, arena, tower)


func _calculated_tower_execute(hero: Hero, arena, tower: Structure) -> bool:
	# Näytetty vaikeustaso 4+ (sisäinen indeksi 3+) oppii dive-executet. Alemmat
	# pelaavat turvallisemmin sen sijaan, että niiden vaikeus syntyisi ruokkimisesta.
	if level < 3 or _target == null or not _target_is_hero():
		return false
	if tower._target_lock == hero or tower._charge >= 0.62:
		return false
	var target_ratio: float = _target.hp / maxf(_target.max_hp, 1.0)
	var execute_limit: float = 0.08 + float(level - 3) * 0.035
	var own_limit: float = 0.82 - float(level - 3) * 0.04
	if target_ratio > execute_limit or hero.hp < hero.max_hp * own_limit:
		return false
	if hero.global_position.distance_to(tower.global_position) < 280.0:
		return false                         # liian syvällä: poistumistie on liian pitkä
	if hero.global_position.distance_to(_target.global_position) > _basic_range:
		return false                         # ei lisäjahtia executea varten
	if arena.heroes_in_circle(_target.global_position, 240.0, 1 - hero.team, true, true).size() > 1:
		return false                         # ei diveä usean puolustajan keskelle
	return _escape_ready(hero)


func _escape_ready(hero: Hero) -> bool:
	if hero.cd.dodge <= 0.0:
		return true
	match hero.hero_id:
		"blink", "shade", "obsidian", "lance":
			return hero.cd.a1 <= 0.0 and hero._can_afford("a1")
		"tide":
			return hero.cd.a1 <= 0.0 and hero.ammo > 0
	return false


func _update_aim(hero: Hero) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		if _move.length() > 0.1:
			_aim = _move.normalized()
		return
	var to_target: Vector2 = _target.global_position - hero.global_position
	# Ennakointi: tähtää sinne minne kohde on menossa.
	var lead: Vector2 = _target.velocity * (to_target.length() / 900.0) * prediction
	_aim = (to_target + lead).normalized().rotated(_aim_err)


func _update_attack(hero: Hero, delta: float) -> void:
	_attack = false
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return
	if _reaction_left > 0.0:
		return
	if _lurk:
		return                          # väijyvä assassin ei tulita, odottaa avausta
	if hero.arena.mode == "moba":
		# Älä jatka perusiskua aggron vaihduttua, äläkä aktivoi puolustusaggroa
		# vihollissankariin ilman hyväksyttyä execute-divenä.
		if _tower_emergency(hero, hero.arena) != null \
				or _protected_nexus_danger(hero, hero.arena) != null:
			return
		if _target_is_hero() and _tower_diving(hero, hero.arena):
			return
	# HUOM: vetäytyessä botti saa puolustautua (ampua takaa-ajajaa), liike vie
	# silti poispäin — ei enää avutonta seisoskelua.
	var dist: float = hero.global_position.distance_to(_target.global_position)
	if dist > _basic_range:
		_hold_timer = 0.0
		return

	if hero.hero_id == "quill":
		# Lataa ja vapauta: pidä pohjassa hetki, sitten irti.
		_hold_pause -= delta
		if _hold_timer > 0.0:
			_hold_timer -= delta
			_attack = _hold_timer > 0.0  # kun ajastin loppuu, release-reuna syntyy
		elif _hold_pause <= 0.0:
			# Latauksen kesto skaalautuu vaikeustasolla: korkeat tasot lataavat
			# lähes täyteen (>=0.9 s), matalat ampuvat vajaalla.
			_hold_timer = randf_range(0.4, 0.7) + ability_chance * 0.4
			# Tauko latauksen JÄLKEEN on yli perushyökkäyksen cd:n, ettei uusi
			# lataus ala cd:n päällä (silloin lataus ei käynnisty -> ei ammu
			# mitään joka toinen kierros, mikä puolitti Quillin vahingon).
			_hold_pause = _hold_timer + float(hero.cd_max.basic) + 0.1
			_attack = true
	else:
		_attack = _combat_engaged(delta)


## Aggression-jaksotus: heikommat botit hyökkäävät vain osan ajasta, jolloin
## niiden tehollinen vahinko laskee eikä pelaajaa tulita jatkuvasti.
func _combat_engaged(delta: float) -> bool:
	if aggression >= 0.999:
		return true
	_atk_phase -= delta
	if _atk_phase <= 0.0:
		_atk_phase = randf_range(0.5, 1.0)
		_atk_firing = randf() < aggression
	return _atk_firing


## Kyvyt harkitaan vain päätöstahdissa, portitettuna vaikeustasolla.
func _update_abilities(hero: Hero, arena, bb: TeamBlackboard, decided: bool) -> void:
	if not decided:
		return
	if arena == null or not is_instance_valid(arena):
		return
	# Ottelun/objektiivin vaihtuessa vanha kohde voi vapautua saman fysiikkaruudun
	# Clear it before the typed hero-specific utility callback.
	if _target != null and not is_instance_valid(_target):
		_target = null
	var pos: Vector2 = hero.global_position
	var dist := 1e20
	if _target != null and is_instance_valid(_target):
		dist = pos.distance_to(_target.global_position)
	var near_enemies: int = arena.heroes_in_circle(pos, 320.0, 1 - hero.team, true, true).size()

	# Onko kohde vihollistornin alla ilman turvallista dive-syytä? Jos on, ei
	# käytetä syöksy-/hyökkäyskykyjä eikä ulttia sinne (ei tornidiveä tappoja
	# jahdaten -> bait-kuolemat loppuvat). Liike hoidetaan _moba_tower_safella.
	var diving: bool = _tower_diving(hero, arena)

	# Ultimate — arvokkain, käytetään herkemmin kaikilla vaikeustasoilla.
	if hero.ult_charge >= 100.0:
		if not diving and _want_ult(hero, arena, bb, dist, near_enemies) and randf() < ult_chance:
			_flags.ult = true
			_begin_ult_combo(hero)
			return

	# Itsesuojelu: hädässä (matala hp tai monta vihollista lähellä) pakene
	# liikkumiskyvyllä tai väistöllä. Ylemmät tasot reagoivat, alemmat eivät.
	if self_preserve > 0.05 and _in_danger(hero, arena) and randf() < self_preserve:
		if _try_escape(hero, bb):
			return

	# Scout: lataa lipas RULLAAMALLA (X) kun se on kolmanneksessa eikä ole
	# välitöntä vaaraa (rulla lataa heti; muuten 2.5 s auto-lataus kesken
	# taistelun syö perusvahingon). Perustaito -> lähes kaikilla tasoilla.
	# (Tornitilassa ammo pysyy täynnä, joten tämä ei laukea silloin turhaan.)
	if hero.hero_id == "scout" and dodge_chance > 0.05 and hero.cd.dodge <= 0.0 \
			and not hero.reloading and hero.ammo <= maxi(2, hero.ammo_max / 3) \
			and not _in_danger(hero, arena):
		_flags.dodge = true
		return

	# Junglerien X on kitin utility, ei geneerinen pakohyppy. Hahmo itse kertoo
	# milloin leiri/objective tarvitsee sen; näin botti käyttää ankkurin, dronin,
	# essenssivaihdon tai maadoituspiikin myös farmissa eikä vain paniikkiväistönä.
	if _is_jungler_role and hero.cd.dodge <= 0.0 and hero.has_method("bot_wants_utility") \
			and bool(hero.call("bot_wants_utility")) \
			and randf() < 0.35 + combo_skill * 0.6:
		_flags.dodge = true
		return

	if _lurk:
		return                          # väijyessä ei käytetä engage-kykyjä (a1/a2)

	if randf() > ability_chance:
		return

	# Tornidive-esto: älä käytä engage-/syöksykykyjä kohteeseen joka on
	# vihollistornin alla ilman omaa aaltoa (pako-a1 hoidetaan _try_escapessa yllä).
	if diving:
		_clear_combo()
		return

	# Valmis kombon jatko ohittaa tavallisen satunnaisheiton. Resurssi ja oikea
	# kantama tarkistetaan uudelleen, joten muisti ei pakota mahdotonta castia.
	if _combo_followup != "" and _combo_target == _target:
		var follow_ready: bool = hero.cd[_combo_followup] <= 0.0 \
			and hero._can_afford(_combo_followup)
		if follow_ready:
			var follow_wanted: bool = _want_a1(hero, arena, bb, dist, pos) \
				if _combo_followup == "a1" else _want_a2(hero, arena, bb, dist, pos)
			if follow_wanted:
				_flags[_combo_followup] = true
				_combo_followup = ""
				return

	var want_a1: bool = hero.cd.a1 <= 0.0 and hero._can_afford("a1") \
		and _want_a1(hero, arena, bb, dist, pos)
	var want_a2: bool = hero.cd.a2 <= 0.0 and hero._can_afford("a2") \
		and _want_a2(hero, arena, bb, dist, pos)

	# Taitava liikkuva sankari ei polta viimeistä poistumistietään aggressiiviseen
	# avaukseen, kun HP on jo matala ja väistö on jäähtymässä.
	if want_a1 and cooldown_discipline >= 0.45 and hero.cd.dodge > 0.0 \
			and hero.hp < hero.max_hp * 0.62 \
			and hero.hero_id in ["blink", "shade"]:
		want_a1 = false

	var chosen := _select_ability_slot(hero, want_a1, want_a2, dist)
	if chosen != "":
		_flags[chosen] = true
		_begin_combo(hero, chosen)


func _select_ability_slot(hero: Hero, want_a1: bool, want_a2: bool, dist: float) -> String:
	if not want_a1 and not want_a2:
		return ""
	if want_a1 and not want_a2:
		return "a1"
	if want_a2 and not want_a1:
		return "a2"
	# Alemmat tasot tuntevat käyttöehdot, mutta eivät aina valitse optimaalista
	# järjestystä. Ylemmät valitsevat sankarin oikean avaajan/jatkon.
	if randf() > combo_skill:
		return "a1" if randf() < 0.5 else "a2"
	match hero.hero_id:
		"blink":
			return "a1" if dist > 250.0 else "a2"
		"bramble":
			return "a1" if dist > 150.0 else "a2"
		"ember":
			return "a1" if dist > 210.0 else "a2"
		"volt", "shade", "scout", "salvo":
			return "a2"                 # alue/stun/shuriken/morttari avaa
		"lance", "obsidian":
			return "a1" if dist > 175.0 else "a2"
		"rift":
			return "a2"                 # pinoräjäytys on aina arvokkain kun valmis
		"kaira":
			return "a1" if dist > 175.0 else "a2"
		"vesper":
			return "a1" if _target != null and _target.mark_timer <= 0.0 else "a2"
		"myria":
			return "a1" if dist > 260.0 else "a2"
		"torq":
			return "a1" if dist > 170.0 else "a2"
		"luma", "prism", "hush":
			return "a2"                 # kiireellinen suoja/hoito ennen vahinkoa
	return "a2" if cooldown_discipline >= 0.7 else "a1"


func _begin_combo(hero: Hero, opener: String) -> void:
	if _target == null or not _target_is_hero() or randf() > combo_skill:
		return
	_combo_target = _target
	_combo_timer = 3.2
	_combo_followup = ""
	match hero.hero_id:
		"blink":
			if opener == "a1": _combo_followup = "a2"
		"bramble":
			if opener == "a1": _combo_followup = "a2"
		"volt":
			if opener == "a2": _combo_followup = "a1"
		"shade":
			if opener == "a2": _combo_followup = "a1"
		"rift":
			if opener == "a1": _combo_followup = "a1"   # merkki -> varppaus
		"lance", "obsidian":
			if opener == "a1": _combo_followup = "a2"
		"kaira", "vesper", "myria", "torq":
			if opener == "a1": _combo_followup = "a2"


func _begin_ult_combo(hero: Hero) -> void:
	if _target == null or not _target_is_hero() or randf() > combo_skill:
		return
	_combo_target = _target
	_combo_timer = 3.8
	match hero.hero_id:
		"titan":
			_combo_followup = "a1"
		"scout":
			_combo_followup = "a2"
		"shade":
			_combo_followup = "a2"
		_:
			_combo_followup = ""


func _clear_combo() -> void:
	_combo_target = null
	_combo_followup = ""
	_combo_timer = 0.0


## Onko botti hädässä. Hauraat roolit (assassin/tuki/kaukotaistelu) pakenevat
## herkemmin ja myös piiritettynä; tankit ja fighterit pitävät linjan ja
## pakenevat vain kriittisen matalalla — ne eivät hylkää etulinjaa.
func _in_danger(hero: Hero, arena) -> bool:
	if arena.mode == "moba" and (_tower_emergency(hero, arena) != null \
			or _protected_nexus_danger(hero, arena) != null):
		return true
	var archetype: String = str(HeroDef.get_def(hero.hero_id).get("archetype", ""))
	var frail: bool = not _is_tank and _role != "Fighter" and archetype != "Bruiser"
	var hp_thresh: float = 0.4 if frail else 0.25
	if hero.hp < hero.max_hp * hp_thresh:
		return true
	if frail and arena.heroes_in_circle(hero.global_position, 180.0, 1 - hero.team, true, true).size() >= 2:
		return true
	return false


## Yritä paeta vaarasta: liikkumiskyvyllä (Blink/Shade/Tide) poispäin, muuten
## väistöllä. Kääntää tähtäyksen pois, jotta syöksy/teleportti vie turvaan.
func _try_escape(hero: Hero, bb: TeamBlackboard) -> bool:
	var away := _escape_dir(hero, bb)
	if away == Vector2.ZERO:
		return false
	match hero.hero_id:
		"blink", "shade", "obsidian", "lance":
			if hero.cd.a1 <= 0.0 and hero._can_afford("a1"):
				_aim = away
				_flags.a1 = true
				return true
		"quill":
			# Quillin väistöhyppy liikkuu taaksepäin tähtäyksestä, joten tähtää
			# uhkaa kohti päästäksesi siitä poispäin.
			if hero.cd.a1 <= 0.0 and hero._can_afford("a1"):
				_aim = -away
				_flags.a1 = true
				return true
		"tide":
			if hero.cd.a1 <= 0.0 and hero.ammo > 0:
				_aim = away
				_flags.a1 = true
				return true
	if hero.cd.dodge <= 0.0:
		_move = away.limit_length(1.0)
		_flags.dodge = true
		return true
	return false


func _escape_dir(hero: Hero, bb: TeamBlackboard) -> Vector2:
	var pos: Vector2 = hero.global_position
	if hero.arena != null and hero.arena.mode == "moba":
		var tower := _tower_emergency(hero, hero.arena)
		if tower == null:
			tower = _protected_nexus_danger(hero, hero.arena)
		if tower != null:
			var home: Vector2 = hero.arena.map.spawn_point(hero.team, 0)
			var d0: Vector2 = (pos - tower.global_position).normalized() * 0.45 \
				+ (home - pos).normalized()
			if d0.length() > 0.1:
				return d0.normalized()
	if bb.threat_center != Vector2.ZERO:
		var d: Vector2 = pos - bb.threat_center
		if d.length() > 1.0:
			return d.normalized()
	if _target != null and is_instance_valid(_target):
		var d2: Vector2 = pos - _target.global_position
		if d2.length() > 1.0:
			return d2.normalized()
	return Vector2.ZERO


func _want_ult(hero: Hero, arena, bb: TeamBlackboard, dist: float, near_enemies: int) -> bool:
	var pos: Vector2 = hero.global_position
	var target_cluster := 0
	if _target != null and is_instance_valid(_target):
		target_cluster = arena.heroes_in_circle(_target.global_position, 240.0,
			1 - hero.team, true, true).size()
	match hero.hero_id:
		"bastion":
			return (hero.carrying and near_enemies >= 1) or near_enemies >= 2 \
				or (bb.own_carrier != null and pos.distance_to(bb.own_carrier.global_position) < 250.0 and near_enemies >= 1)
		"ember", "bramble":
			return near_enemies >= 2
		"blink":
			return dist < 450.0 and hero.hp > hero.max_hp * 0.4 and near_enemies >= 1
		"luma":
			var hurt := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team, true, true):
				if ally.hp < ally.max_hp * 0.6:
					hurt += 1
			return hurt >= 2 or (bb.own_carrier != null and bb.own_carrier.hp < bb.own_carrier.max_hp * 0.5)
		"quill":
			# Koko kartan läpäisevä nuoli ei vaadi vihollista Quillin vierelle.
			return _target_is_hero() and dist < 1500.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.65 \
				or _mode == Mode.ATTACK_CARRIER)
		"boulder":
			# Vyöry on pitkä linjaultti, ei lähialueulti.
			return _target_is_hero() and dist < 770.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.58)
		"tide":
			return _target_is_hero() and dist < 620.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.55 \
				or hero.carrying)
		"volt":
			return _target_is_hero() and dist < 560.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.5)
		"shade":
			return _target_is_hero() and dist < 520.0 \
				and hero.hp > hero.max_hp * 0.35
		"scout":
			return arena.heroes_in_circle(pos, 640.0, 1 - hero.team, true, true).size() >= 2
		"maestro":
			var hurt_allies := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team, true, true):
				if ally.hp < ally.max_hp * 0.6:
					hurt_allies += 1
			return hurt_allies >= 2 or near_enemies >= 3
		"prism":
			return arena.heroes_in_circle(pos, 220.0, hero.team, true, true).size() >= 2
		"rift":
			return near_enemies >= 2
		"titan":
			return dist < 380.0 and near_enemies >= 1
		"hush":
			# Maahan tähdättävä kontrollialue: käytä ryhmään kantaman päästä tai
			# pelasta kantaja yhdeltäkin päälle tulevalta viholliselta.
			var carrier_threat: bool = bb.own_carrier != null \
				and pos.distance_to(bb.own_carrier.global_position) < 560.0 \
				and arena.heroes_in_circle(bb.own_carrier.global_position, 280.0,
					1 - hero.team, true, true).size() >= 1
			return (_target_is_hero() and dist < 560.0 and target_cluster >= 2) \
				or carrier_threat
		"obsidian":
			# Ydinräjähdys: telegrafoitu latausräjähdys — laukaise kun kimpussa on
			# vihollisia (2+ lähellä tai 1 kiinni ja hyvä hp).
			return near_enemies >= 2 or (dist < 200.0 and near_enemies >= 1)
		"lance":
			# Taivaankeihäs: loikkaa kohteeseen kun se on kantamalla (ult-range ~520).
			return dist < 540.0 and (near_enemies >= 1 or _target_is_hero())
		"salvo":
			# Ohjus on pitkämatkainen ohjattava execute; lähivihollista ei vaadita.
			return _target_is_hero() and dist > 220.0 and dist < 1200.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.72)
		"kaira":
			if _target is Critter and (_target as Critter).is_major_objective():
				var contested: bool = arena.heroes_in_circle(_target.global_position, 520.0,
					1 - hero.team, true, true).size() >= 1
				return contested or _target.hp < _target.max_hp * 0.68
			return _target_is_hero() and dist < 620.0 and target_cluster >= 2
		"vesper":
			if _target is Critter and (_target as Critter).is_major_objective():
				return arena.heroes_in_circle(_target.global_position, 620.0,
					1 - hero.team, true, true).size() >= 1
			return _target_is_hero() and dist < 780.0 and target_cluster >= 2
		"myria":
			if _target is Critter and (_target as Critter).is_major_objective():
				var useful: bool = str(hero.get("selected_essence")) in ["red", "void"]
				return useful and (_target.hp < _target.max_hp * 0.62 \
					or arena.heroes_in_circle(_target.global_position, 540.0,
						1 - hero.team, true, true).size() >= 1)
			return _target_is_hero() and dist < 700.0 and target_cluster >= 2
		"torq":
			if _target is Critter and (_target as Critter).is_major_objective():
				var foe_near: int = arena.heroes_in_circle(_target.global_position, 560.0,
					1 - hero.team, true, true).size()
				var ally_near: int = arena.heroes_in_circle(_target.global_position, 420.0,
					hero.team, true, true).size()
				return foe_near >= 1 and ally_near >= 1
			return near_enemies >= 2 or (near_enemies >= 1 and hero.hp < hero.max_hp * 0.45)
	return near_enemies >= 2


func _want_a1(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return dist < 320.0 and (hero.hp < hero.max_hp * 0.82 \
				or arena.heroes_in_circle(pos, 260.0, 1 - hero.team, true, true).size() >= 2)
		"ember":
			return dist > 100.0 and dist < 520.0
		"luma":
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.75 \
				and pos.distance_to(bb.lowest_ally.global_position) < 190.0
		"blink":
			return dist > 175.0 and dist < 390.0 and _target_is_hero() \
				and _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER]
		"bramble":
			return dist > 145.0 and dist < 480.0
		"quill":
			return dist < 260.0 and _target_is_hero()
		"boulder":
			# Vaatii panoksen (muuri kuluttaa ammoa, 3 latausta) eikä hukkaa niitä
			# tiuhaan satunnaisheitolla.
			return dist > 200.0 and dist < 500.0 and hero.ammo > 0 and _target_is_hero() \
				and (hero.carrying or _mode == Mode.ESCORT or randf() < 0.2)
		"volt":
			return dist < 450.0
		"shade":
			return dist > 175.0 and dist < 390.0 and _target_is_hero()
		"tide":
			# Syöksy kuluttaa ammoa (3 latausta); säästä yksi pakoon (_try_escape).
			return dist > 250.0 and dist < 600.0 and hero.ammo > 1 \
				and (_target_is_hero() or arena.mode != "moba")
		"scout":
			# Merkkitikka (+45 % otettu vahinko) on sankarikohde -> ei minioniin.
			return dist > 200.0 and dist < 700.0 and _target_is_hero()
		"maestro":
			# ≥2 = itse + väh. 1 liittolainen (heroes_in_circle sisältää aina itsen,
			# joten pelkkä "ei tyhjä" oli aina tosi -> buffi laukesi turhaan).
			# _target_is_hero(): haste+kilpi-buffi on tiimibuffi oikeaa taistelua
			# varten -> ei tuhlata viidakko-olentoa (Critter) vastaan farmatessa.
			return _target_is_hero() and dist < 500.0 \
				and arena.heroes_in_circle(pos, 240.0, hero.team, true, true).size() >= 2
		"prism":
			return dist < 430.0
		"rift":
			# VoidMark lentää yksiköiden läpi -> vain oikeaa sankaria vastaan.
			var rift := hero as Rift
			if rift._mark_target != null and is_instance_valid(rift._mark_target) \
					and rift._mark_target.alive:
				return true                  # toinen painallus varppaa merkille
			if rift._mark_pending:
				return false                 # odota ammuksen osumaa, älä hakkaa nappia
			return dist > 190.0 and dist < 700.0 and _target_is_hero()
		"titan":
			# Tartunta ei tartu yksiköihin (torni/minioni) -> vain sankaria vastaan.
			return dist < 150.0 and _target_is_hero()
		"hush":
			# Suojasointu: kilpiää haavoittuneimman liittolaisen kantamalta.
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.8 \
				and pos.distance_to(bb.lowest_ally.global_position) < 520.0
		"obsidian":
			# Louhintaloikka: hyppää keskietäisyydeltä vihollisen niskaan.
			return dist > 165.0 and dist < 420.0 \
				and (_target_is_hero() or arena.mode != "moba")
		"lance":
			# Lävistyssyöksy: syöksy vihollisen läpi keskietäisyydeltä (merkit).
			return dist > 135.0 and dist < 365.0 \
				and (_target_is_hero() or arena.mode != "moba")
		"salvo":
			# Miina heitetään 210 px päähän: kylvä se oikeasti kulkureitille.
			return dist > 105.0 and dist < 310.0
		"kaira":
			return dist > 115.0 and dist < 560.0
		"vesper":
			return dist > 160.0 and dist < 760.0
		"myria":
			return dist < 680.0
		"torq":
			return dist < 500.0
	return false


## Onko nykyinen kohde oikea vihollissankari (ei minioni/torni/nexus/olento)?
func _target_is_hero() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.is_unit


func _want_a2(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return arena.heroes_in_circle(pos, 170.0, 1 - hero.team, true, true).size() >= 1
		"ember":
			return dist < 210.0
		"luma":
			return bb.lowest_ally != null and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.7 \
				and (bb.lowest_ally == hero \
				or pos.distance_to(bb.lowest_ally.global_position) < 520.0)
		"blink":
			return dist < 400.0
		"bramble":
			return dist < 150.0
		"quill":
			return dist > 250.0 and dist < 500.0
		"boulder":
			return arena.heroes_in_circle(pos, 190.0, 1 - hero.team, true, true).size() >= 1
		"volt":
			return dist > 120.0 and dist < 540.0
		"shade":
			return dist > 150.0 and dist < 450.0
		"tide":
			return dist < 220.0
		"scout":
			return dist < 500.0 and _target_is_hero()
		"maestro":
			return dist < 200.0
		"prism":
			# a2 ei paranna itseä -> kohteena Prisman OMA lowest (ei-itse) ja sen
			# on oltava säteellä (430), muuten säde whiffaa.
			var low: Hero = (hero as Prism)._lowest_ally()
			return low != null and low.hp < low.max_hp * 0.7 \
				and pos.distance_to(low.global_position) < 430.0
		"rift":
			# Räjäytä vain jos kohteessa on pinoja (muuten hukkaan).
			return dist < 130.0 and _target != null and is_instance_valid(_target) \
				and _target.void_stacks >= 2
		"titan":
			return hero.hp < hero.max_hp * 0.55 and hero.res > 35.0
		"hush":
			# Dissonanssikenttä (slow+DoT) heitetään lähelle vihollisia keskietäisyydeltä.
			return dist > 120.0 and dist < 430.0 and _target_is_hero()
		"obsidian":
			# Kiviho: kertakäyttöinen torjunta/heijastus kun vihollinen on lähellä.
			return dist < 220.0 and hero.res > 35.0
		"lance":
			# Pyörremyrsky: lähitaistelun AoE + vaimennus + merkit (maksaa 40 raivoa).
			return dist < 175.0 and hero.res >= 40.0
		"salvo":
			# Kaarimorttari: pitkä viive palkitsee kaukaa ennakoinnin; botti tähtää
			# nykyiseen kohteeseen oletuskantamalla kuten muut maamaalikyvyt.
			return dist > 150.0 and dist < 780.0 and _target_is_hero()
		"kaira":
			return dist < 195.0 and hero.res >= 35.0
		"vesper":
			return dist < 620.0
		"myria":
			return dist < 570.0 and hero.res >= 28.0
		"torq":
			return dist < 220.0 and hero.res >= 30.0
	return false


func _update_dodge(hero: Hero, arena, delta: float) -> void:
	_dodge_check_timer -= delta
	if _dodge_check_timer > 0.0 or hero.cd.dodge > 0.0:
		return
	_dodge_check_timer = 0.1
	# Tornilaukausta ei voi väistää, mutta dash lyhentää aikaa vaaravyöhykkeellä
	# ja katkaisee ramppauksen. Käytä sitä heti kun lukitus on pitkällä.
	if arena.mode == "moba":
		var tower := _tower_emergency(hero, arena)
		if tower != null and tower._target_lock == hero and tower._charge >= 0.5 \
				and randf() < 0.45 + tower_judgement * 0.5:
			var home: Vector2 = arena.map.spawn_point(hero.team, 0)
			_move = (home - hero.global_position).normalized()
			_flags.dodge = true
			return
	for child in arena.get_children():
		if not child is Projectile:
			continue
		if child.team == hero.team:
			continue
		var to_hero: Vector2 = hero.global_position - child.global_position
		if to_hero.length() > 220.0:
			continue
		if child.direction.dot(to_hero.normalized()) < 0.6:
			continue
		if randf() < dodge_chance:
			_flags.dodge = true
			_move = child.direction.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
		return


# --- DeviceInput-rajapinta ---

func move_vector() -> Vector2:
	return _move


func aim_vector() -> Vector2:
	return _aim


func attack_held() -> bool:
	return _attack


func attack_just_pressed() -> bool:
	return _attack and not _attack_prev


func attack_just_released() -> bool:
	return (not _attack) and _attack_prev


func ability1_just() -> bool:
	return _flags.a1


func ability2_just() -> bool:
	return _flags.a2


# Botit käyttävät välitöntä laukaisua, joten pito/vapautus eivät ole käytössä.
func ability1_held() -> bool:
	return false


func ability2_held() -> bool:
	return false


func ability1_released() -> bool:
	return false


func ability2_released() -> bool:
	return false


func ult_held() -> bool:
	return false


func ult_released() -> bool:
	return false


func dodge_just() -> bool:
	return _flags.dodge


func ult_just() -> bool:
	return _flags.ult


func drop_just() -> bool:
	return false


func is_bot() -> bool:
	return true
