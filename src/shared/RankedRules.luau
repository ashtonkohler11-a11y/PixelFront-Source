--!strict
-- Ranked v2 (Ashton approved docs/director/mockups/PF036/08-ranked-v2.png; PF - 2 server, PF - 3 UI). Pure rules shared by
-- the server and the Ranked tab: per-mode Elo (1v1, 2v2, FFA by finishing place), tiers Bronze..Diamond (each III < II <
-- I, 100-point divisions) then Master, the matchmaking window and grouping, the rotation map and 4-week seasons.
-- Every number lives in Ranked.TUNING (the proposal MM approves), so a change is one line.
local Ranked = {}
Ranked.MODES = table.freeze({"1v1", "2v2", "FFA"})
Ranked.TUNING = table.freeze({
    start = 1000,            -- a new rating (Silver III)
    placementGames = 5,      -- the first games of a season move faster
    kPlacement = 64, k = 32, -- 1v1 / 2v2
    kFFA = 64,               -- FFA: Δ = kFFA × Σ(score − expected) / (N − 1)
    floor = 0,
    window = {start = 100, step = 50, every = 10, max = 600, anyAfter = 120}, -- ± rating, widening; past anyAfter: anyone
    ffa = {full = 16, after = {{60, 8}, {120, 4}}},                         -- FFA starts full, or with fewer after a wait
    seasonDays = 28, seasonEpochDay = 20740,                                 -- 2026-10-14 (a Wednesday) = the start of season 1 (launch; MM)
    unlockMatches = 25,      -- PIVOT D15 (Levels removed; Ashton 2026-10-23): Ranked opens after 25 matches played (was level 10)
    rotationSeconds = 600,
    -- MM (2026-10-16): FFA under ffaFullAt humans plays the map's Compact variant, 12+ the full map. The place ships Compact
    -- maps only (2026-10-01 policy; Availability.supports refuses Normal), so ffaFullSize stays "Compact" until Normal
    -- assets are imported (Ashton's call); then it is this one line.
    ffaFullAt = 12, ffaFullSize = "Compact",
    tribes = 50,             -- Availability.MaxTribes; nations off in every ranked match
})
-- the ladder: each tier's floor; divisions every 100 (III, II, I). Bronze holds everything under 1000.
Ranked.TIERS = table.freeze({{name = "Bronze", from = 700}, {name = "Silver", from = 1000}, {name = "Gold", from = 1300},
    {name = "Platinum", from = 1600}, {name = "Diamond", from = 1900}, {name = "Master", from = 2200}})
Ranked.MAPS = table.freeze({"Africa", "United States", "Qing China"})

local function num(v: any): number return if type(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0 end
-- rating -> tier, division (1 = I the top, 3 = III; nil for Master), and the next step {tier, division, at} (nil at Master)
function Ranked.tier(rating: number): (string, number?, any?)
    local r = math.floor(num(rating))
    local index = 1
    for i, t in Ranked.TIERS do if r >= t.from then index = i end end
    local t = Ranked.TIERS[index]
    if t.name == "Master" then return "Master", nil, nil end
    local base = if index == 1 then t.from else t.from -- Bronze III also holds everything under 800
    local step = math.clamp(math.floor((r - base) / 100), 0, 2) -- 0 = III, 1 = II, 2 = I
    if index == 1 and r < base then step = 0 end
    local division = 3 - step
    local nextAt = base + (step + 1) * 100
    local nextTier, nextDivision = t.name, division - 1
    if division == 1 then nextTier, nextDivision = Ranked.TIERS[index + 1].name, if Ranked.TIERS[index + 1].name == "Master" then nil else 3 end
    return t.name, division, {tier = nextTier, division = nextDivision, at = nextAt}
end
-- the rating the current division starts at (the progress bar: (rating - floor) / (next.at - floor)); Bronze III starts at
-- the rating floor, Master at 2200
function Ranked.floor(rating: number): number
    local tier, _, nextStep = Ranked.tier(rating)
    if tier == "Master" then return Ranked.TIERS[#Ranked.TIERS].from end
    local at = nextStep.at - 100
    return if tier == "Bronze" and at <= Ranked.TIERS[1].from then Ranked.TUNING.floor else at
end
-- Season rewards (Ashton's table): one slot per tier, granted from a season's best rank (RankedProfiles past). Empty =
-- nothing yet. A slot takes e.g. {cobalt = 500, item = "frame_gold_s1"} once the table is decided.
Ranked.SEASON_REWARDS = {Bronze = {}, Silver = {}, Gold = {}, Platinum = {}, Diamond = {}, Master = {}}
function Ranked.rank(tierName: string, division: number?): number -- a sortable rank (the best rank across modes)
    for i, t in Ranked.TIERS do if t.name == tierName then return i * 10 + (if division then 4 - division else 4) end end
    return 0
end
function Ranked.expected(rating: number, opponent: number): number return 1 / (1 + 10 ^ ((opponent - rating) / 400)) end
local function k(games: number): number return if games < Ranked.TUNING.placementGames then Ranked.TUNING.kPlacement else Ranked.TUNING.k end
-- 1v1 / 2v2: teams = {{ {userId, rating, games}... }, ...} with winner = the winning team's index. Team rating = the mean.
-- Returns {[userId] = delta}.
function Ranked.teamDeltas(teams: {any}, winner: number): {[number]: number}
    local means = {}
    for i, team in teams do local sum = 0; for _, p in team do sum += num(p.rating) end; means[i] = sum / math.max(1, #team) end
    local out = {}
    for i, team in teams do
        local opponents, n = 0, 0
        for j, mean in means do if j ~= i then opponents += mean; n += 1 end end
        local e = Ranked.expected(means[i], opponents / math.max(1, n))
        local score = if i == winner then 1 else 0
        for _, p in team do out[p.userId] = math.floor(k(num(p.games)) * (score - e) + 0.5) end
    end
    return out
end
-- FFA: players = {{userId, rating, games, place}} (1 = the winner; leavers share the last place). Pairwise by place.
function Ranked.ffaDeltas(players: {any}): {[number]: number}
    local out, n = {}, #players
    for _, a in players do
        local sum = 0
        for _, b in players do
            if a ~= b then
                local score = if num(a.place) < num(b.place) then 1 elseif num(a.place) == num(b.place) then 0.5 else 0
                sum += score - Ranked.expected(num(a.rating), num(b.rating))
            end
        end
        local kf = if num(a.games) < Ranked.TUNING.placementGames then Ranked.TUNING.kFFA * 1.5 else Ranked.TUNING.kFFA
        out[a.userId] = math.floor(kf * sum / math.max(1, n - 1) + 0.5)
    end
    return out
end
function Ranked.apply(rating: number, delta: number): number return math.max(Ranked.TUNING.floor, math.floor(num(rating) + delta)) end

-- the matchmaking window (± rating) after waiting `seconds`; math.huge past anyAfter (a small population)
function Ranked.window(seconds: number): number
    local w = Ranked.TUNING.window
    if seconds >= w.anyAfter then return math.huge end
    return math.min(w.max, w.start + math.floor(math.max(0, seconds) / w.every) * w.step)
end
-- The queue -> matches. tickets = {{id, mode, members = {userIds}, rating, since}}; now = unix seconds.
-- 1v1: two singles whose windows both cover the gap. 2v2: two teams (a party of 2, or two singles paired). FFA: up to 16
-- within the oldest ticket's window, starting full or after the low-population waits. Oldest tickets first; deterministic.
function Ranked.match(tickets: {any}, now: number): {any}
    local byMode: {[string]: {any}} = {["1v1"] = {}, ["2v2"] = {}, FFA = {}}
    for _, t in tickets do if byMode[t.mode] and type(t.members) == "table" and #t.members > 0 then table.insert(byMode[t.mode], t) end end
    for _, list in byMode do table.sort(list, function(a, b) return if a.since == b.since then tostring(a.id) < tostring(b.id) else a.since < b.since end) end
    local matches, used = {}, {}
    local function fits(a: any, b: any): boolean
        local gap = math.abs(num(a.rating) - num(b.rating))
        return gap <= Ranked.window(now - a.since) and gap <= Ranked.window(now - b.since)
    end
    -- 1v1
    for i, a in byMode["1v1"] do
        if used[a] or #a.members ~= 1 then continue end
        for j = i + 1, #byMode["1v1"] do
            local b = byMode["1v1"][j]
            if not used[b] and #b.members == 1 and fits(a, b) then used[a], used[b] = true, true; table.insert(matches, {mode = "1v1", teams = {{a}, {b}}}); break end
        end
    end
    -- 2v2: first make teams (parties of 2 are teams; singles pair up by rating), then pair teams
    local teams = {}
    local singles = {}
    for _, t in byMode["2v2"] do if #t.members == 2 then table.insert(teams, {tickets = {t}, rating = num(t.rating), since = t.since}) elseif #t.members == 1 then table.insert(singles, t) end end
    local paired = {}
    for i, a in singles do
        if paired[a] then continue end
        for j = i + 1, #singles do
            local b = singles[j]
            if not paired[b] and fits(a, b) then paired[a], paired[b] = true, true
                table.insert(teams, {tickets = {a, b}, rating = (num(a.rating) + num(b.rating)) / 2, since = math.min(a.since, b.since)}); break end
        end
    end
    table.sort(teams, function(a, b) return a.since < b.since end)
    local teamUsed = {}
    for i, a in teams do
        if teamUsed[a] then continue end
        for j = i + 1, #teams do
            local b = teams[j]
            if not teamUsed[b] and fits(a, b) then
                teamUsed[a], teamUsed[b] = true, true
                for _, t in a.tickets do used[t] = true end; for _, t in b.tickets do used[t] = true end
                table.insert(matches, {mode = "2v2", teams = {a.tickets, b.tickets}}); break
            end
        end
    end
    -- FFA
    local ffa = byMode.FFA
    local i = 1
    while i <= #ffa do
        local anchor = ffa[i]
        if used[anchor] then i += 1; continue end
        local group = {anchor}
        for j = i + 1, #ffa do
            local b = ffa[j]
            if not used[b] and #group < Ranked.TUNING.ffa.full and fits(anchor, b) then table.insert(group, b) end
        end
        local waited, need = now - anchor.since, Ranked.TUNING.ffa.full
        for _, step in Ranked.TUNING.ffa.after do if waited >= step[1] then need = step[2] end end
        if #group >= need then
            for _, t in group do used[t] = true end
            local list = {}; for _, t in group do table.insert(list, {t}) end
            table.insert(matches, {mode = "FFA", teams = list})
        end
        i += 1
    end
    return matches
end
-- the season (4 weeks, UTC): id and its end (unix)
function Ranked.season(unix: number): (number, number)
    local day = math.floor(num(unix) / 86400)
    local id = math.max(1, (day - Ranked.TUNING.seasonEpochDay) // Ranked.TUNING.seasonDays + 1)
    local endsAt = (Ranked.TUNING.seasonEpochDay + id * Ranked.TUNING.seasonDays) * 86400
    return id, endsAt
end
-- the next season's soft reset
function Ranked.softReset(rating: number): number return math.floor(Ranked.TUNING.start + (num(rating) - Ranked.TUNING.start) / 2) end
-- the match's map size: 1v1 / 2v2 Compact; FFA Compact under ffaFullAt humans, else ffaFullSize
function Ranked.mapSize(mode: string, players: number?): string
    if mode == "FFA" and (players or 0) >= Ranked.TUNING.ffaFullAt then return Ranked.TUNING.ffaFullSize end
    return "Compact"
end
-- when the current rotation map changes (unix)
function Ranked.rotationEndsAt(unix: number): number
    return (math.floor(num(unix) / Ranked.TUNING.rotationSeconds) + 1) * Ranked.TUNING.rotationSeconds
end
-- the mode's rotation map right now (the same on every server) and its size for `players` (nil: the small size)
function Ranked.rotation(mode: string, unix: number, players: number?): (string, string)
    local size = Ranked.mapSize(mode, players)
    local maps = Ranked.MAPS
    return maps[(math.floor(num(unix) / Ranked.TUNING.rotationSeconds) % #maps) + 1], size
end
-- The match config (PublicGameConfig.validate + Availability.supports pass it): 1v1 = FFA of 2 that ends when one human
-- is left; 2v2 = 2 teams of 2 (cancelled if anyone never spawns); FFA = up to 16. Nations off, tribes on, no modifiers.
function Ranked.config(mode: string, map: string, size: string, players: number): any
    local teams = mode == "2v2"
    local config = {gameType = "Public", gameMode = if teams then "Team" else "Free For All", gameMap = map, gameMapSize = size,
        maxPlayers = players, playerTeams = 2, publicGameModifiers = {isCompact = if size == "Compact" then true else nil}, difficulty = "Medium",
        donateGold = teams, donateTroops = teams, infiniteGold = false, infiniteTroops = false, instantBuild = false, randomSpawn = false,
        nations = "disabled", bots = Ranked.TUNING.tribes, spawnImmunityDuration = 50, disabledUnits = {},
        disableClanTags = if teams then nil else true, rankedType = if mode == "FFA" then nil else mode}
    if mode == "FFA" then config.overtime = {enabled = true, startMinutes = 30} end
    return config
end
return table.freeze(Ranked)
