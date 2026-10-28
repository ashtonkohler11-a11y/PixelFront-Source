--!strict
-- Stats v3 (PF - 2; docs/director/STATS-SYSTEM-DESIGN-2026-10-27.md §v3.1 + the §v3.11 data contract A; Ashton "Build it"
-- 2026-10-27): the per-player record behind the hidden Solo skill, the dealer's band and the private website. Pure:
-- PlayerProfileService owns the DataStore (OpenFrontPlayer_v1 "u:<userId>"). One match fold per player per match
-- (idempotent on the match key), one session fold per server leave, and the client's clamped UI report. Skill (r, form,
-- band) never leaves the server: no client packet carries this record.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local P = {}
P.VERSION = 1
P.HISTORY = 20
P.SESSIONS = 10
P.KEYS = 40
P.SESSION_GAP = 300 -- a join within 5 min of the last leave continues the session (teleports between our servers)
P.DIFFICULTIES = table.freeze({ "Easy", "Medium", "Hard", "Impossible" })
P.NEXT = table.freeze({ Easy = "Medium", Medium = "Hard", Hard = "Impossible" })
-- PF - 1's StatsReport names (surfaces opened; where a product was shown)
P.SCREENS = table.freeze({ Shop = true, Armory = true, Inventory = true, Stats = true, Settings = true, HowToPlay = true, Party = true,
    Leaderboard = true, Daily = true, Build = true })
P.PLACEMENTS = table.freeze({ home = true, armory = true, shop = true, ["end"] = true, match = true, revive = true })
P.COUNTERS = table.freeze({ "matches", "solo", "public", "ranked", "wins", "losses", "left", "minutes", "attacks", "attacksWon",
    "attacksLost", "sendsKept", "nations", "tribes", "players", "built", "city", "port", "factory", "post", "silo", "sam", "warship",
    "captured", "capturedOpening", "comebacks", "revives", "takeovers", "gold", "tradeGold", "trainGold", "piracyGold", "sessions",
    "sessionMinutes", "nextSeen", "nextTapped", "nextWon", "hintShown", "dealt" })
-- the sim's per-owner build counters (StatsProfiles.BUILDS) -> our counter names
P.BUILDS = table.freeze({ city = "cityConstructed", port = "portConstructed", factory = "factoryConstructed", post = "defensePostConstructed",
    silo = "missileSiloConstructed", sam = "samLauncherConstructed", warship = "warshipConstructed" })
P.GOLD = table.freeze({ gold = "goldEarned", tradeGold = "tradeGold", trainGold = "trainGold", piracyGold = "piracyGold" })

local function num(value: any): number
    return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end
local function int(value: any): number return math.max(0, math.floor(num(value))) end
local function clamp01(value: any): number return math.clamp(num(value), 0, 1) end
local function str(value: any, max: number): string? return if type(value) == "string" and #value > 0 and #value <= max then value else nil end

-- userId even -> "A" (gets the dealer when Config.Dealer.Enabled), odd -> "B"
function P.cohort(userId: number): string return if int(userId) % 2 == 0 then "A" else "B" end
function P.day(unix: number): string return os.date("!%Y-%m-%d", int(unix)) :: string end

function P.newRecord(userId: number): any
    local c = {}
    for _, name in P.COUNTERS do c[name] = 0 end
    local d = {}
    for _, name in P.DIFFICULTIES do d[name] = { m = 0, w = 0, l = 0, x = 0 } end
    local start = Config.Skill.Rating.Start
    return { v = P.VERSION, at = 0, co = P.cohort(userId),
        sk = { r = start, form = 0.5, band = "Flow", n = 0, ws = 0, ls = 0, best = 0 },
        c = c, d = d, mp = {}, h = {}, ss = {}, f = { joined = 0, days = 0, opening = false, fsMin = 0 }, ui = {}, rb = {}, keys = {} }
end

-- A stored record, checked and normalised; nil when it isn't ours or is newer (never overwrite data we don't understand).
function P.validate(raw: any, userId: number): any?
    if raw == nil then return P.newRecord(userId) end
    if type(raw) ~= "table" or raw.v ~= P.VERSION then return nil end
    local record = P.newRecord(userId)
    record.at = int(raw.at)
    if raw.co == "A" or raw.co == "B" then record.co = raw.co end
    local sk = if type(raw.sk) == "table" then raw.sk else {}
    record.sk = { r = if type(sk.r) == "number" then num(sk.r) else Config.Skill.Rating.Start, form = if type(sk.form) == "number" then clamp01(sk.form) else 0.5,
        band = if sk.band == "Struggling" or sk.band == "Cruising" then sk.band else "Flow", n = int(sk.n), ws = int(sk.ws), ls = int(sk.ls), best = int(sk.best) }
    if type(raw.c) == "table" then for _, name in P.COUNTERS do record.c[name] = int(raw.c[name]) end end
    if type(raw.d) == "table" then
        for _, name in P.DIFFICULTIES do
            local row = raw.d[name]
            if type(row) == "table" then record.d[name] = { m = int(row.m), w = int(row.w), l = int(row.l), x = int(row.x) } end
        end
    end
    if type(raw.mp) == "table" then
        for name, row in raw.mp do if str(name, 64) and type(row) == "table" then record.mp[name] = { m = int(row.m), w = int(row.w) } end end
    end
    if type(raw.h) == "table" then
        for _, entry in raw.h do if type(entry) == "table" and str(entry.k, 128) then table.insert(record.h, table.clone(entry)) end end
        while #record.h > P.HISTORY do table.remove(record.h) end
    end
    if type(raw.ss) == "table" then
        for _, s in raw.ss do if type(s) == "table" then table.insert(record.ss, { at = int(s.at), last = int(s.last), min = num(s.min), m = int(s.m) }) end end
        while #record.ss > P.SESSIONS do table.remove(record.ss) end
    end
    local f = if type(raw.f) == "table" then raw.f else {}
    record.f = { joined = int(f.joined), days = int(f.days), lastDay = str(f.lastDay, 10), fsMin = num(f.fsMin),
        fsb = if f.fsb == "lt60" or f.fsb == "s60to180" or f.fsb == "later" then f.fsb else nil, opening = f.opening == true }
    if type(raw.ui) == "table" then for name in P.SCREENS do if raw.ui[name] then record.ui[name] = int(raw.ui[name]) end end end
    if type(raw.rb) == "table" then
        for key, row in raw.rb do if str(key, 80) and type(row) == "table" then record.rb[key] = { s = int(row.s), o = int(row.o), b = int(row.b) } end end
    end
    if type(raw.keys) == "table" then
        for _, key in raw.keys do if str(key, 128) then table.insert(record.keys, key) end end
        while #record.keys > P.KEYS do table.remove(record.keys, 1) end
    end
    return record
end

-- §v3.1 the Solo match score S and its parts. m = {res = "W"|"L"|"X", aliveAtEnd, peak (0..1), alive (s), t3, tiles, sent, won,
-- lost, kept, lowHit, comeback, capO, gpm, city (s or nil), built, diff}. comeback is nil (no low point) -> its weight goes to result.
function P.score(m: any): (number, any)
    local S = Config.Skill
    local W = S.Weights
    local result = if m.res == "W" then 1 elseif m.res == "X" then 0.2 elseif m.aliveAtEnd then 0.5 else 0
    local land = math.min(1, num(m.peak) / S.WinLine)
    local survival = if m.res == "W" then 1 else math.min(1, num(m.alive) / S.SurvivalSeconds)
    local pace = math.min(1, num(if m.t3 ~= nil then m.t3 else m.tiles) / S.PaceTiles)
    local fights = int(m.won) + int(m.lost)
    local smart = 0.6 * (if fights >= S.MinAttacks then int(m.won) / fights else 0.5) + 0.4 * (if int(m.sent) > 0 then int(m.kept) / int(m.sent) else 0.5)
    local comeback: number? = nil
    if m.lowHit then comeback = if m.comeback then 1 elseif int(m.capO) > 0 then 0.5 else 0 end
    local target = S.GoldPerMinute[m.diff] or S.GoldPerMinute.Medium
    local city = if type(m.city) == "number" then math.clamp(1 - (m.city - S.CityBest) / (S.CityWorst - S.CityBest), 0, 1) else 0
    local economy = (math.min(1, num(m.gpm) / target) + city + math.min(1, int(m.built) / S.Buildings)) / 3
    local total = W.result * result + W.land * land + W.survival * survival + W.pace * pace + W.smart * smart + W.economy * economy
    total += if comeback ~= nil then W.comeback * comeback else W.comeback * result
    return math.clamp(total, 0, 1), { result = result, land = land, survival = survival, pace = pace, smart = smart, comeback = comeback, economy = economy }
end

-- v1 §3: the band from form and streaks (and an early elimination in the last match)
function P.band(sk: any, last: any?): string
    local B = Config.Skill.Bands
    if sk.form < B.Struggling or sk.ls >= B.LossStreak or (last and last.res ~= "W" and num(last.alive) < B.EarlySeconds) then return "Struggling" end
    if sk.form > B.Cruising and sk.ws >= B.CruiseStreak then return "Cruising" end
    return "Flow"
end

-- graded Elo against the Solo difficulty (one fixed opponent rating per mode)
function P.rate(sk: any, s: number, diff: string)
    local R = Config.Skill.Rating
    local opponent = R[diff] or R.Medium
    local expected = 1 / (1 + 10 ^ ((opponent - sk.r) / 400))
    local k = if sk.n < R.NewMatches then R.KNew else R.K
    sk.r = math.floor((sk.r + k * (s - expected)) * 10 + 0.5) / 10
    sk.form = if sk.n == 0 then s else sk.form * (1 - Config.Skill.Alpha) + s * Config.Skill.Alpha
    sk.n += 1
end

-- One player's match, read at the grant moment. info = StatsService's {key, kind = "Solo"|"Public", ranked?, result, state, owner,
-- facts (LevelFacts, with .skill = SkillFacts:facts()), place = {rank, of}?, at}
function P.matchEntry(info: any): any?
    local state, owner = info.state, info.owner
    if not str(info.key, 128) or type(state) ~= "table" or type(owner) ~= "number" then return nil end
    local facts = if type(info.facts) == "table" then info.facts else {}
    local k = if type(facts.skill) == "table" then facts.skill else {}
    local peak = clamp01(num(facts.peakLandPct) / 100)
    if peak <= 0 then return nil end -- never had land: not a match (StatsProfiles' rule)
    local config = if type(state.gameConfig) == "table" then state.gameConfig else {}
    local mode = if info.ranked then "Ranked" elseif info.kind == "Public" then "Public" else "Solo"
    local res = if info.result == "Victory" then "W" elseif info.result == "Defeat" then "L" else "X"
    local diff = if mode == "Solo" and table.find(P.DIFFICULTIES, config.difficulty) then config.difficulty else nil
    local place = if type(info.place) == "table" then info.place else {}
    local built = 0
    for _, source in P.BUILDS do built += int(state[source] and state[source][owner]) end
    local entry: any = { k = info.key, at = int(info.at), mode = mode, diff = diff,
        map = tostring(config.gameMap or (state.map and state.map.mapType) or "Unknown"), res = res,
        dur = int(state.elapsed), alive = int(k.alive), land = math.floor(peak * 1000) / 1000, place = int(place.rank), of = int(place.of),
        t1 = k.t1, t3 = k.t3, t5 = k.t5, t10 = k.t10, sent = int(k.sent), won = int(k.won), lost = int(k.lost),
        low = if k.low ~= nil then math.floor(clamp01(k.low) * 100) / 100 else nil, cap = int(k.cap), capO = int(k.capO),
        gpm = int(k.gpm), city = if type(k.city) == "number" then int(k.city) else nil, built = built,
        band = k.bandStart, live = if type(k.live) == "table" then { struggle = int(k.live.struggle), cruise = int(k.live.cruise) } else nil,
        dealt = if type(k.dealt) == "table" and next(k.dealt) then table.clone(k.dealt) else nil, next = if k.next then true else nil,
        nations = int(facts.nations), tribes = int(facts.tribes), players = int(facts.players), quit = k.quit, last = k.last,
        prem = if type(k.prem) == "table" and next(k.prem) then table.clone(k.prem) else nil }
    -- counters folded from the sim's per-owner totals (not kept in h)
    entry.counts = { kept = int(k.kept), revive = if k.revive then 1 else 0, takeover = if k.takeover then 1 else 0,
        comeback = if k.comeback then 1 else 0, hint = int(k.hintShown), opening = k.openingDone == true }
    for field, source in P.BUILDS do entry.counts[field] = int(state[source] and state[source][owner]) end
    for field, source in P.GOLD do entry.counts[field] = int(state[source] and state[source][owner]) end
    if mode == "Solo" and diff then
        local s, parts = P.score({ res = res, aliveAtEnd = (state.counts and state.counts[owner] or 0) > 0, peak = peak, alive = k.alive,
            t3 = k.t3, tiles = state.counts and state.counts[owner] or 0, sent = k.sent, won = k.won, lost = k.lost, kept = k.kept,
            lowHit = k.lowHit, comeback = k.comeback, capO = k.capO, gpm = k.gpm, city = k.city, built = built, diff = diff })
        entry.s = math.floor(s * 1000) / 1000
        entry.sa = math.floor(parts.smart * 1000) / 1000
        entry.cb = if parts.comeback ~= nil then parts.comeback else nil
        entry.ec = math.floor(parts.economy * 1000) / 1000
    end
    return entry
end

-- Fold one match in. Returns nil when this key is already in (a retry): nothing changes. Else a summary for the daily
-- aggregate: {mode, res, diff, map, s, band (after), dealt, next, built = {[building] = true}}.
function P.applyMatch(record: any, entry: any): any?
    if type(entry) ~= "table" or not str(entry.k, 128) or table.find(record.keys, entry.k) then return nil end
    table.insert(record.keys, entry.k)
    while #record.keys > P.KEYS do table.remove(record.keys, 1) end
    local c, counts = record.c, entry.counts or {}
    c.matches += 1
    c[if entry.mode == "Solo" then "solo" elseif entry.mode == "Ranked" then "ranked" else "public"] += 1
    if entry.res == "W" then c.wins += 1 elseif entry.res == "L" then c.losses += 1 else c.left += 1 end
    c.minutes += math.floor(int(entry.dur) / 6) / 10
    c.attacks += int(entry.sent); c.attacksWon += int(entry.won); c.attacksLost += int(entry.lost); c.sendsKept += int(counts.kept)
    c.nations += int(entry.nations); c.tribes += int(entry.tribes); c.players += int(entry.players)
    c.captured += int(entry.cap); c.capturedOpening += int(entry.capO)
    c.comebacks += int(counts.comeback); c.revives += int(counts.revive); c.takeovers += int(counts.takeover)
    c.hintShown += int(counts.hint)
    local built = {}
    for field in P.BUILDS do
        c[field] += int(counts[field]); c.built += int(counts[field])
        if int(counts[field]) > 0 then built[field] = true end
    end
    for field in P.GOLD do c[field] += int(counts[field]) end
    local openingNew = counts.opening == true and not record.f.opening
    if counts.opening then record.f.opening = true end
    if entry.dealt then for _, n in entry.dealt do c.dealt += int(n) end end
    if entry.next then c.nextTapped += 1; if entry.res == "W" then c.nextWon += 1 end end
    local offered = entry.mode == "Solo" and entry.res == "W" and P.NEXT[entry.diff] ~= nil -- the win card shows Next difficulty
    if offered then c.nextSeen += 1 end
    local map = record.mp[entry.map]
    if not map then map = { m = 0, w = 0 }; record.mp[entry.map] = map end
    map.m += 1; if entry.res == "W" then map.w += 1 end
    local sk = record.sk
    if entry.mode == "Solo" and entry.diff then
        local row = record.d[entry.diff]
        row.m += 1
        if entry.res == "W" then row.w += 1 elseif entry.res == "L" then row.l += 1 else row.x += 1 end
        if entry.s ~= nil then
            P.rate(sk, entry.s, entry.diff)
            if entry.res == "W" then sk.ws += 1; sk.ls = 0; sk.best = math.max(sk.best, sk.ws) else sk.ls += 1; sk.ws = 0 end
            sk.band = P.band(sk, entry)
        end
    end
    local kept = table.clone(entry); kept.counts = nil; kept.nations = nil; kept.tribes = nil; kept.players = nil; kept.quit = nil; kept.last = nil
    table.insert(record.h, 1, kept)
    while #record.h > P.HISTORY do table.remove(record.h) end
    return { mode = entry.mode, res = entry.res, diff = entry.diff, map = entry.map, s = entry.s, band = if entry.s ~= nil then sk.band else nil,
        dealt = entry.dealt, next = entry.next, offered = offered, built = built, hint = int(counts.hint), openingNew = openingNew,
        prem = entry.prem, bandStart = entry.band, dur = int(entry.dur), quit = entry.quit, last = entry.last, alive = int(entry.alive) }
end

local function bucket(minutes: number): string return if minutes < 1 then "lt60" elseif minutes <= 3 then "s60to180" else "later" end

-- One server stay (join..leave, `matches` matches ended here), folded at leave. Returns what the daily aggregate needs:
-- {newPlayer, firstLeaveToday, returning, newSession, minutes, fsFrom, fsTo, joinedDay}.
function P.applySession(record: any, joinAt: number, leaveAt: number, matches: number): any
    joinAt, leaveAt = int(joinAt), math.max(int(joinAt), int(leaveAt))
    local minutes = math.floor((leaveAt - joinAt) / 6) / 10
    local f = record.f
    local out: any = { minutes = minutes }
    if f.joined == 0 then f.joined = joinAt; out.newPlayer = true end
    out.joinedDay = P.day(f.joined)
    local today = P.day(leaveAt)
    if f.lastDay ~= today then
        out.firstLeaveToday = true
        out.returning = f.lastDay ~= nil and f.lastDay == P.day(leaveAt - 86400)
        f.days += 1; f.lastDay = today
    end
    local current = record.ss[1]
    if current and joinAt - current.last <= P.SESSION_GAP then
        current.last = math.max(current.last, leaveAt); current.min = math.floor((current.min + minutes) * 10 + 0.5) / 10; current.m += int(matches)
    else
        current = { at = joinAt, last = leaveAt, min = minutes, m = int(matches) }
        table.insert(record.ss, 1, current)
        while #record.ss > P.SESSIONS do table.remove(record.ss) end
        record.c.sessions += 1; out.newSession = true
    end
    record.c.sessionMinutes = math.floor((record.c.sessionMinutes + minutes) * 10 + 0.5) / 10
    -- the first session: still growing while the newest session is the player's first one
    if record.c.sessions == 1 then
        if f.fsMin < 15 and current.min >= 15 then out.played15 = true end
        f.fsMin = current.min
        local nextBucket = bucket(f.fsMin)
        if nextBucket ~= f.fsb then out.fsFrom, out.fsTo = f.fsb, nextBucket; f.fsb = nextBucket end
    end
    return out
end

-- The client's report, already cleaned (P.cleanReport), folded into ui/rb.
function P.applyReport(record: any, report: any)
    for screen, n in report.opens or {} do record.ui[screen] = int(record.ui[screen]) + n end
    for key, row in report.rb or {} do
        local mine = record.rb[key]
        if not mine then mine = { s = 0, o = 0, b = 0 }; record.rb[key] = mine end
        mine.s += int(row.s); mine.o += int(row.o); mine.b += int(row.b)
    end
end

-- PF - 1's StatsReport {v=1, o={[surface]=n}, s={["sku@placement"]=n}} (deltas) -> {opens = {[Screen] = n},
-- rb = {["sku|placement"] = {s}}}; unknown names dropped, every count clamped to 0..max. isSku(sku): one of our products.
function P.cleanReport(raw: any, isSku: (string) -> boolean, max: number?): any
    local cap = max or 1000
    local out = { opens = {}, rb = {} }
    if type(raw) ~= "table" then return out end
    if type(raw.o) == "table" then
        for screen, n in raw.o do if type(screen) == "string" and P.SCREENS[screen] and int(n) > 0 then out.opens[screen] = math.min(int(n), cap) end end
    end
    if type(raw.s) == "table" then
        local entries = 0
        for key, n in raw.s do
            if entries >= 64 then break end
            if type(key) ~= "string" or #key > 80 then continue end
            local sku, placement = string.match(key, "^([%w_%-]+)@(%a+)$")
            if sku and placement and P.PLACEMENTS[placement] and isSku(sku) and int(n) > 0 then
                out.rb[sku .. "|" .. placement] = { s = math.min(int(n), cap) }; entries += 1 -- stored as "sku|placement" (§v3.11)
            end
        end
    end
    return out
end

return table.freeze(P)
