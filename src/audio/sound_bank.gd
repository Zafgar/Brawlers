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
	s["hit"] = AudioDsp.mix(
		AudioDsp.tone(0.08, 220.0, 140.0, "tri", 0.002, 0.05, 0.42),
		AudioDsp.noise_burst(0.06, 0.22, 0.4, 1.0, 1028), 0.0)
	s["swing"] = AudioDsp.noise_burst(0.12, 0.26, 0.75, 1.0, 1035)
	s["slam"] = AudioDsp.mix(
		AudioDsp.tone(0.25, 90.0, 50.0, "sine", 0.005, 0.18, 0.5),
		AudioDsp.noise_burst(0.12, 0.26, 0.3, 1.0, 1042), 0.0)
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
	s["rock"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.35, 0.3, 0.35, 1.0, 1056),
		AudioDsp.tone(0.3, 150.0, 70.0, "tri", 0.005, 0.2, 0.22), 0.0)
	s["fire"] = AudioDsp.mix(
		AudioDsp.tone(0.15, 330.0, 190.0, "saw", 0.01, 0.1, 0.3),
		AudioDsp.noise_burst(0.15, 0.2, 0.5, 1.0, 1063), 0.0)
	s["fire_whoosh"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.32, 0.42, 0.55, 1.0, 1070),
		AudioDsp.tone(0.3, 220.0, 520.0, "saw", 0.02, 0.2, 0.16), 0.0)
	s["inferno"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.9, 0.5, 0.18, 1.0, 1077),
		AudioDsp.tone(0.9, 80.0, 140.0, "saw", 0.05, 0.6, 0.32), 0.0)
	s["bow"] = AudioDsp.mix(
		AudioDsp.tone(0.09, 1200.0, 300.0, "tri", 0.002, 0.06, 0.4),
		AudioDsp.noise_burst(0.03, 0.2, 0.8, 1.0, 1084), 0.0)
	s["bow_charged"] = AudioDsp.mix(
		AudioDsp.tone(0.22, 260.0, 720.0, "saw", 0.01, 0.14, 0.32),
		AudioDsp.tone(0.14, 1500.0, 400.0, "tri", 0.002, 0.1, 0.22), 0.06)
	s["arrow_rain"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.4, 0.28, 0.72, 1.0, 1091),
		AudioDsp.tone(0.4, 1300.0, 320.0, "sine", 0.02, 0.3, 0.13), 0.0)
	s["heal"] = AudioDsp.seq([
		[0.08, 660.0, 660.0, "sine"], [0.08, 880.0, 880.0, "sine"],
		[0.12, 1100.0, 1100.0, "sine"]], 0.3)
	s["light"] = AudioDsp.mix(
		AudioDsp.tone(0.25, 880.0, 880.0, "sine", 0.005, 0.2, 0.28),
		AudioDsp.tone(0.25, 1320.0, 1320.0, "sine", 0.01, 0.2, 0.13), 0.0)
	s["blessing"] = AudioDsp.mix(AudioDsp.seq([
		[0.12, 660.0, 660.0, "sine"], [0.12, 880.0, 880.0, "sine"],
		[0.12, 1100.0, 1100.0, "sine"], [0.3, 1320.0, 1320.0, "sine"]], 0.2),
		AudioDsp.tone(0.6, 440.0, 880.0, "sine", 0.05, 0.45, 0.12), 0.0)
	s["shield"] = AudioDsp.mix(
		AudioDsp.tone(0.15, 440.0, 440.0, "tri", 0.005, 0.1, 0.3),
		AudioDsp.tone(0.15, 660.0, 660.0, "sine", 0.005, 0.1, 0.25), 0.0)
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
	s["dash"] = AudioDsp.noise_burst(0.1, 0.28, 0.7, 1.0, 1098)
	s["disc"] = AudioDsp.mix(
		AudioDsp.tone(0.14, 700.0, 1100.0, "saw", 0.004, 0.09, 0.2),
		AudioDsp.noise_burst(0.09, 0.16, 0.75, 1.0, 1105), 0.03)
	s["smoke"] = AudioDsp.noise_burst(0.3, 0.3, 0.32, 1.0, 1112)
	s["water"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.15, 0.3, 0.5, 1.0, 1119),
		AudioDsp.tone(0.12, 500.0, 900.0, "sine", 0.005, 0.08, 0.13), 0.0)
	s["wave"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.42, 0.4, 0.42, 1.0, 1126),
		AudioDsp.tone(0.38, 300.0, 620.0, "sine", 0.02, 0.28, 0.15), 0.0)
	s["blink"] = AudioDsp.mix(
		AudioDsp.tone(0.12, 880.0, 1760.0, "sine", 0.005, 0.07, 0.35),
		AudioDsp.tone(0.08, 1760.0, 880.0, "sine", 0.01, 0.06, 0.2), 0.1)
	s["blade"] = AudioDsp.mix(
		AudioDsp.tone(0.1, 1700.0, 500.0, "saw", 0.002, 0.06, 0.32),
		AudioDsp.noise_burst(0.05, 0.16, 0.85, 1.0, 1133), 0.0)
	s["zap"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.09, 0.32, 0.95, 1.0, 1140),
		AudioDsp.tone(0.1, 2000.0, 700.0, "square", 0.001, 0.06, 0.2), 0.0)
	s["thunder"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.55, 0.5, 0.22, 1.0, 1147),
		AudioDsp.tone(0.55, 95.0, 48.0, "saw", 0.005, 0.4, 0.32), 0.0)
	s["root"] = AudioDsp.tone(0.2, 130.0, 110.0, "saw", 0.01, 0.12, 0.4)
	s["vine"] = AudioDsp.mix(
		AudioDsp.tone(0.12, 420.0, 90.0, "saw", 0.002, 0.08, 0.32),
		AudioDsp.noise_burst(0.07, 0.24, 0.7, 1.0, 1154), 0.0)
	s["thorns"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.24, 0.36, 0.62, 1.0, 1161),
		AudioDsp.tone(0.2, 200.0, 120.0, "tri", 0.005, 0.15, 0.16), 0.0)
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
	s["minion_melee"] = AudioDsp.mix(
		AudioDsp.tone(0.075, 430.0, 155.0, "tri", 0.001, 0.05, 0.18),
		AudioDsp.noise_burst(0.055, 0.13, 0.75, 1.0, 1175), 0.0)
	s["minion_ranged"] = AudioDsp.mix(
		AudioDsp.tone(0.105, 780.0, 1280.0, "sine", 0.002, 0.07, 0.18),
		AudioDsp.tone(0.08, 390.0, 620.0, "tri", 0.002, 0.05, 0.08), 0.0)
	s["minion_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.07, 960.0, 420.0, "sine", 0.001, 0.05, 0.14),
		AudioDsp.noise_burst(0.045, 0.08, 0.65, 1.0, 1182), 0.0)
	s["minion_down"] = AudioDsp.mix(
		AudioDsp.tone(0.15, 260.0, 90.0, "tri", 0.002, 0.11, 0.18),
		AudioDsp.noise_burst(0.09, 0.12, 0.45, 1.0, 1189), 0.0)
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
	s["tower_guard"] = AudioDsp.mix(
		AudioDsp.tone(0.28, 360.0, 180.0, "tri", 0.002, 0.22, 0.24),
		AudioDsp.tone(0.26, 720.0, 540.0, "sine", 0.004, 0.20, 0.13), 0.015)
	s["tower_crack"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.36, 0.32, 0.30, 1.0, 1210),
		AudioDsp.seq([[0.10, 210.0, 98.0, "tri"], [0.18, 140.0, 52.0, "tri"]], 0.18), 0.0)
	s["tower_destroy"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.82, 88.0, 32.0, "sine", 0.002, 0.66, 0.48),
		AudioDsp.noise_burst(0.72, 0.40, 0.24, 1.0, 1217), 0.0),
		AudioDsp.seq([[0.12, 420.0, 180.0, "tri"], [0.28, 240.0, 72.0, "saw"]], 0.15), 0.05)
	s["nexus_laser"] = AudioDsp.mix(
		AudioDsp.tone(0.24, 1280.0, 340.0, "saw", 0.001, 0.17, 0.25),
		AudioDsp.tone(0.24, 96.0, 62.0, "sine", 0.001, 0.18, 0.33), 0.0)
	s["nexus_guard"] = AudioDsp.mix(
		AudioDsp.tone(0.42, 220.0, 92.0, "tri", 0.003, 0.34, 0.30),
		AudioDsp.tone(0.38, 660.0, 330.0, "sine", 0.006, 0.30, 0.15), 0.02)
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
	s["jungle_small_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.12, 520.0, 145.0, "saw", 0.002, 0.08, 0.18),
		AudioDsp.noise_burst(0.075, 0.18, 0.62, 1.0, 1238), 0.0)
	s["jungle_small_down"] = AudioDsp.mix(
		AudioDsp.tone(0.24, 310.0, 72.0, "tri", 0.002, 0.18, 0.22),
		AudioDsp.noise_burst(0.17, 0.20, 0.34, 1.0, 1245), 0.0)
	s["red_guardian_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.34, 180.0, 62.0, "saw", 0.002, 0.24, 0.30),
		AudioDsp.noise_burst(0.28, 0.29, 0.42, 1.0, 1252), 0.0)
	s["red_guardian_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.23, 125.0, 46.0, "sine", 0.002, 0.17, 0.34),
		AudioDsp.noise_burst(0.19, 0.28, 0.46, 1.0, 1259), 0.0)
	s["red_guardian_down"] = AudioDsp.mix(
		AudioDsp.tone(0.52, 128.0, 38.0, "saw", 0.003, 0.40, 0.34),
		AudioDsp.noise_burst(0.44, 0.34, 0.27, 1.0, 1266), 0.0)
	s["red_buff"] = AudioDsp.mix(AudioDsp.seq([
		[0.10, 220.0, 294.0, "tri"], [0.10, 330.0, 440.0, "tri"],
		[0.24, 523.0, 659.0, "sine"]], 0.23),
		AudioDsp.noise_burst(0.42, 0.14, 0.52, 1.0, 1273), 0.0)
	s["blue_guardian_attack"] = AudioDsp.mix(
		AudioDsp.tone(0.32, 420.0, 1180.0, "sine", 0.002, 0.22, 0.25),
		AudioDsp.tone(0.28, 840.0, 360.0, "tri", 0.003, 0.20, 0.14), 0.025)
	s["blue_guardian_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.24, 1180.0, 310.0, "sine", 0.002, 0.18, 0.24),
		AudioDsp.noise_burst(0.15, 0.16, 0.76, 1.0, 1280), 0.0)
	s["blue_guardian_down"] = AudioDsp.mix(
		AudioDsp.tone(0.55, 880.0, 170.0, "sine", 0.002, 0.44, 0.28),
		AudioDsp.noise_burst(0.34, 0.18, 0.72, 1.0, 1287), 0.0)
	s["blue_buff"] = AudioDsp.mix(AudioDsp.seq([
		[0.10, 440.0, 523.0, "sine"], [0.10, 659.0, 784.0, "sine"],
		[0.28, 1046.0, 1318.0, "sine"]], 0.22),
		AudioDsp.tone(0.46, 220.0, 440.0, "sine", 0.03, 0.34, 0.13), 0.0)
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
	s["luma_pulse"] = AudioDsp.mix(
		AudioDsp.tone(0.18, 980.0, 1420.0, "sine", 0.003, 0.13, 0.25),
		AudioDsp.tone(0.16, 1470.0, 1960.0, "tri", 0.006, 0.12, 0.10), 0.025)
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
	s["ember_pool"] = AudioDsp.mix(
		AudioDsp.tone(0.26, 240.0, 620.0, "saw", 0.008, 0.18, 0.24),
		AudioDsp.noise_burst(0.22, 0.26, 0.58, 1.0, 1420), 0.02)
	s["ember_impact"] = AudioDsp.mix(
		AudioDsp.tone(0.22, 170.0, 72.0, "tri", 0.002, 0.16, 0.32),
		AudioDsp.noise_burst(0.20, 0.34, 0.42, 1.0, 1427), 0.0)
	s["ember_wave"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.38, 0.42, 0.58, 1.0, 1434),
		AudioDsp.tone(0.34, 180.0, 640.0, "saw", 0.015, 0.25, 0.18), 0.0)
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
	s["bramble_ult"] = AudioDsp.mix(
		AudioDsp.noise_burst(0.64, 0.34, 0.48, 1.0, 1476),
		AudioDsp.tone(0.62, 165.0, 420.0, "saw", 0.008, 0.46, 0.22), 0.02)
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
	s["salvo_bunker_open"] = AudioDsp.mix(
		AudioDsp.tone(0.28, 140.0, 390.0, "tri", 0.003, 0.2, 0.25),
		AudioDsp.noise_burst(0.18, 0.20, 0.46, 1.0, 1546), 0.0)
	s["salvo_rocket_launch"] = AudioDsp.mix(
		AudioDsp.tone(0.62, 72.0, 210.0, "saw", 0.01, 0.46, 0.34),
		AudioDsp.noise_burst(0.55, 0.40, 0.26, 1.0, 1553), 0.0)
	s["salvo_rocket_impact"] = AudioDsp.mix(AudioDsp.mix(
		AudioDsp.tone(0.92, 66.0, 28.0, "sine", 0.002, 0.72, 0.55),
		AudioDsp.noise_burst(0.78, 0.50, 0.24, 1.0, 1560), 0.0),
		AudioDsp.tone(0.46, 230.0, 62.0, "saw", 0.002, 0.34, 0.20), 0.015)
	return s
