extends Node
## Äänijärjestelmä (autoload: AudioMgr). Kaikki äänet syntetisoidaan
## proseduraalisesti käynnistyksessä taustasäikeessä — ei äänitiedostoja.
## play("nimi") toimii heti; jos synteesi on kesken, ääni jää vain väliin.

const RATE := 44100              # 22050 -> 44100: poistaa square/saw-aliasoinnin (zap/mark/count) ja kirkastaa
const POOL_SIZE := 26            # 4v4 MOBA: sankarit + minionit tarvitsevat oman headroomin
const ALERT_POOL_SIZE := 4       # objective-/rakennusäänet eivät huku taisteluun
const AMBIENT_POOL_SIZE := 4     # pitkät ympäristökerrokset eivät vie combat-kanavia
const MUSIC_VOL := -8.0          # musiikin soittimien häivytystaso
const MIN_REPEAT_MS := 28        # sama ääni ei soi tätä tiheämmin (ei kakofoniaa/klippausta)

# Etäisyysvaimennus (positionaaliset äänet): täysi voimakkuus lähellä, sitten
# hiipuu. Suuret kartat (esim. MOBA 4400x2600) eivät enää soi tasaisen kovaa.
const AUDIO_NEAR := 520.0        # px: tähän asti täysi voimakkuus
const AUDIO_FALLOFF := 34.0      # px per -1 dB tämän jälkeen
const AUDIO_CUTOFF_DB := -38.0   # tätä hiljaisemmat ohitetaan (liian kaukana)

# Biisipoolit: valikot ja taistelut arpovat vaihtelua näistä.
# HUOM: battle4 EI ole poolissa — se on varattu nexus-avauksen huipennukselle
# (play_music("battle4")). Jos se olisi kierrossa, ~25 % otteluista alkaisi jo
# battle4:llä ja huipennuksesta tulisi kuulumaton no-op.
const MUSIC_POOLS := {
	"menu": ["menu", "menu2"],
	"lobby": ["lobby", "lobby2"],
	"battle": ["battle", "battle2", "battle3"],
}

# UI-äänet reititetään kuivalle SFX_UI-väylälle (ei kaikua) — napsautukset
# pysyvät terävinä eikä lyhyt count_tick smearaudu kaiun esiviiveestä.
const UI_SOUNDS := {
	"ui_move": true, "ui_ok": true, "ui_back": true, "ui_open": true,
	"ui_lock": true, "ui_deny": true, "ui_team": true,
	"count_tick": true, "count_go": true, "score": true,
}

# Maailman ratkaisevat cue-äänet saavat oman soittopoolin. Näin esimerkiksi
# Nexuksen avautuminen kuuluu varmasti, vaikka kahdeksan sankaria taistelee samaan aikaan.
const ALERT_SOUNDS := {
	"moba_start": true, "minion_wave": true,
	"tower_destroy": true, "nexus_exposed": true, "nexus_destroy": true,
	"dragon_warning": true, "dragon_spawn": true, "dragon_enrage": true,
	"dragon_defeat": true, "baron_warning": true, "baron_spawn": true,
	"baron_enrage": true, "baron_defeat": true,
}

const AMBIENT_SOUNDS := {
	"ambient_jungle": true, "ambient_river": true, "ambient_lane": true,
	"ambient_brush": true, "ambient_blue_base": true, "ambient_orange_base": true,
	"ambient_baron_pit": true, "ambient_dragon_pit": true,
}

# Tiheästi toistuvilla MOBA-äänillä on oma kakofoniaraja. Arvo millisekunteina.
const SOUND_COOLDOWNS := {
	"minion_melee": 85, "minion_ranged": 90, "minion_impact": 75,
	"minion_down": 80, "tower_lock": 180, "tower_fire": 120,
	"tower_impact": 100, "tower_guard": 420, "nexus_laser": 220,
	"jungle_small_attack": 110, "jungle_small_down": 120,
	"red_guardian_attack": 150, "blue_guardian_attack": 150,
	"red_guardian_impact": 110, "blue_guardian_impact": 110,
	"dragon_attack": 210, "dragon_impact": 180,
	"dragon_slam_warning": 500, "baron_attack": 210, "baron_impact": 180,
	"baron_slam_warning": 500,
	"ambient_jungle": 1800, "ambient_river": 1800, "ambient_lane": 1800,
	"ambient_brush": 1600, "ambient_blue_base": 1800,
	"ambient_orange_base": 1800, "ambient_baron_pit": 2200,
	"ambient_dragon_pit": 2200,
}

var _streams := {}
var _players: Array = []
var _alert_players: Array = []
var _ambient_players: Array = []
var _music_players: Array = []      # kaksi soitinta ristihäivytystä varten
var _music_tracks := {}             # nimi -> AudioStreamWAV
var _active_idx := 0
var _current_track := ""             # haluttu biisi
var _playing_track := ""             # tällä hetkellä soiva biisi
var _music_tween: Tween = null
var _music_enabled := true
var _thread: Thread = null
var _warned := {}
var _pending_ambient := {}         # nimi -> [pitch, volume_db, world_pos]

# Kakofonian esto: viimeksi soitetun äänen aikaleima (ms) nimen mukaan.
var _last_play := {}
# Kuuntelijan (kameran/pelaajan) sijainti positionaalista vaimennusta varten.
var listener_pos := Vector2.ZERO
var listener_on := false
var listener_positions: Array = []

# Musiikin duckaus: perus(ducktaamaton)taso ja käynnissä oleva palautus-tween.
var _music_base_db := 0.0
var _duck_tween: Tween = null


func _ready() -> void:
	_make_bus("SFX")
	_make_bus("SFX_UI")   # kuiva UI-väylä (ei kaikua)
	_make_bus("SFX_ALERT")
	_make_bus("SFX_AMBIENT")
	_make_bus("Music")
	_setup_master_fx()
	_setup_sfx_fx()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	for i in range(ALERT_POOL_SIZE):
		var alert_player := AudioStreamPlayer.new()
		alert_player.bus = "SFX_ALERT"
		add_child(alert_player)
		_alert_players.append(alert_player)
	for i in range(AMBIENT_POOL_SIZE):
		var ambient_player := AudioStreamPlayer.new()
		ambient_player.bus = "SFX_AMBIENT"
		add_child(ambient_player)
		_ambient_players.append(ambient_player)
	for i in range(2):
		var mp := AudioStreamPlayer.new()
		mp.bus = "Music"
		mp.volume_db = -40.0
		add_child(mp)
		_music_players.append(mp)

	_thread = Thread.new()
	_thread.start(_synth_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## Master-väylälle rajoitin: estää yhteenlaskettujen äänten klippauksen
## (moni tehoste + musiikki yhtä aikaa) pehmeästi kattoon. HardLimiter on
## 4.3+ suositeltu (vanha AudioEffectLimiter on vanhentunut).
func _setup_master_fx() -> void:
	if AudioServer.get_bus_effect_count(0) > 0:
		return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)


## SFX-väylälle hienovarainen kaiku: tehosteet istuvat samaan tilaan
## eivätkä kuulosta kuivilta/irrallisilta. Märkyys pidetään pienenä.
func _setup_sfx_fx() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx < 0 or AudioServer.get_bus_effect_count(idx) > 0:
		return
	var verb := AudioEffectReverb.new()
	verb.room_size = 0.4
	verb.damping = 0.6
	verb.spread = 0.7
	verb.predelay_msec = 25.0   # oletus 150 -> 25: ei kuulu erillisenä kaiku-blippinä
	verb.hipass = 0.15          # ei kaikuteta subbassoa (bass/quake/thunder pysyvät selkeinä)
	verb.dry = 0.92
	verb.wet = 0.1
	AudioServer.add_bus_effect(idx, verb)


# --- Julkinen rajapinta ---

## Soittaa tehosteen. pos-parametri (maailmakoordinaatti) tekee äänestä
## positionaalisen: se vaimenee etäisyyden mukaan kuuntelijasta ja liian
## kaukaiset ohitetaan kokonaan. Jätä pois = ei-positionaalinen (UI, musiikki-cue).
func play(sound_name: String, pitch_var := 0.08, volume_db := 0.0, pos := Vector2.INF) -> void:
	# Simulaatiossa (botti vs. botti, nopeutettu) äänet ovat turhia ja
	# kuormittavat äänipoolia — vaimennetaan keskitetysti kaikki tehosteet.
	if Game.simulating:
		return
	if not _streams.has(sound_name):
		# Ympäristökerros on pitkä ja edelleen ajankohtainen valmistuttuaan, joten
		# nopean suoraan-otteluun käynnistyksen ensimmäinen pyyntö jonotetaan.
		if AMBIENT_SOUNDS.has(sound_name):
			_pending_ambient[sound_name] = [pitch_var, volume_db, pos]
		if (_thread == null or not _thread.is_alive()) \
				and not _streams.is_empty() and not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Tuntematon ääni: %s" % sound_name)
		return

	# Positionaalinen vaimennus: lähellä täysi voimakkuus, kaukana hiljenee.
	# Tehdään ENNEN toistorajaa, jotta liian kaukainen (ohitettu) ääni ei
	# "kuluta" toistoikkunaa ja vaienna heti perään tulevaa lähempää ääntä.
	var db := volume_db
	if listener_on and is_finite(pos.x):
		var dist := listener_pos.distance_to(pos)
		if not listener_positions.is_empty():
			dist = INF
			for listener in listener_positions:
				dist = minf(dist, pos.distance_to(listener))
		if dist > AUDIO_NEAR:
			db -= (dist - AUDIO_NEAR) / AUDIO_FALLOFF
			if db < AUDIO_CUTOFF_DB:
				return

	# Kakofonian/klippauksen esto: sama ääni ei käynnisty liian tiheään.
	# Vain oikeasti soivat äänet lasketaan toistorajaan.
	var now := Time.get_ticks_msec()
	var last: int = _last_play.get(sound_name, -10000)
	var repeat_ms: int = int(SOUND_COOLDOWNS.get(sound_name, MIN_REPEAT_MS))
	if now - last < repeat_ms:
		return
	_last_play[sound_name] = now

	var pool: Array = _players
	var bus_name := "SFX"
	if UI_SOUNDS.has(sound_name):
		bus_name = "SFX_UI"
	elif ALERT_SOUNDS.has(sound_name):
		pool = _alert_players
		bus_name = "SFX_ALERT"
	elif AMBIENT_SOUNDS.has(sound_name):
		pool = _ambient_players
		bus_name = "SFX_AMBIENT"
	var player: AudioStreamPlayer = null
	for p in pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = pool[0]
	player.bus = bus_name
	player.stream = _streams[sound_name]
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.volume_db = db
	player.play()


## Jaetussa ruudussa ääni vaimennetaan lähimmän paikallisen pelaajan mukaan.
func set_listener_positions(positions: Array) -> void:
	listener_positions = positions.duplicate()
	listener_on = not listener_positions.is_empty()


func clear_listener_positions() -> void:
	listener_positions.clear()


func set_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(v, 0.001, 1.0)))


func set_sfx_volume(v: float) -> void:
	var db := linear_to_db(clampf(v, 0.0001, 1.0))
	# Sekä pelin SFX että kuiva UI-väylä seuraavat samaa liukusäädintä.
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
	for bus_name in ["SFX_UI", "SFX_ALERT", "SFX_AMBIENT"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, db)


func set_music_volume(v: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		_music_base_db = linear_to_db(clampf(v, 0.0001, 1.0))
		AudioServer.set_bus_volume_db(idx, _music_base_db)


## Duckaa musiikin hetkeksi alas ison hetken alta (nexus, pomo) ja palauttaa
## sen pehmeästi — tarkoituksellinen dippi sen sijaan että Master-rajoitin
## pumppaisi musiikkia hallitsemattomasti SFX-ryöpyn alla.
func duck_music(depth_db: float, release: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var ducked := _music_base_db - absf(depth_db)
	AudioServer.set_bus_volume_db(idx, ducked)   # nopea dippi alas
	_duck_tween = create_tween()
	_duck_tween.set_ease(Tween.EASE_OUT)
	_duck_tween.tween_method(_set_music_bus_db, ducked, _music_base_db, maxf(release, 0.05))


func _set_music_bus_db(v: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, v)


## Vaihtaa taustamusiikin (pehmeä ristihäivytys). Sama nimi = ei uudelleenaloitusta.
## Jos biisiä ei ole vielä syntetisoitu, se käynnistyy heti kun se valmistuu.
func play_music(track: String) -> void:
	_current_track = track
	if not _music_enabled:
		return
	if _music_tracks.has(track) and _playing_track != track:
		_crossfade_to(track)


## Vaihtaa biisin annetusta poolista. Valitsee mieluiten jo valmiin biisin
## joka EI ole nyt soimassa — näin erien ja valikoiden välillä tulee vaihtelua.
func play_music_pool(pool: String) -> void:
	var tracks: Array = MUSIC_POOLS.get(pool, [pool])
	var ready_choices: Array = []
	for t in tracks:
		if _music_tracks.has(t) and t != _playing_track:
			ready_choices.append(t)
	var choice := ""
	if not ready_choices.is_empty():
		choice = ready_choices[randi() % ready_choices.size()]
	else:
		choice = tracks[randi() % tracks.size()]
	play_music(choice)


func _crossfade_to(track: String) -> void:
	var cur: AudioStreamPlayer = _music_players[_active_idx]
	var nxt: AudioStreamPlayer = _music_players[1 - _active_idx]
	nxt.stream = _music_tracks[track]
	nxt.volume_db = -40.0
	nxt.play()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(nxt, "volume_db", MUSIC_VOL, 0.9)
	_music_tween.parallel().tween_property(cur, "volume_db", -40.0, 0.9)
	_music_tween.chain().tween_callback(cur.stop)
	_active_idx = 1 - _active_idx
	_playing_track = track


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		for mp in _music_players:
			mp.stop()
		_playing_track = ""
	elif _current_track != "" and _music_tracks.has(_current_track):
		_crossfade_to(_current_track)


# --- Synteesi ---

func _synth_all() -> void:
	# Musiikki syntetisoidaan ENSIN, ja päävalikon biisi toimitetaan heti
	# omanaan — näin valikko soi lähes välittömästi eikä vasta sitten kun
	# kaikki ~40 tehostetta on ehditty laskea taustasäikeessä.
	# Menu: tumma mutta eteenpäin liikkuva MOBA-komentokeskus (Am-F-C-G).
	var menu_wav := _to_wav(_make_track(
		[110.0, 87.31, 130.81, 98.0], [true, false, false, false], 2.25, "tri", 0.28, 0.94), true)
	call_deferred("_music_ready", {"menu": menu_wav})

	# Ensisijaiset biisit (yksi per näkymä) heti menun perään, jotta lobby ja
	# taistelu soivat nopeasti ilman että vaihtelu­versioita tarvitsee odottaa.
	var primary := {}
	# Draft/lobby: selkeä taktinen pulssi (C-G-Am-F).
	primary["lobby"] = _to_wav(_make_track(
		[130.81, 98.0, 110.0, 87.31], [false, false, true, false], 1.82, "square", 0.62, 0.96), true)
	# Taistelu 1: ajava ja jännittävä (Em-C-G-D).
	primary["battle"] = _to_wav(_make_track(
		[82.41, 130.81, 98.0, 146.83], [true, false, false, false], 1.6, "saw", 1.0, 1.0), true)
	call_deferred("_music_ready", primary)

	# Vaihteluversiot viimeisenä (poolit arpovat näistä).
	var variety := {}
	# Menu 2: hieman kirkkaampi strateginen vaihtoehto (G-Bb-F-C).
	variety["menu2"] = _to_wav(_make_track(
		[98.0, 116.54, 87.31, 130.81], [false, true, false, false], 2.35, "tri", 0.24, 0.92), true)
	# Lobby 2: napakampi odotus (Bb-F-C-G).
	variety["lobby2"] = _to_wav(_make_track(
		[116.54, 87.31, 130.81, 98.0], [false, false, false, true], 1.72, "square", 0.68, 0.96), true)
	# Taistelu 2: vaihtelua (Am-F-G-Em).
	variety["battle2"] = _to_wav(_make_track(
		[110.0, 87.31, 98.0, 82.41], [true, false, false, true], 1.6, "saw", 1.0, 1.0), true)
	# Taistelu 3: kiivas (Dm-G-Em-A).
	variety["battle3"] = _to_wav(_make_track(
		[73.42, 98.0, 82.41, 110.0], [true, false, true, false], 1.5, "saw", 1.0, 1.0), true)
	# Taistelu 4: raju huipennus (F-Bb-G-D).
	variety["battle4"] = _to_wav(_make_track(
		[87.31, 116.54, 98.0, 73.42], [false, false, false, false], 1.4, "saw", 1.0, 1.0), true)
	call_deferred("_music_ready", variety)

	# Tehosteet viimeisenä.
	var sounds := {}
	# Valikkosoundit muodostavat yhtenäisen komentokeskus-kielen: liike on kevyt,
	# lukitus painava ja näkymän avaus tunnistettava. Kaikki ovat kuivalla UI-bussilla.
	sounds["ui_move"] = _mix2(
		_tone(0.055, 620.0, 820.0, "sine", 0.003, 0.035, 0.20),
		_tone(0.04, 1240.0, 980.0, "tri", 0.002, 0.025, 0.08), 0.0)
	sounds["ui_ok"] = _mix2(
		_seq([[0.055, 440.0, 440.0, "sine"], [0.085, 660.0, 660.0, "sine"]], 0.27),
		_tone(0.12, 110.0, 82.0, "tri", 0.002, 0.08, 0.12), 0.0)
	sounds["ui_back"] = _mix2(
		_tone(0.12, 480.0, 280.0, "sine", 0.004, 0.075, 0.30),
		_noise(0.055, 0.10, 0.65), 0.0)
	sounds["ui_open"] = _mix2(
		_seq([[0.07, 220.0, 330.0, "tri"], [0.08, 440.0, 660.0, "sine"],
			[0.14, 880.0, 1040.0, "sine"]], 0.22),
		_tone(0.30, 82.0, 110.0, "sine", 0.01, 0.20, 0.15), 0.0)
	sounds["ui_lock"] = _mix2(
		_seq([[0.045, 330.0, 330.0, "square"], [0.065, 494.0, 494.0, "tri"],
			[0.12, 659.0, 659.0, "sine"]], 0.25),
		_tone(0.18, 105.0, 78.0, "sine", 0.002, 0.12, 0.22), 0.0)
	sounds["ui_deny"] = _mix2(
		_seq([[0.065, 185.0, 155.0, "square"], [0.09, 165.0, 120.0, "square"]], 0.20),
		_noise(0.11, 0.12, 0.55), 0.0)
	sounds["ui_team"] = _mix2(
		_tone(0.13, 300.0, 600.0, "tri", 0.003, 0.08, 0.24),
		_tone(0.13, 900.0, 680.0, "sine", 0.005, 0.08, 0.10), 0.0)
	sounds["count_tick"] = _tone(0.06, 880.0, 880.0, "square", 0.002, 0.04, 0.25)
	sounds["count_go"] = _mix2(
		_tone(0.35, 440.0, 880.0, "square", 0.01, 0.2, 0.22),
		_tone(0.3, 1320.0, 1760.0, "sine", 0.05, 0.2, 0.15), 0.08)
	sounds["round_start"] = _seq([
		[0.14, 523.0, 523.0, "square"], [0.14, 659.0, 659.0, "square"],
		[0.3, 784.0, 784.0, "square"]], 0.28)
	sounds["round_win"] = _seq([
		[0.12, 523.0, 523.0, "square"], [0.12, 659.0, 659.0, "square"],
		[0.12, 784.0, 784.0, "square"], [0.4, 1046.0, 1046.0, "square"]], 0.26)
	sounds["match_win"] = _mix2(_seq([
		[0.16, 523.0, 523.0, "square"], [0.16, 659.0, 659.0, "square"],
		[0.16, 784.0, 784.0, "square"], [0.16, 1046.0, 1046.0, "square"],
		[0.5, 1318.0, 1318.0, "square"]], 0.24),
		_noise(1.1, 0.08, 0.15), 0.0)
	sounds["hit"] = _mix2(
		_tone(0.08, 220.0, 140.0, "tri", 0.002, 0.05, 0.42),
		_noise(0.06, 0.22, 0.4), 0.0)
	sounds["swing"] = _noise(0.12, 0.26, 0.75)
	sounds["slam"] = _mix2(
		_tone(0.25, 90.0, 50.0, "sine", 0.005, 0.18, 0.5),
		_noise(0.12, 0.26, 0.3), 0.0)
	# Raskas maanjäristys: syvä basso + pitkä kohina-jyrinä
	sounds["quake"] = _mix2(_mix2(
		_tone(0.5, 70.0, 38.0, "sine", 0.005, 0.35, 0.44),
		_tone(0.4, 120.0, 60.0, "tri", 0.005, 0.3, 0.2), 0.0),
		_noise(0.45, 0.26, 0.2), 0.02)
	# Kilpi ylös: napakka metallinen kilahdus
	sounds["guard_up"] = _mix2(
		_tone(0.18, 520.0, 780.0, "tri", 0.002, 0.12, 0.35),
		_tone(0.16, 880.0, 1100.0, "sine", 0.005, 0.1, 0.2), 0.02)
	# Kupoli nousee: matala nouseva humaus
	sounds["dome_up"] = _mix2(
		_tone(0.6, 110.0, 220.0, "sine", 0.03, 0.4, 0.4),
		_tone(0.6, 165.0, 330.0, "tri", 0.05, 0.4, 0.2), 0.05)
	# Kivet: murenevat kivet (muuri, vyöry)
	sounds["rock"] = _mix2(
		_noise(0.35, 0.3, 0.35),
		_tone(0.3, 150.0, 70.0, "tri", 0.005, 0.2, 0.22), 0.0)
	sounds["fire"] = _mix2(
		_tone(0.15, 330.0, 190.0, "saw", 0.01, 0.1, 0.3),
		_noise(0.15, 0.2, 0.5), 0.0)
	# Lämpöaalto: pyyhkäisevä kuuma tuulahdus
	sounds["fire_whoosh"] = _mix2(
		_noise(0.32, 0.42, 0.55),
		_tone(0.3, 220.0, 520.0, "saw", 0.02, 0.2, 0.16), 0.0)
	# Tulimyrsky: syvä jyisevä roihu
	sounds["inferno"] = _mix2(
		_noise(0.9, 0.5, 0.18),
		_tone(0.9, 80.0, 140.0, "saw", 0.05, 0.6, 0.32), 0.0)
	sounds["bow"] = _mix2(
		_tone(0.09, 1200.0, 300.0, "tri", 0.002, 0.06, 0.4),
		_noise(0.03, 0.2, 0.8), 0.0)
	# Täysi lataus: voimakas syvä jännitteen laukeaminen
	sounds["bow_charged"] = _mix2(
		_tone(0.22, 260.0, 720.0, "saw", 0.01, 0.14, 0.32),
		_tone(0.14, 1500.0, 400.0, "tri", 0.002, 0.1, 0.22), 0.06)
	# Nuolisade: viheltävä sarja
	sounds["arrow_rain"] = _mix2(
		_noise(0.4, 0.28, 0.72),
		_tone(0.4, 1300.0, 320.0, "sine", 0.02, 0.3, 0.13), 0.0)
	sounds["heal"] = _seq([
		[0.08, 660.0, 660.0, "sine"], [0.08, 880.0, 880.0, "sine"],
		[0.12, 1100.0, 1100.0, "sine"]], 0.3)
	# Valopulssi: pehmeä kellosointu
	sounds["light"] = _mix2(
		_tone(0.25, 880.0, 880.0, "sine", 0.005, 0.2, 0.28),
		_tone(0.25, 1320.0, 1320.0, "sine", 0.01, 0.2, 0.13), 0.0)
	# Siunaus: nouseva enkelimäinen kimallus (ulti)
	sounds["blessing"] = _mix2(_seq([
		[0.12, 660.0, 660.0, "sine"], [0.12, 880.0, 880.0, "sine"],
		[0.12, 1100.0, 1100.0, "sine"], [0.3, 1320.0, 1320.0, "sine"]], 0.2),
		_tone(0.6, 440.0, 880.0, "sine", 0.05, 0.45, 0.12), 0.0)
	sounds["shield"] = _mix2(
		_tone(0.15, 440.0, 440.0, "tri", 0.005, 0.1, 0.3),
		_tone(0.15, 660.0, 660.0, "sine", 0.005, 0.1, 0.25), 0.0)
	# Nuotti: miellyttävä musiikkisointu (Maestron perusisku ja riffi)
	sounds["note"] = _mix2(
		_tone(0.18, 784.0, 784.0, "tri", 0.005, 0.14, 0.26),
		_tone(0.18, 1176.0, 1176.0, "sine", 0.01, 0.14, 0.1), 0.0)
	# Basso: syvä bassoisku
	# Basso: syvä bassoisku (Maestron perushyökkäys -> pidetty maltillisena,
	# ettei toistuva basso jyrää muita ääniä; sine 0.48 -> 0.38).
	sounds["bass"] = _mix2(
		_tone(0.26, 110.0, 68.0, "sine", 0.005, 0.2, 0.38),
		_tone(0.2, 165.0, 110.0, "tri", 0.005, 0.15, 0.16), 0.0)
	# Crescendo: nouseva riemukas huipennus (ulti)
	sounds["crescendo"] = _mix2(_seq([
		[0.12, 523.0, 523.0, "tri"], [0.12, 659.0, 659.0, "tri"],
		[0.12, 784.0, 784.0, "tri"], [0.1, 1046.0, 1046.0, "tri"],
		[0.32, 1318.0, 1318.0, "square"]], 0.2),
		_tone(0.75, 262.0, 523.0, "sine", 0.05, 0.5, 0.14), 0.0)
	sounds["dash"] = _noise(0.1, 0.28, 0.7)
	# Kiekko: viheltävä pyörivä heitto (Shade)
	sounds["disc"] = _mix2(
		_tone(0.14, 700.0, 1100.0, "saw", 0.004, 0.09, 0.2),
		_noise(0.09, 0.16, 0.75), 0.03)
	# Savu: pehmeä häivähdys (naamioituminen, varjoaskel)
	sounds["smoke"] = _noise(0.3, 0.3, 0.32)
	# Vesi: lyhyt roiske (Tiden keihäs)
	sounds["water"] = _mix2(
		_noise(0.15, 0.3, 0.5),
		_tone(0.12, 500.0, 900.0, "sine", 0.005, 0.08, 0.13), 0.0)
	# Aalto: vellova vesipurske (aalto, hyökyaalto)
	sounds["wave"] = _mix2(
		_noise(0.42, 0.4, 0.42),
		_tone(0.38, 300.0, 620.0, "sine", 0.02, 0.28, 0.15), 0.0)
	sounds["blink"] = _mix2(
		_tone(0.12, 880.0, 1760.0, "sine", 0.005, 0.07, 0.35),
		_tone(0.08, 1760.0, 880.0, "sine", 0.01, 0.06, 0.2), 0.1)
	# Valoterä: terävä nopea sähähdys
	sounds["blade"] = _mix2(
		_tone(0.1, 1700.0, 500.0, "saw", 0.002, 0.06, 0.32),
		_noise(0.05, 0.16, 0.85), 0.0)
	# Sähkö: rätisevä kipinä
	sounds["zap"] = _mix2(
		_noise(0.09, 0.32, 0.95),
		_tone(0.1, 2000.0, 700.0, "square", 0.001, 0.06, 0.2), 0.0)
	# Ukkonen: syvä jyrähdys + rätinä (ulti)
	sounds["thunder"] = _mix2(
		_noise(0.55, 0.5, 0.22),
		_tone(0.55, 95.0, 48.0, "saw", 0.005, 0.4, 0.32), 0.0)
	sounds["root"] = _tone(0.2, 130.0, 110.0, "saw", 0.01, 0.12, 0.4)
	# Köynnös: napsahtava orgaaninen ruoskanisku
	sounds["vine"] = _mix2(
		_tone(0.12, 420.0, 90.0, "saw", 0.002, 0.08, 0.32),
		_noise(0.07, 0.24, 0.7), 0.0)
	# Piikit: kahiseva piikkipurkaus
	sounds["thorns"] = _mix2(
		_noise(0.24, 0.36, 0.62),
		_tone(0.2, 200.0, 120.0, "tri", 0.005, 0.15, 0.16), 0.0)
	sounds["ko"] = _mix2(
		_tone(0.3, 300.0, 80.0, "sine", 0.005, 0.22, 0.5),
		_tone(0.15, 990.0, 1320.0, "sine", 0.02, 0.1, 0.16), 0.05)
	sounds["respawn"] = _tone(0.3, 440.0, 1320.0, "sine", 0.02, 0.2, 0.35)
	sounds["pickup"] = _seq([[0.07, 660.0, 660.0, "sine"], [0.1, 990.0, 990.0, "sine"]], 0.4)
	sounds["drop"] = _tone(0.12, 660.0, 330.0, "sine", 0.005, 0.08, 0.4)
	sounds["ult"] = _mix2(_mix2(
		_tone(0.5, 220.0, 330.0, "saw", 0.02, 0.3, 0.25),
		_tone(0.5, 330.0, 495.0, "saw", 0.02, 0.3, 0.2), 0.0),
		_tone(0.4, 440.0, 660.0, "sine", 0.05, 0.25, 0.2), 0.1)
	sounds["ult_ready"] = _mix2(
		_tone(0.3, 1320.0, 1320.0, "sine", 0.005, 0.25, 0.3),
		_tone(0.3, 1980.0, 1980.0, "sine", 0.01, 0.25, 0.15), 0.03)
	sounds["score"] = _tone(0.08, 1100.0, 1100.0, "sine", 0.003, 0.06, 0.42)
	# Kimmoke: pomppiva boing (Sparkringin bumperit)
	sounds["bump"] = _mix2(
		_tone(0.14, 260.0, 760.0, "sine", 0.004, 0.1, 0.4),
		_tone(0.1, 760.0, 380.0, "tri", 0.004, 0.08, 0.18), 0.05)
	# Vaahtopallo: pehmeä thwip (Scoutin kivääri)
	sounds["pop"] = _mix2(
		_tone(0.06, 900.0, 400.0, "sine", 0.002, 0.04, 0.26),
		_noise(0.03, 0.12, 0.6), 0.0)
	# Merkintä: lukituspiippaus
	sounds["mark"] = _mix2(
		_tone(0.1, 1400.0, 1400.0, "square", 0.002, 0.06, 0.2),
		_tone(0.08, 1900.0, 1900.0, "sine", 0.005, 0.05, 0.14), 0.03)
	# Sydämenlyönti: matala tup-tup varoitus kun oma sankari on kriittisessä HP:ssä.
	sounds["heartbeat"] = _mix2(
		_tone(0.10, 95.0, 55.0, "sine", 0.004, 0.07, 0.5),
		_tone(0.09, 82.0, 48.0, "sine", 0.004, 0.07, 0.36), 0.14)
	# Perus/UI-äänet käyttöön heti. MOBA-maailman ja sankarien pitkä
	# synteesi jatkuu taustalla ilman että valikot odottavat koko kirjastoa.
	_deliver_sfx_batch(sounds)

	# --- Eternal Divide / MOBA-maailma ---
	# Linja-aallon oma pieni sotatorvi rytmittää ottelua, mutta varsinaiset
	# minioniäänet ovat lyhyitä ja kevyitä, jotta kahdeksan yksikön aallot
	# eivät peitä sankarien kykyjä.
	sounds["moba_start"] = _mix2(_seq([
		[0.13, 196.0, 262.0, "tri"], [0.13, 262.0, 392.0, "tri"],
		[0.32, 392.0, 523.0, "sine"]], 0.25),
		_tone(0.68, 72.0, 104.0, "sine", 0.02, 0.48, 0.24), 0.0)
	sounds["minion_wave"] = _mix2(
		_seq([[0.10, 196.0, 247.0, "tri"], [0.18, 294.0, 392.0, "tri"]], 0.20),
		_tone(0.34, 82.0, 62.0, "sine", 0.003, 0.24, 0.16), 0.0)
	sounds["minion_melee"] = _mix2(
		_tone(0.075, 430.0, 155.0, "tri", 0.001, 0.05, 0.18),
		_noise(0.055, 0.13, 0.75), 0.0)
	sounds["minion_ranged"] = _mix2(
		_tone(0.105, 780.0, 1280.0, "sine", 0.002, 0.07, 0.18),
		_tone(0.08, 390.0, 620.0, "tri", 0.002, 0.05, 0.08), 0.0)
	sounds["minion_impact"] = _mix2(
		_tone(0.07, 960.0, 420.0, "sine", 0.001, 0.05, 0.14),
		_noise(0.045, 0.08, 0.65), 0.0)
	sounds["minion_down"] = _mix2(
		_tone(0.15, 260.0, 90.0, "tri", 0.002, 0.11, 0.18),
		_noise(0.09, 0.12, 0.45), 0.0)

	# Tornit ovat kylmää arcane-teknologiaa: lukitus on selkeä varoitus,
	# laukaus painava energiatykki ja osuma matala isku. Nexus soi samaa sukua,
	# mutta oktaavia alempana ja leveämpänä.
	sounds["tower_lock"] = _mix2(
		_seq([[0.055, 740.0, 740.0, "square"], [0.075, 980.0, 980.0, "sine"]], 0.18),
		_tone(0.16, 120.0, 92.0, "sine", 0.002, 0.11, 0.12), 0.0)
	sounds["tower_fire"] = _mix2(_mix2(
		_tone(0.25, 145.0, 58.0, "sine", 0.002, 0.18, 0.40),
		_noise(0.16, 0.23, 0.48), 0.0),
		_tone(0.18, 920.0, 360.0, "saw", 0.002, 0.12, 0.13), 0.015)
	sounds["tower_impact"] = _mix2(
		_tone(0.23, 112.0, 44.0, "sine", 0.001, 0.17, 0.42),
		_noise(0.14, 0.25, 0.38), 0.0)
	sounds["tower_guard"] = _mix2(
		_tone(0.28, 360.0, 180.0, "tri", 0.002, 0.22, 0.24),
		_tone(0.26, 720.0, 540.0, "sine", 0.004, 0.20, 0.13), 0.015)
	sounds["tower_crack"] = _mix2(
		_noise(0.36, 0.32, 0.30),
		_seq([[0.10, 210.0, 98.0, "tri"], [0.18, 140.0, 52.0, "tri"]], 0.18), 0.0)
	sounds["tower_destroy"] = _mix2(_mix2(
		_tone(0.82, 88.0, 32.0, "sine", 0.002, 0.66, 0.48),
		_noise(0.72, 0.40, 0.24), 0.0),
		_seq([[0.12, 420.0, 180.0, "tri"], [0.28, 240.0, 72.0, "saw"]], 0.15), 0.05)
	sounds["nexus_laser"] = _mix2(
		_tone(0.24, 1280.0, 340.0, "saw", 0.001, 0.17, 0.25),
		_tone(0.24, 96.0, 62.0, "sine", 0.001, 0.18, 0.33), 0.0)
	sounds["nexus_guard"] = _mix2(
		_tone(0.42, 220.0, 92.0, "tri", 0.003, 0.34, 0.30),
		_tone(0.38, 660.0, 330.0, "sine", 0.006, 0.30, 0.15), 0.02)
	sounds["nexus_crack"] = _mix2(
		_noise(0.58, 0.38, 0.24),
		_tone(0.62, 105.0, 38.0, "saw", 0.003, 0.48, 0.34), 0.0)
	sounds["nexus_exposed"] = _mix2(_seq([
		[0.14, 392.0, 330.0, "tri"], [0.14, 294.0, 247.0, "tri"],
		[0.38, 196.0, 98.0, "saw"]], 0.23),
		_tone(0.86, 82.0, 46.0, "sine", 0.003, 0.68, 0.42), 0.0)
	sounds["nexus_destroy"] = _mix2(_mix2(
		_tone(1.35, 78.0, 24.0, "sine", 0.002, 1.05, 0.58),
		_noise(1.20, 0.52, 0.20), 0.0), _mix2(
		_seq([[0.15, 520.0, 210.0, "saw"], [0.18, 390.0, 130.0, "saw"],
			[0.55, 220.0, 48.0, "tri"]], 0.20),
		_tone(0.95, 1450.0, 170.0, "sine", 0.002, 0.76, 0.10), 0.0), 0.04)

	# Jungle-leirien äänisiluetit: Red on karkea tuli/peto, Blue kiteinen
	# resonanssi ja pieni leiri orgaaninen kynsi. Buffin saaminen soi erillään
	# itse kaadosta, jotta palkinnon tunnistaa myös ruuhkan keskeltä.
	sounds["jungle_small_attack"] = _mix2(
		_tone(0.12, 520.0, 145.0, "saw", 0.002, 0.08, 0.18),
		_noise(0.075, 0.18, 0.62), 0.0)
	sounds["jungle_small_down"] = _mix2(
		_tone(0.24, 310.0, 72.0, "tri", 0.002, 0.18, 0.22),
		_noise(0.17, 0.20, 0.34), 0.0)
	sounds["red_guardian_attack"] = _mix2(
		_tone(0.34, 180.0, 62.0, "saw", 0.002, 0.24, 0.30),
		_noise(0.28, 0.29, 0.42), 0.0)
	sounds["red_guardian_impact"] = _mix2(
		_tone(0.23, 125.0, 46.0, "sine", 0.002, 0.17, 0.34),
		_noise(0.19, 0.28, 0.46), 0.0)
	sounds["red_guardian_down"] = _mix2(
		_tone(0.52, 128.0, 38.0, "saw", 0.003, 0.40, 0.34),
		_noise(0.44, 0.34, 0.27), 0.0)
	sounds["red_buff"] = _mix2(_seq([
		[0.10, 220.0, 294.0, "tri"], [0.10, 330.0, 440.0, "tri"],
		[0.24, 523.0, 659.0, "sine"]], 0.23),
		_noise(0.42, 0.14, 0.52), 0.0)
	sounds["blue_guardian_attack"] = _mix2(
		_tone(0.32, 420.0, 1180.0, "sine", 0.002, 0.22, 0.25),
		_tone(0.28, 840.0, 360.0, "tri", 0.003, 0.20, 0.14), 0.025)
	sounds["blue_guardian_impact"] = _mix2(
		_tone(0.24, 1180.0, 310.0, "sine", 0.002, 0.18, 0.24),
		_noise(0.15, 0.16, 0.76), 0.0)
	sounds["blue_guardian_down"] = _mix2(
		_tone(0.55, 880.0, 170.0, "sine", 0.002, 0.44, 0.28),
		_noise(0.34, 0.18, 0.72), 0.0)
	sounds["blue_buff"] = _mix2(_seq([
		[0.10, 440.0, 523.0, "sine"], [0.10, 659.0, 784.0, "sine"],
		[0.28, 1046.0, 1318.0, "sine"]], 0.22),
		_tone(0.46, 220.0, 440.0, "sine", 0.03, 0.34, 0.13), 0.0)

	# Dragon on hengittävä, siivekäs myrsky; Baron on hidas void-paine.
	# Niiden spawn, hyökkäys, slam, raivo ja kaato eivät jaa yhtään perusääntä.
	sounds["dragon_warning"] = _mix2(
		_tone(0.86, 120.0, 58.0, "saw", 0.04, 0.62, 0.38),
		_noise(0.74, 0.32, 0.34), 0.0)
	sounds["dragon_spawn"] = _mix2(_mix2(
		_tone(1.0, 92.0, 210.0, "saw", 0.03, 0.72, 0.38),
		_noise(0.86, 0.38, 0.42), 0.0),
		_tone(0.62, 620.0, 1280.0, "sine", 0.04, 0.45, 0.14), 0.10)
	sounds["dragon_attack"] = _mix2(
		_noise(0.46, 0.40, 0.48),
		_tone(0.43, 185.0, 760.0, "saw", 0.008, 0.32, 0.25), 0.0)
	sounds["dragon_impact"] = _mix2(
		_tone(0.34, 125.0, 48.0, "sine", 0.002, 0.26, 0.40),
		_noise(0.30, 0.34, 0.46), 0.0)
	sounds["dragon_slam_warning"] = _mix2(
		_tone(0.58, 210.0, 620.0, "saw", 0.01, 0.42, 0.24),
		_tone(0.54, 74.0, 112.0, "sine", 0.01, 0.40, 0.32), 0.0)
	sounds["dragon_slam"] = _mix2(
		_tone(0.64, 82.0, 35.0, "sine", 0.002, 0.50, 0.50),
		_noise(0.52, 0.42, 0.28), 0.0)
	sounds["dragon_enrage"] = _mix2(
		_tone(0.92, 145.0, 52.0, "saw", 0.01, 0.68, 0.42),
		_noise(0.80, 0.40, 0.38), 0.0)
	sounds["dragon_collapse"] = _mix2(
		_tone(0.86, 155.0, 38.0, "saw", 0.003, 0.66, 0.38),
		_noise(0.74, 0.42, 0.30), 0.0)
	sounds["dragon_defeat"] = _mix2(_seq([
		[0.14, 392.0, 523.0, "tri"], [0.14, 523.0, 659.0, "tri"],
		[0.42, 784.0, 1046.0, "sine"]], 0.25),
		_tone(0.72, 98.0, 62.0, "sine", 0.002, 0.56, 0.30), 0.0)
	sounds["baron_warning"] = _mix2(
		_tone(0.95, 68.0, 39.0, "sine", 0.02, 0.72, 0.52),
		_tone(0.82, 210.0, 72.0, "saw", 0.01, 0.62, 0.22), 0.0)
	sounds["baron_spawn"] = _mix2(_mix2(
		_tone(1.15, 58.0, 104.0, "sine", 0.02, 0.86, 0.55),
		_noise(0.95, 0.36, 0.22), 0.0),
		_tone(0.82, 330.0, 980.0, "saw", 0.04, 0.62, 0.17), 0.08)
	sounds["baron_attack"] = _mix2(
		_tone(0.48, 96.0, 42.0, "sine", 0.002, 0.36, 0.47),
		_tone(0.38, 390.0, 120.0, "saw", 0.003, 0.28, 0.20), 0.0)
	sounds["baron_impact"] = _mix2(
		_tone(0.42, 72.0, 30.0, "sine", 0.002, 0.32, 0.52),
		_noise(0.31, 0.28, 0.23), 0.0)
	sounds["baron_slam_warning"] = _mix2(
		_tone(0.62, 52.0, 94.0, "sine", 0.01, 0.46, 0.48),
		_tone(0.55, 185.0, 430.0, "saw", 0.012, 0.40, 0.18), 0.0)
	sounds["baron_slam"] = _mix2(_mix2(
		_tone(0.78, 62.0, 27.0, "sine", 0.002, 0.62, 0.58),
		_noise(0.62, 0.44, 0.22), 0.0),
		_tone(0.42, 280.0, 64.0, "saw", 0.002, 0.32, 0.18), 0.02)
	sounds["baron_enrage"] = _mix2(
		_tone(1.05, 78.0, 32.0, "saw", 0.006, 0.80, 0.48),
		_noise(0.90, 0.42, 0.22), 0.0)
	sounds["baron_collapse"] = _mix2(
		_tone(1.0, 82.0, 24.0, "sine", 0.002, 0.78, 0.55),
		_noise(0.88, 0.46, 0.21), 0.0)
	sounds["baron_defeat"] = _mix2(_seq([
		[0.14, 196.0, 262.0, "tri"], [0.14, 294.0, 392.0, "tri"],
		[0.48, 523.0, 784.0, "sine"]], 0.27),
		_tone(0.86, 68.0, 45.0, "sine", 0.002, 0.68, 0.40), 0.0)

	# Ympäristökerrokset ovat pitkiä, hyvin hiljaisia one-shotteja. AudioDirector
	# limittää niitä pelaajan alueen mukaan: joki solisee, jungle kahisee,
	# baset resonoivat eri sävelillä ja objective-pitit tuntuvat jo ennen spawnia.
	sounds["ambient_jungle"] = _mix2(
		_noise(2.8, 0.075, 0.09),
		_seq([[0.07, 1180.0, 1540.0, "sine"], [0.06, 1360.0, 980.0, "sine"],
			[0.08, 1040.0, 1420.0, "sine"]], 0.055), 1.05)
	sounds["ambient_river"] = _mix2(
		_noise(2.8, 0.105, 0.20),
		_tone(2.8, 145.0, 205.0, "sine", 0.24, 0.62, 0.020), 0.0)
	sounds["ambient_lane"] = _mix2(
		_noise(2.8, 0.070, 0.12),
		_tone(2.7, 78.0, 96.0, "sine", 0.3, 0.62, 0.018), 0.0)
	sounds["ambient_brush"] = _mix2(
		_noise(0.72, 0.12, 0.38),
		_seq([[0.05, 780.0, 1120.0, "sine"], [0.07, 980.0, 720.0, "sine"]], 0.055), 0.25)
	sounds["ambient_blue_base"] = _mix2(
		_tone(2.6, 98.0, 102.0, "sine", 0.24, 0.58, 0.045),
		_tone(2.5, 392.0, 404.0, "sine", 0.28, 0.56, 0.018), 0.03)
	sounds["ambient_orange_base"] = _mix2(
		_tone(2.6, 82.0, 78.0, "sine", 0.24, 0.58, 0.050),
		_tone(2.5, 246.0, 234.0, "tri", 0.28, 0.56, 0.016), 0.03)
	sounds["ambient_baron_pit"] = _mix2(
		_tone(2.9, 54.0, 62.0, "sine", 0.28, 0.72, 0.065),
		_tone(2.8, 180.0, 142.0, "saw", 0.32, 0.70, 0.018), 0.04)
	sounds["ambient_dragon_pit"] = _mix2(
		_noise(2.8, 0.065, 0.16),
		_tone(2.8, 210.0, 285.0, "sine", 0.30, 0.68, 0.035), 0.0)
	# Kenttääänet valmistuvat omana eränä ennen sankarikohtaisia ulteja.
	# Nopea pelaaja saa näin olennaiset MOBA-cuet viimeistään lobby-vaiheessa.
	_deliver_sfx_batch(sounds)

	# Luma: kirkkaat lasikellot ja pehmeä nouseva sointu. Äänissä ei ole tulen
	# kohinaa tai Titanin subbassoa, joten tukikyvyt tunnistaa myös näkemättä.
	sounds["luma_pulse"] = _mix2(
		_tone(0.18, 980.0, 1420.0, "sine", 0.003, 0.13, 0.25),
		_tone(0.16, 1470.0, 1960.0, "tri", 0.006, 0.12, 0.10), 0.025)
	sounds["luma_bloom"] = _mix2(_seq([
		[0.09, 660.0, 660.0, "sine"], [0.09, 880.0, 880.0, "sine"],
		[0.18, 1320.0, 1320.0, "sine"]], 0.25),
		_tone(0.42, 330.0, 660.0, "sine", 0.03, 0.3, 0.12), 0.0)
	sounds["luma_shield"] = _mix2(
		_tone(0.28, 520.0, 780.0, "tri", 0.004, 0.2, 0.25),
		_tone(0.30, 1040.0, 1040.0, "sine", 0.008, 0.24, 0.15), 0.035)
	sounds["luma_ult"] = _mix2(_seq([
		[0.12, 523.0, 523.0, "sine"], [0.12, 659.0, 659.0, "sine"],
		[0.12, 880.0, 880.0, "sine"], [0.34, 1318.0, 1318.0, "tri"]], 0.24),
		_tone(0.78, 262.0, 784.0, "sine", 0.05, 0.58, 0.13), 0.0)

	# Ember: karkea sytytys, ilman pyyhkäisy ja pitkä myrskyroihu.
	sounds["ember_bolt"] = _mix2(
		_tone(0.13, 520.0, 180.0, "saw", 0.003, 0.09, 0.27),
		_noise(0.09, 0.18, 0.72), 0.0)
	sounds["ember_pool"] = _mix2(
		_tone(0.26, 240.0, 620.0, "saw", 0.008, 0.18, 0.24),
		_noise(0.22, 0.26, 0.58), 0.02)
	sounds["ember_impact"] = _mix2(
		_tone(0.22, 170.0, 72.0, "tri", 0.002, 0.16, 0.32),
		_noise(0.20, 0.34, 0.42), 0.0)
	sounds["ember_wave"] = _mix2(
		_noise(0.38, 0.42, 0.58),
		_tone(0.34, 180.0, 640.0, "saw", 0.015, 0.25, 0.18), 0.0)
	sounds["ember_ult"] = _mix2(_mix2(
		_noise(0.95, 0.44, 0.25),
		_tone(0.9, 75.0, 145.0, "saw", 0.04, 0.65, 0.30), 0.0),
		_tone(0.55, 330.0, 780.0, "tri", 0.02, 0.4, 0.15), 0.10)

	# Sankarikohtaiset ultit: äänen siluetti vastaa mekaniikkaa jo ennen kuin
	# pelaaja ehtii katsoa vaikutusta.
	sounds["hush_ult"] = _mix2(
		_tone(0.72, 520.0, 92.0, "sine", 0.012, 0.58, 0.34),
		_tone(0.62, 1040.0, 180.0, "tri", 0.008, 0.48, 0.16), 0.03)
	sounds["volt_ult"] = _mix2(_mix2(
		_noise(0.72, 0.46, 0.28),
		_tone(0.7, 145.0, 52.0, "saw", 0.005, 0.55, 0.32), 0.0),
		_tone(0.32, 1900.0, 430.0, "square", 0.002, 0.22, 0.12), 0.04)
	sounds["tide_ult"] = _mix2(
		_noise(0.76, 0.44, 0.34),
		_tone(0.7, 180.0, 760.0, "sine", 0.018, 0.52, 0.24), 0.02)
	sounds["quill_ult"] = _mix2(
		_tone(0.42, 210.0, 1750.0, "saw", 0.004, 0.30, 0.29),
		_noise(0.24, 0.24, 0.72), 0.045)
	sounds["boulder_ult"] = _mix2(_mix2(
		_tone(0.82, 72.0, 34.0, "sine", 0.004, 0.64, 0.48),
		_noise(0.72, 0.38, 0.24), 0.0),
		_tone(0.34, 210.0, 68.0, "tri", 0.003, 0.24, 0.20), 0.02)
	sounds["bramble_ult"] = _mix2(
		_noise(0.64, 0.34, 0.48),
		_tone(0.62, 165.0, 420.0, "saw", 0.008, 0.46, 0.22), 0.02)
	sounds["obsidian_ult"] = _mix2(_mix2(
		_tone(0.92, 62.0, 118.0, "sine", 0.006, 0.72, 0.50),
		_noise(0.72, 0.42, 0.24), 0.0),
		_tone(0.62, 260.0, 58.0, "saw", 0.006, 0.50, 0.22), 0.05)

	# Titan: metallinen isku ja selvästi painava matala runko.
	sounds["titan_punch"] = _mix2(
		_tone(0.16, 105.0, 48.0, "sine", 0.002, 0.12, 0.48),
		_noise(0.075, 0.30, 0.35), 0.0)
	sounds["titan_grab"] = _mix2(
		_tone(0.24, 150.0, 78.0, "tri", 0.003, 0.18, 0.34),
		_tone(0.14, 620.0, 260.0, "square", 0.002, 0.1, 0.10), 0.025)
	sounds["titan_throw"] = _mix2(
		_noise(0.26, 0.34, 0.4),
		_tone(0.30, 120.0, 42.0, "sine", 0.003, 0.23, 0.50), 0.05)
	sounds["titan_launch"] = _mix2(
		_tone(0.52, 70.0, 35.0, "sine", 0.003, 0.4, 0.50),
		_noise(0.42, 0.32, 0.22), 0.02)
	sounds["titan_brace"] = _mix2(
		_tone(0.34, 180.0, 92.0, "tri", 0.004, 0.26, 0.28),
		_tone(0.22, 540.0, 390.0, "square", 0.002, 0.17, 0.10), 0.03)
	sounds["titan_rage"] = _mix2(_mix2(
		_tone(0.82, 62.0, 38.0, "sine", 0.004, 0.62, 0.52),
		_noise(0.75, 0.37, 0.20), 0.0),
		_tone(0.55, 150.0, 280.0, "saw", 0.03, 0.4, 0.17), 0.08)

	# Salvo: metallinen kranaatinlähtö, korkea morttarivihellys ja raskas
	# hydraulinen bunkkeri. Ääniperhe erottuu Embersin tulesta ja Scoutin popista.
	sounds["salvo_grenade"] = _mix2(
		_tone(0.11, 280.0, 115.0, "tri", 0.002, 0.075, 0.34),
		_noise(0.065, 0.24, 0.56), 0.0)
	sounds["salvo_mortar_launch"] = _mix2(
		_tone(0.32, 150.0, 680.0, "saw", 0.004, 0.22, 0.27),
		_noise(0.18, 0.30, 0.48), 0.025)
	sounds["salvo_mortar_impact"] = _mix2(_mix2(
		_tone(0.48, 82.0, 36.0, "sine", 0.002, 0.36, 0.50),
		_noise(0.34, 0.42, 0.30), 0.0),
		_tone(0.18, 520.0, 120.0, "saw", 0.002, 0.12, 0.14), 0.015)
	sounds["salvo_bunker"] = _mix2(_mix2(
		_tone(0.58, 105.0, 54.0, "tri", 0.003, 0.44, 0.42),
		_noise(0.42, 0.34, 0.28), 0.0),
		_seq([[0.11, 410.0, 280.0, "square"], [0.14, 330.0, 190.0, "square"]], 0.13), 0.06)
	sounds["salvo_bunker_open"] = _mix2(
		_tone(0.28, 140.0, 390.0, "tri", 0.003, 0.2, 0.25),
		_noise(0.18, 0.20, 0.46), 0.0)
	sounds["salvo_rocket_launch"] = _mix2(
		_tone(0.62, 72.0, 210.0, "saw", 0.01, 0.46, 0.34),
		_noise(0.55, 0.40, 0.26), 0.0)
	sounds["salvo_rocket_impact"] = _mix2(_mix2(
		_tone(0.92, 66.0, 28.0, "sine", 0.002, 0.72, 0.55),
		_noise(0.78, 0.50, 0.24), 0.0),
		_tone(0.46, 230.0, 62.0, "saw", 0.002, 0.34, 0.20), 0.015)

	_deliver_sfx_batch(sounds)


## Kutsutaan pääsäikeessä kun uusia biisejä valmistuu. Käynnistää halutun
## biisin heti kun se on saatavilla (ei odota kaikkia).
func _music_ready(tracks: Dictionary) -> void:
	for key in tracks:
		_music_tracks[key] = tracks[key]
	if not _music_enabled:
		return
	if _current_track == "":
		_current_track = "menu"
	if _music_tracks.has(_current_track) and _playing_track != _current_track:
		_crossfade_to(_current_track)


func _sfx_ready(streams: Dictionary) -> void:
	for key in streams:
		_streams[key] = streams[key]
		if _pending_ambient.has(key):
			var request: Array = _pending_ambient[key]
			_pending_ambient.erase(key)
			play(str(key), float(request[0]), float(request[1]), request[2])


## Muuntaa tähän asti rakennetun tehoste-erän WAV-muotoon, toimittaa sen
## pääsäikeelle ja tyhjentää työsanakirjan seuraavaa erää varten.
func _deliver_sfx_batch(sounds: Dictionary) -> void:
	if sounds.is_empty():
		return
	var result := {}
	for key in sounds:
		result[key] = _to_wav(sounds[key], false)
	sounds.clear()
	call_deferred("_sfx_ready", result)


## Rakentaa luupattavan biisin: bassolinja + arpeggio + valinnainen rytmi.
func _make_track(roots: Array, minor: Array, bar: float, lead_wave: String,
		kick_strength: float, gain: float) -> PackedFloat32Array:
	var total := bar * roots.size()
	var out := PackedFloat32Array()
	out.resize(int(total * RATE))
	for i in range(out.size()):
		out[i] = 0.0
	for bar_i in range(roots.size()):
		var root: float = roots[bar_i]
		var bass := _tone(bar, root, root, "sine", 0.05, bar * 0.15, 0.16 * gain)
		out = _mix_at(out, bass, bar_i * bar)
		var third := 2.4 if minor[bar_i] else 2.5
		# Kierrätä arpeggio-kuviota tahdeittain (sama konsonoiva sävelvarasto,
		# vaihteleva kontuuri) -> ei enää identtistä figuuria joka tahdissa.
		var patterns := [
			[2.0, third, 3.0, 4.0, 3.0, third],
			[2.0, 3.0, third, 4.0, third, 2.0],
			[4.0, 3.0, third, 2.0, third, 3.0],
		]
		var steps: Array = patterns[bar_i % patterns.size()]
		var note_len := bar / steps.size()
		for step_i in range(steps.size()):
			var freq: float = root * steps[step_i]
			var note := _tone(note_len * 0.85, freq, freq, lead_wave, 0.01, note_len * 0.4, 0.06 * gain)
			out = _mix_at(out, note, bar_i * bar + step_i * note_len)
		if kick_strength > 0.0:
			for beat in range(4):
				out = _mix_at(out, _kick(kick_strength * gain), bar_i * bar + beat * (bar / 4.0))
	return out


## Lyhyt rumpupotku (basso + naks).
func _kick(strength: float) -> PackedFloat32Array:
	return _mix2(
		_tone(0.12, 135.0, 45.0, "sine", 0.002, 0.09, 0.42 * strength),
		_noise(0.035, 0.22 * strength, 0.5), 0.0)


# --- Aallonmuodostus ---

func _tone(dur: float, f0: float, f1: float, wave: String,
		attack: float, release: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / n
		var freq := lerpf(f0, f1, t)
		phase += freq / RATE
		var s := 0.0
		var p := fmod(phase, 1.0)
		match wave:
			"sine":
				s = sin(phase * TAU)
			"square":
				s = 1.0 if p < 0.5 else -1.0
			"tri":
				s = 4.0 * absf(p - 0.5) - 1.0
			"saw":
				s = 2.0 * p - 1.0
		var env := 1.0
		var time_s := float(i) / RATE
		if time_s < attack:
			env = time_s / maxf(attack, 0.0001)
		var tail := dur - time_s
		if tail < release:
			env = minf(env, tail / maxf(release, 0.0001))
		out[i] = s * env * gain
	return out


func _noise(dur: float, gain: float, lowpass: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	# DC-esto (~30 Hz ylipäästö): poistaa suodatetun kohinan subbasso-mudan
	# ja tasajännitteen -> vapauttaa headroomia, ei ohenna kuuluvaa bodya.
	var hp := 0.0
	var prev := 0.0
	var atk_n := maxi(int(0.003 * RATE), 1)   # 3 ms nousu: poistaa alun naksun
	# Alipäästön rajataajuus ~ kerroin*RATE, joten skaalataan kerroin niin että
	# kohinan sointi säilyy SAMANA vaikka RATE nousi (22050 -> 44100). Näin vain
	# tonaalinen aliasointi paranee, kohinan luonne ei muutu yllättäen.
	var lp := clampf(lowpass * (22050.0 / float(RATE)), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 1000.0 + gain * 777.0)
	for i in range(n):
		var x := rng.randf_range(-1.0, 1.0)
		y += lp * (x - y)
		hp = 0.996 * (hp + y - prev)
		prev = y
		var env := 1.0 - float(i) / n
		if i < atk_n:
			env *= float(i) / float(atk_n)
		out[i] = hp * env * gain
	return out


## Soittaa palat peräkkäin (fanfaarit, arpeggiot).
func _seq(notes: Array, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		var piece := _tone(note[0], note[1], note[2], note[3], 0.005,
			minf(0.08, note[0] * 0.5), gain)
		var base := out.size()
		out.resize(base + piece.size())
		for i in range(piece.size()):
			out[base + i] = piece[i]
	return out


func _mix2(a: PackedFloat32Array, b: PackedFloat32Array, b_offset: float) -> PackedFloat32Array:
	return _mix_at(a, b, b_offset)


func _mix_at(base: PackedFloat32Array, add: PackedFloat32Array, offset_sec: float) -> PackedFloat32Array:
	var offset := int(offset_sec * RATE)
	var needed := offset + add.size()
	if needed > base.size():
		var old := base.size()
		base.resize(needed)
		for i in range(old, needed):
			base[i] = 0.0
	for i in range(add.size()):
		base[offset + i] += add[i]
	return base


func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes[i * 2] = v & 0xff
		bytes[i * 2 + 1] = (v >> 8) & 0xff
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
