extends Node
## Äänijärjestelmä (autoload: AudioMgr). Kaikki äänet syntetisoidaan
## proseduraalisesti käynnistyksessä taustasäikeessä — ei äänitiedostoja.
## play("nimi") toimii heti; jos synteesi on kesken, ääni jää vain väliin.
##
## Rakenne:
##   SoundDefs  — rekisteri: avain -> kategoria, trimmi, toistoraja, prioriteetti
##   AudioDsp   — jaetut DSP-palikat + mittaus ja äänekkyysnormalisointi
##   SoundBank  — tehosteiden reseptit
##   MusicBank  — biisit ja niiden kerrokset
##   tämä luokka — väylät, soitinpoolit, ääniprioriteetit, kuuntelijat, musiikki
##
## Kaikki puskurit normalisoidaan synteesin jälkeen kategoriansa
## äänekkyystavoitteeseen ja rajoitetaan -1 dBFS:ään. Mitatut arvot jäävät
## talteen (loudness_report / dump_loudness).

const POOL_SIZES := {"world": 26, "ui": 6, "alert": 4, "ambient": 4, "stinger": 2}
const MUSIC_VOL := -8.0          # musiikin soittimien häivytystaso
const MIN_REPEAT_MS := 28        # ehdoton alaraja saman äänen toistolle

# --- Adaptiivinen musiikki ---
# Jokainen biisi on joukko kerroksia, jotka soivat rinnakkain ja pysyvät
# näytetarkasti synkassa. Kerroksen voimakkuus seuraa INTENSITEETTIÄ (0..1),
# jonka areena laskee sekunnin välein oikeasta pelitilasta.
const LAYER_RANGE := {
	"bed": [0.0, 0.0],           # aina täysillä
	"pulse": [0.16, 0.42],
	"lead": [0.38, 0.66],
	"tension": [0.58, 0.92],
}
# Hystereesi: nousu on nopeampi kuin lasku ja pieni muutos jätetään huomiotta,
# jottei mittari väpätä taistelun reunalla.
const INT_RISE := 0.35           # yksikköä sekunnissa ylös
const INT_FALL := 0.10           # yksikköä sekunnissa alas
const INT_DEADZONE := 0.04
const LAYER_TAU := 0.35          # s: kerroksen ristihäivytyksen aikavakio (~1.2 s täysi)
const DECK_TAU := 0.28           # s: biisistä toiseen
const CALM_EXIT := 0.45          # tämän yli...
const CALM_HOLD := 3.0           # ...näin kauan -> rauhallinen peti vaihtuu taisteluun

## Musiikin tilacuet: motiivi + musiikin duckaus + intensiteetin alaraja.
## floor < 0 = ei kosketa intensiteettiin (valikot, loppuruutu).
const MUSIC_CUES := {
	"match_start": {"sound": "cue_match_start", "duck": 3.0, "release": 1.4, "floor": 0.10},
	"first_blood": {"sound": "cue_first_blood", "duck": 4.0, "release": 1.1, "floor": 0.30},
	"objective_spawn": {"sound": "cue_objective", "duck": 4.0, "release": 1.2, "floor": 0.35},
	"objective_taken": {"sound": "cue_objective_taken", "duck": 5.0, "release": 1.2, "floor": 0.45},
	"nexus_exposed": {"sound": "cue_nexus", "duck": 7.0, "release": 1.5, "floor": 0.78},
	"victory": {"sound": "cue_victory", "duck": 9.0, "release": 2.0, "floor": -1.0},
	"defeat": {"sound": "cue_defeat", "duck": 9.0, "release": 2.0, "floor": -1.0},
	"promo_tier": {"sound": "cue_promo_tier", "duck": 6.0, "release": 1.6, "floor": -1.0},
	"promo_division": {"sound": "cue_promo_div", "duck": 4.0, "release": 1.2, "floor": -1.0},
}

# Etäisyysvaimennus (positionaaliset äänet): täysi voimakkuus lähellä, sitten
# hiipuu. Suuret kartat (esim. MOBA 4400x2600) eivät enää soi tasaisen kovaa.
const AUDIO_NEAR := 520.0        # px: tähän asti täysi voimakkuus
const AUDIO_FALLOFF := 34.0      # px per -1 dB tämän jälkeen
const AUDIO_CUTOFF_DB := -38.0   # tätä hiljaisemmat ohitetaan (liian kaukana)

# Panorointi tehdään viidellä kiinteällä panner-väylällä, jotka syöttävät
# SFX-väylää. Näin poolatuille AudioStreamPlayereille saadaan suuntatieto
# ilman 2D-kuuntelijoita (jaettu ruutu ei tue niitä järkevästi).
const PAN_WIDTH := 900.0         # px sivusuunnassa = täysi panorointi
const PAN_VALUES := [-0.85, -0.45, 0.0, 0.45, 0.85]
const PAN_BUS_PREFIX := "SFX_P"

# Biisipoolit: valikot ja taistelut arpovat vaihtelua näistä.
# HUOM: battle4 EI ole poolissa — se on varattu nexus-avauksen huipennukselle
# (play_music("battle4")). Jos se olisi kierrossa, ~25 % otteluista alkaisi jo
# battle4:llä ja huipennuksesta tulisi kuulumaton no-op.
const MUSIC_POOLS := {
	"menu": ["menu", "menu2"],
	"lobby": ["lobby", "lobby2"],
	"battle": ["battle", "battle2", "battle3"],
}

var _streams := {}
var _defs := {}                     # avain -> täysi määrittely (SoundDefs)
var _loudness := {}                 # avain -> mitatut arvot synteesin jälkeen
var _pools := {}                    # poolin nimi -> Array[AudioStreamPlayer]
var _voice_cat := {}                # poolin nimi -> Array[String]
var _voice_prio := {}               # poolin nimi -> Array[int]
var _voice_seq := {}                # poolin nimi -> Array[int] (ikäjärjestys)
var _seq_counter := 0
var _pan_ready := false

var _decks: Array = []              # kaksi "kannua", kumpikin kerros -> soitin
var _deck_gain: Array = [0.0, 0.0]
var _deck_target: Array = [0.0, 0.0]
var _layer_gain := {}               # kerros -> nykyinen kerroin (häivytetty)
var _intensity := 0.0
var _intensity_target := 0.0
var _calm_hold := 0.0
var _auto_promote := false          # rauhallinen peti saa vaihtua taisteluun
var _music_tracks := {}             # nimi -> {kerros -> AudioStreamWAV}
var _active_idx := 0
var _current_track := ""             # haluttu biisi
var _playing_track := ""             # tällä hetkellä soiva biisi
var _music_enabled := true
var _thread: Thread = null
var _warned := {}
var _pending_ambient := {}         # nimi -> [spread, volume_db, world_pos]

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
	_defs = SoundDefs.resolve_all()
	_make_bus("SFX", "Master")
	_make_bus("SFX_UI", "Master")     # kuiva UI-väylä (ei kaikua)
	_make_bus("SFX_ALERT", "Master")
	_make_bus("SFX_AMBIENT", "Master")
	_make_bus("Music", "Master")
	_make_bus("MusicCue", "Master")   # cuet eivät saa duckata itseään
	_setup_master_fx()
	_setup_sfx_fx()
	_setup_pan_buses()
	_build_pool("world", "SFX")
	_build_pool("ui", "SFX_UI")
	_build_pool("alert", "SFX_ALERT")
	_build_pool("ambient", "SFX_AMBIENT")
	_build_pool("stinger", "MusicCue")
	for deck_i in range(2):
		var deck := {}
		for layer_name in MusicBank.LAYERS:
			var mp := AudioStreamPlayer.new()
			mp.bus = "Music"
			mp.volume_db = -60.0
			add_child(mp)
			deck[layer_name] = mp
		_decks.append(deck)
	for layer_name in MusicBank.LAYERS:
		_layer_gain[layer_name] = 1.0 if String(layer_name) == MusicBank.BED else 0.0

	# Autoload-järjestys on Game -> AudioMgr, joten Game.apply_options() ehtii
	# ajaa ENNEN kuin nämä väylät ovat olemassa. Asetetaan voimakkuudet
	# uudelleen tässä, muuten tallennetut liukusäätimet eivät vaikuttaneet
	# mihinkään ennen kuin asetuksia kävi käsin muuttamassa.
	if Game.options.has("volume"):
		set_master_volume(float(Game.options.volume))
		set_music_volume(float(Game.options.music_volume))
		set_sfx_volume(float(Game.options.sfx_volume))
		set_music_enabled(bool(Game.options.music))

	_thread = Thread.new()
	_thread.start(_synth_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _build_pool(pool_name: String, bus_name: String) -> void:
	var size: int = int(POOL_SIZES.get(pool_name, 8))
	var list: Array = []
	var cats: Array = []
	var prios: Array = []
	var seqs: Array = []
	for i in range(size):
		var player := AudioStreamPlayer.new()
		player.bus = bus_name
		add_child(player)
		list.append(player)
		cats.append("")
		prios.append(-1)
		seqs.append(0)
	_pools[pool_name] = list
	_voice_cat[pool_name] = cats
	_voice_prio[pool_name] = prios
	_voice_seq[pool_name] = seqs


func _make_bus(bus_name: String, send_to: String) -> int:
	var existing := AudioServer.get_bus_index(bus_name)
	if existing >= 0:
		return existing
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	return idx


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


## Viisi kiinteää panorointiväylää maailman äänille. Ne syöttävät SFX-väylää,
## joten kaiku ja tehosteiden liukusäädin toimivat entiseen tapaan.
func _setup_pan_buses() -> void:
	for i in range(PAN_VALUES.size()):
		var bus_name: String = PAN_BUS_PREFIX + str(i)
		var idx := _make_bus(bus_name, "SFX")
		if AudioServer.get_bus_effect_count(idx) > 0:
			continue
		var panner := AudioEffectPanner.new()
		panner.pan = float(PAN_VALUES[i])
		AudioServer.add_bus_effect(idx, panner)
	_pan_ready = true


# --- Julkinen rajapinta ---

## Soittaa tehosteen. pos-parametri (maailmakoordinaatti) tekee äänestä
## positionaalisen (jos rekisteri sallii): se vaimenee ja panoroituu LÄHIMMÄN
## kuuntelijan mukaan, ja liian kaukaiset ohitetaan kokonaan.
##
## spread on vanha suhdeluku-parametri sävelvaihtelulle. Rekisteri määrää nyt
## vaihtelun absoluuttisen suuruuden puolisävelaskelina, ja spread toimii sen
## kertoimena: 0.0 = ei vaihtelua, 0.08 (oletus) = rekisterin arvo sellaisenaan.
func play(sound_name: String, spread := 0.08, volume_db := 0.0, pos := Vector2.INF) -> void:
	# Simulaatiossa (botti vs. botti, nopeutettu) äänet ovat turhia ja
	# kuormittavat äänipoolia — vaimennetaan keskitetysti kaikki tehosteet.
	if Game.simulating:
		return
	var def: Dictionary = _defs.get(sound_name, {})
	if def.is_empty():
		def = SoundDefs.fallback()
	if not _streams.has(sound_name):
		# Ympäristökerros on pitkä ja edelleen ajankohtainen valmistuttuaan, joten
		# nopean suoraan-otteluun käynnistyksen ensimmäinen pyyntö jonotetaan.
		if String(def["cat"]) == "ambient":
			_pending_ambient[sound_name] = [spread, volume_db, pos]
		if (_thread == null or not _thread.is_alive()) \
				and not _streams.is_empty() and not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Tuntematon ääni: %s" % sound_name)
		return

	# Positionaalinen vaimennus + panorointi lähimmän kuuntelijan mukaan.
	# Tehdään ENNEN toistorajaa, jotta liian kaukainen (ohitettu) ääni ei
	# "kuluta" toistoikkunaa ja vaienna heti perään tulevaa lähempää ääntä.
	var db := volume_db
	var pan := 0.0
	if bool(def["positional"]) and listener_on and is_finite(pos.x):
		var near: Vector2 = nearest_listener(pos)
		var dist: float = pos.distance_to(near)
		if dist > AUDIO_NEAR:
			db -= (dist - AUDIO_NEAR) / AUDIO_FALLOFF
			if db < AUDIO_CUTOFF_DB:
				return
		pan = clampf((pos.x - near.x) / PAN_WIDTH, -1.0, 1.0)

	# Kakofonian/klippauksen esto: sama ääni ei käynnisty liian tiheään.
	var now := Time.get_ticks_msec()
	var last: int = int(_last_play.get(sound_name, -100000))
	var repeat_ms: int = maxi(int(def["cooldown"]), MIN_REPEAT_MS)
	if now - last < repeat_ms:
		return

	var pool_name: String = String(def["pool"])
	var cat: String = String(def["cat"])
	var player: AudioStreamPlayer = _acquire(pool_name, cat, int(def["prio"]))
	if player == null:
		return   # tärkeämmät äänet pitävät pintansa; tämä jää soimatta
	_last_play[sound_name] = now

	var bus_name: String = String(def["bus"])
	if pool_name == "world" and _pan_ready:
		bus_name = PAN_BUS_PREFIX + str(_pan_index(pan))
	player.bus = bus_name
	player.stream = _streams[sound_name]
	var semis: float = float(def["pitch_var"]) * clampf(spread / 0.08, 0.0, 2.0)
	if semis > 0.0:
		player.pitch_scale = pow(2.0, randf_range(-semis, semis) / 12.0)
	else:
		player.pitch_scale = 1.0
	player.volume_db = db
	player.play()


## Varaa soittimen poolista. Järjestys:
##  1) kategorian samanaikaisuuskatto täynnä -> korvaa oman kategorian vanhin
##  2) vapaa soitin
##  3) pooli täynnä -> varasta matalin prioriteetti (tasapelissä vanhin).
## Korkeampaa prioriteettia ei koskaan keskeytetä: prio 3 objective-cue saa
## viedä prio 0 minioni-iskun soittimen, mutta ei koskaan päinvastoin.
func _acquire(pool_name: String, cat: String, prio: int) -> AudioStreamPlayer:
	if not _pools.has(pool_name):
		return null
	var pool: Array = _pools[pool_name]
	var cats: Array = _voice_cat[pool_name]
	var prios: Array = _voice_prio[pool_name]
	var seqs: Array = _voice_seq[pool_name]
	var cap: int = SoundDefs.voice_cap(cat)
	var used := 0
	var free_idx := -1
	for i in range(pool.size()):
		var p: AudioStreamPlayer = pool[i]
		if not p.playing:
			if free_idx < 0:
				free_idx = i
		elif String(cats[i]) == cat:
			used += 1
	if used >= cap:
		var old_idx := -1
		var old_seq := 0x7FFFFFFFFFFF
		for i in range(pool.size()):
			var pp: AudioStreamPlayer = pool[i]
			if not pp.playing or String(cats[i]) != cat:
				continue
			if int(seqs[i]) < old_seq:
				old_seq = int(seqs[i])
				old_idx = i
		if old_idx < 0:
			return null
		return _claim(pool_name, old_idx, cat, prio)
	if free_idx >= 0:
		return _claim(pool_name, free_idx, cat, prio)
	var victim := -1
	var victim_prio := 99
	var victim_seq := 0x7FFFFFFFFFFF
	for i in range(pool.size()):
		var vp: int = int(prios[i])
		if vp > prio:
			continue
		if vp < victim_prio or (vp == victim_prio and int(seqs[i]) < victim_seq):
			victim_prio = vp
			victim_seq = int(seqs[i])
			victim = i
	if victim < 0:
		return null
	return _claim(pool_name, victim, cat, prio)


func _claim(pool_name: String, idx: int, cat: String, prio: int) -> AudioStreamPlayer:
	var pool: Array = _pools[pool_name]
	var player: AudioStreamPlayer = pool[idx]
	if player.playing:
		player.stop()
	var cats: Array = _voice_cat[pool_name]
	var prios: Array = _voice_prio[pool_name]
	var seqs: Array = _voice_seq[pool_name]
	cats[idx] = cat
	prios[idx] = prio
	_seq_counter += 1
	seqs[idx] = _seq_counter
	return player


func _pan_index(pan: float) -> int:
	var last: int = PAN_VALUES.size() - 1
	return clampi(int(round((pan + 1.0) * 0.5 * float(last))), 0, last)


## Lähin paikallinen kuuntelija. Jaetussa ruudussa vaimennus JA panorointi
## lasketaan aina siitä kuuntelijasta, joka on lähimpänä äänilähdettä — ei
## keskiarvosta eikä ensimmäisestä.
func nearest_listener(pos: Vector2) -> Vector2:
	if listener_positions.is_empty():
		return listener_pos
	var best: Vector2 = listener_positions[0]
	var best_d: float = pos.distance_squared_to(best)
	for i in range(1, listener_positions.size()):
		var cand: Vector2 = listener_positions[i]
		var d: float = pos.distance_squared_to(cand)
		if d < best_d:
			best_d = d
			best = cand
	return best


## Jaetussa ruudussa ääni vaimennetaan lähimmän paikallisen pelaajan mukaan.
func set_listener_positions(positions: Array) -> void:
	listener_positions = positions.duplicate()
	listener_on = not listener_positions.is_empty()


func clear_listener_positions() -> void:
	listener_positions.clear()
	# Ilman tätä positionaaliset äänet olisi vaimennettu origoon nähden
	# (listener_pos = 0,0) heti kun kamera vapauttaa kuuntelijat.
	listener_on = false


func set_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(v, 0.001, 1.0)))


func set_sfx_volume(v: float) -> void:
	var db := linear_to_db(clampf(v, 0.0001, 1.0))
	# Sekä pelin SFX että kuiva UI-väylä seuraavat samaa liukusäädintä.
	# Panorointiväylät syöttävät SFX:ää, joten ne seuraavat automaattisesti.
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
	for bus_name in ["SFX_UI", "SFX_ALERT", "SFX_AMBIENT"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, db)


func set_music_volume(v: float) -> void:
	_music_base_db = linear_to_db(clampf(v, 0.0001, 1.0))
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _music_base_db)
	# Musiikkicuet ovat musiikkia: sama liukusäädin, mutta ei duckausta.
	var cue_idx := AudioServer.get_bus_index("MusicCue")
	if cue_idx >= 0:
		AudioServer.set_bus_volume_db(cue_idx, _music_base_db)


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
	var nxt: int = 1 - _active_idx
	var layers: Dictionary = _music_tracks[track]
	var deck: Dictionary = _decks[nxt]
	for layer_name in MusicBank.LAYERS:
		var mp: AudioStreamPlayer = deck[layer_name]
		if layers.has(layer_name):
			mp.stream = layers[layer_name]
			mp.volume_db = -60.0
			mp.play()
		else:
			mp.stop()
			mp.stream = null
	_deck_gain[nxt] = 0.0
	_deck_target[nxt] = 1.0
	_deck_target[_active_idx] = 0.0
	_active_idx = nxt
	_playing_track = track


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		for deck in _decks:
			for layer_name in MusicBank.LAYERS:
				var mp: AudioStreamPlayer = deck[layer_name]
				mp.stop()
		_deck_gain = [0.0, 0.0]
		_deck_target = [0.0, 0.0]
		_playing_track = ""
	elif _current_track != "" and _music_tracks.has(_current_track):
		_crossfade_to(_current_track)


# --- Adaptiivinen intensiteetti ---

## Areena kutsuu tätä kerran sekunnissa raa'alla tavoitearvolla 0..1.
## Hystereesi ja häivytys hoidetaan täällä, joten kutsuja saa heittää
## hyppiviäkin lukemia ilman että musiikki nykii.
func set_music_intensity(value: float) -> void:
	_intensity_target = clampf(value, 0.0, 1.0)


func music_intensity() -> float:
	return _intensity


## Ottelun musiikki alkaa rauhallisesta linjapedistä ja nousee taistelubiisiin
## itsestään, kun intensiteetti pysyy CALM_EXITin yllä CALM_HOLD sekuntia.
func start_match_music() -> void:
	_intensity = 0.0
	_intensity_target = 0.0
	_calm_hold = 0.0
	_auto_promote = true
	if _music_tracks.has("lane_calm"):
		play_music("lane_calm")
	else:
		_current_track = "lane_calm"


## Tilacue: lyhyt motiivi omalla väylällään + musiikin duckaus + tarvittaessa
## intensiteetin alaraja (esim. nexus auki pitää musiikin loppupelitasolla).
func music_cue(cue: String) -> void:
	var spec: Dictionary = MUSIC_CUES.get(cue, {})
	if spec.is_empty():
		return
	play(String(spec["sound"]), 0.0, 0.0)
	duck_music(float(spec["duck"]), float(spec["release"]))
	var floor_v: float = float(spec["floor"])
	if floor_v >= 0.0:
		_intensity_target = maxf(_intensity_target, floor_v)
		_intensity = maxf(_intensity, floor_v - 0.15)


func _process(delta: float) -> void:
	if _decks.is_empty() or not _music_enabled:
		return
	_advance_intensity(delta)
	_advance_layers(delta)
	_advance_decks(delta)
	_apply_music_mix()
	_check_calm_promotion(delta)


func _advance_intensity(delta: float) -> void:
	var diff: float = _intensity_target - _intensity
	if absf(diff) <= INT_DEADZONE:
		return
	var step: float = (INT_RISE if diff > 0.0 else INT_FALL) * delta
	if absf(diff) <= step:
		_intensity = _intensity_target
	else:
		_intensity += step * signf(diff)


func _layer_target(layer_name: String) -> float:
	var span: Array = LAYER_RANGE.get(layer_name, [0.0, 0.0])
	var lo: float = float(span[0])
	var hi: float = float(span[1])
	if hi <= lo:
		return 1.0
	return clampf((_intensity - lo) / (hi - lo), 0.0, 1.0)


func _advance_layers(delta: float) -> void:
	var k: float = 1.0 - exp(-delta / LAYER_TAU)
	for layer_name in MusicBank.LAYERS:
		var cur: float = float(_layer_gain[layer_name])
		var target: float = _layer_target(String(layer_name))
		_layer_gain[layer_name] = cur + (target - cur) * k


func _advance_decks(delta: float) -> void:
	var k: float = 1.0 - exp(-delta / DECK_TAU)
	for i in range(_deck_gain.size()):
		var cur: float = float(_deck_gain[i])
		var target: float = float(_deck_target[i])
		var next_v: float = cur + (target - cur) * k
		if target <= 0.0 and next_v < 0.004:
			next_v = 0.0
			var deck: Dictionary = _decks[i]
			for layer_name in MusicBank.LAYERS:
				var mp: AudioStreamPlayer = deck[layer_name]
				if mp.playing:
					mp.stop()
		_deck_gain[i] = next_v


func _apply_music_mix() -> void:
	for i in range(_decks.size()):
		var deck: Dictionary = _decks[i]
		var deck_g: float = float(_deck_gain[i])
		for layer_name in MusicBank.LAYERS:
			var mp: AudioStreamPlayer = deck[layer_name]
			if mp.stream == null:
				continue
			var g: float = deck_g * float(_layer_gain[layer_name])
			if g <= 0.0015:
				mp.volume_db = -60.0
			else:
				mp.volume_db = MUSIC_VOL + linear_to_db(g)


func _check_calm_promotion(delta: float) -> void:
	if not _auto_promote or _playing_track != "lane_calm":
		return
	if _intensity < CALM_EXIT:
		_calm_hold = 0.0
		return
	_calm_hold += delta
	if _calm_hold >= CALM_HOLD:
		_auto_promote = false
		_calm_hold = 0.0
		play_music_pool("battle")


# --- Äänekkyysraportti (debug) ---

## Jokaisen syntetisoidun äänen mitatut arvot: peak/RMS ennen ja jälkeen
## normalisoinnin, käytetty korjaus, DC-offset, klippinäytteet ja kesto.
func loudness_report() -> Dictionary:
	return _loudness.duplicate(true)


## Tulostaa äänekkyystaulukon ja hajonnan konsoliin.
func dump_loudness() -> void:
	var keys: Array = _loudness.keys()
	keys.sort()
	print("avain                    kat        vpeak   vrms   upeak   urms   korj clip")
	var lo := 999.0
	var hi := -999.0
	for key in keys:
		var d: Dictionary = _loudness[key]
		var rms: float = float(d["rms_db"])
		lo = minf(lo, rms)
		hi = maxf(hi, rms)
		print("%-24s %-9s %6.2f %6.2f %6.2f %6.2f %6.2f %4d" % [
			key, String(d["cat"]), float(d["pre_peak_db"]), float(d["pre_rms_db"]),
			float(d["peak_db"]), rms, float(d["gain_db"]), int(d["clip"])])
	if not keys.is_empty():
		print("Äänekkyyshajonta: %.2f dB (%d ääntä)" % [hi - lo, keys.size()])


# --- Synteesi ---

func _synth_all() -> void:
	# Musiikki syntetisoidaan ENSIN, ja päävalikon biisi toimitetaan heti
	# omanaan — näin valikko soi lähes välittömästi eikä vasta sitten kun
	# kaikki tehosteet on ehditty laskea taustasäikeessä.
	# Menu: tumma mutta eteenpäin liikkuva MOBA-komentokeskus (Am-F-C-G).
	call_deferred("_music_ready", {"menu": _single_layer(MusicBank.make_track(
		[110.0, 87.31, 130.81, 98.0], [true, false, false, false], 2.25, "tri", 0.28, 0.94))})

	# Ottelun ensimmäinen biisi on rauhallinen linjapeti; taistelukerrokset
	# tulevat heti perään, jotta nousu taisteluun ei jää odottamaan synteesiä.
	var primary := {}
	# Rauhallinen laning-peti (Am-C-F-G): patja + kevyt pulssi, ei leadia.
	primary["lane_calm"] = _layered(MusicBank.make_calm_bed(
		[110.0, 130.81, 87.31, 98.0], 2.6, 0.90))
	# Draft/lobby: selkeä taktinen pulssi (C-G-Am-F).
	primary["lobby"] = _single_layer(MusicBank.make_track(
		[130.81, 98.0, 110.0, 87.31], [false, false, true, false], 1.82, "square", 0.62, 0.96))
	# Taistelu 1: ajava ja jännittävä (Em-C-G-D).
	primary["battle"] = _layered(MusicBank.make_layers(
		[82.41, 130.81, 98.0, 146.83], [true, false, false, false], 1.6, "saw", 1.0, 8100))
	call_deferred("_music_ready", primary)

	# Vaihteluversiot viimeisenä (poolit arpovat näistä).
	var variety := {}
	# Menu 2: hieman kirkkaampi strateginen vaihtoehto (G-Bb-F-C).
	variety["menu2"] = _single_layer(MusicBank.make_track(
		[98.0, 116.54, 87.31, 130.81], [false, true, false, false], 2.35, "tri", 0.24, 0.92))
	# Lobby 2: napakampi odotus (Bb-F-C-G).
	variety["lobby2"] = _single_layer(MusicBank.make_track(
		[116.54, 87.31, 130.81, 98.0], [false, false, false, true], 1.72, "square", 0.68, 0.96))
	# Taistelu 2: vaihtelua (Am-F-G-Em).
	variety["battle2"] = _layered(MusicBank.make_layers(
		[110.0, 87.31, 98.0, 82.41], [true, false, false, true], 1.6, "saw", 1.0, 8200))
	# Taistelu 3: kiivas (Dm-G-Em-A).
	variety["battle3"] = _layered(MusicBank.make_layers(
		[73.42, 98.0, 82.41, 110.0], [true, false, true, false], 1.5, "saw", 1.0, 8300))
	# Taistelu 4: raju huipennus (F-Bb-G-D) — nexus-avauksen loppupeli.
	variety["battle4"] = _layered(MusicBank.make_layers(
		[87.31, 116.54, 98.0, 73.42], [false, false, false, false], 1.4, "saw", 1.0, 8400))
	call_deferred("_music_ready", variety)

	# Tehosteet erissä: perus/UI ensin, sitten MOBA-maailma, sankarit ja lopuksi
	# uudet järjestelmät + musiikkicuet.
	_deliver_sfx(SoundBank.core_batch())
	_deliver_sfx(SoundBank.world_batch())
	_deliver_sfx(SoundBank.hero_batch())
	_deliver_sfx(SoundBank.extra_batch())
	_deliver_sfx(SoundBank.cue_batch())


## Yksikerroksinen biisi (valikot): pelkkä "bed".
func _single_layer(samples: PackedFloat32Array) -> Dictionary:
	var report: Dictionary = AudioDsp.normalize(samples, MusicBank.MUSIC_RMS, 0.0)
	return {MusicBank.BED: AudioDsp.to_wav(report["buf"], true)}


## Kerroksittainen biisi: jokainen kerros normalisoidaan omaan tavoitteeseensa,
## jotta kerroksen mukaantulo ei koskaan hyppää voimakkuudessa.
func _layered(layers: Dictionary) -> Dictionary:
	var out := {}
	for layer_name in layers:
		var name: String = String(layer_name)
		var target: float = float(MusicBank.LAYER_RMS.get(name, MusicBank.MUSIC_RMS))
		var report: Dictionary = AudioDsp.normalize(layers[layer_name], target, 0.0)
		out[name] = AudioDsp.to_wav(report["buf"], true)
	return out


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


func _sfx_ready(streams: Dictionary, stats: Dictionary) -> void:
	for key in streams:
		_streams[key] = streams[key]
		_loudness[key] = stats[key]
		if _pending_ambient.has(key):
			var request: Array = _pending_ambient[key]
			_pending_ambient.erase(key)
			play(String(key), float(request[0]), float(request[1]), request[2])


## Normalisoi erän jokaisen puskurin kategoriansa tavoitteeseen, muuntaa
## WAV-muotoon ja toimittaa pääsäikeelle mittaustietojen kanssa.
func _deliver_sfx(sounds: Dictionary) -> void:
	if sounds.is_empty():
		return
	var result := {}
	var stats := {}
	for key in sounds:
		var name: String = String(key)
		var def: Dictionary = _defs.get(name, {})
		if def.is_empty():
			def = SoundDefs.fallback()
		var raw: PackedFloat32Array = sounds[key]
		var report: Dictionary = AudioDsp.normalize(
			raw, float(def["rms"]), float(def["gain"]))
		result[name] = AudioDsp.to_wav(report["buf"], false)
		report.erase("buf")
		report["cat"] = String(def["cat"])
		stats[name] = report
	call_deferred("_sfx_ready", result, stats)
