class_name HeroDef
## Sankarien staattiset määrittelyt: nimet, roolit, tilastot, kyvyt ja värit.
## Sankariluokat lukevat cooldownit ja perustilastot täältä, jotta
## käyttöliittymä ja pelilogiikka pysyvät aina samassa linjassa.

const ORDER := ["bastion", "ember", "luma", "blink", "bramble", "quill"]

const HEROES := {
	"bastion": {
		"name": "Bastion",
		"role": "Tankki",
		"difficulty": 1,
		"hp": 280.0,
		"speed": 295.0,
		"ratings": {"kesto": 5, "liike": 2, "vahinko": 2, "tuki": 4},
		"weapon": "Kilpi ja nuija",
		"desc": "Rintaman kallio. Suojaa joukkuetta edestä ja pitää linjan.",
		"color": Color("86ccd9"),
		"color_b": Color("2e5f74"),
		"abilities": {
			"basic": {"name": "Nuijan heilautus", "desc": "Leveä isku eteen.", "cd": 0.6},
			"a1": {"name": "Kilpivalli", "desc": "Torjuu edestä tulevat osumat 2,5 s ajan.", "cd": 9.0},
			"a2": {"name": "Maanjäristys", "desc": "Maahan isku: vahinkoa ja hidastus ympärillä.", "cd": 8.0},
			"dodge": {"name": "Rynnäkkö", "desc": "Raskas syöksy, joka tönäisee vihollisia.", "cd": 5.0},
			"ult": {"name": "Linnake", "desc": "Suuri kupoli, joka torjuu viholliset ammukset.", "cd": 0.0},
		},
	},
	"ember": {
		"name": "Ember",
		"role": "Mage",
		"difficulty": 2,
		"hp": 170.0,
		"speed": 320.0,
		"ratings": {"kesto": 2, "liike": 3, "vahinko": 5, "tuki": 1},
		"weapon": "Tulilyhty",
		"desc": "Alueiden hallitsija. Sytyttää kentän palamaan ja pakottaa liikkeelle.",
		"color": Color("ff8a4a"),
		"color_b": Color("b33b17"),
		"abilities": {
			"basic": {"name": "Tulipallo", "desc": "Suora räiskyvä ammus.", "cd": 0.55},
			"a1": {"name": "Liekkilammikko", "desc": "Heittää palavan alueen, joka polttaa vihollisia.", "cd": 8.0},
			"a2": {"name": "Lämpöaalto", "desc": "Purkaus eteen: vahinkoa ja työntö.", "cd": 7.0},
			"dodge": {"name": "Kipinäliuku", "desc": "Nopea liuku, joka jättää kipinäjäljen.", "cd": 4.0},
			"ult": {"name": "Tulimyrsky", "desc": "Laajeneva liekkirengas Emberin ympärille.", "cd": 0.0},
		},
	},
	"luma": {
		"name": "Luma",
		"role": "Tuki",
		"difficulty": 2,
		"hp": 200.0,
		"speed": 325.0,
		"ratings": {"kesto": 3, "liike": 3, "vahinko": 2, "tuki": 5},
		"weapon": "Valosauva",
		"desc": "Joukkueen sydän. Parantaa, suojaa ja pitää kaikki pelissä.",
		"color": Color("ffe9a8"),
		"color_b": Color("d9a13f"),
		"abilities": {
			"basic": {"name": "Valopulssi", "desc": "Ammus, joka vahingoittaa vihollisia ja parantaa liittolaisia.", "cd": 0.5},
			"a1": {"name": "Hoitokehä", "desc": "Parantava purkaus Luman ympärillä.", "cd": 8.0},
			"a2": {"name": "Suojasäde", "desc": "Antaa suojakilven lähimmälle liittolaiselle.", "cd": 7.0},
			"dodge": {"name": "Pyrähdys", "desc": "Kevyt ja nopea väistö.", "cd": 3.5},
			"ult": {"name": "Valokenttä", "desc": "Suuri alue, joka parantaa ja nopeuttaa liittolaisia.", "cd": 0.0},
		},
	},
	"blink": {
		"name": "Blink",
		"role": "Assassin",
		"difficulty": 3,
		"hp": 160.0,
		"speed": 360.0,
		"ratings": {"kesto": 2, "liike": 5, "vahinko": 4, "tuki": 1},
		"weapon": "Kaksi valomiekkaa",
		"desc": "Välähdys pimeässä. Iskee, katoaa ja iskee taas.",
		"color": Color("b48aff"),
		"color_b": Color("5b2f9e"),
		"abilities": {
			"basic": {"name": "Valoviilto", "desc": "Nopea kaksoisviilto lähelle.", "cd": 0.4},
			"a1": {"name": "Teleportti", "desc": "Siirtyy hetkessä tähtäyksen suuntaan.", "cd": 6.0},
			"a2": {"name": "Valoviuhka", "desc": "Heittää kolme valoterää viuhkana.", "cd": 7.0},
			"dodge": {"name": "Sivuaskel", "desc": "Salamannopea väistöliike.", "cd": 3.0},
			"ult": {"name": "Varjotanssi", "desc": "Iskee sarjan teleportteja lähivihollisten läpi.", "cd": 0.0},
		},
	},
	"bramble": {
		"name": "Bramble",
		"role": "Fighter",
		"difficulty": 2,
		"hp": 230.0,
		"speed": 310.0,
		"ratings": {"kesto": 4, "liike": 3, "vahinko": 3, "tuki": 2},
		"weapon": "Köynnösruoska",
		"desc": "Piikikäs lähitaistelija, joka sitoo viholliset paikoilleen.",
		"color": Color("7ed957"),
		"color_b": Color("2f7a33"),
		"abilities": {
			"basic": {"name": "Ruoskanisku", "desc": "Keskipitkä pyyhkäisy kaaressa.", "cd": 0.55},
			"a1": {"name": "Juurisidonta", "desc": "Köynnös, joka juurruttaa ensimmäisen osuman.", "cd": 8.0},
			"a2": {"name": "Piikkipyörre", "desc": "Piikit sinkoutuvat ympärille ja jättävät piikkialueen.", "cd": 7.5},
			"dodge": {"name": "Köynnösheitto", "desc": "Vetäisee itsensä ruoskalla eteenpäin.", "cd": 4.0},
			"ult": {"name": "Piikkipuutarha", "desc": "Suuri alue, joka hidastaa ja pistelee vihollisia.", "cd": 0.0},
		},
	},
	"quill": {
		"name": "Quill",
		"role": "Ranger",
		"difficulty": 2,
		"hp": 175.0,
		"speed": 330.0,
		"ratings": {"kesto": 2, "liike": 3, "vahinko": 4, "tuki": 2},
		"weapon": "Jousi",
		"desc": "Tarkka-ampuja. Ladattu nuoli palkitsee kärsivällisen.",
		"color": Color("5fd0a0"),
		"color_b": Color("1f6e52"),
		"abilities": {
			"basic": {"name": "Nuoli", "desc": "Pidä pohjassa ladataksesi: täysi lataus lävistää.", "cd": 0.5},
			"a1": {"name": "Tarkkuuslaukaus", "desc": "Pitkä, nopea ja lävistävä erikoisnuoli.", "cd": 7.0},
			"a2": {"name": "Nuolisade", "desc": "Nuolia sataa valitulle alueelle hetken päästä.", "cd": 8.0},
			"dodge": {"name": "Kuperkeikka", "desc": "Nopea kieräys, joka lataa jousta.", "cd": 3.5},
			"ult": {"name": "Myrskysarja", "desc": "Ampuu nopean sarjan nuolia tähtäyksen mukaan.", "cd": 0.0},
		},
	},
}


static func get_def(id: String) -> Dictionary:
	return HEROES[id]


static func ability(id: String, slot: String) -> Dictionary:
	return HEROES[id]["abilities"][slot]


static func cooldown(id: String, slot: String) -> float:
	return HEROES[id]["abilities"][slot]["cd"]
