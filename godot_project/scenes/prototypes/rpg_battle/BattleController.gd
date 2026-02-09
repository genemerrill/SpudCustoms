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
@onready var ui_hero_health_label = %HeroHealthLabel
@onready var ui_initiative_container = %InitiativeContainer
@onready var ui_restart_button = $CanvasLayer/UI/RestartButton

# Audio Players
@onready var sfx_hero_melee = %HeroMelee
@onready var sfx_enemy_melee = %EnemyMelee
@onready var sfx_arrow = %Arrow
@onready var sfx_fireball = %Fireball
@onready var sfx_victory = %Victory
@onready var sfx_defeat = %Defeat

var turn_manager
var tile_size = Vector2(100, 100) # Grid cell size
var grid_size = Vector2i(4, 4) # 4x4 Battle Mat (TMB Style)
var active_unit = null
var current_dex: int = 0
var bones_meter: int = 0 # Track rolled bones (Max 6)
enum Phase { MOVE, ACTION }
var current_phase = Phase.MOVE # Initialize

# Battle phases
enum BattlePhase { DEPLOYMENT, INITIATIVE_ROLL, COMBAT }
var battle_phase = BattlePhase.DEPLOYMENT

var hit_overlay: ColorRect
var damage_label_pool = [] # Simple object pool for damage numbers
var stored_dice_results = [] # Persist dice state
var hero_unit = null # Track hero for UI updates
var melee_enemy = null # Track melee enemy for UI
var ranged_enemy = null # Track ranged enemy for UI
var battle_ended = false # Prevent duplicate end-game messages
var is_acting = false # Input lock during animations

# Deployment phase
var deployment_highlights = [] # Highlight rects for valid placement
var pending_hero_data = null # Hero data waiting for placement

# Initiative tracking
var initiative_order = [] # Units sorted by initiative
var rolled_init_values = { } # Stores the rolled init value per unit
var current_round = 1 # Current battle round


func _ready():
	turn_manager = preload("res://scripts/rpg/TurnManager.gd").new()
	add_child(turn_manager)
	turn_manager.turn_changed.connect(_on_turn_changed)
	turn_manager.round_changed.connect(_on_round_changed)

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
	# Configure GridLines first
	%GridLines.setup(grid_size, tile_size)

	# Create hero data with custom initiative die
	pending_hero_data = UnitData.new()
	pending_hero_data.unit_name = "Potato Hero"
	pending_hero_data.is_hero = true
	pending_hero_data.initiative_die = [3, 3, 2, 2, 4, 1] # Tank: slow but heavy
	pending_hero_data.health = 5
	pending_hero_data.max_health = 5
	pending_hero_data.attack_dice = 3
	pending_hero_data.defense_dice = 0
	pending_hero_data.dex = 3

	# Start deployment phase
	battle_phase = BattlePhase.DEPLOYMENT
	start_deployment_phase()

	# Print tactical battle debug commands
	print("")
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║           TACTICAL BATTLE DEBUG COMMANDS                     ║")
	print("╠══════════════════════════════════════════════════════════════╣")
	print("║  F1  - Fill Bones Meter                                      ║")
	print("╚══════════════════════════════════════════════════════════════╝")
	print("")


func start_deployment_phase():
	# Show deployment message
	ui_turn_label.text = "Deploy Potato Hero"

	# Highlight valid deployment cells (row 2 for melee heroes)
	for x in range(grid_size.x):
		var grid_pos = Vector2i(x, 2) # Row 2 = melee hero row
		var highlight = create_deployment_highlight(grid_pos)
		deployment_highlights.append(highlight)


func create_deployment_highlight(grid_pos: Vector2i) -> ColorRect:
	var highlight = ColorRect.new()
	highlight.size = tile_size - Vector2(8, 8)
	highlight.position = grid_to_world(grid_pos) - tile_size / 2 + Vector2(4, 4)
	highlight.color = Color(0.2, 0.9, 0.3, 0.6) # Bright green, more opaque
	highlight.z_index = 5 # Above grid lines
	highlight.set_meta("grid_pos", grid_pos)

	# Add to the scene at the grid level (not units_container)
	add_child(highlight)

	# Add a bright border using a second rect
	var border = ColorRect.new()
	border.size = tile_size - Vector2(4, 4)
	border.position = grid_to_world(grid_pos) - tile_size / 2 + Vector2(2, 2)
	border.color = Color(0.0, 1.0, 0.2, 0.9) # Bright green border
	border.z_index = 4
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# Make inner rect slightly smaller to create border effect
	highlight.z_index = 6

	# Store border for cleanup
	highlight.set_meta("border", border)

	# Pulse animation on the highlight
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(highlight, "color:a", 0.3, 0.4)
	tween.tween_property(highlight, "color:a", 0.7, 0.4)

	# Also pulse the border
	var tween2 = create_tween()
	tween2.set_loops()
	tween2.tween_property(border, "color:a", 0.5, 0.4)
	tween2.tween_property(border, "color:a", 1.0, 0.4)

	return highlight


func clear_deployment_highlights():
	for h in deployment_highlights:
		if is_instance_valid(h):
			# Also remove the border if it exists
			if h.has_meta("border"):
				var border = h.get_meta("border")
				if is_instance_valid(border):
					border.queue_free()
			h.queue_free()
	deployment_highlights.clear()


func deploy_hero_at(grid_pos: Vector2i):
	# Clear highlights
	clear_deployment_highlights()

	# Spawn hero at chosen position
	hero_unit = spawn_unit(pending_hero_data, grid_pos)
	pending_hero_data = null

	# Now spawn enemies
	spawn_enemies()

	# Roll initiative and start combat
	battle_phase = BattlePhase.INITIATIVE_ROLL
	roll_initiative()


func spawn_enemies():
	# Bad Spud (melee) - fixed initiative 1
	var melee_data = UnitData.new()
	melee_data.unit_name = "Bad Spud"
	melee_data.initiative = 1
	melee_data.health = 8
	melee_data.max_health = 8
	melee_data.attack_dice = 1
	melee_enemy = spawn_unit(melee_data, Vector2i(0, 1), Color(0.7, 0.4, 0.4))

	# Archer Spud (ranged) - fixed initiative 3
	var ranged_data = UnitData.new()
	ranged_data.unit_name = "Archer Spud"
	ranged_data.initiative = 3
	ranged_data.health = 3
	ranged_data.max_health = 3
	ranged_data.attack_dice = 1
	ranged_data.is_ranged = true
	ranged_data.min_attack_range = 2
	ranged_data.min_attack_range = 2
	ranged_data.defense_dice = 0 # Archer is squishy
	ranged_enemy = spawn_unit(ranged_data, Vector2i(3, 0), Color(0.6, 0.3, 0.7))

	# Update enemy UI
	update_enemy_health_ui(melee_enemy)
	update_archer_health_ui(ranged_enemy)


func roll_initiative():
	# Roll hero's custom die
	var hero_init = 0
	if hero_unit.data.initiative_die.size() > 0:
		var roll_idx = randi() % hero_unit.data.initiative_die.size()
		hero_init = hero_unit.data.initiative_die[roll_idx]
	else:
		hero_init = hero_unit.data.initiative

	print("Initiative Roll: Hero rolled %d" % hero_init)

	# Build initiative order
	var units_with_init = []
	units_with_init.append({ "unit": hero_unit, "init": hero_init, "is_hero": true })
	units_with_init.append({ "unit": melee_enemy, "init": melee_enemy.data.initiative, "is_hero": false })
	units_with_init.append({ "unit": ranged_enemy, "init": ranged_enemy.data.initiative, "is_hero": false })

	# Sort by initiative (highest first), ties go to hero
	units_with_init.sort_custom(
		func(a, b):
			if a.init != b.init:
				return a.init > b.init
			return a.is_hero # Hero wins ties
	)

	# Store sorted order and rolled values
	initiative_order.clear()
	rolled_init_values.clear()
	print("Initiative Order:")
	for i in range(units_with_init.size()):
		var entry = units_with_init[i]
		initiative_order.append(entry.unit)
		rolled_init_values[entry.unit] = entry.init
		print("  %d. %s (init %d)" % [i + 1, entry.unit.data.unit_name, entry.init])

	# Update UI and start combat
	update_hero_health_ui(hero_unit)
	update_hero_stats_ui(hero_unit)
	update_initiative_ui()

	battle_phase = BattlePhase.COMBAT
	turn_manager.start_battle(initiative_order)


func update_initiative_ui():
	# Clear existing slots
	for child in ui_initiative_container.get_children():
		child.queue_free()

	# Create a slot for each unit in initiative order
	for i in range(initiative_order.size()):
		var unit = initiative_order[i]
		if not is_instance_valid(unit):
			continue

		var slot = create_initiative_slot(unit, i)
		ui_initiative_container.add_child(slot)


func create_initiative_slot(unit, index: int) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(90, 60)
	slot.set_meta("unit", unit)

	# Color based on unit type
	var style = StyleBoxFlat.new()
	if unit == hero_unit:
		style.bg_color = Color(0.2, 0.5, 0.3) # Green for hero
	elif unit == ranged_enemy:
		style.bg_color = Color(0.4, 0.2, 0.5) # Purple for archer
	else:
		style.bg_color = Color(0.5, 0.25, 0.25) # Red for melee enemy
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	slot.add_theme_stylebox_override("panel", style)

	# Unit name label
	var name_label = Label.new()
	name_label.text = unit.data.unit_name.split(" ")[0] # First word only
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.position = Vector2(5, 5)
	name_label.size = Vector2(80, 20)
	slot.add_child(name_label)

	# Init value badge
	var init_label = Label.new()
	var init_val = unit.data.initiative
	if unit.data.is_hero and unit.data.initiative_die.size() > 0:
		# Show the rolled value (stored during roll_initiative)
		init_val = get_stored_init(unit)
	init_label.text = str(init_val)
	init_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	init_label.add_theme_font_size_override("font_size", 18)
	init_label.position = Vector2(5, 28)
	init_label.size = Vector2(80, 25)
	slot.add_child(init_label)

	# Selection Reticle (Yellow Border) - Initially hidden
	var reticle = Panel.new()
	reticle.name = "Reticle"
	reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var reticle_style = StyleBoxFlat.new()
	reticle_style.bg_color = Color(0, 0, 0, 0) # Transparent center
	reticle_style.border_width_left = 3
	reticle_style.border_width_top = 3
	reticle_style.border_width_right = 3
	reticle_style.border_width_bottom = 3
	reticle_style.border_color = Color(1, 1, 0) # Yellow
	reticle_style.corner_radius_top_left = 5
	reticle_style.corner_radius_top_right = 5
	reticle_style.corner_radius_bottom_left = 5
	reticle_style.corner_radius_bottom_right = 5

	reticle.add_theme_stylebox_override("panel", reticle_style)
	reticle.hide() # Hidden by default
	slot.add_child(reticle)

	return slot


func get_stored_init(unit) -> int:
	# Return stored value from roll, or fall back to unit data
	if rolled_init_values.has(unit):
		return rolled_init_values[unit]
	return unit.data.initiative


func highlight_active_initiative_slot():
	if not is_instance_valid(active_unit):
		return

	for slot in ui_initiative_container.get_children():
		var unit = slot.get_meta("unit") if slot.has_meta("unit") else null
		var reticle = slot.get_node_or_null("Reticle")

		if unit == active_unit:
			slot.modulate = Color(1.5, 1.5, 1.0) # Highlight active
			if reticle:
				reticle.show()
		else:
			slot.modulate = Color(0.7, 0.7, 0.7) # Dim others
			if reticle:
				reticle.hide()


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
		if is_acting:
			return
		var clicked_grid_pos = world_to_grid(event.position)

		# Handle deployment phase clicks
		if battle_phase == BattlePhase.DEPLOYMENT:
			# Check if clicked a valid deployment cell
			if clicked_grid_pos.y == 2 and clicked_grid_pos.x >= 0 and clicked_grid_pos.x < grid_size.x:
				deploy_hero_at(clicked_grid_pos)
			return

		# Combat phase: existing logic
		if active_unit and active_unit.data.unit_name == "Potato Hero": # Player Turn
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
							# attack_unit sets current_dex = 0, now check for turn end
							check_hero_turn_end()
						else:
							print("Not enough Dex to attack!")

				# Check for Move (Empty logic)
				elif is_cell_empty(clicked_grid_pos) and is_adjacent(active_unit.grid_position, clicked_grid_pos):
					if current_dex > 0:
						move_active_unit(clicked_grid_pos)
						current_dex -= 1
						print("Hero moved. usage: 1 Dex. Remaining: %d" % current_dex)
						update_dex_ui()
						check_hero_turn_end()
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


func check_hero_turn_end():
	# Check if hero's turn should end based on DEX consumption.
	# Central point for DEX-based turn ending, enabling end-of-turn effects.
	if current_dex <= 0:
		# === TIMING WINDOW: PRE_END_TURN ===
		# Future: trigger_pre_end_turn_effects()

		print("Dex exhausted. Turn Ended.")
		end_turn()


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
		is_acting = true
		active_unit.grid_position = target_grid_pos
		active_unit.move_to_grid_pos(grid_to_world(target_grid_pos), tile_size)
		is_acting = false


func _on_turn_changed(new_unit):
	if active_unit:
		active_unit.set_selected(false)

	active_unit = new_unit
	current_phase = Phase.MOVE
	current_dex = active_unit.data.dex
	update_dex_ui()

	# Update initiative tracker highlighting
	highlight_active_initiative_slot()

	ui_turn_label.text = "Round %d: %s" % [current_round, active_unit.data.unit_name]

	# Only show selection (yellow box) for hero when ready for input
	if active_unit.data.unit_name == "Potato Hero":
		active_unit.set_selected(true)
	else:
		# AI Turn - don't show selection, trigger AI
		print("AI Turn Started...")
		call_deferred("execute_ai_turn")


func _on_round_changed(round_number: int):
	current_round = round_number
	print("=== ROUND %d ===" % round_number)

	# At round 6, add red tinge for urgency
	if round_number >= 6:
		# Create subtle red background tinge
		var bg = get_node_or_null("Background")
		if bg:
			bg.modulate = Color(1.2, 0.9, 0.9) # Red tint
		# Also tint the grid overlay slightly
		if grid_overlay:
			grid_overlay.modulate = Color(1.1, 0.95, 0.95)


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
		await attack_unit(active_unit, hero)
		end_turn()
	else:
		print("Melee AI couldn't reach hero, ending turn.")
		end_turn()


func execute_ranged_ai(hero):
	# Ranged AI: Attacks if NOT adjacent (min range 2)
	# If too close, will move to one random adjacent open position first
	var distance = calc_manhattan_dist(active_unit.grid_position, hero.grid_position)

	if distance >= active_unit.data.min_attack_range:
		# Can attack - fire arrow!
		await ranged_attack_unit(active_unit, hero)
		end_turn()
	else:
		# Too close! Try to retreat to a random adjacent open position
		var retreat_pos = get_random_adjacent_open_position(active_unit.grid_position)

		if retreat_pos != active_unit.grid_position:
			# Move to retreat position
			move_active_unit(retreat_pos)
			print("Ranged AI retreated to ", retreat_pos)
			await get_tree().create_timer(0.5).timeout

			# Now check if we can attack from new position
			distance = calc_manhattan_dist(active_unit.grid_position, hero.grid_position)
			if distance >= active_unit.data.min_attack_range:
				await ranged_attack_unit(active_unit, hero)
			else:
				print("Ranged AI: Still too close after retreat!")
			end_turn()
		else:
			# No retreat position available, can't attack
			print("Ranged AI: Cornered! Can't escape or attack.")
			end_turn()


func get_random_adjacent_open_position(from_pos: Vector2i) -> Vector2i:
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	directions.shuffle()

	for dir in directions:
		var new_pos = from_pos + dir
		# Check bounds
		if new_pos.x >= 0 and new_pos.x < grid_size.x and \
		new_pos.y >= 0 and new_pos.y < grid_size.y:
			# Check if empty
			if is_cell_empty(new_pos):
				return new_pos

	# No open position found
	return from_pos


func get_best_move_towards(current: Vector2i, target: Vector2i) -> Vector2i:
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var best_moves = []
	var current_dist = calc_manhattan_dist(current, target)
	var min_dist = current_dist

	for dir in directions:
		var next_pos = current + dir
		if is_valid_pos(next_pos) and is_cell_empty(next_pos):
			var dist = calc_manhattan_dist(next_pos, target)

			# STRICT: Only consider moves that REDUCE the distance
			if dist < current_dist:
				if dist < min_dist:
					min_dist = dist
					best_moves = [next_pos] # Found a new best distance, reset list
				elif dist == min_dist:
					best_moves.append(next_pos) # Found another move just as good (e.g. diagonal path option)

	if best_moves.size() > 0:
		return best_moves.pick_random()

	# If no moves reduce distance, stay put (don't wander aimlessly)
	return current


func calc_manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y


func attack_unit(attacker, target):
	is_acting = true
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

	# Capture bones count BEFORE rolling (for INSTA-KILL check)
	var bones_at_attack_start = bones_meter

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
			is_acting = false
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
				icon.add_theme_font_size_override("font_size", 36)
				icon.add_theme_color_override("font_color", Color.WHITE)
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
	var used_insta_kill = false

	# BONES ULTIMATE CHECK - uses bones count from BEFORE attack
	var is_hero = attacker.data.unit_name == "Potato Hero"
	if is_hero and bones_at_attack_start >= 5 and total_damage > 0:
		print("BONES ULTIMATE! INSTA-KILL!")
		used_insta_kill = true

		# Reset Bones after using Ultimate, then add back bones from THIS attack
		var bones_from_this_attack = bones_meter - bones_at_attack_start
		bones_meter = bones_from_this_attack
		update_bones_ui()
		check_hero_glow(attacker)

	# ... (Print results) ...

	# 4. Apply Damage or INSTA-KILL
	if used_insta_kill:
		# INSTA-KILL bypasses health - directly removes enemy from battle
		sfx_fireball.play()
		show_insta_kill_text(target)
		print("%s was INSTA-KILLED!" % target.data.unit_name)
		await play_flame_dissolve(target)
		target.queue_free()
		turn_manager.units.erase(target)
		update_target_health_ui(target)
	elif total_damage > 0:
		# Play melee attack sound based on attacker
		if attacker.data.unit_name == "Potato Hero":
			sfx_hero_melee.play()
		else:
			sfx_enemy_melee.play()
		target.take_damage(total_damage)
		show_damage_number(target, total_damage)

		# Update appropriate health UI
		update_target_health_ui(target)

		# VISUAL FEEDBACK
		if target.data.unit_name == "Potato Hero":
			trigger_screen_flash()
		else:
			trigger_unit_blink(target)
			trigger_unit_blink(target)
	elif hits > 0 and total_damage == 0:
		# Hits were fully blocked!
		var block_color = Color(0.3, 0.3, 0.9) # Blue for blocked
		show_blocked_text(target, block_color)
	else:
		# Miss! Show miss text with attacker's color theme
		var miss_color = Color(0.9, 0.3, 0.3) \
		if attacker.data.unit_name == "Bad Spud" else Color(0.7, 0.7, 0.7)
		show_miss_text(target, miss_color)

	# 5. Check Death (only for normal damage, not INSTA-KILL)
	if not used_insta_kill and target.current_health <= 0:
		print("%s has been defeated!" % target.data.unit_name)
		target.queue_free() # Actually free the unit node
		turn_manager.units.erase(target) # Remove from turn order

	if check_battle_over():
		is_acting = false
		return # Stop turn logic if battle ends

	is_acting = false
	# Turn ending is handled by the caller based on DEX consumption
	# This allows for future "end of turn" effects to be triggered


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

	# 3. Play arrow projectile animation and sound
	sfx_arrow.play()
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

	# Turn ending is handled by the caller


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


func play_flame_dissolve(target):
	# DRAMATIC INSTA-KILL EFFECT!
	# 1. Bright white screen flash
	trigger_white_flash()

	# 2. Create flame overlay on target
	var sprite = target.get_node_or_null("Sprite2D")
	if not sprite:
		await get_tree().create_timer(0.5).timeout
		return

	# Create a bright flame-colored overlay
	var flame_overlay = ColorRect.new()
	flame_overlay.color = Color(1.0, 0.6, 0.1, 0.9) # Bright orange
	flame_overlay.size = Vector2(120, 120)
	flame_overlay.position = Vector2(-60, -60) # Center on sprite
	flame_overlay.z_index = 10
	sprite.add_child(flame_overlay)

	# Make target glow bright orange/yellow
	target.modulate = Color(3.0, 2.0, 0.5) # Very bright!

	# Animate: scale up, flash colors, then shrink and fade
	var tween = create_tween()
	tween.set_parallel(true)

	# Scale up dramatically
	tween.tween_property(target, "scale", Vector2(1.5, 1.5), 0.15)

	# Flash the overlay through flame colors
	tween.tween_property(flame_overlay, "color", Color(1.0, 1.0, 0.3, 1.0), 0.1) # Yellow flash

	await get_tree().create_timer(0.15).timeout

	# Second phase: shrink and burn away
	var tween2 = create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(target, "scale", Vector2(0.0, 0.0), 0.4).set_ease(Tween.EASE_IN)
	tween2.tween_property(target, "modulate:a", 0.0, 0.4)
	tween2.tween_property(flame_overlay, "color", Color(0.8, 0.2, 0.0, 0.0), 0.4) # Fade to red then gone

	await tween2.finished
	flame_overlay.queue_free()


func trigger_white_flash():
	# Create a bright white flash that covers the whole screen
	var flash_layer = CanvasLayer.new()
	flash_layer.layer = 100
	add_child(flash_layer)

	var white_rect = ColorRect.new()
	white_rect.color = Color(1, 1, 1, 0.9) # Bright white
	white_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	white_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_layer.add_child(white_rect)

	# Quick flash: fade out rapidly
	var tween = create_tween()
	tween.tween_property(white_rect, "color:a", 0.0, 0.25)
	tween.tween_callback(flash_layer.queue_free)


func show_blocked_text(target, color: Color = Color(0.3, 0.3, 0.9)):
	var label = Label.new()
	label.text = "BLOCKED"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.position = target.position + Vector2(-40, -60)
	label.z_index = 100
	add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	await tween.finished
	label.queue_free()


func show_miss_text(target, color: Color = Color(0.7, 0.7, 0.7)):
	var miss_label = Label.new()
	miss_label.text = "MISS"
	miss_label.add_theme_font_size_override("font_size", 24)
	miss_label.add_theme_color_override("font_color", color)
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
		sfx_defeat.play()
		show_end_screen("KO", Color(0.5, 0, 0, 0.6))
		return true

	if not baddies_alive:
		battle_ended = true
		print("VICTORY - All Baddies Defeated")
		sfx_victory.play()
		# Sepia/warm grey overlay for victory
		show_end_screen("You Win\nThe Battle", Color(0.4, 0.35, 0.25, 0.5))
		pulse_restart_button()
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


func pulse_restart_button():
	# Pulse the restart button green to draw user attention
	if not ui_restart_button:
		return

	# Set initial green tint
	ui_restart_button.modulate = Color(0.5, 1.0, 0.5)

	# Create pulsing animation
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(ui_restart_button, "modulate", Color(0.3, 1.0, 0.3), 0.4)
	tween.tween_property(ui_restart_button, "modulate", Color(0.7, 1.0, 0.7), 0.4)


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
			die_rect.custom_minimum_size = Vector2(40, 40)
			die_rect.pivot_offset = Vector2(20, 20) # Center pivot for shake

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
				icon.add_theme_font_size_override("font_size", 36)
				icon.add_theme_color_override("font_color", Color.WHITE)
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


func show_insta_kill_text(target):
	var label = Label.new()
	label.text = "☠ INSTA-KILL! ☠"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2)) # Golden
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.global_position = target.global_position + Vector2(-60, -60)
	add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y - 50, 1.0) \
	.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)


func update_bones_ui():
	if not ui_bones_container:
		return

	# Clear existing bone markers
	for child in ui_bones_container.get_children():
		child.queue_free()

	# Max bones is 6 (assumed for now)
	var bones_ready = bones_meter >= 5

	# Load sparkle shader for ready state
	var sparkle_shader = null
	if bones_ready:
		sparkle_shader = load("res://scenes/prototypes/rpg_battle/shaders/bones_sparkle.gdshader")

	for i in range(6):
		var bone_rect = ColorRect.new()
		bone_rect.custom_minimum_size = Vector2(25, 25)

		if i < bones_meter:
			if bones_ready:
				# Glowing golden with sparkle shader
				bone_rect.color = Color(1.0, 0.85, 0.2)
				if sparkle_shader:
					var mat = ShaderMaterial.new()
					mat.shader = sparkle_shader
					mat.set_shader_parameter("time_offset", i * 0.5)
					mat.set_shader_parameter("intensity", 1.5)
					bone_rect.material = mat
			else:
				bone_rect.color = Color(0.3, 0.3, 0.8)
		else:
			bone_rect.color = Color(0.2, 0.2, 0.2)

		ui_bones_container.add_child(bone_rect)

# Shake animation removed - HBoxContainer center alignment makes position
# manipulation unreliable. Golden glow is the primary visual indicator now.


func check_hero_glow(unit):
	if not is_instance_valid(unit):
		return

	var sprite = unit.get_node_or_null("Sprite2D")
	if not sprite:
		return

	if bones_meter >= 5:
		# Apply dramatic sparkle shader to hero sprite
		if not sprite.material or not sprite.material is ShaderMaterial:
			var sparkle_shader = load("res://scenes/prototypes/rpg_battle/shaders/bones_sparkle.gdshader")
			var mat = ShaderMaterial.new()
			mat.shader = sparkle_shader
			mat.set_shader_parameter("intensity", 2.5)
			sprite.material = mat
		# Also boost modulate for extra brightness
		unit.modulate = Color(1.4, 1.3, 1.0)
	else:
		# Remove shader when not ready
		sprite.material = null
		unit.modulate = Color(1, 1, 1)


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

	# Determine warning colors based on current health
	var warning_color = Color(0.2, 0.2, 0.2) # Default grey for spent health
	var label_color = Color(0.6, 0.6, 0.6) # Default grey for label

	if unit.current_health == 1:
		# CRITICAL - Red warning
		warning_color = Color(0.9, 0.2, 0.2)
		label_color = Color(1.0, 0.3, 0.3)
	elif unit.current_health == 2:
		# LOW - Yellow warning
		warning_color = Color(0.9, 0.8, 0.2)
		label_color = Color(1.0, 0.9, 0.3)

	# Update Health label color
	if ui_hero_health_label:
		ui_hero_health_label.add_theme_color_override("font_color", label_color)

	for i in range(unit.data.max_health):
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(20, 25)

		if i < unit.current_health:
			rect.color = Color(0.2, 0.8, 0.2) # Green Health
		else:
			rect.color = warning_color # Spent - uses warning color

		ui_hero_health_container.add_child(rect)


func update_hero_stats_ui(unit):
	if ui_attack_label:
		ui_attack_label.text = "Attack: %d" % unit.data.attack_dice
	if ui_defense_label:
		ui_defense_label.text = "Defense: %d" % unit.data.defense_dice
