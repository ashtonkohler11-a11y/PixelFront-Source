--!strict
-- Ashton's explicit Compact-only selection/count policy, 2026-10-01.
-- Keep the complete pinned catalog order intact for map-index-v1 storage.
local Catalog=require(script.Parent.OpenFrontMapCatalog)
local Availability={DefaultMap="United States",MapSize="Compact",MaxNations=25,MaxTribes=50,StorageVersion="compact3_v2"}
local allowed=table.freeze({["Qing China"]=true,["United States"]=true,Africa=true})
local maps={};local byType={}
for _,entry in Catalog.maps do if allowed[entry.type]then table.insert(maps,entry);byType[entry.type]=entry end end
assert(#maps==3,"Selected reference maps missing")
Availability.MapTypes=allowed
-- Tutorial-only maps (Ashton 2026-10-11: Honshu, replacing 2026-10-08's Italia; Italia_Compact stays in the place,
-- unused): every OpenFrontTutorialMapCatalog entry, never in Availability.maps / MapTypes (the Solo, lobby and public
-- pickers); MatchService.tutorialConfig names one directly and supportsTutorial is its gate.
local tutorialMaps={};for _,entry in require(script.Parent.OpenFrontTutorialMapCatalog).maps do tutorialMaps[entry.type]=true end
table.freeze(tutorialMaps)
Availability.TutorialMaps=tutorialMaps
Availability.TutorialMap="Honshu"
assert(tutorialMaps[Availability.TutorialMap],"Tutorial map missing from OpenFrontTutorialMapCatalog")
Availability.maps=table.freeze(maps)
function Availability.defaultNations(mapType:string):number
    return math.min(Availability.MaxNations,math.floor(assert(byType[mapType],"Unavailable map").defaultNationCount*.25))
end
function Availability.options(options:any):any
    if not allowed[options.selectedMap]then options.selectedMap=Availability.DefaultMap end
    options.compactMap=true
    options.defaultNationCount=byType[options.selectedMap].defaultNationCount
    options.bots=math.clamp(options.bots,0,Availability.MaxTribes)
    options.nations=math.clamp(options.nations,0,Availability.MaxNations)
    return options
end
-- Run the source config validator first; this is the additional availability gate.
function Availability.supports(config:any):boolean
    if type(config)~="table"or not allowed[config.gameMap]or config.gameMapSize~=Availability.MapSize then return false end
    if type(config.bots)~="number"or config.bots<0 or config.bots>Availability.MaxTribes then return false end
    if config.nations=="disabled"then return true end
    if config.nations=="default"then
        return config.gameType=="Public"and (config.playerTeams~="Humans Vs Nations"or config.maxPlayers<=Availability.MaxNations)
    end
    return type(config.nations)=="number"and config.nations>=1 and config.nations<=Availability.MaxNations
end
-- The tutorial's gate (the pickers never offer these maps; only MatchService.tutorialConfig builds one).
function Availability.supportsTutorial(config:any):boolean
    if type(config)~="table"or not tutorialMaps[config.gameMap]or config.gameMapSize~=Availability.MapSize then return false end
    if type(config.bots)~="number"or config.bots<0 or config.bots>Availability.MaxTribes then return false end
    return type(config.nations)=="number"and config.nations>=1 and config.nations<=Availability.MaxNations
end
return table.freeze(Availability)
