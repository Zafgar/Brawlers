class_name HudLayer
extends CanvasLayer
## Ottelun HUD: pelaajakortit ylä- ja alareunassa, tulospaneeli keskellä
## ylhäällä, bannerit, laskurit ja tyrmäyssyöte.

const CARD_SLOT := 240.0

var arena = null

var _root: Control = null
var _score_panel: Control = null
var _feed_box: VBoxContainer = null
var _pane_bars: Array = []         # jaettu ruutu: kykypalkki per ruutu
var _pane_minis: Array = []        # jaettu ruutu: minimap per ruutu


func setup(p_arena) -> void:
	arena = p_arena
	layer = 10

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Pelaajakortit: sininen ylös, oranssi alas. Enintään kolme korttia
	# rivissä, jotta ne eivät osu keskellä olevaan tulospaneeliin.
	var counts := [0, 0]
	for profile in Game.roster:
		var card := PlayerCard.new()
		card.setup(arena, profile)
		var slot: int = counts[profile.team]
		counts[profile.team] += 1
		var x := 16.0 + (slot % 3) * CARD_SLOT
		var row_offset := (slot / 3) * 130.0
		if profile.team == 0:
			card.position = Vector2(x, 14.0 + row_offset)
		else:
			card.position = Vector2(x, 1080.0 - card.size.y - 14.0 - row_offset)
		_root.add_child(card)

	_score_panel = ScorePanel.new()
	_score_panel.arena = arena
	_score_panel.position = Vector2(960.0 - 300.0, 10.0)
	_score_panel.size = Vector2(600.0, 96.0)
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_score_panel)

	# Buffilaskuri tulospaneelin alle: näyttää ajan seuraavaan buffiaaltoon.
	var buff_strip := BuffStrip.new()
	buff_strip.arena = arena
	buff_strip.position = Vector2(960.0 - 150.0, 112.0)
	buff_strip.size = Vector2(300.0, 30.0)
	buff_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(buff_strip)

	_feed_box = UiKit.vbox(4)
	_feed_box.position = Vector2(1920.0 - 420.0, 120.0)
	_feed_box.size = Vector2(400.0, 300.0)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed_box)

	# LoL-tyylinen kykypalkki (oman hahmon HP/resurssi/ulti + kyvyt jäähdytyksineen)
	# alakeskelle, ja minimap oikeaan alakulmaan.
	if arena.hosted:
		# Jaettu ruutu: yksi kykypalkki + minimap PER RUUTU, sidottuna kyseisen
		# ruudun pelaajaan. SplitView asemoi ne layout_panes-kutsulla.
		for i in range(4):
			var pb := AbilityBar.new()
			pb.arena = arena
			pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pb.visible = false
			_root.add_child(pb)
			_pane_bars.append(pb)
			var pm := Minimap.new()
			pm.arena = arena
			pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pm.visible = false
			_root.add_child(pm)
			_pane_minis.append(pm)
	else:
		var abil := AbilityBar.new()
		abil.arena = arena
		abil.size = Vector2(540.0, 118.0)
		abil.position = Vector2(960.0 - 270.0, 1080.0 - 118.0 - 10.0)
		abil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(abil)

		var mini := Minimap.new()
		mini.arena = arena
		mini.size = Vector2(216.0, 216.0)
		mini.position = Vector2(1920.0 - 216.0 - 12.0, 1080.0 - 216.0 - 12.0)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(mini)


## Jaettu ruutu: asemoi ja sido per-ruutu kykypalkit + minimapit. rects = ruutujen
## suorakulmiot ruudulla, heroes = kunkin ruudun pelaaja (sama indeksointi).
## Kutsutaan SplitViewistä kun ruutujako muuttuu.
func layout_panes(rects: Array, heroes: Array) -> void:
	for i in range(_pane_bars.size()):
		var bar: Control = _pane_bars[i]
		var mini: Control = _pane_minis[i]
		var active: bool = i < rects.size()
		bar.visible = active
		mini.visible = active
		if not active:
			continue
		var rect: Rect2 = rects[i]
		bar.bound_hero = heroes[i] if i < heroes.size() else null
		# Kykypalkki: skaalaa ruudun leveyteen, alakeskelle.
		var bw: float = clampf(rect.size.x * 0.62, 300.0, 540.0)
		var bh: float = clampf(bw * 0.22, 78.0, 118.0)
		bar.size = Vector2(bw, bh)
		bar.position = Vector2(
			rect.position.x + (rect.size.x - bw) / 2.0,
			rect.position.y + rect.size.y - bh - 10.0)
		# Minimap: skaalaa ruudun kokoon, oikeaan alakulmaan.
		var ms: float = clampf(minf(rect.size.x, rect.size.y) * 0.24, 132.0, 216.0)
		mini.size = Vector2(ms, ms)
		mini.position = Vector2(
			rect.position.x + rect.size.x - ms - 12.0,
			rect.position.y + rect.size.y - ms - 12.0)


## Iso banneri ruudun yläkolmanteen: "ERÄ 1", "SININEN VOITTAA ERÄN!" jne.
func show_banner(big: String, small := "", dur := 2.0) -> void:
	# Absoluuttinen sijainti täysruudun juuressa (ei ankkuriesiasetusta, joka
	# siirtäisi position-arvon ruudun keskeltä -> ulos oikeasta reunasta).
	# Container-leveys pakotetaan custom_minimum_sizella (pelkkä .size ei pysy
	# containerissa), jotta keskitetty teksti osuu ruudun keskelle.
	var box := UiKit.vbox(6)
	box.position = Vector2(960.0 - 600.0, 250.0)
	box.custom_minimum_size = Vector2(1200.0, 0.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var big_label := UiKit.title(big, 68)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(big_label)
	if small != "":
		var small_label := UiKit.label(small, 26, Palette.TEXT_DIM)
		small_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(small_label)
	_root.add_child(box)

	box.modulate = Color(1, 1, 1, 0)
	box.scale = Vector2(1.12, 1.12)
	box.pivot_offset = Vector2(600.0, 60.0)
	var tween := box.create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "modulate:a", 1.0, 0.18)
	tween.tween_property(box, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(maxf(dur - 0.5, 0.1))
	tween.chain().tween_property(box, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(box.queue_free)


## Valtava keskinumero: lähtölaskenta ja "PELIIN!".
func show_big_number(text: String) -> void:
	# Absoluuttinen sijainti (ei ankkuriesiasetusta — muuten numero valuu ulos
	# ruudun oikeasta reunasta).
	var label := UiKit.title(text, 150)
	label.position = Vector2(960.0 - 500.0, 400.0)
	label.size = Vector2(1000.0, 220.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.pivot_offset = Vector2(500.0, 110.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)

	label.scale = Vector2(1.5, 1.5)
	label.modulate = Color(1, 1, 1, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.25)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(label.queue_free)


## Pieni tapahtumarivi oikeaan yläkulmaan.
func ko_feed(text: String) -> void:
	if _feed_box.get_child_count() >= 4:
		_feed_box.get_child(_feed_box.get_child_count() - 1).queue_free()
	var label := UiKit.label(text, 18, Palette.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_box.add_child(label)
	_feed_box.move_child(label, 0)
	var tween := label.create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


## Tulospaneeli: reliikkipisteet, aika, erävoitot ja reliikin tila.
class ScorePanel:
	extends Control

	var arena = null
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if arena == null:
			return
		var w := size.x
		var bg := StyleBoxFlat.new()
		bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.85)
		bg.set_corner_radius_all(16)
		bg.border_color = Palette.UI_STROKE
		bg.set_border_width_all(2)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		var blue_frac: float
		var orange_frac: float
		if arena.mode == "moba":
			# MOBAssa palkit näyttävät nexusten kestopisteet (kumpi lähempänä häviötä).
			blue_frac = arena.nexus_fraction(0)
			orange_frac = arena.nexus_fraction(1)
		elif arena.mode == "jungle":
			# Viidakossa ei ole kiinteää maalia -> palkit näyttävät suhteellisen
			# johdon (johtava täysi, toinen suhteessa siihen).
			var bp: float = arena.team_points(0)
			var op: float = arena.team_points(1)
			var lead: float = maxf(maxf(bp, op), 1.0)
			blue_frac = clampf(bp / lead, 0.0, 1.0)
			orange_frac = clampf(op / lead, 0.0, 1.0)
		else:
			var target: float = arena.score_target
			blue_frac = clampf(arena.team_points(0) / target, 0.0, 1.0)
			orange_frac = clampf(arena.team_points(1) / target, 0.0, 1.0)

		# Reliikkipistepalkit: sininen vasemmalta, oranssi oikealta.
		var bar_y := 16.0
		var bar_h := 20.0
		var bar_half := w / 2.0 - 74.0
		draw_rect(Rect2(12, bar_y, bar_half, bar_h), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(w - 12 - bar_half, bar_y, bar_half, bar_h), Color(0, 0, 0, 0.5))
		var blue_color := Palette.TEAM_BLUE
		var orange_color := Palette.TEAM_ORANGE
		var holder: int = arena.holder_team()
		if holder == 0:
			blue_color = Palette.glow(Palette.TEAM_BLUE, 1.3 + 0.2 * sin(_time * 8.0))
		elif holder == 1:
			orange_color = Palette.glow(Palette.TEAM_ORANGE, 1.3 + 0.2 * sin(_time * 8.0))
		draw_rect(Rect2(12, bar_y, bar_half * blue_frac, bar_h), blue_color)
		draw_rect(Rect2(w - 12 - bar_half * orange_frac, bar_y, bar_half * orange_frac, bar_h),
			orange_color)
		var blue_num := int(arena.team_points(0))
		var orange_num := int(arena.team_points(1))
		if arena.mode == "moba":
			blue_num = arena.nexus_hp_int(0)
			orange_num = arena.nexus_hp_int(1)
		UiKit.draw_text(self, Vector2(12 + 30, bar_y + bar_h / 2.0),
			str(blue_num), 16, Palette.TEXT_MAIN, true, 3)
		UiKit.draw_text(self, Vector2(w - 12 - 30, bar_y + bar_h / 2.0),
			str(orange_num), 16, Palette.TEXT_MAIN, true, 3)

		# Aika tai äkkikuolema
		if arena.sudden_death:
			var blink_alpha := 0.6 + 0.4 * sin(_time * 7.0)
			UiKit.draw_text(self, Vector2(w / 2.0, bar_y + 10.0), "RATKAISU!",
				24, Palette.with_alpha(Palette.GOLD, blink_alpha), true, 4)
		else:
			var secs := int(maxf(arena.time_left, 0.0))
			var text := "%d:%02d" % [secs / 60, secs % 60]
			var time_color := Palette.TEXT_MAIN
			if secs <= 30:
				time_color = Palette.with_alpha(Palette.BAD, 0.7 + 0.3 * sin(_time * 5.0))
			UiKit.draw_text(self, Vector2(w / 2.0, bar_y + 10.0), text, 30, time_color, true, 4)

		# Erävoittopisteet
		var pip_y := 62.0
		var wins_needed: int = Game.rounds_to_win
		for i in range(wins_needed):
			var blue_pip := Vector2(w / 2.0 - 40.0 - i * 22.0, pip_y)
			var filled_blue: bool = Game.blue_rounds > i
			draw_circle(blue_pip, 8.0, Palette.TEAM_BLUE if filled_blue else Color(0, 0, 0, 0.5))
			draw_arc(blue_pip, 8.0, 0.0, TAU, 20, Palette.with_alpha(Palette.TEAM_BLUE, 0.7), 1.5)
			var orange_pip := Vector2(w / 2.0 + 40.0 + i * 22.0, pip_y)
			var filled_orange: bool = Game.orange_rounds > i
			draw_circle(orange_pip, 8.0, Palette.TEAM_ORANGE if filled_orange else Color(0, 0, 0, 0.5))
			draw_arc(orange_pip, 8.0, 0.0, TAU, 20, Palette.with_alpha(Palette.TEAM_ORANGE, 0.7), 1.5)

		# Reliikin tila pieni timantti keskellä pippujen välissä
		var gem_center := Vector2(w / 2.0, pip_y)
		var gem_color := Palette.glow(Palette.GOLD, 1.5)
		var gem_holder: int = arena.holder_team()
		if gem_holder >= 0:
			gem_color = Palette.glow(Palette.team(gem_holder), 1.5)
		var pulse := 1.0 + 0.1 * sin(_time * 5.0)
		var gem := PackedVector2Array([
			gem_center + Vector2(0, -10) * pulse, gem_center + Vector2(8, 0) * pulse,
			gem_center + Vector2(0, 10) * pulse, gem_center + Vector2(-8, 0) * pulse])
		draw_colored_polygon(gem, gem_color)


## Buffilaskuri: näyttää ajan seuraavaan kenttäbuffiaaltoon (power spike).
class BuffStrip:
	extends Control

	var arena = null
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if arena == null:
			return
		var t: float = arena.next_buff_in()
		if t < 0.0:
			return
		var bg := StyleBoxFlat.new()
		bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.8)
		bg.set_corner_radius_all(12)
		bg.border_color = Palette.with_alpha(Palette.GOLD, 0.3)
		bg.set_border_width_all(1)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		var cy := size.y / 2.0
		_diamond(Vector2(24, cy), Color("6aa0ff"))
		_diamond(Vector2(42, cy), Color("ff7a6a"))
		var secs := int(ceil(t))
		var soon: bool = t <= 8.0
		var col: Color = Palette.TEXT_DIM
		if soon:
			col = Palette.with_alpha(Palette.glow(Palette.GOLD, 1.3), 0.7 + 0.3 * sin(_time * 6.0))
		UiKit.draw_text(self, Vector2(size.x / 2.0 + 22.0, cy),
			"BUFFIT  %d:%02d" % [secs / 60, secs % 60], 17, col, true, 3)

	func _diamond(c: Vector2, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -6), c + Vector2(5, 0), c + Vector2(0, 6), c + Vector2(-5, 0)]),
			Palette.glow(col, 1.4))


## LoL-tyylinen kykypalkki oman hahmon alle: HP + resurssi + ultti-palkit ja viisi
## kykyruutua (perus/a1/a2/ult/väistö) jäähdytyksineen, näppäinvihjeineen ja
## nimineen. Näyttää PAIKALLISEN ihmispelaajan hahmon (näppäimistö etusijalla).
class AbilityBar:
	extends Control

	var arena = null
	var bound_hero = null            # jaetussa ruudussa: sidottu kyseisen ruudun pelaajaan
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _local_hero():
		# Jaetussa ruudussa palkki on sidottu tietyn ruudun pelaajaan.
		if bound_hero != null and is_instance_valid(bound_hero):
			return bound_hero
		if arena == null:
			return null
		var kb = null
		var first = null
		for h in arena.heroes:
			if not is_instance_valid(h) or h.profile == null or h.profile.is_bot:
				continue
			if first == null:
				first = h
			if h.profile.device == -1:
				kb = h
		return kb if kb != null else first

	func _draw() -> void:
		var hero = _local_hero()
		if hero == null or not is_instance_valid(hero):
			return
		var w := size.x
		var h := size.y
		var c: Color = hero.hero_color()
		var bg := StyleBoxFlat.new()
		bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.82)
		bg.set_corner_radius_all(14)
		bg.border_color = Palette.with_alpha(c, 0.55)
		bg.set_border_width_all(2)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		# Muotokuva (väripallo) vasemmalle.
		var pc := Vector2(40.0, h / 2.0)
		draw_circle(pc, 30.0, Palette.darker(c, 0.55))
		draw_circle(pc, 25.0, c)
		draw_arc(pc, 30.0, 0.0, TAU, 30, Palette.glow(c, 1.3), 2.5)
		var initial: String = str(hero.hero_id).substr(0, 1).to_upper()
		UiKit.draw_text(self, pc, initial, 24, Palette.TEXT_MAIN, true, 3)

		# Palkit (HP, resurssi, ultti) muotokuvan oikealle.
		var bx := 80.0
		var bw := w - bx - 14.0
		var by := 12.0
		var hp_frac: float = clampf(hero.hp / maxf(hero.max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(bx, by, bw, 13.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bx, by, bw * hp_frac, 13.0), _hp_color(hp_frac))
		UiKit.draw_text(self, Vector2(bx + bw / 2.0, by + 6.5),
			"%d / %d" % [int(hero.hp), int(hero.max_hp)], 11, Palette.TEXT_MAIN, true)
		by += 17.0
		if hero.res_type != "" and hero.res_max > 0.0:
			var rf: float = clampf(hero.res / hero.res_max, 0.0, 1.0)
			draw_rect(Rect2(bx, by, bw, 8.0), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bx, by, bw * rf, 8.0), _res_color(hero.res_type))
			by += 11.0
		var uf: float = hero.ult_charge / 100.0
		draw_rect(Rect2(bx, by, bw, 6.0), Color(0, 0, 0, 0.5))
		var uc: Color = Palette.GOLD if uf < 1.0 else Palette.glow(Palette.GOLD, 1.3 + 0.3 * sin(_time * 6.0))
		draw_rect(Rect2(bx, by, bw * uf, 6.0), Palette.with_alpha(uc, 0.95))

		# Kykyruudut (perus/a1/a2/ult/väistö).
		var slots := _slot_data(hero)
		var n := slots.size()
		var sz := 46.0
		var gap := 9.0
		var total := n * sz + (n - 1) * gap
		var sx := bx + (bw - total) / 2.0
		var sy := h - sz - 18.0
		for i in range(n):
			_draw_slot(Vector2(sx + i * (sz + gap), sy), sz, slots[i])

	func _slot_data(hero) -> Array:
		var pad: bool = hero.profile.device >= 0
		var ab: Dictionary = HeroDef.get_def(hero.hero_id)["abilities"]
		var c: Color = hero.hero_color()
		var keys := {
			"basic": "R2" if pad else "Hiiri V", "a1": "R1" if pad else "Hiiri O",
			"a2": "L1" if pad else "Q", "ult": "L2" if pad else "E",
			"dodge": "X" if pad else "Väli"}
		var out: Array = []
		for slot in ["basic", "a1", "a2", "ult", "dodge"]:
			var col: Color = c
			var frac: float
			var cd: float = 0.0
			if slot == "ult":
				col = Palette.GOLD
				frac = hero.ult_charge / 100.0
			else:
				col = Palette.glow(c, 1.15) if slot == "dodge" else c
				var cur: float = hero.cd[slot]
				var mx: float = maxf(hero.cd_max[slot], 0.001)
				frac = clampf(1.0 - cur / mx, 0.0, 1.0)
				cd = cur
			out.append({"name": str(ab[slot]["name"]), "key": str(keys[slot]),
				"frac": frac, "cd": cd, "color": col, "ult": slot == "ult"})
		return out

	func _draw_slot(pos: Vector2, sz: float, d: Dictionary) -> void:
		var base: Color = d["color"]
		var frac: float = clampf(float(d["frac"]), 0.0, 1.0)
		var ready: bool = frac >= 0.999
		var box := StyleBoxFlat.new()
		box.bg_color = Palette.with_alpha(Palette.darker(base, 0.5), 0.92) if ready \
			else Color(0.05, 0.06, 0.11, 0.92)
		box.set_corner_radius_all(9)
		box.border_color = Palette.glow(base, 1.3) if ready else Palette.with_alpha(base, 0.5)
		box.set_border_width_all(2)
		box.draw(get_canvas_item(), Rect2(pos, Vector2(sz, sz)))
		var cen := pos + Vector2(sz / 2.0, sz / 2.0)
		if not ready:
			# Jäähdytys: tumma peitto alhaalta + latauskaari + sekuntiluku.
			var cover: float = (1.0 - frac) * sz
			draw_rect(Rect2(pos.x, pos.y, sz, cover), Color(0, 0, 0, 0.55))
			draw_arc(cen, sz * 0.42, -PI * 0.5, -PI * 0.5 + TAU * frac, 24,
				Palette.with_alpha(base, 0.8), 2.5)
			if float(d["cd"]) > 0.3:
				UiKit.draw_text(self, cen, str(int(ceil(float(d["cd"])))), 18,
					Palette.TEXT_MAIN, true, 3)
		elif bool(d["ult"]):
			draw_arc(cen, sz * 0.46, 0.0, TAU, 28,
				Palette.glow(Palette.GOLD, 1.35 + 0.25 * sin(_time * 6.0)), 2.5)
		# Näppäinvihje ruudun sisään alas, nimi ruudun alle.
		UiKit.draw_text(self, pos + Vector2(sz / 2.0, sz - 9.0), str(d["key"]), 10,
			Palette.TEXT_DIM, true)
		UiKit.draw_text(self, pos + Vector2(sz / 2.0, sz + 8.0), str(d["name"]), 9,
			Palette.with_alpha(Palette.TEXT_DIM, 0.85), true)

	func _hp_color(frac: float) -> Color:
		if frac > 0.5:
			return Color("5fd07a")
		return Color("e0a13a") if frac > 0.25 else Color("e05a5a")

	func _res_color(t: String) -> Color:
		match t:
			"mana":
				return Color("5b8cff")
			"energy":
				return Color("4ad4ff")
			"rage":
				return Color("ff6b3d")
		return Palette.TEXT_DIM


## Minimap oikeaan alakulmaan: kartan alue + sankaripisteet (joukkuevärit) +
## rakennukset (MOBA). Omat ihmispelaajat korostettu renkaalla.
class Minimap:
	extends Control

	var arena = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if arena == null or arena.map == null:
			return
		var bg := StyleBoxFlat.new()
		bg.bg_color = Palette.with_alpha(Palette.UI_PANEL, 0.82)
		bg.set_corner_radius_all(10)
		bg.border_color = Palette.UI_STROKE
		bg.set_border_width_all(2)
		bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

		var msz: Vector2 = arena.map.size()
		var pad := 8.0
		var inner: Vector2 = size - Vector2(pad * 2.0, pad * 2.0)
		var sc: float = minf(inner.x / msz.x, inner.y / msz.y)
		var origin: Vector2 = Vector2(pad, pad) + (inner - msz * sc) * 0.5
		# Kartan lattia.
		draw_rect(Rect2(origin, msz * sc), Color(0, 0, 0, 0.3))

		# Rakennukset (MOBA): neliöt joukkuevärillä.
		if "structures" in arena:
			for st in arena.structures:
				if not is_instance_valid(st) or not st.alive:
					continue
				var sp: Vector2 = origin + (st.global_position + msz * 0.5) * sc
				draw_rect(Rect2(sp - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
					Palette.glow(Palette.team(st.team), 1.2))

		# Sankarit: pisteet joukkuevärillä; omat pelaajat korostettu.
		for hh in arena.heroes:
			if not is_instance_valid(hh) or not hh.alive or hh.is_unit:
				continue
			var p: Vector2 = origin + (hh.global_position + msz * 0.5) * sc
			var col: Color = Palette.team(hh.team)
			draw_circle(p, 4.0, col)
			if hh.profile != null and not hh.profile.is_bot:
				draw_arc(p, 6.5, 0.0, TAU, 14, Palette.glow(col, 1.4), 1.5)
