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


## Lyhyt rumpupotku (basso + naks).
static func kick(strength: float) -> PackedFloat32Array:
	return AudioDsp.mix(
		AudioDsp.tone(0.12, 135.0, 45.0, "sine", 0.002, 0.09, 0.42 * strength),
		AudioDsp.noise_burst(0.035, 0.22 * strength, 0.5, 1.0, 4201), 0.0)
