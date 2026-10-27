--!strict
--!native
-- OpenFrontIO93a136a1 NationExecution + every source AiAttackBehavior strategy.
-- Diplomacy, emoji and enabled mixed-structure decisions retain source ordering.
-- Isolated source decisions are checked independently; no full replay claim.
local Random = require(script.Parent.OpenFrontRandom)
local AttackMath = require(script.Parent.OpenFrontNationAttackMath)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local NationAI = {}
local function friendly(owner: number,target: number,api: any): boolean
    return if api.friendly then api.friendly(owner,target) else owner==target
end
local function hasStructures(state: any,owner: number,api: any): boolean
    if api.hasStructures then return api.hasStructures(owner) end
    for _,name in {"cities","ports","factories","defensePosts","missileSilos","samLaunchers"} do
        for _,unit in state[name] or {} do if unit.owner==owner and unit.active~=false then return true end end
    end
    return false
end
function NationAI.shouldAttack(state: any,owner: number,target: number,api: any): boolean
    if target==0 or state.players[target].playerType~="Human"
        or (api.isTraitor and api.isTraitor(target)) or state.players[target].isTraitor==true
        or state.players[owner].playerType=="Bot" or state.gameConfig and state.gameConfig.playerTeams=="Humans Vs Nations" then return true end
    local difficulty=AttackMath.difficulty(state)
    if difficulty=="Easy" then return Random.int(state.nations[owner].random,0,4)==0 end
    if difficulty=="Medium" then return Random.int(state.nations[owner].random,0,4)~=0 end
    return true
end

function NationAI.tick(state: any, owner: number, api: any)
    local nation = state.nations[owner]
    if not nation or not nation.enabled or state.counts[owner] == 0 then return end
    if not nation.started then
        nation.started = true
        -- initializeBehaviors creates NationNukeBehavior, consuming this draw
        -- even before a weapon exists (isHydroNation field initializer).
        nation.isHydroNation = Random.int(nation.random, 0, 3) == 0
        api.queue(owner, 0, state.troops[owner] / 2)
        return
    end
    if state.ticks % nation.attackRate ~= nation.attackTick then
        local offset = state.ticks % nation.attackRate
        local oneThird = (nation.attackTick + math.floor(nation.attackRate / 3)) % nation.attackRate
        local twoThirds = (nation.attackTick + math.floor(nation.attackRate * 2 / 3)) % nation.attackRate
        if api.structures and (offset == oneThird or offset == twoThirds) then api.structures(owner) end
        return
    end
    if api.structures then api.structures(owner) end
    if api.warship then api.warship(owner) end
    if api.beforeAttack then api.beforeAttack(owner) end
    local capacity = api.capacity(owner)
    local function send(target: number, force: boolean?): boolean
        if not force and not NationAI.shouldAttack(state,owner,target,api) then return false end
        if api.mercy and api.mercy(owner,target) then return false end -- PF043 tutorial-only nation mercy (Simulation.mercyActor)
        if target == 0 and not api.neutral(owner) then return if api.neutralBoat then api.neutralBoat(owner) else false end
        if target > 0 and not api.shares(owner, target) then return if api.boat then api.boat(owner, target) else false end
        local amount=AttackMath.calculateTroops(state,owner,target,false,api)
        if amount==nil then return false end
        return api.queue(owner,target,amount)
    end
    local nearby = api.nearby(owner)
    -- Source nearby omits unowned fallout. Fresh wilderness can expand before
    -- reserve checks; reclaiming fallout is a later Easy attack strategy.
    local nonFalloutNeutral = if api.nonFalloutNeutral then api.nonFalloutNeutral(owner) else api.neutral(owner)
    if (nonFalloutNeutral or table.find(nearby, 0)) and send(0) then return end
    local neighbors,insertion={},{}
    for _, other in nearby do
        if other > 0 then table.insert(neighbors, other) insertion[other] = #neighbors end
    end
    table.sort(neighbors, function(a, b)
        return if state.troops[a] == state.troops[b] then insertion[a] < insertion[b] else state.troops[a] < state.troops[b]
    end)
    local enemies,friends={},{}
    for _,other in neighbors do table.insert(if friendly(owner,other,api) then friends else enemies,other) end
    if #enemies == 0 then
        if Random.int(nation.random, 0, 5) == 0 and api.randomBoat then api.randomBoat(owner, enemies) end
    elseif Random.int(nation.random, 0, 10) == 0 then
        if api.randomBoat then api.randomBoat(owner, enemies) end
        return
    end
    if #enemies>0 and api.allianceRequests then api.allianceRequests(owner,enemies) end
    local function attackBots(): boolean
        local bots,order={},{}
        for _,other in nearby do
            if other>0 and state.players[other].playerType=="Bot" and not friendly(owner,other,api) then
                table.insert(bots,other);order[other]=#bots
            end
        end
        if #bots==0 then return false end
        nation.botAttackTroopsSent=0
        table.sort(bots,function(a,b)
            local aStructures,bStructures=hasStructures(state,a,api),hasStructures(state,b,api)
            if aStructures~=bStructures then return aStructures end
            local da,db=state.troops[a]/state.counts[a],state.troops[b]/state.counts[b]
            return if da==db then order[a]<order[b] else da<db
        end)
        local difficulty=AttackMath.difficulty(state)
        local limit=if difficulty=="Easy" then 1 elseif difficulty=="Medium" then (if Random.int(nation.random,0,2)==0 then 1 else 2) elseif difficulty=="Hard" then 3 else 100
        for index=1,math.min(#bots,limit) do send(bots[index]) end
        return nation.botAttackTroopsSent>0
    end
    for _,other in nearby do
        if other>0 and state.players[other].playerType=="Bot" and not friendly(owner,other,api)
            and hasStructures(state,other,api) then if attackBots() then return end;break end
    end
    if state.troops[owner] / capacity < nation.reserveRatio then return end
    if state.troops[owner] / capacity < nation.triggerRatio and Random.int(nation.random, 0, 10) ~= 0 then return end
    local strategies={}
    strategies.nuked=function() return api.fallout and api.fallout(owner) and send(0) or false end
    strategies.bots=attackBots
    strategies.retaliate=function()
        local attacker,largest=nil,0
        -- (attack.forgiven: the first match's step-4 attack; the nation blunts it and forgets it, never retaliates)
        for _,attack in state.attacks do if attack.active and not attack.forgiven and attack.targetOwner==owner and not friendly(owner,attack.owner,api)
            and state.players[attack.owner].playerType~="Bot" and attack.budget>largest then attacker,largest=attack.owner,attack.budget end end
        return if attacker then send(attacker,true) else false
    end
    strategies.assist=function()
      if api.disabledAlliances~=true and api.allies and api.targets and api.relation then
        for _,ally in api.allies(owner) do
            local targets=api.targets(ally)
            if #targets==0 then continue end
            if api.relation(owner,ally)<3 then
                if api.assistEmoji then api.assistEmoji(owner,ally,"LowRelation") end
                continue
            end
            for _,target in targets do
                if target==owner then if api.assistEmoji then api.assistEmoji(owner,ally,"TargetMe") end;continue end
                if friendly(owner,target,api) then if api.assistEmoji then api.assistEmoji(owner,ally,"TargetAlly") end;continue end
                if not send(target) then continue end
                api.updateRelation(owner,ally,-20)
                if api.assistEmoji then api.assistEmoji(owner,ally,"Accept") end
                return true
            end
        end
      end
      return false
    end
    strategies.betray=function()
      if api.disabledAlliances~=true and api.betray then
        local candidates={};for _,friend in friends do if api.isAllied(owner,friend) then table.insert(candidates,friend) end end
        local juiciest=AttackMath.juiciest(state,candidates,api)
        for _,friend in friends do
            if api.betray(owner,friend,juiciest,friends,enemies) then return send(friend,true) end
        end
      end
      return false
    end
    strategies.hated=function()
      if api.relations then
        for _,relation in api.relations(owner) do
            local other=relation.owner
            if relation.relation==0 and not friendly(owner,other,api) and (not AttackMath.isFFA(state) or state.troops[other]<=state.troops[owner]*3) then
                return send(other)
            end
        end
      end
      return false
    end
    -- PF043 no pile-on (Config.Combat.NationPileOn=false; real matches only): the opportunist strategies (weakest,
    -- veryWeak, juicy, victim) skip a human another nation is already attacking. Retaliate, hated, assist, betray,
    -- traitor and afk are unchanged, so the nation you hit still answers.
    local noPileOn=state.gameConfig~=nil and GameConfig.forState(state).Combat.NationPileOn==false
    local function piledOn(target: number): boolean
        if not noPileOn or state.players[target].playerType~="Human" then return false end
        for _,attack in state.attacks do
            if attack.active and attack.targetOwner==target and attack.owner~=owner and state.players[attack.owner].playerType=="Nation" then return true end
        end
        return false
    end
    strategies.weakest=function()
        local weakest=nil;for _,target in enemies do if not piledOn(target) then weakest=target;break end end
        return if weakest and (not AttackMath.isFFA(state) or state.troops[weakest]<state.troops[owner]) then send(weakest) else false
    end
    strategies.traitor=function()
        if api.disabledAlliances==true then return false end
        for _,target in enemies do if api.isTraitor and api.isTraitor(target)
            and (not AttackMath.isFFA(state) or state.troops[target]<state.troops[owner]*1.2) then return send(target) end end
        return false
    end
    strategies.afk=function()
        for _,target in enemies do if (state.players[target].isDisconnected or state.players[target].disconnected)
            and (not AttackMath.isFFA(state) or state.troops[target]<state.troops[owner]*3) then return send(target) end end
        return false
    end
    strategies.veryWeak=function()
        for _,target in enemies do if not piledOn(target) and state.troops[target]<api.capacity(target)*.15
            and (not AttackMath.isFFA(state) or state.troops[target]<state.troops[owner]*1.2) then return send(target) end end
        return false
    end
    strategies.juicy=function()
        local candidates={};for _,target in enemies do if not piledOn(target) and state.troops[target]<=state.troops[owner]*.75 then table.insert(candidates,target) end end
        local target=AttackMath.juiciest(state,candidates,api)
        return if target then send(target) else false
    end
    strategies.victim=function()
        for _,target in enemies do
            if piledOn(target) or AttackMath.isFFA(state) and state.troops[target]>state.troops[owner]*1.2 then continue end
            local _,incoming=AttackMath.incoming(state,target)
            if incoming>state.troops[target]*.5 then return send(target) end
        end
        return false
    end
    strategies.island=function()
        if #enemies==0 and api.nearestIsland then local target=api.nearestIsland(owner);return if target then send(target) else false end
        return false
    end
    strategies.donate=function()
        local config=state.gameConfig
        if not config or config.gameMode~="Team" or config.gameType=="Public" or config.donateTroops==false or state.winner~=nil then return false end
        local difficulty=AttackMath.difficulty(state)
        if difficulty=="Easy" or difficulty=="Medium" and Random.int(nation.random,0,4)~=0 or difficulty=="Hard" and Random.int(nation.random,0,2)~=0 then return false end
        local teammates,order={},{}
        for _,target in state.playerOrder do if state.counts[target]>0 and api.sameTeam(owner,target) then
            local fighting=false;for _,attack in state.attacks do if attack.active and (attack.owner==target or attack.targetOwner==target) then fighting=true;break end end
            if fighting then table.insert(teammates,target);order[target]=#teammates end
        end end
        table.sort(teammates,function(a,b)
            local x,y=state.troops[a]/math.max(api.capacity(a),1),state.troops[b]/math.max(api.capacity(b),1)
            return if x==y then order[a]<order[b] else x<y
        end)
        for _,target in teammates do if api.canDonateTroops and api.canDonateTroops(owner,target) then
            local amount=state.troops[owner]-capacity*nation.reserveRatio
            if amount<1 then return false end
            if api.queueDonation then api.queueDonation(owner,target,amount);return true end
            return false
        end end
        return false
    end
    local orders={Easy={"nuked","bots","retaliate","assist","betray","hated","weakest"},
        Medium={"bots","nuked","retaliate","assist","betray","hated","afk","traitor","weakest","island","donate"},
        Hard={"bots","retaliate","assist","betray","nuked","traitor","afk","hated","veryWeak","juicy","victim","weakest","island","donate"},
        Impossible={"retaliate","bots","veryWeak","betray","assist","victim","traitor","juicy","afk","nuked","hated","weakest","island","donate"}}
    for _,strategy in orders[AttackMath.difficulty(state)] do if strategies[strategy]() then return end end
end

return table.freeze(NationAI)
