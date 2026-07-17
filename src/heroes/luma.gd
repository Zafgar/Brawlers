class_name Luma
extends Hero
## Tuki: valosauva. Parantaa, suojaa ja nopeuttaa joukkuetta.
## Passiivi: palautuu itsekseen nopeasti taistelun ulkopuolella.

func _init() -> void:
	radius = 24.0


## Perushyökkäys: valopulssi — vahingoittaa vihollisia ja parantaa
## liittolaiset, joiden läpi se kulkee.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("bow", 0.12, -4.0)
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 800.0,
		"dmg": 12.0,
		"radius": 10.0,
		"life": 0.85,
		"kb": 80.0,
		"pierce": 1,
		"heal_allies": 10.0,
		"color": Color("ffe9a8"),
	})


## Kyky 1: Hoitokehä — parantava purkaus ympärillä.
func _ability1(_dir: Vector2) -> void:
	AudioMgr.play("heal")
	Fx.ring(arena, global_position, Palette.glow(Palette.HEAL, 1.5), 190.0, 0.5, 6.0)
	for ally in arena.heroes_in_circle(global_position, 190.0, team):
		ally.heal_hp(30.0, self)
	visual.squash(1.2, 0.85)


## Kyky 2: Suojasäde — suojakilpi eniten kärsineelle liittolaiselle.
func _ability2(_dir: Vector2) -> void:
	var target: Hero = null
	var worst_frac := 1.1
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		if ally.global_position.distance_to(global_position) > 500.0:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst_frac:
			worst_frac = frac
			target = ally
	if target == null:
		target = self
	target.add_shield(45.0, 3.5, self)
	Fx.ring(arena, target.global_position, Palette.glow(Palette.SHIELD, 1.5), 60.0, 0.4)
	arena.popup(target.global_position + Vector2(0, -70), "SUOJATTU", Palette.SHIELD, 16)


## Väistö: kevyt pyrähdys, joka antaa hetkeksi vauhtia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	apply_haste(1.25, 1.0)
	AudioMgr.play("dash")
	Fx.dust(arena, global_position)


## Ultimate: Valokenttä — suuri alue, joka parantaa ja nopeuttaa joukkuetta.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "VALOKENTTÄ!", Palette.glow(Palette.GOLD, 1.5), 24)
	AudioMgr.play("heal", 0.05, 2.0)
	Zone.spawn(self, global_position, {
		"type": "heal",
		"radius": 260.0,
		"dur": 6.0,
		"heal_ps": 22.0,
	})
	Zone.spawn(self, global_position, {
		"type": "haste",
		"radius": 260.0,
		"dur": 6.0,
		"haste_f": 1.3,
	})


## Passiivi: nopea itsepalautuminen taistelun ulkopuolella.
func _passive_update(delta: float) -> void:
	if since_damage > 3.0 and hp < max_hp:
		hp = minf(hp + 6.0 * delta, max_hp)
