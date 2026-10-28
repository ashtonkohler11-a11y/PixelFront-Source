--!strict
-- Stats v3 (PF - 2; STATS-SYSTEM-DESIGN §v3.11 contract B): the sharded daily totals the private website sums. Pure:
-- PlayerProfileService adds each delta to ONE random shard of the day (OpenFrontDaily_v1 "d:<YYYY-MM-DD>:<0..15>") with
-- UpdateAsync. Every number is a sum except `ver` (a max). The deltas come from PlayerProfile's fold summaries.
local D = {}
D.VERSION = 1
D.SHARDS = 16
function D.key(day: string, shard: number): string return "d:" .. day .. ":" .. tostring(shard) end

local function num(value: any): number
    return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end
local function bump(t: any, path: { string }, amount: number)
    if amount == 0 then return end
    local node = t
    for i = 1, #path - 1 do
        local key = path[i]
        node[key] = node[key] or {}
        node = node[key]
    end
    local last = path[#path]
    node[last] = num(node[last]) + amount
end
D.bump = bump

-- shard ⊕ delta (in place), tables recursively; `ver` keeps the max; `v` and `day` are set, never summed
local function merge(into: any, delta: any)
    for key, value in delta do
        if key == "v" or key == "day" then continue end
        if key == "ver" then into.ver = math.max(num(into.ver), num(value))
        elseif type(value) == "table" then
            if type(into[key]) ~= "table" then into[key] = {} end
            merge(into[key], value)
        elseif type(value) == "number" then into[key] = num(into[key]) + value end
    end
end
function D.add(shard: any?, day: string, delta: any): any
    local out = if type(shard) == "table" and (shard.v == nil or shard.v == D.VERSION) then shard else { v = D.VERSION, day = day }
    out.v, out.day = D.VERSION, day
    merge(out, delta)
    return out
end

-- after PlayerProfile.applyMatch: s = its summary, record = the record after, cohort
function D.matchDelta(s: any, record: any, ver: number?): any
    local d: any = { ver = ver }
    local mode = s.mode
    bump(d, { "n", "matches" }, 1)
    bump(d, { "n", if mode == "Solo" then "solo" elseif mode == "Ranked" then "ranked" else "public" }, 1)
    if s.res == "W" then bump(d, { "n", "wins" }, 1) end
    bump(d, { "n", "minutes" }, math.floor(num(s.dur) / 6) / 10)
    local total = record.c.matches
    if total >= 1 and total <= 10 then bump(d, { "fn", "FirstTen", tostring(total) }, 1) end
    if total == 1 then
        bump(d, { "fn", "FirstSession", "match" }, 1)
        if num(s.alive) >= 180 then bump(d, { "fn", "FirstSession", "alive3" }, 1) end
    elseif total == 2 then bump(d, { "fn", "FirstSession", "match2" }, 1) end
    if s.offered then bump(d, { "fn", "Next", "seen" }, 1) end
    if s.next then bump(d, { "fn", "Next", "tapped" }, 1); if s.res == "W" then bump(d, { "fn", "Next", "won" }, 1) end end
    if num(s.hint) > 0 then bump(d, { "fn", "Hint", "shown" }, num(s.hint)) end
    if s.openingNew then bump(d, { "fn", "Hint", "done" }, 1) end
    if s.res == "X" then bump(d, { "q", mode .. "|" .. tostring(s.quit or "lt1") .. "|" .. tostring(s.last or "nothing") }, 1) end
    local co = record.co
    if mode == "Solo" then
        bump(d, { "co", co, "soloMatches" }, 1)
        if s.res == "W" then bump(d, { "co", co, "soloWins" }, 1) end
        if s.band then bump(d, { "sk", s.band }, 1) end
        if s.diff then
            local row = { "bal", "dm", s.diff .. "|" .. tostring(s.map) }
            bump(d, { row[1], row[2], row[3], "m" }, 1)
            if s.res == "W" then bump(d, { row[1], row[2], row[3], "w" }, 1) end
            for item, used in s.prem or {} do
                local key = item .. "|" .. s.diff .. "|" .. tostring(s.bandStart or "Flow")
                bump(d, { "bal", "prem", key, if used then "um" else "nm" }, 1)
                if s.res == "W" then bump(d, { "bal", "prem", key, if used then "uw" else "nw" }, 1) end
            end
        end
    end
    for building in s.built or {} do bump(d, { "bal", "bld", mode .. "|" .. building, if s.res == "W" then "w" else "l" }, 1) end
    for lever, n in s.dealt or {} do bump(d, { "dealt", lever }, num(n)); bump(d, { "co", co, "dealt" }, num(n)) end
    return d
end

-- after PlayerProfile.applySession: out = its result. Returns (today's delta, {day, delta} for the day the player joined).
function D.sessionDelta(out: any, record: any, ver: number?): (any, any?)
    local d: any = { ver = ver }
    local co = record.co
    bump(d, { "n", "joins" }, 1)
    bump(d, { "n", "sessionMinutes" }, num(out.minutes)); bump(d, { "co", co, "sessionMinutes" }, num(out.minutes))
    if out.newSession then bump(d, { "n", "sessions" }, 1); bump(d, { "co", co, "sessions" }, 1) end
    if out.firstLeaveToday then bump(d, { "n", "players" }, 1); bump(d, { "co", co, "players" }, 1) end
    if out.returning then bump(d, { "n", "returning" }, 1); bump(d, { "co", co, "returning" }, 1) end
    local joinDay: any = nil
    if out.newPlayer or out.fsFrom or out.fsTo or out.played15 then
        local j: any = { ver = ver }
        if out.newPlayer then
            bump(j, { "n", "newPlayers" }, 1); bump(j, { "co", co, "newPlayers" }, 1)
            bump(j, { "fn", "FirstSession", "join" }, 1)
        end
        if out.fsFrom then bump(j, { "b", out.fsFrom }, -1); if out.fsFrom ~= "later" then bump(j, { "co", co, out.fsFrom }, -1) end end
        if out.fsTo then bump(j, { "b", out.fsTo }, 1); if out.fsTo ~= "later" then bump(j, { "co", co, out.fsTo }, 1) end end
        if out.played15 then bump(j, { "fn", "FirstSession", "played15" }, 1) end
        joinDay = { day = out.joinedDay, delta = j }
    end
    return d, joinDay
end

-- Server-side counts (UI audit build-out 2026-10-28; PlayerProfileService batches them per server into today's shard):
--   cb.e[source] = {c = Cobalt earned, n = grants}; cb.s[item] = {c = Cobalt spent, n = buys} (CosmeticProfiles' economy
--     port: every grant and spend that actually happened)
--   pt[size] = public / custom player-matches by party size ("1" = no party, "6" = 6 or more)
--   inv = {sent = friends invited, link = party joins from an invite link, code = party joins from the hub notice or a
--     typed code, referred = never-played players who arrived through a Roblox invite, credited = their first match}
D.COBALT_SOURCES = table.freeze({ match = "match", streak = "streak", daily = "daily", dailybonus = "daily_bonus",
    weekly = "weekly", invite = "invite", tutorial_reward = "tutorial", group_reward = "group", vip_daily = "vip" })
D.INVITES = table.freeze({ sent = true, link = true, code = true, referred = true, credited = true })
local function safeKey(value: any): string
    if type(value) ~= "string" or value == "" then return "other" end
    return (string.gsub(string.sub(value, 1, 40), "[^%w_]", "_"))
end
-- e = the economy port's {flow = "Source" | "Sink", amount, kind, sku}
function D.cobalt(d: any, e: any)
    if type(e) ~= "table" then return end
    local amount = math.floor(num(e.amount))
    if amount <= 0 then return end
    local side, key = "e", nil
    if e.flow == "Sink" then side, key = "s", safeKey(e.sku)
    elseif e.kind == "IAP" then key = "robux"
    elseif e.kind == "Refund" then key = "refund"
    elseif e.kind == "Reward" then key = "streak_item" -- a streak item already owned, paid as Cobalt
    else key = D.COBALT_SOURCES[e.sku] or "other" end
    bump(d, { "cb", side, key, "c" }, amount)
    bump(d, { "cb", side, key, "n" }, 1)
end
function D.party(d: any, size: any)
    if type(size) ~= "number" or size ~= size or size < 1 then return end
    bump(d, { "pt", tostring(math.min(math.floor(size), 6)) }, 1)
end
function D.invite(d: any, kind: string, n: number?)
    if not D.INVITES[kind] then return end
    bump(d, { "inv", kind }, math.floor(num(n or 1)))
end

-- a cleaned client report (PlayerProfile.cleanReport) plus server-side prompt / purchase marks
function D.reportDelta(report: any, ver: number?): any
    local d: any = { ver = ver }
    for screen, n in report.opens or {} do bump(d, { "ui", screen }, n) end
    for key, row in report.rb or {} do
        for field, n in row do bump(d, { "rb", key, field }, n) end
    end
    return d
end

return table.freeze(D)
