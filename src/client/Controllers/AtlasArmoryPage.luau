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
    local function bind(button: any,fn: ()->())
        if not button then return end
        local function go() if os.clock()-self.openedAt>=.35 then fn() end end
        listen(button.Activated,go)
        local hit=button:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then listen(hit.Activated,go) end
    end
    local okLine,Line=pcall(require,script.Parent:FindFirstChild("TopbarLine") :: any)
    if okLine and Line and Line.keepRight then Line.keepRight(root.Top.Left,self.connections) end
    local stage,info=root.Stage,root.Stage.Info
    bind(root.Top.Left.Back,function() if context.back then context.back() end end)
    bind(root.Top.Wallet.Plus,function() if context.openCobalt then context.openCobalt() end end)
    bind(stage.Nav.Prev,function() self:step(-1) end)
    bind(stage.Nav.Next,function() self:step(1) end)
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
        if pass and type(pass.passId)=="number" and pass.passId>0 and me then pcall(function() Market:PromptGamePassPurchase(me,pass.passId) end) end
    end)
    -- the rail: a card picks its item; a set's Starter key prompts its pack
    for i,item in (cat and cat.items) or {} do
        local card=root.Rail:FindFirstChild(item.id,true)
        if card then bind(card,function() self:select(i) end) end
    end
    for _,pack in (cat and cat.packs) or {} do
        local grp=root.Rail:FindFirstChild(pack.set);local key=grp and grp.Head:FindFirstChild("Starter")
        if key then bind(key,function() self:prompt(pack.productId) end) end
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
    if on and not self.visible then self.clock=0;self.frame=0;self.openedAt=os.clock();self:preload() end
    self.visible=on;self.root.Visible=on
    if on then self:paint() end
end
-- every sheet streams in once, on the first visit (a sheet first shown on a switch takes a few seconds)
function Page:preload()
    if self.preloaded then return end;self.preloaded=true
    local labels={}
    for _,show in Showcase.items do local l=Instance.new("ImageLabel");l.Image=show.sheet;table.insert(labels,l) end
    task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync(labels) end) end)
end
function Page:select(i: number)
    if not self.cat or i==self.index then return end
    self.index=i;self.note=nil;self.clock=0;self.frame=0;self:paint()
end
function Page:step(d: number)
    if not self.cat then return end
    local n=#self.cat.items;self:select((self.index-1+d)%n+1)
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
    if have<item.cobalt then self:say("Need "..short(item.cobalt-have));return end
    self.request=(self.request or 0)+1
    self.pending={id=item.id,requestId="armory-"..item.id.."-"..self.request}
    self.context.remotes.CosmeticsCommand:FireServer({kind="UnlockArsenal",itemId=item.id,requestId=self.pending.requestId})
    self:paint()
end
function Page:prompt(productId: any)
    if type(productId)~="number" or productId<=0 then return end -- Ashton makes the products later
    local me=Players.LocalPlayer
    if me then pcall(function() Market:PromptProductPurchase(me,productId) end) end
end
-- a short word on the Cobalt key ("Need 7.5K", the server's reason), then the price again
function Page:say(words: string)
    local at=os.clock();self.note={words=words,at=at};self:paint()
    task.delay(2,function() if not self.destroyed and self.note and self.note.at==at then self.note=nil;self:paint() end end)
end
-- newly owned: its rail card pops; on the stage, the Owned card scales in
function Page:pop(id: string)
    local card=self.root.Rail:FindFirstChild(id,true)
    for _,node in {card,if self:item() and self:item().id==id then self.root.Stage.Info.Owned else nil} do
        if not node then continue end
        local s=node:FindFirstChild("PFPop") or Instance.new("UIScale");s.Name="PFPop";s.Parent=node
        s.Scale=1.08;Tween:Create(s,TweenInfo.new(.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
    end
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
        local sub=x2:FindFirstChild("Sub");if sub and sub:IsA("TextLabel") then sub.Text=if self.x2Owned then "Active · every match pays double" else "Every match pays double, forever" end
    end
    local have=self.balance
    root.Top.Wallet.Amount.Text=if have then comma(have) else "…"
    -- the stage
    local art=self:art()
    art.Hero.Image=show.sheet;art.Glow.Image=show.sheet;self:paintFrame()
    local chip=art.Chip;chip.Text=show.chip[3];chip.TextColor3=hex(Showcase.CHIP[show.chip[4]] or "#d6dbe4");chip.Position=UDim2.fromScale(show.chip[1],show.chip[2])
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
    local own=self.owned[item.id]==true;local pack=if own then nil else self:pack()
    info.Owned.Visible=own;info.Unlock.Visible=not own and pack==nil;info.UnlockStarter.Visible=not own and pack~=nil
    if not own then
        local m=if pack then info.UnlockStarter else info.Unlock
        local got=math.min(have or 0,item.cobalt);local frac=if item.cobalt>0 then got/item.cobalt else 0
        m.Pct.Text=tostring(math.floor(frac*100)).."%"
        m.Bar.Fill.Size=UDim2.fromScale(math.max(frac,.02),1)
        m.Have.Text=string.format('<font color="#ffffff">%s</font> / %s',comma(have or 0),comma(item.cobalt))
        local ready=have~=nil and have>=item.cobalt
        m.ToGo.Text=if ready then '<font color="#9cc8ff">Ready to unlock</font>' else comma(item.cobalt-(have or 0)).." to go"
        local look=if ready then CO.ready else CO.idle
        local key=m.Cobalt;key.BackgroundColor3=look.bg;key.Main.TextColor3=look.text;key.Sub.TextColor3=look.text
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
        m.Robux.Main.Text=ROBUX..NB..tostring(item.robux)
        if pack then
            local names={}
            for _,id in pack.items do local it=self.cat.byId[id];if it then table.insert(names,it.name) end end
            -- every screen shows the same words (pure scale: nothing dropped on phones; UI-REVIEW rule 5a)
            m.Starter.Text.Text=string.format('Also in the <font color="#ffd36a">%s</font>: %s',pack.name,table.concat(names," + "))
            m.Starter.Buy.Main.Text=ROBUX..NB..tostring(pack.robux)
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
        card.BackgroundColor3=if sel then CARD.sel elseif o then CARD.own else CARD.bg
        local tone=card:FindFirstChild("Tone");if tone then tone.Enabled=not sel and not o end
        card.Rim.Color=if sel then CARD.selRim elseif o then CARD.ownRim else CARD.rim
        card.Rim.Thickness=if sel then 2 else 1
        card.Well.BackgroundColor3=if sel then CARD.selWell elseif o then CARD.ownWell else CARD.well
        card.Well.Icon.ImageColor3=if o or sel then Color3.new(1,1,1) else Color3.fromRGB(150,150,160)
        card.Label.TextColor3=if sel then hex("#ffe6a8") elseif o then hex("#d6dce6") else hex("#9aa2b0")
        card.Gem.Visible=not o;card.Price.Visible=not o;card.Own.Visible=o;card.Price.Text=short(it.cobalt)
        local b=card.Badge;b.BackgroundColor3=if o then hex("#3ed47e") else hex("#0c0f15")
        b.Ok.Visible=o;b.Shackle.Visible=not o;b.Body.Visible=not o
    end
    for _,set in {"Warfare","Industry"} do
        local grp=root.Rail:FindFirstChild(set);if not grp then continue end
        local total=0;for _,it in self.cat.items do if it.set==set then total+=1 end end
        grp.Head.Title.Text=string.format('%s  <font color="#6f7888">%d / %d</font>',string.upper(set),count[set] or 0,total)
        for _,pack in self.cat.packs or {} do if pack.set==set then grp.Head.Starter.Label.Text="· Starter pack  "..ROBUX..NB..tostring(pack.robux) end end
    end
end

function Page:focusActive() if self.visible then Gui.SelectedObject=self.root.Top.Left.Back end end
function Page:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
end
return Page
