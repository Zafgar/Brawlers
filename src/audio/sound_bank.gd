class_name SoundBank
extends RefCounted
## Kaikkien tehosteiden reseptit yhdessä paikassa, kirjoitettuna AudioDsp:n
## jaetuilla palikoilla. Jokainen resepti on YKSI lauseke, joten sen voi
## poimia ja mitata myös pelin ulkopuolelta (scratchpad/audio_probe.py).
##
## Erät toimitetaan siinä järjestyksessä kuin peli niitä tarvitsee:
##   core_batch   -> valikot ja perustaistelu (soi heti)
##   world_batch  -> MOBA-maailma, objectivet, ympäristö
##   hero_batch   -> sankarikohtaiset kyvyt ja ultit


## Valikko-, UI- ja perustaisteluäänet.
static func core_batch() -> Dictionary:
	var s := {}
	s["ui_move"] = AudioDsp.mix(
		AudioDsp.tone(0.055, 620.0, 820.0, "sine", 0.003, 0.035, 0.20),
		AudioDsp.tone(0.04, 1240.0, 980.0, "tri", 0.002, 0.025, 0.08), 0.0)
	s["ui_ok"] = AudioDsp.mix(
		AudioDsp.seq([[0.055, 440.0, 440.0, "sine"], [0.085, 660.0, 660.0, "sine"]], 0.27),
		AudioDsp.tone(0.12, 110.0, 82.0, "tri", 0.002, 0.08, 0.12), 0.0)
	s["ui_back"] = AudioDsp.mix(
		AudioDsp.tone(0.12, 480.0, 280.0, "sine", 0.004, 0.075, 0.30),
		AudioDsp.noise_burst(0.055, 0.10, 0.65, 1.0, 1007), 0.0)
	s["ui_open"] = AudioDsp.mix(
		AudioDsp.seq([[0.07, 220.0, 330.0, "tri"], [0.08, 440.0, 660.0, "sine"],
			[0.14, 880.0, 1040.0, "sine"]], 0.22),
		AudioDsp.tone(0.30, 82.0, 110.0, "sine", 0.01, 0.20, 0.15), 0.0)
	s["ui_lock"] = AudioDsp.mix(
		AudioDsp.seq([[0.045, 330.0, 330.0, "square"], [0.065, 494.0, 494.0, "tri"],
			[0.12, 659.0, 659.0, "sine"]], 0.25),
		AudioDsp.tone(0.18, 105.0, 78.0, "sine", 0.002, 0.12, 0.22), 0.0)
	s["ui_deny"] = AudioDsp.mix(
		AudioDsp.seq([[0.065, 185.0, 155.0, "square"], [0.09, 165.0, 120.0, "square"]], 0.20),
		AudioDsp.noise_burst(0.11, 0.12, 0.55, 1.0, 1014), 0.0)
	s["ui_team"] = AudioDsp.mix(
		AudioDsp.tone(0.13, 300.0, 600.0, "tri", 0.003, 0.08, 0.24),
		AudioDsp.tone(0.13, 900.0, 680.0, "sine", 0.005, 0.08, 0.10), 0.0)
	s["count_tick"] = AudioDsp.tone(0.06, 880.0, 880.0, "square", 0.002, 0.04, 0.25)
	s["count_go"] = AudioDsp.mix(
		AudioDsp.tone(0.35, 440.0, 880.0, "square", 0.01, 0.2, 0.22),
		AudioDsp.tone(0.3, 1320.0, 1760.0, "sine", 0.05, 0.2, 0.15), 0.08)
	s["round_start"] = AudioDsp.seq([
		[0.14, 523.0, 523.0, "square"], [0.14, 659.0, 659.0, "square"],
		[0.3, 784.0, 784.0, "square"]], 0.28)
	s["round_win"] = AudioDsp.seq([
		[0.12, 523.0, 523.0, "square"], [0.12, 659.0, 659.0, "square"],
		[0.12, 784.0, 784.0, "square"], [0.4, 1046.0, 1046.0, "square"]], 0.26)
	s["match_win"] = AudioDsp.mix(AudioDsp.seq([
		[0.16, 523.0, 523.0, "square"], [0.16, 659.0, 659.0, "square"],
		[0.16, 784.0, 784.0, "square"], [0.16, 1046.0, 1046.0, "square"],
		[0.5, 1318.0, 1318.0, "square"]], 0.24),
		AudioDsp.noise_burst(1.1, 0.08, 0.15, 1.0, 1021), 0.0)
	# Fyysinen isku: sub_thump (runko) + crack (kosketus) + lyhyt kohina.
	s["hit"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.sub_thump(150.0, 0.09, 0.55),
		AudioDsp.crack(0.028, 0.55, 1600.0, 101), 0.0),
		AudioDsp.noise_burst(0.05, 0.20, 0.42, 2.4, 102), 0.0)
	s["swing"] = AudioDsp.mix(
		AudioDsp.whoosh(0.13, 0.60, 2400.0, 520.0, 1.6, 103),
		AudioDsp.noise_burst(0.06, 0.10, 0.55, 2.6, 104), 0.03)
	s["slam"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.sub_thump(78.0, 0.26, 0.60),
		AudioDsp.thud(150.0, 0.14, 0.34), 0.0),
		AudioDsp.noise_burst(0.11, 0.22, 0.32, 2.0, 105), 0.0)
	s["quake"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.5, 70.0, 38.0, "sine", 0.005, 0.35, 0.44),
		AudioDsp.tone(0.4, 120.0, 60.0, "tri", 0.005, 0.3, 0.2), 0.0),
		AudioDsp.noise_burst(0.45, 0.26, 0.2, 1.0, 1049), 0.02)
	s["guard_up"] = AudioDsp.mix(
		AudioDsp.tone(0.18, 520.0, 780.0, "tri", 0.002, 0.12, 0.35),
		AudioDsp.tone(0.16, 880.0, 1100.0, "sine", 0.005, 0.1, 0.2), 0.02)
	s["dome_up"] = AudioDsp.mix(
		AudioDsp.tone(0.6, 110.0, 220.0, "sine", 0.03, 0.4, 0.4),
		AudioDsp.tone(0.6, 165.0, 330.0, "tri", 0.05, 0.4, 0.2), 0.05)
	# Kivi: puu/kivi-runko + murtuma + murenevaa kohinaa.
	s["rock"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(150.0, 0.22, 0.42),
		AudioDsp.crack(0.05, 0.45, 900.0, 106), 0.0),
		AudioDsp.noise_burst(0.30, 0.18, 0.30, 1.6, 107), 0.01)
	s["fire"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.noise_burst(0.16, 0.30, 0.42, 1.8, 124), 1.4),
		AudioDsp.crack(0.02, 0.30, 2200.0, 125), 0.0),
		AudioDsp.tone(0.15, 320.0, 180.0, "saw", 0.008, 0.10, 0.20), 0.0)
	s["fire_whoosh"] = AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.whoosh(0.34, 0.48, 320.0, 1700.0, 0.8, 123), 1.6),
		AudioDsp.tone(0.30, 200.0, 520.0, "saw", 0.02, 0.20, 0.14), 0.0)
	s["inferno"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.9, 0.5, 0.18, 1.0, 1077),
		AudioDsp.tone(0.9, 80.0, 140.0, "saw", 0.05, 0.6, 0.32), 0.0)
	s["bow"] = AudioDsp.mix(
		AudioDsp.tone(0.09, 1200.0, 300.0, "tri", 0.002, 0.06, 0.4),
		AudioDsp.noise_burst(0.03, 0.2, 0.8, 1.0, 1084), 0.0)
	s["bow_charged"] = AudioDsp.mix(
		AudioDsp.tone(0.22, 260.0, 720.0, "saw", 0.01, 0.14, 0.32),
		AudioDsp.tone(0.14, 1500.0, 400.0, "tri", 0.002, 0.1, 0.22), 0.06)
	s["arrow_rain"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.42, 0.42, 3000.0, 700.0, 2.4, 126),
		AudioDsp.whoosh(0.34, 0.32, 2400.0, 520.0, 2.4, 127), 0.06),
		AudioDsp.noise_burst(0.36, 0.10, 0.55, 1.4, 128), 0.02)
	s["heal"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(660.0, 0.34, 0.30),
		AudioDsp.bell(990.0, 0.26, 0.20), 0.06),
		AudioDsp.shimmer(0.40, 1320.0, 0.09, 137), 0.03)
	# Taika: kello + kimallus + suodatettu kohinahäntä.
	s["light"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(880.0, 0.30, 0.34),
		AudioDsp.shimmer(0.32, 1320.0, 0.10, 135), 0.015),
		AudioDsp.noise_burst(0.20, 0.05, 0.10, 2.2, 136), 0.01)
	s["blessing"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.10, 660.0, 660.0, "sine"], [0.10, 880.0, 880.0, "sine"],
			[0.26, 1320.0, 1320.0, "sine"]], 0.18),
		AudioDsp.bell(660.0, 0.55, 0.26), 0.0),
		AudioDsp.shimmer(0.62, 1320.0, 0.10, 139), 0.10)
	s["shield"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(440.0, 0.26, 0.30),
		AudioDsp.metal_ring(660.0, 0.22, 0.16), 0.0),
		AudioDsp.noise_burst(0.14, 0.06, 0.22, 2.4, 138), 0.0)
	s["note"] = AudioDsp.mix(
		AudioDsp.tone(0.18, 784.0, 784.0, "tri", 0.005, 0.14, 0.26),
		AudioDsp.tone(0.18, 1176.0, 1176.0, "sine", 0.01, 0.14, 0.1), 0.0)
	s["bass"] = AudioDsp.mix(
		AudioDsp.tone(0.26, 110.0, 68.0, "sine", 0.005, 0.2, 0.38),
		AudioDsp.tone(0.2, 165.0, 110.0, "tri", 0.005, 0.15, 0.16), 0.0)
	s["crescendo"] = AudioDsp.mix(AudioDsp.seq([
		[0.12, 523.0, 523.0, "tri"], [0.12, 659.0, 659.0, "tri"],
		[0.12, 784.0, 784.0, "tri"], [0.1, 1046.0, 1046.0, "tri"],
		[0.32, 1318.0, 1318.0, "square"]], 0.2),
		AudioDsp.tone(0.75, 262.0, 523.0, "sine", 0.05, 0.5, 0.14), 0.0)
	s["dash"] = AudioDsp.whoosh(0.15, 0.55, 900.0, 3200.0, 1.3, 108)
	s["disc"] = AudioDsp.mix(
		AudioDsp.whoosh(0.20, 0.48, 700.0, 1900.0, 2.6, 113),
		AudioDsp.tone(0.16, 720.0, 1180.0, "tri", 0.004, 0.10, 0.16), 0.0)
	s["smoke"] = AudioDsp.mix(
		AudioDsp.whoosh(0.34, 0.45, 1600.0, 320.0, 0.9, 109),
		AudioDsp.noise_burst(0.28, 0.10, 0.14, 1.4, 110), 0.02)
	s["water"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.17, 0.50, 400.0, 2400.0, 1.1, 114),
		AudioDsp.noise_burst(0.13, 0.22, 0.45, 2.0, 115), 0.0),
		AudioDsp.tone(0.12, 480.0, 900.0, "sine", 0.005, 0.08, 0.12), 0.01)
	s["wave"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.46, 0.52, 260.0, 1500.0, 0.8, 116),
		AudioDsp.noise_burst(0.40, 0.22, 0.35, 1.2, 117), 0.0),
		AudioDsp.tone(0.38, 280.0, 600.0, "sine", 0.02, 0.26, 0.14), 0.0)
	s["blink"] = AudioDsp.mix(
		AudioDsp.tone(0.12, 880.0, 1760.0, "sine", 0.005, 0.07, 0.35),
		AudioDsp.tone(0.08, 1760.0, 880.0, "sine", 0.01, 0.06, 0.2), 0.1)
	s["blade"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.09, 0.55, 3800.0, 900.0, 2.2, 111),
		AudioDsp.crack(0.02, 0.42, 3200.0, 112), 0.0),
		AudioDsp.tone(0.08, 1700.0, 620.0, "saw", 0.001, 0.05, 0.16), 0.0)
	s["zap"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.035, 0.50, 2600.0, 129),
		AudioDsp.crack(0.02, 0.34, 4200.0, 130), 0.012),
		AudioDsp.tone(0.09, 2000.0, 700.0, "square", 0.001, 0.05, 0.14), 0.0)
	s["thunder"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.55, 0.5, 0.22, 1.0, 1147),
		AudioDsp.tone(0.55, 95.0, 48.0, "saw", 0.005, 0.4, 0.32), 0.0)
	s["root"] = AudioDsp.tone(0.2, 130.0, 110.0, "saw", 0.01, 0.12, 0.4)
	s["vine"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.04, 0.45, 640.0, 121),
		AudioDsp.whoosh(0.15, 0.38, 1900.0, 400.0, 1.2, 122), 0.004),
		AudioDsp.thud(120.0, 0.10, 0.20), 0.02)
	# Luonto: kaksi orgaanista naksahdusta + lehtikohina, loivat transientit.
	s["thorns"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.05, 0.42, 1400.0, 118),
		AudioDsp.crack(0.06, 0.34, 820.0, 119), 0.035),
		AudioDsp.noise_burst(0.22, 0.16, 0.42, 2.0, 120), 0.0)
	s["ko"] = AudioDsp.mix(
		AudioDsp.tone(0.3, 300.0, 80.0, "sine", 0.005, 0.22, 0.5),
		AudioDsp.tone(0.15, 990.0, 1320.0, "sine", 0.02, 0.1, 0.16), 0.05)
	s["respawn"] = AudioDsp.tone(0.3, 440.0, 1320.0, "sine", 0.02, 0.2, 0.35)
	s["pickup"] = AudioDsp.seq([[0.07, 660.0, 660.0, "sine"], [0.1, 990.0, 990.0, "sine"]], 0.4)
	s["drop"] = AudioDsp.tone(0.12, 660.0, 330.0, "sine", 0.005, 0.08, 0.4)
	s["ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.5, 220.0, 330.0, "saw", 0.02, 0.3, 0.25),
		AudioDsp.tone(0.5, 330.0, 495.0, "saw", 0.02, 0.3, 0.2), 0.0),
		AudioDsp.tone(0.4, 440.0, 660.0, "sine", 0.05, 0.25, 0.2), 0.1)
	s["ult_ready"] = AudioDsp.mix(
		AudioDsp.tone(0.3, 1320.0, 1320.0, "sine", 0.005, 0.25, 0.3),
		AudioDsp.tone(0.3, 1980.0, 1980.0, "sine", 0.01, 0.25, 0.15), 0.03)
	s["score"] = AudioDsp.tone(0.08, 1100.0, 1100.0, "sine", 0.003, 0.06, 0.42)
	s["bump"] = AudioDsp.mix(
		AudioDsp.tone(0.14, 260.0, 760.0, "sine", 0.004, 0.1, 0.4),
		AudioDsp.tone(0.1, 760.0, 380.0, "tri", 0.004, 0.08, 0.18), 0.05)
	s["pop"] = AudioDsp.mix(
		AudioDsp.tone(0.06, 900.0, 400.0, "sine", 0.002, 0.04, 0.26),
		AudioDsp.noise_burst(0.03, 0.12, 0.6, 1.0, 1168), 0.0)
	s["mark"] = AudioDsp.mix(
		AudioDsp.tone(0.1, 1400.0, 1400.0, "square", 0.002, 0.06, 0.2),
		AudioDsp.tone(0.08, 1900.0, 1900.0, "sine", 0.005, 0.05, 0.14), 0.03)
	s["heartbeat"] = AudioDsp.mix(
		AudioDsp.tone(0.10, 95.0, 55.0, "sine", 0.004, 0.07, 0.5),
		AudioDsp.tone(0.09, 82.0, 48.0, "sine", 0.004, 0.07, 0.36), 0.14)
	return s


## MOBA-maailma: minionit, tornit, nexus, viidakko, objectivet, ympäristö.
static func world_batch() -> Dictionary:
	var s := {}
	s["moba_start"] = AudioDsp.mix(AudioDsp.seq([
		[0.13, 196.0, 262.0, "tri"], [0.13, 262.0, 392.0, "tri"],
		[0.32, 392.0, 523.0, "sine"]], 0.25),
		AudioDsp.tone(0.68, 72.0, 104.0, "sine", 0.02, 0.48, 0.24), 0.0)
	s["minion_wave"] = AudioDsp.mix(
		AudioDsp.seq([[0.10, 196.0, 247.0, "tri"], [0.18, 294.0, 392.0, "tri"]], 0.20),
		AudioDsp.tone(0.34, 82.0, 62.0, "sine", 0.003, 0.24, 0.16), 0.0)
	s["minion_melee"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(300.0, 0.06, 0.30),
		AudioDsp.crack(0.018, 0.26, 1800.0, 142), 0.0),
		AudioDsp.noise_burst(0.045, 0.12, 0.60, 2.6, 143), 0.0)
	s["minion_ranged"] = AudioDsp.mix(
		AudioDsp.tone(0.105, 780.0, 1280.0, "sine", 0.002, 0.07, 0.18),
		AudioDsp.tone(0.08, 390.0, 620.0, "tri", 0.002, 0.05, 0.08), 0.0)
	s["minion_impact"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(420.0, 0.05, 0.24),
		AudioDsp.crack(0.014, 0.22, 2600.0, 144), 0.0),
		AudioDsp.noise_burst(0.04, 0.08, 0.62, 3.0, 145), 0.0)
	s["minion_down"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(190.0, 0.13, 0.30),
		AudioDsp.noise_burst(0.09, 0.12, 0.42, 2.0, 146), 0.0),
		AudioDsp.tone(0.14, 260.0, 92.0, "tri", 0.002, 0.10, 0.14), 0.0)
	s["tower_lock"] = AudioDsp.mix(
		AudioDsp.seq([[0.055, 740.0, 740.0, "square"], [0.075, 980.0, 980.0, "sine"]], 0.18),
		AudioDsp.tone(0.16, 120.0, 92.0, "sine", 0.002, 0.11, 0.12), 0.0)
	s["tower_fire"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.25, 145.0, 58.0, "sine", 0.002, 0.18, 0.40),
		AudioDsp.noise_burst(0.16, 0.23, 0.48, 1.0, 1196), 0.0),
		AudioDsp.tone(0.18, 920.0, 360.0, "saw", 0.002, 0.12, 0.13), 0.015)
	s["tower_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.23, 112.0, 44.0, "sine", 0.001, 0.17, 0.42),
		AudioDsp.noise_burst(0.14, 0.25, 0.38, 1.0, 1203), 0.0)
	s["tower_guard"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(340.0, 0.40, 0.30),
		AudioDsp.sub_thump(96.0, 0.28, 0.26), 0.0),
		AudioDsp.noise_burst(0.10, 0.06, 0.30, 2.0, 133), 0.0)
	# Rakenne: murtuma + metallisointi + raskas kohinahäntä.
	s["tower_crack"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.06, 0.46, 700.0, 131),
		AudioDsp.metal_ring(210.0, 0.34, 0.24), 0.0),
		AudioDsp.noise_burst(0.32, 0.20, 0.28, 1.5, 132), 0.01)
	s["tower_destroy"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.82, 88.0, 32.0, "sine", 0.002, 0.66, 0.48),
		AudioDsp.noise_burst(0.72, 0.40, 0.24, 1.0, 1217), 0.0),
		AudioDsp.seq([[0.12, 420.0, 180.0, "tri"], [0.28, 240.0, 72.0, "saw"]], 0.15), 0.05)
	s["nexus_laser"] = AudioDsp.mix(
		AudioDsp.tone(0.24, 1280.0, 340.0, "saw", 0.001, 0.17, 0.25),
		AudioDsp.tone(0.24, 96.0, 62.0, "sine", 0.001, 0.18, 0.33), 0.0)
	s["nexus_guard"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(215.0, 0.60, 0.34),
		AudioDsp.sub_thump(66.0, 0.44, 0.30), 0.0),
		AudioDsp.shimmer(0.40, 660.0, 0.06, 134), 0.02)
	s["nexus_crack"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.58, 0.38, 0.24, 1.0, 1224),
		AudioDsp.tone(0.62, 105.0, 38.0, "saw", 0.003, 0.48, 0.34), 0.0)
	s["nexus_exposed"] = AudioDsp.mix(AudioDsp.seq([
		[0.14, 392.0, 330.0, "tri"], [0.14, 294.0, 247.0, "tri"],
		[0.38, 196.0, 98.0, "saw"]], 0.23),
		AudioDsp.tone(0.86, 82.0, 46.0, "sine", 0.003, 0.68, 0.42), 0.0)
	s["nexus_destroy"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(1.35, 78.0, 24.0, "sine", 0.002, 1.05, 0.58),
		AudioDsp.noise_burst(1.20, 0.52, 0.20, 1.0, 1231), 0.0), AudioDsp.mix(
		AudioDsp.seq([[0.15, 520.0, 210.0, "saw"], [0.18, 390.0, 130.0, "saw"],
			[0.55, 220.0, 48.0, "tri"]], 0.20),
		AudioDsp.tone(0.95, 1450.0, 170.0, "sine", 0.002, 0.76, 0.10), 0.0), 0.04)
	s["jungle_small_attack"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.03, 0.38, 900.0, 147),
		AudioDsp.whoosh(0.11, 0.34, 2000.0, 500.0, 1.4, 148), 0.004),
		AudioDsp.thud(160.0, 0.08, 0.18), 0.01)
	s["jungle_small_down"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(220.0, 0.18, 0.34),
		AudioDsp.noise_burst(0.16, 0.16, 0.34, 1.7, 149), 0.0),
		AudioDsp.crack(0.035, 0.24, 620.0, 150), 0.0)
	s["red_guardian_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.34, 180.0, 62.0, "saw", 0.002, 0.24, 0.30),
		AudioDsp.noise_burst(0.28, 0.29, 0.42, 1.0, 1252), 0.0)
	s["red_guardian_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.23, 125.0, 46.0, "sine", 0.002, 0.17, 0.34),
		AudioDsp.noise_burst(0.19, 0.28, 0.46, 1.0, 1259), 0.0)
	s["red_guardian_down"] = AudioDsp.mix(
		AudioDsp.tone(0.52, 128.0, 38.0, "saw", 0.003, 0.40, 0.34),
		AudioDsp.noise_burst(0.44, 0.34, 0.27, 1.0, 1266), 0.0)
	s["red_buff"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.10, 220.0, 294.0, "tri"], [0.10, 330.0, 440.0, "tri"],
			[0.24, 523.0, 659.0, "sine"]], 0.20),
		AudioDsp.bell(440.0, 0.42, 0.22), 0.10),
		AudioDsp.saturate(AudioDsp.noise_burst(0.40, 0.12, 0.50, 1.3, 160), 1.3), 0.0)
	s["blue_guardian_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.32, 420.0, 1180.0, "sine", 0.002, 0.22, 0.25),
		AudioDsp.tone(0.28, 840.0, 360.0, "tri", 0.003, 0.20, 0.14), 0.025)
	s["blue_guardian_impact"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(1180.0, 0.20, 0.32),
		AudioDsp.crack(0.02, 0.26, 3000.0, 151), 0.0),
		AudioDsp.noise_burst(0.13, 0.10, 0.70, 2.2, 152), 0.0)
	s["blue_guardian_down"] = AudioDsp.mix(
		AudioDsp.tone(0.55, 880.0, 170.0, "sine", 0.002, 0.44, 0.28),
		AudioDsp.noise_burst(0.34, 0.18, 0.72, 1.0, 1287), 0.0)
	s["blue_buff"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.10, 440.0, 523.0, "sine"], [0.10, 659.0, 784.0, "sine"],
			[0.28, 1046.0, 1318.0, "sine"]], 0.20),
		AudioDsp.bell(880.0, 0.46, 0.22), 0.10),
		AudioDsp.shimmer(0.50, 1320.0, 0.08, 161), 0.06)
	s["dragon_warning"] = AudioDsp.mix(
		AudioDsp.tone(0.86, 120.0, 58.0, "saw", 0.04, 0.62, 0.38),
		AudioDsp.noise_burst(0.74, 0.32, 0.34, 1.0, 1294), 0.0)
	s["dragon_spawn"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(1.0, 92.0, 210.0, "saw", 0.03, 0.72, 0.38),
		AudioDsp.noise_burst(0.86, 0.38, 0.42, 1.0, 1301), 0.0),
		AudioDsp.tone(0.62, 620.0, 1280.0, "sine", 0.04, 0.45, 0.14), 0.10)
	s["dragon_attack"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.46, 0.40, 0.48, 1.0, 1308),
		AudioDsp.tone(0.43, 185.0, 760.0, "saw", 0.008, 0.32, 0.25), 0.0)
	s["dragon_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.34, 125.0, 48.0, "sine", 0.002, 0.26, 0.40),
		AudioDsp.noise_burst(0.30, 0.34, 0.46, 1.0, 1315), 0.0)
	s["dragon_slam_warning"] = AudioDsp.mix(
		AudioDsp.tone(0.58, 210.0, 620.0, "saw", 0.01, 0.42, 0.24),
		AudioDsp.tone(0.54, 74.0, 112.0, "sine", 0.01, 0.40, 0.32), 0.0)
	s["dragon_slam"] = AudioDsp.mix(
		AudioDsp.tone(0.64, 82.0, 35.0, "sine", 0.002, 0.50, 0.50),
		AudioDsp.noise_burst(0.52, 0.42, 0.28, 1.0, 1322), 0.0)
	s["dragon_enrage"] = AudioDsp.mix(
		AudioDsp.tone(0.92, 145.0, 52.0, "saw", 0.01, 0.68, 0.42),
		AudioDsp.noise_burst(0.80, 0.40, 0.38, 1.0, 1329), 0.0)
	s["dragon_collapse"] = AudioDsp.mix(
		AudioDsp.tone(0.86, 155.0, 38.0, "saw", 0.003, 0.66, 0.38),
		AudioDsp.noise_burst(0.74, 0.42, 0.30, 1.0, 1336), 0.0)
	s["dragon_defeat"] = AudioDsp.mix(AudioDsp.seq([
		[0.14, 392.0, 523.0, "tri"], [0.14, 523.0, 659.0, "tri"],
		[0.42, 784.0, 1046.0, "sine"]], 0.25),
		AudioDsp.tone(0.72, 98.0, 62.0, "sine", 0.002, 0.56, 0.30), 0.0)
	s["baron_warning"] = AudioDsp.mix(
		AudioDsp.tone(0.95, 68.0, 39.0, "sine", 0.02, 0.72, 0.52),
		AudioDsp.tone(0.82, 210.0, 72.0, "saw", 0.01, 0.62, 0.22), 0.0)
	s["baron_spawn"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(1.15, 58.0, 104.0, "sine", 0.02, 0.86, 0.55),
		AudioDsp.noise_burst(0.95, 0.36, 0.22, 1.0, 1343), 0.0),
		AudioDsp.tone(0.82, 330.0, 980.0, "saw", 0.04, 0.62, 0.17), 0.08)
	s["baron_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.48, 96.0, 42.0, "sine", 0.002, 0.36, 0.47),
		AudioDsp.tone(0.38, 390.0, 120.0, "saw", 0.003, 0.28, 0.20), 0.0)
	s["baron_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.42, 72.0, 30.0, "sine", 0.002, 0.32, 0.52),
		AudioDsp.noise_burst(0.31, 0.28, 0.23, 1.0, 1350), 0.0)
	s["baron_slam_warning"] = AudioDsp.mix(
		AudioDsp.tone(0.62, 52.0, 94.0, "sine", 0.01, 0.46, 0.48),
		AudioDsp.tone(0.55, 185.0, 430.0, "saw", 0.012, 0.40, 0.18), 0.0)
	s["baron_slam"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.78, 62.0, 27.0, "sine", 0.002, 0.62, 0.58),
		AudioDsp.noise_burst(0.62, 0.44, 0.22, 1.0, 1357), 0.0),
		AudioDsp.tone(0.42, 280.0, 64.0, "saw", 0.002, 0.32, 0.18), 0.02)
	s["baron_enrage"] = AudioDsp.mix(
		AudioDsp.tone(1.05, 78.0, 32.0, "saw", 0.006, 0.80, 0.48),
		AudioDsp.noise_burst(0.90, 0.42, 0.22, 1.0, 1364), 0.0)
	s["baron_collapse"] = AudioDsp.mix(
		AudioDsp.tone(1.0, 82.0, 24.0, "sine", 0.002, 0.78, 0.55),
		AudioDsp.noise_burst(0.88, 0.46, 0.21, 1.0, 1371), 0.0)
	s["baron_defeat"] = AudioDsp.mix(AudioDsp.seq([
		[0.14, 196.0, 262.0, "tri"], [0.14, 294.0, 392.0, "tri"],
		[0.48, 523.0, 784.0, "sine"]], 0.27),
		AudioDsp.tone(0.86, 68.0, 45.0, "sine", 0.002, 0.68, 0.40), 0.0)
	s["ambient_jungle"] = AudioDsp.mix(
		AudioDsp.noise_burst(2.8, 0.075, 0.09, 1.0, 1378),
		AudioDsp.seq([[0.07, 1180.0, 1540.0, "sine"], [0.06, 1360.0, 980.0, "sine"],
			[0.08, 1040.0, 1420.0, "sine"]], 0.055), 1.05)
	s["ambient_river"] = AudioDsp.mix(
		AudioDsp.noise_burst(2.8, 0.105, 0.20, 1.0, 1385),
		AudioDsp.tone(2.8, 145.0, 205.0, "sine", 0.24, 0.62, 0.020), 0.0)
	s["ambient_lane"] = AudioDsp.mix(
		AudioDsp.noise_burst(2.8, 0.070, 0.12, 1.0, 1392),
		AudioDsp.tone(2.7, 78.0, 96.0, "sine", 0.3, 0.62, 0.018), 0.0)
	s["ambient_brush"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.72, 0.12, 0.38, 1.0, 1399),
		AudioDsp.seq([[0.05, 780.0, 1120.0, "sine"], [0.07, 980.0, 720.0, "sine"]], 0.055), 0.25)
	s["ambient_blue_base"] = AudioDsp.mix(
		AudioDsp.tone(2.6, 98.0, 102.0, "sine", 0.24, 0.58, 0.045),
		AudioDsp.tone(2.5, 392.0, 404.0, "sine", 0.28, 0.56, 0.018), 0.03)
	s["ambient_orange_base"] = AudioDsp.mix(
		AudioDsp.tone(2.6, 82.0, 78.0, "sine", 0.24, 0.58, 0.050),
		AudioDsp.tone(2.5, 246.0, 234.0, "tri", 0.28, 0.56, 0.016), 0.03)
	s["ambient_baron_pit"] = AudioDsp.mix(
		AudioDsp.tone(2.9, 54.0, 62.0, "sine", 0.28, 0.72, 0.065),
		AudioDsp.tone(2.8, 180.0, 142.0, "saw", 0.32, 0.70, 0.018), 0.04)
	s["ambient_dragon_pit"] = AudioDsp.mix(
		AudioDsp.noise_burst(2.8, 0.065, 0.16, 1.0, 1406),
		AudioDsp.tone(2.8, 210.0, 285.0, "sine", 0.30, 0.68, 0.035), 0.0)
	return s


## Sankarikohtaiset kyky- ja ultiäänet.
static func hero_batch() -> Dictionary:
	var s := {}
	s["luma_pulse"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(980.0, 0.22, 0.32),
		AudioDsp.shimmer(0.26, 1960.0, 0.09, 140), 0.01),
		AudioDsp.noise_burst(0.14, 0.04, 0.10, 2.4, 141), 0.0)
	s["luma_bloom"] = AudioDsp.mix(AudioDsp.seq([
		[0.09, 660.0, 660.0, "sine"], [0.09, 880.0, 880.0, "sine"],
		[0.18, 1320.0, 1320.0, "sine"]], 0.25),
		AudioDsp.tone(0.42, 330.0, 660.0, "sine", 0.03, 0.3, 0.12), 0.0)
	s["luma_shield"] = AudioDsp.mix(
		AudioDsp.tone(0.28, 520.0, 780.0, "tri", 0.004, 0.2, 0.25),
		AudioDsp.tone(0.30, 1040.0, 1040.0, "sine", 0.008, 0.24, 0.15), 0.035)
	s["luma_ult"] = AudioDsp.mix(AudioDsp.seq([
		[0.12, 523.0, 523.0, "sine"], [0.12, 659.0, 659.0, "sine"],
		[0.12, 880.0, 880.0, "sine"], [0.34, 1318.0, 1318.0, "tri"]], 0.24),
		AudioDsp.tone(0.78, 262.0, 784.0, "sine", 0.05, 0.58, 0.13), 0.0)
	s["ember_bolt"] = AudioDsp.mix(
		AudioDsp.tone(0.13, 520.0, 180.0, "saw", 0.003, 0.09, 0.27),
		AudioDsp.noise_burst(0.09, 0.18, 0.72, 1.0, 1413), 0.0)
	s["ember_pool"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.noise_burst(0.26, 0.26, 0.50, 1.5, 155), 1.5),
		AudioDsp.whoosh(0.24, 0.30, 500.0, 1600.0, 0.9, 156), 0.0),
		AudioDsp.tone(0.24, 240.0, 600.0, "saw", 0.008, 0.16, 0.18), 0.0)
	s["ember_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.22, 170.0, 72.0, "tri", 0.002, 0.16, 0.32),
		AudioDsp.noise_burst(0.20, 0.34, 0.42, 1.0, 1427), 0.0)
	s["ember_wave"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.whoosh(0.40, 0.46, 380.0, 1900.0, 0.8, 157), 1.7),
		AudioDsp.noise_burst(0.34, 0.20, 0.46, 1.4, 158), 0.0),
		AudioDsp.tone(0.34, 180.0, 620.0, "saw", 0.015, 0.24, 0.16), 0.0)
	s["ember_ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.noise_burst(0.95, 0.44, 0.25, 1.0, 1441),
		AudioDsp.tone(0.9, 75.0, 145.0, "saw", 0.04, 0.65, 0.30), 0.0),
		AudioDsp.tone(0.55, 330.0, 780.0, "tri", 0.02, 0.4, 0.15), 0.10)
	s["hush_ult"] = AudioDsp.mix(
		AudioDsp.tone(0.72, 520.0, 92.0, "sine", 0.012, 0.58, 0.34),
		AudioDsp.tone(0.62, 1040.0, 180.0, "tri", 0.008, 0.48, 0.16), 0.03)
	s["volt_ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.noise_burst(0.72, 0.46, 0.28, 1.0, 1448),
		AudioDsp.tone(0.7, 145.0, 52.0, "saw", 0.005, 0.55, 0.32), 0.0),
		AudioDsp.tone(0.32, 1900.0, 430.0, "square", 0.002, 0.22, 0.12), 0.04)
	s["tide_ult"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.76, 0.44, 0.34, 1.0, 1455),
		AudioDsp.tone(0.7, 180.0, 760.0, "sine", 0.018, 0.52, 0.24), 0.02)
	s["quill_ult"] = AudioDsp.mix(
		AudioDsp.tone(0.42, 210.0, 1750.0, "saw", 0.004, 0.30, 0.29),
		AudioDsp.noise_burst(0.24, 0.24, 0.72, 1.0, 1462), 0.045)
	s["boulder_ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.82, 72.0, 34.0, "sine", 0.004, 0.64, 0.48),
		AudioDsp.noise_burst(0.72, 0.38, 0.24, 1.0, 1469), 0.0),
		AudioDsp.tone(0.34, 210.0, 68.0, "tri", 0.003, 0.24, 0.20), 0.02)
	s["bramble_ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.07, 0.42, 520.0, 153),
		AudioDsp.whoosh(0.55, 0.42, 700.0, 2200.0, 0.9, 154), 0.0),
		AudioDsp.tone(0.60, 165.0, 420.0, "saw", 0.008, 0.44, 0.20), 0.0)
	s["obsidian_ult"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.92, 62.0, 118.0, "sine", 0.006, 0.72, 0.50),
		AudioDsp.noise_burst(0.72, 0.42, 0.24, 1.0, 1483), 0.0),
		AudioDsp.tone(0.62, 260.0, 58.0, "saw", 0.006, 0.50, 0.22), 0.05)
	s["titan_punch"] = AudioDsp.mix(
		AudioDsp.tone(0.16, 105.0, 48.0, "sine", 0.002, 0.12, 0.48),
		AudioDsp.noise_burst(0.075, 0.30, 0.35, 1.0, 1490), 0.0)
	s["titan_grab"] = AudioDsp.mix(
		AudioDsp.tone(0.24, 150.0, 78.0, "tri", 0.003, 0.18, 0.34),
		AudioDsp.tone(0.14, 620.0, 260.0, "square", 0.002, 0.1, 0.10), 0.025)
	s["titan_throw"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.26, 0.34, 0.4, 1.0, 1497),
		AudioDsp.tone(0.30, 120.0, 42.0, "sine", 0.003, 0.23, 0.50), 0.05)
	s["titan_launch"] = AudioDsp.mix(
		AudioDsp.tone(0.52, 70.0, 35.0, "sine", 0.003, 0.4, 0.50),
		AudioDsp.noise_burst(0.42, 0.32, 0.22, 1.0, 1504), 0.02)
	s["titan_brace"] = AudioDsp.mix(
		AudioDsp.tone(0.34, 180.0, 92.0, "tri", 0.004, 0.26, 0.28),
		AudioDsp.tone(0.22, 540.0, 390.0, "square", 0.002, 0.17, 0.10), 0.03)
	s["titan_rage"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.82, 62.0, 38.0, "sine", 0.004, 0.62, 0.52),
		AudioDsp.noise_burst(0.75, 0.37, 0.20, 1.0, 1511), 0.0),
		AudioDsp.tone(0.55, 150.0, 280.0, "saw", 0.03, 0.4, 0.17), 0.08)
	s["salvo_grenade"] = AudioDsp.mix(
		AudioDsp.tone(0.11, 280.0, 115.0, "tri", 0.002, 0.075, 0.34),
		AudioDsp.noise_burst(0.065, 0.24, 0.56, 1.0, 1518), 0.0)
	s["salvo_mortar_launch"] = AudioDsp.mix(
		AudioDsp.tone(0.32, 150.0, 680.0, "saw", 0.004, 0.22, 0.27),
		AudioDsp.noise_burst(0.18, 0.30, 0.48, 1.0, 1525), 0.025)
	s["salvo_mortar_impact"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.48, 82.0, 36.0, "sine", 0.002, 0.36, 0.50),
		AudioDsp.noise_burst(0.34, 0.42, 0.30, 1.0, 1532), 0.0),
		AudioDsp.tone(0.18, 520.0, 120.0, "saw", 0.002, 0.12, 0.14), 0.015)
	s["salvo_bunker"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.58, 105.0, 54.0, "tri", 0.003, 0.44, 0.42),
		AudioDsp.noise_burst(0.42, 0.34, 0.28, 1.0, 1539), 0.0),
		AudioDsp.seq([[0.11, 410.0, 280.0, "square"], [0.14, 330.0, 190.0, "square"]], 0.13), 0.06)
	s["salvo_bunker_open"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(280.0, 0.26, 0.28),
		AudioDsp.whoosh(0.24, 0.34, 600.0, 1800.0, 1.1, 159), 0.01),
		AudioDsp.tone(0.26, 140.0, 380.0, "tri", 0.003, 0.18, 0.20), 0.0)
	s["salvo_rocket_launch"] = AudioDsp.mix(
		AudioDsp.tone(0.62, 72.0, 210.0, "saw", 0.01, 0.46, 0.34),
		AudioDsp.noise_burst(0.55, 0.40, 0.26, 1.0, 1553), 0.0)
	s["salvo_rocket_impact"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.92, 66.0, 28.0, "sine", 0.002, 0.72, 0.55),
		AudioDsp.noise_burst(0.78, 0.50, 0.24, 1.0, 1560), 0.0),
		AudioDsp.tone(0.46, 230.0, 62.0, "saw", 0.002, 0.34, 0.20), 0.015)
	return s


## Kauppa, artefakti, vartija, häive, eteneminen, piiritys, kristalli,
## paluu, lähde, tyrmäyssarjat, ranked-cuet ja neljän junglerin omat kyvyt.
static func extra_batch() -> Dictionary:
	var s := {}
	# --- Kauppa: tekniikkakieli, kuiva väylä, ei kaikuhäntää ---
	s["shop_open"] = AudioDsp.mix(
		AudioDsp.seq([[0.06, 330.0, 440.0, "tri"], [0.07, 494.0, 659.0, "sine"],
			[0.12, 880.0, 988.0, "sine"]], 0.20),
		AudioDsp.tone(0.26, 110.0, 147.0, "sine", 0.008, 0.18, 0.14), 0.0)
	s["shop_close"] = AudioDsp.mix(
		AudioDsp.seq([[0.07, 660.0, 494.0, "sine"], [0.10, 440.0, 294.0, "sine"]], 0.20),
		AudioDsp.tone(0.16, 147.0, 98.0, "tri", 0.004, 0.10, 0.14), 0.0)
	s["shop_move"] = AudioDsp.mix(
		AudioDsp.tone(0.045, 740.0, 880.0, "square", 0.002, 0.03, 0.16),
		AudioDsp.tone(0.035, 1480.0, 1480.0, "sine", 0.002, 0.02, 0.06), 0.0)
	s["shop_buy"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.05, 587.0, 587.0, "sine"], [0.09, 880.0, 880.0, "sine"]], 0.22),
		AudioDsp.bell(1174.0, 0.26, 0.16), 0.05),
		AudioDsp.tone(0.14, 147.0, 110.0, "tri", 0.003, 0.09, 0.12), 0.0)
	s["shop_sell"] = AudioDsp.mix(
		AudioDsp.seq([[0.05, 880.0, 880.0, "sine"], [0.09, 587.0, 587.0, "sine"]], 0.22),
		AudioDsp.tone(0.13, 220.0, 147.0, "tri", 0.003, 0.09, 0.12), 0.0)
	s["shop_deny"] = AudioDsp.mix(
		AudioDsp.seq([[0.055, 196.0, 165.0, "square"], [0.08, 165.0, 131.0, "square"]], 0.18),
		AudioDsp.noise_burst(0.09, 0.10, 0.50, 2.0, 201), 0.0)
	s["shop_legendary"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.09, 523.0, 523.0, "sine"], [0.09, 784.0, 784.0, "sine"],
			[0.24, 1046.0, 1046.0, "sine"]], 0.18),
		AudioDsp.bell(1046.0, 0.70, 0.26), 0.0),
		AudioDsp.shimmer(0.70, 1568.0, 0.10, 202), 0.10)

	# --- Baronin artefakti ---
	s["artifact_drop"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(392.0, 0.55, 0.28),
		AudioDsp.sub_thump(72.0, 0.26, 0.26), 0.0),
		AudioDsp.shimmer(0.50, 784.0, 0.08, 203), 0.04)
	s["artifact_pickup"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.08, 523.0, 659.0, "sine"], [0.20, 784.0, 1046.0, "sine"]], 0.20),
		AudioDsp.bell(1046.0, 0.55, 0.24), 0.02),
		AudioDsp.shimmer(0.55, 1568.0, 0.09, 204), 0.06)
	s["artifact_lost"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(330.0, 0.50, 0.26),
		AudioDsp.tone(0.44, 392.0, 165.0, "tri", 0.006, 0.32, 0.20), 0.0),
		AudioDsp.noise_burst(0.30, 0.10, 0.24, 1.8, 205), 0.02)

	# --- Vartiolyhty (ward) ---
	s["ward_place"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(1046.0, 0.22, 0.24),
		AudioDsp.tone(0.10, 220.0, 330.0, "tri", 0.003, 0.07, 0.16), 0.0),
		AudioDsp.noise_burst(0.06, 0.08, 0.40, 2.4, 206), 0.0)
	s["ward_expire"] = AudioDsp.mix(
		AudioDsp.seq([[0.07, 880.0, 660.0, "sine"], [0.11, 587.0, 392.0, "sine"]], 0.16),
		AudioDsp.tone(0.14, 165.0, 110.0, "tri", 0.004, 0.10, 0.10), 0.0)
	s["ward_spot"] = AudioDsp.mix(
		AudioDsp.tone(0.05, 1568.0, 1568.0, "square", 0.002, 0.03, 0.14),
		AudioDsp.tone(0.07, 2093.0, 2093.0, "sine", 0.003, 0.05, 0.08), 0.045)

	# --- Häive (varjoviitta) ---
	s["stealth_in"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.30, 0.40, 2600.0, 380.0, 0.9, 207),
		AudioDsp.tone(0.28, 440.0, 165.0, "sine", 0.01, 0.20, 0.16), 0.0),
		AudioDsp.shimmer(0.26, 880.0, 0.05, 208), 0.02)
	s["stealth_out"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.22, 0.38, 380.0, 2400.0, 1.0, 209),
		AudioDsp.tone(0.20, 220.0, 560.0, "sine", 0.006, 0.14, 0.16), 0.0),
		AudioDsp.noise_burst(0.10, 0.06, 0.45, 2.2, 210), 0.0)
	s["stealth_strike"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.022, 0.55, 2800.0, 211),
		AudioDsp.sub_thump(120.0, 0.13, 0.50), 0.0), AudioDsp.mix(
		AudioDsp.whoosh(0.10, 0.40, 3200.0, 800.0, 2.0, 212),
		AudioDsp.bell(1568.0, 0.20, 0.14), 0.01), 0.0)

	# --- Eteneminen: kyvyn rankki (kevyt) ja ultin avautuminen (isompi) ---
	s["rank_up"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.05, 659.0, 659.0, "sine"], [0.10, 988.0, 988.0, "sine"]], 0.20),
		AudioDsp.bell(988.0, 0.30, 0.18), 0.03),
		AudioDsp.tone(0.16, 165.0, 220.0, "tri", 0.004, 0.11, 0.10), 0.0)
	s["ult_unlock"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.09, 392.0, 392.0, "tri"], [0.09, 587.0, 587.0, "tri"],
			[0.26, 784.0, 784.0, "sine"]], 0.20),
		AudioDsp.bell(1568.0, 0.62, 0.24), 0.05), AudioDsp.mix(
		AudioDsp.sub_thump(58.0, 0.42, 0.30),
		AudioDsp.shimmer(0.66, 1568.0, 0.10, 213), 0.02), 0.0)

	# --- Piiritys: torni ei ota vahinkoa ---
	s["siege_blocked"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(120.0, 0.10, 0.42),
		AudioDsp.metal_ring(180.0, 0.14, 0.16), 0.0),
		AudioDsp.noise_burst(0.07, 0.08, 0.30, 2.6, 214), 0.0)
	s["siege_immune"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(520.0, 0.20, 0.24),
		AudioDsp.tone(0.14, 330.0, 247.0, "square", 0.002, 0.09, 0.12), 0.0),
		AudioDsp.noise_burst(0.06, 0.06, 0.35, 2.6, 215), 0.0)

	# --- Kristalli (inhibiittori) ---
	s["crystal_rise"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(392.0, 0.70, 0.30),
		AudioDsp.tone(0.60, 110.0, 330.0, "sine", 0.05, 0.40, 0.22), 0.0),
		AudioDsp.shimmer(0.66, 784.0, 0.09, 216), 0.04)
	s["crystal_break"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.08, 0.55, 1600.0, 217),
		AudioDsp.metal_ring(520.0, 0.55, 0.26), 0.0), AudioDsp.mix(
		AudioDsp.sub_thump(64.0, 0.50, 0.36),
		AudioDsp.noise_burst(0.50, 0.22, 0.34, 1.4, 218), 0.0), 0.0)

	# --- Superminioniaalto ---
	s["super_wave"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.12, 147.0, 196.0, "saw"], [0.12, 196.0, 262.0, "saw"],
			[0.30, 294.0, 392.0, "tri"]], 0.20),
		AudioDsp.sub_thump(58.0, 0.55, 0.34), 0.0),
		AudioDsp.saturate(AudioDsp.noise_burst(0.40, 0.14, 0.30, 1.5, 219), 1.4), 0.02)

	# --- Paluukanavointi ---
	s["recall_start"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(523.0, 0.42, 0.24),
		AudioDsp.tone(0.40, 262.0, 392.0, "sine", 0.03, 0.28, 0.18), 0.0),
		AudioDsp.shimmer(0.44, 1046.0, 0.07, 220), 0.02)
	s["recall_done"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.07, 523.0, 659.0, "sine"], [0.18, 784.0, 1046.0, "sine"]], 0.20),
		AudioDsp.bell(1046.0, 0.44, 0.22), 0.0),
		AudioDsp.whoosh(0.26, 0.26, 500.0, 2600.0, 1.0, 221), 0.0)
	s["recall_cancel"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.20, 523.0, 196.0, "sine", 0.004, 0.14, 0.24),
		AudioDsp.metal_ring(262.0, 0.18, 0.14), 0.0),
		AudioDsp.noise_burst(0.10, 0.08, 0.36, 2.2, 222), 0.0)

	# --- Lähderegen ---
	s["fountain_regen"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(784.0, 0.34, 0.16),
		AudioDsp.shimmer(0.42, 1568.0, 0.06, 223), 0.02),
		AudioDsp.noise_burst(0.30, 0.04, 0.12, 1.6, 224), 0.0)

	# --- Ensiveri ja moninkertaiset tyrmäykset ---
	s["first_blood"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.10, 196.0, 196.0, "saw"], [0.10, 262.0, 262.0, "saw"],
			[0.32, 392.0, 392.0, "square"]], 0.16),
		AudioDsp.sub_thump(52.0, 0.62, 0.34), 0.0), AudioDsp.mix(
		AudioDsp.metal_ring(660.0, 0.44, 0.16),
		AudioDsp.noise_burst(0.44, 0.10, 0.26, 1.6, 225), 0.0), 0.0)
	s["multi_kill_2"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.08, 440.0, 440.0, "square"], [0.20, 587.0, 587.0, "square"]], 0.18),
		AudioDsp.bell(880.0, 0.34, 0.16), 0.02),
		AudioDsp.sub_thump(70.0, 0.26, 0.24), 0.0)
	s["multi_kill_3"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.08, 523.0, 523.0, "square"], [0.08, 659.0, 659.0, "square"],
			[0.24, 880.0, 880.0, "square"]], 0.18),
		AudioDsp.bell(1046.0, 0.42, 0.18), 0.02),
		AudioDsp.sub_thump(64.0, 0.34, 0.26), 0.0)
	s["multi_kill_4"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.08, 587.0, 587.0, "saw"], [0.08, 784.0, 784.0, "saw"],
			[0.08, 988.0, 988.0, "saw"], [0.30, 1319.0, 1319.0, "square"]], 0.17),
		AudioDsp.bell(1319.0, 0.58, 0.20), 0.02), AudioDsp.mix(
		AudioDsp.sub_thump(56.0, 0.50, 0.30),
		AudioDsp.shimmer(0.62, 1568.0, 0.08, 226), 0.0), 0.0)

	# --- Ranked-ylennykset ---
	s["promo_div_up"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.07, 523.0, 523.0, "sine"], [0.18, 784.0, 784.0, "sine"]], 0.18),
		AudioDsp.bell(1046.0, 0.50, 0.20), 0.02),
		AudioDsp.shimmer(0.54, 1568.0, 0.08, 227), 0.05)
	s["promo_tier_up"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.11, 392.0, 392.0, "tri"], [0.11, 523.0, 523.0, "tri"],
			[0.11, 659.0, 659.0, "tri"], [0.38, 784.0, 784.0, "square"]], 0.18),
		AudioDsp.bell(1568.0, 0.95, 0.26), 0.05), AudioDsp.mix(
		AudioDsp.sub_thump(48.0, 0.80, 0.34),
		AudioDsp.shimmer(1.00, 2093.0, 0.10, 228), 0.02), 0.0)
	s["promo_slot_win"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(880.0, 0.30, 0.22),
		AudioDsp.tone(0.14, 523.0, 784.0, "sine", 0.003, 0.10, 0.16), 0.0),
		AudioDsp.noise_burst(0.08, 0.06, 0.40, 2.4, 229), 0.0)
	s["promo_slot_loss"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(330.0, 0.28, 0.20),
		AudioDsp.tone(0.16, 330.0, 196.0, "square", 0.003, 0.11, 0.14), 0.0),
		AudioDsp.noise_burst(0.10, 0.08, 0.34, 2.2, 230), 0.0)
	s["promo_failed"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.06, 0.42, 700.0, 231),
		AudioDsp.tone(0.55, 330.0, 110.0, "saw", 0.006, 0.40, 0.24), 0.0), AudioDsp.mix(
		AudioDsp.sub_thump(52.0, 0.46, 0.28),
		AudioDsp.noise_burst(0.44, 0.14, 0.26, 1.5, 232), 0.0), 0.0)
	s["promo_demote"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.07, 0.44, 520.0, 233),
		AudioDsp.sub_thump(46.0, 0.60, 0.34), 0.0), AudioDsp.mix(
		AudioDsp.tone(0.62, 262.0, 82.0, "saw", 0.006, 0.46, 0.22),
		AudioDsp.noise_burst(0.55, 0.16, 0.24, 1.4, 234), 0.0), 0.0)
	s["promo_shield"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(659.0, 0.40, 0.24),
		AudioDsp.metal_ring(988.0, 0.34, 0.14), 0.01),
		AudioDsp.shimmer(0.42, 1319.0, 0.07, 235), 0.03)

	# --- Ranked-aula ---
	s["rank_hub_open"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.07, 262.0, 392.0, "tri"], [0.09, 523.0, 659.0, "sine"],
			[0.16, 784.0, 988.0, "sine"]], 0.18),
		AudioDsp.bell(988.0, 0.42, 0.16), 0.05),
		AudioDsp.tone(0.30, 98.0, 131.0, "sine", 0.01, 0.20, 0.12), 0.0)
	s["rank_hub_move"] = AudioDsp.mix(
		AudioDsp.tone(0.05, 660.0, 784.0, "sine", 0.002, 0.035, 0.16),
		AudioDsp.tone(0.035, 1320.0, 1180.0, "tri", 0.002, 0.02, 0.06), 0.0)
	s["rank_hub_lp"] = AudioDsp.tone(0.035, 1568.0, 1760.0, "sine", 0.002, 0.025, 0.14)
	s["rank_hub_confirm"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.05, 392.0, 392.0, "square"], [0.10, 587.0, 587.0, "tri"]], 0.20),
		AudioDsp.bell(1174.0, 0.30, 0.16), 0.02),
		AudioDsp.tone(0.18, 131.0, 98.0, "sine", 0.003, 0.12, 0.14), 0.0)

	# --- Kaira: kivi ja laava (fyysinen isku + saturoitu tuli) ---
	s["kaira_drill"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.thud(260.0, 0.09, 0.36),
		AudioDsp.crack(0.022, 0.40, 1300.0, 240), 0.0),
		AudioDsp.whoosh(0.11, 0.32, 2200.0, 600.0, 1.6, 241), 0.0)
	s["kaira_charge"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.whoosh(0.32, 0.46, 400.0, 1800.0, 0.9, 242), 1.6),
		AudioDsp.sub_thump(80.0, 0.28, 0.34), 0.0),
		AudioDsp.tone(0.30, 180.0, 460.0, "saw", 0.01, 0.20, 0.16), 0.0)
	s["kaira_slam"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.sub_thump(64.0, 0.34, 0.58),
		AudioDsp.thud(150.0, 0.20, 0.32), 0.0), AudioDsp.mix(
		AudioDsp.crack(0.05, 0.40, 800.0, 243),
		AudioDsp.noise_burst(0.28, 0.20, 0.30, 1.7, 244), 0.0), 0.0)
	s["kaira_fissure"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.sub_thump(46.0, 0.85, 0.55),
		AudioDsp.saturate(AudioDsp.noise_burst(0.80, 0.26, 0.22, 1.2, 245), 1.4), 0.0),
		AudioDsp.mix(AudioDsp.crack(0.09, 0.46, 520.0, 246),
		AudioDsp.tone(0.70, 140.0, 52.0, "saw", 0.01, 0.52, 0.22), 0.0), 0.02)
	s["kaira_lava"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.saturate(AudioDsp.noise_burst(0.42, 0.24, 0.34, 1.3, 247), 1.6),
		AudioDsp.tone(0.40, 120.0, 260.0, "saw", 0.02, 0.28, 0.18), 0.0),
		AudioDsp.whoosh(0.34, 0.24, 700.0, 240.0, 0.8, 248), 0.03)

	# --- Torq: magneetti ja metalli (metal_ring-perhe) ---
	s["torq_hammer"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(280.0, 0.20, 0.30),
		AudioDsp.sub_thump(110.0, 0.12, 0.40), 0.0),
		AudioDsp.crack(0.018, 0.34, 2000.0, 250), 0.0)
	s["torq_hook"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(520.0, 0.24, 0.24),
		AudioDsp.whoosh(0.26, 0.38, 900.0, 2600.0, 1.5, 251), 0.0),
		AudioDsp.tone(0.22, 260.0, 620.0, "square", 0.003, 0.15, 0.12), 0.0)
	s["torq_hook_hit"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(196.0, 0.34, 0.32),
		AudioDsp.sub_thump(84.0, 0.22, 0.42), 0.0), AudioDsp.mix(
		AudioDsp.crack(0.03, 0.38, 1500.0, 252),
		AudioDsp.whoosh(0.20, 0.26, 2200.0, 500.0, 1.4, 253), 0.0), 0.0)
	s["torq_lock"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(392.0, 0.34, 0.28),
		AudioDsp.whoosh(0.30, 0.30, 2600.0, 420.0, 0.9, 255), 0.0),
		AudioDsp.tone(0.28, 147.0, 98.0, "sine", 0.01, 0.20, 0.26), 0.0)
	s["torq_well"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.metal_ring(147.0, 0.85, 0.28),
		AudioDsp.tone(0.80, 82.0, 62.0, "sine", 0.05, 0.55, 0.30), 0.0),
		AudioDsp.whoosh(0.75, 0.22, 2400.0, 260.0, 0.7, 254), 0.03)

	# --- Vesper: tarkkuus, merkintä ja kisko ---
	s["vesper_bolt"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.016, 0.34, 3000.0, 260),
		AudioDsp.whoosh(0.09, 0.34, 3400.0, 1100.0, 2.4, 261), 0.0),
		AudioDsp.tone(0.08, 1400.0, 700.0, "tri", 0.001, 0.05, 0.14), 0.0)
	s["vesper_spike"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.20, 0.44, 1200.0, 3600.0, 2.0, 267),
		AudioDsp.crack(0.02, 0.36, 2200.0, 268), 0.0),
		AudioDsp.tone(0.18, 620.0, 1480.0, "saw", 0.002, 0.12, 0.16), 0.0)
	s["vesper_mark"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(1568.0, 0.22, 0.24),
		AudioDsp.tone(0.06, 2093.0, 2093.0, "square", 0.002, 0.04, 0.10), 0.0),
		AudioDsp.noise_burst(0.05, 0.05, 0.60, 2.6, 262), 0.0)
	s["vesper_execute"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.sub_thump(96.0, 0.18, 0.48),
		AudioDsp.crack(0.024, 0.44, 2400.0, 263), 0.0),
		AudioDsp.tone(0.20, 880.0, 220.0, "saw", 0.002, 0.14, 0.18), 0.0)
	s["vesper_kill"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(1319.0, 0.44, 0.26),
		AudioDsp.sub_thump(72.0, 0.26, 0.32), 0.0), AudioDsp.mix(
		AudioDsp.metal_ring(1046.0, 0.30, 0.14),
		AudioDsp.shimmer(0.44, 1976.0, 0.08, 264), 0.0), 0.0)
	s["vesper_rail"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.34, 0.50, 4200.0, 900.0, 2.6, 265),
		AudioDsp.tone(0.30, 1760.0, 320.0, "saw", 0.002, 0.20, 0.22), 0.0), AudioDsp.mix(
		AudioDsp.sub_thump(60.0, 0.30, 0.30),
		AudioDsp.crack(0.03, 0.40, 3200.0, 266), 0.0), 0.0)

	# --- Myria: orkideat ja kukinta (kello + kimallus, pehmeät transientit) ---
	s["myria_wisp"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(740.0, 0.20, 0.24),
		AudioDsp.whoosh(0.14, 0.24, 1400.0, 3000.0, 1.2, 270), 0.0),
		AudioDsp.noise_burst(0.10, 0.05, 0.30, 2.0, 271), 0.0)
	s["myria_plant"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.crack(0.04, 0.34, 560.0, 272),
		AudioDsp.thud(140.0, 0.14, 0.28), 0.0), AudioDsp.mix(
		AudioDsp.bell(880.0, 0.26, 0.16),
		AudioDsp.noise_burst(0.20, 0.10, 0.26, 1.8, 273), 0.0), 0.0)
	s["myria_drift"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.whoosh(0.20, 0.36, 900.0, 2600.0, 1.0, 278),
		AudioDsp.bell(1174.0, 0.18, 0.14), 0.0),
		AudioDsp.noise_burst(0.14, 0.05, 0.22, 2.0, 279), 0.0)
	s["myria_bloom"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(587.0, 0.46, 0.28),
		AudioDsp.shimmer(0.52, 1174.0, 0.11, 274), 0.02), AudioDsp.mix(
		AudioDsp.whoosh(0.34, 0.28, 500.0, 2200.0, 0.9, 275),
		AudioDsp.sub_thump(90.0, 0.22, 0.22), 0.0), 0.0)
	s["myria_garden"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.bell(392.0, 0.80, 0.28),
		AudioDsp.bell(587.0, 0.62, 0.18), 0.09), AudioDsp.mix(
		AudioDsp.shimmer(0.86, 1174.0, 0.11, 276),
		AudioDsp.whoosh(0.70, 0.24, 400.0, 1800.0, 0.7, 277), 0.02), 0.0)
	return s


## Musiikkicuet: lyhyet motiivit, jotka soivat omalla MusicCue-väylällään
## samalla kun taustamusiikki duckataan hetkeksi niiden alta.
static func cue_batch() -> Dictionary:
	var s := {}
	# Ottelun alku: nouseva kvartti + matala isku.
	s["cue_match_start"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.16, 196.0, 196.0, "tri"], [0.16, 262.0, 262.0, "tri"],
			[0.42, 392.0, 392.0, "sine"]], 0.20),
		AudioDsp.sub_thump(49.0, 0.70, 0.30), 0.0),
		AudioDsp.bell(784.0, 0.62, 0.14), 0.30)
	# Ensiveri: kaksi terävää nousevaa askelta.
	s["cue_first_blood"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.13, 233.0, 233.0, "saw"], [0.34, 349.0, 349.0, "saw"]], 0.17),
		AudioDsp.sub_thump(58.0, 0.50, 0.30), 0.0),
		AudioDsp.metal_ring(699.0, 0.44, 0.13), 0.10)
	# Objective herää: kolmen sävelen laskeva varoitus.
	s["cue_objective"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.20, 294.0, 294.0, "tri"], [0.20, 247.0, 247.0, "tri"],
			[0.48, 185.0, 185.0, "saw"]], 0.18),
		AudioDsp.tone(0.90, 62.0, 49.0, "sine", 0.03, 0.66, 0.26), 0.0),
		AudioDsp.whoosh(0.60, 0.10, 260.0, 1600.0, 0.7, 3001), 0.10)
	# Objective vallattu: kirkas voittosointu.
	s["cue_objective_taken"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.14, 392.0, 392.0, "tri"], [0.14, 523.0, 523.0, "tri"],
			[0.44, 784.0, 784.0, "sine"]], 0.19),
		AudioDsp.bell(1046.0, 0.70, 0.20), 0.10),
		AudioDsp.shimmer(0.76, 1568.0, 0.09, 3002), 0.14)
	# Nexus avattu: uhkaava laskeva urku + subisku.
	s["cue_nexus"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.20, 233.0, 233.0, "saw"], [0.20, 185.0, 185.0, "saw"],
			[0.62, 123.0, 123.0, "saw"]], 0.18),
		AudioDsp.sub_thump(41.0, 1.10, 0.34), 0.0),
		AudioDsp.metal_ring(123.0, 0.95, 0.16), 0.06)
	# Voitto: nouseva duurifanfaari.
	s["cue_victory"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.15, 392.0, 392.0, "tri"], [0.15, 523.0, 523.0, "tri"],
			[0.15, 659.0, 659.0, "tri"], [0.60, 784.0, 784.0, "square"]], 0.18),
		AudioDsp.bell(1568.0, 1.10, 0.22), 0.06),
		AudioDsp.shimmer(1.15, 2093.0, 0.09, 3003), 0.12)
	# Tappio: laskeva mollikadenssi.
	s["cue_defeat"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.22, 349.0, 349.0, "tri"], [0.22, 294.0, 294.0, "tri"],
			[0.70, 220.0, 220.0, "sine"]], 0.18),
		AudioDsp.tone(1.15, 55.0, 44.0, "sine", 0.05, 0.85, 0.26), 0.0),
		AudioDsp.metal_ring(220.0, 0.85, 0.10), 0.20)
	# Tier-ylennys: pisin ja juhlavin motiivi (promo-cinematic).
	s["cue_promo_tier"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.14, 262.0, 262.0, "tri"], [0.14, 392.0, 392.0, "tri"],
			[0.14, 523.0, 523.0, "tri"], [0.14, 659.0, 659.0, "square"],
			[0.72, 1046.0, 1046.0, "square"]], 0.17),
		AudioDsp.bell(2093.0, 1.30, 0.22), 0.10), AudioDsp.mix(
		AudioDsp.sub_thump(44.0, 1.05, 0.32),
		AudioDsp.shimmer(1.40, 2093.0, 0.10, 3004), 0.06), 0.0)
	# Divisioonanousu: sama kieli, lyhyempi ja pehmeämpi.
	s["cue_promo_div"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.seq([[0.12, 392.0, 392.0, "sine"], [0.34, 587.0, 587.0, "sine"]], 0.19),
		AudioDsp.bell(1174.0, 0.66, 0.20), 0.04),
		AudioDsp.shimmer(0.72, 1760.0, 0.08, 3005), 0.08)
	return s
