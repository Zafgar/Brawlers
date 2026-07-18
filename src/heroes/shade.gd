class_name Shade
extends Hero
## Assassin: varjot ja shurikenit. Kaksi kaksivaiheista kykyä:
## - Varjoloikka (R1): tähtää ja loikkaa, jättäen varjon lähtöpaikkaan; paina
##   uudelleen palataksesi varjolle ja iskeäksesi alueesi.
## - Paluushuriken (L1): tähtää ja heitä; paina uudelleen kutsuaksesi sen
##   takaisin. Osuu molempiin suuntiin, ja kopatessa jäähdytys laskee.
## Jäähdytyspohjainen (ei resurssia). Passiivi: väistö lataa ultimatea.

const DASH_RANGE := 300.0
const SHADOW_WINDOW := 2.4          # kuinka kauan varjolle voi palata
const RETURN_AOE_RADIUS := 145.0
const RETURN_AOE_DMG := 26.0

const SHURI_SPEED := 900.0
const SHURI_DMG := 22.0
const SHURI_RADIUS := 30.0          # iso osuma-alue (helppo ohjaimella)
const SHURI_OUT_TIME := 0.4
const SHURI_KB := 110.0
const SHURI_CATCH_RADIUS := 36.0

var _empower_timer := 0.0

# Varjoloikka (a1)
var _shadow_active := false
var _shadow_pos := Vector2.ZERO
var _shadow_timer := 0.0
var _shadow_decoy: Decoy = null

# Paluushuriken (a2)
var _active_shuriken: Shuriken = null


func _init() -> void:
	radius = 22.0


## Jäähdytyspohjainen assassiini (ei resurssipalkkia) — molemmat kyvyt ovat
## kaksivaiheisia yhdistelmiä, jotka nojaavat jäähdytyksiin.
func _setup_resource() -> void:
	res_type = ""
	cd_max.a1 = 5.0
	cd_max.a2 = 4.0


## Molemmat kyvyt tähdätään: pidä pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _aim_range(slot: String) -> float:
	return DASH_RANGE if slot == "a1" else 420.0


## Ensimmäinen painallus aloittaa tähtäyksen; jos kyvyn toinen vaihe on
## saatavilla (varjo pystyssä / shuriken lennossa), se laukeaa heti.
func _aim_begin(slot: String) -> bool:
	if slot == "a1":
		if _shadow_active:
			_return_to_shadow()
			return false
		return true
	if _active_shuriken != null and is_instance_valid(_active_shuriken):
		_active_shuriken.recall()
		return false
	return true


## Perushyökkäys: nopea varjokiekko (tehostuu ultin aikana).
func _basic(dir: Vector2) -> void:
	AudioMgr.play("disc", 0.15, -2.0)
	visual.attack_swing()
	var dmg := 21.0
	if _empower_timer > 0.0:
		dmg *= 1.6
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 1000.0,
		"dmg": dmg,
		"radius": 10.0,
		"life": 0.55,
		"kb": 90.0,
		"spin": true,
		"color": Palette.glow(hero_color(), 1.3) if _empower_timer > 0.0 else hero_color(),
	})


## Kyky 1: Varjoloikka — loikkaa tähtäyssuuntaan ja jätä varjo lähtöpaikkaan.
## Ihminen voi painaa uudelleen palatakseen varjolle (+ aluesku). Botti tekee
## aluesku heti saapumispisteessä.
func _ability1(dir: Vector2) -> void:
	var bot: bool = controller.is_bot()
	AudioMgr.play("smoke")
	var smoke_color := Palette.darker(hero_color(), 0.5)
	var origin := global_position
	Fx.burst(arena, origin, Palette.with_alpha(smoke_color, 0.7), 12, 200.0, 0.5, 7.0)
	global_position = arena.map.clamp_to_field(origin + dir * DASH_RANGE, 40.0)
	Fx.burst(arena, global_position, Palette.with_alpha(smoke_color, 0.6), 10, 180.0, 0.5, 6.0)
	apply_haste(1.2, 1.0)
	iframes = maxf(iframes, 0.25)
	if bot:
		cd.a1 = cd_max.a1
		_shadow_aoe(global_position)
		return
	# Ihminen: jätä varjo ja avaa paluu-ikkuna.
	var decoy := Decoy.new()
	decoy.global_position = origin
	decoy.body_color = hero_color()
	decoy.facing = aim
	decoy.lifetime = SHADOW_WINDOW + 0.2
	arena.add_child(decoy)
	_shadow_decoy = decoy
	_shadow_pos = origin
	_shadow_active = true
	_shadow_timer = SHADOW_WINDOW
	cd.a1 = 0.15                # lyhyt, jotta paluupainallus toimii


## Paluu varjolle + aluesku ympärille.
func _return_to_shadow() -> void:
	AudioMgr.play("smoke", 0.1, 1.0)
	var from := global_position
	global_position = arena.map.clamp_to_field(_shadow_pos, 40.0)
	iframes = maxf(iframes, 0.3)
	Fx.beam(arena, from, global_position, Palette.glow(hero_color(), 1.3), 5.0)
	_shadow_aoe(global_position)
	if is_instance_valid(_shadow_decoy):
		_shadow_decoy.queue_free()
	_shadow_decoy = null
	_shadow_active = false
	cd.a1 = cd_max.a1


func _shadow_aoe(center: Vector2) -> void:
	AudioMgr.play("disc", 0.1, -1.0)
	arena.shake(0.2)
	Fx.ring(arena, center, Palette.glow(hero_color(), 1.5), RETURN_AOE_RADIUS, 0.5, 7.0)
	Fx.burst(arena, center, Palette.with_alpha(Palette.darker(hero_color(), 0.4), 0.7), 14, 240.0, 0.5, 6.0)
	for enemy in arena.heroes_in_circle(center, RETURN_AOE_RADIUS):
		if enemy.team == team:
			continue
		var away: Vector2 = enemy.global_position - center
		var kbdir: Vector2 = away.normalized() if away.length() > 1.0 else aim
		deal_damage_to(enemy, RETURN_AOE_DMG, 260.0, kbdir)


## Kyky 2: Paluushuriken — tähdättävä shuriken, joka lentää ulos ja palaa
## (automaattisesti tai painamalla uudelleen). Osuu molempiin suuntiin.
func _ability2(dir: Vector2) -> void:
	var bot: bool = controller.is_bot()
	AudioMgr.play("disc", 0.1, -4.0)
	var sh := Shuriken.new()
	sh.source = self
	sh.direction = dir.normalized()
	sh.color = hero_color()
	sh.speed = SHURI_SPEED
	sh.dmg = SHURI_DMG
	sh.hit_radius = SHURI_RADIUS
	sh.out_time = SHURI_OUT_TIME
	sh.kb = SHURI_KB
	sh.catch_radius = SHURI_CATCH_RADIUS
	sh.global_position = global_position + dir * 26.0
	arena.add_child(sh)
	_active_shuriken = sh
	cd.a2 = cd_max.a2 if bot else 0.15


## Shuriken kopattiin -> jäähdytys laskee ja saa hieman ultia.
func on_shuriken_caught() -> void:
	_active_shuriken = null
	cd.a2 = 0.3
	add_ult(6.0)
	arena.popup(global_position + Vector2(0, -70), "KOPPI!", Palette.glow(hero_color(), 1.4), 18)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 40.0, 0.35)


## Shuriken katosi ilman koppia -> täysi jäähdytys.
func on_shuriken_expired() -> void:
	_active_shuriken = null
	cd.a2 = maxf(cd.a2, cd_max.a2)


## Väistö: varjoaskel, joka lataa ultia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	add_ult(6.0)
	AudioMgr.play("smoke", 0.12, 3.0)
	Fx.burst(arena, global_position, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.5),
		8, 150.0, 0.4, 5.0)


## Ultimate: Varjoisku — hetken salamannopea ja iskut tehostuvat.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "VARJOISKU!", Palette.glow(hero_color(), 1.5), 26)
	AudioMgr.play("smoke", 0.05, -3.0)
	AudioMgr.play("disc", 0.1, 2.0)
	_empower_timer = 3.5
	apply_haste(1.5, 3.5)
	iframes = maxf(iframes, 0.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), 160.0, 0.5, 7.0)
	Fx.burst(arena, global_position, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.7),
		16, 240.0, 0.6, 7.0)


func _passive_update(delta: float) -> void:
	_empower_timer = maxf(_empower_timer - delta, 0.0)
	if _shadow_active:
		_shadow_timer -= delta
		if _shadow_timer <= 0.0:
			# Varjo haihtui käyttämättä -> täysi jäähdytys.
			_shadow_active = false
			_shadow_decoy = null
			cd.a1 = maxf(cd.a1, cd_max.a1)


## Nollaa yhdistelmätilat tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_reset_shade_state()


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_reset_shade_state()


func _reset_shade_state() -> void:
	_shadow_active = false
	_shadow_decoy = null
	_active_shuriken = null
	_empower_timer = 0.0
	_shadow_timer = 0.0


## Paikalleen jäävä harhakuva, joka haihtuu hitaasti.
class Decoy:
	extends Node2D

	var lifetime := 2.2
	var body_color := Color.WHITE
	var facing := Vector2.RIGHT
	var _age := 0.0

	func _ready() -> void:
		z_index = 1

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = clampf(1.0 - _age / lifetime, 0.0, 1.0) * 0.65
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 22.0, Color(0.02, 0.03, 0.08, 0.3 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -14), 18.0, Palette.with_alpha(Palette.darker(body_color, 0.5), fade))
		draw_circle(Vector2(0, -14), 15.0, Palette.with_alpha(body_color, fade))
		var perp: Vector2 = facing.orthogonal().normalized() * 6.0
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(0, -18) + perp * side + facing * 2.5, 3.0,
				Palette.with_alpha(Color.WHITE, fade))


## Paluushuriken: lentää ulos, palaa (auto tai kutsuttaessa) ja osuu molempiin
## suuntiin. Kun se saavuttaa Shaden (koppi), Shaden jäähdytys laskee.
class Shuriken:
	extends Node2D

	var source: Shade = null
	var direction := Vector2.RIGHT
	var color := Color("b48aff")
	var speed := 900.0
	var dmg := 22.0
	var hit_radius := 30.0
	var out_time := 0.4
	var kb := 110.0
	var catch_radius := 36.0
	var returning := false
	var _t := 0.0
	var _out := 0.0
	var _return_target := Vector2.ZERO
	var _hit: Array = []

	func _ready() -> void:
		z_index = 20

	func _physics_process(delta: float) -> void:
		_t += delta
		if source == null or not is_instance_valid(source) or not source.alive:
			queue_free()
			return
		var arena = source.arena
		if arena == null:
			queue_free()
			return
		if not returning:
			_out += delta
			global_position += direction * speed * delta
			if _out >= out_time:
				_start_return()
		else:
			if global_position.distance_to(source.global_position) < catch_radius:
				source.on_shuriken_caught()
				_pop(arena)
				queue_free()
				return
			var to_t: Vector2 = _return_target - global_position
			if to_t.length() < 22.0:
				source.on_shuriken_expired()
				_pop(arena)
				queue_free()
				return
			global_position += to_t.normalized() * (speed * 1.1) * delta
		_hit_pass(arena)
		queue_redraw()

	func _start_return() -> void:
		returning = true
		_return_target = source.global_position
		_hit.clear()

	func recall() -> void:
		if not returning:
			_start_return()

	func _hit_pass(arena) -> void:
		var pass_dmg: float = dmg
		if source._empower_timer > 0.0:
			pass_dmg *= 1.6
		for enemy in arena.alive_enemies(source.team):
			if enemy in _hit:
				continue
			if global_position.distance_to(enemy.global_position) < hit_radius + enemy.radius:
				_hit.append(enemy)
				var kbdir: Vector2 = direction
				if returning:
					kbdir = (enemy.global_position - global_position).normalized()
				source.deal_damage_to(enemy, pass_dmg, kb, kbdir)
				Fx.spark(arena, enemy.global_position, Palette.glow(color, 1.4))

	func _pop(arena) -> void:
		Fx.burst(arena, global_position, Palette.with_alpha(color, 0.7), 8, 160.0, 0.4, 5.0)

	func _draw() -> void:
		var spin := _t * 18.0
		for rot in [0.0, PI * 0.25]:
			var pts := PackedVector2Array()
			for k in range(4):
				var a: float = spin + rot + k * PI * 0.5
				pts.append(Vector2(cos(a), sin(a)) * 14.0)
			draw_colored_polygon(pts, Palette.glow(color, 1.4))
		draw_circle(Vector2.ZERO, 4.0, Palette.glow(Color.WHITE, 1.3))
