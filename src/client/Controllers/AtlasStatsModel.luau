--!strict
-- Atlas statistics: this client connection's matches, plus (PF036) the lifetime record PF - 2's StatsService sends
-- (setLifetime). No storage or command writes here.
-- Feed only accepted, decoded viewer snapshots: the transport remaps the local player to 1.
local Model = {}
Model.__index = Model

local MAPS = {
    { id = "UnitedStates", name = "United States", role = "Inland industry" },
    { id = "Africa", name = "Africa", role = "Coastal trade" },
    { id = "QingChina", name = "Qing China", role = "Connected fronts" },
}
local COUNTERS = {
    "goldEarned", "tradeGold", "trainGold", "piracyGold", "cityConstructed",
    "portConstructed", "factoryConstructed", "defensePostConstructed",
    "missileSiloConstructed", "samLauncherConstructed", "warshipConstructed",
}
local BUILDINGS = { "cityConstructed", "portConstructed", "factoryConstructed",
    "defensePostConstructed", "missileSiloConstructed", "samLauncherConstructed" }
-- Stats v2 (PF - 3, 2026-10-26): the Built strip's counts by building kind
local BUILT_KINDS = { City = "cityConstructed", Port = "portConstructed", Factory = "factoryConstructed",
    DefensePost = "defensePostConstructed", MissileSilo = "missileSiloConstructed", SAMLauncher = "samLauncherConstructed" }
local function builtFrom(totals: {[string]: number}): {[string]: number}
    local out = {}
    for kind, key in BUILT_KINDS do out[kind] = totals[key] or 0 end
    return out
end

local function finite(value: any): number?
    if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return nil end
    return value
end
local function owned(values: any): number?
    return if type(values) == "table" then finite(values[1]) else nil
end
local function maximum(a: number?, b: number?): number?
    if b == nil then return a end
    return if a == nil then b else math.max(a, b)
end
local function mapInfo(state: any): (string, string)
    local config = state.gameConfig
    local name = if type(config) == "table" then config.gameMap else state.mapType
    name = name or state.mapType
    for _, map in MAPS do
        if name == map.name or name == map.id then return map.id, map.name end
    end
    return "Unknown", "Unknown map"
end
local function fleetCount(state: any): number?
    if type(state.ships) ~= "table" or type(state.warships) ~= "table" or type(state.tradeShips) ~= "table" then return nil end
    local count = 0
    for _, list in { state.ships, state.warships, state.tradeShips } do
        for _, unit in list do
            if unit.owner == 1 and unit.active ~= false then count += 1 end
        end
    end
    return count
end
local function sumFields(values: any, keys: {string}): number?
    local total = 0
    for _, key in keys do
        if values[key] == nil then return nil end
        total += values[key]
    end
    return total
end

function Model.formatNumber(value: number?): string
    if value == nil then return "—" end
    if value >= 1000000000 then return string.format("%.2fB", value / 1000000000) end
    if value >= 1000000 then return string.format("%.2fM", value / 1000000) end
    if value >= 10000 then return string.format("%.1fK", value / 1000) end
    return tostring(math.floor(value + 0.5))
end
function Model.formatDuration(value: number?): string
    if value == nil then return "—" end
    local seconds = math.floor(value)
    if seconds >= 3600 then return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds / 60) % 60) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
function Model.formatPercent(value: number?): string
    return if value == nil then "—" else string.format("%.1f%%", value * 100)
end

function Model.new(): any
    return setmetatable({ records = {}, order = {}, activeId = nil, latestMatchId = -1, version = 0 }, Model)
end

function Model.observe(self: any, packet: any): boolean
    if type(packet) ~= "table" or type(packet.state) ~= "table" or packet.tutorialMatch == true then return false end
    local id, revision = finite(packet.matchId), finite(packet.revision)
    if id == nil or revision == nil or id < self.latestMatchId then return false end
    local state = packet.state
    -- Local-owner omission is valid for decoded legacy snapshots. Never read a different owner.
    if state.localOwner ~= nil and state.localOwner ~= 1 then return false end
    if type(state.players) ~= "table" or type(state.players[1]) ~= "table" then return false end
    local record: any = self.records[id]
    if record and (record.closed or revision <= record.revision) then return false end
    if not record then
        if self.activeId ~= nil then self:leave(self.activeId) end
        local mapId, mapName = mapInfo(state)
        local config = state.gameConfig or {}
        local format = if config.gameMode == "Team" then "Teams" elseif config.gameMode == "Free For All" then "Free-for-all" else "Format unavailable"
        record = { id = id, sequence = #self.order + 1, revision = -1, mapId = mapId, mapName = mapName,
            mode = (if packet.online == true then "Public" else "Solo") .. " · " ..
                format,
            counters = {}, duration = nil, peakLand = nil, peakFleet = nil, result = "In progress", closed = false }
        self.records[id] = record
        table.insert(self.order, id)
        self.activeId = id
    end
    self.latestMatchId = id
    record.revision = revision
    record.duration = finite(state.elapsed) or record.duration
    for _, field in COUNTERS do
        -- These are cumulative match values, not deltas. Repeated full/delta packets cannot double count.
        record.counters[field] = owned(state[field])
    end
    local land = finite(state.landCount) or (if type(state.map) == "table" then finite(state.map.landCount) else nil)
    local tiles = owned(state.counts)
    if land and land > 0 and tiles then
        -- Original map land is stable. Fallout does not make the percentage grow by shrinking its denominator.
        record.peakLand = maximum(record.peakLand, math.clamp(tiles / land, 0, 1))
    end
    record.peakFleet = maximum(record.peakFleet, fleetCount(state))
    -- PF023 L3: the match's XP breakdown arrives once, on the packet that ends it (PF - 2's packet.xpResult).
    local xpResult = packet.xpResult
    if type(xpResult) == "table" and finite(xpResult.total) then record.xp = xpResult.total; record.matchKey = xpResult.matchKey end
    if state.winner ~= nil or state.winnerTeam ~= nil then
        local won = state.winner == 1 or (state.winnerTeam ~= nil and state.players[1].team == state.winnerTeam)
        record.result = if won then "Victory" else "Defeat"
    elseif state.phase == "Won" then record.result = "Victory"
    elseif state.phase == "Lost" then
        -- An eliminated team member can still win later. Lost alone is not a final team result.
        record.result = if state.winner ~= nil or state.winnerTeam ~= nil then "Defeat" else "Eliminated"
    elseif state.phase == "Cancelled" then record.result = "Cancelled"
    end
    -- Keep observing until Home/new match. Keep Playing can legitimately add counters after the win.
    self.version += 1
    return true
end

function Model.leave(self: any, matchId: any): boolean
    local record = self.records[matchId]
    if not record or record.closed then return false end
    if record.result == "In progress" then record.result = "Left" end
    record.closed = true
    if self.activeId == matchId then self.activeId = nil end
    self.version += 1
    return true
end

-- The five stat groups from the summed counters (the session's, or the lifetime record's plus the session's).
local function groupsFor(totals: {[string]: number}, count: number, mostGold: number?, peakLand: number?, peakFleet: number?): {any}
    local function row(label: string, value: number?): any return { label = label, value = Model.formatNumber(value) } end
    return {
        { id = "Combat", lead = "—", label = "Troops committed", rows = {
            row("Troops lost", nil), row("Attacks launched", nil), row("Players eliminated", nil),
            row("Nations defeated", nil), row("Tribes defeated", nil) } },
        { id = "Economy", lead = Model.formatNumber(totals.goldEarned), label = "Gold earned", rows = {
            row("Gold spent", nil), row("Gold from ships", totals.tradeGold), row("Gold from trains", totals.trainGold),
            row("Most gold / match", mostGold), { label = "Peak land observed", value = Model.formatPercent(peakLand) } } },
        { id = "Construction", lead = Model.formatNumber(if count > 0 then sumFields(totals, BUILDINGS) else nil), label = "Builds & upgrades ordered", rows = {
            row("City orders", totals.cityConstructed), row("Factory orders", totals.factoryConstructed), row("Port orders", totals.portConstructed),
            row("Defense post orders", totals.defensePostConstructed), { label = "Silo / SAM orders",
                value = Model.formatNumber(totals.missileSiloConstructed) .. " / " .. Model.formatNumber(totals.samLauncherConstructed) } } },
        { id = "Naval", lead = Model.formatNumber(totals.warshipConstructed), label = "Warships commissioned", rows = {
            row("Trade voyages", nil), row("Warships destroyed", nil), row("Transport launches", nil),
            row("Piracy gold", totals.piracyGold), row("Peak fleet observed", peakFleet) } },
        { id = "Nuclear", lead = "—", label = "Missiles launched", rows = {
            row("Atom bombs", nil), row("Hydrogen bombs", nil), row("MIRVs", nil), row("Missiles intercepted", nil),
            row("Silo orders", totals.missileSiloConstructed) } },
    }
end

-- This connection's matches. skip (PF036): match keys the lifetime record already holds (a match played here lands in
-- both once its write does; PF - 2's de-dupe rule).
local function sessionView(self: any, skip: {[string]: boolean}?): any
    local count, wins, losses, settled = 0, 0, 0, 0
    local longest: number? = nil
    local totals: {[string]: number} = {}
    local missing: {[string]: boolean} = {}
    local history, recent = {}, {}
    local mapRecords: {[string]: any} = {}
    local peakLand: number? = nil
    local peakFleet: number? = nil
    local mostGold: number? = nil
    local totalDuration: number? = 0
    for _, map in MAPS do
        mapRecords[map.id] = { id = map.id, name = map.name, role = map.role, matches = 0, wins = 0, settled = 0, peakLand = nil }
    end
    for i = #self.order, 1, -1 do
        local record = self.records[self.order[i]]
        if skip and record.matchKey ~= nil and skip[tostring(record.matchKey)] then continue end
        count += 1
        local terminal = record.result == "Victory" or record.result == "Defeat"
        if terminal then
            settled += 1
            if record.result == "Victory" then wins += 1 else losses += 1 end
            if #recent < 10 then table.insert(recent, record.result) end
        end
        longest = maximum(longest, record.duration)
        if record.duration == nil then totalDuration = nil
        elseif totalDuration ~= nil then totalDuration += record.duration end
        peakLand = maximum(peakLand, record.peakLand)
        peakFleet = maximum(peakFleet, record.peakFleet)
        mostGold = maximum(mostGold, record.counters.goldEarned)
        for _, key in COUNTERS do
            local value = record.counters[key]
            if value == nil then missing[key] = true else totals[key] = (totals[key] or 0) + value end
        end
        local map = mapRecords[record.mapId]
        if map then
            map.matches += 1
            map.wins += if record.result == "Victory" then 1 else 0
            map.settled += if terminal then 1 else 0
            map.peakLand = maximum(map.peakLand, record.peakLand)
        end
        if #history < 50 then
            table.insert(history, { id = record.id, mapName = record.mapName, mode = record.mode, result = record.result, xp = record.xp, matchKey = record.matchKey, -- PF023 L3
                duration = record.duration, peakLand = record.peakLand, goldEarned = record.counters.goldEarned,
                played = "Match " .. tostring(record.sequence) .. " · This session" })
        end
    end
    local raw = table.clone(totals) -- PF036: the session's sums before missing counters drop out (lifetime adds them)
    for key in missing do totals[key] = nil end
    local maps = {}
    for _, map in MAPS do
        local record = mapRecords[map.id]
        record.rate = if record.settled > 0 then record.wins / record.settled else nil
        table.insert(maps, record)
    end
    return {
        version = self.version, status = if count == 0 then "empty" else "ready", scope = "This session",
        notice = "This connection only · No lifetime archive. — means unavailable. Peaks are observed snapshots.",
        summary = { matches = count, wins = wins, losses = losses, settled = settled,
            rate = if settled > 0 then wins / settled else nil, longest = longest, duration = totalDuration },
        maps = maps, recent = recent, history = history, historyTotal = count,
        groups = groupsFor(totals, count, mostGold, peakLand, peakFleet),
        built = builtFrom(raw), peakLand = peakLand,
        raw = { totals = raw, mostGold = mostGold, peakLand = peakLand, peakFleet = peakFleet, mapRecords = mapRecords },
    }
end

-- PF036 lifetime (PF - 2's OpenFrontStats_v1 through StatsCommand): {kind="Stats", status="ready"|"unavailable", record=view}.
-- record: totals {matches, wins, losses, settled, time, longest, gold, trade, train, piracy, city, port, factory, post, silo,
-- sam, warship}, maps {[name] = {matches, wins, settled, peak}}, peakLand, mostGold, history (newest 20), keys (last 100).
function Model.setLifetime(self: any, packet: any): boolean
    if type(packet) ~= "table" or packet.kind ~= "Stats" then return false end
    if packet.status == "ready" and type(packet.record) == "table" and type(packet.record.totals) == "table" then self.lifetime = packet.record
    elseif self.lifetime == nil then self.lifetimeFailed = packet.status == "unavailable" end
    self.version += 1
    return true
end
local LIFE_COUNTERS = { goldEarned = "gold", tradeGold = "trade", trainGold = "train", piracyGold = "piracy", cityConstructed = "city",
    portConstructed = "port", factoryConstructed = "factory", defensePostConstructed = "post", missileSiloConstructed = "silo",
    samLauncherConstructed = "sam", warshipConstructed = "warship" }
local function day(at: number): string
    local today = os.time() // 86400
    local d = math.floor(at) // 86400
    if d == today then return "Today" elseif d == today - 1 then return "Yesterday" end
    return os.date("!%d %b", math.floor(at)) :: string
end

function Model.view(self: any): any
    local life = self.lifetime
    if not life then return sessionView(self, nil) end
    local skip: {[string]: boolean} = {}
    for _, key in life.keys or {} do skip[tostring(key)] = true end
    local s = sessionView(self, skip) -- this connection's matches the record doesn't hold yet
    local t = life.totals
    local function n(value: any): number return finite(value) or 0 end
    local sum = s.summary
    local matches, wins, losses, settled = n(t.matches) + sum.matches, n(t.wins) + sum.wins, n(t.losses) + sum.losses, n(t.settled) + sum.settled
    -- the latest decided results: this session's first (newest), then the record's history
    local recent = table.clone(s.recent)
    for _, entry in life.history or {} do
        if #recent >= 10 then break end
        if entry.result == "Victory" or entry.result == "Defeat" then table.insert(recent, entry.result) end
    end
    local maps = {}
    for _, map in MAPS do
        local L = (life.maps or {})[map.name] or {}
        local S = s.raw.mapRecords[map.id]
        local record = { id = map.id, name = map.name, role = map.role, matches = n(L.matches) + S.matches, wins = n(L.wins) + S.wins,
            settled = n(L.settled) + S.settled, peakLand = maximum(finite(L.peak), S.peakLand) }
        record.rate = if record.settled > 0 then record.wins / record.settled else nil
        table.insert(maps, record)
    end
    local totals: {[string]: number} = {}
    for key, field in LIFE_COUNTERS do totals[key] = n(t[field]) + (s.raw.totals[key] or 0) end
    local history = table.clone(s.history)
    for _, entry in life.history or {} do
        if #history >= 50 then break end
        table.insert(history, { id = entry.key, mapName = tostring(entry.map or "Unknown map"), mode = tostring(entry.mode or ""), result = tostring(entry.result or ""),
            xp = finite(entry.xp), matchKey = entry.key, duration = finite(entry.dur), peakLand = finite(entry.peak), goldEarned = finite(entry.gold),
            played = if type(entry.at) == "number" then day(entry.at) else "" })
    end
    return {
        version = self.version, status = if matches == 0 then "empty" else "ready", scope = "Lifetime", lifetime = true,
        notice = "",
        summary = { matches = matches, wins = wins, losses = losses, settled = settled, rate = if settled > 0 then wins / settled else nil,
            longest = maximum(finite(t.longest), sum.longest), duration = n(t.time) + (sum.duration or 0) },
        maps = maps, recent = recent, history = history, historyTotal = matches,
        groups = groupsFor(totals, matches, maximum(finite(life.mostGold), s.raw.mostGold), maximum(finite(life.peakLand), s.raw.peakLand), s.raw.peakFleet),
        built = builtFrom(totals), peakLand = maximum(finite(life.peakLand), s.raw.peakLand),
    }
end

Model.Maps = MAPS
return Model
