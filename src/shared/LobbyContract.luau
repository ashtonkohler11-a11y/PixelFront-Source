--!strict
-- PF019 W6 global lobby contract (v1.1). Shared by GlobalLobbyService (server),
-- PublicLobbyController (client facade) and the Create/Join/waiting-room UIs.
-- Prose version: docs/director/handoffs/PF-019-W6-lobby-contract.md.
local Availability = require(script.Parent.OpenFrontMatchAvailability)
local Lobby = require(script.Parent.OpenFrontLobbySettings)

local Contract = {}
Contract.Version = "w6-1"

-- Client -> server (OpenFrontRemotes.LobbyCommand). UIs never fire these
-- directly; they call the PublicLobbyController facade.
Contract.Commands = table.freeze({
    Refresh = "Refresh",         -- {}  -> Lobbies
    JoinPublic = "JoinPublic",   -- {attempt,id}  public match room (deferred, you stay in your hub)
    CreateLobby = "CreateLobby", -- {attempt,settings,visibility,name?}
    JoinLobby = "JoinLobby",     -- {attempt,id}  a Public custom lobby from the directory
    JoinCode = "JoinCode",       -- {attempt,code}  any custom lobby by its 6-character code
    UpdateLobby = "UpdateLobby", -- {attempt,settings?,visibility?,name?}  host only, live
    StartLobby = "StartLobby",   -- {attempt}  host only
    LeaveLobby = "LeaveLobby",   -- {attempt}  host leaving closes the room for everyone
    LockLobby = "LockLobby",     -- {attempt,locked}  host with Lobby Host+ only (PF020 G8)
    KickMember = "KickMember",   -- {attempt,userId}  host with Lobby Host+ only; they can't rejoin (PF020 G8)
    Cancel = "Cancel",           -- {attempt}  abandon a pending request
    Return = "Return",           -- {}  match server only: back to a hub
    -- PF036 parties (up to Limits.partyMax; the leader queues, everyone takes a seat in the same public match)
    PartyOpen = "PartyOpen",     -- {}  your party (made on first open) -> Party
    PartyJoin = "PartyJoin",     -- {code}  a friend's party by its 5-character code (you leave yours)
    PartyLeave = "PartyLeave",   -- {}  the next seat becomes leader
    PartyKick = "PartyKick",     -- {userId}  leader only
    PartyInvited = "PartyInvited", -- {userIds}  after the Roblox invite prompt: friends on a hub get a notice
    Rejoin = "Rejoin",           -- {}  PF036: back into the match you dropped out of (inside Limits.rejoinWindow)
    GoNow = "GoNow",             -- {}  PF043: a public match's countdown ("Match found · joining 3"): teleport this player now
})

-- Server -> client (OpenFrontRemotes.LobbyState). Every packet carries serverNow.
Contract.Packets = table.freeze({
    Lobbies = "Lobbies",         -- {queues={ffa,team,special}, rooms={RoomSummary}}
    Room = "Room",               -- {attempt, room=RoomView}  your room changed
    RoomEvent = "RoomEvent",     -- {roomId, event, userId?, name?, changed?, at}
    RoomClosed = "RoomClosed",   -- {roomId, reason, message}
    Transfer = "Transfer",       -- {roomId, phase, teleportAt?, message?}
    LobbyError = "LobbyError",   -- {attempt, operation, code, message}
    Unavailable = "Unavailable", -- {message}  global lobbies offline (Studio uses the local store instead)
    Waiting = "Waiting",         -- match server only, during the arrival window (legacy shape)
    Party = "Party",             -- {party=PartyView?}  your party changed (nil: not in one)
    PartyInvite = "PartyInvite", -- {from={userId,name}, code, size}  a friend invited you
    Rejoin = "Rejoin",           -- {rejoin={untilAt, map, mode, kind}?}  PF036: a match you dropped out of is still going (nil: none)
})

Contract.Status = table.freeze({ Waiting = "Waiting", Starting = "Starting", Running = "Running", Closed = "Closed" })
Contract.Visibility = table.freeze({ Public = "Public", Private = "Private" })
-- Solo/Tutorial: a one-player match the hub starts on its own reserved server (matches never run on a hub).
Contract.Kinds = table.freeze({ Custom = "custom", Public = "public", Solo = "solo", Tutorial = "tutorial" })
Contract.Events = table.freeze({
    Joined = "Joined", Left = "Left", HostLeft = "HostLeft", Updated = "Updated", Starting = "Starting", Closed = "Closed",
    Kicked = "Kicked", -- PF020 G8: the host removed someone (everyone's Activity shows a short note)
})
Contract.CloseReasons = table.freeze({
    HostLeft = "HostLeft", Left = "Left", Expired = "Expired", StartFailed = "StartFailed", Started = "Started", Kicked = "Kicked",
})
Contract.TransferPhases = table.freeze({
    Countdown = "Countdown", Teleporting = "Teleporting", Retrying = "Retrying", Failed = "Failed",
})

-- Error codes with the default player-facing message. UIs may show `message` as is.
Contract.Errors = table.freeze({
    RateLimited = "Please wait a moment and try again.",
    StoreBusy = "Lobbies are busy right now. Try again in a moment.",
    Full = "That lobby is full.",
    NotFound = "That lobby is no longer available.",
    BadCode = "Enter the six-character lobby code.",
    Closed = "That lobby has closed.",
    Started = "That match has already started.",
    NotHost = "Only the host can do that.",
    InvalidSettings = "Some settings are not available. Check them and try again.",
    NameRejected = "That lobby name can't be used. Try another or leave it blank.",
    AlreadyInRoom = "Leave your current lobby first.",
    TeleportFailed = "The teleport failed. You are still in the lobby.",
    MatchFailed = "Your match couldn't start. You are still in the lobby. Try again.",
    Locked = "That lobby is locked. Ask the host for its code.",
    Kicked = "The host removed you from that lobby.",
    HostPlus = "That needs Lobby Host+.",
    PartyFull = "That party is full.",
    PartyNotFound = "That party is no longer available.",
    PartyCode = "Enter the five-character party code.",
    LeaderPicks = "Your party leader picks the match.",
    PartySeats = "There aren't enough seats for your party in that match.",
    NotLeader = "Only the party leader can do that.",
    RejoinGone = "That match has ended.",
    Unknown = "Something went wrong. Try again.",
})

Contract.Limits = table.freeze({
    nameMax = 32,                    -- characters, filtered by TextService
    codeLength = 6,
    codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
    minPlayers = 2,
    maxPlayers = 60,                 -- also capped by the server's Players.MaxPlayers
    maxNations = Availability.MaxNations,
    maxTribes = Availability.MaxTribes,
    startCountdown = 3,              -- seconds of 3-2-1 on every member's hub before the group teleport
    fullStart = 5,                   -- seconds from the last player seat filling to the teleport (custom lobbies; never extended)
    publicFullStart = 0,             -- PF044 (Ashton: "full = quick start"): a full public room teleports at once (teleportAt = now + 1)
    arrivalWindow = 30,              -- seconds the match server waits for teleported members
    hostedArrival = 60,              -- seconds a Solo/Tutorial ticket stays valid (one player, teleport retries)
    leaseSeconds = 30,               -- member presence lease; renewed by their hub
    renewSeconds = 10,
    roomMaxAge = 1800,               -- an unstarted custom room closes after 30 minutes
    refreshSeconds = 5,              -- directory/queue cache per hub
    eventHistory = 20,               -- RoomEvents kept in the client model
    partyMax = 4,                    -- PF036: seats in a party
    partyCodeLength = 5,             -- PF036: party codes (lobby codes are 6, so one code box takes both)
    partyLease = 45,                 -- PF036: party seat lease; renewed by the member's hub every renewSeconds
    partyAway = 1800,                -- PF036: a member who teleported to a match keeps the seat this long
    partyTTL = 2100,                 -- PF036: the party record (refreshed on every write; > partyAway)
    rejoinWindow = 300,              -- PF036: a dropped player's nation waits this long for them
})

-- Per-command minimum spacing (seconds), enforced on the server.
Contract.RateLimits = table.freeze({
    Refresh = 3, JoinPublic = 3, CreateLobby = 15, JoinLobby = 3, JoinCode = 3,
    UpdateLobby = 1, StartLobby = 3, LeaveLobby = 2, Cancel = 1, Return = 3, LockLobby = 1, KickMember = 1,
    PartyOpen = 1, PartyJoin = 2, PartyLeave = 1, PartyKick = 1, PartyInvited = 5, Rejoin = 3, -- PF036
    GoNow = 1, -- PF043
})

-- PF020 G8 Lobby Host+ (pass_lobby_host_plus; ownership = the Game Pass OR profile-owned, replicated as
-- the OpenFrontHostPlus attribute). Without it a host keeps every standard setting with up to 12 players.
Contract.HostPlus = table.freeze({
    pass = "pass_lobby_host_plus",
    freeMaxPlayers = 12,     -- the most without the pass; with it, the server max (Limits.maxPlayers)
    peaceMinutesMax = 10,    -- the peace timer, whole minutes
    spectatorsMax = 8,       -- spectator seats; players + spectators must fit the server
    teamColorSlots = 4,      -- Team 1-4 colours (later teams keep the default palette)
    keys = table.freeze({ "teamColors", "peaceMinutes", "spectators" }),
})
-- Retired setting keys: dropped wherever settings are read, never rejected, so old saved presets and stored rooms
-- still load. autoStart: the Host+ "auto-start when full" perk, retired 2026-10-07 when every lobby began starting
-- Limits.fullStart seconds after its last player seat fills (Ashton: "Remove it").
Contract.RetiredSettingKeys = table.freeze({ autoStart = true })
-- Readable team colours (Ashton: readable only). Ids are what the client sends; the match gets the hex.
-- The mockup's last swatch was ivory; pale land reads like the white tribes, so it is lime here.
Contract.TeamPalette = table.freeze({
    table.freeze({ id = "crimson", name = "Crimson", hex = "#d94f5c" }),
    table.freeze({ id = "ember", name = "Ember", hex = "#e07a3a" }),
    table.freeze({ id = "sun", name = "Sun", hex = "#e8b84a" }),
    table.freeze({ id = "sage", name = "Sage", hex = "#7bb06a" }),
    table.freeze({ id = "tide", name = "Tide", hex = "#2fb3a8" }),
    table.freeze({ id = "sky", name = "Sky", hex = "#4a9be0" }),
    table.freeze({ id = "cobalt", name = "Cobalt", hex = "#4a63d9" }),
    table.freeze({ id = "violet", name = "Violet", hex = "#8a5ad9" }),
    table.freeze({ id = "orchid", name = "Orchid", hex = "#c95ab8" }),
    table.freeze({ id = "lime", name = "Lime", hex = "#b6d94a" }),
})
Contract.DefaultTeamColors = table.freeze({ "crimson", "tide", "sun", "violet" })
function Contract.teamColor(id: any): any?
    for _, entry in Contract.TeamPalette do if entry.id == id then return entry end end
    return nil
end

Contract.Maps = (function()
    local list = {}
    for _, entry in Availability.maps do table.insert(list, entry.type) end
    return table.freeze(list)
end)()
Contract.Units = Lobby.UnitOptions                -- disabledUnits values (weapon bans)
Contract.Premium = Lobby.PremiumOptions           -- disabledPremium values (premium item bans: Arsenal ids, shelf order)
Contract.TeamOptions = Lobby.TeamOptions
Contract.Difficulties = Lobby.Difficulties
Contract.ClockSpeeds = Lobby.ClockSpeeds

-- The W4 settings a Create/Update may send. Missing keys take these defaults.
-- nil-able keys mean "off". The server re-validates everything (PrivateLobbyConfig).
function Contract.defaultSettings(): any
    return {
        gameMap = Availability.DefaultMap,
        gameMode = "Free For All",
        playerTeams = 2,
        difficulty = "Medium",
        maxPlayers = 10,
        nations = Availability.defaultNations(Availability.DefaultMap),
        bots = 25,
        disabledUnits = {},
        disabledPremium = {},         -- premium item bans (Arsenal ids; PF - 2's PremiumItems refuses them in the match)
        infiniteGold = false, infiniteTroops = false, instantBuild = false, randomSpawn = false,
        donateGold = false, donateTroops = false,
        startingGold = nil,           -- integer gold, 0..1e9
        goldMultiplier = nil,         -- 0.1..1000
        maxTimerValue = nil,          -- minutes 1..120
        customAllianceDuration = nil, -- minutes 0..15
        doomsdayClock = nil,          -- {speed = "slow"|"normal"|"fast"|"veryfast"}
        overtime = nil,               -- {startMinutes = 1..120}
        -- PF020 G8 Lobby Host+ only (nil = off):
        teamColors = nil,             -- {paletteId, ...} up to 4, Team mode
        peaceMinutes = nil,           -- 1..10: no attacks on players for the first minutes
        spectators = nil,             -- 1..8 spectator seats
    }
end

Contract.SettingKeys = table.freeze({
    gameMap = "string", gameMode = "string", playerTeams = "team", difficulty = "string", maxPlayers = "integer",
    nations = "integer", bots = "integer", disabledUnits = "units", disabledPremium = "premium",
    infiniteGold = "boolean", infiniteTroops = "boolean", instantBuild = "boolean", randomSpawn = "boolean",
    donateGold = "boolean", donateTroops = "boolean",
    startingGold = "number", goldMultiplier = "number", maxTimerValue = "integer", customAllianceDuration = "integer",
    doomsdayClock = "clock", overtime = "overtime",
    teamColors = "colors", peaceMinutes = "integer", spectators = "integer", -- PF020 G8
})

return table.freeze(Contract)
