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
		"luma":
			_luma(ci, center, r)
		"blink":
			_blink(ci, center, r)
		"bramble":
			_bramble(ci, center, r)
		"quill":
			_quill(ci, center, r)
		"boulder":
			_boulder(ci, center, r)
		"volt":
			_volt(ci, center, r)
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


static func _luma(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Nelisakarainen loistetähti pitkillä sakaroilla.
	var star := PackedVector2Array()
	for i in range(8):
		var rr: float = r * 0.98 if i % 2 == 0 else r * 0.3
		star.append(center + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * i / 8.0) * rr)
	var shadow := PackedVector2Array()
	for p in star:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(star, INK)
	ci.draw_circle(center, r * 0.24, SHADE)
	ci.draw_circle(center, r * 0.14, INK)
	# Pienet kimalteet
	for i in range(4):
		var d := center + Vector2.RIGHT.rotated(PI / 4.0 + TAU * i / 4.0) * r * 0.62
		ci.draw_circle(d, r * 0.06, INK)


static func _blink(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Kaksi ristissä olevaa valoterää.
	for ang in [-0.72, 0.72]:
		var d := Vector2.RIGHT.rotated(ang)
		var a := center - d * r * 0.5
		var b := center + d * r * 0.98
		ci.draw_line(a + Vector2(0, r * 0.05), b + Vector2(0, r * 0.05), SHADE, r * 0.22)
		ci.draw_line(a, b, INK, r * 0.15)
		ci.draw_circle(b, r * 0.07, INK)
	# Keskustimantti (kahvojen risteys)
	var hub := PackedVector2Array([
		center + Vector2(0, -r * 0.3), center + Vector2(r * 0.3, 0),
		center + Vector2(0, r * 0.3), center + Vector2(-r * 0.3, 0)])
	ci.draw_colored_polygon(hub, SHADE)
	var inner := PackedVector2Array([
		center + Vector2(0, -r * 0.17), center + Vector2(r * 0.17, 0),
		center + Vector2(0, r * 0.17), center + Vector2(-r * 0.17, 0)])
	ci.draw_colored_polygon(inner, INK)


static func _bramble(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Piikikäs lehti: kärki ylhäällä, ruoto ja sivupiikit.
	var leaf := PackedVector2Array([
		center + Vector2(0, -r * 0.95),
		center + Vector2(r * 0.5, -r * 0.18),
		center + Vector2(r * 0.42, r * 0.5),
		center + Vector2(0, r * 0.9),
		center + Vector2(-r * 0.42, r * 0.5),
		center + Vector2(-r * 0.5, -r * 0.18),
	])
	var shadow := PackedVector2Array()
	for p in leaf:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(leaf, INK)
	# Ruoto ja suonet
	ci.draw_line(center + Vector2(0, -r * 0.8), center + Vector2(0, r * 0.8), SHADE, r * 0.1)
	for side in [-1.0, 1.0]:
		ci.draw_line(center + Vector2(0, -r * 0.1), center + Vector2(side * r * 0.32, r * 0.28),
			SHADE, r * 0.06)
	# Sivupiikit
	for side in [-1.0, 1.0]:
		var base := center + Vector2(side * r * 0.46, -r * 0.05)
		ci.draw_colored_polygon(PackedVector2Array([
			base + Vector2(0, -r * 0.12), base + Vector2(side * r * 0.28, 0),
			base + Vector2(0, r * 0.12)]), INK)


static func _quill(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Jousi vasemmalla + vaakanuoli oikealle.
	var bc := center + Vector2(-r * 0.35, 0)
	var br := r * 0.82
	ci.draw_arc(bc, br, -1.05, 1.05, 22, SHADE, r * 0.2)
	ci.draw_arc(bc, br, -1.05, 1.05, 22, INK, r * 0.13)
	var e1 := bc + Vector2(cos(-1.05), sin(-1.05)) * br
	var e2 := bc + Vector2(cos(1.05), sin(1.05)) * br
	ci.draw_line(e1, e2, INK, r * 0.05)
	# Nuoli
	var tail := center + Vector2(-r * 0.42, 0)
	var tip := center + Vector2(r * 0.78, 0)
	ci.draw_line(tail, tip, INK, r * 0.1)
	ci.draw_colored_polygon(PackedVector2Array([
		tip + Vector2(r * 0.14, 0), tip + Vector2(-r * 0.12, -r * 0.17),
		tip + Vector2(-r * 0.12, r * 0.17)]), INK)
	# Sulat
	ci.draw_line(tail, tail + Vector2(-r * 0.2, -r * 0.15), INK, r * 0.05)
	ci.draw_line(tail, tail + Vector2(-r * 0.2, r * 0.15), INK, r * 0.05)


static func _boulder(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Särmikäs kallio halkeamin.
	var rock := PackedVector2Array([
		center + Vector2(-0.9, -0.15) * r, center + Vector2(-0.45, -0.82) * r,
		center + Vector2(0.35, -0.9) * r, center + Vector2(0.9, -0.15) * r,
		center + Vector2(0.68, 0.72) * r, center + Vector2(-0.4, 0.86) * r,
		center + Vector2(-0.85, 0.45) * r])
	var shadow := PackedVector2Array()
	for p in rock:
		shadow.append(p + Vector2(0, r * 0.06))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(rock, INK)
	# Särmälinjat
	ci.draw_line(center + Vector2(-0.45, -0.82) * r, center + Vector2(0.1, 0.0) * r, SHADE, r * 0.08)
	ci.draw_line(center + Vector2(0.1, 0.0) * r, center + Vector2(0.68, 0.72) * r, SHADE, r * 0.08)
	ci.draw_line(center + Vector2(0.1, 0.0) * r, center + Vector2(-0.4, 0.86) * r, SHADE, r * 0.08)
	ci.draw_line(center + Vector2(0.1, 0.0) * r, center + Vector2(0.9, -0.15) * r, SHADE, r * 0.06)


static func _volt(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Salamanuoli (zigzag).
	var bolt := PackedVector2Array([
		center + Vector2(0.15, -0.95) * r,
		center + Vector2(-0.45, -0.05) * r,
		center + Vector2(0.05, -0.05) * r,
		center + Vector2(-0.2, 0.95) * r,
		center + Vector2(0.5, -0.2) * r,
		center + Vector2(0.02, -0.2) * r,
		center + Vector2(0.4, -0.95) * r,
	])
	var shadow := PackedVector2Array()
	for p in bolt:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(bolt, INK)


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
