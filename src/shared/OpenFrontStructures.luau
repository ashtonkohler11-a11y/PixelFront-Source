--!strict
--!native
-- OpenFrontIO 93a136a1: Factory/Defense Post Config, PlayerImpl and ordered structure executions.
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local MapData = require(script.Parent.MapData)
local Economy = require(script.Parent.OpenFrontEconomy)
local Ports = require(script.Parent.OpenFrontPorts)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Structures = {}

local function integer(v: any): boolean return type(v) == "number" and v == v and math.abs(v) < math.huge and v % 1 == 0 end
local function validOwner(state: any, owner: any): boolean return integer(owner) and owner >= 1 and owner <= #state.players end
local function validTile(state: any, tile: any): boolean return integer(tile) and tile >= 1 and tile <= state.map.width * state.map.height end
local function fields(kind: string): (string, string, string)
    if kind == "Factory" then return "factories", "factoryOrders", "factoryConstructed" end
    return "defensePosts", "defensePostOrders", "defensePostConstructed"
end
local function unit(state: any, kind: string, id: number): any
    return Index.byId(state[(fields(kind))], id) -- PF-4: was a scan of the whole list
end
local function owned(state: any, kind: string, owner: number): { any }
    local list, order = fields(kind)
    local result = {}
    if state[order] then
        for _, id in state[order][owner] or {} do local value = unit(state, kind, id); if value then table.insert(result, value) end end
    else
        for _, value in state[list] or {} do if value.owner == owner then table.insert(result, value) end end
    end
    return result
end
local function levels(state: any, kind: string, owner: number): number
    local list = fields(kind)
    local total = 0
    for _, value in state[list] or {} do
        if value.owner == owner then total += if value.underConstruction then 1 else value.level end
    end
    return total
end
local function cost(state: any, kind: string, owner: number, extra: number?): number
    if GameConfig.freeGold(state, owner) then return 0 end
    local _, _, history = fields(kind)
    local count = math.min(levels(state, kind, owner), (state[history] and state[history][owner]) or 0) + (extra or 0)
    if kind == "Factory" then
        count += math.min(Ports.ownedLevels(state, owner), (state.portConstructed and state.portConstructed[owner]) or 0)
        return math.min(GameConfig.forState(state).Factory.MaxCost, GameConfig.forState(state).Factory.BaseCost * 2 ^ math.min(count, 4))
    end
    return math.min(GameConfig.forState(state).DefensePost.MaxCost, GameConfig.forState(state).DefensePost.BaseCost * (count + 1))
end
local function affordable(state: any, kind: string, owner: any): boolean
    return validOwner(state, owner) and GameConfig.forState(state)[kind].Enabled and state.counts[owner] > 0 and state.gold[owner] >= cost(state, kind, owner)
end
function Structures.spawnTile(state: any, owner: number, tile: number): number?
    -- PlayerImpl.validStructureSpawnTiles: stable nearest sort of connected own
    -- strict-radius-15 N/S/W/E DFS discovery, spacing from every structure type.
    -- PF-4: Economy.spawnTile is this exact search (same validity, traversal, ties), with its inner loops hoisted.
    return Economy.spawnTile(state, owner, tile)
end
local function canBuild(state: any, kind: string, owner: number, tile: number): number?
    if not affordable(state, kind, owner) then return nil end
    return Structures.spawnTile(state, owner, tile)
end
local function canUpgrade(state: any, kind: string, owner: number, id: number): boolean
    if kind ~= "Factory" or not affordable(state, kind, owner) then return false end
    local value = unit(state, kind, id)
    return value ~= nil and value.owner == owner and value.active ~= false and not value.underConstruction and value.deletionMarkedTick == nil
end
local function canDelete(state: any, kind: string, owner: number, id: number): boolean
    if not validOwner(state, owner) or state.phase == "Choosing" then return false end
    local value = unit(state, kind, id)
    return value ~= nil and value.active ~= false and value.owner == owner and state.owners[value.tileId] == owner and state.map.land[value.tileId]
        and state.ticks - state.lastDeleteTicks[owner] >= GameConfig.forState(state).City.DeleteCooldownTicks
end
local function query(state: any, kind: string, owner: number, tile: number): any
    local result: any = { type = if kind == "DefensePost" then "Defense Post" else kind, cost = if validOwner(state, owner) then cost(state, kind, owner) else GameConfig.forState(state)[kind].BaseCost,
        canBuild = false, canUpgrade = false }
    if state.phase == "Choosing" or not validTile(state, tile) or not affordable(state, kind, owner) then return result end
    if kind == "Factory" then
        local nearest, distance, cellOrder = nil, math.huge, math.huge
        for _, value in state.factories or {} do
            if value.active == false then continue end
            local d = Economy.distanceSquared(state, tile, value.tileId)
            local x, y = (value.tileId - 1) % state.map.width, math.floor((value.tileId - 1) / state.map.width)
            local cell = math.floor(y / 100) * math.ceil(state.map.width / 100) + math.floor(x / 100)
            if d <= GameConfig.forState(state).City.StructureMinDistance ^ 2 and (d < distance or (d == distance and cell < cellOrder)) then nearest, distance, cellOrder = value, d, cell end
        end
        if nearest and canUpgrade(state, kind, owner, nearest.id) then
            result.canUpgrade, result.upgradeCosts = nearest.id, {}
            local total = 0
            for extra = 0, GameConfig.forState(state).City.MaxUpgradeAmount - 1 do total += cost(state, kind, owner, extra); table.insert(result.upgradeCosts, total) end
        end
    end
    result.canBuild = canBuild(state, kind, owner, tile) or false
    return result
end
local function removeOrder(state: any, kind: string, owner: number, id: number)
    local _, order = fields(kind)
    local index = table.find(state[order][owner], id)
    if index then table.remove(state[order][owner], index) end
end
local function remove(state: any, kind: string, value: any)
    if value.active == false then return end
    value.active = false
    if kind == "Factory" and state.invalidateRailUnitCounts then state.invalidateRailUnitCounts("Factory") end
    if state.recordUnitDeath then state.recordUnitDeath(value, if kind == "DefensePost" then "Defense Post" else kind) end
    if state.removeRailStation then state.removeRailStation(value) end
    removeOrder(state, kind, value.owner, value.id)
    local list = fields(kind)
    local index = table.find(state[list], value)
    if index then table.remove(state[list], index) end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[value.id] = nil end
end
function Structures.captureOwned(state: any, owner: number, orderedUnits: { any })
    -- PlayerExecution's first loop is mixed acquisition order. Rail deletion
    -- has observable graph effects, so sorting only after per-type mutation is insufficient.
    for _, value in orderedUnits do
        if value.owner ~= owner or value.active == false then continue end
        local kind = if Economy.city(state, value.id) == value then "City" elseif Ports.port(state, value.id) == value then "Port"
            elseif unit(state, "Factory", value.id) == value then "Factory" elseif unit(state, "DefensePost", value.id) == value then "DefensePost"
            elseif value.unitType == "Missile Silo" then "MissileSilo" elseif value.unitType == "SAM Launcher" then "SAMLauncher" else nil
        if not kind then continue end
        local function retire()
            if kind == "City" then Economy.removeCity(state, value)
            elseif kind == "Port" then Ports.removePort(state, value)
            elseif kind == "MissileSilo" or kind == "SAMLauncher" then if state.removeWeaponUnit then state.removeWeaponUnit(value) end
            else remove(state, kind, value) end
        end
        local nextOwner = state.owners[value.tileId]
        if nextOwner <= 0 then retire()
        elseif nextOwner ~= owner then
            if kind == "DefensePost" then retire()
            else
                local order = if kind == "City" then state.cityOrders elseif kind == "Port" then state.portOrders elseif kind == "MissileSilo" then state.missileSiloOrders
                    elseif kind == "SAMLauncher" then state.samLauncherOrders else state.factoryOrders
                local index = table.find(order[owner], value.id)
                if index then table.remove(order[owner], index) end
                value.owner, value.deletionMarkedTick = nextOwner, nil
                if kind == "Factory" and state.invalidateRailUnitCounts then state.invalidateRailUnitCounts("Factory") end
                table.insert(order[nextOwner], value.id); Ports.recordAcquisition(state, value)
            end
        end
    end
end
function Structures.playerTick(state: any, owner: number)
    for _, kind in { "Factory", "DefensePost" } do
        for _, value in owned(state, kind, owner) do
            local nextOwner = state.owners[value.tileId]
            if nextOwner <= 0 then remove(state, kind, value)
            elseif nextOwner ~= owner then
                -- Defense posts are destroyed on territorial capture, never captured.
                if kind == "DefensePost" then remove(state, kind, value)
                else
                    removeOrder(state, kind, owner, value.id)
                    value.owner, value.deletionMarkedTick = nextOwner, nil
                    if state.invalidateRailUnitCounts then state.invalidateRailUnitCounts("Factory") end
                    local _, order = fields(kind)
                    table.insert(state[order][nextOwner], value.id)
                    Ports.recordAcquisition(state, value)
                end
            end
        end
        if state.counts[owner] <= 0 then for _, value in owned(state, kind, owner) do remove(state, kind, value) end end
    end
    for _, fields in { { "missileSilos", "missileSiloOrders" }, { "samLaunchers", "samLauncherOrders" } } do
        local values = {}
        for _, value in state[fields[1]] or {} do if value.owner == owner and value.active ~= false then table.insert(values, value) end end
        for _, value in values do
            local nextOwner = state.owners[value.tileId]
            if nextOwner <= 0 then if state.removeWeaponUnit then state.removeWeaponUnit(value) end
            elseif nextOwner ~= owner then
                local order = state[fields[2]]
                local index = table.find(order[owner], value.id); if index then table.remove(order[owner], index) end
                value.owner, value.deletionMarkedTick = nextOwner, nil
                table.insert(order[nextOwner], value.id); Ports.recordAcquisition(state, value)
            end
        end
        if state.counts[owner] <= 0 and state.removeWeaponUnit then
            local remaining = {}
            for _, value in state[fields[1]] or {} do if value.owner == owner then table.insert(remaining, value) end end
            for _, value in remaining do state.removeWeaponUnit(value) end
        end
    end
end
local function executionType(execution: any): string? return string.match(execution.kind, "Factory$") or string.match(execution.kind, "DefensePost$") end
function Structures.initExecution(state: any, execution: any): boolean
    local kind = executionType(execution)
    if not kind then return false end
    if execution.kind == "Build" .. kind then return validTile(state, execution.tileId) and GameConfig.forState(state)[kind].Enabled end
    if execution.kind == "Upgrade" .. kind then
        local _, _, history = fields(kind)
        for _ = 1, execution.amount do
            if not canUpgrade(state, kind, execution.owner, execution.unitId) then break end
            local value = unit(state, kind, execution.unitId)
            state.gold[execution.owner] -= cost(state, kind, execution.owner)
            value.level += 1; state[history][execution.owner] += 1
            if kind == "Factory" and state.invalidateRailUnitCounts then state.invalidateRailUnitCounts("Factory") end
        end
        return false
    end
    if execution.kind == "Delete" .. kind and canDelete(state, kind, execution.owner, execution.unitId) then
        state.lastDeleteTicks[execution.owner] = state.ticks
        unit(state, kind, execution.unitId).deletionMarkedTick = state.ticks + GameConfig.forState(state).City.DeletionMarkTicks
        return true
    end
    return false
end
function Structures.tickExecution(state: any, execution: any): boolean
    local kind = executionType(execution)
    if not kind then return false end
    if execution.kind == "Build" .. kind then
        if execution.unitId == nil then
            local tile = canBuild(state, kind, execution.owner, execution.tileId)
            if not tile then return false end
            local value = { id = state.nextUnitId, owner = execution.owner, tileId = tile, level = 1,
                active = true, underConstruction = true, createdTick = state.ticks, hasTrainStation = false }
            local list, order, history = fields(kind)
            state.nextUnitId += 1; state.gold[execution.owner] -= cost(state, kind, execution.owner); state[history][execution.owner] += 1
            table.insert(state[list], value); table.insert(state[order][execution.owner], value.id); Ports.recordAcquisition(state, value)
            if kind == "Factory" and state.invalidateRailUnitCounts then state.invalidateRailUnitCounts("Factory") end
            execution.unitId, execution.remaining = value.id, GameConfig.forState(state)[kind].ConstructionTicks
            if execution.remaining == 0 then
                value.underConstruction = false
                if kind == "Factory" then table.insert(state.pendingExecutions, { kind = "FactoryStation", unitId = value.id }) end
                return false
            end
            return true
        end
        local value = unit(state, kind, execution.unitId)
        if not value then return false end
        if execution.remaining == 0 then
            value.underConstruction = false
            if kind == "Factory" then table.insert(state.pendingExecutions, { kind = "FactoryStation", unitId = value.id }) end
            return false
        end
        execution.remaining -= 1; return true
    end
    if execution.kind == "Delete" .. kind then
        local value = unit(state, kind, execution.unitId)
        if not value then return false end
        if value.deletionMarkedTick and state.ticks > value.deletionMarkedTick then remove(state, kind, value); return false end
        return true
    end
    return false
end
function Structures.defensePostProtectsTile(state: any, owner: number, tile: number): boolean
    if not validOwner(state, owner) or not validTile(state, tile) then return false end
    for _, value in state.defensePosts or {} do
        if value.owner == owner and value.active ~= false and not value.underConstruction
            and Economy.distanceSquared(state, tile, value.tileId) <= GameConfig.forState(state).DefensePost.Range ^ 2 then return true end
    end
    return false
end
function Structures.factory(state: any, id: number): any return unit(state, "Factory", id) end
function Structures.defensePost(state: any, id: number): any return unit(state, "DefensePost", id) end
function Structures.ownedFactories(state: any, owner: number): { any } return owned(state, "Factory", owner) end
function Structures.ownedDefensePosts(state: any, owner: number): { any } return owned(state, "DefensePost", owner) end
function Structures.factoryLevels(state: any, owner: number): number return levels(state, "Factory", owner) end
function Structures.defensePostLevels(state: any, owner: number): number return levels(state, "DefensePost", owner) end
function Structures.factoryCost(state: any, owner: number, extra: number?): number return cost(state, "Factory", owner, extra) end
function Structures.defensePostCost(state: any, owner: number, extra: number?): number return cost(state, "DefensePost", owner, extra) end
function Structures.canBuildFactory(state: any, owner: number, tile: number): number? return canBuild(state, "Factory", owner, tile) end
function Structures.canBuildDefensePost(state: any, owner: number, tile: number): number? return canBuild(state, "DefensePost", owner, tile) end
function Structures.canUpgradeFactory(state: any, owner: number, id: number): boolean return canUpgrade(state, "Factory", owner, id) end
function Structures.canUpgradeDefensePost(_state: any, _owner: number, _id: number): boolean return false end
function Structures.canDeleteFactory(state: any, owner: number, id: number): boolean return canDelete(state, "Factory", owner, id) end
function Structures.canDeleteDefensePost(state: any, owner: number, id: number): boolean return canDelete(state, "DefensePost", owner, id) end
function Structures.queryBuildableFactory(state: any, owner: number, tile: number): any return query(state, "Factory", owner, tile) end
function Structures.queryBuildableDefensePost(state: any, owner: number, tile: number): any return query(state, "DefensePost", owner, tile) end
function Structures.removeFactory(state: any, value: any) remove(state, "Factory", value) end
function Structures.removeDefensePost(state: any, value: any) remove(state, "DefensePost", value) end
return table.freeze(Structures)
