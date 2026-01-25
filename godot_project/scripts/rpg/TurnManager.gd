extends Node

signal turn_changed(current_unit)

var units = []
var current_unit_index = 0

func start_battle(battle_units):
	units = battle_units
	# Sort by initiative descending
	units.sort_custom(func(a, b): return a.data.initiative > b.data.initiative)
	current_unit_index = 0
	emit_signal("turn_changed", units[current_unit_index])

func next_turn():
	if units.is_empty():
		return
	
	current_unit_index = (current_unit_index + 1) % units.size()
	emit_signal("turn_changed", units[current_unit_index])

func get_current_unit():
	if units.is_empty():
		return null
	return units[current_unit_index]
