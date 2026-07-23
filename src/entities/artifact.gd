class_name LegendaryArtifact
extends Node2D
## Baronin pudottama legendaarinen artefakti (MOBA). Lojuu maassa kunnes
## joku poimii sen: ihminen painaa interactia (Ympyrä/F) säteellä, botti
## poimii seisottuaan hetken päällä. Poimittu artefakti kuluu legendaarisen
## itemin ostoon kaupassa; kantajan kuollessa arena pudottaa uuden artefaktin
## kuolinpaikalle (on_hero_ko). Ei katoamisaikaa — odottaa poimijaansa.

const PICKUP_RADIUS := 90.0
const BOT_PICK_TIME := 0.4       # botti poimii seisottuaan tämän ajan säteellä

var arena = null
var _time := 0.0
var _bot_hold := {}              # sankarin instanssi-id -> aika säteellä
var _deny_t := 0.0               # "sinulla on jo" -popupin kuristus


func setup(p_arena, pos: Vector2) -> void:
	arena = p_arena
	global_position = pos
	z_index = 18
	arena.artifacts.append(self)


func _physics_process(delta: float) -> void:
	_time += delta
	_deny_t = maxf(_deny_t - delta, 0.0)
	if arena == null or arena.state != arena.State.PLAY:
		return
	queue_redraw()
	var seen := {}
	for hero in arena.heroes:
		if not is_instance_valid(hero) or hero.is_unit or not hero.alive:
			continue
		if hero.global_position.distance_to(global_position) > PICKUP_RADIUS + hero.radius:
			continue
		var hid := hero.get_instance_id()
		seen[hid] = true
		if hero.controller == null:
			continue
		if bool(hero.controller.is_bot()):
			# Botti: kävely päälle riittää — poiminta pienen viiveen jälkeen.
			if bool(hero.legendary_artifact):
				continue
			var held: float = float(_bot_hold.get(hid, 0.0)) + delta
			_bot_hold[hid] = held
			if held >= BOT_PICK_TIME:
				_pickup(hero)
				return
		elif hero.controller.has_method("drop_just") and bool(hero.controller.drop_just()):
			if bool(hero.legendary_artifact):
				if _deny_t <= 0.0:
					_deny_t = 1.0
					arena.popup(hero.global_position + Vector2(0, -64),
						"SINULLA ON JO ARTEFAKTI", Palette.BAD, 15)
					AudioMgr.play("ui_back", 0.05, -8.0)
			else:
				_pickup(hero)
				return
	# Poistuneiden bottien pitoaika nollautuu (keys() on kopio -> turvallinen).
	for hid_v in _bot_hold.keys():
		if not seen.has(hid_v):
			_bot_hold.erase(hid_v)


func _pickup(hero) -> void:
	hero.legendary_artifact = true
	arena.artifacts.erase(self)
	arena.hud.show_banner("%s POIMI ARTEFAKTIN!" % str(hero.profile.display_name),
		"Legendaarinen esine on nyt ostettavissa kaupassa", 2.2)
	arena.hud.ko_feed("%s poimi artefaktin!" % str(hero.profile.display_name))
	hero.controller_rumble(0.4, 0.25, 0.3)
	Fx.flash(arena, global_position, Palette.glow(Palette.GOLD, 1.6), 70.0, 0.4)
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.5), 110.0, 0.6, 6.0)
	Fx.burst(arena, global_position, Palette.glow(Palette.GOLD, 1.6), 18, 320.0, 0.6, 6.0)
	AudioMgr.play("blessing", 0.04, -2.0, global_position)
	queue_free()


func _draw() -> void:
	if arena != null and Game.simulating and not Game.sim_visuals:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	# Varjo maahan.
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 17.0, Color(0.02, 0.03, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Poimintasäde himmeänä + valokeila ylös.
	draw_arc(Vector2.ZERO, PICKUP_RADIUS, 0.0, TAU, 40,
		Palette.with_alpha(Palette.GOLD, 0.16 + pulse * 0.1), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, -8.0), Vector2(4.0, -8.0),
		Vector2(10.0, -120.0), Vector2(-10.0, -120.0)]),
		Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4), 0.10 + pulse * 0.08))
	# Hehku + hitaasti pyörivä kultatimantti (leijuu kevyesti).
	var bob := sin(_time * 2.0) * 4.0
	draw_circle(Vector2(0, -14.0 + bob), 24.0 + pulse * 4.0,
		Palette.with_alpha(Palette.GOLD, 0.14))
	draw_set_transform(Vector2(0, -14.0 + bob), _time * 0.8, Vector2.ONE)
	var r := 15.0 + pulse * 1.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -r), Vector2(r * 0.72, 0), Vector2(0, r), Vector2(-r * 0.72, 0)]),
		Palette.glow(Palette.GOLD, 1.45))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -r * 0.5), Vector2(r * 0.36, 0), Vector2(0, r * 0.5),
		Vector2(-r * 0.36, 0)]), Palette.glow(Color.WHITE, 1.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
