--!strict
-- MapPlaylist.ts, OpenFront 93a136a1. Platform adapters are explicit in gameConfig.
local Shared=game:GetService("ReplicatedStorage").Shared
local Catalog=require(Shared.OpenFrontMapCatalog)
local Random=require(Shared.OpenFrontRandom)
local Land=require(script.Parent.PublicMapLand)
local Availability=require(Shared.OpenFrontMatchAvailability)
local Playlist={};Playlist.__index=Playlist
-- Schedule entries persist generated configs, so hosting must include this
-- policy version in its transient namespace. The stable map encoding is unchanged.
Playlist.StorageVersion="atlas_bands_v3" -- v3: PF043 per-card seats 8/6/4 (v2: 6/8 on 2 cards); bump on any seat change (Config.PublicQueue)
local normalCapacity={
    ["Qing China"]={ffa=10,team=4},
    ["United States"]={ffa=10,team=4},
    Africa={ffa=12,team=6},
}
local weights={{2,10},{3,10},{4,10},{5,10},{6,10},{7,10},{"Duos",5},{"Trios",7.5},{"Quads",7.5},{"Humans Vs Nations",20}}
local tickets={{"isRandomSpawn",4},{"isCompact",4},{"isCrowded",2},{"isHardNations",1},{"startingGold1M",2},{"startingGold5M",4},{"startingGold25M",3},{"goldMultiplier",6},{"isAlliancesDisabled",1},{"isNukesDisabled",1},{"isSAMsDisabled",1},{"isPeaceTime",1},{"isWaterNukes",4},{"isDoomsdayClock",4}}
local exclusive={{"startingGold5M","startingGold25M"},{"startingGold5M","startingGold1M"},{"startingGold25M","startingGold1M"},{"isHardNations","startingGold25M"},{"isNukesDisabled","isSAMsDisabled"},{"isNukesDisabled","isWaterNukes"}}
local info={};for _,m in Catalog.maps do info[m.type]=m end
local mapIndex={};for i,m in Catalog.maps do mapIndex[m.type]=i end
-- Lossless server storage representation. Map names across all four weighted
-- playlists exceed MemoryStore's 32KiB item limit; ordered catalog indices fit.
function Playlist.packState(state:any):any
    local packed={scheduled=state.scheduled,encoding="map-index-v1",playlists={}}
    for key,list in state.playlists do local out={};for i,map in list do out[i]=assert(mapIndex[map],"Unknown playlist map")end;packed.playlists[key]=out end
    return packed
end
function Playlist.unpackState(state:any?):any?
    if not state or state.encoding==nil then return state end
    assert(state.encoding=="map-index-v1","Unsupported public playlist storage")
    local decoded={scheduled=state.scheduled,playlists={}}
    for key,list in state.playlists do local out={};for i,index in list do out[i]=assert(Catalog.maps[index],"Unknown stored map").type end;decoded.playlists[key]=out end
    return decoded
end
local function adjust(p,t)
    if not t then return p end
    if t=="Humans Vs Nations"then return math.floor(p/2)end
    local n=if t=="Duos"then 2 elseif t=="Trios"then 3 elseif t=="Quads"then 4 else t
    return p-p%n
end
local function supports(p,t)
    if t=="Humans Vs Nations"then return p>=2 end
    local group=if t=="Duos"then 2 elseif t=="Trios"then 3 elseif t=="Quads"then 4 else nil
    return if group then p>=group*2 else t>=2 and math.floor(p/t)>=2
end
local function normalTeamCapacity(p,t)
    -- The band counts humans. Humans Vs Nations retains one nation per human;
    -- applying the source total-participant halving here would halve the band.
    if t=="Humans Vs Nations"then return p,t end
    local group=if t=="Duos"then 2 elseif t=="Trios"then 3 elseif t=="Quads"then 4 else nil
    if group and p%group==0 and supports(p,t)then return p,t end
    -- A lower Roblox server limit may cut across a band. Keep equal teams and
    -- never round upward past that limit. Two singleton teams remain playable
    -- on a two/three-player host, whose limit cannot support ordinary duos.
    p-=p%2
    if group then return p,if p>=4 then "Duos"else 2 end
    for teams=math.min(t,math.max(2,math.floor(p/2))),2,-1 do
        if p%teams==0 then return p,teams end
    end
    return p,2
end
function Playlist.counts(land:number):{number}
    local function round(n)return math.floor(n/5+.5)*5 end
    local b=math.max(round(land/1000000*50),5);return {b,round(b*.75),round(b*.5)}
end
function Playlist.new(state:any?,options:any?):any
    options=options or {}
    if state and options.availability then
        state=table.clone(state);state.playlists=table.clone(state.playlists)
        for key,list in state.playlists do local filtered={};for _,map in list do if Availability.MapTypes[map]then table.insert(filtered,map)end end;state.playlists[key]=filtered end
    end
    return setmetatable({state=state or {scheduled=0,playlists={ffa={},team={},specialFfa={},specialTeam={}}},availability=options.availability==true,
        random=options.random or math.random,now=options.now or function()return DateTime.now().UnixTimestampMillis end,
        maxPlayers=options.maxPlayers or math.huge,openTrust=options.openTrust~=false,ffaOnly=options.ffaOnly==true,
        -- PF043 (Config.PublicQueue): seat caps per card kind and whether Chaos may roll Crowded; nil = the source bands
        seats=options.seats,crowded=options.crowded~=false},Playlist) -- seats: {[card kind]=cap}
end
function Playlist:buildMapsList(kind,mode)
    local out={}
    for _,m in Catalog.maps do
        if self.availability and not Availability.MapTypes[m.type]then continue end
        local f
        if kind=="ffa"then f=if m.ffaFrequency>=0 then m.ffaFrequency else m.multiplayerFrequency
        elseif kind=="team"then f=if m.teamFrequency>=0 then m.teamFrequency else m.multiplayerFrequency
        else local mf=if mode=="Team"then m.teamFrequency else m.ffaFrequency;f=if m.specialFrequency>=0 then m.specialFrequency elseif mf>0 then mf else m.multiplayerFrequency end
        for _=1,f do table.insert(out,m.type)end
    end;return out
end
function Playlist:generateNewPlaylist(kind,mode)
    local maps=self:buildMapsList(kind,mode);assert(#maps>0,"Empty public map playlist")
    local rng=Random.new(self.now())
    local function shuffle()
        local out=table.clone(maps);for i=#out,2,-1 do local j=Random.int(rng,0,i)+1;out[i],out[j]=out[j],out[i]end;return out
    end
    if self.availability and #maps>3 then
        -- Three distinct maps cannot satisfy the source five-map exclusion.
        -- Each failed attempt consumes exactly #maps-1 random draws. Retain
        -- those draws and the exact final fallback, skipping only placement.
        for _=1,10000*(#maps-1)do Random.next(rng)end
        return shuffle()
    end
    for _=1,10000 do
        local source,out=shuffle(),{};local success=true
        while #source>0 do
            local chosen
            for i,m in source do local found=false;for j=math.max(1,#out-4),#out do if out[j]==m then found=true;break end end;if not found then chosen=i;break end end
            if not chosen then success=false;break end;table.insert(out,table.remove(source,chosen))
        end
        if success then return out end
    end;return shuffle()
end
function Playlist:getNextMap(kind,mode)
    local key=if kind=="special"then (if mode=="Team"then "specialTeam"else "specialFfa")else kind
    if #self.state.playlists[key]==0 then self.state.playlists[key]=self:generateNewPlaylist(kind,mode)end
    return table.remove(self.state.playlists[key],1)
end
function Playlist:getTeamCount(map)
    local forced=info[map].specialTeamCount
    if forced and self.random()<.75 then return forced end
    local r=self.random()*100;local total=0;for _,w in weights do total+=w[2];if r<total then return w[1]end end;return 2
end
function Playlist:supportsCompactMapForTeams(map,t)
    local c=Playlist.counts(Land[map]);local p=math.max(3,math.floor(math.min(math.ceil(c[3]*1.5),c[1])*.25))
    return supports(adjust(p,t),t)
end
function Playlist:lobbyMaxPlayers(map,mode,compact)
    local c=Playlist.counts(Land[map]);local r=self.random();local base=if r<.3 then c[1]elseif r<.6 then c[2]else c[3]
    local p=math.min(if mode=="Team"then math.ceil(base*1.5)else base,c[1]);return if compact then math.max(3,math.floor(p*.25))else p
end
-- V8's short-array TimSort: the reference deliberately uses a random comparator,
-- so its run scan and binary insertion comparison order is retained (pool <64).
function Playlist:sortTickets(pool)
    if #pool<2 then return pool end
    local descending=self.random()<.5;local run=2
    while run<#pool do local less=self.random()<.5;if less~=descending then break end;run+=1 end
    if descending then for i=1,math.floor(run/2)do pool[i],pool[run-i+1]=pool[run-i+1],pool[i]end end
    for start=run+1,#pool do local pivot=pool[start];local left,right=1,start
        while left<right do local mid=math.floor((left+right)/2);if self.random()<.5 then right=mid else left=mid+1 end end
        for j=start,left+1,-1 do pool[j]=pool[j-1]end;pool[left]=pivot
    end;return pool
end
local function modifiers(selected)
    local out={};for key in selected do if not string.match(key,"^startingGold")and key~="goldMultiplier"then out[key]=true end end
    out.startingGold=if selected.startingGold25M then 25000000 elseif selected.startingGold5M then 5000000 elseif selected.startingGold1M then 1000000 else nil
    out.goldMultiplier=if selected.goldMultiplier then 2 else nil;return out
end
function Playlist:getRandomSpecialGameModifiers(excluded,count,reduction)
    local counts={1,1,1,2,2,2,2,2,3,3};local rolled=counts[math.floor(self.random()*10)+1];local k=math.max(0,(count or rolled)-(reduction or 0))
    local pool={};for _,entry in tickets do if not excluded[entry[1]]then for _=1,entry[2]do table.insert(pool,entry[1])end end end;self:sortTickets(pool)
    local selected={};local n=0;for _,key in pool do if n>=k then break end
        local blocked=false;for _,pair in exclusive do if key==pair[1]and selected[pair[2]]or key==pair[2]and selected[pair[1]]then blocked=true;break end end
        if not blocked and not selected[key]then selected[key]=true;n+=1 end
    end;return modifiers(selected)
end
function Playlist:gameConfig(kind)
    assert(kind=="ffa"or kind=="team"or kind=="special")
    -- Ashton 2026-10-12: every public match is free for all (custom rooms can still pick Teams). With ffaOnly the
    -- team queue builds an ordinary FFA match and the special queue keeps its chaos rules but never draws Team.
    local card=kind -- PF043: the card it runs on (seats are per card, before the team card turns FFA)
    if self.ffaOnly and kind=="team"then kind="ffa"end
    self.state.scheduled+=1;local trusted=self.state.scheduled%7==0
    local mode=if kind=="special"then (if self.random()<.5 then "Free For All"else "Team")elseif kind=="ffa"then "Free For All"else "Team"
    if self.ffaOnly then mode="Free For All"end
    local map=self:getNextMap(kind,mode);local t=if mode=="Team"then self:getTeamCount(map)else nil
    local mods={}
    if kind~="special"then mods.isCompact=if #self.state.playlists[kind]%3==0 then true else nil
        if mods.isCompact and t and not self:supportsCompactMapForTeams(map,t)then mods.isCompact=nil end
    else
        local ex={};if trusted or not self.crowded then ex.isCrowded=true end
        if t and not self:supportsCompactMapForTeams(map,t)then ex.isCompact=true end
        if t=="Duos"or t=="Trios"or t=="Quads"then ex.isRandomSpawn=true end
        if t then ex.isHardNations=true;if map=="Four Islands"then ex.goldMultiplier=true end;if info[map].specialTeamCount then ex.isNukesDisabled=true end end
        if t=="Humans Vs Nations"then ex.startingGold25M=true;ex.isPeaceTime=true end
        for _,key in info[map].disabledModifiers or {}do ex[key]=true end
        local forced,order={},{}
        for _,entry in info[map].forcedModifiers or {}do local pieces=string.split(entry,":");local key=pieces[1];local chance=if pieces[2]then (tonumber(pieces[2])or 0)/100 else 1
            if not ex[key]and self.random()<chance then
                if not forced[key]then table.insert(order,key);forced[key]=true end;ex[key]=true
                for _,pair in exclusive do if key==pair[1]then ex[pair[2]]=true elseif key==pair[2]then ex[pair[1]]=true end end
            end
        end
        forced={};for i=1,math.min(3,#order)do forced[order[i]]=true end
        mods=self:getRandomSpecialGameModifiers(ex,nil,math.min(3,#order));for key,value in modifiers(forced)do mods[key]=value end
        if mods.isCrowded and (Playlist.counts(Land[map])[1]>60 or not self.crowded)then mods.isCrowded=nil
            if next(mods)==nil then ex.isCrowded=true;mods=self:getRandomSpecialGameModifiers(ex,1,0)end
        end
    end
    if self.availability then mods.isCompact=true end
    local p=if mods.isCrowded then (if mods.isCompact then 60 else 125)else self:lobbyMaxPlayers(map,mode,mods.isCompact)
    if trusted then p=math.min(p,25)end
    p=math.min(p,self.maxPlayers) -- Ashton approved the configured Roblox capacity.
    if kind=="special"and self.seats and self.seats[card]then p=math.min(p,self.seats[card])end -- PF043 small population
    if self.availability and kind~="special"then
        -- OF-017 approved Atlas bands use actual Compact map identity. Keep the
        -- source random draws above, AI/tuning below, and special queue unchanged.
        p=math.min(assert(normalCapacity[map],"Missing Compact capacity band")[kind],math.floor(self.maxPlayers))
        if self.seats and self.seats[card]then p=math.min(p,self.seats[card])end -- PF043 small population
        assert(p>=2,"Public matches require a host capacity of at least two")
        if t then p,t=normalTeamCapacity(p,t)end
    else
        if type(t)=="number"and not supports(adjust(p,t),t)then t=math.max(2,math.floor(p/2))end
        p=math.max(2,adjust(p,t))
    end
    if self.availability and t=="Humans Vs Nations"then p=math.min(p,Availability.MaxNations)end
    local disabled={};if mods.isNukesDisabled then disabled={"Missile Silo","Atom Bomb","Hydrogen Bomb","MIRV","SAM Launcher"}elseif mods.isSAMsDisabled then disabled={"SAM Launcher"}end
    local gold=mods.startingGold;local immunity=if mods.isPeaceTime then 2400 elseif t=="Humans Vs Nations"then 50 elseif gold and gold>=25000000 then 1500 elseif gold and gold>=5000000 then 450 else 50
    local config={gameType="Public",gameMode=mode,gameMap=map,gameMapSize=if mods.isCompact then "Compact"else "Normal",maxPlayers=p,
        playerTeams=t or 2,publicGameModifiers=mods,difficulty=if mods.isHardNations or t=="Humans Vs Nations"then "Hard"else "Medium",
        donateGold=t~=nil,donateTroops=t~=nil,infiniteGold=false,infiniteTroops=false,instantBuild=false,randomSpawn=mods.isRandomSpawn==true,
        nations=if t and t~="Humans Vs Nations"or gold and gold>=25000000 then "disabled"else "default",bots=if mods.isCompact then 100 else 400,
        spawnImmunityDuration=immunity,disabledUnits=disabled,disableClanTags=if not t then true else nil,
        startingGold=gold,goldMultiplier=mods.goldMultiplier,disableAlliances=mods.isAlliancesDisabled,waterNukes=mods.isWaterNukes,
        trusted=if trusted and not self.openTrust then true else nil}
    if kind=="ffa"then config.overtime={enabled=true,startMinutes=30}end
    if mods.isDoomsdayClock then local speeds={"slow","normal","fast","veryfast"};config.doomsdayClock={enabled=true,speed=speeds[math.floor(self.random()*4)+1]}end
    if self.availability then config.bots=math.min(config.bots,Availability.MaxTribes)end
    return config
end
return table.freeze(Playlist)
