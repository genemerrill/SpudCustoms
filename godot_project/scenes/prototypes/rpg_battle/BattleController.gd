extends Node2D

@export var unit_scene: PackedScene
@onready var units_container = %UnitsContainer
@onready var ui_turn_label = %TurnLabel
@onready var grid_overlay = %GridOverlay
@onready var ui_dex_label = %DexLabel
@onready var ui_dice_container = %DiceContainer
@onready var ui_bones_container = %BonesContainer
@onready var ui_enemy_health_container = %HealthContainer

var turn_manager
var tile_size = Vector2(100, 100) # Grid cell size
var grid_size = Vector2i(4, 4) # 4x4 Battle Mat (TMB Style)
var active_unit = null
var current_dex: int = 0
var bones_meter: int = 0 # Track rolled bones (Max 6)
enum Phase { MOVE, ACTION }
var current_phase = Phase.MOVE # Initialize
var hit_overlay: ColorRect
var damage_label_pool = [] # Simple object pool for damage numbers
var stored_dice_results = [] # Persist dice state [true(Hit), false(Bone), null(Empty)]


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
	enemy_data.health = 10 # Beefy Baddie
	enemy_data.max_health = 10
	enemy_data.attack_dice = 1
	enemy_data.defense_dice = 0

	# TMB positions: Baddie Top-Left (0,0), Hero Bottom-Left (0,3)
	var hero = spawn_unit(hero_data, Vector2i(0, 3))
	var enemy = spawn_unit(enemy_data, Vector2i(0, 0), Color(0.7, 0.4, 0.4)) # Dark Red tint for baddie

	turn_manager.start_battle([hero, enemy])
	update_enemy_health_ui(enemy)

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
	var x = grid_pos.x * tile_size.x + tile_size.x / 2
	var y = grid_pos.y * tile_size.y + tile_size.y / 2
	return Vector2(x, y) + grid_overlay.position


func world_to_grid(world_pos: Vector2):
	var local_pos = world_pos - grid_overlay.position
	return Vector2i(local_pos.x / tile_size.x, local_pos.y / tile_size.y)


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if active_unit and active_unit.data.unit_name == "Potato Hero": # Player Turn Check
			var clicked_grid_pos = world_to_grid(event.position)

			if clicked_grid_pos.x >= 0 and clicked_grid_pos.x < grid_size.x and \
			clicked_grid_pos.y >= 0 and clicked_grid_pos.y < grid_size.y:
				# Check for Attack (Target logic)
				if not is_cell_empty(clicked_grid_pos) and is_adjacent(active_unit.grid_position, clicked_grid_pos):
					var target = get_unit_at(clicked_grid_pos)
					if target and target != active_unit:
						# Attack consumes ALL remaining Dex
						if current_dex > 0:
							print("Hero attacks with %d Dex!" % current_dex)
							await attack_unit(active_unit, target)
							# Note: attack_unit already sets current_dex = 0
							end_turn() # End turn after attack completes
						else:
							print("Not enough Dex to attack!")

				# Check for Move (Empty logic)
				elif is_cell_empty(clicked_grid_pos) and is_adjacent(active_unit.grid_position, clicked_grid_pos):
					if current_dex > 0:
						move_active_unit(clicked_grid_pos)
						current_dex -= 1
						print("Hero moved. usage: 1 Dex. Remaining: %d" % current_dex)
						update_dex_ui()

						if current_dex <= 0:
							print("Dex exhausted after move. Turn Ended.")
							end_turn()
					else:
						print("Not enough Dex to move!")

				# Check for Wait (Click Self)
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
	current_dex = active_unit.data.dex
	update_dex_ui()

	ui_turn_label.text = "Turn: %s" % [active_unit.data.unit_name]

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

	# 1. Roll Attack Dice
	var hits = 0
	var dice_count = attacker.data.attack_dice
	var dice_results = [] # Store boolean IsHit for animation

	# Override for Hero using Dex system
	if attacker.data.unit_name == "Potato Hero":
		dice_count = current_dex # Use remaining Dex as dice pool
		current_dex = 0 # Consume all Dex

	print("%s Attack Rolls (%d dice):" % [attacker.data.unit_name, dice_count])

	for i in range(dice_count):
		var roll = randi_range(1, 6)
		if roll <= 4: # 4 Hits (1-4)
			hits += 1
			dice_results.append(true)
			print("Die %d: HIT (%d)" % [i + 1, roll])
		else: # 2 Bones (5-6)
			dice_results.append(false)
			print("Die %d: BONE (%d)" % [i + 1, roll])
			# Player Logic for bones
			if attacker.data.unit_name == "Potato Hero":
				bones_meter = min(bones_meter + 1, 6)

	# Animate Dice UI if player
	if attacker.data.unit_name == "Potato Hero":
		# 1. Clear stored results and rebuild blank dice
		stored_dice_results = []
		update_dex_ui()
		await get_tree().process_frame # Wait for queue_free to complete

		# 2. Sequential Roll Animation: Each die shakes then reveals
		if not is_instance_valid(ui_dice_container):
			print("[DEBUG] ui_dice_container is invalid, returning early!")
			return
		var children = ui_dice_container.get_children()
		print("[DEBUG] dice_count=%d, children.size()=%d" % [dice_count, children.size()])

		for i in range(dice_count):
			print("[DEBUG] Animation loop i=%d" % i)
			if i < children.size():
				var die_rect = children[i]

				# Safety check: skip if node was freed
				if not is_instance_valid(die_rect):
					print("[DEBUG] die_rect[%d] is invalid, skipping!" % i)
					continue

				# Add "?" placeholder
				for c in die_rect.get_children():
					c.queue_free()
				var q_label = Label.new()
				q_label.text = "?"
				q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				q_label.set_anchors_preset(Control.PRESET_FULL_RECT)
				die_rect.add_child(q_label)

				# Shake animation
				var shake_tween = create_tween()
				shake_tween.set_loops(4)
				shake_tween.tween_property(die_rect, "rotation", 0.15, 0.05)
				shake_tween.tween_property(die_rect, "rotation", -0.15, 0.05)
				await shake_tween.finished

				# Safety check after await
				if not is_instance_valid(die_rect):
					stored_dice_results.append(dice_results[i])
					continue

				die_rect.rotation = 0.0

				# Reveal this die's result
				stored_dice_results.append(dice_results[i])

				# Update just this die visually
				for c in die_rect.get_children():
					c.queue_free()
				var result = dice_results[i]
				var icon_text = "⚔" if result else "☠"
				var base_color = Color(0.2, 0.8, 0.2) if result else Color(0.5, 0.5, 0.8)
				die_rect.color = base_color

				var icon = Label.new()
				icon.text = icon_text
				icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				icon.set_anchors_preset(Control.PRESET_FULL_RECT)
				die_rect.add_child(icon)

				await get_tree().create_timer(0.15).timeout # Brief pause between dice

		update_bones_ui()
		check_hero_glow(attacker)

		await get_tree().create_timer(0.3).timeout # Final pause before damage

	var blocks = 0
	for i in range(target.data.defense_dice):
		if randi_range(1, 6) <= 3:
			blocks += 1

	var total_damage = max(0, hits - blocks)

	# BONES ULTIMATE CHECK
	var is_hero = attacker.data.unit_name == "Potato Hero"
	if is_hero and bones_meter >= 5 and total_damage > 0:
		print("BONES ULTIMATE! INSTA-KILL!")
		total_damage = target.data.max_health # Overkill

		# Reset Bones after using Ultimate
		bones_meter = 0
		update_bones_ui()
		check_hero_glow(attacker)

	# ... (Print results) ...

	# 4. Apply Damage
	if total_damage > 0:
		target.take_damage(total_damage)
		show_damage_number(target, total_damage)

		# Update UI if enemy
		if target.data.unit_name != "Potato Hero":
			update_enemy_health_ui(target)

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

	# If Player (Potato Hero), we need to end turn explicitly after the long animation sequence
	if attacker.data.unit_name == "Potato Hero":
		end_turn()
	# AI calls end_turn() in its own logic if not attacking, but if it attacks, it falls here too.
	# So we can just call end_turn() generally.
	else:
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


func _on_restart_button_pressed():
	get_tree().reload_current_scene()


func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/menus/main_menu/main_menu_with_animations.tscn")


func update_dex_ui():
	# Always ensure visibility
	if ui_dex_label:
		ui_dex_label.visible = true
	if ui_dice_container:
		ui_dice_container.visible = true
	if ui_bones_container:
		ui_bones_container.visible = true

	# Only REBUILD the Dex/Dice pool if it is the Hero's turn.
	if active_unit and active_unit.data.unit_name == "Potato Hero":
		ui_dex_label.text = "Dex: %d / %d" % [current_dex, active_unit.data.dex]

		# Clear existing dice
		for child in ui_dice_container.get_children():
			child.queue_free()

		# Rebuild dice pool with stored results
		for i in range(active_unit.data.dex):
			var die_rect = ColorRect.new()
			die_rect.custom_minimum_size = Vector2(30, 30)
			die_rect.pivot_offset = Vector2(15, 15) # Center pivot for shake

			var is_active = i < current_dex
			var result = null
			if i < stored_dice_results.size():
				result = stored_dice_results[i]

			var icon_text = ""
			var base_color = Color(0.8, 0.8, 0.8) # Default Grey

			if result == true: # Hit
				base_color = Color(0.2, 0.8, 0.2) # Green
				icon_text = "⚔"
			elif result == false: # Bone
				base_color = Color(0.5, 0.5, 0.8) # Blueish
				icon_text = "☠"

			# Apply Active/Spent Logic
			if is_active:
				die_rect.color = base_color
			else:
				die_rect.color = base_color.darkened(0.6) # Dimmed

			# Add Icon if present
			if icon_text != "":
				var icon = Label.new()
				icon.text = icon_text
				icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				icon.set_anchors_preset(Control.PRESET_FULL_RECT)
				if not is_active:
					icon.modulate = Color(0.5, 0.5, 0.5) # Dim icon too
				die_rect.add_child(icon)

			ui_dice_container.add_child(die_rect)

	update_bones_ui()


func show_damage_number(target, amount):
	var label = Label.new()
	label.text = str(amount)
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1, 0, 0)) # Red
	label.global_position = target.global_position + Vector2(0, -60)
	add_child(label)

	var tween = create_tween()
	tween.tween_property(
		label,
		"global_position:y",
		\
		label.global_position.y - 40,
		0.8,
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func update_bones_ui():
	if not ui_bones_container:
		return

	# Clear existing bone markers
	for child in ui_bones_container.get_children():
		child.queue_free()

	# Max bones is 6 (assumed for now)
	for i in range(6):
		var bone_rect = ColorRect.new()
		bone_rect.custom_minimum_size = Vector2(25, 25)

		if i < bones_meter:
			bone_rect.color = Color(0.3, 0.3, 0.8) # Blue/Bone Color
		else:
			bone_rect.color = Color(0.2, 0.2, 0.2) # Empty slot

		ui_bones_container.add_child(bone_rect)


func check_hero_glow(hero_unit):
	if not is_instance_valid(hero_unit):
		return
	if bones_meter >= 5:
		hero_unit.modulate = Color(1.5, 1.5, 1.2) # Glow
	else:
		hero_unit.modulate = Color(1, 1, 1)


func update_enemy_health_ui(enemy_unit):
	if not ui_enemy_health_container:
		return

	for child in ui_enemy_health_container.get_children():
		child.queue_free()

	# Max Health as total slots (10)
	for i in range(enemy_unit.data.max_health):
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 25)

		if i < enemy_unit.current_health:
			rect.color = Color(0.8, 0.2, 0.2) # Red Health
		else:
			rect.color = Color(0.2, 0.2, 0.2) # Empty/Dead

		ui_enemy_health_container.add_child(rect)
