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
var _returning := false
var _retarget_timer := 0.0
const RETARGET_INTERVAL := 0.14


func is_bot() -> bool:
	return true


## Kykypisteiden kehitystila ei koske yksiköitä.
func spend_held() -> bool:
	return false


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
		_returning = true
		_target = null
	if _returning:
		# Complete the leash reset before reacquiring a target. This prevents
		# boundary ping-pong and risk-free ranged damage from outside the camp.
		if to_home.length() <= 46.0:
			_returning = false
			if hero.has_method("on_leash_reset"):
				hero.on_leash_reset()
			else:
				hero.hp = hero.max_hp
				hero._recent_damagers.clear()
			return
		var dir: Vector2 = to_home.normalized()
		_mv = _avoid_walls(hero, (dir + dir.orthogonal() * 0.4 * _strafe).normalized())
		return

	_retarget_timer -= delta
	var target_lost := _target != null and (not is_instance_valid(_target) or not _target.alive)
	if _retarget_timer <= 0.0 or target_lost:
		_retarget_timer = RETARGET_INTERVAL
		_target = _pick_target(hero, pos)
	if _target != null and is_instance_valid(_target):
		var to_t: Vector2 = _target.global_position - pos
		var dist: float = to_t.length()
		if dist > 0.5:
			_aim = to_t.normalized()
		if dist > attack_range:
			# Lähesty pienellä kiertoliikkeellä (ei suoraa törmäystä).
			var perp: Vector2 = _aim.orthogonal() * _strafe
			_mv = _avoid_walls(hero, (_aim + perp * 0.32).normalized())
		else:
			_attack = true
	elif to_home.length() > 46.0:
		# Ei kohdetta -> ajaudu takaisin kotileirille vuorottelevalla sivuliikkeellä
		# (ei juutu leirialkovin seinän kulmaan matkalla kotiin).
		var hdir: Vector2 = to_home.normalized()
		_mv = _avoid_walls(hero, (hdir + hdir.orthogonal() * 0.3 * _strafe).normalized())
	else:
		# Laiduntelu: kotipesässä olento kiertelee hitaasti pienellä kehällä sen
		# sijaan että seisoisi naulittuna — leirit näyttävät eläviltä kaukaakin.
		# Monotoninen kello (match_elapsed) -> aito kierto ilman sahalaitahyppyä;
		# vaihesiirto johdetaan kodista, joten leirit eivät tanssi tahdissa.
		var graze: float = hero.arena.match_elapsed * 0.9 \
			+ home.x * 0.013 + home.y * 0.007
		var spot: Vector2 = home + Vector2(cos(graze), sin(graze)) * 34.0
		if pos.distance_to(spot) > 14.0:
			_mv = (spot - pos).normalized() * 0.3


## Kohdevalinta: 1) tuorein vahingoittaja (kosto), 2) lähin pelaaja aggro-
## säteellä. Jo valittua kohdetta seurataan hieman kauemmas (hystereesi).
func _pick_target(hero, pos: Vector2) -> Hero:
	var threat := _recent_attacker(hero, pos)
	if threat != null:
		return threat
	var best: Hero = null
	var best_d_sq := 1.0e20
	for enemy in hero.arena.alive_enemies(hero.team):
		if enemy.is_unit:
			continue   # monsteri ei vedä aggroa minioneihin tai rakennuksiin
		var limit: float = aggro_radius * (1.4 if enemy == _target else 1.0)
		var d_sq: float = enemy.global_position.distance_squared_to(pos)
		if d_sq <= limit * limit and d_sq < best_d_sq:
			best_d_sq = d_sq
			best = enemy
	return best


func _avoid_walls(hero, desired: Vector2) -> Vector2:
	if desired.length() < 0.1:
		return desired
	var space: PhysicsDirectSpaceState2D = hero.get_world_2d().direct_space_state
	var origin: Vector2 = hero.global_position
	var look: float = hero.radius + 82.0
	var direct := PhysicsRayQueryParameters2D.create(origin, origin + desired * look, 1)
	if space.intersect_ray(direct).is_empty():
		return desired
	# Neutraali ei tarvitse täyttä pathfinderia: viuhka pitää sen omassa pitissä
	# ja löytää objective-/leirialkovin avoimen sivun luotettavasti.
	for angle in [0.55, -0.55, 1.0, -1.0, 1.45, -1.45]:
		var candidate: Vector2 = desired.rotated(float(angle) * _strafe).normalized()
		var ray := PhysicsRayQueryParameters2D.create(origin, origin + candidate * look, 1)
		if space.intersect_ray(ray).is_empty():
			return candidate
	return -desired * 0.35


## Viimeksi olentoa lyönyt pelaaja (leashin sisällä, tuoreen ikkunan aikana).
func _recent_attacker(hero, pos: Vector2) -> Hero:
	# Peliaika pitää uhkaikkunan oikean mittaisena myös nopeutetussa simissä.
	var now: float = hero.arena.match_elapsed
	var best: Hero = null
	var best_time := -1.0
	for entry in hero._recent_damagers:
		var h = entry.hero
		if not is_instance_valid(h) or not h.alive:
			continue
		if h.is_unit:
			continue
		if h.team == hero.team:
			continue
		if now - float(entry.time) > threat_window:
			continue
		if h.global_position.distance_squared_to(pos) > leash * leash:
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
