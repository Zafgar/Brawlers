extends Node
## Äänijärjestelmä (autoload: AudioMgr). Kaikki äänet syntetisoidaan
## proseduraalisesti käynnistyksessä taustasäikeessä — ei äänitiedostoja.
## play("nimi") toimii heti; jos synteesi on kesken, ääni jää vain väliin.

const RATE := 22050
const POOL_SIZE := 12

var _streams := {}
var _players: Array = []
var _music_player: AudioStreamPlayer = null
var _music_enabled := true
var _music_stream: AudioStreamWAV = null
var _thread: Thread = null
var _warned := {}


func _ready() -> void:
	_make_bus("SFX")
	_make_bus("Music")
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -14.0
	add_child(_music_player)

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


# --- Julkinen rajapinta ---

func play(sound_name: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	if not _streams.has(sound_name):
		if not _streams.is_empty() and not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Tuntematon ääni: %s" % sound_name)
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[0]
	player.stream = _streams[sound_name]
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.volume_db = volume_db
	player.play()


func set_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(v, 0.001, 1.0)))


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if _music_player == null:
		return
	if enabled and _music_stream != null and not _music_player.playing:
		_music_player.play()
	elif not enabled and _music_player.playing:
		_music_player.stop()


# --- Synteesi ---

func _synth_all() -> void:
	var sounds := {}
	sounds["ui_move"] = _tone(0.05, 660.0, 880.0, "sine", 0.005, 0.03, 0.35)
	sounds["ui_ok"] = _seq([[0.06, 520.0, 520.0, "sine"], [0.09, 780.0, 780.0, "sine"]], 0.5)
	sounds["ui_back"] = _tone(0.1, 520.0, 340.0, "sine", 0.005, 0.06, 0.4)
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
		_tone(0.08, 220.0, 140.0, "tri", 0.002, 0.05, 0.5),
		_noise(0.06, 0.25, 0.4), 0.0)
	sounds["swing"] = _noise(0.12, 0.3, 0.75)
	sounds["slam"] = _mix2(
		_tone(0.25, 90.0, 50.0, "sine", 0.005, 0.18, 0.7),
		_noise(0.12, 0.35, 0.3), 0.0)
	# Raskas maanjäristys: syvä basso + pitkä kohina-jyrinä
	sounds["quake"] = _mix2(_mix2(
		_tone(0.5, 70.0, 38.0, "sine", 0.005, 0.35, 0.8),
		_tone(0.4, 120.0, 60.0, "tri", 0.005, 0.3, 0.3), 0.0),
		_noise(0.45, 0.4, 0.2), 0.02)
	# Kilpi ylös: napakka metallinen kilahdus
	sounds["guard_up"] = _mix2(
		_tone(0.18, 520.0, 780.0, "tri", 0.002, 0.12, 0.35),
		_tone(0.16, 880.0, 1100.0, "sine", 0.005, 0.1, 0.2), 0.02)
	# Kupoli nousee: matala nouseva humaus
	sounds["dome_up"] = _mix2(
		_tone(0.6, 110.0, 220.0, "sine", 0.03, 0.4, 0.4),
		_tone(0.6, 165.0, 330.0, "tri", 0.05, 0.4, 0.2), 0.05)
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
	sounds["dash"] = _noise(0.1, 0.28, 0.7)
	sounds["blink"] = _mix2(
		_tone(0.12, 880.0, 1760.0, "sine", 0.005, 0.07, 0.35),
		_tone(0.08, 1760.0, 880.0, "sine", 0.01, 0.06, 0.2), 0.1)
	# Valoterä: terävä nopea sähähdys
	sounds["blade"] = _mix2(
		_tone(0.1, 1700.0, 500.0, "saw", 0.002, 0.06, 0.32),
		_noise(0.05, 0.16, 0.85), 0.0)
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
		_tone(0.3, 300.0, 80.0, "sine", 0.005, 0.22, 0.6),
		_tone(0.15, 990.0, 1320.0, "sine", 0.02, 0.1, 0.2), 0.05)
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
	sounds["score"] = _tone(0.08, 1100.0, 1100.0, "sine", 0.003, 0.06, 0.3)

	var result := {}
	for key in sounds:
		result[key] = _to_wav(sounds[key], false)
	var music := _to_wav(_synth_music(), true)
	call_deferred("_synth_done", result, music)


func _synth_done(streams: Dictionary, music: AudioStreamWAV) -> void:
	_streams = streams
	_music_stream = music
	_music_player.stream = _music_stream
	if _music_enabled:
		_music_player.play()


## Kevyt taustaluuppi: bassolinja + arpeggio neljällä soinnulla.
func _synth_music() -> PackedFloat32Array:
	var bar := 2.4
	var roots := [110.0, 87.31, 65.41, 98.0]  # A2, F2, C2, G2
	var minor := [true, false, false, false]
	var total := bar * roots.size()
	var out := PackedFloat32Array()
	out.resize(int(total * RATE))
	for i in range(out.size()):
		out[i] = 0.0
	for bar_i in range(roots.size()):
		var root: float = roots[bar_i]
		var bass := _tone(bar, root, root, "sine", 0.05, 0.4, 0.16)
		out = _mix_at(out, bass, bar_i * bar)
		var third := 2.4 if minor[bar_i] else 2.5
		var steps := [2.0, third, 3.0, 4.0, 3.0, third]
		for step_i in range(steps.size()):
			var note := _tone(0.32, root * steps[step_i], root * steps[step_i],
				"tri", 0.02, 0.24, 0.07)
			out = _mix_at(out, note, bar_i * bar + step_i * 0.4)
	return out


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
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 1000.0 + gain * 777.0)
	for i in range(n):
		var x := rng.randf_range(-1.0, 1.0)
		y += lowpass * (x - y)
		var env := 1.0 - float(i) / n
		out[i] = y * env * gain
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
