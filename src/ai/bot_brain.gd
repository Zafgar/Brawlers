class_name BotBrain
extends RefCounted
## Botin aivot. Toteuttaa täsmälleen saman rajapinnan kuin DeviceInput,
## joten Hero ei erota bottia ihmisestä. Päätökset tehdään utility-
## arvioinnilla ja joukkueen TeamBlackboard-tilannekuvalla.
##
## Vaikeustaso EI muuta vahinkoa tai kestoa — vain reaktioaikaa,
## tähtäysvirhettä, ennakointia, väistämistä ja kykyjen käyttöä.

enum Mode { GET_RELIC, ATTACK_CARRIER, ESCORT, CARRY, RETREAT, FIGHT, SUPPORT }

const MELEE_HEROES := ["bastion", "blink", "bramble"]

var level := 1

# Vaikeustasoparametrit
var reaction := 0.28
var aim_error_deg := 9.0
var decision_interval := 0.4
var dodge_chance := 0.35
var ability_chance := 0.6
var prediction := 0.5

var _hero: Hero = null
var _mode: int = Mode.FIGHT
var _target: Hero = null
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

# Quillin lataus-ammunta
var _hold_timer := 0.0
var _hold_pause := 0.0


func _init(p_level: int) -> void:
	level = p_level
	if level == Game.BotLevel.EASY:
		reaction = 0.45
		aim_error_deg = 16.0
		decision_interval = 0.6
		dodge_chance = 0.10
		ability_chance = 0.35
		prediction = 0.0
	elif level == Game.BotLevel.HARD:
		reaction = 0.14
		aim_error_deg = 4.0
		decision_interval = 0.25
		dodge_chance = 0.70
		ability_chance = 0.85
		prediction = 0.9
	else:
		reaction = 0.28
		aim_error_deg = 9.0
		decision_interval = 0.4
		dodge_chance = 0.35
		ability_chance = 0.6
		prediction = 0.5


func update(hero: Hero, delta: float) -> void:
	_hero = hero
	_time += delta
	_attack_prev = _attack
	for key in _flags:
		_flags[key] = false

	var arena = hero.arena
	var bb: TeamBlackboard = arena.blackboard(hero.team)

	_reaction_left = maxf(_reaction_left - delta, 0.0)
	_aim_err_timer -= delta
	if _aim_err_timer <= 0.0:
		_aim_err_timer = 0.3
		_aim_err = deg_to_rad(randf_range(-aim_error_deg, aim_error_deg))

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = decision_interval
		_decide(hero, arena, bb)

	_update_target(hero, arena)
	_update_movement(hero, arena, bb, delta)
	_update_aim(hero)
	_update_attack(hero, delta)
	_update_abilities(hero, arena, bb)
	_update_dodge(hero, arena, delta)


## Utility-arviointi: mikä toimintatila on nyt arvokkain.
func _decide(hero: Hero, arena, bb: TeamBlackboard) -> void:
	if hero.carrying:
		_mode = Mode.CARRY
		return
	if hero.hp < hero.max_hp * 0.3:
		_mode = Mode.RETREAT
		return
	if _mode == Mode.RETREAT and hero.hp < hero.max_hp * 0.55:
		return  # jatka vetäytymistä kunnes palautunut

	# Luma tukee, jos joku on pulassa.
	if hero.hero_id == "luma" and bb.lowest_ally != null and bb.lowest_ally != hero:
		if bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.6:
			_mode = Mode.SUPPORT
			return

	if arena.relic.is_free():
		# Lähin oman joukkueen jäsen hakee reliikin, muut taistelevat.
		var my_dist: float = hero.global_position.distance_to(arena.relic.global_position)
		var closest := true
		for ally in arena.alive_allies(hero.team):
			if ally == hero:
				continue
			if ally.global_position.distance_to(arena.relic.global_position) < my_dist - 40.0:
				closest = false
				break
		_mode = Mode.GET_RELIC if closest or randf() < 0.25 else Mode.FIGHT
		return

	if bb.enemy_carrier != null:
		_mode = Mode.ATTACK_CARRIER
		return
	if bb.own_carrier != null:
		_mode = Mode.ESCORT
		return
	_mode = Mode.FIGHT


func _update_target(hero: Hero, arena) -> void:
	var nearest: Hero = null
	var best := 999999.0
	for enemy in arena.alive_enemies(hero.team):
		var d: float = enemy.global_position.distance_to(hero.global_position)
		if d < best:
			best = d
			nearest = enemy
	if _mode == Mode.ATTACK_CARRIER:
		var bb: TeamBlackboard = arena.blackboard(hero.team)
		if bb.enemy_carrier != null:
			nearest = bb.enemy_carrier
	if nearest != _target:
		_target = nearest
		_reaction_left = reaction


func _update_movement(hero: Hero, arena, bb: TeamBlackboard, _delta: float) -> void:
	var pos: Vector2 = hero.global_position
	var goal := pos

	match _mode:
		Mode.GET_RELIC:
			goal = arena.relic.global_position
		Mode.ATTACK_CARRIER:
			if _target != null and is_instance_valid(_target):
				goal = _target.global_position
		Mode.ESCORT:
			if bb.own_carrier != null:
				var toward_threat := Vector2.ZERO
				if bb.threat_center != Vector2.ZERO:
					toward_threat = (bb.threat_center - bb.own_carrier.global_position).normalized() * 200.0
				goal = bb.own_carrier.global_position + toward_threat
		Mode.CARRY:
			# Pakoile lähintä vihollista, pysy pelialueen keskiosissa.
			var flee := Vector2.ZERO
			if _target != null and is_instance_valid(_target):
				var away: Vector2 = pos - _target.global_position
				if away.length() < 420.0:
					flee = away.normalized() * 300.0
			var orbit: Vector2 = (pos - Vector2.ZERO).orthogonal().normalized() * 120.0 * _strafe_dir
			goal = arena.map.clamp_to_field(pos + flee + orbit, 160.0)
			if flee == Vector2.ZERO:
				goal = arena.map.clamp_to_field(pos + orbit, 160.0)
		Mode.RETREAT:
			goal = bb.retreat_pos
		Mode.SUPPORT:
			if bb.lowest_ally != null:
				goal = bb.lowest_ally.global_position + \
					(pos - bb.lowest_ally.global_position).normalized() * 130.0
		Mode.FIGHT:
			if _target != null and is_instance_valid(_target):
				var dist: float = pos.distance_to(_target.global_position)
				var preferred := 90.0 if hero.hero_id in MELEE_HEROES else 380.0
				var to_target: Vector2 = (_target.global_position - pos).normalized()
				if dist > preferred + 40.0:
					goal = _target.global_position - to_target * preferred
				elif dist < preferred - 60.0:
					goal = pos - to_target * 120.0
				else:
					goal = pos
			else:
				goal = arena.relic.global_position

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
	var in_range: bool = dist < (130.0 if hero.hero_id in MELEE_HEROES else 550.0)
	if not in_range:
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
		_attack = true


func _update_abilities(hero: Hero, arena, bb: TeamBlackboard) -> void:
	# Kykyjä harkitaan vain päätöstahdissa, portitettuna vaikeustasolla.
	if _decision_timer > decision_interval - 0.05 and randf() > ability_chance:
		return
	var pos: Vector2 = hero.global_position
	var dist := 999999.0
	if _target != null and is_instance_valid(_target):
		dist = pos.distance_to(_target.global_position)

	var near_enemies: int = arena.heroes_in_circle(pos, 320.0, 1 - hero.team).size()

	# Ultimate
	if hero.ult_charge >= 100.0:
		var use_ult := false
		match hero.hero_id:
			"bastion":
				use_ult = (hero.carrying and near_enemies >= 1) or near_enemies >= 2 \
					or (bb.own_carrier != null and pos.distance_to(bb.own_carrier.global_position) < 250.0 and near_enemies >= 1)
			"ember", "bramble":
				use_ult = near_enemies >= 2
			"blink":
				use_ult = dist < 450.0 and hero.hp > hero.max_hp * 0.4
			"luma":
				var hurt := 0
				for ally in arena.heroes_in_circle(pos, 300.0, hero.team):
					if ally.hp < ally.max_hp * 0.6:
						hurt += 1
				use_ult = hurt >= 2 or (bb.own_carrier != null and bb.own_carrier.hp < bb.own_carrier.max_hp * 0.5)
			"quill":
				use_ult = dist < 700.0 and near_enemies >= 1
			_:
				use_ult = near_enemies >= 2
		if use_ult:
			_flags.ult = true
			return

	# Kyky 1
	if hero.cd.a1 <= 0.0:
		match hero.hero_id:
			"bastion":
				_flags.a1 = dist < 260.0
			"ember":
				_flags.a1 = dist > 180.0 and dist < 620.0
			"luma":
				_flags.a1 = bb.lowest_ally != null \
					and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.75 \
					and pos.distance_to(bb.lowest_ally.global_position) < 190.0
			"blink":
				_flags.a1 = dist > 250.0 and dist < 500.0 and _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER]
			"bramble":
				_flags.a1 = dist > 150.0 and dist < 600.0
			"quill":
				_flags.a1 = dist > 300.0 and dist < 900.0

	# Kyky 2
	if hero.cd.a2 <= 0.0:
		match hero.hero_id:
			"bastion":
				_flags.a2 = arena.heroes_in_circle(pos, 170.0, 1 - hero.team).size() >= 1
			"ember":
				_flags.a2 = dist < 210.0
			"luma":
				_flags.a2 = bb.lowest_ally != null \
					and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.7
			"blink":
				_flags.a2 = dist < 400.0
			"bramble":
				_flags.a2 = dist < 150.0
			"quill":
				_flags.a2 = dist > 250.0 and dist < 500.0


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


func dodge_just() -> bool:
	return _flags.dodge


func ult_just() -> bool:
	return _flags.ult


func drop_just() -> bool:
	return false


func is_bot() -> bool:
	return true
