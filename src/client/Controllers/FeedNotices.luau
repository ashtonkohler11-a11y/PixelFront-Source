--!strict
-- PF045 (PF - 3 + MM; Ashton: "I keep hearing cool sounds but I have no clue what they are for"): every match sound a player
-- hears gets something on screen. One feed line (the bottom-left notice stack, DiplomacyController:addNotice) per moment, the
-- conditions copied from AudioCues.diff so a line and its sound always pair. NoticeKind sets the tone and the sound family
-- (Sfx: DANGER / WARNING get the low alert, POSITIVE the soft toast).
--   g_crown   "You're #1"                    b_station "Train station built"
--   g_tribe   "You took {tribe}"             b_gold    "You can afford a City" (MatchGuide's City tip the first time; one message)
--   n_*hit    "Your Atom Bomb hit {name}"    n_sam     "{name} shot down your Atom Bomb"
--   n_land    "Your boat landed"             d_target  "{name} targeted you"      d_embargo "{name} embargoed you"
-- (b_train / b_trade: the "+X" by the gold readout is CityController's own bonus flash; no feed line.)
--   g_incoming (sound v3: it plays off screen too) "{name} is attacking you" (DANGER, tap = the camera to them) when the
--   attack's source is off screen; on screen the attack column already shows it
local Feed=require(script.Parent.MatchPacketFeed)
local M={}
M.say=nil :: ((string,string,string?,number?)->())? -- set by attach (PF - 4)
local BOMBS={["Atom Bomb"]="AtomBomb",["Hydrogen Bomb"]="HydrogenBomb",["MIRV Warhead"]="MIRV"}
local BOMB_NAMES={["Atom Bomb"]="Atom Bomb",["Hydrogen Bomb"]="Hydrogen Bomb",["MIRV Warhead"]="MIRV"}
local STRUCTURES={"cities","ports","factories","defensePosts","missileSilos","samLaunchers"}
local function ownerById(state: any,id: any): number?
    for owner,p in state.players or {} do if p.id==id then return owner end end
    return nil
end
local function name(state: any,owner: number?): string
    local p=owner and state.players and state.players[owner]
    return (owner and state.names and state.names[owner]) or (p and p.name) or "A rival"
end
local function after(list: any,cursor: number?,field: string): {any}
    local out={};if cursor==nil then return out end
    for _,e in list or {} do if (tonumber(e[field]) or 0)>cursor then table.insert(out,e) end end
    return out
end
local function maxId(list: any,field: string,fallback: number?): number
    local v=fallback or 0;for _,e in list or {} do v=math.max(v,tonumber(e[field]) or 0) end;return v
end
-- diff(state, packet, memory, cityPrice?, offscreen?) -> {{text, kind, glyph, focus?, city?}} (pure; AudioCues.diff's conditions)
-- offscreen(tile) -> boolean: the map's view (nil: nothing counts as off screen)
function M.diff(state: any,packet: any,m: any,cityPrice: number?,offscreen: ((number)->boolean)?): {any}
    local out={}
    local function say(text: string,kind: string,glyph: string,focus: number?) table.insert(out,{text=text,kind=kind,glyph=glyph,focus=focus}) end
    if type(state)~="table" or not state.players then return out end
    local first=m.started~=true;m.started=true
    if packet and packet.spectator==true then return out end
    local phase=state.phase
    local mine=(state.counts and state.counts[1]) or 0
    -- 1. the crown: you take #1 by land (two alive or more, after the spawn)
    if phase~="Choosing" and mine>0 then
        local top=true;local alive=0
        for owner,count in state.counts or {} do if count>0 then alive+=1 end;if owner~=1 and count>=mine then top=false end end
        if top and alive>=2 and m.top==false then say("You're #1","POSITIVE","TeamHUDLeaderboardIconSolidWhite") end
        m.top=top
    end
    -- 0. a new attack on you from a player / nation whose source is off screen (AudioCues' g_incoming)
    local seenAttacks=m.attacks or {};local attacks={}
    for _,a in state.attacks or {} do
        attacks[a.id]=true
        if not first and not seenAttacks[a.id] and a.owner~=1 and a.targetOwner==1 and (a.owner or 0)>0 then
            local p=state.players[a.owner]
            if p and p.playerType~="Bot" and offscreen and type(a.sourceTile)=="number" and offscreen(a.sourceTile) then
                say(name(state,a.owner).." is attacking you","DANGER","DiplomacySoldierAttack",a.owner)
            end
        end
    end
    m.attacks=attacks
    -- 2. a tribe you conquered
    local myId=state.players[1] and state.players[1].id
    for _,e in after(state.conquestEvents,m.conquestCursor,"id") do
        local victim=ownerById(state,e.conqueredId)
        local p=victim and state.players[victim]
        if (e.conquerorId==myId or e.conquerorId==1) and p and p.playerType=="Bot" then say("You took "..name(state,victim),"POSITIVE","TeamHUDClaimIcon") end
    end
    m.conquestCursor=maxId(state.conquestEvents,"id",state.conquestEventCursor or m.conquestCursor)
    -- 3. a train station on one of your structures
    m.stations=m.stations or {}
    local stations={}
    for _,list in STRUCTURES do for _,u in state[list] or {} do
        if u.owner~=1 or u.active==false then continue end
        stations[u.id]=u.hasTrainStation==true
        if not first and u.hasTrainStation and m.stations[u.id]==false then say("Train station built","POSITIVE","FactoryGlyph") end
    end end
    m.stations=stations
    -- 5. the next City is affordable (the gold chime): the caller routes it (MatchGuide's tip, else this line)
    if type(cityPrice)=="number" and phase~="Choosing" then
        local gold=(state.gold and state.gold[1]) or 0
        if gold>=cityPrice and m.goldBelow==true then table.insert(out,{text="You can afford a City",kind="POSITIVE",glyph="CityGlyph",city=true}) end
        m.goldBelow=gold<cityPrice
    end
    -- 6-8. your bombs (hit / shot down) and your boat landing
    for _,e in after(state.deadUnitEvents,m.deadCursor,"eventId") do
        local kind=e.unitType
        if e.owner==1 and BOMBS[kind] then
            local victim=state.owners and state.owners[e.tileId]
            if e.reachedTarget then
                if victim and victim>0 and victim~=1 then say("Your "..BOMB_NAMES[kind].." hit "..name(state,victim),"POSITIVE",BOMBS[kind],victim)
                else say("Your "..BOMB_NAMES[kind].." landed","POSITIVE",BOMBS[kind]) end
            else
                -- the event names no shooter: the enemy SAM nearest the intercept
                local by=nil;local w=state.map and state.map.width;local best=math.huge
                if w and type(e.tileId)=="number" then
                    local x,y=(e.tileId-1)%w,(e.tileId-1)//w
                    for _,sam in state.samLaunchers or {} do
                        if sam.owner~=1 and sam.active~=false then
                            local d=((sam.tileId-1)%w-x)^2+((sam.tileId-1)//w-y)^2
                            if d<best then best,by=d,sam.owner end
                        end
                    end
                end
                say((if by then name(state,by) else "A SAM").." shot down your "..BOMB_NAMES[kind],"WARNING","SAMLauncherGlyph",by)
            end
        elseif kind=="Transport" and e.owner==1 and e.reachedTarget then say("Your boat landed","POSITIVE","Boat") end
    end
    m.deadCursor=maxId(state.deadUnitEvents,"eventId",state.deadUnitEventCursor or m.deadCursor)
    -- 9-10. targeted / embargoed
    for _,e in after(state.diplomacyEvents,m.diplomacyCursor,"eventId") do
        if e.type=="TargetPlayer" and e.targetID==1 then
            local by=if type(e.playerID)=="number" then e.playerID else ownerById(state,e.playerID)
            say(name(state,by).." targeted you","DANGER","DiplomacyTarget",by)
        elseif e.type=="Embargo" and (e.targetID==1 or e.recipientID==1) then
            local by=if type(e.playerID)=="number" then e.playerID else ownerById(state,e.playerID)
            say(name(state,by).." embargoed you","WARNING","DiplomacyStopTrade",by)
        end
    end
    m.diplomacyCursor=maxId(state.diplomacyEvents,"eventId",state.diplomacyEventCursor or m.diplomacyCursor)
    return out
end
local bound=false
-- attach(getDiplomacy): MatchController wires it once; a new match (a falling match id) starts a fresh memory
function M.attach(getDiplomacy: () -> any)
    if bound then return end;bound=true
    local memory: any={};local matchId: any=nil
    local okE,Economy=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.OpenFrontEconomy) end)
    local okG,Guide=pcall(require,script.Parent.MatchGuide)
    -- off screen = outside the map's viewport (the World frame's tiles mapped to the screen)
    local function offscreen(state: any): ((number)->boolean)?
        local pg=game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
        local panel=pg and pg:FindFirstChild("OpenFrontMap");panel=panel and panel:FindFirstChild("MapPanel")
        local view=panel and panel:FindFirstChild("Viewport");local world=view and view:FindFirstChild("World")
        if not (view and world and state.map) then return nil end
        local w,h=state.map.width,state.map.height
        return function(tile: number): boolean
            local x,y=(tile-1)%w,(tile-1)//w
            local p=world.AbsolutePosition+Vector2.new((x+.5)/w*world.AbsoluteSize.X,(y+.5)/h*world.AbsoluteSize.Y)
            local a,b=view.AbsolutePosition,view.AbsolutePosition+view.AbsoluteSize
            return p.X<a.X or p.Y<a.Y or p.X>b.X or p.Y>b.Y
        end
    end
    local lastTicks=0
    -- PF - 4: another controller's one feed line (PremiumFx: "Captured Bank!" / "Your Tesla Coil was destroyed")
    M.say=function(text: string,kind: string,glyph: string?,focus: number?)
        local d=getDiplomacy()
        if d and type(d.addNotice)=="function" then pcall(function() d:addNotice(text,focus,lastTicks,kind,nil,glyph) end) end
    end
    Feed.subscribe(function(packet: any)
        local state=type(packet)=="table" and packet.state
        if type(state)~="table" then return end
        lastTicks=state.ticks or lastTicks
        if packet.matchId~=matchId then matchId=packet.matchId;memory={} end
        local price=nil
        if okE and type(Economy)=="table" and Economy.cityCost then local ok,v=pcall(Economy.cityCost,state,1);if ok and type(v)=="number" then price=v end end
        local d=getDiplomacy()
        for _,n in M.diff(state,packet,memory,price,offscreen(state)) do
            -- the City: the guide's tip the first time (one message), a feed line after
            if n.city and okG and type(Guide)=="table" and Guide.affordCity and Guide.affordCity() then continue end
            if d and type(d.addNotice)=="function" then pcall(function() d:addNotice(n.text,n.focus,state.ticks,n.kind,nil,n.glyph) end) end
        end
    end)
end
return M
