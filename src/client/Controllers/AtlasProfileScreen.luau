--!strict
-- PF023 P1 (PF - 1): Screens.Profile, opened by tapping the lobby's top-right plate (approved board P1:
-- "your equipped look, one tap per slot to change it"). Left: the same plate, large (PIVOT D15: the level
-- panel stays hidden; Levels are removed). Right: the eight slots (Banner, Frame, Crown, Flag / Skin, Effect, Buildings, Nuke FX); a tap opens that slot's
-- Inventory tab. Layout authored (tools/atlas/author-pf023-profile-plate.luau); content only here.
local Gui=game:GetService("GuiService")
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog=require(Shared:WaitForChild("CosmeticCatalog"))
local Art=require(script.Parent.CosmeticArt)
local PlateView=require(script.Parent.AtlasProfilePlate)
local Screen={};Screen.__index=Screen
local ORDER={"Banner","Frame","Crown","Flag","Skin","VFX","Buildings","Missiles"}
local GOLD,LINE=Color3.fromHex("#ddbf76"),Color3.fromHex("#3a3a3a")

function Screen.new(root: Frame,context: any): any
    -- Profile v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-profile-v2.luau): the plate + 3 x 3 locker take over while authored
    if root:FindFirstChild("PFProfileV2") then return require(script.Parent.AtlasProfileV2).new(root,context) end
    local self: any=setmetatable({root=root,context=context,connections={},visible=false,destroyed=false,tiles={}},Screen)
    local body=root:WaitForChild("Body")
    local left,right=body:WaitForChild("Left"),body:WaitForChild("Right")
    local levelPanel=left:FindFirstChild("LevelPanel")
    if levelPanel and levelPanel:IsA("GuiObject") then levelPanel.Visible=false end
    self.plate=PlateView.new(left:WaitForChild("Plate") :: any,{
        onOpen=nil,
        onChip=function(category) self:open(category) end,
        reducedMotion=context.reducedMotion})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    listen(root.Header.Back.Activated,function() if context.back then context.back() end end)
    for _,row in right:GetChildren() do
        if not row:IsA("Frame") then continue end
        for _,tile in row:GetChildren() do
            if not tile:IsA("TextButton") then continue end
            self.tiles[tile.Name]=tile
            local rim=tile:FindFirstChild("PFStroke")
            listen(tile.Activated,function() self:open(tile:GetAttribute("Category")) end)
            listen(tile.MouseEnter,function() if rim then rim.Color=GOLD end end)
            listen(tile.MouseLeave,function() if rim then rim.Color=LINE end end)
            listen(tile.SelectionGained,function() if rim then rim.Color=GOLD end end)
            listen(tile.SelectionLost,function() if rim then rim.Color=LINE end end)
        end
    end
    self:refresh()
    return self
end

function Screen:open(category: any)
    if type(category)~="string" then return end
    if self.context.openSlot then self.context.openSlot(category) end
end

-- The authenticated look comes from the shop state (the same record the Inventory shows).
function Screen:refresh()
    if self.destroyed then return end
    local player=Players.LocalPlayer
    local state=if self.context.getCommerce then self.context.getCommerce() else nil
    local profile=if type(state)=="table" and type(state.profile)=="table" then state.profile else {}
    local equipped=if type(profile.equipped)=="table" then profile.equipped else {}
    self.plate:bind({userId=player.UserId,displayName=player.DisplayName,name=player.Name,equipped=equipped,cosmetics=profile.identityCosmetics})
    for _,slot in ORDER do
        local tile=self.tiles[slot];if not tile then continue end
        local id=equipped[slot]
        local item=if type(id)=="string" then Catalog.byId[id] else nil
        local on=item~=nil and item.category==slot
        local art=tile:FindFirstChild("Art")
        if art and art:IsA("ImageLabel") then Art.bind(art,if on then id else nil) end
        local plus=tile:FindFirstChild("Plus");if plus then plus.Visible=not on end
        local name=tile:FindFirstChild("ItemName")
        if name then name.Text=if on and item then item.name elseif slot=="Missiles" then "Get one in the Shop" else "None" end
    end
end

function Screen:update(_model: any)
    if self.visible then self:refresh() end
end
function Screen:setVisible(value: boolean)
    self.visible=value
    if value then self:refresh() end
end
function Screen:focusActive()
    local first=self.tiles.Banner
    if first then Gui.SelectedObject=first end
end
function Screen:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    table.clear(self.connections)
    self.plate:destroy()
end

return Screen
