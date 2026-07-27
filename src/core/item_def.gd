class_name ItemDef
## MOBA-itemien staattinen katalogi ja osto-apurit. Kauppa-UI (Phase B),
## sankarin statimoottori ja bottien ostologiikka lukevat kaikki samaa
## katalogia, jotta hinnat ja statit pysyvät varmasti samassa linjassa.
##
## Hinnat ovat KOKONAISARVOJA: yhdistelmän hinta = cost - yhdistelmään
## kuluvien, jo omistettujen komponenttien arvo (combine_cost). Statit ovat
## osuuksia ellei toisin mainita; armor/mr ovat KIINTEITÄ pisteitä ja
## hp/gold_per_sec kiinteitä arvoja.
##
## Legendat vaativat Baron-artefaktin (require_artifact) — poiminta on
## LegendaryArtifactissa; osto kuluttaa artefaktin.
##
## LEGENDOJEN HINTA ON TARKISTETTU EIKÄ SITÄ MUUTETTU (130 ottelun ladder:
## 119 artefaktipudotusta, 3 valmistunutta legendaa, 96 % hukkaan). Laskelma
## oikeilla kultakäyrillä: sankarin GPM on tierin mukaan 850–1400, joten 2400 g
## on 1.7–2.8 minuutin tulo. Ottelun keskipituus on 17:42 ja Baron herää 3:00,
## joten hinta EI ole pullonkaula — pullonkaula oli se, ettei ostologiikka
## säästänyt legendaan lainkaan (Hero._bot_shop otti legendan tavoitelistalle
## vain jos koko 2400 g sattui jo olemaan lompakossa, mutta runkobuild valutti
## lompakon joka sekunti 300–1050 g:n paloihin). Hinnan laskeminen olisi vain
## siirtänyt saman virheen halvemmaksi. Legendan statiarvo commonien
## yksikköhinnoilla on 2400–3300 g, eli 2400 g + kiistelty tavoite on jo
## reilusti pelaajan puolella oleva hinta.
##
## TALOUS -> VOIMA (mitattu ongelma: ottelut päättyivät aikakattoon vaikka
## voittava puoli johti kultaa 11-33 %): epicien ja legendojen HYÖKKÄYSrivit
## (attack / ap / attack_speed / crit / armor_pen) nostettiin noin 15 %.
## Puolustusrivejä (hp/armor/mr) EI kasvatettu — muuten meta muuttuisi
## kestämiseksi ja pelit venyisivät entisestään. Commonit ja raret pidettiin
## ennallaan, jotta alkupeli pysyy luettavana.
## Sama hyökkäysvoima kertautuu rakennuksia vastaan (Structure.take_damage),
## joten itemijohto näkyy suoraan piiritysnopeutena.
##
## TUKIRIVIN KORJAUS (72 ottelun mittaus): tukilinja oli pelin huonoin.
## Airutlyhty 18.3 % voittoja / kulta-teho 1567, Kolikkotalismaani 26.1 % / 1578,
## Vartiolyhty 44.4 % / 1826 — kun otannan epic-keskiarvo oli 3314 ja parhaat
## (Torjuntakupu 4106, Riistanraatelija 3879) yli kaksinkertaisia.
##
## SYY EI OLLUT HINTA VAAN MUUNNOS: raportin kulta-teho = 1000 * (vahinko +
## parannus + vaimennettu) / käytetty kulta. Tuen vanhat statit (cdr,
## mana_regen, gold_per_sec, assist_gold) EIVÄT tuota yhtään noista kolmesta —
## ne vain sallivat useamman loitsun, ja kun loitsut olivat pieniä, useampi
## kerta ei ollut mitään. Tuki muutti kultansa tyhjäksi.
##
## KORJAUS: jokainen tukitavara kantaa nyt vähintään yhtä TUOTOSSTATTIA
## (heal_power, ap) tai jakaa kilpiä suoraan (aurat, aktiivi). Kilpi kirjautuu
## antajalle (Hero.take_damage -> prevented), joten tuen panos näkyy sekä
## pelissä että telemetriassa. Voima tulee MAHDOLLISTAMISESTA (parannuksen ja
## kilven vahvistus, puolustus, kontrolli), ei raakavahingosta — tuki ei saa
## muuttua kantajaksi.
##
## heal_power = uusi statiavain: vahvistaa haltijan MUILLE antamia parannuksia
## ja kilpiä (Hero.heal_hp / Hero.add_shield). Ei vaikuta omaan elämänimuun,
## jottei tukitavaroista tule tankkien itsekestoa.
##
## Statien kultahinnat (johdettu commoneista) tuotosmallia varten:
##   1 % attack/ap 44 g · 1 % cdr 60 g · 1 % ms 75 g · 1 HP 3.3 g ·
##   1 panssari/taikavastus 30 g · 1 % mana_regen 12 g · 1 % heal_power 25 g.
## 1 % heal_power tuottaa tuelle, joka antaa ~7000 parannusta+kilpeä ottelussa,
## noin 70 tuotosta = 2.8 tuotosta per kulta — samaa luokkaa kuin 1 % attack
## kantajalle (140 tuotosta / 44 g = 3.2). ap on tuelle heikko (pieni
## vahinkopohja), joten sitä annetaan vain Hoivasydämelle.

const ITEMS := {
	# --- Common (~300-400 g) ---
	"veitsi": {
		"name": "Veitsi", "tier": "common", "cost": 350, "builds_from": [],
		"stats": {"attack": 0.08}, "passive": "", "active": "",
		"desc": "+8 % perusvahinko", "role_hint": "carry",
	},
	"sirpalesauva": {
		"name": "Sirpalesauva", "tier": "common", "cost": 350, "builds_from": [],
		"stats": {"ap": 0.08}, "passive": "", "active": "",
		"desc": "+8 % kykyvahinko", "role_hint": "ap",
	},
	"nahkakilpi": {
		"name": "Nahkakilpi", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"armor": 10.0}, "passive": "", "active": "",
		"desc": "+10 panssaria", "role_hint": "tank",
	},
	"harmaaviitta": {
		"name": "Harmaaviitta", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"mr": 10.0}, "passive": "", "active": "",
		"desc": "+10 taikavastusta", "role_hint": "tank",
	},
	"rautahelmi": {
		"name": "Rautahelmi", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"hp": 90.0}, "passive": "", "active": "",
		"desc": "+90 HP", "role_hint": "tank",
	},
	"sulkasaappaat": {
		"name": "Sulkasaappaat", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"ms": 0.04}, "passive": "", "active": "",
		"desc": "+4 % liikenopeus", "role_hint": "any",
	},
	"veripisara": {
		"name": "Veripisara", "tier": "common", "cost": 350, "builds_from": [],
		"stats": {"lifesteal": 0.05}, "passive": "", "active": "",
		"desc": "+5 % elämänimu", "role_hint": "carry",
	},
	"tähtäinlinssi": {
		"name": "Tähtäinlinssi", "tier": "common", "cost": 350, "builds_from": [],
		"stats": {"crit": 0.07}, "passive": "", "active": "",
		"desc": "+7 % kriittinen osuma", "role_hint": "carry",
	},
	"kellojousi": {
		"name": "Kellojousi", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"cdr": 0.05}, "passive": "", "active": "",
		"desc": "-5 % jäähdytykset", "role_hint": "support",
	},
	"manahelmi": {
		"name": "Manahelmi", "tier": "common", "cost": 300, "builds_from": [],
		"stats": {"mana_regen": 0.25}, "passive": "", "active": "",
		"desc": "+25 % manan palautuminen", "role_hint": "ap",
	},
	"riistanveitsi": {
		"name": "Riistanveitsi", "tier": "common", "cost": 350, "builds_from": [],
		"stats": {"jungle_dmg": 0.15}, "passive": "", "active": "",
		"desc": "+15 % vahinko viidakon olentoihin", "role_hint": "jungle",
	},

	# --- Rare (~800-1100 g, kaksi commonia) ---
	"myrskyterä": {
		"name": "Myrskyterä", "tier": "rare", "cost": 900,
		"builds_from": ["veitsi", "veitsi"],
		"stats": {"attack": 0.12, "attack_speed": 0.12},
		"passive": "", "active": "",
		"desc": "+12 % perusvahinko, +12 % hyökkäysnopeus", "role_hint": "carry",
	},
	"verinuoli": {
		"name": "Verinuoli", "tier": "rare", "cost": 950,
		"builds_from": ["veitsi", "veripisara"],
		"stats": {"attack": 0.10, "lifesteal": 0.08},
		"passive": "", "active": "",
		"desc": "+10 % perusvahinko, +8 % elämänimu", "role_hint": "carry",
	},
	"kaksoislinssi": {
		"name": "Kaksoislinssi", "tier": "rare", "cost": 950,
		"builds_from": ["tähtäinlinssi", "tähtäinlinssi"],
		"stats": {"crit": 0.15, "attack": 0.06},
		"passive": "", "active": "",
		"desc": "+15 % kriittinen osuma, +6 % perusvahinko", "role_hint": "carry",
	},
	"runosauva": {
		"name": "Runosauva", "tier": "rare", "cost": 950,
		"builds_from": ["sirpalesauva", "sirpalesauva"],
		"stats": {"ap": 0.16},
		"passive": "", "active": "",
		"desc": "+16 % kykyvahinko", "role_hint": "ap",
	},
	"virtakide": {
		"name": "Virtakide", "tier": "rare", "cost": 900,
		"builds_from": ["sirpalesauva", "manahelmi"],
		"stats": {"ap": 0.10, "mana_regen": 0.5},
		"passive": "", "active": "",
		"desc": "+10 % kykyvahinko, +50 % manan palautuminen", "role_hint": "ap",
	},
	"muuripala": {
		"name": "Muuripala", "tier": "rare", "cost": 900,
		"builds_from": ["nahkakilpi", "rautahelmi"],
		"stats": {"hp": 140.0, "armor": 14.0},
		"passive": "", "active": "",
		"desc": "+140 HP, +14 panssaria", "role_hint": "tank",
	},
	"loitsulukko": {
		"name": "Loitsulukko", "tier": "rare", "cost": 900,
		"builds_from": ["harmaaviitta", "rautahelmi"],
		"stats": {"hp": 120.0, "mr": 16.0},
		"passive": "", "active": "",
		"desc": "+120 HP, +16 taikavastusta", "role_hint": "tank",
	},
	"elonjuuri": {
		"name": "Elonjuuri", "tier": "rare", "cost": 850,
		"builds_from": ["rautahelmi", "rautahelmi"],
		"stats": {"hp": 200.0, "hp_regen": 0.5},
		"passive": "", "active": "",
		"desc": "+200 HP, +50 % elämän palautuminen", "role_hint": "tank",
	},
	# Airutlyhty oli 850 g:n kuollut osto: pelkkää jäähdytystä, manaa ja kultaa,
	# eli nolla tuotosta. Nyt sama talousidentiteetti mutta mukana runko (HP) ja
	# ensimmäinen hoivateho — tuen avausostosta tulee heti mitattavaa hyötyä.
	"airutlyhty": {
		"name": "Airutlyhty", "tier": "rare", "cost": 850,
		"builds_from": ["kellojousi", "manahelmi"],
		"stats": {"cdr": 0.06, "mana_regen": 0.3, "hp": 150.0,
			"heal_power": 0.10, "gold_per_sec": 0.4},
		"passive": "", "active": "",
		"desc": "-6 % jäähdytykset, +30 % manan palautuminen, +150 HP, +10 % hoivateho, +0.4 kultaa/s",
		"role_hint": "support",
	},
	"ajojahti": {
		"name": "Ajojahti", "tier": "rare", "cost": 900,
		"builds_from": ["riistanveitsi", "sulkasaappaat"],
		"stats": {"jungle_dmg": 0.25, "ms": 0.05},
		"passive": "", "active": "",
		"desc": "+25 % viidakkovahinko, +5 % liikenopeus", "role_hint": "jungle",
	},

	# --- Epic: carry ---
	"myrskynsilma": {
		"name": "Myrskynsilmä", "tier": "epic", "cost": 2300,
		"builds_from": ["myrskyterä", "veitsi"],
		"stats": {"attack": 0.23, "attack_speed": 0.29},
		"passive": "ketjusalama", "active": "",
		"desc": "Ketjusalama: joka 4. perusosuma sinkoaa 35 % vahingosta lähimpään toiseen viholliseen",
		"role_hint": "carry",
	},
	"verikuu": {
		"name": "Verikuu", "tier": "epic", "cost": 2300,
		"builds_from": ["verinuoli", "veripisara"],
		"stats": {"attack": 0.21, "lifesteal": 0.12},
		"passive": "verikuu", "active": "",
		"desc": "Verikuu: alle 35 % HP:llä elämänimu tuplaantuu",
		"role_hint": "carry",
	},
	"teräsarmä": {
		"name": "Teräsärmä", "tier": "epic", "cost": 2400,
		"builds_from": ["kaksoislinssi", "veitsi"],
		"stats": {"attack": 0.17, "crit": 0.23},
		"passive": "panssarinmurskain", "active": "",
		"desc": "Panssarinmurskain: kritit repivät 20 % kohteen panssarista 3 s ajaksi",
		"role_hint": "carry",
	},

	# --- Epic: tank ---
	"jäätikkövyö": {
		"name": "Jäätikkövyö", "tier": "epic", "cost": 2200,
		"builds_from": ["muuripala", "nahkakilpi"],
		"stats": {"hp": 300.0, "armor": 28.0},
		"passive": "huurre", "active": "",
		"desc": "Huurre: osuman ottaminen hidastaa lyöjää 12 % 1.2 s ajan",
		"role_hint": "tank",
	},
	"torjuntakupu": {
		"name": "Torjuntakupu", "tier": "epic", "cost": 2200,
		"builds_from": ["loitsulukko", "harmaaviitta"],
		"stats": {"hp": 220.0, "mr": 30.0},
		"passive": "loitsukilpi", "active": "",
		"desc": "Loitsukilpi: torjuu 40 % seuraavan kyvyn vahingosta 8 s välein",
		"role_hint": "tank",
	},
	"elonlähde": {
		"name": "Elonlähde", "tier": "epic", "cost": 2100,
		"builds_from": ["elonjuuri", "rautahelmi"],
		# HP 340 -> 280 budjettitarkistuksessa: tankkisetin yhteis-HP pysyy
		# ~800:ssa (300 + 220 + 280), muuten setti ylitti budjetin selvästi.
		"stats": {"hp": 280.0, "hp_regen": 1.0},
		"passive": "elinvoima", "active": "",
		"desc": "Elinvoima: elämän palautuminen toimii taistelussakin 50 % teholla",
		"role_hint": "tank",
	},

	# --- Epic: support ---
	# Kolikkotalismaani säilyttää talousidentiteetin (kulta + avustuskulta),
	# mutta palkkio-passiivi antaa nyt myös kilpiauran: 8 s välein kilpi
	# lähiliittolaisille. Aura tuottaa vaimennusta = mitattavaa arvoa, ja se
	# on tuen ainoa "taistele lähellä joukkuetta" -palkinto.
	"kolikkotalismaani": {
		"name": "Kolikkotalismaani", "tier": "epic", "cost": 2100,
		"builds_from": ["airutlyhty", "kellojousi"],
		"stats": {"cdr": 0.10, "hp": 240.0, "heal_power": 0.15,
			"gold_per_sec": 1.0, "assist_gold": 0.5},
		"passive": "palkkio", "active": "",
		"desc": "Palkkio: lähellä kaatuva minioni antaa 2 kultaa ilman last hitiä; 8 s välein 55 kilpeä lähiliittolaisille",
		"role_hint": "support",
	},
	# Vartiolyhty oli 2100 g pelkästä minimap-vartijasta. Vartija on nyt myös
	# taisteluväline: asetuspulssi kilpiää lähiliittolaiset ja lyhty itse
	# kilpiää läheisiä liittolaisia koko 60 s elinaikansa (Ward._pulse).
	"vartiolyhty": {
		"name": "Vartiolyhty", "tier": "epic", "cost": 2100,
		"builds_from": ["airutlyhty", "manahelmi"],
		"stats": {"cdr": 0.10, "mana_regen": 0.5, "hp": 260.0, "heal_power": 0.12},
		"passive": "", "active": "vartija",
		"desc": "Vartija: aseta tähystäjä joka kilpiää liittolaisia — asetus antaa 80 kilpeä lähelle, lyhty 45 kilpeä 6 s välein",
		"role_hint": "support",
	},
	# Hoivasydämen +20 % on nyt näkyvä statti (heal_power) eikä piilotettu
	# erikoistapaus — sama kerroin, mutta se lukee kaupassa ja tietonäkymässä.
	"hoivasydän": {
		"name": "Hoivasydän", "tier": "epic", "cost": 2200,
		"builds_from": ["virtakide", "rautahelmi"],
		"stats": {"ap": 0.15, "mana_regen": 0.4, "hp": 220.0, "heal_power": 0.22},
		"passive": "hoiva", "active": "",
		"desc": "Hoiva: avustus parantaa sinua 8 % max HP:sta; hoivateho vahvistaa kaikkia antamiasi parannuksia ja kilpiä",
		"role_hint": "support",
	},

	# --- Epic: ap ---
	"arkkisauva": {
		"name": "Arkkisauva", "tier": "epic", "cost": 2400,
		"builds_from": ["runosauva", "sirpalesauva"],
		"stats": {"ap": 0.35},
		"passive": "momentum", "active": "",
		"desc": "Momentum: kykyosuma sankariin +1 % kykyvahinko (max 10, nollautuu kuollessa)",
		"role_hint": "ap",
	},
	"kaikukide": {
		"name": "Kaikukide", "tier": "epic", "cost": 2300,
		"builds_from": ["runosauva", "kellojousi"],
		"stats": {"ap": 0.21, "cdr": 0.12},
		"passive": "kaiku", "active": "",
		"desc": "Kaiku: joka 3. kykyosuma toistaa 30 % vahingosta",
		"role_hint": "ap",
	},
	"manaydin": {
		"name": "Manaydin", "tier": "epic", "cost": 2200,
		"builds_from": ["virtakide", "manahelmi"],
		"stats": {"ap": 0.17, "mana_regen": 1.0},
		"passive": "ylivuoto", "active": "",
		"desc": "Ylivuoto: kyvyt maksavat 15 % vähemmän resurssia",
		"role_hint": "ap",
	},

	# --- Epic: jungle ---
	"riistanraatelija": {
		"name": "Riistanraatelija", "tier": "epic", "cost": 2100,
		"builds_from": ["ajojahti", "riistanveitsi"],
		"stats": {"jungle_dmg": 0.5, "attack": 0.12},
		"passive": "saalistaja", "active": "",
		"desc": "Saalistaja: leiribuffit kestävät +40 %; leirin kaato parantaa 8 % max HP",
		"role_hint": "jungle",
	},
	"varjoviitta": {
		"name": "Varjoviitta", "tier": "epic", "cost": 2300,
		"builds_from": ["ajojahti", "sulkasaappaat"],
		"stats": {"ms": 0.07, "attack": 0.14},
		"passive": "", "active": "varjo",
		"desc": "Varjo: 3 sekunnin häive",
		"role_hint": "jungle",
	},
	"ansalanka": {
		"name": "Ansalanka", "tier": "epic", "cost": 2300,
		"builds_from": ["myrskyterä", "riistanveitsi"],
		"stats": {"attack": 0.17, "jungle_dmg": 0.25},
		"passive": "ansa", "active": "",
		"desc": "Ansa: hidastetut/juurrutetut kohteet ottavat sinulta +12 % vahinkoa",
		"role_hint": "jungle",
	},

	# --- Legendary (2400 g + Baron-artefakti) ---
	"kuninkaansurma": {
		"name": "Kuninkaansurma", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"attack": 0.32, "attack_speed": 0.23, "crit": 0.17},
		"passive": "giljotiini", "active": "",
		"desc": "Giljotiini: perusosumat alle 25 % HP:n sankareihin +25 % vahinkoa",
		"role_hint": "carry",
	},
	"maailmanpuu": {
		"name": "Maailmanpuu", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"hp": 450.0, "armor": 30.0, "mr": 30.0},
		"passive": "juurakko", "active": "",
		"desc": "Juurakko: alle 30 % HP:llä juurruttaa lähiviholliset 1 s ja parantaa (1/60 s)",
		"role_hint": "tank",
	},
	"aamunkoitto": {
		"name": "Aamunkoiton kruunu", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"cdr": 0.15, "gold_per_sec": 1.5, "assist_gold": 0.75, "hp": 200.0,
			"heal_power": 0.20},
		"passive": "koitto", "active": "",
		"desc": "Koitto: parantamasi tai kilpesi saanut liittolainen saa +15 % vauhtia 2 s",
		"role_hint": "support",
	},
	"tyhjyydenydin": {
		"name": "Tyhjyyden ydin", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"ap": 0.40, "cdr": 0.15, "mana_regen": 0.6},
		"passive": "tyhjyys", "active": "",
		"desc": "Tyhjyys: sankaritappo/avustus palauttaa 40 ult-latausta ja nollaa kyvyt",
		"role_hint": "ap",
	},
	"alfaturkki": {
		"name": "Alfapedon turkki", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"attack": 0.23, "ms": 0.10, "jungle_dmg": 0.6},
		"passive": "alfa", "active": "",
		"desc": "Alfa: +50 % vahinko Baroniin/Dragoniin; leirin kaato lataa hidasteosuman",
		"role_hint": "jungle",
	},
}


static func get_item(id: String) -> Dictionary:
	var item: Dictionary = ITEMS.get(id, {})
	return item


## Tierin itemit roolivihjeen mukaan, halvin ensin (tasatilanne katalogin
## järjestyksessä = determinismi). role_hint = "" palauttaa koko tierin.
static func tier_ids(tier: String, role_hint := "") -> Array:
	var out: Array = []
	for id_v in ITEMS:
		var id: String = str(id_v)
		var item: Dictionary = ITEMS[id]
		if str(item.get("tier", "")) != tier:
			continue
		if role_hint != "" and str(item.get("role_hint", "")) != role_hint:
			continue
		out.append(id)
	out.sort_custom(func(x, y): return int(get_item(str(x)).get("cost", 0)) \
		< int(get_item(str(y)).get("cost", 0)))
	return out


## TALOUSKORJAUS (130 ottelun ladder: käyttämätön kulta ottelun lopussa top
## 1024 / jungle 1717 / bottom 951 / support 1232 g). Bottien runkobuild
## (BotBrain._item_build) on vain KOLME epicia = 6400–7000 g, mutta telakassa
## on kuusi paikkaa ja ottelun tulot ovat moninkertaiset. Kun runko valmistui,
## ostotavoite tyhjeni ja botti lopetti ostamisen kokonaan. Sama näkyy
## mittauksessa: mitä halvempi rungon hinta, sitä enemmän kultaa jäi käteen
## (halvin tuki 6400 g -> 1232 g, kallein carry 7000 g -> 951 g).
##
## Jatkobuild täyttää loput kolme paikkaa: ensin roolin omat epicit, sitten
## TANKKIEPICIT (HP/panssari/taikavastus hyödyttää jokaista roolia) ja lopuksi
## carry-/ap-epicit. Tuki- ja viidakkoepicit jätetään pois muilta rooleilta:
## niiden arvo (kultatulo, avustuskulta, leirivahinko) ei realisoidu väärässä
## roolissa, joten ne olisivat vain toisenlainen tapa hukata kulta.
static func extended_build(role_hint: String) -> Array:
	var out: Array = []
	for group in [role_hint, "tank", "carry", "ap"]:
		var group_role: String = str(group)
		if group_role == "":
			continue
		for id_v in tier_ids("epic", group_role):
			var id: String = str(id_v)
			if not out.has(id):
				out.append(id)
	return out


static func all_ids() -> Array:
	return ITEMS.keys()


## Ostohinta kun omistetut komponentit hyvitetään: cost - yhdistelmään kuluvien
## omistettujen komponenttien kokonaisarvot. Kukin omistettu item hyvitetään
## vain kerran (components_consumed hoitaa kulutuslaskennan).
static func combine_cost(id: String, owned: Array) -> int:
	var item := get_item(id)
	if item.is_empty():
		return 0
	var total: int = item.get("cost", 0)
	for comp in components_consumed(id, owned):
		total -= int(get_item(str(comp)).get("cost", 0))
	return maxi(total, 0)


## Yhdistelmään kuluvat omistetut komponentit (id-lista). Puuttuvan komponentin
## tilalta hyvitetään rekursiivisesti sen omistetut alikomponentit.
static func components_consumed(id: String, owned: Array) -> Array:
	var remaining: Array = owned.duplicate()
	var consumed: Array = []
	var comps: Array = get_item(id).get("builds_from", [])
	for comp in comps:
		_consume_into(str(comp), remaining, consumed)
	return consumed


## Kuluttaa yhden komponentin omistetuista: suora osuma tai sen omistetut
## alikomponentit. remaining estää saman itemin hyvittämisen kahdesti.
static func _consume_into(comp: String, remaining: Array, consumed: Array) -> void:
	if remaining.has(comp):
		remaining.erase(comp)
		consumed.append(comp)
		return
	var subs: Array = get_item(comp).get("builds_from", [])
	for sub in subs:
		_consume_into(str(sub), remaining, consumed)


## Seuraava ostos kohti tavoitetta: itse tavoite jos yhdistelmään on varaa,
## muuten halvin puuttuva komponentti johon on varaa (rekursio raroihin ja
## niiden commoneihin). "" = mihinkään ei ole varaa.
static func next_purchase(goal_id: String, owned: Array, wallet: int) -> String:
	var goal := get_item(goal_id)
	if goal.is_empty() or owned.has(goal_id):
		return ""
	if combine_cost(goal_id, owned) <= wallet:
		return goal_id
	var remaining: Array = owned.duplicate()
	var comps: Array = goal.get("builds_from", [])
	var best := ""
	var best_cost := 0
	for comp_v in comps:
		var comp := str(comp_v)
		if remaining.has(comp):
			remaining.erase(comp)   # jo omistettu komponentti ei ole ostotarve
			continue
		# Rekursioon annetaan remaining (ei owned): kun resepti vaatii samaa
		# komponenttia kahdesti ja yksi on jo omistettu, TOINEN kappale on yhä
		# ostotarve — muuten botti jäi säästämään suoraan yhdistelmään.
		var pick := next_purchase(comp, remaining, wallet)
		if pick == "":
			continue
		var pick_cost := combine_cost(pick, remaining)
		if best == "" or pick_cost < best_cost:
			best = pick
			best_cost = pick_cost
	return best
