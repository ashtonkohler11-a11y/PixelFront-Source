--!strict
--!native
-- OpenFrontIO 93a136a1: Warship/Shell/MoveWarship executions, UnitImpl and UnitGrid.
-- Simulation supplies one ordered queue and active object references. See WARSHIP_RULES_BRIEF.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Random = require(script.Parent.OpenFrontRandom)
local Navigation = require(script.Parent.OpenFrontNavigation)
local MapData = require(script.Parent.MapData)
local Ports = require(script.Parent.OpenFrontPorts)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Warships = {}

local function integer(value: any): boolean return type(value) == "number" and value == value and math.abs(value) < math.huge and value % 1 == 0 end
local function validTile(state: any, tile: any): boolean return integer(tile) and tile >= 1 and tile <= state.map.width * state.map.height end
local function validOwner(state: any, owner: any): boolean return integer(owner) and owner >= 1 and owner <= #state.players end
local function navFor(state: any, api: any): any return (api and api.navigation) or Navigation.forMap(state.map) end
local function shoreline(state: any, tile: number, nav: any): boolean
    if nav.isShoreline then return nav:isShoreline(tile) end
    return bit32.band(buffer.readu8(state.map.terrain, tile - 1), 64) ~= 0
end
local function active(unit: any): boolean return unit ~= nil and unit.active ~= false end
local function unitType(unit: any): string return unit.unitType or "Transport" end
local function distance(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
local function distanceSquared(state: any, a: number, b: number): number
    local w = state.map.width
    local dx, dy = (a - 1) % w - (b - 1) % w, math.floor((a - 1) / w) - math.floor((b - 1) / w)
    return dx * dx + dy * dy
end
local function emit(api: any, event: any) if api and api.message then api.message(event) end end
local function increment(state: any, key: string, owner: number, amount: number)
    state[key] = state[key] or {}; state[key][owner] = (state[key][owner] or 0) + amount
end
local function ownPorts(state: any, owner: number): {any}
    local result = {}
    for _, port in Ports.ownedPorts(state, owner) do if active(port) and port.owner == owner then table.insert(result, port) end end
    return result
end
function Warships.ship(state: any, id: number): any
    local ship = Index.byId(state.warships, id) -- PF-4: ids are unique, so the first match is the only one
    return if ship ~= nil and active(ship) then ship else nil
end
function Warships.ownedShips(state: any, owner: number): {any}
    local result = {}
    for _, ship in state.warships or {} do if ship.owner == owner and active(ship) then table.insert(result, ship) end end
    if state.unitAcquisitionOrder then
        table.sort(result, function(a, b) return (state.unitAcquisitionOrder[a.id] or a.id) < (state.unitAcquisitionOrder[b.id] or b.id) end)
    end
    return result
end
function Warships.cost(state: any, owner: number, extra: number?): number
    if GameConfig.freeGold(state, owner) then return 0 end
    local count = 0
    for _, ship in Warships.ownedShips(state, owner) do count += ship.level or 1 end
    count = math.min(count, (state.warshipConstructed and state.warshipConstructed[owner]) or 0)
    return math.min(GameConfig.forState(state).Warship.MaxCost, (count + (extra or 0) + 1) * GameConfig.forState(state).Warship.BaseCost)
end
function Warships.spawnTile(state: any, owner: number, tile: number, navigation: any?): number?
    if not validTile(state, tile) then return nil end
    local nav = navigation or navFor(state, nil)
    if not nav:isWater(tile) then return nil end
    local component = nav:getWaterComponent(tile)
    if component == nil then return nil end
    local best, bestDistance = nil, math.huge
    for _, port in ownPorts(state, owner) do
        if port.underConstruction or not nav:hasWaterComponent(port.tileId, component) then continue end
        local dist = distance(state, port.tileId, tile)
        if dist < bestDistance then best, bestDistance = port.tileId, dist end
    end
    return best
end
function Warships.canBuildWarship(state: any, owner: number, tile: number, navigation: any?): number | false
    if not GameConfig.forState(state).Warship.Enabled or not validOwner(state, owner) or not validTile(state, tile)
        or state.counts[owner] <= 0 or state.gold[owner] < Warships.cost(state, owner) then return false end
    return Warships.spawnTile(state, owner, tile, navigation) or false
end
function Warships.queryBuildableWarship(state: any, owner: number, tile: number?, navigation: any?): any
    return {type = "Warship", canBuild = if tile and state.phase ~= "Choosing" then Warships.canBuildWarship(state, owner, tile, navigation) else false,
        canUpgrade = false, cost = Warships.cost(state, owner), upgradeCosts = {}}
end

-- UnitGrid order survives moves within a cell; crossing a cell appends to its set.
-- Naval/Trade call this after every create/move. Captures preserve grid position.
function Warships.trackUnit(state: any, unit: any)
    local typ = unitType(unit)
    if typ ~= "Transport" and typ ~= "Warship" and typ ~= "Trade Ship" then return end
    if state.warshipUnitGrid == nil then
        state.warshipUnitGrid = {}
        local all = {}
        for _, list in {state.ships or {}, state.warships or {}, state.tradeShips or {}} do for _, existing in list do if active(existing) then table.insert(all, existing) end end end
        table.sort(all, function(a, b) return a.id < b.id end)
        for _, existing in all do Warships.trackUnit(state, existing) end
    end
    local grid = state.warshipUnitGrid
    local w = state.map.width
    local cellX, cellY = math.floor(((unit.tileId - 1) % w) / 100), math.floor(math.floor((unit.tileId - 1) / w) / 100)
    local cell = cellY * math.ceil(w / 100) + cellX
    if unit._gridState == state and unit._gridCell == cell and active(unit) then return end
    if unit._gridState == state then
        local oldCell = grid[unit._gridCell]
        local previous = oldCell and oldCell[typ]
        if previous then for index, candidate in previous do if candidate == unit then table.remove(previous, index) break end end end
    end
    if not active(unit) then unit._gridState, unit._gridCell, unit._gridOrder = nil, nil, nil; return end
    state.warshipGridSequence = (state.warshipGridSequence or 0) + 1
    unit._gridState, unit._gridCell, unit._gridOrder = state, cell, state.warshipGridSequence
    grid[cell] = grid[cell] or {}; grid[cell][typ] = grid[cell][typ] or {}; table.insert(grid[cell][typ], unit)
end
function Warships.nearbyUnits(state: any, tile: number, range: number, types: {string}, api: any?): {any}
    if api and api.nearbyUnits then return api.nearbyUnits(tile, range, types) end
    if state.warshipUnitGrid == nil then
        local all = {}
        for _, list in {state.ships or {}, state.warships or {}, state.tradeShips or {}} do for _, unit in list do if active(unit) then table.insert(all, unit) end end end
        table.sort(all, function(a, b) return a.id < b.id end)
        state.warshipUnitGrid = {}
        for _, unit in all do Warships.trackUnit(state, unit) end
    end
    local nearby, w, h = {}, state.map.width, state.map.height
    local x, y = (tile - 1) % w, math.floor((tile - 1) / w)
    local gridX, gridY, cellsWide, cellsHigh = math.floor(x / 100), math.floor(y / 100), math.ceil(w / 100), math.ceil(h / 100)
    local startX, endX = math.max(0, gridX - math.ceil((range - x % 100) / 100)), math.min(cellsWide - 1, gridX + math.ceil((range - (100 - x % 100)) / 100))
    local startY, endY = math.max(0, gridY - math.ceil((range - y % 100) / 100)), math.min(cellsHigh - 1, gridY + math.ceil((range - (100 - y % 100)) / 100))
    for cy = startY, endY do for cx = startX, endX do
        local cell = state.warshipUnitGrid[cy * cellsWide + cx]
        if cell then for _, typ in types do
            for _, unit in cell[typ] or {} do
                if not active(unit) or unit.underConstruction then continue end
                local dist = distanceSquared(state, tile, unit.tileId)
                if dist <= range * range then table.insert(nearby, {unit = unit, distSquared = dist}) end
            end
        end end
    end end
    return nearby
end
local function move(state: any, unit: any, tile: number)
    unit.lastTileId, unit.tileId = unit.tileId, tile
    Warships.trackUnit(state, unit)
end
function Warships.deleteUnit(state: any, unit: any, displayMessage: boolean?, destroyer: number?, api: any?)
    if not active(unit) then return end
    unit.active, unit.wasDestroyedByEnemy, unit.destroyer = false, destroyer ~= nil, destroyer
    Warships.trackUnit(state, unit)
    local typ = unitType(unit)
    local list = if typ == "Warship" then state.warships elseif typ == "Shell" then state.shells
        elseif typ == "Trade Ship" then state.tradeShips else state.ships
    if list then for index, candidate in list do if candidate == unit then table.remove(list, index) break end end end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[unit.id] = nil end
    if displayMessage ~= false then
        if typ == "Transport" then increment(state, "shipsLost", unit.owner, 1)
        elseif typ == "Trade Ship" then increment(state, "tradeShipsLost", unit.owner, 1) end
        if typ == "Warship" or typ == "Transport" then
            emit(api, {key = "events_display.unit_destroyed", type = "UNIT_DESTROYED", owner = unit.owner,
                shipId = unit.id, unitId = unit.id, unit = if typ == "Warship" then "unit_type.warship" else "unit_type.boat"})
        end
    end
    if destroyer ~= nil then
        if typ == "Transport" then increment(state, "shipsDestroyed", destroyer, 1)
        elseif typ == "Trade Ship" then increment(state, "tradeShipsDestroyed", destroyer, 1)
        elseif typ == "Warship" then increment(state, "warshipsDestroyed", destroyer, 1); increment(state, "warshipsLost", unit.owner, 1) end
    end
    if api and api.deadUnit then api.deadUnit(unit) end
end
function Warships.maxHealth(unit: any): number
    if unitType(unit) ~= "Warship" then return unit.maxHealth or 1 end
    return Config.Warship.MaxHealth + math.floor(Config.Warship.MaxHealth * (unit.veterancy or 0) * Config.Warship.VeterancyHealthBonus / 100)
end
function Warships.modifyHealth(state: any, unit: any, delta: number, attacker: number?, api: any?)
    local before = unit.health or (if unitType(unit) == "Warship" then GameConfig.forState(state).Warship.MaxHealth else 1)
    local after = math.clamp(before + math.floor(delta), 0, Warships.maxHealth(unit))
    if before == after then return end
    if attacker ~= nil and delta < 0 and unitType(unit) == "Warship" then unit.lastCombatTick = state.ticks end
    unit.health = after
    if after == 0 then Warships.deleteUnit(state, unit, true, attacker, api) end
end
function Warships.isInCombat(state: any, ship: any): boolean return state.ticks - (ship.lastCombatTick or -100) <= 3 end
function Warships.warshipState(state: any, ship: any): any
    return {state = ship.state or "patrolling", patrolTile = ship.patrolTile, retreatPort = ship.retreatPort,
        isInCombat = Warships.isInCombat(state, ship), veterancy = ship.veterancy or 0, veterancyProgress = ship.veterancyProgress or 0}
end
local function addVeterancyProgress(ship: any, typ: string)
    if (ship.veterancy or 0) >= Config.Warship.MaxVeterancy then return end
    local transports, captures = Config.Warship.VeterancyTransportKills, Config.Warship.VeterancyTradeCaptures
    ship.veterancyProgress = (ship.veterancyProgress or 0) + (if typ == "Transport" then captures else transports)
    while ship.veterancyProgress >= transports * captures and (ship.veterancy or 0) < Config.Warship.MaxVeterancy do
        ship.veterancyProgress -= transports * captures; ship.veterancy = (ship.veterancy or 0) + 1
    end
    if ship.veterancy >= Config.Warship.MaxVeterancy then ship.veterancyProgress = 0 end
end
function Warships.recordKill(ship: any, typ: string)
    if unitType(ship) ~= "Warship" then return end
    if typ == "Warship" then
        ship.veterancyProgress = 0
        ship.veterancy = math.min(Config.Warship.MaxVeterancy, (ship.veterancy or 0) + 1)
    elseif typ == "Transport" then addVeterancyProgress(ship, typ) end
end
function Warships.recordTradeCapture(ship: any) if unitType(ship) == "Warship" then addVeterancyProgress(ship, "Trade Ship") end end
local function friendly(owner: number, other: number, api: any): boolean
    return if api and api.friendly then api.friendly(owner, other) else owner == other
end
local function canAttack(state: any, owner: number, other: number, api: any): boolean
    if api and api.canAttack then return api.canAttack(owner, other, true) end
    if friendly(owner, other, api) then return false end
    if state.players[owner].playerType ~= "Human" or state.players[other].playerType == "Bot" then return true end
    return state.phase ~= "Choosing" and state.ticks - (state.startTick or 0) >= 50
end
local function doomed(state: any, owner: number, api: any): boolean
    if api and api.inDoomsdayClock then return api.inDoomsdayClock(owner) end
    return state.inDoomsdayClock ~= nil and state.inDoomsdayClock[owner] == true
end
local function setTarget(ship: any, unit: any) ship._targetUnit, ship.targetUnitId = unit, if unit then unit.id else nil end
local function getTradeTarget(state: any, ship: any): any
    if ship._targetUnit then return ship._targetUnit end
    for _, port in state.ports or {} do if port.id == ship.targetPortId then return port end end
    return nil
end
local function nearestPort(state: any, ship: any, api: any): number?
    local ports = ownPorts(state, ship.owner)
    if #ports == 0 then return nil end
    local nav, best, bestDistance = navFor(state, api), nil, math.huge
    local component = nav:getWaterComponent(ship.tileId)
    assert(component ~= nil, "Warship has no water component")
    for _, port in ports do
        local portComponent = nav:getWaterComponent(port.tileId)
        assert(portComponent ~= nil, "Port has no water component")
        if portComponent ~= component then continue end
        local dist = distanceSquared(state, ship.tileId, port.tileId)
        if dist < bestDistance then best, bestDistance = port.tileId, dist end
    end
    return best
end
local function currentPort(state: any, ship: any): any
    if ship.retreatPort == nil then return nil end
    for _, port in ownPorts(state, ship.owner) do if port.tileId == ship.retreatPort then return port end end
    return nil
end
local function dockedShips(state: any, ship: any, port: any, exclude: any, api: any): {any}
    local result = {}
    for _, entry in Warships.nearbyUnits(state, port.tileId, GameConfig.forState(state).Warship.DockingRange, {"Warship"}, api) do
        local candidate = entry.unit
        if candidate ~= exclude and candidate.owner == ship.owner and candidate.state ~= "patrolling" and candidate.targetTileId == nil then table.insert(result, candidate) end
    end
    return result
end
local function portFull(state: any, ship: any, port: any, exclude: any, api: any): boolean return #dockedShips(state, ship, port, exclude, api) >= port.level end
local function nearestAvailable(state: any, ship: any, exclude: any, api: any): any
    local nav, best, bestDistance = navFor(state, api), nil, math.huge
    local component = nav:getWaterComponent(ship.tileId)
    assert(component ~= nil, "Warship has no water component")
    for _, port in ownPorts(state, ship.owner) do
        if portFull(state, ship, port, exclude, api) or not nav:hasWaterComponent(port.tileId, component) then continue end
        local dist = distanceSquared(state, ship.tileId, port.tileId)
        if dist < bestDistance then best, bestDistance = port.tileId, dist end
    end
    return if best ~= nil then {tile = best, distSquared = bestDistance} else nil
end
local function cancelRetreat(execution: any, clearTarget: boolean?)
    execution.activeHealingRemainder = 0
    execution.ship.state, execution.ship.retreatPort = "patrolling", nil
    if clearTarget ~= false then execution.ship.targetTileId = nil end
end
local function fullyHealed(ship: any): boolean return ship.health >= Warships.maxHealth(ship) end
local function heal(state: any, execution: any, api: any)
    local ship = execution.ship
    if doomed(state, ship.owner, api) then return end
    for _, port in ownPorts(state, ship.owner) do
        if distanceSquared(state, ship.tileId, port.tileId) <= GameConfig.forState(state).Warship.PassiveHealingRange ^ 2 then
            Warships.modifyHealth(state, ship, GameConfig.forState(state).Warship.PassiveHealing, nil, api); break
        end
    end
    if ship.state ~= "docked" then return end
    local port = currentPort(state, ship)
    if not port then return end
    local ships = dockedShips(state, ship, port, nil, api)
    if not table.find(ships, ship) or #ships == 0 then return end
    local pool = port.level * GameConfig.forState(state).Warship.PortHealingPerLevel
    if pool <= 0 then return end
    execution.activeHealingRemainder += pool / #ships
    local integerHealing = math.floor(execution.activeHealingRemainder)
    if integerHealing <= 0 then return end
    execution.activeHealingRemainder -= integerHealing
    Warships.modifyHealth(state, ship, integerHealing, nil, api)
end
function Warships.findBestTarget(state: any, execution: any, types: {string}, includeTradeShips: boolean?, api: any?): any
    local ship, nav, reachable, component, patrolRange = execution.ship, navFor(state, api), nil, nil, GameConfig.forState(state).Warship.PatrolRange ^ 2
    local best, bestPriority, bestDistance = nil, 0, 0
    for _, entry in Warships.nearbyUnits(state, ship.tileId, GameConfig.forState(state).Warship.TargetingRange, types, api) do
        local candidate, typ = entry.unit, unitType(entry.unit)
        if candidate == ship or candidate.owner == ship.owner or not canAttack(state, ship.owner, candidate.owner, api)
            or execution.alreadySentShell[candidate] or (typ == "Warship" and candidate.state == "docked") then continue end
        if includeTradeShips and typ == "Trade Ship" then
            if reachable == nil then
                component, reachable = nav:getWaterComponent(ship.tileId), false
                if component ~= nil then for _, port in ownPorts(state, ship.owner) do
                    if port.deletionMarkedTick == nil and not port.underConstruction and nav:hasWaterComponent(port.tileId, component) then reachable = true break end
                end end
            end
            local destination = getTradeTarget(state, candidate)
            if not reachable or ship.patrolTile == nil or state.ticks - (candidate.lastSetSafeFromPirates or 0) < GameConfig.forState(state).Trade.SafeFromPiratesTicks
                or (destination and (destination.owner == ship.owner or friendly(destination.owner, ship.owner, api)))
                or distanceSquared(state, ship.patrolTile, candidate.tileId) > patrolRange then continue end
            -- PF044 Trade Guild (PremiumItems.tradeSafe): its owner's ships near its owner's Ports can't be taken
            if state.premium and state.premium.guildActive and state.premium.tradeSafe(state, candidate) then continue end
        end
        local priority = if typ == "Transport" then 0 elseif typ == "Warship" then 1 else 2
        if best == nil or priority < bestPriority or (priority == bestPriority and entry.distSquared < bestDistance) then
            best, bestPriority, bestDistance = candidate, priority, entry.distSquared
        end
    end
    return best
end
local function shoot(state: any, execution: any)
    local ship, target = execution.ship, execution.ship._targetUnit
    ship.lastCombatTick = state.ticks
    if state.ticks - execution.lastShellAttack <= GameConfig.forState(state).Warship.ShellAttackRate then return end
    if unitType(target) ~= "Transport" then execution.lastShellAttack = state.ticks end
    table.insert(state.pendingExecutions, {kind = "Shell", spawn = ship.tileId, owner = ship.owner, ownerUnit = ship, target = target})
    if unitType(target) ~= "Warship" and target.maxHealth == nil then
        execution.alreadySentShell[target] = true; setTarget(ship, nil)
    end
end
local function refreshPort(state: any, execution: any, api: any): boolean
    local ship = execution.ship
    if #ownPorts(state, ship.owner) == 0 then return false end
    local port = currentPort(state, ship)
    if port == nil then
        local nearest = nearestAvailable(state, ship, ship, api)
        ship.retreatPort = if nearest then nearest.tile else nil
        return ship.retreatPort ~= nil
    end
    if portFull(state, ship, port, nil, api) then
        local alternative = nearestAvailable(state, ship, nil, api)
        if alternative then ship.retreatPort = alternative.tile end
        return ship.retreatPort ~= nil
    end
    local better = nearestAvailable(state, ship, nil, api)
    local currentDistance = distanceSquared(state, ship.tileId, ship.retreatPort)
    if better and better.distSquared < currentDistance * GameConfig.forState(state).Warship.PortSwitchThreshold and better.tile ~= ship.retreatPort then ship.retreatPort = better.tile end
    return true
end
local function repairRetreat(state: any, execution: any, api: any): boolean
    local ship = execution.ship
    if ship.state == "patrolling" then return false end
    local target = Warships.findBestTarget(state, execution, {"Transport", "Warship"}, false, api)
    if target then setTarget(ship, target); shoot(state, execution) end
    if not refreshPort(state, execution, api) then cancelRetreat(execution) return false end
    if not target then setTarget(ship, nil) end
    if ship.retreatPort == nil then return false end
    if distanceSquared(state, ship.tileId, ship.retreatPort) <= GameConfig.forState(state).Warship.DockingRange ^ 2 then
        local port = currentPort(state, ship)
        if port and not portFull(state, ship, port, ship, api) then
            ship.targetTileId, ship.state = nil, "docked"; return true
        end
        if fullyHealed(ship) then cancelRetreat(execution) return false end
        return true
    end
    ship.targetTileId = ship.retreatPort
    local result = execution.pathFinder:next(ship.tileId, ship.retreatPort)
    if result.status == "complete" then
        move(state, ship, result.node); if result.node == ship.retreatPort then ship.targetTileId = nil end
    elseif result.status == "next" then move(state, ship, result.node)
    elseif result.status == "not_found" then
        local nearest = nearestAvailable(state, ship, ship, api)
        ship.retreatPort = if nearest then nearest.tile else nil
        if ship.retreatPort == nil then cancelRetreat(execution) end
    end
    return true
end
function Warships.randomTile(state: any, execution: any, api: any?, allowShoreline: boolean?): number?
    local ship, nav, patrolRange = execution.ship, navFor(state, api), GameConfig.forState(state).Warship.PatrolRange
    local attempts, expansions = 0, 0
    local component = nav:getWaterComponent(ship.tileId)
    if not validTile(state, ship.patrolTile) then return nil end
    local w, h = state.map.width, state.map.height
    while expansions < 3 do
        local x = (ship.patrolTile - 1) % w + Random.int(execution.random, -patrolRange / 2, patrolRange / 2)
        local y = math.floor((ship.patrolTile - 1) / w) + Random.int(execution.random, -patrolRange / 2, patrolRange / 2)
        if x < 0 or y < 0 or x >= w or y >= h then continue end
        local tile = y * w + x + 1
        if not nav:isWater(tile) or (not allowShoreline and shoreline(state, tile, nav)) or (component ~= nil and not nav:hasWaterComponent(tile, component)) then
            attempts += 1
            if attempts == 500 then expansions += 1; attempts = 0; patrolRange += math.floor(patrolRange / 2) end
            continue
        end
        return tile
    end
    if not allowShoreline then return Warships.randomTile(state, execution, api, true) end
    return nil
end
local function patrol(state: any, execution: any, api: any)
    local ship = execution.ship
    if ship.targetTileId == nil then ship.targetTileId = Warships.randomTile(state, execution, api); if ship.targetTileId == nil then return end end
    local result = execution.pathFinder:next(ship.tileId, ship.targetTileId)
    if result.status == "complete" then ship.targetTileId = nil; move(state, ship, result.node)
    elseif result.status == "next" then move(state, ship, result.node)
    elseif result.status == "not_found" then ship.targetTileId = nil end
end
local function captureTrade(state: any, execution: any)
    local ship, target = execution.ship, execution.ship._targetUnit
    target.lastOwner, target.owner = target.owner, ship.owner
    if state.unitAcquisitionOrder then
        state.unitAcquisitionOrder[target.id] = state.nextUnitAcquisitionOrder
        state.nextUnitAcquisitionOrder += 1
    end
    Warships.recordTradeCapture(ship); setTarget(ship, nil)
end
local function hunt(state: any, execution: any, api: any)
    local ship, nav = execution.ship, navFor(state, api)
    ship.lastCombatTick = state.ticks
    for _ = 1, 2 do
        local target = ship._targetUnit
        local dist = distance(state, ship.tileId, target.tileId)
        if dist <= 5 then captureTrade(state, execution) return end
        if dist <= 20 then
            local best, bestDist = nil, dist
            for _, neighbor in MapData.neighbors(ship.tileId, state.map.width, state.map.height) do
                if not nav:isWater(neighbor) then continue end
                local d = distance(state, neighbor, target.tileId)
                if d < bestDist then best, bestDist = neighbor, d end
            end
            if best ~= nil then move(state, ship, best) continue end
        end
        local result = execution.pathFinder:next(ship.tileId, target.tileId, 5)
        if result.status == "complete" then captureTrade(state, execution) return
        elseif result.status == "next" then move(state, ship, result.node) end
    end
end
function Warships.moveWarships(state: any, owner: number, ids: {number}, position: number, navigation: any?): number
    if not validOwner(state, owner) or not validTile(state, position) then return 0 end
    local nav, count, seen = navigation or navFor(state, nil), 0, {}
    local component = nav:getWaterComponent(position)
    local units = {}; for _, ship in Warships.ownedShips(state, owner) do units[ship.id] = ship end
    for _, id in ids do
        if seen[id] then continue end
        seen[id] = true
        local ship = units[id]
        if ship == nil or not active(ship) or not nav:hasWaterComponent(ship.tileId, component) then continue end
        ship.patrolTile, ship.targetTileId = position, nil; count += 1
    end
    return count
end
function Warships.playerDeath(state: any, owner: number, api: any?)
    -- Source PlayerExecution becomes inactive after its first death cleanup.
    -- A ShellExecution initialized before death may build its Shell afterward;
    -- it then retains the source fifty-tick firing-unit-death lifetime.
    state.navalDeathCleanupDone = state.navalDeathCleanupDone or {}
    if state.navalDeathCleanupDone[owner] then return end
    state.navalDeathCleanupDone[owner] = true
    local remaining, acquisition = {}, state.unitAcquisitionOrder or {}
    for _, pair in {{state.ships or {},"Transport"},{state.tradeShips or {},"Trade Ship"},{state.warships or {},"Warship"},
        {state.shells or {},"Shell"},{state.trains or {},"Train"},{state.cities or {},"City"},{state.ports or {},"Port"},
        {state.factories or {},"Factory"},{state.defensePosts or {},"Defense Post"},{state.missileSilos or {},"Missile Silo"},
        {state.samLaunchers or {},"SAM Launcher"},{state.samMissiles or {},"SAMMissile"}} do
        for _, unit in pair[1] do if unit.owner == owner and active(unit) then
            unit.unitType = unit.unitType or pair[2]; table.insert(remaining, unit)
        end end
    end
    table.sort(remaining, function(a, b) return (acquisition[a.id] or a.id) < (acquisition[b.id] or b.id) end)
    for _, unit in remaining do
        if (unitType(unit)=="City" or unitType(unit)=="Port" or unitType(unit)=="Factory" or unitType(unit)=="Defense Post")
            and state.removeStructureUnit then state.removeStructureUnit(unit)
        elseif unitType(unit) == "Train" and state.removeTrainUnit then state.removeTrainUnit(unit)
        elseif (unitType(unit) == "Missile Silo" or unitType(unit) == "SAM Launcher" or unitType(unit) == "SAMMissile") and state.removeWeaponUnit then state.removeWeaponUnit(unit)
        else Warships.deleteUnit(state, unit, nil, nil, api) end
    end
end

-- AirPathFinder re-seeds each path query; its random generator is distinct from damage.
function Warships.airPath(state: any, seed: number, from: number, to: number): {number}
    local random, w, path, current = Random.new(seed), state.map.width, {from}, from
    while current ~= to do
        local x, y = (current - 1) % w, math.floor((current - 1) / w)
        local tx, ty = (to - 1) % w, math.floor((to - 1) / w)
        local nx, ny = x, y
        local ratio = math.floor(1 + math.abs(ty - y) / (math.abs(tx - x) + 1))
        if x == tx then ny += if y < ty then 1 else -1
        elseif y == ty then nx += if x < tx then 1 else -1
        elseif Random.int(random, 0, ratio) == 0 then nx += if x < tx then 1 else -1
        else ny += if y < ty then 1 else -1 end
        local nextTile = ny * w + nx + 1
        if nextTile == current then break end
        current = nextTile; table.insert(path, current)
    end
    return path
end
local AirStepper = {}; AirStepper.__index = AirStepper
function AirStepper:next(from: number, to: number): any
    if from == to then return {status = "complete", node = to} end
    if self.lastTo ~= to then self.path, self.index, self.lastTo = nil, 1, to end
    if self.path == nil then
        self.path, self.index = Warships.airPath(self.state, self.seed, from, to), 1
        if self.path[1] == from then self.index = 2 end
    end
    if self.index > 1 and from ~= self.path[self.index - 1] then
        self.path, self.index, self.lastTo = nil, 1, to; return self:next(from, to)
    end
    if self.index > #self.path then return {status = "complete", node = to} end
    local node = self.path[self.index]; self.index += 1; return {status = "next", node = node}
end
function Warships.shellDamage(execution: any): number
    local multiplier = (Random.int(execution.random, 1, 6) - 1) * 25 + 200
    local veterancy = execution.ownerUnit.veterancy or 0
    if veterancy > 0 then multiplier = math.floor(multiplier * (100 + veterancy * Config.Warship.VeterancyDamageBonus) / 100) end
    return math.floor((Config.Warship.ShellDamage / 250) * multiplier + 0.5)
end
function Warships.initExecution(state: any, execution: any, api: any?): boolean
    if execution.kind == "BuildWarship" then return GameConfig.forState(state).Warship.Enabled and validTile(state, execution.tileId) end
    if execution.kind == "MoveWarship" then Warships.moveWarships(state, execution.owner, execution.unitIds, execution.position, if api then api.navigation else nil) return false end
    if execution.kind == "Shell" then
        execution.pathFinder = setmetatable({state = state, seed = state.ticks, path = nil, index = 1, lastTo = nil}, AirStepper)
        execution.random, execution.destroyAtTick = Random.new(state.ticks), -1
        return true
    end
    if execution.kind ~= "Warship" then return false end
    execution.random, execution.pathFinder = Random.new(state.ticks), navFor(state, api):newStepper()
    execution.lastShellAttack, execution.alreadySentShell, execution.lastManualMoveTickRetreatDisabled = 0, {}, 0
    execution.activeHealingRemainder, execution.lastEmittedCombat = 0, false
    local ship = execution.ship or (if execution.unitId then Warships.ship(state, execution.unitId) else nil)
    if ship == nil then
        local spawn = Warships.canBuildWarship(state, execution.owner, execution.patrolTile, if api then api.navigation else nil)
        if spawn == false then return false end
        local cost = Warships.cost(state, execution.owner)
        ship = {id = state.nextUnitId, owner = execution.owner, unitType = "Warship", tileId = spawn, lastTileId = spawn,
            health = GameConfig.forState(state).Warship.MaxHealth, active = true, level = 1, createdTick = state.ticks, state = "patrolling", patrolTile = execution.patrolTile,
            lastCombatTick = -100, veterancy = 0, veterancyProgress = 0}
        state.nextUnitId += 1; state.warships = state.warships or {}; table.insert(state.warships, ship)
        increment(state, "warshipConstructed", execution.owner, 1); state.gold[execution.owner] -= cost
        if state.unitAcquisitionOrder then state.unitAcquisitionOrder[ship.id] = state.nextUnitAcquisitionOrder; state.nextUnitAcquisitionOrder += 1 end
        Warships.trackUnit(state, ship)
    end
    execution.ship, execution.shipId, execution.lastObservedPatrolTile = ship, ship.id, ship.patrolTile
    return active(ship)
end
function Warships.tickExecution(state: any, execution: any, api: any?): boolean
    if execution.kind == "BuildWarship" then
        table.insert(state.pendingExecutions, {kind = "Warship", owner = execution.owner, patrolTile = execution.tileId}); return false
    end
    if execution.kind == "Shell" then
        local shell = execution.shell
        if shell == nil then
            shell = {id = state.nextUnitId, owner = execution.owner, unitType = "Shell", tileId = execution.spawn, lastTileId = execution.spawn,
                active = true, health = 1, createdTick = state.ticks, reachedTarget = false}
            state.nextUnitId += 1; state.shells = state.shells or {}; table.insert(state.shells, shell); execution.shell = shell
            if state.unitAcquisitionOrder then state.unitAcquisitionOrder[shell.id] = state.nextUnitAcquisitionOrder; state.nextUnitAcquisitionOrder += 1 end
        end
        if not active(shell) then return false end
        if not active(execution.target) or execution.target.owner == shell.owner or (execution.destroyAtTick ~= -1 and state.ticks >= execution.destroyAtTick) then
            Warships.deleteUnit(state, shell, false, nil, api); return false
        end
        if execution.destroyAtTick == -1 and not active(execution.ownerUnit) then execution.destroyAtTick = state.ticks + GameConfig.forState(state).Warship.ShellLifetime end
        for _ = 1, 3 do
            local result = execution.pathFinder:next(shell.tileId, execution.target.tileId)
            if result.status == "complete" then
                local target, targetType, wasActive = execution.target, unitType(execution.target), active(execution.target)
                Warships.modifyHealth(state, target, -Warships.shellDamage(execution), execution.owner, api)
                if wasActive and not active(target) and active(execution.ownerUnit) and unitType(execution.ownerUnit) == "Warship" then Warships.recordKill(execution.ownerUnit, targetType) end
                shell.reachedTarget = true; Warships.deleteUnit(state, shell, false, nil, api); return false
            elseif result.status == "next" then move(state, shell, result.node) end
        end
        return true
    end
    if execution.kind ~= "Warship" then return false end
    local ship = execution.ship
    if not active(ship) then return false end
    if ship.health <= 0 then Warships.deleteUnit(state, ship, nil, nil, api); return false end
    execution.lastEmittedCombat = Warships.isInCombat(state, ship)
    local healthBeforeHealing = ship.health
    heal(state, execution, api)
    if execution.lastObservedPatrolTile ~= nil and ship.patrolTile ~= execution.lastObservedPatrolTile then
        execution.lastManualMoveTickRetreatDisabled = state.ticks
        if ship.state ~= "patrolling" then cancelRetreat(execution, false) end
    end
    execution.lastObservedPatrolTile = ship.patrolTile
    if doomed(state, ship.owner, api) and ship.state ~= "patrolling" then cancelRetreat(execution) end
    if ship.state == "docked" then
        if currentPort(state, ship) == nil or fullyHealed(ship) then cancelRetreat(execution) end
        if ship.state == "docked" then return true end
    end
    if repairRetreat(state, execution, api) then return true end
    if ship.state == "patrolling" and not doomed(state, ship.owner, api)
        and state.ticks - execution.lastManualMoveTickRetreatDisabled >= 50
        and healthBeforeHealing < math.floor(Warships.maxHealth(ship) * GameConfig.forState(state).Warship.RetreatHealthPercent / 100)
        and #ownPorts(state, ship.owner) > 0 then
        local port = nearestPort(state, ship, api)
        if port ~= nil then ship.retreatPort, ship.state = port, "retreating"; execution.activeHealingRemainder = 0; setTarget(ship, nil) end
        if repairRetreat(state, execution, api) then return true end
    end
    local target = Warships.findBestTarget(state, execution, {"Transport", "Warship", "Trade Ship"}, true, api)
    setTarget(ship, target)
    if target and (unitType(target) == "Transport" or unitType(target) == "Warship") then shoot(state, execution); patrol(state, execution, api)
    elseif target and unitType(target) == "Trade Ship" then hunt(state, execution, api)
    else patrol(state, execution, api) end
    return true
end
return table.freeze(Warships)
