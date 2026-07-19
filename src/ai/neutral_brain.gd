class_name NeutralBrain
## Viidakko-olentojen ohjain. Pysyy leirinsä lähellä, hyökkää lähelle tulevia
## pelaajia (joukkueet 0/1) vastaan ja palaa kotiin jos se houkutellaan liian
## kauas. Toteuttaa saman rajapinnan kuin DeviceInput/BotBrain, mutta ei käytä
## kykyjä, väistöä eikä ultia — pelkkää liikettä ja perushyökkäystä.

# Vaikeuskertoimet luetaan Hero.setupissa kun is_bot() == true. Neutraaleilla
# nämä pysyvät 1.0:ssa (ei huijausta suuntaan tai toiseen).
var damage_mult := 1.0
var damage_taken_mult := 1.0
var cooldown_mult := 1.0
var ult_gain_mult := 1.0
var speed_mult := 1.0

var home := Vector2.ZERO
var aggro_radius := 260.0        # kuinka läheltä olento havaitsee pelaajan
var attack_range := 76.0         # kuinka läheltä se pysähtyy lyömään
var leash := 380.0               # kuinka kauas kotoa se lähtee ennen paluuta

var _mv := Vector2.ZERO
var _aim := Vector2.RIGHT
var _attack := false
var _target: Hero = null


func is_bot() -> bool:
	return true


func update(hero, _delta: float) -> void:
	_attack = false
	_mv = Vector2.ZERO
	var pos: Vector2 = hero.global_position
	var to_home: Vector2 = home - pos
	# Houkuteltu liian kauas -> unohda kohde ja palaa leirille.
	if to_home.length() > leash:
		_target = null
		_mv = to_home.normalized()
		return

	_target = _pick_target(hero, pos)
	if _target != null:
		var to_t: Vector2 = _target.global_position - pos
		if to_t.length() > 0.5:
			_aim = to_t.normalized()
		if to_t.length() > attack_range:
			_mv = to_t.normalized()
		else:
			_attack = true
	elif to_home.length() > 46.0:
		# Ei kohdetta -> ajaudu takaisin kotileirille.
		_mv = to_home.normalized()


## Lähin elossa oleva pelaaja aggro-säteellä. Jo valittua kohdetta seurataan
## hieman kauemmas (1.4x), jottei aggro heilu edestakaisin rajalla.
func _pick_target(hero, pos: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1.0e20
	for enemy in hero.arena.alive_enemies(hero.team):
		var d: float = enemy.global_position.distance_to(pos)
		var limit: float = aggro_radius * (1.4 if enemy == _target else 1.0)
		if d <= limit and d < best_d:
			best_d = d
			best = enemy
	return best


func move_vector() -> Vector2:
	return _mv


func aim_vector() -> Vector2:
	return _aim


func attack_held() -> bool:
	return _attack


func attack_just_pressed() -> bool:
	return _attack


func attack_just_released() -> bool:
	return false


func ability1_just() -> bool:
	return false


func ability2_just() -> bool:
	return false


func ability1_held() -> bool:
	return false


func ability2_held() -> bool:
	return false


func ability1_released() -> bool:
	return false


func ability2_released() -> bool:
	return false


func ult_held() -> bool:
	return false


func ult_released() -> bool:
	return false


func dodge_just() -> bool:
	return false


func ult_just() -> bool:
	return false


func drop_just() -> bool:
	return false
