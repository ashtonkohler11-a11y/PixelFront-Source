--!strict
-- Source-backed City/Port build configuration: BuildMenu, MainRadialMenu,
-- RadialMenuElements, InputHandler and BuildPreviewController at 93a136a.
local Economy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontEconomy)
local Ports=require(game:GetService("ReplicatedStorage").Shared.OpenFrontPorts)
local Warships=require(game:GetService("ReplicatedStorage").Shared.OpenFrontWarships)
local Structures=require(game:GetService("ReplicatedStorage").Shared.OpenFrontStructures)
local Rails=require(game:GetService("ReplicatedStorage").Shared.OpenFrontRails)
local Weapons=require(game:GetService("ReplicatedStorage").Shared.OpenFrontWeapons)
local Nukes=require(game:GetService("ReplicatedStorage").Shared.OpenFrontNukes)
local GameConfig=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGameConfig)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local DP=require(script.Parent.DiplomacyPresentation)
local ActionModel=require(script.Parent.PlayerActionsModel) -- PF022: disabled-slice reasons
local Icons=require(script.Parent.ReferenceIcons)
local BuildingRenderer=require(script.Parent.BuildingRenderer)
-- UI audit build-out 2026-10-28: the shared motion kit (PF - 4's UiMotion); nil where it can't load (test fakes)
local Motion: any=(function() local ok,mod=pcall(function() return require(script.Parent.UiMotion) end);return if ok and type(mod)=="table" and type(mod.tween)=="function" then mod else nil end)()
-- PF - 3's HitZone: a key's Activated, also from its invisible finger-zone strips (falls back to the key alone in test fakes)
local HitZone: any=(function() local ok,mod=pcall(function() return require(script.Parent.HitZone) end);return if ok and type(mod)=="table" and type(mod.signal)=="function" then mod else nil end)()
local function activated(key: any): any return if HitZone then HitZone.signal(key) else key.Activated end
local BonusRenderer=require(script.Parent.BonusRenderer)
local TweenService=game:GetService("TweenService")
local TextBounds=require(script.Parent.BattleHudTextBounds)
local GuiService=game:GetService("GuiService")
local Names=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local UserInputService=game:GetService("UserInputService")
local Theme=table.clone(require(game:GetService("ReplicatedStorage").Shared.Theme))
local HudTheme=require(script.Parent.BattleHudTheme)
local PB:(string)->(),PE:()->()=(debug :: any).profilebegin or function(_: string) end,(debug :: any).profileend or function() end -- microprofile labels (no-ops outside Roblox)
Theme.Panel=HudTheme.Panel;Theme.PanelRaised=HudTheme.Raised;Theme.Border=HudTheme.Border
Theme.Accent=HudTheme.Cobalt;Theme.Gold=HudTheme.Gold;Theme.Danger=HudTheme.Danger
Theme.Text=HudTheme.Text;Theme.MutedText=HudTheme.Muted;Theme.CommandCobalt=HudTheme.Cobalt
Theme.CommandRaised=HudTheme.Raised;Theme.CommandInk=HudTheme.Text
local Blueprint=require(script.Parent.BlueprintPresentation)
local InputPrompts=require(script.Parent.InputPrompts)
local HudControls=require(script.Parent.BattleHudControls)
local City={}
City.__index=City
local BULK_NAMES={"Top","Right","Bottom","Left"}
local BUILD_ORDER={"AtomBomb","MIRV","HydrogenBomb","Warship","Port","MissileSilo","SAMLauncher","DefensePost","City","Factory"}
local STRUCTURE_ORDER={"Port","MissileSilo","SAMLauncher","DefensePost","City","Factory"}
local ATTACK_ORDER={"AtomBomb","MIRV","HydrogenBomb","Warship"}
local SOURCE_NAMES={DefensePost="Defense Post",MissileSilo="Missile Silo",SAMLauncher="SAM Launcher",AtomBomb="Atom Bomb",HydrogenBomb="Hydrogen Bomb"}
-- PF - 4 building animations (Ashton 2026-10-27): the card squashes when picked, flashes + floats its cost when placed
local okBuildAnim,BuildAnim=pcall(require,script.Parent.BuildAnim)
local DESCRIPTIONS={Warship="Captures trade ships, destroys ships and boats",Port="Sends trade ships to generate gold",City="Increases max population",Factory="Creates railroads and spawns trains",DefensePost="Increases defenses of nearby borders",MissileSilo="Used to launch nukes",SAMLauncher="Defends against incoming nukes",AtomBomb="Small explosion",HydrogenBomb="Large explosion",MIRV="Huge explosion, only targets selected player"}
-- PF022 (MM): a disabled root slice is a readable dark plate (not a 60%-faded ghost) carrying its reason.
local PLATE,PLATE_ALPHA=Color3.fromHex("#3a3f47"),.12
local COLORS={Build=Color3.fromHex("#e6c74a"),Delete=Color3.fromHex("#ef4444"),City=Color3.fromHex("#1e3a5f"),Port=Color3.fromHex("#1e3a5f"),Factory=Color3.fromHex("#1e3a5f"),DefensePost=Color3.fromHex("#1e3a5f"),Boat=Color3.fromHex("#2a82c9"),Attack=Color3.fromHex("#ef4444"),Warship=Color3.fromHex("#ef4444")}
local BUILD_KEYS={[Enum.KeyCode.One]="City",[Enum.KeyCode.KeypadOne]="City",[Enum.KeyCode.Two]="Factory",[Enum.KeyCode.KeypadTwo]="Factory",[Enum.KeyCode.Three]="Port",[Enum.KeyCode.KeypadThree]="Port",[Enum.KeyCode.Four]="DefensePost",[Enum.KeyCode.KeypadFour]="DefensePost",[Enum.KeyCode.Five]="MissileSilo",[Enum.KeyCode.KeypadFive]="MissileSilo",[Enum.KeyCode.Six]="SAMLauncher",[Enum.KeyCode.KeypadSix]="SAMLauncher",[Enum.KeyCode.Seven]="Warship",[Enum.KeyCode.KeypadSeven]="Warship",[Enum.KeyCode.Eight]="AtomBomb",[Enum.KeyCode.KeypadEight]="AtomBomb",[Enum.KeyCode.Nine]="HydrogenBomb",[Enum.KeyCode.KeypadNine]="HydrogenBomb",[Enum.KeyCode.Zero]="MIRV",[Enum.KeyCode.KeypadZero]="MIRV"}
local function bindGlyph(icon: ImageLabel,name: string)
    icon.BackgroundTransparency=1;icon.ImageColor3=Color3.new(1,1,1)
    Icons.bindWhite(icon,name)
end
function City.isBuildKey(key: Enum.KeyCode): boolean return BUILD_KEYS[key]~=nil end
-- PF013: Builder C moves the leaderboard into the authored PFLeaderboardRegion.
function City.leaderboardOf(ui: Instance): any
    local region=ui:FindFirstChild("PFLeaderboardRegion")
    return (region and region:FindFirstChild("Leaderboard")) or ui:FindFirstChild("Leaderboard") or ui
end
local function brighten(color: Color3): Color3 return Color3.new(math.min(1,color.R*1.5),math.min(1,color.G*1.5),math.min(1,color.B*1.5)) end
function City.enabledKinds(state: any,order: {string}): {string}
    local result={}
    for _,kind in order do if not state or not GameConfig.disabled(state,SOURCE_NAMES[kind] or kind) then table.insert(result,kind) end end
    return result
end
function City:refreshBuildConfiguration(): boolean
    local raw=self.state and self.state.gameConfig
    local signature=if raw then table.concat(raw.disabledUnits or {},"\0") else ""
    if self.buildConfigSignature==signature then return false end
    self.buildConfigSignature=signature
    self.buildOrder=City.enabledKinds(self.state,Blueprint.Catalog)
    self.structureOrder=City.enabledKinds(self.state,STRUCTURE_ORDER)
    self.attackOrder=City.enabledKinds(self.state,ATTACK_ORDER)
    self:retireCatalog()
    for _,entry in {{self.actions.City,STRUCTURE_ORDER,self.structureOrder},{self.actions.Warship,ATTACK_ORDER,self.attackOrder}} do
        local group,all,order=entry[1],entry[2],entry[3]
        for _,kind in all do local item=group[kind];local index=table.find(order,kind);item.Visible=index~=nil
            if index then
                Icons.bind(item,string.format("BuildChildArc_%d_%d",#order,index))
                local angle=(index-1)*math.pi*2/#order
                -- UDim offsets are integral. Scale preserves source fractional
                -- centroids within the unchanged280px source radial viewBox.
                item.Icon.Position=UDim2.fromScale(.5+math.sin(angle)*107.5/280,.5-math.cos(angle)*107.5/280)
            else item:SetAttribute("Enabled",false) end
        end
    end
    if self.lastLayout then self:layout() end
    return true
end
function City.deleteTarget(state: any,tile: number): number?
    if state.phase=="Choosing" or state.owners[tile]~=1 or not state.map.land[tile] then return nil end
    if City.deleteCooldown(state)>0 then return nil end
    local w=state.map.width
    local x,y=(tile-1)%w,math.floor((tile-1)/w)
    local nearest,distance,nearestOrder=nil,math.huge,math.huge
    local units=Economy.ownedCities(state,1)
    for _,port in Ports.ownedPorts(state,1) do table.insert(units,port) end
    for _,factory in state.factories or {} do if factory.owner==1 then table.insert(units,factory) end end
    for _,post in state.defensePosts or {} do if post.owner==1 then table.insert(units,post) end end
    for _,silo in state.missileSilos or {} do if silo.owner==1 then table.insert(units,silo) end end
    for _,sam in state.samLaunchers or {} do if sam.owner==1 then table.insert(units,sam) end end
    for index,unit in units do
        local d=math.abs((unit.tileId-1)%w-x)+math.abs(math.floor((unit.tileId-1)/w)-y)
        local order=unit.ownershipOrder or index
        if not unit.underConstruction and not unit.deletionMarkedTick and d<=5 and (d<distance or (d==distance and order<nearestOrder)) then
            nearest,distance,nearestOrder=unit.id,d,order
        end
    end
    return nearest
end
function City.deleteCooldown(state: any): number
    return math.max(0,300-(state.ticks+1-state.lastDeleteTicks[1]))/10
end
function City.goldPipProgress(elapsed: number): number
    -- CSS ease-out = cubic-bezier(0,0,.58,1), not Roblox's Quad approximation.
    local x=math.clamp(elapsed/.25,0,1)
    if x==0 or x==1 then return x end
    local low,high=0,1
    for _=1,20 do
        local t=(low+high)/2
        local bx=3*(1-t)*t*t*.58+t*t*t
        if bx<x then low=t else high=t end
    end
    local t=(low+high)/2
    return 3*(1-t)*t*t+t*t*t
end
function City.conquestGain(state: any,previousCursor: number?): (number?,number,number?)
    local cursor=math.max(previousCursor or 0,state.conquestEventCursor or 0)
    if previousCursor==nil then return nil,cursor,nil end
    local amount,eventId=nil,nil
    local localId=state.players[1].id
    for _,event in state.conquestEvents or {} do
        if event.id>previousCursor and event.conquerorId==localId and event.gold>0 then amount,eventId=event.gold,event.id end
    end
    return amount,cursor,eventId
end
function City.new(ui: Frame,world: Frame,callbacks: any)
    local self=setmetatable({ui=ui,world=world,callbacks=callbacks,menu=ui:FindFirstChild("BuildMenu"),radial=ui:WaitForChild("Radial"),
        tooltip=ui:WaitForChild("CityTooltip"),gold=ui.Controls:WaitForChild("Gold"),state=nil,cache={},level=0,
        ghostActive=false,multiplier=1,rocketDirectionUp=true,lastPreview=-math.huge,lastRadial=-math.huge,hover=nil,destroyed=false,connections={},tweens={}},City)
    City.current=self -- PIVOT: the live dock, for City.equipKind (a tip's action line)
    self.actions=self.radial:WaitForChild("CityActions")
    self.gain=self.gold:WaitForChild("Gain")
    self.palette=ui.Controls:WaitForChild("Blueprints")
    self.placement=ui.Controls:WaitForChild("Placement")
    self.blueprints={}
    self.slots={}
    self.nuclear=ui:WaitForChild("NuclearActions")
    self.nuclearButtons={}
    self.blueprintTip=ui:FindFirstChild("BlueprintTooltip")
    self.buildings=BuildingRenderer.new(world,ui.Templates:WaitForChild("CitySprite"))
    self.bonuses=BonusRenderer.new(world,ui.Templates)
    table.insert(self.connections,ui.Destroying:Connect(function() self:destroy() end))
    local function listen(signal: RBXScriptSignal,callback: any)
        table.insert(self.connections,signal:Connect(function(...)
            -- Deferred Visible/MouseLeave callbacks can outlive a removed UI.
            if self.destroyed or self.ui.Parent==nil then return end
            callback(...)
        end))
    end
    -- UI audit build-out: Cancel's finger zone (PF - 3's HitZone strips, authored by author-pf1-buildout) fires it too
    listen(activated(self.placement.Cancel),function() self:clearGhost() end)
    -- PF-040: the aim bar (Placement.PFAim, tools/atlas/author-pf040.luau): Launch fires the pinned target on touch
    local aim=self.placement:FindFirstChild("PFAim")
    local launch=aim and aim:FindFirstChild("Launch",true)
    if launch and launch:IsA("GuiButton") then listen(launch.Activated,function() self:launchPinned() end) end
    Icons.bind(self.gold.Coin,"Gold")
    Icons.bind(self.radial.Attack.Back,"Back")
    for _,entry in {{"Build","RootBuild"},{"Delete","RootDelete"}} do
        Icons.bind(self.actions.Root[entry[1]],entry[2]);Icons.bind(self.actions.Root[entry[1]].Icon,entry[1])
    end
    self.actions.Root.Delete.Icon.Size=UDim2.fromOffset(32,26) -- source getSvgAspectRatio(XIcon)=.8.
    Icons.bind(self.actions.Root.Boat,"RootBoat");Icons.bind(self.actions.Root.Boat.Icon,"Boat")
    Icons.bind(self.actions.Root.Attack,"RootBuild");Icons.bind(self.actions.Root.Attack.Icon,"Sword")
    for _,name in {"Info","Alliance","BreakAlliance","DonateGold"} do
        local v=self.actions.Root:FindFirstChild(name)
        if v then Icons.bind(v,if name=="Info" then "DiplomacyRootInfo" elseif name=="Alliance" then "DiplomacyRootAlliance" elseif name=="BreakAlliance" then "RootBoat" else "RootBuild")
            Icons.bind(v.Icon,"Diplomacy"..(if name=="Alliance" then "Alliance" elseif name=="BreakAlliance" then "Break" else name)) end
    end
    if self.actions.Root:FindFirstChild("Alliance") then Icons.bind(self.actions.Root.Alliance.ExtendLeft,"DiplomacyAlliance");Icons.bind(self.actions.Root.Alliance.ExtendRight,"DiplomacyAlliance") end
    for _,kind in ATTACK_ORDER do Icons.bind(self.actions.Warship[kind],kind.."WeaponsAttackRing");bindGlyph(self.actions.Warship[kind].Icon,kind) end
    for _,kind in STRUCTURE_ORDER do Icons.bind(self.actions.City[kind],kind.."WeaponsBuildRing");bindGlyph(self.actions.City[kind].Icon,kind) end
    for _,name in BULK_NAMES do Icons.bind(self.actions.Bulk[name],"Bulk"..name) end
    listen(self.actions.Hit.Activated,function(input: InputObject)
        local position=Vector2.new(input.Position.X,input.Position.Y)
        self:activate(self:itemAt(position))
    end)
    listen(self.actions.Hit.MouseMoved,function(x: number,y: number) self:hoverAt(Vector2.new(x,y)) end)
    listen(self.actions.Hit.MouseLeave,function() self.hover=nil;self.tooltip.Visible=false;self:refreshRadial() end)
    for _,kind in Blueprint.Order do
        -- the Warship slot (PF - 1) is authored by tools/atlas/author-warship-slot; a place without it keeps the key-7 path only
        local card=if kind=="Warship" then self.palette.Cards:FindFirstChild(kind) else self.palette.Cards:WaitForChild(kind)
        if not card then continue end
        self.blueprints[kind]=card
        self.slots[kind]=card
        bindGlyph(card.Icon,kind)
        card.Title.Text=Blueprint.ChipNames[kind];card.Description.Text=Blueprint.Purposes[kind]
        card.Shortcut.Text=Blueprint.Shortcuts[kind]
        listen(card.Activated,function() if HudControls.available(card) then self:equip(kind) end end)
        listen(card.MouseEnter,function() self.tipControl=card;self.tipKind=kind;card:SetAttribute("Hovered",true);self:refreshBlueprints() end)
        listen(card.MouseLeave,function() if self.tipControl==card then self.tipControl=nil;self.tipKind=nil end;card:SetAttribute("Hovered",nil);self:refreshBlueprints() end)
    end
    for _,kind in Blueprint.Nuclear do
        local button=self.palette.Cards:FindFirstChild(kind) or self.nuclear.Buttons:WaitForChild(kind)
        self.nuclearButtons[kind]=button
        self.slots[kind]=button
        bindGlyph(button.Icon,kind)
        button.Title.Text=Blueprint.NuclearNames[kind]
        button.Shortcut.Text=Blueprint.Shortcuts[kind]
        -- Exactly the key8/9/0 equip path. A GUI selection cannot launch.
        listen(button.Activated,function()
            if HudControls.available(button) then self:equip(kind) end
        end)
        listen(button.MouseEnter,function() self.tipControl=button;self.tipKind=kind;button:SetAttribute("Hovered",true);self:refreshBlueprints() end)
        listen(button.MouseLeave,function() if self.tipControl==button then self.tipControl=nil;self.tipKind=nil end;button:SetAttribute("Hovered",nil);self:refreshBlueprints() end)
    end
    -- Home/results/modals can change between State packets. Refresh guards at
    -- their actual visibility boundary, rather than waiting for the next tick.
    for _,parent in {ui,ui.Parent} do
        for _,panel in parent:GetChildren() do
            if panel:IsA("GuiObject") and panel~=self.nuclear and panel~=self.blueprintTip then
                listen(panel:GetPropertyChangedSignal("Visible"),function() self:refreshBlueprints() end)
            end
        end
    end
    listen(ui.Controls:GetPropertyChangedSignal("Visible"),function() self:refreshBlueprints() end)
    if self.menu then
        local function retire() self.catalogClean=nil;self:retireCatalog() end
        listen(self.menu:GetPropertyChangedSignal("Visible"),retire)
        listen(self.menu:GetPropertyChangedSignal("Active"),retire)
        listen(self.menu:GetPropertyChangedSignal("Selectable"),retire)
        for _,object in self.menu:GetDescendants() do
            if object:IsA("GuiObject") then
                listen(object:GetPropertyChangedSignal("Visible"),retire)
                listen(object:GetPropertyChangedSignal("Active"),retire)
                listen(object:GetPropertyChangedSignal("Selectable"),retire)
            end
        end
    end
    self:retireCatalog()
    listen(self.palette:GetPropertyChangedSignal("Visible"),function() self:refreshBlueprints() end)
    listen(self.palette:GetAttributeChangedSignal("HudColumns"),function() self:refreshSlotNavigation() end)
    listen(GuiService:GetPropertyChangedSignal("MenuIsOpen"),function() self:refreshBlueprints() end)
    listen(UserInputService.TextBoxFocused,function() self:refreshBlueprints() end)
    listen(UserInputService.TextBoxFocusReleased,function() task.defer(function() if not self.destroyed then self:refreshBlueprints() end end) end)
    listen(UserInputService:GetPropertyChangedSignal("PreferredInput"),function() self:refreshBlueprints() end)
    listen(UserInputService.GamepadConnected,function() InputPrompts.invalidate();self:refreshBlueprints() end)
    listen(UserInputService.GamepadDisconnected,function() InputPrompts.invalidate();self:refreshBlueprints() end)
    local motionNode: Instance?=ui
    while motionNode do
        for _,name in {"ReducedMotion","Static","StaticBackground","MotionEnabled"} do
            listen(motionNode:GetAttributeChangedSignal(name),function() self:syncMotion() end)
        end
        motionNode=motionNode.Parent
    end
    listen(GuiService:GetPropertyChangedSignal("SelectedObject"),function()
        local selected=GuiService.SelectedObject
        self.tipControl=nil;self.tipKind=nil
        if InputPrompts.mode()=="Gamepad" and selected then
            for kind,control in self.blueprints do if selected==control then self.tipControl=control;self.tipKind=kind;break end end
            if not self.tipKind then for kind,control in self.nuclearButtons do if selected==control then self.tipControl=control;self.tipKind=kind;break end end end
        end
        self:refreshBlueprintTip()
    end)
    local function scheduleTipRefresh()
        if self.tipRefreshPending then return end;self.tipRefreshPending=true
        task.defer(function()
            self.tipRefreshPending=false
            if not self.destroyed then self:refreshBlueprintTip() end
        end)
    end
    for _,object in {ui,self.palette,self.nuclear,ui.Attacks,ui.DiplomacyHover,ui.TutorialGuide,ui.GamepadHelp,City.leaderboardOf(ui),ui.VariantPanels,ui.VariantSpeedPanel} do
        listen(object:GetPropertyChangedSignal("AbsolutePosition"),scheduleTipRefresh)
        listen(object:GetPropertyChangedSignal("AbsoluteSize"),scheduleTipRefresh)
        listen(object:GetPropertyChangedSignal("Visible"),scheduleTipRefresh)
    end
    -- The authored AutomaticSize tooltip settles a frame after its text changes.
    if self.blueprintTip then listen(self.blueprintTip:GetPropertyChangedSignal("AbsoluteSize"),scheduleTipRefresh) end
    listen(self.radial:GetPropertyChangedSignal("Visible"),function()
        if not self.radial.Visible then self.tooltip.Visible=false;self.level=0;self:applyLevel(false) end
    end)
    return self
end
-- PIVOT (MM: the Defense Post tip's action line opens Build on that slot): equip a build slot on the live dock, as its own
-- card or key would (the same rules: City:equip). False when there is no dock or the slot can't be equipped now.
function City.equipKind(kind: string): boolean
    local current=City.current
    return current~=nil and not current.destroyed and current:equip(kind)
end
-- PIVOT D12 Phase 4 (PF - 1, MM approved the Arsenal wing): the wing's premium slots (PremiumBuildPlaceholder) share the dock's
-- one placement. Arming a premium item clears a base blueprint; arming a blueprint, Cancel or Esc ends the premium item
-- (premiumHooks.cancel); while it is armed the authored Placement panel words it ("BANK · 600K gold" / "Tap your land to place").
City.premiumHooks={cancel=nil :: (()->())?,launch=nil :: (()->())?,tip=nil :: ((string)->any)?}
-- the wing's hover (desk) / long-press (touch) card: the dock's own BlueprintTooltip, its content from premiumHooks.tip(item)
-- = {title, purpose, price, state = "ready"|"short"|"blocked", owned}; nil hides it
function City.premiumTip(control: GuiObject?)
    local current=City.current;if not current or current.destroyed then return end
    if control then current.tipControl=control;current.tipKind="premium"
    elseif current.tipKind=="premium" then current.tipControl=nil;current.tipKind=nil end
    current:refreshBlueprintTip()
end
-- the launch items' prerequisite, as the base nukes': a ready Missile Silo (nil when one is ready)
function City.siloReason(state: any): string? return if state then City._prerequisite(state,"AtomBomb") else nil end
-- aim (touch launches, MM): {item, name, cost, image, rect, state = "tap"|"ready"|"self", ready} -> the aim bar with Launch
function City.premiumPlacement(title: string?,line: string?,aim: any?)
    local current=City.current;if not current or current.destroyed then return end
    if title and current.ghostActive then
        local hook=City.premiumHooks.cancel;City.premiumHooks.cancel=nil;current:clearGhost();City.premiumHooks.cancel=hook
    end
    current.premiumTitle=title;current.premiumLine=line;current.premiumAim=if title then aim else nil
    current:refreshBlueprints()
end
local function endPremium(self: any) if self.premiumTitle and City.premiumHooks.cancel then City.premiumHooks.cancel() end end
function City:destroy()
    if self.destroyed then return end
    self.destroyed=true
    if City.current==self then City.current=nil end
    for _,record in self.tweens do record.tween:Cancel() end;table.clear(self.tweens)
    for _,connection in self.connections do connection:Disconnect() end
    table.clear(self.connections)
    -- UI Destroying can be deferred until its children have already gone.
    if self.ui.Parent~=nil then
        self:clearGhost();self.buildings:reset()
        self:retireCatalog();self.radial.Visible=false;self.tooltip.Visible=false;self.gain.Visible=false
    end
    self.bonuses:destroy();self.state=nil;self.cache={}
end
function City:query(tile: number,kind: string?): any
    kind=kind or "City"
    local key=tostring(tile)..kind
    local q=self.cache[key]
    if not q then
        q=if kind=="Warship" then Warships.queryBuildableWarship(self.state,1,tile) elseif kind=="Port" then Ports.queryBuildablePort(self.state,1,tile)
            elseif kind=="Factory" then Structures.queryBuildableFactory(self.state,1,tile) elseif kind=="DefensePost" then Structures.queryBuildableDefensePost(self.state,1,tile)
            elseif kind=="MissileSilo" then Weapons.queryBuildableMissileSilo(self.state,1,tile) elseif kind=="SAMLauncher" then Weapons.queryBuildableSAMLauncher(self.state,1,tile)
            elseif kind=="AtomBomb" or kind=="HydrogenBomb" or kind=="MIRV" then Nukes.queryBuildable(self.state,1,SOURCE_NAMES[kind] or kind,tile)
            else Economy.queryBuildableCity(self.state,1,tile)
        if kind=="Factory" or kind=="City" or kind=="Port" then
            local preview=Rails.preview(self.state,kind,tile)
            q.ghostRailPaths=preview.ghostRailPaths;q.overlappingRailroads=preview.overlappingRailroads
        end
        if kind=="AtomBomb" then q.readyMissileCount=self:readyMissiles() end
        self.cache[key]=q
    end
    return q
end
function City:setPreferences(preferences: any)
    self.preferences=preferences;self.buildings:setPreferences(preferences)
end
function City:motionAllowed(): boolean
    if self.destroyed or not self.ui.Visible or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return false end
    if self.callbacks.canSelectBlueprint and not self.callbacks.canSelectBlueprint() then return false end
    local node: Instance?=self.ui
    while node do
        if node:GetAttribute("ReducedMotion")==true or node:GetAttribute("Static")==true or node:GetAttribute("StaticBackground")==true or node:GetAttribute("MotionEnabled")==false then return false end
        node=node.Parent
    end
    if self.preferences then
        local values=self.preferences:snapshot()
        if values["settings.reducedMotion"]=="true" or values["settings.staticBackground"]=="true" or values["settings.motionEnabled"]=="false" then return false end
    end
    return true
end
function City:animateScale(scale: UIScale,value: number,duration: number)
    local previous=self.tweens[scale];if previous then previous.tween:Cancel();self.tweens[scale]=nil end
    if not self:motionAllowed() then scale.Scale=value;return end
    local tween=TweenService:Create(scale,TweenInfo.new(duration,Enum.EasingStyle.Cubic,Enum.EasingDirection.Out),{Scale=value})
    self.tweens[scale]={tween=tween,value=value};tween:Play()
end
function City:syncMotion()
    if self:motionAllowed() then return end
    for scale,record in self.tweens do
        record.tween:Cancel();if scale.Parent then scale.Scale=record.value end
    end
    table.clear(self.tweens)
end
function City:shouldBlockRecentAllyNuke(tile: number,kind: string): boolean
    local duration=if self.preferences then self.preferences:get("nukeAllianceSafetyDuration") else 5
    if duration<=0 or (kind~="Atom Bomb" and kind~="Hydrogen Bomb" and kind~="MIRV") then return false end
    local allies=Diplomacy.alliances(self.state,1);if #allies==0 then return false end
    self.usedSafetyAllies=self.usedSafetyAllies or {};local fresh={}
    for _,alliance in allies do
        if not self.usedSafetyAllies[alliance.id] and self.state.ticks-alliance.createdAt<=duration then
            fresh[if alliance.requestor==1 then alliance.recipient else alliance.requestor]=alliance.id
        end
    end
    if next(fresh)==nil then return false end
    local affected=if kind=="MIRV" then {self.state.owners[tile]} else Nukes.affectedOwners(self.state,kind,tile)
    local blocked=false
    for _,owner in affected do local allianceId=fresh[owner];if allianceId~=nil then self.usedSafetyAllies[allianceId]=true;blocked=true end end
    if blocked and self.callbacks.blockedNuke then self.callbacks.blockedNuke(tile) end
    return blocked
end
function City:readyMissiles(): number
    local total=0;for _,unit in self.state.missileSilos or {} do if unit.owner==1 and unit.active~=false and not unit.underConstruction then total+=math.max(0,unit.level-#(unit.missileTimerQueue or {})) end end;return total
end
function City:bulkMaximum(q: any): number
    if q.type=="Atom Bomb" then return math.min(50,math.floor(self.state.gold[1]/q.cost),self:readyMissiles()) end
    return Economy.maxAffordableUpgrades(q.upgradeCosts,self.state.gold[1])
end
function City:update(state: any,colors: any,palettes: any)
    if self.destroyed then return end
    self.state=state;self.cache={}
    self:refreshBuildConfiguration()
    -- the gold rolls toward each new total (.25 s); a big gain (>= 10%) punches the coin 1.15 -> 1
    local gold=(state.gold and state.gold[1]) or 0
    if Motion then
        Motion.count(self.gold.Value,gold,{format=self.callbacks.formatNumber,time=.25})
        if self.lastGold and self.lastGold>0 and gold-self.lastGold>=self.lastGold*.1 then Motion.pop(self.gold.Coin,1.15,.2) end
    else self.gold.Value.Text=self.callbacks.formatNumber(gold) end
    self.lastGold=gold
    PB("PF.Cities.Bonuses");local bonus=self.bonuses:update(state);PE()
    local amount,cursor,eventId=City.conquestGain(state,self.conquestCursor)
    -- ControlPanel visits BonusEvent before ConquestEvent. Last positive local
    -- event wins, and a conquest in the same update supersedes a trade bonus.
    if not amount and bonus then amount,eventId=bonus.gold,bonus.id end
    if amount then
        self.gainStarted=os.clock()
        local value="+"..self.callbacks.formatNumber(amount)
        self.gain.Value.Text=value;self.gain.Shadow.Text=value
        self.gain:SetAttribute("Gold",amount);self.gain:SetAttribute("EventId",eventId)
        self.gain.Visible=true
    end
    -- First snapshot is a baseline. Same-match full resync retains this cursor.
    self.conquestCursor=cursor
    PB("PF.Cities.Buildings");self.buildings:update(state,colors,palettes);PE()
    if not self.callbacks.canPlay() then self:clearGhost() end
    -- PF020 perf audit: refreshBlueprints retires the catalog first; retire here only when it returns early
    if self.destroyed or not self.palette then self:retireCatalog() end
    PB("PF.Cities.Blueprints");self:refreshBlueprints();PE()
end
function City:reset()
    self.tipControl=nil;self.tipKind=nil;self.tipLayoutKey=nil
    if self.blueprintTip then self.blueprintTip.Visible=false end
    if self.destroyed then return end
    self.state=nil
    for _,record in self.tweens do record.tween:Cancel() end;table.clear(self.tweens)
    self:clearGhost();self.buildings:reset();self.bonuses:reset();self:retireCatalog();self.level=0;self.radial.Visible=false;self.cache={}
    self.navigationUntil=0;self.selectedItemName=nil;self.conquestCursor=nil;self.gainStarted=nil;self.gain.Visible=false;self.usedSafetyAllies={}
    self.gain:SetAttribute("Gold",nil);self.gain:SetAttribute("EventId",nil)
    self.nuclear.Visible=false
end
-- PF013: the dock, slots and gold-gain label are authored in Scale; nothing to size.
function City:layout()
    self.lastLayout=true;self:refreshBuildConfiguration();self:retireCatalog()
end
function City:completedLevels(kind: string): number
    if kind=="City" then return Economy.completedLevels(self.state,1) end
    if kind=="Warship" then local count=0;for _,ship in self.state.warships or {} do if ship.owner==1 and ship.active~=false then count+=1 end end;return count end
    local levels=0
    local units=if kind=="Factory" then self.state.factories elseif kind=="DefensePost" then self.state.defensePosts elseif kind=="MissileSilo" then self.state.missileSilos elseif kind=="SAMLauncher" then self.state.samLaunchers else self.state.ports
    for _,port in units or {} do if port.owner==1 and not port.underConstruction then levels+=port.level end end
    return levels
end
-- Retained only for old native templates/hooks. Catalog content has no handlers.
-- PF - 4 perf (2026-10-27 endgame microprofile): this ran several times a packet and once a frame, re-writing ~7 properties
-- on every catalog descendant (~700 writes) that were already retired. Now the walk runs only when something could have
-- un-retired one: the root shows/activates again, a descendant changes or is added (the listeners in new mark it dirty),
-- or a second has passed (a safety re-walk).
function City:retireCatalog()
    local menu=self.menu
    if not menu or menu.Parent==nil then return end
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(menu) then GuiService.SelectedObject=nil end
    local now=os.clock()
    if self.catalogClean==menu and now<(self.catalogWalkAt or 0)+1 and not menu.Visible and not menu.Active and not menu.Selectable then return end
    if self.catalogWatched~=menu then
        self.catalogWatched=menu
        local added=(menu :: any).DescendantAdded -- (CLI fakes have none: they keep the walk)
        if added then added:Connect(function() self.catalogClean=nil end) else self.catalogWatched=nil end
    end
    HudControls.retire(menu)
    for _,object in menu:GetDescendants() do
        if object:IsA("GuiObject") then HudControls.retire(object) end
    end
    menu:SetAttribute("CatalogRetired",true)
    self.catalogClean=menu;self.catalogWalkAt=now
end
function City:refreshMenu() self:retireCatalog() end
function City:showMenu(_tile: number?): boolean self:retireCatalog();return false end
function City:placementPrice(kind: string): number
    local price=Blueprint.price(self.state,kind)
    local query=self.previewQuery
    if query and query.type==(SOURCE_NAMES[kind] or kind) and type(query.cost)=="number" then
        if query.canUpgrade~=nil and query.canUpgrade~=false then
            local amount=self.multiplier or 1
            price=(query.upgradeCosts and query.upgradeCosts[amount]) or query.cost*amount
        else price=query.cost end
    end
    -- Only Atom's retained Build intent consumes a launch multiplier. Normal
    -- builds, Hydrogen and MIRV remain single orders regardless of repeat keys.
    if kind=="AtomBomb" then price*=self.multiplier or 1 end
    return price
end
function City:refreshBlueprints()
    if self.destroyed or not self.palette then return end
    self:retireCatalog()
    self:syncMotion()
    HudControls.retire(self.ui.Controls.Actions.Build)
    HudControls.retire(self.ui.Controls.Actions.Primary)
    self:refreshNuclearActions()
    local allowed=self:canEquipSlot()
    if not self.state then
        for _,card in self.blueprints do card.Active=false;card.Selectable=false;HudControls.clearLinks(card) end
        self.placement.Visible=false;self:refreshSlotNavigation();self:refreshBlueprintTip();return
    end
    local mode=InputPrompts.mode()
    local gamepad=mode=="Gamepad"
    local touch=mode=="Touch"
    for _,kind in Blueprint.Order do
        local card=self.blueprints[kind]
        if not card then continue end
        card.Visible=Blueprint.enabled(self.state,kind)
        card.Active=allowed and card.Visible;card.Selectable=card.Active
        if not card.Visible then continue end
        local price=Blueprint.price(self.state,kind)
        local active=self.ghostActive and self.ghostKind==kind
        local hovered=card:GetAttribute("Hovered")==true
        card:SetAttribute("Affordable",self.state.gold[1]>=price)
        card:SetAttribute("Enabled",card.Active)
        card:SetAttribute("HudUnavailableReason",self:unavailableReason(kind))
        card:SetAttribute("BlueprintSelected",active)
        card:SetAttribute("PFHotbarLift",active and self.hotbarEquipped==true) -- PF020 console hotbar: raised + lit
        card.Border.Color=if active then Theme.Accent else Theme.Border
        card.Border.Thickness=if active then 2 else 1
        if card:GetAttribute("ClarityUnifiedSlot") then
            card.BackgroundTransparency=if active or hovered then 0 else 1
            card.Border.Enabled=active
        end
        local rest=card:GetAttribute("RestColor") or Theme.PanelRaised
        card.BackgroundColor3=if active then (card:GetAttribute("SelectedColor") or Theme.PanelRaised:Lerp(Theme.Accent,.18)) elseif hovered then rest:Lerp(Theme.Text,.07) else rest
        InputPrompts.apply(card,Blueprint.Shortcuts[kind],Enum.KeyCode.ButtonA,mode)
        self:paintSlot(card,kind,active)
    end
    local kind=self.ghostKind
    self.placement.Visible=self.ghostActive==true and kind~=nil and allowed
    self.placement.Cancel.Active=self.placement.Visible;self.placement.Cancel.Selectable=self.placement.Visible
    if kind then
        local price=self:placementPrice(kind)
        self.placement:SetAttribute("QuotedPrice",price)
        local query=self.previewQuery
        local bulk=kind=="AtomBomb" or (query and query.type==(SOURCE_NAMES[kind] or kind) and query.canUpgrade~=nil and query.canUpgrade~=false)
        local amount=if bulk then self.multiplier or 1 else 1
        self.placement.Title.Text=string.upper(Blueprint.Names[kind] or kind)..(if amount>1 then " ×"..amount else "").." · "..self.callbacks.formatNumber(price).." gold"
        local accept=InputPrompts.buttonName(Enum.KeyCode.ButtonA)
        local cancel=InputPrompts.buttonName(Enum.KeyCode.ButtonB)
        self.placement.Description.Text=if self.state.gold[1]<price then "Need "..self.callbacks.formatNumber(price-self.state.gold[1]).." more gold" elseif gamepad then "Aim · "..accept.." place · "..cancel.." cancel" elseif touch then "Tap your land to place" else "Click your land · Right-click cancel"
        if kind=="Warship" then self.placement.Description.Text=if gamepad then "Coastal water · "..accept.." launch · "..cancel.." cancel" elseif touch then "Tap coastal water to launch" else "Click coastal water · Right-click cancel"
        elseif kind=="AtomBomb" or kind=="HydrogenBomb" or kind=="MIRV" then self.placement.Description.Text=if gamepad then "Aim · "..accept.." launch · "..cancel.." cancel" elseif touch then "Tap a target to launch" else "Click a target · Right-click cancel" end
        local unavailable=self:unavailableReason(kind)
        if unavailable then self.placement.Description.Text=unavailable end
        self:paintAim(kind,price,amount,touch,unavailable)
        if self.state.gold[1]<price then self.placement.Description.Text="Need "..self.callbacks.formatNumber(price-self.state.gold[1]).." more gold" end
        if self.placementFeedback and os.clock()<(self.placementFeedbackUntil or 0) then
            self.placement.Description.Text=self.placementFeedback
        end
    end
    -- PIVOT D12: an armed premium item (the Arsenal wing) words the same panel; its Cancel ends it (clearGhost)
    if self.premiumTitle and not self.ghostActive then
        self.placement.Visible=allowed
        self.placement.Cancel.Active=allowed;self.placement.Cancel.Selectable=allowed
        local aim=self.placement:FindFirstChild("PFAim");local pa=self.premiumAim
        if aim then aim.Visible=pa~=nil end
        self.placement.Title.Visible=pa==nil;self.placement.Description.Visible=pa==nil
        self.placement.Title.Text=self.premiumTitle;self.placement.Description.Text=self.premiumLine or ""
        if aim and pa then -- touch launches: name, cost, one chip, Launch (lit once a target is pinned)
            local name=aim:FindFirstChild("Name",true);if name then name.Text=pa.name end
            local cost=aim:FindFirstChild("Cost",true);if cost then cost.Text=pa.cost;cost.TextColor3=Color3.fromHex("#ffd77a") end
            local glyph=aim:FindFirstChild("Glyph",true)
            if glyph and glyph:IsA("ImageLabel") and pa.image and pa.rect then
                glyph.Image=pa.image;glyph.ImageRectOffset=Vector2.new(pa.rect.x,pa.rect.y);glyph.ImageRectSize=Vector2.new(pa.rect.w,pa.rect.h)
                glyph.ImageColor3=Color3.new(1,1,1);glyph:SetAttribute("PFKind",pa.item) -- a base nuke re-binds its own glyph
            end
            local chip=aim:FindFirstChild("Chip",true)
            if chip then
                local color=Color3.fromHex(if pa.state=="self" then "#ff5a4f" else "#4ade80") -- CHIP.self / CHIP.ready (declared below this function)
                local label=chip:FindFirstChild("Label");local dot=chip:FindFirstChild("Dot");local edge=chip:FindFirstChildOfClass("UIStroke")
                if label then label.Text=if pa.state=="self" then "Hits your land" elseif pa.state=="tap" then "Tap a target" else "Ready";label.TextColor3=color end
                if dot then dot.BackgroundColor3=color end;if edge then edge.Color=color end;chip.BackgroundColor3=color
            end
            local launch=aim:FindFirstChild("Launch",true)
            if launch and launch:IsA("GuiButton") then
                launch.Visible=true;launch.Active=pa.ready;launch.AutoButtonColor=false
                local face=launch:FindFirstChild("Face");if face and face:IsA("GuiObject") then face.BackgroundTransparency=if pa.ready then 0 else .65 end
                launch:SetAttribute("PFReady",pa.ready)
            end
        end
    end
    self:refreshSlotNavigation()
    self:refreshBlueprintTip()
end
-- PF-040 (Ashton: nuke aim "Good, build"): while a nuke is armed the placement panel becomes the aim bar: the trefoil, the
-- nuke's name, its cost, ONE status chip (Ready / SAM covers target / why it can't), Cancel; on touch, Launch (a tap on the
-- map only places the target; Launch fires it, so the aim can never get stuck). The cost lives here, not on the map.
local NUKE_KINDS={AtomBomb=true,HydrogenBomb=true,MIRV=true}
local CHIP={ready=Color3.fromHex("#4ade80"),sam=Color3.fromHex("#ff5a4f"),cant=Color3.fromHex("#9aa0a8"),self=Color3.fromHex("#ff5a4f")}
local NukeSelfHit=require(script.Parent.NukeSelfHit) -- PIVOT (MM): "Hits your land" when the blast covers your territory (no block)
local NukeConfig=require(game:GetService("ReplicatedStorage").Shared.Config).Nuclear
function City:samCovers(tile: number?): boolean
    local state=self.state;if not tile or not state then return false end
    local w=state.map.width;local x,y=(tile-1)%w,(tile-1)//w
    for _,sam in state.samLaunchers or {} do
        if sam.owner~=1 and sam.active~=false then
            local sx,sy=(sam.tileId-1)%w,(sam.tileId-1)//w;local r=Weapons.samRange(sam.level)
            if (sx-x)^2+(sy-y)^2<=r*r then return true end
        end
    end
    return false
end
function City:paintAim(kind: string,price: number,amount: number,touch: boolean,unavailable: string?)
    local aim=self.placement:FindFirstChild("PFAim");if not aim then return end
    local nuke=NUKE_KINDS[kind]==true
    aim.Visible=nuke
    for _,name in {"Title","Description"} do local node=self.placement:FindFirstChild(name);if node then node.Visible=not nuke end end
    if not nuke then return end
    local tile=if touch then self.pinnedTile else self.previewTile
    local q=self.previewQuery
    local cost=price*amount
    local why: string?=nil
    if self.state.gold[1]<cost then why="Need "..self.callbacks.formatNumber(cost-self.state.gold[1]).." gold"
    elseif (kind=="AtomBomb" or kind=="HydrogenBomb") and self:readyMissiles()<=0 then why="No Missile Silo ready"
    elseif unavailable then why="Unavailable"
    elseif q and tile and q.canBuild==false then why="Can't target here" end
    local state=if why then "cant" elseif kind~="MIRV" and self:samCovers(tile) then "sam" else "ready"
    if state~="cant" and kind~="MIRV" and NukeSelfHit.covers(self.state,tile,if kind=="AtomBomb" then NukeConfig.AtomOuter else NukeConfig.HydrogenOuter) then state="self" end
    local name=aim:FindFirstChild("Name",true);if name then name.Text=(Blueprint.Names[kind] or kind)..(if amount>1 then " ×"..amount else "") end
    local glyph=aim:FindFirstChild("Glyph",true)
    if glyph and glyph:IsA("ImageLabel") and glyph:GetAttribute("PFKind")~=kind then bindGlyph(glyph,kind);glyph.ImageColor3=Color3.fromHex("#ffd2cc");glyph:SetAttribute("PFKind",kind) end
    local costLabel=aim:FindFirstChild("Cost",true);if costLabel then costLabel.Text=self.callbacks.formatNumber(cost);costLabel.TextColor3=if self.state.gold[1]<cost then CHIP.sam else Color3.fromHex("#ffd77a") end
    local chip=aim:FindFirstChild("Chip",true)
    if chip then
        local color=CHIP[state];local label=chip:FindFirstChild("Label");local dot=chip:FindFirstChild("Dot");local edge=chip:FindFirstChildOfClass("UIStroke")
        if label then label.Text=if state=="ready" then (if touch and not tile then "Tap a target" else "Ready") elseif state=="sam" then "SAM Launcher covers target" elseif state=="self" then "Hits your land" else why or "";label.TextColor3=color end
        if dot then dot.BackgroundColor3=color end;if edge then edge.Color=color end;chip.BackgroundColor3=color
    end
    local launch=aim:FindFirstChild("Launch",true)
    if launch and launch:IsA("GuiButton") then
        launch.Visible=touch
        local ready=touch and tile~=nil and state~="cant"
        launch.Active=ready;launch.AutoButtonColor=false
        local face=launch:FindFirstChild("Face");if face and face:IsA("GuiObject") then face.BackgroundTransparency=if ready then 0 else .65 end
        launch:SetAttribute("PFReady",ready)
    end
end
-- touch: fire the pinned target (the aim bar's Launch); the confirm dialog is the bar itself on touch
function City:launchPinned()
    -- a premium launch on touch (the Arsenal wing) fires its own pin
    if self.premiumTitle and not self.ghostActive then local h=City.premiumHooks.launch;if h then h() end;return end
    local tile=self.pinnedTile
    if not self.ghostActive or not tile or not self.state or not self:canEquipSlot() then return end
    local q=self:query(tile,self.ghostKind)
    if q.canBuild~=nil and q.canBuild~=false then
        if self:shouldBlockRecentAllyNuke(tile,q.type) then return end
        local kind=self.ghostKind
        self:dispatch(q,tile,self.multiplier);self.pinnedTile=nil
        self:afterLaunch()
        if kind=="MIRV" and self.ghostActive then self:clearGhost() end
        self:refreshBlueprints()
    end
end
function City:refreshBlueprintTip()
    local tip=self.blueprintTip
    if not tip then return end
    local kind,control=self.tipKind,self.tipControl
    local allowed=kind~=nil and control~=nil and HudControls.available(control) and self.state~=nil
        and self.ui.Visible and self.ui.Controls.Visible and not self.ghostActive
        and self.callbacks.canPlay() and (not self.callbacks.canSelectBlueprint or self.callbacks.canSelectBlueprint())
    if not allowed then tip.Visible=false;return end
    local priceLabel,ownedLabel=tip:FindFirstChild("Price",true),tip:FindFirstChild("Owned",true)
    if kind=="premium" then -- PIVOT D12: an Arsenal wing slot / a Premium rail card (PremiumBuildPlaceholder fills it)
        local hook=City.premiumHooks.tip;local item=control:GetAttribute("PFPremiumItem")
        local info=if hook and type(item)=="string" then hook(item) else nil
        if not info then tip.Visible=false;return end
        tip.Title.Text=info.title
        local why=info.reason -- the base card's second line: muted when blocked, red when gold is short
        tip.Purpose.Text=if not why then info.purpose elseif tip.Purpose.RichText then info.purpose..'\n<font color="#'..(if info.state=="blocked" then HudTheme.Muted else HudTheme.Shortfall):ToHex()..'">'..why.."</font>" else info.purpose.."\n"..why
        priceLabel.Text=info.price;priceLabel.TextColor3=City.priceColor(info.state)
        ownedLabel.Text=info.owned
    else
    local price=Blueprint.price(self.state,kind)
    local slotState,reason=self:slotState(kind)
    tip.Title.Text=Blueprint.Names[kind] or kind
    local purpose=Blueprint.Purposes[kind] or ""
    -- The slot's blocked/short reason is the same truth placement reports.
    tip.Purpose.Text=if not reason then purpose elseif tip.Purpose.RichText then purpose..'\n<font color="#'..(if slotState=="blocked" then HudTheme.Muted else HudTheme.Shortfall):ToHex()..'">'..reason.."</font>" else purpose.."\n"..reason
    priceLabel.Text=self.callbacks.formatNumber(price).." gold"
    priceLabel.TextColor3=City.priceColor(slotState)
    ownedLabel.Text=if slotState=="blocked" then "Unavailable" elseif table.find(Blueprint.Nuclear,kind) then "Choose a target" else tostring(Blueprint.count(self.state,kind)).." owned"
    end
    -- PF - 3 variant C: a Premium rail card (right edge) shows its card to its left, its top on the card's, kept on screen
    if control:GetAttribute("PFRailCard") then
        local origin=self.ui.AbsolutePosition
        local left=control.AbsolutePosition.X-origin.X-tip.AbsoluteSize.X-10
        local top=math.clamp(control.AbsolutePosition.Y-origin.Y,8,math.max(8,self.ui.AbsoluteSize.Y-tip.AbsoluteSize.Y-8))
        if left<8 then tip.Visible=false;return end
        tip.Position=UDim2.fromOffset(left,top);tip.Visible=true
        return
    end
    -- PF013: the tooltip's size is authored (280 wide, AutomaticSize height);
    -- only its slot-anchored position is dynamic.
    local rightClearance=8
    local width=tip.AbsoluteSize.X
    local origin=self.ui.AbsolutePosition
    local left=math.clamp(control.AbsolutePosition.X-origin.X,8,math.max(8,self.ui.AbsoluteSize.X-width-rightClearance))
    local top=self.palette.AbsolutePosition.Y-origin.Y-tip.AbsoluteSize.Y-8
    -- Tooltips yield to gameplay readouts, including persistent controller focus.
    -- On a short canvas, yield to the actual attack list and navigation.
    -- Placement keeps the selected kind and actual eligibility feedback visible.
    local height=tip.AbsoluteSize.Y
    local obstacles={}
    local panels={self.ui.Controls,self.palette,self.nuclear,self.ui.ClockPanel,self.ui.Pause,self.ui.GameRightSidebar,
        self.ui.Navigation.Focus,self.ui.Navigation.ZoomIn,self.ui.Navigation.ZoomOut,
        self.ui.Attacks,self.ui.DiplomacyHover,self.ui.TutorialGuide,self.ui.GamepadHelp,City.leaderboardOf(self.ui),self.ui.VariantPanels,self.ui.VariantSpeedPanel}
    local premiumGrid=self.ui.Controls:FindFirstChild("PFArsenalGrid") -- PIVOT D12 v4: the card sits above the open grid
    if premiumGrid and premiumGrid:IsA("GuiObject") then table.insert(panels,premiumGrid) end
    local inspector=self.ui:FindFirstChild("PFInspector") -- PF012 Builder B's strip
    if inspector and inspector:IsA("GuiObject") then table.insert(panels,inspector) end
    for _,panel in panels do
        if panel~=self.ui and panel.Visible and panel.AbsoluteSize.Y>0 then
            table.insert(obstacles,{position=panel.AbsolutePosition-origin,size=panel.AbsoluteSize})
        end
    end
    -- Only the occupied part of the bottom-left notification stack.
    local stack=self.ui:GetAttribute("PFNoticeStackHeight") or 0
    local noticeRect=self.ui:GetAttribute("PFHudNoticeRect")
    if stack>0 and typeof(noticeRect)=="Rect" then
        table.insert(obstacles,{position=Vector2.new(noticeRect.Min.X,noticeRect.Max.Y-stack),size=Vector2.new(noticeRect.Width,stack)})
    end
    table.sort(obstacles,function(a,b)
        return a.position.Y+a.size.Y>b.position.Y+b.size.Y
    end)
    for _,obstacle in obstacles do
        local p,size=obstacle.position,obstacle.size
        if left<p.X+size.X and left+width>p.X and top<p.Y+size.Y and top+height>p.Y then
            top=p.Y-height-8
        end
    end
    if top<8 or top+height>self.ui.AbsoluteSize.Y-8 then tip.Visible=false;return end
    tip.Position=UDim2.fromOffset(left,top)
    tip.Visible=true
end
function City:refreshNuclearActions()
    if self.destroyed or not self.nuclear then return end
    local state=self.state
    local allowed=self:canEquipSlot()
    -- The compatibility tray can never reappear at the top after a snapshot,
    -- typing/modal change or result dismissal. Only the authored Cards are live.
    self.nuclear.Visible=false
    for _,legacy in self.nuclear.Buttons:GetChildren() do
        if legacy:IsA("GuiButton") then HudControls.retire(legacy) end
    end
    for _,kind in Blueprint.Nuclear do
        local button=self.nuclearButtons[kind]
        button.Visible=button.Parent==self.palette.Cards and state~=nil and Blueprint.enabled(state,kind)
        button.Active=allowed and button.Visible;button.Selectable=button.Active
        button:SetAttribute("Enabled",button.Active)
        if not button.Visible then continue end
        local price=Blueprint.price(state,kind)
        local affordable=state.gold[1]>=price
        local selected=self.ghostActive and self.ghostKind==kind
        local rest=button:GetAttribute("RestColor") or Theme.CommandCobalt
        button:SetAttribute("Affordable",affordable);button:SetAttribute("BlueprintSelected",selected)
        button:SetAttribute("PFHotbarLift",selected and self.hotbarEquipped==true) -- PF020 console hotbar
        button:SetAttribute("HudUnavailableReason",self:unavailableReason(kind))
        button.Border.Color=if selected then Theme.Accent else Theme.Border
        button.Border.Thickness=if selected then 2 else 1
        if button:GetAttribute("ClarityUnifiedSlot") then
            button.BackgroundTransparency=if selected or button:GetAttribute("Hovered")==true then 0 else 1
            button.Border.Enabled=selected
        end
        button.BackgroundColor3=if selected then Theme.CommandRaised:Lerp(Theme.Accent,.16) elseif button:GetAttribute("Hovered")==true then rest:Lerp(Theme.Text,.07) else rest
        InputPrompts.apply(button,Blueprint.Shortcuts[kind],Enum.KeyCode.ButtonA)
        self:paintSlot(button,kind,selected)
    end
end
function City:canEquipSlot(): boolean
    return not self.destroyed and self.state~=nil and self.callbacks.canPlay()
        and self.ui.Visible and self.ui.Controls.Visible and self.palette.Visible
        and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
        and (not self.callbacks.canSelectBlueprint or self.callbacks.canSelectBlueprint())
end
-- A real prerequisite that gold alone cannot fix (nukes need a ready silo).
local function prerequisite(state: any,kind: string): string?
    -- a warship launches from one of your ports
    if kind=="Warship" then return if Blueprint.count(state,"Port")>0 then nil else "Build a port to launch warships" end
    if not table.find(Blueprint.Nuclear,kind) then return nil end
    local silos=Nukes.ownedSilos(state,1)
    if #silos==0 then return "Build a missile silo to launch" end
    for _,silo in silos do
        local ready=if state.canLaunchSilo then state.canLaunchSilo(silo)
            else not silo.underConstruction and #(silo.missileTimerQueue or {})~=(silo.level or 1)
        if ready then return nil end
    end
    return "Missile silos are building or reloading"
end
City._prerequisite=prerequisite -- PIVOT D12: City.siloReason (the wing's launch items)
function City:unavailableReason(kind: string): string?
    if not self.state then return nil end
    local price=Blueprint.price(self.state,kind)
    local deficit=price-self.state.gold[1]
    if deficit>0 then return "Need "..self.callbacks.formatNumber(deficit).." more gold" end
    return prerequisite(self.state,kind)
end
-- PF012 dock states: "blocked" (blacked out) for a missing prerequisite,
-- "short" (red price) when only gold is missing, otherwise "ready".
function City:slotState(kind: string): (string,string?)
    if not self.state then return "ready",nil end
    local missing=prerequisite(self.state,kind)
    if missing then return "blocked",missing end
    local deficit=Blueprint.price(self.state,kind)-self.state.gold[1]
    if deficit>0 then return "short","Need "..self.callbacks.formatNumber(deficit).." more gold" end
    return "ready",nil
end
function City.priceColor(slotState: string): Color3
    return if slotState=="blocked" then HudTheme.BlockedInk elseif slotState=="short" then HudTheme.Shortfall else Theme.Gold
end
-- MM 2026-10-16 (A06: "25.0…"): a dock price is never ellipsized; it drops its trailing zeros so it fits the tile
-- ("25.0M" -> "25M", "1.50M" -> "1.5M", "1.00M" -> "1M", "50.0K" -> "50K")
function City.compactPrice(text: string): string
    local s=string.gsub(text,"(%d)%.0+([KMBT])","%1%2")
    s=string.gsub(s,"(%.%d-)0+([KMBT])","%1%2")
    return s
end
function City:paintSlot(card: any,kind: string,selected: boolean)
    local slotState,reason=self:slotState(kind)
    local blocked=slotState=="blocked"
    local was=card:GetAttribute("HudSlotState")
    card:SetAttribute("HudSlotState",slotState);card:SetAttribute("HudBlocked",blocked);card:SetAttribute("HudSlotReason",reason)
    local cost=card:FindFirstChild("Cost")
    -- short -> affordable: the price turns white with a 1.1 -> 1 pop, so a new player sees a building unlock
    if Motion and was=="short" and slotState=="ready" and cost and cost:IsA("GuiObject") then Motion.pop(cost,1.1,.18) end
    if cost and cost:IsA("TextLabel") then
        cost.Text=City.compactPrice(self.callbacks.formatNumber(Blueprint.price(self.state,kind)));cost.TextColor3=City.priceColor(slotState)
    end
    local count=card:FindFirstChild("Count")
    if count and count:IsA("TextLabel") then
        local owned=if table.find(Blueprint.Order,kind) then Blueprint.count(self.state,kind) else 0
        count.Text="×"..owned;count.Visible=owned>0;count.TextColor3=HudTheme.Muted
        count.TextTransparency=if blocked then .45 else 0
        -- The decorative corner hatch yields its corner to the owned badge.
        local hatch=card:FindFirstChild("PFHatch")
        if hatch and hatch:IsA("GuiObject") then hatch.Visible=owned==0 end
    end
    local icon=card:FindFirstChild("Icon")
    if icon and icon:IsA("ImageLabel") then icon.ImageTransparency=if blocked then .72 else 0 end
    local shortcut=card:FindFirstChild("Shortcut")
    if shortcut and shortcut:IsA("TextLabel") then shortcut.TextTransparency=if blocked then .5 else 0 end
    if blocked and not selected and card:GetAttribute("Hovered")~=true then card.BackgroundColor3=HudTheme.Blocked end
end
function City:refreshSlotNavigation()
    if self.destroyed then return end
    local columns=self.palette:GetAttribute("HudColumns") or (if self.ui.AbsoluteSize.X<640 then 3 else 9)
    local slider=self.ui.Controls.AttackSlider.Input
    local cancel=self.placement.Cancel
    slider.NextSelectionLeft=slider;slider.NextSelectionRight=slider;slider.NextSelectionDown=slider
    cancel.NextSelectionLeft=cancel;cancel.NextSelectionRight=cancel
    cancel.NextSelectionDown=if HudControls.available(slider) then slider else cancel
    local down=if HudControls.available(cancel) then cancel else slider
    -- PF012: the top-left icon bar's magnifier replaced the old Focus button.
    local bar=self.ui:FindFirstChild("PFIconBar")
    local up=(bar and bar:FindFirstChild("Locate")) or self.ui.Navigation.Focus
    self.firstSlot=HudControls.link(self.slots,columns,up,down)
    for _,name in {"Settings","Speed","Exit"} do
        self.ui.GameRightSidebar[name].NextSelectionDown=self.firstSlot
    end
    for _,name in {"Leave","Settings"} do
        local disc=bar and bar:FindFirstChild(name)
        if disc and HudControls.available(disc) then disc.NextSelectionDown=self.firstSlot end
    end
    local selected=GuiService.SelectedObject
    if selected and selected:IsDescendantOf(self.ui) and not HudControls.available(selected) then
        GuiService.SelectedObject=nil
    end
end
function City:firstBlueprint(): GuiObject?
    self:refreshSlotNavigation()
    return self.firstSlot
end
-- PF020 console hotbar (Ashton: "similar to minecraft inventory"): the bumpers move one
-- selected build slot left/right with a wrap, buildings then nukes, and equip it, so A
-- places it at the target with the ghost preview; the slot is raised and lit and its cost
-- turns red when unaffordable (paintSlot). Disabled kinds are skipped. The first press
-- selects the last hotbar slot used, or the first slot.
City.HotbarOrder=table.freeze((function() local order=table.clone(Blueprint.Order);for _,kind in Blueprint.Nuclear do table.insert(order,kind) end;return order end)())
function City:cycleHotbar(direction: number): boolean
    local order=City.HotbarOrder;local count=#order
    local current=if self.ghostActive then table.find(order,self.ghostKind) else nil
    local first=current==nil
    local start=current or self.hotbarIndex
    for step=0,count-1 do
        local index
        if start==nil then index=step+1
        elseif first and step==0 then index=start
        else index=(start-1+direction*(if first then step else step+1))%count+1 end
        local kind=order[index]
        if Blueprint.enabled(self.state,kind) then
            if not self:equip(kind) then return false end
            self.hotbarIndex=index;self.hotbarEquipped=true;self:refreshBlueprints()
            return true
        end
    end
    return false
end
function City:equip(kind: string): boolean
    if not self:canEquipSlot() or not Blueprint.enabled(self.state,kind) then return false end
    self.hotbarEquipped=false
    self:dismissMenu()
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.ui) then GuiService.SelectedObject=nil end
    self.ghostActive=true;self.ghostKind=kind;self.multiplier=1;self.placementFeedback=nil;self.previewQuery=nil;self.previewTile=nil;self.pinnedTile=nil
    self.ui:SetAttribute("GhostStructure",kind);self.ui:SetAttribute("UpgradeMultiplier",1)
    self.radial.Visible=false;self.lastPreview=-math.huge
    if self.callbacks.blueprintEquipped then self.callbacks.blueprintEquipped(kind) end
    endPremium(self) -- PIVOT D12: a blueprint ends an armed premium item
    self:refreshBlueprints()
    if okBuildAnim and self.blueprints[kind] then (BuildAnim :: any).press(self.blueprints[kind],false) end
    return true
end
function City:dismissMenu(): boolean self:retireCatalog();return false end
function City:dispatch(q: any,tile: number,amount: number)
    if q.canUpgrade~=nil and q.canUpgrade~=false then self.callbacks.send("Upgrade",{unitId=q.canUpgrade,amount=amount})
    elseif q.canBuild~=nil and q.canBuild~=false then self.callbacks.send("Build",{unitType=q.type or "City",targetId=tile,
        directionUp=if q.type=="Atom Bomb" or q.type=="Hydrogen Bomb" then self.rocketDirectionUp else nil,
        amount=if q.type=="Atom Bomb" then amount else nil})
        if okBuildAnim then -- PF - 4: the placed kind's card confirms (+ its cost floats up)
            local placed=q.type or "City";for k,source in SOURCE_NAMES do if source==placed then placed=k end end
            local card=self.blueprints[placed]
            if card and card.Visible then (BuildAnim :: any).confirm(card,false,if type(q.cost)=="number" and q.cost>0 then self.callbacks.formatNumber(q.cost) else nil) end
        end
    end
end
function City:openRadial(tile: number)
    pcall(function() require(script.Parent.StatsReport).open("Build") end) -- STATS v3: a UI open
    self.navigationUntil=0;self.selectedItemName=nil;self.radialTile=tile;self.level=0;self.radialKind="City";self.attackSubmenu=false;self:retireCatalog();self.hover=nil;self:applyLevel(false);self:refreshRadial()
end
function City:isSubmenu(): boolean return self.level>0 end
function City:applyLevel(animate: boolean)
    self:refreshBuildConfiguration()
    local own=self.state and self.radialTile and self.state.owners[self.radialTile]==1
    self.actions.Visible=true
    self.actions.Root.Build.Visible=own==true;self.actions.Root.Delete.Visible=own==true
    self.actions.Root.Boat.Visible=not own
    self.actions.Root.Attack.Visible=not own
    if self.actions.Root:FindFirstChild("Info") then self:refreshDiplomacy() end
    for i,name in {"Root","City","Bulk"} do
        local level=i-1;local group=self.actions[name]
        group.Visible=level==self.level or level==self.level-1
        local scale=if level==self.level then 1 elseif self.level==1 then .65 else .5
        if animate and level==self.level then
            group.Scale.Scale=.5
            self:animateScale(group.Scale,scale,.3)
        else group.Scale.Scale=scale end
    end
    self.actions.Warship.Visible=self.attackSubmenu and self.level==1 and #(self.attackOrder or ATTACK_ORDER)>0
    if self.attackSubmenu then self.actions.City.Visible=false end
    self.actions.Warship.Scale.Scale=1
    if animate and self.attackSubmenu and self.level==1 then
        self.actions.Warship.Scale.Scale=.5
        self:animateScale(self.actions.Warship.Scale,1,.3)
    end
    local back=self.level>0
    self.radial.Attack.Back.Visible=back
    self.radial.Attack.Text=if back then "" else "Attack"
    self.radial.Attack.Size=UDim2.fromOffset(if back then 48 else 60,if back then 48 else 60)
    if back then self.radial.Attack.Active=true;self.radial.Attack.BackgroundColor3=Color3.fromRGB(15,39,68) end
    self:placeRadial(nil)
    self.actions:SetAttribute("Level",self.level)
end
-- PF022 (MM): the radial sits in the free band between the HUD's top row and the dock, at most ~60% of
-- the screen height: on small screens it shrinks through the authored Radial.PFScale (author-pf022-
-- player-actions) and near any edge it shifts, never clips. point = the clicked spot in Game-local
-- pixels; nil keeps the current centre (a level change re-fits for the larger submenu ring).
function City.radialFit(size: Vector2,top: number,bottom: number,center: Vector2,ring: number): (Vector2,number)
    local reach=ring+10
    local band=math.max(0,bottom-top)
    local scale=math.clamp(math.min(1,band/(2*reach),size.X/(2*reach),size.Y*.6/(2*ring)),.5,1)
    local r=reach*scale
    local x=if size.X<2*r then size.X/2 else math.clamp(center.X,r,size.X-r)
    local y=if band<2*r then (top+bottom)/2 else math.clamp(center.Y,top+r,bottom-r)
    return Vector2.new(math.floor(x+.5),math.floor(y+.5)),scale
end
function City:radialBand(): (number,number)
    local ui=self.ui;local origin,size=ui.AbsolutePosition,ui.AbsoluteSize
    local top,bottom=math.max(0,-origin.Y),size.Y
    local function visible(node: Instance?): boolean return node~=nil and node:IsA("GuiObject") and HudControls.visible(node) end
    -- The top row's controls (PF018) and the dock with its build bar (PF012/PF013).
    for _,name in {"PFTopRow","PFIconBar","ClockPanel"} do
        local node=ui:FindFirstChild(name)
        if visible(node) then local y1=(node :: GuiObject).AbsolutePosition.Y+(node :: GuiObject).AbsoluteSize.Y-origin.Y;if y1<size.Y*.35 then top=math.max(top,y1+4) end end
    end
    local controls=ui:FindFirstChild("Controls")
    for _,node in {controls,controls and controls:FindFirstChild("Blueprints")} do
        if visible(node) then local y0=(node :: GuiObject).AbsolutePosition.Y-origin.Y;if y0>size.Y*.5 then bottom=math.min(bottom,y0-4) end end
    end
    return top,bottom
end
function City:placeRadial(point: Vector2?)
    local radial=self.radial;local size=self.ui.AbsoluteSize
    local center=point or Vector2.new(radial.Position.X.Offset,radial.Position.Y.Offset)
    local top,bottom=self:radialBand()
    local position,scale=City.radialFit(size,top,bottom,center,if self.level>0 then 140 else 95)
    radial.Position=UDim2.fromOffset(position.X,position.Y)
    local node=radial:FindFirstChild("PFScale")
    if node and node:IsA("UIScale") then node.Scale=scale;self.radialScale=scale else self.radialScale=1 end
end
-- Disabled root slices (Build/Attack/Delete/Boat): why, in a few characters.
function City:rootReason(name: string): string?
    if not self.state then return nil end
    if self.state.phase=="Choosing" then return "Spawning" end
    if name=="Boat" then return "No route" end
    if name=="Delete" then return if City.deleteCooldown(self.state)>0 then nil else "None near" end
    return nil
end
-- Console (X / Square opens the radial): the stick points at a slice with the mouse's own angle math, at the ring's
-- middle radius; the D-pad walks the ring's slices in order. Both only move the highlight; A activates it.
local function radialRing(self: any): (number,number,number)
    local inner=if self.level==0 then 40 else 75;local outer=if self.level==0 then 95 else 140
    local count=if self.level==1 then #(if self.attackSubmenu then self.attackOrder or ATTACK_ORDER else self.structureOrder or STRUCTURE_ORDER) else 4
    return (inner+outer)/2,count,inner
end
local function radialPoint(self: any,angle: number,radius: number): Vector2
    local center=self.radial.AbsolutePosition+self.radial.AbsoluteSize/2
    return center+Vector2.new(math.sin(angle),-math.cos(angle))*radius*(self.radialScale or 1)
end
function City:aimRadial(direction: Vector2)
    if not self.radial.Visible or direction.Magnitude<.5 then return end
    local radius=radialRing(self)
    self:hoverAt(radialPoint(self,math.atan2(direction.X,-direction.Y),radius))
end
function City:stepRadial(step: number)
    if not self.radial.Visible then return end
    local radius,count=radialRing(self)
    if count<1 then return end
    local points,current={},nil
    for index=1,count do
        local point=radialPoint(self,(index-1)*2*math.pi/count,radius)
        local name=self:itemAt(point)
        if name then table.insert(points,point);if name==self.hover then current=#points end end
    end
    if #points==0 then return end
    local nextIndex=if current then (current-1+step)%#points+1 elseif step>0 then 1 else #points
    self:hoverAt(points[nextIndex])
end
function City:back(): boolean
    if self.level==0 then return false end
    self.navigationUntil=os.clock()+.24;self.level-=1;if self.level==0 then self.selectedItemName=nil end;self.hover=nil;self.tooltip.Visible=false;self:applyLevel(true);self:refreshRadial();return true
end
function City:itemAt(position: Vector2): string?
    if not self.actions.Visible or not self.radial.Visible then return nil end
    -- PF022: radii are in design pixels; the authored PFScale shrinks the ring on small screens.
    local p=(position-(self.radial.AbsolutePosition+self.radial.AbsoluteSize/2))/(self.radialScale or 1)
    local r=p.Magnitude;local inner=if self.level==0 then 40 else 75;local outer=if self.level==0 then 95 else 140
    if r<inner or r>outer then return nil end
    local angle=math.atan2(p.X,-p.Y)
    if self.level==1 then
        local order=if self.attackSubmenu then self.attackOrder or ATTACK_ORDER else self.structureOrder or STRUCTURE_ORDER
        if #order==0 then return nil end
        if #order==1 then return order[1] end -- d3's full-annulus arc ignores padding.
        local sector=2*math.pi/#order
        local index=math.floor(((angle+sector/2)%(math.pi*2))/sector)+1
        local middle=(index-1)*sector
        local deviation=math.abs((angle-middle+math.pi)%(2*math.pi)-math.pi)
        local gap=math.asin(math.sqrt(inner*inner+outer*outer)*math.sin(.015)/r)
        return if deviation>sector/2-gap then nil else order[index]
    end
    local index=math.floor(((angle+math.pi/4)%(math.pi*2))/(math.pi/2))+1
    -- d3 arc padAngle=.03; keep the exact visible gap non-interactive.
    local middle=(index-1)*math.pi/2
    local deviation=math.abs((angle-middle+math.pi)%(2*math.pi)-math.pi)
    local gap=math.asin(math.sqrt(inner*inner+outer*outer)*math.sin(.015)/r)
    if deviation>math.pi/4-gap then return nil end
    if self.level==0 then
        if self.rootItems then return self.rootItems[index].name end
        local own=self.state.owners[self.radialTile]==1
        return if index==2 then (if own then "Delete" else "Boat") elseif index==4 then (if own then "Build" else "Attack") else nil
    end
    return BULK_NAMES[index]
end
function City:refreshDiplomacy()
    if not self.state or not self.state.diplomacy or not self.radialTile then return end
    local hasAttack=false;for _,kind in self.attackOrder or ATTACK_ORDER do if self:query(self.radialTile,kind).canBuild~=false then hasAttack=true;break end end
    self.rootItems=DP.root(self.state,self.radialTile,hasAttack)
    for _,name in {"Info","Alliance","BreakAlliance","DonateGold","Build","Attack","Delete","Boat"} do self.actions.Root[name].Visible=false end
    local owner=self.state.owners[self.radialTile];local query=if owner>0 then Diplomacy.interaction(self.state,1,owner) else nil
    for _,item in self.rootItems do
        local name=item.name;local button=self.actions.Root[if name=="AllianceRequest" or name=="AllianceExtend" then "Alliance" else name];button.Visible=true
        if name=="Info" or name=="AllianceRequest" or name=="AllianceExtend" or name=="BreakAlliance" or name=="DonateGold" then
            local color=if name=="Info" then DP.COLORS.Info elseif name=="BreakAlliance" then (if Diplomacy.isTraitor(self.state,owner) or self.state.players[owner].isDisconnected then DP.COLORS.SafeBreak else DP.COLORS.Break) elseif name=="DonateGold" then DP.COLORS.DonateGold else DP.COLORS.Alliance
            button.ImageColor3=if item.enabled then (if self.hover==name then brighten(color) else color) else PLATE
            button.ImageTransparency=if item.enabled then .18 else PLATE_ALPHA;button.Icon.ImageTransparency=if item.enabled then 0 else .45;button:SetAttribute("Enabled",item.enabled)
            local reason=button:FindFirstChild("PFReason")
            if reason and reason:IsA("TextLabel") then
                local text=if item.enabled then nil else ActionModel.sliceReason(self.state,name,owner)
                reason.Text=text or "";reason.Visible=text~=nil
            end
            if name=="AllianceRequest" or name=="AllianceExtend" then
                local extension=name=="AllianceExtend";button.Icon.Visible=not extension;button.ExtendLeft.Visible=extension;button.ExtendRight.Visible=extension
                button:SetAttribute("ExtensionFraction",if extension then DP.extensionFraction(self.state,1,owner) else 1)
                button:SetAttribute("MyAgreed",extension and query.allianceInfo.myPlayerAgreedToExtend or false);button:SetAttribute("OtherAgreed",extension and query.allianceInfo.otherAgreedToExtend or false)
                local gradient=button.TimerGradient;gradient.Enabled=extension;gradient.Rotation=90
                if extension then local cut=1-DP.extensionFraction(self.state,1,owner);local base=if item.enabled then color else PLATE;local faded=base:Lerp(Color3.new(1,1,1),.4)
                    if cut<=0 then gradient.Color=ColorSequence.new(base) elseif cut>=1 then gradient.Color=ColorSequence.new(faded) else gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,faded),ColorSequenceKeypoint.new(math.max(.000001,cut-.000001),faded),ColorSequenceKeypoint.new(math.min(.999999,cut+.000001),base),ColorSequenceKeypoint.new(1,base)}) end
                    button.ImageColor3=Color3.new(1,1,1)
                end
            end
        end
    end
    if self.level==0 then
        local friendly=owner>0 and DP.friendly(self.state,1,owner) and not self.state.players[owner].isDisconnected
        self.radial.Attack.Text="";Icons.bind(self.radial.Attack.Back,if friendly then "DiplomacyDonateTroops" else "Sword");self.radial.Attack.Back.Visible=true
        self.radial.Attack.Back.Size=UDim2.fromOffset(if friendly then 24 else 32,if friendly then 24 else 32)
        self.radial.Attack.Back.Position=UDim2.fromScale(.5,.5);self.radial.Attack.Back.AnchorPoint=Vector2.new(.5,.5)
        -- the centre's only painter (tester round 2026-10-13, JiN: "the middle icon jitters"): MatchController also
        -- repainted it every packet, so it flipped between its colours and these
        local attackable=self.callbacks.canAttackAt~=nil and self.callbacks.canAttackAt(self.radialTile)==true
        self.radial.Attack.BackgroundColor3=if friendly then Color3.fromHex("#22d3ee") elseif attackable then Color3.fromRGB(15,39,68) else Color3.fromRGB(153,153,153)
        self.radial.Attack.Active=if friendly then query.canDonateTroops else attackable
        self.radial.Attack.AutoButtonColor=self.radial.Attack.Active
    else Icons.bind(self.radial.Attack.Back,"Back") end
end
function City:refreshRadial()
    if not self.state or not self.radialTile then return end
    self:refreshBuildConfiguration()
    self.radialQuery=self:query(self.radialTile,self.radialKind)
    local q=self.radialQuery
    local max=self:bulkMaximum(q)
    self.amounts=if q.type=="Atom Bomb" then {1,2,5,max} else {1,5,10,max};self.deleteId=City.deleteTarget(self.state,self.radialTile)
    local cooldown=City.deleteCooldown(self.state)
    self.actions.Root.Delete.Cooldown.Text=if cooldown>0 then tostring(math.ceil(cooldown)).."s" else ""
    for _,name in {"Build","Attack","Delete","Boat","City","Port","Factory","DefensePost","MissileSilo","SAMLauncher","AtomBomb","MIRV","HydrogenBomb","Warship","Top","Right","Bottom","Left"} do
        local building=table.find(STRUCTURE_ORDER,name)~=nil or table.find(ATTACK_ORDER,name)~=nil
        local item=if name=="Build" or name=="Attack" or name=="Delete" or name=="Boat" then self.actions.Root[name] elseif table.find(STRUCTURE_ORDER,name) then self.actions.City[name] elseif table.find(ATTACK_ORDER,name) then self.actions.Warship[name] else self.actions.Bulk[name]
        if building and not item.Visible then item:SetAttribute("Enabled",false);continue end
        local itemQuery=if building then self:query(self.radialTile,name) else q
        local enabled=if name=="Build" or name=="Attack" then self.state.phase~="Choosing" elseif name=="Delete" then self.deleteId~=nil
            elseif name=="Boat" then self.callbacks.canBoatAt~=nil and self.callbacks.canBoatAt(self.radialTile)~=false elseif building then itemQuery.canBuild~=false or itemQuery.canUpgrade~=false
            else (q.canUpgrade~=false or q.type=="Atom Bomb") and self.amounts[table.find(BULK_NAMES,name)]<=max
        local rootSlice=name=="Build" or name=="Attack" or name=="Delete" or name=="Boat"
        local color=if enabled then (if table.find(ATTACK_ORDER,name) then COLORS.Attack else COLORS[name] or COLORS.City) elseif rootSlice then PLATE else Color3.fromRGB(128,128,128)
        item.ImageColor3=if self.hover==name and enabled then brighten(color) else color
        item.ImageTransparency=if enabled then .18 elseif rootSlice then PLATE_ALPHA else .8
        local reason=if rootSlice then item:FindFirstChild("PFReason") else nil
        if reason and reason:IsA("TextLabel") then local text=if enabled then nil else self:rootReason(name);reason.Text=text or "";reason.Visible=text~=nil end
        item:SetAttribute("Enabled",enabled)
        local foreground=item:FindFirstChild("Icon") or item:FindFirstChild("Amount")
        if foreground:IsA("ImageLabel") then foreground.ImageTransparency=if enabled then 0 else .5
        else foreground.TextTransparency=if enabled then 0 else .5;foreground.Text="x"..self.amounts[table.find(BULK_NAMES,name)] end
    end
    if self.actions.Root:FindFirstChild("Info") then self:refreshDiplomacy() end
end
function City:sliceEnabled(name: string): boolean
    local group=if table.find(STRUCTURE_ORDER,name) then self.actions.City elseif table.find(ATTACK_ORDER,name) then self.actions.Warship elseif table.find(BULK_NAMES,name) then self.actions.Bulk else self.actions.Root
    local item=group:FindFirstChild(if name=="AllianceRequest" or name=="AllianceExtend" then "Alliance" else name)
    return item~=nil and item.Visible and item:GetAttribute("Enabled")==true
end
function City:activate(name: string?)
    if not name or not self.state or not self.radialTile then return end
    self:refreshRadial()
    if not self:sliceEnabled(name) or os.clock()<(self.navigationUntil or 0) then return end
    if self.callbacks.playSound then self.callbacks.playSound("click") end
    local rootSlice=not table.find(STRUCTURE_ORDER,name) and not table.find(ATTACK_ORDER,name) and not table.find(BULK_NAMES,name)
    if self.level>0 and rootSlice and name~=self.selectedItemName then return end
    if name=="Info" or name=="AllianceRequest" or name=="AllianceExtend" or name=="BreakAlliance" or name=="DonateGold" then
        local item=self.actions.Root[if name=="AllianceRequest" or name=="AllianceExtend" then "Alliance" else name];if item:GetAttribute("Enabled")~=true then return end
        if self.callbacks.diplomacyAction then self.callbacks.diplomacyAction(name,self.radialTile) end;self.radial.Visible=false;return
    end
    if name=="Build" then if #(self.structureOrder or STRUCTURE_ORDER)==0 then return end;self.attackSubmenu=false;self.level=1
    elseif name=="Attack" then if #(self.attackOrder or ATTACK_ORDER)==0 then return end;self.attackSubmenu=true;self.level=1
    elseif name=="Boat" then
        if not self.callbacks.launchBoat or not self.callbacks.launchBoat(self.radialTile) then return end
        self.radial.Visible=false;return
    elseif name=="Delete" then
        if not self.deleteId then return end
        self.callbacks.send("Delete",{unitId=self.deleteId});self.radial.Visible=false;return
    elseif table.find(STRUCTURE_ORDER,name) or table.find(ATTACK_ORDER,name) then
        self.radialKind=name;self:refreshRadial()
        local q=self.radialQuery
        if (q.canUpgrade~=false or (q.type=="Atom Bomb" and q.canBuild~=false)) and self:bulkMaximum(q)>1 then self.level=2
        elseif q.canBuild~=false or q.canUpgrade~=false then self:dispatch(q,self.radialTile,1);self.radial.Visible=false;return
        else return end
    else
        local index=table.find(BULK_NAMES,name)
        local amount=index and self.amounts[index]
        if not amount or amount<1 or amount>self:bulkMaximum(self.radialQuery) then return end
        self:dispatch(self.radialQuery,self.radialTile,amount);self.radial.Visible=false;return
    end
    self.selectedItemName=name;self.navigationUntil=os.clock()+.24;self.hover=nil;self.tooltip.Visible=false;self:applyLevel(true);self:refreshRadial()
end
function City:hoverAt(position: Vector2)
    local name=self:itemAt(position)
    if self.hover~=name then self.hover=name;self:refreshRadial() end
    -- Source Boat slot has no build tooltip; only build/delete cards use this.
    self.tooltip.Visible=name~=nil and name~="Build" and name~="Attack" and name~="Boat" and name~="Info" and name~="AllianceRequest" and name~="AllianceExtend" and name~="BreakAlliance" and name~="DonateGold"
    if not self.tooltip.Visible then return end
    local deleting=name=="Delete"
    local q=if table.find(STRUCTURE_ORDER,name) or table.find(ATTACK_ORDER,name) then self:query(self.radialTile,name) else self.radialQuery
    local index=table.find(BULK_NAMES,name)
    local amount=if index then self.amounts[index] else 1
    self.tooltip.Title.Text=if deleting then "Delete Unit" elseif index then "Upgrade x"..amount elseif name=="DefensePost" then "Defense Post" else SOURCE_NAMES[name] or name
    self.tooltip.Description.Text=if deleting then "Click to delete the nearest unit" elseif index then "" else DESCRIPTIONS[name] or ""
    local cost=if index then (q.upgradeCosts and q.upgradeCosts[amount]) or q.cost*amount else q.cost
    self.tooltip.Cost.Text=if deleting then "" else self.callbacks.formatNumber(cost).." Gold"
    self.tooltip.Count.Text=if deleting or index or name=="AtomBomb" or name=="HydrogenBomb" or name=="MIRV" then "" else tostring(self:completedLevels(name)).."x"
    self.tooltip.Cost.Position=UDim2.fromOffset(10,if index then 27 else 46)
    local function measured() if not self.destroyed and self.radial.Visible then self:hoverAt(position) end end
    local width=math.min(270,math.max(TextBounds.measure(self.tooltip.Description,250,measured).X,
        TextBounds.measure(self.tooltip.Title,250,measured).X)+20)
    self.tooltip.Size=UDim2.fromOffset(width,if deleting or index then 48 else 82)
    local p=position-self.ui.AbsolutePosition+Vector2.new(10,10)
    self.tooltip.Position=UDim2.fromOffset(p.X,p.Y)
end
function City:clearGhost()
    self:closeNukeConfirm()
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.placement) then GuiService.SelectedObject=nil end
    self.ghostActive=false;self.ghostKind=nil;self.multiplier=1;self.previewTile=nil;self.previewQuery=nil;self.placementFeedback=nil;self.pinnedTile=nil;self.buildings:hideGhost()
    self.placement:SetAttribute("QuotedPrice",nil)
    self.ui:SetAttribute("GhostStructure",nil);self.ui:SetAttribute("UpgradeMultiplier",1)
    if self.callbacks.weaponsGhost then self.callbacks.weaponsGhost(nil) end
    endPremium(self) -- PIVOT D12: Cancel / Esc end an armed premium item too
    self:refreshBlueprints()
end
function City:key(key: Enum.KeyCode,position: Vector2?): boolean
    if self.destroyed then return false end
    if key==Enum.KeyCode.Escape then self:clearGhost();self:dismissMenu();return false end
    if not self.callbacks.canPlay() then return false end
    if BUILD_KEYS[key] then
        local kind=BUILD_KEYS[key]
        if not self:canEquipSlot() or not Blueprint.enabled(self.state,kind) then return false end
        if self.ghostActive and self.ghostKind==kind then self.multiplier=if self.multiplier==1 then 5 else 1
        elseif not self:equip(kind) then return false end
        self.ui:SetAttribute("GhostStructure",kind);self.ui:SetAttribute("UpgradeMultiplier",self.multiplier)
        self.radial.Visible=false;self:dismissMenu();self.lastPreview=-math.huge;self:refreshBlueprints();return true
    elseif key==Enum.KeyCode.U then self.rocketDirectionUp=not self.rocketDirectionUp;self.ui:SetAttribute("RocketDirectionUp",self.rocketDirectionUp);self.lastPreview=-math.huge;return true
    elseif (key==Enum.KeyCode.Return or key==Enum.KeyCode.KeypadEnter) and self.ghostActive and position then self:confirm(position);return true end
    return false
end
-- PF019 W7 S3 Confirm before nukes (default On): "Launch Atom Bomb on Texas?" before any
-- Atom Bomb, Hydrogen Bomb or MIRV fires. The prompt is authored (Game.PF019NukeConfirm,
-- tools/atlas/author-pf019-nuke-confirm.luau); without it, nukes fire as before.
local NUKES={["Atom Bomb"]=true,["Hydrogen Bomb"]=true,MIRV=true}
function City:askNukeConfirm(q: any,tile: number,amount: number): boolean
    if not NUKES[q.type] or not self.preferences or self.preferences:get("confirmNukes")~=true then return false end
    local prompt=self.ui:FindFirstChild("PF019NukeConfirm");if not prompt then return false end
    if not self.nukePromptBound then
        self.nukePromptBound=true
        local panel=prompt.Panel
        table.insert(self.connections,panel.Launch.Activated:Connect(function()
            local pending=self.pendingNuke;self:closeNukeConfirm()
            if pending and self.state then self:dispatch(pending.q,pending.tile,pending.amount);self:afterLaunch() end
        end))
        for _,button in {panel.Cancel,prompt.Backdrop} do table.insert(self.connections,button.Activated:Connect(function()self:closeNukeConfirm()end)) end
    end
    self.pendingNuke={q=q,tile=tile,amount=amount}
    local owner=self.state.owners[tile];local target=if owner and owner>0 then Names.resolve(self.state,owner,self.preferences) else ""
    prompt.Panel.Title.Text="Launch "..q.type..(if target~="" and owner~=1 then " on "..target elseif owner==1 then " on your own land" else " here").."?"
    local body=prompt.Panel:FindFirstChild("Body");if body and body:IsA("GuiObject") and prompt:GetAttribute("PF040Trimmed") then body.Visible=false end
    prompt.Visible=true
    if UserInputService.PreferredInput==Enum.PreferredInput.Gamepad then GuiService.SelectedObject=prompt.Panel.Cancel end
    return true
end
function City:closeNukeConfirm()
    self.pendingNuke=nil
    local prompt=self.ui:FindFirstChild("PF019NukeConfirm")
    if prompt and prompt.Visible then prompt.Visible=false;if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(prompt) then GuiService.SelectedObject=nil end end
end
function City:nukeConfirmOpen(): boolean return self.pendingNuke~=nil end
-- Tester round 2026-10-13 (Tenzo, mobile: "the nuke got stuck and wouldn't launch. I also couldn't access anything
-- related to my city"): a launched Atom/Hydrogen bomb stays armed for the next shot (mouse: Esc / right-click put it
-- away). On touch every later tap fired at the map instead (no missile ready: nothing), so a touch launch puts it away.
function City:afterLaunch()
    if self.ghostActive and (self.ghostKind=="AtomBomb" or self.ghostKind=="HydrogenBomb") and InputPrompts.mode()=="Touch" then self:clearGhost() end
end
function City:confirm(position: Vector2): boolean
    if not self.ghostActive then return false end
    if not self:canEquipSlot() or (self.callbacks.canConfirmPreview and not self.callbacks.canConfirmPreview(position)) then return true end
    local tile=self.callbacks.targetAt(position)
    -- PF-040: on touch a tap only places a nuke's target (Launch on the aim bar fires it)
    if tile and NUKE_KINDS[self.ghostKind] and InputPrompts.mode()=="Touch" then
        self.pinnedTile=tile;self.lastPreview=-math.huge;self:refreshBlueprints();return true
    end
    if tile then
        local q=self:query(tile,self.ghostKind)
        if (q.canBuild~=nil and q.canBuild~=false) or (q.canUpgrade~=nil and q.canUpgrade~=false) then
            if q.canUpgrade==false and self:shouldBlockRecentAllyNuke(tile,q.type) then return true end
            if not self:askNukeConfirm(q,tile,self.multiplier) then self:dispatch(q,tile,self.multiplier);self:afterLaunch() end
            if self.ghostKind~="AtomBomb" and self.ghostKind~="HydrogenBomb" then self:clearGhost() end
        else
            local price=Blueprint.price(self.state,self.ghostKind)
            local missile=(self.ghostKind=="AtomBomb" or self.ghostKind=="HydrogenBomb") and self:readyMissiles()<=0
            self.placementFeedback=if self.state.gold[1]<price then "Need "..self.callbacks.formatNumber(price-self.state.gold[1]).." more gold"
                elseif missile then "No missile ready · wait for a silo to reload" elseif self.ghostKind=="Port" then "Place ports on your coastline" else "Can't place here · choose another spot"
            self.placementFeedbackUntil=os.clock()+2.5;self:refreshBlueprints()
        end
    end
    return true
end
function City:draw(zoom: number,viewport: Frame,position: Vector2?)
    if self.destroyed then return end
    self.buildings:draw(zoom,viewport)
    self.bonuses:draw(zoom,viewport)
    if not self.state then return end
    local now=os.clock()
    if self.gainStarted then
        local elapsed=now-self.gainStarted
        if elapsed>=2 then self.gainStarted=nil;self.gain.Visible=false
        else
            local progress=if self:motionAllowed() then City.goldPipProgress(elapsed) else 1
            self.gain.Visible=self.ui.Visible and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                and (not self.callbacks.canSelectBlueprint or self.callbacks.canSelectBlueprint())
            -- Content motion: the authored label drifts up 4 design px inside Gold (160×50).
            self.gain.Position=UDim2.fromScale(1-9/160,(-20+4*(1-progress))/50)
            self.gain.Value.TextTransparency=1-progress
            self.gain.Shadow.TextTransparency=1-progress*.9
        end
    end
    self:retireCatalog()
    if self.radial.Visible and now-self.lastRadial>=.5 then self.lastRadial=now;self:refreshRadial() end
    local allianceSlot=self.actions.Root:FindFirstChild("Alliance")
    if self.radial.Visible and allianceSlot and allianceSlot.ExtendLeft.Visible then
        local enabled=allianceSlot:GetAttribute("Enabled")==true;local phase=(now%1.5)/1.5;local pulse=if phase<.5 then 1-phase*1.6 else .2+(phase-.5)*1.6
        allianceSlot.ExtendLeft.ImageTransparency=1-(if allianceSlot:GetAttribute("MyAgreed") then (if enabled then 1 else .5) else pulse*(if enabled then 1 else .5))
        allianceSlot.ExtendRight.ImageTransparency=1-(if allianceSlot:GetAttribute("OtherAgreed") then (if enabled then 1 else .5) else pulse*(if enabled then 1 else .5))
    end
    if self.ghostActive and self.pinnedTile and NUKE_KINDS[self.ghostKind] and InputPrompts.mode()=="Touch" then
        local w=self.state.map.width;local id=self.pinnedTile-1
        position=self.world.AbsolutePosition+Vector2.new((id%w+.5)*zoom,(id//w+.5)*zoom)
    elseif self.ghostActive and NUKE_KINDS[self.ghostKind] and InputPrompts.mode()=="Touch" then position=nil end
    if not self.ghostActive or not position or (self.callbacks.canSelectBlueprint and not self.callbacks.canSelectBlueprint()) or not self.callbacks.isMapPointer(position) then self.buildings:hideGhost();if self.callbacks.weaponsGhost then self.callbacks.weaponsGhost(nil) end;return end
    local tile=self.callbacks.targetAt(position)
    if not tile then self.buildings:hideGhost();if self.callbacks.weaponsGhost then self.callbacks.weaponsGhost(nil) end;return end
    local terrain=buffer.readu8(self.state.map.terrain,tile-1)
    if bit32.band(terrain,128)~=0 and bit32.band(terrain,31)==31 then
        self.buildings:hideGhost();if self.callbacks.weaponsGhost then self.callbacks.weaponsGhost(if self.ghostKind=="AtomBomb" or self.ghostKind=="HydrogenBomb" then self.ghostKind else nil,tile,position,self.previewQuery,self.rocketDirectionUp) end;return
    end
    if now-self.lastPreview>=.05 then self.previewTile=tile;self.previewQuery=self:query(tile,self.ghostKind);self.lastPreview=now;self:refreshBlueprints() end
    if self.previewQuery then self.buildings:drawGhost(zoom,position-self.world.AbsolutePosition,self.previewQuery,self.multiplier,self.callbacks.formatNumber) end
    if self.callbacks.weaponsGhost then self.callbacks.weaponsGhost(self.ghostKind,tile,position,self.previewQuery,self.rocketDirectionUp) end
end
return City
