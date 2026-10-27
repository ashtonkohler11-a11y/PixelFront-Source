--!strict
-- PF038 tutorial stats archive (PF - 2, MM 2026-10-13: Ashton picked "Tutorial stats archive"): every finished tutorial
-- attempt (the TutorialReport summary #tutorial posts) is also kept for good in OpenFrontTutorialArchive_v1, keyed by the
-- attempt's UTC start day ("d:2026-10-13", then "d:2026-10-13:2"... when a chunk fills), so a day's runs are one or a few
-- reads (tools/tutorial-archive-read.luau aggregates a date range in Studio). Personal data stays what the report shows:
-- userId, name, device, country. Writes are batched per server (every FLUSH_SECONDS and at shutdown), off the gameplay
-- thread, idempotent on the attempt id; a failed write keeps the rows for the next flush (capped). Pure: the engine gets
-- {update(key, transform), spawn, wait, log}.
local Archive = {}
Archive.VERSION = 1
Archive.STORE = "OpenFrontTutorialArchive_v1"
Archive.CHUNK = 250 -- rows per key (a row is ~0.5-1 KB, far under the 4 MB value limit)
Archive.FLUSH_SECONDS = 60
Archive.MAX_BUFFER = 400 -- rows a server keeps while the store fails (the oldest go first)

local function num(value: any): number
    return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end
-- "d:YYYY-MM-DD" for a unix time (UTC; days-from-civil inverse, no DateTime needed)
function Archive.day(unix: number): string
    local days = math.floor(num(unix) / 86400) + 719468
    local era = math.floor(days / 146097)
    local doe = days - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = if mp < 10 then mp + 3 else mp - 9
    if m <= 2 then y += 1 end
    return string.format("d:%04d-%02d-%02d", y, m, d)
end
function Archive.chunkKey(day: string, chunk: number): string return if chunk <= 1 then day else day .. ":" .. tostring(chunk) end

-- One finished attempt (TutorialReport.summarize) as a stored row: the report's own fields (display name dropped)
-- plus device and country.
function Archive.row(attempt: any, info: any?): any?
    if type(attempt) ~= "table" or attempt.id == nil or type(attempt.userId) ~= "number" then return nil end
    local row = table.clone(attempt)
    row.display = nil
    -- no device report: the client never loaded (it sends one on start; those runs are 0% done) -> "not loaded"
    row.dev = if info and type(info.device) == "string" then info.device
        elseif attempt.loaded == nil and not attempt.loadedBefore then "not loaded" else nil
    row.cc = if info and type(info.country) == "string" then info.country else nil
    row.id = tostring(attempt.id)
    return row
end

local Methods = {}; Methods.__index = Methods
function Archive.new(ports: any): any
    assert(ports.update and ports.spawn, "Missing tutorial archive ports")
    return setmetatable({ports = ports, buffer = {}, chunk = {}, done = {}, flushing = false, inflight = 0}, Methods)
end
function Methods.add(self: any, attempt: any, info: any?): boolean
    local row = Archive.row(attempt, info)
    -- an attempt finishes on one server, so this server's own record of what it archived keeps retries out of later chunks
    if not row or self.done[row.id] then return false end
    table.insert(self.buffer, row)
    while #self.buffer > Archive.MAX_BUFFER do table.remove(self.buffer, 1) end
    return true
end
-- Write every buffered row (grouped by day). Rows that couldn't be written stay buffered.
function Methods.flush(self: any)
    if self.flushing or #self.buffer == 0 then return end
    self.flushing = true
    local rows = self.buffer; self.buffer = {}
    local byDay, order = {}, {}
    for _, row in rows do
        local day = Archive.day(num(row.start))
        if not byDay[day] then byDay[day] = {}; table.insert(order, day) end
        table.insert(byDay[day], row)
    end
    local failed = {}
    for _, day in order do
        local pending = byDay[day]
        local chunk = self.chunk[day] or 1
        local guard = 0
        while #pending > 0 and guard < 50 do
            guard += 1
            local written = {}
            local ok, failure = pcall(self.ports.update, Archive.chunkKey(day, chunk), function(raw: any): any?
                table.clear(written)
                local record = if type(raw) == "table" and raw.v == Archive.VERSION and type(raw.rows) == "table" then raw else {v = Archive.VERSION, rows = {}}
                local seen = {}
                for _, existing in record.rows do if type(existing) == "table" then seen[existing.id] = true end end
                local changed = false
                for _, row in pending do
                    if seen[row.id] then table.insert(written, row) -- already archived (a retry): done
                    elseif #record.rows < Archive.CHUNK then table.insert(record.rows, row); seen[row.id] = true; table.insert(written, row); changed = true end
                end
                return if changed then record else nil
            end)
            if not ok then
                if self.ports.log then pcall(self.ports.log, "[OpenFront] Tutorial archive write failed: " .. tostring(failure)) end
                for _, row in pending do table.insert(failed, row) end
                break
            end
            local done = {}; for _, row in written do done[row] = true; self.done[row.id] = true end
            local rest = {}; for _, row in pending do if not done[row] then table.insert(rest, row) end end
            if #rest > 0 then chunk += 1 end -- this chunk is full
            self.chunk[day] = chunk
            pending = rest
        end
        for _, row in pending do if not table.find(failed, row) then table.insert(failed, row) end end
    end
    for index, row in failed do table.insert(self.buffer, index, row) end
    while #self.buffer > Archive.MAX_BUFFER do table.remove(self.buffer, 1) end
    self.flushing = false
end
-- The flush loop and the shutdown flush (Roblox wiring passes task.spawn / task.wait).
function Methods.run(self: any)
    self.ports.spawn(function()
        while not self.closed do
            self.ports.wait(Archive.FLUSH_SECONDS)
            pcall(self.flush, self)
        end
    end)
end
function Methods.close(self: any)
    self.closed = true
    pcall(self.flush, self)
end

return table.freeze(Archive)
