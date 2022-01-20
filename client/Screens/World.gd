extends Node2D

export var PlayerScene: PackedScene

onready var players = $YSort/Players
onready var local_player = $YSort/Player

var characters := {}

func _ready():
	#warning-ignore: return_value_discarded
	Network.connect("initial_state_received", self, "_on_initial_state_received")

func _on_initial_state_received(
	positions: Dictionary, inputs: Dictionary, names: Dictionary
) -> void:
	#warning-ignore: return_value_discarded
	Network.disconnect(
		"initial_state_received", self, "_on_Network_initial_state_received"
	)
	join_room(positions, inputs, names)

# The main entry point. Sets up the client player and the various characters that
# are already logged into the room, and sets up the signal chain to respond to
# the server.
func join_room(
	state_positions: Dictionary,
	state_inputs: Dictionary,
	state_names: Dictionary
) -> void:
	var user_id := Network.get_user_id()
	assert(state_positions.has(user_id), "Server did not return valid state")

	# var player = PlayerScene.instance()
	# var username: String = state_names.get(user_id)

	# var player_position: Vector3 = room.get_node("SpawnPoints/0").transform.origin
	# # player.setup(int(user_id), username, player_color, player_position)
	# room.get_node("Players").add_child(player)

	local_player.user_id = user_id

	# spawn other players
	var presences := Network.presences
	for p in presences.keys():
		var character_position := Vector2(state_positions[p].x, state_positions[p].y)
		create_character(p, state_names[p], character_position)

	#warning-ignore: return_value_discarded
	Network.connect("presences_changed", self, "_on_Network_presences_changed")
	#warning-ignore: return_value_discarded
	Network.connect("state_updated", self, "_on_Network_state_updated")
	#warning-ignore: return_value_discarded
	Network.connect("color_updated", self, "_on_Network_color_updated")
	#warning-ignore: return_value_discarded
	Network.connect("character_spawned", self, "_on_Network_character_spawned")


func create_character(
	id: String,
	username: String,
	position: Vector2
) -> void:
	var character := PlayerScene.instance()
	character.transform.origin = position

	#warning-ignore: return_value_discarded
	players.add_child(character)
	character.user_id = id
	character.username = username
	characters[id] = character

func _on_Network_presences_changed() -> void:
	var presences := Network.presences

	for key in presences:
		if not key in characters:
			create_character(key, "User", Vector2.ZERO)

	var to_delete := []
	for key in characters.keys():
		if not key in presences:
			to_delete.append(key)

	for key in to_delete:
		characters[key].despawn()
		# @TODO game_ui.add_notification(characters[key].username, characters[key].color, true)
		#warning-ignore: return_value_discarded
		characters.erase(key)


func _on_Network_state_updated(positions: Dictionary, rotations: Dictionary, inputs: Dictionary) -> void:
	var update := false
	for key in characters:

		# check if the character has been freed (disconnected)
		if !is_instance_valid(characters[key]):
			continue

		update = false
		if key in positions:
			var next_position: Dictionary = positions[key]
			characters[key].next_position = Vector2(next_position.x, next_position.y)
			update = true
		if key in inputs:
			var next_input: Dictionary = inputs[key].dir
			characters[key].next_input = Vector2(next_input.x, next_input.y)
			characters[key].move_speed = inputs[key].spd
			update = true
		if key in rotations:
			var next_rotation: Dictionary = rotations[key]
			characters[key].next_rotation = Vector2(next_rotation.x, next_rotation.y)
			update = true
		if update:
			characters[key].update_state()


func _on_Network_color_updated(id: String, color: Color) -> void:
	if id in characters:
		characters[id].color = color

func _on_Network_character_spawned(id: String, color: Color, name: String) -> void:
	if id in characters:
		characters[id].username = name
		characters[id].spawn()
		characters[id].do_show()
		# @TODO game_ui.add_notification(characters[id].username, color)

