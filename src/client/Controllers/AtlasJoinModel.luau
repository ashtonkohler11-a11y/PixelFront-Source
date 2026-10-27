--!strict
-- PF019 M12: pure view model for the Join a Lobby screen. Turns the W6 facade
-- model (PublicLobbyController:getState(), see PF-019-W6-lobby-contract.md) into
-- row, drawer and code-popover views (the waiting room and 3-2-1 are PF - 3's
-- Screens.Room). No Instances, no I/O.
local Contract=require(game.ReplicatedStorage.Shared.LobbyContract)
local Country=require(game.ReplicatedStorage.Shared.CountryNames)
local Model={}
Model.Filters={"All","Free for All","Teams","Has space"}
Model.MaxPips=16
local function count(n: number,one: string,many: string): string return tostring(n).." "..(if n==1 then one else many) end
-- Server time from the model's clock sync.
function Model.serverTime(state: any,clock: number): number
    return (state.serverNow or 0)+(clock-(state.receivedAt or clock))
end
function Model.modeLabel(mode: any,teams: any): string
    if mode~="Team" then return "Free for All" end
    if type(teams)=="number" then return "Teams · "..teams.." teams" end
    if type(teams)=="string" then return "Teams · "..teams end
    return "Teams"
end
function Model.ago(seconds: number): string
    seconds=math.max(0,seconds)
    if seconds<10 then return "just now" end
    if seconds<60 then return math.floor(seconds).."s ago" end
    if seconds<3600 then return math.floor(seconds/60).."m ago" end
    return math.floor(seconds/3600).."h ago"
end
-- Seat pips: filled = joined, open = free seat, host = the first filled seat.
-- Large lobbies show a compact bar instead (pips=nil, fill 0..1).
function Model.seats(players: number,capacity: number): any
    capacity=math.max(1,capacity);players=math.clamp(players,0,capacity)
    local view={players=players,capacity=capacity,label=players.." / "..capacity,open=capacity-players,fill=players/capacity,pips=nil :: {string}?}
    if capacity<=Model.MaxPips then
        local pips={}
        for i=1,capacity do table.insert(pips,if i==1 and players>0 then "host" elseif i<=players then "filled" else "open") end
        view.pips=pips
    end
    return view
end
function Model.matches(room: any,search: string,filter: string): boolean
    if filter=="Free for All" and room.mode=="Team" then return false end
    if filter=="Teams" and room.mode~="Team" then return false end
    if filter=="Has space" and (room.players or 0)>=(room.capacity or 0) then return false end
    local needle=string.lower((string.gsub(search or "","^%s*(.-)%s*$","%1")))
    if needle=="" then return true end
    for _,field in {room.name,room.hostName,room.map} do
        if type(field)=="string" and string.find(string.lower(field),needle,1,true) then return true end
    end
    return false
end
-- One list row per Public lobby (the directory never lists Private ones).
function Model.row(room: any,now: number): any
    local full=(room.players or 0)>=(room.capacity or 0)
    local starting=room.status==Contract.Status.Starting
    local chips={Model.modeLabel(room.mode,room.teams)}
    if type(room.difficulty)=="string" then table.insert(chips,"Nations · "..room.difficulty) end
    -- Two chips fit the row on every device (native check 2026-10-06): the nations chip wins;
    -- weapon bans show when there are no nations, and always in the drawer facts.
    if #chips<2 and type(room.bans)=="number" and room.bans>0 then table.insert(chips,count(room.bans,"weapon ban","weapon bans")) end
    return {
        id=room.id,title=if type(room.name)=="string" and room.name~="" then room.name else (tostring(room.hostName or "Host").."'s lobby"),
        hostUserId=room.hostUserId,hostName=tostring(room.hostName or "Host"),map=tostring(room.map or ""),
        -- W6 v1.1: the host's country when Roblox provides it, as its full name (never a raw
        -- code); no cross-server region or ping exists.
        region=Country.name(room.hostCountry),
        chips=chips,seats=Model.seats(room.players or 0,room.capacity or 0),
        state=if starting then "starting" elseif full then "full" else "open",
        statusLabel=if starting then "Starting" elseif full then "Full" else "Open",
        age=Model.ago(now-(room.createdAt or now)),
        joinable=not full and not starting and room.locked~=true,
        -- PF020 V6 (PF - 2): a VIP host's lobby is gold; the directory already lists it first.
        hostVip=room.hostVip==true,
        -- PF023 L4 (PF - 2): the host's level on the listing (absent until loaded: no badge)
        hostLevel=if type(room.hostLevel)=="number" then room.hostLevel else nil,
        -- PF020 G8: a locked room stays listed (friends see it) but Join is off; its code still works.
        locked=room.locked==true,
    }
end
function Model.rows(state: any,search: string,filter: string,now: number): {any}
    local rows={}
    for _,room in state.rooms or {} do
        if Model.matches(room,search,filter) then table.insert(rows,Model.row(room,now)) end
    end
    return rows
end
-- The slide-in drawer for the selected lobby (same RoomSummary; full settings arrive after joining).
function Model.detail(room: any?,state: any,now: number): any?
    if not room then return nil end
    local row=Model.row(room,now)
    local pending=state.pending=="JoinLobby" or state.pending=="JoinCode"
    local facts={
        {label="Mode",value=Model.modeLabel(room.mode,room.teams)},
        {label="Map",value=row.map},
        {label="Nations",value=if type(room.nations)=="number" then (if room.nations==0 then "None" else tostring(room.nations)..(if type(room.difficulty)=="string" then " · "..room.difficulty else "")) else "—"},
        {label="Tribes",value=if type(room.bots)=="number" then (if room.bots==0 then "None" else tostring(room.bots)) else "—"},
        {label="Weapon bans",value=if type(room.bans)=="number" then (if room.bans==0 then "None" else tostring(room.bans)) else "—"},
        {label="Seats",value=row.seats.label..(if row.seats.open>0 then " · "..count(row.seats.open,"open","open") else " · full")},
    }
    local join=if pending then "Joining…" elseif row.locked then "Locked · ask the host for the code" elseif row.state=="full" then "Lobby full" elseif row.state=="starting" then "Already starting" else "Join lobby"
    return {row=row,facts=facts,join=join,canJoin=row.joinable and not pending and state.room==nil,
        note="You wait in your own server until the host starts, then everyone teleports together."}
end
-- Have a code?: typed text → the 6-character code (letters and digits only, uppercased).
function Model.sanitizeCode(text: string): string
    local clean=string.upper((string.gsub(text or "","[^%w]","")))
    return string.sub(clean,1,Contract.Limits.codeLength)
end
function Model.formatCode(code: string): string
    if #code<=3 then return code end
    return string.sub(code,1,3).."-"..string.sub(code,4)
end
-- Popover state: typing | invalid | joining.
function Model.codeView(text: string,state: any): any
    local code=Model.sanitizeCode(text)
    -- W6 v1.1: model.error is the message string; errorCode/errorOperation carry the rest.
    local message=Model.errorText(state)
    local codeError=message~=nil and (state.errorOperation=="JoinCode" or state.errorCode=="BadCode")
    local phase=if state.pending=="JoinCode" then "joining" elseif codeError then "invalid" else "typing"
    return {code=code,complete=#code==Contract.Limits.codeLength,phase=phase,
        hint=if phase=="invalid" then (message or Contract.Errors.BadCode)
            elseif phase=="joining" then "Finding the lobby…" else "6 letters and numbers, shared by the host",
        button=if phase=="joining" then "Joining…" elseif phase=="invalid" then "Try again" else "Join",
        canJoin=#code==Contract.Limits.codeLength and phase~="joining" and state.room==nil}
end
function Model.errorText(state: any): string?
    local err=state.error
    if err==nil or err=="" then
        if type(state.errorCode)=="string" then return Contract.Errors[state.errorCode] or Contract.Errors.Unknown end
        return nil
    end
    if type(err)=="table" then return tostring(err.message or Contract.Errors[err.code] or Contract.Errors.Unknown) end
    return tostring(err)
end
return table.freeze(Model)
