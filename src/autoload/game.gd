extends Node
## Globaali pelitila: otteluasetukset, pelaajakokoonpano, ruutujen vaihto
## ja pysyvät asetukset. Autoload-nimi: Game.

# Bottien vaikeustasot 1–6 (indeksit 0–5). Taso 6 on tahallaan epäreilu:
# se huijaa (enemmän vahinkoa, vähemmän otettua, nopeammat jäähdytykset ym.).
const BOT_MIN_LEVEL := 1
const BOT_MAX_LEVEL := 6
const BOT_LEVEL_NAMES := [
	"1 – Vasta-alkaja", "2 – Helppo", "3 – Normaali",
	"4 – Kova", "5 – Mestari", "6 – Epäreilu",
]
const OPTIONS_PATH := "user://arena_options.cfg"

# Otteluasetukset
var team_size := 4
var rounds_to_win := 1          # MOBA on yksi 20 minuutin ottelu
var bot_level := 2              # 0–5 (vanha asteikko; pidetään synkassa tierin kanssa)
var bot_tier := 2               # ranking-taso 0–7 (Wood..Challenger); oletus Silver
var map_id := "moba"
var mode_id := "moba"
var practice := false


## Ottelun bottien rank: valitun tierin divisioona III. Toimii myöhemmin
## pelaajan oman ranking-tason pohjana (save/load): pelaaja kohtaa oman
## tasonsa botteja ja nousee divisioonia voittamalla.
func match_bot_rank() -> int:
	return BotRank.tier_default_rank(bot_tier)

# Kokoonpano (PlayerProfile-oliot, ihmiset ja botit)
var roster: Array = []

# Ottelun tila
var blue_rounds := 0
var orange_rounds := 0
var last_winner_team := 0

# Paikallisen co-opin pelaajakatto (loput täytetään boteilla). Verkkopeliä
# varten (myöhemmin) määrää voi nostaa.
const MAX_LOCAL_PLAYERS := 4

var options := {
	"volume": 0.9,            # kokonaisäänenvoimakkuus (master)
	"music_volume": 0.9,      # musiikin oma säädin
	"sfx_volume": 0.7,        # ääniefektien oma säädin
	"music": true,
	"shake": true,
	"fullscreen": true,
	"split_screen": true,     # per-pelaaja-ruudut (oma hahmo keskiössä, 1-4 jaettu)
}

var main: Node = null
var arena = null

# Simulaatio: bot vs bot -ajot telemetriaa varten (tekoälyn/tasapainon kehitys).
var simulating := false
var sim_visuals := true       # false = turbo: ei taisteluvisuaaleja/efektejä
var sim_runner = null
var last_report := ""     # viimeisimmän ottelun raportti (pelaaja voi antaa sen)


func boot(root: Node) -> void:
	main = root
	RenderingServer.set_default_clear_color(Palette.BG_DARK)
	_register_actions()
	load_options()
	apply_options()
	go_menu()


func _register_actions() -> void:
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", key)
		var btn := InputEventJoypadButton.new()
		btn.button_index = JOY_BUTTON_START
		InputMap.action_add_event("pause", btn)

	# Varmista että peliohjaimella voi valita ja peruuttaa valikoissa.
	# Godotin oletukset eivät kaikissa versioissa sisällä ohjaimen
	# kasvopainikkeita, jolloin navigointi toimii mutta valinta ei.
	_ensure_pad_button("ui_accept", JOY_BUTTON_A)     # Risti = valitse
	_ensure_pad_button("ui_cancel", JOY_BUTTON_B)     # Ympyrä = takaisin

	# Koko ruudun vaihto (F11).
	if not InputMap.has_action("toggle_fullscreen"):
		InputMap.add_action("toggle_fullscreen")
		var f := InputEventKey.new()
		f.physical_keycode = KEY_F11
		InputMap.action_add_event("toggle_fullscreen", f)


## Lisää ohjaimen painikkeen toimintoon vain jos sitä ei jo ole (ei tuplia).
func _ensure_pad_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		var jb := ev as InputEventJoypadButton
		if jb != null and jb.button_index == button:
			return
	var b := InputEventJoypadButton.new()
	b.button_index = button
	InputMap.action_add_event(action, b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()


func toggle_fullscreen() -> void:
	options.fullscreen = not options.fullscreen
	_apply_fullscreen()
	save_options()


func _apply_fullscreen() -> void:
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if options.fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _swap(node: Node) -> void:
	arena = null
	for child in main.get_children():
		main.remove_child(child)
		child.queue_free()
	main.add_child(node)


# --- Ruutujen vaihto ---

func go_menu() -> void:
	# Kesken oleva simulaatio keskeytetään siististi (palauttaa aikaskaalauksen
	# ja siivoaa etenemisnäytön) ettei peli jää jumiin nopeutettuun tilaan.
	if sim_runner != null:
		sim_runner.abort()
	_swap(MainMenu.new())


func go_setup(practice_mode: bool) -> void:
	practice = practice_mode
	_apply_moba_format()
	if practice_mode:
		bot_level = 0
		bot_tier = 0
		go_lobby()
	else:
		_swap(MatchSetup.new())


func go_lobby() -> void:
	_apply_moba_format()
	_swap(Lobby.new())


func go_gallery() -> void:
	_swap(HeroGallery.new())


## Pikakokeilu: hyppää suoraan 4v4 MOBA-harjoitusotteluun valitulla sankarilla.
## Muut seitsemän paikkaa täytetään helpoilla boteilla.
func try_hero(hero_id: String) -> void:
	practice = true
	_apply_moba_format()
	bot_level = 0
	bot_tier = 0

	var human := PlayerProfile.new()
	human.index = 0
	var pads := Input.get_connected_joypads()
	human.device = pads[0] if not pads.is_empty() else -1
	human.is_bot = false
	human.team = 0
	human.hero_id = hero_id
	human.display_name = "Sinä"

	roster = [human]
	var used := [{}, {}]
	used[0][hero_id] = true
	for team in range(2):
		var first_slot := 1 if team == 0 else 0
		for slot in range(first_slot, 4):
			var bot := PlayerProfile.new()
			bot.index = roster.size()
			bot.device = -2
			bot.is_bot = true
			bot.team = team
			bot.hero_id = _random_unused_hero(used[team])
			used[team][bot.hero_id] = true
			bot.display_name = "Liittolais-AI %d" % slot if team == 0 \
				else "Vihollis-AI %d" % (slot + 1)
			roster.append(bot)
	start_match()


func _random_other_hero(exclude: String) -> String:
	var pool: Array = HeroDef.ORDER.duplicate()
	pool.erase(exclude)
	if pool.is_empty():
		return exclude
	var pick: String = pool[randi() % pool.size()]
	return pick


func _random_unused_hero(used: Dictionary) -> String:
	var pool: Array = HeroDef.ORDER.filter(func(id): return not used.has(id))
	if pool.is_empty():
		pool = HeroDef.ORDER.duplicate()
	return str(pool[randi() % pool.size()])


## Pelaajalle näkyvä peli on aina sama kilpailullinen formaatti. Simulaatioajo
## asettaa oman joukkuemääränsä suoraan eikä kulje tämän valikkopolun kautta.
func _apply_moba_format() -> void:
	team_size = 4
	rounds_to_win = 1
	mode_id = "moba"
	map_id = "moba"
	# Pelaajanäkymä on aina sankaria seuraava 1–4 pelaajan split screen.
	options.split_screen = true


func start_match() -> void:
	if not simulating:
		_apply_moba_format()
	blue_rounds = 0
	orange_rounds = 0
	for profile in roster:
		profile.reset_stats()
	var new_arena := Arena.new()
	if not simulating:
		# Pelaaminen tapahtuu aina sankaria seuraavissa paikallisissa viewporteissa.
		var host := SplitView.new()
		host.setup(new_arena)
		_swap(host)
	else:
		_swap(new_arena)
	arena = new_arena


func match_finished() -> void:
	if simulating and sim_runner != null:
		sim_runner.on_match_done()
		return
	# Pelaajien ottelu: tuota raportti, jonka pelaaja voi antaa kehittäjälle.
	_capture_report()
	_swap(Results.new())


## Tallentaa juuri päättyneen ottelun raportin (luetaan areenasta ennen vaihtoa).
func _capture_report() -> void:
	last_report = ""
	if arena == null or not is_instance_valid(arena):
		return
	if not arena.has_method("sim_snapshot"):
		return
	var snap: Dictionary = arena.sim_snapshot()
	var intro := [
		"=== OTTELUN RAPORTTI ===",
		"Pelimuoto: %s | %dv%d" % [mode_id, team_size, team_size]]
	last_report = MatchReport.build([snap], intro)


func go_sim() -> void:
	_swap(SimSetup.new())


func go_report() -> void:
	if last_report == "":
		return
	var r := SimResults.new()
	r.report_text = last_report
	_swap(r)


func rematch() -> void:
	start_match()


# --- Apurit ---

func team_name(team: int) -> String:
	return "SININEN" if team == 0 else "ORANSSI"


func team_color(team: int) -> Color:
	return Palette.team(team)


func humans() -> Array:
	return roster.filter(func(p): return not p.is_bot)


func team_members(team: int) -> Array:
	return roster.filter(func(p): return p.team == team)


func rounds_label() -> String:
	return "Paras %d:sta" % (rounds_to_win * 2 - 1)


# --- Asetukset ---

func load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		return
	options.volume = cfg.get_value("audio", "volume", options.volume)
	options.music_volume = cfg.get_value("audio", "music_volume", options.music_volume)
	options.sfx_volume = cfg.get_value("audio", "sfx_volume", options.sfx_volume)
	options.music = cfg.get_value("audio", "music", options.music)
	options.shake = cfg.get_value("video", "shake", options.shake)
	options.fullscreen = cfg.get_value("video", "fullscreen", options.fullscreen)
	# Vanha yhteiskameravalinta poistui; nykyinen pelaajaformaatti on aina tämä.
	options.split_screen = true


func save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", options.volume)
	cfg.set_value("audio", "music_volume", options.music_volume)
	cfg.set_value("audio", "sfx_volume", options.sfx_volume)
	cfg.set_value("audio", "music", options.music)
	cfg.set_value("video", "shake", options.shake)
	cfg.set_value("video", "fullscreen", options.fullscreen)
	cfg.set_value("video", "split_screen", options.split_screen)
	cfg.save(OPTIONS_PATH)


func apply_options() -> void:
	AudioMgr.set_master_volume(options.volume)
	AudioMgr.set_music_volume(options.music_volume)
	AudioMgr.set_sfx_volume(options.sfx_volume)
	AudioMgr.set_music_enabled(options.music)
	_apply_fullscreen()
