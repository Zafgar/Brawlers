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
	custom_minimum_size = Vector2(186, 74) if compact else Vector2(228, 94)
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

	# Medaljonki
	var med_r := 20.0 if compact else 25.0
	var med := Vector2(med_r + 12.0, h / 2.0)
	draw_circle(med, med_r + 3.0, Palette.darker(c2, 0.6))
	draw_circle(med, med_r, Palette.with_alpha(c1, dim))
	UiKit.draw_text(self, med + Vector2(0, 1), def["name"].substr(0, 1),
		int(med_r * 1.1), Color.WHITE, true, 3)

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

	# Ultimittari
	var ult_y := hp_y + hp_h + 4.0
	var ult_h := 6.0 if compact else 8.0
	var ult_frac: float = hero.ult_charge / 100.0
	draw_rect(Rect2(left, ult_y, bar_w, ult_h), Color(0, 0, 0, 0.5))
	var ult_color := Palette.GOLD
	if ult_frac >= 1.0:
		ult_color = Palette.glow(Palette.GOLD, 1.3 + 0.4 * sin(_time * 6.0))
	draw_rect(Rect2(left, ult_y, bar_w * ult_frac, ult_h),
		Palette.with_alpha(ult_color, dim))

	# Cooldown-ruudut (kyky 1, kyky 2, väistö) — vain ihmisille
	if not compact:
		var slot_size := 20.0
		var cd_y := ult_y + ult_h + 5.0
		var slots := ["a1", "a2", "dodge"]
		for i in range(slots.size()):
			var slot: String = slots[i]
			var x := left + i * (slot_size + 6.0)
			var rect := Rect2(x, cd_y, slot_size, slot_size)
			draw_rect(rect, Color(0, 0, 0, 0.5))
			var max_cd: float = maxf(hero.cd_max[slot], 0.001)
			var ready: float = clampf(1.0 - hero.cd[slot] / max_cd, 0.0, 1.0)
			var fill_h := slot_size * ready
			var fill_color: Color = Palette.glow(c1, 1.2) if ready >= 1.0 \
				else Palette.with_alpha(c1, 0.45)
			draw_rect(Rect2(x, cd_y + slot_size - fill_h, slot_size, fill_h), fill_color)
			if hero.cd[slot] > 0.0:
				UiKit.draw_text(self, rect.get_center(), str(int(ceil(hero.cd[slot]))),
					12, Palette.TEXT_MAIN, true, 2)

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
