class_name NeutralBrain
## Viidakko-olentojen ohjain. Pysyy leirinsä lähellä, hyökkää pelaajia
## (joukkueet 0/1) vastaan ja palaa kotiin jos se houkutellaan liian kauas.
## Toteuttaa saman rajapinnan kuin DeviceInput/BotBrain, mutta ei käytä kykyjä.
##
## Äly: kohdistaa ensisijaisesti siihen pelaajaan joka on viimeksi lyönyt sitä
## (uhka), muuten lähimpään aggro-säteellä olevaan. Lähestyy pienellä
## kiertoliikkeellä eikä puske suoraan päin, ja luopuu kohteesta jos se pakenee
## leashin yli.

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
var threat_window := 5.0         # kuinka tuoreen osuman perusteella se kostaa

var _mv := Vector2.ZERO
var _aim := Vector2.RIGHT
var _attack := false
var _target: Hero = null
var _strafe := 1.0
var _strafe_t := 0.0


func is_bot() -> bool:
	return true


func update(hero, delta: float) -> void:
	_attack = false
	_mv = Vector2.ZERO
	_strafe_t += delta
	if _strafe_t > 1.4:
		_strafe_t = 0.0
		_strafe = -_strafe

	var pos: Vector2 = hero.global_position
	var to_home: Vector2 = home - pos
	# Houkuteltu liian kauas -> unohda kohde ja palaa leirille. Lisää vuorotteleva
	# sivukomponentti (vaihtuu _strafe-ajastimella), ettei olento juutu suoraan
	# leirialkovin seinää vasten paluumatkalla — se liukuu seinää pitkin ympäri.
	if to_home.length() > leash:
		_target = null
		var dir: Vector2 = to_home.normalized()
		_mv = (dir + dir.orthogonal() * 0.4 * _strafe).normalized()
		return

	_target = _pick_target(hero, pos)
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - pos
		var dist: float = to_t.length()
		if dist > 0.5:
			_aim = to_t.normalized()
		if dist > attack_range:
			# Lähesty pienellä kiertoliikkeellä (ei suoraa törmäystä).
			var perp: Vector2 = _aim.orthogonal() * _strafe
			_mv = (_aim + perp * 0.32).normalized()
		else:
			_attack = true
	elif to_home.length() > 46.0:
		# Ei kohdetta -> ajaudu takaisin kotileirille vuorottelevalla sivuliikkeellä
		# (ei juutu leirialkovin seinän kulmaan matkalla kotiin).
		var hdir: Vector2 = to_home.normalized()
		_mv = (hdir + hdir.orthogonal() * 0.3 * _strafe).normalized()


## Kohdevalinta: 1) tuorein vahingoittaja (kosto), 2) lähin pelaaja aggro-
## säteellä. Jo valittua kohdetta seurataan hieman kauemmas (hystereesi).
func _pick_target(hero, pos: Vector2) -> Hero:
	var threat := _recent_attacker(hero, pos)
	if threat != null:
		return threat
	var best: Hero = null
	var best_d := 1.0e20
	for enemy in hero.arena.alive_enemies(hero.team):
		var d: float = enemy.global_position.distance_to(pos)
		var limit: float = aggro_radius * (1.4 if enemy == _target else 1.0)
		if d <= limit and d < best_d:
			best_d = d
			best = enemy
	return best


## Viimeksi olentoa lyönyt pelaaja (leashin sisällä, tuoreen ikkunan aikana).
func _recent_attacker(hero, pos: Vector2) -> Hero:
	var now: float = Time.get_ticks_msec() / 1000.0
	var best: Hero = null
	var best_time := -1.0
	for entry in hero._recent_damagers:
		var h = entry.hero
		if not is_instance_valid(h) or not h.alive:
			continue
		if h.team == hero.team:
			continue
		if now - float(entry.time) > threat_window:
			continue
		if h.global_position.distance_to(pos) > leash:
			continue
		if float(entry.time) > best_time:
			best_time = float(entry.time)
			best = h
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
