class_name Scout
extends Hero
## Ranger: vaahtopallo-konekivääri. Iso lipas ja pitkä lataus — pidä liipaisin
## pohjassa ryöpyttääksesi, ja lataa kesken taistelun kierähtämällä (X).
## Merkitsee kohteita (koko joukkue tekee niihin lisävahinkoa) ja tainnuttaa
## pienellä aluepamahduksella. Passiivi: osumat lataavat energiaa.

const MAG_SIZE := 26                # lippaan koko (patruunat)
const FIRE_INTERVAL := 0.09         # aika laukausten välillä (konekivääri)
const RELOAD_TIME := 2.5            # automaattisen latauksen kesto
const SHOT_DMG := 6.0

const MARK_DUR := 4.5
const MARK_AMP := 1.45              # merkitty kohde ottaa +45 % vahinkoa (vahva)

const STUN_AOE_RADIUS := 95.0
const STUN_DUR := 0.8

var _reload_time := 0.0


func _init() -> void:
	radius = 23.0


## Energia: merkki- ja tainnutuspallot maksavat energiaa, joka karttuu ennen
## kaikkea konekiväärin osumista. Perusammunta on ilmainen mutta rajattu
## lippaalla — lataa kierähtämällä (X) tai odota pitkä automaattilataus.
func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = 100.0
	res_regen = 13.0
	res_cost = {"basic": 0.0, "a1": 30.0, "a2": 36.0, "dodge": 0.0}
	cd_max.a1 = 1.6
	cd_max.a2 = 2.2
	ammo_max = MAG_SIZE
	ammo = MAG_SIZE


## Sekä merkkipanos (R1) että tainnutuspallo (L1) tähdätään: pidä pohjassa
## (tähtäysviiva) ja vapauta laukaistaksesi.
func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _aim_range(slot: String) -> float:
	return 640.0 if slot == "a1" else 460.0


# --- Konekivääri: lipas + lataus ---

## Perusammunnan ohjaus korvaa oletuksen: pidä liipaisin pohjassa ryöpyttääksesi
## patruunan kerrallaan, kunnes lipas tyhjenee -> pitkä automaattilataus.
func _attack_control(held: bool, _just_pressed: bool, _just_released: bool,
		dir: Vector2, _delta: float) -> void:
	if reloading:
		return
	if ammo <= 0:
		_start_reload()
		return
	if held and cd.basic <= 0.0:
		cd.basic = FIRE_INTERVAL
		_fire_one(dir)


func _fire_one(dir: Vector2) -> void:
	ammo -= 1
	visual.attack_swing()
	AudioMgr.play("pop", 0.12, -1.0)
	var spread := randf_range(-0.05, 0.05)
	Projectile.launch(self, global_position + dir * 28.0, dir.rotated(spread), {
		"speed": 1000.0,
		"dmg": SHOT_DMG,
		"radius": 7.0,
		"life": 0.7,
		"kb": 55.0,
		"color": hero_color(),
	})
	if ammo <= 0:
		_start_reload()


func _start_reload() -> void:
	if reloading:
		return
	reloading = true
	_reload_time = RELOAD_TIME
	AudioMgr.play("ui_back", 0.05, -6.0)
	arena.popup(global_position + Vector2(0, -70), "LATAA…",
		Palette.with_alpha(Palette.TEXT_DIM, 0.95), 15)


func _finish_reload() -> void:
	reloading = false
	ammo = MAG_SIZE
	AudioMgr.play("count_tick", 0.05, -1.0)
	Fx.spark(arena, global_position, hero_color())


## Lataus etenee myös tainnutuksen/tähtäyksen aikana.
func _passive_update(delta: float) -> void:
	if reloading:
		_reload_time -= delta
		if _reload_time <= 0.0:
			_finish_reload()


## Perushyökkäys (varapolku boteille, jotka eivät ohjaa liipaisinta pito­logiikalla).
func _basic(dir: Vector2) -> void:
	if reloading or ammo <= 0:
		return
	_fire_one(dir)


## Kyky 1: Merkkipanos — pitkän kantaman tarkkuuspanos, joka merkitsee kohteen.
## Merkitty kohde ottaa selvästi enemmän vahinkoa kaikilta.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("pop", 0.08, -2.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 1300.0,
		"dmg": 12.0,
		"radius": 10.0,
		"life": 1.0,
		"kb": 100.0,
		"color": Palette.glow(Palette.GOLD, 1.3),
		"on_hit": Callable(self, "_mark_target"),
	})


func _mark_target(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	hit_hero.apply_mark(MARK_DUR, MARK_AMP)
	AudioMgr.play("mark", 0.05)
	Fx.ring(arena, hit_hero.global_position, Palette.glow(Palette.GOLD, 1.5), 50.0, 0.4)
	# Tähtäinristikko kohteen ylle
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2.RIGHT.rotated(ang)
		Fx.spark(arena, hit_hero.global_position + d * 30.0, Palette.GOLD)


## Kyky 2: Tainnutuspallo — tähdättävä tahmea pallo, joka pamahtaa osuessaan
## ja tainnuttaa pienellä alueella.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("pop", 0.08, -6.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 900.0,
		"dmg": 8.0,
		"radius": 11.0,
		"life": 0.85,
		"kb": 60.0,
		"color": Color("f2f5ff"),
		"on_hit": Callable(self, "_stun_target"),
	})


func _stun_target(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	var center: Vector2 = hit_hero.global_position
	AudioMgr.play("pop", 0.1, -8.0)
	# Vaahtoräjähdys ja aluepamahdus
	Fx.burst(arena, center, Color(1, 1, 1, 0.85), 16, 240.0, 0.45, 6.0)
	Fx.ring(arena, center, Palette.with_alpha(Color.WHITE, 0.7), STUN_AOE_RADIUS, 0.4, 4.0)
	for enemy in arena.heroes_in_circle(center, STUN_AOE_RADIUS):
		if enemy.team == team:
			continue
		enemy.apply_stun(STUN_DUR)
		Fx.spark(arena, enemy.global_position, Color.WHITE)


## Väistö: kierähdys, joka lataa kiväärin heti — X:n pointti kesken taistelun.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	var needed: bool = reloading or ammo < ammo_max
	reloading = false
	_reload_time = 0.0
	ammo = MAG_SIZE
	AudioMgr.play("dash", 0.12, 2.0)
	Fx.dust(arena, global_position)
	if needed:
		arena.popup(global_position + Vector2(0, -70), "LADATTU!", Palette.glow(Palette.GOLD, 1.3), 16)
		Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.3), 44.0, 0.35)


## Ultimate: Merkkisade — merkitsee kaikki lähiviholliset (vahvalla merkillä)
## ja kiihdyttää joukkueen.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "MERKKISADE!", Palette.glow(Palette.GOLD, 1.5), 26)
	AudioMgr.play("mark", 0.02, -2.0)
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.6), 640.0, 0.7, 6.0)
	Fx.ring(arena, global_position, Palette.with_alpha(Palette.GOLD, 0.5), 400.0, 0.6, 4.0)
	for enemy in arena.alive_enemies(team):
		if enemy.global_position.distance_to(global_position) < 640.0:
			enemy.apply_mark(5.0, MARK_AMP)
			Fx.spark(arena, enemy.global_position, Palette.GOLD)
	for ally in arena.alive_allies(team):
		ally.apply_haste(1.2, 3.0)
