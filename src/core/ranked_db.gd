class_name RankedDB
## Ranked-tilan pysyvä tallennus: käyttäjätilit (savet) ja bottipopulaatio.
## Sama kone voi pitää useaa käyttäjää — jokainen kiipeää omaa tikapuutaan.
##
## Tallennus on JSON osoitteessa user://ranked_save.json ja pidetään
## välimuistissa staattisessa _db:ssä. Kirjoitus menee ensin .tmp-tiedostoon ja
## nimetään vasta sitten paikalleen, jotta kesken jäänyt kirjoitus ei riko
## vanhaa tallennusta. Puuttuva tai rikkinäinen tiedosto korvataan oletuksilla:
## ranked ei saa koskaan kaataa peliä.
##
## Skeema (version = 1, kentän varaus tuleville migraatioille):
##   {"version": 1,
##    "users": [{"id","name","rank","lp","wins","losses","streak","promo",
##               "shield","created","last_played","peak_rank","history"}],
##    "last_user_id": "u1",
##    "bots": [{"name","rank","lp","hero_pool","pos"}]}

const SAVE_PATH := "user://ranked_save.json"
const TMP_PATH := "user://ranked_save.tmp"
const VERSION := 1
const HISTORY_MAX := 40          # viimeisimmät ottelut säilytetään, vanhat karsitaan
const NAME_MAX := 18
const START_RANK := 0            # uusi pelaaja aloittaa Wood IV:stä
const BOTS_PER_RANK := 10        # 10 bottia x 32 rankia = 320 nimettyä bottia
const BOT_SEED := 20250726       # kiinteä siemen: sama populaatio joka koneella

static var _db: Dictionary = {}
static var _loaded := false


# --- Lataus ja tallennus ---

## Oletustallennus (myös rikkinäisen tiedoston korvaaja).
static func _defaults() -> Dictionary:
	return {"version": VERSION, "users": [], "last_user_id": "", "bots": []}


## Lataa tallennuksen välimuistiin ja palauttaa sen. Turvallinen kutsua usein.
static func load_db() -> Dictionary:
	if _loaded:
		return _db
	_loaded = true
	_db = _defaults()
	var raw: Dictionary = _read_file()
	if raw.is_empty():
		return _db

	_db["version"] = maxi(int(raw.get("version", VERSION)), 1)
	_db["last_user_id"] = str(raw.get("last_user_id", ""))

	var users_list: Array = []
	var users_raw: Variant = raw.get("users", [])
	if users_raw is Array:
		for entry in users_raw:
			if entry is Dictionary:
				var user: Dictionary = _sanitize_user(entry)
				if str(user.get("id", "")) != "":
					users_list.append(user)
	_db["users"] = users_list

	var bots_list: Array = []
	var bots_raw: Variant = raw.get("bots", [])
	if bots_raw is Array:
		for entry in bots_raw:
			if entry is Dictionary:
				bots_list.append(_sanitize_bot(entry))
	_db["bots"] = bots_list
	return _db


## Lukee ja jäsentää tallennustiedoston. Palauttaa tyhjän jos tiedostoa ei ole
## tai se ei ole kelvollista JSONia.
static func _read_file() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var dict: Dictionary = parsed
		return dict
	return {}


## Kirjoittaa välimuistin levylle: ensin .tmp, sitten nimeäminen paikalleen.
static func save_db() -> void:
	load_db()
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_db))
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if DirAccess.rename_absolute(TMP_PATH, SAVE_PATH) != OK:
		# Nimeäminen ei onnistunut: kirjoitetaan varmuuden vuoksi suoraan.
		var direct := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if direct != null:
			direct.store_string(JSON.stringify(_db))
			direct.close()


## Tyhjentää välimuistin (seuraava kutsu lataa levyltä uudelleen).
static func reload() -> void:
	_loaded = false
	_db = {}
	load_db()


# --- Siivoajat: jokainen kenttä luetaan .get:llä oletusarvon kanssa ---

static func _clean_name(name: String) -> String:
	var clean := name.strip_edges()
	if clean.length() > NAME_MAX:
		clean = clean.substr(0, NAME_MAX)
	if clean == "":
		clean = "PELAAJA"
	return clean


static func _sanitize_promo(src: Variant) -> Dictionary:
	if not (src is Dictionary):
		return {}
	var promo: Dictionary = src
	if not promo.has("target_rank"):
		return {}
	var games: Array = []
	var games_raw: Variant = promo.get("games", [])
	if games_raw is Array:
		for game in games_raw:
			games.append(bool(game))
	return {
		"target_rank": clampi(int(promo.get("target_rank", 0)), 0, BotRank.MAX_RANK),
		"wins": clampi(int(promo.get("wins", 0)), 0, RankedRules.SERIES_LENGTH),
		"losses": clampi(int(promo.get("losses", 0)), 0, RankedRules.SERIES_LENGTH),
		"games": games,
	}


static func _sanitize_user(src: Dictionary) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var rank: int = clampi(int(src.get("rank", START_RANK)), 0, BotRank.MAX_RANK)
	var history: Array = []
	var history_raw: Variant = src.get("history", [])
	if history_raw is Array:
		for entry in history_raw:
			if entry is Dictionary:
				var row: Dictionary = entry
				history.append({
					"t": int(row.get("t", 0)),
					"rank": clampi(int(row.get("rank", 0)), 0, BotRank.MAX_RANK),
					"lp": clampi(int(row.get("lp", 0)), 0, RankedRules.LP_MAX),
					"win": bool(row.get("win", false)),
					"delta": int(row.get("delta", 0)),
				})
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	return {
		"id": str(src.get("id", "")),
		"name": _clean_name(str(src.get("name", ""))),
		"rank": rank,
		"lp": clampi(int(src.get("lp", 0)), 0, RankedRules.LP_MAX),
		"wins": maxi(int(src.get("wins", 0)), 0),
		"losses": maxi(int(src.get("losses", 0)), 0),
		"streak": int(src.get("streak", 0)),
		"promo": _sanitize_promo(src.get("promo", {})),
		"shield": maxi(int(src.get("shield", 0)), 0),
		"created": int(src.get("created", now)),
		"last_played": int(src.get("last_played", now)),
		"peak_rank": clampi(int(src.get("peak_rank", rank)), 0, BotRank.MAX_RANK),
		"history": history,
	}


static func _sanitize_bot(src: Dictionary) -> Dictionary:
	var pool: Array = []
	var pool_raw: Variant = src.get("hero_pool", [])
	if pool_raw is Array:
		for hero_id in pool_raw:
			var id := str(hero_id)
			if HeroDef.ORDER.has(id):
				pool.append(id)
	return {
		"name": _clean_name(str(src.get("name", "BOTTI"))),
		"rank": clampi(int(src.get("rank", 0)), 0, BotRank.MAX_RANK),
		"lp": clampi(int(src.get("lp", 0)), 0, RankedRules.LP_MAX - 1),
		"hero_pool": pool,
		"pos": str(src.get("pos", "")),
	}


# --- Käyttäjät ---

## Kaikki käyttäjät. Palauttaa ELÄVÄN listan: alkioiden muokkaus vaikuttaa
## välimuistiin (tallennus vaatii silti save_db-kutsun).
static func users() -> Array:
	load_db()
	var list: Array = []
	var raw: Variant = _db.get("users", [])
	if raw is Array:
		list = raw
	return list


## Yksi käyttäjä id:llä. Tyhjä sanakirja = ei löytynyt.
static func get_user(id: String) -> Dictionary:
	if id == "":
		return {}
	for entry in users():
		var user: Dictionary = entry
		if str(user.get("id", "")) == id:
			return user
	return {}


## Seuraava vapaa id-tunnus ("u1", "u2", ...).
static func _next_user_id() -> String:
	var highest := 0
	for entry in users():
		var user: Dictionary = entry
		var id: String = str(user.get("id", ""))
		if id.begins_with("u") and id.substr(1).is_valid_int():
			highest = maxi(highest, int(id.substr(1)))
	return "u%d" % (highest + 1)


## Luo uusi käyttäjä ja tee siitä aktiivinen. Palauttaa luodun rivin.
static func create_user(name: String) -> Dictionary:
	load_db()
	var now: int = int(Time.get_unix_time_from_system())
	var user: Dictionary = {
		"id": _next_user_id(),
		"name": _clean_name(name),
		"rank": START_RANK,
		"lp": 0,
		"wins": 0,
		"losses": 0,
		"streak": 0,
		"promo": {},
		"shield": 0,
		"created": now,
		"last_played": now,
		"peak_rank": START_RANK,
		"history": [],
	}
	var list: Array = users()
	list.append(user)
	_db["users"] = list
	_db["last_user_id"] = str(user.get("id", ""))
	save_db()
	return user


## Poistaa käyttäjän. Aktiivinen valinta siirtyy ensimmäiseen jäljelle jäävään.
static func delete_user(id: String) -> void:
	load_db()
	var list: Array = users()
	for i in range(list.size() - 1, -1, -1):
		var user: Dictionary = list[i]
		if str(user.get("id", "")) == id:
			list.remove_at(i)
	_db["users"] = list
	if str(_db.get("last_user_id", "")) == id:
		var fallback := ""
		if not list.is_empty():
			var first: Dictionary = list[0]
			fallback = str(first.get("id", ""))
		_db["last_user_id"] = fallback
	save_db()


## Nimeää käyttäjän uudelleen.
static func rename_user(id: String, name: String) -> void:
	var user: Dictionary = get_user(id)
	if user.is_empty():
		return
	user["name"] = _clean_name(name)
	save_db()


## Asettaa aktiivisen käyttäjän (tyhjä id nollaa valinnan).
static func set_active_user(id: String) -> void:
	load_db()
	if id != "" and get_user(id).is_empty():
		return
	_db["last_user_id"] = id
	save_db()


## Aktiivinen käyttäjä tai tyhjä sanakirja jos valintaa ei ole.
static func active_user() -> Dictionary:
	load_db()
	return get_user(str(_db.get("last_user_id", "")))


## Aktiivisen käyttäjän id ("" jos ei valintaa).
static func active_user_id() -> String:
	load_db()
	var user: Dictionary = active_user()
	return str(user.get("id", ""))


# --- Ottelun kirjaus ---

## Kirjaa yhden ottelun tuloksen käyttäjälle: LP, ylennykset, promo-sarjat,
## putket, historia ja tallennus. Palauttaa RankedRulesin yhteenvedon, jonka
## Phase B piirtää ottelun jälkeisellä ruudulla (lp_before/after,
## rank_before/after, promoted/demoted/promo_state, ...).
static func record_match(user_id: String, won: bool, enemy_avg_rank: float) -> Dictionary:
	load_db()
	var user: Dictionary = get_user(user_id)
	if user.is_empty():
		return {}

	var res: Dictionary = RankedRules.apply_match(user, won, enemy_avg_rank)
	var rank_after: int = int(res.get("rank_after", 0))
	var lp_after: int = int(res.get("lp_after", 0))
	var now: int = int(Time.get_unix_time_from_system())

	user["rank"] = rank_after
	user["lp"] = lp_after
	user["streak"] = int(res.get("streak_after", 0))
	user["promo"] = _sanitize_promo(res.get("promo", {}))
	user["shield"] = int(res.get("shield", 0))
	user["wins"] = int(user.get("wins", 0)) + (1 if won else 0)
	user["losses"] = int(user.get("losses", 0)) + (0 if won else 1)
	user["peak_rank"] = maxi(int(user.get("peak_rank", 0)), rank_after)
	user["last_played"] = now

	var history: Array = []
	var history_raw: Variant = user.get("history", [])
	if history_raw is Array:
		history = history_raw
	history.append({
		"t": now,
		"rank": rank_after,
		"lp": lp_after,
		"win": won,
		"delta": int(res.get("delta", 0)),
	})
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	user["history"] = history

	res["user_id"] = user_id
	res["name"] = str(user.get("name", ""))
	save_db()
	return res


# --- Botit ---

## Bottipopulaatio (elävä lista). Täytetään Matchmakerin käyttöön.
static func bots() -> Array:
	load_db()
	var list: Array = []
	var raw: Variant = _db.get("bots", [])
	if raw is Array:
		list = raw
	return list


## Tallentaa bottipopulaation muutokset (ladder-tikitys, uudet botit).
static func save_bots() -> void:
	save_db()


## Varmistaa että populaatio on olemassa. Ensimmäisellä kerralla luodaan
## BOTS_PER_RANK bottia jokaiselle 32 rankille = 320 nimettyä bottia, jotka
## tallennetaan — sen jälkeen ne elävät omaa elämäänsä tikapuilla.
static func ensure_bots() -> Array:
	load_db()
	var list: Array = bots()
	if list.size() >= (BotRank.MAX_RANK + 1) * BOTS_PER_RANK:
		return list
	list = _generate_bots()
	_db["bots"] = list
	save_db()
	return list


## Luo populaation kiinteällä siemenellä: 10 bottia per rank, kullakin nimi,
## LP, 2–3 sankarin oma pooli ja suosikkipositio.
static func _generate_bots() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = BOT_SEED
	var total: int = (BotRank.MAX_RANK + 1) * BOTS_PER_RANK
	var names: Array = BotNames.generate(total, BOT_SEED)
	var positions := ["top", "jungle", "carry", "support"]
	var list: Array = []
	var index := 0
	for rank in range(BotRank.MAX_RANK + 1):
		for i in range(BOTS_PER_RANK):
			var pool: Array = []
			var wanted: int = rng.randi_range(2, 3)
			var guard := 0
			while pool.size() < wanted and guard < 40:
				guard += 1
				var hero_id: String = str(HeroDef.ORDER[rng.randi_range(0,
					HeroDef.ORDER.size() - 1)])
				if not pool.has(hero_id):
					pool.append(hero_id)
			var bot_name := "Botti %d" % (index + 1)
			if index < names.size():
				bot_name = str(names[index])
			list.append({
				"name": bot_name,
				"rank": rank,
				"lp": rng.randi_range(0, RankedRules.LP_MAX - 1),
				"hero_pool": pool,
				"pos": str(positions[rng.randi_range(0, positions.size() - 1)]),
			})
			index += 1
	return list


## Kevyt ladder-tikitys pelaajan ottelun jälkeen: otoksesta botteja pannaan
## lähirankista vastustajaa vastaan ja voittaja ratkaistaan rank-erolla
## (RankedRules.win_chance). Voittajan ja häviäjän LP päivitetään samoilla
## peruskaavoilla ilman promo-sarjoja. Tämä EI simuloi oikeita otteluita —
## tarkoitus on vain pitää tikapuut elossa: nimet nousevat ja putoavat
## taustalla, joten sijoitus tuntuu ansaitulta.
static func ladder_tick(sample := 40) -> void:
	var list: Array = ensure_bots()
	if list.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(maxi(sample, 0)):
		var index_a: int = rng.randi_range(0, list.size() - 1)
		var index_b: int = _nearby_opponent(list, index_a, rng)
		if index_b < 0:
			continue
		var bot_a: Dictionary = list[index_a]
		var bot_b: Dictionary = list[index_b]
		var rank_a: int = clampi(int(bot_a.get("rank", 0)), 0, BotRank.MAX_RANK)
		var rank_b: int = clampi(int(bot_b.get("rank", 0)), 0, BotRank.MAX_RANK)
		var a_wins: bool = rng.randf() < RankedRules.win_chance(rank_a, rank_b)
		var step_a: Dictionary = RankedRules.simple_step(rank_a, int(bot_a.get("lp", 0)),
			a_wins, rank_b)
		var step_b: Dictionary = RankedRules.simple_step(rank_b, int(bot_b.get("lp", 0)),
			not a_wins, rank_a)
		bot_a["rank"] = int(step_a.get("rank", rank_a))
		bot_a["lp"] = int(step_a.get("lp", 0))
		bot_b["rank"] = int(step_b.get("rank", rank_b))
		bot_b["lp"] = int(step_b.get("lp", 0))
	save_db()


## Satunnainen vastustaja enintään kahden rankin päästä. Jos lähistöltä ei
## löydy ketään, otetaan naapuri listasta ettei tikitys jää tyhjäkäynnille.
static func _nearby_opponent(list: Array, index: int, rng: RandomNumberGenerator) -> int:
	if list.size() < 2:
		return -1
	var own: Dictionary = list[index]
	var rank: int = int(own.get("rank", 0))
	for attempt in range(12):
		var pick: int = rng.randi_range(0, list.size() - 1)
		if pick == index:
			continue
		var other: Dictionary = list[pick]
		if absi(int(other.get("rank", 0)) - rank) <= 2:
			return pick
	return (index + 1) % list.size()


## Bottipopulaation sijoituslista (korkein rank ensin) — Phase B voi piirtää
## tästä ranked-hubin tikapuunäkymän.
static func leaderboard(limit := 20) -> Array:
	var list: Array = ensure_bots().duplicate()
	list.sort_custom(func(a, b):
		var rank_a: int = int(a.get("rank", 0))
		var rank_b: int = int(b.get("rank", 0))
		if rank_a == rank_b:
			return int(a.get("lp", 0)) > int(b.get("lp", 0))
		return rank_a > rank_b)
	if list.size() > limit:
		list = list.slice(0, limit)
	return list
