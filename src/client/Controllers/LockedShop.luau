--!strict
-- PF019 M13b (PF - 2): the shop over a live match ("locked mode"). AtlasMenuController
-- opens the real Shop page (PF - 3's M3 bar + M2 cards) and calls this for what locked
-- mode adds: the scrim over the match, the gold banner under the bar ("In a match · Shop
-- only" with the clock and players alive) and the gold "Back to battle · Esc" key that
-- stands in for the Inventory key. The nodes are authored by
-- tools/atlas/author-pf019-locked-shop.luau (PF013: Edit == Play); this fills text and
-- animates: the scrim fades in and the shop rises 16 px over 180 ms; the key lifts 2 px
-- and glows on hover and presses to 0.97. Prices, purchases and inventory are the lobby
-- shop's own: nothing here touches the economy.
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local Locked={};Locked.__index=Locked
Locked.OPEN=.18
Locked.RISE=16
Locked.LIFT=2
Locked.PRESS=.97
Locked.WIDE=1000 -- banner width (px) under which the message shortens (phones: A06 669, iPhone 13 Pro Max 789)
Locked.TICK=.5

function Locked.message(compact: boolean): string
    return if compact then "In a match \u{00B7} Shop only"
        else "In a match \u{00B7} Shop only. The lobby is hidden until you go back to the battle."
end
-- "12:41 · 63 alive · you are not paused"; phones drop the last part. Missing pieces drop out.
function Locked.statusText(status: any, compact: boolean): string
    local parts={}
    if type(status)=="table"then
        if type(status.clock)=="string"and status.clock~=""then table.insert(parts,status.clock)end
        if type(status.alive)=="number"then table.insert(parts,tostring(math.floor(status.alive)).." alive")end
    end
    if not compact then table.insert(parts,"you are not paused")end
    return table.concat(parts," \u{00B7} ")
end
-- The key's hint follows the last input: Esc on a keyboard, B on a gamepad, none on touch.
function Locked.keycap(input: string): string?
    if input=="Gamepad"then return "B"elseif input=="Touch"then return nil end
    return "Esc"
end
local function lastInput(): string
    local name=UserInputService:GetLastInputType().Name
    if string.sub(name,1,7)=="Gamepad"then return "Gamepad"end
    if name=="Touch"then return "Touch"end
    return "Keyboard"
end

-- nil until the helper has authored the nodes (AtlasMenuController then has no locked mode).
function Locked.new(atlasRoot: any, hooks: any, services: any?): any?
    local pages=atlasRoot:FindFirstChild("Pages")
    local page=pages and pages:FindFirstChild("Shop")
    local content=page and page:FindFirstChild("AtlasCommerceContent")
    -- PF - 1 2026-10-25: the Header may live in AtlasMenu.PFShopTop (one bar); the content keeps PFHeaderRef to it
    local ref=content and content:FindFirstChild("PFHeaderRef")
    local header=content and (content:FindFirstChild("Header") or (ref and (ref :: any).Value))
    local banner=content and content:FindFirstChild("PFLockedBanner")
    local button=header and header:FindFirstChild("PFBackToBattle")
    local body=button and button:FindFirstChild("Body")
    local scrim=atlasRoot:FindFirstChild("PFLockedScrim")
    if not (banner and body and scrim)then return nil end
    local s=services or {}
    local stroke=body:FindFirstChild("PFStroke")
    -- PFLockedPanel (optional, beside the page in Pages: the page clips): the shop's card while locked.
    -- The lobby's opaque surfaces step aside so the match shows: the root's fill, and every root
    -- child the helper tagged PFLockedHide (Backdrop, TopInsetBacking).
    local surfaces={}
    for _,child in atlasRoot:GetChildren()do if child:GetAttribute("PFLockedHide")==true then table.insert(surfaces,child)end end
    local self=setmetatable({hooks=hooks,root=atlasRoot,surfaces=surfaces,saved={},page=page,banner=banner,scrim=scrim,panel=pages:FindFirstChild("PFLockedPanel"),inventoryKey=header:FindFirstChild("NavigateInventory"),
        shown=false,token=0,connections={},options=nil,inventoryWas=true,
        pageRest=page.Position,scrimRest=scrim.BackgroundTransparency,
        key={button=button,body=body,base=body.Position,stroke=stroke,restStroke=if stroke then stroke.Color else nil,
            hoverStroke=body:GetAttribute("PFHoverStroke"),glow=button:FindFirstChild("PFGlow"),scale=body:FindFirstChild("PFScale"),
            keycap=body:FindFirstChild("Keycap"),hovered=false,pressed=false},
        tween=s.tween or function(target,info,goals)local t=TweenService:Create(target,info,goals);t:Play();return t end,
        every=s.every or function(seconds: number,fn: ()->boolean)task.spawn(function()while fn()do task.wait(seconds)end end)end,
        input=s.input or lastInput,
        reduced=s.reduced or function()return atlasRoot:GetAttribute("ReducedMotion")==true end},Locked)
    local key=self.key
    local function listen(signal: any,fn: any)table.insert(self.connections,signal:Connect(fn))end
    listen(button.MouseEnter,function()key.hovered=true;self:look()end)
    listen(button.MouseLeave,function()key.hovered=false;key.pressed=false;self:look()end)
    listen(button.SelectionGained,function()key.hovered=true;self:look()end)
    listen(button.SelectionLost,function()key.hovered=false;self:look()end)
    listen(button.InputBegan,function(input: any)
        local t=input.UserInputType
        if t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.Touch then key.pressed=true;self:look()end
    end)
    listen(button.InputEnded,function()if key.pressed then key.pressed=false;self:look()end end)
    listen(button.Activated,function()if self.shown and self.hooks.back then self.hooks.back()end end)
    listen(banner:GetPropertyChangedSignal("AbsoluteSize"),function()if self.shown then self:refresh()end end)
    return self
end

function Locked:isShown(): boolean return self.shown end

-- Key look: hover lifts the body 2 px, brightens the gold stroke and wakes the glow;
-- press scales to 0.97 for 80 ms.
function Locked:look()
    local key=self.key
    local reduced=self.reduced()
    local info=TweenInfo.new(if reduced then 0 else .13,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    local hot=key.hovered or key.pressed
    local base=key.base
    self.tween(key.body,info,{Position=UDim2.new(base.X.Scale,base.X.Offset,base.Y.Scale,base.Y.Offset+(if hot and not key.pressed then -Locked.LIFT else 0))})
    if key.stroke and key.restStroke then
        local hover=if typeof(key.hoverStroke)=="Color3"then key.hoverStroke else key.restStroke:Lerp(Color3.new(1,1,1),.3)
        self.tween(key.stroke,info,{Color=if hot then hover else key.restStroke})
    end
    if key.glow then self.tween(key.glow,info,{ImageTransparency=if hot then .5 else 1})end
    if key.scale then
        self.tween(key.scale,TweenInfo.new(if reduced then 0 else .08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=if key.pressed then Locked.PRESS else 1})
    end
end

function Locked:refresh()
    local width=self.banner.AbsoluteSize.X
    local compact=width>0 and width<Locked.WIDE
    local message=self.banner:FindFirstChild("Message")
    local status=self.banner:FindFirstChild("Status")
    if message then message.Text=Locked.message(compact)end
    if status then status.Text=Locked.statusText(self.options and self.options.status and self.options.status(),compact)end
    local keycap=self.key.keycap
    if keycap then
        local hint=Locked.keycap(self.input())
        keycap.Visible=hint~=nil
        local label=keycap:FindFirstChild("Label")
        if hint and label then label.Text=hint end
    end
end

function Locked:show(options: any?)
    if self.shown then return end
    self.shown=true;self.options=options or {}
    self.token+=1
    local token=self.token
    self.scrim.Visible=true;self.banner.Visible=true;self.key.button.Visible=true
    if self.panel then self.panel.Visible=true end
    self.saved={fill=self.root.BackgroundTransparency}
    self.root.BackgroundTransparency=1
    for _,surface in self.surfaces do self.saved[surface]=surface.Visible;surface.Visible=false end
    if self.inventoryKey then self.inventoryWas=self.inventoryKey.Visible;self.inventoryKey.Visible=false end
    self:refresh()
    local rest=self.pageRest
    if self.reduced()then
        self.page.Position=rest;self.scrim.BackgroundTransparency=self.scrimRest
    else
        local info=TweenInfo.new(Locked.OPEN,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        self.page.Position=UDim2.new(rest.X.Scale,rest.X.Offset,rest.Y.Scale,rest.Y.Offset+Locked.RISE)
        self.scrim.BackgroundTransparency=1
        self.tween(self.page,info,{Position=rest})
        self.tween(self.scrim,info,{BackgroundTransparency=self.scrimRest})
    end
    -- the banner's clock ticks while the shop is up
    self.every(Locked.TICK,function()
        if token~=self.token or not self.shown then return false end
        self:refresh();return true
    end)
end

function Locked:hide()
    if not self.shown then return end
    self.shown=false;self.token+=1
    self.scrim.Visible=false;self.banner.Visible=false;self.key.button.Visible=false
    if self.panel then self.panel.Visible=false end
    if self.saved.fill~=nil then self.root.BackgroundTransparency=self.saved.fill end
    for _,surface in self.surfaces do if self.saved[surface]~=nil then surface.Visible=self.saved[surface]end end
    self.saved={}
    if self.inventoryKey then self.inventoryKey.Visible=self.inventoryWas end
    self.page.Position=self.pageRest;self.scrim.BackgroundTransparency=self.scrimRest
    local key=self.key
    if key.hovered or key.pressed then key.hovered=false;key.pressed=false;self:look()end
end

function Locked:destroy()
    self:hide()
    for _,c in self.connections do c:Disconnect()end
    table.clear(self.connections)
end

return Locked
