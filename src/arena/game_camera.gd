class_name GameCamera
extends Camera2D
## Yhteinen kamera: rajaa kaikki elossa olevat sankarit ja reliikin näkyviin,
## zoomaa pehmeästi ja tärähtää osumista (jos asetuksissa sallittu).

const MARGIN := 260.0
const MIN_ZOOM := 0.76
const MAX_ZOOM := 1.05
const FOLLOW_SPEED := 3.5
const ZOOM_SPEED := 2.5

var arena = null
var _shake_strength := 0.0
var _noise_t := 0.0


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	if arena == null or arena.heroes.is_empty():
		return

	var rect := Rect2(arena.relic.global_position, Vector2.ONE) if arena.relic != null \
		else Rect2(Vector2.ZERO, Vector2.ONE)
	var any := false
	for hero in arena.heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		if hero.team >= 2:
			continue   # neutraalit viidakko-olennot eivät venytä kameraa
		if not any:
			rect = Rect2(hero.global_position, Vector2.ONE)
			any = true
		else:
			rect = rect.expand(hero.global_position)
	if arena.relic != null and is_instance_valid(arena.relic):
		rect = rect.expand(arena.relic.global_position)
	rect = rect.grow(MARGIN)

	var viewport_size := get_viewport_rect().size
	var fit: float = minf(viewport_size.x / rect.size.x, viewport_size.y / rect.size.y)
	var target_zoom: float = clampf(fit, MIN_ZOOM, MAX_ZOOM)

	global_position = global_position.lerp(rect.get_center(), 1.0 - exp(-FOLLOW_SPEED * delta))
	var z: float = lerpf(zoom.x, target_zoom, 1.0 - exp(-ZOOM_SPEED * delta))
	zoom = Vector2(z, z)

	# Tärinä
	_shake_strength = maxf(_shake_strength - delta * 2.2, 0.0)
	if _shake_strength > 0.001 and Game.options.shake:
		_noise_t += delta * 40.0
		var amp: float = _shake_strength * _shake_strength * 22.0
		offset = Vector2(
			sin(_noise_t * 1.1) * amp,
			cos(_noise_t * 0.9) * amp)
	else:
		offset = Vector2.ZERO


func add_shake(amount: float) -> void:
	_shake_strength = clampf(_shake_strength + amount, 0.0, 1.0)
