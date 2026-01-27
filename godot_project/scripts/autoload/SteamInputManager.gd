extends Node
## SteamInputManager - STUB
##
## Stubbed to prevent crashes due to missing Steam integration.

signal steam_input_initialized()
signal steam_input_failed(reason: String)
signal action_set_changed(action_set_name: String)
signal glyph_requested(action_name: String, glyph_path: String)

const ACTION_SET_MENU = "MenuControls"
const ACTION_SET_GAMEPLAY = "GameplayControls"
const ACTION_SET_DIALOGUE = "DialogueControls"

func _ready():
	emit_signal("steam_input_failed", "Steam integration stubbed")

func init() -> void:
	pass

func run() -> void:
	pass

func get_digital_action(action_name: String) -> bool:
	return false

func get_analog_action(action_name: String) -> Vector2:
	return Vector2.ZERO

func show_binding_panel(action_name: String) -> void:
	pass

func get_glyph_path(action_name: String) -> String:
	return ""

func trigger_haptic_pulse(duration_microsec: int = 0) -> void:
	pass

func set_action_set(set_name: String) -> void:
	pass
