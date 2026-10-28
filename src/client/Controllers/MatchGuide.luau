--!strict
-- PIVOT onboarding + triggered tips (PF - 1; Ashton approved the board work/pivot/onboard/boards/OB-board.png; MM). Presentation only:
-- it reads MatchController's decoded packets (MatchPacketFeed) and fills the nodes tools/atlas/author-pivot-guide.luau authors.
--   the one clock   during the tribe-mercy window (Config.Mercy: Playing, elapsed < Seconds, you under ShieldTiles) the match pill
--                   shows PFSafe ("SAFE" + the countdown, teal) over its clock; then the clock again
--   the land strip  your land, the leader's tick and the win goal (GameConfig Match.VictoryPercent of land less fallout)
--   the low edge    a soft red screen edge while your troops are under 10% of your cap
--   tips            "when you should be doing something and aren't" (Ashton). Each at most once a match, 90 s apart, at most 4 a
--                   match, never in the tutorial (the first-border tip, an onboarding tip, also shows there). A tip pointing at the
--                   map sits in the map's World (it pans and zooms with it) with a pulse on the spot; the others hang under the land
--                   strip. Tap / click the card ("Got it") or wait 12 s.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Feed=require(script.Parent.MatchPacketFeed)
local TipMemory=require(script.Parent.TipMemory) -- Ashton's tips rule: retire once done; all off after 5 matches
local GameConfig=require(RS:WaitForChild("Shared"):WaitForChild("OpenFrontGameConfig"))
local M={}
local hex=Color3.fromHex
local GOLD,AMBER=hex("#ffd77a"),hex("#ffae48")
local GAP,MAX_TIPS,SHOW_FOR=90,4,12

local nodes: any=nil
local state: any=nil
local packetNow: any=nil
local m: any={matchId=-1}
local active: any=nil -- the tip on screen {card, pulse, line, at}
-- UI audit build-out 2026-10-28: the shared motion kit (PF - 4's UiMotion); nil where it can't load (test fakes)
local Motion: any=(function() local ok,mod=pcall(function() return require(script.Parent.UiMotion) end);return if ok and type(mod)=="table" and type(mod.tween)=="function" then mod else nil end)()

local function touch(): boolean return UIS:GetLastInputType()==Enum.UserInputType.Touch end
local function short(n: number): string
    if n>=1e6 then return (string.format("%.1fM",n/1e6):gsub("%.0M","M")) end
    if n>=1e3 then return (string.format("%.1fK",n/1e3):gsub("%.0K","K")) end
    return tostring(math.floor(n))
end
-- the land share as the leaderboard and the top strip print it (HudInspectorModel.percent): "<0.1%" for a sliver, else one decimal
local function pct(p: number): string
    if p~=p or p<=0 then return "0%" elseif p<.05 then return "<0.1%" end
    return string.format("%.1f%%",math.floor(p*10+.5)/10)
end
local function clock(s: number): string s=math.max(0,math.ceil(s));return string.format("%d:%02d",s//60,s%60) end
local function name(owner: number): string local p=state and state.players[owner];return if type(p)=="table" and type(p.name)=="string" then p.name else "A rival" end
local function kind(owner: number): string? local p=state and state.players[owner];return if type(p)=="table" then p.playerType else nil end
-- an ally or a teammate: never a tip's target
local function friendly(owner: number): boolean
    for _,a in state.alliances or {} do
        if (a.requestor==1 and a.recipient==owner) or (a.requestor==owner and a.recipient==1) then return true end
    end
    local me,them=state.players[1],state.players[owner]
    return type(me)=="table" and type(them)=="table" and me.team~=nil and me.team==them.team
end
local function share(): number local ui=nodes and nodes.ui;return if ui and ui.AbsoluteSize.Y>0 then ui.AbsoluteSize.Y/1080 else 1 end

-- ------------------------------------------------------------------ the one clock + the land strip + the low edge
local function paintSafe(playing: boolean)
    local time=nodes.time;if not time then return end
    local safe=time:FindFirstChild("PFSafe");if not safe then return end
    local cfg=GameConfig.forState(state);local mercy=cfg.Mercy
    local mine=(state.counts and state.counts[1]) or 0
    local on=playing and mercy~=nil and type(state.elapsed)=="number" and state.elapsed<mercy.Seconds and mine>0 and mine<mercy.ShieldTiles
    safe.Visible=on
    local clockLabel=time:FindFirstChild("Clock");if clockLabel then clockLabel.Visible=not on end
    local rim=time:FindFirstChild("PFSafeRim");if rim then rim.Enabled=on end
    if on then safe.Left.Text=clock(mercy.Seconds-state.elapsed) end
end
-- UI review (Ashton on the spawn board: "keep the clock on its original place"): during the pick the countdown lives in the Pick
-- card only, so the match pill (its 00:00) steps aside by its own Visible and comes back when the pick ends. Repainted every
-- packet, so BeginVoteView's own hide / restore of the same pill (the vote, before the pick) can't leave it showing mid-pick.
local function paintPick()
    local time=nodes.time;if not time or not time:IsA("GuiObject") then return end
    if state.phase=="Choosing" then
        if time.Visible then time.Visible=false end
        m.pickHid=true
    elseif m.pickHid then
        m.pickHid=false;time.Visible=true
    end
end
local function paintStrip(playing: boolean)
    local strip=nodes.strip;if not strip then return end
    local mine=(state.counts and state.counts[1]) or 0
    strip.Visible=playing and mine>0
    if not strip.Visible then return end
    local land=math.max(1,(state.map and state.map.landCount or 1)-(state.falloutCount or 0))
    local goal=GameConfig.forState(state).Match.VictoryPercent or 80
    local leader,top=nil,0
    for owner,count in state.counts do if owner~=1 and count>top then leader,top=owner,count end end
    local you,lead=100*mine/land,100*top/land
    strip.You.Text="You "..pct(you)
    local wide=strip.AbsoluteSize.X>=360
    -- (no ♛: Ubuntu has no crown glyph; the gold "#1" says it)
    strip.Leader.Text=if leader then string.format("#1 %s%s · goal %d%%",if wide then name(leader).." " else "",pct(lead),goal) else string.format("goal %d%%",goal)
    -- your fill eases to its share (.3 s) instead of jumping
    if Motion then Motion.fill(strip.Track.Fill,math.clamp(you/goal,.01,1)) else strip.Track.Fill.Size=UDim2.fromScale(math.clamp(you/goal,.01,1),1) end
    strip.Track.Lead.Visible=leader~=nil;strip.Track.Lead.Position=UDim2.fromScale(math.clamp(lead/goal,0,1),.5)
end
-- PIVOT (smoke pass, A06: the land strip's left end sat under Roblox's menu pill): the status column (the strip + the slim
-- tracker under it) steps down only as far as the pill's bottom when its top-left is under the pill. Its base is the current
-- UI-size variant (PFPhoneVariant swaps Position_Phone / _Base in) or the authored spot, so this never fights PF019UiSize.
local TopbarLine=require(script.Parent.TopbarLine)
local function clearPill()
    if not nodes then return end;local strip=nodes.strip;local ui=nodes.ui;if not (strip and ui and strip.Visible) then return end
    local phone=ui:GetAttribute("PF019UiSizeKey")=="Phone"
    local function base(node: any): UDim2
        local v=node:GetAttribute(if phone then "Position_Phone" else "Position_Base")
        if typeof(v)=="UDim2" then return v end
        local a=node:GetAttribute("PFAuthoredPos");if typeof(a)~="UDim2" then a=node.Position;node:SetAttribute("PFAuthoredPos",a) end
        return a
    end
    local line,bottom=TopbarLine.inset()
    local b=base(strip);local push=0
    if line and bottom then
        local left=ui.AbsolutePosition.X+b.X.Scale*ui.AbsoluteSize.X+b.X.Offset-strip.AnchorPoint.X*strip.AbsoluteSize.X
        local top=ui.AbsolutePosition.Y+b.Y.Scale*ui.AbsoluteSize.Y+b.Y.Offset-strip.AnchorPoint.Y*strip.AbsoluteSize.Y
        if left<line-TopbarLine.GAP and top<bottom then push=math.ceil(bottom-top) end -- TopbarLine's own frame (as clearBelow)
    end
    local want=b+UDim2.fromOffset(0,push);if strip.Position~=want then strip.Position=want end
    local tracker=ui:FindFirstChild("PFTracker");local slim=tracker and tracker:FindFirstChild("Slim")
    if slim then local w2=base(slim)+UDim2.fromOffset(0,push);if slim.Position~=w2 then slim.Position=w2 end end
end
-- the tips' slot (tips, the attack alert, the opening hint): centred, 152 px down at 1080. Under the HUD's one layout (R2,
-- Game.PFOneLayout) it scales with the screen like the rest of the HUD; else a phone-height UI uses its phone column at 118
local function slot(): (number,number)
    local ui=nodes.ui;local h=ui.AbsoluteSize.Y
    if ui:GetAttribute("PFOneLayout")==true then return .5,math.floor(152*h/1080+.5) end
    local phone=h>0 and h<540
    return (if phone then (tonumber(ui:GetAttribute("PFPhoneColumnX")) or .5) else .5),(if phone then 118 else 152)
end
local alert: any=nil -- the under-attack alert on screen {card, pulse, at, by} (below)
local function paintEdge(playing: boolean)
    local edge=nodes.edge;if not edge then return end
    local troops=(state.troops and state.troops[1]) or 0;local cap=(state.caps and state.caps[1]) or 0
    edge.Visible=playing and cap>0 and ((state.counts and state.counts[1]) or 0)>0 and troops/cap<.10
    if playing and alert and alert.card and not alert.hint then edge.Visible=true end -- the under-attack alert's red edge (not the hint's)
    if Run:IsStudio() and nodes.pg and nodes.pg:GetAttribute("PFDebugLow")==true then edge.Visible=playing end -- the Studio-only check (see M.start)
end

-- ------------------------------------------------------------------ tips
local function dismiss()
    local a=active;active=nil
    if not a then return end
    for _,n in {a.card,a.pulse,a.line} do if n then n:Destroy() end end
end
-- a tile -> a Scale point in the World frame (it is sized to the map)
local function at(tile: number): UDim2
    local w,h=state.map.width,state.map.height
    return UDim2.fromScale(((tile-1)%w+.5)/w,((tile-1)//w+.5)/h)
end
local function show(id: string,o: any)
    dismiss()
    m.shown[id]=true;m.count+=1;m.lastAt=os.clock()
    local card=nodes.templates.PFTipCard:Clone()
    local s=math.min(share(),1) -- pure scale (UI review 2026-10-26): no phone floor
    card.PFScale.Scale=s
    local tone=if o.warn then AMBER else GOLD
    card.Edge.BackgroundColor3=tone;card.GotIt.TextColor3=tone;card.Action.TextColor3=tone
    card.Title.Text=o.title;card.Line.Text=o.line;card.Action.Text=o.action or "";card.Action.Visible=o.action~=nil
    local a: any={card=card,at=os.clock()}
    if o.tile and nodes.world then
        -- the pulse sits in the map (it pans and zooms with it); the card and its line live in the HUD (the map's gui draws
        -- under it: live test r1 hid a map-parented card behind the strip) and follow the pulse each frame (breathe), kept on
        -- screen between the status column and the dock
        local pulse=nodes.templates.PFTipPulse:Clone();local d=40*math.clamp(share(),.45,1)
        pulse.Size=UDim2.fromOffset(d,d);pulse.Position=at(o.tile);pulse.Visible=true
        for _,r in {pulse.Outer,pulse.Inner} do r.Line.Color=tone end;pulse.Core.BackgroundColor3=tone
        pulse.Parent=nodes.world
        card.AnchorPoint=Vector2.zero;card.Parent=nodes.ui
        local line=Instance.new("Frame");line.Name="PFTipLine";line.BorderSizePixel=0;line.BackgroundColor3=tone;line.BackgroundTransparency=.35
        line.AnchorPoint=Vector2.new(0,.5);line.Size=UDim2.fromOffset(0,math.max(1,2*s));line.ZIndex=29
        line.Parent=nodes.ui
        a.pulse,a.line,a.s=pulse,line,s
    else
        -- on screen: centred under the status column (the land strip, the slim tracker)
        local x,y=slot()
        card.AnchorPoint=Vector2.new(.5,0);card.Position=UDim2.new(x,0,0,y);card.Parent=nodes.ui
    end
    card.Visible=true
    if Motion then Motion.open(card) end -- the tip pops in from the centre (.94 -> 1)
    local function close() if active==a then dismiss() end end
    card.Activated:Connect(close);card.PFHit.Activated:Connect(close)
    -- an action line that equips a build slot (MM: the Defense Post tip opens Build on that slot): a button over the line,
    -- above the card's own hit area; it equips (CityController.equipKind, the slot's own rules) and closes the tip
    if o.equip then
        local act=Instance.new("TextButton");act.Name="PFAction";act.Text="";act.AutoButtonColor=false;act.BackgroundTransparency=1;act.Selectable=false
        act.AnchorPoint=card.Action.AnchorPoint;act.Position=card.Action.Position;act.Size=card.Action.Size;act.ZIndex=card.PFHit.ZIndex+1;act.Parent=card
        local minHit=Instance.new("UISizeConstraint");minHit.MinSize=Vector2.new(44,44);minHit.Parent=act -- invisible: the SPACING hit floor
        act.Activated:Connect(function()
            local ok,City=pcall(require,script.Parent.CityController)
            if ok then pcall(City.equipKind,o.equip) end
            close()
        end)
    end
    active=a
end
-- your border's neighbours: {owner -> a tile of theirs touching you} (every 2 s)
local function neighbours(): any
    if m.nAt and os.clock()-m.nAt<2 then return m.n end
    m.nAt=os.clock();local out={}
    local w=state.map.width;local owners=state.owners
    local border=state.borders and state.borders[1]
    for _,tile in (border and border.values) or {} do
        if tile==0 then continue end
        for _,t in {tile-1,tile+1,tile-w,tile+w} do
            local o=owners[t]
            if o and o>1 and not out[o] then out[o]=t end
        end
    end
    m.n=out
    return out
end
local function ready(id: string): boolean
    local tutorial=packetNow~=nil and (packetNow.tutorialMatch==true or packetNow.tutorial==true)
    return not m.shown[id] and m.count<MAX_TIPS and (m.lastAt==nil or os.clock()-m.lastAt>=GAP) and active==nil and not (alert and alert.card)
        and TipMemory.allowed(id,tutorial) -- Ashton's tips rule: done once / 5 matches (the tutorial is exempt)
end
-- Ashton's tips rule: the moment the player does a tip's thing (in any match), that tip retires for good (TipMemory)
local learned: {[string]: boolean}={} -- marked this session (skips the saved list's parse)
local function learn(id: string) if not learned[id] then learned[id]=true;TipMemory.mark(id) end end
local function watchLearning()
    local troops=(state.troops and state.troops[1]) or 0;local cap=(state.caps and state.caps[1]) or 0
    for _,a in state.attacks or {} do
        if a.owner~=1 or a.active==false then continue end
        local k=kind(a.targetOwner or 0)
        if k=="Nation" or k=="Human" then learn("border");learn("weak") end -- attacked a rival
        m.sends=m.sends or {}
        if a.id~=nil and not m.sends[a.id] then
            m.sends[a.id]=true
            if (a.budget or 0)<=.5*(troops+(a.budget or 0)) then learn("home") end -- a send that kept half home
        end
    end
    for _,c in state.cities or {} do if c.owner==1 and c.active~=false then learn("city");break end end
    for _,p in state.defensePosts or {} do if p.owner==1 and p.active~=false then learn("defend");break end end
    for _,p in state.ports or {} do if p.owner==1 and p.active~=false then learn("port");break end end
    local mine=(state.counts and state.counts[1]) or 0
    if mine>0 then m.firstCount=m.firstCount or mine;if mine>m.firstCount then learn("grow") end end -- took land
    if cap>0 then -- let troops regrow after running low
        if troops/cap<.05 then m.wasLow=true elseif m.wasLow and troops/cap>=.5 then learn("save") end
    end
end

-- ------------------------------------------------------------------ the under-attack alert (early-wipe fix, Ashton 2026-10-27)
-- The first attack on you in a match (the packet's firstAttacked {tick, by}, PF - 2): a red banner in the tips' slot (author-
-- pf1-attack-alert's Templates.PFAttackAlert, pure scale), the front pulsing red on the map, the red edge. ONE gold key,
-- Counterattack: the normal Attack at your send % on the attacker (MatchController's Feed.context.counterattack); "Got it" when
-- they can't be reached by land. 8 s or a tap hides it. The g_incoming horn is AudioCues' own. Every match until you've held
-- off HELD_MAX first attacks (their attack ended with most of your land kept: the saved settings.pfAttacksHeld). Never a stale
-- one after a rejoin. UI audit 2026-10-28 (a passive new player was wiped at ~4:30 with no big warning): it shows in the first
-- match and the tutorial too, just under the mission card when that is up.
local HELD_KEY,HELD_MAX,ALERT_FOR,RED="settings.pfAttacksHeld",3,8,hex("#ff5a4f")
local function heldOff(): number
    local p=Feed.context and Feed.context.preferences
    return tonumber(p and p.storage and p.storage[HELD_KEY]) or 0
end
local function closeAlert()
    local a=alert;if not a then return end
    for _,n in {a.card,a.pulse} do if n then n:Destroy() end end
    a.card=nil;a.pulse=nil
end
local function attackOn(by: number): any?
    for _,a in state.attacks or {} do if a.owner==by and a.targetOwner==1 and a.active~=false then return a end end
    return nil
end
local function showAlert(by: number)
    local template=nodes.templates:FindFirstChild("PFAttackAlert");if not template then return end
    dismiss();closeAlert() -- a tip (or the opening hint) on screen makes way
    local hit=attackOn(by);local front=neighbours()[by] or (hit and hit.sourceTile)
    local card=template:Clone();card.PFScale.Scale=math.min(share(),1)
    local x,y=slot()
    -- the mission card holds the tips' slot in the first match: the banner sits 8 px under it instead
    local tracker=nodes.ui:FindFirstChild("PFTracker");local mission=tracker and tracker:FindFirstChild("Mission")
    if m.mission and mission and mission:IsA("GuiObject") and mission.Visible and mission.AbsoluteSize.Y>0 then
        y=math.max(y,mission.AbsolutePosition.Y+mission.AbsoluteSize.Y-nodes.ui.AbsolutePosition.Y+8)
    end
    card.Position=UDim2.new(x,0,0,y)
    card.Line.Text=name(by).." sends "..short((hit and hit.budget) or 0).." at your border"
    local reach=neighbours()[by]~=nil and type(Feed.context and Feed.context.counterattack)=="function"
    card.Key.Label.Text=if reach then "Counterattack" else "Got it"
    local a: any={card=card,at=os.clock(),by=by}
    local function close() if alert==a then closeAlert() end end
    local function strike()
        if reach then pcall(Feed.context.counterattack,by) end
        close()
    end
    card.PFHit.Activated:Connect(close)
    for _,k in {card.Key,card.Key.PFKeyHit} do (k :: any).Activated:Connect(strike) end
    -- the key's centred hover / press (its PFHover UIScale; the key is anchored at its centre)
    local grow=card.Key.PFHover
    card.Key.PFKeyHit.MouseEnter:Connect(function() grow.Scale=1.04 end)
    card.Key.PFKeyHit.MouseLeave:Connect(function() grow.Scale=1 end)
    card.Key.PFKeyHit.MouseButton1Down:Connect(function() grow.Scale=.97 end)
    card.Visible=true;card.Parent=nodes.ui
    -- it slams in (1.08 -> 1, one 3 px shake) and the Counterattack key sheens once
    if Motion then
        Motion.pop(card,1.08,.18);Motion.shake(card,3)
        local sheen=card.Key:FindFirstChildWhichIsA("UIGradient",true);if sheen then Motion.sweep(sheen) end
    end
    if front and nodes.world then
        local pulse=nodes.templates.PFTipPulse:Clone();local d=48*math.clamp(share(),.45,1)
        pulse.Size=UDim2.fromOffset(d,d);pulse.Position=at(front);pulse.Visible=true
        for _,r in {pulse.Outer,pulse.Inner} do r.Line.Color=RED end;pulse.Core.BackgroundColor3=RED
        pulse.Parent=nodes.world;a.pulse=pulse
    end
    alert=a
end
local function checkAlert(packet: any,playing: boolean,tutorial: boolean)
    if alert and alert.card and os.clock()-alert.at>ALERT_FOR then closeAlert() end
    local first=packet.firstAttacked
    if type(first)~="table" or type(first.by)~="number" then return end
    -- held off? the attack ended and you kept most of your land (once a match; it counts toward HELD_MAX)
    if m.alertBy and not m.alertDone and not attackOn(m.alertBy) then
        m.alertDone=true
        local mine=(state.counts and state.counts[1]) or 0
        local p=Feed.context and Feed.context.preferences
        if mine>0 and mine>=.75*(m.alertTiles or 0) and p and p.setCached then p:setCached(HELD_KEY,tostring(heldOff()+1)) end
    end
    if m.alertSeen or not playing or (packetNow and packetNow.spectator==true) then return end
    m.alertSeen=true
    if type(first.tick)=="number" and type(state.ticks)=="number" and state.ticks-first.tick>100 then return end -- a rejoin: stale
    if heldOff()>=HELD_MAX or not TipMemory.beginner() then return end -- held off 3 / played 5 matches (Ashton's tips rule)
    m.alertBy=first.by;m.alertTiles=(state.counts and state.counts[1]) or 0
    showAlert(first.by)
end
-- ------------------------------------------------------------------ the opening hint (STATS v3 §v3.3, Ashton "Ship it")
-- A neighbour is losing land to a third nation: strike it now (Ashton's comeback move). PF - 2's server gates it (Solo Easy /
-- Medium, troops ≥ 60%, at most one per 3 min, retired once the player has made the move; Config.Dealer.OpeningHint) and sends
-- packet.openingHint {id, tick, victim, by, tile, name}. Shown once per id: the under-attack banner's anatomy in gold
-- (author-pf1-opening-hint's Templates.PFOpeningHint) in the same slot, the victim's tile touching you pulsing gold, ONE key,
-- Strike: the normal Attack at your send % on the victim (MatchController's Feed.context.counterattack). 8 s or a tap.
local GOLD_HINT=hex("#ffd36a")
local function showHint(h: any)
    local template=nodes.templates:FindFirstChild("PFOpeningHint");if not template then return end
    dismiss() -- a tip on screen makes way
    local card=template:Clone();card.PFScale.Scale=math.min(share(),1)
    local x,y=slot()
    card.Position=UDim2.new(x,0,0,y)
    local victim=if type(h.name)=="string" and h.name~="" then h.name else name(h.victim)
    card.Title.Text=victim.." is under attack"
    card.Line.Text=if type(h.by)=="number" then name(h.by).." is taking its land. Strike now!" else "Strike now!"
    local reach=type(Feed.context and Feed.context.counterattack)=="function"
    card.Key.Label.Text=if reach then "Strike" else "Got it"
    local a: any={card=card,at=os.clock(),by=h.victim,hint=true}
    local function close() if alert==a then closeAlert() end end
    local function strike()
        if reach then pcall(Feed.context.counterattack,h.victim) end
        close()
    end
    card.PFHit.Activated:Connect(close)
    for _,k in {card.Key,card.Key.PFKeyHit} do (k :: any).Activated:Connect(strike) end
    local grow=card.Key.PFHover -- centred hover / press (the key is anchored at its centre)
    card.Key.PFKeyHit.MouseEnter:Connect(function() grow.Scale=1.04 end)
    card.Key.PFKeyHit.MouseLeave:Connect(function() grow.Scale=1 end)
    card.Key.PFKeyHit.MouseButton1Down:Connect(function() grow.Scale=.97 end)
    card.Visible=true;card.Parent=nodes.ui
    local front=if type(h.tile)=="number" then h.tile else neighbours()[h.victim]
    if front and nodes.world then
        local pulse=nodes.templates.PFTipPulse:Clone();local d=48*math.clamp(share(),.45,1)
        pulse.Size=UDim2.fromOffset(d,d);pulse.Position=at(front);pulse.Visible=true
        for _,r in {pulse.Outer,pulse.Inner} do r.Line.Color=GOLD_HINT end;pulse.Core.BackgroundColor3=GOLD_HINT
        pulse.Parent=nodes.world;a.pulse=pulse
    end
    alert=a
end
local function checkHint(packet: any,playing: boolean,tutorial: boolean)
    local h=packet.openingHint
    if type(h)~="table" or type(h.victim)~="number" then return end
    local id=h.id or h.tick;if id==nil or id==m.hintId then return end
    m.hintId=id -- once per id, shown or not
    if not playing or tutorial or m.mission or (packetNow and packetNow.spectator==true) then return end
    if alert and alert.card then return end -- the under-attack alert outranks it
    if type(h.tick)=="number" and type(state.ticks)=="number" and state.ticks-h.tick>100 then return end -- a rejoin: stale
    showHint(h)
end
-- PF045 (PF - 3: "merge it with your existing Build a City smart tip"): the gold chime (your next City just became affordable)
-- shows the City tip the first time it can; false = it can't now (FeedNotices then puts a feed line instead)
local CITY_TIP={title="You can afford a City",line="Cities hold 25K more troops and grow your gold.",action="Build a City ›",equip="City"}
function M.affordCity(): boolean
    -- the first-match mission card teaches the City itself (its step 5): no tip and no feed line over it (MM 2026-10-26)
    if m.mission then return true end
    if not nodes or not state or not ready("city") then return false end
    local cities=0;for _,c in state.cities or {} do if c.owner==1 and c.active~=false then cities+=1 end end
    if cities>0 then return false end -- the tip teaches the first City; later ones get the feed line
    show("city",CITY_TIP);return true
end
local function checkTips(playing: boolean,tutorial: boolean)
    if active and os.clock()-active.at>SHOW_FOR then dismiss() end
    if not playing or (packetNow and packetNow.spectator==true) then return end
    -- while the first-match mission card is up (TutorialTracker), it is the only guide: no contextual tips over it; they
    -- resume once its steps are done (MM 2026-10-26, PF - 3's first-match run)
    if m.mission then return end
    local mine=(state.counts and state.counts[1]) or 0;if mine<=0 then return end
    local troops=(state.troops and state.troops[1]) or 0;local cap=(state.caps and state.caps[1]) or 0
    local gold=(state.gold and state.gold[1]) or 0
    local n=neighbours()
    -- onboarding: your first border with a nation or a player (the tutorial too)
    if ready("border") then
        for owner,tile in n do
            local k=kind(owner)
            if (k=="Nation" or k=="Human") and not friendly(owner) then
                show("border",{title="You border "..name(owner),tile=tile,
                    line=if touch() then "Tap their land to attack · hold to ally" else "Click their land to attack · right-click to ally"})
                return
            end
        end
    end
    if tutorial then return end
    -- low troops: under 5% of your cap
    if cap>0 and troops/cap<.05 and ready("save") then
        show("save",{warn=true,title="Save your troops",line="Let them regrow before you attack again."});return
    end
    -- an incoming attack of half your army or more
    for _,a in state.attacks or {} do
        if a.targetOwner==1 and (a.owner or 0)>1 and (a.budget or 0)>=.5*math.max(1,troops) and ready("defend") then
            show("defend",{warn=true,title=name(a.owner).." attacks with "..short(a.budget),line="That's most of your army.",action="Place a Defense Post ›",equip="DefensePost",tile=n[a.owner]})
            return
        end
    end
    -- a big send while a neighbour is stronger than you
    for _,a in state.attacks or {} do
        if a.owner==1 and (a.targetOwner or 0)>0 and not (m.seenSend or {})[a.id] then
            m.seenSend=m.seenSend or {};m.seenSend[a.id]=true
            if (a.budget or 0)>=.6*(troops+(a.budget or 0)) and ready("home") then
                for owner in n do
                    local k=kind(owner);local t=(state.troops and state.troops[owner]) or 0
                    if (k=="Nation" or k=="Human") and t>troops then
                        show("home",{warn=true,title="Keep some troops home",line=name(owner).." is next to you with "..short(t).."."});return
                    end
                end
            end
        end
    end
    -- no land gained in the first 40 s
    m.startCount=m.startCount or mine
    if type(state.elapsed)=="number" and state.elapsed>=40 and state.elapsed<70 and mine<=m.startCount and ready("grow") then
        show("grow",{title="Take the land next to you",line=if touch() then "Tap the grey land at your border to grow." else "Click the grey land at your border to grow."});return
    end
    -- (PF045: the City tip shows when the gold chime plays, M.affordCity from FeedNotices; one message, not a second tip)
    -- MM (PF - 2: piracy gold only lands when a captured trade ship reaches YOUR port): warships but no Port of yours
    local warships,ports=0,0
    for _,w in state.warships or {} do if w.owner==1 and w.active~=false then warships+=1 end end
    for _,p in state.ports or {} do if p.owner==1 and p.active~=false then ports+=1 end end
    if warships>0 and ports==0 and ready("port") then
        show("port",{title="Build a Port",line="Build a Port to cash in captured trade ships.",action="Build a Port ›",equip="Port"});return
    end
    -- a weak neighbour you haven't attacked for 30 s
    local attacking={};for _,a in state.attacks or {} do if a.owner==1 then attacking[a.targetOwner or 0]=true end end
    m.weakSince=m.weakSince or {}
    for owner,tile in n do
        local t=(state.troops and state.troops[owner]) or 0
        if t<.5*troops and not attacking[owner] and not friendly(owner) then
            m.weakSince[owner]=m.weakSince[owner] or os.clock()
            if os.clock()-m.weakSince[owner]>=30 and ready("weak") then
                show("weak",{title="Attack "..name(owner),line="They're weak: "..short(t).." against your "..short(troops)..".",tile=tile});return
            end
        else m.weakSince[owner]=nil end
    end
end

-- ------------------------------------------------------------------ wiring
local function onPacket(packet: any)
    if type(packet)~="table" or type(packet.state)~="table" or not nodes then return end
    if packet.matchId~=m.matchId then dismiss();closeAlert();alert=nil;m={matchId=packet.matchId,shown={},count=0,pickHid=m.pickHid} end
    state=packet.state;packetNow=packet
    paintPick()
    local playing=state.phase=="Playing" and nodes.ui.Visible
    local tutorial=packet.tutorialMatch==true or packet.tutorial==true
    -- the mission card: the packet's tutorial snapshot (TutorialProgress) until it reads complete
    local mission=type(packet.tutorial)=="table" and packet.tutorial.complete~=true
    if mission and not m.mission and active then dismiss() end
    m.mission=mission
    paintSafe(playing);paintStrip(playing);paintEdge(playing)
    checkAlert(packet,playing,tutorial)
    checkHint(packet,playing,tutorial)
    if playing and not (packet.spectator==true) then watchLearning() end
    if not m.tipAt or os.clock()-m.tipAt>=1 then m.tipAt=os.clock();checkTips(playing,tutorial) end
    if not playing then dismiss();closeAlert() end
end
local function breathe()
    local al=alert;if al and al.pulse then local b=.5+.5*math.sin(os.clock()*5);al.pulse.Outer.Size=UDim2.fromScale(.8+.5*b,.8+.5*b);al.pulse.Outer.Line.Transparency=.35+.5*b end
    local a=active;if not a or not a.pulse or not a.line then
        local edge=nodes and nodes.edge
        if edge and edge.Visible then for _,b in edge:GetChildren() do if b:IsA("Frame") then b.BackgroundTransparency=.15+.15*math.sin(os.clock()*3) end end end
        return
    end
    local b=.5+.5*math.sin(os.clock()*3)
    a.pulse.Outer.Size=UDim2.fromScale(.8+.4*b,.8+.4*b);a.pulse.Outer.Line.Transparency=.45+.5*b
    -- the card follows the pulse (out to its upper right), clamped to the screen between the status column and the dock
    local ui=nodes.ui;local origin=ui.AbsolutePosition;local size=ui.AbsoluteSize
    local p=a.pulse.AbsolutePosition+a.pulse.AbsoluteSize/2-origin
    local cs=a.card.AbsoluteSize
    local top=if size.Y<540 then 118 else 152
    local dock=ui:FindFirstChild("Controls");local bottom=size.Y-12
    if dock and dock:IsA("GuiObject") and dock.Visible then
        local tray=dock:FindFirstChild("Blueprints");local edge=if tray and tray:IsA("GuiObject") and tray.Visible then tray.AbsolutePosition.Y else dock.AbsolutePosition.Y
        bottom=edge-origin.Y-8
    end
    local x=math.clamp(p.X+60*a.s,12,math.max(12,size.X-cs.X-12))
    local y=math.clamp(p.Y-42*a.s,top,math.max(top,bottom-cs.Y))
    a.card.Position=UDim2.fromOffset(x,y)
    -- the line from the pulse to the card's nearer side
    local c=Vector2.new(if p.X<x then x else x+cs.X,y+cs.Y/2)
    local d=c-p;a.line.Position=UDim2.fromOffset(p.X,p.Y);a.line.Size=UDim2.fromOffset(d.Magnitude,a.line.Size.Y.Offset);a.line.Rotation=math.deg(math.atan2(d.Y,d.X))
end
function M.start()
    task.spawn(function()
        local pg=Players.LocalPlayer:WaitForChild("PlayerGui")
        local gui=pg:WaitForChild("OpenFront",120);if not gui then return end
        local ui=gui:WaitForChild("Background"):WaitForChild("Game")
        local templates=ui:WaitForChild("Templates",30)
        if not (templates and templates:FindFirstChild("PFTipCard")) then return end -- the authored nodes (author-pivot-guide) aren't there
        local map=pg:WaitForChild("OpenFrontMap",120)
        local bar=ui:FindFirstChild("PFIconBar")
        nodes={ui=ui,templates=templates,world=map and map:FindFirstChild("World",true),time=bar and bar:FindFirstChild("Time"),
            strip=ui:FindFirstChild("PFLandStrip"),edge=ui:FindFirstChild("PFLowEdge"),pg=pg}
        -- the icon bar's discs press .95 from their centre (Roblox-style, nothing more: R3): only a glyph anchored at its centre
        -- scales (R4; the discs themselves sit at AnchorPoint 0,0, so they stay still rather than grow from a corner)
        if Motion and bar then
            for _,b in bar:GetChildren() do
                if not b:IsA("GuiButton") then continue end
                local glyph=b:FindFirstChildWhichIsA("ImageLabel",true)
                if glyph and glyph.AnchorPoint==Vector2.new(.5,.5) then pcall(Motion.press,b,{hover=1,press=.95,target=glyph}) end
            end
        end
        Feed.subscribe(onPacket)
        Run.RenderStepped:Connect(breathe)
        Run.RenderStepped:Connect(clearPill) -- PIVOT: the status column clears Roblox's menu pill
        -- Studio only (live QA, where a tip's real trigger is slow to stage): PlayerGui's PFDebugTip = a tip id shows that tip now
        -- (map tips on one of your border tiles); PFDebugLow = true forces the low-troops edge. Never in a live server.
        if Run:IsStudio() then
            pg:GetAttributeChangedSignal("PFDebugTip"):Connect(function()
                local id=pg:GetAttribute("PFDebugTip");if type(id)~="string" or not state or not m.shown then return end
                local tile=nil;local border=state.borders and state.borders[1]
                for _,t in (border and border.values) or {} do if t~=0 then tile=t;break end end
                local tap=touch()
                local specs={border={title="You border Kanto",line=if tap then "Tap their land to attack · hold to ally" else "Click their land to attack · right-click to ally",tile=tile},
                    defend={warn=true,title="Kanto attacks with 6.1K",line="That's most of your army.",action="Place a Defense Post ›",equip="DefensePost",tile=tile},
                    grow={title="Take the land next to you",line=if tap then "Tap the grey land at your border to grow." else "Click the grey land at your border to grow."},
                    save={warn=true,title="Save your troops",line="Let them regrow before you attack again."},
                    city=CITY_TIP}
                if specs[id] then show(id,specs[id]) end
            end)
        end
    end)
end
M._tips=function() return m end -- tests
return M
