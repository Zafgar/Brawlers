class_name Myria
extends JungleHero
## Mage-jungleri: leirien kaadot tallentuvat neljäksi eri essenssiksi.

const ESSENCES := ["red", "blue", "green", "void"]
const FIELD_RADIUS := 138.0
const ULT_RADIUS := 275.0

var essence_counts := {"red": 0, "blue": 0, "green": 1, "void": 0}
var selected_essence := "green"
var _essence_flash := 0.0


func _setup_resource() -> void:
	# The field mage trades some clear speed for safety without stalling at one camp.
	jungle_clear_mult = 2.0
	res_type = "mana"
	res_max = 120.0
	res = res_max
	res_regen = 10.5
	res_cost.a1 = 18.0
	res_cost.a2 = 28.0


func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_range(slot: String) -> float:
	return 680.0 if slot == "a1" else 600.0


func _aim_default_range(slot: String) -> float:
	return 470.0 if slot == "a1" else 390.0


func _aim_target_radius(slot: String) -> float:
	return FIELD_RADIUS if slot == "a2" else 0.0


func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("myria", 105.0, d)
	Projectile.launch(self, global_position + d * (radius + 7.0), d, {
		"speed": 780.0, "dmg": 14.0, "radius": 10.0, "life": 0.95,
		"kb": 55.0, "homing_rate": 1.2, "color": essence_color(),
		"visual": "myria_wisp", "on_hit": Callable(self, "_wisp_hit"),
	})
	AudioMgr.play("light", 0.05, -10.0, global_position)


func _wisp_hit(target: Hero, _projectile: Projectile) -> void:
	match selected_essence:
		"red":
			deal_damage_to(target, 4.0)
		"blue":
			target.apply_slow(0.78, 0.7)
		"green":
			heal_hp(3.5, self)
		"void":
			var pull := global_position - target.global_position
			if pull.length() > 1.0:
				target.velocity += pull.normalized() * 90.0


func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("myria", 155.0, d)
	Projectile.launch(self, global_position + d * (radius + 8.0), d, {
		"speed": 940.0, "dmg": 25.0, "radius": 11.0, "life": 0.78,
		"kb": 80.0, "pierce": 1, "color": essence_color(),
		"visual": "myria_thread", "on_hit": Callable(self, "_thread_hit"),
	})
	AudioMgr.play("luma_pulse", 0.08, -5.0, global_position)
	controller_rumble(0.16, 0.35, 0.12)


func _thread_hit(target: Hero, _projectile: Projectile) -> void:
	if target is Critter:
		gain_res(18.0)
		if target.hp < target.max_hp * 0.5:
			heal_hp(11.0, self)
	else:
		target.apply_slow(0.74, 0.65)
	Fx.beam(arena, global_position, target.global_position,
		Palette.glow(essence_color(), 1.5), 6.0)


func _ability2(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, 600.0, 390.0)
	var essence := selected_essence
	_consume_selected()
	ability_signature("myria", 150.0, target - global_position)
	JungleField.spawn(self, target, "essence", {
		"variant": essence, "radius": FIELD_RADIUS, "dur": 5.2,
		"dps": 20.0 if essence != "green" else 15.0, "tick": 0.42,
		"color": essence_color_for(essence),
	})
	Fx.ring(arena, target, Palette.glow(essence_color_for(essence), 1.5),
		FIELD_RADIUS, 0.45, 5.0)
	AudioMgr.play("dome_up", 0.06, -9.0, target)


func _dodge_action(_dir: Vector2) -> void:
	_cycle_essence()
	_essence_flash = 1.0
	iframes = maxf(iframes, 0.38)
	add_shield(24.0, 1.8, self)
	ability_signature("myria", 130.0, aim)
	Fx.ring(arena, global_position, Palette.glow(essence_color(), 1.6), 95.0, 0.4, 5.0)
	arena.popup(global_position + Vector2(0, -74), selected_essence.to_upper(), essence_color(), 16)
	AudioMgr.play("pickup", 0.07, -5.0, global_position)


func on_jungle_camp_defeated(camp: Critter) -> void:
	super.on_jungle_camp_defeated(camp)
	var gained := "green"
	match camp.kind:
		Critter.Kind.RED_CAMP, Critter.Kind.DAMAGE_CAMP:
			gained = "red"
		Critter.Kind.BLUE_CAMP, Critter.Kind.POINTS_CAMP:
			gained = "blue"
		Critter.Kind.BOSS, Critter.Kind.DRAGON:
			gained = "void"
		_:
			gained = "green"
	essence_counts[gained] = mini(int(essence_counts[gained]) + 1, 3)
	selected_essence = gained
	_essence_flash = 1.0
	add_ult(8.0 if camp.is_major_objective() else 3.0)
	if arena != null:
		arena.popup(global_position + Vector2(0, -80), "+%s ESSENSSI" % gained.to_upper(),
			essence_color_for(gained), 16)


func _consume_selected() -> void:
	if int(essence_counts.get(selected_essence, 0)) > 0:
		essence_counts[selected_essence] = int(essence_counts[selected_essence]) - 1
	if int(essence_counts.get(selected_essence, 0)) <= 0:
		_cycle_essence()


func _cycle_essence() -> void:
	var start := ESSENCES.find(selected_essence)
	for step in range(1, ESSENCES.size() + 1):
		var candidate: String = ESSENCES[(start + step) % ESSENCES.size()]
		if int(essence_counts.get(candidate, 0)) > 0:
			selected_essence = candidate
			return
	# Tyhjä varasto käyttää heikkoa vihreää peruskaikua, jotta X ei lukitse kittiä.
	selected_essence = "green"


func essence_color() -> Color:
	return essence_color_for(selected_essence)


func essence_color_for(kind: String) -> Color:
	match kind:
		"red": return Color("ff704a")
		"blue": return Color("66b7ff")
		"green": return Color("79df76")
		"void": return Color("c477ff")
	return hero_color()


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 700.0


func _ult_default_range() -> float:
	return 450.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	var essence := selected_essence
	var ec := essence_color_for(essence)
	Fx.ultimate_warning(arena, target, Palette.glow(ec, 1.6),
		Palette.team(team), ULT_RADIUS, 0.6, "myria")
	Fx.ultimate_field(arena, target, ec, Palette.team(team), ULT_RADIUS, 7.0, "myria")
	JungleField.spawn(self, target, "essence", {
		"variant": essence, "radius": ULT_RADIUS, "dur": 7.0,
		"dps": 31.0 if essence != "green" else 24.0, "tick": 0.38,
		"color": ec,
	})
	arena.popup(target + Vector2(0, -ULT_RADIUS - 24),
		"NELJÄ KAIKUA — %s" % essence.to_upper(), ec, 23)
	AudioMgr.play("ult", 0.12, -3.0, target)
	controller_rumble(0.55, 0.85, 0.32)


func _passive_update(delta: float) -> void:
	_essence_flash = maxf(_essence_flash - delta, 0.0)


func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	if not is_instance_valid(target) or not target is Critter \
			or int(essence_counts.get(selected_essence, 0)) > 0:
		return false
	for essence in ESSENCES:
		if essence != selected_essence and int(essence_counts.get(essence, 0)) > 0:
			return true
	return false
