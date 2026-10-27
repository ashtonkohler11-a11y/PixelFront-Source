--!strict
-- PF026 (PF - 1; Ashton: "Good, build", WITH Play again): the end screen. Content only: the cards are authored in the
-- place (tools/atlas/author-pf026-end-screen.luau: Game.Result is the 70% dim, Result.PFEnd.Desk / .Phone the cards).
--   * the outcome: VICTORY (gold crest + rays), DEFEAT (steel, cracked), DIDN'T SPAWN (an empty dashed shield, one wide
--     NO LANDING tile, +0 XP), CANCELLED / MATCH OVER (spectators) neutral; your flag in the shield, your nation colour
--     on its ribbon, your name + the map; RANK, PEAK LAND, PEAK TROOPS, SURVIVED from the packets this module watched
--   * the Cobalt row: what this match paid (+ the 2x chip and the next unlock), read from the end packet's xpResult
--   * the keys: Return to lobby (MatchController's requestReturn; Result's PFReturning attribute = the busy spinner),
--     Keep watching (not on Victory), Play again (Solo: a new Solo with the same settings; public: back to the lobby and
--     into the next public match of the same mode; hidden in custom rooms, the tutorial and for spectators)
-- Desk or Phone is a visibility choice by the screen's height (a phone in landscape gets the two-column card).
-- 2026-10-26 (Levels removed, Ashton "Remove it"): the XP block, the level reward row and the level claims are gone; the
-- authored Xp block stays hidden. Claim all collects the finished dailies only.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local GuiService=game:GetService("GuiService")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local Feed=require(script.Parent.MatchPacketFeed)
local RewardDrop=require(script.Parent.RewardDrop) -- PF043 D1c: Claim all plays the reward drop
local DailyClient=require(script.Parent.DailyClient) -- PF043 D1c: the finished dailies join the one Claim all
-- PIVOT D15 (Levels removed): the simple card's level row gives way to the Cobalt this match earned (an authored Cobalt row,
-- tools/atlas/author-pf043-end-simple.luau v3)
local Marketplace=game:GetService("MarketplaceService")
local Catalog=require(RS:WaitForChild("Shared"):WaitForChild("CosmeticCatalog"))
local MatchCobalt=require(RS.Shared:WaitForChild("MatchCobalt"))
local M={}
local hex=Color3.fromHex
local GOLD,STEEL,RED,GREY,CRIMSON=hex("#ffd77a"),hex("#5d6676"),hex("#e5544b"),hex("#c9ced6"),hex("#2e1416")
local PANEL=hex("#121418")
local TONE={victory={hex("#3a2c10"),GOLD},defeat={CRIMSON,RED},nospawn={hex("#1d2026"),GREY},neutral={hex("#1d2026"),GREY}}
local WORD={victory="VICTORY",defeat="DEFEAT",nospawn="DIDN'T SPAWN",cancelled="CANCELLED",over="MATCH OVER"}
local PHONE_HEIGHT=520 -- below this screen height the landscape card shows

local state: any={matchId=-1}
local gui: any=nil;local result: any=nil;local root: any=nil
local hooks: any={}
local started=false;local bound=false
local views: {any}={}
local spin: RBXScriptConnection?=nil
local claimBound=false
-- PF043 D1c (the simple card, views with PF043Simple): one Claim all collects the finished dailies for the reward drop;
-- requeuing = Play again was pressed (its key shows the next match's countdown instead of dimming)
local collect: any=nil
local requeuing=false
local reviveUp=false -- PIVOT D10: ReviveView's card is up (an open Revive offer): the Desk card steps aside
local showPay: (xr: any)->() -- the Cobalt row from the end packet's xpResult (defined with the row, below)

local function art(): any local ok,a=pcall(require,script.Parent.CosmeticArt);return if ok then a else nil end
local function grouped(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse();return (out:gsub("^,",""))
end
local function short(n: number): string
    if n>=1e6 then return (string.format("%.1fM",n/1e6):gsub("%.0M","M")) end
    if n>=1e3 then return string.format("%.0fK",n/1e3) end
    return tostring(math.floor(n))
end
local function clock(seconds: number?): string
    if type(seconds)~="number" or seconds<0 then return "—" end
    local s=math.floor(seconds);if s>=3600 then return string.format("%d:%02d:%02d",s//3600,(s%3600)//60,s%60) end
    return string.format("%d:%02d",s//60,s%60)
end
local function contender(p: any): boolean return type(p)=="table" and (p.playerType=="Human" or p.playerType=="Nation") end

-- ------------------------------------------------------------------ the packets (stats for the card)
local function observe(packet: any)
    if type(packet)~="table" or type(packet.matchId)~="number" or type(packet.state)~="table" then return end
    local s=packet.state
    if packet.matchId~=state.matchId then
        state={matchId=packet.matchId,peakLand=0,peakTroops=0,spawned=false,outAt=nil,outRank=nil}
    end
    state.online=packet.online==true;state.spectator=packet.spectator==true;state.tutorial=packet.tutorialMatch==true or packet.tutorial==true
    state.kind=packet.matchKind;state.place=if type(packet.xpResult)=="table" then packet.xpResult.place else state.place
    -- the match's pay arrives once, on the end packet (MatchRewardsService: cobalt, cobaltDouble, cobaltDoubled, cobaltUnlock)
    local xr=packet.xpResult
    if type(xr)=="table" and state.paid~=(xr.matchKey or true) then state.paid=xr.matchKey or true;showPay(xr) end
    state.config=s.gameConfig;state.elapsed=s.elapsed;state.phase=s.phase
    local me=type(s.players)=="table" and s.players[1] or nil
    if me then state.name=me.name;state.flag=me.flag;if me.spawnTile~=nil then state.spawned=true end end
    local cfg=type(s.gameConfig)=="table" and s.gameConfig or {}
    state.map=cfg.gameMap or s.mapType
    local counts=type(s.counts)=="table" and s.counts or {}
    local land=tonumber(s.landCount) or (type(s.map)=="table" and tonumber(s.map.landCount)) or nil
    local mine=tonumber(counts[1]) or 0
    if land and land>0 then state.peakLand=math.max(state.peakLand,mine/land) end
    if type(s.troops)=="table" and tonumber(s.troops[1]) then state.peakTroops=math.max(state.peakTroops,tonumber(s.troops[1]) :: number) end
    -- contenders (humans + nations), and where you stood when you went out
    local total,alive=0,0
    if type(s.players)=="table" then for owner,p in s.players do if contender(p) then total+=1;if owner~=1 and (tonumber(counts[owner]) or 0)>0 then alive+=1 end end end end
    state.of=total
    if state.spawned and mine==0 and s.phase~="Choosing" and state.outAt==nil then state.outAt=s.elapsed;state.outRank=alive+1 end
end

-- ------------------------------------------------------------------ painting
local function activeView(): any
    if #views==0 then return nil end
    local phone=root and root:FindFirstChild("Phone");local desk=root and root:FindFirstChild("Desk")
    local small=result.AbsoluteSize.Y>0 and result.AbsoluteSize.Y<PHONE_HEIGHT
    if desk then desk.Visible=(not small or phone==nil) and not reviveUp end
    if phone then phone.Visible=small or desk==nil end
    for _,v in views do if v.root.Visible then return v end end
    return views[1]
end
local function outcome(): string
    local o=result:GetAttribute("Outcome")
    if state.spectator then return "over" end
    if o=="Won" then return "victory" end
    if o=="Cancelled" then return "cancelled" end
    if not state.spawned then return "nospawn" end
    return "defeat"
end
local function setVis(item: any,on: boolean) if item then item.Visible=on end end
local function paintHero(v: any,kind: string)
    local hero=v.root:FindFirstChild("Hero");if not hero then return end
    local tone=if kind=="victory" then "victory" elseif kind=="defeat" then "defeat" elseif kind=="nospawn" then "nospawn" else "neutral"
    local bg=hero:FindFirstChild("Bg");if bg then bg.Color=ColorSequence.new(TONE[tone][1],PANEL) end
    local empty=kind=="nospawn"
    for _,name in {"ShieldFill","ShieldRim","FlagClip","Ribbon","Laurel"} do setVis(hero:FindFirstChild(name),not empty) end
    setVis(hero:FindFirstChild("Dash"),empty);setVis(hero:FindFirstChild("Hourglass"),empty)
    setVis(hero:FindFirstChild("Rays"),kind=="victory");setVis(hero:FindFirstChild("Star"),kind=="victory");setVis(hero:FindFirstChild("Crack"),kind=="defeat")
    local metal=if kind=="victory" then GOLD else STEEL
    for _,name in {"ShieldRim","Laurel"} do local i=hero:FindFirstChild(name);if i then i.ImageColor3=metal end end
    local laurel=hero:FindFirstChild("Laurel");if laurel then laurel.ImageTransparency=if kind=="victory" then 0 else .6 end
    local glow=hero:FindFirstChild("Glow");if glow then glow.ImageColor3=if kind=="victory" then GOLD elseif kind=="defeat" then RED else GREY;glow.ImageTransparency=if kind=="victory" then .55 elseif kind=="defeat" then .8 else 1 end
    local color=if hooks.ownerColor then hooks.ownerColor(1) else nil
    local ribbon=hero:FindFirstChild("Ribbon");if ribbon then ribbon.ImageColor3=(if typeof(color)=="Color3" then color else hex("#b46ee0")):Lerp(Color3.new(),if kind=="defeat" then .35 else 0) end
    local fill=hero:FindFirstChild("ShieldFill");if fill then fill.ImageColor3=(if typeof(color)=="Color3" then color else hex("#3a2a52")):Lerp(Color3.new(),.65) end
    local clip=hero:FindFirstChild("FlagClip");local flag=clip and clip:FindFirstChild("Flag")
    local A=art()
    if flag and A and type(state.flag)=="string" and state.flag~="" then
        local ok=pcall(A.bind,flag,state.flag);flag.ImageTransparency=if kind=="defeat" then .45 else 0;clip.Visible=clip.Visible and ok and flag.Visible
    elseif clip then clip.Visible=false end
end
local function paintText(v: any,kind: string)
    local r=v.root
    local word=r:FindFirstChild("Word");if word then word.Text=WORD[kind] or "";word.TextColor3=if kind=="victory" then GOLD elseif kind=="defeat" then RED else GREY end
    local color=if hooks.ownerColor then hooks.ownerColor(1) else nil
    local swatch=if typeof(color)=="Color3" then color:ToHex() else "b46ee0"
    local name=tostring(state.name or Players.LocalPlayer.DisplayName)
    local map=r:FindFirstChild("Map")
    local who=r:FindFirstChild("Who")
    if who then
        local esc=function(s: string) return (s:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")) end
        who.Text=string.format('<font color="#%s">■</font>  %s',swatch,esc(name))..(if map then "" else string.format('  <font color="#8f96a0">·  %s</font>',esc(tostring(state.map or ""))))
    end
    if map then map.Text=tostring(state.map or "") end
    -- the numbers
    local place=state.place
    local rank,of=nil,state.of
    if type(place)=="table" and tonumber(place.rank) then rank,of=tonumber(place.rank),tonumber(place.of) or of
    elseif kind=="victory" then rank=1 elseif state.outRank then rank=state.outRank end
    local nospawn=kind=="nospawn"
    local stats=r:FindFirstChild("Stats");setVis(stats,not nospawn);setVis(r:FindFirstChild("NoLanding"),nospawn)
    local rankText=if rank then "#"..rank else "—"
    if stats then
        local t=stats:FindFirstChild("Rank");if t then t.Value.Text=rankText;local s=t:FindFirstChild("Sub");if s then s.Text=if rank and of and of>0 then "of "..of else "" end end
        t=stats:FindFirstChild("Land");if t then t.Value.Text=string.format("%d%%",math.floor(state.peakLand*100+.5)) end
        t=stats:FindFirstChild("Troops");if t then t.Value.Text=short(state.peakTroops) end
        t=stats:FindFirstChild("Time");if t then t.Value.Text=clock(if state.outAt then state.outAt else state.elapsed) end
    end
    local phoneRank=r:FindFirstChild("Rank");if phoneRank and phoneRank:IsA("TextLabel") then phoneRank.Text=if rank and of and of>0 then rankText.." of "..of else rankText;phoneRank.Visible=not nospawn end
    setVis(r:FindFirstChild("Why"),nospawn and r:FindFirstChild("NoLanding")==nil) -- the NO LANDING tile already says it
end
local function paintKeys(v: any,kind: string)
    local keys=v.root:FindFirstChild("Keys");if not keys then return end
    local custom=state.online and state.kind~=nil and state.kind~="public"
    local again=not state.spectator and not state.tutorial and not custom and kind~="cancelled" and (not state.online or state.kind=="public")
    -- Ashton 2026-10-12: "add a keep playing button on the end tutorial menu aswell, some may wanna keep playing". A
    -- tutorial win offers the watch key as "Keep playing" (it closes the card; the match runs on after a win), with the
    -- sheet's land cell instead of the eye.
    -- 2026-10-14 (Ashton: "Keep conquering after a win"): every win offers it. The match runs on after a winner in
    -- Solo, custom rooms and public matches alike (the simulation keeps stepping; nothing closes the server), and the
    -- win's XP and stats are granted once (levelGranted / countedMatches), so playing on never pays twice.
    local keepPlaying=kind=="victory" and not state.spectator
    local watch=kind~="victory" or keepPlaying
    for _,name in {"Watch","WatchWide"} do
        local k=keys:FindFirstChild(name)
        local l=k and k:FindFirstChild("Label");local ic=k and k:FindFirstChild("Icon",true)
        if l and l:IsA("TextLabel") then local text=if keepPlaying then "Keep playing" else "Keep watching";if l.Text~=text then l.Text=text end end
        if ic and ic:IsA("ImageLabel") then ic.ImageRectOffset=if keepPlaying then Vector2.new(64,256) else Vector2.new(256,256) end -- land | eye
    end
    -- PF043 D1c: Play again is the big key (Return to lobby takes it where there's no Play again); Keep playing + Return share row two
    if v.root:GetAttribute("PF043Simple")==true then
        setVis(keys:FindFirstChild("Again"),again);setVis(keys:FindFirstChild("ReturnBig"),not again)
        setVis(keys:FindFirstChild("Watch"),again and watch);setVis(keys:FindFirstChild("Return"),again and watch)
        setVis(keys:FindFirstChild("ReturnWide"),again and not watch);setVis(keys:FindFirstChild("WatchWide"),watch and not again)
        return
    end
    -- both: side by side; one: it takes the row (WatchWide / AgainWide); none (a win in a custom room): just Return
    setVis(keys:FindFirstChild("Watch"),watch and again);setVis(keys:FindFirstChild("Again"),watch and again)
    setVis(keys:FindFirstChild("AgainWide"),again and not watch);setVis(keys:FindFirstChild("WatchWide"),watch and not again)
end
local function busy(on: boolean)
    for _,v in views do
        local keys=v.root:FindFirstChild("Keys")
        for _,rn in {"Return","ReturnBig","ReturnWide"} do -- PF043 D1c: the simple card's Return variants
            local ret=keys and keys:FindFirstChild(rn)
            if ret then
                ret.Active=not on
                local l=ret:FindFirstChild("Label");if l then l.Text=if on and not requeuing then "Returning…" else "Return to lobby" end
                local sock=ret:FindFirstChild("Socket");if sock then setVis(sock:FindFirstChild("Icon"),not on or requeuing);setVis(sock:FindFirstChild("Spinner"),on and not requeuing) end
            end
        end
        for _,name in {"Watch","WatchWide","Again","AgainWide"} do
            local k=keys and keys:FindFirstChild(name)
            if k and not (requeuing and name=="Again") then k.Active=not on;k.BackgroundTransparency=if on then .5 else 0 end
        end
    end
    if on and not spin then
        local t0=os.clock()
        spin=Run.RenderStepped:Connect(function()
            if not result or not result.Parent then if spin then spin:Disconnect();spin=nil end;return end
            for _,v in views do local ks=v.root:FindFirstChild("Keys");for _,rn in {"Return","ReturnBig","ReturnWide"} do local s=ks and ks:FindFirstChild(rn);s=s and s:FindFirstChild("Socket");s=s and s:FindFirstChild("Spinner");if s then s.Rotation=(os.clock()-t0)*360 end end end
        end)
    elseif not on and spin then spin:Disconnect();spin=nil end
end
-- ------------------------------------------------------------------ Claim all (PF043 D1c): the finished dailies
-- the finished dailies (daily, the all-three bonus, the weekly) that the one Claim all takes
local function dailyReady(): number
    local s=DailyClient.get();if type(s)~="table" then return 0 end
    local n=0
    for _,c in (if type(s.daily)=="table" then s.daily else {}) do if type(c)=="table" and c.state=="done" then n+=1 end end
    for _,c in {s.bonus,s.weekly} do if type(c)=="table" and c.state=="done" then n+=1 end end
    return n
end
-- v10 card (author-pf043-end-simple): with nothing in its middle (no Cobalt plate, Xp or Claim all) the card collapses to
-- its authored PFC_* geometry (the band taken out); otherwise the PFE_* geometry (PF - 4's sweep: VICTORY at +0)
local function fit(v: any)
    local root=v.root;if typeof(root:GetAttribute("PFC_Size"))~="UDim2" then return end
    local empty=true
    for _,name in {"Cobalt","Xp","ClaimAll"} do local n=root:FindFirstChild(name);if n and n:IsA("GuiObject") and n.Visible then empty=false end end
    local tag=if empty then "PFC_" else "PFE_"
    local size=root:GetAttribute(tag.."Size");if typeof(size)=="UDim2" and root.Size~=size then root.Size=size end
    local aspect=root:FindFirstChild("Aspect");local ratio=root:GetAttribute(tag.."Aspect")
    if aspect and type(ratio)=="number" and aspect.AspectRatio~=ratio then aspect.AspectRatio=ratio end
    for _,c in root:GetChildren() do
        local p,s=c:GetAttribute(tag.."Pos"),c:GetAttribute(tag.."Size")
        if typeof(p)=="UDim2" and (c :: any).Position~=p then (c :: any).Position=p end
        if typeof(s)=="UDim2" and (c :: any).Size~=s then (c :: any).Size=s end
    end
end
local function paintRewards()
    local daily=dailyReady()
    for _,v in views do
        local ca=v.root:FindFirstChild("ClaimAll")
        if ca then
            ca.Visible=daily>0 or collect~=nil;ca.Active=collect==nil
            local cnt=ca:FindFirstChild("Count");if cnt then cnt.Text=tostring(daily);cnt.Visible=daily>1 end
            local l=ca:FindFirstChild("Label");if l then l.Text=if collect then "…" elseif daily>1 then "Claim all" else "Claim" end
        end
        fit(v)
    end
end
-- hand everything collected to the reward drop (once every reply landed, or after 4 s)
local function flushDrop()
    local c=collect;if not c then return end
    collect=nil
    local drop=RewardDrop.get(gui)
    if drop and #c.entries>0 then drop:play(c.entries,function() paintRewards() end) end
    paintRewards()
end
local function pressSimple()
    if collect then return end
    collect={entries={},waiting=0,daily=0}
    local n=DailyClient.claimAll();collect.daily=n;collect.waiting+=n
    if collect.waiting==0 then collect=nil;paintRewards();return end
    local mine=collect;task.delay(4,function() if collect==mine then flushDrop() end end)
    paintRewards()
end
local function bindClaims()
    if claimBound then return end
    claimBound=true
    for _,v in views do
        local ca=v.root:FindFirstChild("ClaimAll");if ca and ca:IsA("GuiButton") then ca.Activated:Connect(pressSimple) end
    end
    DailyClient.claimed(function(dc: any)
        local c=collect;if not c or c.daily<=0 then return end
        c.daily-=1;c.waiting-=1
        if dc.status=="granted" then local e=RewardDrop.entry(dc.granted,"DAILY REWARD");if e then table.insert(c.entries,e) end end
        if c.waiting<=0 then flushDrop() end
    end)
    DailyClient.changed(function() if result and result.Visible then paintRewards() end end)
    DailyClient.start() -- idempotent: the simple card has no daily block (DailyView.endCard started it there)
end
M.paintRewards=paintRewards -- tests / the stage

-- ------------------------------------------------------------------ the Cobalt row
-- PIVOT D15: the Cobalt this match earned (xpResult.cobalt, the match server's grant; +0 until it sends one)
-- PIVOT (Ashton 2026-10-24, author-pf043-end-simple v5): the plate's 2x chip buys the 2x Cobalt pass on the card (its price
-- tag), then flips to "2× ACTIVE" and the "+N" counts up to the doubled pay (the server pays the difference once);
-- the Unlock row names the next item to save for (xpResult.cobaltUnlock {name, price, balance}).
local cobaltShown=0
local pay: any={double=nil,doubled=false,unlock=nil,bought=false}
local function doublePass(): any
    local id=MatchCobalt.doublePass();return id and Catalog.passById and Catalog.passById[id] or nil
end
local function paintCobalt(v: any)
    setVis(v.root:FindFirstChild("Xp"),false)
    local row=v.root:FindFirstChild("Cobalt");if not row then return end
    -- v9 plate (author-pf043-end-simple): the content sits in PFBody; older plates keep it at the root
    local box=row:FindFirstChild("PFBody") or row
    -- RELEASE-QA #11: a match that paid nothing (a replayed tutorial) shows no "COBALT EARNED +0" plate
    if cobaltShown<=0 and not pay.bought then setVis(row,false);return end
    setVis(row,true)
    local amount=box:FindFirstChild("Amount");if amount then amount.Text="+"..grouped(cobaltShown) end
    local pass=doublePass()
    local active=pay.doubled or pay.bought
    local chip=box:FindFirstChild("Double")
    if chip then
        chip.Visible=not active and pass~=nil and type(pay.double)=="number" and pay.double>cobaltShown
        local l=chip:FindFirstChild("Label");if l then l.Text="2× +"..grouped(tonumber(pay.double) or 0) end
        -- v7 row: "+80 → +160", the doubled pay in gold (the Gain label is RichText)
        local g=chip:FindFirstChild("Gain")
        if g then g.Text="+"..grouped(cobaltShown)..' → <font color="#ffd77a">+'..grouped(tonumber(pay.double) or 0).."</font>" end
        local tag=chip:FindFirstChild("Tag");local p=tag and tag:FindFirstChild("Price")
        if p then p.Text=(if g then utf8.char(0xE002).." " else "R$ ")..tostring(pass and pass.robux or "--") end
    end
    local on=box:FindFirstChild("DoubleOn")
    setVis(on,active and cobaltShown>0)
    local un=box:FindFirstChild("Unlock");local u=pay.unlock
    setVis(un,type(u)=="table" and type(u.price)=="number" and u.price>0)
    -- RELEASE-QA #10: the plate is as tall as its lines (the authored state sizes; no empty band under "+N")
    local two=(chip~=nil and chip.Visible) or (on~=nil and on.Visible);local low=un~=nil and un.Visible
    local state=if two and low then "Full" elseif two then "TwoX" elseif low then "Unlock" else "Bare"
    local size,at,inner=row:GetAttribute("PFSize_"..state),row:GetAttribute("PFPos_"..state),box:GetAttribute("PFSize_"..state)
    if typeof(size)=="UDim2" and typeof(at)=="UDim2" and typeof(inner)=="UDim2" and box~=row then
        if row.Size~=size then row.Size=size end;if row.Position~=at then row.Position=at end;if box.Size~=inner then box.Size=inner end
        setVis(box:FindFirstChild("Rule"),state~="Bare");setVis(box:FindFirstChild("Rule2"),state=="Full")
    end
    -- v7: the Unlock row rises into the 2x line's slot when that line is empty
    if un then
        local empty=not (chip and chip.Visible) and not (on and on.Visible)
        local slot=un:GetAttribute(if empty then "PFSlotUp" else "PFSlotDown")
        if typeof(slot)=="UDim2" and un.Position~=slot then un.Position=slot end
    end
    if un and type(u)=="table" and type(u.price)=="number" and u.price>0 then
        local balance=math.max(0,tonumber(u.balance) or 0)+(if pay.bought and not pay.doubled then math.max(0,cobaltShown-(tonumber(u.earned) or cobaltShown)) else 0)
        local nm=un:FindFirstChild("Name");if nm then nm.Text=tostring(u.name or "Next unlock") end
        local bar=un:FindFirstChild("Bar");local f=bar and bar:FindFirstChild("Fill");if f then f.Size=UDim2.fromScale(math.clamp(balance/u.price,0,1),1) end
        local n=un:FindFirstChild("Numbers");if n then n.Text=grouped(math.min(balance,u.price)).." / "..grouped(u.price) end
    end
end
local function buyDouble()
    local pass=doublePass()
    if not pass or type(pass.passId)~="number" or pass.passId<=0 or pay.doubled or pay.bought then return end -- no Game Pass yet: truthful no-op
    pcall(function() Marketplace:PromptGamePassPurchase(Players.LocalPlayer,pass.passId) end)
end
-- bought: count the "+N" up to the doubled pay (0.6 s), then the chip reads ACTIVE
local function onDoubleBought()
    if pay.bought or pay.doubled or type(pay.double)~="number" then return end
    pay.bought=true
    local from,to=cobaltShown,pay.double
    if pay.unlock then pay.unlock.earned=from end
    task.spawn(function()
        local t0=os.clock()
        while os.clock()-t0<.6 do
            cobaltShown=math.floor(from+(to-from)*math.clamp((os.clock()-t0)/.6,0,1));for _,v in views do paintCobalt(v) end;task.wait()
        end
        cobaltShown=to;for _,v in views do paintCobalt(v) end
    end)
end
-- the end packet's xpResult (observe): this match's pay, the 2x chip and the next unlock
showPay=function(xr: any)
    cobaltShown=math.max(0,math.floor(tonumber(xr.cobalt) or 0))
    pay={double=tonumber(xr.cobaltDouble),doubled=xr.cobaltDoubled==true,unlock=if type(xr.cobaltUnlock)=="table" then table.clone(xr.cobaltUnlock) else nil,bought=false}
    M.refresh();paintRewards()
end

-- ------------------------------------------------------------------ wiring
function M.refresh()
    if not result or not result.Visible then return end
    if not requeuing then for _,v in views do local k=v.root:FindFirstChild("Keys");k=k and k:FindFirstChild("Again") -- PF043 D1c
        if k then for _,n in {"BusyTitle","Sub"} do setVis(k:FindFirstChild(n),false) end;setVis(k:FindFirstChild("Label"),true)
            local sock=k:FindFirstChild("Socket");if sock then setVis(sock:FindFirstChild("Icon"),true);setVis(sock:FindFirstChild("Spinner"),false) end end end end
    local kind=outcome()
    activeView()
    for _,v in views do paintHero(v,kind);paintText(v,kind);paintKeys(v,kind);paintCobalt(v);fit(v) end
    busy(result:GetAttribute("PFReturning")==true)
    -- gamepad: the first key (RevampInterface focuses the hidden legacy Continue)
    if UIS.GamepadEnabled then task.defer(function()
        local v=activeView();local ks=v and v.root:FindFirstChild("Keys");local k=nil
        for _,name in {"Again","ReturnBig","Return"} do local c=ks and ks:FindFirstChild(name);if c and c.Visible and v.root:GetAttribute("PF043Simple")==true then k=c;break end end -- PF043 D1c
        k=k or (ks and ks:FindFirstChild("Return"))
        if k and result.Visible then GuiService.SelectedObject=k end
    end) end
end
function M.attach(resultFrame: any)
    if started then return end
    local pf=resultFrame:FindFirstChild("PFEnd");if not pf then return end
    started=true;result=resultFrame;root=pf;gui=resultFrame:FindFirstAncestorOfClass("ScreenGui")
    for _,name in {"Desk","Phone"} do local r=pf:FindFirstChild(name);if r then table.insert(views,{root=r}) end end
    bindClaims()
    Feed.subscribe(observe)
    -- MM 2026-10-14 (A06: "nothing may overlap the end card"): the top-left HUD row (search, exit, settings, clock) steps
    -- aside while the card is up; Keep watching / Keep playing (the card closes) brings it back. Nothing else sets its Visible.
    -- PIVOT live test (A06): the open leaderboard reached over the card's corner too; it steps aside with the icon row
    local function hudClear()
        for _,name in {"PFIconBar","PFLeaderboardRegion"} do
            local node=result.Parent and result.Parent:FindFirstChild(name)
            if node and node:IsA("GuiObject") then node.Visible=not result.Visible end
        end
    end
    result:GetPropertyChangedSignal("Visible"):Connect(function() hudClear();if result.Visible then M.refresh() else requeuing=false;busy(false) end end)
    -- PF043 D1c: after Play again the big key shows "Next match · 0:18" (or "Finding a match…") from hooks.requeueState only
    Run.RenderStepped:Connect(function()
        if not requeuing or not result.Visible then return end
        local title,sub="Starting…",""
        if state.online then local ok,LR=pcall(require,script.Parent.LeaveRequeue);if ok then title,sub=(LR :: any).busyText(if hooks.requeueState then hooks.requeueState() else nil) end end
        for _,v in views do
            local k=v.root:FindFirstChild("Keys");k=k and k:FindFirstChild("Again")
            if not k then continue end
            local l,bt,sb=k:FindFirstChild("Label"),k:FindFirstChild("BusyTitle"),k:FindFirstChild("Sub")
            if l then l.Visible=false end
            if bt then bt.Visible=true;if bt.Text~=title then bt.Text=title end end
            if sb then sb.Visible=sub~="";if sb.Text~=sub then sb.Text=sub end end
            local sock=k:FindFirstChild("Socket");if sock then setVis(sock:FindFirstChild("Icon"),false);local sp=sock:FindFirstChild("Spinner");if sp then sp.Visible=true;sp.Rotation=os.clock()*360 end end
        end
    end)
    hudClear()
    result:GetAttributeChangedSignal("Outcome"):Connect(M.refresh)
    result:GetAttributeChangedSignal("PFReturning"):Connect(function() busy(result:GetAttribute("PFReturning")==true) end)
    result:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if result.Visible then activeView() end end)
    -- the 2x chip (the plate's Double + its hit area) and the purchase it opens
    for _,v in views do
        local chip=v.root:FindFirstChild("Cobalt") and v.root.Cobalt:FindFirstChild("Double",true) -- v9: under PFBody
        if chip and chip:IsA("GuiButton") then
            chip.Activated:Connect(buyDouble)
            local hit=chip:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then hit.Activated:Connect(function() if chip.Visible then buyDouble() end end) end
        end
    end
    Marketplace.PromptGamePassPurchaseFinished:Connect(function(player: Player,passId: number,purchased: boolean)
        local pass=doublePass()
        if player==Players.LocalPlayer and purchased and pass and passId==pass.passId and result and result.Visible then onDoubleBought() end
    end)    for _,v in views do
        local ret=v.root:FindFirstChild("Keys") and v.root.Keys:FindFirstChild("Return")
        if ret then
            -- hover: the gloss brightens (the face's lip and rim stay)
            local fade=ret:FindFirstChild("Gloss") and ret.Gloss:FindFirstChild("Fade")
            ret.MouseEnter:Connect(function() if fade then fade.Transparency=NumberSequence.new(.45,1) end end)
            ret.MouseLeave:Connect(function() if fade then fade.Transparency=NumberSequence.new(.7,1) end end)
        end
    end
end
-- MatchController's hooks: requestReturn(), keepWatching(), playAgain(info), ownerColor(owner)
function M.bind(resultFrame: any,h: any)
    hooks=h or {}
    M.attach(resultFrame)
    if bound or not root then return end
    bound=true
    for _,v in views do
        local keys=v.root:FindFirstChild("Keys");if not keys then continue end
        local function on(name: string,fn: ()->())
            local k=keys:FindFirstChild(name);if not (k and k:IsA("GuiButton")) then return end
            k.Activated:Connect(function() if k.Active then fn() end end)
            -- v5: the invisible 44 dp hit area sits on top of the key (SPACING override); it acts for the key
            local hit=k:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then hit.Activated:Connect(function() if k.Active and k.Visible then fn() end end) end
        end
        -- release QA (PF - 2): every Return variant acts, the tutorial's / a room's big "Return to lobby" (ReturnBig) and the
        -- full-row one (ReturnWide) too: only "Return" was bound, so the tutorial's end card had a dead key
        local function ret() if hooks.requestReturn then hooks.requestReturn() end end
        on("Return",ret);on("ReturnBig",ret);on("ReturnWide",ret)
        local function watch() if hooks.keepWatching then hooks.keepWatching() end end
        on("Watch",watch);on("WatchWide",watch)
        local function again()
            if v.root:GetAttribute("PF043Simple")==true then requeuing=true end -- PF043 D1c: the key turns into the countdown
            if hooks.playAgain then hooks.playAgain({online=state.online,kind=state.kind,config=state.config}) end
        end
        on("Again",again);on("AgainWide",again)
    end
end
-- PIVOT D10 (ReviveView): the Revive card takes the Desk's place while the offer is open; its Keep watching / Return run the
-- same MatchController hooks as the end card's own keys
function M.setRevive(on: boolean)
    reviveUp=on==true
    if result and result.Visible then activeView() end
end
function M.run(name: string)
    local fn=hooks[name];if type(fn)=="function" then fn() end
end
M._state=function() return state end -- tests
return M
