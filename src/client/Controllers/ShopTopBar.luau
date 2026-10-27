--!strict
-- PF019 A3 (PF - 3): the approved M3 shop top bar's life (the Inventory page reuses it). The bar itself is AUTHORED
-- (tools/atlas/author-pf019-topbar.luau): one raised strip with the pixel bag + "Shop", the
-- category tabs, the Cobalt chip and the Inventory button; on a phone the title collapses to the
-- bag, Inventory to its chest and the tabs scroll under a fade + ›. This module only animates
-- looks and fills content:
--   * tabs: hover brightens the text over a faint pill (0.12s); the active tab sits on a raised
--     pill with a cobalt underline that SLIDE to the new tab (0.18s Quad Out); the active tab
--     scrolls into view; LB / RB cycle the tabs (wrapping) through onCycle.
--   * Cobalt chip: the crystal glints every 4-6s; a gain counts the number up (0.6s), floats
--     "+N" up and fades (0.5s) and bursts the crystal once; a spend counts down with a "−N"
--     float. "+" opens the Cobalt tab (onAdd).
--   * Inventory: hover lifts 2px, border #8c8c8c, the chest brightens and pops 1px.
-- ReducedMotion makes every change instant and stops the glint. The pill and underline copy the
-- active tab's authored box (they are an overlay; the tabs' own layout is never touched).
local Run=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local Tween=game:GetService("TweenService")
local NavIcons=require(script.Parent.AtlasNavIcons)
local Bar={};Bar.__index=Bar
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),border=Color3.fromHex("#4a4a4a"),hot=Color3.fromHex("#8c8c8c")}
export type Options={tabs: ScrollingFrame, onAdd: (()->())?, onCycle: ((number)->())?, reduced: (()->boolean)?}

local function number(value: number): string
    local result=tostring(math.floor(value))
    while true do local replacement,count=string.gsub(result,"^(%-?%d+)(%d%d%d)","%1,%2");result=replacement;if count==0 then break end end
    return result
end
-- The authored PF019 bar is present (older places keep their PF015 header untouched).
function Bar.installed(header: Instance): boolean
    return header:GetAttribute("PF019TopBarRevision")~=nil and header:FindFirstChild("PFTabs")~=nil
end
function Bar.new(header: Frame,options: Options): any
    local tabs=options.tabs
    local self: any=setmetatable({header=header,tabs=tabs,options=options,connections={},hover={},active=nil,visible=false,destroyed=false,
        clip=nil,pill=nil,line=nil,wallet=header:FindFirstChild("Wallet"),
        -- the right key: Inventory on the Shop bar, Visit shop on the Inventory bar
        inventory=header:FindFirstChild("NavigateInventory") or header:FindFirstChild("NavigateShop"),balance=nil,shown=nil,count=nil,nextGlint=os.clock()+2+math.random()*3},Bar)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    -- The pill + underline sit behind the scroller in PFTabs.PFPillClip (outside its list layout).
    local clip=tabs.Parent and tabs.Parent:FindFirstChild("PFPillClip")
    self.clip=clip;self.pill=clip and clip:FindFirstChild("PFTabPill");self.line=clip and clip:FindFirstChild("PFTabLine")
    for _,tab in tabs:GetChildren() do
        if not tab:IsA("TextButton") then continue end
        listen(tab.MouseEnter,function() if Input.PreferredInput~=Enum.PreferredInput.Touch then self.hover[tab]=true;self:paintTab(tab) end end)
        listen(tab.MouseLeave,function() self.hover[tab]=nil;self:paintTab(tab) end)
    end
    -- The overlay follows layout changes (rotation, window size, tab visibility) instantly.
    for _,signal in {tabs:GetPropertyChangedSignal("AbsoluteSize"),tabs:GetPropertyChangedSignal("AbsoluteCanvasSize"),tabs:GetPropertyChangedSignal("CanvasPosition")} do
        listen(signal,function() self:place(true) end)
    end
    local add=self.wallet and self.wallet:FindFirstChild("PFAdd")
    if add and options.onAdd then listen(add.Activated,function() options.onAdd() end) end
    local inv=self.inventory
    if inv and inv:FindFirstChild("PFLift") then
        local lift=inv.PFLift;local base=lift.Position;local glyph=lift:FindFirstChild("Glyph");local glyphBase=glyph and glyph.Position
        local stroke=inv:FindFirstChild("PFStroke") or inv:FindFirstChild("Border")
        local function look(hot: boolean)
            local info=self:info(.12)
            Tween:Create(lift,info,{Position=if hot then base-UDim2.fromOffset(0,2) else base}):Play()
            if stroke then Tween:Create(stroke,info,{Color=if hot then C.hot else C.border}):Play() end
            if glyph then NavIcons.paint(glyph,hot);Tween:Create(glyph,info,{Position=if hot then glyphBase-UDim2.fromOffset(0,1) else glyphBase}):Play() end
        end
        listen(inv.MouseEnter,function() if Input.PreferredInput~=Enum.PreferredInput.Touch then look(true) end end)
        listen(inv.MouseLeave,function() look(false) end)
        listen(inv.SelectionGained,function() look(true) end);listen(inv.SelectionLost,function() look(false) end)
        if glyph then NavIcons.paint(glyph,false) end
    end
    local title=header:FindFirstChild("PFTitle");local bag=title and title:FindFirstChild("Glyph")
    if bag then NavIcons.paint(bag,true) end
    listen(Input.InputBegan,function(input: InputObject,processed: boolean)
        if not self.visible or not options.onCycle then return end
        if input.KeyCode==Enum.KeyCode.ButtonL1 then options.onCycle(-1) elseif input.KeyCode==Enum.KeyCode.ButtonR1 then options.onCycle(1) end
    end)
    listen(Run.Heartbeat,function() self:step() end)
    return self
end
function Bar:reduced(): boolean return self.options.reduced~=nil and self.options.reduced() end
function Bar:info(t: number): TweenInfo return TweenInfo.new(if self:reduced() then 0 else t,Enum.EasingStyle.Quad,Enum.EasingDirection.Out) end
function Bar:paintTab(tab: TextButton)
    local active=tab.Name==self.active;local hot=self.hover[tab]==true
    local info=self:info(.12)
    Tween:Create(tab,info,{TextColor3=if active or hot then C.text else C.muted,BackgroundTransparency=if hot and not active then .94 else 1}):Play()
end
-- The raised pill + cobalt underline copy the active tab's box (canvas coordinates).
function Bar:place(instant: boolean?)
    local tab=self.active and self.tabs:FindFirstChild(self.active)
    if not tab or not tab:IsA("GuiObject") or not tab.Visible or not self.pill then
        if self.pill then self.pill.Visible=false end;if self.line then self.line.Visible=false end;return
    end
    -- Screen-space offset from the clip (it covers the scroller), so scrolling carries the pill.
    local at=tab.AbsolutePosition-(if self.clip then self.clip.AbsolutePosition else self.tabs.AbsolutePosition);local size=tab.AbsoluteSize
    local info=if instant then TweenInfo.new(0) else self:info(.18)
    self.pill.Visible=true
    Tween:Create(self.pill,info,{Position=UDim2.fromOffset(at.X,at.Y),Size=UDim2.fromOffset(size.X,size.Y)}):Play()
    if self.line then
        self.line.Visible=true
        local width=math.max(12,size.X-24)
        Tween:Create(self.line,info,{Position=UDim2.fromOffset(at.X+(size.X-width)/2,at.Y+size.Y-5),Size=UDim2.fromOffset(width,3)}):Play()
    end
end
function Bar:setActive(name: string)
    local previous=self.active;self.active=name
    for _,tab in self.tabs:GetChildren() do if tab:IsA("TextButton") then self:paintTab(tab) end end
    self:place(previous==nil)
    -- The active tab always scrolls into view (past the right fade + ›).
    local tab=self.tabs:FindFirstChild(name)
    if tab and tab:IsA("GuiObject") then
        local delta=tab.AbsolutePosition.X-self.tabs.AbsolutePosition.X;local x=self.tabs.CanvasPosition.X
        if delta<8 then x+=delta-8 elseif delta+tab.AbsoluteSize.X>self.tabs.AbsoluteWindowSize.X-36 then x+=delta+tab.AbsoluteSize.X-self.tabs.AbsoluteWindowSize.X+36 end
        local target=Vector2.new(math.max(0,x),0)
        if target~=self.tabs.CanvasPosition then Tween:Create(self.tabs,self:info(.18),{CanvasPosition=target}):Play() end
    end
end
-- Balance: count up on a gain (with the +N float and a crystal burst), count DOWN on a spend (a
-- "−N" float in the spend colour, no burst; Cobalt buy, Ashton via MM); otherwise set it. The page
-- passes server-confirmed balances only, so a count-down is a real spend.
local SPEND=Color3.fromHex("#ff9a9a")
function Bar:setBalance(value: number?,text: string?)
    local wallet=self.wallet;if not wallet then return end
    local amount=wallet:FindFirstChild("Amount");if not amount then return end
    if type(value)~="number" then self.balance=nil;self.count=nil;amount.Text=text or "—";return end
    local previous=self.balance;self.balance=value
    if previous==nil or value==previous or self:reduced() or not self.visible then self.count=nil;amount.Text=number(value);return end
    local gain=value>previous
    self.count={from=self.shown or previous,to=value,start=os.clock()}
    local float=wallet:FindFirstChild("PFFloat")
    if float then
        local gainColor=float:GetAttribute("PFGainColor") or float.TextColor3;float:SetAttribute("PFGainColor",gainColor)
        float.Text=(if gain then "+" else "−")..number(math.abs(value-previous));float.TextColor3=if gain then gainColor else SPEND
        float.Visible=true;float.TextTransparency=0
        local base=float:GetAttribute("PFBase") or float.Position;float:SetAttribute("PFBase",base);float.Position=base
        Tween:Create(float,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=base-UDim2.fromOffset(0,18),TextTransparency=1}):Play()
    end
    if not gain then return end
    local burst=wallet:FindFirstChild("CurrencyIcon") and wallet.CurrencyIcon:FindFirstChild("PFBurst")
    if burst then burst.Scale=1.25;Tween:Create(burst,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    self:glint()
end
function Bar:glint()
    local wallet=self.wallet;local glint=wallet and wallet:FindFirstChild("PFGlint");local gradient=glint and glint:FindFirstChildOfClass("UIGradient")
    if not gradient or self:reduced() then return end
    gradient.Offset=Vector2.new(-1,0)
    Tween:Create(gradient,TweenInfo.new(.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Offset=Vector2.new(1,0)}):Play()
end
function Bar:step()
    if self.destroyed or not self.visible then return end
    local now=os.clock()
    if self.count then
        local c=self.count;local t=math.clamp((now-c.start)/.6,0,1);t=1-(1-t)^3
        local shown=math.floor(c.from+(c.to-c.from)*t+.5)
        if shown~=self.shown then require(script.Parent.Sfx).play("u_tick") end -- PF - 3's audio (one per 70 ms)
        self.shown=shown
        local amount=self.wallet and self.wallet:FindFirstChild("Amount");if amount then amount.Text=number(shown) end
        if t>=1 then self.count=nil end
    else self.shown=self.balance end
    -- Glint every 4-6s at rest, offset from the cards' loops.
    if now>=self.nextGlint then self.nextGlint=now+4+math.random()*2;self:glint() end
end
function Bar:setVisible(value: boolean)
    if self.visible==value then return end
    self.visible=value
    if value then task.defer(function() if not self.destroyed then self:place(true) end end) end
end
function Bar:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
return Bar
