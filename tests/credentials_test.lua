-- Verify that official API credentials are explicit and never added as a raw secret header.

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
        format_json = function() return "{}" end,
    }
end

options = {
    dandanplay_app_id = "",
    dandanplay_app_secret = "",
    user_agent = "uosc_danmaku_smooth/test",
    proxy = "",
}

Base64 = {
    encode = function() return "test-signature" end,
}

local signature_input = nil
function Sha256(value)
    signature_input = value
    return "00"
end

function hex_to_bin() return "\0" end
function show_message() end

assert(loadfile("apis/dandanplay.lua"))()

local missing = make_danmaku_request_args(
    "GET",
    "https://api.dandanplay.net/api/v2/search/anime"
)
assert(missing == nil, "official API requests must require explicit credentials")

local custom = make_danmaku_request_args(
    "GET",
    "https://example.invalid/api/v2/search/anime"
)
assert(type(custom) == "table", "custom compatible servers must remain usable without official credentials")

options.dandanplay_app_id = "example-app-id"
options.dandanplay_app_secret = "example-app-secret"

local official = make_danmaku_request_args(
    "GET",
    "https://api.dandanplay.net/api/v2/search/anime"
)
assert(type(official) == "table", "configured official request was not built")
assert(signature_input:find("example-app-id", 1, true), "AppId was not included in the signature input")
assert(signature_input:find("example-app-secret", 1, true), "AppSecret was not included in the signature input")

local joined = table.concat(official, "\n")
assert(joined:find("X-AppId: example-app-id", 1, true), "AppId header is missing")
assert(not joined:find("example-app-secret", 1, true), "AppSecret leaked into request arguments")

io.write("credential handling: ok\n")
