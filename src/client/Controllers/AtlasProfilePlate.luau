--!strict
-- PF023 P1 (PF - 1): fills an authored profile plate (tools/atlas/author-pf023-profile-plate.luau): the
-- lobby's top-right Header.PFRight.Profile and the large copy in Screens.Profile. Content, states and
-- motion only; the layout is authored (Edit == Play).
--   Art: the banner backdrop, the frame round the avatar, the crown (+ its soft drop), the flag
--   (AtlasCommerceArt.bindProfile, so custom flags and idle loops behave as everywhere else).
--   Level: PIVOT D15 removed Levels; the authored badge, LEVEL row and XP bar stay hidden (hideLevel).
--   Chips: skin, effect, buildings, Nuke FX; "+" when a slot is empty; hover names it; tap opens it.
--   States (the approved board): hover lifts 2 px, mint→violet rim + soft glow, banner brighter
--   (.15 s Quad Out); press scales .98 and darkens 12% (.08 s), release springs back and opens.
--   Reduced motion: no lift/scale tweens (states snap), idle art holds frame 0 (CosmeticIdleAnimator).
local Tween=game:GetService("TweenService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog=require(Shared:WaitForChild("CosmeticCatalog"))
local Art=require(script.Parent.CosmeticArt)
local ProfileArt=require(script.Parent.AtlasCommerceArt)
local Plate={};Plate.__index=Plate
local HOVER=TweenInfo.new(.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local PRESS=TweenInfo.new(.08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local SPRING=TweenInfo.new(.14,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local CHIPS={"Skin","VFX","Buildings","Missiles"}
local WHITE=Color3.new(1,1,1)
local TITLE_INK,HANDLE_INK=Color3.fromHex("#cfe1ff"),Color3.fromHex("#b9c8da")

-- displayOnly (Ashton: "remove the hover/click on the top right profile thing"): the plate only shows; no hover, press,
-- click or gamepad selection on it or its chips.
export type Options={onOpen: (() -> ())?,onChip: ((category: string) -> ())?,reducedMotion: (() -> boolean)?,displayOnly: boolean?}

local function find(root: Instance,name: string): any return root:FindFirstChild(name,true) end
local function valid(id: any,category: string): boolean
    return type(id)=="string" and Catalog.byId[id]~=nil and Catalog.byId[id].category==category
end

function Plate.new(root: GuiButton,options: Options?): any
    local self: any=setmetatable({root=root,options=options or {},connections={},hovered=false,pressed=false,destroyed=false,level=nil},Plate)
    self.lift=root:FindFirstChild("Lift")
    -- its authored rest position (UI review 2026-10-26: Lift is centre-anchored so the press scale grows from the centre)
    self.liftBase=if self.lift then (self.lift :: GuiObject).Position else UDim2.new()
    self.press=self.lift and self.lift:FindFirstChild("PFPress")
    self.shade=find(root,"PressShade");self.scrim=find(root,"Scrim");self.glow=root:FindFirstChild("HoverGlow")
    self.rim=find(root,"RimStroke");self.rimTint=self.rim and self.rim:FindFirstChild("RimTint")
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    if self.options.displayOnly then
        local function inert(item: Instance) if item:IsA("GuiObject") then item.Active=false;item.Selectable=false end;if item:IsA("GuiButton") then item.AutoButtonColor=false end end
        inert(root);for _,d in root:GetDescendants() do if d:IsA("GuiButton") then inert(d) end end
        self:hideLevel()
        return self
    end
    listen(root.MouseEnter,function() self:setHover(true) end)
    listen(root.MouseLeave,function() self:setHover(false);self:setPress(false) end)
    listen(root.SelectionGained,function() self:setHover(true) end)
    listen(root.SelectionLost,function() self:setHover(false) end)
    listen(root.MouseButton1Down,function() self:setPress(true) end)
    listen(root.MouseButton1Up,function() self:setPress(false) end)
    listen(root.Activated,function()
        self:setPress(false)
        if self.options.onOpen then self.options.onOpen() end
    end)
    local chips=find(root,"Chips")
    for _,name in CHIPS do
        local chip=chips and chips:FindFirstChild(name)
        if not chip or not chip:IsA("GuiButton") then continue end
        local tip=chip:FindFirstChild("Tip")
        listen(chip.MouseEnter,function() if tip then tip.Visible=true end end)
        listen(chip.MouseLeave,function() if tip then tip.Visible=false end end)
        listen(chip.SelectionGained,function() if tip then tip.Visible=true end end)
        listen(chip.SelectionLost,function() if tip then tip.Visible=false end end)
        listen(chip.Activated,function()
            if tip then tip.Visible=false end
            if self.options.onChip then self.options.onChip(name) end
        end)
    end
    self:hideLevel()
    return self
end

function Plate:reduced(): boolean
    local check=self.options.reducedMotion
    return check~=nil and check()==true
end
function Plate:tween(target: Instance?,info: TweenInfo,goal: {[string]: any})
    if not target then return end
    if self:reduced() then for k,v in goal do (target :: any)[k]=v end;return end
    Tween:Create(target,info,goal):Play()
end
function Plate:setHover(on: boolean)
    if self.destroyed or self.hovered==on then return end
    self.hovered=on
    self:tween(self.lift,HOVER,{Position=self.liftBase+UDim2.fromOffset(0,if on and not self:reduced() then -2 else 0)})
    if self.rim then self:tween(self.rim,HOVER,{Transparency=if on then 0 else .84,Thickness=if on then 1.5 else 1}) end
    if self.rimTint then self.rimTint.Enabled=on end
    if self.rim then self.rim.Color=WHITE end
    self:tween(self.glow,HOVER,{BackgroundTransparency=if on then 0 else 1})
    -- the banner reads ~12% brighter: the scrim thins over it
    self:tween(self.scrim,HOVER,{BackgroundTransparency=if on then .22 else 0})
end
function Plate:setPress(on: boolean)
    if self.destroyed or self.pressed==on then return end
    self.pressed=on
    self:tween(self.press,if on then PRESS else SPRING,{Scale=if on then .98 else 1})
    self:tween(self.shade,PRESS,{BackgroundTransparency=if on then .88 else 1})
end

-- identity: {userId, displayName, name, equipped, cosmetics} (the integrator's authenticated profile).
function Plate:bind(identity: any)
    if self.destroyed then return end
    local root=self.root
    identity=if type(identity)=="table" then identity else {}
    ProfileArt.bindProfile(root,identity)
    local equipped=if type(identity.equipped)=="table" then identity.equipped else {}
    -- under the name: the worn Title in small caps (L2b "Wear title" puts it here), else the @handle
    local detail=find(root,"Detail")
    if detail and detail:IsA("TextLabel") then
        local title=if valid(equipped.Title,"Title") then Catalog.byId[equipped.Title] else nil
        detail.Text=if title then string.upper(title.name) elseif type(identity.name)=="string" then "@"..identity.name else ""
        detail.TextColor3=if title then TITLE_INK else HANDLE_INK
    end
    -- the crown's soft drop mirrors the crown (same idle loop, drawn black at 45%)
    local crown,shadow=find(root,"Crown"),find(root,"CrownShadow")
    if shadow and shadow:IsA("ImageLabel") then
        local id=equipped.Crown
        if crown and crown.Visible and valid(id,"Crown") then
            Art.bind(shadow,id);shadow.ImageColor3=Color3.new(0,0,0);shadow.ImageTransparency=.45
            local from,to=crown:FindFirstChild("ProfileArtAspect"),shadow:FindFirstChild("ProfileArtAspect")
            if from and to then (to :: any).AspectRatio=(from :: any).AspectRatio end
        else Art.bind(shadow,nil) end
    end
    -- no frame equipped: a thin rim keeps the avatar box tidy
    local frameArt,avatarRim=find(root,"FrameArt"),find(root,"AvatarRim")
    if avatarRim then avatarRim.Enabled=not (frameArt and frameArt.Visible) end
    -- the bar plate (PF023 v4) shows only what you wear: an empty slot hides; the Profile sheet's plate keeps its "+" chips
    local bar=root:GetAttribute("PF023BarPlate")==true
    local chips=find(root,"Chips")
    for _,name in CHIPS do
        local chip=chips and chips:FindFirstChild(name)
        if not chip then continue end
        local id=equipped[name]
        local on=valid(id,name)
        if bar then chip.Visible=on end
        local art=chip:FindFirstChild("Art")
        if art and art:IsA("ImageLabel") then Art.bind(art,if on then id else nil);art.ScaleType=Enum.ScaleType.Crop end
        local plus=chip:FindFirstChild("Plus");if plus then plus.Visible=not on end
        local tip=chip:FindFirstChild("Tip")
        local item=tip and tip:FindFirstChild("Item")
        if item then item.Text=if on then Catalog.byId[id].name.." · tap to change" else "Get one in the Shop" end
    end
end

-- PIVOT D15: Levels are removed; the authored badge (Level, PF043's LevelMini), LEVEL row and XP bar stay hidden.
function Plate:hideLevel()
    for _,name in {"Level","LevelMini","LevelRow","XpTrack"} do
        local node=find(self.root,name)
        if node and node:IsA("GuiObject") then node.Visible=false end
    end
end

function Plate:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    table.clear(self.connections)
    ProfileArt.unbindProfile(self.root)
end

return Plate
