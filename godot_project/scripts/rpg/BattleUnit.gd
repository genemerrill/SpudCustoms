extends Node2D

@export var data: Resource # UnitData

@onready var sprite = $Sprite2D
@onready var health_bar = $HealthBar
@onready var selection_indicator = $SelectionIndicator

var current_health: int
var grid_position: Vector2i = Vector2i.ZERO


func _ready():
	if data:
		setup_unit(data)
	selection_indicator.hide()


func setup_unit(unit_data):
	data = unit_data
	current_health = data.health
	health_bar.max_value = data.max_health
	health_bar.value = current_health

	if data.texture_path != "" and ResourceLoader.exists(data.texture_path):
		var tex = load(data.texture_path)
		if tex:
			sprite.texture = tex

	# Add ranged indicator icon if this is a ranged unit
	if data.is_ranged:
		var ranged_icon = Label.new()
		ranged_icon.text = "🏹"
		ranged_icon.add_theme_font_size_override("font_size", 14)
		ranged_icon.position = Vector2(health_bar.size.x / 2 + 15, -12)
		health_bar.add_child(ranged_icon)


func take_damage(amount):
	current_health -= amount
	current_health = max(0, current_health)
	health_bar.value = current_health
	if current_health <= 0:
		die()


func die():
	queue_free()


func set_selected(selected: bool):
	selection_indicator.visible = selected


func move_to_grid_pos(pos: Vector2, tile_size: Vector2):
	# Simplified movement animation
	var target_pos = pos
	position = target_pos
