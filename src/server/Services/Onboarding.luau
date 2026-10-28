--!strict
-- Onboarding (PF - 2, MM 2026-10-07; Ashton: "it should be auto sending me into [tutorial] if im a new player").
-- A new player's first hub visit starts the tutorial, once ever. "New" comes only from durable server data (this
-- store, the levels record, the cosmetic receipts, the saved gamesPlayed); a store that failed or is late means
-- "not new", never a guess. An invited player is never hijacked: they are marked deferred and offered it on a
-- later visit, once. PF043 D9 (Ashton: "No tutorial isnt optional"): both go through the intro card (Start only, no
-- "Not now"); a tap starts it, else it starts by itself after INTRO_SECONDS. Pure engine: OnboardingService supplies the ports, tools/test-onboarding.luau
-- drives every path without Roblox.
local Onboarding = {}
Onboarding.VERSION = 1
Onboarding.STORE = "OpenFrontOnboarding_v1"
-- stores, counted from join; later than this the visit is skipped (the next can run it). UX audit #1 (Ashton picked
-- "Instant start", 2026-10-27): was 45 s; the verdict lands as soon as every source is in, this only caps a slow store,
-- and the client's boot cover (LobbyController.COVER_GIVE_UP) holds a little longer so the menu never flashes first
Onboarding.WAIT_SECONDS = 10
Onboarding.POLL_SECONDS = 0.5
Onboarding.SPLASH_SECONDS = 2 -- the splash is read before the teleport begins
Onboarding.RETRY_SECONDS = 6 -- one retry (after the admission's 5 s cooldown), then the player stays in the lobby
Onboarding.ADMIT_SECONDS = 900 -- a reserved server admits an auto run marked within this window
Onboarding.READY_SECONDS = 15 -- no boot handshake by then (a missed event): go ahead, the splash is only cosmetic
Onboarding.INTRO_SECONDS = 3 -- an older client's intro card (no longer sent): a splash at most, then the tutorial starts anyway
Onboarding.Text = table.freeze({
    starting = "Starting your first match…",
    retrying = "Still starting your tutorial…",
    failed = "The tutorial couldn't start, so you're in the lobby.",
})
local Methods = {}; Methods.__index = Methods

local function stamp(value: any): boolean
    return value == nil or (type(value) == "number" and value == value and value >= 0 and value <= 1e12 and value % 1 == 0)
end
function Onboarding.newRecord(): any return {version = Onboarding.VERSION} end
-- Reject unknown storage rather than overwriting it (an unreadable record means "not new").
function Onboarding.validate(raw: any): (any?, string?)
    if raw == nil then return Onboarding.newRecord(), nil end
    if type(raw) ~= "table" or raw.version ~= Onboarding.VERSION then return nil, "Unsupported onboarding record." end
    for key in raw do
        if key ~= "version" and key ~= "autoStarted" and key ~= "deferred" and key ~= "offered" then return nil, "Unknown onboarding fields." end
    end
    if not stamp(raw.autoStarted) or not stamp(raw.deferred) or not stamp(raw.offered) then return nil, "Invalid onboarding record." end
    return {version = raw.version, autoStarted = raw.autoStarted, deferred = raw.deferred, offered = raw.offered}, nil
end

-- The decision, from facts only. input = {record?, recordFailed?, levels?, cosmetics?, preferences?, admin?, studio?,
-- studioTest?, invited?, teleported?, busy?}; a source is nil while loading, {failed=true}, or its facts:
-- levels {xp, matches}, cosmetics {tutorial, receipts}, preferences {gamesPlayed}.
-- Returns verdict, reason. Verdicts: "wait" (a store is loading), "skip" (not this visit; nothing is recorded),
-- "new" (start it), "defer" (new but invited: record it, don't hijack), "offer" (an earlier invitee: offer it once).
function Onboarding.classify(input: any): (string, string)
    if input.studio and not input.studioTest then return "skip", "studio" end
    if input.admin and not input.studioTest then return "skip", "admin" end
    if input.teleported then return "skip", "teleported" end
    if input.recordFailed then return "skip", "store" end
    local record = input.record
    if record == nil then return "wait", "record" end
    if record.autoStarted then return "skip", "done" end
    if input.studioTest then -- Studio test: a brand-new player once per session (the memory store); invites still win
        if input.invited then return "skip", "invited" end
        if input.busy then return "skip", "busy" end
        return "new", "studio-test"
    end
    local levels, cosmetics, preferences = input.levels, input.cosmetics, input.preferences
    -- (explicit: a nil inside a table constructor is a hole that iteration skips)
    if levels == nil or cosmetics == nil or preferences == nil then return "wait", "sources" end
    if levels.failed or cosmetics.failed or preferences.failed then return "skip", "store" end
    if cosmetics.tutorial then return "skip", "tutorial" end
    if record.deferred then
        -- an earlier invitee: history no longer matters (they played their friend's match); offer once
        if record.offered then return "skip", "offered" end
        if input.invited then return "skip", "invited" end
        if input.busy then return "skip", "busy" end
        return "offer", "deferred"
    end
    if (tonumber(levels.xp) or 0) > 0 or (tonumber(levels.matches) or 0) > 0 then return "skip", "played" end
    if (tonumber(cosmetics.receipts) or 0) > 0 then return "skip", "receipts" end
    if (tonumber(preferences.gamesPlayed) or 0) > 0 then return "skip", "gamesPlayed" end
    if input.invited then return "defer", "invited" end
    if input.busy then return "skip", "busy" end
    return "new", "new"
end
-- A reserved server's check (option A: /tutorial stays restricted): admit an auto run marked moments ago.
function Onboarding.admits(record: any, nowUnix: number): boolean
    return type(record) == "table" and type(record.autoStarted) == "number" and nowUnix - record.autoStarted >= -60
        and nowUnix - record.autoStarted <= Onboarding.ADMIT_SECONDS
end

-- ports: now() (seconds, monotonic), unix() (os.time), wait(s), spawn(fn), get(key), update(key, transform),
-- sources(userId) -> levels?, cosmetics?, preferences?; busy(userId); present(userId); splash(userId, phase, message?);
-- notice(userId, message); start(userId, hooks{phase, failed, started}) -> (ok, why?); log(message)?
function Onboarding.new(ports: any): any
    for _, name in {"now", "unix", "wait", "spawn", "get", "update", "sources", "busy", "present", "splash", "notice", "start"} do
        assert(ports[name], "Missing onboarding port " .. name)
    end
    return setmetatable({ports = ports, players = {}, closing = false}, Methods)
end
function Methods.log(self: any, message: string) if self.ports.log then pcall(self.ports.log, message) end end

-- info = {admin, studio, studioTest, invited, teleported} (facts from Roblox at join, never from the client)
function Methods.add(self: any, userId: number, info: any): any?
    if self.closing or self.players[userId] then return self.players[userId] end
    local entry = {info = info or {}, ready = false, addedAt = self.ports.now(), state = "loading", record = nil, recordFailed = false}
    self.players[userId] = entry
    self.ports.spawn(function() self:run(userId, entry) end)
    return entry
end
function Methods.ready(self: any, userId: number) -- the client's boot handshake: its lobby can show the splash
    local entry = self.players[userId]
    if entry then entry.ready = true end
end
function Methods.remove(self: any, userId: number) self.players[userId] = nil end
function Methods.close(self: any) self.closing = true end

function Methods.input(self: any, userId: number, entry: any): any
    local levels, cosmetics, preferences = self.ports.sources(userId)
    local info = entry.info
    local okBusy, busy = pcall(self.ports.busy, userId)
    return {record = entry.record, recordFailed = entry.recordFailed, levels = levels, cosmetics = cosmetics, preferences = preferences,
        admin = info.admin, studio = info.studio, studioTest = info.studioTest, invited = info.invited, teleported = info.teleported,
        busy = not okBusy or busy}
end

function Methods.run(self: any, userId: number, entry: any)
    local P = self.ports
    local ok, data = false, nil
    for attempt = 1, 3 do
        if self.players[userId] ~= entry or self.closing then return end
        ok, data = pcall(P.get, "u:" .. tostring(userId))
        if ok then break end
        if attempt < 3 then P.wait(attempt) end
    end
    if self.players[userId] ~= entry then return end
    if ok then
        entry.record = (Onboarding.validate(data))
        entry.recordFailed = entry.record == nil
    else entry.recordFailed = true end
    local deadline = entry.addedAt + Onboarding.WAIT_SECONDS -- from join: the record's retries count toward it
    while true do
        if self.players[userId] ~= entry or self.closing then return end
        local verdict, reason = Onboarding.classify(self:input(userId, entry))
        entry.verdict, entry.reason = verdict, reason
        -- first-match onboarding: no wait for the client's boot handshake (the splash packet queues on the client
        -- until its listener connects), so the teleport starts as soon as the verdict is in
        local needsClient = false
        if verdict ~= "wait" and (not needsClient or entry.ready or P.now() - entry.addedAt >= Onboarding.READY_SECONDS) then
            -- first-match onboarding: everyone hears the verdict ("Lobby" = show the menu), so a client can hold a
            -- neutral cover on boot instead of flashing the menu at a player who's about to be sent into a match
            if verdict == "new" then self:begin(userId, entry)
            elseif verdict == "defer" then entry.state = "done"; P.splash(userId, "Lobby"); self:mark(userId, entry, "deferred")
            elseif verdict == "offer" then self:offer(userId, entry)
            else entry.state = "done"; P.splash(userId, "Lobby") end
            self:log(string.format("[OpenFront] Onboarding %d: %s (%s)", userId, verdict, reason))
            return
        end
        if P.now() >= deadline then
            entry.state = "done"; entry.verdict, entry.reason = "skip", "timeout"; P.splash(userId, "Lobby")
            self:log(string.format("[OpenFront] Onboarding %d: skip (timeout; was %s %s)", userId, verdict, reason))
            return
        end
        P.wait(Onboarding.POLL_SECONDS)
    end
end

-- The durable once-ever write. True only when this call set the field (an unreadable record, or one another server
-- already marked, writes nothing).
function Methods.mark(self: any, userId: number, entry: any, field: string): boolean
    local set, at = false, self.ports.unix()
    local ok, failure = pcall(self.ports.update, "u:" .. tostring(userId), function(old: any)
        set = false
        local record = Onboarding.validate(old)
        if not record or record[field] ~= nil or (field ~= "autoStarted" and record.autoStarted ~= nil) then return nil end
        record[field] = at; set = true
        return record
    end)
    if not ok then set = false; self:log("[OpenFront] Onboarding write failed: " .. tostring(failure)) end
    if set and entry.record then entry.record[field] = at end
    return set
end

-- PF043 D9: the intro card (splash "Intro"): Start (OnboardingCommand OfferPlay -> answer(true)) or the timeout ends it.
function Methods.intro(self: any, userId: number, entry: any)
    local P = self.ports
    entry.introOpen, entry.introGo = true, false
    P.splash(userId, "Intro")
    local deadline = P.now() + Onboarding.INTRO_SECONDS
    while self.players[userId] == entry and not self.closing and P.present(userId) and not entry.introGo and P.now() < deadline do
        P.wait(Onboarding.POLL_SECONDS)
    end
    entry.introOpen = false
end
-- New player: mark first, then straight into the first match. First-match onboarding (Ashton 2026-10-26: "not put them
-- in main menu then ask"): no intro card and no splash wait any more; "FirstMatch" tells the client to show the match
-- loading screen instead of the menu while the teleport runs. (Methods.intro stays for an older client's Start.)
function Methods.begin(self: any, userId: number, entry: any)
    local P = self.ports
    entry.state = "starting"
    if not self:mark(userId, entry, "autoStarted") then entry.state = "done"; P.splash(userId, "Lobby"); return end
    if self.players[userId] ~= entry or not P.present(userId) then return end
    P.splash(userId, "FirstMatch", Onboarding.Text.starting)
    self:attempt(userId, entry, 1)
end
function Methods.attempt(self: any, userId: number, entry: any, try: number)
    local P = self.ports
    if self.players[userId] ~= entry or self.closing or not P.present(userId) then return end
    local okBusy, busy = pcall(P.busy, userId)
    if not okBusy or busy then entry.state = "done"; P.splash(userId, "Cleared"); return end -- they chose something else
    local token = {try = try}
    entry.attemptToken = token
    local hooks = {
        phase = function(phase: string)
            if entry.attemptToken == token and phase == "Retrying" then P.splash(userId, "Retrying", Onboarding.Text.retrying) end
        end,
        failed = function(code: any) self:failed(userId, entry, token, code) end,
        started = function() if entry.attemptToken == token then entry.state = "started"; P.splash(userId, "Cleared") end end,
    }
    local ok, started, why = pcall(P.start, userId, hooks)
    if ok and started then if entry.state ~= "started" then entry.state = "teleporting" end; return end
    self:failed(userId, entry, token, if ok then why else started)
end
function Methods.failed(self: any, userId: number, entry: any, token: any, why: any)
    local P = self.ports
    if self.players[userId] ~= entry or entry.attemptToken ~= token or token.failed then return end
    token.failed = true
    self:log(string.format("[OpenFront] Onboarding %d: attempt %d failed (%s)", userId, token.try, tostring(why)))
    if token.try < 2 then
        entry.state = "retrying"
        P.splash(userId, "Retrying", Onboarding.Text.retrying)
        P.spawn(function()
            P.wait(Onboarding.RETRY_SECONDS)
            self:attempt(userId, entry, token.try + 1)
        end)
        return
    end
    entry.state = "done"
    P.splash(userId, "Failed")
    P.notice(userId, Onboarding.Text.failed)
end

-- An earlier invitee (PF043 D9: the tutorial is mandatory): marked once, then the same intro + once-only start.
function Methods.offer(self: any, userId: number, entry: any)
    entry.state = "offering"
    if not self:mark(userId, entry, "offered") then entry.state = "done"; self.ports.splash(userId, "Lobby"); return end
    if self.players[userId] ~= entry or not self.ports.present(userId) then return end
    self:begin(userId, entry)
end
-- /tutorial (Ashton 2026-10-26: "/tutorial should basically gimme the experience like I just loaded in and put me straight
-- into a match"): the first-join flow again (the FirstMatch screen, then the same start and retry), as a new player would
-- get it. Nothing is read or written in the store, so the real record and profile are untouched. The caller checks
-- who may use it (OnboardingService.replay: TutorialAccess only).
function Methods.replay(self: any, userId: number): boolean
    local entry = self.players[userId]
    if not entry or self.closing then return false end
    local state = entry.state
    if state == "starting" or state == "teleporting" or state == "retrying" then return false end -- one already in flight
    entry.state = "starting"
    self.ports.splash(userId, "FirstMatch", Onboarding.Text.starting)
    self:attempt(userId, entry, 1)
    return true
end
-- The intro's Start (OnboardingCommand OfferPlay). There's no "Not now" any more: a decline is ignored.
function Methods.answer(self: any, userId: number, accept: boolean): boolean
    local entry = self.players[userId]
    if not entry or not entry.introOpen or not accept then return false end
    entry.introGo = true
    return true
end

return table.freeze(Onboarding)
