--!strict
--!native
-- NationWarshipBehavior/NationExecution, OpenFrontIO93a136a1, all source branches.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Random = require(script.Parent.OpenFrontRandom)
local Warships = require(script.Parent.OpenFrontWarships)
local Ports = require(script.Parent.OpenFrontPorts)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Emoji=require(script.Parent.OpenFrontNationEmojiAI)
local AttackMath=require(script.Parent.OpenFrontNationAttackMath)
local AI = {}
function AI.warshipSpawnTile(state: any, owner: number, portTile: number, radius: number, api: any?): number?
    local w, h, random = state.map.width, state.map.height, state.nations[owner].random
    local nav = (api and api.navigation) or Navigation.forMap(state.map)
    local x, y = (portTile - 1) % w, math.floor((portTile - 1) / w)
    for _ = 1, 50 do
        local rx, ry = Random.int(random, x - radius, x + radius), Random.int(random, y - radius, y + radius)
        if rx < 0 or ry < 0 or rx >= w or ry >= h then continue end
        local tile = ry * w + rx + 1
        if nav:isWater(tile) then return tile end
    end
    return nil
end
function AI.maybeSpawnWarship(state: any, owner: number, api: any?): boolean
    if not GameConfig.forState(state).Warship.Enabled then return false end
    local nation = state.nations[owner]
    if not nation then return false end
    if Random.int(nation.random, 0, 50) ~= 0 then return false end
    local ports = Ports.ownedPorts(state, owner)
    if #ports == 0 or #Warships.ownedShips(state, owner) ~= 0 or state.gold[owner] <= Warships.cost(state, owner) then return false end
    local port = ports[Random.int(nation.random, 0, #ports) + 1]
    local target = AI.warshipSpawnTile(state, owner, port.tileId, 250, api)
    if target == nil or Warships.canBuildWarship(state, owner, target, if api then api.navigation else nil) == false then return false end
    table.insert(state.pendingExecutions, {kind = "BuildWarship", owner = owner, tileId = target})
    return true
end
local function manhattan(state: any,a: number,b: number): number
    return math.abs((a-1)%state.map.width-(b-1)%state.map.width)+math.abs(math.floor((a-1)/state.map.width)-math.floor((b-1)/state.map.width))
end
local function distanceSquared(state: any,a: number,b: number): number
    return ((a-1)%state.map.width-(b-1)%state.map.width)^2+(math.floor((a-1)/state.map.width)-math.floor((b-1)/state.map.width))^2
end
local function canBuild(state: any,owner: number,tile: number,api: any): boolean
    return if api.canBuildWarship then api.canBuildWarship(owner,tile)~=false else Warships.canBuildWarship(state,owner,tile,api.navigation)~=false
end
local function add(set: {any},unit: any) if not table.find(set,unit) then table.insert(set,unit) end end
function AI.maybeMoveWarship(state: any,owner: number,tile: number,api: any): boolean
    local nav=api.navigation or Navigation.forMap(state.map)
    if not nav:isWater(tile) then return false end
    local best,nearest=nil,math.huge
    for _,ship in Warships.ownedShips(state,owner) do
        if ship.patrolTile==nil or manhattan(state,ship.tileId,ship.patrolTile)>=130 then continue end
        local distance=manhattan(state,ship.tileId,tile)
        if distance<nearest then best,nearest=ship,distance end
    end
    if not best then return false end
    best.patrolTile=tile
    return true
end
function AI.maybeRetaliate(state: any,owner: number,tile: number,enemy: number,reason: string,api: any)
    if enemy==owner then return end
    if #Warships.ownedShips(state,owner)>=10 then AI.maybeMoveWarship(state,owner,tile,api);return end
    local difficulty=AttackMath.difficulty(state)
    local percent={Medium=15,Hard=50,Impossible=80}
    if difficulty=="Easy" or Random.int(state.nations[owner].random,0,100)>=percent[difficulty] then return end
    if not canBuild(state,owner,tile,api) then AI.maybeMoveWarship(state,owner,tile,api);return end
    table.insert(state.pendingExecutions,{kind="BuildWarship",owner=owner,tileId=tile})
    Emoji.maybeSend(state,owner,enemy,Emoji.Lists.WarshipRetaliation,api)
    api.updateRelation(owner,enemy,if reason=="trade" then -7.5 else -15)
end
function AI.trackShipsAndRetaliate(state: any,owner: number,api: any)
    local nation=state.nations[owner]
    if not nation or not nation.started or state.counts[owner]<=0 or AttackMath.difficulty(state)=="Easy"
        or (state.portConstructed and state.portConstructed[owner] or 0)==0
        or not GameConfig.forState(state).Warship.Enabled then return end
    nation.warshipAI=nation.warshipAI or {trackedTransportShips={},trackedTradeShips={},trackedIncomingTransportShips={},dealtWithTransportShip={}}
    local data=nation.warshipAI
    if not GameConfig.disabled(state,"Transport") then
        for _,ship in state.ships or {} do if ship.owner==owner and ship.active~=false then add(data.trackedTransportShips,ship) end end
        local index=1
        while index<=#data.trackedTransportShips do
            local ship=data.trackedTransportShips[index]
            if ship.active==false then
                if ship.wasDestroyedByEnemy and ship.destroyer~=nil then AI.maybeRetaliate(state,owner,ship.tileId,ship.destroyer,"transport",api) end
                table.remove(data.trackedTransportShips,index)
            else index+=1 end
        end
    end
    for _,ship in state.tradeShips or {} do if ship.owner==owner and ship.active~=false then add(data.trackedTradeShips,ship) end end
    local index=1
    while index<=#data.trackedTradeShips do
        local ship=data.trackedTradeShips[index]
        if ship.active==false then table.remove(data.trackedTradeShips,index)
        elseif ship.owner~=owner then AI.maybeRetaliate(state,owner,ship.tileId,ship.owner,"trade",api);table.remove(data.trackedTradeShips,index)
        else index+=1 end
    end
    for _,ship in state.ships or {} do
        local target=ship.targetTileId
        -- Literal source target truthiness skips zero-based tile zero.
        if target and target>1 and ship.active~=false and not ship.isRetreating and state.owners[target]==owner and ship.owner~=owner then add(data.trackedIncomingTransportShips,ship) end
    end
    index=1
    while index<=#data.trackedIncomingTransportShips do
        local ship=data.trackedIncomingTransportShips[index]
        local target=ship.targetTileId
        if ship.active==false or target==nil or ship.isRetreating then
            table.remove(data.trackedIncomingTransportShips,index)
            local dealt=table.find(data.dealtWithTransportShip,ship);if dealt then table.remove(data.dealtWithTransportShip,dealt) end
            continue
        end
        index+=1
        if table.find(data.dealtWithTransportShip,ship) then continue end
        if manhattan(state,ship.tileId,target)<20 then add(data.dealtWithTransportShip,ship);continue end
        if api.isAllied(ship.owner,owner) then continue end
        local protected=false
        for _,warship in Warships.ownedShips(state,owner) do
            if distanceSquared(state,warship.tileId,target)<=90^2 or warship.patrolTile and manhattan(state,target,warship.patrolTile)<90 then protected=true;break end
        end
        if protected then add(data.dealtWithTransportShip,ship);continue end
        local ocean=AI.warshipSpawnTile(state,owner,target,30,api)
        if not ocean then continue end
        AI.maybeRetaliate(state,owner,ocean,ship.owner,"transport",api)
        add(data.dealtWithTransportShip,ship)
        break
    end
end
function AI.counterWarshipInfestation(state: any,owner: number,api: any): boolean
    local difficulty=AttackMath.difficulty(state)
    if not GameConfig.forState(state).Warship.Enabled
        or difficulty~="Hard" and difficulty~="Impossible" or #(state.warships or {})<=10
        or Warships.cost(state,owner)>state.gold[owner] or #Ports.ownedPorts(state,owner)==0 or #Warships.ownedShips(state,owner)>=10 then return false end
    local ownTeam=state.players[owner].team
    local players,order={},{}
    for _,other in state.playerOrder do if state.counts[other]>0 and state.players[other].playerType~="Human" and (ownTeam==nil or state.players[other].team==ownTeam) then table.insert(players,other);order[other]=#players end end
    table.sort(players,function(a,b)return if state.gold[a]==state.gold[b] then order[a]<order[b] else state.gold[a]>state.gold[b] end)
    if not table.find({players[1],players[2],players[3]},owner) then return false end
    local target=nil
    if ownTeam~=nil then
        local groups,groupOrder={},{}
        for _,other in state.playerOrder do if state.counts[other]>0 and other~=owner and not api.friendly(owner,other) then
            local team=state.players[other].team
            if team~=nil then
                if not groups[team] then groups[team]={count=0,players={}};table.insert(groupOrder,team) end
                local group=groups[team];group.count+=#Warships.ownedShips(state,other);table.insert(group.players,other)
            end
        end end
        for _,team in groupOrder do
            local group=groups[team]
            if group.count<=15 then continue end
            local most,maximum=nil,0
            for _,other in group.players do local count=#Warships.ownedShips(state,other);if count>maximum then most,maximum=other,count end end
            if most and maximum>3 then local ships=Warships.ownedShips(state,most);target=ships[Random.int(state.nations[owner].random,0,#ships)+1];break end
        end
    else
        for _,other in state.playerOrder do if state.counts[other]>0 and other~=owner and not api.friendly(owner,other) then
            local ships=Warships.ownedShips(state,other)
            if #ships>10 then target=ships[Random.int(state.nations[owner].random,0,#ships)+1];break end
        end end
    end
    if not target then return false end
    if not canBuild(state,owner,target.tileId,api) then AI.maybeMoveWarship(state,owner,target.tileId,api);return false end
    table.insert(state.pendingExecutions,{kind="BuildWarship",owner=owner,tileId=target.tileId})
    Emoji.send(state,owner,0,Emoji.Lists.WarshipRetaliation,api)
    return true
end
return table.freeze(AI)
