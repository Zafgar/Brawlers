class_name AudioDsp
extends RefCounted
## Jaetut DSP-rakennuspalikat proseduraaliselle äänisynteesille.
##
## Kaikki funktiot ovat staattisia ja TÄYSIN DETERMINISTISIÄ: sama kutsu tuottaa
## joka ajolla tavu tavulta saman puskurin. Kohina käyttää omaa LCG-generaattoria
## eikä RandomNumberGeneratoria, jotta tulos on toistettavissa myös pelin
## ulkopuolella (scratchpad/audio_probe.py mittaa samat puskurit).
##
## Yksi äänikieli koko pelille rakennetaan näistä palikoista:
##   fyysinen isku   = sub_thump + crack + noise_burst
##   taika/kyky      = bell + shimmer + suodatettu kohinahäntä
##   tekniikka/UI    = puhtaat sine/square-blipit, kuiva väylä
##   luonto/viidakko = pehmeä puu/lehtikohina, loivat transientit
##   rakenteet       = metal_ring + raskas matala häntä

const RATE := 44100
const CEILING_DB := -1.0        # normalisoinnin turvakatto (huippu jää tähän)
const LOUD_WINDOW := 0.2        # s: lyhyen aikavälin äänekkyysikkuna (RMS-huippu)
const LCG_A := 1103515245
const LCG_C := 12345
const LCG_M := 0x7FFFFFFF
const LCG_HALF := 1073741823.5


# --- Perusapurit ---

static func buffer(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(int(dur * RATE), 1))
	out.fill(0.0)
	return out


## Pehmeä kylläisyys ilman tanh()-riippuvuutta (sama kaava Python-peilissä).
static func soft(x: float) -> float:
	var v: float = clampf(x, -8.0, 8.0)
	var e: float = exp(2.0 * v)
	return (e - 1.0) / (e + 1.0)


# --- Verhokäyrät ---

## ADSR näytteinä. attack/decay/release sekunteina, sustain 0..1 tasona.
static func env_adsr(n: int, attack: float, decay: float, sustain: float,
		release: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(n, 1))
	var a: int = maxi(int(attack * RATE), 1)
	var d: int = maxi(int(decay * RATE), 1)
	var r: int = maxi(int(release * RATE), 1)
	var total: int = out.size()
	var rel_start: int = maxi(total - r, 0)
	for i in range(total):
		var v := 0.0
		if i < a:
			v = float(i) / float(a)
		elif i < a + d:
			v = lerpf(1.0, sustain, float(i - a) / float(d))
		else:
			v = sustain
		if i >= rel_start:
			v *= 1.0 - float(i - rel_start) / float(maxi(r, 1))
		out[i] = maxf(v, 0.0)
	return out


# --- Oskillaattorit ---

## Perusääni liukuvalla taajuudella. Sama rajapinta kuin vanhassa _tone():ssa,
## joten olemassa olevat reseptit siirtyivät sellaisenaan.
static func tone(dur: float, f0: float, f1: float, wave: String,
		attack: float, release: float, gain: float) -> PackedFloat32Array:
	var n: int = maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerpf(f0, f1, t)
		phase += freq / float(RATE)
		var p: float = fmod(phase, 1.0)
		var s := 0.0
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
		var time_s: float = float(i) / float(RATE)
		if time_s < attack:
			env = time_s / maxf(attack, 0.0001)
		var tail: float = dur - time_s
		if tail < release:
			env = minf(env, tail / maxf(release, 0.0001))
		out[i] = s * env * gain
	return out


## Determinististä kohinaa: yksinapainen alipäästö + DC-esto + laskeva verho.
## curve > 1 = nopeampi vaimeneminen (terävä transientti), curve < 1 = pidempi häntä.
static func noise_burst(dur: float, gain: float, lowpass: float, curve: float,
		seed_i: int) -> PackedFloat32Array:
	var n: int = maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var st: int = (absi(seed_i) * 2654435761 + 97) & LCG_M
	var y := 0.0
	var hp := 0.0
	var prev := 0.0
	var atk_n: int = maxi(int(0.003 * RATE), 1)
	# Rajataajuuden kerroin skaalataan näytetaajuuteen, jotta kohinan sointi ei
	# muutu jos RATE joskus vaihtuu.
	var lp: float = clampf(lowpass * (22050.0 / float(RATE)), 0.0, 1.0)
	for i in range(n):
		st = (st * LCG_A + LCG_C) & LCG_M
		var x: float = float(st) / LCG_HALF - 1.0
		y += lp * (x - y)
		hp = 0.996 * (hp + y - prev)
		prev = y
		var env: float = pow(1.0 - float(i) / float(n), curve)
		if i < atk_n:
			env *= float(i) / float(atk_n)
		out[i] = hp * env * gain
	return out


## Kello: harmonisesti hieman epäpuhtaat osasävelet, eksponentiaalinen sammuminen.
## Taika-, kyky- ja palkintoäänten runko.
static func bell(freq: float, decay: float, gain: float) -> PackedFloat32Array:
	var ratios: Array = [1.0, 2.0, 2.76, 5.40, 8.93]
	var amps: Array = [1.0, 0.42, 0.26, 0.15, 0.08]
	var decs: Array = [1.0, 0.80, 0.62, 0.42, 0.28]
	var n: int = maxi(int(decay * 1.05 * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	var atk_n: int = maxi(int(0.002 * RATE), 1)
	for k in range(ratios.size()):
		var f: float = freq * float(ratios[k])
		if f > float(RATE) * 0.45:
			continue
		var amp: float = float(amps[k]) * gain
		var d: float = maxf(decay * float(decs[k]), 0.02)
		var w: float = TAU * f / float(RATE)
		var mul: float = exp(-4.6 / (d * float(RATE)))
		var env := 1.0
		for i in range(n):
			var a: float = amp * env
			if i < atk_n:
				a *= float(i) / float(atk_n)
			out[i] += a * sin(w * float(i))
			env *= mul
	return out


## Epäharmoninen metallisointi: tornit, kilvet, kristallit, mekaniikka.
static func metal_ring(freq: float, decay: float, gain: float) -> PackedFloat32Array:
	var ratios: Array = [1.0, 1.47, 2.09, 2.83, 4.17, 5.43]
	var amps: Array = [1.0, 0.66, 0.48, 0.34, 0.20, 0.12]
	var decs: Array = [1.0, 0.88, 0.72, 0.58, 0.40, 0.28]
	var n: int = maxi(int(decay * 1.05 * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	var atk_n: int = maxi(int(0.0015 * RATE), 1)
	for k in range(ratios.size()):
		var f: float = freq * float(ratios[k])
		if f > float(RATE) * 0.45:
			continue
		var amp: float = float(amps[k]) * gain
		var d: float = maxf(decay * float(decs[k]), 0.02)
		var w: float = TAU * f / float(RATE)
		var mul: float = exp(-4.6 / (d * float(RATE)))
		var env := 1.0
		for i in range(n):
			var a: float = amp * env
			if i < atk_n:
				a *= float(i) / float(atk_n)
			out[i] += a * sin(w * float(i))
			env *= mul
	return out


## Tömähdys: puu/kivi-runko. Nopeasti putoava sävelkorkeus + eksponentiaalinen verho.
static func thud(freq: float, decay: float, gain: float) -> PackedFloat32Array:
	var n: int = maxi(int(decay * 1.1 * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var mul: float = exp(-4.6 / (maxf(decay, 0.02) * float(RATE)))
	var env := 1.0
	var atk_n: int = maxi(int(0.0012 * RATE), 1)
	for i in range(n):
		var ts: float = float(i) / float(RATE)
		var f: float = freq * (0.34 + 0.66 * exp(-ts * 22.0))
		phase += f / float(RATE)
		var a: float = env
		if i < atk_n:
			a *= float(i) / float(atk_n)
		out[i] = sin(phase * TAU) * a * gain
		env *= mul
	return out


## Subisku: matala rungon paine (osumat, räjähdykset, rakennusten kaatuminen).
static func sub_thump(freq: float, decay: float, gain: float) -> PackedFloat32Array:
	var n: int = maxi(int(decay * 1.15 * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var mul: float = exp(-4.6 / (maxf(decay, 0.03) * float(RATE)))
	var env := 1.0
	var atk_n: int = maxi(int(0.004 * RATE), 1)
	for i in range(n):
		var ts: float = float(i) / float(RATE)
		var f: float = freq * (0.52 + 0.48 * exp(-ts * 9.0))
		phase += f / float(RATE)
		var a: float = env
		if i < atk_n:
			a *= float(i) / float(atk_n)
		out[i] = sin(phase * TAU) * a * gain
		env *= mul
	return out


## Pyyhkäisy: kaistanpäästösuodatettu kohina, jonka keskitaajuus liukuu.
## Heitot, dashit, lentävät ammukset, tuulenpuuskat.
static func whoosh(dur: float, gain: float, f_start: float, f_end: float,
		q: float, seed_i: int) -> PackedFloat32Array:
	var n: int = maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var st: int = (absi(seed_i) * 2654435761 + 313) & LCG_M
	var low := 0.0
	var band := 0.0
	var damp: float = clampf(1.0 / maxf(q, 0.4), 0.02, 1.8)
	for i in range(n):
		st = (st * LCG_A + LCG_C) & LCG_M
		var x: float = float(st) / LCG_HALF - 1.0
		var t: float = float(i) / float(n)
		var fc: float = lerpf(f_start, f_end, t)
		var f: float = clampf(2.0 * sin(PI * fc / float(RATE)), 0.0, 0.98)
		var high: float = x - low - damp * band
		band += f * high
		low += f * band
		out[i] = band * sin(PI * t) * gain
	return out


## Kimallus: korkeiden osasävelten porrastettu parvi. Taikakykyjen häntä.
static func shimmer(dur: float, base: float, gain: float, seed_i: int) -> PackedFloat32Array:
	var ratios: Array = [1.0, 1.5, 2.0, 2.67, 3.5, 4.5]
	var n: int = maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	var st: int = (absi(seed_i) * 2654435761 + 7717) & LCG_M
	for k in range(ratios.size()):
		st = (st * LCG_A + LCG_C) & LCG_M
		var jitter: float = float(st) / LCG_HALF - 1.0
		var f: float = base * float(ratios[k]) * (1.0 + jitter * 0.012)
		if f > float(RATE) * 0.45:
			continue
		var onset: int = int(float(k) / float(ratios.size()) * float(n) * 0.35)
		var d: float = maxf(dur * (0.9 - 0.1 * float(k)), 0.04)
		var mul: float = exp(-4.6 / (d * float(RATE)))
		var w: float = TAU * f / float(RATE)
		var lfo: float = TAU * (4.5 + float(k) * 1.3) / float(RATE)
		var amp: float = gain / (1.0 + float(k) * 0.75)
		var env := 1.0
		for i in range(onset, n):
			var trem: float = 0.82 + 0.18 * sin(lfo * float(i))
			out[i] += amp * env * trem * sin(w * float(i - onset))
			env *= mul
	return out


## Halkeama/naksahdus: erittäin lyhyt resonoiva kohinatransientti.
## Puun rusahdus, kiven murtuminen, sähkön rätinä.
static func crack(dur: float, gain: float, freq: float, seed_i: int) -> PackedFloat32Array:
	var n: int = maxi(int(dur * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var st: int = (absi(seed_i) * 2654435761 + 5051) & LCG_M
	var low := 0.0
	var band := 0.0
	var f: float = clampf(2.0 * sin(PI * clampf(freq, 40.0, float(RATE) * 0.45) / float(RATE)),
		0.0, 0.98)
	var damp := 0.22
	for i in range(n):
		st = (st * LCG_A + LCG_C) & LCG_M
		var x: float = float(st) / LCG_HALF - 1.0
		var high: float = x - low - damp * band
		band += f * high
		low += f * band
		var env: float = pow(1.0 - float(i) / float(n), 3.4)
		out[i] = band * env * gain
	return out


# --- Suodattimet ja muokkaus ---

static func lowpass(buf: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var a: float = clampf(1.0 - exp(-TAU * maxf(cutoff_hz, 10.0) / float(RATE)), 0.0, 1.0)
	var y := 0.0
	for i in range(buf.size()):
		y += a * (buf[i] - y)
		buf[i] = y
	return buf


static func highpass(buf: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var rc: float = exp(-TAU * maxf(cutoff_hz, 5.0) / float(RATE))
	var y := 0.0
	var prev := 0.0
	for i in range(buf.size()):
		var x: float = buf[i]
		y = rc * (y + x - prev)
		prev = x
		buf[i] = y
	return buf


## Pehmeä saturaatio: lisää harmonisia ja tiivistää transientit ilman kovaa klippiä.
static func saturate(buf: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var d: float = maxf(drive, 0.01)
	var comp: float = 1.0 / soft(d)
	for i in range(buf.size()):
		buf[i] = soft(buf[i] * d) * comp
	return buf


static func scale_buf(buf: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in range(buf.size()):
		buf[i] *= g
	return buf


## Lyhyt stereolevitys (Haas): oikea kanava viivästyy muutaman millisekunnin ja
## saa kevyen alipäästön. Huippu ei kasva, joten normalisointi tehdään ennen tätä.
static func widen(buf: PackedFloat32Array, ms: float, tilt_hz: float) -> Array:
	var left := buf.duplicate()
	var right := PackedFloat32Array()
	var n: int = buf.size()
	right.resize(n)
	var delay: int = clampi(int(ms * 0.001 * RATE), 1, maxi(n - 1, 1))
	for i in range(n):
		if i >= delay:
			right[i] = buf[i - delay] * 0.92
		else:
			right[i] = 0.0
	right = lowpass(right, tilt_hz)
	return [left, right]


static func mix(base: PackedFloat32Array, add: PackedFloat32Array,
		offset_sec: float) -> PackedFloat32Array:
	var offset: int = maxi(int(offset_sec * RATE), 0)
	var needed: int = offset + add.size()
	if needed > base.size():
		var old: int = base.size()
		base.resize(needed)
		for i in range(old, needed):
			base[i] = 0.0
	for i in range(add.size()):
		base[offset + i] += add[i]
	return base


## Soittaa palat peräkkäin (fanfaarit, arpeggiot).
static func seq(notes: Array, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		var item: Array = note
		var dur: float = float(item[0])
		var piece := tone(dur, float(item[1]), float(item[2]), String(item[3]),
			0.005, minf(0.08, dur * 0.5), gain)
		var base: int = out.size()
		out.resize(base + piece.size())
		for i in range(piece.size()):
			out[base + i] = piece[i]
	return out


# --- Mittaus ja normalisointi ---

static func peak_of(buf: PackedFloat32Array) -> float:
	var p := 0.0
	for i in range(buf.size()):
		var a: float = absf(buf[i])
		if a > p:
			p = a
	return p


static func dc_of(buf: PackedFloat32Array) -> float:
	var n: int = buf.size()
	if n == 0:
		return 0.0
	var acc := 0.0
	for i in range(n):
		acc += buf[i]
	return acc / float(n)


## Lyhyen aikavälin äänekkyys: suurin RMS 200 ms liukuvassa ikkunassa.
## Tämä vastaa koettua voimakkuutta paremmin kuin koko puskurin RMS, koska
## 60 ms napsautus ja 2.8 s ympäristökerros eivät muuten ole vertailukelpoisia.
static func window_rms(buf: PackedFloat32Array) -> float:
	var n: int = buf.size()
	if n == 0:
		return 0.0
	var w: int = mini(maxi(int(LOUD_WINDOW * RATE), 1), n)
	var acc := 0.0
	for i in range(w):
		acc += buf[i] * buf[i]
	var best: float = acc
	for i in range(w, n):
		acc += buf[i] * buf[i] - buf[i - w] * buf[i - w]
		if acc > best:
			best = acc
	return sqrt(maxf(best, 0.0) / float(w))


static func measure(buf: PackedFloat32Array) -> Dictionary:
	var pk: float = peak_of(buf)
	var rms: float = window_rms(buf)
	var clip := 0
	for i in range(buf.size()):
		if absf(buf[i]) >= 1.0:
			clip += 1
	return {
		"peak_db": linear_to_db(maxf(pk, 0.0000001)),
		"rms_db": linear_to_db(maxf(rms, 0.0000001)),
		"dc": dc_of(buf),
		"clip": clip,
		"dur": float(buf.size()) / float(RATE),
	}


## Yhtenäinen äänekkyys: poistaa DC:n, nostaa/laskee puskurin kategorian
## tavoite-RMS:ään ja rajoittaa huipun pehmeästi kattoon (-1 dBFS).
## Palauttaa mitatut arvot ennen ja jälkeen raportointia varten sekä käsitellyn
## puskurin avaimella "buf" (PackedFloat32Array välittyy arvona, ei viitteenä).
static func normalize(buf: PackedFloat32Array, target_rms_db: float,
		trim_db: float) -> Dictionary:
	var n: int = buf.size()
	if n == 0:
		return {"buf": buf, "pre_peak_db": -120.0, "pre_rms_db": -120.0,
			"peak_db": -120.0, "rms_db": -120.0, "gain_db": 0.0, "dc": 0.0,
			"clip": 0, "dur": 0.0, "limited": false}
	var dc: float = dc_of(buf)
	if absf(dc) > 0.000001:
		for i in range(n):
			buf[i] -= dc
	var pre_peak: float = peak_of(buf)
	var pre_rms: float = window_rms(buf)
	var pre_rms_db: float = linear_to_db(maxf(pre_rms, 0.0000001))
	var pre_peak_db: float = linear_to_db(maxf(pre_peak, 0.0000001))
	# Rajattu korjaus: lähes tyhjä puskuri ei saa räjähtää +60 dB:llä.
	var gain_db: float = clampf(target_rms_db - pre_rms_db, -30.0, 30.0) + trim_db
	var g: float = db_to_linear(gain_db)
	var ceil_lin: float = db_to_linear(CEILING_DB)
	var limited: bool = pre_peak * g > ceil_lin
	for i in range(n):
		var v: float = buf[i] * g
		if limited:
			v = ceil_lin * soft(v / ceil_lin)
		buf[i] = v
	var post: Dictionary = measure(buf)
	return {
		"buf": buf,
		"pre_peak_db": pre_peak_db,
		"pre_rms_db": pre_rms_db,
		"peak_db": float(post["peak_db"]),
		"rms_db": float(post["rms_db"]),
		"gain_db": gain_db,
		"dc": float(post["dc"]),
		"clip": int(post["clip"]),
		"dur": float(post["dur"]),
		"limited": limited,
	}


# --- WAV-muunnos ---

static func to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
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


static func to_wav_stereo(left: PackedFloat32Array, right: PackedFloat32Array,
		looped: bool) -> AudioStreamWAV:
	var n: int = mini(left.size(), right.size())
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in range(n):
		var l: int = int(clampf(left[i], -1.0, 1.0) * 32000.0)
		var r: int = int(clampf(right[i], -1.0, 1.0) * 32000.0)
		bytes[i * 4] = l & 0xff
		bytes[i * 4 + 1] = (l >> 8) & 0xff
		bytes[i * 4 + 2] = r & 0xff
		bytes[i * 4 + 3] = (r >> 8) & 0xff
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
