--!strict
-- PF034 Discord activity feed (Ashton 2026-10-12): #joins, #leaves, #purchases and #tutorial.
-- A JOIN or LEAVE means entering or quitting the GAME, never a server hop: players enter on a hub (lobby) server and
-- our own teleports carry them to reserved servers (Solo, the tutorial, public matches) and back. An arrival by one of
-- our teleports (GetJoinData has a SourcePlaceId) is not a join; a departure our code teleported is marked first
-- (TeleportMarks) and is not a leave. A real quit from ANY server posts the leave.
-- The session spans the hops through one small record per player (OpenFrontPresence_v1 "u:<userId>"): opened at a
-- real join, bumped at match ends and purchases, closed at a real leave. No read at a hop arrival.
-- Pure engine: DiscordFeedService supplies the Roblox side (ports); tools/test-discord-feed.luau drives it with fakes.
-- Everything is pcall'd and off the gameplay thread. Posts are batched per channel (one message every FlushInterval,
-- at most 10 embeds and 6000 characters), routed through the proxy (Discord blocks Roblox's servers).
local Text = require(script.Parent.DiscordText)
local Report = require(script.Parent.TutorialReport)
local Feed = {}
Feed.VERSION = 1
Feed.FEEDS = table.freeze({"Joins", "Leaves", "Purchases", "Tutorial"})
Feed.URL_KEYS = table.freeze({Joins = "JoinUrl", Leaves = "LeaveUrl", Purchases = "PurchaseUrl", Tutorial = "TutorialUrl"})
Feed.MAX_BUYS = 20 -- purchases kept in one session record
Feed.STALE_SESSION = 12 * 3600 -- a session never counts for more than this (a leave that was never seen)
Feed.PERSIST_DELAY = 1 -- seconds a finished tutorial attempt / match count waits, so a leave in the same moment takes it
Feed.CLOSE_WAIT = 20 -- BindToClose: seconds to wait for the last stores before the final flush
local DISCORD_HOSTS = {"https://discord.com/", "https://discordapp.com/", "https://ptb.discord.com/", "https://canary.discord.com/"}

local function num(value: any): number return Text.finite(value) or 0 end
local function int(value: any): number return math.max(0, math.floor(num(value))) end
local function key(userId: number): string return "u:" .. tostring(userId) end

-- Ashton pastes the normal discord.com webhook URL; the feed sends it through the proxy host instead.
function Feed.proxied(url: any, proxyHost: string): string?
    if type(url) ~= "string" or not string.find(url, "/api/webhooks/", 1, true) or string.sub(url, 1, 8) ~= "https://" then return nil end
    for _, host in DISCORD_HOSTS do
        if string.sub(url, 1, #host) == host then return proxyHost .. string.sub(url, #host + 1) end
    end
    return url
end

-- The client's one report (DeviceReport.luau), validated: Phone / Tablet / PC / Console / VR.
function Feed.device(report: any): string?
    if type(report) ~= "table" then return nil end
    for _, field in {"touch", "keyboard", "mouse", "gamepad", "vr", "tenFoot"} do
        if report[field] ~= nil and type(report[field]) ~= "boolean" then return nil end
    end
    local w, h = Text.finite(report.w), Text.finite(report.h)
    if w == nil or h == nil or w < 1 or h < 1 or w > 10000 or h > 10000 then return nil end
    if report.vr then return "VR" end
    if report.tenFoot then return "Console" end
    if report.touch and not report.keyboard and not report.mouse then return if math.min(w, h) < 600 then "Phone" else "Tablet" end
    if report.gamepad and not report.keyboard and not report.mouse and not report.touch then return "Console" end
    return "PC"
end

-- Has this player been here before, from the durable stores (levels, cosmetic receipts, saved games played)? Captured at
-- the join, before this visit adds anything. true / false, or nil when a store is unknown.
function Feed.played(history: any): boolean?
    if type(history) ~= "table" then return nil end
    local known = true
    local l, c, p = history.levels, history.cosmetics, history.preferences
    if type(l) == "table" and not l.failed then
        if num(l.xp) > 0 or num(l.matches) > 0 then return true end
    else known = false end
    if type(c) == "table" and not c.failed then
        if c.tutorial == true or num(c.receipts) > 0 then return true end
    else known = false end
    if type(p) == "table" and not p.failed then
        if num(p.gamesPlayed) > 0 then return true end
    else known = false end
    return if known then false else nil
end

function Feed.tutorialWhere(step: any, steps: {any}): string
    local n = math.floor(num(step))
    if n > #steps then return "Tutorial · finished" end
    local entry = steps[math.max(1, n)]
    return "Tutorial · step " .. tostring(math.max(1, n)) .. ": " .. (if entry then entry.title else "?")
end

-- The presence record (OpenFrontPresence_v1 "u:<userId>"). Lifetime numbers count from the day the feed went live.
function Feed.newPresence(): any
    return {version = Feed.VERSION, firstSeen = 0, lastSeen = 0, playtime = 0, sessions = 0, matches = 0, wins = 0}
end
-- A record we can't read is left alone (nil), never overwritten.
function Feed.validatePresence(raw: any): any?
    if raw == nil then return Feed.newPresence() end
    if type(raw) ~= "table" or raw.version ~= Feed.VERSION then return nil end
    local record = Feed.newPresence()
    for _, field in {"firstSeen", "lastSeen", "playtime", "sessions", "matches", "wins"} do record[field] = int(raw[field]) end
    if raw.tut == true then record.tut = true end -- a stored tutorial attempt waits for the next leave
    local c = raw.current
    if type(c) == "table" then
        local buys = {}
        for _, buy in (if type(c.buys) == "table" then c.buys else {}) do
            if type(buy) == "table" and type(buy.id) == "string" then
                table.insert(buys, {id = buy.id, n = if type(buy.n) == "string" then buy.n else "?", r = int(buy.r)})
            end
        end
        record.current = {start = int(c.start), seen = int(c.seen), matches = int(c.matches), wins = int(c.wins), levels = int(c.levels),
            robux = int(c.robux), buys = buys, ret = c.ret == true, done = c.done == true,
            dev = if type(c.dev) == "string" then c.dev else nil, cc = if type(c.cc) == "string" then c.cc else nil}
    end
    return record
end
-- A real join opens this visit's session. Returns what the record said before it (for the join embed).
function Feed.openSession(record: any, now: number, info: any): any
    local c = record.current
    if c then -- the last visit's leave was never seen (a crash or a quit mid-teleport): count what was seen of it
        record.playtime += math.clamp(c.seen - c.start, 0, Feed.STALE_SESSION)
        record.lastSeen = math.max(record.lastSeen, c.seen)
    end
    local prior = {sessions = record.sessions, lastSeen = record.lastSeen, playtime = record.playtime, matches = record.matches,
        wins = record.wins, firstSeen = record.firstSeen}
    if record.firstSeen == 0 then record.firstSeen = now end
    record.sessions += 1
    record.current = {start = now, seen = now, matches = 0, wins = 0, levels = 0, robux = 0, buys = {},
        ret = record.sessions > 1 or info.played == true, done = info.done == true, dev = info.device, cc = info.country}
    return prior
end
-- Match ends this visit: {matches, wins, levels}.
function Feed.bump(record: any, now: number, change: any)
    record.matches += int(change.matches); record.wins += int(change.wins)
    local c = record.current
    if c then
        c.seen = math.max(c.seen, now)
        c.matches += int(change.matches); c.wins += int(change.wins); c.levels += int(change.levels)
    end
end
-- A purchase this visit. false when it is already recorded (no write).
function Feed.buy(record: any, now: number, buy: any): boolean
    local c = record.current
    if not c then return false end
    for _, entry in c.buys do if entry.id == buy.id then return false end end
    table.insert(c.buys, {id = buy.id, n = buy.name, r = int(buy.robux)})
    while #c.buys > Feed.MAX_BUYS do table.remove(c.buys, 1) end
    c.robux += int(buy.robux)
    c.seen = math.max(c.seen, now)
    return true
end
-- A real leave closes the session. Returns the closed session (with .length), or nil when none was open.
function Feed.closeSession(record: any, now: number): any?
    local c = record.current
    record.lastSeen = math.max(record.lastSeen, now)
    if not c then return nil end
    local length = math.clamp(now - c.start, 0, Feed.STALE_SESSION)
    record.playtime += length
    record.current = nil
    local session = table.clone(c)
    session.length = length
    return session
end

local Methods = {}; Methods.__index = Methods
-- ports (DiscordFeedService): now, unix, iso, spawn, wait, log, post(url, body) -> ok, httpEnabled, encode, budget(critical),
-- presence {update}, tutorial {update}, steps, arrival(player) -> "join"|"hop", hopping(player), country(player),
-- cosmetics(userId), history(userId), level(player), where(player), price(kind, id), itemName(kind, id)
function Feed.new(ports: any, config: any, urls: any?): any
    local self = setmetatable({ports = ports, config = config, urls = {}, queues = {}, players = {}, devices = {}, closing = false,
        inflight = 0, purchases = {}, pendingTutorial = {}, bumps = {}, writing = {}, recent = {}, prices = {}, warned = {}, flushing = false}, Methods)
    if config.Enabled ~= false then
        for _, feed in Feed.FEEDS do
            if config.Feeds == nil or config.Feeds[feed] ~= false then
                local url = Feed.proxied(urls and urls[Feed.URL_KEYS[feed]], config.ProxyHost)
                if url then self.urls[feed] = url
                elseif urls and type(urls[Feed.URL_KEYS[feed]]) == "string" and urls[Feed.URL_KEYS[feed]] ~= "" then
                    self:log("[OpenFront] Discord feed: " .. Feed.URL_KEYS[feed] .. " is not a Discord webhook URL, so #" .. string.lower(feed) .. " stays off.")
                end
            end
        end
    end
    self.tracker = Report.new({now = ports.now, unix = ports.unix, steps = ports.steps, log = ports.log, stages = ports.stages,
        ended = function(attempt: any) self:tutorialEnded(attempt) end})
    return self
end
function Methods.log(self: any, message: string) if self.ports.log then pcall(self.ports.log, message) end end
function Methods.active(self: any, feed: string): boolean return self.urls[feed] ~= nil end
function Methods.any(self: any): boolean return next(self.urls) ~= nil end
function Methods.tracksPresence(self: any): boolean
    return self.ports.presence ~= nil and (self:active("Joins") or self:active("Leaves") or self:active("Purchases"))
end
-- One store transaction (pcall'd and budget-aware). Returns whether the call itself worked.
function Methods.store(self: any, store: any, userId: number, transform: any, critical: boolean): boolean
    if not store then return false end
    if self.ports.budget then
        local ok, enough = pcall(self.ports.budget, critical)
        if ok and not enough then return false end
    end
    self.inflight += 1
    local ok, failure = pcall(store.update, key(userId), transform)
    self.inflight -= 1
    if not ok then self:log("[OpenFront] Discord feed store failed: " .. tostring(failure)) end
    return ok
end
function Methods.task(self: any, fn: any, ...: any)
    self.inflight += 1
    local args = table.pack(...)
    self.ports.spawn(function()
        local ok, failure = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then self:log("[OpenFront] Discord feed task failed: " .. tostring(failure)) end
        self.inflight -= 1
    end)
end

-- Players ----------------------------------------------------------------------------------------------------------
function Methods.playerAdded(self: any, player: any)
    if self.closing or self.players[player] or not self:any() then return end
    local okArrival, arrival = pcall(self.ports.arrival, player)
    local visit = {player = player, userId = player.UserId, name = player.Name, display = player.DisplayName, at = self.ports.now(),
        kind = if okArrival and arrival == "hop" then "hop" else "join"}
    self.players[player] = visit
    self:task(function()
        local ok, country = pcall(self.ports.country, player)
        if ok and type(country) == "string" and #country >= 2 and #country <= 3 then visit.country = country end
        visit.countryDone = true
    end)
    if visit.kind == "join" then self:task(self.join, self, visit) end
end
function Methods.device(self: any, player: any, report: any): boolean
    if self.devices[player.UserId] then return false end -- one report per player per server
    local device = Feed.device(report)
    if not device then return false end
    self.devices[player.UserId] = device
    local visit = self.players[player]
    if visit and not visit.device then visit.device = device end
    return true
end
-- What the visit knows now (the caches outlive the profiles, which other services drop as the player leaves).
function Methods.refreshVisit(self: any, visit: any)
    local P = self.ports
    visit.device = visit.device or self.devices[visit.userId]
    local okC, cosmetics = pcall(P.cosmetics, visit.userId)
    if okC and type(cosmetics) == "table" and (not cosmetics.failed or visit.cosmetics == nil) then visit.cosmetics = cosmetics end
    local okL, level = pcall(P.level, visit.player)
    if okL and Text.finite(level) then visit.level = level end
    if visit.kind == "join" and visit.history == nil then
        local okH, history = pcall(P.history, visit.userId)
        if okH and type(history) == "table" then visit.history = history end
    end
    if not visit.departed then
        local okW, where = pcall(P.where, visit.player)
        if okW and type(where) == "string" then visit.where = where end
    end
end
function Methods.refresh(self: any) for _, visit in self.players do self:refreshVisit(visit) end end
-- A real join: gather (device, stores, country) for up to JoinWaitSeconds, then open the session and post.
function Methods.join(self: any, visit: any)
    local deadline = self.ports.now() + (self.config.JoinWaitSeconds or 15)
    while not visit.departed and not self.closing and self.ports.now() < deadline do
        self:refreshVisit(visit)
        if visit.device and visit.countryDone and visit.cosmetics ~= nil and visit.level ~= nil and visit.history ~= nil then break end
        self.ports.wait(0.5)
    end
    if not visit.departed then self:refreshVisit(visit) end
    self:open(visit)
end
-- Once per real join (the gather, an early purchase, a hop or a quit can each get here first).
function Methods.open(self: any, visit: any)
    if visit.kind ~= "join" or visit.openState == "done" then return end
    if visit.openState == "busy" then
        while visit.openState == "busy" do self.ports.wait(0.1) end
        return
    end
    visit.openState = "busy"
    local ok, failure = pcall(function()
        local played = Feed.played(visit.history)
        local done = type(visit.cosmetics) == "table" and visit.cosmetics.tutorial == true
        local prior = nil
        if self:tracksPresence() then
            local now = self.ports.unix()
            self:store(self.ports.presence, visit.userId, function(raw: any): any?
                prior = nil
                local record = Feed.validatePresence(raw)
                if not record then return nil end
                prior = Feed.openSession(record, now, {played = played, done = done, device = visit.device, country = visit.country})
                return record
            end, true)
        end
        visit.prior = prior
        visit.returning = (prior ~= nil and prior.sessions > 0) or played == true
        if self:active("Joins") then self:push("Joins", self:joinEmbed(visit)) end
    end)
    visit.openState = "done"
    if not ok then self:log("[OpenFront] Discord feed join failed: " .. tostring(failure)) end
end
function Methods.playerRemoving(self: any, player: any)
    local visit = self.players[player]
    if not visit then return end
    self.players[player] = nil
    self:refreshVisit(visit)
    visit.departed = true
    -- where they were: the tutorial tracker knows the step best (MatchService may already have dropped the match)
    local live = self.tracker:current(visit.userId)
    local recent = self.recent[visit.userId]
    if live then visit.where = Feed.tutorialWhere(live.progress.step, self.ports.steps)
    elseif recent and self.ports.now() - recent.at < 5 then
        visit.where = Feed.tutorialWhere(if recent.attempt.done then #self.ports.steps + 1 else recent.attempt.step, self.ports.steps)
    end
    self.devices[visit.userId] = nil
    local okHop, hop = pcall(self.ports.hopping, player)
    if okHop and hop then self.recent[visit.userId] = nil; return end -- our own teleport: the join task (if still gathering) posts on its own
    self:task(function()
        self.ports.wait(0) -- every other PlayerRemoving handler runs first (MatchService ends the tutorial attempt)
        self:leave(visit)
    end)
end
-- A real quit: the join first (a quick quitter), then close the session, take the tutorial attempts, post.
function Methods.leave(self: any, visit: any)
    if visit.kind == "join" then self:open(visit) end
    self.tracker:finishUser(visit.userId, Report.How.Quit) -- a safety net: MatchService normally ended it already
    -- a match count or a tutorial attempt already being stored lands first; then this leave takes whatever is left
    local deadline = self.ports.now() + 10
    local waited = false
    while (self.writing[visit.userId] or 0) > 0 and self.ports.now() < deadline do waited = true; self.ports.wait(0.1) end
    local pending = self.pendingTutorial[visit.userId] or {}
    self.pendingTutorial[visit.userId] = nil
    local session, record, flagged = nil, nil, false
    local bumps = self.bumps[visit.userId]
    self.bumps[visit.userId] = nil
    local stored = false
    if self:tracksPresence() then
        local now = self.ports.unix()
        stored = self:store(self.ports.presence, visit.userId, function(raw: any): any?
            session, record, flagged = nil, nil, false
            local current = Feed.validatePresence(raw)
            if not current then return nil end
            if bumps then Feed.bump(current, now, bumps) end
            session = Feed.closeSession(current, now)
            flagged = current.tut == true; current.tut = nil -- taken just below
            record = current
            return current
        end, true) and record ~= nil
    end
    -- the tutorial store is read only when there is something to post: an attempt on this server, the presence record's
    -- flag (another server stored one), or no presence record to ask
    local attempts = {}
    if flagged or waited or not stored or #pending > 0 then attempts = self:takeTutorial(visit.userId, pending) end
    if self:active("Leaves") then self:push("Leaves", self:leaveEmbed(visit, session, record, attempts)) end
    if self:active("Tutorial") then
        local returning = if session then session.ret else visit.returning
        for _, attempt in attempts do
            self:push("Tutorial", Report.embed(attempt, {steps = self.ports.steps, returning = returning,
                device = visit.device or (session and session.dev), country = visit.country or (session and session.cc),
                color = self.config.Colors.Tutorial, doneColor = self.config.Colors.TutorialDone}))
        end
    end
    self.recent[visit.userId] = nil
end

-- Matches and levels (the levels grant: one call per match per player) ---------------------------------------------
function Methods.grant(self: any, userId: any, matchKey: any, facts: any, result: any)
    if not self:tracksPresence() or type(userId) ~= "number" or type(matchKey) ~= "string" then return end
    local tutorial = string.sub(matchKey, 1, 9) == "tutorial:"
    local played = not tutorial and type(facts) == "table" and num(facts.peakLandPct) > 0
    local won = played and type(facts) == "table" and facts.won == true
    local gained = 0
    if type(result) == "table" and Text.finite(result.level) and Text.finite(result.levelBefore) then gained = int(result.level - result.levelBefore) end
    if not played and gained == 0 then return end
    local bumps = self.bumps[userId]
    if not bumps then bumps = {matches = 0, wins = 0, levels = 0}; self.bumps[userId] = bumps end
    bumps.matches += if played then 1 else 0
    bumps.wins += if won then 1 else 0
    bumps.levels += gained
    self:task(function()
        self.ports.wait(Feed.PERSIST_DELAY)
        self:writeBumps(userId)
    end)
end
-- One user's store write in flight (a leave waits for it, so the two never pass each other).
function Methods.writingFor(self: any, userId: number, fn: any)
    self.writing[userId] = (self.writing[userId] or 0) + 1
    local ok, failure = pcall(fn)
    self.writing[userId] -= 1
    if self.writing[userId] <= 0 then self.writing[userId] = nil end
    if not ok then self:log("[OpenFront] Discord feed write failed: " .. tostring(failure)) end
end
function Methods.writeBumps(self: any, userId: number)
    local bumps = self.bumps[userId]
    if not bumps then return end
    self.bumps[userId] = nil
    self:writingFor(userId, function()
        local now = self.ports.unix()
        local ok = self:store(self.ports.presence, userId, function(raw: any): any?
            local record = Feed.validatePresence(raw)
            if not record then return nil end
            Feed.bump(record, now, bumps)
            return record
        end, false)
        if not ok then -- keep them for the next write (the leave takes them)
            local again = self.bumps[userId]
            if again then for field, value in bumps do again[field] += value end else self.bumps[userId] = bumps end
        end
    end)
end

-- Tutorial attempts ------------------------------------------------------------------------------------------------
function Methods.tutorialHooks(self: any): any
    local tracker = self.tracker
    return table.freeze({begin = function(context: any) tracker:begin(context) end, sample = function(context: any) tracker:sample(context) end,
        finish = function(context: any, how: string?) tracker:finish(context, how) end})
end
function Methods.tutorialEnded(self: any, attempt: any)
    -- PF038: the permanent tutorial archive gets every finished attempt, with this visit's device and country
    if self.ports.archive then
        local country = nil
        for _, visit in self.players do if visit.userId == attempt.userId then country = visit.country end end
        pcall(self.ports.archive, attempt, {device = self.devices[attempt.userId], country = country})
    end
    self.recent[attempt.userId] = {attempt = attempt, at = self.ports.now()}
    if not self:active("Tutorial") or not self.ports.tutorial then return end
    local list = self.pendingTutorial[attempt.userId]
    if not list then list = {}; self.pendingTutorial[attempt.userId] = list end
    table.insert(list, attempt)
    self:task(function()
        self.ports.wait(Feed.PERSIST_DELAY) -- a leave in the same moment takes it with its own write
        self:persistTutorial(attempt.userId)
    end)
end
function Methods.persistTutorial(self: any, userId: number)
    local pending = self.pendingTutorial[userId]
    if not pending or #pending == 0 then return end
    self.pendingTutorial[userId] = nil
    self:writingFor(userId, function()
        local appended = false
        local ok = self:store(self.ports.tutorial, userId, function(raw: any): any?
            appended = false
            local record = Report.validate(raw)
            if not record or not Report.append(record, pending) then return nil end
            appended = true
            return record
        end, false)
        if not ok then -- keep them for the leave
            local again = self.pendingTutorial[userId] or {}
            for index, attempt in pending do table.insert(again, index, attempt) end
            self.pendingTutorial[userId] = again
        elseif appended and self:tracksPresence() then -- flag it, so the leave (on any server) knows to read the tutorial store
            local now = self.ports.unix()
            self:store(self.ports.presence, userId, function(raw: any): any?
                local record = Feed.validatePresence(raw)
                if not record or record.tut then return nil end
                record.tut = true
                if record.current then record.current.seen = math.max(record.current.seen, now) end
                return record
            end, false)
        end
    end)
end
-- The leave: this server's unsaved attempts plus every stored one not yet posted, in order.
function Methods.takeTutorial(self: any, userId: number, pending: {any}): {any}
    if not self:active("Tutorial") or not self.ports.tutorial then return {} end
    local taken = {}
    local ok = self:store(self.ports.tutorial, userId, function(raw: any): any?
        taken = {}
        local record = Report.validate(raw)
        if not record then return nil end
        local changed = Report.append(record, pending)
        if #record.pending == 0 and not changed then return nil end -- nothing to post: no write
        taken = Report.take(record)
        return record
    end, true)
    if not ok then return pending end -- the store is down: post what this server saw rather than lose it
    return taken
end

-- Purchases (CosmeticService.onPurchase: the real receipt and Game Pass paths) -------------------------------------------
-- info = {player, userId, kind = "product"|"pass", id, purchaseId?, robux?, fresh?}
function Methods.purchase(self: any, info: any)
    if type(info) ~= "table" or info.fresh == false or type(info.userId) ~= "number" or not Text.finite(info.id) then return end
    if not self:active("Purchases") and not self:tracksPresence() then return end
    local id = if type(info.purchaseId) == "string" and info.purchaseId ~= "" then info.purchaseId else info.kind .. ":" .. tostring(info.id)
    local dedupe = tostring(info.userId) .. ":" .. id
    if self.purchases[dedupe] then return end
    self.purchases[dedupe] = true
    self:task(self.bought, self, info, id)
end
function Methods.price(self: any, kind: string, id: number): number?
    local cacheKey = kind .. ":" .. tostring(id)
    local cached = self.prices[cacheKey]
    if cached ~= nil then return if cached == false then nil else cached end
    local ok, price = pcall(self.ports.price, kind, id)
    local value = if ok and Text.finite(price) then math.floor(price) else nil
    self.prices[cacheKey] = if value then value else false
    return value
end
function Methods.bought(self: any, info: any, id: string)
    local P = self.ports
    local okName, name = pcall(P.itemName, info.kind, info.id)
    name = if okName and type(name) == "string" then name else (if info.kind == "pass" then "Game Pass " else "Product ") .. tostring(info.id)
    local robux = if Text.finite(info.robux) then math.floor(info.robux) else self:price(info.kind, info.id)
    local visit = info.player and self.players[info.player]
    if visit then
        if visit.kind == "join" then self:open(visit) end -- a purchase in the first seconds still lands in the session
        self:refreshVisit(visit)
    end
    local session, record = nil, nil
    if self:tracksPresence() then
        local now = P.unix()
        self:store(P.presence, info.userId, function(raw: any): any?
            session, record = nil, nil
            local current = Feed.validatePresence(raw)
            if not current then return nil end
            local changed = Feed.buy(current, now, {id = id, name = name, robux = robux})
            record = current
            session = if current.current then table.clone(current.current) else nil
            return if changed then current else nil
        end, false)
    end
    if not self:active("Purchases") then return end
    local summary = if visit and type(visit.cosmetics) == "table" and not visit.cosmetics.failed then visit.cosmetics else nil
    local count, same, lifetime = 0, 0, 0
    if summary then
        for productId, n in summary.products or {} do
            count += n
            lifetime += n * (self:price("product", productId) or 0)
            if info.kind == "product" and productId == info.id then same += n end
        end
        for _, pass in summary.passes or {} do
            count += 1
            lifetime += self:price("pass", pass.passId) or 0
            if info.kind == "pass" and pass.passId == info.id then same = 1 end
        end
        if info.kind == "pass" and same == 0 then count += 1; same = 1; lifetime += robux or 0 end -- confirmation still landing
    end
    self:push("Purchases", self:purchaseEmbed(info, visit, name, robux, session, record, count, same, lifetime))
end

-- Embeds -------------------------------------------------------------------------------------------------------------
local function who(visit: any): string
    local display, name = visit.display or visit.name or "?", visit.name or "?"
    if display == name then return Text.escape(name) end
    return Text.escape(display) .. " (@" .. Text.escape(name) .. ")"
end
local function profile(userId: number): string return "https://www.roblox.com/users/" .. tostring(userId) .. "/profile" end
local function passes(summary: any): string?
    if type(summary) ~= "table" or summary.failed or type(summary.passes) ~= "table" or #summary.passes == 0 then return nil end
    local names = {}
    for _, pass in summary.passes do table.insert(names, pass.name) end
    return Text.list(names)
end
local function matchesText(matches: number, wins: number): string?
    if matches <= 0 then return nil end
    return Text.number(matches) .. (if wins > 0 then " · " .. Text.number(wins) .. (if wins == 1 then " win" else " wins") else "")
end
function Methods.tutorialDone(self: any, visit: any, session: any?, attempts: {any}?): boolean
    if type(visit.cosmetics) == "table" and visit.cosmetics.tutorial == true then return true end
    if session and session.done then return true end
    for _, attempt in attempts or {} do if attempt.done then return true end end
    return false
end
-- The player's standing: Cobalt, level, passes, lifetime matches and playtime (each left out when 0 or none).
function Methods.statFields(self: any, fields: {any}, visit: any, totals: any?)
    local c = if type(visit.cosmetics) == "table" and not visit.cosmetics.failed then visit.cosmetics else nil
    Text.field(fields, "Cobalt", if c and num(c.balance) > 0 then Text.number(c.balance) else nil)
    Text.field(fields, "Level", if visit.level and visit.level > 1 then tostring(math.floor(visit.level)) else nil)
    Text.field(fields, "Passes", passes(c))
    if totals then
        Text.field(fields, "Matches", matchesText(totals.matches, totals.wins))
        Text.field(fields, "Playtime", if totals.playtime > 0 then Text.duration(totals.playtime) else nil)
    end
end
function Methods.joinEmbed(self: any, visit: any): any
    local fields = {}
    -- Ashton 2026-10-12: only a true first-timer shows no stats; veterans from before the tutorial existed show theirs
    local hide = self.config.HideStatsUntilTutorial ~= false and not visit.returning and not self:tutorialDone(visit)
    local headline = if visit.returning then "**Returning player**" else "**New player**"
    if hide and visit.returning then headline ..= " · tutorial not finished" end
    local prior = visit.prior
    if not hide then self:statFields(fields, visit, prior) end
    if visit.returning and prior and prior.lastSeen > 0 then Text.field(fields, "Last seen", Text.ago(self.ports.unix() - prior.lastSeen)) end
    Text.field(fields, "Device", visit.device)
    Text.field(fields, "Country", visit.country)
    return {title = who(visit) .. " joined", url = profile(visit.userId), description = headline, color = self.config.Colors.Join,
        fields = fields, footer = {text = "userId " .. tostring(visit.userId)}}
end
function Methods.leaveEmbed(self: any, visit: any, session: any?, record: any?, attempts: {any}): any
    local fields = {}
    local returning = if session then session.ret else visit.returning == true
    local done = self:tutorialDone(visit, session, attempts)
    local hide = self.config.HideStatsUntilTutorial ~= false and not visit.returning and not done
    Text.field(fields, "Session", if session then Text.duration(session.length) else nil)
    Text.field(fields, "Left from", visit.where or "Unknown")
    if session then
        local visitParts = {}
        if session.matches > 0 then table.insert(visitParts, session.matches .. (if session.matches == 1 then " match" else " matches")) end
        if session.wins > 0 then table.insert(visitParts, session.wins .. (if session.wins == 1 then " win" else " wins")) end
        if session.levels > 0 then table.insert(visitParts, "+" .. session.levels .. (if session.levels == 1 then " level" else " levels")) end
        Text.field(fields, "This visit", table.concat(visitParts, " · "), false)
        if #session.buys > 0 then
            local names = {}
            for _, buy in session.buys do table.insert(names, buy.n) end
            Text.field(fields, "Bought", Text.list(names) .. (if session.robux > 0 then " · R$" .. Text.number(session.robux) else ""), false)
        end
    end
    if hide then
        local step = nil
        for _, attempt in attempts do step = attempt.step end
        Text.field(fields, "Tutorial", "Not finished" .. (if step then " (step " .. step .. ")" else ""))
    else self:statFields(fields, visit, record) end
    Text.field(fields, "Device", visit.device or (session and session.dev))
    Text.field(fields, "Country", visit.country or (session and session.cc))
    local headline = (if returning then "**Returning player**" else "**New player**")
        .. (if visit.closedBy then " · the server shut down" else "")
    return {title = who(visit) .. " left", url = profile(visit.userId), description = headline, color = self.config.Colors.Leave,
        fields = fields, footer = {text = "userId " .. tostring(visit.userId)}}
end
function Methods.purchaseEmbed(self: any, info: any, visit: any?, name: string, robux: number?, session: any?, record: any?,
    count: number, same: number, lifetime: number): any
    local fields = {}
    local player = visit or {userId = info.userId, name = info.player and info.player.Name, display = info.player and info.player.DisplayName}
    local nth = if count > 0 then " · their " .. Text.ordinal(count) .. " purchase" .. (if same > 1 then " (" .. Text.ordinal(same) .. " " .. name .. ")" else "") else ""
    local description = (if robux then "**R$" .. Text.number(robux) .. "**" else "**R$?**") .. nth
    Text.field(fields, "Lifetime", if lifetime > 0 then "R$" .. Text.number(lifetime) else nil)
    local returning = if session then session.ret elseif visit then visit.returning else nil
    Text.field(fields, "Player", if returning == nil then nil elseif returning then "Returning" else "New")
    Text.field(fields, "Level", if visit and visit.level and visit.level > 1 then tostring(math.floor(visit.level)) else nil)
    if session and session.start > 0 then
        local minutes = math.max(0, math.floor((self.ports.unix() - session.start) / 60))
        Text.field(fields, "Session", if minutes < 1 then "first minute" else tostring(minutes) .. " min in")
    end
    Text.field(fields, "Where", if visit then visit.where else nil)
    local c = if visit and type(visit.cosmetics) == "table" and not visit.cosmetics.failed then visit.cosmetics else nil
    Text.field(fields, "Cobalt now", if c and num(c.balance) > 0 then Text.number(c.balance) else nil)
    return {title = who(player) .. " bought " .. name, url = profile(info.userId), description = description,
        color = self.config.Colors.Purchase, fields = fields,
        footer = {text = "userId " .. tostring(info.userId) .. " · " .. (if info.kind == "pass" then "pass " else "product ") .. tostring(info.id)}}
end

-- Queues and the flush ------------------------------------------------------------------------------------------------
function Methods.push(self: any, feed: string, embed: any)
    if not self.urls[feed] then return end
    if embed.timestamp == nil and self.ports.iso then
        local ok, stamp = pcall(self.ports.iso)
        if ok and type(stamp) == "string" then embed.timestamp = stamp end
    end
    local queue = self.queues[feed]
    if not queue then queue = {embeds = {}, dropped = 0, failures = 0}; self.queues[feed] = queue end
    if #queue.embeds >= (self.config.MaxQueue or 50) then table.remove(queue.embeds, 1); queue.dropped += 1 end
    table.insert(queue.embeds, Text.fit(embed))
end
function Methods.pending(self: any): number
    local total = 0
    for _, queue in self.queues do total += #queue.embeds end
    return total
end
-- One message per channel per call (final: until empty, a few messages at most).
function Methods.flush(self: any, final: boolean?)
    if self.flushing then
        if not final then return end
        local deadline = self.ports.now() + 10
        while self.flushing and self.ports.now() < deadline do self.ports.wait(0.1) end
    end
    self.flushing = true
    local ok, failure = pcall(function()
        local okHttp, enabled = pcall(self.ports.httpEnabled)
        if not okHttp or not enabled then
            if self:pending() > 0 and not self.warned.http then
                self.warned.http = true
                self:log("[OpenFront] Discord feed: HTTP requests are off. Turn on Game Settings > Security > Allow HTTP Requests.")
            end
            return
        end
        local perMessage = math.clamp(self.config.MaxPerMessage or 10, 1, Text.LIMITS.embeds)
        for _, feed in Feed.FEEDS do
            local queue, url = self.queues[feed], self.urls[feed]
            if not queue or not url then continue end
            for _ = 1, if final then 6 else 1 do
                if #queue.embeds == 0 then break end
                local batch, size = {}, 0
                while #queue.embeds > 0 and #batch < perMessage do
                    local nextSize = Text.size(queue.embeds[1])
                    if #batch > 0 and size + nextSize > Text.LIMITS.total - 100 then break end
                    table.insert(batch, table.remove(queue.embeds, 1))
                    size += nextSize
                end
                local content = if queue.dropped > 0 then "(" .. queue.dropped .. " older " .. (if queue.dropped == 1 then "event was" else "events were") .. " dropped: the queue was full)" else nil
                local body = self.ports.encode({content = content, embeds = batch, allowed_mentions = {parse = {}}})
                local sent, why = pcall(self.ports.post, url, body)
                if sent then
                    queue.dropped, queue.failures = 0, 0
                else
                    queue.failures += 1
                    self:log("[OpenFront] Discord feed post failed (#" .. string.lower(feed) .. "): " .. tostring(why))
                    if queue.failures < 3 then -- back to the front for the next flush
                        for index, embed in batch do table.insert(queue.embeds, index, embed) end
                        while #queue.embeds > (self.config.MaxQueue or 50) do table.remove(queue.embeds); queue.dropped += 1 end
                    else
                        queue.dropped += #batch; queue.failures = 0
                    end
                    break
                end
            end
        end
    end)
    self.flushing = false
    if not ok then self:log("[OpenFront] Discord feed flush failed: " .. tostring(failure)) end
end

-- BindToClose: anyone still here leaves with the server, unsaved tutorial attempts and match counts are stored, the
-- queues are flushed (reserved match servers close the moment the last player leaves).
function Methods.close(self: any)
    if self.closing then return end
    local deadline = self.ports.now() + 3
    while next(self.players) ~= nil and self.ports.now() < deadline do self.ports.wait(0.25) end -- their PlayerRemoving first
    self.closing = true
    self.tracker:finishAll(Report.How.Closed)
    for player, visit in table.clone(self.players) do
        self.players[player] = nil
        self:refreshVisit(visit)
        visit.departed, visit.closedBy = true, true
        self:task(self.leave, self, visit)
    end
    for userId in table.clone(self.pendingTutorial) do self:task(self.persistTutorial, self, userId) end
    for userId in table.clone(self.bumps) do self:task(self.writeBumps, self, userId) end
    local until_ = self.ports.now() + Feed.CLOSE_WAIT
    while self.inflight > 0 and self.ports.now() < until_ do self.ports.wait(0.1) end
    self:flush(true)
end

-- /discordtest: one sample embed per channel (posted at once).
function Feed.samples(steps: {any}, colors: any, unix: number): any
    local visit = {userId = 1, name = "PixelFront_Test", display = "Feed Test", device = "PC", country = "US", level = 12, returning = true,
        cosmetics = {balance = 4200, passes = {{name = "VIP", passId = 0}}, products = {}, tutorial = true}, where = "Lobby"}
    local attempt = {v = 1, n = 1, id = "sample", userId = 1, name = "PixelFront_Test", display = "Feed Test", start = unix, dur = 754, how = Report.How.Won,
        done = true, step = #steps + 1, reached = #steps, spawn = {t = 14, g = 50000},
        steps = {{i = 1, t = 21, g = 50000}, {i = 2, t = 112, g = 212000}, {i = 3, t = 190, g = 420000}, {i = 4, t = 205, g = 305000},
            {i = 5, t = 402, g = 880000}, {i = 6, t = 610, g = 1200000}, {i = 7, t = 754, g = 640000}},
        gold = {s = 50000, e = 4100000, x = 3510000, n = 640000}, built = {City = 4, Port = 1, ["Missile Silo"] = 1, ["Atom Bomb"] = 2},
        land = 61.2, troops = 18400, game = 980}
    local config = {Colors = colors, HideStatsUntilTutorial = true}
    local fake = setmetatable({config = config, ports = {unix = function() return unix end, steps = steps}}, Methods)
    local session = {length = 1520, matches = 2, wins = 1, levels = 1, buys = {{id = "x", n = "Medium Cobalt", r = 99}}, robux = 99, ret = true, start = unix - 600}
    local join = fake:joinEmbed(visit)
    local leave = fake:leaveEmbed(visit, session, {matches = 14, wins = 5, playtime = 40000}, {})
    local buy = fake:purchaseEmbed({userId = 1, kind = "product", id = 0}, visit, "Medium Cobalt", 99, session, nil, 3, 2, 647)
    local tutorial = Report.embed(attempt, {steps = steps, returning = false, device = "Phone", country = "US", color = colors.Tutorial, doneColor = colors.TutorialDone})
    for _, embed in {join, leave, buy, tutorial} do embed.title = "[TEST] " .. embed.title end
    return {Joins = join, Leaves = leave, Purchases = buy, Tutorial = tutorial}
end

return table.freeze(Feed)
