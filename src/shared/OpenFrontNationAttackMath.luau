--!strict
--!native
-- AiAttackBehavior/NationUtils, OpenFrontIO93a136a1; source-safe per-match queries.
local Config=require(script.Parent.Config)
local AI={}
function AI.difficulty(state: any): string return (state.gameConfig and state.gameConfig.difficulty) or Config.Match.Difficulty end
function AI.isFFA(state: any): boolean return not state.gameConfig or state.gameConfig.gameMode~="Team" end
local function friendly(api: any,a: number,b: number): boolean return if api.friendly then api.friendly(a,b) else a==b end
function AI.incoming(state: any,owner: number): (number,number)
    local count,total=0,0
    for _,attack in state.attacks or {} do if attack.active and attack.targetOwner==owner then count+=1;total+=attack.budget end end
    return count,total
end
function AI.troopSendCap(state: any,owner: number,api: any): number
    local difficulty=AI.difficulty(state)
    if state.players[owner].playerType=="Bot" or not AI.isFFA(state) or difficulty~="Hard" and difficulty~="Impossible" then return math.huge end
    local maximum=0
    for _,target in api.nearby(owner) do
        if target>0 and not friendly(api,owner,target) and state.players[target].playerType~="Bot" then maximum=math.max(maximum,state.troops[target]) end
    end
    local cap=if maximum==0 then math.huge else math.max(0,state.troops[owner]-math.ceil(maximum*(if difficulty=="Hard" then .75 else .9)))
    local count,incoming=AI.incoming(state,owner)
    return if count>0 then math.max(cap,incoming) else cap
end
function AI.expansionCap(state: any,owner: number,api: any): number
    local cap=AI.troopSendCap(state,owner,api)
    return if cap>0 then cap else math.ceil(state.troops[owner]*.05)
end
function AI.tooWeak(state: any,owner: number,target: number,amount: number): boolean
    local difficulty=AI.difficulty(state)
    local count=AI.incoming(state,owner)
    return state.players[owner].playerType~="Bot" and AI.isFFA(state) and count==0
        and (difficulty=="Hard" or difficulty=="Impossible") and amount<state.troops[target]*.2
end
function AI.botAmount(state: any,target: number,maximum: number): number
    if AI.difficulty(state)=="Easy" then return maximum end
    local amount=state.troops[target]*4
    if amount>maximum then return if maximum<state.troops[target]*2 then 0 else maximum end
    return amount
end
function AI.calculateTroops(state: any,owner: number,target: number,boat: boolean,api: any): number?
    local brain=(state.nations and state.nations[owner]) or state.bots[owner]
    local isBotAttack=target>0 and state.players[target].playerType=="Bot" and state.players[owner].playerType~="Bot"
    local structured=target>0 and state.players[target].playerType=="Bot" and api.hasStructures and api.hasStructures(target)
    local reserve=api.capacity(owner)*(if target==0 or structured then brain.expandRatio else brain.reserveRatio)
    local amount=if isBotAttack then AI.botAmount(state,target,state.troops[owner]-reserve-(brain.botAttackTroopsSent or 0))
        elseif boat then state.troops[owner]/5 else state.troops[owner]-reserve
    amount=math.min(amount,if target==0 then AI.expansionCap(state,owner,api) else AI.troopSendCap(state,owner,api))
    if amount<1 or target>0 and AI.tooWeak(state,owner,target,amount) then return nil end
    if target>0 and state.players[owner].playerType=="Nation" and api.attackEmoji then api.attackEmoji(owner,target) end
    if isBotAttack then brain.botAttackTroopsSent=(brain.botAttackTroopsSent or 0)+amount end
    return amount
end
function AI.juiciest(state: any,candidates: {number},api: any): number?
    if #candidates==0 then return nil end
    local stats,low,high={}, {math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
    for _,owner in candidates do
        local structures=0
        if api.structureValue then structures=api.structureValue(owner)
        else for _,name in {"cities","ports","factories","samLaunchers"} do
            for _,unit in state[name] or {} do if unit.owner==owner and unit.active~=false then structures+=unit.level end end
        end end
        local maxTroops=api.capacity(owner)
        local values={structures,if maxTroops>0 then 1-state.troops[owner]/maxTroops else 0,state.counts[owner]}
        for index,value in values do low[index]=math.min(low[index],value);high[index]=math.max(high[index],value) end
        table.insert(stats,{owner=owner,values=values})
    end
    local best,score=nil,-math.huge
    for _,entry in stats do
        local total=0;for index,value in entry.values do if high[index]>low[index] then total+=(value-low[index])/(high[index]-low[index]) end end
        if total>score then best,score=entry.owner,total end
    end
    return best
end
return table.freeze(AI)
