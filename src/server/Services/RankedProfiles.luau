--!strict
-- Ranked v2 (PF - 2): one player's ranked record, pure (RankedService stores it in OpenFrontRanked_v1 "u:<userId>").
-- Per mode: rating, games, wins, peak (this season). A new season soft-resets every mode (RankedRules.softReset) and
-- keeps the old season's best rank in `past` (the season reward follows it). A match lands once (its id in `applied`).
--   {v=1, season, modes={["1v1"|"2v2"|"FFA"]={rating, games, wins, peak}}, applied={matchId...}, last?, past={...}}
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Ranked = require(Shared.RankedRules)
local Profiles = {}
Profiles.VERSION = 1
Profiles.APPLIED = 20 -- recent match ids kept for idempotence
Profiles.PAST = 12    -- past seasons kept

local function count(v: any): number return if type(v) == "number" and v == v and v >= 0 and v < 1e12 then math.floor(v) else 0 end -- (timestamps too)
local function newMode(): any local r = Ranked.TUNING.start; return {rating = r, games = 0, wins = 0, peak = r} end
function Profiles.new(season: number): any
    local modes = {}; for _, mode in Ranked.MODES do modes[mode] = newMode() end
    return {v = Profiles.VERSION, season = season, modes = modes, applied = {}, past = {}}
end
-- A stored value -> a clean record, nil for data from a newer version (never overwritten), a new one for nothing.
function Profiles.validate(raw: any, season: number): any?
    if raw == nil then return Profiles.new(season) end
    if type(raw) ~= "table" or type(raw.v) ~= "number" then return Profiles.new(season) end
    if raw.v > Profiles.VERSION then return nil end
    local record = Profiles.new(if type(raw.season) == "number" and raw.season >= 1 then math.floor(raw.season) else season)
    for _, mode in Ranked.MODES do
        local m = type(raw.modes) == "table" and raw.modes[mode]
        if type(m) == "table" then
            local rating = if type(m.rating) == "number" and m.rating == m.rating then math.max(Ranked.TUNING.floor, math.floor(m.rating)) else Ranked.TUNING.start
            record.modes[mode] = {rating = rating, games = count(m.games), wins = count(m.wins), peak = math.max(rating, count(m.peak))}
        end
    end
    if type(raw.applied) == "table" then for _, id in raw.applied do if type(id) == "string" and #record.applied < Profiles.APPLIED then table.insert(record.applied, id) end end end
    if type(raw.past) == "table" then for _, p in raw.past do
        if type(p) == "table" and type(p.season) == "number" and type(p.tier) == "string" and #record.past < Profiles.PAST then
            table.insert(record.past, {season = p.season, tier = p.tier, division = if type(p.division) == "number" then p.division else nil, mode = p.mode})
        end
    end end
    if type(raw.last) == "table" and type(raw.last.mode) == "string" and type(raw.last.delta) == "number" then
        local l = raw.last
        record.last = {matchId = l.matchId, mode = l.mode, delta = l.delta, rating = count(l.rating), before = count(l.before), at = count(l.at), season = count(l.season)}
    end
    return record
end
-- The season's best rank across the modes (placement done: a mode counts after its placement games). nil: unranked.
function Profiles.best(record: any): any?
    local best, bestRank = nil, -1
    for _, mode in Ranked.MODES do
        local m = record.modes[mode]
        if m.games >= Ranked.TUNING.placementGames then
            local tier, division = Ranked.tier(m.rating)
            local rank = Ranked.rank(tier, division)
            if rank > bestRank then best, bestRank = {tier = tier, division = division, mode = mode}, rank end
        end
    end
    return best
end
-- Move the record to `season` (the current one). Returns whether it changed.
function Profiles.roll(record: any, season: number): boolean
    if record.season >= season then return false end
    local best = Profiles.best(record)
    if best then
        table.insert(record.past, 1, {season = record.season, tier = best.tier, division = best.division, mode = best.mode})
        while #record.past > Profiles.PAST do table.remove(record.past) end
    end
    local steps = math.min(3, season - record.season) -- a long absence settles toward the start, three halvings at most
    for _, mode in Ranked.MODES do
        local m = record.modes[mode]
        local rating = m.rating
        if m.games > 0 or rating ~= Ranked.TUNING.start then for _ = 1, steps do rating = Ranked.softReset(rating) end end
        record.modes[mode] = {rating = rating, games = 0, wins = 0, peak = rating}
    end
    record.season = season
    return true
end
-- One ranked result: entry = {matchId, mode, delta, won, at, season}. false: already counted (or a bad entry).
function Profiles.apply(record: any, entry: any): boolean
    if type(entry) ~= "table" or type(entry.matchId) ~= "string" or not record.modes[entry.mode] or type(entry.delta) ~= "number" then return false end
    if table.find(record.applied, entry.matchId) then return false end
    if type(entry.season) == "number" then Profiles.roll(record, entry.season) end
    local m = record.modes[entry.mode]
    local before = m.rating
    m.rating = Ranked.apply(m.rating, entry.delta)
    m.games += 1
    if entry.won then m.wins += 1 end
    m.peak = math.max(m.peak, m.rating)
    table.insert(record.applied, 1, entry.matchId)
    while #record.applied > Profiles.APPLIED do table.remove(record.applied) end
    record.last = {matchId = entry.matchId, mode = entry.mode, delta = m.rating - before, rating = m.rating, before = before,
        at = count(entry.at), season = record.season}
    return true
end
-- The Ranked tab's mode cards (PF - 3 contract: M = {rating, tier, division, games, wins, peak, placement, next}).
function Profiles.modeView(m: any): any
    local tier, division, nextStep = Ranked.tier(m.rating)
    local left = math.max(0, Ranked.TUNING.placementGames - m.games)
    -- MM: while placementsLeft > 0 the card shows "Placing n/5" instead of the tier (placement = the same number)
    return {rating = m.rating, tier = tier, division = division, games = m.games, wins = m.wins, peak = m.peak,
        placement = left, placementsLeft = left, placementGames = Ranked.TUNING.placementGames, next = nextStep,
        floor = Ranked.floor(m.rating)} -- PF - 3: the division's start, for the progress bar
end
function Profiles.view(record: any): any
    local modes = {}; for _, mode in Ranked.MODES do modes[mode] = Profiles.modeView(record.modes[mode]) end
    return modes
end
-- The last match card: promoted / demoted compare the tier+division before and after.
function Profiles.lastView(record: any): any?
    local l = record.last
    if not l then return nil end
    local tier, division = Ranked.tier(l.rating)
    local beforeTier, beforeDivision = Ranked.tier(l.before)
    local now, was = Ranked.rank(tier, division), Ranked.rank(beforeTier, beforeDivision)
    return {mode = l.mode, delta = l.delta, rating = l.rating, tier = tier, division = division, promoted = now > was, demoted = now < was,
        matchId = l.matchId, at = l.at}
end
-- A finished ranked match -> each player's change. ranked = the match record's {mode, players = {[uid] = {rating, games,
-- team}}} (the ratings when it was made); results = {[uid] = {result = "Victory"|"Defeat"|"Left", order, rank?}} from the
-- XP-grant moments (order = when it came; a missing player left). Leaving = a loss / the last place.
-- Returns {[uid] = {delta, won, place?}}, or nil when nobody won (a 1v1/2v2 with no winner: no change).
function Profiles.outcome(ranked: any, results: any): {[string]: any}?
    local out = {}
    local function result(uid: string): any return results[uid] or {result = "Left", order = math.huge} end
    if ranked.mode == "FFA" then
        local list = {}
        for uid, p in ranked.players do local r = result(uid); table.insert(list, {uid = uid, p = p, r = r}) end
        -- the winner first; then the eliminated, later out = better (ties: the end-of-match land rank); leavers share the last place
        local function key(e: any): number return if e.r.result == "Victory" then 0 elseif e.r.result == "Defeat" then 1 else 2 end
        table.sort(list, function(a, b)
            local ka, kb = key(a), key(b)
            if ka ~= kb then return ka < kb end
            if ka == 1 then
                if a.r.order ~= b.r.order then return a.r.order > b.r.order end
                local ra, rb = a.r.rank or math.huge, b.r.rank or math.huge
                if ra ~= rb then return ra < rb end
            end
            return a.uid < b.uid
        end)
        local players, place = {}, 0
        for i, e in list do
            place = if key(e) == 2 then (place + (if i > 1 and key(list[i - 1]) == 2 then 0 else 1)) else i
            table.insert(players, {userId = e.uid, rating = e.p.rating, games = e.p.games, place = place})
        end
        local deltas = Ranked.ffaDeltas(players)
        for _, p in players do out[p.userId] = {delta = deltas[p.userId], won = p.place == 1, place = p.place} end
        return out
    end
    -- 1v1 / 2v2: the team with a Victory wins
    local teams, winner = {}, nil
    for uid, p in ranked.players do
        local t = p.team or 1
        teams[t] = teams[t] or {}
        table.insert(teams[t], {userId = uid, rating = p.rating, games = p.games})
        if result(uid).result == "Victory" then winner = t end
    end
    if winner == nil or #teams ~= 2 then return nil end
    local loser = 3 - winner
    local win, lose = Ranked.teamDeltas(teams, winner), Ranked.teamDeltas(teams, loser)
    for uid in ranked.players do
        local onWinner = (ranked.players[uid].team or 1) == winner
        local left = result(uid).result == "Left"
        if onWinner and not left then out[uid] = {delta = win[uid], won = true}
        else out[uid] = {delta = if onWinner then lose[uid] else win[uid], won = false} end -- a winning team's leaver takes the loss
    end
    return out
end
return table.freeze(Profiles)
