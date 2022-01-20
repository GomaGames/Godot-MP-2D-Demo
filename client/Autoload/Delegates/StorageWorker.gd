# Class that ServerConnection delegates work to. Stores and fetches data in and out
# of server storage - namely, character listing and color data.
class_name StorageWorker
extends Reference

# Nakama read permissions
enum ReadPermissions { NO_READ, OWNER_READ, PUBLIC_READ }

# Nakama write permissions
enum WritePermissions { NO_WRITE, OWNER_WRITE }

# Server key. Must be unique.
const KEY := "nakama_godot_demo"

# Collection in the storage for data that pertains to player's info
const COLLECTION := "player_data"

# Key within the storage collection for where the character list is stored
const KEY_CHARACTERS := "characters"

# Key within the storage collection for hwere the last logged in character was
const KEY_LAST_CHARACTER := "last_character"

var _session: NakamaSession
var _client: NakamaClient
var _exception_handler: ExceptionHandler


func _init(session: NakamaSession, client: NakamaClient, exception_handler: ExceptionHandler) -> void:
	_session = session
	_client = client
	_exception_handler = exception_handler


# Asynchronous coroutine. Gets the list of characters belonging to the user out of
# server storage.
# Returns an Array of {name: String} dictionaries.
# Returns an empty array if there is a failure or if no characters are found.
func get_player_characters_async() -> Array:
	var storage_objects: NakamaAPI.ApiStorageObjects = yield(
		_client.read_storage_objects_async(
			_session, [NakamaStorageObjectId.new(COLLECTION, KEY_CHARACTERS, _session.user_id)]
		),
		"completed"
	)

	var parsed_result := _exception_handler.parse_exception(storage_objects)
	if parsed_result != OK:
		return []

	var characters := []
	if storage_objects.objects.size() > 0:
		var decoded: Array = JSON.parse(storage_objects.objects[0].value).result.characters
		for character in decoded:
			var name: String = character.name
			characters.append(
				{name = name}
			)
	return characters


# Creates a new character on the player's account. Will ask the server if the name
# is available beforehand, then will register the name and create the character into
# storage if so.
# Returns OK when successful, a nakama error code, or ERR_UNAVAILABLE if the name
# is already taken.
func create_player_character_async(name: String) -> int:
	var availability_response: NakamaAPI.ApiRpc = yield(
		_client.rpc_async(_session, "register_character_name", name), "completed"
	)

	var parsed_result := _exception_handler.parse_exception(availability_response)
	if parsed_result != OK:
		return parsed_result

	var is_available := availability_response.payload == "1"
	if is_available:
		var characters: Array = yield(get_player_characters_async(), "completed")
		characters.append({name = name})
		var result: int = yield(_write_player_characters_async(characters), "completed")
		return result
	else:
		return ERR_UNAVAILABLE


# Update the character's name in storage.
# Returns OK, or a nakama error code.
func update_player_character_async(name: String) -> int:
	var characters: Array = yield(get_player_characters_async(), "completed")

	var do_update := false
	for i in range(characters.size()):
		if characters[i].name == name:
			do_update = true
			break

	if do_update:
		var result: int = yield(_write_player_characters_async(characters), "completed")
		if result == OK:
			result = yield(store_last_player_character_async(name), "completed")
		return result
	else:
		return OK


# Asynchronous coroutine. Delete the character at the specified index in the array from
# player storage. Returns OK, a nakama error code, or ERR_PARAMETER_RANGE_ERROR
# if the index is too large or is invalid.
func delete_player_character_async(idx: int) -> int:
	var characters: Array = yield(get_player_characters_async(), "completed")

	if idx >= 0 and idx < characters.size():
		var character: Dictionary = characters[idx]
		yield(_client.rpc_async(_session, "remove_character_name", character.name), "completed")
		characters.remove(idx)

		var result: int = yield(_write_player_characters_async(characters), "completed")
		return result
	else:
		return ERR_PARAMETER_RANGE_ERROR


# Asynchronous coroutine. Get the last logged in character from the server, if any.
# Returns a {name: String} dictionary, or an empty dictionary if no
# character is found, or something goes wrong.
func get_last_player_character_async() -> Dictionary:
	var storage_objects: NakamaAPI.ApiStorageObjects = yield(
		_client.read_storage_objects_async(
			_session, [NakamaStorageObjectId.new(COLLECTION, KEY_LAST_CHARACTER, _session.user_id)]
		),
		"completed"
	)

	var parsed_result := _exception_handler.parse_exception(storage_objects)
	var character := {}
	if parsed_result != OK or storage_objects.objects.size() == 0:
		return character

	var decoded: Dictionary = JSON.parse(storage_objects.objects[0].value).result
	character["name"] = decoded.name

	var characters: Array = yield(get_player_characters_async(), "completed")
	for c in characters:
		if c.name == character["name"]:
			return character
	return {}


# Asynchronous coroutine. Put the last logged in character into player storage on the server.
# Returns OK, or a nakama error code.
func store_last_player_character_async(name: String) -> int:
	var character := {name = name}
	var result: NakamaAPI.ApiStorageObjectAcks = yield(
		_client.write_storage_objects_async(
			_session,
			[
				NakamaWriteStorageObject.new(
					COLLECTION,
					KEY_LAST_CHARACTER,
					ReadPermissions.OWNER_READ,
					WritePermissions.OWNER_WRITE,
					JSON.print(character),
					""
				)
			]
		),
		"completed"
	)
	var parsed_result := _exception_handler.parse_exception(result)
	return parsed_result


# Asynchronous coroutine. Writes the player's characters into storage on the server.
# Returns OK or a nakama error code.
func _write_player_characters_async(characters: Array) -> int:
	var result: NakamaAPI.ApiStorageObjectAcks = yield(
		_client.write_storage_objects_async(
			_session,
			[
				NakamaWriteStorageObject.new(
					COLLECTION,
					KEY_CHARACTERS,
					ReadPermissions.OWNER_READ,
					WritePermissions.OWNER_WRITE,
					JSON.print({characters = characters}),
					""
				)
			]
		),
		"completed"
	)
	var parsed_result := _exception_handler.parse_exception(result)
	return parsed_result
