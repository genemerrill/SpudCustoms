extends Control

@onready var status_label = %StatusLabel
@onready var grid_container = %GridContainer
@onready var restart_button = %RestartButton
@onready var exit_button = %ExitButton

var board = []
var current_player = 1 # 1 for X, 2 for O
var game_active = true
var buttons = []

func _ready():
	# Generate buttons dynamically if possible, or expect them in the scene
	# For simplicity, we'll expect them to be children of GridContainer
	# Check if GridContainer has children. If not, create them.
	_setup_grid()
	reset_game()

func _setup_grid():
	# Clear existing children if any
	for child in grid_container.get_children():
		child.queue_free()
	
	buttons = []
	for i in range(9):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(100, 100)
		btn.add_theme_font_size_override("font_size", 60)
		btn.name = "Button" + str(i)
		btn.pressed.connect(_on_button_pressed.bind(i))
		grid_container.add_child(btn)
		buttons.append(btn)

func _on_button_pressed(index):
	if not game_active or board[index] != 0:
		return
	
	board[index] = current_player
	buttons[index].text = "X" if current_player == 1 else "O"
	
	if check_win():
		status_label.text = ("Player X" if current_player == 1 else "Player O") + " Wins!"
		game_active = false
	elif 0 not in board:
		status_label.text = "Draw!"
		game_active = false
	else:
		current_player = 1 if current_player == 2 else 2
		status_label.text = "Player " + ("X" if current_player == 1 else "O") + "'s Turn"

func check_win():
	# Rows
	for i in range(0, 9, 3):
		if board[i] != 0 and board[i] == board[i+1] and board[i] == board[i+2]:
			return true
	# Columns
	for i in range(3):
		if board[i] != 0 and board[i] == board[i+3] and board[i] == board[i+6]:
			return true
	# Diagonals
	if board[0] != 0 and board[0] == board[4] and board[0] == board[8]:
		return true
	if board[2] != 0 and board[2] == board[4] and board[2] == board[6]:
		return true
	
	return false

func reset_game():
	board = []
	for i in range(9):
		board.append(0)
	
	for btn in buttons:
		btn.text = ""
	
	current_player = 1
	game_active = true
	status_label.text = "Player X's Turn"

func _on_restart_button_pressed():
	reset_game()

func _on_exit_button_pressed():
	# Reload Main Menu
	SceneLoader.load_scene("res://scenes/menus/main_menu/main_menu_with_animations.tscn")
