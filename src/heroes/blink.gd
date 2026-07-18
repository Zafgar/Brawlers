class_name Blink
extends Hero
## Assassin: kaksi valomiekkaa. Teleporttaa, iskee ja katoaa.
## Passiivi: liikkuu kevyesti nopeammin, kun ei ole otettu vahinkoa hetkeen.
## Selkäänisku: kohteeseen, joka katsoo poispäin, osuu 50 % kovempaa.

const SLASH_RANGE := 75.0
const SLASH_ARC_DEG := 65.0
const SLASH_DMG := 20.0

func _init() -> void:
	radius = 22.0


## Perushyökkäys: nopea valoviilto. Selkäänisku tekee lisävahinkoa.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("blade", 0.15)
	Fx.slash(arena, global_position, dir, SLASH_RANGE, SLASH_ARC_DEG, Color("d9c8ff"))
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SLASH_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SLASH_ARC_DEG:
			continue
		var dmg := SLASH_DMG
		# Selkäänisku: kohde katsoo poispäin Blinkistä -> 50 % lisää.
		if enemy.aim.dot(to_enemy.normalized()) > 0.3:
			dmg *= 1.65
			Fx.spark(arena, enemy.global_position, Palette.glow(hero_color(), 1.9))
			arena.popup(enemy.global_position + Vector2(0, -54), "SELKÄÄN!", hero_color(), 15)
		deal_damage_to(enemy, dmg, 140.0, to_enemy.normalized())


## Kyky 1: Teleportti tähtäyksen suuntaan (jättää valojuovan).
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("blink")
	var from := global_position
	Fx.flash(arena, from, Palette.glow(hero_color(), 1.6), 40.0, 0.3)
	global_position = arena.map.clamp_to_field(global_position + dir * 270.0, 40.0)
	Fx.beam(arena, from, global_position, Palette.glow(Color("d9c8ff"), 1.4), 8.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.6), 46.0, 0.3)
	Fx.ring(arena, global_position, Palette.glow(Color("d9c8ff"), 1.5), 60.0, 0.35)
	iframes = maxf(iframes, 0.25)


## Kyky 2: Valoviuhka — kolme valoterää viuhkana.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("blade", 0.1, -2.0)
	visual.attack_swing()
	for angle_offset in [-0.28, 0.0, 0.28]:
		Projectile.launch(self, global_position + dir * 24.0, dir.rotated(angle_offset), {
			"speed": 950.0,
			"dmg": 15.0,
			"radius": 8.0,
			"life": 0.6,
			"kb": 100.0,
			"color": Color("d9c8ff"),
		})


## Väistö: salamannopea sivuaskel.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	AudioMgr.play("dash", 0.12)
	Fx.dust(arena, global_position)


## Ultimate: Varjotanssi — sarja teleportti-iskuja lähivihollisten läpi.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "VARJOTANSSI!", Palette.glow(hero_color(), 1.5), 24)
	_shadow_dance()


func _shadow_dance() -> void:
	for strike in range(4):
		if not is_inside_tree() or not alive:
			return
		var target: Hero = null
		var best := 520.0
		for enemy in arena.alive_enemies(team):
			var d: float = enemy.global_position.distance_to(global_position)
			if d < best:
				best = d
				target = enemy
		if target == null:
			return
		var offset := Vector2.RIGHT.rotated(randf() * TAU) * (target.radius + 40.0)
		Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.5), 36.0, 0.25)
		global_position = arena.map.clamp_to_field(target.global_position + offset, 40.0)
		iframes = maxf(iframes, 0.3)
		aim = (target.global_position - global_position).normalized()
		visual.attack_swing()
		AudioMgr.play("blade", 0.15)
		Fx.slash(arena, global_position, aim, 60.0, 80.0, Color("d9c8ff"))
		deal_damage_to(target, 32.0, 200.0, aim)
		Fx.spark(arena, target.global_position, Palette.glow(Color("d9c8ff"), 1.9))
		await get_tree().create_timer(0.22).timeout


## Passiivi: kevyt vauhti kun ei paineen alla.
func _passive_update(_delta: float) -> void:
	if since_damage > 2.0:
		apply_haste(1.08, 0.2)
