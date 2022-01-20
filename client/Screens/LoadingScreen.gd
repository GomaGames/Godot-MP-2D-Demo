extends Control

# Called when the node enters the scene tree for the first time.
func _ready():
	# Network.connect("session_connected", self, "_on_session_connected")

	var player_name := "test"
	
	var result: int = yield(Network.connect_to_server_async(), "completed")
	if result == OK:
		result = yield(Network.join_world_async(), "completed")
	if result == OK:
		# warning-ignore:return_value_discarded
		get_tree().change_scene_to(load("res://World.tscn"))
		Network.send_spawn(player_name)


# func _on_session_connected():
# 	get_tree().change_scene("res://World.tscn")
