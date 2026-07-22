class_name Luma
extends Hero
## Tuki: valosauva. Joukkueen sydän — parantaa, suojaa ja nopeuttaa.
## Passiivi: palautuu itsekseen nopeasti taistelun ulkopuolella.

func _init() -> void:
	radius = 24.0


## Mana: hoidot ja suojat maksavat manaa mutta jäähtyvät nopeasti — voit
## ketjuttaa parannuksia ja kilpiä kunnes mana loppuu, sitten se palautuu.
## Valopulssi (perus) on ilmainen.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 14.0
	res_cost = {"basic": 0.0, "a1": 30.0, "a2": 24.0, "dodge": 0.0}
	cd_max.a1 = 1.5
	cd_max.a2 = 1.2


## Perushyökkäys: valopulssi — vahingoittaa vihollisia ja parantaa
## liittolaiset, joiden läpi se kulkee.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("luma_pulse", 0.08, -5.0, global_position)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Palette.GOLD, 1.4))
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 820.0,
		"dmg": 12.0,
		"radius": 10.0,
		"life": 0.85,
		"kb": 80.0,
		"pierce": 1,
		"heal_allies": 12.0,
		"color": Color("ffe9a8"),
		"visual": "luma_pulse",
	})


## Kyky 1: Hoitokehä — parantava purkaus ympärillä.
func _ability1(_dir: Vector2) -> void:
	AudioMgr.play("luma_bloom", 0.05, 0.0, global_position)
	ability_signature("luma", 195.0)
	controller_rumble(0.12, 0.02, 0.16)
	Fx.ring(arena, global_position, Palette.glow(Palette.HEAL, 1.5), 195.0, 0.5, 6.0)
	visual.squash(1.2, 0.85)
	for ally in arena.heroes_in_circle(global_position, 195.0, team):
		ally.heal_hp(32.0, self)


## Kyky 2: Suojasäde — suojakilpi eniten kärsineelle liittolaiselle.
func _ability2(_dir: Vector2) -> void:
	var target: Hero = null
	var worst_frac := 1.1
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		if ally.global_position.distance_to(global_position) > 520.0:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst_frac:
			worst_frac = frac
			target = ally
	if target == null:
		target = self
	AudioMgr.play("luma_shield", 0.05, 0.0, global_position)
	ability_signature("luma", 105.0, (target.global_position - global_position).normalized())
	if target != self:
		Fx.beam(arena, global_position, target.global_position, Palette.glow(Palette.SHIELD, 1.3))
	target.add_shield(50.0, 4.0, self)
	Fx.ring(arena, target.global_position, Palette.glow(Palette.SHIELD, 1.5), 62.0, 0.4)
	arena.popup(target.global_position + Vector2(0, -70), "SUOJATTU", Palette.SHIELD, 16)


## Väistö: kevyt pyrähdys, joka antaa hetkeksi vauhtia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	apply_haste(1.25, 1.0)
	AudioMgr.play("dash", 0.1, 2.0, global_position)
	Fx.dust(arena, global_position)


## Ultimate: Valokenttä — suuri alue, joka parantaa ja nopeuttaa joukkuetta.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "VALOKENTTÄ!", Palette.glow(Palette.GOLD, 1.5), 26)
	AudioMgr.play("luma_ult", 0.03, 1.0, global_position)
	controller_rumble(0.28, 0.08, 0.42)
	# Valopatsas
	Fx.flash(arena, global_position, Palette.glow(Color("ffe9a8"), 1.6), 130.0, 0.6)
	Fx.ring(arena, global_position, Palette.glow(Palette.HEAL, 1.5), 260.0, 0.7, 8.0)
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.4), 200.0, 0.6, 5.0)
	Zone.spawn(self, global_position, {
		"type": "heal",
		"radius": 260.0,
		"dur": 6.0,
		"heal_ps": 22.0,
		"visual": "luma_field",
	})
	Zone.spawn(self, global_position, {
		"type": "haste",
		"radius": 260.0,
		"dur": 6.0,
		"haste_f": 1.3,
		"visual": "hidden",
	})
	# Välitön suoja kentällä oleville liittolaisille
	for ally in arena.heroes_in_circle(global_position, 260.0, team):
		ally.add_shield(20.0, 3.0, self)


## Passiivi: nopea itsepalautuminen taistelun ulkopuolella.
func _passive_update(delta: float) -> void:
	if since_damage > 3.0 and hp < max_hp:
		hp = minf(hp + 6.0 * delta, max_hp)
