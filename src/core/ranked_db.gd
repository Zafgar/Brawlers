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
