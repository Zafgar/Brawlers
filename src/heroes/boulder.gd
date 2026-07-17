class_name Boulder
extends Hero
## Tankki: kivihansikkaat. Rakentaa muureja ja jyrää esteiden läpi.
## Passiivi: lähes immuuni tönäisyille.

const PUNCH_RANGE := 95.0
const PUNCH_ARC_DEG := 60.0
const PUNCH_DMG := 20.0

var _rolling := 0.0
var _roll_hit: Array = []

func _init() -> void:
	kb_resist = 0.7
	radius = 31.0


## Perushyökkäys: raskas murskaava isku.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("slam", 0.1, -4.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > PUNCH_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > PUNCH_ARC_DEG:
			continue
		deal_damage_to(enemy, PUNCH_DMG, 320.0, to_enemy.normalized())


## Kyky 1: Kivimuuri — väliaikainen muuri tähtäyssuuntaan.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("slam", 0.1, -2.0)
	arena.shake(0.2)
	var wall := RockWall.new()
	wall.global_position = arena.map.clamp_to_field(global_position + dir * 130.0, 60.0)
	wall.rotation = dir.angle() + PI / 2.0
	arena.add_child(wall)
	Fx.dust(arena, wall.global_position)


## Kyky 2: Tömistys — työntää kaikki lähellä olevat kauas.
func _ability2(_dir: Vector2) -> void:
	visual.squash(1.35, 0.65)
	arena.shake(0.35)
	AudioMgr.play("slam")
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.4), 190.0, 0.5, 9.0)
	for enemy in arena.heroes_in_circle(global_position, 190.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 16.0, 520.0)


## Väistö: raskas loikka.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 760.0, 0.22, false)
	AudioMgr.play("dash", 0.1, -3.0)
	Fx.dust(arena, global_position)


## Ultimate: Vyöry — vyöryy eteenpäin kaataen viholliset tieltään.
func _ultimate(dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "VYÖRY!", Palette.glow(hero_color(), 1.5), 24)
	arena.shake(0.5)
	AudioMgr.play("slam", 0.05, 3.0)
	_rolling = 0.45
	_roll_hit.clear()
	dash(dir, 1250.0, 0.45, false)
	iframes = maxf(iframes, 0.45)


func _passive_update(delta: float) -> void:
	if _rolling <= 0.0:
		return
	_rolling -= delta
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position, radius + 30.0):
		if enemy.team == team or enemy in _roll_hit:
			continue
		_roll_hit.append(enemy)
		deal_damage_to(enemy, 22.0, 620.0)
		arena.shake(0.2)


## Väliaikainen kivimuuri, joka estää liikkeen ja ammukset.
class RockWall:
	extends Node2D

	const LIFETIME := 3.0
	var _age := 0.0

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

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade := 1.0
		if LIFETIME - _age < 0.5:
			fade = (LIFETIME - _age) / 0.5
		var rise: float = minf(_age / 0.15, 1.0)
		for i in range(4):
			var x := -66.0 + i * 44.0
			var r := (26.0 - absf(i - 1.5) * 3.0) * rise
			draw_circle(Vector2(x, 4), r + 3.0, Palette.with_alpha(Color("39424d"), fade))
			draw_circle(Vector2(x, 0), r, Palette.with_alpha(Color("9aa3ad"), fade))
			draw_circle(Vector2(x - r * 0.3, -r * 0.3), r * 0.4,
				Palette.with_alpha(Color("c4ccd4"), fade * 0.6))
