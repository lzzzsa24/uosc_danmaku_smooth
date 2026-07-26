-- Benchmark the conversion path and simplified/traditional conversion cache.
-- Run from the repository root:
--   luajit tests/parse_benchmark.lua

local root = arg[1] or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

package.preload["mp.msg"] = function()
    return {
        error = function() end,
        warn = function() end,
        info = function() end,
        verbose = function() end,
        debug = function() end,
    }
end

package.preload["mp.utils"] = function()
    return {
        file_info = function() return nil end,
        parse_json = function() return nil end,
    }
end

mp = {
    command_native = function() return "" end,
}

options = {
    blacklist_path = "",
    chConvert = 1,
    merge_tolerance = -1,
    merge_without_style = false,
    max_screen_danmaku = 0,
    fontsize = 50,
    scrolltime = 15,
    fixtime = 5,
}

function show_message() end

assert(loadfile(root .. "/modules/utils.lua"))()
assert(loadfile(root .. "/modules/parse.lua"))()

local total_comments = 20000
local source = { data = {} }
for i = 1, total_comments do
    source.data[i] = {
        time = i / 100,
        orig_time = i / 100,
        type = 1,
        size = 25,
        color = 0xFFFFFF,
        text = string.format("彈幕測試-%05d", i),
    }
end

DANMAKU = {
    sources = {
        ["benchmark"] = source,
    },
}
COMMENTS = nil

collectgarbage("collect")
local memory_before = collectgarbage("count")
local started = os.clock()
convert_danmaku_to_ass_events(true)
local elapsed = os.clock() - started
collectgarbage("collect")
local memory_after = collectgarbage("count")

assert(type(COMMENTS) == "table", "conversion did not produce a comment table")
io.write(string.format(
    "comments=%d events=%d elapsed=%.4fs memory_delta=%.1fKiB\n",
    total_comments,
    #COMMENTS,
    elapsed,
    memory_after - memory_before
))
