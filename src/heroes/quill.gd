class_name Quill
extends Hero
## Ranger: jousi. Perushyökkäys latautuu liipaisinta pohjassa pitämällä —
## täysi lataus lävistää ja iskee kovempaa.
## Passiivi: paikallaan seistessä jousi latautuu nopeammin.

const CHARGE_TIME := 0.9
const SUPER_ARROW_RANGE := 1500.0   # ultin tähdättävän supernuolen kantama

var _charging := false
var _charge := 0.0
var _full_ready := false

func _init() -> void:
	radius = 23.0


## Energia: erikoislaukaukset maksavat energiaa. Energia palautuu itsekseen
## mutta karttuu ennen kaikkea osumista — tarkka ampuja pitää kykynsä käynnissä.
## Ladattava jousi (perus) on ilmainen ja lataa energiaa osuessaan.
func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = 100.0
	res_regen = 12.0
	res_cost = {"basic": 0.0, "a1": 28.0, "a2": 40.0, "dodge": 0.0}
	cd_max.a1 = 2.2
	cd_max.a2 = 2.5


## Ulti tähdätään pitämällä ulttinappi pohjassa (näyttää pitkän viivan) ja
## vapautetaan laukaisemaan supernuoli.
func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return SUPER_ARROW_RANGE


func _ult_preview_width() -> float:
	return 38.0


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
		"dmg": 14.0 + 42.0 * _charge,
		"radius": 10.0,
		"life": 0.9,
		"kb": 120.0 + 160.0 * _charge,
		"pierce": 1 if full else 0,
		"color": Palette.glow(Palette.GOLD, 1.5) if full else hero_color(),
		"visual": "quill_super" if full else "quill_arrow",
	})


## Kyky 1: Väistösyöksy — loikkaa taaksepäin (poispäin tähtäyksestä) ja jättää
## piikkialueen lähtöpaikkaan, joka hidastaa ja vahingoittaa siihen astuvia.
## Kiteyttää Quillin kiteytyspelin: pakene ja jätä ansa perään.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("dash", 0.1, 2.0)
	var origin := global_position
	dash(-dir, 940.0, 0.18, true)     # syöksy taaksepäin, lyhyet suojaruudut
	Fx.dust(arena, origin)
	Fx.ring(arena, origin, Palette.glow(hero_color(), 1.4), 95.0, 0.4, 4.0)
	Zone.spawn(self, origin, {
		"type": "thorn",
		"radius": 95.0,
		"dur": 3.5,
		"dps": 22.0,
		"slow_f": 0.55,
		"color": hero_color(),
	})


## Kyky 2: Nuolisade — nuolia sataa merkitylle alueelle hetken päästä.
func _ability2(dir: Vector2) -> void:
	var target := aimed_ground_position(dir, 620.0, 380.0)
	target = arena.map.clamp_to_field(target, 60.0)
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


## Ultimate: Läpäisynuoli — tähdätään pitämällä ulttinappi pohjassa (pitkä
## viiva) ja vapautetaan. Todella nopea, pitkän kantaman nuoli, joka lävistää
## kaiken tielleen ja tekee valtavaa vahinkoa.
func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir if dir.length() > 0.1 else aim
	d = d.normalized()
	var origin := global_position + d * 30.0
	var finish := global_position + d * SUPER_ARROW_RANGE
	arena.popup(global_position + Vector2(0, -80), "LÄPÄISYNUOLI!", Palette.glow(Palette.GOLD, 1.6), 26)
	AudioMgr.play("quill_ult", 0.05, -4.0, global_position)
	visual.attack_swing()
	Fx.ultimate_line_warning(arena, origin, finish, Palette.glow(Palette.GOLD, 1.5),
		Palette.team(team), 38.0, 0.3)
	_release_super_arrow(origin, d)


func _release_super_arrow(origin: Vector2, d: Vector2) -> void:
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	_act("ult")
	var finish := origin + d * SUPER_ARROW_RANGE
	var side := d.orthogonal()
	AudioMgr.play("quill_ult", 0.04, 2.0, origin)
	arena.shake(0.42)
	Fx.beam(arena, origin, finish, Palette.glow(Palette.GOLD, 1.7), 13.0)
	Fx.beam(arena, origin + side * 22.0, finish + side * 22.0,
		Palette.with_alpha(hero_color(), 0.72), 3.0)
	Fx.beam(arena, origin - side * 22.0, finish - side * 22.0,
		Palette.with_alpha(hero_color(), 0.72), 3.0)
	for enemy in arena.alive_enemies(team):
		var rel: Vector2 = enemy.global_position - origin
		var along := rel.dot(d)
		var across := absf(rel.dot(side))
		if along < 0.0 or along > SUPER_ARROW_RANGE + enemy.radius:
			continue
		if across > 38.0 + enemy.radius:
			continue
		deal_damage_to(enemy, 95.0, 340.0, d)
		Fx.ability_impact(arena, enemy.global_position, "quill_super", hero_color(),
			profile.color() if profile != null and not profile.is_bot else Palette.team(team), Palette.team(team))
	_act_end()
func _aimed_slots() -> Array:
	return ["a2"]


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_range(_slot: String) -> float:
	return 620.0


func _aim_default_range(_slot: String) -> float:
	return 380.0


func _aim_target_radius(_slot: String) -> float:
	return 130.0
