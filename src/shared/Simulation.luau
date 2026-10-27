--!strict
--!native
-- Land-match port of OpenFrontIO at 93a136a1e2915ec7bb83e34980ba5836a91f63ee (AGPL-3.0).
-- References: AttackExecution, SpawnExecution, TribeExecution, AiAttackBehavior,
-- PlayerImpl, GameImpl.updateBorders, WinCheckExecution. See docs/PARITY_AUDIT.md.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Math = require(script.Parent.OpenFrontMath)
local Teams = require(script.Parent.OpenFrontTeams)
local Victory = require(script.Parent.OpenFrontVictory)
local Doomsday = require(script.Parent.OpenFrontDoomsday)
local Water = require(script.Parent.OpenFrontWaterManager)
local MapData = require(script.Parent.MapData)
local Random = require(script.Parent.OpenFrontRandom)
local Rules = require(script.Parent.OpenFrontRules)
local Collections = require(script.Parent.OpenFrontCollections)
local Territory = require(script.Parent.OpenFrontTerritory)
local Roster = require(script.Parent.OpenFrontRoster)
local Balance = require(script.Parent.OpenFrontMatchBalance)
local NationAI = require(script.Parent.OpenFrontNationAI)
local Economy = require(script.Parent.OpenFrontEconomy)
local NationPortAI = require(script.Parent.OpenFrontNationPortAI)
local Naval = require(script.Parent.OpenFrontNaval)
local NationNavalAI = require(script.Parent.OpenFrontNationNavalAI)
local Ports = require(script.Parent.OpenFrontPorts)
local Trade = require(script.Parent.OpenFrontTrade)
local Warships = require(script.Parent.OpenFrontWarships)
local NationWarshipAI = require(script.Parent.OpenFrontNationWarshipAI)
local Structures = require(script.Parent.OpenFrontStructures)
local Rails = require(script.Parent.OpenFrontRails)
local Trains = require(script.Parent.OpenFrontTrains)
local NationNukeAI = require(script.Parent.OpenFrontNationNukeAI)
local NationMIRVAI = require(script.Parent.OpenFrontNationMIRVAI)
local Weapons = require(script.Parent.OpenFrontWeapons)
local Nukes = require(script.Parent.OpenFrontNukes)
local Diplomacy = require(script.Parent.OpenFrontDiplomacy)
local NationDiplomacyAI = require(script.Parent.OpenFrontNationDiplomacyAI)
local NationEmojiAI = require(script.Parent.OpenFrontNationEmojiAI)
local TribeAI = require(script.Parent.OpenFrontTribeAI)
local QuickChat = require(script.Parent.OpenFrontQuickChat)
local AttackPositions = require(script.Parent.OpenFrontAttackPositions)
local MatchMetadata = require(script.Parent.MatchMetadataTransport)

export type Campaign = {
    id: number, owner: number, targetOwner: number, budget: number, retreating: boolean,
    retreated: boolean?, createdTick: number, active: boolean, random: Random.State, heap: Collections.Heap,
    border: { [number]: boolean }, borderOrder: Collections.OrderedSet?, borderSize: number, sourceTile: number?,
}
export type State = {
    map: any, owners: { number }, troops: { number }, counts: { number },
    phase: string, elapsed: number, seed: number, ticks: number, startTick: number, accumulator: number,
    attacks: { Campaign }, nextAttackId: number, changedOwners: { [number]: number },
    executions: { any }, pendingExecutions: { any },
    territories: { Collections.OrderedSet }, borders: { Collections.OrderedSet },
    spawnTiles: { [number]: number }, bot: any, bots: { [number]: any }, winner: number?, names: { string },
    players: { Roster.Player }, playerOrder: { number }, executionOrder: { number }, nations: { [number]: any },
    spawnPhasePending: { any }, choosingDeadline: number?, ownerEpoch: number?, autoPlaced: { [number]: boolean }?,
    largestClusterBounds: { any }, lastTileChange: { number }, lastClusterCalc: { number }, tileChangeVersion: { number },
    gold: { number }, goldEarned: { number }, cityConstructed: { number }, lastDeleteTicks: { number },
    attacksSent: { number }, cities: { any }, cityOrders: { { number } }, nextUnitId: number,
    conquestEvents: { any }, nextConquestEventId: number,
    nationApi: any?, navalApi: any?, ships: { any }, shipStagger: number, navalMessages: { any },
    ports: { any }, portOrders: { { number } }, portConstructed: { number },
    unitAcquisitionOrder: { [number]: number }, nextUnitAcquisitionOrder: number,
    tradeShips: { any }, tradeApi: any?, tradeGold: { number }, piracyGold: { number },
    bonusEvents: { any }, nextBonusEventId: number,
    warships: { any }, shells: { any }, warshipConstructed: { number }, warshipApi: any?,
    trackWarshipUnit: ((any) -> ())?, deadUnitEvents: { any }, nextDeadUnitEventId: number,
    factories: {any}, defensePosts: {any}, factoryOrders: {{number}}, defensePostOrders: {{number}},
    factoryConstructed: {number}, defensePostConstructed: {number}, trainGold: {number},
    stations: {any}, railroads: {any}, trains: {any}, removeRailStation: any?, portRailTick: any?,
    addTrainGold: any?, removeTrainUnit: any?,
    removeStructureUnit: any?,
    missileSilos: {any}, samLaunchers: {any}, samMissiles: {any}, nukes: {any},
    missileSiloOrders: {{number}}, samLauncherOrders: {{number}},
    missileSiloConstructed: {number}, samLauncherConstructed: {number},
    falloutTiles: {[number]: boolean}, falloutCount: number, changedFalloutIds: {[number]: boolean}, changedTerrainIds: {[number]: boolean},
    waterManager: any?, waterGraphVersion: number?, setFallout: any?,
    weaponMessages: {any}, nextWeaponMessageId: number,
    weaponApi: any?, nuclearApi: any?, recordWeaponMessage: any?, removeWeaponUnit: any?,
    removeNukeUnit: any?, trackWeaponUnit: any?, nuclearStats: any?, mirvsLaunched: number?,
    recordUnitDeath: any?, relinquishTile: any?, queueWaterConversion: any?, deleteMixedUnit: any?,
    maxTroopsFor: any?, nukeMessage: any?, canLaunchSilo: any?, launchSilo: any?, gameType: string?, spawnImmunityActive: any?,
    diplomacy: any, diplomacyRequests: {any}, alliances: {any}, diplomacyHooks: any,
    diplomacyEvents: {any}, nextDiplomacyEventId: number, nextAllianceId: number,
    playerExecutionRemoved: {[number]: boolean}, quickChat: any,
    gameConfig: any?, gameId: string?, teams: {string}?, winnerTeam: string?, victory: any?, doomsday: any?, humanSpawnRandom: any?, playerInitTicks: {[number]: number},
    matchBalance: boolean?, incomeLandCount: number?, recordTutorialAction: ((number,string)->any)?, tutorialStep: ((any)->())?, tutorialWinHeld: ((any,number)->boolean)?,
    isFriendly: any?, isOnSameTeam: any?, nukeDiplomacy: any?, mirvDiplomacy: any?, railApi: any?,
}
local Simulation = {}
local shoreDirections = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
local function finite(value: any): boolean
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function ownerValid(state: any, owner: any): boolean
    return finite(owner) and owner % 1 == 0 and owner >= 1 and owner <= #state.players
end
local function isBot(state: any, owner: number): boolean return state.players[owner].playerType == "Bot" end
local function validId(state: any, id: any): boolean
    return finite(id) and id % 1 == 0 and id >= 1 and id <= state.map.width * state.map.height
end
local function neighbors(state: any, id: number, output: { number }): { number }
    return MapData.neighbors(id, state.map.width, state.map.height, output)
end
local function magnitude(state: any, id: number): number
    return bit32.band(buffer.readu8(state.map.terrain, id - 1), 31)
end
local function passable(state: any, id: number): boolean return state.map.land[id] and magnitude(state, id) < 31 end
local function distance(state: any, a: number, b: number): number
    local width = state.map.width
    return math.abs((a - 1) % width - (b - 1) % width)
        + math.abs(math.floor((a - 1) / width) - math.floor((b - 1) / width))
end
local function adjacent(state: any, id: number, owner: number): boolean
    local width, owners = state.map.width, state.owners
    local x = (id - 1) % width
    return (id > width and owners[id - width] == owner)
        or (id <= width * (state.map.height - 1) and owners[id + width] == owner)
        or (x > 0 and owners[id - 1] == owner)
        or (x < width - 1 and owners[id + 1] == owner)
end
local function isBorder(state: any, id: number): boolean
    local width, owners = state.map.width, state.owners
    local x, owner = (id - 1) % width, math.max(0, owners[id])
    return (id > width and math.max(0, owners[id - width]) ~= owner)
        or (id <= width * (state.map.height - 1) and math.max(0, owners[id + width]) ~= owner)
        or (x > 0 and math.max(0, owners[id - 1]) ~= owner)
        or (x < width - 1 and math.max(0, owners[id + 1]) ~= owner)
end
local function updateBorder(state: State, id: number)
    local owner = state.owners[id]
    if owner <= 0 then return end
    if isBorder(state, id) then Collections.add(state.borders[owner], id)
    else Collections.remove(state.borders[owner], id) end
end
local function conquer(state: State, id: number, owner: number)
    local previous = state.owners[id]
    if previous == owner then return end
    -- PF044 Barracks (PremiumItems.conquered): only while one stands, before the counts change
    if previous > 0 and owner > 0 and state.premium and state.premium.conquerActive then state.premium.conquered(state, previous, owner, id) end
    if previous > 0 then
        Collections.remove(state.territories[previous], id)
        Collections.remove(state.borders[previous], id)
        state.counts[previous] -= 1
        -- PF044: who took a human's last tile (the Revive / Takeover killer)
        if state.counts[previous] == 0 and owner > 0 and state.players[previous].playerType == "Human" then
            state.eliminatedBy = state.eliminatedBy or {}; state.eliminatedBy[previous] = owner
        end
        state.lastTileChange[previous] = state.ticks
        state.tileChangeVersion[previous] += 1
    end
    state.owners[id], state.changedOwners[id] = owner, owner
    state.ownerEpoch = (state.ownerEpoch or 0) + 1 -- PF035: any owner change (Simulation.nearby's cache key)
    if owner > 0 then
        if state.falloutTiles[id] then
            state.falloutTiles[id] = nil; state.falloutCount -= 1; state.changedFalloutIds[id] = true
        end
        Collections.add(state.territories[owner], id) state.counts[owner] += 1
        state.lastTileChange[owner] = state.ticks
        state.tileChangeVersion[owner] += 1
    end
    updateBorder(state, id)
    -- Same N,S,W,E update order, without allocating an array for each capture.
    local width, x = state.map.width, (id - 1) % state.map.width
    if id > width then updateBorder(state, id - width) end
    if id <= width * (state.map.height - 1) then updateBorder(state, id + width) end
    if x > 0 then updateBorder(state, id - 1) end
    if x < width - 1 then updateBorder(state, id + 1) end
end

-- Pure fixture helper. Production uses conquer() to preserve reference set order.
function Simulation.rebuildTerritory(state: State)
    state.ownerEpoch = (state.ownerEpoch or 0) + 1 -- owners were written directly (fixtures): nearby recomputes
    state.playerExecutionRemoved={}
    state.territories, state.borders, state.counts = {}, {}, {}
    for owner = 1, #state.players do
        state.territories[owner], state.borders[owner], state.counts[owner] = Collections.set(), Collections.set(), 0
    end
    for id, owner in state.owners do
        if owner > 0 then Collections.add(state.territories[owner], id) state.counts[owner] += 1 end
    end
    for id, owner in state.owners do if owner > 0 then updateBorder(state, id) end end
    state.lastTileChange = table.create(#state.players, state.ticks)
    state.tileChangeVersion = table.create(#state.players, (state.tileChangeVersion and math.max(table.unpack(state.tileChangeVersion)) or 0) + 1)
    -- Fixtures may assign the grid directly instead of running spawn executions.
    state.executionOrder, state.playerOrder = {}, {}
    for owner = 1, #state.players do table.insert(state.playerOrder, owner) end
    for owner = 2, #state.players do table.insert(state.executionOrder, owner) end
    table.insert(state.executionOrder, 1)
end
function Simulation.capacity(state: any, owner: number, completedCityLevels: number?): number
    if not ownerValid(state, owner) then return 0 end
    if GameConfig.infiniteTroops(state,owner)then return 1000000000 end
    return Rules.capacity(state.counts[owner], state.players[owner].playerType, GameConfig.forState(state).Match.Difficulty,
        if completedCityLevels~=nil then completedCityLevels else Economy.completedLevels(state, owner))
end
-- PixelFront PF014 (Ashton): a human player keeps 10% of their CURRENT maximum
-- troops at home. Growth (10+T^.73/4)(1-T/C) peaks near 0.42C and collapses
-- below ~0.1C, so a full send would wreck regrowth. Nations, tribes and
-- infinite-troops games are exempt. Enforced at command time and again when an
-- execution pays out, so several sends queued in one tick cannot dig into it.
Simulation.TroopReserveShare = Config.Combat.TroopReserveShare -- PF014 (PF043: 0.20, was 0.10)
function Simulation.troopReserve(state: any, owner: number): number
    if not ownerValid(state, owner) or state.players[owner].playerType ~= "Human" or GameConfig.infiniteTroops(state, owner) then return 0 end
    -- OpenFront-parity fixtures set state.troopReserveShareOverride=0 to exercise source
    -- mechanics with the reserve off (the rule has its own cases); production never sets it.
    if state.troopReserveShareOverride ~= nil then return math.floor(Simulation.capacity(state, owner) * state.troopReserveShareOverride) end
    return Simulation.reserveOf(state.troops[owner], Simulation.capacity(state, owner))
end
-- The human reserve for `troops` held of `cap` max (shared with the client's estimates): TroopReserveShare of max troops,
-- PF043 never more than ReserveMaxOfTroops (half) of what you hold, so a fresh spawn's first sends aren't starved by the
-- 20%; at full troops a big push still keeps the whole 20% home.
function Simulation.reserveOf(troops: number, cap: number): number
    return math.max(0, math.min(math.floor(cap * Simulation.TroopReserveShare), math.floor(troops * Config.Combat.ReserveMaxOfTroops)))
end
function Simulation.sendableTroops(state: any, owner: number): number
    if not ownerValid(state, owner) then return 0 end
    return math.max(0, state.troops[owner] - Simulation.troopReserve(state, owner))
end
-- Requested send -> (amount actually sent, reserve info when the reserve changed it).
function Simulation.reserveClamp(state: any, owner: number, requested: number): (number, any?)
    local reserve = Simulation.troopReserve(state, owner)
    if reserve <= 0 then return requested, nil end
    local sendable = math.max(0, state.troops[owner] - reserve)
    if requested <= sendable then return requested, nil end
    return sendable, { kept = reserve, sent = math.floor(sendable), refused = sendable < 1 }
end
local function reserveMessage(reserve: any): string
    return "Keeping " .. tostring(reserve.kept) .. " troops to regrow."
end
local function populationGrowth(state: any,owner: number,completedCityLevels: number?): number
    if GameConfig.infiniteTroops(state,owner)then
        local troops,maximum=state.troops[owner],Simulation.capacity(state,owner)
        local increment=(10+Math.pow(troops,.73)/4)*(1-troops/maximum)
        return math.min(troops+increment,maximum)-troops
    end
    local config,levels=GameConfig.forState(state),if completedCityLevels~=nil then completedCityLevels else Economy.completedLevels(state,owner)
    local playerType=state.players[owner].playerType
    local growth=Rules.growth(state.counts[owner],state.troops[owner],playerType,config.Match.Difficulty,levels)
    -- the tutorial's human troop boost (Economy.HumanTroopMultiplier, ×2): more regrowth, never past the cap, decay unchanged
    local boost=if playerType=="Human" then config.Economy.HumanTroopMultiplier or 1 else 1
    if boost~=1 and growth>0 then
        growth=math.min(growth*boost,Rules.capacity(state.counts[owner],playerType,config.Match.Difficulty,levels)-state.troops[owner])
    end
    -- PF043 comeback regrowth (Config.Combat.ComebackGrowth/ComebackBelow): a human low on troops after a big push regrows
    -- faster, real matches only (the reference fixtures have no gameConfig); never past the cap, decay unchanged
    if playerType=="Human" and state.gameConfig~=nil and growth>0 then
        local maximum=Rules.capacity(state.counts[owner],playerType,config.Match.Difficulty,levels)
        if state.troops[owner]<maximum*config.Combat.ComebackBelow then
            growth=math.min(growth*config.Combat.ComebackGrowth,maximum-state.troops[owner])
        end
    end
    -- PF044 Barracks (PremiumItems.growth; only while one stands): its momentum bonus, never past the cap, decay unchanged
    if growth>0 and state.premium and state.premium.barracksActive then
        local bonus=state.premium.growth(state,owner)
        if bonus>0 then
            local maximum=Rules.capacity(state.counts[owner],playerType,config.Match.Difficulty,levels)
            growth=math.max(growth,math.min(growth*(1+bonus),maximum-state.troops[owner]))
        end
    end
    return growth
end
function Simulation.troopRate(state: any, owner: number, completedCityLevels: number?): number
    if not ownerValid(state, owner) or state.counts[owner] == 0 then return 0 end
    return populationGrowth(state,owner,completedCityLevels) / GameConfig.forState(state).Match.StepSeconds
end
function Simulation.goldRate(state: any, owner: number): number
    return if ownerValid(state, owner) and state.counts[owner] > 0 then Economy.goldPerTick(state, owner) / GameConfig.forState(state).Match.StepSeconds else 0
end
Simulation.cityCost = Economy.cityCost
Simulation.canBuildCity = Economy.canBuildCity
Simulation.queryBuildableCity = Economy.queryBuildableCity
function Simulation.buildCity(state: State, owner: number, tileId: number): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not validId(state, tileId)
        or not Economy.canBuildCity(state, owner, tileId) then return false, "A City cannot be built here." end
    table.insert(state.pendingExecutions, { kind = "BuildCity", owner = owner, tileId = tileId })
    return true, "City construction ordered."
end
function Simulation.upgradeCity(state: State, owner: number, unitId: number, amount: number?): (boolean, string)
    local count = if amount == nil then 1 else amount
    if state.phase == "Choosing" or not finite(count) or count % 1 ~= 0 or count < 1 or count > GameConfig.forState(state).City.MaxUpgradeAmount
        or not finite(unitId) or unitId % 1 ~= 0 or not Economy.canUpgradeCity(state, owner, unitId) then return false, "This City cannot be upgraded." end
    table.insert(state.pendingExecutions, { kind = "UpgradeCity", owner = owner, unitId = unitId, amount = count })
    return true, "City upgrade ordered."
end
function Simulation.deleteCity(state: State, owner: number, unitId: number): (boolean, string)
    if not finite(unitId) or unitId % 1 ~= 0 or not Economy.canDeleteCity(state, owner, unitId) then return false, "This City cannot be deleted yet." end
    table.insert(state.pendingExecutions, { kind = "DeleteCity", owner = owner, unitId = unitId })
    return true, "City deletion ordered."
end
Simulation.portCost = Ports.portCost
Simulation.canBuildPort = Ports.canBuildPort
Simulation.queryBuildablePort = Ports.queryBuildablePort
function Simulation.buildPort(state: State, owner: number, tileId: number): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not validId(state, tileId)
        or not Ports.canBuildPort(state, owner, tileId) then return false, "A Port cannot be built here." end
    table.insert(state.pendingExecutions, { kind = "BuildPort", owner = owner, tileId = tileId })
    return true, "Port construction ordered."
end
function Simulation.upgradePort(state: State, owner: number, unitId: number, amount: number?): (boolean, string)
    local count = if amount == nil then 1 else amount
    if state.phase == "Choosing" or not finite(count) or count % 1 ~= 0 or count < 1 or count > GameConfig.forState(state).City.MaxUpgradeAmount
        or not finite(unitId) or unitId % 1 ~= 0 or not Ports.canUpgradePort(state, owner, unitId) then return false, "This Port cannot be upgraded." end
    table.insert(state.pendingExecutions, { kind = "UpgradePort", owner = owner, unitId = unitId, amount = count })
    return true, "Port upgrade ordered."
end
function Simulation.deletePort(state: State, owner: number, unitId: number): (boolean, string)
    if not finite(unitId) or unitId % 1 ~= 0 or not Ports.canDeletePort(state, owner, unitId) then return false, "This Port cannot be deleted yet." end
    table.insert(state.pendingExecutions, { kind = "DeletePort", owner = owner, unitId = unitId })
    return true, "Port deletion ordered."
end
function Simulation.ownedStructures(state: any, owner: number): { any }
    local units = Economy.ownedCities(state, owner)
    for _, port in Ports.ownedPorts(state, owner) do table.insert(units, port) end
    for _, unit in Structures.ownedFactories(state, owner) do table.insert(units, unit) end
    for _, unit in Structures.ownedDefensePosts(state, owner) do table.insert(units, unit) end
    for _, kind in {"MissileSilo", "SAMLauncher"} do
        for _, unit in Weapons.owned(state, kind, owner) do table.insert(units, unit) end
    end
    table.sort(units, function(a, b)
        return (state.unitAcquisitionOrder[a.id] or a.id) < (state.unitAcquisitionOrder[b.id] or b.id)
    end)
    return units
end
function Simulation.recordUnitDeath(state: any, unit: any, sourceType: string?)
    table.insert(state.deadUnitEvents, {eventId=state.nextDeadUnitEventId, id=unit.id,
        owner=unit.owner, unitType=sourceType or unit.unitType or "Transport", tileId=unit.tileId,
        reachedTarget=unit.reachedTarget==true, tick=state.ticks})
    state.nextDeadUnitEventId+=1
end
Simulation.factoryCost = Structures.factoryCost
Simulation.defensePostCost = Structures.defensePostCost
Simulation.queryBuildableFactory = Structures.queryBuildableFactory
Simulation.queryBuildableDefensePost = Structures.queryBuildableDefensePost
function Simulation.buildStructure(state: State, owner: number, unitType: string, tile: number): (boolean, string)
    local factory = unitType == "Factory"
    if (not factory and unitType ~= "Defense Post") or state.phase == "Choosing" or not ownerValid(state, owner)
        or not validId(state, tile) then return false, "Invalid structure order." end
    local spawn = if factory then Structures.canBuildFactory(state, owner, tile) else Structures.canBuildDefensePost(state, owner, tile)
    if not spawn then return false, "This structure cannot be built here." end
    table.insert(state.pendingExecutions, {kind = if factory then "BuildFactory" else "BuildDefensePost", owner = owner, tileId = tile})
    return true, unitType .. " construction ordered."
end
function Simulation.upgradeFactory(state: State, owner: number, id: number, amount: number?): (boolean, string)
    local count = if amount == nil then 1 else amount
    if state.phase == "Choosing" or not finite(count) or count % 1 ~= 0 or count < 1 or count > GameConfig.forState(state).City.MaxUpgradeAmount
        or not finite(id) or id % 1 ~= 0 or not Structures.canUpgradeFactory(state, owner, id) then return false, "This Factory cannot be upgraded." end
    table.insert(state.pendingExecutions, {kind = "UpgradeFactory", owner = owner, unitId = id, amount = count})
    return true, "Factory upgrade ordered."
end
function Simulation.deleteStructure(state: State, owner: number, id: number): (boolean, string)
    if not finite(id) or id % 1 ~= 0 then return false, "Invalid structure deletion." end
    local factory = Structures.factory(state, id)
    local valid = if factory then Structures.canDeleteFactory(state, owner, id) else Structures.canDeleteDefensePost(state, owner, id)
    if not valid then return false, "This structure cannot be deleted yet." end
    table.insert(state.pendingExecutions, {kind = if factory then "DeleteFactory" else "DeleteDefensePost", owner = owner, unitId = id})
    return true, "Structure deletion ordered."
end
local weaponExecutions = {
    BuildMissileSilo=true, UpgradeMissileSilo=true, DeleteMissileSilo=true, MissileSiloTick=true,
    BuildSAMLauncher=true, UpgradeSAMLauncher=true, DeleteSAMLauncher=true, SAMLauncherTick=true, SAMMissile=true,
}
function Simulation.buildWeapon(state: State, owner: number, unitType: string, tile: number): (boolean, string)
    local kind = if unitType == "Missile Silo" then "MissileSilo" elseif unitType == "SAM Launcher" then "SAMLauncher" else nil
    if not kind or state.phase == "Choosing" or not ownerValid(state,owner) or not validId(state,tile)
        or not Weapons.canBuild(state,kind,owner,tile) then return false,"This structure cannot be built here." end
    table.insert(state.pendingExecutions,{kind="Build"..kind,owner=owner,tileId=tile})
    return true,unitType.." construction ordered."
end
function Simulation.upgradeWeapon(state: State, owner: number, id: number, amount: number?): (boolean, string)
    local count=if amount==nil then 1 else amount
    local kind=if Weapons.missileSilo(state,id) then "MissileSilo" elseif Weapons.samLauncher(state,id) then "SAMLauncher" else nil
    if not kind or state.phase=="Choosing" or not finite(count) or count%1~=0 or count<1 or count>GameConfig.forState(state).City.MaxUpgradeAmount
        or not finite(id) or id%1~=0 or not Weapons.canUpgrade(state,kind,owner,id) then return false,"This structure cannot be upgraded." end
    table.insert(state.pendingExecutions,{kind="Upgrade"..kind,owner=owner,unitId=id,amount=count})
    return true,"Structure upgrade ordered."
end
function Simulation.deleteWeapon(state: State, owner: number, id: number): (boolean, string)
    local kind=if Weapons.missileSilo(state,id) then "MissileSilo" elseif Weapons.samLauncher(state,id) then "SAMLauncher" else nil
    if not kind or not finite(id) or id%1~=0 or not Weapons.canDelete(state,kind,owner,id) then return false,"This structure cannot be deleted yet." end
    table.insert(state.pendingExecutions,{kind="Delete"..kind,owner=owner,unitId=id})
    return true,"Structure deletion ordered."
end
function Simulation.launchNuke(state: State, owner: number, unitType: string, tile: number, directionUp: boolean?, amount: number?): (boolean, string)
    local count=if amount==nil then 1 else amount
    if state.phase=="Choosing" or not ownerValid(state,owner) or not validId(state,tile)
        or (directionUp~=nil and type(directionUp)~="boolean")
        or not finite(count) or count%1~=0 or count<1 or count>GameConfig.forState(state).City.MaxUpgradeAmount
        or (unitType~="Atom Bomb" and unitType~="Hydrogen Bomb" and unitType~="MIRV") then return false,"Invalid missile order." end
    if Nukes.canBuild(state,owner,unitType,tile)==false then return false,"Cannot launch "..unitType end
    table.insert(state.pendingExecutions,{kind="BuildNuke",owner=owner,nukeType=unitType,tileId=tile,directionUp=directionUp,amount=count})
    return true,""
end
function Simulation.recordWeaponMessage(state: any, event: any)
    local message=table.clone(event); message.eventId=state.nextWeaponMessageId;message.tick=message.tick or state.ticks
    state.nextWeaponMessageId+=1; table.insert(state.weaponMessages,message)
end
function Simulation.acknowledgeWeaponMessages(state: any, cursor: number)
    local kept={}; local minimum=math.max(0,cursor-64)
    for _,event in state.weaponMessages do if event.eventId>minimum then table.insert(kept,event) end end
    state.weaponMessages=kept
end
function Simulation.weaponUnits(state: any): {any}
    local units={}
    for _,pair in {{state.cities,"City"},{state.ports,"Port"},{state.factories,"Factory"},{state.defensePosts,"Defense Post"},
        {state.missileSilos,"Missile Silo"},{state.samLaunchers,"SAM Launcher"},{state.ships,"Transport"},
        {state.tradeShips,"Trade Ship"},{state.warships,"Warship"},{state.shells,"Shell"},{state.trains,"Train"},
        {state.nukes,"Nuke"},{state.samMissiles,"SAMMissile"}} do
        for _,unit in pair[1] or {} do
            if unit.active~=false then unit.unitType=unit.unitType or pair[2]; table.insert(units,unit) end
        end
    end
    local order={};for index,owner in state.playerOrder do order[owner]=index end
    table.sort(units,function(a,b)
        if a.owner~=b.owner then return (order[a.owner] or a.owner)<(order[b.owner] or b.owner) end
        return (state.unitAcquisitionOrder[a.id] or a.id)<(state.unitAcquisitionOrder[b.id] or b.id)
    end)
    return units
end

Simulation.warshipCost = Warships.cost
Simulation.canBuildWarship = Warships.canBuildWarship
Simulation.queryBuildableWarship = Warships.queryBuildableWarship
function Simulation.buildWarship(state: State, owner: number, tileId: number): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not validId(state, tileId)
        or not Warships.canBuildWarship(state, owner, tileId) then return false, "A Warship cannot be launched here." end
    table.insert(state.pendingExecutions, {kind = "BuildWarship", owner = owner, tileId = tileId})
    return true, "Warship ordered."
end
function Simulation.moveWarships(state: State, owner: number, unitIds: any, position: number): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not validId(state, position)
        or type(unitIds) ~= "table" or #unitIds == 0 then return false, "Invalid Warship move." end
    local ids = {}
    for _, id in unitIds do
        if not finite(id) or id % 1 ~= 0 then return false, "Invalid Warship selection." end
        table.insert(ids, id)
    end
    table.insert(state.pendingExecutions, {kind = "MoveWarship", owner = owner, unitIds = ids, position = position})
    return true, "Warship patrol changed."
end
function Simulation.addBonusGold(state: any, owner: number, gold: number, tile: number)
    Economy.addGold(state, owner, gold)
    -- Source PlayerImpl.addGold checks zero-based tile truthiness before emitting.
    if tile == 1 then return end
    table.insert(state.bonusEvents, { id = state.nextBonusEventId, owner = owner,
        playerId = state.players[owner].id, tileId = tile, gold = gold, tick = state.ticks })
    state.nextBonusEventId += 1
end
local function sharesBorder(state: any, owner: number, targetOwner: number): boolean
    if state.borders then
        for _, id in state.borders[owner].values do
            if id ~= 0 and adjacent(state, id, targetOwner) then return true end
        end
    else
        for id, tileOwner in state.owners do
            if tileOwner == owner and adjacent(state, id, targetOwner) then return true end
        end
    end
    return false
end

-- PF043 tribe mercy (Config.Mercy): for Mercy.Seconds of Playing, a tribe (Bot) takes no wilderness within Mercy.Radius of
-- a human's spawn and doesn't attack a human holding fewer than Mercy.ShieldTiles. Real matches only (a lobby gameConfig);
-- the reference fixtures, which have none, are untouched. Centers = flat x,y pairs of the humans' spawns, rebuilt each tick.
local mercyCache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function mercyCenters(state: any): { number }?
    if not state.gameConfig or state.phase ~= "Playing" then return nil end
    local mercy = GameConfig.forState(state).Mercy
    if not mercy or state.elapsed >= mercy.Seconds then return nil end
    local cache = mercyCache[state]
    if not cache or cache.tick ~= state.ticks then
        local centers, width = {}, state.map.width
        for owner, player in state.players do
            local tile = state.spawnTiles[owner]
            if player.playerType == "Human" and tile then table.insert(centers, (tile - 1) % width); table.insert(centers, (tile - 1) // width) end
        end
        cache = { tick = state.ticks, centers = centers }
        mercyCache[state] = cache
    end
    return cache.centers
end
-- Who the window holds back: tribes only where the match sets tribeMercy (the tutorial: Ashton 2026-10-25 "only add that lil
-- tribe shield in the tutorial"); nations where it sets nationMercy (the tutorial, the Solo Easy/Medium peace).
local function mercyActor(state: any, owner: number): boolean
    local kind = state.players[owner] and state.players[owner].playerType
    local mercy = state.gameConfig ~= nil and GameConfig.forState(state).Mercy or nil
    if not mercy then return false end
    return (kind == "Bot" and mercy.Tribes == true) or (kind == "Nation" and mercy.Nations == true)
end
-- PF044 Revive shield (Simulation.revive): while it lasts nobody attacks the revived player, and tribes and nations take no
-- wilderness within Config.Revive.ZoneRadius of its centre. state.revive[owner] = {untilTick, x, y, ended?}.
function Simulation.reviveShielded(state: any, owner: number): boolean
    local entry = state.revive and state.revive[owner]
    return entry ~= nil and entry.ended == nil and state.ticks < entry.untilTick
end
function Simulation.mercyTile(state: any, owner: number, tile: number): boolean
    if state.revive then
        local kind = state.players[owner] and state.players[owner].playerType
        if kind == "Bot" or kind == "Nation" then
            local x, y, r = (tile - 1) % state.map.width, (tile - 1) // state.map.width, Config.Revive.ZoneRadius
            for who, entry in state.revive do
                if who ~= owner and Simulation.reviveShielded(state, who) and (x - entry.x) ^ 2 + (y - entry.y) ^ 2 <= r * r then return true end
            end
        end
    end
    if not mercyActor(state, owner) then return false end
    local centers = mercyCenters(state)
    if not centers or #centers == 0 then return false end
    local radius = GameConfig.forState(state).Mercy.Radius
    local x, y = (tile - 1) % state.map.width, (tile - 1) // state.map.width
    for index = 1, #centers, 2 do
        local dx, dy = x - centers[index], y - centers[index + 1]
        if dx * dx + dy * dy <= radius * radius then return true end
    end
    return false
end
function Simulation.mercyShield(state: any, owner: number, other: number): boolean
    if state.revive and owner ~= other and Simulation.reviveShielded(state, other) then return true end -- PF044 Revive shield
    -- PF044 Play Solo modes: with NationPeace a nation holds off a human of any size for the whole window (SoloDifficulty)
    return mercyActor(state, owner) and state.players[other] ~= nil and state.players[other].playerType == "Human"
        and mercyCenters(state) ~= nil and (state.counts[other] < GameConfig.forState(state).Mercy.ShieldTiles
            or state.players[owner].playerType == "Nation" and GameConfig.forState(state).Mercy.NationPeace == true)
end
-- The tribe borders wilderness, but all of it is inside a mercy zone (so its expansion would find nothing to take).
function Simulation.mercyBlocksWild(state: any, owner: number): boolean
    if not mercyActor(state, owner) or not mercyCenters(state) then return false end
    local scratch, found = {}, false
    for _, tile in state.borders[owner].values do
        if tile ~= 0 then
            for _, neighbor in neighbors(state, tile, scratch) do
                if state.owners[neighbor] == 0 and passable(state, neighbor) and not state.falloutTiles[neighbor] then
                    if not Simulation.mercyTile(state, owner, neighbor) then return false end
                    found = true
                end
            end
        end
    end
    return found
end

-- PlayerImpl.canAttack: clicked position establishes eligibility, not direction.
function Simulation.canAttackPlayer(state: any, owner: number, other: number, treatAFKFriendly: boolean?): boolean
    if owner==other or not state.players[other] or Diplomacy.friendly(state,owner,other,treatAFKFriendly) then return false end
    if Simulation.mercyShield(state,owner,other) then return false end -- PF043
    if state.players[owner].playerType~="Human" then return true end
    local immunity=if state.spawnImmunityActive then state.spawnImmunityActive()
        else state.phase=="Choosing" or state.ticks-(state.startTick or 0)<GameConfig.forState(state).Match.SpawnImmunityTicks
    return isBot(state,other) or not immunity
end
function Simulation.canAttack(state: any, owner: number, id: number): boolean
    if not ownerValid(state, owner) or state.phase == "Choosing" or not validId(state, id) or state.counts[owner] == 0 then return false end
    if not passable(state, id) or state.owners[id] == owner then return false end
    if state.owners[id] > 0 then return Simulation.canAttackPlayer(state,owner,state.owners[id]) and sharesBorder(state, owner, state.owners[id]) end
    local stack, seen, scratch = { id }, { [id] = true }, {}
    while #stack > 0 do
        local tile = table.remove(stack) :: number
        for _, neighbor in neighbors(state, tile, scratch) do
            if state.owners[neighbor] == owner then return true end
            if not seen[neighbor] and state.owners[neighbor] == 0 and passable(state, neighbor)
                and distance(state, id, neighbor) <= GameConfig.forState(state).Combat.NeutralSearchRadius then
                seen[neighbor] = true table.insert(stack, neighbor)
            end
        end
    end
    return false
end

-- Offset Euclidean radius, geometric traversal before filtering ownership/land.
function Simulation.spawnArea(state: any, id: number, requireAll: boolean?): { number }?
    if not validId(state, id) then return nil end
    local width = state.map.width
    local centerX, centerY = (id - 1) % width - 0.5, math.floor((id - 1) / width) - 0.5
    local stack, seen, ordered, scratch = { id }, { [id] = true }, { id }, {}
    while #stack > 0 do
        local current = table.remove(stack) :: number
        for _, neighbor in neighbors(state, current, scratch) do
            local dx, dy = (neighbor - 1) % width - centerX, math.floor((neighbor - 1) / width) - centerY
            if not seen[neighbor] and dx * dx + dy * dy <= GameConfig.forState(state).Match.SpawnRadius ^ 2 then
                seen[neighbor] = true table.insert(stack, neighbor) table.insert(ordered, neighbor)
            end
        end
    end
    local result = {}
    for _, tile in ordered do
        if state.owners[tile] == 0 and passable(state, tile) then table.insert(result, tile)
        elseif requireAll then return nil end
    end
    return result
end
local function teamSpawnArea(state: State,owner: number): any?
    local areas=state.map.manifest and state.map.manifest.teamGameSpawnAreas
    local area=state.players[owner].team and Teams.spawnArea(state.players[owner].team,state.teams or {},areas)
    if area and state.map.mapSize=="Compact"then area={x=math.floor(area.x/2),y=math.floor(area.y/2),width=math.floor(area.width/2),height=math.floor(area.height/2)}end
    return area
end
local function initializePlayer(state: State,owner: number,tick: number)
    state.playerInitTicks[owner]=tick
    state.lastClusterCalc[owner]=tick+Random.hash(state.players[owner].id)%20
end
local function recordSpawn(state: State,owner: number)
    if not table.find(state.executionOrder,owner)then table.insert(state.executionOrder,owner)end
    if state.phase~="Choosing"then initializePlayer(state,owner,state.ticks)end
end
local function spawnBot(state: State, owner: number)
    local randomSpawn=state.gameConfig and state.gameConfig.randomSpawn==true
    if randomSpawn and state.spawnTiles[owner]then return true end
    local fixed=if randomSpawn then nil else state.players[owner].spawnTile
    if fixed then
        local area=Simulation.spawnArea(state,fixed,false)
        if area and #area>0 then for _,tile in area do conquer(state,tile,owner)end;state.spawnTiles[owner]=fixed;return true end
        return false
    end
    local random = Random.new(Random.hash(state.players[owner].id) + Random.hash(state.gameId or tostring(state.seed)))
    if owner==1 then state.humanSpawnRandom=random end
    local area=teamSpawnArea(state,owner)
    for attempt = 1, GameConfig.forState(state).Match.MaxSpawnTries do
        local x = Random.int(random, if area then area.x else 0,if area then area.x+area.width else state.map.width)
        local y = Random.int(random, if area then area.y else 0,if area then area.y+area.height else state.map.height)
        local id = y * state.map.width + x + 1
        if not passable(state, id) or state.owners[id] ~= 0 or isBorder(state, id) then continue end
        if state.players[owner].playerType == "Human" and not Simulation.spawnAllowed(state, id) then continue end -- the tutorial's mainland
        local tooClose = false
        if attempt <= GameConfig.forState(state).Match.RelaxSpawnDistanceAt then
            for otherOwner, other in state.spawnTiles do
                local ox,oy=(other-1)%state.map.width,math.floor((other-1)/state.map.width)
                if otherOwner~=owner and math.abs(x-ox)+math.abs(y-oy)<GameConfig.forState(state).Match.MinSpawnDistance then tooClose = true break end
            end
            -- Production spacing also reserves pending nation homes. Keep the
            -- source distance/relaxation; tribes remain randomly placed.
            if not tooClose and state.matchBalance and state.bots[owner] then
                for _, pending in state.spawnPhasePending do
                    if not pending.tile then continue end
                    local nx, ny = (pending.tile - 1) % state.map.width, math.floor((pending.tile - 1) / state.map.width)
                    if math.abs(x - nx) + math.abs(y - ny) < GameConfig.forState(state).Match.MinSpawnDistance then tooClose = true break end
                end
            end
        end
        if tooClose then continue end
        local area = Simulation.spawnArea(state, id, true)
        if not area or #area == 0 then continue end
        for _, tile in area do conquer(state, tile, owner) end
        state.spawnTiles[owner] = id
        return true
    end
    return false
end
-- PF044 Revive (Config.Revive; the server owns the offer, payment and timing). eligible: the 4 offer rules for an eliminated
-- human (solo drops rule 2). Returns (ok, reason?). reason: "alive" | "used" | "phase" | "nation" | "time" | "leader" | "few".
function Simulation.reviveEligible(state: any, owner: number, solo: boolean?): (boolean, string?)
    local R = Config.Revive
    if not state.players[owner] or state.players[owner].playerType ~= "Human" then return false, "phase" end
    if state.phase ~= "Playing" then return false, "phase" end
    if (state.counts[owner] or 0) > 0 then return false, "alive" end
    if state.revive and state.revive[owner] then return false, "used" end
    local nation, most, leader, alive = nil, 0, 0, 0
    for other, player in state.players do
        local count = state.counts[other] or 0
        if count > 0 and (player.playerType == "Human" or player.playerType == "Nation") then
            alive += 1; leader = math.max(leader, count)
            if player.playerType == "Nation" and count > most then nation, most = other, count end
        end
    end
    -- rule 1: the pocket (at most a radius-R circle) leaves the nation >= NationKeep
    if not nation or most - math.ceil(math.pi * R.Radius * R.Radius) < R.NationKeep then return false, "nation" end
    if not solo and state.elapsed >= R.BeforeSeconds then return false, "time" end
    if leader >= R.LeaderBelow * state.map.landCount then return false, "leader" end
    if alive < R.MinAlive then return false, "few" end
    return true, nil
end
-- revive: rise inside the largest nation (never on human land). A Radius circle of AI land (wilderness, tribe, nation) with no
-- human land within Radius + HumanClear, coast or map edge first, then as far as possible from `killer`; TroopShare of the new
-- max troops, +Gold, a ShieldSeconds shield. Deterministic (seeded from the player and tick). Returns (ok, {tile, tiles}).
function Simulation.revive(state: any, owner: number, killer: number?, solo: boolean?): (boolean, any)
    local ok, reason = Simulation.reviveEligible(state, owner, solo)
    if not ok then return false, { reason = reason } end
    local R = Config.Revive
    local width, height, radius = state.map.width, state.map.height, R.Radius
    local nation, most = nil, 0
    for other, player in state.players do
        if player.playerType == "Nation" and (state.counts[other] or 0) > most then nation, most = other, state.counts[other] end
    end
    local kx, ky = nil, nil
    if killer and killer > 0 and state.spawnTiles[killer] then kx, ky = (state.spawnTiles[killer] - 1) % width, (state.spawnTiles[killer] - 1) // width end
    local function soft(w: number): boolean
        if w == 0 then return true end
        if w < 0 or w == owner then return false end
        local kind = state.players[w].playerType
        return kind == "Bot" or kind == "Nation"
    end
    local list = {}
    for _, t in state.territories[nation].values do if t ~= 0 then table.insert(list, t) end end
    local random = Random.new(Random.hash(tostring(state.players[owner].id)) + state.ticks)
    local best, bestScore = nil, -math.huge
    local clear = radius + R.HumanClear
    for _ = 1, 400 do
        local id = list[Random.int(random, 1, #list + 1)]
        local x, y = (id - 1) % width, (id - 1) // width
        local hard, coast = false, false
        for dy = -clear, clear do
            for dx = -clear, clear do
                local d2, nx, ny = dx * dx + dy * dy, x + dx, y + dy
                if d2 > clear * clear then continue end
                if nx < 0 or ny < 0 or nx >= width or ny >= height then if d2 <= radius * radius then coast = true end; continue end
                local t = ny * width + nx + 1
                if not state.map.land[t] then if d2 <= radius * radius then coast = true end; continue end
                local w = state.owners[t]
                if w > 0 and w ~= owner and state.players[w].playerType == "Human" then hard = true; break end
            end
            if hard then break end
        end
        if hard then continue end
        local far = if kx then math.sqrt((x - kx) ^ 2 + (y - ky) ^ 2) else 0
        local score = (if coast then 100000 else 0) + far
        if score > bestScore then best, bestScore = id, score end
    end
    if not best then return false, { reason = "room" } end
    local bx, by, home = (best - 1) % width, (best - 1) // width, {}
    for dy = -radius, radius do
        for dx = -radius, radius do
            local nx, ny = bx + dx, by + dy
            if dx * dx + dy * dy > radius * radius or nx < 0 or ny < 0 or nx >= width or ny >= height then continue end
            local t = ny * width + nx + 1
            if passable(state, t) and soft(state.owners[t]) then table.insert(home, t) end
        end
    end
    if #home < 20 then return false, { reason = "room" } end
    if state.counts[nation] - #home < R.NationKeep then return false, { reason = "nation" } end
    for _, t in home do conquer(state, t, owner) end
    state.playerExecutionRemoved[owner] = nil; state.spawnTiles[owner] = best; recordSpawn(state, owner)
    state.troops[owner] = math.floor(R.TroopShare * Simulation.capacity(state, owner))
    state.gold[owner] += R.Gold
    state.revive = state.revive or {}
    state.revive[owner] = { untilTick = state.ticks + R.ShieldSeconds * 10, x = bx, y = by }
    return true, { tile = best, tiles = #home, coast = bestScore >= 100000 }
end
-- PF044 Takeover (Config.Revive): killed by a nation, play on as a nation. eligible: the shared once-per-match use; with
-- other humans (not solo) rules 2-4 of Revive. Returns (ok, reason?).
function Simulation.takeoverEligible(state: any, owner: number, solo: boolean?): (boolean, string?)
    local R = Config.Revive
    if not state.players[owner] or state.players[owner].playerType ~= "Human" then return false, "phase" end
    if state.phase ~= "Playing" then return false, "phase" end
    if (state.counts[owner] or 0) > 0 then return false, "alive" end
    if state.revive and state.revive[owner] then return false, "used" end
    if solo then return true, nil end
    local leader, alive = 0, 0
    for other, player in state.players do
        local count = state.counts[other] or 0
        if count > 0 and (player.playerType == "Human" or player.playerType == "Nation") then alive += 1; leader = math.max(leader, count) end
    end
    if state.elapsed >= R.BeforeSeconds then return false, "time" end
    if leader >= R.LeaderBelow * state.map.landCount then return false, "leader" end
    if alive < R.MinAlive then return false, "few" end
    return true, nil
end
-- the nation a Takeover gives `owner` (killed by `killer`), or nil. Solo: the killer. Otherwise the killer when it's outside
-- the top TakeoverTop (humans + nations, by land) and at most the median nation's land, else the nation nearest the old
-- capital among the middle half (by land) of the nations that fit with >= NationKeep tiles. Returns (nation?, "killer" | "mid").
function Simulation.takeoverTarget(state: any, owner: number, killer: number?, solo: boolean?): (number?, string?)
    local function nation(o: number?): boolean
        return o ~= nil and o > 0 and state.players[o] ~= nil and state.players[o].playerType == "Nation" and (state.counts[o] or 0) > 0
    end
    if not nation(killer) then return nil, nil end
    if solo then return killer, "killer" end
    local R = Config.Revive
    local ranked, sizes = {}, {}
    for o, player in state.players do
        if (state.counts[o] or 0) > 0 and (player.playerType == "Human" or player.playerType == "Nation") then
            table.insert(ranked, o)
            if player.playerType == "Nation" then table.insert(sizes, state.counts[o]) end
        end
    end
    table.sort(ranked, function(a, b) return state.counts[a] > state.counts[b] or state.counts[a] == state.counts[b] and a < b end)
    table.sort(sizes)
    local top, median = {}, sizes[(#sizes + 1) // 2] or 0
    for i = 1, math.min(R.TakeoverTop, #ranked) do top[ranked[i]] = true end
    local function fits(o: number): boolean return not top[o] and state.counts[o] <= median end
    if fits(killer :: number) then return killer, "killer" end
    local mids = {}
    for _, o in ranked do if nation(o) and fits(o) and state.counts[o] >= R.NationKeep then table.insert(mids, o) end end
    local home, width = state.spawnTiles[owner], state.map.width
    if not home or #mids == 0 then return nil, nil end
    local hx, hy = (home - 1) % width, (home - 1) // width
    local best, target = math.huge, nil
    for i = math.floor(#mids * 0.25) + 1, math.max(1, math.ceil(#mids * 0.75)) do
        local o = mids[i]
        local at = state.spawnTiles[o]
        if at then
            local d = ((at - 1) % width - hx) ^ 2 + ((at - 1) // width - hy) ^ 2
            if d < best then best, target = d, o end
        end
    end
    return target, if target then "mid" else nil
end
-- takeOver: `owner` becomes `nation`: every tile through conquer(), its buildings (defense posts too), its whole army (home,
-- attacks in flight, boats at sea), gold, and the Revive shield (ShieldSeconds, centred on the nation's capital). Returns (ok, {tile, tiles, troops}).
function Simulation.takeOver(state: any, owner: number, nation: number, solo: boolean?): (boolean, any)
    local ok, reason = Simulation.takeoverEligible(state, owner, solo)
    if not ok then return false, { reason = reason } end
    if not state.players[nation] or state.players[nation].playerType ~= "Nation" or (state.counts[nation] or 0) <= 0 then
        return false, { reason = "gone" }
    end
    local capital = state.spawnTiles[nation]
    if not capital or state.owners[capital] ~= nation then
        capital = nil
        for _, t in state.territories[nation].values do if t ~= 0 then capital = t; break end end
    end
    -- defense posts are destroyed on capture: hand them over first
    for _, value in state.defensePosts or {} do
        if value.owner == nation and value.active ~= false then
            local orders = state.defensePostOrders
            if orders then
                local index = table.find(orders[nation] or {}, value.id)
                if index then table.remove(orders[nation], index) end
                orders[owner] = orders[owner] or {}; table.insert(orders[owner], value.id)
            end
            value.owner = owner
        end
    end
    -- its land attacks in flight come home first (an ownerless attack would lose them); its boats at sea and warships
    -- (with their executions) are yours (a dead nation's are deleted)
    for _, attack in state.attacks do
        if attack.active and attack.owner == nation then state.troops[nation] += math.floor(attack.budget); attack.active = false end
    end
    for _, execution in state.executions do
        if execution.owner == nation and (execution.kind == "TransportShip" or execution.kind == "BoatRetreat" or execution.kind == "Warship") then
            execution.owner = owner
            if execution.originalOwner == nation then execution.originalOwner = owner end
        end
    end
    for _, list in { state.ships or {}, state.warships or {} } do
        for _, unit in list do if unit.owner == nation and unit.active ~= false then unit.owner = owner end end
    end
    local tiles = {}
    for _, t in state.territories[nation].values do if t ~= 0 then table.insert(tiles, t) end end
    for _, t in tiles do conquer(state, t, owner) end
    Structures.captureOwned(state, nation, Simulation.ownedStructures(state, nation)) -- cities, ports, factories, silos, SAMs
    state.playerExecutionRemoved[owner] = nil; state.spawnTiles[owner] = capital; recordSpawn(state, owner)
    state.troops[owner] = math.floor(state.troops[nation]); state.troops[nation] = 0 -- the whole army (over your max, it decays as usual)
    state.gold[owner] += state.gold[nation]; state.gold[nation] = 0
    local width = state.map.width
    state.revive = state.revive or {}
    state.revive[owner] = { untilTick = state.ticks + Config.Revive.ShieldSeconds * 10, x = (capital - 1) % width, y = (capital - 1) // width, takeover = nation }
    return true, { tile = capital, tiles = #tiles, troops = state.troops[owner] }
end
-- Studio test helper (MatchService Debug StudioEliminate, Studio only): every tile of `owner` goes to `to` through conquer()
function Simulation.studioEliminate(state: any, owner: number, to: number): number
    local tiles = {}
    for _, t in state.territories[owner].values do if t ~= 0 then table.insert(tiles, t) end end
    for _, t in tiles do conquer(state, t, to) end
    return #tiles
end
-- the shield ends at once when its owner attacks (or boats at) a human or nation
function Simulation.reviveAttacked(state: any, owner: number, target: number)
    local entry = state.revive[owner]
    local kind = state.players[target] and state.players[target].playerType
    if entry and entry.ended == nil and state.ticks < entry.untilTick and (kind == "Human" or kind == "Nation") then entry.ended = "attack" end
end
local function nationSpawnCandidate(state: State, owner: number): number?
    local cell = state.players[owner].spawnCell
    if not cell then return nil end
    local random = state.nations[owner].random
    for _ = 1, 50 do
        local x, y = Random.int(random, cell.x - 25, cell.x + 25), Random.int(random, cell.y - 25, cell.y + 25)
        if x < 0 or x >= state.map.width or y < 0 or y >= state.map.height then continue end
        local tile = y * state.map.width + x + 1
        if not passable(state, tile) or state.owners[tile] ~= 0 then continue end
        if magnitude(state, tile) >= 20 and Random.int(random, 0, 2) == 0 then continue end
        return tile
    end
    return nil
end
local function queueNationSpawn(state: State,owner: number)
    local cell=state.players[owner].spawnCell;local area=teamSpawnArea(state,owner)
    local random=cell==nil or area and (cell.x<area.x or cell.x>=area.x+area.width or cell.y<area.y or cell.y>=area.y+area.height)
    local tile=if random then nil else nationSpawnCandidate(state,owner)
    if random or tile then table.insert(state.spawnPhasePending,{owner=owner,tile=tile});state.nations[owner].spawnExecAdded=true end
end
local function applyNationSpawn(state: State, owner: number, tile: number?)
    if state.gameConfig and state.gameConfig.randomSpawn and state.spawnTiles[owner]then return end
    local previous = table.clone(state.territories[owner].values)
    for _, owned in previous do if owned ~= 0 then conquer(state, owned, 0) end end
    if tile==nil or state.gameConfig and state.gameConfig.randomSpawn then
        local alreadySpawned=state.spawnTiles[owner]~=nil
        if not spawnBot(state,owner)then for _,owned in previous do if owned~=0 then conquer(state,owned,owner)end end;return end
        if not alreadySpawned then recordSpawn(state,owner)end;return
    end
    local area = Simulation.spawnArea(state, tile, false)
    if not area or #area == 0 then
        for _, owned in previous do if owned ~= 0 then conquer(state, owned, owner) end end
        return
    end
    for _, owned in area do conquer(state, owned, owner) end
    if not state.spawnTiles[owner] then
        recordSpawn(state,owner)
    end
    state.spawnTiles[owner] = tile
end
function Simulation.new(seed: number?, suppliedMap: any?, options: any?): State
    options = options or {}
    local Config=GameConfig.forState({gameConfig=options.gameConfig})
    local actualSeed = if finite(seed) then math.floor(seed :: number) % 4294967296 else Config.Map.DefaultSeed
    local map = suppliedMap or MapData.generate(actualSeed,options.gameConfig and options.gameConfig.gameMap,options.gameConfig and options.gameConfig.gameMapSize)
    local dynamicWater=options.gameConfig and (options.gameConfig.waterNukes or options.gameConfig.disableNavMesh)
    if dynamicWater then map=MapData.clone(map)end
    local owners = table.create(map.width * map.height, -1)
    for id, land in map.land do owners[id] = if land then 0 else -1 end
    local includeNations = if options.nations ~= nil then options.nations else Config.Nations and Config.Nations.Enabled == true
    local matchBalance = options.matchBalance == true and Balance.supports(options.gameConfig)
    local players,metadata
    if options.roster then players=options.roster
    elseif options.fixture then players=Roster.fixture(options.humanName)
    else players,metadata=Roster.create(actualSeed,options.botCount or Config.Bot.Count,options.humanId,options.humanName,includeNations,options.gameConfig,map.manifest,map,options.humans,options.gameId,matchBalance)end
    assert(#players > 0 and players[1].playerType == "Human", "The local human must occupy owner slot 1")
    local state: State = {
        map = map, owners = owners, troops = {}, counts = {}, players = {}, names = {},
        gameConfig=options.gameConfig,gameId=options.gameId,teams=options.teams or metadata and metadata.teams or {},humanSpawnRandom=Random.new(Random.hash(players[1].id)+Random.hash(options.gameId or tostring(actualSeed))),playerInitTicks={},
        matchBalance=matchBalance,incomeLandCount=if matchBalance then map.landCount else nil,
        playerOrder = {}, executionOrder = {}, bots = {}, bot = nil, nations = {}, spawnPhasePending = {},
        phase = "Choosing", elapsed = 0, seed = actualSeed, ticks = if not options.fixture and options.spawnBots~=false then 1 else 0, startTick = 0, accumulator = 0,
        attacks = {}, executions = {}, pendingExecutions = {}, nextAttackId = 1, changedOwners = {},
        missileSilos={}, samLaunchers={}, samMissiles={}, nukes={}, missileSiloOrders={}, samLauncherOrders={},
        missileSiloConstructed={}, samLauncherConstructed={}, falloutTiles={}, falloutCount=0, changedFalloutIds={}, changedTerrainIds={},
        weaponMessages={}, nextWeaponMessageId=1,
        diplomacy={}, diplomacyRequests={}, alliances={}, diplomacyHooks={}, diplomacyEvents={}, nextDiplomacyEventId=1, nextAllianceId=0,playerExecutionRemoved={},quickChat={},
        territories = {}, borders = {}, spawnTiles = {}, largestClusterBounds = {}, lastTileChange = {}, lastClusterCalc = {}, tileChangeVersion = {},
        gold = {}, goldEarned = {}, cityConstructed = {}, lastDeleteTicks = {}, attacksSent = {}, cities = {}, cityOrders = {}, nextUnitId = 1,
        conquestEvents = {}, nextConquestEventId = 1, ships = {}, shipStagger = 0, navalMessages = {},
        ports = {}, portOrders = {}, portConstructed = {}, unitAcquisitionOrder = {}, nextUnitAcquisitionOrder = 1,
        tradeShips = {}, tradeGold = {}, piracyGold = {}, bonusEvents = {}, nextBonusEventId = 1,
        warships = {}, shells = {}, warshipConstructed = {}, deadUnitEvents = {}, nextDeadUnitEventId = 1,
        factories = {}, defensePosts = {}, factoryOrders = {}, defensePostOrders = {},
        factoryConstructed = {}, defensePostConstructed = {}, trainGold = {}, stations = {}, railroads = {}, trains = {},
    }
    state.trackWarshipUnit = function(unit)
        if unit.active ~= false and state.unitAcquisitionOrder[unit.id] == nil then
            state.unitAcquisitionOrder[unit.id] = state.nextUnitAcquisitionOrder
            state.nextUnitAcquisitionOrder += 1
        elseif unit.active == false then state.unitAcquisitionOrder[unit.id] = nil end
        Warships.trackUnit(state, unit)
    end
    local identities = {}
    for owner, player in players do
        assert(player.playerType == "Human" or player.playerType == "Bot" or player.playerType == "Nation", "Invalid player type")
        assert(not identities[player.id], "Duplicate player identity") identities[player.id] = true
        state.players[owner], state.names[owner] = table.clone(player), player.name
        table.insert(state.playerOrder, owner)
        state.players[owner].markedDoomsdayClockTick=-1;state.players[owner].rottedAtTick=-1
        state.troops[owner] = if GameConfig.infiniteTroops(state,owner)then 1000000 else Rules.startingTroops(player.playerType, Config.Match.Difficulty)
        state.gold[owner] = if player.playerType == "Bot" then 0
            elseif player.playerType == "Human" and Config.Economy.HumanStartingGold ~= nil then Config.Economy.HumanStartingGold -- the tutorial's 50K
            else Config.Economy.StartingGold
        state.goldEarned[owner], state.cityConstructed[owner], state.lastDeleteTicks[owner], state.attacksSent[owner] = 0, 0, -1, 0
        state.cityOrders[owner] = {}
        state.portOrders[owner], state.portConstructed[owner] = {}, 0
        state.tradeGold[owner], state.piracyGold[owner], state.tileChangeVersion[owner] = 0, 0, 0
        state.warshipConstructed[owner] = 0
        state.factoryOrders[owner], state.defensePostOrders[owner] = {}, {}
        state.factoryConstructed[owner], state.defensePostConstructed[owner], state.trainGold[owner] = 0, 0, 0
        state.counts[owner], state.territories[owner], state.borders[owner] = 0, Collections.set(), Collections.set()
        state.largestClusterBounds[owner], state.lastTileChange[owner] = false, 0
        state.lastClusterCalc[owner] = Random.hash(player.id) % 20
        if player.playerType == "Bot" then
            local random = Random.new(Random.hash(player.id))
            local attackRate = Random.int(random, 40, 80)
            state.bots[owner] = {
                random = random, attackRate = attackRate, attackTick = Random.int(random, 0, attackRate),
                triggerRatio = Random.int(random, 50, 60) / 100, reserveRatio = Random.int(random, 30, 40) / 100,
                expandRatio = Random.int(random, 10, 20) / 100, started = false, enabled = true, neighborsTerraNullius = true,
            }
        elseif player.playerType == "Nation" then
            local random = Random.new(Random.hash(player.id) + Random.hash(options.gameId or tostring(actualSeed)))
            local nation: any = { random = random, enabled = true, started = false }
            nation.triggerRatio, nation.reserveRatio, nation.expandRatio = Random.int(random, 50, 60) / 100,
                Random.int(random, 30, 40) / 100, Random.int(random, 10, 20) / 100
            local rates=({Easy={65,100},Medium={55,70},Hard={45,60},Impossible={30,50}})[Config.Match.Difficulty]
            assert(rates,"Unknown source difficulty");nation.attackRate = Random.int(random,rates[1],rates[2])
            nation.attackTick = Random.int(random, 0, nation.attackRate)
            state.nations[owner] = nation
        end
    end
    -- NationExecution chooses its first center before Tribe SpawnExecutions run.
    -- The queued nation footprints are applied on the following spawn-phase tick.
    for owner = 2, #players do
        if state.nations[owner] and options.spawnBots ~= false then
            queueNationSpawn(state,owner)
        end
    end
    if options.gameConfig and options.gameConfig.randomSpawn and options.spawnBots~=false then
        for owner,player in state.players do if player.playerType=="Human"then
            spawnBot(state,owner)
            if state.spawnTiles[owner]then
                if Config.Match.GameType=="Singleplayer"then state.phase="Playing";state.startTick=state.ticks end
                recordSpawn(state,owner)
            end
        end end
    end
    for owner = 2, #players do
        if state.bots[owner] and options.spawnBots ~= false then spawnBot(state, owner) end
        if state.counts[owner] > 0 then recordSpawn(state,owner)end
    end
    -- Compatibility alias for explicit two-owner regression fixtures.
    state.bot = state.bots[2]
    Rails.install(state)
    Weapons.install(state)
    state.recordWeaponMessage=function(event) Simulation.recordWeaponMessage(state,event) end
    state.recordUnitDeath=function(unit, sourceType) Simulation.recordUnitDeath(state,unit,sourceType) end
    state.addTrainGold = function(owner, amount, tile) Simulation.addBonusGold(state, owner, amount, tile) end
    state.removeTrainUnit = function(unit) Trains.deleteUnit(state, unit) end
    state.removeStructureUnit = function(unit)
        if Weapons.missileSilo(state, unit.id) or Weapons.samLauncher(state, unit.id) then Weapons.removeUnit(state,unit)
        elseif Structures.factory(state, unit.id) then Structures.removeFactory(state, unit)
        elseif Structures.defensePost(state, unit.id) then Structures.removeDefensePost(state, unit)
        elseif Ports.port(state, unit.id) then Ports.removePort(state, unit)
        else Economy.removeCity(state, unit) end
    end
    state.relinquishTile=function(tile) if state.owners[tile]>0 then conquer(state,tile,0) end end
    state.setFallout=function(tile,value)
        assert(not value or state.owners[tile]<=0,"Fallout must be unowned")
        -- GameImpl.setFallout returns for existing fallout, even when value=false.
        if state.falloutTiles[tile] then return end
        if value then state.falloutTiles[tile]=true;state.falloutCount+=1 end
        state.changedFalloutIds[tile]=true
    end
    state.queueWaterConversion=function(tile)
        if bit32.band(buffer.readu8(state.map.terrain,tile-1),128)==0 then return end
        assert(state.owners[tile]<=0,"Water conversion must be unowned")
        if not (state.gameConfig and state.gameConfig.waterNukes)then state.setFallout(tile,true);return end
        Water.queue(state,tile)
    end
    if dynamicWater then Water.install(state,options.waterMiniMap)end
    state.deleteMixedUnit=function(unit,_displayMessage,destroyer)
        if unit.unitType=="Missile Silo" or unit.unitType=="SAM Launcher" or unit.unitType=="SAMMissile" then Weapons.removeUnit(state,unit,destroyer)
        elseif unit.unitType=="City" or unit.unitType=="Port" or unit.unitType=="Factory" or unit.unitType=="Defense Post" then state.removeStructureUnit(unit)
        elseif unit.unitType=="Train" then Trains.deleteUnit(state,unit)
        else Warships.deleteUnit(state,unit,nil,destroyer,state.warshipApi) end
    end
    state.maxTroopsFor=function(owner) return Simulation.capacity(state,owner) end
    state.nukeMessage=function(event) Simulation.recordWeaponMessage(state,event) end
    state.canLaunchSilo=function(silo) return Weapons.canLaunch(silo) end
    state.launchSilo=function(silo) Weapons.launchSilo(state,silo) end
    state.gameType=Config.Match.GameType
    state.spawnImmunityActive=function() return state.phase=="Choosing" or state.ticks-state.startTick<Config.Match.SpawnImmunityTicks end
    Nukes.install(state)
    QuickChat.install(state)
    Diplomacy.install(state, {
        nearby=function(owner) return Simulation.nearby(state,owner) end,
        sharedBorder=function(a,b) return sharesBorder(state,a,b) end,
        maxTroops=function(owner) return Simulation.capacity(state,owner) end,
        troopReserve=function(owner) return Simulation.troopReserve(state,owner) end,
        orderedUnits=function(owner)
            local result={};for _,unit in Simulation.weaponUnits(state) do if unit.owner==owner then table.insert(result,unit) end end;return result
        end,
        deleteNuke=function(unit) Nukes.removeUnit(state,unit) end,
        emit=function(event) Simulation.recordDiplomacyEvent(state,event) end,
        spawnPhaseTurns=function() return Config.Diplomacy.SpawnPhaseTicks end,
        canSendEmoji=function(a,b) return Diplomacy.canSendEmoji(state,a,b) end,
        queueEmoji=function(a,b,index) table.insert(state.pendingExecutions,{kind="Emoji",owner=a,targetOwner=b,emoji=index}) end,
        respondToEmoji=function(random,a,b,text) NationEmojiAI.respondToEmoji(state,random,a,b,text,state.nationApi) end,
    })
    state.isFriendly=function(a,b,afk) return Diplomacy.friendly(state,a,b,afk) end
    state.isOnSameTeam=function(a,b) return Diplomacy.sameTeam(state,a,b) end
    state.nukeDiplomacy=function(a,kind,tile) Diplomacy.maybeBreakNuke(state,a,kind,tile) end
    state.mirvDiplomacy=function(a,b) Diplomacy.maybeBreakMIRV(state,a,b) end
    state.railApi={canTrade=function(a,b) return Diplomacy.canTrade(state,a,b) end}
    state.tradeApi={
        canTrade=function(a,b) return Diplomacy.canTrade(state,a,b) end,
        friendly=function(a,b) return Diplomacy.friendly(state,a,b) end,
        addGold=function(owner,amount,tile) Simulation.addBonusGold(state,owner,amount,tile) end,
        message=function(event) table.insert(state.navalMessages,event) end,
    }
    -- The synchronous initial construction corresponds to the first source
    -- execution tick: tribes have spawned and nation spawns are queued.
    if not options.fixture and options.spawnBots ~= false then
        state.ticks = 1
        for owner, _ in state.bots do
            state.lastTileChange[owner] = 1
            state.lastClusterCalc[owner] = 1 + Random.hash(state.players[owner].id) % 20
        end
    end
    -- PF045 Oil Rigs: SIM ONLY, off in live matches (Config.OilRigs.Enabled=false); balance harnesses pass options.oilRigs
    if require(script.Parent.Config).OilRigs.Enabled or options.oilRigs then require(script.Parent.OpenFrontOilRigs).enable(state) end
    return state
end
-- Tutorial maps (Availability.TutorialMaps, Honshu): the human starts on the mainland, the largest connected landmass
-- (4-neighbour, as the simulation's borders), so step 3's tribe is always reachable on foot. Computed once per map.
-- Honshu is one landmass, so the gate passes every land tile there (kept for any future tutorial map with islands).
Simulation.TUTORIAL_SPAWN_HINT = "Pick your start in Japan"
Simulation._mainland = setmetatable({}, {__mode = "k"}) :: any
function Simulation.tutorialMap(state: any): boolean
    local config = state and state.gameConfig
    return type(config) == "table" and require(script.Parent.OpenFrontMatchAvailability).TutorialMaps[config.gameMap] == true
end
local function mainland(map: any): buffer
    local cached = Simulation._mainland[map]
    if cached then return cached end
    local width, height = map.width, map.height
    local count = width * height
    local component, best, bestSize, next = buffer.create(count * 4), 0, 0, 0
    local function land(tile: number): boolean return bit32.band(buffer.readu8(map.terrain, tile - 1), 128) ~= 0 end
    local queue = table.create(1024)
    for start = 1, count do
        if land(start) and buffer.readu32(component, (start - 1) * 4) == 0 then
            next += 1; buffer.writeu32(component, (start - 1) * 4, next)
            table.clear(queue); queue[1] = start
            local head, size = 1, 0
            while head <= #queue do
                local tile = queue[head]; head += 1; size += 1
                local x = (tile - 1) % width
                for side = 1, 4 do
                    local n = if side == 1 then (if x > 0 then tile - 1 else 0) elseif side == 2 then (if x < width - 1 then tile + 1 else 0)
                        elseif side == 3 then (if tile > width then tile - width else 0) else (if tile <= count - width then tile + width else 0)
                    if n > 0 and land(n) and buffer.readu32(component, (n - 1) * 4) == 0 then buffer.writeu32(component, (n - 1) * 4, next); table.insert(queue, n) end
                end
            end
            if size > bestSize then best, bestSize = next, size end
        end
    end
    local result = buffer.create(count)
    for tile = 1, count do if buffer.readu32(component, (tile - 1) * 4) == best then buffer.writeu8(result, tile - 1, 1) end end
    Simulation._mainland[map] = result
    return result
end
-- May the human spawn on this tile? Always, except off the mainland on a tutorial map.
function Simulation.spawnAllowed(state: any, id: number): boolean
    if not Simulation.tutorialMap(state) or not state.map or not state.map.terrain then return true end
    if id < 1 or id > state.map.width * state.map.height then return false end
    return buffer.readu8(mainland(state.map), id - 1) == 1
end
function Simulation.chooseSpawn(state: State, id: number, actor: number?, issuedDuringChoosing: boolean?): (boolean, string)
    local owner=actor or 1
    if not ownerValid(state,owner)or state.players[owner].playerType~="Human"then return false,"Invalid human spawn."end
    if state.phase ~= "Choosing"and not (actor and issuedDuringChoosing==true and state.gameType=="Public"and state.phase=="Playing")then return false, "This match has already started." end
    if not validId(state, id) then return false, "Choose a valid spawn location." end
    if not Simulation.spawnAllowed(state, id) then return false, Simulation.TUTORIAL_SPAWN_HINT .. "." end -- tutorial maps only
    if state.gameConfig and state.gameConfig.randomSpawn and state.spawnTiles[owner]then return true,"Spawn already selected."end
    -- Already queued spawns precede a new human spawn intent in execution order.
    for _, spawn in state.spawnPhasePending do applyNationSpawn(state, spawn.owner, spawn.tile) end
    state.spawnPhasePending = {}
    if state.gameConfig and state.gameConfig.randomSpawn then
        spawnBot(state,owner)
        if not state.spawnTiles[owner]then return false,"No available random spawn location."end
        id=state.spawnTiles[owner]
    end
    local previous={}
    if actor and state.spawnTiles[owner]then
        for _,tile in state.territories[owner].values do if tile~=0 then table.insert(previous,tile)end end
        for _,tile in previous do conquer(state,tile,0)end
    end
    local area = if state.spawnTiles[owner]and not actor then {}else Simulation.spawnArea(state, id, false)
    if state.spawnTiles[owner]and not actor then for _,tile in state.territories[owner].values do if tile~=0 then table.insert(area,tile)end end end
    if not area or #area==0 then for _,tile in previous do conquer(state,tile,owner)end;return false,"No available land at that spawn location."end
    for _, tile in area do conquer(state, tile, owner) end
    state.spawnTiles[owner]=id;recordSpawn(state,owner)
    if GameConfig.forState(state).Match.GameType=="Singleplayer"then state.phase="Playing";state.startTick=state.ticks end
    -- Source PlayerExecution.init is deferred for every spawned player until
    -- Choosing ends; initial AI spawn timestamps are not the cluster clock.
    if state.phase~="Choosing"then for _,owner in state.executionOrder do initializePlayer(state,owner,state.ticks)end end
    return true, "Click wilderness to expand, or a neighboring country's territory to attack."
end

-- PF030 spawn phase (Ashton 2026-10-08): Choosing lasts at most Config.Match.SpawnPhaseSeconds (30 s) in every mode,
-- ends the moment every present human has picked, and at the deadline places anyone still choosing at random.
-- present = the human owners connected and loaded (the runtime knows); nil = every connected human.
-- The 30 s start when the first human is present (a hosted Solo server resets before its client has loaded); a
-- multiplayer match nobody has loaded into starts after twice that.
local function presentHumans(state: State, present: { number }?): { number }
    if present then return present end
    local result = {}
    for owner, player in state.players do if player.playerType == "Human" and not (player :: any).isDisconnected then table.insert(result, owner) end end
    return result
end
-- The spawn ring's facts (the runtime adds `you`): deadlineTick is nil until the first human is present.
function Simulation.choosingStatus(state: State, present: { number }?): any
    local humans, picked = presentHumans(state, present), 0
    for _, owner in humans do if state.spawnTiles[owner] then picked += 1 end end
    return { deadlineTick = state.choosingDeadline, present = #humans, picked = picked, allPicked = #humans > 0 and picked == #humans,
        seconds = GameConfig.forState(state).Match.SpawnPhaseSeconds } -- the phase's full length (the ring's 100%)
end
-- A human who hasn't picked starts at a random spot (spawnBot's search; the tutorial's mainland gate included): at the
-- spawn-phase deadline, or a late loader once the match is Playing.
function Simulation.placeRandom(state: State, owner: number): boolean
    if not ownerValid(state, owner) or state.players[owner].playerType ~= "Human" or state.spawnTiles[owner] then return false end
    if state.phase ~= "Choosing" and state.phase ~= "Playing" then return false end
    for _, spawn in state.spawnPhasePending do applyNationSpawn(state, spawn.owner, spawn.tile) end
    state.spawnPhasePending = {}
    if not spawnBot(state, owner) or not state.spawnTiles[owner] then return false end
    state.autoPlaced = state.autoPlaced or {}; (state.autoPlaced :: any)[owner] = true -- the tutorial report's "Auto-placed"
    recordSpawn(state, owner)
    return true
end
-- First-match onboarding: the "Click here" tile on the Pick card. Deterministic samples of open land (spawnBot's own
-- tests), scored away from the nations' homes (at least MinSpawnDistance) and near tribes (the step-3 fight); the best one
-- whose spawn area is mostly free. nil when nothing qualifies (the card then just says "pick a spot").
function Simulation.spawnHint(state: State): number?
    if state.phase ~= "Choosing" or not state.map then return nil end
    local width, height = state.map.width, state.map.height
    local minDistance = GameConfig.forState(state).Match.MinSpawnDistance
    local nations, tribes = {}, {}
    for owner, player in state.players do
        local tile = state.spawnTiles[owner] or (player :: any).spawnTile
        if not tile then continue end
        if player.playerType == "Nation" then table.insert(nations, tile) elseif state.bots[owner] then table.insert(tribes, tile) end
    end
    local random = Random.new(Random.hash("spawnHint:" .. tostring(state.gameId or state.seed)))
    local best, bestScore = nil, -math.huge
    for _ = 1, 300 do
        local x, y = Random.int(random, 0, width - 1), Random.int(random, 0, height - 1)
        local id = y * width + x + 1
        if not validId(state, id) or not passable(state, id) or state.owners[id] ~= 0 or isBorder(state, id) or not Simulation.spawnAllowed(state, id) then continue end
        local near, close = math.huge, 0
        for _, tile in nations do near = math.min(near, math.abs(x - (tile - 1) % width) + math.abs(y - math.floor((tile - 1) / width))) end
        for _, tile in tribes do
            if math.abs(x - (tile - 1) % width) + math.abs(y - math.floor((tile - 1) / width)) <= 40 then close += 1 end
        end
        local score = math.min(near, 80) + 6 * math.min(close, 5) - (if near < minDistance then 100 else 0)
        if score <= bestScore then continue end
        local area = Simulation.spawnArea(state, id, false)
        local full = math.pi * GameConfig.forState(state).Match.SpawnRadius ^ 2
        if area and #area >= full * 0.6 then best, bestScore = id, score end
    end
    return best
end
function Simulation.stepChoosing(state: State, dt: number, present: { number }?)
    if state.phase ~= "Choosing" or not finite(dt) or dt <= 0 or dt > 1 then return end
    state.accumulator += dt
    while state.accumulator + 1e-8 >= GameConfig.forState(state).Match.StepSeconds do
        local config=GameConfig.forState(state)
        local humans=presentHumans(state,present)
        local phaseTicks=math.round(config.Match.SpawnPhaseSeconds/config.Match.StepSeconds)
        if not state.choosingDeadline then
            if #humans>0 then state.choosingDeadline=state.ticks+phaseTicks
            elseif config.Match.GameType~="Singleplayer"and state.ticks>=2*phaseTicks then state.choosingDeadline=state.ticks end
        end
        local timeUp=state.choosingDeadline~=nil and state.ticks+1>state.choosingDeadline
        if timeUp or Simulation.choosingStatus(state,humans).allPicked then
            if timeUp then for _,owner in humans do Simulation.placeRandom(state,owner)end end
            state.phase="Playing";state.startTick=state.ticks+1
            for _,owner in state.executionOrder do initializePlayer(state,owner,state.startTick)end
            state.accumulator=math.max(0,state.accumulator-config.Match.StepSeconds)
            Simulation.step(state,config.Match.StepSeconds)
            return
        end
        state.accumulator = math.max(0, state.accumulator - GameConfig.forState(state).Match.StepSeconds)
        state.ticks += 1
        local pending = state.spawnPhasePending
        state.spawnPhasePending = {}
        for owner = 2, #state.players do
            local nation = state.nations[owner]
            if not nation or not nation.enabled then continue end
            local alreadyQueued = false
            for _, spawn in pending do if spawn.owner == owner then alreadyQueued = true break end end
            if alreadyQueued then continue end
            if not state.spawnTiles[owner]and nation.spawnExecAdded then continue end
            if state.spawnTiles[owner] and state.ticks % nation.attackRate ~= nation.attackTick then continue end
            queueNationSpawn(state,owner)
        end
        for _, spawn in pending do applyNationSpawn(state, spawn.owner, spawn.tile) end
    end
end

-- This helper cannot yield or recurse; a private buffer avoids allocating for
-- each captured tile. Other neighbor walks have distinct caller-owned buffers.
local attackNeighbors: { number } = {}
local function addNeighbors(state: State, attack: Campaign, tile: number)
    for _, neighbor in neighbors(state, tile, attackNeighbors) do
        if not passable(state, neighbor) or state.owners[neighbor] ~= attack.targetOwner then continue end
        if attack.targetOwner == 0 and Simulation.mercyTile(state, attack.owner, neighbor) then continue end -- PF043
        if not attack.border[neighbor] then
            attack.border[neighbor] = true;attack.borderSize += 1
            if not attack.borderOrder then attack.borderOrder=Collections.set()end
            Collections.add(attack.borderOrder,neighbor)
        end
        local owned = 0
        local width, owners = state.map.width, state.owners
        local x, owner = (neighbor - 1) % width, attack.owner
        if neighbor > width and owners[neighbor - width] == owner then owned += 1 end
        if neighbor <= width * (state.map.height - 1) and owners[neighbor + width] == owner then owned += 1 end
        if x > 0 and owners[neighbor - 1] == owner then owned += 1 end
        if x < width - 1 and owners[neighbor + 1] == owner then owned += 1 end
        local mag = magnitude(state, neighbor)
        local terrainPriority = if mag < 10 then 1 elseif mag < 20 then 1.5 else 2
        local priority = (Random.int(attack.random, 0, 7) + 10) * (1 - owned * 0.5 + terrainPriority / 2) + state.ticks
        Collections.enqueue(attack.heap, neighbor, priority)
    end
end
local function refresh(state: State, attack: Campaign)
    attack.heap, attack.border, attack.borderSize,attack.borderOrder = Collections.heap(), {}, 0,Collections.set()
    for _, tile in state.borders[attack.owner].values do if tile ~= 0 then addNeighbors(state, attack, tile) end end
end
local function pruneAttacks(state: State)
    local alive = {}
    for _, attack in state.attacks do if attack.active then table.insert(alive, attack) end end
    state.attacks = alive
end
-- forgive (first-match step 4, Ashton 2026-10-26: "the nation should blunt the attack and forget it happened"): the nation
-- defends as usual, but no embargo, no relation hit, and its AI never retaliates against this attack (attack.forgiven).
local function launch(state: State, owner: number, targetOwner: number, amount: number, sourceTile: number?, removeTroops: boolean?, forgive: boolean?): boolean
    if owner == targetOwner then return false end
    -- PF014: a queued send that found nothing above the reserve does nothing (before any side effects).
    if removeTroops ~= false and Simulation.troopReserve(state, owner) > 0 and Simulation.sendableTroops(state, owner) < 1 then return false end
    if targetOwner>0 then
        if Diplomacy.friendly(state,owner,targetOwner) then return false end
        if not forgive and not isBot(state,owner) and not isBot(state,targetOwner) then
            Diplomacy.addEmbargo(state,targetOwner,owner,true)
            Simulation.rejectIncomingRequest(state,owner,targetOwner)
        end
        if not Simulation.canAttackPlayer(state,owner,targetOwner) then return false end
    end
    -- A landing already paid at launch. UnitImpl can retain fractional troops;
    -- AttackExecution keeps that amount while StatsImpl floors its numeric entry.
    local paid = if removeTroops == false then amount else math.floor(math.min(state.troops[owner], amount))
    if removeTroops ~= false then
        local reserve = Simulation.troopReserve(state, owner) -- PF014: payout never digs into a human's reserve
        if reserve > 0 then paid = math.floor(math.min(paid, state.troops[owner] - reserve)) end
        state.troops[owner] -= paid
    end
    state.attacksSent[owner] += math.floor(paid)
    local attack: Campaign = {
        id = state.nextAttackId, owner = owner, targetOwner = targetOwner, budget = paid,
        retreating = false, createdTick = state.ticks, active = true, random = Random.new(123), heap = Collections.heap(), border = {}, borderOrder=Collections.set(),borderSize = 0,
        sourceTile = sourceTile, forgiven = if forgive then true else nil,
    }
    state.nextAttackId += 1
    if sourceTile then addNeighbors(state, attack, sourceTile) else refresh(state, attack) end
    for _, incoming in state.attacks do
        if incoming.active and incoming.owner == targetOwner and incoming.targetOwner == owner then
            if incoming.budget > attack.budget then
                incoming.budget -= attack.budget attack.active = false pruneAttacks(state) return true
            else attack.budget -= incoming.budget incoming.active = false end
        end
    end
    for _, outgoing in state.attacks do
        if sourceTile == nil and outgoing.active and outgoing.owner == owner and outgoing.targetOwner == targetOwner then
            attack.budget += outgoing.budget outgoing.active = false
        end
    end
    pruneAttacks(state)
    if targetOwner>0 and not forgive then Diplomacy.updateRelation(state,targetOwner,owner,-60) end
    table.insert(state.attacks, attack)
    table.insert(state.executions, { kind = "Attack", attack = attack })
    return true
end
local function queueAttack(state: State, owner: number, targetOwner: number, amount: number): boolean
    if amount < 1 then return false end
    -- GameRunner queues command executions; GameImpl initializes them only after
    -- all existing executions have ticked. The requested amount is already fixed.
    table.insert(state.pendingExecutions, { kind = "Attack", owner = owner, targetOwner = targetOwner, amount = amount })
    return true
end
-- The third result is PF014 reserve info ({kept, sent, refused}) when the reserve
-- reduced or refused the send; the server forwards it as a ReserveNotice.
function Simulation.attack(state: State, owner: number, id: number, ratio: number): (boolean, string, any?)
    if not finite(ratio) or ratio < GameConfig.forState(state).Combat.RatioMin or ratio > GameConfig.forState(state).Combat.RatioMax then
        return false, "Choose an attack amount between 1% and 100%."
    end
    if not Simulation.canAttack(state, owner, id) then return false, "That territory is not reachable from your border." end
    local amount, reserve = Simulation.reserveClamp(state, owner, state.troops[owner] * ratio)
    if reserve and reserve.refused then return false, reserveMessage(reserve), reserve end
    if not queueAttack(state, owner, state.owners[id], amount) then return false, "Not enough troops." end
    if state.revive and state.owners[id] > 0 then Simulation.reviveAttacked(state, owner, state.owners[id]) end -- PF044
    -- first-match step 4: an accepted attack on a Nation completes it (no win or kill needed); that one attack is forgiven
    -- (launch: the nation blunts it, then forgets it)
    if state.recordTutorialAction and state.owners[id] > 0 and state.players[state.owners[id]].playerType == "Nation"
        and state.recordTutorialAction(owner, "attackNation") == true then
        state.pendingExecutions[#state.pendingExecutions].forgive = true
    end
    return true, if state.owners[id] == 0 then "Expanding into wilderness." else "Attack sent.", reserve
end
Simulation.canBuildTransportShip = Naval.canBuildTransportShip
function Simulation.boat(state: State, owner: number, id: number, ratio: number?): (boolean, string, any?)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not validId(state, id)
        or (ratio ~= nil and (not finite(ratio) or ratio < GameConfig.forState(state).Combat.RatioMin or ratio > GameConfig.forState(state).Combat.RatioMax)) then
        return false, "Choose a valid naval target and troop amount."
    end
    if Naval.canBuildTransportShip(state, owner, id) == false then return false, "A transport ship cannot reach that territory." end
    local requested = if ratio == nil then math.floor(state.troops[owner] * GameConfig.forState(state).Naval.DefaultAttackRatio) else state.troops[owner] * ratio
    local amount, reserve = Simulation.reserveClamp(state, owner, requested)
    if reserve and reserve.refused then return false, reserveMessage(reserve), reserve end
    if amount < 1 then return false, "Not enough troops." end
    table.insert(state.pendingExecutions, { kind = "TransportShip", owner = owner, tileId = id, amount = amount })
    if state.revive and state.owners[id] > 0 then Simulation.reviveAttacked(state, owner, state.owners[id]) end -- PF044
    if state.recordTutorialAction and state.owners[id] > 0 and state.players[state.owners[id]].playerType == "Nation" then state.recordTutorialAction(owner, "attackNation") end -- first-match step 4 by sea
    return true, "Transport ship ordered.", reserve
end
function Simulation.boatRetreat(state: State, owner: number, unitId: number): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or not finite(unitId) or unitId % 1 ~= 0 then
        return false, "Select a transport ship to recall."
    end
    local ship = Naval.ship(state, unitId)
    if not ship or ship.owner ~= owner or ship.isRetreating then return false, "That ship is no longer available to recall." end
    table.insert(state.pendingExecutions, { kind = "BoatRetreat", owner = owner, unitId = unitId })
    return true, "Ship retreat ordered; 25% of its troops will be lost on return."
end
function Simulation.retaliate(state: State, owner: number, attackId: number, ratio: number): (boolean, string, any?)
    if state.phase == "Choosing" or not ownerValid(state, owner) or state.counts[owner] == 0
        or not finite(ratio) or ratio < GameConfig.forState(state).Combat.RatioMin or ratio > GameConfig.forState(state).Combat.RatioMax
        or not finite(attackId) then return false, "Select an incoming attack." end
    for _, attack in state.attacks do
        if attack.active and attack.id == attackId and attack.targetOwner == owner then
            if not sharesBorder(state, owner, attack.owner) then return false, "That territory is not reachable from your border." end
            local amount, reserve = Simulation.reserveClamp(state, owner, math.min(attack.budget, state.troops[owner] * ratio))
            if reserve and reserve.refused then return false, reserveMessage(reserve), reserve end
            if queueAttack(state, owner, attack.owner, amount) then return true, "Counterattack sent.", reserve end
            return false, "Not enough troops."
        end
    end
    return false, "That attack is no longer active."
end
function Simulation.cancel(state: State, owner: number, attackId: number?): (boolean, string)
    if state.phase == "Choosing" or not ownerValid(state, owner) or state.counts[owner] == 0 or not finite(attackId) then return false, "Select an attack to recall." end
    for _, attack in state.attacks do
        if attack.id == attackId and attack.owner == owner and attack.active and not attack.retreating then
            table.insert(state.pendingExecutions, { kind = "Retreat", owner = owner, attackId = attackId })
            return true, if attack.targetOwner == 0 then "Retreat ordered." else "Retreat ordered; 25% of this army will be lost."
        end
    end
    return false, "That attack is no longer active."
end

local function retreat(state: State, attack: Campaign, penalty: number)
    local survivors = attack.budget - attack.budget * penalty
    state.troops[attack.owner] += math.floor(survivors)
    if attack.retreated then state.attacksSent[attack.owner] += math.floor(-survivors) end
    attack.active = false
end
-- Tutorial facts: the captor eliminated a tribe or a nation (observer only; no rule change), by a land
-- attack (finishDefender) or by annexing an encircled remnant (Territory.update -> conquerPlayer).
local function recordDefeat(state: State, owner: number, defender: number)
    if state.recordTutorialAction then
        if isBot(state,defender) then state.recordTutorialAction(owner,"tribe")
        elseif state.players[defender].playerType=="Nation" then state.recordTutorialAction(owner,"nation") end
    end
end
local function conquerPlayer(state: State, captor: number, victim: number)
    Economy.conquerPlayer(state, captor, victim)
    recordDefeat(state, captor, victim)
end
local function finishDefender(state: State, owner: number, defender: number)
    if state.counts[defender] >= GameConfig.forState(state).Combat.DefeatedTerritory then return end
    Economy.conquerPlayer(state, owner, defender)
    recordDefeat(state, owner, defender)
    local scratch = {}
    -- Reference absorbs bordering remnants only, not disconnected islands.
    for _ = 1, 100 do
        local progressed = false
        for _, tile in state.territories[defender].values do
            if tile == 0 then continue end
            if adjacent(state, tile, owner) then conquer(state, tile, owner) progressed = true
            else
                -- AttackExecution.handleDeadDefender hands disconnected remnants
                -- to the first other hostile neighbor in N,S,W,E order.
                for _, neighbor in neighbors(state, tile, scratch) do
                    local other = state.owners[neighbor]
                    if other > 0 and other ~= defender and not Diplomacy.friendly(state,other,defender) then conquer(state, tile, other) progressed = true break end
                end
            end
        end
        if not progressed then break end
    end
end
local function advance(state: State, attack: Campaign)
    if not attack.active or state.ticks <= attack.createdTick then return end
    if attack.retreated then
        retreat(state, attack, if attack.targetOwner > 0 then GameConfig.forState(state).Combat.RetreatLossFraction else 0)
        return
    end
    if attack.retreating then return end
    if attack.targetOwner>0 and Diplomacy.friendly(state,attack.owner,attack.targetOwner) then retreat(state,attack,0);return end
    local troopCount = attack.budget
    local borderSize = attack.borderSize + Random.int(attack.random, 0, 5)
    local tickBudget = 1
    while tickBudget > 0 do
        if troopCount < 1 then attack.active = false return end
        if #attack.heap.tiles == 0 then refresh(state, attack) retreat(state, attack, 0) return end
        local tile = Collections.dequeue(attack.heap)
        if attack.border[tile] then
            attack.border[tile] = nil;attack.borderSize -= 1
            if attack.borderOrder then Collections.remove(attack.borderOrder,tile)end
        end
        if state.owners[tile] ~= attack.targetOwner or not adjacent(state, tile, attack.owner) or not passable(state, tile) then continue end
        addNeighbors(state, attack, tile)
        local defender = attack.targetOwner
        local loss, defenderLoss, fraction = Rules.attack(magnitude(state, tile), troopCount,
            state.counts[attack.owner], isBot(state, attack.owner), if defender > 0 then state.counts[defender] else nil,
            if defender > 0 then state.troops[defender] else 0, defender > 0 and isBot(state, defender), borderSize,
            defender > 0 and Structures.defensePostProtectsTile(state, defender, tile),
            if state.falloutTiles[tile] then state.falloutCount/state.map.landCount else nil,
            defender>0 and Diplomacy.isTraitor(state,defender))
        tickBudget -= fraction
        troopCount -= loss
        attack.budget = math.max(0, troopCount)
        if defender > 0 then state.troops[defender] -= math.min(state.troops[defender], math.floor(defenderLoss)) end
        conquer(state, tile, attack.owner)
        if defender > 0 then finishDefender(state, attack.owner, defender) end
    end
end

local function neutralBorder(state: State, owner: number, excludeFallout: boolean?): boolean
    local scratch = {}
    for _, tile in state.borders[owner].values do
        if tile ~= 0 then
            for _, neighbor in neighbors(state, tile, scratch) do
                if state.owners[neighbor] == 0 and passable(state, neighbor)
                    and (not excludeFallout or not state.falloutTiles[neighbor]) then return true end
            end
        end
    end
    return false
end

-- Protocol validation is a Roblox adapter; execution eligibility remains the
-- source's own per-execution check at init/tick, including queued state changes.
function Simulation.diplomacyCommand(state: State, owner: number, request: any): (boolean, string?, any?)
    local kind=if request.kind=="AllianceExtend" then "AllianceExtension" else request.kind
    if not ownerValid(state,owner) or not Diplomacy.isExecution(kind) or state.phase=="Choosing" then return false,"That action is unavailable." end
    local target=request.targetOwner
    if kind~="EmbargoAll" and not (kind=="Emoji" and target==0) and not ownerValid(state,target) then return false,"Choose a player." end
    if target==owner then return false,"Choose another player." end
    if kind=="Embargo" or kind=="EmbargoAll" then
        if request.action~="start" and request.action~="stop" then return false,"Invalid embargo action." end
    end
    if kind=="DonateGold" or kind=="DonateTroops" then
        if request.amount~=nil and (not finite(request.amount) or request.amount<0) then return false,"Invalid gift amount." end
    elseif kind=="Emoji" then
        if not finite(request.emoji) or request.emoji%1~=0 or request.emoji<0 or request.emoji>=#Diplomacy.EmojiTable then return false,"Invalid emoji." end
    end
    local amount,reserve=request.amount,nil
    if kind=="DonateTroops" then -- PF014: a troop gift never digs into the giver's reserve
        local clamped
        clamped,reserve=Simulation.reserveClamp(state,owner,request.amount or math.floor(state.troops[owner]/3))
        if reserve and reserve.refused then return false,reserveMessage(reserve),reserve end
        if reserve then amount=math.floor(clamped) end
    end
    table.insert(state.pendingExecutions,{kind=kind,owner=owner,targetOwner=target,action=request.action,amount=amount,emoji=request.emoji})
    return true,nil,reserve
end

-- GameImpl holds QuickChat uninitialized throughout spawn; it initializes after
-- the first non-spawn tick's existing executions and sends on the following tick.
function Simulation.quickChatCommand(state: State, owner: number, request: any): (boolean, string?)
    if not ownerValid(state,owner) or not ownerValid(state,request.targetOwner)
        or type(request.quickChatKey)~="string" or not QuickChat.validKey(request.quickChatKey) then
        return false,"Choose a valid quick chat phrase and recipient."
    end
    local target=request.targetPlayer
    if target~=nil and (not finite(target) or target%1~=0 or target<1 or target>9007199254740991) then
        return false,"Choose a valid player reference."
    end
    table.insert(state.pendingExecutions,{kind="QuickChat",owner=owner,targetOwner=request.targetOwner,quickChatKey=request.quickChatKey,targetPlayer=target})
    return true,nil
end

function Simulation.copyDiplomacyEvent(value: any): any
    if type(value)~="table" then return value end
    local result={};for key,item in value do result[key]=Simulation.copyDiplomacyEvent(item) end;return result
end
function Simulation.recordDiplomacyEvent(state: any, event: any)
    local saved=Simulation.copyDiplomacyEvent(event);saved.eventId=state.nextDiplomacyEventId
    state.nextDiplomacyEventId+=1;table.insert(state.diplomacyEvents,saved)
end
function Simulation.acknowledgeDiplomacyEvents(state: any, cursor: number)
    local delivered=0;for _,event in state.diplomacyEvents do if event.eventId>cursor then break end;delivered+=1 end
    local discard=delivered-64;if discard<=0 then return end
    local kept={};for index=discard+1,#state.diplomacyEvents do table.insert(kept,state.diplomacyEvents[index]) end;state.diplomacyEvents=kept
end
function Simulation.rejectIncomingRequest(state: any, owner: number, requestor: number)
    for _,request in Diplomacy.incomingRequests(state,owner) do
        if request.requestor==requestor then Diplomacy.rejectRequest(state,request) end
    end
end
function Simulation.hasNonFalloutNeutralBorder(state: State, owner: number): boolean
    return neutralBorder(state,owner,true)
end
function Simulation.hasFalloutBorder(state: State, owner: number): boolean
    -- AiAttackBehavior.isBorderingNukedTerritory checks land, ownership and
    -- fallout, without the generic attack's impassable predicate.
    if not GameConfig.forState(state).MissileSilo.Enabled or table.find(GameConfig.forState(state).DisabledUnits,"Missile Silo") then return false end
    local scratch={}
    for _,tile in state.borders[owner].values do
        if tile~=0 then
            for _,neighbor in neighbors(state,tile,scratch) do
                if bit32.band(buffer.readu8(state.map.terrain,neighbor-1),128)~=0
                    and state.owners[neighbor]==0 and state.falloutTiles[neighbor] then return true end
            end
        end
    end
    return false
end
-- PlayerImpl.computeNearby/shoreReachableNeighbors preserve discovery order.
-- The five-tile shore search affects even land-only target shuffle order.
-- PF035: nearby walks the owner's whole border (100-380 ms for a big late-game nation) and the AI asks it several times
-- per owner per tick, so it is cached until any owner (ownerEpoch), fallout (falloutCount: adds; removals come with an
-- owner or water change) or water (waterVersion) changes. Exact: the same border, in the same order, gives the same
-- list. Callers get their own copy.
local nearbyCache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local computeNearby
function Simulation.nearby(state: State, owner: number): { number }
    local epoch, fallout, water = state.ownerEpoch or 0, state.falloutCount or 0, state.map.waterVersion or 0
    local cache = nearbyCache[state]
    if not cache or cache.epoch ~= epoch or cache.fallout ~= fallout or cache.water ~= water then
        cache = { epoch = epoch, fallout = fallout, water = water, byOwner = {} }
        nearbyCache[state] = cache
    end
    local hit = cache.byOwner[owner]
    if hit then return table.clone(hit) end
    local result = computeNearby(state, owner)
    cache.byOwner[owner] = table.clone(result)
    return result
end
function computeNearby(state: State, owner: number): { number }
    local result, seen, scratch = {}, {}, {}
    local function visit(tile: number)
        if not passable(state, tile) then return end
        local other = state.owners[tile]
        if other==0 and state.falloutTiles[tile] then return end
        if other ~= owner and not seen[other] then seen[other] = true table.insert(result, other) end
    end
    for _, tile in state.borders[owner].values do
        if tile ~= 0 then for _, nextTile in neighbors(state, tile, scratch) do visit(nextTile) end end
    end
    local shoreIndex = 0
    for _, tile in state.borders[owner].values do
        if tile == 0 or bit32.band(buffer.readu8(state.map.terrain, tile - 1), 64) == 0 then continue end
        shoreIndex += 1
        if (shoreIndex - 1) % 10 ~= 0 then continue end
        local x, y = (tile - 1) % state.map.width, math.floor((tile - 1) / state.map.width)
        for _, direction in shoreDirections do
            local nearX, nearY = x + direction[1], y + direction[2]
            if nearX < 0 or nearX >= state.map.width or nearY < 0 or nearY >= state.map.height then continue end
            if state.map.land[nearY * state.map.width + nearX + 1] then continue end
            local farX, farY = x + direction[1] * 5, y + direction[2] * 5
            if farX >= 0 and farX < state.map.width and farY >= 0 and farY < state.map.height then visit(farY * state.map.width + farX + 1) end
        end
    end
    return result
end
local function checkVictory(state: State)
    if state.counts[1] == 0 and state.gameType~="Public" and not state.reviveHold then state.phase = "Lost" end -- PF044 reviveHold
    if state.gameConfig then
        local result=Victory.tick(state,state.gameConfig)
        if result then
            if result.kind=="player"then state.winner=result.owner;state.phase=if state.gameType=="Public"or result.owner==1 then "Won"else "Lost"
            elseif result.kind=="team"then state.winnerTeam=result.team;state.phase=if state.gameType=="Public"or state.players[1].team==result.team then "Won"else "Lost"
            else state.phase="Cancelled"end
            if state.winner==1 and state.recordTutorialAction then state.recordTutorialAction(1,"win") end
        end
        return
    end
    if state.winner then return end
    if state.ticks % GameConfig.forState(state).Match.WinCheckTicks ~= 0 then return end
    local leader = 0
    for _, owner in state.playerOrder do
        if state.counts[owner] > (if leader == 0 then 0 else state.counts[leader]) then leader = owner end
    end
    if leader == 0 then return end
    if state.counts[leader] * 100 > (state.map.landCount-state.falloutCount) * GameConfig.forState(state).Match.VictoryPercent
        or state.elapsed >= GameConfig.forState(state).Match.HardTimeLimitSeconds then
        state.winner = leader
        state.phase = if leader == 1 then "Won" else "Lost"
        if leader==1 and state.recordTutorialAction then state.recordTutorialAction(1,"win") end
    end
end
-- One bad execution is dropped and logged instead of halting the match: a throw
-- inside the tick would otherwise fault the whole match (it pauses and never recovers).
local function executionFault(state: State, phase: string, execution: any, failure: any)
    if execution.kind == "Attack" and type(execution.attack) == "table" then execution.attack.active = false end
    state.droppedExecutions = (state.droppedExecutions or 0) + 1
    local message = string.format("[OpenFront] %s execution %s (owner %s) dropped at tick %d: %s",
        phase, tostring(execution.kind), tostring(execution.owner), state.ticks, tostring(failure))
    if state.onExecutionFault then state.onExecutionFault(message) elseif warn then warn(message) end
end
-- One active execution's tick. Returns whether it stays active.
local function tickOne(state: State, execution: any): any
    if execution.kind == "Attack" then
        advance(state, execution.attack)
        return execution.attack.active
    elseif execution.kind == "Retreat" then
        for _, attack in state.attacks do
            if attack.active and attack.owner == execution.owner and attack.id == execution.attackId then
                if not execution.ordered then attack.retreating = true end
                if state.ticks >= execution.startTick + GameConfig.forState(state).Combat.RetreatTicks then attack.retreated = true end
                break
            end
        end
        execution.ordered = true
        return state.ticks < execution.startTick + GameConfig.forState(state).Combat.RetreatTicks
    elseif execution.kind == "TransportShip" or execution.kind == "BoatRetreat" then
        return Naval.tickExecution(state, execution, state.navalApi)
    elseif execution.kind == "PortTrade" or execution.kind == "TradeShip" then
        return Trade.tickExecution(state, execution, state.tradeApi)
    elseif execution.kind == "BuildWarship" or execution.kind == "Warship" or execution.kind == "MoveWarship" or execution.kind == "Shell" then
        return Warships.tickExecution(state, execution, state.warshipApi)
    elseif execution.kind == "BuildPort" or execution.kind == "UpgradePort" or execution.kind == "DeletePort" then
        return Ports.tickExecution(state, execution)
    elseif execution.kind == "BuildFactory" or execution.kind == "UpgradeFactory" or execution.kind == "DeleteFactory"
        or execution.kind == "BuildDefensePost" or execution.kind == "DeleteDefensePost" then
        return Structures.tickExecution(state, execution)
    elseif execution.kind == "CityStation" or execution.kind == "FactoryStation" or execution.kind == "TrainStation"
        or execution.kind == "RecomputeRailClusters" then
        return Rails.tickExecution(state, execution)
    elseif execution.kind == "Train" then
        return Trains.tickExecution(state, execution)
    elseif execution.kind=="BuildNuke" then
        local count=if execution.nukeType=="MIRV" then 1 else execution.amount or 1
        for _=1,count do
            table.insert(state.pendingExecutions,{kind=if execution.nukeType=="MIRV" then "MIRV" else "Nuke",
                owner=execution.owner,nukeType=execution.nukeType,tileId=execution.tileId,directionUp=execution.directionUp,waitTicks=0})
        end
        return false
    elseif weaponExecutions[execution.kind] then
        return Weapons.tickExecution(state,execution,state.weaponApi)
    elseif execution.kind=="Nuke" or execution.kind=="MIRV" then
        return Nukes.tickExecution(state,execution,state.nuclearApi)
    elseif execution.kind=="QuickChat" then
        QuickChat.tickExecution(state,execution,function(event) Simulation.recordDiplomacyEvent(state,event) end)
        return execution.active
    elseif Diplomacy.isExecution(execution.kind) then
        return Diplomacy.tickExecution(state,execution)
    end
    return Economy.tickExecution(state, execution)
end
-- One pending execution's init. Returns whether it joins the active executions.
local function initOne(state: State, execution: any): any
    if execution.kind == "Attack" then
        launch(state, execution.owner, execution.targetOwner, execution.amount, execution.sourceTile, execution.removeTroops, execution.forgive)
        return false
    elseif execution.kind == "Retreat" then
        execution.startTick, execution.ordered = state.ticks, false
        return true
    elseif execution.kind == "TransportShip" or execution.kind == "BoatRetreat" then
        return Naval.initExecution(state, execution, state.navalApi)
    elseif execution.kind == "PortTrade" or execution.kind == "TradeShip" then
        return Trade.initExecution(state, execution, state.tradeApi)
    elseif execution.kind == "BuildWarship" or execution.kind == "Warship" or execution.kind == "MoveWarship" or execution.kind == "Shell" then
        return Warships.initExecution(state, execution, state.warshipApi)
    elseif execution.kind == "BuildPort" or execution.kind == "UpgradePort" or execution.kind == "DeletePort" then
        return Ports.initExecution(state, execution)
    elseif execution.kind == "BuildFactory" or execution.kind == "UpgradeFactory" or execution.kind == "DeleteFactory"
        or execution.kind == "BuildDefensePost" or execution.kind == "DeleteDefensePost" then
        return Structures.initExecution(state, execution)
    elseif execution.kind == "CityStation" or execution.kind == "FactoryStation" or execution.kind == "TrainStation"
        or execution.kind == "RecomputeRailClusters" then
        return Rails.initExecution(state, execution)
    elseif execution.kind == "Train" then
        return Trains.initExecution(state, execution)
    elseif execution.kind=="BuildNuke" then
        return GameConfig.forState(state).Nuclear.Enabled and validId(state,execution.tileId)
    elseif weaponExecutions[execution.kind] then
        return Weapons.initExecution(state,execution,state.weaponApi)
    elseif execution.kind=="Nuke" or execution.kind=="MIRV" then
        return Nukes.initExecution(state,execution,state.nuclearApi)
    elseif execution.kind=="QuickChat" then
        QuickChat.initExecution(state,execution)
        return execution.active
    elseif Diplomacy.isExecution(execution.kind) then
        return Diplomacy.initExecution(state,execution) and execution.active~=false
    end
    return Economy.initExecution(state, execution)
end
local function tickExecutions(state: State, cooperate: (() -> ())?)
    Rails.install(state)
    Weapons.install(state)
    state.recordWeaponMessage=function(event) Simulation.recordWeaponMessage(state,event) end
    if not state.recordUnitDeath then state.recordUnitDeath=function(unit,sourceType) Simulation.recordUnitDeath(state,unit,sourceType) end end
    if not state.addTrainGold then state.addTrainGold = function(owner, amount, tile) Simulation.addBonusGold(state, owner, amount, tile) end end
    if not state.removeTrainUnit then state.removeTrainUnit = function(unit) Trains.deleteUnit(state, unit) end end
    if not state.trackWarshipUnit then state.trackWarshipUnit = function(unit)
        if unit.active ~= false and state.unitAcquisitionOrder[unit.id] == nil then
            state.unitAcquisitionOrder[unit.id] = state.nextUnitAcquisitionOrder
            state.nextUnitAcquisitionOrder += 1
        elseif unit.active == false then state.unitAcquisitionOrder[unit.id] = nil end
        Warships.trackUnit(state, unit)
    end end
    if not state.warshipApi then state.warshipApi = {
        friendly=function(a,b) return Diplomacy.friendly(state,a,b) end,
        canAttack=function(a,b,afk) return Simulation.canAttackPlayer(state,a,b,afk) end,
        message = function(event) table.insert(state.navalMessages, event) end,
        deadUnit = function(unit) Simulation.recordUnitDeath(state,unit) end,
    } end
    local kept = {}
    if not state.navalApi then state.navalApi = {
        friendly=function(a,b) return Diplomacy.friendly(state,a,b) end,
        canAttackPlayer=function(a,b) return Simulation.canAttackPlayer(state,a,b) end,
        rejectIncomingRequest=function(a,b) Simulation.rejectIncomingRequest(state,a,b) end,
        troopReserve=function(owner) return Simulation.troopReserve(state,owner) end,
        conquer = function(tile, owner) conquer(state, tile, owner) end,
        message = function(event) table.insert(state.navalMessages, event) end,
    } end
    if not state.tradeApi then state.tradeApi = {
        canTrade=function(a,b) return Diplomacy.canTrade(state,a,b) end,
        friendly=function(a,b) return Diplomacy.friendly(state,a,b) end,
        addGold = function(owner, amount, tile) Simulation.addBonusGold(state, owner, amount, tile) end,
        message = function(event) table.insert(state.navalMessages, event) end,
    } end
    -- Attack and retreat executions share creation order. In particular, an
    -- existing army ticks before the later execution ordering its retreat.
    for _, execution in state.executions do
        local ok, keep = pcall(tickOne, state, execution)
        if not ok then executionFault(state, "Tick", execution, keep)
        elseif keep then table.insert(kept, execution) end
        if cooperate then cooperate() end
    end
    state.executions = kept
    -- GameImpl.executeNextTick: active ticks, pending init, inactive removal.
    -- Bot decisions append behind player intents already queued for this tick.
    local pending = state.pendingExecutions
    state.pendingExecutions = {}
    for _, execution in pending do
        local ok, add = pcall(initOne, state, execution)
        if not ok then executionFault(state, "Init", execution, add)
        elseif add then table.insert(state.executions, execution) end
        if cooperate then cooperate() end
    end
    local active = {}
    for _, execution in state.executions do
        if execution.kind ~= "Attack" or execution.attack.active then table.insert(active, execution) end
    end
    state.executions = active
    pruneAttacks(state)
end
function Simulation.step(state: State, dt: number, cooperate: (() -> ())?)
    if state.phase == "Choosing" or not finite(dt) or dt <= 0 or dt > 1 then return end
    if state.tutorialStep then state.tutorialStep(state) end -- the tutorial's held-troops fact (TutorialProgress.troops)
    local nationApi = state.nationApi
    if not nationApi then
        nationApi = {
            queue = function(attacker, target, amount) return queueAttack(state, attacker, target, amount) end,
            capacity = function(player) return Simulation.capacity(state, player) end,
            neutral = function(player) return neutralBorder(state, player) end,
            nonFalloutNeutral = function(player) return Simulation.hasNonFalloutNeutralBorder(state,player) end,
            fallout = function(player) return Simulation.hasFalloutBorder(state,player) end,
            nearby = function(player) return Simulation.nearby(state, player) end,
            shares = function(player, other) return sharesBorder(state, player, other) end,
            hasStructures=function(owner) return #Simulation.ownedStructures(state,owner)>0 end,
            structuresFor=function(owner) return Simulation.ownedStructures(state,owner) end,
            canDelete=function(owner) return state.ticks-state.lastDeleteTicks[owner]>=GameConfig.forState(state).City.DeleteCooldownTicks end,
            deleteStructure=function(owner,unit)
                local kind=if unit.unitType=="Missile Silo" then "DeleteMissileSilo" elseif unit.unitType=="SAM Launcher" then "DeleteSAMLauncher"
                    elseif unit.unitType=="Factory" then "DeleteFactory" elseif unit.unitType=="Defense Post" then "DeleteDefensePost"
                    elseif unit.unitType=="Port" then "DeletePort" else "DeleteCity"
                table.insert(state.pendingExecutions,{kind=kind,owner=owner,unitId=unit.id})
            end,
            incomingRequests=function(owner) return Diplomacy.incomingRequests(state,owner) end,
            acceptRequest=function(request) Diplomacy.acceptRequest(state,request) end,
            rejectRequest=function(request) Diplomacy.rejectRequest(state,request) end,
            alliances=function(owner) return Diplomacy.alliances(state,owner) end,
            allies=function(owner) return Diplomacy.allies(state,owner) end,
            targets=function(owner) return Diplomacy.targets(state,owner) end,
            queueExtension=function(owner,target) table.insert(state.pendingExecutions,{kind="AllianceExtension",owner=owner,targetOwner=target}) end,
            queueAlliance=function(owner,target) table.insert(state.pendingExecutions,{kind="AllianceRequest",owner=owner,targetOwner=target}) end,
            canSendAlliance=function(a,b) return Diplomacy.canSendAllianceRequest(state,a,b) end,
            isAllied=function(a,b) return Diplomacy.allianceWith(state,a,b)~=nil end,
            breakAlliance=function(a,b) return Diplomacy.breakAlliance(state,a,b) end,
            isTraitor=function(owner) return Diplomacy.isTraitor(state,owner) end,
            friendly=function(a,b) return Diplomacy.friendly(state,a,b) end,
            sameTeam=function(a,b) return Diplomacy.sameTeam(state,a,b) end,
            relation=function(a,b) return Diplomacy.relation(state,a,b) end,
            relations=function(owner) return Diplomacy.relations(state,owner) end,
            updateRelation=function(a,b,delta) Diplomacy.updateRelation(state,a,b,delta) end,
            hasEmbargo=function(a,b) return Diplomacy.hasEmbargo(state,a,b) end,
            addEmbargo=function(a,b,temp) Diplomacy.addEmbargo(state,a,b,temp) end,
            stopEmbargo=function(a,b) Diplomacy.stopEmbargo(state,a,b) end,
            canSendEmoji=function(a,b) return Diplomacy.canSendEmoji(state,a,b) end,
            queueEmoji=function(a,b,index) table.insert(state.pendingExecutions,{kind="Emoji",owner=a,targetOwner=b,emoji=index}) end,
            canDonateTroops=function(a,b)return Diplomacy.canDonateTroops(state,a,b)end,
            queueDonation=function(a,b,amount)table.insert(state.pendingExecutions,{kind="DonateTroops",owner=a,targetOwner=b,amount=amount})end,
            spawnTicks=function() return GameConfig.forState(state).Diplomacy.SpawnPhaseTicks end,
            structures = function(player) return NationPortAI.handleStructures(state, player) end,
            warship = function(player) return NationWarshipAI.maybeSpawnWarship(state, player) end,
            neutralBoat = function(player) return NationNavalAI.sendNearbyNeutral(state, player,nationApi) end,
            boat = function(player, target) return NationNavalAI.sendBoatAttack(state, player, target, Simulation.capacity(state, player),nationApi) end,
            randomBoat = function(player, enemies) return NationNavalAI.attackWithRandomBoat(state, player, enemies,nationApi) end,
            -- PF043 tribe mercy: a tribe skips a send that the mercy window would refuse, and a boat landing inside a zone
            mercy = function(player, target) return if target == 0 then Simulation.mercyBlocksWild(state, player) else Simulation.mercyShield(state, player, target) end,
            mercyTile = function(player, tile) return Simulation.mercyTile(state, player, tile) end,
        }
        nationApi.beforeAttack=function(owner) NationDiplomacyAI.afterStructures(state,owner,nationApi) end
        nationApi.allianceRequests=function(owner,enemies) NationDiplomacyAI.maybeRequests(state,owner,enemies,nationApi) end
        nationApi.betray=function(owner,target,juiciest,friends,enemies) return NationDiplomacyAI.betray(state,owner,target,nationApi,juiciest,friends,enemies) end
        nationApi.attackEmoji=function(owner,target) NationEmojiAI.maybeSendAttack(state,owner,target,nationApi) end
        nationApi.assistEmoji=function(owner,target,kind) NationEmojiAI.send(state,owner,target,NationEmojiAI.Lists["Assist"..kind],nationApi) end
        nationApi.shouldAttack=function(owner,target) return NationAI.shouldAttack(state,owner,target,nationApi) end
        nationApi.nukeEmoji=function(owner,target) NationEmojiAI.maybeSend(state,owner,target,NationEmojiAI.Lists.Nuke,nationApi) end
        nationApi.maybeSendAttackEmoji=nationApi.attackEmoji
        nationApi.sendNukeEmoji=function(owner,_target) NationEmojiAI.send(state,owner,0,NationEmojiAI.Lists.Nuke,nationApi) end
        nationApi.respondToMIRV=function(owner,target) NationEmojiAI.respondToMIRV(state,state.nations[owner].random,target,nationApi) end
        state.nationApi = nationApi
    end
    state.accumulator += dt
    while state.accumulator + 1e-8 >= GameConfig.forState(state).Match.StepSeconds do
        state.accumulator = math.max(0, state.accumulator - GameConfig.forState(state).Match.StepSeconds)
        state.ticks += 1
        state.elapsed = (state.ticks - state.startTick) * GameConfig.forState(state).Match.StepSeconds
        -- NationExecution is installed before WinCheck and spawned PlayerExecution.
        for owner = 2, #state.players do
            if state.nations[owner] then
                NationWarshipAI.trackShipsAndRetaliate(state,owner,nationApi)
                local nation=state.nations[owner]
                local ordinary=nation.started and nation.enabled and state.counts[owner]>0
                    and state.ticks%nation.attackRate==nation.attackTick
                if ordinary then NationDiplomacyAI.beforeDecision(state,owner,nationApi);NationMIRVAI.considerMIRV(state,owner,nationApi) end
                NationAI.tick(state, owner, nationApi)
                if ordinary then NationWarshipAI.counterWarshipInfestation(state,owner,nationApi);NationNukeAI.maybeSendNuke(state,owner,nationApi) end
                if cooperate then cooperate() end
            end
        end
        -- Singleplayer GameRunner installs WinCheck before spawned player
        -- executions. The tribe already exists when the human picks a spawn.
        checkVictory(state)
        Doomsday.tick(state,state.gameConfig)
        -- GameRunner's global rail execution follows WinCheck and precedes
        -- spawned PlayerExecutions. Removals below rebuild on the next tick.
        Rails.recomputeClusters(state)
        for _, owner in state.executionOrder do
            if state.playerExecutionRemoved[owner]or state.playerInitTicks[owner]and state.ticks<=state.playerInitTicks[owner]then continue end
            Diplomacy.decayRelations(state,owner)
            local mixed = Simulation.ownedStructures(state, owner)
            Structures.captureOwned(state, owner, mixed)
            if state.counts[owner] <= 0 then
                Warships.playerDeath(state,owner,state.warshipApi);Diplomacy.playerDeath(state,owner)
                state.playerExecutionRemoved[owner]=true
            end
            Economy.playerTick(state, owner)
            Ports.playerTick(state, owner)
            Structures.playerTick(state, owner)
            -- captureOwned applies the original cross-type acquisition order
            -- before income/death handling; captured Defense Posts are removed.
            if state.counts[owner] > 0 then
                local growth = populationGrowth(state,owner)
                if growth < 0 then state.troops[owner] -= math.min(state.troops[owner], math.floor(-growth))
                else state.troops[owner] += math.floor(growth) end
                Diplomacy.playerTick(state,owner)
                if (state.ticks - state.lastClusterCalc[owner] > 20 or state.counts[owner] < 100)
                    and state.lastTileChange[owner] >= state.lastClusterCalc[owner] then
                    state.lastClusterCalc[owner] = state.ticks
                    -- PF044: a revived player's pocket isn't annexed by encirclement while its shield lasts
                    if not (state.revive and Simulation.reviveShielded(state, owner)) then Territory.update(state, owner, conquer, conquerPlayer) end
                end
            end
            TribeAI.tick(state,owner,nationApi)
            if cooperate then cooperate() end
        end
        if state.premium then state.premium.tick(state) end -- PF044 Arsenal buildings (PremiumItems; nil unless a human owns one)
        if state.oilRigs then state.oilRigs.tick(state) end -- PF045 Oil Rigs (sim only; nil unless enabled)
        tickExecutions(state, cooperate)
        local spawns=state.spawnPhasePending;state.spawnPhasePending={}
        for _,spawn in spawns do applyNationSpawn(state,spawn.owner,spawn.tile)end
        -- PF044: state.reviveHold (MatchService, Solo) keeps an eliminated owner 1's match open while its Revive offer runs
        if state.counts[1] == 0 and state.gameType~="Public" and not state.reviveHold then state.phase = "Lost" end
        for owner = 1, #state.players do Collections.compact(state.borders[owner]) Collections.compact(state.territories[owner]) end
        -- GameImpl flushes water after all executions and player updates.
        if state.waterManager then
            local water=Water.tick(state)
            for _,tile in water.converted do state.owners[tile]=-1;state.changedOwners[tile]=-1 end
            for _,tile in water.changedTerrain do state.changedTerrainIds[tile]=true end
        end
    end
end
-- Private practice matches have one receiving player. Keep64 delivered events
-- for resync deduplication, plus every unsent event regardless of batch size.
-- Called only after FireClient; snapshot/Ready reads never consume events.
function Simulation.acknowledgeConquestEvents(state: State, throughId: number)
    local delivered = 0
    for _, event in state.conquestEvents do
        if event.id > throughId then break end
        delivered += 1
    end
    local discard = delivered - 64
    if discard <= 0 then return end
    local kept = table.create(#state.conquestEvents - discard)
    for index = discard + 1, #state.conquestEvents do table.insert(kept, state.conquestEvents[index]) end
    state.conquestEvents = kept
end
function Simulation.acknowledgeBonusEvents(state: State, throughId: number)
    local delivered = 0
    for _, event in state.bonusEvents do
        if event.id > throughId then break end
        delivered += 1
    end
    local discard = delivered - 64
    if discard <= 0 then return end
    local kept = table.create(#state.bonusEvents - discard)
    for index = discard + 1, #state.bonusEvents do table.insert(kept, state.bonusEvents[index]) end
    state.bonusEvents = kept
end
function Simulation.acknowledgeDeadUnitEvents(state: State, throughId: number)
    local delivered = 0
    for _, event in state.deadUnitEvents do
        if event.eventId > throughId then break end
        delivered += 1
    end
    local discard = delivered - 64
    if discard <= 0 then return end
    local kept = table.create(#state.deadUnitEvents - discard)
    for index = discard + 1, #state.deadUnitEvents do table.insert(kept, state.deadUnitEvents[index]) end
    state.deadUnitEvents = kept
end
-- The viewer's shore border tiles (border tiles that are land next to water), in border order: snapshot.shoreBorders[1].
-- PF032: PublicMatchRuntime builds it per recipient when the rest of a publish is shared.
function Simulation.shoreBorders(state: State, viewer: number): { number }
    local shores = {}
    for _, tile in state.borders[viewer].values do
        if tile ~= 0 and bit32.band(buffer.readu8(state.map.terrain, tile - 1), 192) == 192 then
            table.insert(shores, tile)
        end
    end
    return shores
end
function Simulation.snapshot(state: State, includeMap: boolean?, includeOwners: boolean?,viewer: number?): any
    local localOwner=viewer or 1
    local attacks = {}
    for _, attack in state.attacks do
        if attack.active then table.insert(attacks, {
            id = attack.id, owner = attack.owner, targetOwner = attack.targetOwner, budget = attack.budget,
            retreating = attack.retreating, sourceTile = attack.sourceTile,positions=AttackPositions.forAttack(state.map,attack),
        }) end
    end
    local snapshot: any = {
        troops = table.clone(state.troops), counts = table.clone(state.counts), phase = state.phase,
        elapsed = state.elapsed, ticks = state.ticks, startTick=state.startTick, attacks = attacks, seed = state.seed,
        winner = state.winner,winnerTeam=state.winnerTeam,gameConfig=MatchMetadata.copyConfig(state.gameConfig),mapType=state.map.mapType,mapSize=state.map.mapSize,teams=table.clone(state.teams or {}),doomsday=state.doomsday and {active=state.doomsday.active}, names = table.clone(state.names), players = {}, playerOrder = table.clone(state.playerOrder),
        largestClusterBounds = table.create(#state.players, false), caps = {}, troopRates = {},
        gold = table.clone(state.gold), goldEarned = table.clone(state.goldEarned), goldRates = {}, cityConstructed = table.clone(state.cityConstructed),
        lastDeleteTicks = table.clone(state.lastDeleteTicks), cities = {},
        conquestEvents = {}, conquestEventCursor = state.nextConquestEventId - 1,
        ships = {}, shoreBorders = { [1] = {} }, ports = {}, tradeShips = {},
        portConstructed = table.clone(state.portConstructed), tradeGold = table.clone(state.tradeGold), piracyGold = table.clone(state.piracyGold),
        bonusEvents = {}, bonusEventCursor = state.nextBonusEventId - 1,
        warships = {}, shells = {}, warshipConstructed = table.clone(state.warshipConstructed),
        deadUnitEvents = {}, deadUnitEventCursor = state.nextDeadUnitEventId - 1,
        factories = {}, defensePosts = {}, factoryConstructed = table.clone(state.factoryConstructed),
        defensePostConstructed = table.clone(state.defensePostConstructed), trainGold = table.clone(state.trainGold),
        missileSiloConstructed=table.clone(state.missileSiloConstructed), samLauncherConstructed=table.clone(state.samLauncherConstructed),
        falloutTiles=table.clone(state.falloutTiles), falloutCount=state.falloutCount, weaponMessages={}, weaponMessageCursor=state.nextWeaponMessageId-1,
        landCount=state.map.landCount,waterVersion=state.map.waterVersion or 0,waterGraphVersion=state.map.waterGraphVersion or 0,
    }
    local completedLevels={}
    for _,city in state.cities do if not city.underConstruction then
        completedLevels[city.owner]=(completedLevels[city.owner] or 0)+city.level
    end end
    for owner = 1, #state.players do
        local player = table.clone(state.players[owner])
        player.spawnTile, player.alive = state.spawnTiles[owner], state.counts[owner] > 0
        snapshot.players[owner], snapshot.caps[owner], snapshot.troopRates[owner] = player,
            Simulation.capacity(state, owner,completedLevels[owner] or 0), Simulation.troopRate(state, owner,completedLevels[owner] or 0)
        snapshot.goldRates[owner] = Simulation.goldRate(state, owner)
        local bounds = state.largestClusterBounds[owner]
        if bounds then snapshot.largestClusterBounds[owner] = { min = table.clone(bounds.min), max = table.clone(bounds.max) } end
    end
    local ownershipOrder = {}
    local orderedStructures = table.clone(state.cities)
    for _, port in state.ports do table.insert(orderedStructures, port) end
    for _, unit in state.factories do table.insert(orderedStructures, unit) end
    for _, unit in state.defensePosts do table.insert(orderedStructures, unit) end
    for _, unit in state.missileSilos do table.insert(orderedStructures,unit) end
    for _, unit in state.samLaunchers do table.insert(orderedStructures,unit) end
    table.sort(orderedStructures, function(a, b)
        return (state.unitAcquisitionOrder[a.id] or a.id) < (state.unitAcquisitionOrder[b.id] or b.id)
    end)
    local ownerCounts = {}
    for _, unit in orderedStructures do
        local count = (ownerCounts[unit.owner] or 0) + 1
        ownerCounts[unit.owner], ownershipOrder[unit.id] = count, count
    end
    for _, city in state.cities do
        local publicCity = {id=city.id,owner=city.owner,tileId=city.tileId,level=city.level,underConstruction=city.underConstruction,
            createdTick=city.createdTick,deletionMarkedTick=city.deletionMarkedTick,unitType="City",active=city.active~=false,
            hasTrainStation=city.hasTrainStation==true}
        -- PlayerImpl._units preserves creation order and appends captured units.
        -- UI nearest-deletion ties use this owner-local order, not the global ID.
        publicCity.ownershipOrder = ownershipOrder[city.id]
        table.insert(snapshot.cities, publicCity)
    end
    for _, port in state.ports do
        if port.active == false then continue end -- PF035: never on the wire (the codec rejects it: the whole match would freeze)
        local publicPort = {id=port.id,owner=port.owner,tileId=port.tileId,level=port.level,underConstruction=port.underConstruction,
            createdTick=port.createdTick,deletionMarkedTick=port.deletionMarkedTick,active=port.active~=false,
            hasTrainStation=port.hasTrainStation==true}
        publicPort.unitType = "Port"
        publicPort.ownershipOrder = ownershipOrder[port.id]
        table.insert(snapshot.ports, publicPort)
    end
    for _, event in state.conquestEvents do table.insert(snapshot.conquestEvents, table.clone(event)) end
    for _, event in state.bonusEvents do table.insert(snapshot.bonusEvents, table.clone(event)) end
    for _, event in state.deadUnitEvents do table.insert(snapshot.deadUnitEvents, table.clone(event)) end
    for _, unit in state.warships do
        local public = {id = unit.id, owner = unit.owner, unitType = "Warship", tileId = unit.tileId,
            lastTileId = unit.lastTileId, active = unit.active, health = unit.health, createdTick = unit.createdTick,
            targetTileId = unit.targetTileId, targetUnitId = unit.targetUnitId, patrolTile = unit.patrolTile,
            retreatPort = unit.retreatPort, lastCombatTick = unit.lastCombatTick,
            veterancy = unit.veterancy, veterancyProgress = unit.veterancyProgress, state = unit.state,
            warshipState = Warships.warshipState(state, unit), motionPlan = unit.motionPlan}
        table.insert(snapshot.warships, public)
    end
    for _, unit in state.shells do
        table.insert(snapshot.shells, {id = unit.id, owner = unit.owner, unitType = "Shell", tileId = unit.tileId,
            lastTileId = unit.lastTileId, active = unit.active, createdTick = unit.createdTick,
            reachedTarget = unit.reachedTarget == true})
    end
    for _, pair in {{state.factories, "Factory", snapshot.factories}, {state.defensePosts, "Defense Post", snapshot.defensePosts}} do
        for _, unit in pair[1] do
            if unit.active == false then continue end -- PF035: never on the wire (the codec rejects it: the whole match would freeze)
            table.insert(pair[3], {id = unit.id, owner = unit.owner, tileId = unit.tileId, level = unit.level,
                active = unit.active, underConstruction = unit.underConstruction, createdTick = unit.createdTick,
                deletionMarkedTick = unit.deletionMarkedTick, unitType = pair[2], hasTrainStation = unit.hasTrainStation == true,
                ownershipOrder = ownershipOrder[unit.id]})
        end
    end
    local weaponSnapshot=Weapons.snapshot(state,ownershipOrder)
    snapshot.missileSilos,snapshot.samLaunchers,snapshot.samMissiles=weaponSnapshot.missileSilos,weaponSnapshot.samLaunchers,weaponSnapshot.samMissiles
    snapshot.nukes=Nukes.snapshot(state)
    snapshot.mirvsLaunched=state.mirvsLaunched or 0
    local diplomacySnapshot=Diplomacy.snapshot(state,false)
    snapshot.diplomacy,snapshot.alliances,snapshot.diplomacyRequests=diplomacySnapshot.diplomacy,diplomacySnapshot.alliances,diplomacySnapshot.diplomacyRequests
    snapshot.quickChat=QuickChat.snapshot(state)
    snapshot.diplomacyEvents,snapshot.diplomacyEventCursor={},state.nextDiplomacyEventId-1
    for _,event in state.diplomacyEvents do table.insert(snapshot.diplomacyEvents,Simulation.copyDiplomacyEvent(event)) end
    for _,event in state.weaponMessages do table.insert(snapshot.weaponMessages,table.clone(event)) end
    snapshot.stations, snapshot.railroads = Rails.snapshot(state)
    snapshot.trains = Trains.snapshot(state)
    for _, ship in state.ships do
        -- Motion plans are immutable and replaced only when their route changes.
        table.insert(snapshot.ships, {id=ship.id,owner=ship.owner,tileId=ship.tileId,lastTileId=ship.lastTileId,
            targetTileId=ship.targetTileId,originalTargetOwner=ship.originalTargetOwner,troops=ship.troops,
            isRetreating=ship.isRetreating,active=ship.active,createdTick=ship.createdTick,motionPlan=ship.motionPlan})
    end
    for _, ship in state.tradeShips do
        table.insert(snapshot.tradeShips, {id=ship.id,owner=ship.owner,unitType="Trade Ship",tileId=ship.tileId,
            lastTileId=ship.lastTileId,sourcePortId=ship.sourcePortId,targetPortId=ship.targetPortId,
            targetTileId=ship.targetTileId,originalOwner=ship.originalOwner,active=ship.active,
            createdTick=ship.createdTick,lastSetSafeFromPirates=ship.lastSetSafeFromPirates,motionPlan=ship.motionPlan})
    end
    snapshot.shoreBorders[1] = Simulation.shoreBorders(state, localOwner)
    if includeOwners ~= false then snapshot.owners = table.clone(state.owners) end
    if includeMap ~= false then
        snapshot.map = table.clone(state.map)
        snapshot.map.navigationRuntime=nil
        snapshot.map.land = table.clone(state.map.land)
        local terrain = buffer.create(buffer.len(state.map.terrain))
        buffer.copy(terrain, 0, state.map.terrain)
        snapshot.map.terrain = terrain
    end
    return snapshot
end

return table.freeze(Simulation)
