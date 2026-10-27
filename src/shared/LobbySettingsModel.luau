--!strict
-- PF019 B1 (PF - 3): the ONE settings column shared by Solo (M4), Create Lobby and the waiting
-- room (M9). Pure rules over the W6 settings schema (LobbyContract.defaultSettings): the
-- steppers' value lists, the words every control shows, the match summary, the activity-feed
-- wording, and the Solo config (OpenFrontLobbySettings.buildConfig). No Instances, so
-- tools/run-pf019-settings.mjs runs it under luau.exe.
-- Real limits (Ashton): nations 0..25, tribes 0..50, the map is always Compact, no water nukes.
local Contract=require(script.Parent.LobbyContract)
local Lobby=require(script.Parent.OpenFrontLobbySettings)
local Availability=require(script.Parent.OpenFrontMatchAvailability)
local MapCatalog=require(script.Parent.OpenFrontMapCatalog)
local M={}
local OFF=false -- a stepper slot meaning "game default / off" (nil in the settings table)

-- Stepper value lists (OFF = nil in settings). Increments follow the M9 examples.
M.STEPS=table.freeze({
    startingGold=table.freeze({OFF,0,25000,50000,100000,250000,500000,1000000,5000000,10000000,100000000,1000000000}),
    goldMultiplier=table.freeze({.5,OFF,1.5,2,3,5,10,25}),
    customAllianceDuration=table.freeze({OFF,0,1,2,3,5,10,15}),
    maxTimerValue=table.freeze({5,10,15,20,30,45,60,90,120}),
    overtime=table.freeze({5,10,15,20,30,45,60,90,120}),
    maxPlayers=table.freeze({2,4,6,8,10,12,16,20,24,30,40,50,60}),
})
M.TOGGLE_DEFAULTS=table.freeze({maxTimerValue=60,overtime=45,doomsdayClock="normal"})
M.TEAM_CHIPS=table.freeze({2,3,4,5,6,7,"Humans Vs Nations"}) -- M9's chips (Contract.TeamOptions also allows Duos/Trios/Quads)
M.DIFFICULTIES=Contract.Difficulties -- Easy, Medium, Hard, Impossible (the ladder order)
M.DIFFICULTY_HINTS=table.freeze({
    Easy="Easy: nations expand slowly and leave gaps.",
    Medium="Medium: nations expand steadily and defend their borders.",
    Hard="Hard: nations expand fast and punish weak borders.",
    Impossible="Impossible: nations play their best from the first tick.",
})
M.MODE_HINT="Teams win together.\nFree For All: last nation standing wins."
M.CLOCK_NAMES=table.freeze({slow="Slow",normal="Normal",fast="Fast",veryfast="Very fast"})
M.UNIT_SHORT=table.freeze({["Atom Bomb"]="Atom Bomb",["Hydrogen Bomb"]="Hydrogen Bomb",MIRV="MIRV",["Missile Silo"]="Missile Silo",
    ["SAM Launcher"]="SAM Launcher",Warship="Warship",["Defense Post"]="Defense Post",Port="Port",City="City",Factory="Factory",Transport="Transport Boat"})

function M.defaults(): any return Contract.defaultSettings() end
-- PF021 (MM 2026-10-07): a room's settings can carry the reference lobby's words for nations
-- ("default" = the map's own count, "disabled" = none; the public queues send them). The screens read
-- numbers, so every room setting passes through here first: the real count, never a guess.
function M.defaultNations(map: any): number
    return Availability.defaultNations(if type(map)=="string" and Availability.MapTypes[map] then map else Availability.DefaultMap)
end
function M.normalize(settings: any): any
    if type(settings)~="table" then return M.defaults() end
    local result=M.copy(settings)
    if type(result.nations)~="number" then
        result.nations=if result.nations=="default" then M.defaultNations(result.gameMap)
            elseif result.nations=="disabled" then 0 else (tonumber(result.nations) or M.defaultNations(result.gameMap))
    end
    if type(result.bots)~="number" then result.bots=tonumber(result.bots) or M.defaults().bots end
    -- PF020 G8 Lobby Host+ keys (nil = off): numbers stay numbers, a word becomes its number or off.
    for _,key in {"peaceMinutes","spectators"} do
        if result[key]~=nil and type(result[key])~="number" then result[key]=tonumber(result[key]) end
    end
    for key in Contract.RetiredSettingKeys do result[key]=nil end -- retired keys (old presets) drop
    if result.teamColors~=nil and type(result.teamColors)~="table" then result.teamColors=nil end
    -- premium item bans: known Arsenal ids only, in shelf order (old presets without the key get none)
    local premium={}
    if type(result.disabledPremium)=="table" then for _,id in Contract.Premium do if table.find(result.disabledPremium,id) then table.insert(premium,id) end end end
    result.disabledPremium=premium
    return result
end
function M.copy(settings: any): any
    local result=table.clone(settings)
    result.disabledUnits=table.clone(settings.disabledUnits or {})
    result.disabledPremium=table.clone(settings.disabledPremium or {})
    if type(settings.doomsdayClock)=="table" then result.doomsdayClock=table.clone(settings.doomsdayClock) end
    if type(settings.overtime)=="table" then result.overtime=table.clone(settings.overtime) end
    if type(settings.teamColors)=="table" then result.teamColors=table.clone(settings.teamColors) end -- PF020 G8
    return result
end

-- ------------------------------------------------------------------ PF020 G8 Lobby Host+ (PF - 2)
-- Without the pass the max-players stepper stops at Contract.HostPlus.freeMaxPlayers (12); with it, at
-- the server's max. The Host+ steppers (OFF = nil = off) and the team colours (palette ids, team 1..4).
M.HOST_PLUS_STEPS=table.freeze({
    peaceMinutes=table.freeze({OFF,1,2,3,4,5,6,8,10}),
    spectators=table.freeze({OFF,1,2,3,4,5,6,7,8}),
})
function M.maxPlayersLimit(hostPlus: boolean?,serverMax: number?): number
    local server=math.min(serverMax or Contract.Limits.maxPlayers,Contract.Limits.maxPlayers)
    return if hostPlus then server else math.min(server,Contract.HostPlus.freeMaxPlayers)
end
function M.stepMaxPlayers(settings: any,direction: number,hostPlus: boolean?,serverMax: number?): any
    local result=M.copy(settings)
    local limit=M.maxPlayersLimit(hostPlus,serverMax)
    local list=M.STEPS.maxPlayers
    local index=1
    for i,value in list do if value<=(settings.maxPlayers or 2) then index=i end end
    local nextIndex=math.clamp(index+direction,1,#list)
    if list[nextIndex]<=limit then result.maxPlayers=list[nextIndex]
    elseif direction>0 then result.maxPlayers=math.max(settings.maxPlayers or 2,limit) end
    if result.maxPlayers>limit then result.maxPlayers=limit end
    return result
end
-- (its own lookup: this block sits above the stepper section's local slot())
local function hostPlusIndex(list: {any},value: any): number
    local wanted=if value==nil then OFF else value
    for index,entry in list do if entry==wanted then return index end end
    return 1
end
function M.stepHostPlus(key: string,settings: any,direction: number): any
    local result=M.copy(settings)
    local list=M.HOST_PLUS_STEPS[key];if not list then return result end
    local index=math.clamp(hostPlusIndex(list,settings[key])+direction,1,#list)
    local value=list[index];result[key]=if value==OFF then nil else value
    return result
end
-- The four team colours shown (the saved ids, the defaults for the rest).
function M.teamColorIds(settings: any): {string}
    local ids={}
    local saved=if type(settings.teamColors)=="table" then settings.teamColors else {}
    for team=1,Contract.HostPlus.teamColorSlots do ids[team]=saved[team] or Contract.DefaultTeamColors[team] end
    return ids
end
-- Give team `team` a palette colour; a team already wearing it swaps to the old one (no duplicates).
function M.setTeamColor(settings: any,team: number,id: string): any
    local result=M.copy(settings)
    if not Contract.teamColor(id) or team<1 or team>Contract.HostPlus.teamColorSlots then return result end
    local ids=M.teamColorIds(settings)
    local old=ids[team]
    for other,value in ids do if other~=team and value==id then ids[other]=old end end
    ids[team]=id;result.teamColors=ids
    return result
end
-- Settings a host without the pass can send: every standard key, no Host+ key, the 12-seat cap.
function M.withoutHostPlus(settings: any): any
    local result=M.copy(settings)
    for _,key in Contract.HostPlus.keys do result[key]=nil end
    for key in Contract.RetiredSettingKeys do result[key]=nil end
    result.maxPlayers=math.min(result.maxPlayers or Contract.HostPlus.freeMaxPlayers,Contract.HostPlus.freeMaxPlayers)
    return result
end

-- ------------------------------------------------------------------ words
local function short(value: number): string
    local function trim(n: number): string local s=string.format("%.1f",n);return (string.gsub(s,"%.0$","")) end
    if value>=1e9 then return trim(value/1e9).."B" end
    if value>=1e6 then return trim(value/1e6).."M" end
    if value>=1e3 then return trim(value/1e3).."K" end
    return tostring(math.floor(value))
end
M.short=short
function M.teamsWord(value: any): string
    if value=="Humans Vs Nations" then return "Humans vs Nations" end
    return tostring(value)
end
-- The text a control shows for its current value.
function M.value(key: string,settings: any): string
    if key=="startingGold" then return if settings.startingGold==nil then "Default" else short(settings.startingGold) end
    if key=="goldMultiplier" then
        local v=settings.goldMultiplier or 1
        return "×"..(if v%1==0 then string.format("%d.0",v) else string.format("%g",v))
    end
    if key=="customAllianceDuration" then return if settings.customAllianceDuration==nil then "Default" else settings.customAllianceDuration.." min" end
    if key=="maxTimerValue" then return (settings.maxTimerValue or M.TOGGLE_DEFAULTS.maxTimerValue).." min" end
    if key=="overtime" then return "from "..((settings.overtime and settings.overtime.startMinutes) or M.TOGGLE_DEFAULTS.overtime).." min" end
    if key=="doomsdayClock" then return M.CLOCK_NAMES[(settings.doomsdayClock and settings.doomsdayClock.speed) or M.TOGGLE_DEFAULTS.doomsdayClock] end
    if key=="nations" then return settings.nations.." of "..Availability.MaxNations end
    if key=="bots" then return tostring(settings.bots) end
    if key=="maxPlayers" then return tostring(settings.maxPlayers) end
    -- PF020 G8 Lobby Host+
    if key=="peaceMinutes" then return if settings.peaceMinutes==nil then "Off" else settings.peaceMinutes.." min" end
    if key=="spectators" then return if settings.spectators==nil then "Off" else tostring(settings.spectators) end
    if key=="teamColors" then
        local names={}
        for _,id in M.teamColorIds(settings) do local entry=Contract.teamColor(id);table.insert(names,if entry then entry.name else tostring(id)) end
        return table.concat(names,", ")
    end
    return tostring(settings[key])
end

-- ------------------------------------------------------------------ edits (return a new table)
local function slot(list: {any},value: any): number
    local wanted=if value==nil then OFF else value
    for index,entry in list do if entry==wanted then return index end end
    -- off-list values snap to the nearest entry
    local best,bestDistance=1,math.huge
    for index,entry in list do if entry~=OFF and type(wanted)=="number" and math.abs(entry-wanted)<bestDistance then best,bestDistance=index,math.abs(entry-wanted) end end
    return best
end
function M.canStep(key: string,settings: any,direction: number): boolean
    local list=M.STEPS[key];if not list then return false end
    local current=if key=="overtime" then (settings.overtime and settings.overtime.startMinutes) else settings[key]
    if (key=="maxTimerValue" and settings.maxTimerValue==nil) or (key=="overtime" and settings.overtime==nil) then return false end
    local index=slot(list,current)+direction
    return index>=1 and index<=#list
end
function M.step(key: string,settings: any,direction: number): any
    local result=M.copy(settings)
    if not M.canStep(key,settings,direction) then return result end
    local list=M.STEPS[key]
    local current=if key=="overtime" then (settings.overtime and settings.overtime.startMinutes) else settings[key]
    local nextValue=list[slot(list,current)+direction]
    if key=="overtime" then result.overtime={startMinutes=nextValue}
    elseif key=="maxPlayers" then result.maxPlayers=math.min(nextValue,Contract.Limits.maxPlayers)
    else result[key]=if nextValue==OFF then nil else nextValue end
    return result
end
-- Toggles: plain booleans, and the three that switch a stepped value on/off.
function M.isOn(key: string,settings: any): boolean
    if key=="maxTimerValue" or key=="doomsdayClock" or key=="overtime" then return settings[key]~=nil end
    return settings[key]==true
end
function M.toggle(key: string,settings: any): any
    local result=M.copy(settings)
    if key=="maxTimerValue" then result.maxTimerValue=if settings.maxTimerValue==nil then M.TOGGLE_DEFAULTS.maxTimerValue else nil
    elseif key=="overtime" then result.overtime=if settings.overtime==nil then {startMinutes=M.TOGGLE_DEFAULTS.overtime} else nil
    elseif key=="doomsdayClock" then result.doomsdayClock=if settings.doomsdayClock==nil then {speed=M.TOGGLE_DEFAULTS.doomsdayClock} else nil
    else result[key]=not (settings[key]==true) end
    return result
end
function M.stepClock(settings: any,direction: number): any
    local result=M.copy(settings);if settings.doomsdayClock==nil then return result end
    local list=Contract.ClockSpeeds;local index=table.find(list,settings.doomsdayClock.speed) or 2
    result.doomsdayClock={speed=list[math.clamp(index+direction,1,#list)]}
    return result
end
function M.setMode(settings: any,mode: string): any
    local result=M.copy(settings);result.gameMode=if mode=="Team" then "Team" else "Free For All";return result
end
function M.setTeams(settings: any,teams: any): any
    local result=M.copy(settings);if table.find(Contract.TeamOptions,teams) then result.playerTeams=teams;result.gameMode="Team" end;return result
end
function M.setDifficulty(settings: any,difficulty: string): any
    local result=M.copy(settings);if table.find(Contract.Difficulties,difficulty) then result.difficulty=difficulty end;return result
end
function M.setNations(settings: any,value: number): any
    local result=M.copy(settings);result.nations=math.clamp(math.floor(value+.5),0,Availability.MaxNations);return result
end
function M.setBots(settings: any,value: number): any
    local result=M.copy(settings);result.bots=math.clamp(math.floor(value+.5),0,Availability.MaxTribes);return result
end
function M.toggleUnit(settings: any,unit: string): any
    local result=M.copy(settings)
    if table.find(Contract.Units,unit) then result.disabledUnits=Lobby.updatedDisabledUnits(result.disabledUnits,unit,not table.find(result.disabledUnits,unit)) end
    return result
end
-- Premium item bans (PF - 2's config.disabledPremium; Arsenal ids in shelf order).
function M.togglePremium(settings: any,id: string): any
    local result=M.copy(settings)
    if not table.find(Contract.Premium,id) then return result end
    local on=table.find(result.disabledPremium,id)==nil
    local list={}
    for _,known in Contract.Premium do
        local banned=if known==id then on else table.find(result.disabledPremium,known)~=nil
        if banned then table.insert(list,known) end
    end
    result.disabledPremium=list
    return result
end
function M.clearBans(settings: any): any local result=M.copy(settings);result.disabledUnits={};result.disabledPremium={};return result end
-- A new map resets nations to that map's default (as the Solo screen always has).
function M.setMap(settings: any,map: string): any
    local result=M.copy(settings)
    if Availability.MapTypes[map] then result.gameMap=map;result.nations=Availability.defaultNations(map) end
    return result
end

-- ------------------------------------------------------------------ maps
local function entryOf(map: string): any
    for _,entry in Availability.maps do if entry.type==map then return entry end end
    return nil
end
local REGIONS={north_america="North America",south_america="South America",europe="Europe",asia="Asia",africa="Africa",oceania="Oceania"}
function M.maps(): {any}
    local list={}
    for _,entry in Availability.maps do table.insert(list,M.mapInfo(entry.type)) end
    return list
end
function M.mapInfo(map: string): any
    local entry=entryOf(map)
    if not entry then return {type=map,name=map,details="",thumbnail=nil,nations=0} end
    local area=(entry.compactWidth or 0)*(entry.compactHeight or 0)
    local size=if area>=1050000 then "Large" elseif area>=600000 then "Medium" else "Small"
    local region=nil
    for _,category in entry.categories or {} do if REGIONS[category] then region=REGIONS[category];break end end
    local nations=Availability.defaultNations(map)
    local parts={size,nations.." nations"};if region then table.insert(parts,region) end
    return {type=entry.type,name=entry.name or entry.type,details=table.concat(parts," · "),thumbnail=entry.thumbnail,nations=nations,size=size,region=region}
end
-- Search: case-insensitive substring over name and region.
function M.matches(info: any,query: string): boolean
    local q=string.lower((string.gsub(query,"^%s*(.-)%s*$","%1")))
    if q=="" then return true end
    return string.find(string.lower(info.name),q,1,true)~=nil or (info.region~=nil and string.find(string.lower(info.region),q,1,true)~=nil)
end

-- ------------------------------------------------------------------ summary + feed
function M.modeLine(settings: any): string
    if settings.gameMode~="Team" then return "Free For All" end
    if settings.playerTeams=="Humans Vs Nations" then return "Teams · Humans vs Nations" end
    if type(settings.playerTeams)=="number" then return "Teams · "..settings.playerTeams.." teams" end
    return "Teams · "..tostring(settings.playerTeams)
end
M.PREMIUM_SHORT=table.freeze({tesla_coil="Tesla Coil",artillery="Artillery",warden="Warden",barracks="Barracks",training_camp="Training Camp",
    airdrop="Airdrop",blitz_bomb="Blitz Bomb",titan_bomb="Titan Bomb",engineering_yard="Engineering Yard",bank="Bank",tax_office="Tax Office",
    trade_guild="Shipping Co.",stock_exchange="Stock Exchange"})
-- Every ban, weapons then premium items: "MIRV, Warden" (None when nothing is banned).
function M.bansLine(settings: any): string
    local names={};for _,unit in settings.disabledUnits or {} do table.insert(names,M.UNIT_SHORT[unit] or unit) end
    for _,id in settings.disabledPremium or {} do table.insert(names,M.PREMIUM_SHORT[id] or id) end
    return if #names==0 then "None" else table.concat(names,", ")
end
function M.summary(settings: any): {{string}}
    local timer=if settings.maxTimerValue then settings.maxTimerValue.." min" else "Off"
    if settings.overtime then timer=timer.." · overtime "..settings.overtime.startMinutes end
    return {
        {"Mode",M.modeLine(settings)},
        {"Nations",if settings.nations==0 then "None" else settings.nations.." · "..settings.difficulty},
        {"Tribes",tostring(settings.bots)},
        {"Time limit",timer},
        {"Bans",M.bansLine(settings)},
    }
end
local LABELS={gameMap="Map",gameMode="Mode",playerTeams="Teams",difficulty="Difficulty",maxPlayers="Max players",nations="Nations",bots="Tribes",
    disabledUnits="Weapon bans",disabledPremium="Premium bans",infiniteGold="Infinite gold",infiniteTroops="Infinite troops",instantBuild="Instant build",randomSpawn="Random spawn",
    donateGold="Donate gold",donateTroops="Donate troops",startingGold="Starting gold",goldMultiplier="Gold income",maxTimerValue="Time limit",
    customAllianceDuration="Alliance length",doomsdayClock="Doomsday clock",overtime="Overtime",
    teamColors="Team colours",peaceMinutes="Peace timer",spectators="Spectator seats"} -- PF020 G8
M.LABELS=table.freeze(LABELS)
-- One line for the activity feed: "Time limit to 60 min", "Infinite gold on", "Weapon bans: MIRV".
function M.describe(key: string,settings: any): string
    local label=LABELS[key] or key
    if key=="gameMap" then return "Map to "..tostring(settings.gameMap) end
    if key=="gameMode" or key=="playerTeams" then return "Mode to "..M.modeLine(settings) end
    if key=="difficulty" then return "Difficulty to "..tostring(settings.difficulty) end
    if key=="disabledUnits" or key=="disabledPremium" then return "Bans: "..M.bansLine(settings) end
    local value=settings[key]
    if type(value)=="boolean" then return label..(if value then " on" else " off") end
    if value==nil then return label..(if key=="maxTimerValue" or key=="overtime" or key=="doomsdayClock"
        or key=="peaceMinutes" or key=="spectators" or key=="teamColors" then " off" else " to default") end
    return label.." to "..M.value(key,settings)
end
local function same(a: any,b: any): boolean
    if type(a)~="table" or type(b)~="table" then return a==b end
    for k,v in a do if not same(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
-- The Solo "You'll face" custom rules: every setting off its default except the ones the summary and
-- the counts already show (map, mode, teams, difficulty, nations, tribes, lobby size). One line each.
local SHOWN={gameMap=true,gameMode=true,playerTeams=true,difficulty=true,nations=true,bots=true,maxPlayers=true}
function M.ruleLines(settings: any): {string}
    local lines={}
    local bansShown=false
    for _,key in M.changes(M.defaults(),settings) do
        if SHOWN[key] then continue end
        local value=settings[key]
        if key=="disabledUnits" or key=="disabledPremium" then
            if not bansShown then bansShown=true;table.insert(lines,"Banned: "..M.bansLine(settings)) end
        elseif type(value)=="boolean" then table.insert(lines,(LABELS[key] or key)..(if value then " on" else " off"))
        elseif value==nil then table.insert(lines,(LABELS[key] or key).." off")
        else table.insert(lines,(LABELS[key] or key)..": "..M.value(key,settings)) end
    end
    return lines
end
function M.changes(old: any,new: any): {string}
    local keys={}
    for key in Contract.SettingKeys do if not same(old[key],new[key]) then table.insert(keys,key) end end
    table.sort(keys)
    return keys
end

-- ------------------------------------------------------------------ Solo
-- The same settings, as the singleplayer config the Solo start sends (compact always).
function M.soloConfig(settings: any): (any?,string?)
    local options=Lobby.availableOptions()
    options.selectedMap=settings.gameMap;options.selectedDifficulty=settings.difficulty
    options.gameMode=settings.gameMode;options.teamCount=settings.playerTeams
    options.nations=settings.nations;options.bots=settings.bots;options.disabledUnits=table.clone(settings.disabledUnits or {})
    options.disabledPremium=table.clone(settings.disabledPremium or {}) -- PF - 2's Lobby.buildConfig keeps known ids once
    options.infiniteGold=settings.infiniteGold==true;options.infiniteTroops=settings.infiniteTroops==true
    options.instantBuild=settings.instantBuild==true;options.randomSpawn=settings.randomSpawn==true
    options.maxTimer=settings.maxTimerValue~=nil;options.maxTimerValue=settings.maxTimerValue
    options.goldMultiplier=settings.goldMultiplier~=nil;options.goldMultiplierValue=settings.goldMultiplier
    options.startingGold=settings.startingGold~=nil;options.startingGoldValue=if settings.startingGold then settings.startingGold/1000000 else nil
    options.customAlliances=settings.customAllianceDuration~=nil;options.customAllianceMinutes=settings.customAllianceDuration
    options.doomsdayClock=settings.doomsdayClock~=nil;options.doomsdayClockSpeed=(settings.doomsdayClock and settings.doomsdayClock.speed) or "normal"
    options.overtime=settings.overtime~=nil;options.overtimeStartMinutes=settings.overtime and settings.overtime.startMinutes
    Availability.options(options)
    local config,problem=Lobby.buildConfig(options)
    if not config then return nil,problem end
    -- The column's diplomacy toggles are the truth (buildConfig only defaults them from Teams).
    config.donateGold=settings.donateGold==true;config.donateTroops=settings.donateTroops==true
    if config.startingGold then config.startingGold=math.clamp(math.floor(settings.startingGold),0,1000000000) end
    if not Lobby.validateConfig(config,Availability.MapTypes) then return nil,"Some settings are not available. Check them and try again." end
    return config,nil
end

return table.freeze(M)
