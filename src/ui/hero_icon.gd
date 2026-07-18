class_name HeroIcon
## Sankarien valintatunnukset (kuvakkeet) piirretään koodilla. Käytetään
## medaljongeissa gallerian, lobbyn ja pelaajakorttien kuvakkeina.
## Jokainen viimeistelty sankari saa oman tunnuksensa; muut näyttävät
## toistaiseksi nimikirjaimen.

const INK := Color("f4f7ff")          # vaalea tunnusväri
const SHADE := Color(0.06, 0.08, 0.16, 0.55)


## Piirtää sankarin tunnuksen keskitettynä (medaljongin sisään).
static func draw_symbol(ci: CanvasItem, hero_id: String, center: Vector2, r: float) -> void:
	match hero_id:
		"bastion":
			_bastion(ci, center, r)
		"ember":
			_ember(ci, center, r)
		_:
			_letter(ci, hero_id, center, r)


static func _letter(ci: CanvasItem, hero_id: String, center: Vector2, r: float) -> void:
	var def := HeroDef.get_def(hero_id)
	UiKit.draw_text(ci, center + Vector2(0, r * 0.04), def["name"].substr(0, 1),
		int(r * 1.15), Color.WHITE, true, maxi(2, int(r * 0.1)))


# --- Yksittäiset tunnukset ---

static func _bastion(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Kilpi: pyöreä yläreuna, kärki alhaalla, keskellä kohouma (boss).
	var s := r * 0.92
	var shield := PackedVector2Array([
		center + Vector2(-0.62, -0.68) * s,
		center + Vector2(0.0, -0.78) * s,
		center + Vector2(0.62, -0.68) * s,
		center + Vector2(0.62, 0.12) * s,
		center + Vector2(0.0, 0.86) * s,
		center + Vector2(-0.62, 0.12) * s,
	])
	# Varjo/ääriviiva
	var outline := PackedVector2Array()
	for p in shield:
		outline.append(p + Vector2(0, s * 0.05))
	ci.draw_colored_polygon(outline, SHADE)
	ci.draw_colored_polygon(shield, INK)
	# Poikkipalkki
	ci.draw_line(center + Vector2(-0.5, -0.12) * s, center + Vector2(0.5, -0.12) * s,
		SHADE, s * 0.14)
	# Keskikohouma
	ci.draw_circle(center + Vector2(0, -0.06) * s, s * 0.2, SHADE)
	ci.draw_circle(center + Vector2(0, -0.06) * s, s * 0.12, INK)
	# Kilven kiilto
	ci.draw_line(center + Vector2(-0.4, -0.5) * s, center + Vector2(-0.4, 0.1) * s,
		Color(1, 1, 1, 0.5), s * 0.08)


static func _ember(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Liekki: ulompi kärki + sisempi kieleke.
	var outer := _teardrop(center, r * 0.98, r * 0.62)
	var shadow := PackedVector2Array()
	for p in outer:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(outer, INK)
	# Sisempi liekki tummana antaa syvyyttä
	var inner := _teardrop(center + Vector2(0, r * 0.16), r * 0.6, r * 0.36)
	ci.draw_colored_polygon(inner, SHADE)
	# Kirkas ydin
	var core := _teardrop(center + Vector2(0, r * 0.28), r * 0.34, r * 0.2)
	ci.draw_colored_polygon(core, INK)


## Pisaramainen liekkimuoto: kärki ylhäällä, pyöreä alaosa.
static func _teardrop(center: Vector2, height: float, width: float) -> PackedVector2Array:
	var pts := PackedVector2Array([
		center + Vector2(0, -height),
		center + Vector2(width * 0.6, -height * 0.25),
		center + Vector2(width, height * 0.35),
		center + Vector2(width * 0.5, height * 0.75),
		center + Vector2(0, height * 0.85),
		center + Vector2(-width * 0.5, height * 0.75),
		center + Vector2(-width, height * 0.35),
		center + Vector2(-width * 0.6, -height * 0.25),
	])
	return pts
