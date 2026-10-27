--!strict
-- Roadmap #1 (PF - 1 client, PF - 2 server; boards work/daily/boards 1-3, approved): daily challenges + the login streak.
-- PF - 2's server fires OpenFrontRemotes.DailyState on load, on progress that matters, after each claim and at the UTC
-- resets (from the hub and from the match server alike):
--   {kind="Daily", loaded, day, resetAt, weekResetAt, rerolls,
--    daily={{id, kind="tiles"|"tribes"|"cities"|"nuke"|"survive"|"win", goal, progress, reward={cobalt, xp}, state="run"|"done"|"claimed"} ×3},
--    bonus={reward={cobalt}, done=0..3, state}, weekly={id, kind, goal, progress, reward={cobalt}, state},
--    streak={today=1..7, claimable, tiles={{cobalt} | {item="skin_grid"|"skin_stormfront", owned, cobalt}} ×7},
--    lastDone={id, at}?, lastClaim={target, id, granted, requestId?}?, matchGain={matchId, gains={[id]=gain}}?}
-- DailyCommand (client → server): {kind="Ready"} | {kind="Claim", target="daily"|"bonus"|"weekly"|"streak", id} | {kind="Reroll", id}.
-- PF - 2's server landed 2026-10-14 (docs/director/handoffs/PF-039-daily-challenges.md): kinds also include "nations";
-- lastClaim.status is "granted" | "claimed" | "failed"; rerolls = rerolls LEFT today; Ready is cheap (Client.refresh).
-- Every daily surface (the Play chips, the in-match notice, the end-card block, the streak popup) reads only this module.
-- The remotes are found lazily: a place without the server side never shows a challenge.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local Client={}
local state: any=nil
local listeners: {(any)->()}={}
local doneListeners: {(any,any)->()}={}
local claimListeners: {(any,any)->()}={}
local seenDone: string?=nil
local seenClaim: string?=nil
local started=false
local stub: any=nil -- Studio QA only (Client.useStub): a local stand-in for PF - 2's server

local function emit(list: {any},...)
    for _,listener in table.clone(list) do
        local ok,err=pcall(listener,...)
        if not ok then warn("[DailyClient] "..tostring(err)) end
    end
end
local function subscribe(list: {any},listener: any): ()->()
    table.insert(list,listener)
    return function() local i=table.find(list,listener);if i then table.remove(list,i) end end
end
function Client.get(): any? return state end
-- Fires with every new state.
function Client.changed(listener: (any)->()): ()->() return subscribe(listeners,listener) end
-- Fires once per newly finished challenge (lastDone not seen before) with (challenge, state). The one already present
-- when the player joins is history, never replayed.
function Client.finished(listener: (any,any)->()): ()->() return subscribe(doneListeners,listener) end
-- Fires once per claim reply (lastClaim not seen before) with (lastClaim, state).
function Client.claimed(listener: (any,any)->()): ()->() return subscribe(claimListeners,listener) end

local function remote(name: string): RemoteEvent?
    local folder=ReplicatedStorage:FindFirstChild("OpenFrontRemotes")
    local r=folder and folder:FindFirstChild(name)
    return if r and r:IsA("RemoteEvent") then r else nil
end
local function send(command: any)
    if stub then task.defer(stub.handle,command);return end
    local r=remote("DailyCommand");if r then r:FireServer(command) end
end
-- The challenge (daily or weekly) with this id in a state.
function Client.find(id: any,s: any?): any?
    s=s or state
    if type(s)~="table" or id==nil then return nil end
    for _,c in (if type(s.daily)=="table" then s.daily else {}) do if c.id==id then return c end end
    if type(s.weekly)=="table" and s.weekly.id==id then return s.weekly end
    return nil
end
-- PIVOT (Config.Daily.Challenges=false): the challenges are gone; a packet keeps only the login streak, so every surface
-- (the chips, the end-card rows, the in-match notices, Claim all, the dots) sees none.
local function challengesOn(): boolean
    local shared=ReplicatedStorage:FindFirstChild("Shared")
    local ok,config=pcall(function() return require(shared:FindFirstChild("Config") :: any) end)
    return not (ok and type(config)=="table" and type(config.Daily)=="table" and config.Daily.Challenges==false)
end
Client.challengesOn=challengesOn
function Client.receive(packet: any)
    if type(packet)~="table" or packet.kind~="Daily" or type(packet.daily)~="table" then return end
    if not challengesOn() then
        packet=table.clone(packet);packet.daily={};packet.bonus=nil;packet.weekly=nil;packet.lastDone=nil;packet.matchGain=nil;packet.rerolls=0
        if type(packet.lastClaim)=="table" and packet.lastClaim.target~="streak" then packet.lastClaim=nil end
    end
    local first=state==nil
    state=packet
    emit(listeners,packet)
    local done=packet.lastDone
    if type(done)=="table" and done.id~=nil then
        local key=tostring(done.id).."|"..tostring(done.at)
        if key~=seenDone then
            seenDone=key
            local challenge=Client.find(done.id,packet)
            if not first and challenge then emit(doneListeners,challenge,packet) end
        end
    end
    local claim=packet.lastClaim
    if type(claim)=="table" then
        local key=tostring(claim.requestId or "").."|"..tostring(claim.target).."|"..tostring(claim.id)
        if key~=seenClaim then
            seenClaim=key
            if not first then emit(claimListeners,claim,packet) end
        end
    end
end

-- ------------------------------------------------------------------ reading the state (pure)
-- 0..1 progress of a challenge (claimed / done read full)
function Client.fraction(c: any): number
    if type(c)~="table" then return 0 end
    if c.state=="done" or c.state=="claimed" then return 1 end
    local goal=tonumber(c.goal) or 0
    return if goal>0 then math.clamp((tonumber(c.progress) or 0)/goal,0,1) else 0
end
-- "1.2K" style for big goals ("1.2K / 2K"), plain under 1000
function Client.short(n: number): string
    n=math.floor(n)
    if n<1000 then return tostring(n) end
    local k=n/1000
    local s=if k>=100 or k%1==0 then string.format("%d",math.floor(k)) else string.format("%.1f",math.floor(k*10)/10)
    return (string.gsub(s,"%.0$",""))..(if n>=1000 then "K" else "")
end
function Client.progressText(c: any): string
    if type(c)~="table" then return "" end
    local goal=tonumber(c.goal) or 0
    local progress=math.min(tonumber(c.progress) or 0,goal)
    if c.state=="done" or c.state=="claimed" then progress=goal end
    return Client.short(progress).." / "..Client.short(goal)
end
-- The challenge's one line ("Take 2,000 tiles"); the server may send its own `text`
local function comma(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (string.gsub(out,"^,",""))
end
local LINES={tiles="Take %s tiles",tribes="Defeat %s tribes",nations="Defeat %s nations",cities="Build %s cities",nuke="Launch %s nukes",survive="Survive %s minutes",win="Win %s matches"}
local SINGULAR={tribes="Defeat 1 tribe",nations="Defeat 1 nation",cities="Build 1 city",nuke="Launch a nuke",survive="Survive 1 minute",win="Win a match"}
function Client.line(c: any): string
    if type(c)~="table" then return "" end
    if type(c.text)=="string" and c.text~="" then return c.text end
    local goal=tonumber(c.goal) or 0
    if goal==1 and SINGULAR[c.kind] then return SINGULAR[c.kind] end
    local f=LINES[c.kind];return if f then string.format(f,comma(goal)) else tostring(c.kind)
end
-- The reward's short text: "25 · 40 XP" (the gem is drawn beside it)
function Client.rewardText(reward: any): string
    if type(reward)~="table" then return "" end
    local parts={}
    if tonumber(reward.cobalt) then table.insert(parts,tostring(reward.cobalt)) end
    if tonumber(reward.xp) then table.insert(parts,tostring(reward.xp).." XP") end
    return table.concat(parts," · ")
end
-- Seconds until the daily reset (nil when unknown)
function Client.resetsIn(s: any?): number?
    s=s or state
    local at=type(s)=="table" and tonumber(s.resetAt)
    return if at then math.max(0,at-os.time()) else nil
end
-- PF045 (rolling 24 h): seconds until the next streak claim opens (streak.opensAt), 0 while it's open; falls back to
-- the UTC reset for an older server
function Client.nextClaimIn(s: any?): number?
    s=s or state
    local at=type(s)=="table" and type(s.streak)=="table" and tonumber(s.streak.opensAt)
    if at then return math.max(0,at-os.time()) end
    if type(s)=="table" and type(s.streak)=="table" and s.streak.claimable then return 0 end
    return Client.resetsIn(s)
end
-- "resets in 6h" / "resets in 25m"
function Client.resetText(s: any?): string
    local left=Client.resetsIn(s)
    if not left then return "" end
    if left>=3600 then return "resets in "..math.floor(left/3600).."h" end
    return "resets in "..math.max(1,math.ceil(left/60)).."m"
end
-- Anything to claim right now (a gold chip, the plate dot)?
function Client.claimable(s: any?): boolean
    s=s or state
    if type(s)~="table" then return false end
    for _,c in (if type(s.daily)=="table" then s.daily else {}) do if c.state=="done" then return true end end
    if type(s.bonus)=="table" and s.bonus.state=="done" then return true end
    if type(s.weekly)=="table" and s.weekly.state=="done" then return true end
    return false
end
function Client.streakClaimable(s: any?): boolean
    s=s or state
    return type(s)=="table" and type(s.streak)=="table" and s.streak.claimable==true
end
-- This match's gain for a challenge (the end card's "+600"); matchId must match the state's matchGain
function Client.gain(id: any,matchId: any,s: any?): number?
    s=s or state
    local mg=type(s)=="table" and s.matchGain
    if type(mg)~="table" or type(mg.gains)~="table" or (matchId~=nil and tostring(mg.matchId)~=tostring(matchId)) then return nil end
    local g=tonumber(mg.gains[id])
    return if g and g>0 then g else nil
end

-- ------------------------------------------------------------------ commands
function Client.ready(): boolean return stub~=nil or (type(state)=="table" and remote("DailyCommand")~=nil) end
local function request(command: any): string?
    if not Client.ready() then return nil end
    command.requestId=string.sub(HttpService:GenerateGUID(false),1,36)
    send(command)
    return command.requestId
end
-- target: "daily" | "bonus" | "weekly" | "streak"; id for daily / weekly (PIVOT: only "streak" while challenges are off)
function Client.claim(target: string,id: any?): string?
    if target~="streak" and not challengesOn() then return nil end
    return request({kind="Claim",target=target,id=id})
end
-- Claims everything finished (the end card's one Claim on phones): one command per claimable piece
function Client.claimAll(): number
    local s=state;if type(s)~="table" then return 0 end
    local n=0
    for _,c in (if type(s.daily)=="table" then s.daily else {}) do if c.state=="done" and Client.claim("daily",c.id) then n+=1 end end
    if type(s.bonus)=="table" and s.bonus.state=="done" and Client.claim("bonus") then n+=1 end
    if type(s.weekly)=="table" and s.weekly.state=="done" and Client.claim("weekly",s.weekly.id) then n+=1 end
    return n
end
function Client.reroll(id: any): string? if not challengesOn() then return nil end;return request({kind="Reroll",id=id}) end
-- asks for a fresh push (the Play page calls it when it opens)
function Client.refresh() if not stub and type(state)=="table" then local r=remote("DailyCommand");if r then r:FireServer({kind="Ready"}) end end end

-- ------------------------------------------------------------------ the Studio stub (QA only; never on a live server)
-- Client.useStub({day=2, claimable=true, owned={skin_grid=false}, daily={{kind="tiles",goal=2000,progress=1240}, ...},
-- weekly={kind="win",goal=5,progress=2}, matchGain={matchId, gains}}) plays the server's part locally.
-- Client.useStub(nil) turns it off. Studio only.
local DEFAULT_DAILY={{id="tiles_2000",kind="tiles",goal=2000,progress=1240},{id="tribes_3",kind="tribes",goal=3,progress=3,state="done"},{id="cities_4",kind="cities",goal=4,progress=1}}
function Client.useStub(options: any?)
    if options==nil then stub=nil;return end
    assert(game:GetService("RunService"):IsStudio(),"DailyClient stub is Studio only")
    local s: any={delay=options.delay or .2}
    stub=s
    local daily={}
    for i,c in options.daily or DEFAULT_DAILY do
        local d=table.clone(c);d.id=d.id or ("stub"..i);d.reward=d.reward or {cobalt=25,xp=40}
        d.state=d.state or (if d.progress>=d.goal then "done" else "run");table.insert(daily,d)
    end
    local weekly=table.clone(options.weekly or {id="win_5",kind="win",goal=5,progress=2});weekly.reward=weekly.reward or {cobalt=300}
    weekly.state=weekly.state or (if weekly.progress>=weekly.goal then "done" else "run")
    local owned=options.owned or {}
    local tiles={{cobalt=25},{item="skin_grid",owned=owned.skin_grid==true,cobalt=500},{cobalt=40},{cobalt=50},{cobalt=60},{cobalt=80},
        {item="skin_stormfront",owned=owned.skin_stormfront==true,cobalt=650}}
    s.packet={kind="Daily",loaded=true,day=20000,resetAt=os.time()+(options.resetIn or 6*3600),weekResetAt=os.time()+3*86400,rerolls=1,
        daily=daily,bonus={reward={cobalt=100},done=0,state="run"},weekly=weekly,
        streak={today=options.day or 2,claimable=options.claimable~=false,tiles=tiles},matchGain=options.matchGain}
    local function recount()
        local n=0;for _,d in s.packet.daily do if d.state~="run" then n+=1 end end
        s.packet.bonus.done=n
        if n>=3 and s.packet.bonus.state=="run" then s.packet.bonus.state="done" end
    end
    recount()
    local function push(extra: any?)
        local p=table.clone(s.packet)
        for k,v in extra or {} do p[k]=v end
        Client.receive(p)
    end
    function s.handle(command: any)
        task.wait(s.delay)
        if stub~=s then return end
        if command.kind=="Claim" then
            local piece=if command.target=="bonus" then s.packet.bonus elseif command.target=="streak" then nil else Client.find(command.id,s.packet)
            if command.target=="streak" then
                if s.packet.streak.claimable then s.packet.streak.claimable=false;s.packet.streak.claimedToday=true end
            elseif piece and piece.state=="done" then piece.state="claimed" end
            push({lastClaim={requestId=command.requestId,target=command.target,id=command.id,status="granted"}})
        elseif command.kind=="Reroll" then
            local c=Client.find(command.id,s.packet)
            if c and s.packet.rerolls>0 and c.state=="run" then s.packet.rerolls-=1;c.kind="survive";c.goal=10;c.progress=0;c.id="survive_10" end
            push()
        else push() end
    end
    -- QA: s.progress(id, value) moves a challenge (fires lastDone when it finishes)
    function s.progress(id: any,value: number)
        local c=Client.find(id,s.packet);if not c then return end
        c.progress=value
        local extra=nil
        if c.state=="run" and value>=c.goal then c.state="done";extra={lastDone={id=c.id,at=os.clock()}} end
        recount();push(extra)
    end
    Client.stub=s
    push()
end

function Client.start()
    if started then return end
    started=true
    task.spawn(function()
        local folder=ReplicatedStorage:WaitForChild("OpenFrontRemotes")
        local bound=false
        -- ChildAdded rather than WaitForChild: no infinite-yield warning while the server side isn't in yet.
        local function bind(child: Instance)
            if bound or child.Name~="DailyState" or not child:IsA("RemoteEvent") then return end
            bound=true;child.OnClientEvent:Connect(Client.receive)
            local command=remote("DailyCommand");if command then command:FireServer({kind="Ready"}) end
        end
        folder.ChildAdded:Connect(function(child)
            bind(child)
            if child.Name=="DailyCommand" and bound and child:IsA("RemoteEvent") then child:FireServer({kind="Ready"}) end
        end)
        for _,child in folder:GetChildren() do bind(child) end
    end)
end
return Client
