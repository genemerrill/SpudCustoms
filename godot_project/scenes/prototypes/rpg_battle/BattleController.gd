extends Node2D

@export var unit_scene: PackedScene
@onready var units_container = %UnitsContainer
@onready var ui_turn_label = %TurnLabel
@onready var grid_overlay = %GridOverlay

var turn_manager
var tile_size = Vector2(100, 100) # Grid cell size
var grid_size = Vector2i(6, 4) # 6x4 Battle Mat
var active_unit = null

func _ready():
	turn_manager = preload("res://scripts/rpg/TurnManager.gd").new()
	add_child(turn_manager)
	turn_manager.turn_changed.connect(_on_turn_changed)
	
	# Defer battle setup to ensure everything is ready
	call_deferred("setup_demo_battle")

func setup_demo_battle():
	# Create demo units
	var hero_data = UnitData.new()
	hero_data.unit_name = "Potato Hero"
	hero_data.initiative = 10
	hero_data.health = 20
	hero_data.max_health = 20
	
	var enemy_data = UnitData.new()
	enemy_data.unit_name = "Bad Spud"
	enemy_data.initiative = 5
	enemy_data.health = 15
	enemy_data.max_health = 15
	
	var hero = spawn_unit(hero_data, Vector2i(0, 1))
	var enemy = spawn_unit(enemy_data, Vector2i(5, 2))
	
	turn_manager.start_battle([hero, enemy])

func spawn_unit(data: UnitData, grid_pos: Vector2i):
	var unit = unit_scene.instantiate()
	units_container.add_child(unit)
	unit.setup_unit(data)
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
		if active_unit:
			var clicked_grid_pos = world_to_grid(event.position)
			
			# Check bounds
			if clicked_grid_pos.x >= 0 and clicked_grid_pos.x < grid_size.x and \
			   clicked_grid_pos.y >= 0 and clicked_grid_pos.y < grid_size.y:
				
				# Simplified movement logic: teleport to any empty cell
				if is_cell_empty(clicked_grid_pos):
					move_active_unit(clicked_grid_pos)

func is_cell_empty(grid_pos: Vector2i):
	for unit in turn_manager.units:
		if unit.grid_position == grid_pos:
			return false
	return true

func move_active_unit(target_grid_pos: Vector2i):
	if active_unit:
		active_unit.grid_position = target_grid_pos
		active_unit.move_to_grid_pos(grid_to_world(target_grid_pos), tile_size)
		end_turn()

func _on_turn_changed(new_unit):
	if active_unit:
		active_unit.set_selected(false)
	
	active_unit = new_unit
	active_unit.set_selected(true)
	
	ui_turn_label.text = "Turn: " + active_unit.data.unit_name

func end_turn():
	turn_manager.next_turn()

func _on_exit_button_pressed():
	SceneLoader.load_scene("res://scenes/menus/main_menu/main_menu_with_animations.tscn")
