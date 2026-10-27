--!strict
-- SinglePlayerModal.ts/GameConfigHelpers.ts, pinned OpenFront 93a136a1.
local Lobby = {}
local Availability=require(script.Parent.OpenFrontMatchAvailability)
local units=table.freeze({"City","Defense Post","Port","Warship","Transport","Missile Silo","SAM Launcher","Atom Bomb","Hydrogen Bomb","MIRV","Factory"})
-- Ashton 2026-10-26 ("its missing premium item bans"): the premium items a match can ban, beside the weapon bans (config
-- .disabledPremium, a dense list of these ids; PremiumItems refuses a banned one; unlocks are untouched). Soft: a harness
-- without ArsenalCatalog gets no premium ids (so any disabledPremium is refused there).
local premiumIds={}
do local ok,Arsenal=pcall(function() return require(script.Parent.ArsenalCatalog) end)
    if ok and type(Arsenal)=="table" and type(Arsenal.items)=="table" then for _,item in Arsenal.items do table.insert(premiumIds,item.id) end end end
premiumIds=table.freeze(premiumIds)
local toggles=table.freeze({"instantBuild","randomSpawn","infiniteGold","infiniteTroops","compactMap","waterNukes","doomsdayClock"})
local inputOptions=table.freeze({
    {key="maxTimer",valueKey="maxTimerValue",label="max_timer",min=1,max=120,default=30,integer=true},
    {key="goldMultiplier",valueKey="goldMultiplierValue",label="gold_multiplier",min=.1,max=1000,default=2,integer=false},
    {key="startingGold",valueKey="startingGoldValue",label="starting_gold",min=.1,max=1000,default=5,integer=false},
    {key="customAlliances",valueKey="customAllianceMinutes",label="custom_alliances",min=0,max=15,default=0,integer=true},
    {key="overtime",valueKey="overtimeStartMinutes",label="overtime",min=1,max=120,default=30,integer=true},
})
function Lobby.defaultConfig(): any
    return {gameMap="World",gameMapSize="Normal",gameType="Singleplayer",gameMode="Free For All",playerTeams=2,
        difficulty="Easy",bots=400,nations="default",infiniteGold=false,infiniteTroops=false,instantBuild=false,
        randomSpawn=false,disabledUnits={},donateGold=false,donateTroops=false}
end
function Lobby.validateSupported(config: any): boolean
    if type(config)~="table" then return false end
    local expected=Lobby.defaultConfig()
    for key,value in expected do
        if key=="disabledUnits" then
            if type(config[key])~="table" or next(config[key])~=nil then return false end
        elseif config[key]~=value then return false end
    end
    for key in config do if expected[key]==nil then return false end end
    return true
end
function Lobby.nationsConfig(value: number,defaultCount: number): number|string
    if value==0 then return "disabled" end
    if value==defaultCount then return "default" end
    return value
end
function Lobby.nationsSlider(value: number|string,defaultCount: number): number
    if value=="disabled" then return 0 end
    if value=="default" then return defaultCount end
    return value :: number
end
function Lobby.compactBots(value: number,compact: boolean): number
    if compact and value==400 then return 100 end
    if not compact and value==100 then return 400 end
    return value
end
function Lobby.compactNations(value: number,defaultCount: number,compact: boolean): number
    local compactCount=math.max(0,math.floor(defaultCount*.25))
    if compact and value==defaultCount then return compactCount end
    if not compact and value==compactCount then return defaultCount end
    return value
end
function Lobby.updatedDisabledUnits(disabled: {string},unit: string,checked: boolean): {string}
    local result={}
    for _,value in disabled do if checked or value~=unit then table.insert(result,value) end end
    if checked then table.insert(result,unit) end
    return result
end
function Lobby.defaultOptions(defaultNationCount: number?): any
    local count=defaultNationCount or 72
    return {selectedMap="World",selectedDifficulty="Easy",bots=400,nations=count,defaultNationCount=count,
        infiniteGold=false,infiniteTroops=false,compactMap=false,maxTimer=false,instantBuild=false,randomSpawn=false,
        useRandomMap=false,gameMode="Free For All",teamCount=2,goldMultiplier=false,startingGold=false,
        disabledUnits={},customAlliances=false,waterNukes=false,doomsdayClock=false,doomsdayClockSpeed="normal",overtime=false}
end
function Lobby.buildConfig(options: any): (any?,string?)
    local finalMaxTimer=nil
    if options.maxTimer then
        if not options.maxTimerValue or options.maxTimerValue<=0 then return nil,"Please enter a valid max timer value (1-120 minutes)" end
        finalMaxTimer=math.clamp(options.maxTimerValue,1,120)
    end
    local disabled={}
    for _,unit in options.disabledUnits do if table.find(units,unit) then table.insert(disabled,unit) end end
    local team=options.gameMode=="Team"
    local config={gameMap=options.selectedMap,gameMapSize=if options.compactMap then "Compact" else "Normal",gameType="Singleplayer",
        gameMode=options.gameMode,playerTeams=options.teamCount,difficulty=options.selectedDifficulty,maxTimerValue=finalMaxTimer,
        bots=options.bots,infiniteGold=options.infiniteGold,infiniteTroops=options.infiniteTroops,instantBuild=options.instantBuild,
        randomSpawn=options.randomSpawn,disabledUnits=disabled,nations=Lobby.nationsConfig(options.nations,options.defaultNationCount),
        donateGold=team,donateTroops=team}
    if options.goldMultiplier and options.goldMultiplierValue and options.goldMultiplierValue~=0 then config.goldMultiplier=options.goldMultiplierValue end
    if options.startingGold and options.startingGoldValue~=nil then config.startingGold=math.floor(options.startingGoldValue*1000000+.5) end
    if options.customAlliances then config.customAllianceDuration=options.customAllianceMinutes or 0 end
    if options.waterNukes then config.waterNukes=true end
    if options.doomsdayClock then config.doomsdayClock={enabled=true,speed=options.doomsdayClockSpeed} end
    if options.overtime then config.overtime={enabled=true,startMinutes=options.overtimeStartMinutes or 30} end
    -- premium item bans: only known ids, once each; absent when none
    if type(options.disabledPremium)=="table" then
        local banned={}
        for _,id in options.disabledPremium do if table.find(premiumIds,id) and not table.find(banned,id) then table.insert(banned,id) end end
        if #banned>0 then config.disabledPremium=banned end
    end
    return config,nil
end
function Lobby.availableOptions():any
    local options=Lobby.defaultOptions()
    options.selectedMap=Availability.DefaultMap
    options.nations=Availability.defaultNations(options.selectedMap)
    return Availability.options(options)
end
function Lobby.availableConfig():any
    return assert(Lobby.buildConfig(Lobby.availableOptions()))
end
function Lobby.setToggle(options: any,key: string,value: boolean)
    options[key]=value
    if key=="compactMap" then
        options.bots=Lobby.compactBots(options.bots,value)
        options.nations=Lobby.compactNations(options.nations,options.defaultNationCount,value)
    end
    for _,input in inputOptions do
        if input.key==key and value and (options[input.valueKey]==nil or options[input.valueKey]<input.min) then options[input.valueKey]=input.default end
    end
end
function Lobby.parseInput(key: string,text: string): number?
    for _,input in inputOptions do
        if input.valueKey~=key then continue end
        local value=nil
        if input.integer then
            local stripped=string.gsub(text,"[eE%+%-]","")
            local prefix=string.match(stripped,"^%s*(%d+)")
            value=if prefix then tonumber(prefix) else nil
        else
            local Settings=require(script.Parent.UserSettings)
            value=Settings.parseFloat(text)
        end
        return if value and value>=input.min and value<=input.max then value else nil
    end
    return nil
end
function Lobby.validateConfig(config: any,mapTypes: {[string]: boolean}?): boolean
    if type(config)~="table" then return false end
    if type(config.gameMap)~="string" or (mapTypes and not mapTypes[config.gameMap]) then return false end
    if config.gameType~="Singleplayer" or not table.find({"Free For All","Team"},config.gameMode) then return false end
    if not table.find({"Normal","Compact"},config.gameMapSize) or not table.find({"Easy","Medium","Hard","Impossible"},config.difficulty) then return false end
    if not table.find({2,3,4,5,6,7,"Quads","Trios","Duos","Humans Vs Nations"},config.playerTeams) then return false end
    local function bounded(value: any,min: number,max: number,integer: boolean): boolean
        return type(value)=="number" and value==value and value>=min and value<=max and (not integer or value%1==0)
    end
    if not bounded(config.bots,0,400,true) then return false end
    if config.nations~="default" and config.nations~="disabled" and not bounded(config.nations,1,400,true) then return false end
    for _,key in {"infiniteGold","infiniteTroops","instantBuild","randomSpawn","donateGold","donateTroops"} do if type(config[key])~="boolean" then return false end end
    if config.waterNukes~=nil and type(config.waterNukes)~="boolean" then return false end
    if config.disableNavMesh~=nil and type(config.disableNavMesh)~="boolean" then return false end
    for _,range in {{"maxTimerValue",1,120,true},{"customAllianceDuration",0,15,true},{"goldMultiplier",.1,1000,false},{"startingGold",0,1000000000,true}} do
        local value=config[range[1]];if value~=nil and not bounded(value,range[2],range[3],range[4]) then return false end
    end
    if type(config.disabledUnits)~="table" then return false end
    local seenCount=0
    for key,unit in config.disabledUnits do
        seenCount+=1
        if type(key)~="number" or key%1~=0 or key<1 or key>#config.disabledUnits or not table.find(units,unit) then return false end
    end
    if seenCount~=#config.disabledUnits then return false end
    if config.disabledPremium~=nil then -- a dense list of distinct Arsenal item ids
        local list=config.disabledPremium
        if type(list)~="table" then return false end
        local seen,count={},0
        for key,id in list do
            count+=1
            if type(key)~="number" or key%1~=0 or key<1 or key>#list or not table.find(premiumIds,id) or seen[id] then return false end
            seen[id]=true
        end
        if count~=#list then return false end
    end
    if config.doomsdayClock~=nil then
        local value=config.doomsdayClock
        if type(value)~="table" or value.enabled~=true or not table.find({"slow","normal","fast","veryfast"},value.speed) then return false end
    end
    if config.overtime~=nil then
        local value=config.overtime
        if type(value)~="table" or value.enabled~=true or not bounded(value.startMinutes,1,120,true) then return false end
    end
    local known={gameMap=true,gameMapSize=true,gameType=true,gameMode=true,playerTeams=true,difficulty=true,bots=true,nations=true,
        infiniteGold=true,infiniteTroops=true,instantBuild=true,randomSpawn=true,disabledUnits=true,donateGold=true,donateTroops=true,
        maxTimerValue=true,goldMultiplier=true,startingGold=true,customAllianceDuration=true,waterNukes=true,disableNavMesh=true,doomsdayClock=true,overtime=true,
        disabledPremium=true}
    for key in config do if not known[key] then return false end end
    return true
end
Lobby.UnitOptions=units
Lobby.PremiumOptions=premiumIds -- the premium item bans' ids (ArsenalCatalog shelf order)
Lobby.ToggleOptions=toggles
Lobby.InputOptions=inputOptions
Lobby.TeamOptions=table.freeze({2,3,4,5,6,7,"Quads","Trios","Duos","Humans Vs Nations"})
Lobby.Difficulties=table.freeze({"Easy","Medium","Hard","Impossible"})
Lobby.ClockSpeeds=table.freeze({"slow","normal","fast","veryfast"})
Lobby.DefaultNationCount=72
Lobby.ReferenceRevision="93a136a1e2915ec7bb83e34980ba5836a91f63ee"
return Lobby
