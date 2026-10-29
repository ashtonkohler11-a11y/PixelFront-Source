--!strict
-- PIVOT Armory v2 (PF - 1; Ashton approved the board 2026-10-25): fills AtlasMenu.PFArmory (tools/atlas/author-pivot-armory.luau).
-- One item on the stage at a time (its baked flipbook, ArmoryShowcase), the spec sheet, then the unlock: the Cobalt grind bar +
-- the Cobalt / R$ keys (+ its set's starter pack when it's in one), or Owned + Play. The rail picks the item; ‹ › step through.
-- Data (PF - 2's contract): Shared.ArsenalCatalog (items, packs, prices, productIds; 0 = no product yet: the key stays, its tap is a
-- no-op) and the CosmeticsState packet (balance, arsenal.owned). Cobalt unlock: CosmeticsCommand {kind="UnlockArsenal", itemId,
-- requestId}. The unlock / purchase stings play from Sfx (it watches ownership and Robux receipts), so this page only pops.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Market=game:GetService("MarketplaceService")
local Gui=game:GetService("GuiService")
local Run=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local Showcase=require(script.Parent.ArmoryShowcase)
-- UI lock-in BUILD-OUT (PF - 4, 2026-10-28): every motion here goes through the shared kit (UiMotion; JackpotMotion runs the
-- Starter / 2× boxes' coin tick + key sheen)
local okMotion,UiMotion=pcall(require,script.Parent.UiMotion)
local Motion: any=if okMotion and type(UiMotion)=="table" and type((UiMotion :: any).tween)=="function" then UiMotion else nil -- (CLI loaders stub unknown modules)
local Page={}
Page.__index=Page
local ROBUX=utf8.char(0xE002)
local NB=utf8.char(0xA0) -- no-break: "R$ 649" never wraps under its glyph
local hex=Color3.fromHex
local CO={ready={bg=hex("#2f63e8"),text=Color3.new(1,1,1)},idle={bg=hex("#141b2c"),text=hex("#8fa6d6")}}
local CARD={bg=hex("#151922"),rim=hex("#242a36"),own=hex("#13241b"),ownRim=hex("#2b6a48"),sel=hex("#2a2414"),selRim=hex("#f1c75a"),well=hex("#1c222e"),ownWell=hex("#1f4030"),selWell=hex("#4a3a1a")}
local function short(n: number): string
    if n>=1e6 then return (string.format("%.1f",n/1e6):gsub("%.0$","")).."M" end
    if n>=1e3 then return (string.format("%.1f",n/1e3):gsub("%.0$","")).."K" end
    return tostring(n)
end
local function comma(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (out:gsub("^,",""))
end
local function need(name: string): any
    local shared=RS:FindFirstChild("Shared");local m=shared and shared:FindFirstChild(name)
    if not m then return nil end
    local ok,c=pcall(require,m);return if ok then c else nil
end

function Page.new(menu: Instance,context: any): any
    local root=menu:FindFirstChild("PFArmory") :: any
    assert(root,"author-pivot-armory not installed")
    local cat=need("ArsenalCatalog");local config=need("Config")
    local self=setmetatable({root=root,context=context,cat=cat,match=config and config.Arsenal and config.Arsenal.Match,visible=false,index=1,balance=nil,
        owned={},pending=nil,note=nil,connections={},destroyed=false,frame=0,clock=0,openedAt=-math.huge},Page)
    local function listen(signal: any,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    -- the tap that opened the page never lands on it (on an A06 the home's Armory key sits under the wallet's +)
    -- UI audit R8 (PF - 3's HitZone pattern, author-pf4-hit-zones): a key's invisible finger-zone strips fire it too
    local okZone,HitZone=pcall(function() return require(script.Parent.HitZone) end)
    local zoned=okZone and type(HitZone)=="table" and type((HitZone :: any).signal)=="function"
    local function bind(button: any,fn: ()->())
        if not button then return end
        local function go() if os.clock()-self.openedAt>=.35 then fn() end end
        listen(if zoned then (HitZone :: any).signal(button) else button.Activated,go)
        local hit=button:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then listen(hit.Activated,go) end
    end
    local okLine,Line=pcall(require,script.Parent:FindFirstChild("TopbarLine") :: any)
    if okLine and Line and Line.keepRight then Line.keepRight(root.Top.Left,self.connections) end
    local stage,info=root.Stage,root.Stage.Info
    bind(root.Top.Left.Back,function() if context.back then context.back() end end)
    -- the Cobalt wallet sits beside the ARMORY pill (author-pf1-armory-wallet; Ashton: "top left next to armory text"), else top right
    self.wallet=root.Top.Left:FindFirstChild("Wallet") or root.Top.Wallet
    bind(self.wallet.Plus,function() if context.openCobalt then context.openCobalt() end end)
    bind(stage.Nav.Prev,function() self:step(-1) end)
    bind(stage.Nav.Next,function() self:step(1) end)
    -- Ashton 2026-10-28 (the "‹ 1 / 13 ›" was too small): big ‹ › on the hero's sides (author-pf1-armory-cycler) grow from their
    -- centre on hover; ← → and the pad's L1 / R1 step too while the page shows
    -- BUILD-OUT: hover 1.08, press .92 then a Back release (UiMotion.press on their PFHover); the chevron nudges 3 px its way
    self.handles={}
    if Motion then
        for _,key in {stage.Nav.Prev,stage.Nav.Next} do table.insert(self.handles,Motion.press(key,{hover=1.08,press=.92})) end
        table.insert(self.handles,Motion.press(self.wallet.Plus,{hover=1.08}))
    end
    -- the rail cards: hover 1.02, the selected one holds 1.03 (BUILD-OUT; centred: author-pf4-armory-motion)
    self.cardHandles={}
    listen(game:GetService("UserInputService").InputBegan,function(input: InputObject)
        if not self.visible or game:GetService("UserInputService"):GetFocusedTextBox() then return end
        local k=input.KeyCode
        if k==Enum.KeyCode.Left or k==Enum.KeyCode.ButtonL1 then self:step(-1) elseif k==Enum.KeyCode.Right or k==Enum.KeyCode.ButtonR1 then self:step(1) end
    end)
    for _,name in {"Unlock","UnlockStarter"} do
        local m=info[name]
        bind(m.Cobalt,function() self:unlock() end)
        bind(m.Robux,function() local item=self:item();if item then self:prompt(item.productId) end end)
        if m:FindFirstChild("Starter") then bind(m.Starter.Buy,function() local pack=self:pack();if pack then self:prompt(pack.productId) end end) end
    end
    bind(info.Owned.Play,function() if context.play then context.play() end end)
    bind(stage.X2.Buy,function()
        local cosmetics=need("CosmeticCatalog");local pass=cosmetics and cosmetics.passById and cosmetics.passById.pass_2x_cobalt
        local me=Players.LocalPlayer
        if self.x2Owned then return end -- owned: the strip reads Active (paint)
        if pass and type(pass.passId)=="number" and pass.passId>0 and me then
            pcall(function() require(script.Parent.StatsReport).prompt("double2x","armory") end) -- STATS v3
            pcall(function() Market:PromptGamePassPurchase(me,pass.passId) end)
        end
    end)
    -- the rail: a card picks its item; a set's Starter key prompts its pack
    for i,item in (cat and cat.items) or {} do
        local card=root.Rail:FindFirstChild(item.id,true)
        if card then
            bind(card,function() self:select(i) end)
            if Motion then self.cardHandles[card]=Motion.press(card,{hover=1.02,press=.97,rest=function() return if self.index==i then 1.03 else 1 end}) end
        end
    end
    -- UI audit (R8, A06): a line authored PFFloorHide (author-pf4-buildout: the Jackpot boxes' second line, tags and coin words,
    -- the unlock keys' sub-lines) steps aside when it can't fit at its 11 px floor; a tag / coin goes with its words
    for _,label in root:GetDescendants() do
        if not (label:IsA("TextLabel") and label:GetAttribute("PFFloorHide")) then continue end
        local frame=label.Parent
        local whole=frame and (frame.Name=="PFJPTag" or frame.Name=="PFJPForever" or frame.Name=="PFJPCoin") and frame or nil
        local base=label:GetAttribute("PFFloorBase");if typeof(base)~="number" then base=label.TextTransparency;label:SetAttribute("PFFloorBase",base) end
        local function fit()
            if whole then (whole :: any).Visible=label.TextFits;label.TextTransparency=base :: number
            else label.TextTransparency=if label.TextFits then base :: number else 1 end
        end
        listen(label:GetPropertyChangedSignal("TextFits"),fit);fit()
    end
    -- one name size for every rail tile (UI audit R7: "Barracks" rendered smaller than "Training Camp"): the smallest fit
    listen(root.Rail:GetPropertyChangedSignal("AbsoluteSize"),function() self:fitNames() end)
    task.defer(function() self:fitNames() end)
    pcall(function() require(script.Parent.JackpotMotion).start() end)
    for _,pack in (cat and cat.packs) or {} do
        for _,set in {"Warfare","Industry"} do
            local grp=if self:packIn(pack,set) then root.Rail:FindFirstChild(set) else nil;local key=grp and grp.Head:FindFirstChild("Starter")
            if key then bind(key,function() self:prompt(pack.productId) end) end
        end
    end
    if context.remotes then listen(context.remotes.CosmeticsState.OnClientEvent,function(packet: any) self:receive(packet) end) end
    -- the flipbook: 16 frames over 2.4 s, only while the page shows
    listen(Run.Heartbeat,function(dt: number)
        if not self.visible then return end
        self.clock+=dt
        local f=math.floor(self.clock*Showcase.FPS)%Showcase.FRAMES
        if f~=self.frame then self.frame=f;self:paintFrame() end
    end)
    self:paint()
    return self
end

function Page:item(): any return self.cat and self.cat.items[self.index] end
-- a rail shelf shows a pack's Starter key when the pack is that shelf's, or holds one of its items (the one Starter Pack, set
-- "Starter", spans both: Artillery on Warfare, Bank on Industry)
function Page:packIn(pack: any,set: string): boolean
    if pack.set==set then return true end
    for _,id in pack.items or {} do local it=self.cat and self.cat.byId and self.cat.byId[id];if it and it.set==set then return true end end
    return false
end
-- the set's starter pack when the item is in it and the pack still gives something new
function Page:pack(): any?
    local item=self:item();if not item or not self.cat then return nil end
    for _,pack in self.cat.packs or {} do
        if table.find(pack.items,item.id) then
            for _,id in pack.items do if not self.owned[id] then return pack end end
        end
    end
    return nil
end
function Page:setVisible(on: boolean,itemId: string?)
    if self.destroyed then return end
    if itemId and self.cat then for i,item in self.cat.items do if item.id==itemId then self.index=i end end end
    local opening=on and not self.visible
    if on and not self.visible then self.clock=0;self.frame=0;self.openedAt=os.clock();self:preload()
        -- STATS v3: each Armory item on the rail is a product seen here
        pcall(function() local SR=require(script.Parent.StatsReport);for _,item in (self.cat and self.cat.items or {}) do SR.seen(tostring(item.id),"armory") end end) end
    self.visible=on;self.root.Visible=on
    if on then
        -- BUILD-OUT: the grind bar fills from empty on open (.4 s)
        if opening then self.fillFrom=0 end
        self:paint()
    end
end
-- one TextSize for every rail tile name: each label's own fit (its width against the text's width at 100, its height), the
-- smallest wins, written as the shared UITextSizeConstraint cap (content: the words decide it, not the device)
function Page:fitNames()
    if self.destroyed or not self.cat then return end
    local labels={}
    for _,item in self.cat.items do
        local card=self.root.Rail:FindFirstChild(item.id,true);local l=card and card:FindFirstChild("Label")
        if l and l:IsA("TextLabel") and l.Visible and l.AbsoluteSize.X>0 then table.insert(labels,l) end
    end
    if #labels==0 then return end
    task.spawn(function()
        local TS=game:GetService("TextService");local fit=math.huge
        for _,l in labels do
            local ok,bounds=pcall(function()
                local p=Instance.new("GetTextBoundsParams");p.Text=l.ContentText;p.Font=l.FontFace;p.Size=100;p.Width=1e5
                return TS:GetTextBoundsAsync(p)
            end)
            if ok and bounds.X>0 then fit=math.min(fit,math.floor(100*l.AbsoluteSize.X/bounds.X),math.floor(l.AbsoluteSize.Y*.9)) end
        end
        if fit==math.huge or self.destroyed then return end
        for _,l in labels do
            local cap=l:FindFirstChildOfClass("UITextSizeConstraint")
            if cap then cap.MaxTextSize=math.max(cap.MinTextSize,fit) end
        end
    end)
end
-- every sheet streams in once, on the first visit (a sheet first shown on a switch takes a few seconds)
function Page:preload()
    if self.preloaded then return end;self.preloaded=true
    local labels={}
    for _,show in Showcase.items do local l=Instance.new("ImageLabel");l.Image=show.sheet;table.insert(labels,l) end
    task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync(labels) end) end)
end
function Page:select(i: number,dir: number?)
    if not self.cat or i==self.index then return end
    local was=self.index
    self.index=i;self.note=nil;self.clock=0;self.frame=0;self.fillFrom=0
    -- BUILD-OUT: the hero slides: the old one 24 px toward the arrow + fades (.12 s), the new one in from the other side (.18 s)
    local d=dir or (if i>was then 1 else -1)
    if not (Motion and self.visible and not Motion.reduced(self.root)) then self:paint();self:refreshRail();return end
    self.switch=(self.switch or 0)+1;local mine=self.switch
    local art=self:art();local hero,glow=art.Hero,art.Glow
    local base=hero:GetAttribute("PFBase");if typeof(base)~="UDim2" then base=hero.Position;hero:SetAttribute("PFBase",base) end
    local gbase=glow:GetAttribute("PFBase");if typeof(gbase)~="UDim2" then gbase=glow.Position;glow:SetAttribute("PFBase",gbase) end
    local B,G=base :: UDim2,gbase :: UDim2
    local ht=hero:GetAttribute("PFBaseT");if type(ht)~="number" then ht=hero.ImageTransparency;hero:SetAttribute("PFBaseT",ht) end
    local gt=glow:GetAttribute("PFBaseT");if type(gt)~="number" then gt=glow.ImageTransparency;glow:SetAttribute("PFBaseT",gt) end
    self:refreshRail()
    Motion.tween(hero,{Position=B-UDim2.fromOffset(24*d,0),ImageTransparency=1},.12,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
    Motion.tween(glow,{Position=G-UDim2.fromOffset(24*d,0),ImageTransparency=1},.12,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
    task.delay(.12,function()
        if self.destroyed or self.switch~=mine then return end
        self:paint()
        hero.Position=B+UDim2.fromOffset(24*d,0);glow.Position=G+UDim2.fromOffset(24*d,0)
        Motion.tween(hero,{Position=B,ImageTransparency=ht},.18,Enum.EasingStyle.Quart)
        Motion.tween(glow,{Position=G,ImageTransparency=gt},.18,Enum.EasingStyle.Quart)
    end)
end
-- Ashton 2026-10-28 ("left right cycle ... just jumps around"): ‹ › step to the rail card beside the shown one ON SCREEN
-- (the rail groups Warfare then Industry in its own order, not the catalog's), wrapping at the ends
function Page:railOrder(): {number}
    local order={}
    for i,item in self.cat.items do table.insert(order,{i=i,card=self.root.Rail:FindFirstChild(item.id,true)}) end
    table.sort(order,function(a,b)
        local ax=if a.card then a.card.AbsolutePosition.X else math.huge;local bx=if b.card then b.card.AbsolutePosition.X else math.huge
        if ax~=bx then return ax<bx end;return a.i<b.i
    end)
    local out={};for _,o in order do table.insert(out,o.i) end;return out
end
function Page:step(d: number)
    if not self.cat then return end
    local order=self:railOrder();local at=table.find(order,self.index) or 1
    self:select(order[(at-1+(if d<0 then -1 else 1))%#order+1],d)
    -- the chevron nudges 3 px its way and back (.14 s)
    local key=if d<0 then self.root.Stage.Nav.Prev else self.root.Stage.Nav.Next
    local glyph=key:FindFirstChild("Glyph")
    if Motion and glyph and glyph:IsA("GuiObject") and not Motion.reduced(key) then
        local b=glyph:GetAttribute("PFBase");if typeof(b)~="UDim2" then b=glyph.Position;glyph:SetAttribute("PFBase",b) end
        local gb=b :: UDim2
        glyph.Position=gb+UDim2.fromOffset(3*d,0);Motion.tween(glyph,{Position=gb},.14,Enum.EasingStyle.Back)
    end
end
-- the rail's selected look follows the index at once (the stage may still be sliding)
function Page:refreshRail()
    for _,h in self.cardHandles or {} do h.refresh() end
end
function Page:receive(packet: any)
    if type(packet)~="table" or packet.kind~="Cosmetics" then return end
    if type(packet.balance)=="number" then self.balance=packet.balance end
    -- RELEASE: the 2x Cobalt pass is bought once; owned (the profile's pass flag), its strip reads Active and its key hides
    if type(packet.owned)=="table" then self.x2Owned=packet.owned.pass_2x_cobalt==true end
    if type(packet.arsenal)=="table" and type(packet.arsenal.owned)=="table" then
        local before=self.owned;self.owned=packet.arsenal.owned
        for id,yes in self.owned do if yes and not before[id] and next(before)~=nil then self:pop(id) end end
    end
    local p=self.pending
    if p and packet.requestId==p.requestId then
        self.pending=nil
        if not self.owned[p.id] and type(packet.message)=="string" then self:say(packet.message) end
    end
    self:paint()
end
function Page:unlock()
    local item=self:item()
    if not item or self.pending or self.owned[item.id] or not self.context.remotes then return end
    local have=self.balance or 0
    if have<item.cobalt then
        self:say("Need "..short(item.cobalt-have))
        -- BUILD-OUT: one 3 px shake with the word (.25 s)
        if Motion then local info=self.root.Stage.Info;Motion.shake(info.Unlock.Cobalt);Motion.shake(info.UnlockStarter.Cobalt) end
        return
    end
    self.request=(self.request or 0)+1
    self.pending={id=item.id,requestId="armory-"..item.id.."-"..self.request}
    self.context.remotes.CosmeticsCommand:FireServer({kind="UnlockArsenal",itemId=item.id,requestId=self.pending.requestId})
    self:paint()
end
-- UI audit (PF - 3, 2026-10-28): the R$ keys show Roblox's own price, as the Shop does; the catalog's robux only stands in until
-- GetProductInfo answers (the Bank key read 49 while Roblox charged 80; the X2 key 199 against 160)
function Page:robux(id: any,kind: Enum.InfoType,fallback: number?): number?
    if type(id)~="number" or id<=0 then return fallback end
    self.live=self.live or {}
    local key=kind.Name..":"..id;local known=self.live[key]
    if known==nil then
        self.live[key]=false
        task.spawn(function()
            local ok,info=pcall(function() return Market:GetProductInfo(id,kind) end)
            if ok and type(info)=="table" and type(info.PriceInRobux)=="number" then self.live[key]=info.PriceInRobux;self:paint() end
        end)
    end
    return if type(known)=="number" then known else fallback
end
function Page:prompt(productId: any)
    if type(productId)~="number" or productId<=0 then return end -- Ashton makes the products later
    local me=Players.LocalPlayer
    if me then
        pcall(function() require(script.Parent.StatsReport).promptFor("Product",productId,"armory") end) -- STATS v3
        pcall(function() Market:PromptProductPurchase(me,productId) end)
    end
end
-- a short word on the Cobalt key ("Need 7.5K", the server's reason), then the price again
function Page:say(words: string)
    local at=os.clock();self.note={words=words,at=at};self:paint()
    task.delay(2,function() if not self.destroyed and self.note and self.note.at==at then self.note=nil;self:paint() end end)
end
-- newly owned: its rail card pops; on the stage, the Owned card scales in with the Shop buy's four-star twinkle
-- (BUILD-OUT: UiMotion.pop on the authored PFMotionScale, author-pf4-armory-motion; no runtime UIScale here any more)
function Page:pop(id: string)
    if not Motion then return end
    local card=self.root.Rail:FindFirstChild(id,true)
    local owned=if self:item() and self:item().id==id then self.root.Stage.Info.Owned else nil
    for _,node in {card,owned} do if node then Motion.pop(node,1.08,.4) end end
    if owned then task.defer(function() if owned.Visible then Motion.sparkle(owned,Color3.fromHex("#b8ffd2")) end end) end
    if card then task.delay(.4,function() local h=self.cardHandles and self.cardHandles[card];if h then h.refresh() end end) end
end

-- the hero art: the full-bleed box (author-pf1-armory-bleed) or, before it, the stage
function Page:art(): any
    local bleed=self.root:FindFirstChild("PFBleedArt")
    return bleed and bleed:FindFirstChild("Box",true) or self.root.Stage
end
function Page:paintFrame()
    local art=self:art()
    local base,glow=Showcase.frame(self.frame)
    art.Hero.ImageRectOffset=base;art.Glow.ImageRectOffset=glow;art.Glow.ImageRectSize=Showcase.GLOW_SIZE
end
function Page:paint()
    if self.destroyed or not self.cat then return end
    local item=self:item();if not item then return end
    local show=Showcase.items[item.id] or Showcase.items.tesla_coil
    local root,stage=self.root,self.root.Stage;local info=stage.Info
    local x2=stage:FindFirstChild("X2")
    if x2 then
        local buy=x2:FindFirstChild("Buy");if buy then buy.Visible=not self.x2Owned end
        local cosmetics=need("CosmeticCatalog");local pass=cosmetics and cosmetics.passById and cosmetics.passById.pass_2x_cobalt
        local price=pass and self:robux(pass.passId,Enum.InfoType.GamePass,nil)
        local main=buy and buy:FindFirstChild("Main")
        if price and main and main:IsA("TextLabel") then main.Text=ROBUX..NB..tostring(price) end
        local sub=x2:FindFirstChild("Sub");if sub and sub:IsA("TextLabel") then sub.Text=if self.x2Owned then "✓ Active · every match pays ×2" else "Every match pays ×2" end
    end
    local have=self.balance
    -- BUILD-OUT: the wallet counts up / down to a new balance (.6 s; the first paint lands at once)
    if have and Motion then Motion.count(self.wallet.Amount,have,{format=comma}) else self.wallet.Amount.Text=if have then comma(have) else "…" end
    -- the stage
    local art=self:art()
    art.Hero.Image=show.sheet;art.Glow.Image=show.sheet;self:paintFrame()
    -- UI audit (R5): the art's callout chip repeated the first stat (Drain −1.5% ...): the stats say it once
    art.Chip.Visible=false
    stage.Nav.Count.Text=tostring(self.index).." / "..tostring(#self.cat.items)
    info.Kicker.Text=string.format('<font color="%s">%s</font>  ·  %s',show.accent,string.upper(item.set),string.upper(show.role))
    info.Prestige.Visible=item.prestige==true
    info.ItemName.Text=item.name;info.Line.Text=show.line
    for i=1,3 do
        local row=info.Spec["Row"..i];local s=show.stats[i]
        row.Key.Text=string.upper(s[1]);row.Value.Text=s[2];row.Unit.Text=s[3]
        row.Value.TextColor3=if i==1 then hex(show.accent) else Color3.new(1,1,1)
    end
    local costs=self.match and self.match[item.id] and self.match[item.id].Costs or {}
    local steps={}
    for i,c in costs do if i<=4 then table.insert(steps,short(c)) end end
    info.Spec.Ladder.Value.Text=table.concat(steps,' <font color="#5d6676">›</font> ')
    info.Spec.Ladder.Unit.Text=show.per
    -- the unlock / owned card
    -- Ashton 2026-10-28 ("remove the starter pack text at bottom nobody is gonna read that"): the plain face for every item; the
    -- Starter Pack is its own Jackpot card on the stage (PFStarterJackpot, StarterOffer)
    local own=self.owned[item.id]==true;local pack: any=nil
    info.Owned.Visible=own;info.Unlock.Visible=not own and pack==nil;info.UnlockStarter.Visible=not own and pack~=nil
    if not own then
        local m=if pack then info.UnlockStarter else info.Unlock
        local got=math.min(have or 0,item.cobalt);local frac=if item.cobalt>0 then got/item.cobalt else 0
        -- UI audit (R5): "0%", "0 / 20,000" and "20,000 to go" said one thing three ways: the bar + "20,000 to go" stay
        m.Pct.Visible=false;m.Have.Visible=false;local gem=m:FindFirstChild("Gem");if gem then gem.Visible=false end
        -- BUILD-OUT: the fill eases to its share (.4 s Quad Out): from empty on open / a new item, else from where it was
        local share=math.max(frac,.02)
        if Motion then
            if self.fillFrom then m.Bar.Fill.Size=UDim2.fromScale(math.max(self.fillFrom,.02),1);self.fillFrom=nil end
            Motion.fill(m.Bar.Fill,share)
        else m.Bar.Fill.Size=UDim2.fromScale(share,1) end
        local ready=have~=nil and have>=item.cobalt
        m.ToGo.Text=if ready then '<font color="#9cc8ff">Ready to unlock</font>' else comma(item.cobalt-(have or 0)).." to go"
        -- a full bar glints once (its Shine lifts and settles), each time this item turns ready
        local shine=m.Bar.Fill:FindFirstChild("Shine")
        local readyKey=if ready then item.id else nil
        if Motion and shine and readyKey and self.glinted~=readyKey then
            self.glinted=readyKey;shine.BackgroundTransparency=.3;Motion.tween(shine,{BackgroundTransparency=.78},.6)
        elseif not readyKey and self.glinted==item.id then self.glinted=nil end
        local look=if ready then CO.ready else CO.idle
        local key=m.Cobalt;key.BackgroundColor3=look.bg;key.Main.TextColor3=look.text;key.Sub.TextColor3=look.text
        -- an affordable Cobalt key: one slow light sweep every 5 s (its authored PFSheen band; author-pf4-armory-motion)
        local band=key:FindFirstChild("PFSheen");local g=band and band:FindFirstChildOfClass("UIGradient")
        self.sheens=self.sheens or {}
        if Motion and g and ready and not self.sheens[key] then self.sheens[key]=Motion.sheen(g,{period=5,sweep=.8})
        elseif self.sheens[key] and not ready then self.sheens[key]();self.sheens[key]=nil end
        key.Main.Text=if self.pending and self.pending.id==item.id then "…" elseif self.note then self.note.words else comma(item.cobalt).." Cobalt"
        -- "Need 7.5K" reads "Need ◆7.5K more" (MM 2026-10-25: the Cobalt gem wherever "Need N" shows): PFNeed's row over Main
        local need=key:FindFirstChild("PFNeed")
        local lack=self.note and not self.pending and string.match(self.note.words,"^Need (.+)$")
        if need then
            need.Visible=lack~=nil and lack~=false
            if lack then need.Amount.Text=lack end
            for _,label in {need.Lead,need.Amount,need.Tail} do label.TextColor3=look.text end
        end
        key.Main.Visible=not (need and lack)
        key.Sub.Text=if ready then "Unlock with Cobalt" else "Earn it by playing"
        m.Robux.Main.Text=ROBUX..NB..tostring(self:robux(item.productId,Enum.InfoType.Product,item.robux))
        if pack then
            local names={}
            for _,id in pack.items do local it=self.cat.byId[id];if it then table.insert(names,it.name) end end
            -- every screen shows the same words (pure scale: nothing dropped on phones; UI-REVIEW rule 5a)
            m.Starter.Text.Text=string.format('Also in the <font color="#ffd36a">%s</font>: %s',pack.name,table.concat(names," + "))
            m.Starter.Buy.Main.Text=ROBUX..NB..tostring(self:robux(pack.productId,Enum.InfoType.Product,pack.robux))
        end
    else
        info.Owned.Play.Main.Text=if self.context.inMatch and self.context.inMatch() then "Back" else "Play"
    end
    -- the rail
    local count={}
    for i,it in self.cat.items do
        local card=root.Rail:FindFirstChild(it.id,true);if not card then continue end
        local o=self.owned[it.id]==true;local sel=i==self.index
        count[it.set]=(count[it.set] or 0)+(if o then 1 else 0)
        -- BUILD-OUT: the selected look fades in (.12 s) instead of snapping; the card holds 1.03 (its press handle's rest)
        local function look(node: Instance,props: {[string]: any}) if Motion then Motion.tween(node,props,.12) else for k,v in props do (node :: any)[k]=v end end end
        look(card,{BackgroundColor3=if sel then CARD.sel elseif o then CARD.own else CARD.bg})
        local tone=card:FindFirstChild("Tone");if tone then tone.Enabled=not sel and not o end
        look(card.Rim,{Color=if sel then CARD.selRim elseif o then CARD.ownRim else CARD.rim,Thickness=if sel then 2 else 1})
        look(card.Well,{BackgroundColor3=if sel then CARD.selWell elseif o then CARD.ownWell else CARD.well})
        card.Well.Icon.ImageColor3=if o or sel then Color3.new(1,1,1) else Color3.fromRGB(150,150,160)
        card.Label.TextColor3=if sel then hex("#ffe6a8") elseif o then hex("#d6dce6") else hex("#9aa2b0")
        card.Gem.Visible=not o;card.Price.Visible=not o;card.Own.Visible=o;card.Price.Text=short(it.cobalt)
        -- UI audit (R21): the grey padlock disc read as a meaningless "−" (the price already says locked): only the green ✓ shows,
        -- on owned items; the unexplained ◆ prestige corner goes
        local b=card.Badge;b.Visible=o;b.BackgroundColor3=hex("#3ed47e")
        b.Ok.Visible=o;b.Shackle.Visible=false;b.Body.Visible=false
        local prestige=card:FindFirstChild("Prestige");if prestige then prestige.Visible=false end
    end
    for _,set in {"Warfare","Industry"} do
        local grp=root.Rail:FindFirstChild(set);if not grp then continue end
        local total=0;for _,it in self.cat.items do if it.set==set then total+=1 end end
        grp.Head.Title.Text=string.format('%s  <font color="#6f7888">%d / %d</font>',string.upper(set),count[set] or 0,total)
        local starter=grp.Head:FindFirstChild("Starter");if starter then starter.Visible=false end -- Ashton 2026-10-28: the head's Starter text goes
    end
end

function Page:focusActive() if self.visible then Gui.SelectedObject=self.root.Top.Left.Back end end
function Page:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    for _,h in self.handles or {} do h.Disconnect() end
    for _,h in self.cardHandles or {} do h.Disconnect() end
    for _,stop in self.sheens or {} do stop() end
end
return Page
