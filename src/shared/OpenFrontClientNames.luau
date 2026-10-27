--!strict
-- Util.createRandomName and PlayerView naming, pinned OpenFront 93a136a1.
local TribeNames=require(script.Parent.OpenFrontTribeNames)
local Names={}
-- Source simpleHash iterates UTF-16 code units, including surrogate pairs.
function Names.hash(value: string): number
    local hash=0
    for _,code in utf8.codes(value) do
        if code>65535 then
            code-=65536;hash=(hash*31+55296+math.floor(code/1024))%4294967296
            code=56320+code%1024
        end
        hash=(hash*31+code)%4294967296
    end
    return math.abs(if hash>=2147483648 then hash-4294967296 else hash)
end
function Names.anonymous(name: string,playerType: string): string?
    if playerType~="Human" then return nil end
    local hash=Names.hash(name)
    return "👤 "..TribeNames.prefixes[hash%#TribeNames.prefixes+1].." "..TribeNames.suffixes[math.floor(hash/#TribeNames.prefixes)%#TribeNames.suffixes+1]
end
function Names.resolve(state: any,owner: number,preferences: any?): string
    local player=state.players and state.players[owner]
    local name=(player and (player.displayName or player.name)) or (state.names and state.names[owner]) or ""
    preferences=preferences or state.clientPreferences
    if preferences and preferences:get("anonymousNames") and player and owner~=(state.localOwner or 1) then return Names.anonymous(name,player.playerType) or name end
    return name
end
function Names.clan(state: any,owner: number,preferences: any?): string
    local player=state.players and state.players[owner]
    preferences=preferences or state.clientPreferences
    if preferences and preferences:get("anonymousNames") and player and player.playerType=="Human" then return "" end
    return (player and player.clanTag) or ""
end
return Names
