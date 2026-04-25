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
    "midisista_target_9",
    "midisista_target_10",
    "midisista_target_11",
    "midisista_target_12",
    "midisista_target_13",
    "midisista_target_14",
    "midisista_target_15",
    "midisista_target_16",
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
    next_auto_target = 1,
    grid_page = 1,
    midi_info = {
        rec_state = 0,
        play_state = 0,
        device_id = nil,
        channel = nil,
        event_id = nil,
        value = nil,
        event_name = "--",
    },
    learned_target_mappings = {},
    target_states = {},
}

local redraw_timer
local grid_device
local midigrid_lib
local midigrid_2pages_lib
local using_midigrid = false

local function try_include(path)
    local ok, lib = pcall(function()
        return include(path)
    end)

    if ok then
        return lib
    end

    return nil
end

local function native_grid_connected()
    if grid == nil or grid.vports == nil then
        return false
    end

    local port = grid.vports[1]
    if port == nil or port.name == nil then
        return false
    end

    local name = string.lower(tostring(port.name))
    return name ~= "" and name ~= "none"
end

local function connect_grid_device()
    using_midigrid = false

    if native_grid_connected() then
        return grid.connect()
    end

    if midigrid_2pages_lib == nil then
        midigrid_2pages_lib = try_include("midigrid/lib/midigrid_2pages")
    end

    if midigrid_lib == nil then
        midigrid_lib = try_include("midigrid/lib/midigrid")
    end

    if midigrid_2pages_lib ~= nil and midigrid_2pages_lib.connect ~= nil then
        using_midigrid = true
        return midigrid_2pages_lib.connect()
    end

    if midigrid_lib ~= nil and midigrid_lib.connect ~= nil then
        using_midigrid = true
        return midigrid_lib.connect()
    end

    return nil
end

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

local function encoder_delta(value)
    if value == nil or value == 0 then
        return 0
    elseif value > 0 then
        return 1
    end
    return -1
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

local function target_display_value_text(param_id)
    local state = ui.target_states[param_id]
    if state ~= nil and state.value ~= nil then
        return tostring(state.value)
    end

    return target_value_text(param_id)
end

local function target_numeric_value(param_id)
    local state = ui.target_states[param_id]
    local value = nil

    if state ~= nil and state.value ~= nil then
        value = tonumber(state.value)
    end

    if value == nil then
        value = tonumber(params:get(param_id))
    end

    if value == nil then
        value = 0
    end

    return util.clamp(math.floor(value + 0.5), 0, 127)
end

local function grid_column_for_value(value)
    return util.clamp(math.floor((value / 127) * 15) + 1, 1, 16)
end

local function grid_row_level(param_id)
    local state = ui.target_states[param_id]
    if state == nil then
        return 0
    end

    if state.rec_state == 1 then
        return 15
    end

    if state.play_state == 1 then
        return 10
    end

    if state.value ~= nil then
        return 6
    end

    return 0
end

local function redraw_grid()
    if grid_device == nil then
        return
    end

    grid_device:all(0)

    -- Render 8 targets for current page
    local page_offset = (ui.grid_page - 1) * 8
    for row = 1, 8 do
        local target_index = page_offset + row
        if target_index <= #TARGET_IDS then
            local param_id = TARGET_IDS[target_index]
            local level = grid_row_level(param_id)
            if level > 0 then
                local value = target_numeric_value(param_id)
                local column = grid_column_for_value(value)
                grid_device:led(column, row, level)
            end
        end
    end

    grid_device:refresh()
end

local function target_mapping(param_id)
    local learned = ui.learned_target_mappings[param_id]
    if learned ~= nil then
        return learned
    end

    if norns.pmap == nil or norns.pmap.data == nil then
        return nil
    end

    return norns.pmap.data[param_id]
end

local function target_mapping_from_rev(param_id)
    local learned = ui.learned_target_mappings[param_id]
    if learned ~= nil then
        return learned
    end

    if norns.pmap == nil or norns.pmap.rev == nil then
        return nil
    end

    for dev, by_channel in pairs(norns.pmap.rev) do
        if by_channel ~= nil then
            for ch, by_cc in pairs(by_channel) do
                if by_cc ~= nil then
                    for cc, mapped_param_id in pairs(by_cc) do
                        if mapped_param_id == param_id then
                            return {
                                dev = dev,
                                ch = ch,
                                cc = cc,
                            }
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function values_match(left, right)
    if left == nil or right == nil then
        return false
    end

    if left == right then
        return true
    end

    local left_num = tonumber(left)
    local right_num = tonumber(right)
    if left_num ~= nil and right_num ~= nil then
        local left_midi = math.floor(left_num + 0.5)
        local right_midi = math.floor(right_num + 0.5)
        if left_midi == right_midi then
            return true
        end
    end

    return tostring(left) == tostring(right)
end

local function target_mapping_device_matches(pmap_dev, device_id)
    if pmap_dev == nil then
        return false
    end

    local candidates = {
        device_id,
        ui.selected_device,
    }

    local selected_vport = midi.vports[ui.selected_device]
    if selected_vport ~= nil then
        table.insert(candidates, selected_vport.id)
        if selected_vport.device ~= nil then
            table.insert(candidates, selected_vport.device.id)
        end
    end

    if type(device_id) == "number" then
        local event_vport = midi.vports[device_id]
        if event_vport ~= nil then
            table.insert(candidates, event_vport.id)
            if event_vport.device ~= nil then
                table.insert(candidates, event_vport.device.id)
            end
        end
    end

    for _, candidate in ipairs(candidates) do
        if values_match(pmap_dev, candidate) then
            return true
        end
    end

    return false
end

local function target_has_assigned_mapping(param_id, pmap)
    if pmap == nil or pmap.dev == nil or pmap.ch == nil or pmap.cc == nil then
        return false
    end

    if norns.pmap == nil or norns.pmap.rev == nil then
        return true
    end

    if norns.pmap.rev[pmap.dev] ~= nil
        and norns.pmap.rev[pmap.dev][pmap.ch] ~= nil
        and norns.pmap.rev[pmap.dev][pmap.ch][pmap.cc] == param_id then
        return true
    end

    return target_mapping_device_matches(pmap.dev, ui.midi_info.device_id)
end

local function target_assigned_mapping(param_id)
    local rev_mapping = target_mapping_from_rev(param_id)
    if rev_mapping ~= nil then
        return rev_mapping
    end

    local pmap = target_mapping(param_id)
    if target_has_assigned_mapping(param_id, pmap) then
        return pmap
    end
    return nil
end

local function target_mapping_matches_event(param_id, pmap, device_id, channel, event_id)
    local mapping = target_mapping_from_rev(param_id) or pmap
    if mapping == nil then
        return false
    end

    if not values_match(mapping.ch, channel) or not values_match(mapping.cc, event_id) then
        return false
    end

    return true
end

local function target_rev_matches_event(param_id, channel, event_id)
    if norns.pmap == nil or norns.pmap.rev == nil then
        return false
    end

    for _, by_channel in pairs(norns.pmap.rev) do
        if by_channel ~= nil then
            local by_cc = by_channel[channel]
            if by_cc ~= nil and by_cc[event_id] == param_id then
                return true
            end
        end
    end

    return false
end

local function clear_target_states()
    ui.target_states = {}
    ui.learned_target_mappings = {}
    ui.next_auto_target = 1
end

local function next_available_target()
    local total = #TARGET_IDS
    if total == 0 then
        return nil, nil
    end

    for offset = 0, total - 1 do
        local index = ((ui.next_auto_target - 1 + offset) % total) + 1
        local param_id = TARGET_IDS[index]
        if target_assigned_mapping(param_id) == nil then
            return param_id, index
        end
    end

    local fallback_index = ui.next_auto_target
    return TARGET_IDS[fallback_index], fallback_index
end

local function refresh_target_loop_state(device_id, channel, event_id, rec_state, play_state, value, event_name)
    if norns.pmap == nil or norns.pmap.data == nil then
        return
    end

    local function apply_state(param_id)
        local previous_state = ui.target_states[param_id] or {}
        local next_value = previous_state.value
        local next_rec_state = rec_state
        local next_play_state = play_state

        if value ~= nil and (event_name == "cc" or event_name == "play") then
            next_value = value
        end

        if next_rec_state == nil then
            next_rec_state = previous_state.rec_state or 0
        end

        if next_play_state == nil then
            next_play_state = previous_state.play_state or 0
        end

        ui.target_states[param_id] = {
            rec_state = next_rec_state,
            play_state = next_play_state,
            value = next_value,
        }
    end

    local match_count = 0

    for _, param_id in ipairs(TARGET_IDS) do
        local pmap = target_mapping(param_id)
        local matches = target_mapping_matches_event(param_id, pmap, device_id, channel, event_id)
            or target_rev_matches_event(param_id, channel, event_id)
        if matches then
            match_count = match_count + 1
            apply_state(param_id)
        end
    end

    -- If no exact mapping exists yet for this channel/CC, allocate the next
    -- available target row and learn the mapping for subsequent callbacks.
    if match_count == 0 then
        local param_id, index = next_available_target()
        if param_id ~= nil then
            ui.learned_target_mappings[param_id] = {
                dev = device_id,
                ch = channel,
                cc = event_id,
            }
            apply_state(param_id)
            match_count = 1
            ui.next_auto_target = (index % #TARGET_IDS) + 1
        end
    end
end

local function target_status_text(param_id)
    local state = ui.target_states[param_id]
    if state ~= nil and state.rec_state == 1 then
        return "rec"
    end
    if state ~= nil and state.play_state == 1 then
        return "ply"
    end
    return "---"
end

local function target_channel_cc_text(param_id)
    local pmap = target_assigned_mapping(param_id)
    if pmap == nil or pmap.ch == nil or pmap.cc == nil then
        return "--/--"
    end
    return string.format("%d/%d", pmap.ch, pmap.cc)
end

local function ensure_target_pmaps()
    if norns.pmap == nil or norns.pmap.data == nil or norns.pmap.new == nil then
        return
    end

    for _, param_id in ipairs(TARGET_IDS) do
        if norns.pmap.data[param_id] == nil then
            norns.pmap.new(param_id)
        end
    end
end

local function midi_status_text()
    if ui.midi_info.rec_state == 1 then
        return "recording"
    end
    if ui.midi_info.play_state == 1 then
        return "playing"
    end
    return "idle"
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
    local y = 26

    screen.level(10)
    screen.move(2, 17)
    screen.text("tg")
    screen.move(24, 17)
    screen.text("st")
    screen.move(48, 17)
    screen.text("ch/cc")
    screen.move(126, 17)
    screen.text_right("val")

    for index = start_index, stop_index do
        local param_id = TARGET_IDS[index]
        local active = index == selection

        screen.level(active and 15 or 4)
        screen.move(2, y)
        screen.text(string.format("%s%d", active and ">" or " ", index))
        screen.move(24, y)
        screen.text(target_status_text(param_id))
        screen.move(48, y)
        screen.text(target_channel_cc_text(param_id))
        screen.move(126, y)
        screen.text_right(target_display_value_text(param_id))
        y = y + 9
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
    redraw_grid()
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
        clear_target_states()
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
    ensure_target_pmaps()

    params:set("midisista_persist_device", ui.persist_device)
    params:set("midisista_midi_device", ui.selected_device)

    midididi.on_rec_change(function(device_id, channel, event_id, rec_state)
        refresh_target_loop_state(device_id, channel, event_id, rec_state, nil, nil, nil)
        mark_dirty()
    end)
    midididi.on_loop_state_change(function(device_id, channel, event_id, rec_state, play_state, value, event_name)
        refresh_target_loop_state(device_id, channel, event_id, rec_state, play_state, value, event_name)
        if ui.midi_info.device_id == device_id and ui.midi_info.channel == channel and ui.midi_info.event_id == event_id then
            ui.midi_info.play_state = play_state or 0
            if value ~= nil and (event_name == "cc" or event_name == "play") then
                ui.midi_info.value = value
            end
        end
        mark_dirty()
    end)
    midididi.on_midi_info_change(function(device_id, channel, event_id, rec_state, value, event_name)
        ui.midi_info.device_id = device_id
        ui.midi_info.channel = channel
        ui.midi_info.event_id = event_id
        ui.midi_info.rec_state = rec_state or 0
        if rec_state == 1 then
            ui.midi_info.play_state = 0
        end
        ui.midi_info.value = value
        ui.midi_info.event_name = event_name or "--"
        mark_dirty()
    end)
    midididi.set_device(ui.selected_device)

    grid_device = connect_grid_device()
    if grid_device ~= nil then
        grid_device.key = function(x, y, z)
            if z == 0 then
                return
            end

            -- Top-left corner cycles through grid pages
            if x == 1 and y == 8 then
                local max_pages = math.ceil(#TARGET_IDS / 8)
                ui.grid_page = (ui.grid_page % max_pages) + 1
                show_message(string.format("grid page %d", ui.grid_page))
                mark_dirty()
                return
            end

            -- Pressing rows 1-8 selects targets
            if y >= 1 and y <= 8 then
                local page_offset = (ui.grid_page - 1) * 8
                local target_index = page_offset + y
                if target_index <= #TARGET_IDS then
                    ui.page = PAGE_TARGETS
                    ui.selection[PAGE_TARGETS] = target_index
                    show_message(string.format("target %d", target_index))
                end
            end
        end

        if using_midigrid then
            show_message("midigrid")
        end
    end

    start_redraw_timer()
    mark_dirty()
end

function cleanup()
    save_state()
    stop_redraw_timer()
    if grid_device ~= nil then
        grid_device:all(0)
        grid_device:refresh()
        grid_device.key = nil
        grid_device = nil
    end
    midididi.cleanup()
end

function enc(n, d)
    if n == 1 then
        ui.page = util.clamp(ui.page + encoder_delta(d), 1, ui.page_count)
        show_message(string.lower(page_title()))
        return
    end

    if n == 2 then
        if ui.page == PAGE_DEVICE then
            ui.selection[PAGE_DEVICE] = util.clamp(ui.selection[PAGE_DEVICE] + encoder_delta(d), 1, 2)
        elseif ui.page == PAGE_TARGETS then
            ui.selection[PAGE_TARGETS] = util.clamp(ui.selection[PAGE_TARGETS] + encoder_delta(d), 1, #TARGET_IDS)
        end
        mark_dirty()
        return
    end

    if n == 3 then
        local delta = encoder_delta(d)
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