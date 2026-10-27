--!strict
--!native
-- TribeExecution + AiAttackBehavior.attackRandomTarget, OpenFrontIO 93a136a1.
local Random=require(script.Parent.OpenFrontRandom)
local AttackMath=require(script.Parent.OpenFrontNationAttackMath)
local AI={}
local function chance(random: any,odds: number): boolean return Random.int(random,0,odds)==0 end
function AI.tick(state: any,owner: number,api: any)
    local bot=state.bots[owner]
    if not bot or not bot.enabled or state.counts[owner]<=0 or state.ticks%bot.attackRate~=bot.attackTick then return end
    local function send(target: number): boolean
        if api.mercy and api.mercy(owner,target) then return false end -- PF043 tribe mercy (Simulation.mercyShield/mercyBlocksWild)
        -- Source shouldAttack always allows all targets for a Bot.
        if target==0 and not api.neutral(owner) then return if api.neutralBoat then api.neutralBoat(owner) else false end
        if target>0 and not api.shares(owner,target) then return if api.boat then api.boat(owner,target) else false end
        local amount=AttackMath.calculateTroops(state,owner,target,false,api)
        return if amount then api.queue(owner,target,amount) else false
    end
    if not bot.started then bot.started=true;send(0);return end
    if api.incomingRequests then for _,req in api.incomingRequests(owner) do api.acceptRequest(req) end end
    if api.alliances then
        for _,alliance in api.alliances(owner) do
            if alliance.extensionRequestedRequestor~=alliance.extensionRequestedRecipient then
                api.queueExtension(owner,if alliance.requestor==owner then alliance.recipient else alliance.requestor)
            end
        end
    end
    if api.canDelete and api.canDelete(owner) then
        for _,unit in api.structuresFor(owner) do
            if unit.deletionMarkedTick==nil then api.deleteStructure(owner,unit);break end
        end
    end
    local function friendly(target: number): boolean return if api.friendly then api.friendly(owner,target) else target==owner end
    local function traitor(): number?
        if not api.isTraitor or api.disabledAlliances==true then return nil end
        local targets={}
        for _,other in api.nearby(owner) do if other>0 and not friendly(other) and api.isTraitor(other) then table.insert(targets,other) end end
        return if #targets>0 then targets[Random.int(bot.random,0,#targets)+1] else nil
    end
    local firstTraitor=traitor()
    if firstTraitor and chance(bot.random,if friendly(firstTraitor) then 6 else 3) then
        if api.isAllied and api.isAllied(owner,firstTraitor) then api.breakAlliance(owner,firstTraitor) end
        if send(firstTraitor) then return end
    end
    if bot.neighborsTerraNullius then
        if table.find(api.nearby(owner),0) then if send(0) then return end
        else bot.neighborsTerraNullius=false end
    end
    if state.troops[owner]/api.capacity(owner)<bot.triggerRatio then return end
    local attacker,largest=nil,0
    for _,attack in state.attacks do
        if attack.active and attack.targetOwner==owner and not friendly(attack.owner) and attack.budget>largest then attacker,largest=attack.owner,attack.budget end
    end
    if attacker and send(attacker) then return end
    local secondTraitor=traitor()
    if secondTraitor and chance(bot.random,3) and send(secondTraitor) then return end
    local nearby=api.nearby(owner)
    for index=#nearby,2,-1 do local other=Random.int(bot.random,0,index)+1;nearby[index],nearby[other]=nearby[other],nearby[index] end
    for _,target in nearby do
        if target==0 or friendly(target) then continue end
        local kind=state.players[target].playerType
        if (kind=="Nation" or kind=="Human") and chance(bot.random,2) then continue end
        if send(target) then return end
    end
end
return table.freeze(AI)
