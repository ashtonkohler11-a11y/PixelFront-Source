--!strict
-- PF044 main screen (PF - 3). Ashton approved the board (work/pf044/main/boards/PF044-main.png) 2026-10-24: "its good just
-- make sure not to copy rofronts ui too much I dont wanna get dmca"; Your look + Stats beside Custom matches approved.
-- AtlasMenu.PFHome (tools/atlas/author-pf044-home.luau) holds two authored layouts, Desk and Phone (PF026's rule: the
-- phone one below a 520 px menu height); this module fills content and wires the actions. Nothing here sizes anything.
--   Play.Key        PLAY SOLO: one tap = a solo match with the Solo screen's settings at the picked mode
--   Modes           Easy / Medium / Hard (SoloDifficulty), written back to the Solo screen's settings
--   Play.Help / TopLeft.Help   How to play (hidden until a How to play sheet exists: Routes.howToPlay)
--   Play.Tune       all the old solo settings (Screens.Solo)
--   Custom.Open     Custom matches -> Screens.Join (Create lobby is there); Custom.Look / Custom.Stats -> those pages
--   Public          the 3 fullest public matches (Top), then the rest in a scroll frame (More); FFA only
--   Party           you + 3 seats, one line of why, INVITE FRIENDS (PF - 5: the Invite friends screen)
--   TopLeft.Settings, TopRight.Shop + Cobalt
--   ArmoryGroup.Armory  PF - 5 (Ashton approved 2026-10-25, tools/atlas/author-pf5-main.luau): the Armory's own tile, mid-left:
--                   the Armory heroes' flipbooks in turn, "n / N OWNED", a pip per item (gold when owned)
local RunService=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Preview=require(script.Parent.LobbyMapPreview)
local Showcase=require(script.Parent.ArmoryShowcase)
local HERO_LOOPS=2 -- each Armory hero plays its 2.4 s loop this many times before the next
local Home={};Home.__index=Home

local KINDS={"special","ffa","team"}
local PHONE_HEIGHT=520
local MODES={"Easy","Medium","Hard"}
local TOP_ROWS,MORE_MAX=3,20
local JOIN_GAP=3.25 -- the server takes one JoinPublic per 3 s (LobbyContract.RateLimits); the page paces sends
local TAP_GRACE=.8 -- a public row tapped this soon after it changed joins what it showed before
local C={ink=Color3.fromHex("#f2f2f2"),sub=Color3.fromHex("#b8bcc4"),muted=Color3.fromHex("#8a8a8a"),green=Color3.fromHex("#5fd38a"),
    ice=Color3.fromHex("#9fc0ff"),cobalt=Color3.fromHex("#3678ff"),pipOff=Color3.fromHex("#3a3d45"),pipOn=Color3.fromHex("#cfd6e2"),
    chip=Color3.fromHex("#1f1f1f"),red=Color3.fromHex("#f87171")}
local MODE_TINT={Easy=Color3.fromHex("#5fd38a"),Medium=Color3.fromHex("#3678ff"),Hard=Color3.fromHex("#f87171")}
local LINE_SOLO="Friends start allied." -- UI audit build-out: the old 7-word line read 5 px on an A06 (R5); the reason stays
-- UI audit build-out (Ashton: "just build it all"): every Home motion goes through PF - 4's shared UiMotion (R4 centred, reduced
-- motion and tap-to-skip handled there); pcall keeps the CLI fixtures (no UiMotion) running
local okMotion,UiMotion=pcall(function() return require(script.Parent.UiMotion) end)
local Motion: any=if okMotion and type(UiMotion)=="table" then UiMotion else nil
local okZone,Zone=pcall(function() return require(script.Parent.HitZone) end)
local HitZone: any=if okZone and type(Zone)=="table" and type(Zone.signal)=="function" then Zone else nil

local function finite(value: any): boolean return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function integer(value: any): number? return if finite(value) and value>=0 then math.floor(value) else nil end
local function find(root: Instance,name: string): any return root:FindFirstChild(name,true) end
local function commas(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (out:gsub("^,",""))
end
local function timerText(at: any,now: number): string
    if not finite(at) then return "waiting" end
    local seconds=math.max(0,math.ceil(at-now))
    return if seconds==0 then "starting" else string.format("%d:%02d",seconds//60,seconds%60)
end

function Home.new(root: Frame,context: any): any
    local self: any=setmetatable({root=root,context=context,model={},offset=0,connections={},visible=false,destroyed=false,
        mode="Easy",variant=nil,pools={},preview=Preview.new(context.mapSources),lastJoinAt=-math.huge,statusUntil=0,rowPrev={}},Home)
    self.layouts={Desk=root:FindFirstChild("Desk"),Phone=root:FindFirstChild("Phone")}
    self.templates=root:FindFirstChild("Templates")
    if context.soloDifficulty then
        local current=context.soloDifficulty()
        if table.find(MODES,current) then self.mode=current end
    end
    for name,layout in self.layouts do
        if layout then
            self:bind(layout);self.pools[name]={top={},more={}}
            -- every authored kit slot (PFCard) gets the lobby card kit's lift / press / glow, like every lobby box
            -- PF044 (Ashton: "the back frame is being hovered"): only buttons get it; a panel that holds buttons (Party, PlayPanel,
            -- Public) keeps its look still, so the hover always lands on the button under the mouse
            for _,node in layout:GetDescendants() do if node:GetAttribute("PFCard")==true and node:IsA("GuiButton") then self:bindCard(node) end end
        end
    end
    -- r5 (AtlasPlayPage's PF024 rule): a PFFloorHide label (an explainer: Your look / Stats captions, the Shop's sub, the
    -- party line) shows only when it fits at its text floor; on a small screen it steps aside instead of drawing cropped
    for _,label in root:GetDescendants() do
        if not (label:IsA("TextLabel") and label:GetAttribute("PFFloorHide")) then continue end
        local base=label:GetAttribute("PFFloorBase")
        if typeof(base)~="number" then base=label.TextTransparency;label:SetAttribute("PFFloorBase",base) end
        local function fit() label.TextTransparency=if label.TextFits then base else 1 end
        table.insert(self.connections,label:GetPropertyChangedSignal("TextFits"):Connect(fit));fit()
    end
    table.insert(self.connections,root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:pickLayout() end))
    self:bindArmory()
    self:pickLayout()
    self:bindSheens()
    return self
end
-- build-out: the logo's slow shine (every 8 s) and, until your first match, one light sweep across PLAY SOLO every 6 s
-- (author-pf3-build-home's PFLogoShine / PFKeySheen overlays: a white band in a UIGradient). UiMotion runs them only while shown.
function Home:bindSheens()
    if not Motion then return end
    self.sheens=self.sheens or {}
    local logo=self.root:FindFirstChild("PFLogoShine",true);local lg=logo and logo:FindFirstChildWhichIsA("UIGradient")
    if lg then table.insert(self.sheens,Motion.sheen(lg,{period=8,sweep=1.1})) end
    local me=Players.LocalPlayer
    local matches=me and me:GetAttribute("OpenFrontMatches")
    if type(matches)=="number" and matches==0 then
        for _,layout in self.layouts do
            local sheen=layout and find(layout,"PFKeySheen");local g=sheen and sheen:FindFirstChildWhichIsA("UIGradient")
            if g then table.insert(self.sheens,Motion.sheen(g,{period=6,sweep=.7})) end
        end
    end
end
-- PF - 5: the Armory tile: the catalog's items (shelf order), what you own (the CosmeticsState packet), a hover lift
function Home:bindArmory()
    self.owned={};self.heroClock=0;self.heroFrame=-1
    local shared=ReplicatedStorage:FindFirstChild("Shared");local catalog=shared and shared:FindFirstChild("ArsenalCatalog")
    local ok,cat=pcall(function() return catalog and require(catalog) end)
    self.armoryItems={}
    if ok and type(cat)=="table" and type(cat.items)=="table" then
        for _,item in cat.items do if Showcase.items[item.id] then table.insert(self.armoryItems,item.id) end end
    end
    self.starterPacks=if ok and type(cat)=="table" and type(cat.packs)=="table" then cat.packs else {} -- UX audit #5: the tile's Starter chip
    task.spawn(function()
        local folder=ReplicatedStorage:WaitForChild("OpenFrontRemotes",30);local state=folder and folder:WaitForChild("CosmeticsState",30)
        if self.destroyed or not (state and state:IsA("RemoteEvent")) then return end
        table.insert(self.connections,state.OnClientEvent:Connect(function(packet: any)
            if type(packet)=="table" and packet.kind=="Cosmetics" and type(packet.arsenal)=="table" and type(packet.arsenal.owned)=="table" then
                self.owned=packet.arsenal.owned;self.ownedKnown=true;self:paintArmory()
            end
        end))
    end)
    for _,layout in self.layouts do
        local tile=layout and find(layout,"ArmoryGroup");tile=tile and tile:FindFirstChild("Armory")
        local hover=tile and tile:FindFirstChild("Body") and tile.Body:FindFirstChild("PFHover")
        if tile and hover then
            local Tween=game:GetService("TweenService")
            local function to(s: number) Tween:Create(hover,TweenInfo.new(.12,Enum.EasingStyle.Quad),{Scale=s}):Play() end
            table.insert(self.connections,tile.MouseEnter:Connect(function() to(1.02) end))
            table.insert(self.connections,tile.MouseLeave:Connect(function() to(1) end))
            table.insert(self.connections,tile.MouseButton1Down:Connect(function() to(.98) end))
            table.insert(self.connections,tile.MouseButton1Up:Connect(function() to(1.02) end))
        end
    end
end
-- the hero flipbook (ArmoryShowcase sheets: 16 frames a loop); only while the home shows
function Home:stepHero(dt: number)
    local tile=self:layout();tile=tile and find(tile,"ArmoryGroup");local art=tile and find(tile,"Art")
    if not art or #self.armoryItems==0 then return end
    self.heroClock+=dt
    local frame=math.floor(self.heroClock*Showcase.FPS)
    local index=(frame//(Showcase.FRAMES*HERO_LOOPS))%#self.armoryItems+1
    local item=self.armoryItems[index]
    if frame==self.heroFrame then return end;self.heroFrame=frame
    if index~=self.heroIndex then
        -- build-out (PF - 4's home.armory idea): the next hero crossfades in (.25 s) over a still copy of the last frame of the old
        -- one (a temporary ghost, gone when it has faded), instead of a hard cut; the first paint just shows
        if self.heroIndex~=nil and Motion and type(Motion.tween)=="function" and not Motion.reduced(art) and art.Image~="" then
            local base=art:GetAttribute("PFBaseT");if type(base)~="number" then base=art.ImageTransparency;art:SetAttribute("PFBaseT",base) end
            local ghost=art:Clone();ghost.Name="PFHeroGhost";ghost.ZIndex=art.ZIndex+1
            for _,c in ghost:GetChildren() do if not c:IsA("UICorner") then c:Destroy() end end
            ghost.Parent=art.Parent
            art.ImageTransparency=1
            Motion.tween(art,{ImageTransparency=base},.25)
            Motion.tween(ghost,{ImageTransparency=1},.25)
            task.delay(.3,function() ghost:Destroy() end)
        end
        self.heroIndex=index;self:paintArmory() -- the carousel pip follows the shown item
    end
    art.Image=Showcase.items[item].sheet
    art.ImageRectOffset=(Showcase.frame(frame%Showcase.FRAMES));art.ImageRectSize=Vector2.new(Showcase.BASE.w,Showcase.BASE.h)
end
-- LobbyCardKit (the menu's shared kit): a card needs its authored PFCardBody
function Home:bindCard(card: Instance)
    local kit=self.context.cardKit
    if kit and card:FindFirstChild("PFCardBody") then pcall(kit.bind,kit,card) end
end
function Home:bind(layout: Instance)
    local context=self.context
    local function on(path: {string},callback: () -> ())
        local node: any=layout
        for _,name in path do node=node and node:FindFirstChild(name,true) end
        -- r5: the Desk's Settings + ? sit on the home root (Roblox's line, outside the scaled canvas)
        if not node and path[1]=="TopLeft" and layout.Name=="Desk" then node=self.root:FindFirstChild("TopLeft");node=node and node:FindFirstChild(path[2]) end
        -- (UI audit R8: a key's PFHitZone strips answer too, through HitZone; the fixtures have no HitZone)
        if node and node:IsA("GuiButton") then table.insert(self.connections,(if HitZone then HitZone.signal(node) else node.Activated):Connect(function()
            if self.visible and not self.destroyed then callback() end
        end)) end
        -- r5: the invisible 44 px hit boxes (a PFHits layer under each group; PFFor = this path) do the same thing
        local key=table.concat(path,"/")
        for _,hit in (if layout.Name=="Desk" then self.root else layout):GetDescendants() do
            if hit:IsA("GuiButton") and hit:GetAttribute("PFFor")==key then
                table.insert(self.connections,hit.Activated:Connect(function() if self.visible and not self.destroyed then callback() end end))
            end
        end
    end
    on({"TopLeft","Settings"},function() if context.openSettings then context.openSettings() end end)
    on({"TopLeft","Help"},function() if context.howToPlay then context.howToPlay() end end)
    on({"TopRight","Shop"},function() if context.openShop then context.openShop() end end)
    on({"ArmoryGroup","Armory"},function() if context.openArmory then context.openArmory() end end) -- PF - 5: the Armory tile (PF - 1's page)
    on({"Play","Key"},function() self:playSolo() end)
    on({"Play","Help"},function() if context.howToPlay then context.howToPlay() end end)
    on({"Play","Tune"},function() if context.soloSettings then context.soloSettings() end end)
    for _,mode in MODES do on({"Modes",mode},function() self:setMode(mode) end) end
    on({"Custom","Open"},function() if context.customMatches then context.customMatches() end end)
    on({"Custom","Look"},function() if context.openLook then context.openLook() end end)
    on({"Custom","Stats"},function() if context.openStats then context.openStats() end end)
    on({"Custom","Settings"},function() if context.openSettings then context.openSettings() end end) -- PF044: the game Settings page (Ashton)
    on({"Party","Invite"},function() if context.partyInvite then context.partyInvite() end end)
    -- build-out: the Shop card's balance + (the Armory wallet's twin) lands on the Cobalt packs; Quick join takes the fullest room
    on({"TopRight","PFWalletPlus"},function() if context.openCobalt then context.openCobalt() elseif context.openShop then context.openShop() end end)
    on({"Public","PFQuickJoin"},function() local list=self:holdOrder(self:entries());if list[1] then self:join(list[1].id) end end)
    self:bindMotion(layout)
end
-- build-out motion: the mode chips and the Look / Stats pair grow the hovered one while the others give way (R4); the top-left
-- discs press like Roblox's own; the Shop bag hops on hover
function Home:bindMotion(layout: Instance)
    if not Motion then return end
    local function nodes(names: {string},under: string): {GuiObject}
        local parent=find(layout,under);local out={}
        for _,n in names do local node=parent and parent:FindFirstChild(n);if node and node:IsA("GuiObject") then table.insert(out,node) end end
        return out
    end
    -- (PF-4.home.modes.0 / home.custom.0: hovered grows, the rest give way, from the centre; the kit's hover lift stays off them)
    local modes=nodes(MODES,"Modes");if #modes==3 then for _,c in modes do c:SetAttribute("PFCardNoLift",true) end;table.insert(self.connections,Motion.pair(modes,{grow=1.03,give=.985})) end
    local pairCards=nodes({"Look","Stats"},"Custom");if #pairCards==2 then for _,c in pairCards do c:SetAttribute("PFCardNoLift",true) end;table.insert(self.connections,Motion.pair(pairCards)) end
    local top=self.root:FindFirstChild("TopLeft");local hits=self.root:FindFirstChild("PFTopHits")
    for _,name in {"Settings","Help"} do
        local disc=top and top:FindFirstChild(name);local hit=hits and hits:FindFirstChild("Hit_TopLeft_"..name)
        if disc and disc:IsA("GuiObject") then table.insert(self.connections,Motion.press(if hit then hit else disc,{target=disc})) end
    end
    local shop=find(layout,"TopRight");shop=shop and shop:FindFirstChild("Shop")
    local bag=shop and (shop:FindFirstChild("Bag",true) or shop:FindFirstChild("Glyph",true))
    if shop and bag and bag:IsA("GuiObject") then
        local base=bag.Position
        table.insert(self.connections,shop.MouseEnter:Connect(function()
            if Motion.reduced(bag) then return end
            bag.Position=base;Motion.tween(bag,{Position=base+UDim2.fromOffset(0,-3)},.09,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
            task.delay(.09,function() Motion.tween(bag,{Position=base},.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out) end)
        end))
    end
end

-- the layout for this screen. PF044 r5 (Ashton 2026-10-24: "you didnt need to change shit for mobile, you can have that
-- same list on the right side on mobile ... you only need to change something if it looks bad when scaled down"): every
-- screen gets the Desk layout (Scale + aspect, so it scales down whole); USE_PHONE=true brings back the old switch (Phone
-- below a 520 px menu height or on a squarer screen than 16:10). The authored Phone layout stays in the place, hidden.
local DESK_ASPECT=1.5
local USE_PHONE=false
function Home:pickLayout()
    if self.destroyed then return end
    local size=self.root.AbsoluteSize
    local phone=USE_PHONE and size.Y>0 and (size.Y<PHONE_HEIGHT or size.X/size.Y<DESK_ASPECT)
    local name=if phone and self.layouts.Phone then "Phone" else "Desk"
    if not self.layouts[name] then name=if self.layouts.Phone then "Phone" else "Desk" end
    for key,layout in self.layouts do if layout then layout.Visible=key==name end end
    if name~=self.variant then self.variant=name;self:paint() end
end
function Home:layout(): any return self.variant and self.layouts[self.variant] end
function Home:now(): number return os.clock()+self.offset end

-- Solo -------------------------------------------------------------------------
function Home:setMode(mode: string)
    if not table.find(MODES,mode) then return end
    local changed=mode~=self.mode
    self.mode=mode
    if self.context.setSoloDifficulty then self.context.setSoloDifficulty(mode) end
    self:paintModes()
    -- build-out: the picked chip pops (1.06, Back) as its Sel lands
    local layout=self:layout();local chip=layout and find(layout,mode)
    if changed and Motion and chip then Motion.pop(chip,1.06,.2) end
end
function Home:playSolo()
    local context=self.context
    if context.playSolo then
        local ok,result=pcall(context.playSolo,self.mode)
        if not ok or result==false then self:status("Solo could not start. Try again.",true) end
    end
end
function Home:paintModes()
    local layout=self:layout();if not layout then return end
    for _,mode in MODES do
        local chip=find(layout,mode);if not chip then continue end
        local on=mode==self.mode
        chip:SetAttribute("PFSelected",on)
        local tint=MODE_TINT[mode]
        -- the kit owns the body's fill + stroke (hover / press); the selection is the Sel overlay on top
        local sel=find(chip,"Sel")
        if sel then
            sel.Visible=on;sel.BackgroundColor3=tint
            local rim=sel:FindFirstChild("Rim");if rim then rim.Color=tint end
        end
        -- r5: the dot rides in the label (one centred line at every size; the Dot frame hides)
        local label=find(chip,"Label")
        if label then
            label.TextColor3=if on then C.ink else C.sub;label.RichText=true
            label.Text=string.format('<font color="#%s" transparency="%s">●</font>  %s',tint:ToHex(),if on then "0" else "0.35",mode)
        end
        local dot=find(chip,"Dot");if dot then dot.Visible=false end
    end
end

-- Public matches ---------------------------------------------------------------
local function valid(entry: any): boolean
    return type(entry)=="table" and type(entry.id)=="string" and type(entry.config)=="table" and integer(entry.config.maxPlayers)~=nil
        and (entry.config.maxPlayers :: number)>0
end
local function seats(entry: any): (number,number)
    local cap=integer(entry.config.maxPlayers) or 0
    return math.min(integer(entry.numClients) or integer(entry.players) or 0,cap),cap
end
-- every listed match, the fullest first (= the soonest to start), then the nearest start, then the id
function Home:entries(): {any}
    local list,seen,now={},{},self:now()
    local queues=type(self.model.queues)=="table" and self.model.queues or {}
    for _,kind in KINDS do
        for _,entry in (if type(queues[kind])=="table" then queues[kind] else {}) do
            local n,cap=seats(entry) -- MM 2026-10-24: a full room is teleporting (publicFullStart 0): off the list too
            if valid(entry) and not seen[entry.id] and not (finite(entry.startsAt) and entry.startsAt<=now) and not (cap>0 and n>=cap) then
                seen[entry.id]=true;table.insert(list,entry)
            end
        end
    end
    table.sort(list,function(a,b)
        local an,ac=seats(a);local bn,bc=seats(b)
        local af,bf=an/math.max(ac,1),bn/math.max(bc,1)
        if af~=bf then return af>bf end
        local at,bt=if finite(a.startsAt) then a.startsAt else math.huge,if finite(b.startsAt) then b.startsAt else math.huge
        if at~=bt then return at<bt end
        return a.id<b.id
    end)
    return list
end
function Home:follower(): boolean
    local party=self.model.party
    return type(party)=="table" and type(party.size)=="number" and party.size>1 and party.isLeader~=true
end
function Home:queuedId(): string?
    local room=self.model.room
    return if type(room)=="table" and room.kind=="public" and type(room.id)=="string" then room.id else nil
end
-- a row from the layout's template, kept in a pool per list
function Home:row(list: string,index: number): any?
    local layout=self:layout();local pool=self.pools[self.variant]
    if not layout or not pool or not self.templates then return nil end
    local rows=pool[list]
    if rows[index] then return rows[index] end
    local template=self.templates:FindFirstChild("Row"..self.variant);if not template then return nil end
    local public=find(layout,"Public") -- scoped: the glyphs' pixel pieces have names too (the Shop bag's "Top")
    local parent=public and find(public,if list=="top" then "Top" else "More");if not parent then return nil end
    local row: any=template:Clone();row.Name="Row"..index;row.LayoutOrder=index;row.Visible=false;row.Parent=parent
    table.insert(self.connections,row.Activated:Connect(function()
        local entry=row:GetAttribute("PFEntry")
        local prev=self.rowPrev[row];if prev and os.clock()-prev.at<TAP_GRACE then entry=prev.id end
        if self.visible and entry then self:join(entry) end
    end))
    self:bindCard(row)
    rows[index]=row
    return row
end
function Home:paintRow(row: any,entry: any,now: number)
    local queued=self:queuedId()==entry.id
    -- PF044: your own room's row reads the live room (the dock's source), not the polled list, so the two never disagree
    local room=self.model.room
    if queued and type(room)=="table" then
        local live=table.clone(entry)
        local playing=if type(room.players)=="number" then room.players elseif type(room.members)=="table" then #room.members else nil
        if playing then live.numClients=playing;live.players=playing end
        local capacity=tonumber(room.capacity)
        if capacity then live.config=table.clone(entry.config);live.config.maxPlayers=capacity end
        if finite(room.fullStartsAt) then live.startsAt=room.fullStartsAt elseif finite(room.startsAt) then live.startsAt=room.startsAt end
        entry=live
    end
    local n,cap=seats(entry)
    local full=cap>0 and n>=cap
    local was=row:GetAttribute("PFEntry")
    if was~=entry.id then self.rowPrev[row]=if was then {id=was,at=os.clock()} else nil end
    -- build-out motion: a row that now shows another room settles in (.96 -> 1); a seat that just filled pops its pip
    local seen=row:GetAttribute("PFSeats")
    if Motion and was~=nil and was~=entry.id then Motion.pop(row,.96,.2)
    elseif Motion and was==entry.id and type(seen)=="number" and n>seen then
        local pips0=find(row,"Pips");local pip=pips0 and pips0:FindFirstChild("Pip"..n)
        if pip then Motion.pop(pip,1.3,.18) end
    end
    row:SetAttribute("PFSeats",n)
    row:SetAttribute("PFEntry",entry.id)
    row.Visible=true
    find(row,"MapName").Text=tostring(entry.config.gameMap or "Public match")
    local pips=find(row,"Pips")
    -- r5 (all Scale): the pips box hugs the seats shown, cap/8 of its authored 8-seat share (content, not device)
    local share,pad=pips and pips:GetAttribute("PFFullScale"),pips and pips:GetAttribute("PFFullPad")
    if pips and type(share)=="number" and cap>0 then
        pips.Size=UDim2.new(share*cap/8,0,pips.Size.Y.Scale,0)
        local l=pips:FindFirstChildOfClass("UIListLayout");if l and type(pad)=="number" then l.Padding=UDim.new(pad*8/cap,0) end
    end
    if pips then for i=1,8 do
        local pip=pips:FindFirstChild("Pip"..i)
        if pip then pip.Visible=i<=cap;pip.BackgroundColor3=if i<=n then (if full then C.green else C.pipOn) else C.pipOff end
    end end
    local count=find(row,"Count")
    if count then
        -- r5: no timer yet = the count alone (" · waiting" ran under JOIN on phones)
        count.Text=if full then string.format("%d/%d · starts now",n,cap) elseif finite(entry.startsAt) then string.format("%d/%d · %s",n,cap,timerText(entry.startsAt,now)) else string.format("%d/%d",n,cap)
        count.TextColor3=if full then C.green else C.sub
    end
    local join=find(row,"Join");local label=join and find(join,"Label")
    if label then
        label.Text=if queued then "IN QUEUE ×" elseif self:follower() then "LEADER" elseif full then "FULL" else "JOIN"
        label.TextColor3=if queued then C.ink elseif self:follower() or full then C.muted else C.ice
    end
    if join then
        -- build-out: joining the queue pops the key as its fill lands (.18 s); leaving fades it back out
        local wasQueued=join:GetAttribute("PFQueued")==true
        if Motion and queued~=wasQueued then
            Motion.tween(join,{BackgroundTransparency=if queued then 0 else 1},.18)
            if queued then Motion.pop(join,1.08,.18) end
        else join.BackgroundTransparency=if queued then 0 else 1 end
        join:SetAttribute("PFQueued",queued)
    end
    -- queued / full: the Sel overlay (the kit owns the body's stroke)
    local sel=find(row,"Sel")
    if sel then
        local tint=if queued then C.cobalt else C.green
        sel.Visible=queued or full;sel.BackgroundColor3=tint;sel.BackgroundTransparency=if queued then .82 else .94
        local rim=sel:FindFirstChild("Rim");if rim then rim.Color=tint end
    end
    local well=find(row,"Well");if well then self.preview:set(well,entry.config.gameMap) end
end
-- UI audit (PF - 3, 2026-10-28): the rows re-sorted under the pointer (aimed at Africa, the tap joined United States). While the
-- mouse is over the list the shown order holds (rooms still listed keep their row, gone ones drop out, new ones join the end)
-- and it re-sorts once the mouse leaves; a tap within TAP_GRACE of its row changing joins what the row showed before.
function Home:pointerOnList(): boolean
    local UserInputService=game:GetService("UserInputService")
    local t=UserInputService:GetLastInputType().Name
    if t~="MouseMovement" and t~="MouseButton1" and t~="MouseWheel" then return false end
    local layout=self:layout();local public=layout and find(layout,"Public")
    if not (public and public:IsA("GuiObject")) then return false end
    local gui=public:FindFirstAncestorWhichIsA("ScreenGui")
    local m=UserInputService:GetMouseLocation()-(if gui and gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset())
    local p,s=public.AbsolutePosition,public.AbsoluteSize
    return m.X>=p.X and m.X<=p.X+s.X and m.Y>=p.Y and m.Y<=p.Y+s.Y
end
function Home:holdOrder(list: {any}): {any}
    local shown=self.shownOrder
    if type(shown)=="table" and self:pointerOnList() then
        local byId,used,out={},{},{}
        for _,e in list do byId[e.id]=e end
        for _,id in shown do local e=byId[id];if e then table.insert(out,e);used[id]=true end end
        for _,e in list do if not used[e.id] then table.insert(out,e) end end
        list=out
    end
    local ids={};for i,e in list do ids[i]=e.id end
    self.shownOrder=ids
    return list
end
function Home:paintPublic()
    local layout=self:layout();local pool=self.pools[self.variant]
    if not layout or not pool then return end
    local list,now=self:holdOrder(self:entries()),self:now()
    local wells={}
    for i=1,math.max(TOP_ROWS,#pool.top) do
        local entry=list[i]
        local row=if entry then self:row("top",i) else pool.top[i]
        if row then if entry then self:paintRow(row,entry,now);local w=find(row,"Well");if w then table.insert(wells,w) end else row.Visible=false;row:SetAttribute("PFEntry",nil) end end
    end
    local more=math.min(MORE_MAX,math.max(0,#list-TOP_ROWS))
    for i=1,math.max(more,#pool.more) do
        local entry=if i<=more then list[TOP_ROWS+i] else nil
        local row=if entry then self:row("more",i) else pool.more[i]
        if row then if entry then self:paintRow(row,entry,now);local w=find(row,"Well");if w then table.insert(wells,w) end else row.Visible=false;row:SetAttribute("PFEntry",nil) end end
    end
    local public=find(layout,"Public")
    local empty=public and find(public,"Empty");if empty then empty.Visible=#list==0 end
    local moreHead=public and find(public,"MoreHead");if moreHead then moreHead.Visible=more>0 end
    -- build-out (R21: "which United States do I press?"): Quick join (author-pf3-build-home) takes the fullest room in one tap;
    -- it names that room and steps aside while you're queued or following a leader
    local quick=public and find(public,"PFQuickJoin")
    if quick then
        local best=list[1]
        quick.Visible=best~=nil and self:queuedId()==nil and not self:follower()
        local sub=quick:FindFirstChild("Sub",true)
        if sub and best then local n,cap=seats(best);sub.Text=string.format("%s · %d/%d",tostring(best.config.gameMap or "Public match"),n,cap) end
    end
    self.preview:update(wells,self.root,self.visible)
end
function Home:join(id: string)
    local entry
    for _,e in self:entries() do if e.id==id then entry=e end end
    if not entry then self:status("That match has started. Pick another.");return end
    if self:follower() then self:status("Your party leader picks the match.");return end
    local context=self.context
    local queued=self:queuedId()
    if queued then
        -- already queued: its row leaves the queue; another row switches to it (the join follows once the room is gone)
        self.switchTo=if queued~=id then {id=id,at=os.clock()} else nil
        if context.cancelPublic then pcall(context.cancelPublic) end
        return
    end
    local n,cap=seats(entry)
    if cap>0 and n>=cap then self:status("That match is full. Pick another.");return end
    self:status("Joining "..tostring(entry.config.gameMap).."…")
    local function send()
        if self.destroyed then return end
        self.lastJoinAt=os.clock()
        local ok,result=pcall(context.joinPublic,id)
        if not ok or type(result)=="table" and result.ok==false then
            self:status(if ok and type(result.message)=="string" then result.message else "Could not join. Try again.",true)
        end
    end
    local wait=JOIN_GAP-(os.clock()-self.lastJoinAt)
    if wait>0 then task.delay(wait,send) else send() end
end
function Home:status(text: string?,bad: boolean?)
    local layout=self:layout();local public=layout and find(layout,"Public");local label=public and find(public,"Status")
    if not label then return end
    label.Text=text or "";label.Visible=text~=nil and text~=""
    label.TextColor3=if bad then C.red else C.sub
    self.statusUntil=os.clock()+4
end

-- Party, Cobalt ----------------------------------------------------------------
function Home:paintParty()
    local layout=self:layout();local panel=layout and find(layout,"Party")
    if not panel then return end
    local party=self.model.party
    local members=if type(party)=="table" and type(party.members)=="table" then party.members else {}
    local me=Players.LocalPlayer
    if #members==0 and me then members={{userId=me.UserId,name=me.DisplayName}} end
    local seatsNode=find(panel,"Seats")
    for i=1,4 do
        local seat=seatsNode and seatsNode:FindFirstChild("Seat"..i);if not seat then continue end
        local member=members[i]
        local avatar,plus=seat:FindFirstChild("Avatar"),seat:FindFirstChild("Plus")
        local uid=member and integer(member.userId)
        -- build-out motion: a friend who just took the seat pops in (.6 -> 1, Back); empty seats' rims breathe while you're alone
        local had=seat:GetAttribute("PFSeatUser")
        if avatar then avatar.Visible=uid~=nil and uid>0;avatar.Image=if uid and uid>0 then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",uid) else "" end
        if Motion and avatar and uid and uid>0 and had~=uid and i>1 then Motion.pop(avatar,.6,.25) end
        seat:SetAttribute("PFSeatUser",uid)
        if plus then plus.Visible=member==nil end
        local rim=seat:FindFirstChild("Rim");if rim then rim.Color=if i==1 and member then C.cobalt else Color3.fromHex("#4a4a4a") end
        self.seatGlow=self.seatGlow or {}
        local glowing=self.seatGlow[seat]
        local want=Motion~=nil and rim~=nil and rim:IsA("UIStroke") and member==nil and #members==1
        if want and not glowing then self.seatGlow[seat]=Motion.glow(rim,{lo=.2,hi=.5,period=2.4})
        elseif not want and glowing then glowing();self.seatGlow[seat]=nil end
    end
    local line=find(panel,"Line")
    if line then line.Text=if #members>1 then string.format("%d in your party: you start allied and join matches together.",#members) else LINE_SOLO end
end
function Home:updateCommerce(state: any)
    if self.destroyed or type(state)~="table" then return end
    local profile=type(state.profile)=="table" and state.profile or {}
    self.balance=if profile.loaded and not profile.failed and finite(profile.balance) then profile.balance else nil
    self.ownedCosmetics=if profile.loaded and type(profile.owned)=="table" then profile.owned else nil
    self:paintCobalt()
end
-- the "you can buy" badge (Ashton 2026-10-28: "notif is lame should be top left and not a green dot"): how many Shop items you
-- don't own yet your Cobalt covers, on the red pill at the Shop card's top-left corner (PFBuyBadge, author-pf3-build-out);
-- bundles, pack-only and pass-only items don't count
function Home:buyCount(): number
    local balance,owned=self.balance,self.ownedCosmetics
    if not balance or not owned then return 0 end
    local ok,Catalog=pcall(function() return require(ReplicatedStorage.Shared.CosmeticCatalog) end)
    if not ok or type(Catalog)~="table" or type(Catalog.items)~="table" then return 0 end
    local n=0
    for _,item in Catalog.items do
        if type(item.price)=="number" and item.price>0 and item.price<=balance and not item.packOnly and not item.passOnly
            and item.category~="Bundle" and owned[item.id]~=true then n+=1 end
    end
    return n
end
-- shown, the count pops in (.6 -> 1, Back .25 s) when it first appears or changes, then pulses gently every 3 s; hidden at 0
function Home:paintBadge(badge: GuiObject,count: number)
    local label=badge:FindFirstChild("Count")
    local text=if count>9 then "9+" else tostring(count)
    local was=badge.Visible and badge:GetAttribute("PFBadgeCount")
    badge.Visible=count>0;badge:SetAttribute("PFBadgeCount",count)
    if label and label:IsA("TextLabel") then label.Text=text end
    if not Motion then return end
    self.badgePulse=self.badgePulse or {}
    if count>0 and was~=count then Motion.pop(badge,.6,.25) end
    if count>0 and not self.badgePulse[badge] then
        self.badgePulse[badge]=Motion.every(badge,3,function(node) Motion.tick(node,1.08,.35) end)
    elseif count==0 and self.badgePulse[badge] then self.badgePulse[badge]();self.badgePulse[badge]=nil end
end
function Home:paintCobalt()
    local count=self:buyCount()
    for _,layout in self.layouts do
        local amount=layout and find(layout,"Amount")
        -- build-out: a payout counts up (.6 s) instead of snapping
        if amount then
            if self.balance and Motion then Motion.count(amount,self.balance) else amount.Text=if self.balance then commas(self.balance) else "…" end
        end
        local badge=layout and find(layout,"PFBuyBadge")
        if badge then self:paintBadge(badge,count) end
    end
end
-- PF - 5: the Armory tile shows only while the menu provides context.openArmory (PF - 1's page): owned count + pips
local GOLD,PIP_OFF=Color3.fromHex("#f3c35a"),Color3.fromHex("#e7b54a")
local SHOWN,DIM=Color3.fromHex("#ffe9a6"),Color3.fromHex("#c9a556") -- the gilded tile's carousel
function Home:paintArmory()
    local has=type(self.context.openArmory)=="function"
    local total,own=#self.armoryItems,0
    for _,id in self.armoryItems do if self.owned[id] then own+=1 end end
    -- UX audit #5 (Ashton: "Ship it"): the cheapest Starter pack that still gives something new, until it's owned
    local starter=nil
    if self.ownedKnown then for _,pack in self.starterPacks or {} do
        local fresh=false;for _,id in pack.items or {} do if not self.owned[id] then fresh=true end end
        if fresh and type(pack.robux)=="number" and (starter==nil or pack.robux<starter.robux) then starter=pack end
    end end
    self.starterShown=if has then starter else nil -- STATS v3: counted as seen on each home show (setVisible)
    for _,layout in self.layouts do
        local group=layout and find(layout,"ArmoryGroup");if not group then continue end
        group.Visible=has
        local chip=group:FindFirstChild("PFStarterChip",true) -- author-pf1-starter-chip
        if chip then
            -- build-out (PF - 1's cross-review, R12): the Starter Pack showed twice on Home; the Jackpot box under Play carries it
            chip.Visible=false
            local word=chip:FindFirstChild("Label");if word and starter then word.Text="◆ STARTER · "..utf8.char(0xE002).." "..tostring(starter.robux) end
        end
        local label=find(group,"Owned");label=label and label:FindFirstChild("Label")
        if label then label.Text=string.format("%d/%d OWNED",own,total) end
        local pips=find(group,"Pips")
        -- PF - 3 gilded tile (tools/atlas/author-pf3-armory-gild.luau, 16 pips): a carousel, the shown item's pip long and lit,
        -- owned ones solid gold, the rest dim; without it (12 pips) the PF - 5 row: a pip per item, gold when owned
        local carousel=group:FindFirstChild("Armory") and group.Armory:GetAttribute("PF3ArmoryGild")~=nil
        if pips then for i=1,(if carousel then 16 else 12) do
            local pip=pips:FindFirstChild("Pip"..i);if not pip then continue end
            local id=self.armoryItems[i]
            pip.Visible=id~=nil
            if carousel then
                local shown=i==(self.heroIndex or 1)
                local goal={Size=UDim2.fromScale(if shown then 24/350 else 10/350,1),BackgroundColor3=if shown then SHOWN elseif id and self.owned[id] then GOLD else DIM,
                    BackgroundTransparency=if shown or (id and self.owned[id]) then 0 else .68}
                -- build-out: the long lit pip slides to the shown item (.2 s Quad Out; the pips' list eases with it)
                if Motion and type(Motion.tween)=="function" and self.visible then Motion.tween(pip,goal,.2) else for k,v in goal do (pip :: any)[k]=v end end
            else
                pip.Size=UDim2.fromScale(1/math.max(total,1)-.008,1)
                pip.BackgroundColor3=if id and self.owned[id] then GOLD else PIP_OFF
                pip.BackgroundTransparency=if id and self.owned[id] then 0 else .7
            end
        end end
    end
end
function Home:paintHelp()
    local has=self.context.hasHowToPlay and self.context.hasHowToPlay()==true
    for _,layout in self.layouts do
        if not layout then continue end
        for _,path in {{"TopLeft","Help"},{"Play","Help"}} do
            local parent=find(layout,path[1])
            if not parent and path[1]=="TopLeft" and layout.Name=="Desk" then parent=self.root:FindFirstChild("TopLeft") end -- r5
            local button=parent and parent:FindFirstChild(path[2])
            if button then button.Visible=has end
        end
    end
end

-- The model ----------------------------------------------------------------------
function Home:paint()
    if self.destroyed then return end
    self:paintModes();self:paintPublic();self:paintParty();self:paintCobalt();self:paintHelp();self:paintArmory()
end
function Home:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=table.clone(model)
    if finite(model.serverNow) then self.offset=model.serverNow-(if finite(model.receivedAt) then model.receivedAt else os.clock()) end
    if self.visible then self:paintPublic();self:paintParty() end
    local switch=self.switchTo
    if switch and not model.room and not model.joining and not model.pending then
        self.switchTo=nil
        if os.clock()-switch.at<6 then self:join(switch.id) end
    end
end
function Home:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible=visible;self.root.Visible=visible
    if visible then
        if self.context.soloDifficulty then local m=self.context.soloDifficulty();if table.find(MODES,m) then self.mode=m end end
        self:pickLayout();self:paint()
        -- build-out (home.page): the menu lands instead of cutting: the dim fades in .2 s and the Desk groups rise 1% of the
        -- screen into place left to right, 40 ms apart (.22 s Quart Out). A rise, not a scale: the groups are corner-anchored
        -- (R4), and Frames can't fade without a CanvasGroup. The authored spot is kept on the group (PFRestPos) and restored.
        local layout=self:layout()
        if Motion and layout and not Motion.reduced(layout) then
            local dim=self.root:FindFirstChild("Dim")
            if dim and dim:IsA("GuiObject") then
                local base=dim:GetAttribute("PFRestTransparency")
                if type(base)~="number" then base=dim.BackgroundTransparency;dim:SetAttribute("PFRestTransparency",base) end
                dim.BackgroundTransparency=1;Motion.tween(dim,{BackgroundTransparency=base},.2)
            end
            for i,n in {"LeftGroup","ArmoryGroup","CentreGroup","RightGroup"} do
                local g=layout:FindFirstChild(n)
                if not g or not g:IsA("GuiObject") or not g.Visible then continue end
                local rest=g:GetAttribute("PFRestPos")
                if typeof(rest)~="UDim2" then rest=g.Position;g:SetAttribute("PFRestPos",rest) end
                local home: UDim2=rest :: any
                g.Position=home+UDim2.fromScale(0,.01)
                task.delay((i-1)*.04,function()
                    if self.visible and g.Parent then Motion.tween(g,{Position=home},.22,Enum.EasingStyle.Quart,Enum.EasingDirection.Out) else g.Position=home end
                end)
            end
        end
        local starter=self.starterShown;if starter then pcall(function() require(script.Parent.StatsReport).seen(tostring(starter.id),"home") end) end -- STATS v3
        if not self.ticker then
            local last=0
            self.ticker=RunService.Heartbeat:Connect(function(dt: number)
                self:stepHero(dt) -- PF - 5: the Armory tile's flipbook
                local t=os.clock();if t-last<.5 then return end;last=t
                self:paintPublic()
                if self.statusUntil>0 and t>self.statusUntil then self.statusUntil=0;self:status(nil) end
            end)
        end
    else
        if self.ticker then self.ticker:Disconnect();self.ticker=nil end
        self.preview:update({},self.root,false)
    end
end
function Home:handleEscape(): boolean return false end
function Home:focusActive()
    local layout=self:layout();local key=layout and find(layout,"Key")
    if key and key:IsA("GuiButton") then GuiService.SelectedObject=key end
end
function Home:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.ticker then self.ticker:Disconnect() end
    for _,c in self.connections do c:Disconnect() end
    local kit=self.context.cardKit
    if kit then for _,layout in self.layouts do if layout then
        for _,node in layout:GetDescendants() do if node:GetAttribute("PFCard")==true then pcall(kit.unbind,kit,node) end end
    end end end
    self.preview:dispose()
end
return Home
