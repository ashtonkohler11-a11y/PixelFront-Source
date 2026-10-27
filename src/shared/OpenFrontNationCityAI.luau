--!strict
--!native
-- NationStructureBehavior + NationUtils at OpenFrontIO93a136a1.
-- Structure placement/upgrade scoring preserves the shared Nation PRNG.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local AttackMath = require(script.Parent.OpenFrontNationAttackMath)
local Random = require(script.Parent.OpenFrontRandom)
local Economy = require(script.Parent.OpenFrontEconomy)
local Weapons = require(script.Parent.OpenFrontWeapons)
local Trade = require(script.Parent.OpenFrontTrade)
local Trains = require(script.Parent.OpenFrontTrains)
local NationCity = {}
-- Area-based AI thresholds are per tile. A Compact map has a quarter of a Normal map's
-- tiles (half each side), so on Compact they scale by 4. A nation then places as many
-- DISTINCT buildings as an OpenFront nation on the Normal map, instead of switching to
-- upgrades a quarter of the way in (Ashton 2026-10-07: "they get big then stop placing").
function NationCity.areaScale(state: any): number
    local size=(state.gameConfig and state.gameConfig.gameMapSize) or (state.map and state.map.mapSize)
    return if size=="Compact" then 4 else 1
end
-- PixelFront economy-first nations (Ashton live 2026-10-07: nations "arent placing no buildings and just saving
-- cash not spending asap like us"). Upstream inflates the felt cost of every next structure by its owned levels
-- (City/Port/Factory: x(1+levels)) until the nation holds its nuke save-up (MIRV + Hydrogen, 30M), so a 1-city
-- nation holding 312K waits for a "500K" City, a 2-city one for "1.5M", and big nations sit on millions.
-- PixelFront nations build their economy like players: City / Port / Factory cost what they cost. Defence keeps
-- upstream's felt cost, and a due SAM / Silo is saved for (NationPort: Cities wait), so they still build them.
NationCity.ECONOMY=table.freeze({City=true,Port=true,Factory=true})
function NationCity.perceivedCost(state: any,owner: number,kind: string,cost: number,levels: number,increase: number): number
    if NationCity.ECONOMY[kind] or state.gold[owner]>=NationCity.saveUpTarget(state,owner) then return cost end
    return math.ceil(cost*(1+increase*levels))
end
-- Above this structures-per-tile density a nation upgrades instead of building new (UPGRADE_DENSITY_THRESHOLD).
function NationCity.upgradeDensity(state: any): number return NationCity.areaScale(state)/1500 end
function NationCity.saveUpTarget(state: any, owner: number?): number
    local config=GameConfig.forState(state)
    local samCost=if owner then Weapons.cost(state,"SAMLauncher",owner) else config.SAMLauncher.BaseCost
    if not config.MissileSilo.Enabled then return samCost end
    if not AttackMath.isFFA(state) then return config.Nuclear.HydrogenCost end
    if config.Nuclear.Enabled and not GameConfig.disabled(state,"MIRV") then return config.Nuclear.MIRVBaseCost+(state.mirvsLaunched or 0)*config.Nuclear.MIRVCostIncrease+config.Nuclear.HydrogenCost end
    if config.Nuclear.Enabled and not GameConfig.disabled(state,"Hydrogen Bomb") then return config.Nuclear.HydrogenCost*5 end
    if config.Nuclear.Enabled and not GameConfig.disabled(state,"Atom Bomb") then return config.Nuclear.AtomCost*20 end
    return samCost
end
local function manhattan(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
local function borderDistance(state: any, owner: number, tile: number, cap: number): number
    local slots = state.borders[owner].slots
    if slots[tile] then return 0 end
    local w, h = state.map.width, state.map.height
    local cx, cy = (tile - 1) % w, math.floor((tile - 1) / w)
    for d = 1, cap do
        for dx = -d, d do
            local x = cx + dx
            if x < 0 or x >= w then continue end
            local dy = d - math.abs(dx)
            local y = cy - dy
            if y >= 0 and slots[y * w + x + 1] then return d end
            y = cy + dy
            if dy ~= 0 and y < h and slots[y * w + x + 1] then return d end
        end
    end
    return math.huge
end
local function candidates(state: any, owner: number, random: any, amount: number?): { number }
    local w = state.map.width
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, tile in state.borders[owner].values do
        if tile == 0 then continue end
        local x, y = (tile - 1) % w, math.floor((tile - 1) / w)
        minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
    end
    local result = {}
    for _ = 1, amount or 25 do
        local selected = nil
        for _ = 1, 100 do
            local x, y = Random.int(random, minX, maxX), Random.int(random, minY, maxY)
            if x ~= x or y ~= y or x < 0 or y < 0 or x >= w or y >= state.map.height then continue end
            local tile = y * w + x + 1
            if state.owners[tile] == owner then selected = tile break end
        end
        if selected == nil and state.counts[owner] > 0 and state.counts[owner] <= 100 then
            local owned = {}
            for _, tile in state.territories[owner].values do if tile ~= 0 then table.insert(owned, tile) end end
            selected = owned[Random.int(random, 0, #owned) + 1]
        end
        if selected then table.insert(result, selected) end
    end
    return result
end
local function upgradeCandidate(state: any, owner: number, cities: { any }, random: any, canUpgrade: any?): any
    local eligible = {}
    for _, city in cities do if (canUpgrade or Economy.canUpgradeCity)(state, owner, city.id) then table.insert(eligible, city) end end
    if #eligible == 0 then return nil end
    local config=GameConfig.forState(state)
    if Random.int(random, 0, 100) < ({Easy=70,Medium=40,Hard=25,Impossible=10})[AttackMath.difficulty(state)] then return eligible[Random.int(random, 0, #eligible) + 1] end
    local scores = {}
    for i, city in eligible do
        local score = 0
        for _, sam in state.samLaunchers or {} do
            if sam.owner ~= owner or sam.active == false then continue end
            local range = Weapons.samRange(sam.level)
            if Economy.distanceSquared(state, city.tileId, sam.tileId) <= range ^ 2 then score += 10 + math.max(0, sam.level - 1) * 7.5 end
        end
        table.insert(scores, { city = city, score = score + Random.int(random, 0, 5), order = i })
    end
    table.sort(scores, function(a, b) return if a.score == b.score then a.order < b.order else a.score > b.score end)
    if #scores >= 2 and Random.int(random, 0, 2) == 0 then
        return scores[if #scores >= 3 then Random.int(random, 1, 3) + 1 else 2].city
    end
    return scores[1].city
end
function NationCity.structureCount(state: any, owner: number): number
    local count = 0
    for _, list in { state.cities or {}, state.ports or {}, state.factories or {}, state.defensePosts or {}, state.samLaunchers or {}, state.missileSilos or {} } do
        for _, value in list do if value.owner == owner and value.active ~= false then count += 1 end end
    end
    return count
end
NationCity.candidates = candidates
NationCity.borderDistance = borderDistance
NationCity.upgradeCandidate = upgradeCandidate
function NationCity.useConnectivity(state: any,random: any): boolean
    return Random.int(random,0,100)<({Easy=0,Medium=60,Hard=75,Impossible=100})[AttackMath.difficulty(state)]
end
function NationCity.connectivityEntries(state: any,owner: number): {any}
    local clusters,hasStation={},{}
    if state._railNetwork then
        for _,station in state._railNetwork.stations do hasStation[station.unit.id]=true;clusters[station.unit.id]=station.cluster end
    else
        for _,station in state.stations or {} do hasStation[station.unitId]=true;clusters[station.unitId]=station.clusterId end
    end
    local config=GameConfig.forState(state)
    local api=state.nationApi
    local maximum=math.max(Trains.gold("ally",0,config.Economy.GoldMultiplier),1)
    local result={}
    local function collect(other: number,relation: string)
        local weight=Trains.gold(relation,0,config.Economy.GoldMultiplier)/maximum
        for _,list in {state.cities or {},state.ports or {},state.factories or {}} do
            for _,unit in list do if unit.owner==other and unit.active~=false and hasStation[unit.id] then table.insert(result,{tile=unit.tileId,cluster=clusters[unit.id],weight=weight}) end end
        end
    end
    collect(owner,"self")
    local nearby=if api and api.nearby then api.nearby(owner) else {}
    for _,other in nearby do
        if other==0 or state.players[other].playerType=="Bot" or not Trade.canTrade(state,owner,other) then continue end
        local relation=if state.isOnSameTeam and state.isOnSameTeam(owner,other) then "team" elseif api and api.isAllied(owner,other) then "ally" else "other"
        collect(other,relation)
    end
    return result
end
function NationCity.connectivityScore(state: any,tile: number,entries: {any}): number
    local config=GameConfig.forState(state)
    local clusters,score={},0
    for _,entry in entries do
        local distance=Economy.distanceSquared(state,tile,entry.tile)
        if distance<config.Train.StationMinRange^2 or distance>config.Train.StationMaxRange^2 then continue end
        if entry.cluster~=nil then clusters[entry.cluster]=math.max(clusters[entry.cluster] or 0,entry.weight) else score+=entry.weight end
    end
    for _,value in clusters do score+=value end
    return score
end
function NationCity.handleStructures(state: any, owner: number): boolean
    local nation = state.nations[owner]
    local config=GameConfig.forState(state)
    if not nation or state.counts[owner] == 0 or not config.City.Enabled then return false end
    local cost = Economy.cityCost(state, owner)
    local perceived = NationCity.perceivedCost(state, owner, "City", cost, Economy.ownedLevels(state, owner), 1)
    if state.gold[owner] < perceived then return false end
    local cities = Economy.ownedCities(state, owner)
    if NationCity.structureCount(state, owner) / state.counts[owner] > NationCity.upgradeDensity(state) then
        local city = upgradeCandidate(state, owner, cities, nation.random)
        if city then
            table.insert(state.pendingExecutions, { kind = "UpgradeCity", owner = owner, unitId = city.id, amount = 1 })
            return true
        end
        if #cities > 0 then return false end
    end
    local tiles = candidates(state, owner, nation.random)
    if #tiles == 0 then return false end
    local useConnectivity=NationCity.useConnectivity(state,nation.random)
    local entries=if useConnectivity then NationCity.connectivityEntries(state,owner) else {}
    local bestTile, bestValue = nil, 0
    -- source spacingConstants(): the atom bomb's outer radius (PixelFront x0.7 = 21, PF-033)
    local borderSpacing = config.Nuclear.AtomOuter
    for _, tile in tiles do
        local value = bit32.band(buffer.readu8(state.map.terrain, tile - 1), 31)
            + math.min(borderDistance(state, owner, tile, borderSpacing), borderSpacing)
        local nearest = math.huge
        for _, city in cities do if city.tileId ~= tile then nearest = math.min(nearest, manhattan(state, city.tileId, tile)) end end
        if nearest ~= math.huge then value += math.min(nearest, borderSpacing * 2) end
        local nearestFactory = math.huge
        for _, factory in state.factories or {} do if factory.owner == owner then nearestFactory = math.min(nearestFactory, manhattan(state, factory.tileId, tile)) end end
        if nearestFactory ~= math.huge then value += math.min(nearestFactory, borderSpacing * 2) end
        if useConnectivity then value+=NationCity.connectivityScore(state,tile,entries)*borderSpacing*2 end
        if value <= bestValue and bestTile ~= nil then continue end
        if not Economy.canBuildCity(state, owner, tile) then continue end
        bestTile, bestValue = tile, value
    end
    if not bestTile or not Economy.canBuildCity(state, owner, bestTile) then return false end
    table.insert(state.pendingExecutions, { kind = "BuildCity", owner = owner, tileId = bestTile })
    return true
end
return table.freeze(NationCity)
