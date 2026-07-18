class_name Tide
extends Hero
## Fighter: vesikeihäs. Liukuu vesivanoja pitkin ja lakaisee viholliset aalloilla.
## Passiivi: virrassa liikkuessa (haste päällä) palautuu hitaasti.

const SPEAR_RANGE := 145.0
const SPEAR_ARC_DEG := 28.0
const SPEAR_DMG := 17.0

func _init() -> void:
	radius = 26.0
	kb_resist = 0.2


## Raivo: kertyy taistelusta ja purkautuu vesikykyihin. Mitä kovemmin
## taistelet, sitä useammin voit syöksyä ja lyödä aaltoja.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost = {"basic": 0.0, "a1": 30.0, "a2": 40.0, "dodge": 0.0}
	cd_max.a1 = 0.5
	cd_max.a2 = 0.6


## Perushyökkäys: pitkä kapea keihäspisto.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("water", 0.12)
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SPEAR_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SPEAR_ARC_DEG:
			continue
		deal_damage_to(enemy, SPEAR_DMG, 170.0, to_enemy.normalized())
		hits += 1
	if hits > 0:
		Fx.spark(arena, global_position + dir * SPEAR_RANGE * 0.8, Color("4ad4ff"))


## Kyky 1: Vesivana — syöksy, joka jättää kiihdyttävän vanan.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("water", 0.1, -3.0)
	dash(dir, 950.0, 0.32, false)
	_water_trail()


func _water_trail() -> void:
	for i in range(3):
		if not is_inside_tree() or not alive:
			return
		Zone.spawn(self, global_position, {
			"type": "haste",
			"radius": 80.0,
			"dur": 3.0,
			"haste_f": 1.3,
			"color": Color("4ad4ff"),
		})
		Fx.burst(arena, global_position, Palette.with_alpha(Color("4ad4ff"), 0.6), 6, 120.0, 0.4, 4.0)
		await get_tree().create_timer(0.12).timeout


## Kyky 2: Aalto — työntävä vesiaalto eteen.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("wave")
	visual.attack_swing()
	Fx.burst(arena, global_position + dir * 80.0, Palette.glow(Color("4ad4ff"), 1.5), 18, 420.0, 0.45, 6.0)
	# Etenevät aaltokaaret
	for step in range(1, 4):
		Fx.ring(arena, global_position + dir * step * 60.0,
			Palette.with_alpha(Palette.glow(Color("4ad4ff"), 1.4), 0.6), 40.0 + step * 22.0, 0.35, 4.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > 220.0 + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > 45.0:
			continue
		deal_damage_to(enemy, 12.0, 540.0, to_enemy.normalized())
		enemy.apply_slow(0.8, 1.0)


## Väistö: virtaliuku.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.16, true)
	apply_haste(1.2, 0.8)
	AudioMgr.play("water", 0.12, 2.0)
	Fx.burst(arena, global_position, Palette.with_alpha(Color("4ad4ff"), 0.5), 8, 140.0, 0.4, 4.0)


## Ultimate: Hyökyaalto — valtava laajeneva aalto.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "HYÖKYAALTO!", Palette.glow(Color("4ad4ff"), 1.6), 26)
	arena.shake(0.5)
	AudioMgr.play("wave", 0.05, -2.0)
	_tidal_wave()


func _tidal_wave() -> void:
	var origin := global_position
	for step in range(3):
		if not is_inside_tree():
			return
		var r := 140.0 + step * 120.0
		Fx.ring(arena, origin, Palette.glow(Color("4ad4ff"), 1.7), r, 0.5, 10.0)
		Fx.ring(arena, origin, Palette.with_alpha(Color("bfeaf7"), 0.5), r * 0.7, 0.4, 5.0)
		AudioMgr.play("wave", 0.1, 1.0)
		for enemy in arena.heroes_in_circle(origin, r):
			if enemy.team == team:
				continue
			deal_damage_to(enemy, 15.0, 620.0,
				(enemy.global_position - origin).normalized())
			enemy.apply_slow(0.7, 1.5)
		await get_tree().create_timer(0.3).timeout


func _passive_update(delta: float) -> void:
	if haste_timer > 0.0 and hp < max_hp:
		hp = minf(hp + 5.0 * delta, max_hp)
