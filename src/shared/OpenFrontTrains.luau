--!strict
--!native
-- OpenFrontIO 93a136a1: TrainExecution, TrainStation stop handlers and Config.
-- Each train is seven actual units; cars are ordered tail-engine then back to front.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Math = require(script.Parent.OpenFrontMath)
local Rails = require(script.Parent.OpenFrontRails)
local Trains = {}

local function active(unit: any): boolean return unit ~= nil and unit.active ~= false end
function Trains.saturation(count: number): number
    local boost = 1 + 0.5 * Math.exp(-count / 30)
    local damping = 1 - 1 / (1 + Math.exp(-(0.6931471805599453 / 100) * (count - 560)))
    local plateau = 0.25 * (1 - 1 / (1 + Math.exp(-(0.6931471805599453 / 150) * (count - 900))))
    return boost * math.max(damping, plateau)
end
function Trains.spawnRate(factories: number, unitCount: number): number
    return math.max(1, math.floor((factories + 10) * 15 / Trains.saturation(unitCount)))
end
function Trains.gold(relation: string, stopsVisited: number, multiplier: number?): number
    local base = if relation == "self" then 10000 elseif relation == "ally" then 35000 else 25000
    return math.floor(math.max(5000, base - math.max(0, stopsVisited - 9) * 5000) * (multiplier or Config.Economy.GoldMultiplier))
end
function Trains.unitCount(state: any): number
    return Rails.trainUnitCount(state)
end
function Trains.unit(state: any, id: number): any
    for _, unit in state.trains or {} do if unit.id == id and active(unit) then return unit end end
    return nil
end
local function buildUnit(state: any, owner: number, tile: number, trainType: string, target: any?, loaded: boolean?): any
    state.trains = state.trains or {}
    local unit = { id = state.nextUnitId, owner = owner, unitType = "Train", tileId = tile, lastTileId = tile,
        active = true, createdTick = state.ticks, trainType = trainType, targetUnitId = target and target.id,
        loaded = loaded, reachedTarget = false }
    state.nextUnitId += 1
    table.insert(state.trains, unit)
    Rails.invalidateUnitCounts(state, "Train")
    state.unitAcquisitionOrder = state.unitAcquisitionOrder or {}
    state.nextUnitAcquisitionOrder = state.nextUnitAcquisitionOrder or 1
    state.unitAcquisitionOrder[unit.id] = state.nextUnitAcquisitionOrder
    state.nextUnitAcquisitionOrder += 1
    return unit
end
function Trains.deleteUnit(state: any, unit: any)
    if not active(unit) then return end
    unit.active = false
    Rails.invalidateUnitCounts(state, "Train")
    -- UnitImpl.delete emits the inactive update before GameImpl removes its unit.
    if state.recordUnitDeath then state.recordUnitDeath(unit, "Train") end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[unit.id] = nil end
    local index = table.find(state.trains or {}, unit)
    if index then table.remove(state.trains, index) end
end
local function deleteTrain(state: any, execution: any)
    execution.active = false
    if active(execution.train) then Trains.deleteUnit(state, execution.train) end
    for _, car in execution.cars do if active(car) then Trains.deleteUnit(state, car) end end
end
function Trains.playerDeath(state: any, owner: number)
    local units = {}
    for _, unit in state.trains or {} do if unit.owner == owner then table.insert(units, unit) end end
    table.sort(units, function(a, b)
        return ((state.unitAcquisitionOrder or {})[a.id] or a.id) < ((state.unitAcquisitionOrder or {})[b.id] or b.id)
    end)
    for _, unit in units do Trains.deleteUnit(state, unit) end
end
local function saveTile(execution: any, tile: number)
    table.insert(execution.usedTiles, tile)
    if #execution.usedTiles > #execution.cars * execution.spacing + 3 then table.remove(execution.usedTiles, 1) end
end
local function saveTraversed(execution: any, from: number, speed: number)
    if not execution.currentRailroad then return end
    for index = from, from + speed - 1 do
        if index >= #execution.currentRailroad.tiles then break end
        saveTile(execution, execution.currentRailroad.tiles[index + 1])
    end
end
local function move(unit: any, tile: number)
    unit.lastTileId, unit.tileId = unit.tileId, tile
end
local function credit(state: any, owner: number, amount: number, tile: number)
    if state.addTrainGold then state.addTrainGold(owner, amount, tile)
    else state.gold[owner] += amount; state.goldEarned[owner] += amount end
    state.trainGold = state.trainGold or {}
    state.trainGold[owner] = (state.trainGold[owner] or 0) + amount
end
local function reachedStation(state: any, execution: any)
    local station = execution.stations[2]
    local kind = station.unit.unitType
    if kind == "City" or kind == "Port" then
        local stationOwner, trainOwner = station.unit.owner, execution.owner
        local relation = if trainOwner == stationOwner then "self" else "other"
        if state.railApi and state.railApi.relation then relation = state.railApi.relation(trainOwner, stationOwner) end
        local multiplier = if state.railApi and state.railApi.goldMultiplier then state.railApi.goldMultiplier(trainOwner) else GameConfig.forState(state).Economy.GoldMultiplier
        local gold = Trains.gold(relation, execution.tradeStopsVisited, multiplier)
        if trainOwner ~= stationOwner then credit(state, stationOwner, gold, station.unit.tileId) end
        credit(state, trainOwner, gold, station.unit.tileId)
        execution.tradeStopsVisited += 1
    end
end
local function resolveSplit(state: any, execution: any): any
    local path = Rails.findStationsPath(state, execution.stations[1], execution.stations[2])
    if #path <= 2 then return nil end
    local cursor = execution.pathIndex
    for index = 1, #path - 1 do
        local segment = Rails.oriented(path[index], path[index + 1])
        if not segment then return nil end
        for _, tile in segment.tiles do
            if execution.pathTiles[cursor + 1] ~= tile then return nil end
            cursor += 1
        end
    end
    table.remove(execution.stations, 1); table.remove(execution.stations, 1)
    for index = #path, 1, -1 do table.insert(execution.stations, 1, path[index]) end
    return Rails.oriented(execution.stations[1], execution.stations[2])
end
local function nextStation(state: any, execution: any): boolean
    if #execution.stations > 2 then
        execution.pathIndex += if execution.currentRailroad then #execution.currentRailroad.tiles else 0
        table.remove(execution.stations, 1)
        local segment = Rails.oriented(execution.stations[1], execution.stations[2]) or resolveSplit(state, execution)
        if segment then execution.currentRailroad = segment; return true end
    end
    return false
end
local function nextTile(state: any, execution: any): number?
    if not execution.currentRailroad or #execution.stations <= 1
        or not Rails.tradeAvailable(state, execution.stations[2], execution.owner) then return nil end
    saveTraversed(execution, execution.currentTile, execution.speed)
    execution.currentTile += execution.speed
    local leftover = execution.currentTile - #execution.currentRailroad.tiles
    if leftover >= 0 then
        reachedStation(state, execution)
        if not nextStation(state, execution) then return nil end
        execution.currentTile = leftover
        saveTraversed(execution, 0, leftover)
    end
    return execution.currentRailroad.tiles[execution.currentTile + 1]
end
function Trains.initExecution(state: any, execution: any): boolean
    if execution.kind ~= "Train" then return false end
    local source = execution.source or Rails.stationById(state, execution.sourceStationId)
    local destination = execution.destination or Rails.stationById(state, execution.destinationStationId)
    if not source or not destination then return false end
    local stations = Rails.findStationsPath(state, source, destination)
    if #stations <= 1 then return false end
    local railroad = Rails.oriented(stations[1], stations[2])
    if not railroad then return false end
    local tile, owner = stations[1].unit.tileId, execution.owner
    if (GameConfig.forState(state).Train and GameConfig.forState(state).Train.Enabled == false) or GameConfig.disabled(state, "Train") or (Config.DisabledUnits and table.find(Config.DisabledUnits, "Train"))
        or not state.counts[owner] or state.counts[owner] <= 0 or state.gold[owner] < 0 or not state.map.land[tile]
        or (state.map.terrain and bit32.band(buffer.readu8(state.map.terrain, tile - 1), 31) == 31) then return false end
    execution.stations, execution.currentRailroad, execution.source, execution.destination = stations, railroad, source, destination
    execution.cars, execution.hasCargo, execution.currentTile, execution.spacing, execution.usedTiles = {}, false, 0, 2, {}
    execution.speed, execution.tradeStopsVisited, execution.pathIndex, execution.active = 2, 0, 0, true
    execution.train = buildUnit(state, owner, tile, "Engine", destination.unit)
    table.insert(execution.cars, buildUnit(state, owner, tile, "TailEngine", destination.unit))
    for _ = 1, execution.numCars or 5 do table.insert(execution.cars, buildUnit(state, owner, tile, "Carriage", nil, false)) end
    local path, carIds = {}, {}
    for _, car in execution.cars do car.engineId = execution.train.id; table.insert(carIds, car.id) end
    execution.train.engineId = execution.train.id
    for index = 1, #stations - 1 do
        local segment = Rails.oriented(stations[index], stations[index + 1])
        if not segment then execution.active = false; return false end
        for _, t in segment.tiles do table.insert(path, t) end
    end
    if #path == 0 or path[1] ~= tile then table.insert(path, 1, tile); execution.pathIndex = 1 end
    execution.pathTiles = path
    execution.train.route, execution.train.pathStartTick = path, state.ticks + 1
    execution.train.speed, execution.train.spacing, execution.train.carUnitIds = 2, 2, carIds
    return true
end
function Trains.tickExecution(state: any, execution: any): boolean
    if execution.kind ~= "Train" then return false end
    if not active(execution.train) or #execution.stations <= 1 or not Rails.stationActive(execution.stations[1])
        or not Rails.stationActive(execution.stations[2]) then deleteTrain(state, execution); return false end
    local tile = nextTile(state, execution)
    if tile then
        for index = #execution.cars, 1, -1 do
            -- Source is zero based: car[i] uses usedTiles[(i+1)*spacing+2].
            local offset = index * execution.spacing + 2
            if #execution.usedTiles > offset then move(execution.cars[index], execution.usedTiles[offset + 1]) end
        end
        move(execution.train, tile)
        return true
    end
    execution.train.reachedTarget = true
    for _, car in execution.cars do car.reachedTarget = true end
    deleteTrain(state, execution)
    return false
end
function Trains.loadCargo(execution: any)
    if execution.hasCargo or not execution.train then return end
    execution.hasCargo = true
    -- Source has this method, but no production callsite at the pinned revision.
    for index = 2, #execution.cars do execution.cars[index].loaded = true end
end
function Trains.snapshot(state: any): { any }
    local result = {}
    for _, unit in state.trains or {} do
        if not active(unit) then continue end
        table.insert(result, { id = unit.id, owner = unit.owner, unitType = "Train", tileId = unit.tileId,
            lastTileId = unit.lastTileId, active = true, createdTick = unit.createdTick, trainType = unit.trainType,
            loaded = unit.loaded, targetUnitId = unit.targetUnitId, reachedTarget = unit.reachedTarget,
            engineId = unit.engineId, route = unit.route, pathStartTick = unit.pathStartTick,
            speed = unit.speed, spacing = unit.spacing, carUnitIds = unit.carUnitIds })
    end
    return result
end
return table.freeze(Trains)
