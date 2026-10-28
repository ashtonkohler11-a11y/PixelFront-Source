--!strict
-- Stats v3 (PF - 2; STATS-SYSTEM-DESIGN §v3.1-v3.3, Ashton "Build it" 2026-10-27): one player's in-match skill facts, read
-- from authoritative state only (an observer: it never changes the match, except writing the live band into
-- state.dealer for the dealer to read). LevelFacts owns one per player and samples it with every packet; the work runs
-- once per simulated second (state.elapsed), so pause and game speed don't skew it. facts() goes to PlayerProfile.
--   attacks   sends on players/tribes (wilderness doesn't count): won (took >= WonTiles or finished the target) / lost
--             (ended any other way, except recalled by the player or merged into a new send); kept = left >= KeptShare home
--   low point troops < LowTroops of max while below LowLandOfPeak of peak land, or land < LostLandOfPeak of peak;
--             comeback = land back to the peak it had before the low point
--   live band every Live.CheckSeconds: collapsing / running away, held HoldSeconds to switch, kept KeepSeconds
--   hint      (options.hint: Solo Easy/Medium with Config.Dealer.OpeningHint) a neighbouring nation under attack by a third
--             party while you hold >= Hint.Troops of max troops; once per Hint.Every; retires when you do the move
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Simulation = require(Shared:WaitForChild("Simulation"))
local Economy = require(Shared:WaitForChild("OpenFrontEconomy"))
local NewPlayerGuard = require(Shared:WaitForChild("NewPlayerGuard"))
local SkillFacts = {}; SkillFacts.__index = SkillFacts
local MARKS = { 60, 180, 300, 600 }
local HINT_SECONDS = 20

-- Whether a Solo match shows the opening hint at all: the switch, Easy/Medium, not learned yet, and (Ashton 2026-10-27,
-- "Yes, off at 5") under NewPlayerGuard's match count like the other tips (an unknown count counts as experienced).
function SkillFacts.hintAllowed(enabled: boolean, difficulty: string?, learned: boolean, matches: number?): boolean
    return enabled and (difficulty == "Easy" or difficulty == "Medium") and not learned and NewPlayerGuard.eligible(matches, false)
end

-- options = {hint = boolean (show opening hints), learned = boolean (the move is already done), bandStart, next (from the button)}
function SkillFacts.new(state: any, owner: number, options: any?): any
    options = options or {}
    state.buildingCaptures = state.buildingCaptures or {} -- Structures.captureOwned counts captures into it (observer)
    return setmetatable({ owner = owner, state = state, at = -math.huge, spawnAt = nil, lastAlive = nil, peak = 0, low = 1, lowHit = false,
        lowPeak = 0, comeback = false, tracked = {}, seen = {}, sent = 0, kept = 0, won = 0, lost = 0, cities = 0,
        lastAttacked = -math.huge, lastCityLost = -math.huge, city = nil, prem = {}, revive = false, takeover = false,
        hintOn = options.hint == true, learned = options.learned == true, openingDone = false, hintShown = 0, hintAt = -math.huge,
        hintId = 0, hint = nil, bandStart = options.bandStart, next = options.next == true,
        live = nil, liveSince = -math.huge, pending = nil, pendingSince = -math.huge, checkAt = -math.huge,
        struggle = 0, cruise = 0, marks = {} }, SkillFacts)
end

-- the third party attacking `target` (not me), or nil
local function underThirdParty(state: any, target: number, me: number): number?
    for _, attack in state.attacks do
        if attack.active and attack.targetOwner == target and attack.owner ~= me and attack.owner ~= target then return attack.owner end
    end
    return nil
end
-- a tile of `victim` that touches my land (the hint's pulse)
local function frontTile(state: any, me: number, victim: number): number?
    local width = state.map.width
    for _, tile in state.borders[me].values do
        if tile == 0 then continue end
        local x = (tile - 1) % width
        for _, n in { tile - width, tile + width, if x > 0 then tile - 1 else 0, if x < width - 1 then tile + 1 else 0 } do
            if n > 0 and n <= #state.owners and state.owners[n] == victim then return n end
        end
    end
    return nil
end
local function largestOther(state: any, me: number): number
    local best = 0
    for index, player in state.players do
        if index ~= me and player.playerType ~= "Bot" then best = math.max(best, state.counts[index] or 0) end
    end
    return best
end

function SkillFacts.sample(self: any, state: any)
    if state.phase ~= "Playing" and state.phase ~= "Won" and state.phase ~= "Lost" then return end
    local now = tonumber(state.elapsed) or 0
    if now - self.at < 1 then return end
    self.at = now
    local me = self.owner
    local count = state.counts[me] or 0
    if count <= 0 then self:finishAttacks(state); return end
    self.spawnAt = self.spawnAt or now
    self.lastAlive = now
    local since = now - self.spawnAt
    for _, mark in MARKS do if since >= mark and self.marks[mark] == nil then self.marks[mark] = count end end
    local cap = math.max(1, Simulation.capacity(state, me))
    local share = (state.troops[me] or 0) / cap
    if since >= 60 then self.low = math.min(self.low, share) end
    -- the low point and the comeback (land back to where it peaked before)
    local S = Config.Skill
    if not self.lowHit and since >= 60 and self.peak >= 100
        and ((share < S.LowTroops and count < self.peak * S.LowLandOfPeak) or count < self.peak * S.LostLandOfPeak) then
        self.lowHit, self.lowPeak = true, self.peak
    elseif self.lowHit and not self.comeback and count >= self.lowPeak then
        self.comeback = true
    end
    self.peak = math.max(self.peak, count)
    -- my sends on players and tribes
    for _, attack in state.attacks do
        if attack.owner == me and attack.targetOwner ~= 0 and not self.seen[attack] then
            self.seen[attack] = true
            table.insert(self.tracked, attack)
            self.sent += 1
            if type(attack.sendShare) == "number" and attack.sendShare <= 1 - S.KeptShare then self.kept += 1 end
            if underThirdParty(state, attack.targetOwner, me) ~= nil then self.openingDone = true; self.hint = nil end
        elseif attack.active and attack.targetOwner == me and attack.owner ~= me then
            self.lastAttacked = now
        end
    end
    self:finishAttacks(state)
    -- cities: the first one, and losing one
    local cities = #Economy.ownedCities(state, me)
    if cities < self.cities then self.lastCityLost = now end
    self.cities = cities
    if self.city == nil and (state.cityConstructed and state.cityConstructed[me] or 0) > 0 then self.city = since end
    -- Arsenal items used this match (owned and built / launched at least once)
    local p = state.premium
    if p and p.owned[me] then
        for id in p.owned[me] do
            if self.prem[id] == nil then self.prem[id] = false end
            if not self.prem[id] and p.counts[me] and (p.counts[me][id] or 0) > 0 then self.prem[id] = true end
        end
    end
    local revive = state.revive and state.revive[me]
    if revive then self.revive = true; if revive.takeover or revive.kind == "takeover" then self.takeover = true end end
    self:liveBand(state, now, count, share)
    self:openingHint(state, now, share)
end

function SkillFacts.finishAttacks(self: any, state: any)
    local keep = {}
    for _, attack in self.tracked do
        if attack.active then table.insert(keep, attack); continue end
        if attack.merged or attack.retreated then continue end -- merged into a newer send, or recalled by the player
        local target = attack.targetOwner
        if (attack.taken or 0) >= Config.Skill.WonTiles or (state.counts[target] or 0) == 0 then self.won += 1 else self.lost += 1 end
    end
    self.tracked = keep
end

function SkillFacts.liveBand(self: any, state: any, now: number, count: number, share: number)
    local L = Config.Skill.Live
    if now - self.checkAt < L.CheckSeconds then return end
    local step = if self.checkAt == -math.huge then 0 else math.min(now - self.checkAt, L.CheckSeconds * 2)
    self.checkAt = now
    if self.live == "Struggling" then self.struggle += step elseif self.live == "Cruising" then self.cruise += step end
    local candidate = nil
    if (share < L.CollapseTroops and count <= self.peak * L.CollapseLand) or (now - self.lastCityLost <= 60 and share < L.CityTroops) then
        candidate = "Struggling"
    elseif count >= L.RunAwayRatio * math.max(1, largestOther(state, self.owner)) and share >= L.RunAwayTroops then
        candidate = "Cruising"
    end
    if candidate ~= self.pending then self.pending, self.pendingSince = candidate, now end
    if self.pending ~= self.live and now - self.pendingSince >= L.HoldSeconds and now - self.liveSince >= L.KeepSeconds then
        self.live, self.liveSince = self.pending, now
    end
    local dealer = state.dealer
    if dealer and dealer.human == self.owner then dealer.live = self.live end
end

function SkillFacts.openingHint(self: any, state: any, now: number, share: number)
    if self.hint and now - self.hint.at >= HINT_SECONDS then self.hint = nil end
    if not self.hintOn or self.learned or self.openingDone or self.hint then return end
    local H = Config.Dealer.Hint
    if share < H.Troops or now - self.hintAt < H.Every then return end
    for _, other in Simulation.nearby(state, self.owner) do
        if other <= 0 or state.players[other].playerType ~= "Nation" or (state.nationApi and state.nationApi.friendly(self.owner, other)) then continue end
        local by = underThirdParty(state, other, self.owner)
        local tile = if by then frontTile(state, self.owner, other) else nil
        if by and tile then
            self.hintId += 1; self.hintShown += 1; self.hintAt = now
            self.hint = { id = self.hintId, tick = state.ticks, victim = other, by = by, tile = tile, name = state.players[other].name, at = now }
            return
        end
    end
end

-- The packet field PF - 1 shows (once per tick): {tick, victim, by, tile, name, id} or nil
function SkillFacts.hintPacket(self: any): any?
    local hint = self.hint
    return if hint then { tick = hint.tick, victim = hint.victim, by = hint.by, tile = hint.tile, name = hint.name, id = hint.id } else nil
end

-- the quit point for a player leaving mid-match: when (choosing / minutes since spawn) and the last thing that happened
function SkillFacts.quitPoint(self: any, state: any): (string, string)
    local now = tonumber(state.elapsed) or 0
    local when = if state.phase == "Choosing" or not self.spawnAt then "choosing" else (function()
        local minutes = (now - self.spawnAt) / 60
        return if minutes < 1 then "lt1" elseif minutes < 3 then "1to3" elseif minutes < 10 then "3to10" else "gt10"
    end)()
    local last = if now - self.lastAttacked <= 30 then "attacked" elseif now - self.lastCityLost <= 60 then "lostCity" else "nothing"
    return when, last
end

function SkillFacts.facts(self: any, given: any?): any
    local state = given or self.state
    self:finishAttacks(state)
    local me = self.owner
    local alive = if self.spawnAt and self.lastAlive then self.lastAlive - self.spawnAt else 0
    local earned = state.goldEarned and state.goldEarned[me] or 0
    local captures = state.buildingCaptures and state.buildingCaptures[me]
    local dealt = nil
    if state.dealer and state.dealer.human == me and state.dealer.log then dealt = table.clone(state.dealer.log) end
    local when, last = self:quitPoint(state)
    local prem = nil
    for id, used in self.prem do prem = prem or {}; prem[id] = used end
    return { alive = math.floor(alive), t1 = self.marks[60], t3 = self.marks[180], t5 = self.marks[300], t10 = self.marks[600],
        sent = self.sent, won = self.won, lost = self.lost, kept = self.kept, low = if self.spawnAt then self.low else nil,
        lowHit = self.lowHit, comeback = self.comeback, cap = captures and captures.total or 0, capO = captures and captures.opening or 0,
        gpm = if alive > 0 then math.floor(earned / math.max(1, alive / 60)) else 0, city = if self.city then math.floor(self.city) else nil,
        live = { struggle = math.floor(self.struggle), cruise = math.floor(self.cruise) }, bandStart = self.bandStart, next = self.next,
        dealt = dealt, revive = self.revive, takeover = self.takeover, hintShown = self.hintShown, openingDone = self.openingDone,
        prem = prem, quit = when, last = last }
end

return table.freeze(SkillFacts)
