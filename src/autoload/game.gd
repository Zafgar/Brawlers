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
var team_size := 2
var rounds_to_win := 2          # 2 = paras kolmesta, 3 = paras viidestä
var bot_level := 2              # 0–5 (näytetään 1–6); oletus taso 3 (Normaali)
var map_id := "geargarden"
var mode_id := "relic"
var practice := false

# Kokoonpano (PlayerProfile-oliot, ihmiset ja botit)
var roster: Array = []

# Ottelun tila
var blue_rounds := 0
var orange_rounds := 0
var last_winner_team := 0

var options := {
	"volume": 0.9,            # kokonaisäänenvoimakkuus (master)
	"music_volume": 0.9,      # musiikin oma säädin
	"sfx_volume": 0.7,        # ääniefektien oma säädin
	"music": true,
	"shake": true,
	"fullscreen": true,
}

var main: Node = null
var arena = null


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
	_swap(MainMenu.new())


func go_setup(practice_mode: bool) -> void:
	practice = practice_mode
	if practice_mode:
		team_size = 1
		rounds_to_win = 1
		bot_level = 0
		go_lobby()
	else:
		_swap(MatchSetup.new())


func go_lobby() -> void:
	_swap(Lobby.new())


func go_gallery() -> void:
	_swap(HeroGallery.new())


## Pikakokeilu: hyppää suoraan harjoitusotteluun valitulla sankarilla (1v1 vs
## helppo botti), jotta näkee mitä sankari tekee. Käyttää käytössä olevaa
## ohjainta jos sellainen on kytketty, muuten näppäimistöä.
func try_hero(hero_id: String) -> void:
	practice = true
	team_size = 1
	rounds_to_win = 1
	bot_level = 0
	mode_id = "relic"

	var human := PlayerProfile.new()
	human.index = 0
	var pads := Input.get_connected_joypads()
	human.device = pads[0] if not pads.is_empty() else -1
	human.is_bot = false
	human.team = 0
	human.hero_id = hero_id
	human.display_name = "Sinä"

	var bot := PlayerProfile.new()
	bot.index = 1
	bot.device = -2
	bot.is_bot = true
	bot.team = 1
	bot.hero_id = _random_other_hero(hero_id)
	bot.display_name = "Harjoitusbotti"

	roster = [human, bot]
	start_match()


func _random_other_hero(exclude: String) -> String:
	var pool: Array = HeroDef.ORDER.duplicate()
	pool.erase(exclude)
	if pool.is_empty():
		return exclude
	var pick: String = pool[randi() % pool.size()]
	return pick


func start_match() -> void:
	blue_rounds = 0
	orange_rounds = 0
	for profile in roster:
		profile.reset_stats()
	var new_arena := Arena.new()
	_swap(new_arena)
	arena = new_arena


func match_finished() -> void:
	_swap(Results.new())


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


func save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", options.volume)
	cfg.set_value("audio", "music_volume", options.music_volume)
	cfg.set_value("audio", "sfx_volume", options.sfx_volume)
	cfg.set_value("audio", "music", options.music)
	cfg.set_value("video", "shake", options.shake)
	cfg.set_value("video", "fullscreen", options.fullscreen)
	cfg.save(OPTIONS_PATH)


func apply_options() -> void:
	AudioMgr.set_master_volume(options.volume)
	AudioMgr.set_music_volume(options.music_volume)
	AudioMgr.set_sfx_volume(options.sfx_volume)
	AudioMgr.set_music_enabled(options.music)
	_apply_fullscreen()
