--!strict
--!native
-- Private solo source GameConfig and public team/winner/Doom snapshot records.
local Lobby=require(script.Parent.OpenFrontLobbySettings)
local Catalog=require(script.Parent.OpenFrontMapCatalog)
local Teams=require(script.Parent.OpenFrontTeams)
local Public=require(script.Parent.PublicGameConfig)
local Metadata={}
local mapTypes={};for _,map in Catalog.maps do mapTypes[map.type]=true end
-- PF029: the tutorial's own map (Honshu) is not in the pinned catalog; its config must still cross the wire
local tutorialTypes={}
for _,map in require(script.Parent.OpenFrontTutorialMapCatalog).maps do mapTypes[map.type]=true;tutorialTypes[map.type]=true end
local fields={"gameMap","gameMapSize","gameType","gameMode","playerTeams","difficulty","bots","nations",
    "infiniteGold","infiniteTroops","instantBuild","randomSpawn","donateGold","donateTroops","maxTimerValue",
    "goldMultiplier","startingGold","customAllianceDuration","waterNukes","disableNavMesh",
    "maxPlayers","spawnImmunityDuration","disableAlliances","disableClanTags","trusted",
    "winThreshold"} -- the tutorial's win line (Victory.threshold), so the client's tracker and HUD show the server's
local function integer(value: any,lo: number,hi: number): boolean
    return type(value)=="number"and value==value and value%1==0 and value>=lo and value<=hi
end
local function dense(value: any): boolean
    if type(value)~="table"then return false end
    for key in value do if not integer(key,1,#value)then return false end end
    for i=1,#value do if value[i]==nil then return false end end
    return true
end
local function same(a: any,b: any): boolean
    if type(a)~=type(b)then return false end
    if type(a)~="table"then return a==b end
    for key,value in a do if not same(value,b[key])then return false end end
    for key in b do if a[key]==nil then return false end end
    return true
end
function Metadata.copyConfig(config: any): any?
    if config==nil then return nil end
    local out={};for _,field in fields do out[field]=config[field]end
    out.disabledUnits=if config.disabledUnits then table.freeze(table.clone(config.disabledUnits))else nil
    out.disabledPremium=if config.disabledPremium then table.freeze(table.clone(config.disabledPremium))else nil -- premium item bans
    if config.doomsdayClock then out.doomsdayClock=table.freeze({enabled=config.doomsdayClock.enabled,speed=config.doomsdayClock.speed})end
    if config.overtime then out.overtime=table.freeze({enabled=config.overtime.enabled,startMinutes=config.overtime.startMinutes})end
    if config.publicGameModifiers then out.publicGameModifiers=table.freeze(table.clone(config.publicGameModifiers))end
    if config.teamColors then out.teamColors=table.freeze(table.clone(config.teamColors))end -- PF020 G8 Host+ team colours
    return table.freeze(out)
end
local function configValid(config: any): boolean
    -- winThreshold (Ashton 2026-10-11: the tutorial wins at 60%): whole 1..100, on a tutorial map only; never a lobby,
    -- Solo or public setting (their validators still refuse the key)
    if config.winThreshold~=nil then
        if not integer(config.winThreshold,1,100) or not tutorialTypes[config.gameMap] then return false end
        config=table.clone(config);config.winThreshold=nil
    end
    if not (if config.gameType=="Public"then Public.validate(config,mapTypes)else Lobby.validateConfig(config,mapTypes))then return false end
    for _,pair in {{"doomsdayClock",{enabled=true,speed=true}},{"overtime",{enabled=true,startMinutes=true}}}do
        if config[pair[1]]then for key in config[pair[1]]do if not pair[2][key]then return false end end end
    end
    return dense(config.disabledUnits) and (config.disabledPremium==nil or dense(config.disabledPremium))
end
function Metadata.encode(snapshot: any)
    assert(snapshot.gameConfig==nil or configValid(snapshot.gameConfig),"Invalid private source match configuration")
    snapshot.gameConfig=Metadata.copyConfig(snapshot.gameConfig)
    snapshot.teams=table.clone(snapshot.teams or {})
    if snapshot.doomsday then snapshot.doomsday={active=snapshot.doomsday.active}end
    if snapshot.localBorderTiles then snapshot.localBorderTiles=table.clone(snapshot.localBorderTiles)end
    if snapshot.attacks then
        local attacks={}
        for _,attack in snapshot.attacks do local out=table.clone(attack)
            if attack.positions then out.positions={};for _,point in attack.positions do table.insert(out.positions,{x=point.x,y=point.y})end end
            table.insert(attacks,out)
        end;snapshot.attacks=attacks
    end
end
function Metadata.decode(state: any,previous: any?,full: boolean,count: number,tileCount: number?): (any?,string?)
    local config=state.gameConfig
    if config~=nil and not configValid(config)then return nil,"config"end
    if not full and (not previous or not same(config,previous.gameConfig))then return nil,"config.changed"end
    if config and (state.mapType~=config.gameMap or state.mapSize~=config.gameMapSize)then return nil,"config.map"end
    if state.ticks~=nil and not integer(state.ticks,0,9007199254740991)then return nil,"ticks"end
    if state.startTick~=nil and not integer(state.startTick,0,state.ticks or 0)then return nil,"startTick"end
    if not table.find({"Choosing","Playing","Won","Lost","Cancelled"},state.phase)then return nil,"phase"end
    local players=if full then state.players else previous and previous.players
    local replacePlayers=full
    if not full and state.rosterChanges~=nil then
        if not dense(state.rosterChanges)then return nil,"roster"end
        if #state.rosterChanges>0 then players=table.clone(players or {});replacePlayers=true end
        local last=0
        for _,entry in state.rosterChanges do
            if type(entry)~="table"or not integer(entry.owner,last+1,count)or type(entry.player)~="table"then return nil,"roster.entry"end
            players[entry.owner]=entry.player;last=entry.owner
        end
    end
    local participantCount,teamSet=0,{}
    if players~=nil then
        if not dense(players)or #players~=count then return nil,"roster.count"end
        local ids={}
        for _,player in players do
            if type(player)~="table"or type(player.id)~="string"or ids[player.id]
                or type(player.name)~="string"or not table.find({"Human","Nation","Bot"},player.playerType)then return nil,"roster.player"end
            ids[player.id]=true
            if player.spawnTile~=nil and not integer(player.spawnTile,1,tileCount or 9007199254740991)then return nil,"roster.spawnTile"end
            if player.alive~=nil and type(player.alive)~="boolean"then return nil,"roster.alive"end
            for _,field in {"displayName","clanTag","flag"}do
                if player[field]~=nil and type(player[field])~="string"then return nil,"roster."..field end
            end
            if player.spawnCell~=nil then
                if type(player.spawnCell)~="table"then return nil,"roster.cell"end
                for key in player.spawnCell do if key~="x"and key~="y"then return nil,"roster.cellField"end end
                for _,key in {"x","y"}do local value=player.spawnCell[key]
                    if type(value)~="number"or value~=value or math.abs(value)==math.huge then return nil,"roster.cellValue"end
                end
            end
            if player.friends~=nil then
                if not dense(player.friends)then return nil,"roster.friends"end
                for _,friend in player.friends do if type(friend)~="string"then return nil,"roster.friend"end end
            end
            if player.playerType~="Bot"then participantCount+=1 end
            for _,field in {"markedDoomsdayClockTick","rottedAtTick"}do local tick=player[field]
                if tick~=nil and not integer(tick,-1,state.ticks or 0)then return nil,"doomsday.tick"end
                if tick and tick>=0 and (not config or not config.doomsdayClock or player.playerType=="Bot")then return nil,"doomsday.player"end
            end
            if player.rottedAtTick and player.rottedAtTick>=0 and (player.markedDoomsdayClockTick or -1)<0 then return nil,"doomsday.rot"end
        end
    elseif config then return nil,"roster.missing"end
    local teams=state.teams or {}
    if not dense(teams)then return nil,"teams"end
    for _,team in teams do if type(team)~="string"or teamSet[team]then return nil,"team.name"end;teamSet[team]=true end
    local expected=if config and config.gameMode=="Team"then Teams.resolve(config.playerTeams,participantCount)else {}
    if not same(teams,expected)then return nil,"teams.source"end
    if not full and not same(teams,previous.teams or {})then return nil,"teams.changed"end
    if players then for _,player in players do
        if config and config.gameMode=="Team"then
            if player.playerType=="Bot"then if player.team~="Bot"then return nil,"team.bot"end
            elseif not teamSet[player.team]then return nil,"team.player"end
        elseif player.team~=nil then return nil,"team.ffa"end
    end end
    local winner,winnerTeam=state.winner,state.winnerTeam
    if winner~=nil and (not integer(winner,1,count)or winnerTeam~=nil or config and config.gameMode=="Team")then return nil,"winner"end
    if winnerTeam~=nil and (not config or config.gameMode~="Team"or type(winnerTeam)~="string"or not teamSet[winnerTeam])then return nil,"winner.team"end
    if winner~=nil and state.phase~=(if winner==1 then "Won"else "Lost")then return nil,"winner.phase"end
    if winnerTeam~=nil and state.phase~=(if players[1].team==winnerTeam then "Won"else "Lost")then return nil,"winner.teamPhase"end
    local doomsday=nil
    if state.doomsday~=nil then
        if type(state.doomsday)~="table"or type(state.doomsday.active)~="boolean"or not config or not config.doomsdayClock then return nil,"doomsday"end
        for key in state.doomsday do if key~="active"then return nil,"doomsday.field"end end
        if state.doomsday.active and (winner~=nil or winnerTeam~=nil)then return nil,"doomsday.winner"end
        doomsday=table.freeze({active=state.doomsday.active})
    end
    return {config=Metadata.copyConfig(config),teams=table.freeze(table.clone(teams)),doomsday=doomsday,players=players,replacePlayers=replacePlayers},nil
end
function Metadata.apply(state: any,data: any)
    state.gameConfig,state.teams,state.doomsday=data.config,data.teams,data.doomsday
    if data.replacePlayers and data.players then
        state.players={};for _,player in data.players do
            local copy=table.clone(player)
            if player.spawnCell then copy.spawnCell=table.clone(player.spawnCell)end
            if player.friends then copy.friends=table.clone(player.friends)end
            table.insert(state.players,copy)
        end
    end
end
return table.freeze(Metadata)
