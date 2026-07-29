-- Verify local danmaku cache hits, metadata retention, size isolation and expiry.

local root = arg[1] or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Cache = require("modules/cache")

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[copy(key)] = copy(item)
    end
    return result
end

local now = 10000000
local files = {}
local writes = 0

local cache = Cache.new({
    directory = "cache",
    expire_days = 30,
    refresh_hours = 5,
    now = function() return now end,
    join_path = function(directory, filename)
        return directory .. "/" .. filename
    end,
    hash = function(key)
        local sum = 0
        for index = 1, #key do
            sum = (sum + key:byte(index) * index) % 1000000
        end
        return tostring(sum)
    end,
    ensure_directory = function() return true end,
    read = function(path)
        return files[path] and path or nil
    end,
    decode = function(path)
        return files[path] and copy(files[path]) or nil
    end,
    write = function(path, entry)
        files[path] = copy(entry)
        writes = writes + 1
        return true
    end,
    list = function(directory)
        local result = {}
        for path in pairs(files) do
            local filename = path:match("^" .. directory .. "/(.+)$")
            if filename then
                result[#result + 1] = filename
            end
        end
        return result
    end,
    remove = function(path)
        files[path] = nil
        return true
    end,
})

local comments = {
    { p = "1.00,1,16777215", m = "first" },
    { p = "2.00,5,16777215", m = "second" },
}

assert(cache:put("Example 01.mkv", 123456, {
    keyword = "示例动画",
    anime_title = "示例动画",
    episode_title = "第1话",
    episode_id = 1001,
    api_server = "https://example.invalid",
}, comments), "cache put failed")

local downloaded_at = now
local hit, status = cache:get("example 01.MKV", 123456)
assert(hit, "same filename and size should hit cache")
assert(status == "hit", "fresh cache did not report a hit")
assert(hit.keyword == "示例动画", "search keyword was not retained")
assert(hit.episode_id == 1001, "episode id was not retained")
assert(#hit.comments == 2, "cached comments were not retained")
assert(hit.downloaded_at == downloaded_at, "download timestamp was not recorded")
assert(cache:get("Example 01.mkv", 654321) == nil,
    "same filename with a different size must not reuse cache")

now = downloaded_at + 5 * 60 * 60
hit, status = cache:get("Example 01.mkv", 123456)
assert(hit and status == "hit", "cache refreshed at the exact five-hour boundary")

now = now + 1
local stale
stale, status = cache:get("Example 01.mkv", 123456)
assert(stale and status == "stale", "cache older than five hours did not request refresh")
assert(stale.downloaded_at == downloaded_at, "stale lookup changed the download timestamp")
assert(stale.episode_id == 1001 and stale.api_server == "https://example.invalid",
    "stale cache lost the metadata required for a direct comment refresh")

assert(cache:put("Example 01.mkv", 123456, {
    keyword = "示例动画",
    episode_id = 1001,
    api_server = "https://example.invalid",
}, comments), "cache refresh write failed")
local refreshed
refreshed, status = cache:get("Example 01.mkv", 123456)
assert(refreshed and status == "hit", "updated cache was not immediately fresh")
assert(refreshed.downloaded_at == now, "cache refresh did not reset download time")

local refreshed_at = now
now = refreshed_at + 30 * 24 * 60 * 60
assert(cache:cleanup() == 0, "cache was removed at the exact 30-day boundary")
now = now + 1
assert(cache:cleanup() == 1, "cache unused for more than 30 days was not removed")
assert(cache:get("Example 01.mkv", 123456) == nil, "expired cache still returned a hit")
assert(writes >= 3, "cache access timestamps were not persisted")

-- smooth.2 cache files have created_at but no downloaded_at.
now = now + 1
assert(cache:put("Example 01.mkv", 123456, {}, comments), "cache reinsert failed")
for _, entry in pairs(files) do
    entry.downloaded_at = nil
    entry.created_at = now
end
now = now + 5 * 60 * 60
hit, status = cache:get("Example 01.mkv", 123456)
assert(hit and status == "hit", "legacy cache did not fall back to created_at")
now = now + 1
stale, status = cache:get("Example 01.mkv", 123456)
assert(stale and status == "stale", "legacy cache did not refresh after five hours")
assert(cache:delete("Example 01.mkv", 123456), "cache delete failed")
assert(cache:get("Example 01.mkv", 123456) == nil, "deleted cache still returned a hit")

io.write("local danmaku cache: ok\n")
