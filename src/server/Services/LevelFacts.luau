--!strict
-- PF023 (PF - 2): one player's match facts, from authoritative server state only. The Solo MatchService and the public
-- PublicMatchRuntime feed it through MatchRewardsService.api (injected, so neither requires this module). Levels are gone
-- (2026-10-26): the facts drive the match Cobalt (MatchCobalt), stats, dailies and ranked; no XP is counted.
-- Active time is real seconds alive with a gameplay command in the last 120 s (Solo pause and AFK earn nothing);
-- peak land is sampled; defeats come from the conquest events that name this player; the runtime sets the end
-- facts (win, placement). Pure: the clock is passed in.
local Facts = {}; Facts.__index = Facts
Facts.ACTIVE_WINDOW = 120
-- Commands that are playing the match (chat, emoji, pause, speed and the meta commands don't count)
local GAMEPLAY = {Spawn = true, Attack = true, Boat = true, BoatRetreat = true, MoveWarship = true, Cancel = true, Retaliate = true,
    AllianceRequest = true, AllianceReject = true, AllianceExtend = true, BreakAlliance = true, Embargo = true, EmbargoAll = true,
    DonateGold = true, DonateTroops = true, Target = true, Build = true, Upgrade = true, Delete = true}
function Facts.isGameplay(kind: any): boolean return type(kind) == "string" and GAMEPLAY[kind] == true end

-- options: {public = matchmaking (player defeats and placement pay), solo = Solo (difficulty scales the win)}
function Facts.new(state: any, config: any?, owner: number, options: any?): any
    options = options or {}
    local cfg = config or {}
    local opponents = 0
    for index, player in state.players or {} do
        if index ~= owner and (player.playerType == "Nation" or player.playerType == "Human") then opponents += 1 end
    end
    local types = {}
    for _, player in state.players or {} do if player.id ~= nil then types[player.id] = player.playerType end end
    local me = state.players and state.players[owner]
    return setmetatable({owner = owner, me = me and me.id, types = types, public = options.public == true,
        sandbox = cfg.infiniteGold == true or cfg.infiniteTroops == true or cfg.instantBuild == true,
        difficulty = if options.solo then cfg.difficulty else nil, opponents = opponents,
        activeSeconds = 0, lastAction = -math.huge, lastSample = nil, peak = 0, tribes = 0, nations = 0, players = 0,
        cursor = 0}, Facts)
end
function Facts.command(self: any, now: number) self.lastAction = now end
-- Called with every outgoing packet (~10/s): accrues active time, peak land and new defeats.
function Facts.sample(self: any, state: any, now: number, paused: boolean?)
    local alive = (state.counts and state.counts[self.owner] or 0) > 0
    if self.lastSample and not paused and state.phase == "Playing" and alive and now - self.lastAction <= Facts.ACTIVE_WINDOW then
        self.activeSeconds += math.clamp(now - self.lastSample, 0, 5) -- a server hitch never mints minutes
    end
    self.lastSample = now
    local land = state.map and state.map.landCount
    if type(land) == "number" and land > 0 and alive then
        local pct = state.counts[self.owner] * 100 / land
        if pct > self.peak then self.peak = pct end
    end
    for _, event in state.conquestEvents or {} do
        if type(event.id) == "number" and event.id > self.cursor then
            self.cursor = event.id
            if self.me ~= nil and event.conquerorId == self.me then
                local kind = self.types[event.conqueredId]
                if kind == nil then -- a player added after the start: look once
                    for _, player in state.players or {} do if player.id == event.conqueredId then kind = player.playerType; self.types[player.id] = kind end end
                end
                local source = if kind == "Bot" then "tribes" elseif kind == "Nation" then "nations" elseif kind == "Human" then "players" else nil
                if source then self[source] += 1 end
            end
        end
    end
end
-- the end facts (MatchCobalt.score, stats, dailies); extra = {won, placement, topHalf} at the end
function Facts.facts(self: any, extra: any?): any
    extra = extra or {}
    return {activeMinutes = self.activeSeconds // 60, peakLandPct = self.peak, tribes = self.tribes, nations = self.nations,
        players = self.players, public = self.public, sandbox = self.sandbox, difficulty = self.difficulty, opponents = self.opponents,
        won = extra.won == true, placement = extra.placement, topHalf = extra.topHalf == true}
end
-- Rank among the humans and nations: the winner is 1st; a survivor counts everyone alive with more land; an
-- eliminated player is behind everyone still alive. "of" is everyone who started. (Placement Cobalt uses it in public
-- matchmaking; Solo shows it on the result card only.)
function Facts.rank(self: any, state: any, won: boolean): (number, number)
    local owner = self.owner
    local mine, alive, better = state.counts[owner] or 0, 0, 0
    for index, player in state.players do
        if index ~= owner and player.playerType ~= "Bot" and (state.counts[index] or 0) > 0 then
            alive += 1
            if (state.counts[index] or 0) > mine then better += 1 end
        end
    end
    local rank = if won then 1 elseif mine > 0 then better + 1 else alive + 1
    return rank, self.opponents + 1
end
return table.freeze(Facts)
