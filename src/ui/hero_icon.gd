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
		"maestro":
			_maestro(ci, center, r)
		"shade":
			_shade(ci, center, r)
		"tide":
			_tide(ci, center, r)
		"scout":
			_scout(ci, center, r)
		"prism":
			_prism(ci, center, r)
		"rift":
			_rift(ci, center, r)
		"titan":
			_titan(ci, center, r)
		"hush":
			_hush(ci, center, r)
		"obsidian":
			_obsidian(ci, center, r)
		"lance":
			_lance(ci, center, r)
		_:
			_letter(ci, hero_id, center, r)


static func _letter(ci: CanvasItem, hero_id: String, center: Vector2, r: float) -> void:
	var def := HeroDef.get_def(hero_id)
	UiKit.draw_text(ci, center + Vector2(0, r * 0.04), def["name"].substr(0, 1),
		int(r * 1.15), Color.WHITE, true, maxi(2, int(r * 0.1)))


## Prisma: kolmio, johon tulee säde vasemmalta ja josta hajoaa spektri oikealle.
static func _prism(ci: CanvasItem, center: Vector2, r: float) -> void:
	var s := r * 0.82
	var lw: float = maxf(2.0, r * 0.07)
	var tri := PackedVector2Array([
		center + Vector2(0.0, -0.9) * s,
		center + Vector2(0.8, 0.6) * s,
		center + Vector2(-0.8, 0.6) * s,
	])
	ci.draw_colored_polygon(tri, INK)
	ci.draw_polyline(tri + PackedVector2Array([tri[0]]), SHADE, lw)
	# Tulosäde vasemmalta
	ci.draw_line(center + Vector2(-1.2, 0.2) * s, center + Vector2(-0.1, 0.2) * s, INK, lw)
	# Kolme hajaantuvaa säde oikealle
	for i in range(3):
		var y := center.y + 0.2 * s + (i - 1) * r * 0.32
		ci.draw_line(center + Vector2(0.1, 0.2) * s, Vector2(center.x + 1.2 * s, y), INK, lw * 0.8)


## Rift: tiimalasi (ajanpysäytys).
static func _rift(ci: CanvasItem, center: Vector2, r: float) -> void:
	var s := r * 0.72
	var lw: float = maxf(2.0, r * 0.09)
	ci.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-0.72, -0.82) * s, center + Vector2(0.72, -0.82) * s, center]), INK)
	ci.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-0.72, 0.82) * s, center + Vector2(0.72, 0.82) * s, center]), INK)
	ci.draw_line(center + Vector2(-0.8, -0.82) * s, center + Vector2(0.8, -0.82) * s, INK, lw)
	ci.draw_line(center + Vector2(-0.8, 0.82) * s, center + Vector2(0.8, 0.82) * s, INK, lw)


## Titaani: puristettu rautanyrkki (tartu ja heitä).
static func _titan(ci: CanvasItem, center: Vector2, r: float) -> void:
	var s := r * 0.78
	var lw: float = maxf(2.0, r * 0.08)
	# Nyrkin runko (rystyset)
	var fist := PackedVector2Array([
		center + Vector2(-0.85, -0.2) * s,
		center + Vector2(-0.7, -0.75) * s,
		center + Vector2(0.7, -0.75) * s,
		center + Vector2(0.9, -0.15) * s,
		center + Vector2(0.9, 0.6) * s,
		center + Vector2(-0.85, 0.6) * s,
	])
	ci.draw_colored_polygon(fist, INK)
	ci.draw_polyline(fist + PackedVector2Array([fist[0]]), SHADE, lw)
	# Sormien jaot rystysten päällä
	for i in range(3):
		var fx := center.x + (i - 1) * 0.5 * s
		ci.draw_line(Vector2(fx, center.y - 0.72 * s), Vector2(fx, center.y - 0.18 * s), SHADE, lw)
	# Rystyslinja
	ci.draw_line(center + Vector2(-0.8, -0.15) * s, center + Vector2(0.85, -0.15) * s, SHADE, lw)
	# Peukalo sivussa
	ci.draw_circle(center + Vector2(-0.9, 0.18) * s, 0.22 * s, INK)


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


static func _maestro(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Kahdeksasosanuotti: nuottipää, varsi ja lippu.
	var head := center + Vector2(-r * 0.22, r * 0.48)
	var np := PackedVector2Array()
	for i in range(14):
		var a := TAU * i / 14.0
		np.append(head + Vector2(cos(a) * r * 0.4, sin(a) * r * 0.3))
	var shadow := PackedVector2Array()
	for p in np:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(np, INK)
	# Varsi
	var stem_bot := center + Vector2(r * 0.16, r * 0.44)
	var stem_top := center + Vector2(r * 0.16, -r * 0.85)
	ci.draw_line(stem_bot, stem_top, INK, r * 0.12)
	# Lippu
	ci.draw_line(stem_top, stem_top + Vector2(r * 0.45, r * 0.28), INK, r * 0.11)
	ci.draw_line(stem_top + Vector2(0, r * 0.25), stem_top + Vector2(r * 0.42, r * 0.5),
		INK, r * 0.09)


static func _shade(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Nelisakarainen shuriken keskireiällä.
	var star := PackedVector2Array()
	for i in range(8):
		var rr: float = r * 0.98 if i % 2 == 0 else r * 0.34
		star.append(center + Vector2.RIGHT.rotated(TAU * i / 8.0 + PI / 8.0) * rr)
	var shadow := PackedVector2Array()
	for p in star:
		shadow.append(p + Vector2(0, r * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(star, INK)
	ci.draw_circle(center, r * 0.17, SHADE)


static func _tide(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Atrain: varsi, poikkipuu ja kolme piikkiä.
	var shaft_bot := center + Vector2(0, r * 0.92)
	var shaft_top := center + Vector2(0, -r * 0.25)
	ci.draw_line(shaft_bot + Vector2(0, r * 0.05), shaft_top + Vector2(0, r * 0.05), SHADE, r * 0.16)
	ci.draw_line(shaft_bot, shaft_top, INK, r * 0.12)
	ci.draw_line(center + Vector2(-r * 0.5, -r * 0.25), center + Vector2(r * 0.5, -r * 0.25),
		INK, r * 0.11)
	for x in [-0.5, 0.0, 0.5]:
		var top: float = -r * 0.95 if x == 0.0 else -r * 0.8
		var px := center + Vector2(x * r, -r * 0.25)
		ci.draw_line(px, center + Vector2(x * r, top), INK, r * 0.09)
		# Piikin kärki
		ci.draw_colored_polygon(PackedVector2Array([
			center + Vector2(x * r, top - r * 0.14),
			center + Vector2(x * r - r * 0.08, top),
			center + Vector2(x * r + r * 0.08, top)]), INK)


static func _scout(ci: CanvasItem, center: Vector2, r: float) -> void:
	# Tähtäin: rengas, ristikkoviivat ja keskipiste.
	ci.draw_arc(center + Vector2(0, r * 0.05), r * 0.8, 0.0, TAU, 28, SHADE, r * 0.15)
	ci.draw_arc(center, r * 0.8, 0.0, TAU, 28, INK, r * 0.11)
	for ang in [0.0, PI * 0.5, PI, PI * 1.5]:
		var d := Vector2.RIGHT.rotated(ang)
		ci.draw_line(center + d * r * 0.5, center + d * r * 1.0, INK, r * 0.1)
	ci.draw_circle(center, r * 0.15, INK)


## Lance: vinottain kulkeva keihäs, jonka kärjessä on kaksintaistelumerkki.
static func _lance(ci: CanvasItem, center: Vector2, r: float) -> void:
	var lw: float = maxf(2.0, r * 0.12)
	var tail := center + Vector2(-0.72, 0.72) * r
	var tip := center + Vector2(0.66, -0.66) * r
	# Varsi
	ci.draw_line(tail + Vector2(0, r * 0.05), tip + Vector2(0, r * 0.05), SHADE, lw)
	ci.draw_line(tail, tip, INK, lw * 0.8)
	# Keihäänkärki
	var dir := (tip - tail).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([
		tip + dir * r * 0.28,
		tip - dir * r * 0.16 + perp * r * 0.2,
		tip - dir * r * 0.16 - perp * r * 0.2,
	])
	ci.draw_colored_polygon(head, INK)
	# Kaksintaistelumerkki (timantti) tyven lähellä
	var m := center + Vector2(-0.28, 0.28) * r
	var gem := PackedVector2Array([
		m + Vector2(0, -r * 0.24), m + Vector2(r * 0.2, 0),
		m + Vector2(0, r * 0.24), m + Vector2(-r * 0.2, 0)])
	ci.draw_colored_polygon(gem, Color("ff9db0"))


## Obsidian: särmikäs kivilohkare, jonka halki kulkee hehkuva laavahalkeama.
static func _obsidian(ci: CanvasItem, center: Vector2, r: float) -> void:
	var shard := PackedVector2Array([
		center + Vector2(-0.2, -0.95) * r,
		center + Vector2(0.55, -0.55) * r,
		center + Vector2(0.9, 0.25) * r,
		center + Vector2(0.35, 0.9) * r,
		center + Vector2(-0.55, 0.78) * r,
		center + Vector2(-0.92, -0.05) * r,
	])
	var shadow := PackedVector2Array()
	for p in shard:
		shadow.append(p + Vector2(0, r * 0.06))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(shard, INK)
	# Fasettilinjat (särmät).
	ci.draw_line(center + Vector2(-0.2, -0.95) * r, center + Vector2(0.1, 0.1) * r, SHADE, r * 0.07)
	ci.draw_line(center + Vector2(0.9, 0.25) * r, center + Vector2(0.1, 0.1) * r, SHADE, r * 0.07)
	ci.draw_line(center + Vector2(-0.55, 0.78) * r, center + Vector2(0.1, 0.1) * r, SHADE, r * 0.06)
	# Hehkuva laavahalkeama (zigzag) keskeltä.
	var crack := PackedVector2Array([
		center + Vector2(-0.05, -0.7) * r,
		center + Vector2(0.14, -0.2) * r,
		center + Vector2(-0.08, 0.12) * r,
		center + Vector2(0.12, 0.6) * r,
	])
	ci.draw_polyline(crack, Color("ff7a3a"), r * 0.11)


## Hush: vaimennuskello — kellon runko, kieli ja vaimennuskaari yli.
static func _hush(ci: CanvasItem, center: Vector2, r: float) -> void:
	var s := r * 0.86
	# Kellon runko: kapea yläosa, leviää alas.
	var bell := PackedVector2Array([
		center + Vector2(-0.16, -0.78) * s,
		center + Vector2(0.16, -0.78) * s,
		center + Vector2(0.44, 0.1) * s,
		center + Vector2(0.66, 0.5) * s,
		center + Vector2(-0.66, 0.5) * s,
		center + Vector2(-0.44, 0.1) * s,
	])
	var shadow := PackedVector2Array()
	for p in bell:
		shadow.append(p + Vector2(0, s * 0.05))
	ci.draw_colored_polygon(shadow, SHADE)
	ci.draw_colored_polygon(bell, INK)
	# Nuppi ylhäällä ja suun reunapalkki.
	ci.draw_circle(center + Vector2(0, -0.86) * s, s * 0.14, INK)
	ci.draw_line(center + Vector2(-0.66, 0.5) * s, center + Vector2(0.66, 0.5) * s, SHADE, s * 0.14)
	# Kieli (clapper).
	ci.draw_circle(center + Vector2(0, 0.42) * s, s * 0.13, SHADE)
	# Vaimennuskaari kellon yli (mute-viiva).
	ci.draw_line(center + Vector2(-0.8, 0.7) * s, center + Vector2(0.8, -0.7) * s,
		Color(1, 1, 1, 0.55), s * 0.12)


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
