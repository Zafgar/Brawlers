class_name BotNames
## Bottien nimigeneraattori. Botit eivät ole "Botti 3" vaan oikean tuntuisia
## pelaajanimimerkkejä: suomalaisväritteistä fantasiaa ja gamer-tageja
## sekaisin ("Routavasara", "KaijuKing", "Sirpale_77", "Yölepakko").
##
## Nimet kootaan tavu-/sanataulukoista useaa kaavaa käyttäen, joten
## yhdistelmiä on kymmeniä tuhansia — muutaman sadan botin populaatio saa
## helposti pelkkiä uniikkeja nimiä. Generointi käyttää siemennettyä
## RandomNumberGeneratoria, joten sama siemen tuottaa aina saman listan
## (populaatio pysyy samana ennen kuin se tallennetaan).

# Yhdyssanan etuosat (suomalainen fantasia).
const FI_HEAD := [
	"Routa", "Yö", "Halla", "Tuli", "Jää", "Usva", "Kuura", "Salama",
	"Myrsky", "Kivi", "Rauta", "Terä", "Varjo", "Sumu", "Ukkos", "Louhi",
	"Aamu", "Ilta", "Talvi", "Kevät", "Kalma", "Veri", "Hopea", "Kulta",
	"Pohjan", "Tuhka", "Kaiku", "Vaski", "Kuu", "Meri", "Koski", "Karhu",
	"Susi", "Kotka", "Korppi", "Ilves", "Peto", "Vala", "Loitsu", "Noita",
	"Sampo", "Vasara", "Kirves", "Nuoli", "Jousi", "Kilpi", "Panssari",
	"Revontuli", "Tuisku", "Ahma",
]

# Yhdyssanan jälkiosat (kirjoitetaan pienellä, isketään etuosan perään).
const FI_TAIL := [
	"vasara", "kirves", "terä", "myrsky", "sydän", "veitsi", "lepakko",
	"susi", "karhu", "kotka", "korppi", "haukka", "ilves", "peto", "henki",
	"varjo", "valo", "tuli", "jää", "routa", "koski", "virta", "tuuli",
	"sade", "salama", "ukkonen", "kuiskaus", "huuto", "laulu", "jälki",
	"poltto", "isku", "veto", "murska", "hammas", "kynsi", "siipi", "sarvi",
	"kilpi", "muuri", "portti", "silta", "torni", "linna", "soihtu",
	"lyhty", "lanka", "verkko", "ansa", "koura",
]

# Yksinään toimivat sanat (numerohännällä varustettaviksi).
const FI_SOLO := [
	"Sirpale", "Kipinä", "Riimu", "Kaiku", "Hehku", "Vimma", "Raivo",
	"Routa", "Usva", "Myrsky", "Salama", "Louhi", "Kalma", "Tuisku",
	"Ahma", "Kärppä", "Hiisi", "Peikko", "Haltia", "Velho", "Soturi",
	"Vartija", "Metsästäjä", "Kulkuri", "Vaeltaja", "Ritari", "Airut",
	"Jäänmurtaja", "Kuutamo", "Revontuli", "Pohjantähti", "Aamutähti",
	"Iltarusko", "Karhunkierros", "Susilauma", "Tulikettu", "Haltiakivi",
	"Untuvikko", "Vanhaparta", "Kaihonkantaja",
]

# Gamer-tagin etuosat.
const EN_HEAD := [
	"Kaiju", "Neon", "Cyber", "Ghost", "Void", "Turbo", "Hyper", "Frost",
	"Blaze", "Storm", "Shadow", "Iron", "Steel", "Toxic", "Rapid", "Silent",
	"Savage", "Crimson", "Golden", "Alpha", "Omega", "Zero", "Nova",
	"Astro", "Pixel", "Quantum", "Vortex", "Rogue", "Prime", "Apex",
	"Lunar", "Solar", "Static", "Venom", "Chrome", "Grim", "Wild", "Dusk",
	"Dawn", "Sonic",
]

# Gamer-tagin jälkiosat.
const EN_TAIL := [
	"King", "Lord", "Wolf", "Fang", "Blade", "Storm", "Strike", "Hunter",
	"Slayer", "Reaper", "Rider", "Breaker", "Smith", "Ghost", "Shot",
	"Sniper", "Mage", "Knight", "Titan", "Beast", "Phantom", "Warden",
	"Bolt", "Fury", "Rush", "Core", "Byte", "Wave", "Claw", "Spike",
	"Viper", "Hawk", "Raven", "Bear", "Drake", "Crown", "Ace", "Nova",
	"Pulse", "Zone",
]

# Kaavojen painot (summa 100). Suomalainen yhdyssana on yleisin, mutta
# joukossa on reilusti gamer-tageja ja numerohäntiä.
const PATTERN_WEIGHTS := [26, 22, 14, 12, 10, 8, 8]
const RETRIES := 24              # törmäysyritykset ennen numerohännän lisäystä


## Alkukirjain isoksi ilman Godotin capitalize()-erikoisuuksia (se pilkkoisi
## sanan välilyönneillä).
static func _cap(word: String) -> String:
	if word == "":
		return word
	return word.substr(0, 1).to_upper() + word.substr(1)


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return str(list[rng.randi_range(0, list.size() - 1)])


## Painotettu kaavan valinta 0..PATTERN_WEIGHTS.size()-1.
static func _pattern(rng: RandomNumberGenerator) -> int:
	var total := 0
	for weight in PATTERN_WEIGHTS:
		total += int(weight)
	var roll: int = rng.randi_range(0, total - 1)
	for i in range(PATTERN_WEIGHTS.size()):
		roll -= int(PATTERN_WEIGHTS[i])
		if roll < 0:
			return i
	return 0


## Yksi nimi ilman uniikkiustarkistusta.
static func compose(rng: RandomNumberGenerator) -> String:
	match _pattern(rng):
		0:
			# "Routavasara", "Yölepakko"
			return _pick(rng, FI_HEAD) + _pick(rng, FI_TAIL)
		1:
			# "KaijuKing", "FrostReaper"
			return _pick(rng, EN_HEAD) + _pick(rng, EN_TAIL)
		2:
			# "Sirpale_77"
			return "%s_%d" % [_pick(rng, FI_SOLO), rng.randi_range(10, 99)]
		3:
			# "RoutaBlade"
			return _pick(rng, FI_HEAD) + _pick(rng, EN_TAIL)
		4:
			# "NeonMyrsky"
			return _pick(rng, EN_HEAD) + _cap(_pick(rng, FI_TAIL))
		5:
			# "Yölepakko88"
			return "%s%s%d" % [_pick(rng, FI_HEAD), _pick(rng, FI_TAIL),
				rng.randi_range(10, 99)]
		_:
			# "RiimuReaper"
			return _pick(rng, FI_SOLO) + _pick(rng, EN_TAIL)


## Yksi UNIIKKI nimi: merkitsee sen used-sanakirjaan. Jos törmäyksiä tulee
## liikaa, nimeen liitetään numerohäntä jotta funktio päättyy aina.
static func make_one(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for attempt in range(RETRIES):
		var candidate := compose(rng)
		if not used.has(candidate):
			used[candidate] = true
			return candidate
	var base := compose(rng)
	var suffix: int = rng.randi_range(100, 9999)
	while used.has("%s%d" % [base, suffix]):
		suffix += 1
	var unique: String = "%s%d" % [base, suffix]
	used[unique] = true
	return unique


## count kappaletta uniikkeja nimiä. Sama siemen -> sama lista.
static func generate(count: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var used: Dictionary = {}
	var names: Array = []
	for i in range(maxi(count, 0)):
		names.append(make_one(rng, used))
	return names


## Nimiehdotuksia käyttäjätilin luontiin (satunnainen siemen joka kutsulla).
static func suggestions(count := 6) -> Array:
	return generate(count, int(Time.get_unix_time_from_system()) + randi())
