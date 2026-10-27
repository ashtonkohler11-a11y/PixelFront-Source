--!strict
--!native
-- TransportShipExecution / BoatRetreatExecution, OpenFrontIO 93a136a1.
-- Routing is independent; mutations are server-only and shared queries also accept snapshots.
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Diplomacy = require(script.Parent.OpenFrontDiplomacy)
local Naval = {}

local function validTile(state: any, tile: any): boolean
    return type(tile) == "number" and tile == tile and tile % 1 == 0
        and tile >= 1 and tile <= state.map.width * state.map.height
end
local function validOwner(state: any, owner: any): boolean
    return type(owner) == "number" and owner == owner and owner % 1 == 0 and owner >= 1 and owner <= #state.players
end
function Naval.ship(state: any, unitId: number): any
    for _, ship in state.ships or {} do if ship.id == unitId and ship.active ~= false then return ship end end
    return nil
end
function Naval.unitCount(state: any, owner: number): number
    local count = 0
    for _, ship in state.ships or {} do if ship.owner == owner and ship.active ~= false then count += 1 end end
    return count
end
function Naval.orderedBorders(state: any, owner: number): { number }
    if state.shoreBorders and state.shoreBorders[owner] then return state.shoreBorders[owner] end
    if state.borders and state.borders[owner] then return state.borders[owner].values end
    return {}
end
-- PF035: the owner's shore border tiles (land next to water: terrain bits 192, Nav:isShore), in border order, cached until
-- any owner (Simulation's ownerEpoch) or water (waterVersion) changes; uncached without an epoch (fixtures). The client's
-- decoded state already carries its own (state.shoreBorders). Read-only: callers never change it.
local shoreCache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
function Naval.shoreBorders(state: any, owner: number): { number }
    if state.shoreBorders and state.shoreBorders[owner] then return state.shoreBorders[owner] end
    local values = state.borders and state.borders[owner] and state.borders[owner].values
    if not values then return {} end
    local epoch, water = state.ownerEpoch, (state.map and state.map.waterVersion) or 0
    local cache = shoreCache[state]
    if epoch ~= nil then
        if not cache or cache.epoch ~= epoch or cache.water ~= water then
            cache = { epoch = epoch, water = water, byOwner = {} }; shoreCache[state] = cache
        end
        local hit = cache.byOwner[owner]
        if hit then return hit end
    end
    local shores, terrain = {}, state.map.terrain
    for _, tile in values do
        if tile ~= 0 and bit32.band(buffer.readu8(terrain, tile - 1), 192) == 192 then table.insert(shores, tile) end
    end
    if epoch ~= nil then cache.byOwner[owner] = shores end
    return shores
end
function Naval.navigation(state: any): any
    return Navigation.forMap(state.map)
end
local function targetOwner(state: any, tile: number): number
    return math.max(0, state.owners[tile])
end
function Naval.canBuildTransportShip(state: any, owner: number, tile: number, navigation: any?): any
    if not GameConfig.forState(state).Naval.Enabled or not validOwner(state, owner) or not validTile(state, tile)
        or state.counts[owner] == 0 or Naval.unitCount(state, owner) >= GameConfig.forState(state).Naval.MaxShips then return false end
    if targetOwner(state, tile) == owner then return false end
    local nav = navigation or Naval.navigation(state)
    local borders = Naval.shoreBorders(state, owner) -- PF035: the shore subset (the nav calls keep only shores anyway)
    local dst = nav:targetTransportTile(state.owners, borders, tile)
    if dst == nil then return false end
    local other=targetOwner(state,tile)
    if other>0 then
        if state.diplomacy and Diplomacy.friendly(state,owner,other) then return false end
        if state.players[owner].playerType=="Human" and state.players[other].playerType~="Bot"
            and (state.phase=="Choosing" or state.ticks-(state.startTick or 0)<GameConfig.forState(state).Match.SpawnImmunityTicks) then return false end
    end
    return nav:bestTransportShipSpawn(borders, dst) or false
end
local function deleteShip(state: any, ship: any)
    ship.active = false
    if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
    for index, candidate in state.ships do
        if candidate == ship then table.remove(state.ships, index) break end
    end
end
local function emit(api: any, event: any)
    if api and api.message then api.message(event) end
end
local function plan(state: any, execution: any, ship: any)
    local path = execution.pathFinder:findPath(ship.tileId, execution.dst) or { ship.tileId }
    if #path == 0 or path[1] ~= ship.tileId then table.insert(path, 1, ship.tileId) end
    ship.motionPlan = { kind = "grid", unitId = ship.id, planId = execution.motionPlanId,
        startTick = state.ticks + GameConfig.forState(state).Naval.TicksPerMove, ticksPerStep = GameConfig.forState(state).Naval.TicksPerMove, path = path }
    execution.motionPlanDst = execution.dst
end
function Naval.initExecution(state: any, execution: any, api: any): boolean
    if execution.kind == "BoatRetreat" then return true end
    if execution.kind ~= "TransportShip" then return false end
    local owner, ref = execution.owner, execution.tileId
    if not validTile(state, ref) or not validOwner(state, owner) then return false end
    local nav = (api and api.navigation) or Naval.navigation(state)
    execution.lastMove, execution.targetOwner = state.ticks, targetOwner(state, ref)
    execution.originalOwner = owner
    local stagger = state.shipStagger or 0
    state.shipStagger = stagger + 1
    execution.pathFinder = nav:newStepper(stagger % 50)
    if Naval.unitCount(state, owner) >= GameConfig.forState(state).Naval.MaxShips then
        emit(api, { key = "events_display.no_boats_available", type = "ATTACK_FAILED", owner = owner,
            max = GameConfig.forState(state).Naval.MaxShips })
        return false
    end
    if execution.targetOwner>0 and state.players[owner].playerType~="Bot" and state.players[execution.targetOwner].playerType~="Bot"
        and api and api.rejectIncomingRequest then api.rejectIncomingRequest(owner,execution.targetOwner) end
    if execution.targetOwner == owner then return false end
    if api and api.canAttackPlayer and execution.targetOwner > 0
        and not api.canAttackPlayer(owner, execution.targetOwner) then return false end
    local amount = math.min(execution.amount or math.floor(state.troops[owner] * GameConfig.forState(state).Naval.DefaultAttackRatio), state.troops[owner])
    -- PixelFront PF014: a human's departing ship never digs into their troop reserve.
    local reserve = if api and api.troopReserve then api.troopReserve(owner) else 0
    if reserve > 0 then amount = math.min(amount, state.troops[owner] - reserve); if amount < 1 then return false end end
    execution.dst = nav:targetTransportTile(state.owners, Naval.shoreBorders(state, owner), ref)
    if execution.dst == nil then return false end
    local src = Naval.canBuildTransportShip(state, owner, execution.dst, nav)
    if src == false then return false end
    execution.src, execution.motionPlanId, execution.retreatDst = src, 1, nil
    local ship = { id = state.nextUnitId, owner = owner, tileId = src, lastTileId = src,
        targetTileId = execution.dst, originalTargetOwner = execution.targetOwner,
        troops = amount, isRetreating = false, active = true, createdTick = state.ticks }
    state.nextUnitId += 1
    state.ships = state.ships or {}
    table.insert(state.ships, ship)
    if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
    execution.shipId = ship.id
    -- PlayerImpl.buildUnit floors reserve deduction, while UnitImpl stores the supplied number.
    state.troops[owner] -= math.min(state.troops[owner], math.max(0, math.floor(amount)))
    plan(state, execution, ship)
    state.shipsSent = state.shipsSent or {}
    state.shipsSent[owner] = (state.shipsSent[owner] or 0) + 1
    if execution.targetOwner > 0 then
        emit(api, { type = "NAVAL_INVASION_INBOUND", owner = execution.targetOwner, attacker = owner,
            shipId = ship.id, troops = ship.troops })
    end
    return true
end
function Naval.tickExecution(state: any, execution: any, api: any): boolean
    if execution.kind == "BoatRetreat" then
        local ship = Naval.ship(state, execution.unitId)
        if ship and ship.owner == execution.owner then ship.isRetreating = true end
        return false
    end
    if execution.kind ~= "TransportShip" then return false end
    local ship = Naval.ship(state, execution.shipId)
    if execution.dst == nil or not ship then return false end
    if state.ticks - execution.lastMove < GameConfig.forState(state).Naval.TicksPerMove then return true end
    execution.lastMove = state.ticks
    local owner = execution.owner
    -- Team/disconnect transfers are absent from this FFA slice; keep source hook explicit.
    if api and api.sameTeamTransfer and api.sameTeamTransfer(execution.originalOwner, ship.owner) then
        execution.owner, execution.originalOwner, owner = ship.owner, ship.owner, ship.owner
    end
    local nav = (api and api.navigation) or Naval.navigation(state)
    if execution.pathFinder.rebuilt then execution.motionPlanDst = nil end
    if nav:isWater(execution.dst) then ship.isRetreating, execution.retreatDst = true, nil end
    if ship.isRetreating then
        if execution.retreatDst == nil then
            execution.retreatDst = nav:bestTransportShipSpawn(Naval.shoreBorders(state, owner), ship.tileId) or false
        end
        if execution.retreatDst == false then
            state.troops[owner] += math.floor(ship.troops)
            deleteShip(state, ship)
            return false
        end
        execution.dst, ship.targetTileId = execution.retreatDst, execution.retreatDst
    end
    local result = execution.pathFinder:next(ship.tileId, execution.dst)
    if result.status == "complete" then
        if targetOwner(state, execution.dst) == owner then
            local deaths = ship.troops * GameConfig.forState(state).Naval.RetreatLossFraction
            local survivors = ship.troops - deaths
            state.troops[owner] += math.floor(survivors)
            deleteShip(state, ship)
            state.shipsArrived = state.shipsArrived or {}
            state.shipsArrived[owner] = (state.shipsArrived[owner] or 0) + 1
            if deaths ~= 0 then emit(api, { key = "events_display.attack_cancelled_retreat", type = "ATTACK_CANCELLED",
                owner = owner, troops = deaths }) end
            return false
        end
        api.conquer(execution.dst, owner)
        if execution.targetOwner > 0 and api.friendly and api.friendly(owner, execution.targetOwner) then
            state.troops[owner] += math.floor(ship.troops)
        else
            table.insert(state.pendingExecutions, { kind = "Attack", owner = owner, targetOwner = execution.targetOwner,
                amount = ship.troops, sourceTile = execution.dst, removeTroops = false })
        end
        deleteShip(state, ship)
        state.shipsArrived = state.shipsArrived or {}
        state.shipsArrived[owner] = (state.shipsArrived[owner] or 0) + 1
        return false
    elseif result.status == "next" then
        ship.lastTileId, ship.tileId = ship.tileId, result.node
        if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
    elseif result.status == "not_found" then
        state.troops[owner] += math.floor(ship.troops)
        deleteShip(state, ship)
        return false
    end
    if execution.dst ~= execution.motionPlanDst then
        execution.motionPlanId += 1
        plan(state, execution, ship)
    end
    return true
end
function Naval.playerDeath(state: any, owner: number)
    for index = #(state.ships or {}), 1, -1 do
        local ship = state.ships[index]
        if ship.owner == owner then
            ship.active = false; table.remove(state.ships, index)
            if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
        end
    end
end
return table.freeze(Naval)
