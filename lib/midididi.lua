local Midididi = {}

local reflection = require("reflection")

local patterns = {}
local norns_midi_event
local input_midi_device
local input_midi_passthrough_event
local output_midi_device

local TOLERANCE_TIME_MS = 200
local TOLERANCE_DISTANCE = 0

local MIDI_EVENT_CODES = {
    [0x80] = "note_off",
    [0x90] = "note_on",
    [0xB0] = "cc",
}

local on_rec_change
local on_midi_info_change
local selected_port
local enabled_device_id
local initialized = false

local function copy_midi_msg(midi_msg)
    local msg_copy = {}
    for i = 1, #midi_msg do
        msg_copy[i] = midi_msg[i]
    end
    return msg_copy
end

local function resolve_device_id(vport, fallback_id)
    if vport ~= nil then
        if vport.device ~= nil and vport.device.id ~= nil then
            return vport.device.id
        end

        if vport.id ~= nil then
            return vport.id
        end
    end

    return fallback_id
end

local function normalize_rec_state(rec_state)
    if rec_state == nil or rec_state == false or rec_state == 0 then
        return 0
    end
    return 1
end

local function notify_midi_info(device_id, channel, event_id, rec_state, value, event)
    local normalized_rec_state = normalize_rec_state(rec_state)

    if on_rec_change ~= nil then
        on_rec_change(device_id, channel, event_id, normalized_rec_state, value, event)
    end

    if on_midi_info_change ~= nil then
        on_midi_info_change(device_id, channel, event_id, normalized_rec_state, value, event)
    end
end

local function update_midi_info(device_id, midi_msg, rec_state)
    if midi_msg == nil or midi_msg[1] == nil then
        return
    end

    local event_code = midi_msg[1] & 0xF0
    local channel = (midi_msg[1] & 0x0F) + 1
    local event_id = midi_msg[2]
    local value = midi_msg[3]
    local event = MIDI_EVENT_CODES[event_code] or string.format("0x%X", event_code)

    notify_midi_info(device_id, channel, event_id, rec_state or 0, value, event)
end

local function send_midi_output(midi_msg)
    if output_midi_device == nil and selected_port ~= nil then
        output_midi_device = midi.connect(selected_port)
    end

    if output_midi_device ~= nil and midi_msg ~= nil then
        output_midi_device:send(midi_msg)
    end
end

local function create_pattern(device_id, channel, event_id)
    local pattern = {}
    pattern.device_id = device_id
    pattern.channel = channel
    pattern.event_id = event_id
    pattern.last_value = 0
    pattern.loop = reflection:new()
    pattern.loop:set_loop(1)
    pattern.loop.process = function(event)
        send_midi_output(event.midi_msg)
    end
    table.insert(patterns, pattern)
    return pattern
end

local function get_pattern(device_id, channel, event_id)
    for _, pattern in pairs(patterns) do
        if pattern.device_id == device_id and pattern.channel == channel and pattern.event_id == event_id then
            return pattern
        end
    end
end

local function get_device_rec_state(device_id)
    for _, pattern in pairs(patterns) do
        if pattern.device_id == device_id and pattern.loop ~= nil and normalize_rec_state(pattern.loop.rec) == 1 then
            return 1
        end
    end
    return 0
end

local function on_midi_event(device_id, midi_msg)
    if device_id ~= enabled_device_id then
        norns_midi_event(device_id, midi_msg)
        return
    end

    local event_code = midi_msg[1] & 0xF0
    local channel = (midi_msg[1] & 0x0F) + 1
    local event_id = midi_msg[2]
    local event = MIDI_EVENT_CODES[event_code]
    local value = midi_msg[3]

    local pattern = get_pattern(device_id, channel, event_id)
    if pattern == nil then
        pattern = create_pattern(device_id, channel, event_id)
    end

    if event == "note_on" then
        if normalize_rec_state(pattern.loop.rec) == 1 then
            pattern.loop:set_rec(0)
            pattern.tolerance_time_passed = false
            clock.run(function()
                clock.sleep(TOLERANCE_TIME_MS / 1000)
                pattern.tolerance_time_passed = true
            end)
        else
            pattern.loop:clear()
            pattern.loop:set_rec(1)
        end
        notify_midi_info(device_id, channel, event_id, get_device_rec_state(device_id), value, event)
    elseif pattern ~= nil and event == "note_off" then
        notify_midi_info(device_id, channel, event_id, get_device_rec_state(device_id), value, event)
    elseif pattern ~= nil and event == "cc" then
        local tolerance_distance = math.abs(pattern.last_value - value) > TOLERANCE_DISTANCE
        if pattern.loop.rec == 0 and tolerance_distance and pattern.tolerance_time_passed then
            pattern.loop:clear()
        end
        pattern.last_value = value
        pattern.loop:watch({
            device_id = device_id,
            channel = channel,
            event_id = event_id,
            value = value,
            midi_msg = copy_midi_msg(midi_msg),
        })
        notify_midi_info(device_id, channel, event_id, get_device_rec_state(device_id), value, event)
    else
        notify_midi_info(device_id, channel, event_id, get_device_rec_state(device_id), value, event or string.format("0x%X", event_code))
    end

    norns_midi_event(device_id, midi_msg)
end

function Midididi.init()
    if initialized or _norns.midi.event == on_midi_event then
        return
    end

    norns_midi_event = _norns.midi.event
    _norns.midi.event = on_midi_event
    initialized = true
end

function Midididi.cleanup()
    if initialized and norns_midi_event ~= nil and _norns.midi.event == on_midi_event then
        _norns.midi.event = norns_midi_event
    end

    if input_midi_device ~= nil then
        input_midi_device.event = input_midi_passthrough_event
    end

    norns_midi_event = nil
    input_midi_device = nil
    input_midi_passthrough_event = nil
    output_midi_device = nil
    patterns = {}
    initialized = false
end

function Midididi.on_rec_change(callback)
    on_rec_change = callback
end

function Midididi.on_midi_info_change(callback)
    on_midi_info_change = callback
end

function Midididi.set_device(device_id)
    selected_port = device_id

    if input_midi_device ~= nil then
        input_midi_device.event = input_midi_passthrough_event
    end

    input_midi_device = device_id ~= nil and midi.connect(device_id) or nil
    input_midi_passthrough_event = nil
    enabled_device_id = resolve_device_id(input_midi_device, device_id)

    if input_midi_device ~= nil then
        local passthrough_event = input_midi_device.event
        input_midi_passthrough_event = passthrough_event
        input_midi_device.event = function(data)
            if selected_port == device_id then
                update_midi_info(enabled_device_id, data, get_device_rec_state(enabled_device_id))
            end

            if passthrough_event ~= nil then
                passthrough_event(data)
            end
        end
    end

    output_midi_device = input_midi_device
end

return Midididi