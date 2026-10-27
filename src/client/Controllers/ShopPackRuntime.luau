--!strict
-- PF016: shared runtime for the Forge Starter / Aurora shop cards. Animates only
-- while the card is actually on screen (and the Shop page is open), at ~30 fps on
-- one Heartbeat, honours ReducedMotion/StaticBackground, and follows the single real
-- card.Purchase button for hover/focus/press (visual layers never take input).
-- Debug/capture hook: scene attribute PF016Clock (and PF016PressAge) freezes the
-- drawn frame at that time so frame strips are exact; nil = live.
local Run=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local Visibility=require(script.Parent.ForgeVisibility)
local Runtime={};Runtime.__index=Runtime
local ROBUX=utf8.char(0xE002) -- Roblox's Robux glyph (Ubuntu Bold draws it inline at digit height)
-- PF017: the pack button label for the page's truthful purchase state (the page
-- publishes the price as text: a number, "--" or "Owned"). Returns the text and
-- whether it is a live price.
function Runtime.priceLabel(state: any): (string,boolean)
    local purchaseState,price=state.purchaseState,state.priceText
    if purchaseState=="Owned" then return "✓ Owned",false end
    if purchaseState=="Loading" or purchaseState=="Updating" then return "…",false end
    if type(price)=="string" and string.match(price,"^%d[%d,]*$") then return ROBUX.." "..price,true end
    return "Unavailable",false
end
export type Draw=(clock: number,state: any)->()
function Runtime.new(card: GuiObject,scene: GuiObject,menuRoot: Instance,context: any,draw: Draw,extraRoots: {GuiObject}?)
    local self=setmetatable({card=card,scene=scene,menuRoot=menuRoot,context=context,drawFn=draw,clock=0,accumulator=0,
        visible=false,destroyed=false,connections={},state={hot=false,pressAge=nil::number?,pressed=false,enabled=true}},Runtime)
    local purchase=card:FindFirstChild("Purchase") :: GuiButton?
    self.purchase=purchase
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    if purchase then
        listen(purchase.MouseEnter,function() self.state.hot=true;self:sync() end)
        listen(purchase.MouseLeave,function() self.state.hot=GuiService.SelectedObject==purchase;self:sync() end)
        listen(purchase.SelectionGained,function() self.state.hot=true;self:sync() end)
        listen(purchase.SelectionLost,function() self.state.hot=false;self:sync() end)
        listen(purchase.InputBegan,function(input: InputObject)
            local kind=input.UserInputType
            if kind==Enum.UserInputType.MouseButton1 or kind==Enum.UserInputType.Touch
                or (input.KeyCode==Enum.KeyCode.ButtonA and GuiService.SelectedObject==purchase) then self:press() end
        end)
        for _,property in {"Active","Selectable"} do listen(purchase:GetPropertyChangedSignal(property),function() self:refreshState() end) end
        -- PF017: the page publishes the price as text (PriceText); the pack layer draws it.
        for _,attribute in {"PurchaseState","PriceText"} do listen(purchase:GetAttributeChangedSignal(attribute),function() self:refreshState() end) end
    end
    for _,attribute in {"ReducedMotion","StaticBackground","AtlasPage"} do listen(menuRoot:GetAttributeChangedSignal(attribute),function() self:sync() end) end
    for _,attribute in {"PF016Clock","PF016PressAge"} do listen(scene:GetAttributeChangedSignal(attribute),function() self:draw() end) end
    listen(scene:GetAttributeChangedSignal("PF016ForceEnabled"),function() self:refreshState() end)
    listen(card.Destroying,function() self:destroy() end)
    local roots={card,scene};for _,root in extraRoots or {} do table.insert(roots,root) end
    self.observer=Visibility.watch(roots,function() self:sync() end)
    self:refreshState();self:draw();self:sync()
    return self
end
-- Truthful mirror of PF - 3's purchase binding: Active is canBuy (false without a real
-- Pass/price, and always false in Studio). PurchaseState is shown as-is ("Owned", ...).
-- Studio-only capture override: scene PF016ForceEnabled shows the buyable look.
function Runtime:refreshState()
    local purchase=self.purchase
    if purchase then
        local forced=Run:IsStudio() and self.scene:GetAttribute("PF016ForceEnabled")==true
        self.state.enabled=purchase.Active or forced
        self.state.purchaseState=purchase:GetAttribute("PurchaseState")
        self.state.priceText=purchase:GetAttribute("PriceText")
    end
    self:draw()
end
function Runtime:press()
    -- Reduced motion (or hidden): no press animation. Nothing would advance the age,
    -- so an age-0 frame would strand the burst on the button.
    if not (self:isShown() and self:motion()) then return end
    self.state.pressAge=0;self.state.pressed=true;self:sync();self:draw()
end
function Runtime:isShown(): boolean
    if self.destroyed or not self.visible or not self.scene.Parent then return false end
    local page=self.menuRoot:GetAttribute("AtlasPage")
    if page~=nil and page~="Shop" then return false end
    return Visibility.isShown(self.scene,nil)
end
function Runtime:motion(): boolean
    local reduced=(self.context.reducedMotion and self.context.reducedMotion()) or self.menuRoot:GetAttribute("ReducedMotion")==true
    return not reduced and self.menuRoot:GetAttribute("StaticBackground")~=true
end
function Runtime:draw()
    if self.destroyed or not self.scene.Parent then return end
    local frozen=self.scene:GetAttribute("PF016Clock")
    local clock=if type(frozen)=="number" then frozen else self.clock
    local frozenPress=self.scene:GetAttribute("PF016PressAge")
    local state=self.state
    if type(frozenPress)=="number" then state=table.clone(self.state);state.pressAge=frozenPress end
    self.drawFn(clock,state)
end
function Runtime:sync()
    if self.destroyed then return end
    local animate=self:isShown() and self:motion()
    if animate and not self.running then
        self.running=Run.Heartbeat:Connect(function(dt: number)
            if self.destroyed then return end
            self.accumulator+=dt
            if self.accumulator<1/30 then return end
            local step=math.min(self.accumulator,.1);self.accumulator=0
            self.clock+=step
            if self.state.pressAge then
                self.state.pressAge+=step
                if self.state.pressAge>1.6 then self.state.pressAge=nil;self.state.pressed=false end
            end
            if not (self:isShown() and self:motion()) then self:sync() return end
            self:draw()
        end)
    elseif not animate and self.running then
        self.running:Disconnect();self.running=nil;self.accumulator=0
        self.state.pressAge=nil;self.state.pressed=false;self:draw()
    end
    self.scene:SetAttribute("Animating",animate)
end
function Runtime:setVisible(value: boolean)
    if self.destroyed then return end
    self.visible=value;self:sync()
end
function Runtime:destroy()
    if self.destroyed then return end
    self.destroyed=true
    if self.running then self.running:Disconnect();self.running=nil end
    if self.observer then self.observer:destroy();self.observer=nil end
    for _,connection in self.connections do connection:Disconnect() end
    table.clear(self.connections)
    if self.scene.Parent then self.scene:SetAttribute("Animating",false) end
end
return Runtime
