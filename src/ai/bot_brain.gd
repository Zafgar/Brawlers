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
var _atk_phase := 0.0            # hyökkäyksen jaksotus (aggression-vaihtelu)
var _atk_firing := true

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
	reaction = reactions[level]
	aim_error_deg = aims[level]
	decision_interval = decisions[level]
	dodge_chance = dodges[level]
	ability_chance = abilities[level]
	prediction = predicts[level]
	aggression = aggros[level]
	buff_focus = focuses[level]
	buff_deny = denies[level]
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
	_update_movement(hero, arena, bb, delta)
	_update_aim(hero)
	_update_attack(hero, delta)
	_update_abilities(hero, arena, bb, decided)
	_update_dodge(hero, arena, delta)


## Valitsee toimintatilan roolin ja tilanteen mukaan.
func _decide(hero: Hero, arena, bb: TeamBlackboard) -> void:
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
	if _mode == Mode.RETREAT and hero.hp < hero.max_hp * 0.6:
		return  # jatka vetäytymistä kunnes palautunut

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


## Kohteenvalinta roolin mukaan.
func _update_target(hero: Hero, arena, bb: TeamBlackboard) -> void:
	var enemies: Array = arena.alive_enemies(hero.team)
	if enemies.is_empty():
		_target = null
		return

	var pos: Vector2 = hero.global_position
	var pick: Hero = null

	if _mode == Mode.ATTACK_CARRIER and bb.enemy_carrier != null \
			and is_instance_valid(bb.enemy_carrier):
		pick = bb.enemy_carrier
	elif _is_assassin:
		# Assassinit suosivat heikkoja takalinjan sankareita.
		var best_score := -1e20
		for enemy in enemies:
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
			pick = _nearest(enemies, pos)
	else:
		# Tankki suojaa: jos joku uhkaa suojeltavaa, käännytään sitä vastaan.
		if _is_tank and bb.protect_ally != null and bb.protect_ally != hero:
			var threat := _nearest_to(enemies, bb.protect_ally.global_position, 240.0)
			if threat != null:
				pick = threat
		if pick == null:
			pick = _nearest(enemies, pos)

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


func _update_movement(hero: Hero, arena, bb: TeamBlackboard, _delta: float) -> void:
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
			goal = bb.retreat_pos
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

	# Esteenväistö: säde eteenpäin, käännä jos seinä.
	if desired.length() > 0.1:
		var space := hero.get_world_2d().direct_space_state
		var check := PhysicsRayQueryParameters2D.create(pos, pos + desired * 160.0, 1)
		if not space.intersect_ray(check).is_empty():
			var left: Vector2 = desired.rotated(-0.8)
			var right: Vector2 = desired.rotated(0.8)
			var left_check := PhysicsRayQueryParameters2D.create(pos, pos + left * 160.0, 1)
			desired = left if space.intersect_ray(left_check).is_empty() else right

	# Erottelu: ei tungeta liittolaisen päälle.
	for ally in arena.alive_allies(hero.team):
		if ally == hero:
			continue
		var diff: Vector2 = pos - ally.global_position
		if diff.length() < 70.0 and diff.length() > 0.01:
			desired += diff.normalized() * 0.6

	_move = desired.limit_length(1.0)


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
	return goal


## Taisteluasemointi: lähesty kohdetta roolin ihannematkalle. Tankki peelaa.
func _combat_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	# Tankin peel: jos vihollinen uhkaa suojeltavaa, asetu väliin.
	if _is_tank and bb.protect_ally != null and bb.protect_ally != hero \
			and _target != null and is_instance_valid(_target):
		var pd: float = _target.global_position.distance_to(bb.protect_ally.global_position)
		if pd < 220.0:
			return bb.protect_ally.global_position \
				+ (_target.global_position - bb.protect_ally.global_position).normalized() * 60.0

	if _target == null or not is_instance_valid(_target):
		if bb.own_carrier != null and is_instance_valid(bb.own_carrier):
			return bb.own_carrier.global_position
		return arena.relic.global_position

	var dist: float = pos.distance_to(_target.global_position)
	var to_target: Vector2 = (_target.global_position - pos).normalized()
	if dist > _pref_range + 40.0:
		return _target.global_position - to_target * _pref_range
	elif dist < _pref_range - 60.0:
		# Liian lähellä (etenkin kaukotaistelijat): peräänny.
		return pos - to_target * 120.0
	return pos


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
	if _reaction_left > 0.0 or _mode == Mode.RETREAT:
		return
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
			_hold_timer = randf_range(0.4, 1.0)
			_hold_pause = _hold_timer + 0.25
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
	var near_enemies: int = arena.heroes_in_circle(pos, 320.0, 1 - hero.team).size()

	# Ultimate — arvokkain, käytetään herkemmin kaikilla vaikeustasoilla.
	if hero.ult_charge >= 100.0:
		if _want_ult(hero, arena, bb, dist, near_enemies) and randf() < ult_chance:
			_flags.ult = true
			return

	if randf() > ability_chance:
		return

	if hero.cd.a1 <= 0.0:
		_flags.a1 = _want_a1(hero, arena, bb, dist, pos)
	if hero.cd.a2 <= 0.0:
		_flags.a2 = _want_a2(hero, arena, bb, dist, pos)


func _want_ult(hero: Hero, arena, bb: TeamBlackboard, dist: float, near_enemies: int) -> bool:
	var pos: Vector2 = hero.global_position
	match hero.hero_id:
		"bastion":
			return (hero.carrying and near_enemies >= 1) or near_enemies >= 2 \
				or (bb.own_carrier != null and pos.distance_to(bb.own_carrier.global_position) < 250.0 and near_enemies >= 1)
		"ember", "bramble":
			return near_enemies >= 2
		"blink":
			return dist < 450.0 and hero.hp > hero.max_hp * 0.4
		"luma":
			var hurt := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team):
				if ally.hp < ally.max_hp * 0.6:
					hurt += 1
			return hurt >= 2 or (bb.own_carrier != null and bb.own_carrier.hp < bb.own_carrier.max_hp * 0.5)
		"quill":
			return dist < 700.0 and near_enemies >= 1
		"boulder", "tide":
			return near_enemies >= 2 or (hero.carrying and near_enemies >= 1)
		"volt":
			return near_enemies >= 2 or (dist < 400.0 and near_enemies >= 1)
		"shade":
			return dist < 350.0 and hero.hp > hero.max_hp * 0.35
		"scout":
			return arena.heroes_in_circle(pos, 640.0, 1 - hero.team).size() >= 2
		"maestro":
			var hurt_allies := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team):
				if ally.hp < ally.max_hp * 0.6:
					hurt_allies += 1
			return hurt_allies >= 2 or near_enemies >= 3
		"prism":
			return arena.heroes_in_circle(pos, 220.0, hero.team).size() >= 2
		"rift":
			return near_enemies >= 2
		"titan":
			return dist < 380.0 and near_enemies >= 1
	return near_enemies >= 2


func _want_a1(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return dist < 260.0
		"ember":
			return dist > 180.0 and dist < 620.0
		"luma":
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.75 \
				and pos.distance_to(bb.lowest_ally.global_position) < 190.0
		"blink":
			return dist > 250.0 and dist < 500.0 and _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER]
		"bramble":
			return dist > 150.0 and dist < 600.0
		"quill":
			return dist > 300.0 and dist < 900.0
		"boulder":
			return dist > 200.0 and dist < 500.0 and (hero.carrying or _mode == Mode.ESCORT or randf() < 0.4)
		"volt":
			return dist < 450.0
		"shade":
			return hero.hp < hero.max_hp * 0.5 and dist < 320.0
		"tide":
			return dist > 250.0 and dist < 600.0
		"scout":
			return dist > 200.0 and dist < 700.0
		"maestro":
			return dist < 500.0 and not arena.heroes_in_circle(pos, 240.0, hero.team).is_empty()
		"prism":
			return dist < 430.0
		"rift":
			return dist > 220.0 and dist < 700.0
		"titan":
			return dist < 150.0
	return false


func _want_a2(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return arena.heroes_in_circle(pos, 170.0, 1 - hero.team).size() >= 1
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
			return arena.heroes_in_circle(pos, 190.0, 1 - hero.team).size() >= 1
		"volt":
			return dist > 150.0 and dist < 450.0
		"shade":
			return dist > 150.0 and dist < 450.0
		"tide":
			return dist < 220.0
		"scout":
			return dist < 500.0
		"maestro":
			return dist < 200.0
		"prism":
			return bb.lowest_ally != null and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.7
		"rift":
			return dist < 130.0
		"titan":
			return hero.hp < hero.max_hp * 0.55 and hero.res > 35.0
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
