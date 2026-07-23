class_name ItemIcon
## Itemien kuvakkeet piirretään koodilla (ei tekstuureita): tumma medaljonki,
## tier-värinen rengas, statiperheen symboli ja tier-pippurit alla. Sama
## piirtäjä palvelee tulostaulua ja telakan miniriviä (r ~10) sekä kauppaa
## (r ~22). Symboli valitaan itemin hallitsevan statin mukaan (symbol_for).

const INK := Color("f4f7ff")


static func tier_color(tier: String) -> Color:
	match tier:
		"rare":
			return Color("4a86ff")
		"epic":
			return Color("b04aff")
		"legendary":
			return Palette.glow(Palette.GOLD, 1.25)
	return Color("9aa4b5")


static func tier_rank(tier: String) -> int:
	match tier:
		"rare":
			return 2
		"epic":
			return 3
		"legendary":
			return 4
	return 1


## Piirtää itemin kuvakkeen keskitettynä. r on medaljongin säde; pippurit
## piirtyvät hieman sen alle (varaa ~r * 0.35 lisätilaa pystysuunnassa).
static func draw(ci: CanvasItem, id: String, center: Vector2, r: float) -> void:
	var item := ItemDef.get_item(id)
	if item.is_empty():
		return
	var tier := str(item.get("tier", "common"))
	var col := tier_color(tier)
	# Medaljonki: tumma pohja + tier-rengas; legenda saa kultahehkun.
	ci.draw_circle(center, r + 2.0, Color(0.03, 0.045, 0.09, 0.96))
	ci.draw_circle(center, r, Palette.with_alpha(Palette.darker(col, 0.4), 0.9))
	if tier == "legendary":
		ci.draw_arc(center, r + 3.0, 0.0, TAU, 24,
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.6), 0.5), 2.0)
	ci.draw_arc(center, r + 1.0, 0.0, TAU, 24, col, maxf(1.5, r * 0.14))
	_draw_symbol(ci, symbol_for(id), center, r * 0.66)
	# Tier-pippurit (1-4) kuvakkeen alla.
	var pips := tier_rank(tier)
	var pr := maxf(1.1, r * 0.11)
	var step := pr * 2.0 + 1.5
	var x0 := center.x - step * float(pips - 1) / 2.0
	for i in range(pips):
		ci.draw_circle(Vector2(x0 + step * float(i), center.y + r + pr + 2.5), pr, col)


## Statiperheen symboli itemille: legenda tähti, kritti/vartija silmä,
## viidakko torahammas, kulta kolikko, imu pisara, hyökkäysnopeus jousi,
## CDR kello, panssari kilpi, vastus riimu, HP sydän, vauhti saapas,
## hyökkäys miekka, muut (AP/mana) sauva. Järjestys ratkaisee monistatit.
static func symbol_for(id: String) -> String:
	var item := ItemDef.get_item(id)
	var stats: Dictionary = item.get("stats", {})
	if str(item.get("tier", "")) == "legendary":
		return "star"
	if str(item.get("active", "")) == "vartija":
		return "eye"
	if stats.has("crit"):
		return "eye"
	if stats.has("jungle_dmg"):
		return "fang"
	if stats.has("gold_per_sec") or stats.has("assist_gold"):
		return "coin"
	if stats.has("lifesteal") or stats.has("spellvamp"):
		return "droplet"
	if stats.has("attack_speed"):
		return "bow"
	if stats.has("cdr"):
		return "clock"
	if stats.has("armor"):
		return "shield"
	if stats.has("mr"):
		return "rune"
	if stats.has("hp") or stats.has("hp_regen"):
		return "heart"
	if stats.has("ms"):
		return "boot"
	if stats.has("attack"):
		return "sword"
	return "staff"


static func _draw_symbol(ci: CanvasItem, sym: String, c: Vector2, s: float) -> void:
	var w := maxf(1.6, s * 0.22)
	match sym:
		"sword":
			var dirv := Vector2(1, -1).normalized()
			ci.draw_line(c - dirv * s * 0.75, c + dirv * s * 0.8, INK, w)
			var g := c - dirv * s * 0.35
			var side := dirv.orthogonal() * s * 0.38
			ci.draw_line(g - side, g + side, INK, w)
		"bow":
			for k in range(2):
				var x := -s * 0.55 + float(k) * s * 0.62
				ci.draw_line(c + Vector2(x, -s * 0.6), c + Vector2(x + s * 0.55, 0.0), INK, w)
				ci.draw_line(c + Vector2(x + s * 0.55, 0.0), c + Vector2(x, s * 0.6), INK, w)
		"staff":
			ci.draw_line(c + Vector2(0, s * 0.85), c + Vector2(0, -s * 0.3), INK, w)
			ci.draw_arc(c + Vector2(0, -s * 0.52), s * 0.28, 0.0, TAU, 12, INK, w)
		"droplet":
			ci.draw_circle(c + Vector2(0, s * 0.25), s * 0.5, INK)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s * 0.85), c + Vector2(s * 0.42, s * 0.05),
				c + Vector2(-s * 0.42, s * 0.05)]), INK)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.6, -s * 0.55), c + Vector2(s * 0.6, -s * 0.55),
				c + Vector2(s * 0.55, s * 0.15), c + Vector2(0, s * 0.8),
				c + Vector2(-s * 0.55, s * 0.15)]), INK)
		"rune":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(0, -s * 0.8), c + Vector2(s * 0.6, 0),
				c + Vector2(0, s * 0.8), c + Vector2(-s * 0.6, 0),
				c + Vector2(0, -s * 0.8)]), INK, w)
			ci.draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, s * 0.35), INK, w)
		"heart":
			ci.draw_circle(c + Vector2(-s * 0.32, -s * 0.22), s * 0.36, INK)
			ci.draw_circle(c + Vector2(s * 0.32, -s * 0.22), s * 0.36, INK)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.62, 0.0), c + Vector2(s * 0.62, 0.0),
				c + Vector2(0, s * 0.75)]), INK)
		"boot":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.35, -s * 0.75), c + Vector2(s * 0.05, -s * 0.75),
				c + Vector2(s * 0.05, s * 0.25), c + Vector2(s * 0.65, s * 0.45),
				c + Vector2(s * 0.65, s * 0.75), c + Vector2(-s * 0.35, s * 0.75)]), INK)
		"clock":
			ci.draw_arc(c, s * 0.7, 0.0, TAU, 18, INK, w)
			ci.draw_line(c, c + Vector2(0, -s * 0.48), INK, w * 0.9)
			ci.draw_line(c, c + Vector2(s * 0.34, s * 0.1), INK, w * 0.9)
		"coin":
			ci.draw_circle(c, s * 0.7, INK)
			ci.draw_arc(c, s * 0.4, 0.0, TAU, 14, Color(0.05, 0.07, 0.13, 0.9), w * 0.8)
		"eye":
			ci.draw_arc(c + Vector2(0, s * 0.55), s * 1.05, -PI * 0.78, -PI * 0.22, 12, INK, w)
			ci.draw_arc(c + Vector2(0, -s * 0.55), s * 1.05, PI * 0.22, PI * 0.78, 12, INK, w)
			ci.draw_circle(c, s * 0.3, INK)
		"fang":
			for sgn_v in [-1.0, 1.0]:
				var sgn := float(sgn_v)
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(sgn * s * 0.55, -s * 0.7),
					c + Vector2(sgn * s * 0.12, -s * 0.5),
					c + Vector2(sgn * s * 0.32, s * 0.75)]), INK)
		"star":
			var star := PackedVector2Array()
			for i in range(10):
				var rr := s * (0.95 if i % 2 == 0 else 0.42)
				star.append(c + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * float(i) / 10.0) * rr)
			ci.draw_colored_polygon(star, INK)
		_:
			ci.draw_circle(c, s * 0.4, INK)
