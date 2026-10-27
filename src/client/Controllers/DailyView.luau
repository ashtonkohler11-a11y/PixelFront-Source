--!strict
-- Roadmap #1 (PF - 1; boards work/daily/boards 1-3): every daily surface, content only. The layout is authored
-- (tools/atlas/author-daily.luau); this fills texts, colours, sheet cells and visibility from DailyClient.
--   View.lobby(gui)            the Play page chips (desktop: the heading line; phones: the bottom strip), the streak popup,
--                              the plate dot
--   View.attachMatch(getDiplomacy)  the "challenge done" notice in the match's notice stack (PFNoticeDaily)
--   View.endCard(result, matchId)   the end card's DAILY block (Desk) / ring row + one Claim (Phone)
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Daily=require(script.Parent.DailyClient)
local RewardDrop=require(script.Parent.RewardDrop) -- PF043 (Ashton: "all of them"): every "you got it" moment plays the reward drop
local View={}
View.PHONE=540 -- the menu height at or under which the chips use the bottom strip (AtlasQueueDock's pill threshold)
View.HOLD=.6 -- seconds: a long-press on a running daily rerolls it
View.TIP_SECONDS=2.5
View.AUTO_DELAY=1.5 -- PIVOT D14: seconds after the menu settles before the daily sheet opens on its own
local hex=Color3.fromHex
local C={card=hex("#262626"),rim=hex("#3a3a3a"),text=hex("#f2f2f2"),gold=hex("#ddbf76"),goldHi=hex("#ffd77a"),goldFill=hex("#2a2414"),weeklyRim=hex("#6b5a2e"),
    cobalt=hex("#3678ff"),cobaltHi=hex("#6f9bff"),green=hex("#4ade80"),ice=hex("#a9c4ff"),dim=hex("#7d828c"),dimmer=hex("#6d717a"),pip=hex("#3a3d44"),
    todayFill=hex("#1b2440"),todayInk=hex("#cfe0ff"),dayInk=hex("#8f939b"),xpInk=hex("#e8d39a")}
local GLYPH={tiles=32,tribes=33,nations=33,cities=34,win=35,nuke=36,survive=37,clock=37,check=38,calendar=39}
local function find(root: Instance?,name: string): any return root and root:FindFirstChild(name) end
local function setCell(img: any,index: number)
    if img and img:IsA("ImageLabel") then img.ImageRectOffset=Vector2.new((index%8)*64,math.floor(index/8)*64) end
end
local function show(item: any,on: boolean) if item then item.Visible=on end end
local function setText(item: any,s: string,color: Color3?) if item then item.Text=s;if color then item.TextColor3=color end end end
local function rim(item: any): UIStroke? return item and item:FindFirstChild("Rim") end
local function catalogName(id: string?): string?
    local shared=ReplicatedStorage:FindFirstChild("Shared");local m=shared and shared:FindFirstChild("CosmeticCatalog")
    if not m or not id then return nil end
    local ok,c=pcall(require,m)
    local item=ok and type(c)=="table" and type(c.byId)=="table" and c.byId[id]
    return if item then item.name else nil
end
-- the skin's art: its uploaded static copy (CosmeticArtAssets, the shop's still), else CosmeticArt's own binding
local function bindArt(img: any,id: string?)
    if not img or not id then return end
    local shared=ReplicatedStorage:FindFirstChild("Shared");local m=shared and shared:FindFirstChild("CosmeticArtAssets")
    local okA,assets=pcall(require,m :: any)
    local entry=okA and type(assets)=="table" and assets[id]
    if entry and type(entry.image)=="string" and entry.image~="" then img.Image=entry.image;return end
    local ok,art=pcall(require,script.Parent.CosmeticArt)
    if ok then pcall((art :: any).bind,img,id) end
end

-- ------------------------------------------------------------------ a ring (well, track, arc, glyph, done badge)
-- tone: "cobalt" | "gold" (the weekly)
function View.paintRing(r: any,c: any,tone: string?)
    if not r or type(c)~="table" then return end
    local f=Daily.fraction(c);local finished=c.state=="done" or c.state=="claimed"
    local arc=find(r,"Arc")
    if arc then
        local n=math.clamp(math.floor(f*25+.5),0,25);if f>0 and n==0 then n=1 end
        arc.Visible=n>0;setCell(arc,n)
        arc.ImageColor3=if finished then C.green elseif tone=="gold" then C.goldHi else C.cobalt
    end
    local glyph=find(r,"Glyph");setCell(glyph,GLYPH[c.kind] or GLYPH.tiles)
    if glyph then glyph.ImageColor3=if c.state=="claimed" then C.dim else Color3.new(1,1,1) end
    show(find(r,"Done"),finished)
end

-- ------------------------------------------------------------------ the Play page chips
local function paintChip(b: any,c: any,weekly: boolean)
    if not b or type(c)~="table" then show(b,false);return end
    b.Visible=true
    local body=find(b,"Body");local edge=rim(body)
    local done,claimed=c.state=="done",c.state=="claimed"
    if body then body.BackgroundColor3=if done then C.goldFill else C.card end
    if edge then edge.Color=if done then C.goldHi elseif weekly then C.weeklyRim else C.rim;edge.Thickness=if done then 1.4 else 1 end
    show(find(b,"GoldLine"),weekly and not done)
    View.paintRing(find(b,"Ring"),c,if weekly then "gold" else "cobalt")
    local reward=c.reward or {}
    local cobalt=tostring(reward.cobalt or "")
    local phone=find(b,"Progress")==nil
    show(find(b,"Key"),done)
    if phone then
        show(find(b,"Gem"),not done);setText(find(b,"Reward"),cobalt,if claimed then C.dimmer else C.ice);show(find(b,"Reward"),not done)
    else
        show(find(b,"Progress"),not done);show(find(b,"Gem"),not done);show(find(b,"Reward"),not done)
        setText(find(b,"Progress"),Daily.progressText(c),if claimed then C.dim else C.text)
        setText(find(b,"Reward"),Daily.rewardText(reward),if claimed then C.dimmer else C.ice)
        show(find(b,"ClaimGem"),done);show(find(b,"ClaimAmount"),done);setText(find(b,"ClaimAmount"),cobalt)
        show(find(b,"ClaimXp"),done and reward.xp~=nil);setText(find(b,"ClaimXp"),if reward.xp then tostring(reward.xp).." XP" else "")
    end
    b:SetAttribute("PFDailyState",c.state)
end
local function paintBonus(b: any,bonus: any)
    if not b or type(bonus)~="table" then show(b,false);return end
    b.Visible=true
    local done=bonus.state=="done";local claimed=bonus.state=="claimed"
    local body=find(b,"Body");local edge=rim(body)
    if body then body.BackgroundColor3=if done then C.goldFill else hex("#1d1f24") end
    if edge then edge.Color=if done then C.goldHi else C.rim end
    local n=tonumber(bonus.done) or 0
    for i=1,3 do local p=find(b,"Pip"..i);if p then p.BackgroundColor3=if i<=n then C.green else C.pip end end
    setText(find(b,"Amount"),"+"..tostring(bonus.reward and bonus.reward.cobalt or 100),if done then C.goldHi elseif claimed then C.dimmer else C.ice)
    b:SetAttribute("PFDailyState",bonus.state)
end
function View.paintRow(row: any,s: any)
    if not row then return end
    local daily=type(s)=="table" and s.daily or {}
    for i=1,3 do paintChip(find(row,"Daily"..i),daily[i],false) end
    paintBonus(find(row,"Bonus"),type(s)=="table" and s.bonus)
    paintChip(find(row,"Weekly"),type(s)=="table" and s.weekly,true)
end
-- the chip's challenge (or the bonus) in the current state
local function pieceOf(b: Instance): (any?,string?)
    local s=Daily.get();if type(s)~="table" then return nil,nil end
    local i=tonumber(string.match(b.Name,"^Daily(%d)$"))
    if i then return s.daily and s.daily[i],"daily" end
    if b.Name=="Weekly" then return s.weekly,"weekly" end
    if b.Name=="Bonus" then return s.bonus,"bonus" end
    return nil,nil
end
local function tipText(b: Instance): string?
    local c,target=pieceOf(b);if not c then return nil end
    if target=="bonus" then return "All three dailies · +"..tostring(c.reward and c.reward.cobalt or 100) end
    local line=Daily.line(c)..(if target=="weekly" then " · weekly" else "")
    if c.state=="claimed" then return line.." · claimed" end
    return line.." · "..Daily.progressText(c)
end

-- ------------------------------------------------------------------ the streak popup
local function paintDay(t: any,d: number,tile: any,s: any)
    if not t then return end
    local streak=s.streak
    local today=tonumber(streak.today) or 1
    local state=if d<today or (d==today and not streak.claimable) then "claimed" elseif d==today then "today" else "next"
    local item=type(tile)=="table" and type(tile.item)=="string" and tile.item or nil
    local gold=d==7
    local isToday=state=="today"
    local body=find(t,"Body");local edge=rim(body)
    if body then body.BackgroundColor3=if gold then C.goldFill elseif isToday then C.todayFill else C.card end
    if edge then
        edge.Color=if isToday then (if item then C.goldHi else C.cobaltHi) elseif gold then C.goldHi elseif item then C.weeklyRim else C.rim
        edge.Thickness=if isToday then 2 else 1
    end
    local glow=find(t,"Glow");if glow then glow.Visible=isToday;glow.BackgroundColor3=if item then C.goldHi else C.cobalt end
    setText(find(t,"Num"),tostring(d),if gold or item then C.goldHi elseif isToday then C.todayInk else C.dayInk)
    local small=find(t,"ArtSmall")
    local owned=item~=nil and tile.owned==true and small~=nil
    local fresh=item~=nil and not owned
    local cobalt=tostring(tile and tile.cobalt or "")
    -- a Cobalt day (or an owned skin on a narrow tile): the gem and the amount
    show(find(t,"Gem"),item==nil or (tile.owned==true and small==nil));show(find(t,"Amount"),item==nil or (tile.owned==true and small==nil))
    setText(find(t,"Amount"),cobalt)
    local win=find(t,"ArtWindow");show(win,fresh);show(find(t,"SkinTag"),fresh)
    if fresh then bindArt(find(win,"Art"),item) end
    show(small,owned);show(find(t,"OwnedGem"),owned);show(find(t,"OwnedAmount"),owned);setText(find(t,"OwnedAmount"),cobalt)
    if owned then bindArt(find(small,"Art"),item) end
    local name=find(t,"ItemName")
    if name then
        name.Visible=fresh or owned
        name.Text=if owned then "Owned · Cobalt instead" else (catalogName(item) or "")
        name.TextColor3=if owned then hex("#9aa3b5") else C.goldHi
    end
    show(find(t,"Shade"),state=="claimed");show(find(t,"Check"),state=="claimed")
end
-- PF043 G2 (Ashton: "Good, build"; board work/pf043/boards/PF043-G2-streak.png): the road to day 7 (tools/atlas/author-pf043-streak-road.luau).
-- Done days sit back with a check; today is lifted (its Lift UIScale) with a TODAY tag and a tight glow; the Cobalt pile grows with the
-- amount; a skin shows its art big (an owned one pays its Cobalt); the road fills to today; Claim / the grey Claimed + its timer.
local function pileCount(c: number): number return if c<=25 then 1 elseif c<=40 then 2 elseif c<=50 then 3 elseif c<=60 then 4 else 5 end
function View.paintRoad(panel: any,s: any)
    local streak=s.streak
    local today=math.clamp(tonumber(streak.today) or 1,1,7);local can=streak.claimable==true
    setText(find(panel,"Sub"),"Day "..today.." of 7")
    local fill=find(find(panel,"Road"),"Fill");if fill then fill.Size=UDim2.fromScale((today-1)/6,1) end
    local tiles=type(streak.tiles)=="table" and streak.tiles or {}
    for d=1,7 do
        local t=find(panel,"Day"..d);if not t then continue end
        local tile=tiles[d]
        local state=if d<today or (d==today and not can) then "done" elseif d==today then "today" else "next"
        local now=state=="today";local hero=d==7
        local lift=find(t,"Lift");if lift then lift.Scale=if now then (if hero then 1.08 else 1.16) else 1 end
        show(find(t,"Glow"),now);show(find(t,"Tag"),now)
        local item=type(tile)=="table" and type(tile.item)=="string" and tile.item or nil
        local ownedSkin=item~=nil and tile.owned==true;local fresh=item~=nil and not ownedSkin
        local cobalt=tonumber(type(tile)=="table" and tile.cobalt) or 0
        local edge=rim(find(t,"Body"))
        if edge then edge.Color=if now then C.goldHi elseif hero then hex("#8fb6ff") elseif item then hex("#5c4d28") else hex("#343a46");edge.Thickness=if now or hero then 2 else 1 end
        setText(find(t,"Num"),"DAY "..d,if now then C.goldHi elseif hero then hex("#cfe0ff") elseif state=="next" then hex("#646973") else C.dayInk)
        local pile=find(t,"Pile");show(pile,item==nil)
        if pile then local k=pileCount(cobalt);for i=1,5 do show(find(pile,"G"..i),i<=k) end end
        show(find(t,"Amount"),item==nil);setText(find(t,"Amount"),tostring(cobalt))
        local win=find(t,"ArtWindow");show(win,fresh);if fresh then bindArt(find(win,"Art"),item) end
        local name=find(t,"ItemName");show(name,fresh);if fresh and name then name.Text=catalogName(item) or "" end
        show(find(t,"SkinTag"),fresh)
        local own=find(t,"Owned");show(own,ownedSkin)
        if ownedSkin and own then bindArt(find(find(own,"ArtSmall"),"Art"),item);setText(find(own,"OwnedAmount"),tostring(cobalt)) end
        show(find(t,"Shade"),state=="done");show(find(t,"Check"),state=="done")
    end
    show(find(panel,"Claim"),can);show(find(panel,"Claimed"),not can);show(find(panel,"Timer"),not can)
end
-- PIVOT (Ashton picked "Stage + prize": "Good, build"; boards work/pivot/daily/boards/DS2-A-*): author-pf043-streak-road v3.
-- Today stands on the stage (its one big view) with Claim; Day 7 is the prize scene; days 1-6 below: done days greyed with a
-- check, today dimmed under a gold rim and NOW, tomorrow rimmed in Cobalt. The Cobalt art grows by tier (the shop's own ladder).
local PILE={{25,"rbxassetid://120204330036909",.62},{40,"rbxassetid://110157285242350",.7},{50,"rbxassetid://97931764778480",.78},
    {60,"rbxassetid://136677840941972",.86},{math.huge,"rbxassetid://126899253032057",.94}}
local function pileOf(c: number): (string,number)
    for _,p in PILE do if c<=p[1] then return p[2],p[3] end end
    return PILE[#PILE][2],PILE[#PILE][3]
end
local LIT,DIM=Color3.new(1,1,1),Color3.new(105/255,108/255,116/255)
local S={gold=hex("#d0ae64"),goldHi=hex("#f0d38c"),pipOff=hex("#4a4128"),cobalt=hex("#62baff"),cobaltHi=hex("#9fd3ff"),storm=hex("#8fb6ff"),
    rim=hex("#33373f"),ink=hex("#e5e9e8"),skinInk=hex("#e8cf8f"),grey=hex("#7d8494")}
local function tileOf(tile: any): (string?,boolean,number)
    local item=type(tile)=="table" and type(tile.item)=="string" and tile.item or nil
    return item,item~=nil and tile.owned==true,tonumber(type(tile)=="table" and tile.cobalt) or 0
end
function View.paintStage(panel: any,s: any)
    local streak=s.streak
    local today=math.clamp(tonumber(streak.today) or 1,1,7);local can=streak.claimable==true
    local tiles=type(streak.tiles)=="table" and streak.tiles or {}
    setText(find(panel,"Title"),"Day "..today.." of 7")
    local st=find(panel,"Streak")
    for i=1,7 do local p=find(st,"Pip"..i);if p then p.BackgroundColor3=if i<=today then S.goldHi else S.pipOff end end
    setText(find(st,"Label"),today.."-day streak")
    -- the stage: today
    local stage=find(panel,"Stage");local rw=find(stage,"Reward")
    local item,owned,cobalt=tileOf(tiles[today]);local fresh=item~=nil and not owned
    local pile,win=find(rw,"Pile"),find(rw,"ArtWindow")
    show(pile,not fresh);show(win,fresh)
    if pile and not fresh then pile.Image=(pileOf(cobalt));pile.ImageColor3=if can then LIT else DIM end
    if fresh and win then local a=find(win,"Art");bindArt(a,item);if a then a.ImageColor3=if can then LIT else DIM end end
    show(find(stage,"Gem"),not fresh);show(find(stage,"Amount"),not fresh);setText(find(stage,"Amount"),"+"..tostring(cobalt))
    show(find(stage,"ItemName"),fresh);if fresh then setText(find(stage,"ItemName"),catalogName(item) or "") end
    setText(find(stage,"Overline"),if fresh then "TODAY · MAP SKIN" else "TODAY")
    show(find(panel,"Claim"),can);show(find(panel,"Claimed"),not can)
    -- the clock only once today is claimed (MM: "Next in" while Claim waits reads as broken)
    show(find(panel,"Timer"),not can)
    -- the prize: Day 7
    local prize=find(panel,"Prize")
    if prize then
        local pItem,pOwned,pCobalt=tileOf(tiles[7]);local done7=today==7 and not can
        -- on day 7 the prize is today: dimmed under NOW like a row tile (the stage shows it big)
        local art=find(prize,"Art");bindArt(art,pItem);if art then art.ImageColor3=if today==7 then DIM else LIT end
        setText(find(prize,"Name"),catalogName(pItem) or "Prize")
        setText(find(prize,"Sub"),if pOwned then "Owned · +"..pCobalt.." Cobalt" elseif today==7 then "Map skin · today" elseif today==6 then "Map skin · tomorrow"
            else "Map skin · "..(7-today).." days to go")
        show(find(prize,"Now"),today==7 and can);show(find(prize,"Check"),done7)
        local edge=rim(prize);if edge then edge.Color=if today==7 then S.goldHi else S.storm end
    end
    -- days 1-6
    for d=1,6 do
        local t=find(panel,"Day"..d);if not t then continue end
        local now,tomorrow=d==today,d==today+1
        local done=d<today or (now and not can)
        local tItem,tOwned,tCobalt=tileOf(tiles[d]);local tFresh=tItem~=nil and not tOwned
        setText(find(t,"Label"),"DAY "..d,if now then S.gold elseif tomorrow then S.cobaltHi else S.grey)
        local edge=rim(find(t,"Body"))
        if edge then
            edge.Color=if now then S.goldHi elseif tomorrow then S.cobalt else S.rim
            edge.Thickness=if now or tomorrow then 2 else 1;edge.Transparency=if tomorrow then .3 else 0
        end
        local tint=if done or now then DIM else LIT
        local art,tWin=find(t,"Art"),find(t,"ArtWindow")
        show(art,not tFresh);show(find(t,"Shadow"),not tFresh);show(tWin,tFresh)
        if art and not tFresh then
            local image,grow=pileOf(tCobalt);art.Image=image;art.ImageColor3=tint
            local g=find(art,"Grow");if g then g.Scale=grow/.94 end
        end
        if tFresh and tWin then local a=find(tWin,"Art");bindArt(a,tItem);if a then a.ImageColor3=tint end end
        show(find(t,"Amount"),not tFresh);setText(find(t,"Amount"),tostring(tCobalt),if done or now then S.grey else S.ink)
        show(find(t,"ItemName"),tFresh);if tFresh then setText(find(t,"ItemName"),catalogName(tItem) or "",if done or now then S.grey else S.skinInk) end
        show(find(t,"Now"),now and can);show(find(t,"Check"),done)
    end
end
function View.paintStreak(root: any,s: any)
    if not root or type(s)~="table" or type(s.streak)~="table" then return end
    local panel=find(root,"Panel");if not panel then return end
    if panel:GetAttribute("PFDailyStage")==true then View.paintStage(panel,s);return end
    if panel:GetAttribute("PF043Road")==true then View.paintRoad(panel,s);return end
    local streak=s.streak
    setText(find(panel,"Sub"),"Day "..tostring(streak.today or 1).." of 7")
    local tiles=type(streak.tiles)=="table" and streak.tiles or {}
    for d=1,7 do paintDay(find(panel,"Day"..d),d,tiles[d],s) end
    local claim=find(panel,"Claim")
    if claim then
        claim.Active=streak.claimable==true;claim.AutoButtonColor=false
        local label=find(claim,"Label");if label then label.Text=if streak.claimable then "Claim" else "Claimed" end
    end
end

-- ------------------------------------------------------------------ lobby
function View.openStreak() end -- set by View.lobby (PF043 F)
local lobbyBound=false
function View.lobby(gui: Instance)
    if lobbyBound then return end
    local background=find(gui,"Background");local menu=find(background,"AtlasMenu")
    local content=menu and menu:FindFirstChild("Pages") and menu.Pages:FindFirstChild("Play")
    content=content and content:FindFirstChild("ContentScroll");content=content and content:FindFirstChild("Content")
    local top,strip=find(content,"PFDailyTop"),find(content,"PFDailyStrip")
    local popup=find(background,"PFStreak")
    if not (top or strip or popup) then return end
    lobbyBound=true
    Daily.start()
    local dot: any=nil
    if menu then for _,d in menu:GetDescendants() do if d.Name=="PFDailyDot" and not d:FindFirstAncestor("Navigation") then dot=d;break end end end -- the plate's dot (PF043 F: FreeRewardsRow owns the Shop tab's)
    local dismissed: {[any]: boolean}={}
    local function phone(): boolean return menu~=nil and (menu :: any).AbsoluteSize.Y>0 and (menu :: any).AbsoluteSize.Y<=View.PHONE end
    local function placeRows()
        local s=Daily.get();local on=type(s)=="table" and type(s.daily)=="table" and #s.daily>0 -- PIVOT: no challenges, no rows
        -- PF036 Ranked (PF - 3): while Play's Content carries PFDailyHidden the Ranked switch owns the heading line, so the
        -- desktop row (and its tip) step aside; the phone strip sits at the bottom and stays
        local hidden=content~=nil and content:GetAttribute("PFDailyHidden")==true
        if top then top.Visible=on and not phone() and not hidden end
        if strip then strip.Visible=on and phone() end
        local tipTop=content and content:FindFirstChild("PFDailyTipTop");if tipTop and hidden then tipTop.Visible=false end
    end
    -- the popup: once per day it opens on its own while the menu shows; × closes it (the plate dot then waits)
    local gameUI=find(background,"Game")
    local function blocked(): boolean
        if not (menu and (menu :: any).Visible) then return true end
        -- UI review (spawn board, Ashton-approved): never over a match. The menu can still read Visible while the match screen
        -- shows (PF - 3 saw the sheet over a Studio join's pick), so the match screen itself blocks it too
        if gameUI and (gameUI :: any).Visible then return true end
        -- never over another first-screen moment: a level reveal, the mandatory tutorial's intro, a playing reward drop
        for _,name in {"PFLevelReveal","PFTutorialOffer","PFRewardDrop"} do
            local over=find(background,name);if over and over:IsA("GuiObject") and over.Visible then return true end
        end
        return false
    end
    local autoShown: {[any]: boolean}={}
    local autoToken=0
    local paint: ()->()
    -- PIVOT D14 (Ashton 2026-10-23: "make sure that daily rewards shows up upon join, not starter pack"; this reverses PF043 F):
    -- while the streak is claimable the sheet opens on its own once per day, AUTO_DELAY after the menu settles; × or a claim
    -- dismisses it for the day. The Shop's Free rewards row stays a second way in.
    local function scheduleAuto()
        local s=Daily.get()
        if not popup or popup.Visible or type(s)~="table" or not Daily.streakClaimable(s) or dismissed[s.day] or autoShown[s.day] then return end
        autoToken+=1;local mine=autoToken
        task.delay(View.AUTO_DELAY,function()
            local now=Daily.get()
            if mine~=autoToken or type(now)~="table" or not Daily.streakClaimable(now) or dismissed[now.day] or autoShown[now.day] or popup.Visible then return end
            -- covered (the tutorial intro, a drop): try again shortly; off the menu: the menu's Visible signal repaints
            if blocked() then if menu and (menu :: any).Visible then scheduleAuto() end;return end
            autoShown[now.day]=true;View.openStreak()
        end)
    end
    paint=function()
        local s=Daily.get()
        placeRows()
        View.paintRow(top,s);View.paintRow(strip,s)
        if popup and type(s)=="table" then
            View.paintStreak(popup,s)
            local waiting=Daily.streakClaimable(s)
            if dot then dot.Visible=waiting and not popup.Visible end
            scheduleAuto()
        elseif dot then dot.Visible=false end
    end
    -- PF043 F: the 7-day sheet opens from the Shop's Free rewards row (a tap on its track)
    -- PIVOT (MM, A06 + desktop: a cyan box floated over "+25" / Claim on join): Roblox's default selection ring drew off the
    -- scaled sheet's keys. The keys show their own authored FocusBorder (it hugs them) instead of the default ring, and Claim
    -- is selected for you only when your last input was a gamepad (GamepadEnabled alone is true on any PC with a pad plugged in).
    local blankRing=Instance.new("Frame");blankRing.BackgroundTransparency=1;blankRing.BorderSizePixel=0
    local panel=popup and find(popup,"Panel")
    local keys={}
    for _,name in {"Claim","Close"} do local k=panel and find(panel,name);if k and k:IsA("GuiButton") then k.SelectionImageObject=blankRing;table.insert(keys,k) end end
    -- daily variant B: the card's keys (desk and phone copies) get the same treatment; Claim is the visible card's
    local cardsB=popup and find(popup,"PFDailyB")
    for _,n in {"Desk","Phone"} do
        local c=find(cardsB,n);local card=find(c,"Card")
        for _,k in {find(card,"Claim"),find(c,"Close")} do if k and k:IsA("GuiButton") then k.SelectionImageObject=blankRing;table.insert(keys,k) end end
    end
    -- the join modal (PF - 3, 2026-10-26; author-pf3-daily-modal): one card, its × on the card
    local modalCard=find(popup and find(popup,"PFDailyModal"),"Card")
    for _,k in {find(modalCard,"Claim"),find(modalCard,"Close")} do if k and k:IsA("GuiButton") then k.SelectionImageObject=blankRing;table.insert(keys,k) end end
    local function claimKey(): any
        if modalCard then return find(modalCard,"Claim") end
        for _,n in {"Desk","Phone"} do local c=find(cardsB,n);if c and c.Visible then return find(find(c,"Card"),"Claim") end end
        return panel and find(panel,"Claim")
    end
    local function focusRings()
        for _,k in keys do local f=k:FindFirstChild("FocusBorder");if f and f:IsA("UIStroke") then f.Enabled=GuiService.SelectedObject==k end end
    end
    GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(focusRings)
    local function padLast(): boolean
        local t=UserInputService:GetLastInputType()
        return t==Enum.UserInputType.Gamepad1 or t==Enum.UserInputType.Gamepad2 or t==Enum.UserInputType.Gamepad3 or t==Enum.UserInputType.Gamepad4
    end
    View.openStreak=function()
        if not popup or blocked() then return end
        local s=Daily.get();if type(s)~="table" then return end
        View.paintStreak(popup,s);popup.Visible=true
        if padLast() then local k=claimKey();if k then GuiService.SelectedObject=k end end
        focusRings()
        paint()
    end    local function close()
        local s=Daily.get();if type(s)=="table" then dismissed[s.day]=true end
        if popup then popup.Visible=false end
        if popup and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(popup) then GuiService.SelectedObject=nil end
        paint()
    end
    -- PIVOT (live test 2026-10-24: the sheet stayed over the tutorial's spawn): the sheet belongs to the menu. When a match
    -- takes the screen (the menu hides) it steps aside, not dismissed, so it can open again back in the lobby.
    if menu and popup then
        local function stepAside()
            if not popup.Visible or ((menu :: any).Visible and not (gameUI and (gameUI :: any).Visible)) then return end
            popup.Visible=false
            if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(popup) then GuiService.SelectedObject=nil end
            paint()
        end
        (menu :: any):GetPropertyChangedSignal("Visible"):Connect(stepAside)
        if gameUI then (gameUI :: any):GetPropertyChangedSignal("Visible"):Connect(stepAside) end -- a match took the screen
    end
    Daily.changed(paint)
    -- PF043: the claims asked from here (the sheet's Claim, a chip) close the sheet and play the reward drop
    local asked: {[string]: boolean}={}
    View.asked=asked
    Daily.claimed(function(claim: any)
        local key=tostring(claim.target).."|"..tostring(claim.id)
        local mine=asked[key];asked[key]=nil
        if claim.target=="streak" and claim.status~="failed" and popup and popup.Visible then close() end
        if mine and claim.status=="granted" then
            local label=if claim.target=="streak" then "DAILY REWARD" elseif claim.target=="weekly" then "WEEKLY CHALLENGE" else "DAILY CHALLENGE"
            local e=RewardDrop.entry(claim.granted,label);local drop=RewardDrop.get(gui)
            if e and drop then drop:play({e}) end
        end
    end)
    if content then content:GetAttributeChangedSignal("PFDailyHidden"):Connect(placeRows) end
    if menu then (menu :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(placeRows);(menu :: any):GetPropertyChangedSignal("Visible"):Connect(function()
        if (menu :: any).Visible then Daily.refresh() end;paint() end) end
    if popup then
        local panel=find(popup,"Panel")
        local x=find(panel,"Close");if x then x.Activated:Connect(close) end
        local dim=find(popup,"Dim");if dim then dim.Activated:Connect(close) end
        -- daily variant B (PF - 3, 2026-10-25): the sheet holds the Shop's card (PFDailyB.Desk / .Phone, filled by FreeRewardsRow);
        -- its × closes the sheet like the old one, and a claim from it closes it through the listener above
        local cardB=find(popup,"PFDailyB")
        for _,n in {"Desk","Phone"} do local c=find(cardB,n);local x=find(c,"Close");x=x and (find(x,"Hit") or x);if x then x.Activated:Connect(close) end end
        local mx=find(find(find(popup,"PFDailyModal"),"Card"),"Close");mx=mx and (find(mx,"Hit") or mx);if mx then mx.Activated:Connect(close) end
        local claim=find(panel,"Claim");if claim then claim.Activated:Connect(function() if Daily.streakClaimable() and Daily.claim("streak") then View.asked["streak|nil"]=true end end) end
    end
    -- PF043 G2: while the road is open: its timer (once a second), today's art breathing, the Claim key's light sweep
    if popup then
        local last=0
        game:GetService("RunService").Heartbeat:Connect(function()
            if not popup.Visible then return end
            local panel=find(popup,"Panel");if not panel or panel:GetAttribute("PF043Road")~=true then return end
            local now=os.clock()
            local stageView=panel:GetAttribute("PFDailyStage")==true
            if now-last>=1 then
                last=now
                local tm=find(panel,"Timer");local secs=math.max(0,math.floor(Daily.nextClaimIn(Daily.get()) or 0)) -- PF045: rolling 24 h
                local clock=string.format("%02d:%02d:%02d",secs//3600,(secs%3600)//60,secs%60)
                if tm then tm.Text=if stageView then '<font color="#9dbdaa">Next in</font>  '..clock else clock end
            end
            local s=Daily.get();local today=if type(s)=="table" and type(s.streak)=="table" then tonumber(s.streak.today) or 0 else 0
            -- the reward breathes while it waits to be claimed (v3: on the stage; v2: today's tile)
            local b=if stageView then find(find(find(panel,"Stage"),"Reward"),"Breathe") else find(find(find(panel,"Day"..today),"ArtWindow"),"Breathe")
            if b then b.Scale=if stageView and not Daily.streakClaimable(s) then 1 else 1+.025*math.sin(now*2*math.pi/2.4) end
            local sw=find(find(find(panel,"Claim"),"Sheen"),"Sweep");if sw then local p=(now%4.5)/1.1;sw.Offset=Vector2.new(if p<1 then -1.2+p*2.4 else 1.2,0) end
        end)
    end
    -- the chips: tap / hover shows the line; a finished chip claims; a long-press on a running daily rerolls it
    local function bindRow(row: any,tip: any)
        if not row then return end
        local token=0
        local function showTip(b: Instance)
            local text=tipText(b);if not tip or not text then return end
            local label=tip:FindFirstChild("Pill") and tip.Pill:FindFirstChild("Label")
            if label then label.Text=text end
            tip.Visible=true;token+=1;local mine=token
            task.delay(View.TIP_SECONDS,function() if token==mine then tip.Visible=false end end)
        end
        for _,b in row:GetChildren() do
            if not b:IsA("GuiButton") then continue end
            local held=0
            b.MouseEnter:Connect(function() showTip(b) end)
            b.MouseLeave:Connect(function() if tip then token+=1;tip.Visible=false end end)
            b.MouseButton1Down:Connect(function()
                held+=1;local mine=held
                local c,target=pieceOf(b)
                if target~="daily" or not c or c.state~="run" then return end
                task.delay(View.HOLD,function()
                    if held~=mine then return end
                    held+=1
                    local s=Daily.get()
                    if type(s)=="table" and (tonumber(s.rerolls) or 0)>0 then Daily.reroll(c.id) end
                end)
            end)
            b.MouseButton1Up:Connect(function() held+=1 end)
            b.Activated:Connect(function()
                local c,target=pieceOf(b)
                if c and c.state=="done" and target then
                    local id=if target~="bonus" then c.id else nil
                    if Daily.claim(target,id) then View.asked[tostring(target).."|"..tostring(id)]=true end -- PF043: the drop on the reply
                else showTip(b) end
            end)
        end
    end
    bindRow(top,find(content,"PFDailyTipTop"));bindRow(strip,find(content,"PFDailyTipStrip"))
    paint()
end

-- ------------------------------------------------------------------ in the match: one notice per finished challenge
local matchBound=false
function View.attachMatch(getDiplomacy: () -> any)
    if matchBound then return end
    matchBound=true
    Daily.start()
    Daily.finished(function(c: any)
        local d=getDiplomacy()
        if not d or type(d.addRichNotice)~="function" then return end
        d:addRichNotice({text=Daily.line(c),kind="POSITIVE",glyph=false,template="PFNoticeDaily",paint=function(ui: Instance)
            local glyph=ui:FindFirstChild("Glyph",true);setCell(glyph,GLYPH[c.kind] or GLYPH.tiles)
            if glyph then (glyph :: any).ImageColor3=Color3.new(1,1,1) end
            local amount=ui:FindFirstChild("Reward",true);amount=amount and amount:FindFirstChild("Amount")
            if amount then (amount :: any).Text=tostring(c.reward and c.reward.cobalt or "") end
        end})
    end)
end

-- ------------------------------------------------------------------ the end card
local function paintEndRow(r: any,c: any,weekly: boolean,matchId: any)
    if not r then return end
    if type(c)~="table" then r.Visible=false;return end
    r.Visible=true
    View.paintRing(find(r,"Ring"),c,if weekly then "gold" else "cobalt")
    local done,claimed=c.state=="done",c.state=="claimed"
    setText(find(r,"Line"),Daily.line(c)..(if weekly then " · weekly" else ""),if claimed then C.dim else C.text)
    setText(find(r,"Progress"),Daily.progressText(c),if done or claimed then C.green else C.text)
    local gain=Daily.gain(c.id,matchId)
    show(find(r,"Gain"),gain~=nil);setText(find(r,"Gain"),if gain then "+"..Daily.short(gain) else "")
    show(find(r,"Key"),done);show(find(r,"Gem"),not done);show(find(r,"Reward"),not done)
    setText(find(r,"Reward"),Daily.rewardText(c.reward),if claimed then C.dimmer else C.ice)
end
-- everything claimable now: its total (cobalt, xp) and count
local function claimTotal(s: any): (number,number,number)
    local cobalt,xp,n=0,0,0
    local function add(p: any) if type(p)=="table" and p.state=="done" then n+=1;cobalt+=tonumber(p.reward and p.reward.cobalt) or 0;xp+=tonumber(p.reward and p.reward.xp) or 0 end end
    for _,c in (if type(s.daily)=="table" then s.daily else {}) do add(c) end
    add(s.bonus);add(s.weekly)
    return cobalt,xp,n
end
local endBound=false
function View.endCard(result: any,matchId: () -> any)
    if endBound then return end
    local pf=find(result,"PFEnd");if not pf then return end
    local desk=find(find(pf,"Desk"),"Daily");local phone=find(find(pf,"Phone"),"Daily")
    if not desk and not phone then return end
    endBound=true
    Daily.start()
    local function paint()
        local s=Daily.get();local on=type(s)=="table" and type(s.daily)=="table" and #s.daily>0 -- PIVOT: no challenges, no rows
        show(desk,on);show(phone,on)
        if not on then return end
        local id=matchId()
        if desk then
            setText(find(desk,"Resets"),Daily.resetText(s))
            for i=1,3 do paintEndRow(find(desk,"Row"..i),s.daily[i],false,id) end
            paintEndRow(find(desk,"Weekly"),s.weekly,true,id)
        end
        if phone then
            for i=1,3 do View.paintRing(find(phone,"Ring"..i),s.daily[i],"cobalt");show(find(phone,"Ring"..i),s.daily[i]~=nil) end
            View.paintRing(find(phone,"RingW"),s.weekly,"gold");show(find(phone,"RingW"),type(s.weekly)=="table")
            local cobalt,xp,n=claimTotal(s)
            show(find(phone,"Key"),n>0);show(find(phone,"Gem"),n>0)
            local done=0;for _,c in s.daily do if c.state~="run" then done+=1 end end
            setText(find(phone,"Reward"),if n>0 then tostring(cobalt)..(if xp>0 then " · "..xp.." XP" else "") else done.." / 3 today",if n>0 then C.ice else C.dim)
        end
    end
    Daily.changed(paint)
    result:GetPropertyChangedSignal("Visible"):Connect(function() if result.Visible then paint() end end)
    if desk then
        for _,name in {"Row1","Row2","Row3","Weekly"} do
            local k=find(find(desk,name),"Key")
            if k then k.Activated:Connect(function()
                local s=Daily.get();if type(s)~="table" then return end
                local c=if name=="Weekly" then s.weekly else s.daily[tonumber(string.sub(name,4)) or 0]
                if type(c)=="table" and c.state=="done" then
                    Daily.claim(if name=="Weekly" then "weekly" else "daily",c.id)
                    -- the last daily of three also takes the all-three bonus
                    if name~="Weekly" and type(s.bonus)=="table" and s.bonus.state=="done" then Daily.claim("bonus") end
                end
            end) end
        end
    end
    local pk=find(phone,"Key");if pk then pk.Activated:Connect(function() Daily.claimAll() end) end
    paint()
end
return View
