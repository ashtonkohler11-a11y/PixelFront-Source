--!strict
-- Stats v3 opportunity dealer (PF - 2; STATS-SYSTEM-DESIGN §v3.3, Ashton "Build it" 2026-10-27). Solo only, cohort A only,
-- and only while Config.Dealer.Enabled (OFF for the 2-week record-only phase): MatchService sets state.dealer at the start
-- of such a match; nothing here runs without it. It never hands out land, troops or gold and never aims a nation at the
-- human; it changes what nations do so openings appear:
--   Struggling  war next door (two nations beside you fight each other), attention down (opportunist strategies look past
--               you while another target exists), an ally offer (a bordering nation asks you to ally)
--   Cruising    smarter nations (strike while your troops are out attacking; Medium+ also when your land is weakly held);
--               the -30 s peace is applied by MatchService at the start
-- The band is the pre-match one, or the live one SkillFacts writes (dealer.live). One dealt event per GapSeconds across
-- all levers; every dealt event is counted in dealer.log (the player record and the daily totals read it).
local Config = require(script.Parent.Config)
local Random = require(script.Parent.OpenFrontRandom)
local Dealer = {}

function Dealer.new(human: number, band: string, difficulty: string, seed: number): any
    return { human = human, band = band, difficulty = difficulty, live = nil, random = Random.new(seed),
        last = { any = -math.huge, war = -math.huge, ally = -math.huge }, allies = 0, log = {}, at = -math.huge, attentionAt = -math.huge }
end
function Dealer.band(d: any): string return d.live or d.band end
local function now(state: any): number return tonumber(state.elapsed) or 0 end
local function note(d: any, lever: string) d.log[lever] = (d.log[lever] or 0) + 1 end
local function roll(d: any): number return Random.int(d.random, 0, 9999) / 10000 end
local function alive(state: any, owner: number): boolean return (state.counts[owner] or 0) > 0 end
local function isNation(state: any, owner: number): boolean
    local nation = state.nations and state.nations[owner]
    return owner > 0 and state.players[owner] ~= nil and state.players[owner].playerType == "Nation" and nation ~= nil and nation.enabled and nation.started == true
end
local function fighting(state: any, a: number, b: number): boolean
    for _, attack in state.attacks do
        if attack.active and ((attack.owner == a and attack.targetOwner == b) or (attack.owner == b and attack.targetOwner == a)) then return true end
    end
    return false
end
local function nationNeighbours(state: any, api: any, human: number): { number }
    local out = {}
    for _, other in api.nearby(human) do
        if isNation(state, other) and alive(state, other) and api.shares(human, other) then table.insert(out, other) end
    end
    return out
end

-- war next door: the stronger of two nations that both border the human (and each other) attacks the weaker
local function war(state: any, api: any, d: any): boolean
    local around = nationNeighbours(state, api, d.human)
    local options = {}
    for i = 1, #around do for j = i + 1, #around do
        local a, b = around[i], around[j]
        if api.shares(a, b) and not api.friendly(a, b) and not fighting(state, a, b) then table.insert(options, { a, b }) end
    end end
    if #options == 0 then return false end
    local pick = options[Random.int(d.random, 1, #options)]
    local attacker, target = pick[1], pick[2]
    if state.troops[target] > state.troops[attacker] then attacker, target = target, attacker end
    api.updateRelation(attacker, target, -100); api.updateRelation(target, attacker, -100)
    return api.queue(attacker, target, math.floor(state.troops[attacker] * Config.Dealer.War.Share)) == true
end

-- an ally offer: a bordering nation not at war with the human (preferring one under attack by someone who also attacks
-- the human) sends a normal alliance request
local function ally(state: any, api: any, d: any): boolean
    local human = d.human
    local attackers = {}
    for _, attack in state.attacks do if attack.active and attack.targetOwner == human then attackers[attack.owner] = true end end
    local best, shared = nil, false
    for _, other in nationNeighbours(state, api, human) do
        if api.friendly(other, human) or fighting(state, other, human) or attackers[other] or not api.canSendAlliance(other, human) then continue end
        local common = false
        for _, attack in state.attacks do if attack.active and attack.targetOwner == other and attackers[attack.owner] then common = true; break end end
        if not best or (common and not shared) then best, shared = other, common end
    end
    if not best then return false end
    api.queueAlliance(best, human)
    return true
end

-- once per simulated second (Simulation.step calls it each tick while state.dealer is set): the Struggling levers
function Dealer.tick(state: any, api: any)
    local d = state.dealer
    if not d or state.phase ~= "Playing" then return end
    local t = now(state)
    if t - d.at < 1 then return end
    d.at = t
    if not alive(state, d.human) or Dealer.band(d) ~= "Struggling" or t - d.last.any < Config.Dealer.GapSeconds then return end
    local every = Config.Dealer.War[d.difficulty] or Config.Dealer.War.Medium
    local A = Config.Dealer.Ally
    local cap = if d.difficulty == "Impossible" then A.Impossible else A.PerMatch
    local function tryWar(): boolean
        if t - d.last.war >= every and war(state, api, d) then d.last.war, d.last.any, d.lastLever = t, t, "war"; note(d, "war"); return true end
        return false
    end
    local function tryAlly(): boolean
        if d.allies < cap and t - d.last.ally >= A.Every and ally(state, api, d) then
            d.allies += 1; d.last.ally, d.last.any, d.lastLever = t, t, "ally"; note(d, "ally"); return true
        end
        return false
    end
    -- the two alternate when both are ready (war first)
    if d.lastLever == "war" then if not tryAlly() then tryWar() end elseif not tryWar() then tryAlly() end
end

-- NationAI, after its enemies list: a struggling human drops out of this decision's opportunist targets (weakest,
-- veryWeak, juicy, victim) with chance 1 - Attention[difficulty], when the nation has another enemy to look at.
function Dealer.attention(state: any, nation: number, enemies: { number })
    local d = state.dealer
    if not d or Dealer.band(d) ~= "Struggling" or #enemies < 2 then return end
    local index = table.find(enemies, d.human)
    if not index then return end
    local weight = Config.Dealer.Attention[d.difficulty] or Config.Dealer.Attention.Medium
    if roll(d) < weight then return end
    table.remove(enemies, index)
    local t = now(state)
    if t - d.attentionAt >= 30 then d.attentionAt = t; note(d, "attention") end -- counted at most twice a minute
end

-- NationAI, before its strategies: a cruising human bordering this nation gets struck while >= Smart.TroopsOut of its
-- troops are out attacking (Medium+ also when its land is held thinner than this nation's other enemies). Returns the
-- target for the nation's own send (its normal amount, mercy and difficulty rules), or nil.
function Dealer.smart(state: any, nation: number, enemies: { number }): number?
    local d = state.dealer
    if not d or Dealer.band(d) ~= "Cruising" or not table.find(enemies, d.human) then return nil end
    local t = now(state)
    if t - d.last.any < Config.Dealer.GapSeconds then return nil end
    local human = d.human
    local out = 0
    for _, attack in state.attacks do if attack.active and attack.owner == human then out += attack.budget end end
    local total = out + state.troops[human]
    local strike = total > 0 and out / total >= Config.Dealer.Smart.TroopsOut
    if not strike and d.difficulty ~= "Easy" and #enemies >= 2 then
        local mine = state.troops[human] / math.max(1, state.counts[human])
        local thinner = true
        for _, other in enemies do
            if other ~= human and state.troops[other] / math.max(1, state.counts[other]) < mine then thinner = false; break end
        end
        strike = thinner
    end
    return if strike then human else nil
end
-- NationAI: the smart strike went out
function Dealer.smartSent(state: any)
    local d = state.dealer
    if not d then return end
    d.last.any = now(state)
    note(d, "smart")
end

return table.freeze(Dealer)
