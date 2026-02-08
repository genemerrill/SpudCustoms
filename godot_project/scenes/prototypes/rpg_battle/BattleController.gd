extends Node2D

@export var unit_scene: PackedScene
@onready var units_container = %UnitsContainer
@onready var ui_turn_label = %TurnLabel
@onready var grid_overlay = %GridOverlay
@onready var ui_dex_label = %DexLabel
@onready var ui_attack_label = %AttackLabel
@onready var ui_defense_label = %DefenseLabel
@onready var ui_dice_container = %DiceContainer
@onready var ui_bones_container = %BonesContainer
@onready var ui_enemy_health_container = %HealthContainer
@onready var ui_archer_health_container = %ArcherHealthContainer
@onready var ui_hero_health_container = %HeroHealthContainer

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
var hero_unit = null # Track hero for UI updates
var melee_enemy = null # Track melee enemy for UI
var ranged_enemy = null # Track ranged enemy for UI
var battle_ended = false # Prevent duplicate end-game messages
var bones_container_orig_x = 0.0 # Store original X position for shake reset


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

	# Store original bones container position for shake reset
	if ui_bones_container:
		bones_container_orig_x = ui_bones_container.position.x

	# Defer battle setup to ensure everything is ready
	call_deferred("setup_demo_battle")


func setup_demo_battle():
	# Create demo units
	var hero_data = UnitData.new()
	hero_data.unit_name = "Potato Hero"
	hero_data.initiative = 10 # Highest - goes first
	hero_data.health = 5
	hero_data.max_health = 5
	hero_data.attack_dice = 3 # Up to 3 attack dice
	hero_data.defense_dice = 0 # Defense comes later

	var melee_enemy_data = UnitData.new()
	melee_enemy_data.unit_name = "Bad Spud"
	melee_enemy_data.initiative = 5 # Second
	melee_enemy_data.health = 8
	melee_enemy_data.max_health = 8
	melee_enemy_data.attack_dice = 1
	melee_enemy_data.defense_dice = 0

	var ranged_enemy_data = UnitData.new()
	ranged_enemy_data.unit_name = "Archer Spud"
	ranged_enemy_data.initiative = 3 # Third - goes last
	ranged_enemy_data.health = 3
	ranged_enemy_data.max_health = 3
	ranged_enemy_data.attack_dice = 1
	ranged_enemy_data.defense_dice = 0
	ranged_enemy_data.is_ranged = true
	ranged_enemy_data.min_attack_range = 2 # Can't hit adjacent

	# Positions: Hero bottom-left, Melee top-left, Ranged top-right
	hero_unit = spawn_unit(hero_data, Vector2i(0, 3))
	melee_enemy = spawn_unit(melee_enemy_data, Vector2i(0, 0), Color(0.7, 0.4, 0.4))
	ranged_enemy = spawn_unit(ranged_enemy_data, Vector2i(3, 0), Color(0.6, 0.3, 0.7))

	turn_manager.start_battle([hero_unit, melee_enemy, ranged_enemy])

	# Initialize all UI
	update_enemy_health_ui(melee_enemy)
	update_archer_health_ui(ranged_enemy)
	update_hero_health_ui(hero_unit)
	update_hero_stats_ui(hero_unit)

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

	# Find hero target
	var hero = null
	for unit in turn_manager.units:
		if unit.data.unit_name == "Potato Hero":
			hero = unit
			break

	if not hero:
		end_turn()
		return

	# Check if this is a ranged or melee AI
	if active_unit.data.is_ranged:
		await execute_ranged_ai(hero)
	else:
		await execute_melee_ai(hero)


func execute_melee_ai(hero):
	# Melee AI: Move towards hero, attack if adjacent
	if not is_adjacent(active_unit.grid_position, hero.grid_position):
		var best_move = get_best_move_towards(
			active_unit.grid_position,
			hero.grid_position,
		)
		if best_move != active_unit.grid_position:
			move_active_unit(best_move)
			print("Melee AI moved to ", best_move)
			await get_tree().create_timer(0.5).timeout

	if is_adjacent(active_unit.grid_position, hero.grid_position):
		attack_unit(active_unit, hero)
	else:
		print("Melee AI couldn't reach hero, ending turn.")
		end_turn()


func execute_ranged_ai(hero):
	# Ranged AI: Never moves, attacks if NOT adjacent (min range 2)
	var distance = calc_manhattan_dist(active_unit.grid_position, hero.grid_position)

	if distance >= active_unit.data.min_attack_range:
		# Can attack - fire arrow!
		await ranged_attack_unit(active_unit, hero)
	else:
		# Too close to attack
		print("Ranged AI: Hero too close! Skipping turn.")
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

		# Update appropriate health UI
		update_target_health_ui(target)

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


func ranged_attack_unit(attacker, target):
	print("\n--- RANGED COMBAT LOG ---")
	print("%s fires at %s!" % [attacker.data.unit_name, target.data.unit_name])

	# 1. Roll Attack Dice
	var hits = 0
	var dice_count = attacker.data.attack_dice

	for i in range(dice_count):
		var roll = randi_range(1, 6)
		if roll <= 4:
			hits += 1
			print("Die %d: HIT (%d)" % [i + 1, roll])
		else:
			print("Die %d: MISS (%d)" % [i + 1, roll])

	# 2. Roll Defense
	var blocks = 0
	for i in range(target.data.defense_dice):
		if randi_range(1, 6) <= 3:
			blocks += 1

	var total_damage = max(0, hits - blocks)

	# 3. Play arrow projectile animation
	await play_arrow_projectile(attacker, target)

	# 4. Apply Damage and show result
	if total_damage > 0:
		target.take_damage(total_damage)
		show_damage_number(target, total_damage)

		update_target_health_ui(target)

		if target.data.unit_name == "Potato Hero":
			trigger_screen_flash()
	else:
		show_miss_text(target)

	# 5. Check Death
	if target.current_health <= 0:
		print("%s has been defeated!" % target.data.unit_name)
		target.queue_free()
		turn_manager.units.erase(target)

	if check_battle_over():
		return

	end_turn()


func play_arrow_projectile(attacker, target):
	# Create arrow label
	var arrow = Label.new()
	arrow.text = "➤"
	arrow.add_theme_font_size_override("font_size", 32)
	arrow.add_theme_color_override("font_color", attacker.modulate)
	arrow.z_index = 100

	# Calculate direction and rotation
	var start_pos = attacker.position
	var end_pos = target.position
	var direction = (end_pos - start_pos).normalized()
	arrow.rotation = direction.angle()

	# Position arrow at attacker
	arrow.position = start_pos - Vector2(16, 16) # Center offset
	add_child(arrow)

	# Animate arrow flying to target
	var tween = create_tween()
	tween.tween_property(arrow, "position", end_pos - Vector2(16, 16), 0.4)
	await tween.finished

	# Flash arrow at impact
	var flash_tween = create_tween()
	flash_tween.tween_property(arrow, "modulate:a", 0.0, 0.15)
	await flash_tween.finished

	arrow.queue_free()


func show_miss_text(target):
	var miss_label = Label.new()
	miss_label.text = "MISS"
	miss_label.add_theme_font_size_override("font_size", 24)
	miss_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	miss_label.position = target.position + Vector2(-30, -60)
	miss_label.z_index = 100
	add_child(miss_label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(miss_label, "position:y", miss_label.position.y - 30, 0.6)
	tween.tween_property(miss_label, "modulate:a", 0.0, 0.6)
	await tween.finished
	miss_label.queue_free()


func check_battle_over() -> bool:
	# Prevent duplicate end-game messages
	if battle_ended:
		return true

	var hero_alive = false
	var baddies_alive = false

	for unit in turn_manager.units:
		if unit.data.unit_name == "Potato Hero":
			hero_alive = true
		else:
			baddies_alive = true

	if not hero_alive:
		battle_ended = true
		print("GAME OVER - Hero Defeated")
		show_end_screen("KO", Color(0.5, 0, 0, 0.6))
		return true

	if not baddies_alive:
		battle_ended = true
		print("VICTORY - All Baddies Defeated")
		show_end_screen("You Win\nThe Battle", Color(0, 0, 0, 0))
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
	var bones_ready = bones_meter >= 5

	for i in range(6):
		var bone_rect = ColorRect.new()
		bone_rect.custom_minimum_size = Vector2(25, 25)

		if i < bones_meter:
			if bones_ready:
				# Glowing golden when ready
				bone_rect.color = Color(1.0, 0.85, 0.2)
			else:
				bone_rect.color = Color(0.3, 0.3, 0.8)
		else:
			bone_rect.color = Color(0.2, 0.2, 0.2)

		ui_bones_container.add_child(bone_rect)

	# Animate shake when at 5+ bones
	if bones_ready:
		animate_bones_ready()


func animate_bones_ready():
	if not ui_bones_container:
		return

	# Use stored original position to prevent drift
	var shake_tween = create_tween()
	shake_tween.set_loops(3)
	var ox = bones_container_orig_x
	shake_tween.tween_property(ui_bones_container, "position:x", ox + 3, 0.05)
	shake_tween.tween_property(ui_bones_container, "position:x", ox - 3, 0.05)
	shake_tween.tween_property(ui_bones_container, "position:x", ox, 0.05)


func check_hero_glow(unit):
	if not is_instance_valid(unit):
		return
	if bones_meter >= 5:
		# Strong golden glow with sparkle effect
		unit.modulate = Color(1.6, 1.4, 0.8)
		animate_hero_sparkle(unit)
	else:
		unit.modulate = Color(1, 1, 1)


func animate_hero_sparkle(unit):
	if not is_instance_valid(unit):
		return

	# Create a sparkle/pulse effect
	var pulse_tween = create_tween()
	pulse_tween.set_loops(2)
	pulse_tween.tween_property(unit, "modulate", Color(1.8, 1.6, 1.0), 0.15)
	pulse_tween.tween_property(unit, "modulate", Color(1.6, 1.4, 0.8), 0.15)


func update_target_health_ui(target):
	# Route to correct health bar update based on target
	if target.data.unit_name == "Potato Hero":
		update_hero_health_ui(target)
	elif target.data.unit_name == "Archer Spud":
		update_archer_health_ui(target)
	else:
		update_enemy_health_ui(target)


func update_enemy_health_ui(enemy_unit):
	if not ui_enemy_health_container:
		return

	for child in ui_enemy_health_container.get_children():
		child.queue_free()

	# Max Health as total slots
	for i in range(enemy_unit.data.max_health):
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 25)

		if i < enemy_unit.current_health:
			rect.color = Color(0.8, 0.2, 0.2) # Red Health
		else:
			rect.color = Color(0.2, 0.2, 0.2) # Empty/Dead

		ui_enemy_health_container.add_child(rect)


func update_archer_health_ui(archer_unit):
	if not ui_archer_health_container:
		return

	for child in ui_archer_health_container.get_children():
		child.queue_free()

	for i in range(archer_unit.data.max_health):
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 25)

		if i < archer_unit.current_health:
			rect.color = Color(0.6, 0.3, 0.7) # Purple Health
		else:
			rect.color = Color(0.2, 0.2, 0.2) # Empty/Dead

		ui_archer_health_container.add_child(rect)


func update_hero_health_ui(unit):
	if not ui_hero_health_container:
		return

	for child in ui_hero_health_container.get_children():
		child.queue_free()

	for i in range(unit.data.max_health):
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 25)

		if i < unit.current_health:
			rect.color = Color(0.2, 0.8, 0.2) # Green Health
		else:
			rect.color = Color(0.2, 0.2, 0.2) # Empty/Dead

		ui_hero_health_container.add_child(rect)


func update_hero_stats_ui(unit):
	if ui_attack_label:
		ui_attack_label.text = "Attack: %d" % unit.data.attack_dice
	if ui_defense_label:
		ui_defense_label.text = "Defense: %d" % unit.data.defense_dice
