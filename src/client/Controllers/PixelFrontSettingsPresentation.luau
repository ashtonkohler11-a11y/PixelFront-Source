--!strict
-- Authored frontier pixels/diagonal/gold details; only active visible surfaces tick.
local RunService=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local Accent=require(game:GetService("ReplicatedStorage").Shared.PixelFrontAccent)
local Presentation={};Presentation.__index=Presentation
local function visible(node: Instance,root: Instance): boolean
    if node~=root and not node:IsDescendantOf(root) then return false end
    local current: Instance?=node
    while current do
        if current:GetAttribute("PFSettingRetired")==true then return false end
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        if current:IsA("GuiObject") and current~=node and (current.ClipsDescendants or current:IsA("ScrollingFrame")) then
            local p,s=node.AbsolutePosition,node.AbsoluteSize;local q,t=current.AbsolutePosition,current.AbsoluteSize
            if p.X+s.X<=q.X or p.Y+s.Y<=q.Y or p.X>=q.X+t.X or p.Y>=q.Y+t.Y then return false end
        end
        current=current.Parent
    end
    return true
end
function Presentation.new(root: Instance,settings: any): any
    local self=setmetatable({root=root,settings=settings,items={},connections={},clock=0,destroyed=false},Presentation)
    local function watch(node: Instance)
        if not node:IsA("GuiButton") or self.items[node] or node.Name=="Backdrop" then return end
        local art=node:FindFirstChild("PF011Frontier")
        if not art or art:GetAttribute("PF011Owner")~="PF011Settings" then return end
        local item={node=node,art=art,hover=false,pressed=false,amount=0,connections={}}
        self.items[node]=item
        local function hook(signal: RBXScriptSignal,fn: any) table.insert(item.connections,signal:Connect(fn)) end
        hook(node.MouseEnter,function()item.hover=true;self:wake()end)
        hook(node.MouseLeave,function()item.hover=false;item.pressed=false;self:wake()end)
        hook(node.SelectionGained,function()self:wake()end);hook(node.SelectionLost,function()self:wake()end)
        hook(node.InputBegan,function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then item.pressed=true;self:wake()end end)
        hook(node.InputEnded,function()item.pressed=false;self:wake()end)
        hook(node:GetAttributeChangedSignal("PFSelected"),function()self:wake()end)
        hook(node.Destroying,function()for _,c in item.connections do c:Disconnect()end;self.items[node]=nil end)
    end
    for _,node in root:GetDescendants() do watch(node) end
    table.insert(self.connections,root.DescendantAdded:Connect(watch))
    table.insert(self.connections,root.Destroying:Connect(function()self:dispose()end))
    return self
end
function Presentation:wake()
    if self.destroyed or self.tick then return end
    self.tick=RunService.Heartbeat:Connect(function(dt)self:step(math.min(dt,.05))end)
end
function Presentation:step(dt: number)
    self.clock+=dt;local moving=false
    for node,item in self.items do
        local shown=visible(node,self.root)
        local target=if shown and node.Active and (item.hover or GuiService.SelectedObject==node or node:GetAttribute("PFSelected")==true) then 1 else 0
        local amount=item.amount+(target-item.amount)*math.min(1,dt*18)
        if math.abs(amount-target)<.01 then amount=target else moving=true end
        if not shown then amount=0;item.hover=false;item.pressed=false end
        item.amount=amount;item.art.Visible=shown and amount>0
        local band=item.art:FindFirstChild("Band")
        if band then band.BackgroundColor3=Accent.color(self.settings,"accent");band.BackgroundTransparency=1-amount*(if item.pressed then .2 else .09) end
        for i=1,8 do local pixel=item.art:FindFirstChild("Pixel"..i)
            if pixel then
                pixel.BackgroundColor3=Accent.color(self.settings,"focus")
                pixel.BackgroundTransparency=1-math.clamp(amount*8-(i-1),0,1)*.75
            end
        end
        local gold=item.art:FindFirstChild("Gold");if gold then gold.BackgroundTransparency=1-amount*.8 end
    end
    if not moving and self.tick then self.tick:Disconnect();self.tick=nil end
end
function Presentation:refresh()
    -- Refresh also resets hidden hover without a permanent Heartbeat.
    self:step(0);self:wake()
end
function Presentation:dispose()
    if self.destroyed then return end;self.destroyed=true
    if self.tick then self.tick:Disconnect();self.tick=nil end
    for _,c in self.connections do c:Disconnect() end
    for _,item in self.items do
        if item.art.Parent then item.art.Visible=false end
        for _,c in item.connections do c:Disconnect()end
    end
    self.items={}
end
return Presentation
