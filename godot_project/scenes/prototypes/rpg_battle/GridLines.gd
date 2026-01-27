extends Node2D

var grid_size = Vector2i(4, 4)
var tile_size = Vector2(100, 100)

func setup(p_grid_size, p_tile_size):
	grid_size = p_grid_size
	tile_size = p_tile_size
	queue_redraw()

func _draw():
	# Draw TMB-style 4x4 grid
	# Note: Drawing relative to self (which is properly positioned in GridOverlay)
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2(x * tile_size.x + tile_size.x / 2, y * tile_size.y + tile_size.y / 2)
			
			# Draw slot circle
			draw_circle(pos, 40, Color(0.3, 0.3, 0.3, 0.5))
			draw_circle(pos, 42, Color(0.6, 0.6, 0.6), false, 2.0) # Border
			
			# Draw connections (Right and Down)
			if x < grid_size.x - 1:
				var right_pos = Vector2((x + 1) * tile_size.x + tile_size.x / 2, y * tile_size.y + tile_size.y / 2)
				draw_line(pos, right_pos, Color(0.5, 0.5, 0.5), 2.0)
			if y < grid_size.y - 1:
				var down_pos = Vector2(x * tile_size.x + tile_size.x / 2, (y + 1) * tile_size.y + tile_size.y / 2)
				draw_line(pos, down_pos, Color(0.5, 0.5, 0.5), 2.0)
