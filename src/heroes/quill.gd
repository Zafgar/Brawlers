class_name Quill
extends Hero
## Ranger: jousi. Perushyökkäys latautuu liipaisinta pohjassa pitämällä —
## täysi lataus lävistää ja iskee kovempaa.
## Passiivi: paikallaan seistessä jousi latautuu nopeammin.

const CHARGE_TIME := 0.9

var _charging := false
var _charge := 0.0
var _full_ready := false

func _init() -> void:
	radius = 23.0


## Tarkkuuslaukaus tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 580.0


## Latautuva perushyökkäys korvaa oletuslogiikan.
func _attack_control(held: bool, just_pressed: bool, just_released: bool,
		dir: Vector2, delta: float) -> void:
	if just_pressed and cd.basic <= 0.0:
		_charging = true
		_charge = 0.0
		_full_ready = false
	if held and _charging:
		var rate := 1.0 / CHARGE_TIME
		if velocity.length() < 20.0:
			rate *= 1.4
		_charge = minf(_charge + rate * delta, 1.0)
		visual.aux = _charge
		# Tähtäysviiva latauksen aikana: pitenee ja kirkastuu ladattaessa.
		_aim_active = true
		_aim_len = 300.0 + 520.0 * _charge
		_aim_color = Palette.glow(Palette.GOLD, 1.3) if _charge >= 1.0 else hero_color()
		_aim_charge = _charge
		# Merkkiääni ja kimallus, kun täysi lataus saavutetaan.
		if _charge >= 1.0 and not _full_ready:
			_full_ready = true
			AudioMgr.play("ult_ready", 0.1, -4.0)
			Fx.spark(arena, global_position + dir * 30.0, Palette.glow(Palette.GOLD, 1.7))
	if just_released and _charging:
		_fire_arrow(dir)
		_charging = false
		_charge = 0.0
		_full_ready = false
		visual.aux = 0.0


func _fire_arrow(dir: Vector2) -> void:
	cd.basic = cd_max.basic
	visual.attack_swing()
	var full: bool = _charge >= 1.0
	if full:
		AudioMgr.play("bow_charged")
		arena.shake(0.12)
	else:
		AudioMgr.play("bow", 0.1, -4.0 + _charge * 4.0)
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 950.0 + 450.0 * _charge,
		"dmg": 13.0 + 26.0 * _charge,
		"radius": 8.0,
		"life": 0.9,
		"kb": 120.0 + 160.0 * _charge,
		"pierce": 1 if full else 0,
		"color": Palette.glow(Palette.GOLD, 1.5) if full else hero_color(),
	})


## Kyky 1: Tarkkuuslaukaus — pitkä, nopea ja lävistävä nuoli.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("bow_charged", 0.05, 3.0)
	visual.attack_swing()
	dash(-dir, 250.0, 0.08, false)
	# Tarkkuusviiva korostaa laukauksen linjaa
	Fx.beam(arena, global_position + dir * 30.0, global_position + dir * 500.0,
		Palette.glow(hero_color(), 1.3), 4.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 1400.0,
		"dmg": 30.0,
		"radius": 7.0,
		"life": 1.1,
		"kb": 220.0,
		"pierce": 2,
		"color": Palette.glow(hero_color(), 1.6),
	})


## Kyky 2: Nuolisade — nuolia sataa merkitylle alueelle hetken päästä.
func _ability2(dir: Vector2) -> void:
	var target: Vector2 = arena.map.clamp_to_field(global_position + dir * 380.0, 60.0)
	AudioMgr.play("bow", 0.1, -4.0)
	Fx.ring(arena, target, Palette.with_alpha(hero_color(), 0.7), 130.0, 0.75, 4.0)
	_arrow_rain(target)


func _arrow_rain(target: Vector2) -> void:
	await get_tree().create_timer(0.75).timeout
	if not is_inside_tree():
		return
	AudioMgr.play("arrow_rain")
	arena.shake(0.2)
	# Putoavat nuolet ylhäältä alueelle
	for i in range(7):
		var off := Vector2(randf_range(-110.0, 110.0), randf_range(-110.0, 110.0))
		var landing: Vector2 = target + off
		Fx.beam(arena, landing + Vector2(0, -170.0), landing,
			Palette.glow(hero_color(), 1.2), 3.0)
	Fx.burst(arena, target, Palette.glow(hero_color(), 1.6), 24, 340.0, 0.5, 5.0)
	Fx.ring(arena, target, Palette.glow(hero_color(), 1.4), 130.0, 0.4)
	for enemy in arena.heroes_in_circle(target, 130.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 24.0, 120.0,
			(enemy.global_position - target).normalized())
		enemy.apply_slow(0.7, 1.0)


## Väistö: kuperkeikka, joka lataa jousen heti valmiiksi.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	cd.basic = 0.0
	AudioMgr.play("dash")
	Fx.dust(arena, global_position)


## Ultimate: Myrskysarja — nopea sarja nuolia tähtäyksen mukaan.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "MYRSKYSARJA!", Palette.glow(hero_color(), 1.5), 24)
	_storm_volley()


func _storm_volley() -> void:
	for shot in range(8):
		if not is_inside_tree() or not alive:
			return
		AudioMgr.play("bow", 0.2, -3.0)
		visual.attack_swing()
		Projectile.launch(self, global_position + aim * 28.0, aim, {
			"speed": 1100.0,
			"dmg": 12.0,
			"radius": 8.0,
			"life": 0.9,
			"kb": 130.0,
			"color": Palette.glow(hero_color(), 1.4),
		})
		await get_tree().create_timer(0.2).timeout
