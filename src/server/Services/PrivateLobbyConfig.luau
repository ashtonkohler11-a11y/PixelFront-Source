--!strict
-- PF019 W6: the custom-lobby settings boundary (LobbyContract §5 schema).
-- Clients send W4 settings, never a runtime config. Every key is validated
-- here; unknown keys, wrong types and out-of-range values are rejected, and
-- only bounded, known structures are read (no deep traversal of client tables).
-- Returns (config, nil, settings): the runtime config plus the normalized
-- settings echoed to every member's RoomView.
local Shared = game:GetService("ReplicatedStorage").Shared
local Lobby = require(Shared.OpenFrontLobbySettings)
local Availability = require(Shared.OpenFrontMatchAvailability)
local PublicGameConfig = require(Shared.PublicGameConfig)
local Contract = require(Shared.LobbyContract)

local PrivateConfig = {}
local groupSizes = table.freeze({ Duos = 2, Trios = 3, Quads = 4 })
local groupNames = table.freeze({ [2] = "Duos", [3] = "Trios", [4] = "Quads" })
local toggles = table.freeze({ "infiniteGold", "infiniteTroops", "instantBuild", "randomSpawn", "donateGold", "donateTroops" })

local function integer(value: any, minimum: number, maximum: number): boolean
    return type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value % 1 == 0
end
local function number(value: any, minimum: number, maximum: number): boolean
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end
local function plain(value: any): boolean
    return type(value) == "table" and getmetatable(value) == nil
end

local function normalizeTeams(capacity: number, teams: any): (number, any)
    if teams == "Humans Vs Nations" then
        -- maxPlayers is human admission capacity, not humans plus nations.
        return math.min(capacity, Availability.MaxNations), teams
    end
    local group = groupSizes[teams]
    if group then
        group = math.min(group, math.floor(capacity / 2))
        if group >= 2 then return capacity - capacity % group, groupNames[group] end
        return 2, 2 -- A two- or three-seat host can still run two one-human teams.
    end
    local count = math.min(teams, math.max(2, math.floor(capacity / 2)))
    return capacity - capacity % count, count
end

-- hostPlus: the host owns Lobby Host+ (PF020 G8). Without it maxPlayers caps at HostPlus.freeMaxPlayers
-- and the Host+ keys are refused; with it the cap is the server's.
function PrivateConfig.sanitize(input: any?, maxPlayers: number, hostPlus: boolean?): (any?, string?, any?)
    if not integer(maxPlayers, 2, 4095) then
        return nil, "Custom lobbies are unavailable on this server."
    end
    if input ~= nil and not plain(input) then
        return nil, "Invalid lobby settings."
    end
    -- Retired keys (Contract.RetiredSettingKeys) are ignored, never rejected: old saved presets still load.
    local fields = {}
    for key, value in input or {} do
        if not (type(key) == "string" and Contract.RetiredSettingKeys[key]) then fields[key] = value end
    end
    for key, value in fields do
        local kind = type(key) == "string" and Contract.SettingKeys[key]
        if not kind then return nil, "Unsupported lobby setting." end
        if type(value) == "table" and kind ~= "units" and kind ~= "premium" and kind ~= "clock" and kind ~= "overtime" and kind ~= "colors" then
            return nil, "Unsupported lobby setting."
        end
    end
    if hostPlus ~= true then
        for _, key in Contract.HostPlus.keys do
            if fields[key] ~= nil then return nil, Contract.Errors.HostPlus end
        end
    end
    local config = Lobby.availableConfig()
    if fields.gameMap ~= nil then
        if type(fields.gameMap) ~= "string" or not Availability.MapTypes[fields.gameMap] then
            return nil, "Choose Qing China, United States, or Africa."
        end
        config.gameMap = fields.gameMap
    end
    config.difficulty = "Medium"
    if fields.difficulty ~= nil then
        if not table.find(Lobby.Difficulties, fields.difficulty) then return nil, "Invalid difficulty." end
        config.difficulty = fields.difficulty
    end
    if fields.gameMode ~= nil then
        if fields.gameMode ~= "Free For All" and fields.gameMode ~= "Team" then return nil, "Invalid game mode." end
        config.gameMode = fields.gameMode
    end
    if fields.playerTeams ~= nil then
        if not table.find(Lobby.TeamOptions, fields.playerTeams) then return nil, "Invalid team arrangement." end
        config.playerTeams = fields.playerTeams
    end
    local isTeam = config.gameMode == "Team"
    local serverLimit = math.min(maxPlayers, Contract.Limits.maxPlayers)
    local limit = if hostPlus == true then serverLimit else math.min(serverLimit, Contract.HostPlus.freeMaxPlayers)
    local defaultCapacity = if isTeam then (if config.gameMap == "Africa" then 6 else 4)
        else (if config.gameMap == "Africa" then 12 else 10)
    config.maxPlayers = math.min(defaultCapacity, limit)
    if fields.maxPlayers ~= nil then
        if hostPlus ~= true and integer(fields.maxPlayers, limit + 1, serverLimit) then
            return nil, "More than " .. Contract.HostPlus.freeMaxPlayers .. " players needs Lobby Host+."
        end
        if not integer(fields.maxPlayers, Contract.Limits.minPlayers, limit) then return nil, "Invalid player capacity for this server." end
        config.maxPlayers = fields.maxPlayers
    end
    if isTeam then
        config.maxPlayers, config.playerTeams = normalizeTeams(config.maxPlayers, config.playerTeams)
    else
        config.playerTeams = 2
    end
    config.bots = 25
    if fields.bots ~= nil then
        if not integer(fields.bots, 0, Availability.MaxTribes) then return nil, "Choose between 0 and 50 tribes." end
        config.bots = fields.bots
    end
    local humansVsNations = isTeam and config.playerTeams == "Humans Vs Nations"
    local nations = Availability.defaultNations(config.gameMap)
    if fields.nations ~= nil then
        if not integer(fields.nations, 0, Availability.MaxNations) then return nil, "Choose between 0 and 25 nations." end
        nations = fields.nations
    end
    -- Humans Vs Nations always fields one nation per admitted human.
    if humansVsNations then nations = config.maxPlayers end
    config.nations = if humansVsNations then "default" elseif nations == 0 then "disabled" else nations

    local disabled = {}
    if fields.disabledUnits ~= nil then
        local list = fields.disabledUnits
        if not plain(list) then return nil, "Invalid weapon bans." end
        local count = 0
        for index, unit in list do
            count += 1
            if count > #Lobby.UnitOptions or type(index) ~= "number" or index % 1 ~= 0 or index < 1
                or type(unit) ~= "string" or not table.find(Lobby.UnitOptions, unit) then
                return nil, "Invalid weapon bans."
            end
        end
        if count ~= #list then return nil, "Invalid weapon bans." end
        -- Canonical order and no duplicates, whatever order the client used.
        for _, unit in Lobby.UnitOptions do if table.find(list, unit) then table.insert(disabled, unit) end end
    end
    config.disabledUnits = disabled

    -- Premium item bans (Arsenal ids; PF - 2's PremiumItems refuses a banned one in the match). Same rules as the weapon
    -- bans: a dense list of known ids, stored in the catalogue's shelf order without duplicates; absent from the config when none.
    local premium = {}
    if fields.disabledPremium ~= nil then
        local list = fields.disabledPremium
        if not plain(list) then return nil, "Invalid premium bans." end
        local count = 0
        for index, id in list do
            count += 1
            if count > #Contract.Premium or type(index) ~= "number" or index % 1 ~= 0 or index < 1
                or type(id) ~= "string" or not table.find(Contract.Premium, id) then
                return nil, "Invalid premium bans."
            end
        end
        if count ~= #list then return nil, "Invalid premium bans." end
        for _, id in Contract.Premium do if table.find(list, id) then table.insert(premium, id) end end
    end
    config.disabledPremium = if #premium > 0 then premium else nil

    for _, key in toggles do
        local value = fields[key]
        if value ~= nil and type(value) ~= "boolean" then return nil, "Invalid lobby setting." end
        config[key] = if value == nil then (if key == "donateGold" or key == "donateTroops" then isTeam else false) else value
    end
    if fields.startingGold ~= nil then
        if not integer(fields.startingGold, 0, 1000000000) then return nil, "Starting gold must be 0 to 1,000,000,000." end
        config.startingGold = fields.startingGold
    end
    if fields.goldMultiplier ~= nil then
        if not number(fields.goldMultiplier, 0.1, 1000) then return nil, "Gold income must be ×0.1 to ×1000." end
        config.goldMultiplier = fields.goldMultiplier
    end
    if fields.maxTimerValue ~= nil then
        if not integer(fields.maxTimerValue, 1, 120) then return nil, "The time limit must be 1 to 120 minutes." end
        config.maxTimerValue = fields.maxTimerValue
    end
    if fields.customAllianceDuration ~= nil then
        if not integer(fields.customAllianceDuration, 0, 15) then return nil, "Alliance length must be 0 to 15 minutes." end
        config.customAllianceDuration = fields.customAllianceDuration
    end
    if fields.doomsdayClock ~= nil then
        local clock = fields.doomsdayClock
        if not plain(clock) then return nil, "Invalid doomsday clock." end
        for key, value in clock do
            if key == "enabled" then
                if value ~= true then return nil, "Invalid doomsday clock." end
            elseif key ~= "speed" or not table.find(Lobby.ClockSpeeds, value) then
                return nil, "Invalid doomsday clock."
            end
        end
        if clock.speed == nil then return nil, "Choose a doomsday clock speed." end
        config.doomsdayClock = { enabled = true, speed = clock.speed }
    end
    if fields.overtime ~= nil then
        local overtime = fields.overtime
        if not plain(overtime) then return nil, "Invalid overtime." end
        for key, value in overtime do
            if key == "enabled" then
                if value ~= true then return nil, "Invalid overtime." end
            elseif key ~= "startMinutes" or not integer(value, 1, 120) then
                return nil, "Overtime must start at 1 to 120 minutes."
            end
        end
        if overtime.startMinutes == nil then return nil, "Overtime must start at 1 to 120 minutes." end
        config.overtime = { enabled = true, startMinutes = overtime.startMinutes }
    end

    -- PF020 G8 Lobby Host+ settings (hostPlus was checked above).
    local spectators: number? = nil
    if fields.spectators ~= nil then
        if not integer(fields.spectators, 1, Contract.HostPlus.spectatorsMax) then
            return nil, "Spectator seats must be 1 to " .. Contract.HostPlus.spectatorsMax .. "."
        end
        -- Spectators are Roblox players on the match server too.
        if config.maxPlayers + fields.spectators > maxPlayers then return nil, "This server has no room for that many spectators." end
        spectators = fields.spectators
    end
    local peaceMinutes: number? = nil
    if fields.peaceMinutes ~= nil then
        if not integer(fields.peaceMinutes, 1, Contract.HostPlus.peaceMinutesMax) then
            return nil, "The peace timer must be 1 to " .. Contract.HostPlus.peaceMinutesMax .. " minutes."
        end
        peaceMinutes = fields.peaceMinutes
        -- The runtime's spawn immunity (the public "Peace time" mechanism): 10 ticks per second.
        config.spawnImmunityDuration = fields.peaceMinutes * 600
    end
    local teamColors: {string}? = nil
    if fields.teamColors ~= nil then
        local list = fields.teamColors
        if not plain(list) then return nil, "Invalid team colours." end
        local n, seen = 0, {}
        for index, id in list do
            n += 1
            if n > Contract.HostPlus.teamColorSlots or type(index) ~= "number" or index % 1 ~= 0 or index < 1
                or not Contract.teamColor(id) or seen[id] then
                return nil, "Invalid team colours."
            end
            seen[id] = true
        end
        if n == 0 or n ~= #list then return nil, "Invalid team colours." end
        teamColors = table.clone(list)
        -- Applied in Team mode only; kept in the settings so switching modes keeps the choice.
        if isTeam then
            local hexes = {}
            for _, id in list do table.insert(hexes, (Contract.teamColor(id) :: any).hex) end
            config.teamColors = hexes
        end
    end

    config.gameType = "Public"
    config.gameMapSize = Availability.MapSize
    config.waterNukes = nil
    if not PublicGameConfig.validate(config, Availability.MapTypes) or not Availability.supports(config) then
        return nil, "Unsupported lobby settings."
    end
    local settings = {
        gameMap = config.gameMap, gameMode = config.gameMode, playerTeams = config.playerTeams,
        difficulty = config.difficulty, maxPlayers = config.maxPlayers, nations = nations, bots = config.bots,
        disabledUnits = table.clone(disabled),
        disabledPremium = table.clone(premium),
        startingGold = config.startingGold, goldMultiplier = config.goldMultiplier, maxTimerValue = config.maxTimerValue,
        customAllianceDuration = config.customAllianceDuration,
        doomsdayClock = if config.doomsdayClock then { speed = config.doomsdayClock.speed } else nil,
        overtime = if config.overtime then { startMinutes = config.overtime.startMinutes } else nil,
        teamColors = teamColors, peaceMinutes = peaceMinutes,
        spectators = spectators,
    }
    for _, key in toggles do settings[key] = config[key] end
    return config, nil, settings
end

return table.freeze(PrivateConfig)
