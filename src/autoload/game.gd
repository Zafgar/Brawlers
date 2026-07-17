extends Node
## Globaali pelitila: otteluasetukset, pelaajakokoonpano, ruutujen vaihto
## ja pysyvät asetukset. Autoload-nimi: Game.

enum BotLevel { EASY, NORMAL, HARD }

const BOT_LEVEL_NAMES := ["Helppo", "Normaali", "Kova"]
const OPTIONS_PATH := "user://arena_options.cfg"

# Otteluasetukset
var team_size := 2
var rounds_to_win := 2          # 2 = paras kolmesta, 3 = paras viidestä
var bot_level: int = BotLevel.NORMAL
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
	"volume": 0.85,
	"music": true,
	"shake": true,
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
	if InputMap.has_action("pause"):
		return
	InputMap.add_action("pause")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", key)
	var btn := InputEventJoypadButton.new()
	btn.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", btn)


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
		bot_level = BotLevel.EASY
		go_lobby()
	else:
		_swap(MatchSetup.new())


func go_lobby() -> void:
	_swap(Lobby.new())


func go_gallery() -> void:
	_swap(HeroGallery.new())


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
	options.music = cfg.get_value("audio", "music", options.music)
	options.shake = cfg.get_value("video", "shake", options.shake)


func save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", options.volume)
	cfg.set_value("audio", "music", options.music)
	cfg.set_value("video", "shake", options.shake)
	cfg.save(OPTIONS_PATH)


func apply_options() -> void:
	AudioMgr.set_master_volume(options.volume)
	AudioMgr.set_music_enabled(options.music)
