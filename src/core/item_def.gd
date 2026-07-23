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
## Legendat vaativat Baron-artefaktin (require_artifact) — Phase B toteuttaa
## poiminnan; osto kuluttaa artefaktin.

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
	"airutlyhty": {
		"name": "Airutlyhty", "tier": "rare", "cost": 850,
		"builds_from": ["kellojousi", "manahelmi"],
		"stats": {"cdr": 0.08, "mana_regen": 0.4, "gold_per_sec": 0.5},
		"passive": "", "active": "",
		"desc": "-8 % jäähdytykset, +40 % manan palautuminen, +0.5 kultaa/s",
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
		"stats": {"attack": 0.20, "attack_speed": 0.25},
		"passive": "ketjusalama", "active": "",
		"desc": "Ketjusalama: joka 4. perusosuma sinkoaa 35 % vahingosta lähimpään toiseen viholliseen",
		"role_hint": "carry",
	},
	"verikuu": {
		"name": "Verikuu", "tier": "epic", "cost": 2300,
		"builds_from": ["verinuoli", "veripisara"],
		"stats": {"attack": 0.18, "lifesteal": 0.12},
		"passive": "verikuu", "active": "",
		"desc": "Verikuu: alle 35 % HP:llä elämänimu tuplaantuu",
		"role_hint": "carry",
	},
	"teräsarmä": {
		"name": "Teräsärmä", "tier": "epic", "cost": 2400,
		"builds_from": ["kaksoislinssi", "veitsi"],
		"stats": {"attack": 0.15, "crit": 0.20},
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
	"kolikkotalismaani": {
		"name": "Kolikkotalismaani", "tier": "epic", "cost": 2100,
		"builds_from": ["airutlyhty", "kellojousi"],
		"stats": {"cdr": 0.10, "gold_per_sec": 1.2, "assist_gold": 0.5},
		"passive": "palkkio", "active": "",
		"desc": "Palkkio: lähellä kaatuva minioni antaa 2 kultaa vaikkei last hit osuisi",
		"role_hint": "support",
	},
	"vartiolyhty": {
		"name": "Vartiolyhty", "tier": "epic", "cost": 2100,
		"builds_from": ["airutlyhty", "manahelmi"],
		"stats": {"cdr": 0.10, "mana_regen": 0.6, "hp": 120.0},
		"passive": "", "active": "vartija",
		"desc": "Vartija: aseta vartija tähystämään aluetta",
		"role_hint": "support",
	},
	"hoivasydän": {
		"name": "Hoivasydän", "tier": "epic", "cost": 2200,
		"builds_from": ["virtakide", "rautahelmi"],
		"stats": {"ap": 0.10, "mana_regen": 0.5, "hp": 150.0},
		"passive": "hoiva", "active": "",
		"desc": "Hoiva: antamasi parannukset ja kilvet +20 %; avustus parantaa sinua 6 % max HP",
		"role_hint": "support",
	},

	# --- Epic: ap ---
	"arkkisauva": {
		"name": "Arkkisauva", "tier": "epic", "cost": 2400,
		"builds_from": ["runosauva", "sirpalesauva"],
		"stats": {"ap": 0.30},
		"passive": "momentum", "active": "",
		"desc": "Momentum: kykyosuma sankariin +1 % kykyvahinko (max 10, nollautuu kuollessa)",
		"role_hint": "ap",
	},
	"kaikukide": {
		"name": "Kaikukide", "tier": "epic", "cost": 2300,
		"builds_from": ["runosauva", "kellojousi"],
		"stats": {"ap": 0.18, "cdr": 0.12},
		"passive": "kaiku", "active": "",
		"desc": "Kaiku: joka 3. kykyosuma toistaa 30 % vahingosta",
		"role_hint": "ap",
	},
	"manaydin": {
		"name": "Manaydin", "tier": "epic", "cost": 2200,
		"builds_from": ["virtakide", "manahelmi"],
		"stats": {"ap": 0.15, "mana_regen": 1.0},
		"passive": "ylivuoto", "active": "",
		"desc": "Ylivuoto: kyvyt maksavat 15 % vähemmän resurssia",
		"role_hint": "ap",
	},

	# --- Epic: jungle ---
	"riistanraatelija": {
		"name": "Riistanraatelija", "tier": "epic", "cost": 2100,
		"builds_from": ["ajojahti", "riistanveitsi"],
		"stats": {"jungle_dmg": 0.5, "attack": 0.10},
		"passive": "saalistaja", "active": "",
		"desc": "Saalistaja: leiribuffit kestävät +40 %; leirin kaato parantaa 8 % max HP",
		"role_hint": "jungle",
	},
	"varjoviitta": {
		"name": "Varjoviitta", "tier": "epic", "cost": 2300,
		"builds_from": ["ajojahti", "sulkasaappaat"],
		"stats": {"ms": 0.07, "attack": 0.12},
		"passive": "", "active": "varjo",
		"desc": "Varjo: 3 sekunnin häive",
		"role_hint": "jungle",
	},
	"ansalanka": {
		"name": "Ansalanka", "tier": "epic", "cost": 2300,
		"builds_from": ["myrskyterä", "riistanveitsi"],
		"stats": {"attack": 0.15, "jungle_dmg": 0.25},
		"passive": "ansa", "active": "",
		"desc": "Ansa: hidastetut/juurrutetut kohteet ottavat sinulta +12 % vahinkoa",
		"role_hint": "jungle",
	},

	# --- Legendary (2400 g + Baron-artefakti) ---
	"kuninkaansurma": {
		"name": "Kuninkaansurma", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"attack": 0.28, "attack_speed": 0.20, "crit": 0.15},
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
		"stats": {"cdr": 0.15, "gold_per_sec": 1.5, "assist_gold": 0.75, "hp": 200.0},
		"passive": "koitto", "active": "",
		"desc": "Koitto: parantamasi tai kilpesi saanut liittolainen saa +15 % vauhtia 2 s",
		"role_hint": "support",
	},
	"tyhjyydenydin": {
		"name": "Tyhjyyden ydin", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"ap": 0.35, "cdr": 0.15, "mana_regen": 0.6},
		"passive": "tyhjyys", "active": "",
		"desc": "Tyhjyys: sankaritappo/avustus palauttaa 40 ult-latausta ja nollaa kyvyt",
		"role_hint": "ap",
	},
	"alfaturkki": {
		"name": "Alfapedon turkki", "tier": "legendary", "cost": 2400,
		"builds_from": [], "require_artifact": true,
		"stats": {"attack": 0.20, "ms": 0.10, "jungle_dmg": 0.6},
		"passive": "alfa", "active": "",
		"desc": "Alfa: +50 % vahinko Baroniin/Dragoniin; leirin kaato lataa hidasteosuman",
		"role_hint": "jungle",
	},
}


static func get_item(id: String) -> Dictionary:
	var item: Dictionary = ITEMS.get(id, {})
	return item


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
		var pick := next_purchase(comp, owned, wallet)
		if pick == "":
			continue
		var pick_cost := combine_cost(pick, owned)
		if best == "" or pick_cost < best_cost:
			best = pick
			best_cost = pick_cost
	return best
