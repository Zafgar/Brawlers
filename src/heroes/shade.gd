class_name Shade
extends Hero
## Assassin: varjokiekot. Katoaa savuun ja jättää harhakuvan.
## Passiivi: väistö lataa ultimatea.

var _stealth_timer := 0.0
var _empower_timer := 0.0

func _init() -> void:
	radius = 22.0


## Perushyökkäys: nopea varjokiekko.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("swing", 0.15, -4.0)
	visual.attack_swing()
	var dmg := 11.0
	if _empower_timer > 0.0:
		dmg *= 1.6
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 1000.0,
		"dmg": dmg,
		"radius": 8.0,
		"life": 0.55,
		"kb": 90.0,
		"spin": true,
		"color": Palette.glow(hero_color(), 1.3) if _empower_timer > 0.0 else hero_color(),
	})


## Kyky 1: Naamioituminen — harhakuva jää, Shade häipyy varjoihin.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("blink", 0.1, -3.0)
	var decoy := Decoy.new()
	decoy.global_position = global_position
	decoy.body_color = hero_color()
	decoy.facing = aim
	arena.add_child(decoy)
	Fx.flash(arena, global_position, Palette.with_alpha(hero_color(), 0.7), 44.0, 0.3)
	global_position = arena.map.clamp_to_field(global_position + dir * 220.0, 40.0)
	_stealth_timer = 2.0
	modulate = Color(1, 1, 1, 0.4)
	apply_haste(1.25, 2.0)
	iframes = maxf(iframes, 0.3)


## Kyky 2: Palaava kiekko — lävistää ja palaa takaisin.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("swing", 0.1, -2.0)
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 950.0,
		"dmg": 12.0,
		"radius": 10.0,
		"life": 0.38,
		"kb": 110.0,
		"pierce": 4,
		"spin": true,
		"color": hero_color(),
		"on_expire": Callable(self, "_return_disc"),
	})


func _return_disc(pos: Vector2) -> void:
	if not is_inside_tree() or not alive:
		return
	var back: Vector2 = (global_position - pos).normalized()
	if back == Vector2.ZERO:
		return
	Projectile.launch(self, pos, back, {
		"speed": 1050.0,
		"dmg": 12.0,
		"radius": 10.0,
		"life": 0.7,
		"kb": 110.0,
		"pierce": 4,
		"spin": true,
		"color": Palette.glow(hero_color(), 1.3),
	})


## Väistö: varjoaskel, joka lataa ultia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	add_ult(6.0)
	AudioMgr.play("dash", 0.12)
	Fx.dust(arena, global_position)


## Ultimate: Varjoisku — hetken salamannopea ja iskut tehostuvat.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "VARJOISKU!", Palette.glow(hero_color(), 1.5), 24)
	AudioMgr.play("blink", 0.05, 2.0)
	_empower_timer = 3.5
	apply_haste(1.5, 3.5)
	iframes = maxf(iframes, 0.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), 160.0, 0.5, 7.0)


func _passive_update(delta: float) -> void:
	_empower_timer = maxf(_empower_timer - delta, 0.0)
	if _stealth_timer > 0.0:
		_stealth_timer -= delta
		if _stealth_timer <= 0.0 or since_damage < 0.1:
			_stealth_timer = 0.0
			modulate = Color.WHITE


## Paikalleen jäävä harhakuva, joka haihtuu hitaasti.
class Decoy:
	extends Node2D

	const LIFETIME := 2.2
	var body_color := Color.WHITE
	var facing := Vector2.RIGHT
	var _age := 0.0

	func _ready() -> void:
		z_index = 1

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = clampf(1.0 - _age / LIFETIME, 0.0, 1.0) * 0.65
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 22.0, Color(0.02, 0.03, 0.08, 0.3 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -14), 18.0, Palette.with_alpha(Palette.darker(body_color, 0.5), fade))
		draw_circle(Vector2(0, -14), 15.0, Palette.with_alpha(body_color, fade))
		var perp: Vector2 = facing.orthogonal().normalized() * 6.0
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(0, -18) + perp * side + facing * 2.5, 3.0,
				Palette.with_alpha(Color.WHITE, fade))
