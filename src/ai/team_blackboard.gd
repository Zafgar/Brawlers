class_name TeamBlackboard
extends RefCounted
## Joukkueen jaettu taktinen tilannekuva. Kaikki saman joukkueen botit
## lukevat tätä, jotta ne toimivat yhtenä ryhmänä: kuka kantaa reliikkiä,
## ketä suojataan, kuka johtaa rintamaa ja missä viholliset ovat.

var arena = null
var team := 0

var own_carrier: Hero = null       # oma reliikinkantaja (jos on)
var enemy_carrier: Hero = null     # vihollisen kantaja (jos on)
var lowest_ally: Hero = null       # eniten kärsinyt elossa oleva liittolainen
var frontline_ally: Hero = null    # lähimpänä vihollisia oleva liittolainen (johtaa rintamaa)
var protect_ally: Hero = null      # tärkein suojeltava (kantaja > tuki > kärsinyt)
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

	var allies: Array = arena.alive_allies(team)

	# Vihollisten painopiste
	var enemies: Array = arena.alive_enemies(team)
	if enemies.is_empty():
		threat_center = Vector2.ZERO
	else:
		var sum := Vector2.ZERO
		for enemy in enemies:
			sum += enemy.global_position
		threat_center = sum / enemies.size()

	# Eniten kärsinyt liittolainen
	lowest_ally = null
	var worst := 2.0
	for ally in allies:
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			lowest_ally = ally

	# Rintamaa johtava (lähimpänä vihollisia)
	frontline_ally = null
	if threat_center != Vector2.ZERO:
		var best_d := 1e20
		for ally in allies:
			var d: float = ally.global_position.distance_to(threat_center)
			if d < best_d:
				best_d = d
				frontline_ally = ally

	# Suojeltava: kantaja tärkein, sitten oma tuki, sitten kärsinyt
	protect_ally = own_carrier
	if protect_ally == null:
		for ally in allies:
			if HeroDef.get_def(ally.hero_id)["role"] == "Tuki":
				protect_ally = ally
				break
		if protect_ally == null:
			protect_ally = lowest_ally


func on_relic_taken(_hero) -> void:
	alert_timer = 3.0


func on_enemy_has_relic(_hero) -> void:
	alert_timer = 4.0


func on_relic_free() -> void:
	alert_timer = 2.0
