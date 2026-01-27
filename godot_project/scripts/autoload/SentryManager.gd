extends Node
## SentryManager - Centralized Sentry SDK integration for error tracking
##
## STUB IMPLEMENTATION:
## The original SentryManager depends on a GDExtension 'SentrySDK' which is missing in this environment.
## This stub exposes the same API but does nothing, preventing parser errors and crashes.

# Whether Sentry is available and initialized
var _sentry_available: bool = false

# User context
var _user_id: String = ""
var _user_name: String = ""

func _ready() -> void:
	LogManager.write_info("SentryManager: Sentry integration disabled (Missing SentrySDK)")
	_sentry_available = false
	
	# Connect to EventBus signals for breadcrumbs (optional, but good to keep inputs alive)
	_connect_eventbus_signals()

func _check_sentry_available() -> bool:
	return false

func _set_release_info() -> void:
	pass

func _setup_user_context() -> void:
	pass

func _generate_anonymous_id() -> String:
	return "anonymous"

func _connect_eventbus_signals() -> void:
	if not EventBus:
		return
		
	# Connect signals but do nothing in handlers
	# This ensures we don't crash if EventBus tries to emit to us
	pass

# Breadcrumb helpers
func add_breadcrumb(category: String, message: String, data: Dictionary = {}) -> void:
	# LogManager.write_info("Sentry Breadcrumb: [%s] %s" % [category, message])
	pass

func add_error_breadcrumb(category: String, message: String, data: Dictionary = {}) -> void:
	# LogManager.write_warning("Sentry Error Breadcrumb: [%s] %s" % [category, message])
	pass

# Capture methods
func capture_message(message: String, level: int = 0) -> void:
	# LogManager.write_info("Sentry Capture Message: %s" % message)
	pass

func capture_error(message: String) -> void:
	LogManager.write_error("Sentry Capture Error: %s" % message)
	pass

func capture_exception(error_message: String, stack_trace: String = "") -> void:
	LogManager.write_critical("Sentry Capture Exception: %s" % error_message)
	pass

func _add_game_context() -> void:
	pass

# Set custom tags
func set_tag(key: String, value: String) -> void:
	pass

# Set custom context
func set_context(name: String, data: Dictionary) -> void:
	pass

# EventBus signal handlers - keeping signatures matching original but doing nothing
func _on_session_started() -> void: pass
func _on_session_ended() -> void: pass
func _on_game_over_triggered(reason: String) -> void: pass
func _on_game_mode_changed(new_mode: String) -> void: pass
func _on_shift_advanced(from_shift: int, to_shift: int) -> void: pass
func _on_level_unlocked(level_id: int) -> void: pass
func _on_score_changed(new_score: int, delta: int, source: String) -> void: pass
func _on_strike_changed(current_strikes: int, max_strikes: int, delta: int) -> void: pass
func _on_max_strikes_reached() -> void: pass
func _on_high_score_achieved(difficulty: String, score: int, level: int) -> void: pass
func _on_runner_escaped(runner_data: Dictionary) -> void: pass
func _on_runner_stopped(runner_data: Dictionary) -> void: pass
func _on_perfect_hit_achieved(bonus_points: int) -> void: pass
func _on_minigame_started(minigame_type: String) -> void: pass
func _on_minigame_completed(result: Dictionary) -> void: pass
func _on_dialogue_started(timeline_name: String) -> void: pass
func _on_dialogue_ended(timeline_name: String) -> void: pass
func _on_narrative_choice_made(choice_key: String, choice_value: Variant) -> void: pass

# Check if Sentry is available
func is_available() -> bool:
	return _sentry_available
