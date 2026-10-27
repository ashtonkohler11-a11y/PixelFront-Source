--!strict
-- Authored, bounded feedback only. No command dispatch, values, or static UI generation.
local TweenService=game:GetService("TweenService")
local GuiService=game:GetService("GuiService")
local Theme=require(script.Parent.BattleHudTheme)
local Presentation={};Presentation.__index=Presentation
local function visible(item: Instance): boolean
    local node: Instance?=item
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node=node.Parent
    end
    return item.Parent~=nil
end
function Presentation.new(gui: ScreenGui): any
    local self=setmetatable({gui=gui,root=gui.Background.Game,connections={},tweens={},buttons={},blocked=false,destroyed=false},Presentation)
    local function listen(signal: RBXScriptSignal,fn: any)
        table.insert(self.connections,signal:Connect(function(...)
            if not self.destroyed then fn(...) end
        end))
    end
    self.listen=listen
    self.motionRoots={gui,gui.Background,self.root}
    local atlas=gui.Background:FindFirstChild("AtlasMenu")
    if atlas then table.insert(self.motionRoots,atlas) end
    for _,item in self.root:GetDescendants() do
        if item:IsA("GuiButton") and item:GetAttribute("PFHudButton")==true then self:bindButton(item) end
    end
    listen(self.root.DescendantAdded,function(item)
        if item:IsA("GuiButton") and item:GetAttribute("PFHudButton")==true then self:bindButton(item) end
    end)
    listen(GuiService:GetPropertyChangedSignal("SelectedObject"),function()
        for item in self.buttons do self:refreshButton(item) end
    end)
    for _,node in self.motionRoots do
        for _,name in {"ReducedMotion","Static","StaticBackground","MotionEnabled"} do
            listen(node:GetAttributeChangedSignal(name),function() self:sync() end)
        end
        if node:IsA("GuiObject") then listen(node:GetPropertyChangedSignal("Visible"),function() self:sync() end) end
    end
    listen(gui:GetPropertyChangedSignal("Enabled"),function() self:sync() end)
    listen(self.root.Controls:GetPropertyChangedSignal("Visible"),function() self:sync() end)
    local gain=self.root.Controls.Gold.Gain
    listen(gain:GetPropertyChangedSignal("Visible"),function()
        if gain.Visible and self:canAnimate() then self:glint() end
    end)
    self.glintThread=task.spawn(function()
        while not self.destroyed do
            task.wait(11)
            if self:canAnimate() then self:glint() end
        end
    end)
    self:sync();return self
end
function Presentation:canAnimate(): boolean
    if self.destroyed or self.blocked or not visible(self.root.Controls) then return false end
    for _,node in self.motionRoots do
        if node:GetAttribute("ReducedMotion")==true or node:GetAttribute("Static")==true
            or node:GetAttribute("StaticBackground")==true or node:GetAttribute("MotionEnabled")==false then return false end
    end
    if self.preferences then
        local values=self.preferences:snapshot()
        if values["settings.reducedMotion"]=="true" or values["settings.staticBackground"]=="true"
            or values["settings.motionEnabled"]=="false" then return false end
    end
    return true
end
function Presentation:tween(item: Instance,props: any,duration: number)
    local old=self.tweens[item]
    if old then old.tween:Cancel();old.connection:Disconnect();self.tweens[item]=nil end
    if not self:canAnimate() or not visible(item) then for key,value in props do (item :: any)[key]=value end;return end
    local tween=TweenService:Create(item,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props)
    -- Deferred Destroying signals run after descendants have lost Parent.
    -- Capture ownership while the tree is alive rather than reconstructing it
    -- during retirement from IsDescendantOf on already destroyed children.
    local owner: Instance?=item
    while owner and not self.buttons[owner] do owner=owner.Parent end
    local record: any={tween=tween,owner=owner}
    record.connection=tween.Completed:Connect(function()
        record.connection:Disconnect()
        if self.tweens[item]==record then self.tweens[item]=nil end
    end)
    self.tweens[item]=record;tween:Play()
end
function Presentation:bindButton(item: GuiButton)
    if self.buttons[item] then return end
    local state: any={hovered=false,pressed=false,connections={}};self.buttons[item]=state
    local function listen(signal: RBXScriptSignal,callback: any)
        table.insert(state.connections,signal:Connect(function(...) if not self.destroyed then callback(...) end end))
    end
    local function refresh() self:refreshButton(item) end
    listen(item.MouseEnter,function() state.hovered=true;refresh() end)
    listen(item.MouseLeave,function() state.hovered=false;state.pressed=false;refresh() end)
    listen(item.MouseButton1Down,function() state.pressed=true;refresh() end)
    listen(item.MouseButton1Up,function() state.pressed=false;refresh() end)
    for _,name in {"BlueprintSelected","Affordable","HudUnavailableReason","Hovered","HudBlocked","PFHotbarLift"} do
        listen(item:GetAttributeChangedSignal(name),function()
            task.defer(function() if not self.destroyed and item.Parent then refresh() end end)
        end)
    end
    listen(item:GetPropertyChangedSignal("Visible"),refresh)
    listen(item.Destroying,function()
        self.buttons[item]=nil
        for _,connection in state.connections do connection:Disconnect() end;table.clear(state.connections)
        for target,record in self.tweens do
            if target==item or record.owner==item then record.tween:Cancel();record.connection:Disconnect();self.tweens[target]=nil end
        end
    end)
    refresh()
end
function Presentation:refreshButton(item: GuiButton)
    local state=self.buttons[item];if not state or not item.Parent then return end
    local selected=item:GetAttribute("BlueprintSelected")==true
    local focus=GuiService.SelectedObject==item
    local hovered=(state.hovered or item:GetAttribute("Hovered")==true or focus) and visible(item) and not self.blocked
    -- PF012: a slot missing a real prerequisite is blacked out at rest.
    local base=if item:GetAttribute("HudBlocked")==true then Theme.Blocked else item:GetAttribute("RestColor") or Theme.Raised
    -- PF020: the console hotbar's selected slot is raised (scaled up) and lit brighter.
    local lifted=selected and item:GetAttribute("PFHotbarLift")==true
    local color=if lifted then Theme.Raised:Lerp(Theme.Cobalt,.42) elseif selected then Theme.Raised:Lerp(Theme.Cobalt,.24) elseif hovered then base:Lerp(Theme.Cobalt,.16) else base
    self:tween(item,{BackgroundColor3=color},Theme.HoverTime)
    -- PF - 4 UI review (rule 2, centre-anchored press/lift): in a list / grid layout a UIScale on the slot grows its
    -- footprint (the row reflows and a press jiggles its neighbours), so a laid-out slot scales its Icon
    -- (tools/atlas/author-pf4-hud-iconscale.luau: centre-anchored, PFIconScale) and keeps its own Scale at 1
    local scale=item:FindFirstChild("Scale")
    local icon=item:FindFirstChild("Icon");local iconScale=icon and icon:FindFirstChild("PFIconScale")
    local laid=item.Parent~=nil and item.Parent:FindFirstChildWhichIsA("UIGridStyleLayout")~=nil
    if laid and iconScale and iconScale:IsA("UIScale") then
        if scale and scale:IsA("UIScale") and scale.Scale~=1 then scale.Scale=1 end
        self:tween(iconScale,{Scale=if state.pressed and hovered then .9 elseif lifted then 1.12 else 1},Theme.PressTime)
    elseif scale and scale:IsA("UIScale") then self:tween(scale,{Scale=if state.pressed and hovered then .97 elseif lifted then 1.08 else 1},Theme.PressTime) end
    local border=item:FindFirstChild("Border")
    if border and border:IsA("UIStroke") then border.Color=if selected then Theme.Cobalt elseif focus then Theme.Gold else Theme.Border;border.Thickness=if selected or focus then 2 else 1 end
    local focusBorder=item:FindFirstChild("FocusBorder")
    if focusBorder and focusBorder:IsA("UIStroke") then focusBorder.Color=Theme.Gold;focusBorder.Enabled=focus and visible(item) end
    local rail=item:FindFirstChild("PFSelectionRail")
    if rail and rail:IsA("Frame") then self:tween(rail,{BackgroundTransparency=if selected then 0 elseif hovered then .45 else 1},Theme.SelectTime) end
    local field=item:FindFirstChild("PFHoverField")
    if field then for index=1,6 do local tile=field:FindFirstChild("Tile"..index)
        if tile and tile:IsA("Frame") then
            self:tween(tile,{BackgroundTransparency=if selected then .88 elseif hovered then .83 else 1},Theme.HoverTime+index*.018)
        end
    end end
    -- PF012: the red price and the blacked-out slot replace the old corner dot.
    local unavailable=item:FindFirstChild("PFUnavailable")
    if unavailable and unavailable:IsA("Frame") then unavailable.Visible=false end
end
function Presentation:glint()
    if not self:canAnimate() or os.clock()-(self.lastGlint or -math.huge)<.8 then return end
    self.lastGlint=os.clock()
    local coin=self.root.Controls.Gold:FindFirstChild("PFCoin")
    local shine=coin and coin:FindFirstChild("Shine")
    if shine and shine:IsA("Frame") then
        shine.BackgroundTransparency=1
        self:tween(shine,{BackgroundTransparency=.05},.14)
        task.delay(.2,function()
            if not self.destroyed and shine.Parent then self:tween(shine,{BackgroundTransparency=1},.35) end
        end)
    end
end
function Presentation:setPreferences(preferences: any)
    if self.preferences==preferences then self:sync();return end
    if self.unsubscribe then self.unsubscribe() end
    self.preferences=preferences
    self.unsubscribe=preferences:subscribe(function() self:sync() end)
    self:sync()
end
function Presentation:setBlocked(value: boolean)
    if self.blocked==value then return end;self.blocked=value;self:sync()
end
function Presentation:sync()
    if self.destroyed then return end
    local run=self:canAnimate();self.root:SetAttribute("PFHudMotionRunning",run)
    if not run then
        for item,record in self.tweens do record.tween:Cancel();record.connection:Disconnect();self.tweens[item]=nil end
        local coin=self.root.Controls.Gold:FindFirstChild("PFCoin");local shine=coin and coin:FindFirstChild("Shine")
        if shine and shine:IsA("Frame") then shine.BackgroundTransparency=1 end
        for item,state in self.buttons do state.pressed=false;state.hovered=false;self:refreshButton(item) end
    end
end
function Presentation:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.glintThread then task.cancel(self.glintThread) end
    if self.unsubscribe then self.unsubscribe() end
    for _,connection in self.connections do connection:Disconnect() end
    for _,state in self.buttons do for _,connection in state.connections do connection:Disconnect() end end
    for _,record in self.tweens do record.tween:Cancel();record.connection:Disconnect() end
    table.clear(self.tweens);table.clear(self.buttons);table.clear(self.connections)
end
return Presentation
