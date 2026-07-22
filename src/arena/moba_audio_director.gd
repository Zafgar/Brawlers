class_name MobaAudioDirector
extends Node
## Eternal Dividen adaptiivinen ympäristöääni. Valitsee hiljaisen kerroksen
## kuuntelijan alueen mukaan ja toimii myös 1–4 kuuntelijan split screenissä.
## Varsinaiset taistelu- ja objective-cuet tulevat peliobjekteilta; tämä luokka
## tekee kartasta elävän ilman jatkuvaa äänimattoa tai simulaatiokuormaa.

var arena = null
var map: MapMoba = null

var _environment_timer := 0.45
var _detail_timer := 2.2
var _pit_timer := 1.4
var _listener_index := 0
var _rng := RandomNumberGenerator.new()


func setup(p_arena, p_map: MapMoba) -> void:
	arena = p_arena
	map = p_map
	_rng.seed = 904221


func _process(delta: float) -> void:
	if Game.simulating or arena == null or map == null:
		return
	# INTRO ja PLAY saavat ambienssin; loppuruudun odotuksessa maailma hiljenee.
	if int(arena.state) > 1:
		return

	_environment_timer -= delta
	_detail_timer -= delta
	_pit_timer -= delta
	if _environment_timer <= 0.0:
		_play_environment_layer()
		var count := _listener_points().size()
		_environment_timer = 0.72 if count > 1 else 2.05
	if _detail_timer <= 0.0:
		_play_environment_detail()
		_detail_timer = _rng.randf_range(4.2, 7.0)
	if _pit_timer <= 0.0:
		_play_objective_presence()
		_pit_timer = 4.8


func _listener_points() -> Array:
	if not AudioMgr.listener_positions.is_empty():
		return AudioMgr.listener_positions.duplicate()
	if AudioMgr.listener_on:
		return [AudioMgr.listener_pos]
	# Ensimmäisillä intro-frameillä kamera ei ehkä ole vielä asettanut
	# kuuntelijaa. Käytä silloin paikallisen pelaajan spawnia.
	for hero in arena.heroes:
		if is_instance_valid(hero) and not hero.is_unit and not hero.profile.is_bot:
			return [hero.global_position]
	return [Vector2.ZERO]


func _next_listener() -> Vector2:
	var points := _listener_points()
	if points.is_empty():
		return Vector2.ZERO
	_listener_index %= points.size()
	var point: Vector2 = points[_listener_index]
	_listener_index = (_listener_index + 1) % points.size()
	return point


func _play_environment_layer() -> void:
	var listener := _next_listener()
	var sound := "ambient_jungle"
	var volume := -7.0
	if absf(listener.x) > 2600.0:
		sound = "ambient_blue_base" if listener.x < 0.0 else "ambient_orange_base"
		volume = -6.0
	elif absf(listener.x) < 310.0 and absf(listener.y) < 1260.0:
		sound = "ambient_river"
		volume = -6.5
	elif absf(listener.y) > 1260.0:
		sound = "ambient_lane"
		volume = -8.0
	var source_pos := listener + Vector2(
		_rng.randf_range(-180.0, 180.0), _rng.randf_range(-140.0, 140.0))
	AudioMgr.play(sound, 0.025, volume, source_pos)


func _play_environment_detail() -> void:
	var listener := _next_listener()
	# Jungle/puska saa orgaanisen kahahduksen hieman katseen sivulta. Basessa
	# vastaavan yksityiskohdan hoitaa resonanssikerros, joten sitä ei tuplata.
	if absf(listener.x) < 2600.0 and absf(listener.y) < 1320.0:
		var offset := Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) \
			* _rng.randf_range(190.0, 390.0)
		AudioMgr.play("ambient_brush", 0.08, -10.0, listener + offset)


func _play_objective_presence() -> void:
	var listener := _next_listener()
	var baron_pos := map.boss_spot()
	var dragon_pos := map.dragon_spot()
	var baron_dist := listener.distance_to(baron_pos)
	var dragon_dist := listener.distance_to(dragon_pos)
	if baron_dist < 920.0 and baron_dist <= dragon_dist:
		AudioMgr.play("ambient_baron_pit", 0.02, -5.5, baron_pos)
	elif dragon_dist < 920.0:
		AudioMgr.play("ambient_dragon_pit", 0.02, -6.0, dragon_pos)
