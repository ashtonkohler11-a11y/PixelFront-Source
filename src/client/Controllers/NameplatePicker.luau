--!strict
-- PF043 B4 (PF - 3; Ashton: "im confused what these nameplates are ... they literally dont show up anywhere in the yourlook
-- category so theres no way to preview them"; board PF043-B4-nameplates, "Good, build"). The nameplate is how your name
-- looks on the map. Inventory > Your look gets a NAMEPLATE tile (your name live in the equipped style; the IN MATCH strip
-- follows it) and a tap opens the picker: every style previewed live on a map patch, the way PlayerNames draws it in a
-- match (NameplateStyle's gradients and motion). Owned styles equip; locked ones lead to what unlocks them (the pass /
-- VIP card, or the Levels track). Content only: the tile and the picker are authored (tools/atlas/author-pf043-nameplate.luau).
-- State comes from the server's Cosmetics packet; equipping is the same Equip the Settings row used (slot Nameplate).
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog=require(Shared.CosmeticCatalog)
local Style=require(script.Parent.NameplateStyle)
local Picker={};Picker.__index=Picker
-- The picker's order. item=nil is Default (nothing equipped). level: the Levels reward that unlocks it.
Picker.STYLES=table.freeze({
    table.freeze({key="default",name="Default"}),
    table.freeze({key="neon",name="Neon",item="nameplate_neon"}),
    table.freeze({key="ember",name="Ember",item="nameplate_ember"}),
    table.freeze({key="prism",name="Prism",item="nameplate_prism"}),
    table.freeze({key="frost",name="Frost",item="nameplate_frost"}),
    table.freeze({key="gold",name="Gold",item="nameplate_gold"}),
    -- PIVOT D15 (Levels removed; Ashton 2026-10-23): the two level nameplates are Cobalt unlocks (Catalog.COBALT_UNLOCKS)
    table.freeze({key="centurion",name="Centurion",item="nameplate_level_centurion"}),
    table.freeze({key="celestial",name="Celestial",item="nameplate_level_celestial_190"}),
    -- PIVOT Glacier (PF - 1): the Icicle plate, earned on Day 4 of the Daily reward
    table.freeze({key="icicle",name="Icicle",item="nameplate_icicle"}),
})
Picker.CONFIRM_SECONDS=3 -- a Cobalt unlock buys on a second tap inside this window
local PASS_WORDS={pass_animated_nameplate="Animated Nameplate",pass_vip="VIP"}
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),cobalt=Color3.fromHex("#3678ff"),gold=Color3.fromHex("#f1cf7f"),
    blue=Color3.fromHex("#9fc0ff"),card=Color3.fromHex("#1f1f1f"),cardOn=Color3.fromHex("#141d33"),rim=Color3.fromHex("#3d3d3d")}
-- the level plates' pill under the name (a still version of NameplateStyle.plates for the preview)
local PLATES={centurion={fill=Color3.fromHex("#111318"),rim=Color3.fromHex("#e0a83a")},celestial={fill=Color3.fromHex("#1c2560"),rim=Color3.fromHex("#d8e0ef")},
    icicle={fill=Color3.fromHex("#2c5891"),rim=Color3.fromHex("#a9d4f2")}}

-- What a style is to you: "equipped", "equip", or {pass=id} / {level=n} (what unlocks it).
function Picker.access(entry: any,c: any): any
    local equipped=type(c)=="table" and type(c.equipped)=="table" and c.equipped.Nameplate or nil
    if type(equipped)~="string" then equipped=nil end
    if entry.item==nil then return if equipped==nil then "equipped" else "equip" end
    if equipped==entry.item then return "equipped" end
    local owned=type(c)=="table" and type(c.owned)=="table" and c.owned or {}
    if owned[entry.item]==true then return "equip" end
    local item=Catalog.byId[entry.item]
    local pass=item and item.passOnly
    if type(pass)=="string" then
        local passes=type(c)=="table" and type(c.passes)=="table" and c.passes or {}
        -- RELEASE 2026-10-26: Neon / Ember / Prism / Frost are Cobalt unlocks now (no pass), so only VIP's Gold is pass-only
        local has=owned[pass]==true or (pass=="pass_vip" and c.vip==true)
        return if has then "equip" else {pass=pass}
    end
    -- PIVOT Glacier: an earned pack's item (the Daily reward's day)
    if item and item.packOnly then
        for _,pack in Catalog.earnedPacks or {} do if table.find(pack.items,item.id) then return {daily=pack.daily} end end
    end
    -- PIVOT D15: a Cobalt unlock (no longer a level reward)
    local price=item and not item.levelOnly and tonumber(item.price)
    if price and price>0 then return {price=price} end
    if entry.level then return {level=entry.level} end
    return {level=0}
end
local function grouped(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse();return (out:gsub("^,",""))
end
-- The equipped style's entry (Default when none or unknown).
function Picker.current(c: any): any
    for _,entry in Picker.STYLES do if Picker.access(entry,c)=="equipped" then return entry end end
    return Picker.STYLES[1]
end

-- nodes: {tile=TextButton?, inMatch=TextLabel?, root=Frame?}; context: {remotes, openPass(passId), reducedMotion?}
function Picker.new(nodes: any,context: any): any
    local self: any=setmetatable({nodes=nodes,context=context,cosmetics=nil,cards={},connections={},open=false,destroyed=false,request=0},Picker)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local root=nodes.root
    if nodes.tile then listen(nodes.tile.Activated,function() self:setOpen(true) end) end
    if root then
        root.Visible=false
        local sheet=root.Stage.Sheet
        listen(root.Scrim.Activated,function() self:setOpen(false) end)
        listen(sheet.Close.Activated,function() self:setOpen(false) end)
        local template=sheet.Templates.Card
        for index,entry in Picker.STYLES do
            local card=template:Clone();card.Name="Style_"..entry.key;card.LayoutOrder=index;card.Visible=true;card.Parent=sheet.Grid
            card.Label.Text=entry.name
            local name=card.Patch.PlayerName
            local plate=PLATES[entry.key]
            card.Patch.Plate.Visible=plate~=nil
            if plate then card.Patch.Plate.BackgroundColor3=plate.fill;local rim=card.Patch.Plate:FindFirstChildWhichIsA("UIStroke");if rim then rim.Color=plate.rim end end
            Style.apply(name.PFStyle,if entry.item then entry.key else nil)
            self.cards[entry.key]={card=card,entry=entry,gradient=name.PFStyle}
            listen(card.Activated,function() self:choose(entry) end)
        end
    end
    if context.remotes then
        listen(context.remotes.CosmeticsState.OnClientEvent,function(packet: any)
            if type(packet)~="table" or packet.kind~="Cosmetics" or not packet.loaded then return end
            self.cosmetics=packet;self:paint()
        end)
    end
    listen(Run.Heartbeat,function() self:animate(os.clock()) end)
    self:paint()
    return self
end
function Picker:name(): string
    local me=Players.LocalPlayer
    return if me then me.DisplayName else "Player"
end
-- the tile, the IN MATCH name and every card
function Picker:paint()
    if self.destroyed then return end
    local c=self.cosmetics or {}
    local current=Picker.current(c)
    local display=self:name()
    local tile=self.nodes.tile
    if tile then
        tile.StyleName.Text=current.name
        tile.Preview.PlayerName.Text=display
        Style.apply(tile.Preview.PlayerName.PFStyle,if current.item then current.key else nil)
        local plate=PLATES[current.key];tile.Preview.Plate.Visible=plate~=nil
        if plate then tile.Preview.Plate.BackgroundColor3=plate.fill;local rim=tile.Preview.Plate:FindFirstChildWhichIsA("UIStroke");if rim then rim.Color=plate.rim end end
    end
    local inMatch=self.nodes.inMatch
    if inMatch then local g=inMatch:FindFirstChild("PFStyle");if g and g:IsA("UIGradient") then Style.apply(g,if current.item then current.key else nil) end end
    for _,slot in self.cards do
        local card,entry=slot.card,slot.entry
        card.Patch.PlayerName.Text=display
        local access=Picker.access(entry,c)
        local on=access=="equipped"
        card.BackgroundColor3=if on then C.cardOn else C.card
        local rim=card:FindFirstChild("PFStroke");if rim and rim:IsA("UIStroke") then rim.Color=if on then C.cobalt else C.rim;rim.Thickness=if on then 2 else 1 end
        card.StateFill.Visible=on
        local state=card.State
        if on then state.Text="✓ Equipped";state.TextColor3=C.text
        elseif access=="equip" then state.Text="Equip";state.TextColor3=C.text
        elseif type(access)=="table" and access.pass then
            state.Text="Comes with "..(PASS_WORDS[access.pass] or "a pass");state.TextColor3=if access.pass=="pass_vip" then C.gold else C.blue
        elseif type(access)=="table" and access.price then
            local armed=self.armed and self.armed.key==entry.key and os.clock()<self.armed.until_
            state.Text=if armed then "Tap again · "..grouped(access.price) else grouped(access.price).." Cobalt";state.TextColor3=if armed then C.gold else C.blue
        elseif type(access)=="table" and access.daily then state.Text="Daily reward · Day "..tostring(access.daily);state.TextColor3=C.blue
        else state.Text="Reach Level "..tostring(access.level);state.TextColor3=C.blue end
        card.Patch.Shade.Visible=type(access)=="table"
    end
end
-- Equip yours; a locked style shows what unlocks it.
function Picker:choose(entry: any)
    if not self.open then return end
    local access=Picker.access(entry,self.cosmetics or {})
    if access=="equipped" then return end
    if access=="equip" then
        self.request+=1
        if self.context.remotes then
            self.context.remotes.CosmeticsCommand:FireServer({kind="Equip",itemId=entry.item or false,slot="Nameplate",requestId="nameplate"..self.request})
        end
        return
    end
    -- PIVOT D15: a Cobalt unlock: the first tap arms it, a second within CONFIRM_SECONDS buys it (the server checks the balance)
    if access.price then
        local armed=self.armed
        if armed and armed.key==entry.key and os.clock()<armed.until_ then
            self.armed=nil;self.request+=1
            if self.context.remotes then
                self.context.remotes.CosmeticsCommand:FireServer({kind="Buy",itemId=entry.item,requestId="nameplate-buy-"..entry.key.."-"..self.request})
            end
        else
            self.armed={key=entry.key,until_=os.clock()+Picker.CONFIRM_SECONDS}
            task.delay(Picker.CONFIRM_SECONDS,function() if self.armed and self.armed.key==entry.key and os.clock()>=self.armed.until_ then self.armed=nil;self:paint() end end)
        end
        self:paint()
        return
    end
    self:setOpen(false)
    if access.pass and self.context.openPass then self.context.openPass(access.pass)
    elseif access.daily then local ok,View=pcall(require,script.Parent.DailyView);if ok and (View :: any).openStreak then (View :: any).openStreak() end end
end
function Picker:setOpen(open: boolean)
    local root=self.nodes.root
    if self.destroyed or not root or self.open==open then return end
    self.open=open;root.Visible=open
    if open then
        self:paint()
        local pop=root.Stage.Sheet:FindFirstChild("PFPop")
        if pop and not (self.context.reducedMotion and self.context.reducedMotion()) then
            pop.Scale=.94;game:GetService("TweenService"):Create(pop,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
        end
        local first=self.cards[Picker.current(self.cosmetics or {}).key]
        if first and GuiService.SelectedObject~=nil then GuiService.SelectedObject=first.card end
    elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
        GuiService.SelectedObject=self.nodes.tile
    end
end
function Picker:handleEscape(): boolean
    if self.open then self:setOpen(false);return true end
    return false
end
-- Style.animate writes only on a frame change; the tile always, the cards while the picker is open.
function Picker:animate(now: number)
    if self.destroyed then return end
    local current=Picker.current(self.cosmetics or {})
    local tile=self.nodes.tile
    if tile and current.item then Style.animate(tile.Preview.PlayerName.PFStyle,current.key,now) end
    local inMatch=self.nodes.inMatch
    local g=inMatch and inMatch:FindFirstChild("PFStyle")
    if g and current.item then Style.animate(g :: any,current.key,now) end
    if not self.open then return end
    for key,slot in self.cards do if slot.entry.item then Style.animate(slot.gradient,key,now) end end
end
function Picker:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
return Picker
