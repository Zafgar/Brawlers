class_name Vesper
extends JungleHero
## Ranged tracker: merkki -> pultit/ansa -> valmisteltu saartoristikko.

const TRAP_RADIUS := 112.0
const ULT_RADIUS := 285.0

var _drone_active := 0.0


func _setup_resource() -> void:
	# Safe ranged clearing may be slower than melee, but not several times slower.
	# PvE-kerrointa Vesper tarvitsi buffileiriin yli 40 sekuntia.
	jungle_clear_mult = 2.0
	res_type = "energy"
	res_max = 100.0
	res = res_max
	res_regen = 12.0
	res_cost.a1 = 18.0
	res_cost.a2 = 24.0


func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_range(slot: String) -> float:
	return 760.0 if slot == "a1" else 650.0


func _aim_default_range(slot: String) -> float:
	return 510.0 if slot == "a1" else 420.0


func _aim_target_radius(slot: String) -> float:
	return TRAP_RADIUS if slot == "a2" else 0.0


func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("vesper", 105.0, d)
	Projectile.launch(self, global_position + d * (radius + 9.0), d, {
		"speed": 1120.0, "dmg": 14.0, "radius": 7.5, "life": 0.78,
		"kb": 55.0, "color": hero_color(), "visual": "vesper_bolt",
		"on_hit": Callable(self, "_bolt_hit"),
	})
	AudioMgr.play("bow", 0.06, -11.0, global_position)


func _bolt_hit(target: Hero, _projectile: Projectile) -> void:
	if target.mark_timer <= 0.0:
		return
	deal_damage_to(target, 6.0)
	gain_res(7.0)
	Fx.bolt(arena, target.global_position - aim.orthogonal() * 16.0,
		target.global_position + aim.orthogonal() * 16.0,
		Palette.glow(Color("dcff8f"), 1.6))


func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("vesper", 145.0, d)
	Projectile.launch(self, global_position + d * (radius + 10.0), d, {
		"speed": 1280.0, "dmg": 20.0, "radius": 9.0, "life": 0.68,
		"kb": 80.0, "pierce": 1, "color": Color("d9ff8f"),
		"visual": "vesper_tracker", "on_hit": Callable(self, "_tracker_hit"),
	})
	AudioMgr.play("bow_charged", 0.08, -5.0, global_position)
	controller_rumble(0.18, 0.42, 0.12)


func _tracker_hit(target: Hero, _projectile: Projectile) -> void:
	target.apply_mark(6.0, 1.22)
	if target is Critter:
		target.apply_slow(0.72, 1.0)
		gain_res(10.0)
	# Lukitus näkyy tähtäinristinä saaliin päällä + mark-ping kuuluu.
	var gp := target.global_position
	Fx.ring(arena, gp, Palette.glow(hero_color(), 1.5), 52.0, 0.35, 4.0)
	Fx.beam(arena, gp + Vector2(-30, 0), gp + Vector2(30, 0),
		Palette.glow(Color("dcff8f"), 1.5), 3.0)
	Fx.beam(arena, gp + Vector2(0, -30), gp + Vector2(0, 30),
		Palette.glow(Color("dcff8f"), 1.5), 3.0)
	AudioMgr.play("mark", 0.07, -6.0, gp)


func _ability2(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, 650.0, 420.0)
	ability_signature("vesper", 145.0, target - global_position)
	JungleField.spawn(self, target, "trap", {
		"radius": TRAP_RADIUS, "dur": 6.0, "dps": 29.0, "tick": 0.42,
		"color": hero_color(),
	})
	# Sahalanka näkyy X-ristinä alueen yli ja kuulostaa piikkilangalta.
	Fx.ring(arena, target, Palette.glow(hero_color(), 1.45), TRAP_RADIUS, 0.38, 4.0)
	var arm := TRAP_RADIUS * 0.7
	Fx.beam(arena, target + Vector2(-arm, -arm), target + Vector2(arm, arm),
		Palette.glow(Color("d9ff8f"), 1.4), 3.5)
	Fx.beam(arena, target + Vector2(-arm, arm), target + Vector2(arm, -arm),
		Palette.glow(Color("d9ff8f"), 1.4), 3.5)
	AudioMgr.play("thorns", 0.08, -6.0, target)


func _dodge_action(_dir: Vector2) -> void:
	_drone_active = 8.0
	ability_signature("vesper", 135.0, aim)
	JungleField.spawn(self, global_position, "drone", {
		"radius": 265.0, "dur": 8.0, "dps": 10.0, "tick": 0.5,
		"color": hero_color(),
	})
	apply_haste(1.18, 2.0)
	iframes = maxf(iframes, 0.22)
	Fx.ring(arena, global_position, Color("d9ff8f"), 270.0, 0.55, 3.0)
	AudioMgr.play("blink", 0.08, -8.0, global_position)
	controller_rumble(0.18, 0.26, 0.14)


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 780.0


func _ult_default_range() -> float:
	return 520.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	Fx.ultimate_warning(arena, target, Palette.glow(hero_color(), 1.55),
		Palette.team(team), ULT_RADIUS, 0.55, "vesper")
	Fx.ultimate_field(arena, target, hero_color(), Palette.team(team),
		ULT_RADIUS, 8.0, "vesper")
	JungleField.spawn(self, target, "grid", {
		"radius": ULT_RADIUS, "dur": 8.0, "dps": 18.0, "tick": 0.58,
		"color": hero_color(),
	})
	arena.popup(target + Vector2(0, -ULT_RADIUS - 25), "SAARTORISTIKKO!", Color("d9ff8f"), 24)
	AudioMgr.play("ult", 0.1, -4.0, target)
	AudioMgr.play("mark", 0.08, -5.0, target)
	controller_rumble(0.38, 0.7, 0.28)


func _passive_update(delta: float) -> void:
	_drone_active = maxf(_drone_active - delta, 0.0)


func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	return _drone_active <= 0.0 and is_instance_valid(target) and target is Critter \
		and ((target as Critter).is_major_objective() or hp < max_hp * 0.68)


## Tasoskaalaus: ranged tracker -hypercarry — merkit ja pultit kasvavat.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 1.15, "spell": 1.20, "melee": 1.05, "regen": 0.95}


## Väistön kehitys: vauhti (jäljittäjä pitää saalistusetäisyyden).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Merkkipultit ensin, ansa toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]
