--!strict
--!native
-- OpenFrontIO 93a136a1: Silo/SAM construction, UnitImpl reload/range and SAM targeting/flight.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Economy = require(script.Parent.OpenFrontEconomy)
local Ports = require(script.Parent.OpenFrontPorts)
local Structures = require(script.Parent.OpenFrontStructures)
local Warships = require(script.Parent.OpenFrontWarships)
local Index = require(script.Parent.OpenFrontUnitIndex)
local Weapons = {}
local kinds = { MissileSilo = { "missileSilos", "missileSiloOrders", "missileSiloConstructed", "Missile Silo" },
    SAMLauncher = { "samLaunchers", "samLauncherOrders", "samLauncherConstructed", "SAM Launcher" } }
local nukeTypes = { ["Atom Bomb"] = 1, ["Hydrogen Bomb"] = 2, ["MIRV Warhead"] = 3 }
local function integer(v: any): boolean return type(v) == "number" and v == v and math.abs(v) < math.huge and v % 1 == 0 end
local function validOwner(state: any, owner: any): boolean return integer(owner) and owner >= 1 and owner <= #state.players end
local function validTile(state: any, tile: any): boolean return integer(tile) and tile >= 1 and tile <= state.map.width * state.map.height end
local function active(unit: any): boolean return unit ~= nil and unit.active ~= false end
local function distance(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs(math.floor((a - 1) / w) - math.floor((b - 1) / w))
end
local function kindFor(unit: any): string? return if unit.unitType == "Missile Silo" then "MissileSilo" elseif unit.unitType == "SAM Launcher" then "SAMLauncher" else nil end
function Weapons.unit(state: any, kind: string, id: number): any
    local value = Index.byId(state[kinds[kind][1]], id) -- PF-4: ids are unique, so the first match is the only one
    return if value ~= nil and active(value) then value else nil
end
function Weapons.owned(state: any, kind: string, owner: number): {any}
    local result, fields = {}, kinds[kind]
    if state[fields[2]] then
        for _, id in state[fields[2]][owner] or {} do local value = Weapons.unit(state, kind, id); if value then table.insert(result, value) end end
    else for _, value in state[fields[1]] or {} do if value.owner == owner and active(value) then table.insert(result, value) end end end
    return result
end
function Weapons.ownedLevels(state: any, kind: string, owner: number): number
    local total = 0
    for _, value in state[kinds[kind][1]] or {} do if value.owner == owner and active(value) then total += if value.underConstruction then 1 else value.level end end
    return total
end
function Weapons.cost(state: any, kind: string, owner: number, extra: number?): number
    if GameConfig.freeGold(state, owner) then return 0 end
    if kind == "MissileSilo" then return GameConfig.forState(state).MissileSilo.BaseCost end
    local count = math.min(Weapons.ownedLevels(state, kind, owner), (state[kinds[kind][3]] and state[kinds[kind][3]][owner]) or 0)
    return math.min(GameConfig.forState(state).SAMLauncher.MaxCost, GameConfig.forState(state).SAMLauncher.BaseCost * (count + (extra or 0) + 1))
end
local function affordable(state: any, kind: string, owner: number): boolean
    return validOwner(state, owner) and GameConfig.forState(state)[kind].Enabled and state.counts[owner] > 0 and state.gold[owner] >= Weapons.cost(state, kind, owner)
end
function Weapons.canBuild(state: any, kind: string, owner: number, tile: number): number?
    if not affordable(state, kind, owner) then return nil end
    return Structures.spawnTile(state, owner, tile)
end
function Weapons.canUpgrade(state: any, kind: string, owner: number, id: number): boolean
    if not affordable(state, kind, owner) then return false end
    local value = Weapons.unit(state, kind, id)
    return value ~= nil and value.owner == owner and not value.underConstruction and value.deletionMarkedTick == nil
end
function Weapons.canDelete(state: any, kind: string, owner: number, id: number): boolean
    if not validOwner(state, owner) or state.phase == "Choosing" then return false end
    local value = Weapons.unit(state, kind, id)
    return value ~= nil and value.owner == owner and state.owners[value.tileId] == owner and state.map.land[value.tileId]
        and state.ticks - state.lastDeleteTicks[owner] >= GameConfig.forState(state).City.DeleteCooldownTicks
end
function Weapons.query(state: any, kind: string, owner: number, tile: number): any
    local result: any = { type = kinds[kind][4], cost = if validOwner(state, owner) then Weapons.cost(state, kind, owner) else GameConfig.forState(state)[kind].BaseCost,
        canBuild = false, canUpgrade = false }
    if state.phase == "Choosing" or not validTile(state, tile) or not affordable(state, kind, owner) then return result end
    local nearest, nearestDistance, cellOrder = nil, math.huge, math.huge
    for _, value in state[kinds[kind][1]] or {} do
        if not active(value) then continue end
        local d = Economy.distanceSquared(state, tile, value.tileId)
        local cell = math.floor(math.floor((value.tileId - 1) / state.map.width) / 100) * math.ceil(state.map.width / 100) + math.floor(((value.tileId - 1) % state.map.width) / 100)
        if d <= GameConfig.forState(state).City.StructureMinDistance ^ 2 and (d < nearestDistance or (d == nearestDistance and cell < cellOrder)) then nearest, nearestDistance, cellOrder = value, d, cell end
    end
    if nearest and Weapons.canUpgrade(state, kind, owner, nearest.id) then
        result.canUpgrade, result.upgradeCosts = nearest.id, {}
        local total = 0
        for extra = 0, GameConfig.forState(state).City.MaxUpgradeAmount - 1 do total += Weapons.cost(state, kind, owner, extra); table.insert(result.upgradeCosts, total) end
    end
    result.canBuild = Weapons.canBuild(state, kind, owner, tile) or false
    return result
end
-- The one SAM range (the simulation, the nation AI and the client's rings all call this).
function Weapons.samRange(level: number): number return Config.SAMLauncher.MaxRange - Config.SAMLauncher.RangeFalloff / (level + 5) end
function Weapons.dynamicSamRange(sam: any, tick: number): number
    local value = sam.samLauncherState
    if not value or value.upgradeStartTick == nil then return Weapons.samRange(sam.level) end
    local duration = value.duration or Config.SAMLauncher.UpgradeTicks
    local elapsed = tick - value.upgradeStartTick
    if elapsed >= duration then return Weapons.samRange(value.targetLevel) end
    return value.startRange + (Weapons.samRange(value.targetLevel) - value.startRange) * elapsed / duration
end
function Weapons.canLaunch(value: any, _tick: number?): boolean
    return active(value) and not value.underConstruction and #(value.missileTimerQueue or {}) ~= value.level
end
function Weapons.launchSilo(state: any, value: any) table.insert(value.missileTimerQueue, state.ticks) end
function Weapons.increaseLevel(state: any, value: any)
    if kindFor(value) == "SAMLauncher" then
        value.samLauncherState = { upgradeStartTick = state.ticks, startRange = Weapons.dynamicSamRange(value, state.ticks),
            targetLevel = value.level + 1, duration = GameConfig.forState(state).SAMLauncher.UpgradeTicks }
    end
    value.level += 1; table.insert(value.missileTimerQueue, state.ticks)
end
function Weapons.decreaseLevel(state: any, value: any, destroyer: number?)
    value.level -= 1; table.remove(value.missileTimerQueue)
    if kindFor(value) == "SAMLauncher" then value.samLauncherState = nil end
    if value.level <= 0 then Weapons.removeUnit(state, value, destroyer) end
end
function Weapons.removeUnit(state: any, value: any, _destroyer: number?)
    if not active(value) then return end
    local kind = kindFor(value)
    value.active = false
    if state.recordUnitDeath then state.recordUnitDeath(value, value.unitType or "SAMMissile") end
    local list = if kind then state[kinds[kind][1]] else state.samMissiles
    local index = table.find(list, value); if index then table.remove(list, index) end
    if kind then local order = state[kinds[kind][2]][value.owner]; local orderIndex = table.find(order, value.id); if orderIndex then table.remove(order, orderIndex) end end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[value.id] = nil end
end
function Weapons.trackUnit(state: any, value: any)
    if not nukeTypes[value.unitType] then return end
    local w = state.map.width
    local cell = math.floor(math.floor((value.tileId - 1) / w) / 100) * math.ceil(w / 100) + math.floor(((value.tileId - 1) % w) / 100)
    if value._samGridState == state and value._samGridCell == cell then return end
    state.samGridOrder = (state.samGridOrder or 0) + 1
    value._samGridState, value._samGridCell, value._samGridOrder = state, cell, state.samGridOrder
end
local function validTarget(state: any, sam: any, value: any, api: any): boolean
    if not active(value) or value.targetedBySAM or value.owner == sam.owner then return false end
    if api and api.friendly and api.friendly(sam.owner, value.owner) then
        return state.winner ~= nil and GameConfig.forState(state).Match.GameType ~= "Singleplayer" and api.sameTeam ~= nil and api.sameTeam(sam.owner, value.owner)
    end
    return true
end
local function nearbyTargets(state: any, sam: any, api: any): {any}
    local result = {}
    for _, value in state.nukes or {} do
        if nukeTypes[value.unitType] and validTarget(state, sam, value, api)
            and Economy.distanceSquared(state, sam.tileId, value.tileId) <= (GameConfig.forState(state).SAMLauncher.MaxRange * 4) ^ 2 then
            Weapons.trackUnit(state, value); table.insert(result, value)
        end
    end
    table.sort(result, function(a, b)
        if a._samGridCell ~= b._samGridCell then return a._samGridCell < b._samGridCell end
        if a.unitType ~= b.unitType then return nukeTypes[a.unitType] < nukeTypes[b.unitType] end
        return a._samGridOrder < b._samGridOrder
    end)
    return result
end
function Weapons.computeInterception(state: any, sam: any, value: any, tick: number): any
    local trajectory, cur, waitTicks = value.trajectory, value.trajectoryIndex, value.waitTicks or 0
    local maxIndex, minDist, closest, increasing, lastDistance = #trajectory - 2, math.huge, sam.tileId, 0, -1
    local speed = GameConfig.forState(state).SAMLauncher.MissileSpeed
    for index = cur, maxIndex do
        local tile = trajectory[index + 1]
        local d = Economy.distanceSquared(state, sam.tileId, tile.tileId)
        if d < minDist then minDist, closest = d, tile.tileId end
        increasing = if lastDistance ~= -1 and d > lastDistance then increasing + 1 else 0
        lastDistance = d
        local nukeTicks, samTicks = index - cur + waitTicks, math.ceil(distance(state, sam.tileId, tile.tileId) / speed)
        local range = Weapons.dynamicSamRange(sam, tick + nukeTicks)
        if tile.targetable and d <= range ^ 2 and nukeTicks >= samTicks then
            return { tick = nukeTicks - samTicks, tile = tile.tileId, minDistSq = minDist, lastSeenTick = tick }
        end
        if increasing > 3 and d > GameConfig.forState(state).SAMLauncher.MaxRange ^ 2 then break end
    end
    local finalTile, flightTile = trajectory[#trajectory], trajectory[#trajectory - 1]
    if finalTile and finalTile.targetable then
        local explosionTicks = #trajectory - 1 - cur + waitTicks
        local range = Weapons.dynamicSamRange(sam, tick + explosionTicks)
        if Economy.distanceSquared(state, sam.tileId, finalTile.tileId) <= range ^ 2 and flightTile and flightTile.targetable then
            local before = maxIndex - cur + waitTicks - math.ceil(distance(state, sam.tileId, flightTile.tileId) / speed)
            if before >= 0 then return { tick = before, tile = flightTile.tileId, minDistSq = minDist, lastSeenTick = tick } end
        end
    end
    return { tick = if minDist > GameConfig.forState(state).SAMLauncher.MaxRange ^ 2 then -2 else -1, tile = closest, minDistSq = minDist, lastSeenTick = tick }
end
function Weapons.targetScore(state: any, sam: any, value: any): number
    local target = value.targetTile or value.targetTileId or (value.trajectory[#value.trajectory] and value.trajectory[#value.trajectory].tileId) or sam.tileId
    return (if value.unitType == "Hydrogen Bomb" then 70001 else 0) + math.max(0, 200000 - distance(state, sam.tileId, target) * 1000)
        + math.max(0, 10000 - math.max(1, #value.trajectory - value.trajectoryIndex) * 100)
end
function Weapons.getValidTargets(state: any, execution: any, sam: any, tick: number, api: any?): {any}
    execution.targetCache = execution.targetCache or {}
    local cache, targets = execution.targetCache, {}
    for _, value in nearbyTargets(state, sam, api) do
        local previous, recompute = cache[value.id], true
        if previous then
            previous.lastSeenTick = tick
            if previous.tick == -2 or previous.tick == -1 then continue end
            if previous.tick == tick or previous.tick == tick + 1 then
                table.insert(targets, { tile = previous.tile, unit = value, order = #targets + 1 }); cache[value.id] = nil; continue
            end
            if previous.tick > tick then continue end
            cache[value.id] = nil
        end
        if recompute then
            local entry = Weapons.computeInterception(state, sam, value, tick)
            if entry.tick >= 0 and entry.tick <= 1 then table.insert(targets, { tile = entry.tile, unit = value, order = #targets + 1 })
            else entry.tick = if entry.tick >= 0 then entry.tick + tick else entry.tick; cache[value.id] = entry end
        end
    end
    for id, entry in cache do if entry.lastSeenTick ~= tick then cache[id] = nil end end
    if #targets > 1 then
        for _, target in targets do target.score = Weapons.targetScore(state, sam, target.unit) end
        table.sort(targets, function(a, b) return if a.score == b.score then a.order < b.order else a.score > b.score end)
    end
    return targets
end
local function structureKind(execution: any): string? return string.match(execution.kind, "MissileSilo$") or string.match(execution.kind, "SAMLauncher$") end
function Weapons.initExecution(state: any, execution: any, api: any?): boolean
    local kind = structureKind(execution)
    if kind then
        if execution.kind == "Build" .. kind then return GameConfig.forState(state)[kind].Enabled and validTile(state, execution.tileId) end
        if execution.kind == "Upgrade" .. kind then
            for _ = 1, execution.amount do
                if not Weapons.canUpgrade(state, kind, execution.owner, execution.unitId) then break end
                state.gold[execution.owner] -= Weapons.cost(state, kind, execution.owner)
                Weapons.increaseLevel(state, Weapons.unit(state, kind, execution.unitId)); state[kinds[kind][3]][execution.owner] += 1
            end
            return false
        end
        if execution.kind == "Delete" .. kind and Weapons.canDelete(state, kind, execution.owner, execution.unitId) then
            state.lastDeleteTicks[execution.owner] = state.ticks
            Weapons.unit(state, kind, execution.unitId).deletionMarkedTick = state.ticks + GameConfig.forState(state).City.DeletionMarkTicks
            return true
        end
        return false
    end
    if execution.kind == "MissileSiloTick" or execution.kind == "SAMLauncherTick" then execution.lastLevel, execution.targetCache = 1, {}; return true end
    if execution.kind == "SAMMissile" then
        execution.path, execution.pathIndex = Warships.airPath(state, state.ticks, execution.spawn, execution.targetTile), 2
        return Weapons.tickExecution(state, execution, api)
    end
    return false
end
function Weapons.tickExecution(state: any, execution: any, api: any?): boolean
    local kind = structureKind(execution)
    if kind then
        if execution.kind == "Build" .. kind then
            if execution.unitId == nil then
                local tile = Weapons.canBuild(state, kind, execution.owner, execution.tileId); if not tile then return false end
                local fields = kinds[kind]
                local value: any = { id = state.nextUnitId, owner = execution.owner, tileId = tile, level = 1, active = true,
                    unitType = fields[4], underConstruction = true, createdTick = state.ticks, missileTimerQueue = {} }
                if kind == "SAMLauncher" then value.samLauncherState = { startRange = Weapons.samRange(1), targetLevel = 1, duration = GameConfig.forState(state).SAMLauncher.UpgradeTicks } end
                state.nextUnitId += 1; state.gold[execution.owner] -= Weapons.cost(state, kind, execution.owner); state[fields[3]][execution.owner] += 1
                table.insert(state[fields[1]], value); table.insert(state[fields[2]][value.owner], value.id); Ports.recordAcquisition(state, value)
                execution.unitId, execution.remaining = value.id, GameConfig.forState(state)[kind].ConstructionTicks
                if execution.remaining == 0 then
                    value.underConstruction = false
                    table.insert(state.pendingExecutions, { kind = kind .. "Tick", unitId = value.id, owner = value.owner })
                    return false
                end
                return true
            end
            local value = Weapons.unit(state, kind, execution.unitId); if not value then return false end
            if execution.remaining == 0 then
                value.underConstruction = false
                table.insert(state.pendingExecutions, { kind = kind .. "Tick", unitId = value.id, owner = value.owner })
                return false
            end
            execution.remaining -= 1; return true
        end
        if execution.kind == "Delete" .. kind then
            local value = Weapons.unit(state, kind, execution.unitId); if not value then return false end
            if value.deletionMarkedTick and state.ticks > value.deletionMarkedTick then Weapons.removeUnit(state, value); return false end
            return true
        end
        return false
    end
    if execution.kind == "MissileSiloTick" or execution.kind == "SAMLauncherTick" then
        local typ = if execution.kind == "MissileSiloTick" then "MissileSilo" else "SAMLauncher"
        local value = Weapons.unit(state, typ, execution.unitId); if not value then return false end
        if typ == "SAMLauncher" and execution.lastLevel ~= value.level then
            execution.lastLevel = value.level
            for id, cached in execution.targetCache do if cached.tick == -1 then execution.targetCache[id] = nil end end
        end
        if value.underConstruction then return true end
        execution.owner = value.owner
        local queue = value.missileTimerQueue
        if typ == "MissileSilo" then if queue[1] and state.ticks - queue[1] >= GameConfig.forState(state).MissileSilo.CooldownTicks then table.remove(queue, 1) end; return true end
        while queue[1] and state.ticks - queue[1] >= GameConfig.forState(state).SAMLauncher.CooldownTicks do table.remove(queue, 1) end
        if not Weapons.canLaunch(value) then return true end
        local anyNukes = false
        for _, nuke in state.nukes or {} do if active(nuke) and nukeTypes[nuke.unitType] then anyNukes = true; break end end
        if not anyNukes then return true end
        for _, target in Weapons.getValidTargets(state, execution, value, state.ticks, api) do
            if not Weapons.canLaunch(value) then break end
            Weapons.launchSilo(state, value); target.unit.targetedBySAM = true
            table.insert(state.pendingExecutions, { kind = "SAMMissile", owner = value.owner, spawn = value.tileId,
                ownerUnit = value, target = target.unit, targetTile = target.tile })
        end
        return true
    end
    if execution.kind == "SAMMissile" then
        local target, ownerUnit = execution.target, execution.ownerUnit
        if execution.unit == nil then
            execution.unit = { id = state.nextUnitId, owner = execution.owner, tileId = execution.spawn, unitType = "SAMMissile",
                active = true, targetUnitId = target.id, createdTick = state.ticks }
            state.nextUnitId += 1; table.insert(state.samMissiles, execution.unit); Ports.recordAcquisition(state, execution.unit)
        end
        local value = execution.unit
        if not active(value) then return false end
        if not active(target) or not active(ownerUnit) or target.owner == value.owner or not nukeTypes[target.unitType] then
            if active(target) then target.targetedBySAM = false end
            Weapons.removeUnit(state, value); return false
        end
        for _ = 1, GameConfig.forState(state).SAMLauncher.MissileSpeed do
            if value.tileId == execution.targetTile or execution.pathIndex > #execution.path then
                if state.recordWeaponMessage then state.recordWeaponMessage({ kind = "SAMHit", owner = execution.owner, unitType = target.unitType, targetId = target.id, tick = state.ticks }) end
                if state.removeNukeUnit then state.removeNukeUnit(target, execution.owner) end
                if state.recordBombStat then state.recordBombStat(execution.owner, target.unitType, "intercepted", 1) end
                Weapons.removeUnit(state, value); return false
            end
            value.tileId = execution.path[execution.pathIndex]; execution.pathIndex += 1
        end
        return true
    end
    return false
end
function Weapons.install(state: any)
    state.samMissiles = state.samMissiles or {}
    for _, fields in kinds do
        state[fields[1]], state[fields[2]], state[fields[3]] = state[fields[1]] or {}, state[fields[2]] or {}, state[fields[3]] or {}
        for owner = 1, #state.players do state[fields[2]][owner] = state[fields[2]][owner] or {}; state[fields[3]][owner] = state[fields[3]][owner] or 0 end
    end
    state.trackWeaponUnit = function(value) Weapons.trackUnit(state, value) end
    state.removeWeaponUnit = function(value, destroyer) Weapons.removeUnit(state, value, destroyer) end
end
function Weapons.snapshot(state: any, ownershipOrder: any?): any
    local result = { missileSilos = {}, samLaunchers = {}, samMissiles = {} }
    for kind, fields in kinds do
        for _, value in state[fields[1]] or {} do
            local copy: any = { id = value.id, owner = value.owner, tileId = value.tileId, level = value.level, active = value.active ~= false,
                unitType = fields[4], underConstruction = value.underConstruction, createdTick = value.createdTick,
                deletionMarkedTick = value.deletionMarkedTick, missileTimerQueue = table.clone(value.missileTimerQueue) }
            if value.samLauncherState then copy.samLauncherState = table.clone(value.samLauncherState) end
            if ownershipOrder then copy.ownershipOrder = ownershipOrder[value.id] or value.id end
            table.insert(result[fields[1]], copy)
        end
    end
    for _, value in state.samMissiles or {} do
        table.insert(result.samMissiles, { id = value.id, owner = value.owner, tileId = value.tileId, active = value.active ~= false,
            unitType = "SAMMissile", targetUnitId = value.targetUnitId, createdTick = value.createdTick })
    end
    return result
end
function Weapons.missileSilo(state: any, id: number): any return Weapons.unit(state, "MissileSilo", id) end
function Weapons.samLauncher(state: any, id: number): any return Weapons.unit(state, "SAMLauncher", id) end
function Weapons.canBuildMissileSilo(state: any, owner: number, tile: number): number? return Weapons.canBuild(state, "MissileSilo", owner, tile) end
function Weapons.canBuildSAMLauncher(state: any, owner: number, tile: number): number? return Weapons.canBuild(state, "SAMLauncher", owner, tile) end
function Weapons.canUpgradeMissileSilo(state: any, owner: number, id: number): boolean return Weapons.canUpgrade(state, "MissileSilo", owner, id) end
function Weapons.canUpgradeSAMLauncher(state: any, owner: number, id: number): boolean return Weapons.canUpgrade(state, "SAMLauncher", owner, id) end
function Weapons.canDeleteMissileSilo(state: any, owner: number, id: number): boolean return Weapons.canDelete(state, "MissileSilo", owner, id) end
function Weapons.canDeleteSAMLauncher(state: any, owner: number, id: number): boolean return Weapons.canDelete(state, "SAMLauncher", owner, id) end
function Weapons.queryBuildableMissileSilo(state: any, owner: number, tile: number): any return Weapons.query(state, "MissileSilo", owner, tile) end
function Weapons.queryBuildableSAMLauncher(state: any, owner: number, tile: number): any return Weapons.query(state, "SAMLauncher", owner, tile) end
return table.freeze(Weapons)
