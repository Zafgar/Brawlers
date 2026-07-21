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
var _is_tank := false
var _is_support := false
var _is_assassin := false
var _is_ranged := false

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
	_role = HeroDef.get_def(hero.hero_id)["role"]
	_is_tank = _role == "Tankki"
	_is_support = _role == "Tuki"
	_is_assassin = _role == "Assassin"
	_is_ranged = _role in ["Mage", "Ranger"]
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
		_:
			_pref_range = 200.0


func update(hero: Hero, delta: float) -> void:
	_hero = hero
	_time += delta
	_attack_prev = _attack
	for key in _flags:
		_flags[key] = false
	if _role == "":
		_setup_role(hero)

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
		Critter.Kind.BOSS:
			# Pomo on iso palkinto mutta vaarallinen: mene vain terveenä ja
			# mieluiten ryhmässä; korkein taso uskaltaa yksinkin.
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 420.0) >= 1
			if strong and (grouped or jungle_focus >= 0.85):
				return 260.0
			return 25.0
	return 0.0


## MOBA-päätöksenteko: lähellä oleva vihollinen -> taistele; muuten työnnä
## linjaa hyökkäämällä lähintä tuhottavissa olevaa vihollisrakennusta.
func _decide_moba(hero: Hero, arena, bb: TeamBlackboard) -> void:
	_jungle_target = null
	# PUOLUSTUS: jos oma rakennus on uhattu ja OLEN nimetty (lähin) puolustaja,
	# kääerry puolustamaan — taistele viholliset pois rakennuksen luota. Vain yksi
	# botti kerrallaan, joten koko joukkue ei hylkää linjaa.
	if bb.defender == hero and bb.threatened_structure != null \
			and is_instance_valid(bb.threatened_structure):
		_defend_pos = bb.threatened_structure.global_position
		_mode = Mode.FIGHT
		return
	if _is_support:
		_mode = Mode.SUPPORT
		return
	# Vain oikea vihollissankari laukaisee tiimitaistelun — minionit ja tornit
	# eivat (ne hoidetaan tyontologiikassa, ettei botti jaa jumiin aaltoon eika
	# hylkaa tyontoa minionin takia).
	var enemy_hero := _nearest_enemy_hero(hero, arena, 360.0)
	if enemy_hero != null:
		_mode = Mode.FIGHT
		return
	# Viidakko-objektiivi (pomo = iso tiimibuffi, leirit = buffit) jos vaikeustaso
	# tunnistaa sen ja se on arvokas & lähellä — MUUTEN työnnä linjaa. Näin
	# jungle_focus vaikuttaa vihdoin MOBAssa: matalat tasot vain työntävät,
	# korkeat kiistävät pomon ja buffit (osa botteista, ei koko joukkue kerralla).
	_jungle_target = _pick_moba_objective(hero, arena)
	if _jungle_target == null:
		_jungle_target = _pick_push_target(hero, arena)
	_mode = Mode.FIGHT


## Viidakko-objektiivin valinta MOBAssa: PAIKALLINEN (ei koko kartan yli), jottei
## botti hylkää linjaa. Pomo on iso palkinto (tiimibuffi) ja vaatii terveyden +
## ryhmän; leirit ovat opportunistisia lähibuffeja. jungle_focus (vaikeustaso)
## säätää sekä kantaman että sen uskaltaako pomon kimppuun.
func _pick_moba_objective(hero: Hero, arena) -> Hero:
	if jungle_focus < 0.05 or arena.critters.is_empty():
		return null
	var pos: Vector2 = hero.global_position
	var max_travel: float = 350.0 + jungle_focus * 700.0
	var best: Hero = null
	var best_score := 0.0
	for c in arena.critters:
		var cr := c as Critter
		if cr == null or not cr.alive:
			continue
		var d: float = pos.distance_to(cr.global_position)
		if d > max_travel:
			continue
		var val: float = _moba_objective_value(hero, cr)
		if val <= 0.0:
			continue
		var score: float = val - d * 0.12
		if score > best_score:
			best_score = score
			best = cr
	return best


func _moba_objective_value(hero: Hero, cr: Critter) -> float:
	match cr.kind:
		Critter.Kind.BOSS:
			# Iso tiimibuffi -> korkein prioriteetti, mutta vaarallinen: vain
			# terveenä ja mieluiten ryhmässä (vain korkein taso uskaltaa yksin).
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 460.0) >= 1
			if strong and (grouped or jungle_focus >= 0.85):
				return 300.0
			return 0.0
		Critter.Kind.DAMAGE_CAMP:
			return 110.0 if hero.hp > hero.max_hp * 0.5 else 0.0   # opportunistinen buffi
		Critter.Kind.POINTS_CAMP:
			return 60.0   # pisteet vain 3. tason tiebreak -> matala prioriteetti
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
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Lähin vihollisminioni max_dist päässä (vihollisaallon siivoamiseen).
func _nearest_enemy_minion(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for e in arena.alive_enemies(hero.team):
		if not (e is Minion):
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
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


## MOBA-työnnön kohteenvalinta: vihollissankari lähellä -> taistele; muuten
## siivoa vihollisaalto (jotta oma aalto crashaa tornille); muuten lyö rakennus.
func _moba_push_target(hero: Hero, arena) -> Hero:
	var enemy_hero := _nearest_enemy_hero(hero, arena, 280.0)
	if enemy_hero != null:
		return enemy_hero
	var minion := _nearest_enemy_minion(hero, arena, 360.0)
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
		pick = _nearest_attackable(enemies, pos)

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
		var d: float = a.global_position.distance_to(aim_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


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
			return arena.map.spawn_point(hero.team, 0)   # ei reliikkiä (0,0) MOBAssa
		return arena.relic.global_position

	var dist: float = pos.distance_to(_target.global_position)
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
	# MOBA: älä astu vihollistornin kantamalle ilman omaa aaltoa — riippumatta
	# siitä onko kohde torni vai sitä vartioiva minioni (torni ampuu minioneja
	# ensin, joten oman aallon on annettava crashata). Kaukotaistelijat ohitetaan.
	return _moba_tower_safe(hero, arena, pos, goal)


## Leikkaa maalipisteen niin ettei lähi/keskimatkan botti mene vihollistornin
## kantamalle ilman omaa aaltoa. Iteroi kaikki viholliset tornit; jos maali osuu
## suojaamattoman (ei omia minioneja lähellä) tornin kantamaan, työntää maalin
## juuri kantaman rajalle. Kaukotaistelijat (pref_range >= raja) eivät koske.
func _moba_tower_safe(hero: Hero, arena, pos: Vector2, goal: Vector2) -> Vector2:
	if arena.mode != "moba":
		return goal
	var tower_hold: float = Structure.SHOT_RANGE + 60.0
	var skip_towers: bool = _pref_range >= tower_hold   # kaukotaistelija ampuu ulkoa
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
			var nhold: float = Structure.NEXUS_LASER_RANGE + 60.0
			if out.distance_to(s.global_position) >= nhold:
				continue
			var naway: Vector2 = out - s.global_position
			if naway.length() < 1.0:
				naway = pos - s.global_position
			if naway.length() < 1.0:
				naway = Vector2.LEFT
			out = s.global_position + naway.normalized() * nhold
			continue
		if skip_towers or out.distance_to(s.global_position) >= tower_hold:
			continue
		# Dive on sallittua VAIN jos: torni ei tähtää juuri minuun, olen terve JA
		# vahva oma aalto (>=2 minionia) imee tornin. Muuten pysy kantaman ulkona
		# -> ei turhaa tornitappelua (tätä tapahtui liikaa). Aiemmin jo 1 minioni
		# + mikä tahansa HP riitti, mikä salli jatkuvan tornin alla oleilun.
		var tower_on_me: bool = s._target_lock == hero
		var healthy: bool = hero.hp > hero.max_hp * 0.5
		var wave: int = _own_minions_near(hero, arena, s.global_position, 340.0)
		if not tower_on_me and healthy and wave >= 2:
			continue
		var away: Vector2 = out - s.global_position
		if away.length() < 1.0:
			away = pos - s.global_position
		if away.length() < 1.0:
			away = Vector2.LEFT
		out = s.global_position + away.normalized() * tower_hold
	return out


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
	# HUOM: vetäytyessä botti saa puolustautua (ampua takaa-ajajaa), liike vie
	# silti poispäin — ei enää avutonta seisoskelua.
	var dist: float = hero.global_position.distance_to(_target.global_position)
	var attack_range := _pref_range + 120.0
	if _is_tank or _role == "Fighter" or _is_assassin:
		attack_range = 150.0
	if dist > attack_range:
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
	var pos: Vector2 = hero.global_position
	var dist := 1e20
	if _target != null and is_instance_valid(_target):
		dist = pos.distance_to(_target.global_position)
	var near_enemies: int = arena.heroes_in_circle(pos, 320.0, 1 - hero.team, true, true).size()

	# Ultimate — arvokkain, käytetään herkemmin kaikilla vaikeustasoilla.
	if hero.ult_charge >= 100.0:
		if _want_ult(hero, arena, bb, dist, near_enemies) and randf() < ult_chance:
			_flags.ult = true
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

	if _lurk:
		return                          # väijyessä ei käytetä engage-kykyjä (a1/a2)

	if randf() > ability_chance:
		return

	if hero.cd.a1 <= 0.0:
		_flags.a1 = _want_a1(hero, arena, bb, dist, pos)
	if hero.cd.a2 <= 0.0:
		_flags.a2 = _want_a2(hero, arena, bb, dist, pos)


## Onko botti hädässä. Hauraat roolit (assassin/tuki/kaukotaistelu) pakenevat
## herkemmin ja myös piiritettynä; tankit ja fighterit pitävät linjan ja
## pakenevat vain kriittisen matalalla — ne eivät hylkää etulinjaa.
func _in_danger(hero: Hero, arena) -> bool:
	var frail: bool = not _is_tank and _role != "Fighter"
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
		"blink", "shade":
			if hero.cd.a1 <= 0.0 and hero._can_afford("a1"):
				_aim = away
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
			return dist < 1000.0 and near_enemies >= 1
		"boulder", "tide":
			return near_enemies >= 2 or (hero.carrying and near_enemies >= 1)
		"volt":
			return near_enemies >= 2 or (dist < 400.0 and near_enemies >= 1)
		"shade":
			return dist < 350.0 and hero.hp > hero.max_hp * 0.35 and near_enemies >= 1
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
			# Suuri Vaimennus on itsekeskinen alue-lukitus: laukaise kun 2+
			# vihollista on lähellä (ult-säde 260).
			return arena.heroes_in_circle(pos, 260.0, 1 - hero.team, true, true).size() >= 2
		"obsidian":
			# Ydinräjähdys: telegrafoitu latausräjähdys — laukaise kun kimpussa on
			# vihollisia (2+ lähellä tai 1 kiinni ja hyvä hp).
			return near_enemies >= 2 or (dist < 200.0 and near_enemies >= 1)
		"lance":
			# Taivaankeihäs: loikkaa kohteeseen kun se on kantamalla (ult-range ~520).
			return dist < 540.0 and (near_enemies >= 1 or _target_is_hero())
		"salvo":
			# Ohjusisku: laukaise kun vihollisia on lähistöllä (ohjus ohjautuu niitä kohti).
			return near_enemies >= 1 or dist < 520.0
	return near_enemies >= 2


func _want_a1(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return dist < 260.0
		"ember":
			return dist > 120.0 and dist < 420.0   # tuliallas lentää ~360px -> ei jää lyhyeen
		"luma":
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.75 \
				and pos.distance_to(bb.lowest_ally.global_position) < 190.0
		"blink":
			return dist > 250.0 and dist < 500.0 and _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER]
		"bramble":
			return dist > 150.0 and dist < 600.0
		"quill":
			return dist < 260.0
		"boulder":
			# Vaatii panoksen (muuri kuluttaa ammoa, 3 latausta) eikä hukkaa niitä
			# tiuhaan satunnaisheitolla.
			return dist > 200.0 and dist < 500.0 and hero.ammo > 0 \
				and (hero.carrying or _mode == Mode.ESCORT or randf() < 0.2)
		"volt":
			return dist < 450.0
		"shade":
			return dist > 150.0 and dist < 420.0
		"tide":
			# Syöksy kuluttaa ammoa (3 latausta); säästä yksi pakoon (_try_escape).
			return dist > 250.0 and dist < 600.0 and hero.ammo > 1
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
			return dist > 220.0 and dist < 700.0 and _target_is_hero()
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
			return dist > 160.0 and dist < 560.0
		"lance":
			# Lävistyssyöksy: syöksy vihollisen läpi keskietäisyydeltä (merkit).
			return dist > 120.0 and dist < 460.0
		"salvo":
			# Miina: kylvä miinoja vihollisen suuntaan keskietäisyydeltä.
			return dist > 100.0 and dist < 450.0
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
			return bb.lowest_ally != null and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.7
		"blink":
			return dist < 400.0
		"bramble":
			return dist < 150.0
		"quill":
			return dist > 250.0 and dist < 500.0
		"boulder":
			return arena.heroes_in_circle(pos, 190.0, 1 - hero.team, true, true).size() >= 1
		"volt":
			return dist > 150.0 and dist < 400.0   # kenttä lentää 260px + r130
		"shade":
			return dist > 150.0 and dist < 450.0
		"tide":
			return dist < 220.0
		"scout":
			return dist < 500.0
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
			# Räjäytä kaikki: kun miinoja on kentällä ja vihollinen lähellä niitä.
			return dist < 320.0 and (hero as Salvo)._mines.size() >= 2
	return false


func _update_dodge(hero: Hero, arena, delta: float) -> void:
	_dodge_check_timer -= delta
	if _dodge_check_timer > 0.0 or hero.cd.dodge > 0.0:
		return
	_dodge_check_timer = 0.1
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
