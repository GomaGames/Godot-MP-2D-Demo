extends Control

# Called when the node enters the scene tree for the first time.
func _ready():

	var result: int = yield(Network.connect_to_server_async(), "completed")
	if result == OK:
		result = yield(Network.join_world_async(), "completed")
	if result == OK:
		# warning-ignore:return_value_discarded
		get_tree().change_scene_to(load("res://Screens/World.tscn"))
		var player_name := "test"
		Network.send_spawn(player_name)
