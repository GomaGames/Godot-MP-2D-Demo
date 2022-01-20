-- Module that controls the game world. The world's state is updated every `tickrate` in the
-- `match_loop()` function.

local world_control = {}

local nk = require("nakama")

local SPAWN_POSITION = {0.0, 0.0}

-- Custom operation codes. Nakama specific codes are <= 0.
local OpCodes = {
    update_position = 1,
    update_rotation = 2,
    update_input = 3,
    update_state = 4,
    do_spawn = 5,
    initial_state = 6
}

-- Command pattern table for boiler plate updates that uses data and state.
local commands = {}

-- Updates the position in the game state
commands[OpCodes.update_position] = function(data, state)
    local id = data.id
    local position = data.pos
    if state.positions[id] ~= nil then
        state.positions[id] = position
    end
end

-- Updates the motion input direction in the game state
commands[OpCodes.update_input] = function(data, state)
    local id = data.id
    local input = data.inp
    local move_speed = data.spd
    if state.inputs[id] ~= nil then
        state.inputs[id].dir = input
        state.inputs[id].spd = move_speed
    end
end

-- Updates person's rotation, the direction they are facing
commands[OpCodes.update_rotation] = function(data, state)
    local id = data.id
    local rotation = data.rot
    if state.rotations[id] ~= nil then
        state.rotations[id] = rotation
    end
end

-- Does nothing for now
commands[OpCodes.do_spawn] = function(data, state)
    local id = data.id
end

-- When the match is initialized. Creates empty tables in the game state that will be populated by
-- clients.
function world_control.match_init(_, _)
    local gamestate = {
        presences = {},
        rotations = {}, -- direction the person is facing
        inputs = {}, -- anticipate move direction
        positions = {},
        names = {}
    }
    local tickrate = 10
    local label = "Social world"
    return gamestate, tickrate, label
end

-- When someone tries to join the match. Checks if someone is already logged in and blocks them from
-- doing so if so.
function world_control.match_join_attempt(_, _, _, state, presence, _)
    if state.presences[presence.user_id] ~= nil then
        return state, false, "User already logged in."
    end
    return state, true
end

-- When someone does join the match. Initializes their entries in the game state tables with dummy
-- values until they spawn in.
function world_control.match_join(_, dispatcher, _, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.user_id] = presence

        state.positions[presence.user_id] = {
            ["x"] = 0,
            ["y"] = 0,
        }

        state.rotations[presence.user_id] = {
            ["x"] = 0,
            ["y"] = 0
        }

        state.inputs[presence.user_id] = {
            ["dir"] = {
                ["x"] = 0,
                ["y"] = 0,
            },
            ["spd"] = 0,
        }

        state.names[presence.user_id] = "User"
    end

    return state
end

-- When someone leaves the match. Clears their entries in the game state tables, but saves their
-- position to storage for next time.
function world_control.match_leave(_, _, _, state, presences)
    for _, presence in ipairs(presences) do
        local new_objects = {
            {
                collection = "player_data",
                key = "position_" .. state.names[presence.user_id],
                user_id = presence.user_id,
                value = state.positions[presence.user_id]
            }
        }
        nk.storage_write(new_objects)

        state.presences[presence.user_id] = nil
        state.positions[presence.user_id] = nil
        state.rotations[presence.user_id] = nil
        state.inputs[presence.user_id] = nil
        state.names[presence.user_id] = nil
    end
    return state
end

-- Called `tickrate` times per second. Handles client messages and sends game state updates. Uses
-- boiler plate commands from the command pattern except when specialization is required.
function world_control.match_loop(_, dispatcher, _, state, messages)
    for _, message in ipairs(messages) do
        local op_code = message.op_code

        local decoded = nk.json_decode(message.data)

        -- Run boiler plate commands (state updates.)
        local command = commands[op_code]
        if command ~= nil then
            commands[op_code](decoded, state)
        end

        -- A client has selected a character and is spawning. Get or generate position data,
        -- send them initial state, and broadcast their spawning to existing clients.
        if op_code == OpCodes.do_spawn then
            local object_ids = {
                {
                    collection = "player_data",
                    key = "position_" .. decoded.nm,
                    user_id = message.sender.user_id
                }
            }

            local objects = nk.storage_read(object_ids)

            local position
            for _, object in ipairs(objects) do
                position = object.value
                if position ~= nil then
                    state.positions[message.sender.user_id] = position
                    break
                end
            end

            if position == nil then
                state.positions[message.sender.user_id] = {
                    ["x"] = SPAWN_POSITION[1],
                    ["y"] = SPAWN_POSITION[2],
                }
            end

            state.names[message.sender.user_id] = decoded.nm

            local data = {
                ["pos"] = state.positions,
                ["rot"] = state.rotations,
                ["inp"] = state.inputs,
                ["nms"] = state.names
            }

            local encoded = nk.json_encode(data)
            dispatcher.broadcast_message(OpCodes.initial_state, encoded, {message.sender})

            dispatcher.broadcast_message(OpCodes.do_spawn, message.data)
        elseif op_code == OpCodes.update_color then
            dispatcher.broadcast_message(OpCodes.update_color, message.data)
        end
    end

    local data = {
        ["pos"] = state.positions,
        ["rot"] = state.rotations,
        ["inp"] = state.inputs
    }
    local encoded = nk.json_encode(data)

    dispatcher.broadcast_message(OpCodes.update_state, encoded)

    return state
end

-- Server is shutting down. Save positions of all existing characters to storage.
function world_control.match_terminate(_, _, _, state, _)
    local new_objects = {}
    for k, position in pairs(state.positions) do
        table.insert(
            new_objects,
            {
                collection = "player_data",
                key = "position_" .. state.names[k],
                user_id = k,
                value = position
            }
        )
    end

    nk.storage_write(new_objects)

    return state
end

return world_control
