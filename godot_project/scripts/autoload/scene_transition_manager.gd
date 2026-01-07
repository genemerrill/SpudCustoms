# scene_transition_manager.gd
extends Node

# Signal when transition is complete
signal transition_completed

# Reference to a full-screen fade rectangle
var fade_rect: ColorRect


func _ready():
	# Create the fade rect as a child of a CanvasLayer to ensure it covers everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 128
	add_child(canvas_layer)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.anchors_preset = Control.PRESET_FULL_RECT
	canvas_layer.add_child(fade_rect)


# Transition to a new scene with fade (uses threaded loading to prevent main thread hangs)
func transition_to_scene(scene_path: String):
	# Fade out
	var fade_tween = create_tween()
	fade_tween.tween_property(fade_rect, "color", Color(0, 0, 0, 1), 0.5)
	await fade_tween.finished

	# Start threaded scene load to prevent main thread blocking
	var err = ResourceLoader.load_threaded_request(scene_path)
	if err == OK:
		# Wait for load to complete with timeout to prevent infinite hang
		var timeout: float = 30.0
		var elapsed: float = 0.0
		while elapsed < timeout:
			var status = ResourceLoader.load_threaded_get_status(scene_path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var scene_resource = ResourceLoader.load_threaded_get(scene_path)
				var new_scene = scene_resource.instantiate()
				var root = get_tree().root
				var current_scene = get_tree().current_scene
				if current_scene:
					root.remove_child(current_scene)
					current_scene.queue_free()
				root.add_child(new_scene)
				get_tree().current_scene = new_scene
				break
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("Failed to load scene: " + scene_path + ", using fallback")
				get_tree().change_scene_to_file(scene_path)
				break
			await get_tree().create_timer(0.016).timeout
			elapsed += 0.016
		if elapsed >= timeout:
			push_error("Scene load timeout after 30s, using fallback: " + scene_path)
			get_tree().change_scene_to_file(scene_path)
	else:
		# Fallback to direct scene change if threaded request fails
		get_tree().change_scene_to_file(scene_path)

	# Fade back in
	fade_tween = create_tween()
	fade_tween.tween_property(fade_rect, "color", Color(0, 0, 0, 0), 0.5)
	await fade_tween.finished

	emit_signal("transition_completed")


# Reload the current scene
func reload_current_scene():
	transition_to_scene(get_tree().current_scene.scene_file_path)
