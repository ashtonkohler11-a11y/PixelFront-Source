--!strict
--!native
-- OpenFrontIO 93a136a1: Config, PlayerImpl, UnitImpl and Construction/Upgrade/Delete executions.
-- Shared queries operate on server state or decoded snapshots; mutations stay server-side.
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local MapData = require(script.Parent.MapData)
local Balance = require(script.Parent.OpenFrontMatchBalance)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Economy = {}
local STRUCTURE_LISTS = { "cities", "ports", "factories", "defensePosts", "samLaunchers", "missileSilos" }

local function integer(value: any): boolean
    return type(value) == "number" and value == value and math.abs(value) < math.huge and value % 1 == 0
end
local function validOwner(state: any, owner: any): boolean
    return integer(owner) and owner >= 1 and owner <= #state.players
end
local function validTile(state: any, tile: any): boolean
    return integer(tile) and tile >= 1 and tile <= state.map.width * state.map.height
end
function Economy.city(state: any, id: number): any
    return Index.byId(state.cities, id) -- PF-4: was a scan of every city (~1,200 calls a tick late game)
end
function Economy.ownedCities(state: any, owner: number): { any }
    local result = {}
    if state.cityOrders then
        for _, id in state.cityOrders[owner] do
            local city = Economy.city(state, id)
            if city then table.insert(result, city) end
        end
    else
        for _, city in state.cities or {} do if city.owner == owner then table.insert(result, city) end end
    end
    return result
end
function Economy.ownedLevels(state: any, owner: number): number
    local total = 0
    for _, city in state.cities or {} do
        if city.owner == owner then total += if city.underConstruction then 1 else city.level end
    end
    return total
end
function Economy.completedLevels(state: any, owner: number): number
    local total = 0
    for _, city in state.cities or {} do if city.owner == owner and not city.underConstruction then total += city.level end end
    return total
end
function Economy.cityCost(state: any, owner: number, extra: number?): number
    if GameConfig.freeGold(state, owner) then return 0 end
    local count = math.min(Economy.ownedLevels(state, owner), (state.cityConstructed and state.cityConstructed[owner]) or 0) + (extra or 0)
    return math.min(GameConfig.forState(state).City.MaxCost, GameConfig.forState(state).City.BaseCost * 2 ^ math.min(count, 4))
end
-- PF036: the early-game boost for players and nations (never tribes): Multiplier at the Playing start (startTick, so the
-- spawn phase doesn't count), fading linearly to exactly x1 at FadeSeconds. 1 when off (the tutorial) or before Playing.
function Economy.earlyBoost(state: any, owner: number): number
    local config = GameConfig.forState(state)
    local boost = config.Economy.EarlyBoost
    local kind = state.players[owner].playerType
    if not boost or (kind ~= "Human" and kind ~= "Nation") or state.phase == "Choosing" or type(state.startTick) ~= "number" then return 1 end
    local seconds = (state.ticks - state.startTick) * config.Match.StepSeconds
    if seconds >= boost.FadeSeconds then return 1 end
    return 1 + (boost.Multiplier - 1) * math.max(0, 1 - seconds / boost.FadeSeconds)
end
function Economy.goldPerTick(state: any, owner: number): number
    local base = if state.players[owner].playerType == "Bot" then GameConfig.forState(state).Economy.BotGoldPerTick else GameConfig.forState(state).Economy.HumanGoldPerTick
    local human = if state.players[owner].playerType == "Human" then (GameConfig.forState(state).Economy.HumanGoldMultiplier or 1) else 1 -- the tutorial's ×5
    return math.floor(base * GameConfig.forState(state).Economy.GoldMultiplier * human * Economy.earlyBoost(state, owner) * Balance.goldFactor(state, owner))
end
function Economy.addGold(state: any, owner: number, amount: number)
    state.gold[owner] += amount
    state.goldEarned[owner] += amount
end
function Economy.distanceSquared(state: any, a: number, b: number): number
    local w = state.map.width
    local dx, dy = (a - 1) % w - (b - 1) % w, math.floor((a - 1) / w) - math.floor((b - 1) / w)
    return dx * dx + dy * dy
end
local function canAfford(state: any, owner: any): boolean
    return validOwner(state, owner) and GameConfig.forState(state).City.Enabled and state.counts[owner] > 0
        and state.gold[owner] >= Economy.cityCost(state, owner)
end
function Economy.spawnTile(state: any, owner: number, tile: number): number?
    if not validTile(state, tile) or state.owners[tile] ~= owner then return nil end
    -- PF-4: the same search with the config, coordinates and neighbour order (N, S, W, E, as MapData.neighbors)
    -- hoisted out of the inner loops. Structures.spawnTile is this exact search and now calls it.
    local config = GameConfig.forState(state)
    local width, owners = state.map.width, state.owners
    local count = width * state.map.height
    local tx, ty = (tile - 1) % width, (tile - 1) // width
    local searchRadius = config.City.SearchRadius
    local radiusSquared, nearRange, minSquared = searchRadius ^ 2, (searchRadius * 2) ^ 2, config.City.StructureMinDistance ^ 2
    local nearX, nearY, nearCount = {}, {}, 0
    for _, key in STRUCTURE_LISTS do
        for _, structure in state[key] or {} do
            if structure.active == false then continue end
            local z = structure.tileId - 1
            local sx, sy = z % width, z // width
            local dx, dy = sx - tx, sy - ty
            if dx * dx + dy * dy <= nearRange then nearCount += 1; nearX[nearCount] = sx; nearY[nearCount] = sy end
        end
    end
    local stack, visited, candidates = { tile }, { [tile] = true }, { tile }
    local top, candidateCount = 1, 1
    local function visit(t: number)
        if visited[t] or owners[t] ~= owner then return end
        local z = t - 1
        local dx, dy = z % width - tx, z // width - ty
        if dx * dx + dy * dy >= radiusSquared then return end
        visited[t] = true; top += 1; stack[top] = t; candidateCount += 1; candidates[candidateCount] = t
    end
    while top > 0 do
        local current = stack[top]; stack[top] = nil; top -= 1
        if current > width then visit(current - width) end
        if current <= count - width then visit(current + width) end
        local cx = (current - 1) % width
        if cx > 0 then visit(current - 1) end
        if cx < width - 1 then visit(current + 1) end
    end
    local best, bestDistance = nil, math.huge
    for i = 1, candidateCount do
        local candidate = candidates[i]
        local z = candidate - 1
        local cx, cy = z % width, z // width
        local dx, dy = cx - tx, cy - ty
        local d = dx * dx + dy * dy
        if d >= bestDistance then continue end -- Stable nearest-distance sort, traversal breaks ties.
        local blocked = false
        for j = 1, nearCount do
            local ex, ey = cx - nearX[j], cy - nearY[j]
            if ex * ex + ey * ey < minSquared then blocked = true break end
        end
        if not blocked then best, bestDistance = candidate, d end
    end
    return best
end
function Economy.canBuildCity(state: any, owner: number, tile: number): number?
    if not canAfford(state, owner) then return nil end
    return Economy.spawnTile(state, owner, tile)
end
function Economy.canUpgradeCity(state: any, owner: number, id: number): boolean
    if not canAfford(state, owner) then return false end
    local city = Economy.city(state, id)
    return city ~= nil and city.owner == owner and not city.underConstruction and city.deletionMarkedTick == nil
end
function Economy.canDeleteCity(state: any, owner: number, id: number): boolean
    if not validOwner(state, owner) or state.phase == "Choosing" then return false end
    local city = Economy.city(state, id)
    return city ~= nil and city.owner == owner and state.owners[city.tileId] == owner and state.map.land[city.tileId]
        and state.ticks - state.lastDeleteTicks[owner] >= GameConfig.forState(state).City.DeleteCooldownTicks
end
function Economy.queryBuildableCity(state: any, owner: number, tile: number): any
    local result: any = { type = "City", cost = if validOwner(state, owner) then Economy.cityCost(state, owner) else GameConfig.forState(state).City.BaseCost,
        canBuild = false, canUpgrade = false }
    if state.phase == "Choosing" or not validTile(state, tile) or not canAfford(state, owner) then return result end
    local nearest, distance, nearestCell = nil, math.huge, math.huge
    for _, city in state.cities or {} do
        local d = Economy.distanceSquared(state, tile, city.tileId)
        -- UnitGrid traverses 100x100 cells row-major, then creation order.
        local x, y = (city.tileId - 1) % state.map.width, math.floor((city.tileId - 1) / state.map.width)
        local cell = math.floor(y / 100) * math.ceil(state.map.width / 100) + math.floor(x / 100)
        if d <= GameConfig.forState(state).City.StructureMinDistance ^ 2 and (d < distance or (d == distance and cell < nearestCell)) then
            nearest, distance, nearestCell = city, d, cell
        end
    end
    if nearest and Economy.canUpgradeCity(state, owner, nearest.id) then
        result.canUpgrade, result.upgradeCosts = nearest.id, {}
        local total = 0
        for extra = 0, GameConfig.forState(state).City.MaxUpgradeAmount - 1 do total += Economy.cityCost(state, owner, extra) table.insert(result.upgradeCosts, total) end
    end
    result.canBuild = Economy.canBuildCity(state, owner, tile) or false
    return result
end
function Economy.maxAffordableUpgrades(costs: { number }?, gold: number): number
    local max = 0
    for amount, cost in costs or {} do if cost <= gold then max = amount else break end end
    return max
end
local function removeOrder(state: any, owner: number, id: number)
    local index = table.find(state.cityOrders[owner], id)
    if index then table.remove(state.cityOrders[owner], index) end
end
local function recordAcquisition(state: any, unit: any)
    state.unitAcquisitionOrder = state.unitAcquisitionOrder or {}
    local order = state.nextUnitAcquisitionOrder or state.nextUnitId or unit.id
    state.unitAcquisitionOrder[unit.id] = order
    state.nextUnitAcquisitionOrder = order + 1
end
function Economy.removeCity(state: any, city: any)
    if city.active == false then return end
    city.active = false
    if state.recordUnitDeath then state.recordUnitDeath(city, "City") end
    if state.removeRailStation then state.removeRailStation(city) end
    removeOrder(state, city.owner, city.id)
    local index = table.find(state.cities, city)
    if index then table.remove(state.cities, index) end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[city.id] = nil end
end
function Economy.playerTick(state: any, owner: number)
    -- Source PlayerExecution captures structures before checking whether their old owner died.
    for _, city in Economy.ownedCities(state, owner) do
        local nextOwner = state.owners[city.tileId]
        if nextOwner <= 0 then Economy.removeCity(state, city)
        elseif nextOwner ~= owner then
            removeOrder(state, owner, city.id)
            city.owner, city.deletionMarkedTick = nextOwner, nil
            table.insert(state.cityOrders[nextOwner], city.id)
            recordAcquisition(state, city)
        end
    end
    if state.counts[owner] <= 0 then
        state.gold[owner] = 0
        for _, city in Economy.ownedCities(state, owner) do Economy.removeCity(state, city) end
        return
    end
    Economy.addGold(state, owner, Economy.goldPerTick(state, owner))
end
function Economy.conquerPlayer(state: any, captor: number, victim: number)
    local human = state.players[victim].playerType == "Human"
    local skip = human and state.attacksSent[victim] == 0
    local captured = if skip then 0 else (if human then math.floor(state.gold[victim] / 2) else state.gold[victim])
    if not skip then
        Economy.addGold(state, captor, captured)
        state.gold[victim] = 0
    end
    -- GameImpl.conquerPlayer emits this even when the protected victim yields0.
    -- IDs/tick are transport metadata; identity/amount match ConquestUpdate.
    state.conquestEvents = state.conquestEvents or {}
    local eventId = state.nextConquestEventId or 1
    table.insert(state.conquestEvents, { id = eventId, tick = state.ticks,
        conquerorId = state.players[captor].id, conqueredId = state.players[victim].id, gold = captured })
    state.nextConquestEventId = eventId + 1
end
function Economy.initExecution(state: any, execution: any): boolean
    if execution.kind == "BuildCity" then return validTile(state, execution.tileId) and GameConfig.forState(state).City.Enabled end
    if execution.kind == "UpgradeCity" then
        for _ = 1, execution.amount do
            if not Economy.canUpgradeCity(state, execution.owner, execution.unitId) then break end
            local city = Economy.city(state, execution.unitId)
            state.gold[execution.owner] -= Economy.cityCost(state, execution.owner)
            city.level += 1 state.cityConstructed[execution.owner] += 1
        end
        return false
    end
    if execution.kind == "DeleteCity" and Economy.canDeleteCity(state, execution.owner, execution.unitId) then
        state.lastDeleteTicks[execution.owner] = state.ticks
        Economy.city(state, execution.unitId).deletionMarkedTick = state.ticks + GameConfig.forState(state).City.DeletionMarkTicks
        return true
    end
    return false
end
function Economy.tickExecution(state: any, execution: any): boolean
    if execution.kind == "BuildCity" then
        if execution.unitId == nil then
            local tile = Economy.canBuildCity(state, execution.owner, execution.tileId)
            if not tile then return false end
            local city = { id = state.nextUnitId, owner = execution.owner, tileId = tile, level = 1,
                underConstruction = true, createdTick = state.ticks }
            state.nextUnitId += 1
            state.gold[execution.owner] -= Economy.cityCost(state, execution.owner)
            state.cityConstructed[execution.owner] += 1
            table.insert(state.cities, city) table.insert(state.cityOrders[execution.owner], city.id)
            recordAcquisition(state, city)
            if state.recordTutorialAction then state.recordTutorialAction(execution.owner,"city") end
            execution.unitId, execution.remaining = city.id, GameConfig.forState(state).City.ConstructionTicks
            if execution.remaining == 0 then
                city.underConstruction = false
                table.insert(state.pendingExecutions, { kind = "CityStation", unitId = city.id })
                return false
            end
            return true
        end
        local city = Economy.city(state, execution.unitId)
        if not city then return false end
        if execution.remaining == 0 then
            city.underConstruction = false
            table.insert(state.pendingExecutions, { kind = "CityStation", unitId = city.id })
            return false
        end
        execution.remaining -= 1 return true
    end
    if execution.kind == "DeleteCity" then
        local city = Economy.city(state, execution.unitId)
        if not city then return false end
        if city.deletionMarkedTick and state.ticks > city.deletionMarkedTick then Economy.removeCity(state, city) return false end
        return true
    end
    return false
end
return table.freeze(Economy)
