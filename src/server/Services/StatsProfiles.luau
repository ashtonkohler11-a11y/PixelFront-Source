--!strict
-- PF035 lifetime stats (PF - 2, MM go 2026-10-13): the persisted record behind the Stats page, which used to be
-- session-only (public and Solo matches run on other servers, so nothing ever counted). Pure: StatsService owns the
-- DataStore (OpenFrontStats_v1 "u:<userId>") and the StatsCommand remote. One entry per player per match, made at the
-- XP-grant moments (PublicMatchRuntime / MatchService endLevels), idempotent on the match key; the tutorial never
-- records (it has no grant). A match counts when the player had land (peak land > 0), the same rule as the Discord
-- feed's presence count (DiscordFeed Methods.grant), so the two never disagree on what a match is.
local Stats = {}
Stats.VERSION = 1
Stats.HISTORY = 20 -- the newest matches kept in full
Stats.KEYS = 100 -- match keys remembered for idempotency (and the client's session de-duplication)
Stats.BUILDS = table.freeze({city = "cityConstructed", port = "portConstructed", factory = "factoryConstructed",
    post = "defensePostConstructed", silo = "missileSiloConstructed", sam = "samLauncherConstructed", warship = "warshipConstructed"})
Stats.GOLD = table.freeze({gold = "goldEarned", trade = "tradeGold", train = "trainGold", piracy = "piracyGold"})
Stats.RESULTS = table.freeze({Victory = true, Defeat = true, Left = true})

local function num(value: any): number
    return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end
local function int(value: any): number return math.max(0, math.floor(num(value))) end

function Stats.newRecord(): any
    local totals = {matches = 0, wins = 0, losses = 0, settled = 0, time = 0, longest = 0}
    for field in Stats.GOLD do totals[field] = 0 end
    for field in Stats.BUILDS do totals[field] = 0 end
    return {version = Stats.VERSION, totals = totals, maps = {}, peakLand = 0, mostGold = 0, history = {}, keys = {}}
end

-- A stored record, checked and normalised; nil when it isn't one of ours (never overwrite unknown data).
function Stats.validate(raw: any): any?
    if raw == nil then return Stats.newRecord() end
    if type(raw) ~= "table" or raw.version ~= Stats.VERSION or type(raw.totals) ~= "table" or type(raw.maps) ~= "table"
        or type(raw.history) ~= "table" or type(raw.keys) ~= "table" then return nil end
    local record = Stats.newRecord()
    for field in record.totals do record.totals[field] = int(raw.totals[field]) end
    for name, map in raw.maps do
        if type(name) == "string" and #name <= 64 and type(map) == "table" then
            record.maps[name] = {matches = int(map.matches), wins = int(map.wins), settled = int(map.settled), peak = math.clamp(num(map.peak), 0, 1)}
        end
    end
    record.peakLand, record.mostGold = math.clamp(num(raw.peakLand), 0, 1), int(raw.mostGold)
    for _, entry in raw.history do if type(entry) == "table" and type(entry.key) == "string" then table.insert(record.history, table.clone(entry)) end end
    while #record.history > Stats.HISTORY do table.remove(record.history) end
    for _, key in raw.keys do if type(key) == "string" and #key <= 128 then table.insert(record.keys, key) end end
    while #record.keys > Stats.KEYS do table.remove(record.keys, 1) end
    return record
end

-- One player's match, read from the live state at the grant moment.
-- info = {key, kind = "Public"|"Solo", result = "Victory"|"Defeat"|"Left", state, owner, facts (LevelFacts:facts), xp?, at}
function Stats.entry(info: any): any?
    local state, owner = info.state, info.owner
    if type(info.key) ~= "string" or #info.key == 0 or #info.key > 128 or type(state) ~= "table" or type(owner) ~= "number" then return nil end
    local facts = if type(info.facts) == "table" then info.facts else {}
    local peak = math.clamp(num(facts.peakLandPct) / 100, 0, 1)
    if peak <= 0 then return nil end -- never had land: not a match (as the Discord feed counts)
    local config = if type(state.gameConfig) == "table" then state.gameConfig else {}
    local format = if config.gameMode == "Team" then "Teams" else "Free-for-all"
    local entry: any = {key = info.key, at = int(info.at), map = tostring(config.gameMap or (state.map and state.map.mapType) or "Unknown"),
        mode = (if info.kind == "Public" then "Public" else "Solo") .. " · " .. format,
        result = if Stats.RESULTS[info.result] then info.result else "Left", dur = int(state.elapsed), peak = peak, xp = int(info.xp),
        tiles = int(peak * ((state.map and state.map.landCount) or 0))} -- the land taken (peak tiles): the weekly land board
    for field, source in Stats.GOLD do entry[field] = int(state[source] and state[source][owner]) end
    for field, source in Stats.BUILDS do entry[field] = int(state[source] and state[source][owner]) end
    return entry
end

-- Add one match. false when this match key is already in (a retry, a second grant path): nothing changes.
function Stats.apply(record: any, entry: any): boolean
    if type(entry) ~= "table" or type(entry.key) ~= "string" or table.find(record.keys, entry.key) then return false end
    table.insert(record.keys, entry.key)
    while #record.keys > Stats.KEYS do table.remove(record.keys, 1) end
    local t = record.totals
    local settled = entry.result == "Victory" or entry.result == "Defeat"
    t.matches += 1
    if entry.result == "Victory" then t.wins += 1 elseif entry.result == "Defeat" then t.losses += 1 end
    if settled then t.settled += 1 end
    t.time += int(entry.dur); t.longest = math.max(t.longest, int(entry.dur))
    for field in Stats.GOLD do t[field] += int(entry[field]) end
    for field in Stats.BUILDS do t[field] += int(entry[field]) end
    local map = record.maps[entry.map]
    if not map then map = {matches = 0, wins = 0, settled = 0, peak = 0}; record.maps[entry.map] = map end
    map.matches += 1; map.wins += if entry.result == "Victory" then 1 else 0; map.settled += if settled then 1 else 0
    map.peak = math.max(map.peak, num(entry.peak))
    record.peakLand = math.max(record.peakLand, num(entry.peak))
    record.mostGold = math.max(record.mostGold, int(entry.gold))
    table.insert(record.history, 1, table.clone(entry))
    while #record.history > Stats.HISTORY do table.remove(record.history) end
    return true
end

-- What the client gets (StatsCommand {kind="Stats", status, record}): a detached copy.
function Stats.view(record: any): any
    local maps = {}
    for name, map in record.maps do maps[name] = table.clone(map) end
    local history = {}
    for _, entry in record.history do table.insert(history, table.clone(entry)) end
    return {version = record.version, totals = table.clone(record.totals), maps = maps, peakLand = record.peakLand,
        mostGold = record.mostGold, history = history, keys = table.clone(record.keys)}
end

-- The UTC week (Monday 00:00), as LevelsService / DailyProfiles count it: the weekly boards' key.
function Stats.week(unix: number): number return (math.floor(num(unix) / 86400) + 3) // 7 end
Stats.BOARDS = table.freeze({wins = "OpenFrontLB_Wins_v1_w", land = "OpenFrontLB_Land_v1_w", level = "OpenFrontLB_Level_v1"})
return table.freeze(Stats)
