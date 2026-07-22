class_name Boulder
extends Hero
## Tankki: kivihansikkaat. Rakentaa muureja ja jyrää esteiden läpi.
## Passiivi: lähes immuuni tönäisyille.

const PUNCH_RANGE := 95.0
const PUNCH_ARC_DEG := 60.0
const PUNCH_DMG := 14.0

const WALL_CHARGES := 3             # muureja varastossa yhtä aikaa
const WALL_RECHARGE := 6.0          # yhden muurin palautuminen
const WALL_HP := 90.0               # muurin oma kesto-hp
const WALL_LIFETIME := 8.0          # muuri kestää pitkään

const SPIKE_WAVES := 4              # piikkikartion aaltojen määrä
const SPIKE_DMG := 11.0
const SPIKE_KB := 400.0

const ROLL_SPEED := 1250.0
const ROLL_DUR := 0.62
const ROLL_RANGE := ROLL_SPEED * ROLL_DUR
const ROLL_HALF_WIDTH := 58.0
const ROLL_DMG := 35.0
const ROLL_STUN := 0.45

var _rolling := 0.0
var _roll_hit: Array = []
var _roll_dir := Vector2.RIGHT
var _wall_drop := 0.0               # ultin seinäjäljen ajastin
var _wall_recharge := 0.0           # muurilatausten palautusajastin

func _init() -> void:
	kb_resist = 0.7
	radius = 31.0


## Kivimuuri tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 150.0


## Voi tähdätä muurin vain jos latauksia on jäljellä.
func _aim_begin(_slot: String) -> bool:
	return ammo > 0


## Raivo: kertyy taistelusta ja purkautuu Piikkikartioon (a2). Kivimuuri (a1)
## on irti raivosta: sillä on 3 latausta (voi käyttää vaikka kaikki heti), ja
## lataukset palautuvat yksitellen hitaasti. Muureilla on oma kesto-hp.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost = {"basic": 0.0, "a1": 0.0, "a2": 35.0, "dodge": 0.0}
	cd_max.a1 = 0.3                # lyhyt käyttöväli muurien välillä
	cd_max.a2 = 5.0
	ammo_max = WALL_CHARGES
	ammo = WALL_CHARGES


## Perushyökkäys: raskas murskaava isku.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("slam", 0.1, -4.0)
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > PUNCH_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > PUNCH_ARC_DEG:
			continue
		deal_damage_to(enemy, PUNCH_DMG, 320.0, to_enemy.normalized())
		hits += 1
	if hits > 0:
		arena.shake(0.15)
		Fx.spark(arena, global_position + dir * PUNCH_RANGE * 0.7, Color("9aa3ad"))


## Kyky 1: Kivimuuri — kestävä muuri tähtäyssuuntaan. Käyttää muurilatauksia
## (max 3) raivon sijaan; muurilla on oma kesto-hp ja pitkä kesto.
func _ability1(dir: Vector2) -> void:
	if ammo <= 0:
		return
	if ammo >= ammo_max:
		_wall_recharge = WALL_RECHARGE
	ammo -= 1
	AudioMgr.play("rock")
	arena.shake(0.2)
	var wall := RockWall.new()
	wall.owner_team = team
	wall.hp = WALL_HP
	wall.max_hp = WALL_HP
	wall.lifetime = WALL_LIFETIME
	var pos: Vector2 = arena.map.clamp_to_field(global_position + dir * 130.0, 60.0)
	wall.global_position = pos
	wall.rotation = dir.angle() + PI / 2.0
	arena.add_child(wall)
	Fx.dust(arena, pos)
	Fx.ring(arena, pos, Palette.with_alpha(Color("9aa3ad"), 0.7), 90.0, 0.4, 4.0)


## Kyky 2: Piikkikartio — iskee neljä piikkiaaltoa eteenpäin kartioon. Jokainen
## aalto etenee kauemmas ja levenee, työntää kohteet poispäin ja juurruttaa
## hetkeksi (estää liikkeen aallon läpi).
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("rock", 0.1, -2.0)
	visual.squash(1.2, 0.8)
	_spike_cone(dir)


func _spike_cone(dir: Vector2) -> void:
	var perp: Vector2 = dir.orthogonal().normalized()
	for wave in range(SPIKE_WAVES):
		if not is_inside_tree() or not alive:
			return
		var dist: float = 75.0 + wave * 68.0
		var half_w: float = 42.0 + wave * 30.0
		var center: Vector2 = global_position + dir * dist
		AudioMgr.play("rock", 0.12, 1.0 + wave * 0.6)
		arena.shake(0.14)
		Fx.dust(arena, center)
		# Piikkirivi kartion poikki
		for s in range(-2, 3):
			Fx.spark(arena, center + perp * (s * half_w * 0.45), Color("8a7a5a"))
		Fx.ring(arena, center, Palette.with_alpha(Color("9aa3ad"), 0.6), half_w, 0.3, 4.0)
		for enemy in arena.alive_enemies(team):
			var to: Vector2 = enemy.global_position - global_position
			var along: float = to.dot(dir)
			if along < dist - 48.0 or along > dist + 48.0:
				continue
			if (to - dir * along).length() > half_w + enemy.radius:
				continue
			deal_damage_to(enemy, SPIKE_DMG, SPIKE_KB, dir)   # työntö poispäin
			var _rb: float = enemy.root_timer
			enemy.root_timer = maxf(enemy.root_timer, 0.3)     # estää liikkeen hetkeksi (hiljainen)
			enemy._record_cc("root", enemy.root_timer - _rb)   # kirjaa CC telemetriaan
		await get_tree().create_timer(0.11).timeout


## Väistö: raskas loikka.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 760.0, 0.22, false)
	AudioMgr.play("dash", 0.1, -3.0)
	Fx.dust(arena, global_position)


## Ultimate: Vyöry — vyöryy voimalla tähtäyssuuntaan kaataen viholliset ja
## jättää kiviseinän matkan varrelle, joka kestää hetken ennen murenemistaan.
func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return ROLL_RANGE


func _ult_preview_width() -> float:
	return ROLL_HALF_WIDTH


func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir if dir.length() > 0.1 else aim
	arena.popup(global_position + Vector2(0, -84), "VYÖRY!", Palette.glow(hero_color(), 1.5), 26)
	arena.shake(0.5)
	AudioMgr.play("boulder_ult", 0.05, -2.0, global_position)
	controller_rumble(0.45, 0.85, 0.55)
	_roll_dir = d
	_rolling = ROLL_DUR
	_roll_hit.clear()
	_wall_drop = 0.0
	dash(d, ROLL_SPEED, ROLL_DUR, false, true)
	iframes = maxf(iframes, ROLL_DUR)


func _passive_update(delta: float) -> void:
	# Muurilatausten palautus yksitellen.
	if ammo < ammo_max:
		_wall_recharge -= delta
		if _wall_recharge <= 0.0:
			ammo += 1
			_wall_recharge = WALL_RECHARGE

	if _rolling <= 0.0:
		return
	var was_rolling := _rolling
	_rolling = maxf(_rolling - delta, 0.0)
	Fx.dust(arena, global_position)
	Fx.spark(arena, global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
		Color("9aa3ad"))
	# Kiviseinä matkan varrelle (jätetään taakse, ettei törmää itseensä).
	_wall_drop -= delta
	if _wall_drop <= 0.0:
		_wall_drop = 0.22
		_drop_trail_wall()
	for enemy in arena.heroes_in_circle(global_position, radius + 30.0):
		if enemy.team == team or enemy in _roll_hit:
			continue
		_roll_hit.append(enemy)
		deal_damage_to(enemy, ROLL_DMG, 620.0, _roll_dir)
		enemy.apply_stun(ROLL_STUN)
		arena.shake(0.2)
	if _rolling <= 0.0 and was_rolling > 0.0:
		_roll_finish()


func _roll_finish() -> void:
	_act("ult")
	AudioMgr.play("slam", 0.05, -3.0, global_position)
	arena.shake(0.5)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.45), 105.0, 0.38)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.55), 155.0, 0.48, 9.0)
	Fx.burst(arena, global_position, Color("9aa3ad"), 22, 360.0, 0.55, 7.0)
	for enemy in arena.heroes_in_circle(global_position, 155.0):
		if enemy.team == team or enemy in _roll_hit:
			continue
		var away: Vector2 = (enemy.global_position - global_position).normalized()
		deal_damage_to(enemy, 24.0, 480.0, away)
		enemy.apply_stun(0.55)
	_act_end()


## Pudottaa lyhytkestoisemman kiviseinän vyöryn jäljelle.
func _drop_trail_wall() -> void:
	var pos: Vector2 = arena.map.clamp_to_field(global_position - _roll_dir * 70.0, 60.0)
	var wall := RockWall.new()
	wall.owner_team = team
	wall.hp = WALL_HP * 0.7
	wall.max_hp = WALL_HP * 0.7
	wall.lifetime = 3.8
	wall.global_position = pos
	wall.rotation = _roll_dir.angle() + PI / 2.0
	arena.add_child(wall)
	Fx.dust(arena, pos)


## Kestävä kivimuuri, joka estää liikkeen ja ammukset. Sillä on oma kesto-hp:
## vihollisen ammukset murtavat sitä, ja se murenee itsestään keston lopussa.
class RockWall:
	extends Node2D

	var lifetime := 8.0
	var hp := 90.0
	var max_hp := 90.0
	var owner_team := 0
	var _age := 0.0
	var _flash := 0.0

	func _ready() -> void:
		z_index = 6
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(180, 40)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)

	## Vihollisen ammus vahingoittaa muuria (Projectile kutsuu tätä).
	func hit_by_projectile(amount: float, proj_team: int) -> void:
		if proj_team == owner_team:
			return
		hp -= amount
		_flash = 0.15
		if hp <= 0.0:
			_crumble()

	func _crumble() -> void:
		var arena = get_parent()
		if arena != null:
			Fx.burst(arena, global_position, Palette.with_alpha(Color("9aa3ad"), 0.8), 14, 220.0, 0.5, 6.0)
			AudioMgr.play("rock", 0.1, -3.0)
		queue_free()

	func _process(delta: float) -> void:
		_age += delta
		_flash = maxf(_flash - delta, 0.0)
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade := 1.0
		if lifetime - _age < 0.5:
			fade = (lifetime - _age) / 0.5
		var rise: float = minf(_age / 0.15, 1.0)
		var dmg_frac: float = clampf(1.0 - hp / max_hp, 0.0, 1.0)
		for i in range(4):
			var x := -66.0 + i * 44.0
			var r := (26.0 - absf(i - 1.5) * 3.0) * rise
			draw_circle(Vector2(x, 4), r + 3.0, Palette.with_alpha(Color("39424d"), fade))
			var body_col: Color = Color("e6b25a") if _flash > 0.0 else Color("9aa3ad")
			draw_circle(Vector2(x, 0), r, Palette.with_alpha(body_col, fade))
			draw_circle(Vector2(x - r * 0.3, -r * 0.3), r * 0.4,
				Palette.with_alpha(Color("c4ccd4"), fade * 0.6))
			# Vauriohalkeamat lisääntyvät hp:n laskiessa.
			var cracks: int = 1 + int(dmg_frac * 3.0)
			for c in range(cracks):
				var cx: float = x + (c - 1) * r * 0.35
				draw_line(Vector2(cx, -r * 0.6), Vector2(cx + r * 0.2, r * 0.5),
					Palette.with_alpha(Color("39424d"), fade * (0.4 + dmg_frac * 0.5)), 1.5 + dmg_frac)
