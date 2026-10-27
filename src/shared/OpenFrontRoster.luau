--!strict
-- OpenFrontIO 93a136a1: GameRunner.createGameRunner, NationCreation,
-- TribeSpawner.randomTribeName/spawnTribe and PseudoRandom.nextID.
-- World uses the default name theme and has no custom tribes. Nations require
-- NationExecution's still-separate systems and are never replaced with tribe AI.
local Random = require(script.Parent.OpenFrontRandom)
local Names = require(script.Parent.OpenFrontTribeNames)
local WorldNations = require(script.Parent.OpenFrontWorldNations)
local VariantData = require(script.Parent.OpenFrontRosterData)
local MapCatalog = require(script.Parent.OpenFrontMapCatalog)
local TutorialMapCatalog = require(script.Parent.OpenFrontTutorialMapCatalog) -- PF029: tutorial-only maps (Honshu: Japan's "asia" names)
local Teams = require(script.Parent.OpenFrontTeams)
local Balance = require(script.Parent.OpenFrontMatchBalance)
local Roster = {}
export type Player = { id: string, name: string, playerType: string, spawnTile: number?, spawnCell: { x: number, y: number }?, flag: string? }

local function nextID(random: Random.State): string
    local value = math.floor(Random.next(random) * 2821109907456)
    local alphabet, characters = "0123456789abcdefghijklmnopqrstuvwxyz", table.create(8, "0")
    for index = 8, 1, -1 do
        local digit = value % 36
        characters[index] = string.sub(alphabet, digit + 1, digit + 1)
        value = math.floor(value / 36)
    end
    return table.concat(characters)
end

local function shuffle(items: {any},random: Random.State): {any}
    local out=table.clone(items);for i=#out,2,-1 do local j=Random.int(random,0,i)+1;out[i],out[j]=out[j],out[i]end;return out
end
local function mapInfo(mapType: string?): any
    for _,list in {MapCatalog.maps,TutorialMapCatalog.maps} do for _,info in list do if info.type==mapType or info.id==mapType then return info end end end;return nil
end
function Roster.tribeNameData(mapType: string?): any
    local info=mapInfo(mapType);local themeNames=if info and info.themes and #info.themes>0 then info.themes else {"default"};local prefixes,suffixes={},{}
    for _,name in themeNames do local theme=VariantData.themes[name];if theme then for _,value in theme.prefixes do table.insert(prefixes,value)end;for _,value in theme.suffixes do table.insert(suffixes,value)end end end
    if #prefixes==0 or #suffixes==0 then local theme=assert(VariantData.themes.default,"Missing original default tribe theme");for _,value in theme.prefixes do table.insert(prefixes,value)end;for _,value in theme.suffixes do table.insert(suffixes,value)end end
    return {prefixes=prefixes,suffixes=suffixes,customTribes=if info and info.customTribes and #info.customTribes>0 then info.customTribes else nil}
end
local function generatedName(random: Random.State): string
    local data=VariantData.nationNames;local template=data.templates[Random.int(random,0,#data.templates)+1];local noun=data.nouns[Random.int(random,0,#data.nouns)+1];local parts={}
    for _,part in template do table.insert(parts,if part=="$noun"then noun elseif part=="$plural"then data.plural[noun]else part)end;return table.concat(parts," ")
end
local function uniqueName(random: Random.State,used: {[string]: boolean}): string
    for _=1,1000 do local name=generatedName(random);if not used[name]then return name end end
    local counter=1;local base=generatedName(random);while used[base.." "..counter]do counter+=1 end;return base.." "..counter
end
function Roster.nations(config: any,manifest: any,numHumans: number,random: Random.State,spread: boolean?,map: any?): {any}
    local nations,extras=manifest.nations or {},manifest.additionalNations or {};if config.nations=="disabled"then return {}end
    local function toNation(n)
        local coordinates=n.coordinates;local divisor=if config.gameMapSize=="Compact"then 2 else 1
        return {id=nextID(random),name=n.name,playerType="Nation",flag=n.flag,spawnCell=if coordinates then {x=math.floor(coordinates[1]/divisor),y=math.floor(coordinates[2]/divisor)}else nil}
    end
    local target=if type(config.nations)=="number"then config.nations else nil
    if target==nil and config.gameType=="Public"then
        if config.gameMode=="Team"and config.playerTeams=="Humans Vs Nations"then target=numHumans
        elseif config.gameMapSize=="Compact"then target=if #nations==0 then 0 else math.max(1,math.floor(#nations*.25))end
    end
    if target==nil then local out={};for _,n in nations do table.insert(out,toNation(n))end;return out end
    local shuffled=shuffle(nations,random)
    if spread then shuffled=Balance.spreadNations(shuffled,target,map)end
    local out={};for i=1,math.min(target,#shuffled)do table.insert(out,toNation(shuffled[i]))end
    if target<=#nations then return out end
    local used={};for _,nation in out do used[nation.name]=true end;local remaining=target-#nations
    if remaining>0 and #extras>0 then
        local candidates={};for _,n in extras do if not used[n.name]then table.insert(candidates,n)end end;local choices=shuffle(candidates,random);local count=math.min(remaining,#choices)
        for i=1,count do local n=choices[i];table.insert(out,toNation(n));used[n.name]=true end;remaining-=count
    end
    for _=1,remaining do local name=uniqueName(random,used);used[name]=true;table.insert(out,{name=name,playerType="Nation",id=nextID(random)})end;return out
end
function Roster.create(seed: number, botCount: number, humanId: string?, humanName: string?, includeNations: boolean?,gameConfig: any?,mapManifest: any?,map: any?,humans: {any}?,gameId: string?,spread: boolean?): ({ Player },any?)
    assert(botCount >= 0 and botCount % 1 == 0 and botCount < 65534, "Invalid tribe count")
    local playerRandom = Random.new(Random.hash(gameId or tostring(seed)))
    local generatedHumanId = nextID(playerRandom)
    local players: { Player } = { { id = humanId or generatedHumanId, name = humanName or "You", playerType = "Human" } }
    if humans then
        assert(#humans>0,"Public roster needs an admitted human")
        players={}
        for i,human in humans do
            local player:any={id=if i==1 then generatedHumanId else nextID(playerRandom),name=human.name,playerType="Human",clientID=human.clientID}
            player.friends=human.friends;player.clanTag=human.clanTag;player.teamIndex=human.teamIndex
            table.insert(players,player)
        end
    end
    if gameConfig then
        local manifest=mapManifest
        if not manifest then local nations={};for _,n in WorldNations do table.insert(nations,{name=n.name,flag=n.flag,coordinates={n.x,n.y}})end;manifest={nations=nations}end
        local nations=Roster.nations(gameConfig,manifest,#players,playerRandom,spread,map);for _,nation in nations do table.insert(players,nation)end
        local teamList;players,teamList=Teams.apply(players,gameConfig)
        local random=Random.new(Random.hash(gameId or tostring(seed))+2);local data=Roster.tribeNameData(gameConfig.gameMap);local used={};local tribeCount=0
        local function addTribe(name,tile)
            local player={id=nextID(random),name=name,playerType="Bot",spawnTile=tile,team=if gameConfig.gameMode=="Team"then "Bot"else nil};table.insert(players,player);tribeCount+=1
        end
        for _,ct in data.customTribes or {}do
            if tribeCount>=botCount then break end;if not ct.coordinates then continue end
            local divisor=if gameConfig.gameMapSize=="Compact"then 2 else 1;local x,y=math.floor(ct.coordinates[1]/divisor),math.floor(ct.coordinates[2]/divisor)
            local allowed=map and x>=0 and y>=0 and x<map.width and y<map.height;local tile=if allowed then y*map.width+x+1 else nil
            if tile and (not map.land[tile]or (map.terrain and bit32.band(buffer.readu8(map.terrain,tile-1),31)==31))then allowed=false end
            if tile then for _,nation in nations do if nation.spawnCell and nation.spawnCell.x==x and nation.spawnCell.y==y then allowed=false;break end end end
            if allowed then addTribe(ct.name,tile);used[ct.name]=true end
        end
        while tribeCount<botCount do
            local available={};for _,ct in data.customTribes or {}do if not ct.coordinates and not used[ct.name]then table.insert(available,ct)end end
            local name
            if #available>0 then local chosen=available[Random.int(random,0,#available)+1];name=chosen.name;used[name]=true
            else name=data.prefixes[Random.int(random,0,#data.prefixes)+1].." "..data.suffixes[Random.int(random,0,#data.suffixes)+1]end
            addTribe(name,nil)
        end
        return players,{playerRandom=table.clone(playerRandom),tribeRandom=table.clone(random),teams=teamList}
    end
    if includeNations then
        for _, nation in WorldNations do
            table.insert(players, { id = nextID(playerRandom), name = nation.name, playerType = "Nation", flag = nation.flag,
                spawnCell = { x = nation.x, y = nation.y } })
        end
    end
    local random = Random.new(Random.hash(tostring(seed)) + 2)
    for _ = 1, botCount do
        local prefix = Names.prefixes[Random.int(random, 0, #Names.prefixes) + 1]
        local suffix = Names.suffixes[Random.int(random, 0, #Names.suffixes) + 1]
        table.insert(players, { id = nextID(random), name = prefix .. " " .. suffix, playerType = "Bot" })
    end
    return players
end

function Roster.fixture(humanName: string?): { Player }
    return {
        { id = "human-1", name = humanName or "You", playerType = "Human" },
        { id = "bot-2", name = "Tribe", playerType = "Bot" },
    }
end

return table.freeze(Roster)
