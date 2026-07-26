-- modified from https://github.com/rkscv/danmaku/blob/main/danmaku.lua
local msg = require('mp.msg')
local utils = require("mp.utils")
local unpack = unpack or table.unpack

local osd_width, osd_height, pause = 0, 0, true
local time_pos_observer_active = false
local overlay_low = mp.create_osd_overlay('ass-events')
local overlay_high = mp.create_osd_overlay('ass-events')
local overlay_state = {
    low = { data = nil, width = nil, height = nil, visible = false },
    high = { data = nil, width = nil, height = nil, visible = false },
}
local style_cache = {}
local re_entity = "&#%d+;"
local re_fs = "\\fs(%d+)"
local re_move = "\\move%(.-%)"

local function clear_overlays()
    overlay_low:remove()
    overlay_high:remove()
    overlay_state.low.data = nil
    overlay_state.low.visible = false
    overlay_state.high.data = nil
    overlay_state.high.visible = false
end

local function update_overlay(overlay, state, data, width, height, z)
    if state.visible
        and state.data == data
        and state.width == width
        and state.height == height
    then
        return
    end

    overlay.res_x = width
    overlay.res_y = height
    overlay.z = z
    overlay.data = data
    overlay:update()

    state.data = data
    state.width = width
    state.height = height
    state.visible = true
end

local function get_ass_prefix(fontname, fontsize)
    local opacity = tonumber(options.opacity) or 0
    local outline = options.outline
    local shadow = options.shadow
    local bold = options.bold and "1" or "0"

    if style_cache.fontname ~= fontname
        or style_cache.fontsize ~= fontsize
        or style_cache.opacity ~= opacity
        or style_cache.outline ~= outline
        or style_cache.shadow ~= shadow
        or style_cache.bold ~= bold
    then
        local alpha = string.format("%02X", (1 - opacity) * 255)
        style_cache.prefix = string.format(
            "{\\rDefault\\fn%s\\fs%d\\c&HFFFFFF&\\alpha&H%s\\bord%s\\shad%s\\b%s\\q2}",
            fontname,
            fontsize,
            alpha,
            outline,
            shadow,
            bold
        )
        style_cache.fontname = fontname
        style_cache.fontsize = fontsize
        style_cache.opacity = opacity
        style_cache.outline = outline
        style_cache.shadow = shadow
        style_cache.bold = bold
    end

    return style_cache.prefix
end

local function prepare_event_text(event)
    if event._render_text ~= nil then
        return event._render_text
    end

    local text = event.text or ""
    text = text:gsub(re_entity, "")
    if text:find("\\fs", 1, true) then
        text = text:gsub(re_fs, function(size)
            return string.format("\\fs%d", math.floor((tonumber(size) or 0) * 1.5))
        end)
    end
    if event.move then
        text = text:gsub(re_move, "")
    end

    event._render_text = text
    return text
end

local function first_visible_index(comments, target)
    local lo, hi = 1, #comments
    local result = hi + 1

    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if comments[mid].start_time >= target then
            result = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end

    return result
end

local function realtime_position_text(event, pos, displayarea)
    if not event.move then
        local _, current_y = unpack(event.pos)
        if not current_y or tonumber(current_y) > displayarea then return end
        local alignment = event.style ~= "SP" and event.style ~= "MSG" and 8 or 7
        return string.format("{\\an%d}%s", alignment, prepare_event_text(event))
    end

    local x1, y1, x2, y2 = unpack(event.move)
    local duration = event.end_time - event.start_time
    local progress = (pos - event.start_time) / duration

    local current_x = x1 + (x2 - x1) * progress
    local current_y = y1 + (y2 - y1) * progress

    if current_y > displayarea then return end
    if event.style ~= "SP" and event.style ~= "MSG" then
        return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, prepare_event_text(event))
    else
        return string.format("{\\pos(%.1f,%.1f)\\an7}%s", current_x, current_y, prepare_event_text(event))
    end
end

function render(pos_arg)
    local comments = COMMENTS
    if comments == nil then return end

    local pos, err
    if pos_arg == nil then
        pos, err = mp.get_property_number('time-pos')
        if err ~= nil then
            return msg.error(err)
        end
    else
        pos = pos_arg
    end

    if not pos then
        clear_overlays()
        return
    end

    local fontname = options.fontname
    local fontsize = tonumber(options.fontsize) or 50

    local width, height = 1920, 1080
    local ratio = osd_height > 0 and osd_width / osd_height or width / height
    if ratio > 0 and width / height < ratio then
        height = width / ratio
        fontsize = fontsize - ratio * 2
    end
    fontsize = math.max(1, math.floor(fontsize + 0.5))

    local ass_events_low = {}
    local ass_events_high = {}
    local low_count, high_count = 0, 0
    local max_display = math.max(tonumber(options.scrolltime) or 15, tonumber(options.fixtime) or 5)
    local window_start = pos - max_display

    local lo = first_visible_index(comments, window_start)
    local ass_prefix = get_ass_prefix(fontname, fontsize)
    local displayarea = height * (tonumber(options.displayarea) or 0.85)

    for i = lo, #comments do
        local event = comments[i]
        if not event then break end

        if event.start_time > pos then break end
        if event.end_time >= pos then
            local text = realtime_position_text(event, pos, displayarea)
            if text then
                local ass_text = ass_prefix .. text
                if event.layer == nil or tonumber(event.layer) == 0 then
                    low_count = low_count + 1
                    ass_events_low[low_count] = ass_text
                else
                    high_count = high_count + 1
                    ass_events_high[high_count] = ass_text
                end
            end
        end
    end

    update_overlay(overlay_low, overlay_state.low, table.concat(ass_events_low, '\n'), width, height, 0)
    update_overlay(overlay_high, overlay_state.high, table.concat(ass_events_high, '\n'), width, height, 1)
end

local function time_pos_callback(_, time_pos)
    if time_pos then
        render(time_pos)
    else
        clear_overlays()
    end
end

local function start_time_observer()
    if not time_pos_observer_active then
        mp.observe_property('time-pos', 'number', time_pos_callback)
        time_pos_observer_active = true
    end
end

local function stop_time_observer()
    if time_pos_observer_active then
        mp.unobserve_property(time_pos_callback)
        time_pos_observer_active = false
    end
end

function render_danmaku(from_menu, no_osd)
    if ENABLED and (from_menu or get_danmaku_visibility()) then
        if not no_osd then
            show_loaded(true)
        end
        toggle_danmaku_switch("on")
        show_danmaku_func()
    else
        show_message("")
        hide_danmaku_func()
    end
end

local function filter_state(label, name)
    local filters = mp.get_property_native("vf")
    for _, filter in pairs(filters) do
        if filter.label == label or filter.name == name
        or filter.params[name] ~= nil then
            return true
        end
    end
    return false
end

function show_danmaku_func()
    mp.set_property_bool(HAS_DANMAKU, true)
    set_danmaku_visibility(true)
    render()
    if not pause then
        start_time_observer()
    end
    if options.vf_fps then
        local display_fps = mp.get_property_number('display-fps')
        local video_fps = mp.get_property_number('estimated-vf-fps')
        if (display_fps and display_fps < 58) or (video_fps and video_fps > 58) then
            return
        end
        if not filter_state("danmaku", "fps") then
            mp.commandv("vf", "append", string.format("@danmaku:fps=fps=%s", options.fps))
        end
    end
end

function hide_danmaku_func()
    stop_time_observer()
    mp.set_property_bool(HAS_DANMAKU, false)
    set_danmaku_visibility(false)
    clear_overlays()
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end
end

local message_overlay = mp.create_osd_overlay('ass-events')
local message_timer = mp.add_timeout(3, function()
    message_overlay:remove()
end, true)

function show_message(text, time)
    message_timer.timeout = time or 3
    message_timer:kill()
    message_overlay:remove()
    local message = string.format("{\\an%d\\pos(%d,%d)}%s", options.message_anlignment,
       options.message_x, options.message_y, text)
    local width, height = 1920, 1080
    local ratio = osd_width / osd_height
    if width / height < ratio then
        height = width / ratio
    end
    message_overlay.res_x = width
    message_overlay.res_y = height
    message_overlay.data = message
    message_overlay:update()
    message_timer:resume()
end

mp.observe_property('osd-width', 'number', function(_, value) osd_width = value or osd_width end)
mp.observe_property('osd-height', 'number', function(_, value) osd_height = value or osd_height end)
mp.observe_property('pause', 'bool', function(_, value)
    if value ~= nil then
        pause = value
    end
    if ENABLED then
        if pause then
            stop_time_observer()
        elseif COMMENTS ~= nil then
            start_time_observer()
        end
    end
end)

mp.register_event('playback-restart', function(event)
    if event.error then
        return msg.error(event.error)
    end
    if ENABLED and COMMENTS ~= nil then
        render()
    end
end)

mp.add_hook("on_unload", 50, function()
    COMMENTS, DELAY = nil, 0
    stop_time_observer()
    clear_overlays()
    mp.set_property_native(DELAY_PROPERTY, 0)
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end

    local files_to_remove = {
        file1 = utils.join_path(DANMAKU_PATH, "temp-" .. PID .. ".mp4"),
    }

    if options.save_danmaku then
        save_danmaku(true)
    end

    for _, file in pairs(files_to_remove) do
        if file_exists(file) then
            os.remove(file)
        end
    end

    DANMAKU = {sources = {}, count = 1}
    mp.set_property_native(DANMAKU_COUNT, 0)
end)
