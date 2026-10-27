--!strict
-- PF043 H (PF - 3; the approved list, work/pf043/sounds/list.mjs): the match's sounds, read from each decoded packet
-- (MatchPacketFeed, presentation only; you are owner 1). It also drives the music (start, intensity, climax, the result
-- stinger). Existing callers keep their cues (DiplomacyController's alliance / chat sounds, MatchController's spawn and
-- result cues): those resolve to their new sounds in OpenFrontAudioMapping and are not repeated here.
-- Cues.diff(previous, state, packet, memory) -> {{name, perKey?}} is pure (tested); Cues.new binds it to the feed.
local Feed=require(script.Parent.MatchPacketFeed)
local Cues={};Cues.__index=Cues
local STRUCTURES={{"cities","b_city"},{"ports","b_port"},{"factories","b_factory"},{"defensePosts","b_post"},{"missileSilos","b_silo"},{"samLaunchers","b_sam"}}
local LAUNCH={["Atom Bomb"]="n_atom",["Hydrogen Bomb"]="n_hydro",MIRV="n_mirv"}
local HIT={["Atom Bomb"]="n_atomhit",["Hydrogen Bomb"]="n_hydrohit",["MIRV Warhead"]="n_mirvhit"}
local SHIPS={Transport=true,Warship=true,["Trade Ship"]=true}
Cues.FAR=.35 -- PF045 v2: another player's event on screen plays ~9 dB under yours (minor: learn to ignore it)
Cues.CLIMAX_SHARE=.8 -- Last Stand: top 2 with this share of the win line
Cues.PEAK_SHARE=.25 -- ... or down to this share of your peak land
local function isBot(state: any,owner: number): boolean local p=state.players and state.players[owner];return p~=nil and p.playerType=="Bot" end
-- events name players by their id (player.id); the state indexes them by owner
local function ownerById(state: any,id: any): number?
    for owner,p in state.players or {} do if p.id==id then return owner end end
    return nil
end
local function eventsAfter(list: any,cursor: number?,field: string): {any}
    local out={};if cursor==nil then return out end
    for _,e in list or {} do if (tonumber(e[field]) or 0)>cursor then table.insert(out,e) end end
    return out
end
local function maxId(list: any,field: string,fallback: number?): number
    local m=fallback or 0;for _,e in list or {} do m=math.max(m,tonumber(e[field]) or 0) end;return m
end
-- memory: what earlier packets left (units seen, cursors, the peak, counters). Returns the cues for this packet.
function Cues.diff(state: any,packet: any,m: any): {any}
    local out={}
    -- opts (PF045 v3): {size=k} the magnitude file, {tile=t} a map event's pan
    local function cue(name: string,perKey: any?,scale: number?,opts: any?) table.insert(out,{name=name,perKey=perKey,scale=scale,opts=opts}) end
    local function sizeOf(share: number,cuts: {number}): number local s=1;for _,c in cuts do if share>=c then s+=1 end end;return s end
    if type(state)~="table" or not state.players then return out end
    local first=m.started~=true
    m.started=true
    -- PF045 (Ashton: every sound heard maps to something seen): others' far-off events only sound when their tile is in view.
    -- m.inView is set from the map's view (Cues:packet); without one (tests, no map yet) everything counts as seen.
    local function seen(tile: any): boolean return m.inView==nil or m.inView(state,tile) end
    local function onMine(tile: any): boolean return state.owners~=nil and type(tile)=="number" and state.owners[tile]==1 end
    local mine=(state.counts and state.counts[1]) or 0
    -- the phase: the battle begins; the result
    local phase=state.phase
    if not first and m.phase=="Choosing" and phase~="Choosing" and phase~=nil then cue("g_start") end
    -- spawn countdown: the last 5 s of the ring tick once a second
    if phase=="Choosing" and type(m.spawnSeconds)=="number" and m.spawnSeconds>=1 and m.spawnSeconds<=5 and m.lastTick~=m.spawnSeconds then
        m.lastTick=m.spawnSeconds;cue("u_count")
    end
    m.phase=phase
    if packet and packet.spectator==true and not m.spectating then m.spectating=true;if not first then cue("g_spectate") end end
    -- eliminated: your land reaches 0 after you had some
    if (m.peak or 0)>0 and mine==0 and phase~="Choosing" and not m.lost then m.lost=true;cue("g_lost") end
    m.peak=math.max(m.peak or 0,mine)
    -- attacks: yours sent / retreating / counter; incoming from players; your expansion into wilderness
    local attacks={}
    local seenAttack=m.attacks or {}
    local attackingMe={}
    for _,a in state.attacks or {} do
        attacks[a.id]=a
        if a.targetOwner==1 and a.owner~=1 then attackingMe[a.owner]=true end
    end
    for _,a in state.attacks or {} do
        local was=seenAttack[a.id]
        -- PF045 v3 "one input, one hit": your sends, counters and retreats sound on the click (MatchController), never
        -- again here. An attack on you: the alarm (on screen or off: the RTS "under attack"), sized by its troops against
        -- yours, panned toward where it comes from
        if not was and not first and a.owner~=1 and a.targetOwner==1 and (a.owner or 0)>0 and not isBot(state,a.owner) then
            local troops=(state.troops and state.troops[1]) or 0
            cue("g_incoming",a.owner,nil,{size=sizeOf((a.budget or 0)/math.max(1,troops),{.15,.4}),tile=a.sourceTile})
        end
    end
    local nextSeen={};for id,a in attacks do nextSeen[id]={retreating=a.retreating==true} end
    m.attacks=nextSeen
    -- PF045 v3.2 expansion pops (Ashton: "an expanding pop noise ... it felt more interactive"): while YOUR push into
    -- wilderness / a tribe / a nation is gaining land, a soft pop per gain (SoundList cd: ~4 a second at most), the pitch
    -- rising a little as the push keeps succeeding (+0.6% a pop, up to +7%), +-6% jitter. Two packets without a gain end it.
    local expanding=false
    for _,a in state.attacks or {} do
        if a.owner==1 then
            local t=a.targetOwner or 0
            local p=t>0 and state.players[t]
            if t==0 or (p and (p.playerType=="Bot" or p.playerType=="Nation")) then expanding=true;break end
        end
    end
    if not first and phase~="Choosing" and expanding and mine>(m.lastCount or 0) then
        m.expandStreak=(m.expandStreak or 0)+1;m.expandIdle=0
        local rise=1+math.min(m.expandStreak,12)*.006
        cue("g_expand",nil,nil,{pitch=rise*(1+(math.random()*2-1)*.06)})
    else
        m.expandIdle=(m.expandIdle or 0)+1
        if m.expandIdle>=2 then m.expandStreak=0 end
    end
    m.lastCount=mine
    -- conquests (yours: a player / nation or a tribe; others': a nation falls)
    local myId=state.players[1] and state.players[1].id
    for _,e in eventsAfter(state.conquestEvents,m.conquestCursor,"id") do
        local victim=ownerById(state,e.conqueredId)
        local bot=victim~=nil and isBot(state,victim)
        if e.conquerorId==myId or e.conquerorId==1 then cue(if bot then "g_tribe" else "g_conquer")
        elseif victim~=nil and victim~=1 and state.players[victim] and state.players[victim].playerType=="Human" then cue("g_fallen") end -- v2: players only
    end
    m.conquestCursor=maxId(state.conquestEvents,"id",state.conquestEventCursor or m.conquestCursor)
    -- the crown: you take #1 by land (two players or more, after the spawn)
    if phase~="Choosing" and mine>0 then
        local top=true;local alive=0
        for owner,count in state.counts or {} do if count>0 then alive+=1 end;if owner~=1 and count>=mine then top=false end end
        if top and alive>=2 and m.top==false then cue("g_crown") end
        m.top=top
    end
    -- structures: placed (construction starts), finished (its own sound), upgraded; stations; demolished
    m.units=m.units or {}
    local units=m.units
    local nextUnits={}
    for _,spec in STRUCTURES do
        for _,u in state[spec[1]] or {} do
            if u.owner~=1 or u.active==false then continue end
            local was=units[u.id]
            nextUnits[u.id]={building=u.underConstruction==true,level=u.level or 1,station=u.hasTrainStation==true}
            if first then continue end
            -- (v3: placing, upgrading and demolishing sound on the click; the finish is the building's own sound)
            if not was then
                if not u.underConstruction then cue(spec[2],nil,nil,{tile=u.tileId}) end
            else
                if was.building and not u.underConstruction then cue(spec[2],nil,nil,{tile=u.tileId}) end
                if u.hasTrainStation and not was.station then cue("b_station") end
            end
        end
    end
    m.units=nextUnits
    -- gold: trains, trade, and the price of your next City
    for _,pair in {{"trainGold","b_train"},{"tradeGold","b_trade"}} do
        local v=state[pair[1]] and state[pair[1]][1]
        if not first and type(v)=="number" and type(m[pair[1]])=="number" and v>m[pair[1]] then cue(pair[2]) end
        m[pair[1]]=v
    end
    if type(m.cityPrice)=="number" and phase~="Choosing" then
        local gold=(state.gold and state.gold[1]) or 0
        if gold>=m.cityPrice and (m.goldBelow==true) then cue("b_gold",m.cityPrice) end
        m.goldBelow=gold<m.cityPrice
    end
    -- ships: your boats and warships launched
    m.ships=m.ships or {}
    local ships={}
    for _,s in state.ships or {} do if s.owner==1 then ships[s.id]=true end end -- (v3: a boat sounds on the click)
    for _,s in state.warships or {} do if s.owner==1 and s.active~=false then ships[s.id]=true;if not first and not m.ships[s.id] then cue("n_warship") end end end
    m.ships=ships
    -- your warships' shells
    m.shells=m.shells or {}
    local shells={}
    for _,sh in state.shells or {} do if sh.owner==1 then shells[sh.id]=true;if not first and not m.shells[sh.id] and seen(sh.tileId) then cue("n_cannon",nil,nil,{tile=sh.tileId}) end end end
    m.shells=shells
    -- nukes: your launches; aimed at you (siren); impacts; SAM intercepts (from the dead-unit events)
    m.nukes=m.nukes or {}
    local nukes={}
    local inbound=false
    for _,n in state.nukes or {} do
        nukes[n.id]=true
        local aimed=n.targetOwner==1 or (state.owners and n.targetTile and state.owners[n.targetTile]==1)
        if aimed and n.owner~=1 then inbound=true end
        if not first and not m.nukes[n.id] then
            if n.owner==1 and LAUNCH[n.unitType] then cue(LAUNCH[n.unitType]) end
            if aimed and n.owner~=1 and n.unitType~="MIRV Warhead" then cue("n_warning") end
        end
    end
    m.nukes=nukes
    for _,e in eventsAfter(state.deadUnitEvents,m.deadCursor,"eventId") do
        local kind=e.unitType
        -- impacts / intercepts: yours or on your land at full level; another player's only in view, Cues.FAR quieter;
        -- your ships sunk always, others' warships in view (quieter)
        local mineNear=e.owner==1 or onMine(e.tileId)
        local scale=if mineNear then nil else Cues.FAR
        local near=mineNear or seen(e.tileId)
        local at={tile=e.tileId}
        if HIT[kind] and e.reachedTarget then if near then cue(HIT[kind],nil,scale,at) end
        elseif HIT[kind] and not e.reachedTarget then if near then cue("n_sam",nil,scale,at) end
        elseif kind=="Transport" and e.owner==1 and e.reachedTarget then cue("n_land",nil,nil,at)
        elseif SHIPS[kind] and not e.reachedTarget and e.owner==1 then cue("n_sunk",nil,nil,at)
        elseif kind=="Warship" and not e.reachedTarget and seen(e.tileId) then cue("n_sunk",nil,Cues.FAR,at) end
    end
    m.deadCursor=maxId(state.deadUnitEvents,"eventId",state.deadUnitEventCursor or m.deadCursor)
    -- diplomacy the source layer leaves silent (DiplomacyController keeps requests, replies, betrayal, chat)
    for _,e in eventsAfter(state.diplomacyEvents,m.diplomacyCursor,"eventId") do
        if e.type=="DonateEvent" then
            local recipient=if type(e.recipientId)=="number" then e.recipientId else ownerById(state,e.recipientId)
            if recipient==1 then -- v3: sized by the gift against what you had
                local gold=e.donationType=="gold"
                local have=(if gold then (state.gold and state.gold[1]) else (state.troops and state.troops[1])) or 0
                local amount=tonumber(e.amount) or 0
                cue(if gold then "d_gold" else "d_troops",nil,nil,{size=sizeOf(amount/math.max(1,have),{.1,.35})})
            end
        elseif e.type=="Emoji" then
            local emoji=e.emoji or e
            if emoji.recipientID==1 then cue("d_emoji") end
        elseif e.type=="TargetPlayer" and e.targetID==1 then cue("d_target")
        elseif e.type=="AllianceExtension" and e.playerID==1 then cue("d_expire",e.allianceID)
        elseif e.type=="Embargo" and (e.targetID==1 or e.recipientID==1) then cue("d_embargo") end
    end
    m.diplomacyCursor=maxId(state.diplomacyEvents,"eventId",state.diplomacyEventCursor or m.diplomacyCursor)
    -- the music's inputs: how hard the fighting is, and whether it is the end game
    local intensity=0
    for _,a in state.attacks or {} do
        if a.targetOwner==1 and (a.owner or 0)>0 and not isBot(state,a.owner) then intensity=1;break end
        if a.owner==1 and (a.targetOwner or 0)>0 and not isBot(state,a.targetOwner) then intensity=math.max(intensity,.7) end
    end
    if inbound then intensity=1 end
    m.intensity=intensity
    local rank,leader=1,0
    for owner,count in state.counts or {} do if owner~=1 and count>mine then rank+=1 end;leader=math.max(leader,count) end
    local land=(state.landCount or (state.map and state.map.landCount) or 0)-(state.falloutCount or 0)
    local winShare=(m.winPercent or 80)/100
    m.climax=(m.overtime==true) or (mine>0 and rank<=2 and land>0 and mine/land>=winShare*Cues.CLIMAX_SHARE)
        or ((m.peak or 0)>=200 and mine>0 and mine<(m.peak or 0)*Cues.PEAK_SHARE)
    return out
end

-- PF045 v2: the Arsenal weapons, from the server's "Premium" packet (PremiumItems.packet: owners as you see them, 1 = you).
-- Yours at full level; another player's only in view, Cues.FAR quieter. inView(tile) -> boolean (nil: all in view).
Cues.WORK_GAP=4 -- seconds between your Tesla Coils' work sounds
local PREMIUM_LAUNCH={airdrop="p_airdrop",blitz_bomb="p_blitz",titan_bomb="p_titan"} -- (the Longshot is retired)
local PREMIUM_HIT={blitz_bomb="p_blitzhit",titan_bomb="p_titanhit"}
function Cues.premium(packet: any,m: any,inView: ((number) -> boolean)?): {any}
    local out={}
    if type(packet)~="table" or packet.kind~="Premium" then return out end
    local first=m.premiumCursor==nil
    local function cue(name: string,owner: any,tile: any)
        if owner==1 then table.insert(out,{name=name,opts={tile=tile}})
        elseif inView==nil or (type(tile)=="number" and inView(tile)) then table.insert(out,{name=name,scale=Cues.FAR,opts={tile=tile}}) end
    end
    local cursor=m.premiumCursor or 0
    for _,e in packet.events or {} do
        local id=tonumber(e.id) or 0
        if not first and id>cursor then
            if e.kind=="launch" and PREMIUM_LAUNCH[e.item] then cue(PREMIUM_LAUNCH[e.item],e.owner,e.tile)
            elseif e.kind=="detonate" and PREMIUM_HIT[e.item] then cue(PREMIUM_HIT[e.item],e.owner,e.tile)
            elseif e.kind=="airdrop" and e.landed then cue("p_chutes",e.owner,e.tile)
            elseif e.kind=="intercepted" then cue("n_sam",e.owner,e.tile) end
        end
        cursor=math.max(cursor,id)
    end
    m.premiumCursor=cursor
    -- your Arsenal buildings finishing (once: b.built is the tick it finishes, so done = the packet's tick has reached it;
    -- PF - 4: comparing it with true re-played b_premium on every packet, Ashton's "bell that plays over and over")
    local built=m.premiumBuilt or {}
    local nextBuilt={}
    local now=tonumber(packet.ticks) or 0
    for _,b in packet.buildings or {} do
        if b.owner==1 then
            local done=type(b.built)=="number" and now>=b.built
            nextBuilt[b.id]=done
            if not first and done and built[b.id]==false then table.insert(out,{name="b_premium",opts={tile=b.tile}}) end
        end
    end
    m.premiumBuilt=nextBuilt
    -- your Tesla Coils / Artillery at work (the stats count zaps and shells)
    local s=packet.stats
    if type(s)=="table" then
        -- PF - 4: a coil zaps every second, so its sound is held to one per WORK_GAP and plays as a map sound (zoom-scaled)
        local now=os.clock()
        if not first and type(m.zapped)=="number" and (s.zapped or 0)>m.zapped and now-(m.teslaAt or -math.huge)>=Cues.WORK_GAP then
            m.teslaAt=now;table.insert(out,{name="p_tesla",opts={map=true}}) end
        if not first and type(m.shelled)=="number" and (s.shelled or 0)>m.shelled then table.insert(out,{name="p_artillery",opts={map=true}}) end
        m.zapped=s.zapped or 0;m.shelled=s.shelled or 0
    end
    return out
end

function Cues.new(audio: any): any
    local self=setmetatable({audio=audio,memory={},premiumMemory={}},Cues)
    self.off=Feed.subscribe(function(packet: any) self:packet(packet) end)
    -- the Premium packet arrives on the State remote beside the snapshot (guarded: no remotes in a test world)
    task.spawn(function()
        local ok,Remotes=pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes")) end)
        if not ok or type(Remotes)~="table" or not Remotes.client then return end
        local okR,remotes=pcall(Remotes.client);if not okR or not remotes or not remotes.State then return end
        self.premiumConnection=remotes.State.OnClientEvent:Connect(function(packet: any)
            if type(packet)~="table" then return end
            if packet.kind=="Home" then self.premiumMemory={};return end
            if packet.kind~="Premium" then return end
            local beds=self.audio.beds
            local view=if beds and beds.view then function(tile: number): boolean return beds:sees({map={width=packet.width}},tile) end else nil
            for _,c in Cues.premium(packet,self.premiumMemory,view) do self.audio:play(c.name,nil,nil,c.scale,c.opts) end
        end)
    end)
    return self
end
function Cues:reset() self.memory={};self.premiumMemory={} end
-- variant clocks (Overtime, Doomsday) and the spawn ring, from the HUD's own presentation rules (guarded)
local P: any=nil
local function presentation(): any
    if P==nil then local ok,mod=pcall(require,script.Parent:FindFirstChild("VariantHudPresentation") :: any);P=if ok then mod else false end
    return P or nil
end
function Cues:clocks(state: any)
    local m=self.memory;local p=presentation();if not p then return end
    local ok,seconds=pcall(p.timer,state,m.timerPrevious)
    if ok then
        local value=if type(seconds)=="number" then seconds elseif type(seconds)=="table" then seconds.seconds else nil
        m.timerPrevious=value
        if state.phase=="Choosing" then m.spawnSeconds=value
        else
            m.spawnSeconds=nil
            local okView,view=pcall(p.timerView,state,value or 0)
            if okView and view and view.flashSidebar and value and value>0 and m.doomTick~=value then m.doomTick=value;self.audio:play("g_doom") end
        end
    end
    local okO,o=pcall(p.overtime,state,1)
    local overtime=okO and o and o.visible==true
    if overtime and not m.overtime and m.overtime~=nil then self.audio:play("g_overtime") end
    m.overtime=overtime
    if okO and o and o.requiredPct then m.winPercent=o.requiredPct end
end
function Cues:packet(packet: any)
    local state=type(packet)=="table" and packet.state
    if type(state)~="table" then return end
    local m=self.memory
    if not m.started then
        -- the match's first packet: the music starts (First Steps in the tutorial)
        local tutorial=packet.tutorial~=nil or packet.tutorialMatch==true
        self.audio.music:startMatch(tutorial)
        m.tutorial=tutorial
    end
    self:clocks(state)
    -- the next City's price (the gold chime), guarded
    local okE,Economy=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.OpenFrontEconomy) end)
    if okE and type(Economy)=="table" and Economy.cityCost then local ok,price=pcall(Economy.cityCost,state,1);if ok and type(price)=="number" then m.cityPrice=price end end
    local beds=self.audio.beds
    m.inView=if beds and beds.view then function(s: any,tile: any): boolean return beds:sees(s,tile) end else nil
    for _,c in Cues.diff(state,packet,m) do self.audio:play(c.name,c.perKey,c.opts and c.opts.pitch,c.scale,c.opts) end
    -- the tutorial: each step done chimes; finishing it plays the fanfare (TutorialController reads the same packet)
    local tutorial=packet.tutorial
    if type(tutorial)=="table" then
        local step=tonumber(tutorial.step)
        if step and m.tutorialStep and step>m.tutorialStep then self.audio:play("u_step") end
        if step then m.tutorialStep=math.max(m.tutorialStep or 0,step) end
    end
    local music=self.audio.music
    if state.phase=="Won" or state.phase=="Lost" then
        local won=state.winner==1 or (state.winnerTeam~=nil and state.players[1] and state.players[1].team==state.winnerTeam)
        if won and m.tutorial then self.audio:play("u_tutdone") end
        music:finish(if won then "Won" else "Lost")
    else
        music:setIntensity(if m.tutorial then 0 else (m.intensity or 0))
        music:setClimax(not m.tutorial and m.climax==true)
    end
end
function Cues:destroy()
    if self.off then self.off();self.off=nil end
    if self.premiumConnection then self.premiumConnection:Disconnect();self.premiumConnection=nil end
end
return Cues
