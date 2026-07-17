class_name TeamBlackboard
extends RefCounted
## Joukkueen jaettu taktinen tilannekuva. Kaikki saman joukkueen botit
## lukevat tätä: kuka kantaa reliikkiä, kuka tarvitsee apua ja missä
## viholliset ovat.

var arena = null
var team := 0

var own_carrier: Hero = null
var enemy_carrier: Hero = null
var lowest_ally: Hero = null       # elossa oleva liittolainen pienimmällä hp-osuudella
var threat_center := Vector2.ZERO  # elossa olevien vihollisten painopiste
var retreat_pos := Vector2.ZERO
var alert_timer := 0.0             # hetkellinen hälytystila (reliikki vaihtoi omistajaa)


func setup(p_arena, p_team: int) -> void:
	arena = p_arena
	team = p_team
	retreat_pos = arena.map.spawn_point(team, 0)


func update(delta: float) -> void:
	alert_timer = maxf(alert_timer - delta, 0.0)

	own_carrier = null
	enemy_carrier = null
	var carrier: Hero = arena.relic.carrier
	if carrier != null and is_instance_valid(carrier) and carrier.alive:
		if carrier.team == team:
			own_carrier = carrier
		else:
			enemy_carrier = carrier

	lowest_ally = null
	var worst := 2.0
	for ally in arena.alive_allies(team):
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			lowest_ally = ally

	var enemies: Array = arena.alive_enemies(team)
	if enemies.is_empty():
		threat_center = Vector2.ZERO
	else:
		var sum := Vector2.ZERO
		for enemy in enemies:
			sum += enemy.global_position
		threat_center = sum / enemies.size()


func on_relic_taken(_hero) -> void:
	alert_timer = 3.0


func on_enemy_has_relic(_hero) -> void:
	alert_timer = 4.0


func on_relic_free() -> void:
	alert_timer = 2.0
