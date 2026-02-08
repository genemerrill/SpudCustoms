extends Node
## SteamManager - STUB
##
## Stubbed to prevent crashes due to missing Steam integration.
## Implements methods called by Global.gd to avoid parse errors.

signal leaderboard_updated(entries: Array)
signal score_submitted(success: bool)
signal steam_status_changed(connected: bool)

# Property expected by SaveManager
var steam_init_success: bool = false


func _ready():
	LogManager.write_info("SteamManager: Stub initialized")
	emit_signal("steam_status_changed", false)


# Cloud save operations
func download_cloud_saves() -> bool:
	return false


func upload_cloud_saves() -> bool:
	return false


# Achievement handling
func check_achievements(total_shifts_completed: int, total_runners_stopped: int, perfect_hits: int, score: int, current_story_state: int) -> void:
	pass


# Update Steam stats
func update_steam_stats(total_shifts_completed: int, total_runners_stopped: int, perfect_hits: int, score: int) -> void:
	pass


# Leaderboards
func submit_score(score: int, difficulty: String = "Normal", shift: int = -1) -> bool:
	return false


func request_leaderboard_entries(difficulty: String = "Normal", shift: int = -1) -> bool:
	return false
