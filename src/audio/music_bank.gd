class_name MusicBank
extends RefCounted
## Musiikin generointi. Biisit ovat luupattavia, ja jokainen niistä koostuu
## nimetyistä KERROKSISTA (bed/pulse/lead/tension), jotka ovat täsmälleen saman
## mittaisia ja siten aina synkassa keskenään. AudioMgr ristihäivyttää kerrosten
## voimakkuuksia intensiteetin mukaan; valikkobiiseillä on vain "bed".

const BED := "bed"
const PULSE := "pulse"
const LEAD := "lead"
const TENSION := "tension"
const LAYERS := [BED, PULSE, LEAD, TENSION]

## Musiikki normalisoidaan omaan tavoitteeseensa (kerrosten summa jää tämän
## alle, koska kerrokset lasketaan yhteen vasta soitettaessa).
const MUSIC_RMS := -20.0
const LAYER_RMS := {
	BED: -22.0,
	PULSE: -21.0,
	LEAD: -23.0,
	TENSION: -25.0,
}


## Yksikerroksinen biisi (valikot, lobby): basso + arpeggio + valinnainen rytmi.
static func make_track(roots: Array, minor: Array, bar: float, lead_wave: String,
		kick_strength: float, gain: float) -> PackedFloat32Array:
	var total: float = bar * float(roots.size())
	var out := AudioDsp.buffer(total)
	for bar_i in range(roots.size()):
		var root: float = float(roots[bar_i])
		var bass := AudioDsp.tone(bar, root, root, "sine", 0.05, bar * 0.15, 0.16 * gain)
		out = AudioDsp.mix(out, bass, bar_i * bar)
		var third: float = 2.4 if bool(minor[bar_i]) else 2.5
		# Kierrätä arpeggio-kuviota tahdeittain: sama konsonoiva sävelvarasto,
		# vaihteleva kontuuri -> ei identtistä figuuria joka tahdissa.
		var patterns: Array = [
			[2.0, third, 3.0, 4.0, 3.0, third],
			[2.0, 3.0, third, 4.0, third, 2.0],
			[4.0, 3.0, third, 2.0, third, 3.0],
		]
		var steps: Array = patterns[bar_i % patterns.size()]
		var note_len: float = bar / float(steps.size())
		for step_i in range(steps.size()):
			var freq: float = root * float(steps[step_i])
			var note := AudioDsp.tone(note_len * 0.85, freq, freq, lead_wave,
				0.01, note_len * 0.4, 0.06 * gain)
			out = AudioDsp.mix(out, note, bar_i * bar + step_i * note_len)
		if kick_strength > 0.0:
			for beat in range(4):
				out = AudioDsp.mix(out, kick(kick_strength * gain),
					bar_i * bar + beat * (bar / 4.0))
	return out


## Kerroksittainen taistelubiisi. Kaikki neljä kerrosta ovat NÄYTETARKASTI
## saman mittaisia ja luupattuja, joten ne pysyvät ikuisesti synkassa ja
## AudioMgr voi ristihäivyttää niitä vapaasti intensiteetin mukaan.
##   bed      basso + patja (soi aina)
##   pulse    potku, hattu ja offbeat-näppäys  (intensiteetti ~0.16 ->)
##   lead     kiertävä arpeggio                (intensiteetti ~0.38 ->)
##   tension  matala drone + tahdin riser      (intensiteetti ~0.58 ->)
static func make_layers(roots: Array, minor: Array, bar: float, lead_wave: String,
		gain: float, seed_base: int) -> Dictionary:
	var total: float = bar * float(roots.size())
	var bed := AudioDsp.buffer(total)
	var pulse := AudioDsp.buffer(total)
	var lead := AudioDsp.buffer(total)
	var tension := AudioDsp.buffer(total)
	for bar_i in range(roots.size()):
		var root: float = float(roots[bar_i])
		var at: float = float(bar_i) * bar
		var third: float = 2.4 if bool(minor[bar_i]) else 2.5

		# BED: perusbasso + hitaasti hengittävä patja (oktaavi + kvintti).
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar, root, root, "sine",
			0.05, bar * 0.15, 0.16 * gain), at)
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar * 0.98, root * 2.0, root * 2.0,
			"tri", bar * 0.25, bar * 0.35, 0.050 * gain), at)
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar * 0.98, root * 3.0, root * 3.0,
			"tri", bar * 0.30, bar * 0.35, 0.034 * gain), at)

		# PULSE: potku joka iskulle, offbeat-hattu ja parittomien iskujen näppäys.
		for beat in range(4):
			var beat_at: float = at + float(beat) * (bar / 4.0)
			pulse = AudioDsp.mix(pulse, kick(gain), beat_at)
			pulse = AudioDsp.mix(pulse, AudioDsp.noise_burst(0.045, 0.10 * gain,
				0.88, 2.8, seed_base + beat * 3 + bar_i), beat_at + bar / 8.0)
			if beat % 2 == 1:
				pulse = AudioDsp.mix(pulse, AudioDsp.tone(bar / 8.0, root * 2.0,
					root * 2.0, "square", 0.002, bar / 16.0, 0.05 * gain), beat_at)

		# LEAD: sama kiertävä arpeggio-kuvio kuin yksikerroksisissa biiseissä.
		var patterns: Array = [
			[2.0, third, 3.0, 4.0, 3.0, third],
			[2.0, 3.0, third, 4.0, third, 2.0],
			[4.0, 3.0, third, 2.0, third, 3.0],
		]
		var steps: Array = patterns[bar_i % patterns.size()]
		var note_len: float = bar / float(steps.size())
		for step_i in range(steps.size()):
			var freq: float = root * float(steps[step_i])
			lead = AudioDsp.mix(lead, AudioDsp.tone(note_len * 0.85, freq, freq,
				lead_wave, 0.01, note_len * 0.4, 0.075 * gain),
				at + float(step_i) * note_len)

		# TENSION: oktaavia alempi drone + tahdin loppupuolen nouseva riser.
		tension = AudioDsp.mix(tension, AudioDsp.tone(bar, root * 0.5, root * 0.5,
			"saw", bar * 0.30, bar * 0.30, 0.085 * gain), at)
		tension = AudioDsp.mix(tension, AudioDsp.whoosh(bar * 0.55, 0.14 * gain,
			300.0, 3200.0, 0.8, seed_base + 700 + bar_i), at + bar * 0.45)

	# Näytetarkka pituus: yhdenkin näytteen ero ajaisi luupit vähitellen erilleen.
	var n: int = int(total * float(AudioDsp.RATE))
	bed.resize(n)
	pulse.resize(n)
	lead.resize(n)
	tension.resize(n)
	return {BED: bed, PULSE: pulse, LEAD: lead, TENSION: tension}


## Rauhallinen linjapeti ottelun alkuun: pelkkä patja + hidas pulssi, ei leadia.
## Musiikki nousee tästä taistelubiisiin kun intensiteetti pysyy korkealla.
static func make_calm_bed(roots: Array, bar: float, gain: float) -> Dictionary:
	var total: float = bar * float(roots.size())
	var bed := AudioDsp.buffer(total)
	var pulse := AudioDsp.buffer(total)
	for bar_i in range(roots.size()):
		var root: float = float(roots[bar_i])
		var at: float = float(bar_i) * bar
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar, root, root, "sine",
			bar * 0.20, bar * 0.30, 0.15 * gain), at)
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar * 0.96, root * 2.0, root * 2.0,
			"tri", bar * 0.35, bar * 0.40, 0.045 * gain), at)
		bed = AudioDsp.mix(bed, AudioDsp.tone(bar * 0.92, root * 3.0, root * 3.0,
			"sine", bar * 0.40, bar * 0.40, 0.028 * gain), at)
		# Kaksi pehmeää potkua per tahti: rytmi on olemassa mutta ei työnnä.
		pulse = AudioDsp.mix(pulse, kick(gain * 0.45), at)
		pulse = AudioDsp.mix(pulse, kick(gain * 0.32), at + bar * 0.5)
	var n: int = int(total * float(AudioDsp.RATE))
	bed.resize(n)
	pulse.resize(n)
	return {BED: bed, PULSE: pulse}


## Lyhyt rumpupotku (basso + naks).
static func kick(strength: float) -> PackedFloat32Array:
	return AudioDsp.mix(
		AudioDsp.tone(0.12, 135.0, 45.0, "sine", 0.002, 0.09, 0.42 * strength),
		AudioDsp.noise_burst(0.035, 0.22 * strength, 0.5, 1.0, 4201), 0.0)
