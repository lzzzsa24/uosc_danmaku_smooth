-- Lightweight benchmark for modules/render.lua.
-- Run from the repository root:
--   luajit tests/render_benchmark.lua

local render_path = arg[1] or "modules/render.lua"
local update_count = 0
local removed_count = 0
local now = 0

package.preload["mp.msg"] = function()
    return {
        error = function() end,
        warn = function() end,
        info = function() end,
        verbose = function() end,
    }
end

package.preload["mp.utils"] = function()
    return {
        join_path = function(a, b) return a .. "/" .. b end,
    }
end

local function new_timer()
    return {
        timeout = 0,
        kill = function() end,
        resume = function() end,
    }
end

mp = {
    create_osd_overlay = function()
        return {
            data = "",
            update = function() update_count = update_count + 1 end,
            remove = function() removed_count = removed_count + 1 end,
        }
    end,
    get_property_number = function(name)
        if name == "time-pos" then return now end
        if name == "display-fps" then return 60 end
        if name == "estimated-vf-fps" then return 24 end
        return 0
    end,
    get_property_native = function() return {} end,
    get_time = function() return now end,
    add_timeout = function() return new_timer() end,
    observe_property = function() end,
    unobserve_property = function() end,
    register_event = function() end,
    add_hook = function() end,
    set_property_bool = function() end,
    set_property_native = function() end,
    commandv = function() end,
}

options = {
    fontname = "sans-serif",
    fontsize = 50,
    opacity = 0.7,
    outline = 1,
    shadow = 0,
    bold = true,
    displayarea = 0.85,
    scrolltime = 15,
    fixtime = 5,
    vf_fps = false,
    fps = "60/1.001",
    message_anlignment = 7,
    message_x = 30,
    message_y = 30,
    save_danmaku = false,
}

ENABLED = true
DELAY = 0
DANMAKU = { sources = {}, count = 1 }
DANMAKU_PATH = "."
PID = "benchmark"
HAS_DANMAKU = "benchmark/has-danmaku"
DELAY_PROPERTY = "benchmark/delay"
DANMAKU_COUNT = "benchmark/count"

function binary_search(tbl, target, key)
    local lo, hi, result = 1, #tbl, #tbl + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if key(tbl[mid]) >= target then
            result = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    return result
end

function get_danmaku_visibility() return true end
function set_danmaku_visibility() end
function toggle_danmaku_switch() end
function show_loaded() end
function set_danmaku_button() end
function file_exists() return false end
function save_danmaku() end

COMMENTS = {}
local total_comments = 12000
local duration = 120

for i = 1, total_comments do
    local start_time = (i - 1) * duration / total_comments
    local is_fixed = i % 5 == 0
    local lifetime = is_fixed and options.fixtime or options.scrolltime
    local y = 40 + (i % 18) * 48
    local text = string.format(
        "{\\move(1970, %d, -50, %d)}{\\c&HFFFFFF&}benchmark-%d&#123;\\fs20",
        y,
        y,
        i
    )
    COMMENTS[i] = {
        start_time = start_time,
        end_time = start_time + lifetime,
        style = is_fixed and "TOP" or "R2L",
        text = text,
        pos = is_fixed and {960, y} or nil,
        move = is_fixed and nil or {1970, y, -50, y},
        layer = is_fixed and 1 or 0,
    }
end

assert(loadfile(render_path))()

collectgarbage("collect")
local memory_before = collectgarbage("count")
local started = os.clock()
local frames = 300

for frame = 1, frames do
    now = 60 + frame / 60
    render(now)
end

local elapsed = os.clock() - started
local memory_after = collectgarbage("count")

io.write(string.format(
    "frames=%d comments=%d elapsed=%.4fs avg=%.3fms updates=%d removed=%d memory_delta=%.1fKiB\n",
    frames,
    total_comments,
    elapsed,
    elapsed * 1000 / frames,
    update_count,
    removed_count,
    memory_after - memory_before
))
