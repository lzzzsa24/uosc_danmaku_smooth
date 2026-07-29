local Cache = {}

local CACHE_VERSION = 1
local CACHE_FILE_PREFIX = "entry-"
local SECONDS_PER_DAY = 24 * 60 * 60
local SECONDS_PER_HOUR = 60 * 60

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize_size(file_size)
    local value = tonumber(file_size) or 0
    if value <= 0 then
        return 0
    end
    return math.floor(value)
end

function Cache.make_key(video_name, file_size)
    local name = trim(video_name):lower()
    if name == "" then
        return nil
    end
    return name .. "|" .. tostring(normalize_size(file_size))
end

function Cache.is_expired(entry, now, expire_days)
    local days = tonumber(expire_days) or 30
    if days <= 0 then
        return false
    end

    local last_used_at = tonumber(entry and entry.last_used_at)
    if not last_used_at then
        return true
    end
    return last_used_at < (now - days * SECONDS_PER_DAY)
end

function Cache.needs_refresh(entry, now, refresh_hours)
    local hours = tonumber(refresh_hours) or 5
    if hours <= 0 then
        return false
    end

    -- smooth.2 缓存没有 downloaded_at，使用 created_at 保持向后兼容。
    local downloaded_at = tonumber(entry and (entry.downloaded_at or entry.created_at))
    if not downloaded_at then
        return true
    end
    return downloaded_at < (now - hours * SECONDS_PER_HOUR)
end

local function is_valid_entry(entry)
    return type(entry) == "table"
        and entry.version == CACHE_VERSION
        and trim(entry.video_name) ~= ""
        and type(entry.comments) == "table"
        and #entry.comments > 0
end

function Cache.new(config)
    assert(type(config) == "table", "cache config is required")
    assert(type(config.directory) == "string" and config.directory ~= "",
        "cache directory is required")
    assert(type(config.join_path) == "function", "cache join_path function is required")
    assert(type(config.hash) == "function", "cache hash function is required")
    assert(type(config.ensure_directory) == "function",
        "cache ensure_directory function is required")
    assert(type(config.read) == "function", "cache read function is required")
    assert(type(config.decode) == "function", "cache decode function is required")
    assert(type(config.write) == "function", "cache write function is required")
    assert(type(config.list) == "function", "cache list function is required")
    assert(type(config.remove) == "function", "cache remove function is required")

    local self = {
        directory = config.directory,
        join_path = config.join_path,
        hash = config.hash,
        ensure_directory = config.ensure_directory,
        read = config.read,
        decode = config.decode,
        write = config.write,
        list = config.list,
        remove = config.remove,
        now = config.now or os.time,
        expire_days = tonumber(config.expire_days) or 30,
        refresh_hours = tonumber(config.refresh_hours) or 5,
        warn = config.warn or function() end,
    }

    function self:_path_for_key(key)
        local digest = tostring(self.hash(key) or "")
        if digest == "" or digest:find("[^%w_-]") then
            self.warn("无法生成安全的本地弹幕缓存文件名")
            return nil
        end
        return self.join_path(self.directory, CACHE_FILE_PREFIX .. digest .. ".json")
    end

    function self:_load(path)
        local ok_read, raw = pcall(self.read, path)
        if not ok_read or raw == nil or raw == "" then
            return nil
        end

        local ok_decode, entry = pcall(self.decode, raw)
        if not ok_decode or not is_valid_entry(entry) then
            return nil
        end
        return entry
    end

    function self:_save(path, entry)
        local ok_directory, directory_ready = pcall(self.ensure_directory, self.directory)
        if not ok_directory or not directory_ready then
            self.warn("无法创建本地弹幕缓存目录：" .. self.directory)
            return false
        end

        local ok, result = pcall(self.write, path, entry)
        if not ok or result == false then
            self.warn("本地弹幕缓存写入失败：" .. path)
            return false
        end
        return true
    end

    function self:cleanup()
        local ok_directory, directory_ready = pcall(self.ensure_directory, self.directory)
        if not ok_directory or not directory_ready then
            return 0
        end

        local ok_list, files = pcall(self.list, self.directory)
        if not ok_list or type(files) ~= "table" then
            return 0
        end

        local now = self.now()
        local removed = 0
        for _, filename in ipairs(files) do
            if filename:match("^" .. CACHE_FILE_PREFIX .. "[%w_-]+%.json$") then
                local path = self.join_path(self.directory, filename)
                local entry = self:_load(path)
                if not entry or Cache.is_expired(entry, now, self.expire_days) then
                    local ok_remove, did_remove = pcall(self.remove, path)
                    if ok_remove and did_remove then
                        removed = removed + 1
                    end
                end
            end
        end
        return removed
    end

    function self:get(video_name, file_size)
        local key = Cache.make_key(video_name, file_size)
        if not key then
            return nil
        end

        local path = self:_path_for_key(key)
        if not path then
            return nil
        end

        local entry = self:_load(path)
        if not entry then
            return nil
        end
        if Cache.make_key(entry.video_name, entry.file_size) ~= key then
            self.warn("本地弹幕缓存键冲突，已忽略：" .. path)
            return nil
        end
        local now = self.now()
        if Cache.is_expired(entry, now, self.expire_days) then
            pcall(self.remove, path)
            return nil, "expired"
        end
        if Cache.needs_refresh(entry, now, self.refresh_hours) then
            return entry, "stale"
        end

        entry.last_used_at = now
        self:_save(path, entry)
        return entry, "hit"
    end

    function self:delete(video_name, file_size)
        local key = Cache.make_key(video_name, file_size)
        if not key then
            return false
        end

        local path = self:_path_for_key(key)
        if not path then
            return false
        end
        if not self:_load(path) then
            return false
        end

        local ok_remove, did_remove = pcall(self.remove, path)
        return ok_remove and did_remove and true or false
    end

    function self:put(video_name, file_size, metadata, comments)
        local key = Cache.make_key(video_name, file_size)
        if not key or type(comments) ~= "table" or #comments == 0 then
            return false
        end

        local path = self:_path_for_key(key)
        if not path then
            return false
        end

        local now = self.now()
        local previous = self:_load(path)
        local entry = {
            version = CACHE_VERSION,
            video_name = trim(video_name),
            file_size = normalize_size(file_size),
            created_at = previous and previous.created_at or now,
            downloaded_at = now,
            last_used_at = now,
            comments = comments,
            comment_count = #comments,
        }

        metadata = type(metadata) == "table" and metadata or {}
        entry.keyword = trim(metadata.keyword)
        entry.anime_title = trim(metadata.anime_title)
        entry.episode_title = trim(metadata.episode_title)
        entry.episode_id = metadata.episode_id
        entry.api_server = trim(metadata.api_server)

        return self:_save(path, entry)
    end

    return self
end

return Cache
