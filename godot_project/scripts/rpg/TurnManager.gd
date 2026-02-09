extends Node

signal turn_changed(current_unit)
signal round_changed(round_number)

var units = []
var current_unit_index = 0
var current_round = 1


func start_battle(battle_units):
	# Units are already sorted by initiative from BattleController
	units = battle_units
	current_unit_index = 0
	current_round = 1
	emit_signal("round_changed", current_round)
	emit_signal("turn_changed", units[current_unit_index])


func next_turn():
	if units.is_empty():
		return

	current_unit_index = (current_unit_index + 1) % units.size()

	# Check if we've looped back to the start (new round)
	if current_unit_index == 0:
		current_round += 1
		emit_signal("round_changed", current_round)

	emit_signal("turn_changed", units[current_unit_index])


func get_current_unit():
	if units.is_empty():
		return null
	return units[current_unit_index]
