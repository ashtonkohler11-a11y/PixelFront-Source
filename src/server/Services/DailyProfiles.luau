--!strict
-- PF039 daily challenges + login streak (PF - 2; Ashton approved PF - 1's boards 2026-10-13: work/daily/boards). Pure:
-- DailyService owns the DataStore (OpenFrontDaily_v1 "u:<userId>"), the DailyState / DailyCommand remotes and the grants.
-- Three dailies a UTC day (00:00) from a pool, all three = a bonus, one weekly (Monday 00:00 UTC), one free reroll a day
-- (VIP 2), a 7-day login streak (a missed day = day 1). Progress comes from real matches (public, Solo, custom; never the
-- tutorial): each match's own facts on top of what earlier matches gave (`base`), so a live update never double counts.
local Daily = {}
Daily.VERSION = 1
Daily.REWARD = table.freeze({daily = {cobalt = 25}, bonus = {cobalt = 100}, weekly = {cobalt = 300}}) -- Levels removed 2026-10-26: no daily XP
-- the streak's seven tiles (Ashton 2026-10-25, daily variant B): day 2 = Artillery and day 7 = Warden (was the Longshot until the
-- premium reshuffle; a Longshot owner owns the Warden, so gets the Cobalt) (Arsenal unlocks,
-- CosmeticService.grantArsenal), day 4 = the Glacier pack (its cosmetic items), the rest a Cobalt climb (PF - 2). On an item
-- day `cobalt` is what an owner gets instead (flat, Ashton approved: ~2 / ~3 / ~5 matches of pay) and what VIP's "2x" adds.
-- Cobalt days (Ashton 2026-10-25): 500 / 750 / 1,000 / 1,500. The Glacier pack's items are PF - 1's reserved ids; until they
-- are in CosmeticCatalog, DailyService grants only the catalogued ones and the tile pays its Cobalt.
Daily.STREAK = table.freeze({{cobalt = 500}, table.freeze({arsenal = "artillery", cobalt = 1000}), {cobalt = 750},
    table.freeze({pack = "glacier", items = table.freeze({"skin_glacier", "buildings_glacier", "vfx_frostbloom", "nameplate_icicle", "flag_snowcrest"}), cobalt = 1500}),
    {cobalt = 1000}, {cobalt = 1500}, table.freeze({arsenal = "warden", cobalt = 2500})})
-- the pools: kind -> the goals one can draw (ids are kind_goal, e.g. tiles_2000)
Daily.POOL = table.freeze({{kind = "win", goals = {1}}, {kind = "tiles", goals = {1500, 2000, 3000}}, {kind = "tribes", goals = {3, 5}},
    {kind = "cities", goals = {2, 3, 4}}, {kind = "nuke", goals = {1}}, {kind = "survive", goals = {8, 12}}, {kind = "nations", goals = {1}}})
Daily.WEEKLY = table.freeze({{kind = "win", goals = {5}}, {kind = "tiles", goals = {20000}}, {kind = "tribes", goals = {25}}, {kind = "cities", goals = {15}}})
Daily.REROLLS, Daily.VIP_REROLLS = 1, 2

local function int(value: any): number
    return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then math.max(0, math.floor(value)) else 0
end
function Daily.day(unix: number): number return math.floor(int(unix) / 86400) end
function Daily.week(day: number): number return (day + 3) // 7 end -- weeks start Monday 00:00 UTC (1970-01-01 was a Thursday)
function Daily.resetAt(day: number): number return (day + 1) * 86400 end
function Daily.weekResetAt(day: number): number return (Daily.week(day) + 1) * 7 * 86400 - 3 * 86400 end

-- a small deterministic generator per (user, day): the same three dailies on every server
local function random(seed: number): () -> number
    local s = seed % 2147483647; if s <= 0 then s += 2147483646 end
    return function() s = (s * 48271) % 2147483647; return s end
end
local function challenge(entry: any, goal: number): any return {id = entry.kind .. "_" .. tostring(goal), kind = entry.kind, goal = goal, base = 0, progress = 0} end
local function draw(pool: {any}, nextValue: () -> number, exclude: {[string]: boolean}): any?
    local options = {}
    for _, entry in pool do if not exclude[entry.kind] then table.insert(options, entry) end end
    if #options == 0 then return nil end
    local entry = options[nextValue() % #options + 1]
    return challenge(entry, entry.goals[nextValue() % #entry.goals + 1])
end
function Daily.newDay(userId: number, day: number): {any}
    local nextValue = random(userId * 7919 + day * 104729)
    local list, kinds = {}, {}
    for _ = 1, 3 do local c = draw(Daily.POOL, nextValue, kinds); if c then kinds[c.kind] = true; table.insert(list, c) end end
    return list
end
function Daily.newWeekly(userId: number, week: number): any
    return draw(Daily.WEEKLY, random(userId * 15485863 + week * 32452843), {})
end
function Daily.newRecord(): any
    return {v = Daily.VERSION, day = -1, daily = {}, claimed = {}, bonus = false, rerolls = 0, week = -1, weekly = nil, weeklyClaimed = false,
        streak = {day = -1, index = 0}, matches = {}}
end
-- A stored record, checked; nil when it isn't ours (never overwritten).
function Daily.validate(raw: any): any?
    if raw == nil then return Daily.newRecord() end
    if type(raw) ~= "table" or raw.v ~= Daily.VERSION or type(raw.daily) ~= "table" or type(raw.claimed) ~= "table" or type(raw.streak) ~= "table" then return nil end
    local record = Daily.newRecord()
    record.day, record.bonus, record.rerolls = math.floor(tonumber(raw.day) or -1), raw.bonus == true, int(raw.rerolls)
    for _, c in raw.daily do
        if type(c) == "table" and type(c.id) == "string" and type(c.kind) == "string" then
            table.insert(record.daily, {id = c.id, kind = c.kind, goal = math.max(1, int(c.goal)), base = int(c.base), progress = int(c.progress)})
        end
    end
    for id, v in raw.claimed do if type(id) == "string" and v == true then record.claimed[id] = true end end
    record.week, record.weeklyClaimed = math.floor(tonumber(raw.week) or -1), raw.weeklyClaimed == true
    if type(raw.weekly) == "table" and type(raw.weekly.id) == "string" then
        local w = raw.weekly; record.weekly = {id = w.id, kind = w.kind, goal = math.max(1, int(w.goal)), base = int(w.base), progress = int(w.progress)}
    end
    record.streak = {day = math.floor(tonumber(raw.streak.day) or -1), index = math.clamp(int(raw.streak.index), 0, #Daily.STREAK),
        at = if type(raw.streak.at) == "number" then int(raw.streak.at) else nil}
    if type(raw.matches) == "table" then for key, v in raw.matches do if type(key) == "string" and v == true then record.matches[key] = true end end end
    return record
end
-- Bring a record to today (a new day: new dailies, claims and rerolls reset; a new week: a new weekly). true = changed.
function Daily.roll(record: any, userId: number, day: number): boolean
    local changed = false
    if record.day ~= day then
        record.day, record.daily, record.claimed, record.bonus, record.rerolls, record.matches = day, Daily.newDay(userId, day), {}, false, 0, {}
        changed = true
    end
    local week = Daily.week(day)
    if record.week ~= week then record.week, record.weekly, record.weeklyClaimed = week, Daily.newWeekly(userId, week), false; changed = true end
    return changed
end

-- One match's facts (so far): {won, tiles, tribes, nations, cities, nukes, minutes}. What a challenge of `kind` counts.
function Daily.amount(kind: string, facts: any): number
    if kind == "win" then return if facts.won == true then 1 else 0 end
    if kind == "survive" then return int(facts.minutes) end
    return int(facts[kind])
end
local function counts(c: any, facts: any): number
    if c.kind == "survive" then return math.max(c.base, Daily.amount("survive", facts)) end -- survive: the best single match
    return c.base + Daily.amount(c.kind, facts)
end
-- A live update from a running match (never stored as base): returns the ids that just reached their goal.
function Daily.live(record: any, facts: any): {string}
    local done = {}
    for _, c in record.daily do
        local before = c.progress
        c.progress = math.max(c.progress, math.min(c.goal, counts(c, facts)))
        if before < c.goal and c.progress >= c.goal then table.insert(done, c.id) end
    end
    local w = record.weekly
    if w then
        local before = w.progress
        w.progress = math.max(w.progress, math.min(w.goal, counts(w, facts)))
        if before < w.goal and w.progress >= w.goal then table.insert(done, w.id) end
    end
    return done
end
-- The match is over for this player (the XP-grant moment): its facts become base, once per match key.
-- Returns gains {[id] = what this match added} (nil when this match was already counted), and the ids now done.
function Daily.final(record: any, key: string, facts: any): ({[string]: number}?, {string})
    if record.matches[key] then return nil, {} end
    record.matches[key] = true
    local done = Daily.live(record, facts) -- (a goal a live update already reached isn't listed again)
    local gains = {}
    local function settle(c: any)
        local before = c.base
        local total = math.min(c.goal, counts(c, facts))
        c.base, c.progress = math.max(c.base, total), math.max(c.progress, total)
        if c.base > before then gains[c.id] = c.base - before end
    end
    for _, c in record.daily do settle(c) end
    if record.weekly then settle(record.weekly) end
    return gains, done
end
function Daily.find(record: any, id: string): any?
    for _, c in record.daily do if c.id == id then return c end end
    return nil
end
function Daily.allDone(record: any): number
    local n = 0
    for _, c in record.daily do if c.progress >= c.goal then n += 1 end end
    return n
end
-- Reroll one unfinished, unclaimed daily (a new kind, not one of the others). nil, reason when it can't.
function Daily.reroll(record: any, userId: number, id: string, vip: boolean): (boolean, string?)
    local limit = if vip then Daily.VIP_REROLLS else Daily.REROLLS
    if record.rerolls >= limit then return false, "no rerolls" end
    local c = Daily.find(record, id)
    if not c or c.progress >= c.goal or record.claimed[id] then return false, "not rerollable" end
    local kinds = {}
    for _, other in record.daily do kinds[other.kind] = true end
    local fresh = draw(Daily.POOL, random(userId * 31 + record.day * 977 + (record.rerolls + 1) * 7777), kinds)
    if not fresh then return false, "no other challenge" end
    for index, other in record.daily do if other == c then record.daily[index] = fresh end end
    record.rerolls += 1
    return true, nil
end
-- PF045 (Ashton picked a rolling 24 h): the next streak claim opens WINDOW after the last one; no claim within GRACE of
-- the last breaks the streak (day 1 again), so a later claim each day never costs it. A record from before keeps its UTC
-- day: its last claim counts as made at that day's 00:00 UTC (so it opens at the next UTC midnight, never twice a day).
Daily.WINDOW, Daily.GRACE = 86400, 2 * 86400
local function lastAt(s: any): number? return if s.index >= 1 then (s.at or (if s.day >= 0 then s.day * 86400 else nil)) else nil end
-- The streak now: its tile (1..7), whether it can be claimed, when the next claim opens (unix; nil = open) and the
-- window's key (the claim it fills: the previous claim + WINDOW, or "start" for a first claim). A retry or a second
-- server claiming the same window writes the same receipt, so it can never pay twice.
function Daily.streakNow(record: any, now: number): (number, boolean, number?, string)
    local s = record.streak
    local at = lastAt(s)
    if not at then return 1, true, nil, "start" end
    local key = tostring(at + Daily.WINDOW)
    if now < at + Daily.WINDOW then return math.max(1, s.index), false, at + Daily.WINDOW, key end
    if now < at + Daily.GRACE then return s.index % #Daily.STREAK + 1, true, nil, key end
    return 1, true, nil, key -- a full window missed: day 1
end
-- (callers that only know the UTC day: the middle of that day)
local function nowOf(day: number, now: number?): number return now or day * 86400 + 43200 end
function Daily.streakToday(record: any, day: number, now: number?): (number, boolean)
    local index, can = Daily.streakNow(record, nowOf(day, now))
    return index, can
end
-- What a claim grants and its receipt key (CosmeticProfiles.grantRewards), or nil, reason.
-- target "daily" | "bonus" | "weekly" | "streak"; owns(itemId) -> boolean for the streak's skin tiles.
function Daily.claimable(record: any, target: string, id: string?, day: number, now: number?): (any?, string?)
    if target == "daily" then
        local c = id and Daily.find(record, id)
        if not c then return nil, "unknown" end
        if record.claimed[c.id] then return nil, "claimed" end
        if c.progress < c.goal then return nil, "not done" end
        return {receipt = "daily_" .. day .. "_" .. c.id, cobalt = Daily.REWARD.daily.cobalt}, nil
    elseif target == "bonus" then
        if record.bonus then return nil, "claimed" end
        if Daily.allDone(record) < #record.daily or #record.daily == 0 then return nil, "not done" end
        return {receipt = "dailybonus_" .. day, cobalt = Daily.REWARD.bonus.cobalt}, nil
    elseif target == "weekly" then
        local w = record.weekly
        if not w or (id and id ~= w.id) then return nil, "unknown" end
        if record.weeklyClaimed then return nil, "claimed" end
        if w.progress < w.goal then return nil, "not done" end
        return {receipt = "weekly_" .. record.week .. "_" .. w.id, cobalt = Daily.REWARD.weekly.cobalt}, nil
    elseif target == "streak" then
        local index, can, _, key = Daily.streakNow(record, nowOf(day, now))
        if not can then return nil, "claimed" end
        local tile = Daily.STREAK[index]
        -- receipt per window (PF045); vip = the VIP bonus: the same tile's Cobalt value ("2x daily rewards"), its own receipt
        return {receipt = "streakr_" .. key, cobalt = tile.cobalt, item = tile.item, arsenal = tile.arsenal, pack = tile.pack,
            packItems = tile.items, streakIndex = index, vipCobalt = tile.cobalt, vipReceipt = "vipstreak_" .. key}, nil
    end
    return nil, "unknown"
end
-- Mark a granted claim (after the grant succeeded).
function Daily.markClaimed(record: any, target: string, id: string?, grant: any, day: number, now: number?)
    if target == "daily" and id then record.claimed[id] = true
    elseif target == "bonus" then record.bonus = true
    elseif target == "weekly" then record.weeklyClaimed = true
    elseif target == "streak" then record.streak = {day = day, index = grant.streakIndex, at = nowOf(day, now)} end
end
-- Two copies of the same record (this server's and the store's, e.g. across a teleport): the union, never losing
-- progress or a claim. The later day/week wins; on the same day the copy with more rerolls owns the challenge set.
function Daily.merge(stored: any, mine: any): any
    if stored.day ~= mine.day then return if stored.day > mine.day then stored else mine end
    local out = if stored.rerolls > mine.rerolls then stored else mine
    local other = if out == stored then mine else stored
    for _, c in out.daily do
        local twin = Daily.find(other, c.id)
        if twin then c.base, c.progress = math.max(c.base, twin.base), math.max(c.progress, twin.progress) end
    end
    for id in other.claimed do out.claimed[id] = true end
    for key in other.matches do out.matches[key] = true end
    out.bonus = out.bonus or other.bonus
    if other.week == out.week and other.weekly and out.weekly and other.weekly.id == out.weekly.id then
        out.weekly.base, out.weekly.progress = math.max(out.weekly.base, other.weekly.base), math.max(out.weekly.progress, other.weekly.progress)
        out.weeklyClaimed = out.weeklyClaimed or other.weeklyClaimed
    elseif other.week > out.week then out.week, out.weekly, out.weeklyClaimed = other.week, other.weekly, other.weeklyClaimed end
    if (lastAt(other.streak) or -1) > (lastAt(out.streak) or -1) then out.streak = other.streak end -- the later claim wins
    return out
end

-- The DailyState packet (PF - 1's agreed shape). owns(itemId) -> boolean; vip -> boolean; day = today.
function Daily.view(record: any, day: number, vip: boolean, owns: (string) -> boolean, now: number?): any
    local function state(done: boolean, claimed: boolean): string return if claimed then "claimed" elseif done then "done" else "run" end
    local daily = {}
    for _, c in record.daily do
        table.insert(daily, {id = c.id, kind = c.kind, goal = c.goal, progress = math.min(c.goal, c.progress),
            reward = table.clone(Daily.REWARD.daily), state = state(c.progress >= c.goal, record.claimed[c.id] == true)})
    end
    local done = Daily.allDone(record)
    local weekly = nil
    if record.weekly then
        local w = record.weekly
        weekly = {id = w.id, kind = w.kind, goal = w.goal, progress = math.min(w.goal, w.progress), reward = table.clone(Daily.REWARD.weekly),
            state = state(w.progress >= w.goal, record.weeklyClaimed)}
    end
    local today, can, opensAt = Daily.streakNow(record, nowOf(day, now))
    local tiles = {}
    for _, tile in Daily.STREAK do
        local copy = table.clone(tile)
        -- owned: the claim pays `cobalt` instead (an Arsenal id is owned as "arsenal_<id>"; a pack when all its items are)
        if tile.item then copy.owned = owns(tile.item) == true
        elseif tile.arsenal then copy.owned = owns("arsenal_" .. tile.arsenal) == true
        elseif tile.pack then
            local all = #tile.items > 0
            for _, id in tile.items do if not owns(id) then all = false end end
            copy.owned, copy.items = all, nil
        end
        table.insert(tiles, copy)
    end
    local limit = if vip then Daily.VIP_REROLLS else Daily.REROLLS
    return {kind = "Daily", loaded = true, day = day, resetAt = Daily.resetAt(day), weekResetAt = Daily.weekResetAt(day),
        rerolls = math.max(0, limit - record.rerolls), daily = daily,
        bonus = {reward = table.clone(Daily.REWARD.bonus), done = done, state = state(done >= #record.daily and #record.daily > 0, record.bonus)},
        -- streak.opensAt: the next claim (unix; nil while open); vipCobalt: VIP's same-size bonus on today's claim (nil without VIP)
        weekly = weekly, streak = {today = today, claimable = can, tiles = tiles, opensAt = opensAt,
            vipCobalt = if vip then Daily.STREAK[today].cobalt else nil}}
end

return table.freeze(Daily)
