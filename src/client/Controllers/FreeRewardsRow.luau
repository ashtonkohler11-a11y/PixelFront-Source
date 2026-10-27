--!strict
-- Daily reward variant B (PF - 3; Ashton 2026-10-25: "good build"; board side-session-notes/…/PF3-daily-variant-B.png): the Shop's
-- Free rewards row, the ONE daily claim place. Authored by tools/atlas/author-pf3-daily-b.luau (Scroll.PFFreeRewards desk /
-- PFFreeRewardsPhone phone, the same canvas scaled); this fills it:
--   Hero  today's reward on a stage: Day 2 / 7 play their Armory flipbook (ArmoryShowcase sheets), Day 4 the Glacier painting,
--         the Cobalt days a pile and "+N". Once claimed it turns to TOMORROW's reward (the reason to come back).
--   Week  "Daily reward · Day N of 7" over the seven stations on one line: ✓ in your colour behind you, today gold, Day 7 framed.
--   Side  one Claim (the Cobalt gem only on a Cobalt day: Ashton, "the claim button shouldnt have cobalt if theres an item"),
--         claimed: "✓ Claimed · Next in 00:00:00" (24 h after the last claim, PF045); the VIP perk under it ("2× daily rewards").
-- Claim asks the server (DailyCommand Claim streak; the reply carries VIP's bonus) and plays what lands in the reward drop.
-- The Shop tab's gold dot (Navigation.Shop.PFDailyDot) lights while the claim is ready. Shown with the Discover rows only
-- (it follows Scroll.Offers' visibility). The join sheet (Background.PFStreak.PFDailyB, opened by DailyView) holds the same
-- card, filled from here too. Content only.
local DailyClient=require(script.Parent.DailyClient)
local RewardDrop=require(script.Parent.RewardDrop)
local Showcase=require(script.Parent.ArmoryShowcase)
local Row={};Row.__index=Row
Row.FLUSH=6 -- seconds to wait for the claim reply (an Arsenal unlock is a wallet transaction) before the drop plays what landed
local hex=Color3.fromHex
-- the Cobalt days' piles by day (work/pivot/daily4/upload/ids.json: the shop's Cobalt ladder art), the Glacier pack's art
-- (PF - 1, work/pivot/glacier/upload/ids.json) and its stage crop (960 x 540 painting), how each Armory scene is framed
Row.PILE=table.freeze({[1]="rbxassetid://91398831925075",[3]="rbxassetid://84463129581235",[5]="rbxassetid://79498043828677",[6]="rbxassetid://82486807889221"})
Row.GLACIER=table.freeze({stage="rbxassetid://93428568166340",offset=Vector2.new(69,58),size=Vector2.new(826,346),tile="rbxassetid://131351477472245"})
Row.PACKS=table.freeze({glacier=table.freeze({name="Glacier Pack",kind="PACK · 5 ITEMS",accent="#8fd4ff"})})
Row.HERO_ASPECT,Row.THUMB_ASPECT=482/202,2 -- the authored stage and track thumbnails (w / h)
Row.SCRIM=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.34,.55),NumberSequenceKeypoint.new(.56,1),NumberSequenceKeypoint.new(1,1)})
Row.SCRIM_DEEP=NumberSequence.new({NumberSequenceKeypoint.new(0,.04),NumberSequenceKeypoint.new(.4,.28),NumberSequenceKeypoint.new(.66,.85),NumberSequenceKeypoint.new(1,1)})
Row.FRAMING=table.freeze({
    artillery=table.freeze({hero={z=1.3,fx=.6,fy=.55,ax=.7,ay=.52},thumb={z=1.9,fx=.62,fy=.52,ax=.5,ay=.5}}),
    -- the Daily's D7 Longshot is the Warden now (premium reshuffle); its keep stands right of centre in the scene
    warden=table.freeze({hero={z=1.08,fx=.74,fy=.5,ax=.64,ay=.6},thumb={z=1.25,fx=.76,fy=.5,ax=.5,ay=.55}}),
})
-- "HH:MM:SS" (never negative)
function Row.clock(seconds: number?): string
    local s=math.max(0,math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d:%02d",s//3600,(s%3600)//60,s%60)
end
function Row.grouped(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse();return (out:gsub("^,",""))
end
-- the row's state from the daily packet + the commerce profile
function Row.view(daily: any,profile: any): any
    local streak=type(daily)=="table" and daily.streak or nil
    local vip=type(profile)=="table" and profile.vip==true
    local streakReady=type(streak)=="table" and streak.claimable==true
    local today=if type(streak)=="table" then tonumber(streak.today) or 1 else 1
    local tiles=if type(streak)=="table" and type(streak.tiles)=="table" then streak.tiles else {}
    -- the stage: today's reward while it's claimable, else tomorrow's
    local stage=if streakReady then today else today%7+1
    return {loaded=type(streak)=="table",today=today,tiles=tiles,streakReady=streakReady,vip=vip,ready=streakReady,stage=stage}
end
-- a station's look: "claimed" (before today, or today once claimed), "today" (claimable), "next" (tomorrow, once claimed), "later"
function Row.tileState(i: number,today: number,streakReady: boolean): string
    if i<today or (i==today and not streakReady) then return "claimed" end
    if i==today then return "today" end
    if i==today+1 and not streakReady then return "next" end
    return "later"
end
-- what a tile is: "arsenal" | "pack" | "cobalt"
function Row.kind(tile: any): string
    if type(tile)~="table" then return "cobalt" end
    if type(tile.arsenal)=="string" then return "arsenal" end
    if type(tile.pack)=="string" then return "pack" end
    return "cobalt"
end
-- an Armory frame cropped to a box of `aspect` (w / h): base and glow ImageRect offset + size
function Row.crop(frame: number,aspect: number,f: any): (Vector2,Vector2,Vector2,Vector2)
    local B,G=Showcase.BASE,Showcase.GLOW
    local h=math.min(B.h,B.h/f.z);local w=math.min(B.w,h*aspect);h=w/aspect
    local x=math.clamp(f.fx*B.w-f.ax*w,0,B.w-w);local y=math.clamp(f.fy*B.h-f.ay*h,0,B.h-h)
    local base,glow=Showcase.frame(frame)
    local k=G.w/B.w
    local gx,gy=math.clamp(x*k,1,G.w-1-w*k),math.clamp(y*k,1,G.h-1-h*k)
    return base+Vector2.new(x,y),Vector2.new(w,h),glow-Vector2.new(1,1)+Vector2.new(gx,gy),Vector2.new(w*k,h*k)
end
local function arsenalName(id: string): string
    local ok,Catalog=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.ArsenalCatalog) :: any end)
    local e=ok and Catalog.byId and Catalog.byId[id]
    return if e then tostring(e.name) else id
end
local function accent(tile: any): Color3
    if Row.kind(tile)=="pack" then local p=Row.PACKS[tile.pack];return hex(if p then p.accent else "#8fd4ff") end
    local s=Showcase.items[tile.arsenal];return hex(if s then s.accent else "#ffb35c")
end

-- nodes: {desk=Frame?, phone=Frame?, offers=Frame?, dot=GuiObject?}; ctx: {phone=()->boolean, getVip=()->(), gui=ScreenGui}
function Row.new(nodes: any,ctx: any): any
    local self: any=setmetatable({nodes=nodes,ctx=ctx,connections={},profile=nil,collect=nil,t0=os.clock(),destroyed=false},Row)
    local function on(signal: RBXScriptSignal,fn: (...any)->()) table.insert(self.connections,signal:Connect(fn)) end
    -- the join sheet's copy of the card (Background.PFStreak.PFDailyB: DailyView opens / closes it, this fills it)
    local gui=ctx.gui or (nodes.desk and nodes.desk:FindFirstAncestorOfClass("ScreenGui"))
    local bg=gui and gui:FindFirstChild("Background");local sheet=bg and bg:FindFirstChild("PFStreak");local b=sheet and sheet:FindFirstChild("PFDailyB")
    -- the join modal (PF - 3, 2026-10-26; tools/atlas/author-pf3-daily-modal.luau): one compact card for every screen (phone = desk
    -- scaled), the same node names as the Shop card; it replaces the row copy while authored
    local modal=sheet and sheet:FindFirstChild("PFDailyModal")
    self.sheet=if modal then {modal=modal} elseif b then {desk=b:FindFirstChild("Desk"),phone=b:FindFirstChild("Phone")} else {}
    for _,r in self:rows() do
        if not r then continue end
        -- each key's invisible Hit (a 44 px floor around the scaled key) takes the taps
        local claim=r:FindFirstChild("Claim",true);claim=claim and (claim:FindFirstChild("Hit") or claim)
        if claim then on(claim.Activated,function() self:claim() end) end
        local get=r:FindFirstChild("GetVip",true);get=get and (get:FindFirstChild("Hit") or get)
        if get then on(get.Activated,function() if ctx.getVip then ctx.getVip() end end) end
    end
    if nodes.offers then on(nodes.offers:GetPropertyChangedSignal("Visible"),function() self:paint() end) end
    table.insert(self.connections,{Disconnect=DailyClient.changed(function() self:paint() end)} :: any)
    table.insert(self.connections,{Disconnect=DailyClient.claimed(function(c: any) self:onDaily(c) end)} :: any)
    on(game:GetService("RunService").Heartbeat,function() self:step() end)
    DailyClient.start()
    self:paint()
    return self
end
-- every card this fills: the Shop's desk / phone rows and the join sheet's two
function Row:rows(): {any}
    local list={}
    for _,r in {self.nodes.desk,self.nodes.phone,self.sheet and self.sheet.desk,self.sheet and self.sheet.phone,self.sheet and self.sheet.modal} do if r then table.insert(list,r) end end
    return list
end
function Row:update(state: any)
    if self.destroyed then return end
    self.profile=type(state)=="table" and state.profile or nil
    self:paint()
end

local GREY,DONE_TEXT,TEXT,GOLD=Color3.fromRGB(110,116,128),hex("#566173"),hex("#8d97a6"),hex("#ffd77a")
local function paintStation(s: any,tile: any,i: number,look: string)
    if not s then return end
    local kind,done=Row.kind(tile),look=="claimed"
    local owned=type(tile)=="table" and tile.owned==true
    local icon=s:FindFirstChild("Icon")
    if icon then
        icon.Image=if kind=="pack" then Row.GLACIER.tile else (Row.PILE[i] or Row.PILE[1])
        icon.ImageColor3=if done then GREY else Color3.new(1,1,1);icon.ImageTransparency=if done then .45 else 0
    end
    local thumb=s:FindFirstChild("Thumb")
    if thumb and kind=="arsenal" then
        local sc=thumb:FindFirstChild("Scene");local item=Showcase.items[tile.arsenal];local f=Row.FRAMING[tile.arsenal]
        if sc and item and f and sc:GetAttribute("PFFor")~=tile.arsenal then
            sc:SetAttribute("PFFor",tile.arsenal);sc.Image=item.sheet
            local o,z=Row.crop(2,Row.THUMB_ASPECT,f.thumb);sc.ImageRectOffset,sc.ImageRectSize=o,z
        end
        local shade=thumb:FindFirstChild("Shade");if shade then shade.Visible=done end
    end
    local m=s:FindFirstChild("Mark")
    if m then
        local rim=m:FindFirstChild("Rim")
        local bg,line,num=hex("#121a26"),hex("#3b4c62"),hex("#7d8899")
        if done then bg,line=hex("#3678ff"),hex("#9cc2ff") elseif look=="today" then bg,line,num=hex("#2a2412"),GOLD,GOLD elseif look=="next" then line,num=hex("#5d8fff"),hex("#9cc2ff") end
        m.BackgroundColor3=bg;if rim then rim.Color=line end
        local n,ck=m:FindFirstChild("Num"),m:FindFirstChild("Check")
        if n then n.Visible=not done;n.TextColor3=num end;if ck then ck.Visible=done end
    end
    -- the join modal's tiles (PFModalTile): today gold, Day 7 framed blue, the days behind you dimmed
    if s:GetAttribute("PFModalTile") then
        local tr=s:FindFirstChild("TileRim")
        s.BackgroundColor3=if look=="today" then hex("#231e10") else hex("#111620")
        s.BackgroundTransparency=if done then .45 else 0
        if tr then
            tr.Color=if look=="today" then GOLD elseif i==7 then hex("#9fd8ff") elseif look=="next" then hex("#5d8fff") else hex("#232b39")
            tr.Thickness=if look=="today" then 2.5 elseif i==7 then 2 else 1.5
            tr.Transparency=if i==7 and look~="today" then .35 else 0
        end
    end
    local lb=s:FindFirstChild("Label")
    if lb then
        local tx,gem=lb:FindFirstChild("Text"),lb:FindFirstChild("Gem")
        local coins=kind=="cobalt" or (owned and not done) -- an owned item still ahead pays its Cobalt: the label says so
        if tx then
            tx.Text=if coins then Row.grouped(tonumber(tile and tile.cobalt) or 0) elseif kind=="arsenal" then arsenalName(tile.arsenal)
                else (if Row.PACKS[tile.pack] then Row.PACKS[tile.pack].name else tostring(tile.pack))
            tx.TextColor3=if look=="today" then GOLD elseif done then DONE_TEXT else TEXT
        end
        if gem then gem.Visible=coins;gem.ImageTransparency=if done then .5 else 0 end
    end
end
-- the gem sits just left of its amount (text width changes with the number and the screen)
local function placeGems(card: any)
    local week=card:FindFirstChild("Week");if not week then return end
    for i=1,7 do
        local lb=week:FindFirstChild("Day"..i);lb=lb and lb:FindFirstChild("Label")
        local tx,gem=lb and lb:FindFirstChild("Text"),lb and lb:FindFirstChild("Gem")
        if tx and gem and gem.Visible then gem.Position=UDim2.new(.5,-math.floor(tx.TextBounds.X/2)-3,gem.Position.Y.Scale,0) end
    end
    local hero=card:FindFirstChild("Hero");local amt,x2=hero and hero:FindFirstChild("Amount"),hero and hero:FindFirstChild("X2")
    if amt and x2 and x2.Visible then x2.Position=UDim2.new(amt.Position.X.Scale,amt.TextBounds.X+10,x2.Position.Y.Scale,0) end
end
local function paintHero(h: any,tile: any,i: number,tomorrow: boolean,vip: boolean)
    if not h then return end
    local kind=Row.kind(tile);local cobalt=kind=="cobalt";local owned=type(tile)=="table" and tile.owned==true
    local function vis(name: string,on: boolean) local n=h:FindFirstChild(name);if n then n.Visible=on end;return n end
    vis("CobaltGlow",cobalt);vis("Unit",cobalt)
    local pile=vis("Pile",cobalt);if pile and cobalt then pile.Image=Row.PILE[i] or Row.PILE[1] end
    local amt=vis("Amount",cobalt);if amt and cobalt then amt.Text="+"..Row.grouped(tonumber(tile and tile.cobalt) or 0) end
    vis("X2",cobalt and vip and not tomorrow)
    local scene=vis("Scene",not cobalt);vis("Glow",kind=="arsenal")
    -- the words' dark corner: deeper on the Glacier painting (bright ice right under the title)
    local scrim=vis("Scrim",not cobalt);local fade=scrim and scrim:FindFirstChild("Fade")
    if fade then fade.Transparency=if kind=="pack" then Row.SCRIM_DEEP else Row.SCRIM end
    if scene and kind=="pack" then scene.Image=Row.GLACIER.stage;scene.ImageRectOffset=Row.GLACIER.offset;scene.ImageRectSize=Row.GLACIER.size
    elseif scene and kind=="arsenal" then local item=Showcase.items[tile.arsenal];scene.Image=if item then item.sheet else "";local g=h:FindFirstChild("Glow");if g then g.Image=scene.Image end end
    if h:GetAttribute("PFScene")~=(if kind=="arsenal" then tile.arsenal else nil) then h:SetAttribute("PFFrame",nil) end -- crop the new sheet at once
    h:SetAttribute("PFScene",if kind=="arsenal" then tile.arsenal else nil)
    vis("ChipToday",not tomorrow);vis("ChipTomorrow",tomorrow);vis("Dim",tomorrow)
    local k=vis("Kind",not cobalt);local nm=vis("ItemName",not cobalt)
    if not cobalt then
        local p=kind=="pack" and Row.PACKS[tile.pack]
        if k then k.Text=(if i==7 then "DAY 7 · " else "")..(if p then p.kind else "PREMIUM BUILDING");k.TextColor3=accent(tile) end
        if nm then nm.Text=if p then p.name elseif kind=="arsenal" then arsenalName(tile.arsenal) else tostring(tile.pack) end
    end
    local own=vis("Owned",owned and not cobalt)
    local oa=own and own:FindFirstChild("Amount");if oa then oa.Text="+"..Row.grouped(tonumber(tile.cobalt) or 0) end
end
function Row:paint()
    if self.destroyed then return end
    local v=Row.view(DailyClient.get(),self.profile)
    local discover=self.nodes.offers==nil or self.nodes.offers.Visible
    local phone=self.ctx.phone and self.ctx.phone() or false
    if self.nodes.desk then self.nodes.desk.Visible=v.loaded and discover and not phone end
    if self.nodes.phone then self.nodes.phone.Visible=v.loaded and discover and phone end
    if self.sheet.desk then self.sheet.desk.Visible=v.loaded and not phone end
    if self.sheet.phone then self.sheet.phone.Visible=v.loaded and phone end
    if self.sheet.modal then self.sheet.modal.Visible=v.loaded end
    if self.nodes.dot then self.nodes.dot.Visible=v.ready end
    self.view=v
    if not v.loaded then return end
    local busy=self.collect~=nil
    for _,r in self:rows() do
        if not r then continue end
        local card=r:FindFirstChild("Card") or r
        paintHero(card:FindFirstChild("Hero"),v.tiles[v.stage],v.stage,not v.streakReady,v.vip)
        local week=card:FindFirstChild("Week")
        if week then
            local day=week:FindFirstChild("Day");if day then day.Text="Day "..v.today.." of 7" end
            local line,lit=week:FindFirstChild("Line"),week:FindFirstChild("Lit")
            local travelled=(if v.streakReady then v.today-1 else v.today)-1 -- legs behind you
            if line and lit then lit.Visible=travelled>0;lit.Size=UDim2.fromScale(line.Size.X.Scale*math.max(0,travelled)/6,line.Size.Y.Scale) end
            for i=1,7 do paintStation(week:FindFirstChild("Day"..i),v.tiles[i],i,Row.tileState(i,v.today,v.streakReady)) end
        end
        -- the key: the gem on a Cobalt day only
        local claim,claimed=card:FindFirstChild("Claim"),card:FindFirstChild("Claimed")
        if claim then
            claim.Visible=v.ready;claim.Active=not busy
            local coins=Row.kind(v.tiles[v.today])=="cobalt"
            local icon,l=claim:FindFirstChild("Icon"),claim:FindFirstChild("Label")
            if icon then icon.Visible=coins and not busy end
            if l then
                l.Text=if busy then "…" else "Claim"
                local at=l:GetAttribute(if coins and not busy then "PFWithIcon" else "PFAlone")
                if typeof(at)=="UDim2" then l.Position=at end
                l.Size=UDim2.fromScale(if coins and not busy then l.Size.X.Scale else 1,l.Size.Y.Scale)
                l.TextXAlignment=if coins and not busy then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
            end
        end
        if claimed then claimed.Visible=not v.ready end
        -- the VIP perk
        local lane=card:FindFirstChild("Vip")
        if lane then
            local l=lane:FindFirstChild("Label");if l then l.Text=if v.vip then "VIP · 2× daily rewards ✓" else "2× daily rewards";l.TextColor3=if v.vip then GOLD else TEXT end
            local crown=lane:FindFirstChild("Crown");if crown then crown.ImageColor3=if v.vip then GOLD else hex("#c9a64f") end
            local get=lane:FindFirstChild("GetVip");if get then get.Visible=not v.vip end
        end
        placeGems(card)
    end
end
-- once a second: the timer and the label gems; every frame: the stage's flipbook and the Claim key's light sweep
function Row:step()
    if self.destroyed or not self.view or not self.view.loaded then return end
    local now=os.clock()
    local rows=self:rows()
    if not self.lastTick or now-self.lastTick>=1 then
        self.lastTick=now
        local text="Next in <b>"..Row.clock(DailyClient.nextClaimIn(DailyClient.get())).."</b>"
        for _,r in rows do
            local t=r and r:FindFirstChild("Timer",true);if t and t.Text~=text then t.Text=text end
            local card=r and r:FindFirstChild("Card");if card and r.Visible then placeGems(card) end
        end
        -- the next claim opened: ask for the new state
        if not self.view.ready and (DailyClient.nextClaimIn(DailyClient.get()) or 1)<=0 and (not self.refreshedAt or now-self.refreshedAt>10) then self.refreshedAt=now;DailyClient.refresh() end
    end
    local frame=math.floor((now-self.t0)*Showcase.FPS)%Showcase.FRAMES
    local phase=((now-self.t0)%4.5)/1.1
    local offset=if phase<1 then -1.2+phase*2.4 else 1.2
    for _,r in rows do
        if not (r and r.Visible) then continue end
        local hero=r:FindFirstChild("Hero",true)
        local id=hero and hero:GetAttribute("PFScene")
        local f=type(id)=="string" and Row.FRAMING[id]
        if hero and f and (hero:GetAttribute("PFFrame")~=frame) then
            hero:SetAttribute("PFFrame",frame)
            local bo,bs,go,gs=Row.crop(frame,Row.HERO_ASPECT,f.hero)
            local sc,g=hero:FindFirstChild("Scene"),hero:FindFirstChild("Glow")
            if sc then sc.ImageRectOffset,sc.ImageRectSize=bo,bs end
            if g then g.ImageRectOffset,g.ImageRectSize=go,gs end
        end
        local s=r:FindFirstChild("Sweep",true);if s then s.Offset=Vector2.new(offset,0) end
    end
end
function Row:claim()
    local v=self.view
    if self.destroyed or self.collect or not v or not v.ready then return end
    -- PF045: one claim; VIP's matching bonus comes back on the same reply (granted.vip)
    local c={entries={},waiting=0,streak=false}
    if v.streakReady and DailyClient.claim("streak") then c.waiting+=1;c.streak=true;c.day=v.today end
    if c.waiting==0 then return end
    self.collect=c
    task.delay(Row.FLUSH,function() if self.collect==c then self:flush() end end)
    self:paint()
end
function Row:onDaily(dc: any)
    local c=self.collect
    if not c or not c.streak or type(dc)~="table" or dc.target~="streak" then return end
    c.streak=false;c.waiting-=1
    local g=type(dc.granted)=="table" and dc.granted or nil
    if dc.status=="granted" and g then
        local label="DAY "..tostring(c.day or "").." REWARD"
        if type(g.arsenal)=="string" then table.insert(c.entries,{kind="arsenal",itemId=g.arsenal,label=label})
        elseif type(g.items)=="table" then for _,id in g.items do table.insert(c.entries,{kind="item",itemId=id,label=label}) end
        else local e=RewardDrop.entry({cobalt=g.cobalt,item=g.item},if g.owned then "ALREADY OWNED · DAY "..tostring(c.day or "") else label);if e then table.insert(c.entries,e) end end
        local vip=tonumber(g.vip)
        if vip and vip>0 then table.insert(c.entries,{kind="cobalt",amount=vip,label="VIP · 2× DAILY"}) end
    end
    if c.waiting<=0 then self:flush() end
end
function Row:flush()
    local c=self.collect;if not c then return end
    self.collect=nil
    local drop=RewardDrop.get(self.ctx.gui)
    if drop and #c.entries>0 then drop:play(c.entries,function() self:paint() end) end
    self:paint()
end
function Row:destroy()
    self.destroyed=true
    for _,c in self.connections do pcall(function() if typeof(c)=="RBXScriptConnection" then c:Disconnect() else (c :: any).Disconnect() end end) end
    table.clear(self.connections)
end
return Row
