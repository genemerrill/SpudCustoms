extends MainMenu

@export var level_select_packed_scene: PackedScene

var level_select_scene
var animation_state_machine : AnimationNodeStateMachinePlayback
@onready var version_label = $VersionMargin/VersionContainer/VersionLabel
@onready var bgm_player = $BackgroundMusicPlayer

func load_game_scene():
	GameState.start_game()
	SceneLoader.load_scene(story_game_scene_path)

func new_game():
	await JuicyButtons.setup_button(%NewGameButton)
	GlobalState.reset()
	load_game_scene()

func load_endless_scene():
	SceneLoader.load_scene(endless_game_scene_path)

func new_endless_game():
	load_endless_scene()

func intro_done():
	animation_state_machine.travel("OpenMainMenu")

func _is_in_intro():
	return animation_state_machine.get_current_node() == "Intro"

func _event_is_mouse_button_released(event : InputEvent):
	return event is InputEventMouseButton and not event.is_pressed()

func _event_skips_intro(event : InputEvent):
	return event.is_action_released("ui_accept") or \
		event.is_action_released("ui_select") or \
		event.is_action_released("ui_cancel") or \
		_event_is_mouse_button_released(event)

func _open_sub_menu(menu):
	super._open_sub_menu(menu)
	animation_state_machine.travel("OpenSubMenu")

func _close_sub_menu():
	super._close_sub_menu()
	animation_state_machine.travel("OpenMainMenu")

func _setup_level_select(): 
	if level_select_packed_scene != null:
		level_select_scene = level_select_packed_scene.instantiate()
		level_select_scene.hide()
		%LevelSelectContainer.call_deferred("add_child", level_select_scene)
		if level_select_scene.has_signal("level_selected"):
			level_select_scene.connect("level_selected", load_game_scene)

func _input(event):
	if _is_in_intro() and _event_skips_intro(event):
		intro_done()
		return
	super._input(event)

# Musical intervals (simplified selection)
var musical_intervals = {
	"original": 1.0,        # Original pitch
	"major_third_down": 0.8, # More somber
	"major_third_up": 1.25,  # Brighter feel
	"fifth_down": 0.67,      # Much darker
	"fifth_up": 1.5          # Brighter, heroic
}

# Current tracks
var bgm_tracks = []
var current_track_index = 0

@export var parallax_strength : float = 15.0
var initial_background_offsets = {}

func _ready():
	print("DEBUG: main_menu_with_animations _ready started")
	load_tracks()
	# Play with original pitch by default
	next_track_with_random_pitch()
	#play_with_pitch_variation("original")
	super._ready() # Calls _setup_game_buttons
	_setup_level_select()
	animation_state_machine = $MenuAnimationTree.get("parameters/playback")
	
	# Capture initial background offsets for parallax
	if has_node("BackgroundTextureRect"):
		var bg = $BackgroundTextureRect
		initial_background_offsets = {
			"left": bg.offset_left,
			"top": bg.offset_top,
			"right": bg.offset_right,
			"bottom": bg.offset_bottom
		}
	
	print("DEBUG: main_menu_with_animations _ready finished")
	
	# Emergency fix for blocked input if animation fails
	if has_node("FlowControlContainer"):
		print("DEBUG: Forcing FlowControlContainer to ignore mouse")
		$FlowControlContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	if initial_background_offsets.is_empty() or not has_node("BackgroundTextureRect"):
		return
		
	var bg = $BackgroundTextureRect
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	
	# Safe division check
	if center.x == 0 or center.y == 0:
		return
		
	var dist = (center - mouse_pos) / center # Ranges roughly from -1 to 1
	
	var target_offset_x = dist.x * parallax_strength
	var target_offset_y = dist.y * parallax_strength
	
	bg.offset_left = lerpf(bg.offset_left, initial_background_offsets.left + target_offset_x, 5 * delta)
	bg.offset_top = lerpf(bg.offset_top, initial_background_offsets.top + target_offset_y, 5 * delta)
	bg.offset_right = lerpf(bg.offset_right, initial_background_offsets.right + target_offset_x, 5 * delta)
	bg.offset_bottom = lerpf(bg.offset_bottom, initial_background_offsets.bottom + target_offset_y, 5 * delta)
	
func _setup_game_buttons():
	print("DEBUG: _setup_game_buttons called")
	super._setup_game_buttons()
	if GameState.has_game_state():
		%ContinueGameButton.show()
		if level_select_packed_scene != null and GameState.get_max_level_reached() > 0:
			%LevelSelectButton.show()

	# Debug/Prototype Buttons
	# Only frame them if they exist and we are in a debug build or specifically enabled
	var show_debug_buttons = OS.is_debug_build() # or Input.is_key_pressed(KEY_F1)
	print("DEBUG: show_debug_buttons = ", show_debug_buttons)

	var tic_tac = get_node_or_null("%TicTacToeButton")
	if tic_tac:
		print("DEBUG: Found TicTacToeButton")
		tic_tac.visible = show_debug_buttons
		if not tic_tac.pressed.is_connected(_on_tic_tac_toe_pressed):
			tic_tac.pressed.connect(_on_tic_tac_toe_pressed)
	else:
		print("ERROR: TicTacToeButton not found!")

	var battle = get_node_or_null("%TacticalBattleButton")
	if battle:
		print("DEBUG: Found TacticalBattleButton")
		battle.visible = show_debug_buttons
		if not battle.pressed.is_connected(_on_tactical_battle_pressed):
			battle.pressed.connect(_on_tactical_battle_pressed)
	else:
		print("ERROR: TacticalBattleButton not found!")

func _on_continue_game_button_pressed():
	load_game_scene()

func _on_level_select_button_pressed():
	_open_sub_menu(level_select_scene)

func _on_tic_tac_toe_pressed():
	print("DEBUG: TicTacToe pressed")
	get_tree().change_scene_to_file("res://scenes/prototypes/tic_tac_toe/TicTacToe.tscn")

func _on_tactical_battle_pressed():
	print("DEBUG: TacticalBattle pressed")
	get_tree().change_scene_to_file("res://scenes/prototypes/rpg_battle/BattleMat.tscn")

func load_tracks():
	# Replace with your actual music tracks
	bgm_tracks = [
	"res://assets/music/ambient_3_eternal_main.mp3",
	"res://assets/music/ambient_concern_main.mp3",
	"res://assets/music/ambient_faded_defeat_main_menu.mp3",
	"res://assets/music/ambient_nothingness_main.mp3",
	"res://assets/music/ambient_sadness_main.mp3"
	]

func play_with_pitch_variation(interval_name: String = "original"):
	# Default to original if invalid interval name provided
	if !musical_intervals.has(interval_name):
		interval_name = "original"
		
	var pitch = musical_intervals[interval_name]
	
	# Apply pitch shift
	bgm_player.pitch_scale = pitch
	
	# Adjust volume to maintain perceived loudness (optional)
	bgm_player.volume_db = -3 * log(pitch) / log(2)
	
	# If not already playing, start playback
	if !bgm_player.playing:
		play_current_track()
	
	print("Music initiated: Interval [", interval_name.to_upper(), "] / Pitch [", pitch, "]")

func play_random_pitch_variation():
	# Select a random interval
	var keys = musical_intervals.keys()
	var random_interval = keys[randi() % keys.size()]
	play_with_pitch_variation(random_interval)
	
func next_track_with_random_pitch():
	# Move to next track
	current_track_index = (current_track_index + 1) % bgm_tracks.size()
	
	# Play with random pitch variation
	play_random_pitch_variation()

func play_current_track():
	if bgm_tracks.size() > 0:
		var track = load(bgm_tracks[current_track_index])
		if track:
			bgm_player.stream = track
			bgm_player.play()
			print("Now playing: ", bgm_tracks[current_track_index])
		else:
			print("Failed to load track: ", bgm_tracks[current_track_index])
