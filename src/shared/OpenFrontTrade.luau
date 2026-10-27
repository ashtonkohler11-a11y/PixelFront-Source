--!strict
--!native
-- OpenFrontIO 93a136a1: PortExecution, TradeShipExecution and Config trade formulas.
-- Port construction is separate. These executions run in the server's ordered queue.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Math = require(script.Parent.OpenFrontMath)
local Random = require(script.Parent.OpenFrontRandom)
local MapData = require(script.Parent.MapData)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Trade = {}

local function distance(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
local function navFor(state: any, api: any): any return (api and api.navigation) or Navigation.forMap(state.map) end
local function portById(state: any, id: number): any
    return Index.byId(state.ports, id) -- PF-4: was a scan of every port
end
local function active(port: any): boolean return port ~= nil and port.active ~= false end
function Trade.ownedPorts(state: any, owner: number, byId: any?): {any}
    local result = {}
    if state.portOrders then
        for _, id in state.portOrders[owner] or {} do
            local port = if byId then byId[id] else portById(state, id)
            if active(port) then table.insert(result, port) end
        end
    else
        for _, port in state.ports or {} do if port.owner == owner and active(port) then table.insert(result, port) end end
    end
    return result
end
function Trade.canTrade(state: any, owner: number, other: number, api: any?): boolean
    api=api or state.tradeApi
    if api and api.canTrade then return api.canTrade(owner, other) end
    if owner == other then return false end
    local embargoes = state.embargoes
    return not (embargoes and ((embargoes[owner] and embargoes[owner][other]) or (embargoes[other] and embargoes[other][owner])))
end
local function friendly(owner: number, other: number, api: any): boolean
    return if api and api.friendly then api.friendly(owner, other) else owner == other
end
-- perTile: the long-trip slope (OpenFront's own is 50, which the reference parity test passes; the game uses Config's)
function Trade.gold(tilesTraveled: number, multiplier: number?, perTile: number?): number
    local debuff = Config.Trade.ShortRangeDebuff
    local base = 75000 / (1 + Math.exp(-0.03 * (tilesTraveled - debuff))) + (perTile or Config.Trade.LongRangeGoldPerTile) * tilesTraveled
    return math.floor(base * (multiplier or Config.Economy.GoldMultiplier))
end
function Trade.saturation(count: number): number
    local boost = 1 + 0.45 * Math.exp(-count / 120)
    local damping = 1 - 1 / (1 + Math.exp(-(0.6931471805599453 / 50) * (count - 330)))
    local plateau = 0.25 * (1 - 1 / (1 + Math.exp(-(0.6931471805599453 / 100) * (count - 800))))
    return boost * math.max(damping, plateau)
end
function Trade.spawnRate(rejections: number, count: number): number
    return math.max(1, math.floor((100 * (1 / (rejections + 1))) / Trade.saturation(count)))
end
function Trade.ship(state: any, id: number): any
    local ship = Index.byId(state.tradeShips, id) -- PF-4: ids are unique, so the first match is the only one
    return if ship ~= nil and ship.active ~= false then ship else nil
end
function Trade.unitCount(state: any): number
    local count = 0
    for _, ship in state.tradeShips or {} do if ship.active ~= false then count += 1 end end
    return count
end
function Trade.tradingPorts(state: any, source: any, api: any?): {any}
    local nav, components = navFor(state, api), {}
    for _, tile in MapData.neighbors(source.tileId, state.map.width, state.map.height) do
        if nav:isWater(tile) then
            local component = nav:getWaterComponent(tile)
            if component ~= nil then components[component] = true end
        end
    end
    local candidates, byId, order = {}, {}, state.playerOrder
    for _, port in state.ports or {} do byId[port.id] = port end
    if not order then order = {} for owner = 1, #state.players do table.insert(order, owner) end end
    for _, owner in order do
        if state.counts[owner] <= 0 or owner == source.owner or not Trade.canTrade(state, owner, source.owner, api) then continue end
        for _, port in Trade.ownedPorts(state, owner, byId) do
            for component in components do
                if nav:hasWaterComponent(port.tileId, component) then
                    table.insert(candidates, {port = port, distance = distance(state, source.tileId, port.tileId), order = #candidates + 1})
                    break
                end
            end
        end
    end
    -- JS sort is stable: original registration/owned-unit order wins distance ties.
    table.sort(candidates, function(a, b) return a.distance < b.distance or (a.distance == b.distance and a.order < b.order) end)
    local weighted, bonusCount = {}, math.min(math.max(#candidates / 3, 4), #candidates)
    for index, candidate in candidates do
        local port, repetitions = candidate.port, 1
        if candidate.distance >= GameConfig.forState(state).Trade.ShortRangeDebuff then
            if index - 1 < bonusCount then repetitions += 1 end
            if friendly(source.owner, port.owner, api) then repetitions += 1 end
        end
        for _ = 1, repetitions do for _ = 1, port.level do table.insert(weighted, port) end end
    end
    return weighted
end
function Trade.shouldSpawn(state: any, execution: any): boolean
    local count = Trade.unitCount(state)
    -- PF045 Ports: past Config.Trade.PortSoftCap Ports, each of the owner's Ports spawns at x sqrt(cap / ports)
    local cap = Config.Trade.PortSoftCap
    local owned = if cap then #Trade.ownedPorts(state, execution.port.owner) else 0
    local soft = if cap and owned > cap then math.sqrt(owned / cap) else 1
    for _ = 1, execution.port.level do
        if Random.int(execution.random, 0, math.floor(Trade.spawnRate(execution.rejections, count) * soft)) == 0 then
            execution.rejections = 0
            return true
        end
        execution.rejections += 1
    end
    return false
end
local function removeShip(state: any, ship: any)
    ship.active = false
    if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
    local index = table.find(state.tradeShips, ship)
    if index then table.remove(state.tradeShips, index) end
end
function Trade.playerDeath(state: any, owner: number)
    for index = #(state.tradeShips or {}), 1, -1 do
        local ship = state.tradeShips[index]
        if ship.owner == owner then
            ship.active = false; table.remove(state.tradeShips, index)
            if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
        end
    end
end
local function emit(api: any, event: any) if api and api.message then api.message(event) end end
local function credit(state: any, owner: number, amount: number, tile: number, api: any)
    if api and api.addGold then api.addGold(owner, amount, tile)
    else state.gold[owner] += amount state.goldEarned[owner] += amount end
end
local function increment(state: any, field: string, owner: number, amount: number)
    state[field] = state[field] or {}
    state[field][owner] = (state[field][owner] or 0) + amount
end
local function complete(state: any, execution: any, ship: any, api: any): boolean
    removeShip(state, ship)
    local multiplier = if api and api.goldMultiplier then api.goldMultiplier(ship.owner) else GameConfig.forState(state).Economy.GoldMultiplier
    local gold, source, destination = Trade.gold(execution.tilesTraveled, multiplier), execution.srcPort, execution.dstPort
    if execution.wasCaptured and ship.owner == execution.owner then
        credit(state, execution.owner, gold, destination.tileId, api)
    elseif execution.wasCaptured then
        credit(state, ship.owner, gold, destination.tileId, api)
        increment(state, "piracyGold", ship.owner, gold)
        emit(api, {key = "events_display.received_gold_from_captured_ship", type = "CAPTURED_ENEMY_UNIT",
            owner = ship.owner, gold = gold, otherOwner = execution.owner})
        increment(state, "tradeShipsCaptured", ship.owner, 1)
    else
        credit(state, source.owner, gold, source.tileId, api)
        credit(state, destination.owner, gold, destination.tileId, api)
        -- PF044 Trade Guild (PremiumItems.tradeGold; only while one stands, so reference matches never reach it)
        if state.premium and state.premium.guildActive then
            state.premium.tradeGold(state, source.owner, gold); state.premium.tradeGold(state, destination.owner, gold)
        end
        increment(state, "tradeGold", source.owner, gold)
        increment(state, "tradeGold", destination.owner, gold)
        increment(state, "tradeShipsArrived", source.owner, 1)
    end
    return false
end
function Trade.initExecution(state: any, execution: any, api: any?): boolean
    if execution.kind == "PortTrade" then
        execution.port = portById(state, execution.unitId)
        execution.random, execution.checkOffset, execution.rejections = Random.new(state.ticks), state.ticks % 10, 0
        return execution.port ~= nil
    elseif execution.kind == "TradeShip" then
        local stagger = state.tradeShipStagger or 0
        state.tradeShipStagger = stagger + 1
        execution.pathFinder = navFor(state, api):newStepper(stagger % 50, true)
        execution.wasCaptured, execution.tilesTraveled, execution.motionPlanId = false, 0, 1
        return true
    end
    return false
end
function Trade.tickExecution(state: any, execution: any, api: any?): boolean
    if execution.kind == "PortTrade" then
        local port = execution.port
        if not active(port) then return false end
        if port.underConstruction then return true end
        if state.portRailTick then state.portRailTick(port) end
        if (state.ticks + execution.checkOffset) % 10 ~= 0 or not Trade.shouldSpawn(state, execution) then return true end
        local choices = Trade.tradingPorts(state, port, api)
        if #choices > 0 then
            table.insert(state.pendingExecutions, {kind = "TradeShip", owner = port.owner,
                srcPort = port, dstPort = choices[Random.int(execution.random, 1, #choices + 1)]})
        end
        return true
    elseif execution.kind ~= "TradeShip" then return false end
    local nav = navFor(state, api)
    if execution.pathFinder.rebuilt then execution.motionPlanDst = nil end
    local ship = execution.ship
    if not ship then
        if not GameConfig.forState(state).Trade.Enabled or GameConfig.disabled(state, "Trade Ship") or state.counts[execution.owner] <= 0 then return false end
        local spawn = false
        for _, port in Trade.ownedPorts(state, execution.owner) do if port.tileId == execution.srcPort.tileId then spawn = true break end end
        if not spawn then return false end
        ship = {id = state.nextUnitId, owner = execution.owner, unitType = "Trade Ship", tileId = execution.srcPort.tileId,
            lastTileId = execution.srcPort.tileId, sourcePortId = execution.srcPort.id, targetPortId = execution.dstPort.id,
            targetTileId = execution.dstPort.tileId, originalOwner = execution.owner, active = true, createdTick = state.ticks,
            lastSetSafeFromPirates = state.ticks}
        state.nextUnitId += 1
        state.tradeShips = state.tradeShips or {}
        table.insert(state.tradeShips, ship)
        ship._targetUnit = execution.dstPort
        if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
        execution.ship, execution.shipId = ship, ship.id
        increment(state, "tradeShipsSent", execution.owner, 1)
    end
    if ship.active == false then return false end
    if not execution.wasCaptured and execution.owner ~= ship.owner then
        execution.wasCaptured = true
        emit(api, {key = "events_display.trade_ship_captured", type = "UNIT_DESTROYED", owner = execution.owner,
            otherOwner = ship.owner, shipId = ship.id})
    end
    local destination = execution.dstPort
    if destination.owner == execution.srcPort.owner then removeShip(state, ship) return false end
    if not execution.wasCaptured and (not active(destination) or not Trade.canTrade(state, ship.owner, destination.owner, api)) then
        removeShip(state, ship) return false
    end
    if execution.wasCaptured and (ship.owner ~= destination.owner or not active(destination)) then
        local component, nearest, nearestDistance = nav:getWaterComponent(ship.tileId), nil, math.huge
        for _, port in Trade.ownedPorts(state, ship.owner) do
            if port.deletionMarkedTick ~= nil or port.underConstruction or component == nil or not nav:hasWaterComponent(port.tileId, component) then continue end
            local d = distance(state, port.tileId, ship.tileId)
            if d < nearestDistance then nearest, nearestDistance = port, d end
        end
        if not nearest then removeShip(state, ship) return false end
        execution.dstPort, destination = nearest, nearest
        ship._targetUnit = nearest
        ship.targetPortId, ship.targetTileId = nearest.id, nearest.tileId
    end
    if ship.tileId == destination.tileId then return complete(state, execution, ship, api) end
    local result = execution.pathFinder:next(ship.tileId, destination.tileId)
    if result.status == "next" then
        if destination.tileId ~= execution.motionPlanDst then
            execution.motionPlanId += 1
            ship.motionPlan = {kind = "grid", unitId = ship.id, planId = execution.motionPlanId,
                startTick = state.ticks + 1, ticksPerStep = 1, path = execution.pathFinder:pathForTraversal(result.node, destination.tileId)}
            execution.motionPlanDst = destination.tileId
        end
        if nav:isWater(result.node) and bit32.band(buffer.readu8(state.map.terrain, result.node - 1), 64) ~= 0 then
            ship.lastSetSafeFromPirates = state.ticks
        end
        ship.lastTileId, ship.tileId = ship.tileId, result.node
        if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
        execution.tilesTraveled += 1
    elseif result.status == "complete" then return complete(state, execution, ship, api)
    elseif result.status == "not_found" then removeShip(state, ship) return false end
    return true
end
return table.freeze(Trade)
