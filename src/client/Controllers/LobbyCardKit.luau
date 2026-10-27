--!strict
-- PF019 (PF - 3): the global lobby card kit (approved M2 template; M6 is the bar).
-- Every lobby box (Play match/mode cards, Shop and Discover items, bundles, inventory,
-- art cards) binds here, so one change restyles all of them.
--
-- Authored structure (PF013: geometry lives in the place, made by the author helpers):
--   <Card> (GuiButton or Frame, a transparent layout slot)
--     PFCardShadow  ImageLabel, LobbyCardAssets.glow 9-slice, black
--     PFCardGlow    ImageLabel, same image, tinted the set colour, hidden at rest
--     PFCardBody    Frame, the visible panel (UICorner, AnchorPoint .5,.5)
--       PFCardStroke  UIStroke (rest hairline)
--       PFCardScale   UIScale (press)
--       PFCardRing    Frame + UIStroke tagged PFAccentStroke=focus (gamepad ring)
--       ...content; an optional UIScale named PFCardZoom zooms the art on hover
-- Attributes: PFCardSet (Color3, hover border/glow colour).
-- Code here only animates looks (lift, scale, colours, transparency). It never sizes.
local Run=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Tween=game:GetService("TweenService")
local Math=require(script.Parent.LobbyCardKitMath)
local NEUTRAL_SET=Color3.fromHex("#8c8c8c")
local ACCENT=Color3.fromHex("#3678ff")
local Kit={};Kit.__index=Kit
local Handle={};Handle.__index=Handle

export type Options={set: Color3?, targets: {GuiObject}?, idle: ((any, number)->())?, onLook: ((any, any)->())?}

local function isPress(input: InputObject): boolean
    return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch
end
local function screenGui(node: Instance): ScreenGui?
    local found=node:FindFirstAncestorWhichIsA("LayerCollector")
    return if found and found:IsA("ScreenGui") then found else nil
end

function Kit.new(root: GuiObject): any
    local self: any=setmetatable({root=root,cards={},connections={},active=false,destroyed=false,lastScan=0},Kit)
    local function listen(signal: RBXScriptSignal, callback: any) table.insert(self.connections,signal:Connect(callback)) end
    listen(Gui:GetPropertyChangedSignal("SelectedObject"),function() self:_syncFocus() end)
    listen(Input:GetPropertyChangedSignal("PreferredInput"),function()
        for _,h in self.cards do if Input.PreferredInput==Enum.PreferredInput.Touch then h.state.hover=false end;h:_apply() end
        self:_syncFocus()
    end)
    listen(Input.InputBegan,function(input: InputObject)
        if input.KeyCode~=Enum.KeyCode.ButtonA and input.KeyCode~=Enum.KeyCode.Return then return end
        for _,h in self.cards do if h.state.focused and not h.state.pressed then h.state.pressed=true;h.pressInput=input;h:_apply() end end
    end)
    listen(Input.InputEnded,function(input: InputObject)
        for _,h in self.cards do
            local active=h.pressInput
            if h.state.pressed and active and (input==active or (input.UserInputType==active.UserInputType and input.KeyCode==active.KeyCode)) then
                h.state.pressed=false;h.pressInput=nil;h:_apply()
            end
        end
    end)
    listen(Input.InputChanged,function(input: InputObject)
        if input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        for _,h in self.cards do if h.state.hover and not h:_mouseInside() then h.state.hover=false;h:_apply() end end
    end)
    listen(Input.WindowFocusReleased,function()
        for _,h in self.cards do h.state.hover=false;h.state.pressed=false;h.pressInput=nil;h:_apply() end
    end)
    listen(root:GetAttributeChangedSignal("ReducedMotion"),function() for _,h in self.cards do h:_apply() end end)
    listen(Run.Heartbeat,function() self:_step() end)
    listen(root.Destroying,function() self:destroy() end)
    return self
end
function Kit:reduced(): boolean return self.root:GetAttribute("ReducedMotion")==true end
-- The menu shows/hides as a whole; idle loops only run while it is up.
function Kit:setActive(active: boolean)
    self.active=active
    if not active then for _,h in self.cards do h.state.hover=false;h.state.pressed=false;h.pressInput=nil;h:_apply(true) end end
end
function Kit:_syncFocus()
    local selected=Gui.SelectedObject
    local touch=Input.PreferredInput==Enum.PreferredInput.Touch
    for card,h in self.cards do
        local focused=not touch and selected~=nil and (selected==card or selected:IsDescendantOf(card))
        if focused~=(h.state.focused==true) then h.state.focused=focused;h:_apply() end
    end
end
-- Visible = every ancestor up to the ScreenGui is shown and the card overlaps its scroll
-- window and the viewport. Scanned at 5Hz; idle loops run each frame for visible cards.
function Kit:_visible(card: GuiObject): boolean
    local node: Instance?=card
    local window: GuiObject?=nil
    while node and not node:IsA("LayerCollector") do
        if node:IsA("GuiObject") then
            if not node.Visible then return false end
            if window==nil and node~=card and node:IsA("ScrollingFrame") then window=node end
        end
        node=node.Parent
    end
    if not node or not (node :: LayerCollector).Enabled then return false end
    local camera=workspace.CurrentCamera
    if camera and not Math.overlaps(card.AbsolutePosition,card.AbsoluteSize,Vector2.new(-64,-64),camera.ViewportSize+Vector2.new(128,128)) then return false end
    if window and not Math.overlaps(card.AbsolutePosition,card.AbsoluteSize,window.AbsolutePosition,window.AbsoluteSize) then return false end
    return true
end
function Kit:_step()
    if self.destroyed or not self.active then return end
    local now=os.clock()
    if now-self.lastScan>=.2 then
        self.lastScan=now
        for card,h in self.cards do h.onScreen=self:_visible(card) end
    end
    if self:reduced() then return end
    for _,h in self.cards do
        if h.idle and h.onScreen then
            local ok,err=pcall(h.idle,h,now)
            if not ok then h.idle=nil;warn("[LobbyCardKit] idle loop stopped: "..tostring(err)) end
        end
    end
end

function Kit:bind(card: GuiObject, options: Options?): any
    if self.cards[card] then self.cards[card]:destroy() end
    local opts: any=options or {}
    local body=card:FindFirstChild("PFCardBody") :: GuiObject?
    assert(body and body:IsA("GuiObject"),"LobbyCardKit: "..card:GetFullName().." has no authored PFCardBody")
    local ring=body:FindFirstChild("PFCardRing")
    local ringStroke=if ring then ring:FindFirstChildWhichIsA("UIStroke") else nil
    local stroke=body:FindFirstChild("PFCardStroke") :: UIStroke?
    local h: any=setmetatable({kit=self,card=card,body=body,stroke=stroke,scale=body:FindFirstChild("PFCardScale"),
        ringStroke=ringStroke,glow=card:FindFirstChild("PFCardGlow"),shadow=card:FindFirstChild("PFCardShadow"),
        zoom=card:FindFirstChild("PFCardZoom",true),idle=opts.idle,onLook=opts.onLook,
        phase=Math.phase(card:GetFullName()),onScreen=false,state={},connections={},wasPressed=false},Handle)
    h.bodyBase=body.Position
    h.shadowBase=if h.shadow then (h.shadow :: GuiObject).Position-UDim2.fromOffset(0,4) else nil
    h.style={set=opts.set or card:GetAttribute("PFCardSet") or NEUTRAL_SET,
        rest=if stroke then stroke.Color else Color3.fromHex("#535353"),fill=body.BackgroundColor3,accent=ACCENT}
    local function listen(signal: RBXScriptSignal, callback: any) table.insert(h.connections,signal:Connect(callback)) end
    local hosts={card};for _,t in opts.targets or {} do table.insert(hosts,t) end
    for _,host in hosts do
        listen(host.MouseEnter,function()
            if Input.PreferredInput==Enum.PreferredInput.Touch then return end
            if not h.state.hover then h.state.hover=true;h:_apply() end
        end)
        listen(host.MouseLeave,function() if h.state.hover and not h:_mouseInside() then h.state.hover=false;h:_apply() end end)
        listen(host.InputBegan,function(input: InputObject)
            if isPress(input) and not h.state.pressed then h.state.pressed=true;h.pressInput=input;h:_apply() end
        end)
    end
    listen(card:GetAttributeChangedSignal("PFCardSet"),function()
        local value=card:GetAttribute("PFCardSet");if typeof(value)=="Color3" then h.style.set=value;h:_apply() end
    end)
    listen(card.Destroying,function() h:destroy() end)
    -- The gold selected ring is the kit's own: anything that repaints it (the lobby accent registry
    -- painting a card parented after it was selected, an accent change) sets the new focus colour,
    -- which the kit keeps for later, and gold comes back.
    if ringStroke then
        listen(ringStroke:GetPropertyChangedSignal("Color"),function()
            if h.ringGold and not h.destroyed and ringStroke.Color~=Math.SELECTED_RING then
                h.style.accent=ringStroke.Color;ringStroke.Color=Math.SELECTED_RING
            end
        end)
    end
    self.cards[card]=h
    h.onScreen=self:_visible(card)
    h:_apply(true)
    return h
end
function Kit:unbind(card: GuiObject) local h=self.cards[card];if h then h:destroy() end end
-- The interface accent moved (LobbyAccentFocus repainted every focus ring): rings in their gold
-- selected look are the kit's own, so put gold back; the rest adopt the new focus colour as theirs.
function Kit:accentChanged()
    for _,h in self.cards do
        local ring=h.ringStroke
        if ring and not h.destroyed then
            -- the registry has just painted the new focus colour on every ring: adopt it (gold rings too,
            -- for when they are deselected), then give the selected ones their gold back
            if ring.Color~=Math.SELECTED_RING then h.style.accent=ring.Color end
            if h.ringGold then ring.Color=Math.SELECTED_RING end
        end
    end
end
function Kit:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    for _,h in table.clone(self.cards) do h:destroy() end
end

function Handle:_mouseInside(): boolean
    local p=Input:GetMouseLocation()
    local gui=screenGui(self.card)
    -- PF044 (Ashton: "hovering is really weird"): GetMouseLocation counts the top bar; AbsolutePosition doesn't when the gui
    -- keeps the inset OR uses DeviceSafeInsets (IgnoreGuiInset alone isn't enough: OpenFront's origin sits 58 px down). Without
    -- this every mouse move cleared the button's hover a frame after MouseEnter and the parent card tested 58 px off.
    if gui and (not gui.IgnoreGuiInset or gui.ScreenInsets~=Enum.ScreenInsets.None) then p-=Gui:GetGuiInset() end
    local a,s=self.card.AbsolutePosition,self.card.AbsoluteSize
    return p.X>=a.X and p.Y>=a.Y and p.X<=a.X+s.X and p.Y<=a.Y+s.Y
end
function Handle:setEquipped(value: boolean) if self.state.equipped~=value then self.state.equipped=value;self:_apply() end end
function Handle:setDisabled(value: boolean)
    if self.state.disabled~=value then self.state.disabled=value;if value then self.state.pressed=false end;self:_apply() end
end
function Handle:setSet(color: Color3) self.style.set=color;self:_apply() end
function Handle:setSelected(value: boolean) if self.state.selected~=value then self.state.selected=value;self:_apply() end end
function Handle:_apply(instant: boolean?)
    if self.destroyed then return end
    local ring=self.ringStroke
    -- the ring's own colour is the live accent (the accent system recolours it), except while the
    -- kit has painted it gold for a selection
    if ring and not self.ringGold then self.style.accent=ring.Color end
    local look=Math.look(self.state,self.style)
    local reduced=instant==true or self.kit:reduced()
    local base,scaleTime,ease=Math.timing(self.wasPressed,self.state.pressed==true,reduced)
    self.wasPressed=self.state.pressed==true
    local info=TweenInfo.new(base,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    local scaleInfo=TweenInfo.new(scaleTime,Enum.EasingStyle[ease],Enum.EasingDirection.Out)
    local function set(node: Instance?, props: {[string]: any}, how: TweenInfo?)
        if not node then return end
        local tweenInfo=how or info
        if tweenInfo.Time<=0 then for k,v in props do (node :: any)[k]=v end
        else Tween:Create(node,tweenInfo,props):Play() end
    end
    local bb=self.bodyBase
    set(self.body,{Position=UDim2.new(bb.X.Scale,bb.X.Offset,bb.Y.Scale,bb.Y.Offset-look.lift),BackgroundColor3=look.fill})
    set(self.stroke,{Color=look.stroke,Thickness=look.thickness})
    set(self.scale,{Scale=look.scale},scaleInfo)
    set(self.glow,{ImageTransparency=look.glow,ImageColor3=look.glowColor})
    if self.shadow then set(self.shadow,{ImageTransparency=look.shadow,Position=self.shadowBase+UDim2.fromOffset(0,look.drop)}) end
    if ring then
        local gold=look.ringRole=="selected"
        if gold~=(self.ringGold==true) then
            self.ringGold=gold;ring.Color=if gold then Math.SELECTED_RING else self.style.accent -- the flag first: the gold guard watches Color
        end
    end
    set(ring,{Transparency=look.ring})
    set(self.zoom,{Scale=look.zoom})
    if self.onLook then task.spawn(self.onLook,self,look) end
end
function Handle:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.kit.cards[self.card]==self then self.kit.cards[self.card]=nil end
end
return Kit
