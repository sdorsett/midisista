local midididi = include("midisista/lib/midididi")

local DATA_DIR = _path.data .. "midisista/"
local STATE_FILE = DATA_DIR .. "state.data"

local TARGET_IDS = {
    "midisista_target_1",
    "midisista_target_2",
    "midisista_target_3",
    "midisista_target_4",
    "midisista_target_5",
    "midisista_target_6",
    "midisista_target_7",
    "midisista_target_8",
}

local PAGE_DEVICE = 1
local PAGE_MONITOR = 2
local PAGE_TARGETS = 3

local ui = {
    page = PAGE_DEVICE,
    page_count = 3,
    selection = {
        [PAGE_DEVICE] = 1,
        [PAGE_MONITOR] = 1,
        [PAGE_TARGETS] = 1,
    },
    dirty = true,
    message = "",
    message_until = 0,
    selected_device = 1,
    persist_device = 1,
    midi_info = {
        rec_state = 0,
        device_id = nil,
        channel = nil,
        event_id = nil,
        value = nil,
        event_name = "--",
    },
    rec_states = {},
}

local redraw_timer

local function clamp_page_selection()
    if ui.selection[PAGE_DEVICE] > 2 then
        ui.selection[PAGE_DEVICE] = 2
    end
    if ui.selection[PAGE_MONITOR] > 1 then
        ui.selection[PAGE_MONITOR] = 1
    end
    if ui.selection[PAGE_TARGETS] > #TARGET_IDS then
        ui.selection[PAGE_TARGETS] = #TARGET_IDS
    end
end

local function mark_dirty()
    ui.dirty = true
end

local function show_message(text)
    ui.message = text
    ui.message_until = util.time() + 1.2
    mark_dirty()
end

local function short_name(name)
    if name == nil or name == "" then
        return "none"
    end
    return string.len(name) <= 10 and name or util.acronym(name)
end

local function device_options()
    local options = {}
    for index = 1, 16 do
        local vport = midi.vports[index]
        local label = string.format("%d %s", index, short_name(vport and vport.name))
        table.insert(options, label)
    end
    return options
end

local function load_state()
    if util.file_exists(STATE_FILE) then
        local loaded = tab.load(STATE_FILE)
        if loaded ~= nil then
            if loaded.persist_device ~= nil then
                ui.persist_device = util.clamp(loaded.persist_device, 1, 2)
            end
            if ui.persist_device == 2 and loaded.selected_device ~= nil then
                ui.selected_device = util.clamp(loaded.selected_device, 1, 16)
            end
        end
    else
        util.make_dir(DATA_DIR)
    end
end

local function save_state()
    tab.save({
        selected_device = ui.selected_device,
        persist_device = ui.persist_device,
    }, STATE_FILE)
end

local function selected_target_id()
    return TARGET_IDS[ui.selection[PAGE_TARGETS]]
end

local function target_value_text(param_id)
    local ok, value = pcall(function()
        return params:string(param_id)
    end)
    if ok and value ~= nil and value ~= "" then
        return value
    end
    return tostring(params:get(param_id))
end

local function refresh_target_rec_state(device_id, channel, event_id, rec_state)
    if norns.pmap == nil or norns.pmap.data == nil then
        return
    end

    for param_id, pmap in pairs(norns.pmap.data) do
        if pmap.dev == device_id and pmap.ch == channel and pmap.cc == event_id then
            ui.rec_states[param_id] = rec_state
        end
    end
end

local function midi_status_text()
    return ui.midi_info.rec_state == 1 and "recording" or "idle"
end

local function page_title()
    if ui.page == PAGE_DEVICE then
        return "DEVICE"
    elseif ui.page == PAGE_MONITOR then
        return "MONITOR"
    end
    return "TARGETS"
end

local function draw_header()
    screen.level(15)
    screen.font_face(1)
    screen.font_size(8)
    screen.move(2, 8)
    screen.text("midisista")
    screen.move(126, 8)
    screen.text_right(page_title())
    screen.level(4)
    screen.move(0, 11)
    screen.line(128, 11)
    screen.stroke()
end

local function draw_device_page()
    local device_focus = ui.selection[PAGE_DEVICE] == 1
    local persist_focus = ui.selection[PAGE_DEVICE] == 2
    local vport = midi.vports[ui.selected_device]

    screen.level(device_focus and 15 or 4)
    screen.move(2, 23)
    screen.text("device")
    screen.move(126, 23)
    screen.text_right(string.format("%d %s", ui.selected_device, short_name(vport and vport.name)))

    screen.level(persist_focus and 15 or 4)
    screen.move(2, 35)
    screen.text("persist")
    screen.move(126, 35)
    screen.text_right(ui.persist_device == 2 and "on" or "off")

    screen.level(10)
    screen.move(2, 49)
    screen.text("status")
    screen.move(126, 49)
    screen.text_right(midi_status_text())

    screen.move(2, 61)
    screen.text("enc1 page  enc2 field  enc3 edit")
end

local function draw_monitor_page()
    local device_id = ui.midi_info.device_id ~= nil and tostring(ui.midi_info.device_id) or "--"
    local channel = ui.midi_info.channel ~= nil and tostring(ui.midi_info.channel) or "--"
    local event_id = ui.midi_info.event_id ~= nil and tostring(ui.midi_info.event_id) or "--"
    local value = ui.midi_info.value ~= nil and tostring(ui.midi_info.value) or "--"
    local event_name = ui.midi_info.event_name or "--"

    screen.level(15)
    screen.move(2, 23)
    screen.text("state")
    screen.move(126, 23)
    screen.text_right(midi_status_text())

    screen.level(10)
    screen.move(2, 35)
    screen.text("dev/ch")
    screen.move(126, 35)
    screen.text_right(string.format("%s/%s", device_id, channel))

    screen.move(2, 47)
    screen.text("evt")
    screen.move(126, 47)
    screen.text_right(string.format("%s %s", event_name, event_id))

    screen.move(2, 59)
    screen.text("val")
    screen.move(126, 59)
    screen.text_right(value)
end

local function draw_targets_page()
    local selection = ui.selection[PAGE_TARGETS]
    local start_index = util.clamp(selection - 1, 1, math.max(#TARGET_IDS - 3, 1))
    local stop_index = math.min(start_index + 3, #TARGET_IDS)
    local y = 21

    for index = start_index, stop_index do
        local param_id = TARGET_IDS[index]
        local active = index == selection
        local rec = ui.rec_states[param_id] == 1 and "rec" or "   "

        screen.level(active and 15 or 4)
        screen.move(2, y)
        screen.text(string.format("%d %s", index, rec))
        screen.move(126, y)
        screen.text_right(target_value_text(param_id))
        y = y + 11
    end

    screen.level(10)
    screen.move(2, 61)
    screen.text(selected_target_id())
end

local function draw_message()
    if ui.message == "" or util.time() > ui.message_until then
        ui.message = ""
        return
    end

    local width = math.min(124, string.len(ui.message) * 6 + 8)
    local left = math.floor((128 - width) / 2)
    screen.level(0)
    screen.rect(left, 26, width, 12)
    screen.fill()
    screen.level(15)
    screen.rect(left, 26, width, 12)
    screen.stroke()
    screen.move(64, 35)
    screen.text_center(ui.message)
end

function redraw()
    ui.dirty = false
    screen.clear()
    draw_header()

    if ui.page == PAGE_DEVICE then
        draw_device_page()
    elseif ui.page == PAGE_MONITOR then
        draw_monitor_page()
    else
        draw_targets_page()
    end

    draw_message()
    screen.update()
end

local function set_device(device_id)
    ui.selected_device = util.clamp(device_id, 1, 16)
    params:set("midisista_midi_device", ui.selected_device)
    midididi.set_device(ui.selected_device)
    save_state()
    show_message(string.format("device %d", ui.selected_device))
end

local function adjust_device_page(delta)
    local field = ui.selection[PAGE_DEVICE]
    if field == 1 then
        set_device(util.clamp(ui.selected_device + delta, 1, 16))
    elseif field == 2 then
        ui.persist_device = util.clamp(ui.persist_device + delta, 1, 2)
        params:set("midisista_persist_device", ui.persist_device)
        save_state()
        show_message(ui.persist_device == 2 and "persist on" or "persist off")
    end
end

local function adjust_targets_page(delta)
    local param_id = selected_target_id()
    params:delta(param_id, delta)
    mark_dirty()
end

local function build_params()
    params:add_separator("midisista")
    params:add_group("midisista setup", 2)
    params:add_option("midisista_midi_device", "midi device", device_options(), ui.selected_device)
    params:set_action("midisista_midi_device", function(value)
        ui.selected_device = value
        midididi.set_device(value)
        save_state()
        mark_dirty()
    end)
    params:add_option("midisista_persist_device", "persist device", {"off", "on"}, ui.persist_device)
    params:set_action("midisista_persist_device", function(value)
        ui.persist_device = value
        save_state()
        mark_dirty()
    end)

    params:add_group("midisista targets", #TARGET_IDS)
    for index, param_id in ipairs(TARGET_IDS) do
        params:add_control(
            param_id,
            "target " .. index,
            controlspec.new(0, 127, "lin", 1, 0)
        )
        params:set_action(param_id, function()
            mark_dirty()
        end)
    end
end

local function start_redraw_timer()
    redraw_timer = metro.init()
    redraw_timer.time = 1 / 15
    redraw_timer.count = -1
    redraw_timer.event = function()
        if ui.message ~= "" and util.time() > ui.message_until then
            ui.message = ""
            ui.dirty = true
        end

        if ui.dirty then
            redraw()
        end
    end
    redraw_timer:start()
end

local function stop_redraw_timer()
    if redraw_timer ~= nil then
        redraw_timer:stop()
        redraw_timer = nil
    end
end

function init()
    load_state()
    clamp_page_selection()
    midididi.init()
    build_params()

    params:set("midisista_persist_device", ui.persist_device)
    params:set("midisista_midi_device", ui.selected_device)

    midididi.on_rec_change(function(device_id, channel, event_id, rec_state)
        refresh_target_rec_state(device_id, channel, event_id, rec_state)
        mark_dirty()
    end)
    midididi.on_midi_info_change(function(device_id, channel, event_id, rec_state, value, event_name)
        ui.midi_info.device_id = device_id
        ui.midi_info.channel = channel
        ui.midi_info.event_id = event_id
        ui.midi_info.rec_state = rec_state or 0
        ui.midi_info.value = value
        ui.midi_info.event_name = event_name or "--"
        mark_dirty()
    end)
    midididi.set_device(ui.selected_device)

    start_redraw_timer()
    mark_dirty()
end

function cleanup()
    save_state()
    stop_redraw_timer()
    midididi.cleanup()
end

function enc(n, d)
    if n == 1 then
        ui.page = util.clamp(ui.page + util.sign(d), 1, ui.page_count)
        show_message(string.lower(page_title()))
        return
    end

    if n == 2 then
        if ui.page == PAGE_DEVICE then
            ui.selection[PAGE_DEVICE] = util.clamp(ui.selection[PAGE_DEVICE] + util.sign(d), 1, 2)
        elseif ui.page == PAGE_TARGETS then
            ui.selection[PAGE_TARGETS] = util.clamp(ui.selection[PAGE_TARGETS] + util.sign(d), 1, #TARGET_IDS)
        end
        mark_dirty()
        return
    end

    if n == 3 then
        local delta = util.sign(d)
        if ui.page == PAGE_DEVICE then
            adjust_device_page(delta)
        elseif ui.page == PAGE_TARGETS then
            adjust_targets_page(delta)
        end
        mark_dirty()
    end
end

function key(n, z)
    if z == 0 then
        return
    end

    if n == 2 then
        ui.page = PAGE_MONITOR
        show_message("monitor")
    elseif n == 3 then
        ui.page = PAGE_TARGETS
        show_message("targets")
    end
end