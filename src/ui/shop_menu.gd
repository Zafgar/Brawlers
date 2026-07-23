class_name ShopMenu
extends RefCounted
## Per-pelaajan kauppavalikon TILA ja syötelogiikka (PS5-ensin). PaneHud
## piirtää valikon tämän tilan pohjalta omaan ruutuunsa; Hero omistaa
## instanssin (laiskasti luotu) ja kutsuu update() joka fysiikkaframessa
## kaupan ollessa auki. Botit eivät koskaan avaa valikkoa (_bot_shop_tick).
##
## Syötteet luetaan suoraan laitteelta omalla reunatunnistuksella, jotta
## kaupan napit voivat poiketa pelin toiminnoista: L1/R1 välilehti, Risti
## osta, Kolmio myy, Ympyrä sulje (sulun hoitaa Hero drop-napista).
## Näppäimistö: Q/E välilehti, ENTER/VÄLILYÖNTI osta, T myy, F sulje.
## Navigointi: vasen tatti / D-pad / WASD + nuolet, 0.16 s toistolla.

const TABS := ["SUOSITUS", "CARRY", "TANKKI", "TUKI", "AP", "JUNGLE", "KAIKKI"]
const TAB_ROLES := {"CARRY": "carry", "TANKKI": "tank", "TUKI": "support",
	"AP": "ap", "JUNGLE": "jungle"}
const TIER_ORDER := ["common", "rare", "epic", "legendary"]
const TIER_LABELS := {"common": "TAVALLINEN", "rare": "HARVINAINEN",
	"epic": "EEPPINEN", "legendary": "LEGENDA"}
const NAV_REPEAT := 0.16
const SELL_RATIO := 0.7

var tab := 0
var col := 0                 # tier-sarake 0..3 (common..legendary)
var row := 0
var in_inventory := false    # valinta alarivillä (omat itemit -> myynti)
var inv_index := 0
var flash_t := 0.0           # > 0 osto onnistui (vihreä), < 0 esto (punainen)
var flash_msg := ""          # eston syy detaljipaneeliin
var columns: Array = [[], [], [], []]   # tier-sarakkeiden item-id:t

var _nav_t := 0.0
var _prev := {}              # nappien edellinen tila (reunatunnistus)
var _cache_key := ""


## Avataan: nollaa valinta ja nappitilat (avauspainallus ei saa vuotaa ostoon).
func open_for(hero) -> void:
	tab = 0
	row = 0
	in_inventory = false
	inv_index = 0
	flash_t = 0.0
	flash_msg = ""
	_nav_t = 0.2
	_cache_key = ""
	_refresh_columns(hero)
	col = _first_column()
	_prev = _poll(hero)


func update(hero, delta: float) -> void:
	flash_t = move_toward(flash_t, 0.0, delta)
	_nav_t = maxf(_nav_t - delta, 0.0)
	_refresh_columns(hero)
	var now := _poll(hero)
	if _edge(now, "tab_prev"):
		_switch_tab(hero, -1)
	if _edge(now, "tab_next"):
		_switch_tab(hero, 1)
	# Navigointi: tatti tai D-pad/nuolet, toisto NAV_REPEAT-tahdilla.
	var dx := 0
	var dy := 0
	var mv: Vector2 = hero.controller.move_vector()
	if mv.x < -0.55 or bool(now.get("left", false)):
		dx = -1
	elif mv.x > 0.55 or bool(now.get("right", false)):
		dx = 1
	if mv.y < -0.55 or bool(now.get("up", false)):
		dy = -1
	elif mv.y > 0.55 or bool(now.get("down", false)):
		dy = 1
	if dx != 0 or dy != 0:
		if _nav_t <= 0.0:
			_nav_t = NAV_REPEAT
			_move_selection(dx, dy)
	else:
		_nav_t = 0.0   # suunta irti -> seuraava painallus liikuttaa heti
	if _edge(now, "buy"):
		_try_buy(hero)
	if _edge(now, "sell"):
		_try_sell(hero)
	_prev = now


## Valittu item-id (ruudukosta tai alarivin inventaariosta). "" = ei valintaa.
func selected_id(hero) -> String:
	if in_inventory:
		var items: Array = hero.items
		if inv_index < items.size():
			return str(items[inv_index])
		return ""
	var colc: Array = columns[col]
	if colc.is_empty():
		return ""
	return str(colc[clampi(row, 0, colc.size() - 1)])


## Myyntihinta: 70 % kokonaisarvosta (sama laskenta kuin Hero.sell_item).
static func sell_value(id: String) -> int:
	return int(round(float(int(ItemDef.get_item(id).get("cost", 0))) * SELL_RATIO))


# --- Roolit ja suositukset ---

## Sankarin roolin kauppakartoitus. Lobbyn positiovalinta ensin; muuten sama
## kartoitus kuin BotBrain._item_role tekee sankarin roolista.
static func role_for(hero) -> String:
	var pos := str(hero.profile.moba_position)
	if pos == "jungle":
		return "jungle"
	if pos == "support":
		return "support"
	if pos == "carry":
		return "carry"
	var role := str(HeroDef.get_def(hero.hero_id).get("role", ""))
	if role == HeroDef.ROLE_JUNGLER:
		return "jungle"
	if role == "Tuki":
		return "support"
	if role == "Tankki":
		return "tank"
	if role == "Mage":
		return "ap"
	return "carry"


## Roolin tavoite-epicit (peili BotBrain._item_buildistä — pidä synkassa).
static func role_build(role: String) -> Array:
	match role:
		"jungle":
			return ["riistanraatelija", "ansalanka", "varjoviitta"]
		"support":
			return ["kolikkotalismaani", "vartiolyhty", "hoivasydän"]
		"tank":
			return ["jäätikkövyö", "torjuntakupu", "elonlähde"]
		"ap":
			return ["arkkisauva", "kaikukide", "manaydin"]
	return ["myrskynsilma", "verikuu", "teräsarmä"]


## Roolin legenda (peili BotBrain._item_legendarystä — pidä synkassa).
static func role_legendary(role: String) -> String:
	match role:
		"jungle":
			return "alfaturkki"
		"support":
			return "aamunkoitto"
		"tank":
			return "maailmanpuu"
		"ap":
			return "tyhjyydenydin"
	return "kuninkaansurma"


## Suositellut itemit: roolibuildin tavoitteet + legenda + kaikki komponentit
## rekursiivisesti (commonit ja raret joista tavoitteet rakentuvat).
static func recommended_ids(hero) -> Array:
	var role := role_for(hero)
	var queue: Array = role_build(role).duplicate()
	queue.append(role_legendary(role))
	var out: Array = []
	while not queue.is_empty():
		var id := str(queue.pop_front())
		if id == "" or out.has(id):
			continue
		if ItemDef.get_item(id).is_empty():
			continue
		out.append(id)
		var comps: Array = ItemDef.get_item(id).get("builds_from", [])
		queue.append_array(comps)
	return out


## Itemin statit suomenkielisinä riveinä detaljipaneeliin.
static func stat_lines(item: Dictionary) -> Array:
	var out: Array = []
	var stats: Dictionary = item.get("stats", {})
	for key_v in stats:
		var key := str(key_v)
		var v: float = float(stats[key])
		var pct := int(round(v * 100.0))
		match key:
			"attack":
				out.append("+%d %% perusvahinko" % pct)
			"ap":
				out.append("+%d %% kykyvahinko" % pct)
			"attack_speed":
				out.append("+%d %% hyökkäysnopeus" % pct)
			"crit":
				out.append("+%d %% kriittinen osuma" % pct)
			"lifesteal":
				out.append("+%d %% elämänimu" % pct)
			"spellvamp":
				out.append("+%d %% loitsuimu" % pct)
			"cdr":
				out.append("-%d %% jäähdytykset" % pct)
			"ms":
				out.append("+%d %% liikenopeus" % pct)
			"hp":
				out.append("+%d HP" % int(v))
			"armor":
				out.append("+%d panssaria" % int(v))
			"mr":
				out.append("+%d taikavastusta" % int(v))
			"hp_regen":
				out.append("+%d %% elämän palautuminen" % pct)
			"mana_regen":
				out.append("+%d %% manan palautuminen" % pct)
			"gold_per_sec":
				out.append("+%.1f kultaa/s" % v)
			"assist_gold":
				out.append("+%d %% avustuskulta" % pct)
			"jungle_dmg":
				out.append("+%d %% viidakkovahinko" % pct)
			_:
				out.append("+%s %s" % [str(v), key])
	return out


# --- Sisäiset ---

func _refresh_columns(hero) -> void:
	var key := "%d:%s" % [tab, role_for(hero)]
	if key == _cache_key:
		return
	_cache_key = key
	columns = [[], [], [], []]
	var ids: Array = []
	var tname := str(TABS[tab])
	if tname == "KAIKKI":
		ids = ItemDef.all_ids()
	elif tname == "SUOSITUS":
		ids = recommended_ids(hero)
	else:
		var role := str(TAB_ROLES.get(tname, "carry"))
		for id_v in ItemDef.all_ids():
			var hint := str(ItemDef.get_item(str(id_v)).get("role_hint", ""))
			if hint == role or hint == "any":
				ids.append(str(id_v))
	for id_v in ids:
		var id := str(id_v)
		var ti := TIER_ORDER.find(str(ItemDef.get_item(id).get("tier", "")))
		if ti >= 0:
			(columns[ti] as Array).append(id)
	col = clampi(col, 0, 3)
	if (columns[col] as Array).is_empty():
		col = _first_column()
	row = clampi(row, 0, maxi(_col_size() - 1, 0))


func _first_column() -> int:
	for i in range(4):
		if not (columns[i] as Array).is_empty():
			return i
	return 0


func _col_size() -> int:
	return (columns[col] as Array).size()


func _switch_tab(hero, d: int) -> void:
	tab = wrapi(tab + d, 0, TABS.size())
	in_inventory = false
	row = 0
	_cache_key = ""
	_refresh_columns(hero)
	col = _first_column()
	AudioMgr.play("ui_move", 0.04, -10.0)


## Valinnan siirto: sarakkeet kiertävät (tyhjät ohitetaan), pystysuunnassa
## ruudukon yli mennään omaan inventaarioon (myyntirivi) ja siitä takaisin.
func _move_selection(dx: int, dy: int) -> void:
	AudioMgr.play("ui_move", 0.03, -14.0)
	if in_inventory:
		if dy != 0:
			in_inventory = false
			row = 0 if dy > 0 else maxi(_col_size() - 1, 0)
		elif dx != 0:
			inv_index = wrapi(inv_index + dx, 0, Hero.MAX_ITEMS)
		return
	if dx != 0:
		var c := col
		for i in range(4):
			c = wrapi(c + dx, 0, 4)
			if not (columns[c] as Array).is_empty():
				break
		col = c
		row = clampi(row, 0, maxi(_col_size() - 1, 0))
	if dy != 0:
		var nr := row + dy
		if nr < 0 or nr >= _col_size():
			in_inventory = true
			inv_index = clampi(inv_index, 0, Hero.MAX_ITEMS - 1)
		else:
			row = nr


func _try_buy(hero) -> void:
	if in_inventory:
		flash_t = -0.35
		flash_msg = "OSTA RUUDUKOSTA — ALARIVI MYY"
		AudioMgr.play("ui_back", 0.05, -8.0)
		return
	var id := selected_id(hero)
	if id == "":
		return
	if bool(hero.buy_item(id)):
		flash_t = 0.35
		flash_msg = ""
		AudioMgr.play("blessing", 0.04, -8.0)
	else:
		flash_t = -0.35
		flash_msg = _fail_reason(hero, id)
		AudioMgr.play("ui_back", 0.05, -6.0)


func _try_sell(hero) -> void:
	var items: Array = hero.items
	if not in_inventory or inv_index >= items.size():
		flash_t = -0.35
		flash_msg = "VALITSE MYYTÄVÄ ALARIVILTÄ"
		AudioMgr.play("ui_back", 0.05, -8.0)
		return
	var id := str(items[inv_index])
	if bool(hero.sell_item(id)):
		flash_t = 0.35
		flash_msg = ""
		var remaining: Array = hero.items
		inv_index = clampi(inv_index, 0, maxi(remaining.size() - 1, 0))
	else:
		flash_t = -0.35
		flash_msg = "MYYNTI EI ONNISTU"
		AudioMgr.play("ui_back", 0.05, -6.0)


## Oston eston syy (sama järjestys kuin Hero.buy_item tarkistaa).
func _fail_reason(hero, id: String) -> String:
	var item := ItemDef.get_item(id)
	if bool(item.get("require_artifact", false)) and not bool(hero.legendary_artifact):
		return "VAATII ARTEFAKTIN"
	var consumed := ItemDef.components_consumed(id, hero.items)
	var items: Array = hero.items
	if items.size() - consumed.size() + 1 > Hero.MAX_ITEMS:
		return "EI VAPAITA PAIKKOJA"
	if int(hero.profile.wallet()) < ItemDef.combine_cost(id, hero.items):
		return "EI TARPEEKSI KULTAA"
	return "OSTO EI ONNISTU"


## Nappien nykytila laitteelta (oma reunatunnistus _edge-apurilla).
func _poll(hero) -> Dictionary:
	var dev := int(hero.profile.device)
	var s := {}
	if dev >= 0:
		s["tab_prev"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER)
		s["tab_next"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_RIGHT_SHOULDER)
		s["buy"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_A)
		s["sell"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_Y)
		s["up"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP)
		s["down"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN)
		s["left"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT)
		s["right"] = Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT)
	else:
		s["tab_prev"] = Input.is_physical_key_pressed(KEY_Q)
		s["tab_next"] = Input.is_physical_key_pressed(KEY_E)
		s["buy"] = Input.is_physical_key_pressed(KEY_ENTER) \
			or Input.is_physical_key_pressed(KEY_SPACE)
		s["sell"] = Input.is_physical_key_pressed(KEY_T)
		s["up"] = Input.is_physical_key_pressed(KEY_UP)
		s["down"] = Input.is_physical_key_pressed(KEY_DOWN)
		s["left"] = Input.is_physical_key_pressed(KEY_LEFT)
		s["right"] = Input.is_physical_key_pressed(KEY_RIGHT)
	return s


func _edge(now: Dictionary, name: String) -> bool:
	return bool(now.get(name, false)) and not bool(_prev.get(name, false))
