--!strict
--!native
-- AiAttackBehavior transport branches, OpenFrontIO93a136a1, all difficulties/modes.
-- The same targeted/nearby-wilderness helpers are used by tribes. Diplomacy and
-- nation attack-emoji hooks preserve source selection and random draw ordering.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Random = require(script.Parent.OpenFrontRandom)
local Naval = require(script.Parent.OpenFrontNaval)
local AttackMath = require(script.Parent.OpenFrontNationAttackMath)
local AI = {}
local directions = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

local function brain(state: any, owner: number): any
    return (state.nations and state.nations[owner]) or state.bots[owner]
end
function AI.shoreTiles(state: any, owner: number): { number }
    local result = {}
    for _, tile in Naval.shoreBorders(state, owner) do -- PF035: the cached shore subset (the same filter, the same order)
        if tile ~= 0 and bit32.band(buffer.readu8(state.map.terrain, tile - 1), 192) == 192 then table.insert(result, tile) end
    end
    return result
end
-- Source uses an x-sorted sweep, not a brute-force nearest-pair search.
function AI.closestTwoTiles(state: any, xs: { number }, ys: { number }): any
    if #xs == 0 or #ys == 0 then return nil end
    local width, xOrder, yOrder = state.map.width, {}, {}
    for i, tile in xs do xOrder[tile] = i end
    for i, tile in ys do yOrder[tile] = i end
    local x, y = table.clone(xs), table.clone(ys)
    table.sort(x, function(a, b)
        local ax, bx = (a - 1) % width, (b - 1) % width
        return if ax == bx then xOrder[a] < xOrder[b] else ax < bx
    end)
    table.sort(y, function(a, b)
        local ax, bx = (a - 1) % width, (b - 1) % width
        return if ax == bx then yOrder[a] < yOrder[b] else ax < bx
    end)
    local i, j, best, result = 1, 1, math.huge, { x = x[1], y = y[1] }
    while i <= #x and j <= #y do
        local a, b = x[i] - 1, y[j] - 1
        local ax, bx = a % width, b % width
        local distance = math.abs(ax - bx) + math.abs(math.floor(a / width) - math.floor(b / width))
        if distance < best then best, result = distance, { x = a + 1, y = b + 1 } end
        if i == #x then j += 1
        elseif j == #y then i += 1
        elseif ax < bx then i += 1
        else j += 1 end
    end
    return result
end
local function eligible(state: any, owner: number, tile: number, api: any?): boolean
    if api and api.canBuild then return api.canBuild(owner, tile) ~= false end
    return Naval.canBuildTransportShip(state, owner, tile, if api then api.navigation else nil) ~= false
end
local function queue(state: any, owner: number, tile: number, troops: number): boolean
    if troops < 1 then return false end
    table.insert(state.pendingExecutions, { kind = "TransportShip", owner = owner, tileId = tile, amount = troops })
    return true
end
local function enabled(state: any, owner: number): boolean
    local config=GameConfig.forState(state)
    return config.Naval.Enabled and Naval.unitCount(state, owner) < config.Naval.MaxShips
end
local function mathApi(state: any,owner: number,capacity: number?,api: any?): any
    local result=table.clone(api or {})
    result.capacity=result.capacity or function(a) return if a==owner and capacity then capacity else (state.players[a].capacity or 100000) end
    result.nearby=result.nearby or function() return {} end
    result.hasStructures=result.hasStructures or function(target)
        for _,name in {"cities","ports","factories","defensePosts","missileSilos","samLaunchers"} do
            for _,unit in state[name] or {} do if unit.owner==target and unit.active~=false then return true end end
        end
        return false
    end
    return result
end
function AI.sendNearbyNeutral(state: any, owner: number, api: any?): boolean
    if not enabled(state, owner) then return false end
    local w, h, shores = state.map.width, state.map.height, AI.shoreTiles(state, owner)
    for index = 1, #shores, 10 do
        local tile = shores[index]
        local bx, by = (tile - 1) % w, math.floor((tile - 1) / w)
        for _, direction in directions do
            local dx, dy = direction[1], direction[2]
            local x1, y1 = bx + dx, by + dy
            if x1 < 0 or y1 < 0 or x1 >= w or y1 >= h
                or bit32.band(buffer.readu8(state.map.terrain, y1 * w + x1), 128) ~= 0 then continue end
            local nx, ny = bx + dx * 5, by + dy * 5
            if nx < 0 or ny < 0 or nx >= w or ny >= h then continue end
            local target = ny * w + nx + 1
            if not state.map.land[target] or bit32.band(buffer.readu8(state.map.terrain, target - 1), 31) == 31
                or state.owners[target] > 0 or state.falloutTiles and state.falloutTiles[target] then continue end
            if not eligible(state, owner, target, api) then continue end
            if api and api.mercyTile and api.mercyTile(owner, target) then continue end -- PF043 tribe mercy zone
            return queue(state, owner, target, math.min(state.troops[owner]/5,AttackMath.expansionCap(state,owner,mathApi(state,owner,nil,api))))
        end
    end
    return false
end
function AI.sendBoatAttack(state: any, owner: number, target: number, capacity: number, api: any?): boolean
    if not GameConfig.forState(state).Naval.Enabled then return false end
    local closest = AI.closestTwoTiles(state, AI.shoreTiles(state, owner), AI.shoreTiles(state, target))
    if not closest or not eligible(state, owner, closest.y, api) then return false end
    local amount=AttackMath.calculateTroops(state,owner,target,true,mathApi(state,owner,capacity,api))
    if amount==nil then return false end
    return queue(state, owner, closest.y, amount)
end
function AI.findRandomBoatTarget(state: any, owner: number, tile: number, enemies: { number }, highInterest: boolean, api: any?): number?
    local w, h, random = state.map.width, state.map.height, brain(state, owner).random
    local x, y = (tile - 1) % w, math.floor((tile - 1) / w)
    local unreachable = {}
    for _ = 1, 500 do
        local rx, ry = Random.int(random, x - 150, x + 150), Random.int(random, y - 150, y + 150)
        if rx < 0 or ry < 0 or rx >= w or ry >= h then continue end
        local candidate = ry * w + rx + 1
        if not state.map.land[candidate] or bit32.band(buffer.readu8(state.map.terrain, candidate - 1), 31) == 31 then continue end
        local other = state.owners[candidate]
        if other == owner or (other > 0 and (unreachable[other] or table.find(enemies, other))) then continue end
        if AttackMath.isFFA(state) and other > 0 and state.troops[other] > state.troops[owner] then continue end
        if highInterest and other > 0 and state.players[other].playerType ~= "Bot" then continue end
        if not highInterest and other > 0 and api and api.friendly and api.friendly(owner, other) then continue end
        if not eligible(state, owner, candidate, api) then
            if other > 0 then unreachable[other] = true end
            continue
        end
        return candidate
    end
    return nil
end
function AI.attackWithRandomBoat(state: any, owner: number, enemies: { number }?, api: any?): boolean
    if not enabled(state, owner) then return false end
    local shores = AI.shoreTiles(state, owner)
    if #shores == 0 then return false end
    local src = shores[Random.int(brain(state, owner).random, 0, #shores) + 1]
    local nearby = enemies or {}
    local dst = AI.findRandomBoatTarget(state, owner, src, nearby, true, api)
    if dst == nil then dst = AI.findRandomBoatTarget(state, owner, src, nearby, false, api) end
    if not dst then return false end
    local target=state.owners[dst]
    local query=mathApi(state,owner,nil,api)
    local cap=if target>0 then AttackMath.troopSendCap(state,owner,query) else AttackMath.expansionCap(state,owner,query)
    local amount=math.min(state.troops[owner]/5,cap)
    if amount<1 or target>0 and AttackMath.tooWeak(state,owner,target,amount) then return false end
    return queue(state,owner,dst,amount)
end
function AI.findNearestIsland(state: any,owner: number,api: any): number?
    if not enabled(state,owner) or #AI.shoreTiles(state,owner)==0 then return nil end
    local function center(target: number): any
        local box=state.largestClusterBounds and state.largestClusterBounds[target]
        if box then return {x=box.min.x+math.floor((box.max.x-box.min.x)/2),y=box.min.y+math.floor((box.max.y-box.min.y)/2)} end
        local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
        for _,tile in Naval.orderedBorders(state,target) do if tile~=0 then
            local x,y=(tile-1)%state.map.width,math.floor((tile-1)/state.map.width)
            minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
        end end
        return {x=math.floor((minX+maxX)/2),y=math.floor((minY+maxY)/2)}
    end
    local ownCenter=center(owner)
    local candidates={}
    for _,target in state.playerOrder do
        if target==owner or state.counts[target]<=0 or api.friendly(owner,target) or AttackMath.isFFA(state) and state.troops[target]>=state.troops[owner] then continue end
        local otherCenter=center(target)
        table.insert(candidates,{owner=target,distance=math.abs(ownCenter.x-otherCenter.x)+math.abs(ownCenter.y-otherCenter.y),order=#candidates+1})
    end
    table.sort(candidates,function(a,b)return if a.distance==b.distance then a.order<b.order else a.distance<b.distance end)
    local reachable={}
    for _,entry in candidates do
        local closest=AI.closestTwoTiles(state,AI.shoreTiles(state,owner),AI.shoreTiles(state,entry.owner))
        if closest and eligible(state,owner,closest.y,api) then table.insert(reachable,entry.owner);if #reachable>=2 then break end end
    end
    if #reachable==0 then return nil end
    return if #reachable>=2 and Random.int(brain(state,owner).random,0,3)==0 then reachable[2] else reachable[1]
end
return table.freeze(AI)
