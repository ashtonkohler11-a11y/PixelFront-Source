--!strict
-- Public server-generated extension of the existing private config contract.
local Lobby=require(script.Parent.OpenFrontLobbySettings)
local Public={}
local extra={maxPlayers=true,publicGameModifiers=true,spawnImmunityDuration=true,disableAlliances=true,disableClanTags=true,trusted=true,
    teamColors=true, -- PF020 G8: Lobby Host+ team colours (hex strings, team 1..n)
    rankedType=true} -- Ranked v2: "1v1" | "2v2" (OpenFrontVictory)
local modifierKeys={isRandomSpawn=true,isCompact=true,isCrowded=true,isHardNations=true,startingGold=true,goldMultiplier=true,
    isAlliancesDisabled=true,isNukesDisabled=true,isSAMsDisabled=true,isPeaceTime=true,isWaterNukes=true,isDoomsdayClock=true}
function Public.validate(config:any,mapTypes:any?):boolean
    if type(config)~="table"or config.gameType~="Public"then return false end
    local private=table.clone(config);private.gameType="Singleplayer"
    for key in extra do private[key]=nil end
    if not Lobby.validateConfig(private,mapTypes)then return false end
    if type(config.maxPlayers)~="number"or config.maxPlayers%1~=0 or config.maxPlayers<2 or config.maxPlayers>4095 then return false end
    if config.spawnImmunityDuration~=nil and (type(config.spawnImmunityDuration)~="number"or config.spawnImmunityDuration%1~=0 or config.spawnImmunityDuration<0 or config.spawnImmunityDuration>9007199254740991)then return false end
    if config.rankedType~=nil and config.rankedType~="1v1"and config.rankedType~="2v2"then return false end
    for _,key in {"disableAlliances","disableClanTags","trusted"}do if config[key]~=nil and type(config[key])~="boolean"then return false end end
    if config.teamColors~=nil then
        if type(config.teamColors)~="table"or #config.teamColors<1 or #config.teamColors>8 then return false end
        for index,hex in config.teamColors do
            if type(index)~="number"or type(hex)~="string"or not string.match(hex,"^#%x%x%x%x%x%x$")then return false end
        end
    end
    if config.publicGameModifiers~=nil then
        if type(config.publicGameModifiers)~="table"then return false end
        for key,value in config.publicGameModifiers do
            if not modifierKeys[key]then return false end
            if key=="startingGold"or key=="goldMultiplier"then
                if type(value)~="number"or value~=value or value<0 or value>1000000000 then return false end
            elseif type(value)~="boolean"then return false end
        end
    end
    return true
end
return table.freeze(Public)
