--!strict
--!native
-- OpenFrontIO 93a136a1: shared structure rules and PlayerImpl.portSpawn.
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local MapData = require(script.Parent.MapData)
local Economy = require(script.Parent.OpenFrontEconomy)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Ports = {}
local STRUCTURE_LISTS = { "cities", "ports", "factories", "defensePosts", "samLaunchers", "missileSilos" }

local function integer(n: any): boolean return type(n) == "number" and n == n and math.abs(n) < math.huge and n % 1 == 0 end
local function ownerValid(state: any, owner: any): boolean return integer(owner) and owner >= 1 and owner <= #state.players end
local function tileValid(state: any, tile: any): boolean return integer(tile) and tile >= 1 and tile <= state.map.width * state.map.height end
local function manhattan(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
function Ports.port(state: any, id: number): any
    return Index.byId(state.ports, id) -- PF-4: was a scan of every port (~1,500 calls a tick late game)
end
function Ports.ownedPorts(state: any, owner: number): { any }
    local result = {}
    if state.portOrders then
        for _, id in state.portOrders[owner] or {} do local port = Ports.port(state, id); if port then table.insert(result, port) end end
    else
        for _, port in state.ports or {} do if port.owner == owner then table.insert(result, port) end end
    end
    return result
end
function Ports.ownedLevels(state: any, owner: number): number
    local count = 0
    for _, port in state.ports or {} do if port.owner == owner then count += if port.underConstruction then 1 else port.level end end
    return count
end
function Ports.portCost(state: any, owner: number, extra: number?): number
    if GameConfig.freeGold(state, owner) then return 0 end
    local factoryLevels = 0
    for _, factory in state.factories or {} do
        if factory.owner == owner then factoryLevels += if factory.underConstruction then 1 else factory.level end
    end
    local count = math.min(Ports.ownedLevels(state, owner), (state.portConstructed and state.portConstructed[owner]) or 0)
        + math.min(factoryLevels, (state.factoryConstructed and state.factoryConstructed[owner]) or 0) + (extra or 0)
    return math.min(GameConfig.forState(state).Port.MaxCost, GameConfig.forState(state).Port.BaseCost * 2 ^ math.min(count, 4))
end
local function affordable(state: any, owner: any): boolean
    return GameConfig.forState(state).Port.Enabled and ownerValid(state, owner) and state.counts[owner] > 0 and state.gold[owner] >= Ports.portCost(state, owner)
end
function Ports.spawnTile(state: any, owner: number, tile: number): number?
    if not tileValid(state, tile) or state.owners[tile] ~= owner then return nil end
    -- validStructureSpawnTiles: connected own land, strict radius15, all structures.
    -- PF-4: the same searches with the config, coordinates and neighbour order (N, S, W, E, as MapData.neighbors)
    -- hoisted out of the inner loops; it was the source of the largest late-game server spikes.
    local config = GameConfig.forState(state)
    local width, height, owners = state.map.width, state.map.height, state.owners
    local count = width * height
    local tx, ty = (tile - 1) % width, (tile - 1) // width
    local searchRadius = config.City.SearchRadius
    local nearRange, radiusSquared, minSquared = (searchRadius * 2) ^ 2, searchRadius ^ 2, config.City.StructureMinDistance ^ 2
    local nearX, nearY, nearCount = {}, {}, 0
    for _, key in STRUCTURE_LISTS do
        for _, structure in state[key] or {} do
            if structure.active == false then continue end
            local z = structure.tileId - 1
            local sx, sy = z % width, z // width
            local dx, dy = tx - sx, ty - sy
            if dx * dx + dy * dy <= nearRange then nearCount += 1; nearX[nearCount] = sx; nearY[nearCount] = sy end
        end
    end
    -- the structure flood only decides which tiles are valid (a set); its order never reaches the result
    local visited, stack, valid = { [tile] = true }, { tile }, {}
    local top = 1
    local function visit(t: number)
        if visited[t] or owners[t] ~= owner then return end
        local z = t - 1
        local dx, dy = tx - z % width, ty - z // width
        if dx * dx + dy * dy >= radiusSquared then return end
        visited[t] = true; top += 1; stack[top] = t
    end
    while top > 0 do
        local current = stack[top]; stack[top] = nil; top -= 1
        local z = current - 1
        local cx, cy = z % width, z // width
        local blocked = false
        for i = 1, nearCount do
            local dx, dy = cx - nearX[i], cy - nearY[i]
            if dx * dx + dy * dy < minSquared then blocked = true; break end
        end
        if not blocked then valid[current] = true end
        if current > width then visit(current - width) end
        if current <= count - width then visit(current + width) end
        if cx > 0 then visit(current - 1) end
        if cx < width - 1 then visit(current + 1) end
    end
    -- Source portSpawn uses a separate unrestricted Manhattan DFS. Its insertion
    -- order, not the structure flood order, breaks equally distant shore ties.
    local portRadius = config.Port.SearchRadius
    local seen, pending, spawns = { [tile] = true }, { tile }, { tile }
    local pendingTop, spawnCount = 1, 1
    local function reach(n: number)
        if seen[n] then return end
        local z = n - 1
        if math.abs(tx - z % width) + math.abs(ty - z // width) > portRadius then return end
        seen[n] = true; pendingTop += 1; pending[pendingTop] = n; spawnCount += 1; spawns[spawnCount] = n
    end
    while pendingTop > 0 do
        local current = pending[pendingTop]; pending[pendingTop] = nil; pendingTop -= 1
        if current > width then reach(current - width) end
        if current <= count - width then reach(current + width) end
        local cx = (current - 1) % width
        if cx > 0 then reach(current - 1) end
        if cx < width - 1 then reach(current + 1) end
    end
    local terrain = state.map.terrain
    local best, distance = nil, math.huge
    for _, candidate in spawns do
        if not valid[candidate] or bit32.band(buffer.readu8(terrain, candidate - 1), 192) ~= 192 then continue end
        local d = manhattan(state, tile, candidate)
        if d < distance then best, distance = candidate, d end
    end
    return best
end
function Ports.canBuildPort(state: any, owner: number, tile: number): number?
    if not affordable(state, owner) then return nil end
    return Ports.spawnTile(state, owner, tile)
end
function Ports.canUpgradePort(state: any, owner: number, id: number): boolean
    if not affordable(state, owner) then return false end
    local port = Ports.port(state, id)
    return port ~= nil and port.owner == owner and not port.underConstruction and port.deletionMarkedTick == nil
end
function Ports.canDeletePort(state: any, owner: number, id: number): boolean
    if not ownerValid(state, owner) or state.phase == "Choosing" then return false end
    local port = Ports.port(state, id)
    return port ~= nil and port.owner == owner and state.owners[port.tileId] == owner and state.map.land[port.tileId]
        and state.ticks - state.lastDeleteTicks[owner] >= GameConfig.forState(state).City.DeleteCooldownTicks
end
function Ports.queryBuildablePort(state: any, owner: number, tile: number): any
    local result: any = { type = "Port", cost = if ownerValid(state, owner) then Ports.portCost(state, owner) else GameConfig.forState(state).Port.BaseCost,
        canBuild = false, canUpgrade = false }
    if state.phase == "Choosing" or not tileValid(state, tile) or not affordable(state, owner) then return result end
    local nearest, distance, nearestCell = nil, math.huge, math.huge
    for _, port in state.ports or {} do
        local d = Economy.distanceSquared(state, tile, port.tileId)
        local x, y = (port.tileId - 1) % state.map.width, math.floor((port.tileId - 1) / state.map.width)
        local cell = math.floor(y / 100) * math.ceil(state.map.width / 100) + math.floor(x / 100)
        if d <= GameConfig.forState(state).City.StructureMinDistance ^ 2 and (d < distance or (d == distance and cell < nearestCell)) then
            nearest, distance, nearestCell = port, d, cell
        end
    end
    if nearest and Ports.canUpgradePort(state, owner, nearest.id) then
        result.canUpgrade, result.upgradeCosts = nearest.id, {}
        local total = 0
        for extra = 0, GameConfig.forState(state).City.MaxUpgradeAmount - 1 do total += Ports.portCost(state, owner, extra); table.insert(result.upgradeCosts, total) end
    end
    result.canBuild = Ports.canBuildPort(state, owner, tile) or false
    return result
end
function Ports.recordAcquisition(state: any, port: any)
    state.unitAcquisitionOrder = state.unitAcquisitionOrder or {}
    state.nextUnitAcquisitionOrder = state.nextUnitAcquisitionOrder or 1
    state.unitAcquisitionOrder[port.id] = state.nextUnitAcquisitionOrder
    state.nextUnitAcquisitionOrder += 1
end
local function removeOrder(state: any, owner: number, id: number)
    local index = table.find(state.portOrders[owner], id)
    if index then table.remove(state.portOrders[owner], index) end
end
function Ports.removePort(state: any, port: any)
    if port.active == false then return end
    port.active = false
    if state.recordUnitDeath then state.recordUnitDeath(port, "Port") end
    if state.removeRailStation then state.removeRailStation(port) end
    removeOrder(state, port.owner, port.id)
    local index = table.find(state.ports, port)
    if index then table.remove(state.ports, index) end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[port.id] = nil end
end
function Ports.playerTick(state: any, owner: number)
    for _, port in Ports.ownedPorts(state, owner) do
        local nextOwner = state.owners[port.tileId]
        if nextOwner <= 0 then Ports.removePort(state, port)
        elseif nextOwner ~= owner then
            removeOrder(state, owner, port.id)
            port.owner, port.deletionMarkedTick = nextOwner, nil
            table.insert(state.portOrders[nextOwner], port.id)
            Ports.recordAcquisition(state, port)
        end
    end
    if state.counts[owner] <= 0 then for _, port in Ports.ownedPorts(state, owner) do Ports.removePort(state, port) end end
end
function Ports.initExecution(state: any, execution: any): boolean
    if execution.kind == "BuildPort" then return tileValid(state, execution.tileId) and GameConfig.forState(state).Port.Enabled end
    if execution.kind == "UpgradePort" then
        for _ = 1, execution.amount do
            if not Ports.canUpgradePort(state, execution.owner, execution.unitId) then break end
            local port = Ports.port(state, execution.unitId)
            state.gold[execution.owner] -= Ports.portCost(state, execution.owner)
            port.level += 1; state.portConstructed[execution.owner] += 1
        end
        return false
    end
    if execution.kind == "DeletePort" and Ports.canDeletePort(state, execution.owner, execution.unitId) then
        state.lastDeleteTicks[execution.owner] = state.ticks
        Ports.port(state, execution.unitId).deletionMarkedTick = state.ticks + GameConfig.forState(state).City.DeletionMarkTicks
        return true
    end
    return false
end
function Ports.tickExecution(state: any, execution: any): boolean
    if execution.kind == "BuildPort" then
        if execution.unitId == nil then
            local tile = Ports.canBuildPort(state, execution.owner, execution.tileId)
            if not tile then return false end
            local port = { id = state.nextUnitId, owner = execution.owner, tileId = tile, level = 1,
                active = true, underConstruction = true, createdTick = state.ticks }
            state.nextUnitId += 1
            state.gold[execution.owner] -= Ports.portCost(state, execution.owner)
            state.portConstructed[execution.owner] += 1
            table.insert(state.ports, port); table.insert(state.portOrders[execution.owner], port.id)
            Ports.recordAcquisition(state, port)
            execution.unitId, execution.remaining = port.id, GameConfig.forState(state).Port.ConstructionTicks
            if execution.remaining == 0 then
                port.underConstruction = false
                table.insert(state.pendingExecutions, { kind = "PortTrade", unitId = port.id })
                return false
            end
            return true
        end
        local port = Ports.port(state, execution.unitId)
        if not port then return false end
        if execution.remaining == 0 then
            port.underConstruction = false
            table.insert(state.pendingExecutions, { kind = "PortTrade", unitId = port.id })
            return false
        end
        execution.remaining -= 1; return true
    end
    if execution.kind == "DeletePort" then
        local port = Ports.port(state, execution.unitId)
        if not port then return false end
        if port.deletionMarkedTick and state.ticks > port.deletionMarkedTick then Ports.removePort(state, port); return false end
        return true
    end
    return false
end
return table.freeze(Ports)
