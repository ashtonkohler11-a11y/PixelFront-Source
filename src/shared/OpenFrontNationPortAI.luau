--!strict
--!native
-- OpenFrontIO 93a136a1 NationStructureBehavior/SharedWaterCache, all variants.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local AttackMath = require(script.Parent.OpenFrontNationAttackMath)
local MapData = require(script.Parent.MapData)
local Random = require(script.Parent.OpenFrontRandom)
local Economy = require(script.Parent.OpenFrontEconomy)
local Ports = require(script.Parent.OpenFrontPorts)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Trade = require(script.Parent.OpenFrontTrade)
local NationCity = require(script.Parent.OpenFrontNationCityAI)
local Structures = require(script.Parent.OpenFrontStructures)
local Weapons = require(script.Parent.OpenFrontWeapons)
local NationPort = {}
local function manhattan(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
local function ocean(state: any, tile: number): boolean return bit32.band(buffer.readu8(state.map.terrain, tile - 1), 32) ~= 0 end
local function navigationFor(state: any): any
    -- Ocean and waterless fixtures need no component graph. Resolve the exact
    -- official navigation only if an inland component is actually queried.
    return { isShore = function(_, tile) return bit32.band(buffer.readu8(state.map.terrain, tile - 1), 192) == 192 end,
        isWater = function(_, tile) return bit32.band(buffer.readu8(state.map.terrain, tile - 1), 128) == 0 end,
        getWaterComponent = function(_, tile) return Navigation.forMap(state.map):getWaterComponent(tile) end,
        getWaterComponentSize = function(_,tile) return Navigation.forMap(state.map):getWaterComponentSize(tile) end }
end
function NationPort.sharedWaterComponents(state: any, owner: number, navOverride: any?): any
    local cache = state.sharedWaterCache
    if cache and state.ticks - cache.tick < 30 then return cache.byPlayer[owner] end
    local nav = navOverride or navigationFor(state)
    local previous = if cache then cache.playerWater else {}
    local playerWater, lakePartners, byPlayer = {}, {}, {}
    for _, current in state.playerOrder do
        if state.players[current].playerType == "Bot" or state.counts[current] <= 0 then continue end
        local version = state.tileChangeVersion and state.tileChangeVersion[current]
        local entry = previous[current]
        if version == nil or entry == nil or entry.version ~= version then
            entry = { version = version, hasOcean = false, lakes = {} }
            for _, tile in state.borders[current].values do
                if tile == 0 or not nav:isShore(tile) then continue end
                for _, neighbor in MapData.neighbors(tile, state.map.width, state.map.height) do
                    if not nav:isWater(neighbor) then continue end
                    if ocean(state, neighbor) then entry.hasOcean = true
                    else local component = nav:getWaterComponent(neighbor); if component ~= nil then entry.lakes[component] = true end end
                end
            end
        end
        playerWater[current] = entry
        for component in entry.lakes do
            lakePartners[component] = lakePartners[component] or {}
            table.insert(lakePartners[component], current)
        end
    end
    for _, current in state.playerOrder do
        local entry = playerWater[current]
        if not entry then continue end
        local shared, hasAny = {}, false
        if entry.hasOcean then shared[-1] = true; hasAny = true end
        for component in entry.lakes do
            for _, other in lakePartners[component] do
                if Trade.canTrade(state, current, other) then shared[component] = true; hasAny = true; break end
            end
        end
        if hasAny then byPlayer[current] = shared end
    end
    state.sharedWaterCache = { tick = state.ticks, byPlayer = byPlayer, playerWater = playerWater }
    return byPlayer[owner]
end
local function coastalCandidates(state: any, owner: number, shared: any, random: any, nav: any): { number }
    if shared == nil then return {} end
    local candidates = {}
    for _, tile in state.borders[owner].values do
        if tile == 0 or not nav:isShore(tile) then continue end
        for _, neighbor in MapData.neighbors(tile, state.map.width, state.map.height) do
            if not nav:isWater(neighbor) then continue end
            local component = if ocean(state, neighbor) then nil else nav:getWaterComponent(neighbor)
            if ocean(state, neighbor) then table.insert(candidates,tile);break end
            if component~=nil and shared[component] then
                local size=if nav.getWaterComponentSize then nav:getWaterComponentSize(neighbor) else nil
                if AttackMath.difficulty(state)~="Easy" and size~=nil and size<3000/NationCity.areaScale(state) then continue end
                table.insert(candidates,tile);break
            end
        end
    end
    if #candidates <= 25 then return candidates end
    local sample = {}
    for _ = 1, 25 do
        local index = Random.int(random, 0, #candidates) + 1
        table.insert(sample, table.remove(candidates, index))
    end
    return sample
end
local function chooseUpgrade(state: any, owner: number, ports: {any}, random: any): any
    return NationCity.upgradeCandidate(state, owner, ports, random, Ports.canUpgradePort)
end
local function maybePort(state: any, owner: number, shared: any, nav: any): boolean
    local cost = Ports.portCost(state, owner)
    local perceived = NationCity.perceivedCost(state, owner, "Port", cost, Ports.ownedLevels(state, owner), 1)
    if state.gold[owner] < perceived then return false end
    local ports = Ports.ownedPorts(state, owner)
    local random = state.nations[owner].random
    if NationCity.structureCount(state, owner) / state.counts[owner] > NationCity.upgradeDensity(state) then
        local port = chooseUpgrade(state, owner, ports, random)
        if port then
            table.insert(state.pendingExecutions, { kind = "UpgradePort", owner = owner, unitId = port.id, amount = 1 })
            return true
        end
        if #ports > 0 then return false end
    end
    local best, bestValue = nil, 0
    for _, tile in coastalCandidates(state, owner, shared, random, nav) do
        local value = math.huge
        for _, port in ports do if port.tileId ~= tile then value = math.min(value, manhattan(state, port.tileId, tile)) end end
        if value <= bestValue and best ~= nil then continue end
        if not Ports.canBuildPort(state, owner, tile) then continue end
        best, bestValue = tile, value
    end
    if not best or not Ports.canBuildPort(state, owner, best) then return false end
    table.insert(state.pendingExecutions, { kind = "BuildPort", owner = owner, tileId = best })
    return true
end
local function maybeFactory(state: any, owner: number): boolean
    local config=GameConfig.forState(state)
    local cost = Structures.factoryCost(state, owner)
    local perceived = NationCity.perceivedCost(state, owner, "Factory", cost, Structures.factoryLevels(state, owner), 1)
    if state.gold[owner] < perceived then return false end
    local factories = Structures.ownedFactories(state, owner)
    local random = state.nations[owner].random
    if NationCity.structureCount(state, owner) / state.counts[owner] > NationCity.upgradeDensity(state) then
        local factory = NationCity.upgradeCandidate(state, owner, factories, random, Structures.canUpgradeFactory)
        if factory then
            table.insert(state.pendingExecutions, { kind = "UpgradeFactory", owner = owner, unitId = factory.id, amount = 1 })
            return true
        end
        if #factories > 0 then return false end
    end
    local tiles = NationCity.candidates(state, owner, random)
    if #tiles == 0 then return false end
    local connectivity=NationCity.useConnectivity(state,random)
    local entries=if connectivity then NationCity.connectivityEntries(state,owner) else {}
    local best, bestValue = nil, 0
    -- source spacingConstants(): the atom bomb's outer radius (PixelFront x0.7 = 21, PF-033)
    local borderSpacing, stationRange = config.Nuclear.AtomOuter, config.Train.StationMaxRange
    for _, tile in tiles do
        local value = bit32.band(buffer.readu8(state.map.terrain, tile - 1), 31)
            + math.min(NationCity.borderDistance(state, owner, tile, borderSpacing), borderSpacing)
        local nearest = math.huge
        for _, factory in factories do if factory.tileId ~= tile then nearest = math.min(nearest, manhattan(state, factory.tileId, tile)) end end
        if nearest ~= math.huge then value += math.min(nearest, stationRange) end
        local nearestCity = math.huge
        for _, city in Economy.ownedCities(state, owner) do nearestCity = math.min(nearestCity, manhattan(state, city.tileId, tile)) end
        if nearestCity ~= math.huge then value += math.min(nearestCity, borderSpacing * 2) end
        if connectivity then value+=NationCity.connectivityScore(state,tile,entries)*borderSpacing*2 end
        if value <= bestValue and best ~= nil then continue end
        if not Structures.canBuildFactory(state, owner, tile) then continue end
        best, bestValue = tile, value
    end
    if not best or not Structures.canBuildFactory(state, owner, best) then return false end
    table.insert(state.pendingExecutions, { kind = "BuildFactory", owner = owner, tileId = best })
    return true
end
local function maybeWeapon(state: any, owner: number, kind: string): boolean
    local config=GameConfig.forState(state)
    local levels, cost = Weapons.ownedLevels(state, kind, owner), Weapons.cost(state, kind, owner)
    local perceived = NationCity.perceivedCost(state, owner, kind, cost, levels, if kind == "SAMLauncher" then 0.3 else 1)
    if state.gold[owner] < perceived then return false end
    local units, random = Weapons.owned(state, kind, owner), state.nations[owner].random
    if NationCity.structureCount(state, owner) / state.counts[owner] > NationCity.upgradeDensity(state) then
        local canUpgrade = function(s, o, id) return Weapons.canUpgrade(s, kind, o, id) end
        local value = NationCity.upgradeCandidate(state, owner, units, random, canUpgrade)
        if value then table.insert(state.pendingExecutions, { kind = "Upgrade" .. kind, owner = owner, unitId = value.id, amount = 1 }); return true end
        if #units > 0 then return false end
    end
    local candidates = NationCity.candidates(state, owner, random)
    local best, bestValue = nil, 0
    local borderSpacing = config.Nuclear.AtomOuter -- source spacingConstants(): the atom's outer radius (PF-033)
    local difficulty=AttackMath.difficulty(state)
    local protected={}
    if kind=="SAMLauncher" then
        for _,name in {"cities","factories","missileSilos","ports"} do for _,unit in state[name] or {} do
            if unit.owner==owner and unit.active~=false then table.insert(protected,{tile=unit.tileId,weight=if difficulty=="Hard" or difficulty=="Impossible" then unit.level else 1}) end
        end end
    end
    local coverageWeighting=kind=="SAMLauncher" and difficulty~="Easy" and Random.int(random,0,100)<25
    if coverageWeighting then for _,entry in protected do
        local coverage=0;for _,sam in units do local range=Weapons.samRange(sam.level);if Economy.distanceSquared(state,entry.tile,sam.tileId)<=range^2 then coverage+=sam.level end end
        entry.coverage=coverage
    end end
    -- source defaultSamRange() 70 = samRange(1): a new SAM's own reach (PixelFront x0.7 -> 49, PF-033)
    local samReach2=Weapons.samRange(1)^2
    for _, tile in candidates do
        local value = bit32.band(buffer.readu8(state.map.terrain, tile - 1), 31)
        if kind ~= "SAMLauncher" or next(state.borders[owner].slots) ~= nil then value += math.min(NationCity.borderDistance(state, owner, tile, borderSpacing), borderSpacing) end
        local nearest = math.huge
        for _, existing in units do if existing.tileId ~= tile then nearest = math.min(nearest, manhattan(state, existing.tileId, tile)) end end
        if nearest ~= math.huge then value += math.min(nearest, borderSpacing * 2) end
        if kind=="SAMLauncher" and difficulty~="Easy" then for _,entry in protected do
            if Economy.distanceSquared(state,tile,entry.tile)<=samReach2 then value+=borderSpacing*2*entry.weight*(if coverageWeighting then 1/(1+entry.coverage) else 1) end
        end end
        if value <= bestValue and best ~= nil then continue end
        if not Weapons.canBuild(state, kind, owner, tile) then continue end
        best, bestValue = tile, value
    end
    if not best or not Weapons.canBuild(state, kind, owner, best) then return false end
    table.insert(state.pendingExecutions, { kind = "Build" .. kind, owner = owner, tileId = best }); return true
end
local function incomingLand(state: any,owner: number): ({any},number)
    local attacks,total={},0
    for _,attack in state.attacks or {} do if attack.active and attack.targetOwner==owner and attack.sourceTile==nil then table.insert(attacks,attack);total+=attack.budget end end
    return attacks,total
end
function NationPort.defensePostNeeded(state: any,owner: number): boolean
    if AttackMath.difficulty(state)=="Easy" or state.troops[owner]<=0 then return false end
    local attacks,total=incomingLand(state,owner)
    return #attacks>0 and total/state.troops[owner]>=.35
end
function NationPort.attackFront(state: any,owner: number,attacks: {any}): {number}
    local enemies={};for _,attack in attacks do enemies[attack.owner]=true end
    local result={}
    for _,tile in state.borders[owner].values do
        if tile==0 then continue end
        for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height) do if enemies[state.owners[neighbor]] then table.insert(result,tile);break end end
    end
    return result
end
function NationPort.sampleNearFront(state: any,owner: number,front: {number}): {number}
    if #front==0 then return {} end
    local config=GameConfig.forState(state)
    local spacing=config.Nuclear.AtomOuter -- source spacingConstants(): the atom's outer radius (PF-033)
    local radius,minimum,maximum=math.ceil(spacing*1.5),math.ceil(spacing*.75),math.ceil(spacing*1.5)
    local posts=Structures.ownedDefensePosts(state,owner)
    local anchors={}
    if #posts>0 then
        for _,tile in front do local nearby=false;for _,post in posts do if Economy.distanceSquared(state,tile,post.tileId)<(spacing*1.5)^2 then nearby=true;break end end;if not nearby then table.insert(anchors,tile) end end
    end
    if #anchors==0 then anchors=front end
    local random=state.nations[owner].random
    local function sample(attempts: number,depth: boolean): {number}
        local result={}
        for _=1,attempts do
            if #result>=25 then break end
            local anchor=anchors[Random.int(random,0,#anchors)+1]
            local x=Random.int(random,(anchor-1)%state.map.width-radius,(anchor-1)%state.map.width+radius+1)
            local y=Random.int(random,math.floor((anchor-1)/state.map.width)-radius,math.floor((anchor-1)/state.map.width)+radius+1)
            if x<0 or x>=state.map.width or y<0 or y>=state.map.height then continue end
            local tile=y*state.map.width+x+1
            if state.owners[tile]~=owner then continue end
            if depth then
                local distance=NationCity.borderDistance(state,owner,tile,maximum)
                if distance<minimum or distance>maximum or not Structures.canBuildDefensePost(state,owner,tile) then continue end
            end
            table.insert(result,tile)
        end
        return result
    end
    local result=sample(25*6,true)
    return if #result>0 then result else sample(25*4,false)
end
function NationPort.tryDefensePost(state: any,owner: number): boolean
    local difficulty=AttackMath.difficulty(state)
    if difficulty=="Easy" or difficulty=="Medium" and Random.int(state.nations[owner].random,0,2)~=0 then return false end
    local attacks,total=incomingLand(state,owner)
    if #attacks==0 or state.troops[owner]<=0 or total/state.troops[owner]<.35 then return false end
    local allowed=if difficulty=="Medium" then 1 else math.ceil(total/state.troops[owner]/.4)
    local front=NationPort.attackFront(state,owner,attacks)
    local count=0
    for _,post in Structures.ownedDefensePosts(state,owner) do for _,tile in front do
        if Economy.distanceSquared(state,post.tileId,tile)<=(GameConfig.forState(state).Nuclear.AtomOuter*1.5)^2 then count+=1;break end
    end;if count>=allowed then return false end end
    if state.gold[owner]<Structures.defensePostCost(state,owner) then return false end
    for _,tile in NationPort.sampleNearFront(state,owner,front) do
        if Structures.canBuildDefensePost(state,owner,tile) then table.insert(state.pendingExecutions,{kind="BuildDefensePost",owner=owner,tileId=tile});return true end
    end
    return false
end
local function doHandleStructures(state: any, owner: number, navOverride: any?): boolean
    local nation = state.nations[owner]
    if not nation or state.counts[owner] == 0 then return false end
    local config=GameConfig.forState(state)
    local difficulty=AttackMath.difficulty(state)
    local nav = navOverride or navigationFor(state)
    local shared = NationPort.sharedWaterComponents(state, owner, nav)
    local cityCount = if config.City.Enabled then Economy.ownedLevels(state,owner) else math.max(1,math.floor(state.counts[owner]*NationCity.areaScale(state)/2000))
    if (nation.placementsCount or 0)==0 and (difficulty=="Hard" or difficulty=="Impossible") and not GameConfig.disabled(state,"Atom Bomb")
        and config.MissileSilo.Enabled and config.SAMLauncher.Enabled and config.Economy.StartingGold>=3000000 and maybeWeapon(state,owner,"SAMLauncher") then return true end
    local nationCount = 0
    for _, player in state.players do if player.playerType == "Nation" then nationCount += 1 end end
    if config.City.Enabled and not nation.builtCrowdedMapFirstStructure and state.map.landCount > 0 and nationCount / state.map.landCount > NationCity.areaScale(state) / 7500 then
        if shared and config.Port.Enabled then
            if maybePort(state, owner, shared, nav) then nation.builtCrowdedMapFirstStructure = true; return true end
        elseif config.Factory.Enabled then
            if maybeFactory(state, owner) then nation.builtCrowdedMapFirstStructure = true; return true end
        else
            nation.builtCrowdedMapFirstStructure = true
        end
    end
    -- PixelFront: a coastal nation's first Port comes with its first City (upstream: 0.75 per City, floored, so
    -- not until the 2nd City), so players always have nation trade partners early.
    local portQuota = if cityCount >= 1 then math.max(1, math.floor(cityCount * 0.75)) else 0
    if shared and config.Port.Enabled and Ports.ownedLevels(state, owner) < portQuota and maybePort(state, owner, shared, nav) then return true end
    local factoryRatio = 0.75 * (if shared and config.Port.Enabled then 0.33 else 1)
    if config.Factory.Enabled and Structures.factoryLevels(state, owner) < math.floor(cityCount * factoryRatio) and maybeFactory(state, owner) then return true end
    -- PixelFront: a due SAM / Silo the nation can't afford yet is saved for, so Cities wait for it (upstream got
    -- this from its inflated City cost; economy buildings now cost what they cost, see NationCity.ECONOMY).
    local saving = false
    local function short(kind: string, levels: number): boolean
        return state.gold[owner] < NationCity.perceivedCost(state, owner, kind, Weapons.cost(state, kind, owner), levels, if kind == "SAMLauncher" then 0.3 else 1)
    end
    if config.Nuclear and config.Nuclear.Enabled and config.MissileSilo.Enabled then
        local sams = Weapons.ownedLevels(state, "SAMLauncher", owner)
        if config.SAMLauncher.Enabled and sams < math.floor(cityCount * ({Easy=.15,Medium=.2,Hard=.25,Impossible=.3})[difficulty]) then
            if maybeWeapon(state, owner, "SAMLauncher") then return true end
            if short("SAMLauncher", sams) then saving = true end
        end
        local silos = Weapons.ownedLevels(state, "MissileSilo", owner)
        if silos < 3 and silos < math.floor(cityCount * (if silos == 0 then 0.4 else 0.2)) then
            if maybeWeapon(state, owner, "MissileSilo") then return true end
            if short("MissileSilo", silos) then saving = true end
        end
    end
    if saving then return false end
    return NationCity.handleStructures(state, owner)
end
function NationPort.handleStructures(state: any, owner: number, navOverride: any?): boolean
    local nation = state.nations[owner]
    if not nation or state.counts[owner] == 0 then return false end
    local config=GameConfig.forState(state)
    if (nation.placementsCount or 0)>0 and config.DefensePost.Enabled then
        if NationPort.tryDefensePost(state,owner) then return true end
        if NationPort.defensePostNeeded(state,owner) then return false end
    end
    if nation.lastStructureTick~=nil and config.Economy.StartingGold>=3000000 then
        local gap=({[2]=250,[3]=150,[4]=100})[nation.placementsCount] or 0
        if state.ticks-nation.lastStructureTick<gap then return false end
    end
    if config.MissileSilo and config.MissileSilo.Enabled then
        if nation.postSaveUpStartTick == nil and state.gold[owner] >= NationCity.saveUpTarget(state,owner) then nation.postSaveUpStartTick = state.ticks end
        if nation.postSaveUpStartTick and (state.ticks - nation.postSaveUpStartTick) % 300 >= 150 then return false end
    end
    local built=doHandleStructures(state,owner,navOverride)
    if built then nation.lastStructureTick=state.ticks;nation.placementsCount=(nation.placementsCount or 0)+1 end
    return built
end
return table.freeze(NationPort)
