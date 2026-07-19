class_name PlayerCard
extends Control
## Yhden pelaajan tilakortti HUDissa: sankari, kesto, ulti, cooldownit,
## reliikki ja tyrmäystila. Bottien kortit ovat pienempiä ja himmeämpiä,
## jotta ihmispelaajien tieto pysyy selkeimpänä.

var arena = null
var profile: PlayerProfile = null
var hero: Hero = null
var compact := false

var _time := 0.0


func setup(p_arena, p_profile: PlayerProfile) -> void:
	arena = p_arena
	profile = p_profile
	compact = p_profile.is_bot
	custom_minimum_size = Vector2(186, 74) if compact else Vector2(232, 118)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for candidate in arena.heroes:
		if candidate.profile == profile:
			hero = candidate
			break


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var w := size.x
	var h := size.y
	var def := HeroDef.get_def(profile.hero_id)
	var c1: Color = def["color"]
	var c2: Color = def["color_b"]
	var dim := 0.72 if compact else 1.0

	# Tausta ja reunus
	var bg := StyleBoxFlat.new()
	bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.82 * dim)
	bg.set_corner_radius_all(12)
	var border_color: Color = profile.color() if profile.is_human() \
		else Palette.with_alpha(Palette.team(profile.team), 0.45)
	bg.border_color = border_color
	bg.set_border_width_all(3 if profile.is_human() else 2)
	bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	# Medaljonki — pyörivä hehkukaari, hehkukehä ja kiiltohuippu.
	var med_r := 20.0 if compact else 25.0
	var med := Vector2(med_r + 12.0, h / 2.0)
	draw_arc(med, med_r + 4.5, _time * 0.8, _time * 0.8 + TAU * 0.72, 26,
		Palette.with_alpha(Palette.glow(c1, 1.3), 0.5 * dim), 2.0)
	draw_circle(med, med_r + 3.0, Palette.darker(c2, 0.6))
	draw_circle(med, med_r, Palette.with_alpha(c1, dim))
	draw_circle(med + Vector2(0, med_r * 0.35), med_r * 0.72, Palette.with_alpha(c2, 0.3 * dim))
	draw_circle(med + Vector2(-med_r * 0.32, -med_r * 0.36), med_r * 0.38,
		Palette.with_alpha(Color.WHITE, 0.2 * dim))
	HeroIcon.draw_symbol(self, profile.hero_id, med, med_r * 0.66)

	# Pelaajanumero / BOT-merkki
	if profile.is_human():
		var chip := Vector2(12, 12)
		draw_circle(chip, 11.0, profile.color())
		UiKit.draw_text(self, chip + Vector2(0, 1), str(profile.index + 1), 14,
			Palette.TEXT_DARK, true)
	else:
		UiKit.draw_text(self, Vector2(20, 12), "BOT", 10, Palette.TEXT_DIM, true)

	var left := med.x + med_r + 10.0
	var bar_w := w - left - 12.0

	# Nimi
	UiKit.draw_text(self, Vector2(left + bar_w / 2.0, 13.0), def["name"],
		13 if compact else 15, Palette.with_alpha(Palette.TEXT_MAIN, dim), true)

	# Kestopalkki + kilpi
	var hp_y := 24.0 if compact else 28.0
	var hp_h := 10.0 if compact else 13.0
	var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
	draw_rect(Rect2(left, hp_y, bar_w, hp_h), Color(0, 0, 0, 0.5))
	var hp_color: Color = Palette.GOOD if frac > 0.35 else Palette.BAD
	draw_rect(Rect2(left, hp_y, bar_w * frac, hp_h), Palette.with_alpha(hp_color, dim))
	if hero.shield_hp > 0.0:
		var sfrac: float = clampf(hero.shield_hp / hero.max_hp, 0.0, 1.0 - frac)
		draw_rect(Rect2(left + bar_w * frac, hp_y, bar_w * sfrac, hp_h),
			Palette.with_alpha(Palette.SHIELD, 0.9 * dim))

	# Resurssipalkki (mana/energy/rage) HP:n alla — vain täydessä kortissa.
	var y := hp_y + hp_h + 3.0
	if not compact and hero.res_type != "":
		var rfrac: float = clampf(hero.res / hero.res_max, 0.0, 1.0)
		draw_rect(Rect2(left, y, bar_w, 4.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(left, y, bar_w * rfrac, 4.0),
			Palette.with_alpha(_res_color(hero.res_type), dim))
		y += 6.0

	# Ultimittari
	var ult_h := 6.0 if compact else 7.0
	var ult_frac: float = hero.ult_charge / 100.0
	draw_rect(Rect2(left, y, bar_w, ult_h), Color(0, 0, 0, 0.5))
	var ult_color := Palette.GOLD
	if ult_frac >= 1.0:
		ult_color = Palette.glow(Palette.GOLD, 1.3 + 0.4 * sin(_time * 6.0))
	draw_rect(Rect2(left, y, bar_w * ult_frac, ult_h), Palette.with_alpha(ult_color, dim))
	y += ult_h + 5.0

	# Neljä kykypalleroa: kyky 1 (R1), kyky 2 (L1), väistö (X), ulti (L2).
	# Väri kertoo kyvyn, hehku valmiuden; ulti keltainen, väistö vaaleampi.
	if not compact:
		var pip_r := 13.0
		var pad_keys := ["R1", "L1", "X", "L2"]
		var kb_keys := ["HO", "Q", "VÄLI", "E"]
		var keys: Array = pad_keys if profile.device >= 0 else kb_keys
		var dodge_col: Color = Palette.glow(c1, 1.15)
		for i in range(4):
			var cx: float = left + pip_r + i * (bar_w - 2.0 * pip_r) / 3.0
			var center := Vector2(cx, y + pip_r)
			var base: Color = c1
			var pip_frac: float = 1.0
			var pip_cd: float = 0.0
			match i:
				0:
					pip_frac = clampf(1.0 - hero.cd.a1 / maxf(hero.cd_max.a1, 0.001), 0.0, 1.0)
					pip_cd = hero.cd.a1
				1:
					pip_frac = clampf(1.0 - hero.cd.a2 / maxf(hero.cd_max.a2, 0.001), 0.0, 1.0)
					pip_cd = hero.cd.a2
				2:
					base = dodge_col
					pip_frac = clampf(1.0 - hero.cd.dodge / maxf(hero.cd_max.dodge, 0.001), 0.0, 1.0)
					pip_cd = hero.cd.dodge
				3:
					base = Palette.GOLD
					pip_frac = ult_frac
			_ability_pip(center, pip_r, i, base, pip_frac, pip_cd, str(keys[i]), dim)

	# Reliikki-ikoni
	if hero.carrying:
		var gem_center := Vector2(w - 16.0, 16.0)
		var pulse := 1.0 + 0.15 * sin(_time * 6.0)
		var gem := PackedVector2Array([
			gem_center + Vector2(0, -9) * pulse, gem_center + Vector2(7, 0) * pulse,
			gem_center + Vector2(0, 9) * pulse, gem_center + Vector2(-7, 0) * pulse])
		draw_colored_polygon(gem, Palette.glow(Palette.GOLD, 1.7))

	# Tyrmäystila
	if not hero.alive:
		bg = StyleBoxFlat.new()
		bg.bg_color = Color(0.03, 0.04, 0.1, 0.78)
		bg.set_corner_radius_all(12)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		UiKit.draw_text(self, Vector2(w / 2.0, h / 2.0 - 8.0),
			str(int(ceil(hero.respawn_timer))), 30, Palette.TEXT_MAIN, true, 4)
		UiKit.draw_text(self, Vector2(w / 2.0, h / 2.0 + 16.0), "PALAA PELIIN...",
			11, Palette.TEXT_DIM, true)


## Resurssin väri (mana/energy/rage) — sama koodi kuin sankarin päällä.
func _res_color(t: String) -> Color:
	match t:
		"mana":
			return Color("5b8cff")
		"energy":
			return Color("4ad4ff")
		"rage":
			return Color("ff6b3d")
	return Palette.TEXT_DIM


## Pyöreä kykypallero: kuvio keskellä, hehku kun valmis, latauskaari kun
## jäähtyy. ready_frac 0..1, cd_secs > 0.5 näyttää sekuntiluvun.
func _ability_pip(center: Vector2, radius: float, icon_index: int, base_color: Color,
		ready_frac: float, cd_secs: float, key_hint: String, dim: float) -> void:
	var ready: bool = ready_frac >= 1.0
	draw_circle(center, radius + 1.0, Color(0, 0, 0, 0.55))
	if ready:
		draw_circle(center, radius, Palette.with_alpha(base_color, 0.32 * dim))
		draw_arc(center, radius, 0.0, TAU, 26, Palette.with_alpha(Palette.glow(base_color, 1.35), dim), 2.5)
	else:
		draw_circle(center, radius, Color(0, 0, 0, 0.4))
		if ready_frac > 0.01:
			draw_arc(center, radius - 1.0, -PI * 0.5, -PI * 0.5 + TAU * ready_frac, 24,
				Palette.with_alpha(base_color, 0.7 * dim), 3.0)
		draw_arc(center, radius, 0.0, TAU, 26, Palette.with_alpha(base_color, 0.28 * dim), 1.5)
	var icol: Color = Palette.glow(base_color, 1.4) if ready \
		else Palette.with_alpha(Palette.TEXT_DIM, 0.75)
	_draw_slot_icon(icon_index, center, icol)
	if cd_secs > 0.5:
		UiKit.draw_text(self, center + Vector2(0, 1), str(int(ceil(cd_secs))), 14,
			Palette.TEXT_MAIN, true, 3)
	UiKit.draw_text(self, center + Vector2(0, radius + 8.0), key_hint, 9,
		Palette.with_alpha(Palette.TEXT_DIM, dim), true)


## Kykyikonit: 0 = kyky 1 (tähti), 1 = kyky 2 (timantti), 2 = väistö (nuolet),
## 3 = ulti (säteilevä tähti).
func _draw_slot_icon(slot_index: int, center: Vector2, color: Color) -> void:
	match slot_index:
		0:
			var star := PackedVector2Array()
			for i in range(8):
				var r := 8.0 if i % 2 == 0 else 3.2
				star.append(center + Vector2.RIGHT.rotated(-PI / 2.0 + TAU * i / 8.0) * r)
			draw_colored_polygon(star, color)
		1:
			var gem := PackedVector2Array([
				center + Vector2(0, -8), center + Vector2(7, 0),
				center + Vector2(0, 8), center + Vector2(-7, 0)])
			draw_colored_polygon(gem, color)
		2:
			for k in range(2):
				var off := Vector2(-6.0 + k * 7.0, 0)
				draw_line(center + off + Vector2(-2, -6), center + off + Vector2(4, 0), color, 2.5)
				draw_line(center + off + Vector2(4, 0), center + off + Vector2(-2, 6), color, 2.5)
		3:
			# Ulti: säteilevä aurinko/tähti.
			for i in range(8):
				var a: float = TAU * i / 8.0
				draw_line(center + Vector2(cos(a), sin(a)) * 3.5,
					center + Vector2(cos(a), sin(a)) * 8.0, color, 2.0)
			draw_circle(center, 3.2, color)
