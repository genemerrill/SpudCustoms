extends Node2D

@export var unit_scene: PackedScene
@onready var units_container = %UnitsContainer
@onready var ui_turn_label = %TurnLabel
@onready var grid_overlay = %GridOverlay

var turn_manager
var tile_size = Vector2(100, 100) # Grid cell size
var grid_size = Vector2i(4, 4) # 4x4 Battle Mat (TMB Style)
var active_unit = null
enum Phase { MOVE, ACTION }
var current_phase = Phase.MOVE # Initialize
var hit_overlay: ColorRect


func _ready():
	turn_manager = preload("res://scripts/rpg/TurnManager.gd").new()
	add_child(turn_manager)
	turn_manager.turn_changed.connect(_on_turn_changed)

	# Create Hit Overlay for feedback
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hit_overlay = ColorRect.new()
	hit_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_overlay.color = Color(1, 0, 0, 0) # Transparent Red
	hit_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hit_overlay)

	# Defer battle setup to ensure everything is ready
	call_deferred("setup_demo_battle")


func setup_demo_battle():
	# Create demo units
	var hero_data = UnitData.new()
	hero_data.unit_name = "Potato Hero"
	hero_data.initiative = 4 # TMB Hero Init
	hero_data.health = 3 # TMB Hero HP
	hero_data.max_health = 3
	hero_data.attack_dice = 1
	hero_data.defense_dice = 1

	var enemy_data = UnitData.new()
	enemy_data.unit_name = "Bad Spud"
	enemy_data.initiative = 3 # TMB Baddie Init
	enemy_data.health = 2 # TMB Baddie HP
	enemy_data.max_health = 2
	enemy_data.attack_dice = 1
	enemy_data.defense_dice = 0

	# TMB positions: Baddie Top-Left (0,0), Hero Bottom-Left (0,3)
	# TMB positions: Baddie Top-Left (0,0), Hero Bottom-Left (0,3)
	var hero = spawn_unit(hero_data, Vector2i(0, 3))
	var enemy = spawn_unit(enemy_data, Vector2i(0, 0), Color(0.7, 0.4, 0.4)) # Dark Red tint for baddie

	turn_manager.start_battle([hero, enemy])

	# Configure GridLines (Fixes visibility)
	%GridLines.setup(grid_size, tile_size)


func spawn_unit(data: UnitData, grid_pos: Vector2i, tint: Color = Color.WHITE):
	var unit = unit_scene.instantiate()
	units_container.add_child(unit)
	unit.setup_unit(data)
	unit.modulate = tint # Apply visual distinction
	unit.grid_position = grid_pos
	unit.position = grid_to_world(grid_pos)
	return unit


func grid_to_world(grid_pos: Vector2i):
	# Center units in the tile
	return Vector2(grid_pos.x * tile_size.x + tile_size.x / 2, grid_pos.y * tile_size.y + tile_size.y / 2) + grid_overlay.position


func world_to_grid(world_pos: Vector2):
	var local_pos = world_pos - grid_overlay.position
	return Vector2i(local_pos.x / tile_size.x, local_pos.y / tile_size.y)


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if active_unit and active_unit.data.unit_name == "Potato Hero": # Player Turn Check
			var clicked_grid_pos = world_to_grid(event.position)

			if clicked_grid_pos.x >= 0 and clicked_grid_pos.x < grid_size.x and \
			clicked_grid_pos.y >= 0 and clicked_grid_pos.y < grid_size.y:
				# PHASE 1: MOVE
				if current_phase == Phase.MOVE:
					# Check for Single Click Attack (Enemy in range)
					var target = get_unit_at(clicked_grid_pos)
					if target and target != active_unit and is_adjacent(active_unit.grid_position, clicked_grid_pos):
						print("Hero attacks directly from Move phase!")
						attack_unit(active_unit, target)

					# Option A: Move to adjacent empty cell
					elif is_adjacent(active_unit.grid_position, clicked_grid_pos) and is_cell_empty(clicked_grid_pos):
						move_active_unit(clicked_grid_pos)

						# Auto-End Turn Check (If no enemies adjacent)
						if not has_adjacent_enemy(active_unit):
							print("No targets in range. Auto-ending turn.")
							end_turn()
						else:
							current_phase = Phase.ACTION
							print("Hero moved. Phase: ACTION")

					# Option B: Click self to skip move
					elif clicked_grid_pos == active_unit.grid_position:
						current_phase = Phase.ACTION
						print("Hero held position. Phase: ACTION")

				# PHASE 2: ACTION (Attack)
				elif current_phase == Phase.ACTION:
					if not is_cell_empty(clicked_grid_pos) and is_adjacent(active_unit.grid_position, clicked_grid_pos):
						var target = get_unit_at(clicked_grid_pos)
						if target and target != active_unit:
							attack_unit(active_unit, target)

					# Option B: Click self to Wait (Skip Attack)
					elif clicked_grid_pos == active_unit.grid_position:
						print("Hero waits. Turn Ended.")
						end_turn()


func has_adjacent_enemy(unit) -> bool:
	for other_unit in turn_manager.units:
		if other_unit != unit and is_adjacent(unit.grid_position, other_unit.grid_position):
			return true
	return false


func is_adjacent(pos1: Vector2i, pos2: Vector2i) -> bool:
	var diff = (pos1 - pos2).abs()
	return (diff.x + diff.y) == 1


func get_unit_at(grid_pos: Vector2i):
	for unit in turn_manager.units:
		if unit.grid_position == grid_pos:
			return unit
	return null


func is_cell_empty(grid_pos: Vector2i):
	for unit in turn_manager.units:
		if unit.grid_position == grid_pos:
			return false
	return true


func trigger_screen_flash():
	var tween = create_tween()
	tween.tween_property(hit_overlay, "color:a", 0.3, 0.1)
	tween.tween_property(hit_overlay, "color:a", 0.0, 0.2)


func trigger_unit_blink(unit):
	var tween = create_tween()
	var original_modulate = unit.modulate
	# Flash bright red/white
	tween.tween_property(unit, "modulate", Color(2, 2, 2), 0.1)
	tween.tween_property(unit, "modulate", original_modulate, 0.1)
	tween.tween_property(unit, "modulate", Color(2, 2, 2), 0.1)
	tween.tween_property(unit, "modulate", original_modulate, 0.1)


func move_active_unit(target_grid_pos: Vector2i):
	if active_unit:
		active_unit.grid_position = target_grid_pos
		active_unit.move_to_grid_pos(grid_to_world(target_grid_pos), tile_size)


func _on_turn_changed(new_unit):
	if active_unit:
		active_unit.set_selected(false)

	active_unit = new_unit
	active_unit.set_selected(true)
	current_phase = Phase.MOVE

	ui_turn_label.text = "Turn: " + active_unit.data.unit_name

	# AI Turn Trigger
	if active_unit.data.unit_name != "Potato Hero":
		print("AI Turn Started...")
		call_deferred("execute_ai_turn")


func execute_ai_turn():
	await get_tree().create_timer(1.0).timeout

	# Check if battle is already over before doing anything
	if check_battle_over():
		return

	# 1. AI Move Logic
	var hero = null
	for unit in turn_manager.units:
		if unit.data.unit_name == "Potato Hero":
			hero = unit
			break

	if hero:
		# If not adjacent, try to move closer
		if not is_adjacent(active_unit.grid_position, hero.grid_position):
			var best_move = get_best_move_towards(active_unit.grid_position, hero.grid_position)
			if best_move != active_unit.grid_position:
				move_active_unit(best_move)
				print("AI moved to ", best_move)
				await get_tree().create_timer(0.5).timeout

		# 2. AI Attack Logic
		if is_adjacent(active_unit.grid_position, hero.grid_position):
			attack_unit(active_unit, hero)
		else:
			print("AI couldn't reach hero, ending turn.")
			end_turn()
	else:
		end_turn()


func get_best_move_towards(current: Vector2i, target: Vector2i) -> Vector2i:
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var best_moves = []
	var min_dist = calc_manhattan_dist(current, target)

	for dir in directions:
		var next_pos = current + dir
		if is_valid_pos(next_pos) and is_cell_empty(next_pos):
			var dist = calc_manhattan_dist(next_pos, target)

			if dist < min_dist:
				min_dist = dist
				best_moves = [next_pos] # Found a new best distance, reset list
			elif dist == min_dist:
				best_moves.append(next_pos) # Found another move just as good

	if best_moves.size() > 0:
		return best_moves.pick_random()

	return current


func calc_manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y


func attack_unit(attacker, target):
	# ... (Logging) ...
	print("\n--- COMBAT LOG ---")
	print("%s attacks %s!" % [attacker.data.unit_name, target.data.unit_name])

	# ... (Dice Logic) ...
	var hits = 0
	for i in range(attacker.data.attack_dice):
		if randi_range(1, 6) <= 3:
			hits += 1

	var blocks = 0
	for i in range(target.data.defense_dice):
		if randi_range(1, 6) <= 3:
			blocks += 1

	var total_damage = max(0, hits - blocks)
	# ... (Print results) ...

	# 4. Apply Damage
	if total_damage > 0:
		target.take_damage(total_damage)

		# VISUAL FEEDBACK
		if target.data.unit_name == "Potato Hero":
			trigger_screen_flash()
		else:
			trigger_unit_blink(target)

	# 5. Check Death
	if target.current_health <= 0:
		print("%s has been defeated!" % target.data.unit_name)
		target.queue_free() # Actually free the unit node
		turn_manager.units.erase(target) # Remove from turn order

	if check_battle_over():
		return # Stop turn logic if battle ends

	end_turn()


func check_battle_over() -> bool:
	var hero_alive = false
	var baddies_alive = false

	for unit in turn_manager.units:
		if unit.data.unit_name == "Potato Hero":
			hero_alive = true
		else:
			baddies_alive = true

	if not hero_alive:
		print("GAME OVER - Hero Defeated")
		show_end_screen("KO", Color(0.5, 0, 0, 0.6)) # Red for KO
		return true
	elif not baddies_alive:
		print("VICTORY - All Baddies Defeated")
		show_end_screen("You Win\nThe Battle", Color(0, 0, 0, 0)) # No background color for Win (just text)
		return true

	return false


func show_end_screen(message: String, bg_color: Color):
	# 1. Kill any existing tweens (fixes the "Damage Flash hides KO screen" bug)
	var tweens = get_tree().get_processed_tweens()
	for t in tweens:
		t.kill()

	# 2. Update Overlay
	hit_overlay.color = bg_color

	# Add Label
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 80)
	label.set_anchors_preset(Control.PRESET_CENTER)
	hit_overlay.add_child(label)

	# Stop any further input/turns
	turn_manager.set_process(false)


func end_turn():
	if not check_battle_over():
		turn_manager.next_turn()


func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/menus/main_menu/main_menu_with_animations.tscn")
