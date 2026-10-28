--!strict
-- Battle HUD shell state. PF013: every panel's geometry is authored in the place
-- (Scale + UIAspectRatioConstraint/UISizeConstraint floors, see
-- tools/atlas/author-pf013-shell.luau), so the Edit-mode Device Emulator already
-- shows the real HUD. This module only sets content, visibility, focus and
-- interaction state. Its one geometry write is the icon bar's X, which follows
-- Roblox's own topbar cluster (its width varies with voice/chat; MM ruling);
-- PF018's top-row reserves mirror that same edge. The attack list's size is a
-- choice between two authored sizes by leaderboard state (no measuring).
local HudTheme=require(script.Parent.BattleHudTheme)
local HudPresentation=require(script.Parent.BattleHudPresentation)
local InputPrompts=require(script.Parent.InputPrompts)
local HudControls=require(script.Parent.BattleHudControls)
local Shell=require(script.Parent.BattleHudShell)
local GoldRateTracker=require(script.Parent.StatsGoldRateTracker)
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Interface={}
local Methods={};Methods.__index=Methods
local SLOTS={"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher","Warship","AtomBomb","HydrogenBomb","MIRV"}

-- Two boxes overlap (absolute screen space; reads only).
local function overlaps(a: GuiObject,b: GuiObject): boolean
    local ap,as,bp,bs=a.AbsolutePosition,a.AbsoluteSize,b.AbsolutePosition,b.AbsoluteSize
    return ap.X<bp.X+bs.X and bp.X<ap.X+as.X and ap.Y<bp.Y+bs.Y and bp.Y<ap.Y+as.Y
end

function Interface.new(gui: ScreenGui): any
    local root=gui.Background
    local self=setmetatable({gui=gui,root=root,game=root.Game,connections={},gamepad=false,selectionRevision=0,inputRevision=0},Methods)
    local function listen(signal,callback) table.insert(self.connections,signal:Connect(callback)) end
    -- PIVOT (Ashton 2026-10-26: Levels "Remove it"): the authored XP pill on the icon bar stays hidden (LevelsMatchController,
    -- which used to hide it, is gone)
    local iconBar=root.Game:FindFirstChild("PFIconBar");local pill=iconBar and iconBar:FindFirstChild("PFXpPill")
    if pill and pill:IsA("GuiObject") then pill.Visible=false end
    -- Selection feedback is inherited by authored buttons and runtime clones.
    local selected: GuiObject?=nil
    listen(GuiService:GetPropertyChangedSignal("SelectedObject"),function()
        self.selectionRevision+=1
        if selected then local border=selected:FindFirstChild("FocusBorder");if border and border:IsA("UIStroke") then border.Enabled=false end end
        selected=GuiService.SelectedObject
        if selected and selected:IsDescendantOf(gui) then
            local border=selected:FindFirstChild("FocusBorder");if border and border:IsA("UIStroke") then border.Enabled=true end
        end
    end)
    for _,entry in {{root.Home,root.Home.Body.Solo},{root.Lobby,root.Lobby.Body.Footer.Start},
        -- PF019 W7: the authored sheet keeps its tabs in the header bar.
        {root.UserSettings,(root.UserSettings:GetAttribute("PF019SettingsRevision") and root.UserSettings.Body.Header.Tabs.Gameplay) or root.UserSettings.Body.Tabs.Gameplay},{root.GameMenu,(root.GameMenu:GetAttribute("PF019GameMenu")==true and root.GameMenu:FindFirstChild("Panel")and root.GameMenu.Panel.Rows.Resume)or root.GameMenu.Body.Header.Back},
        {root.PublicWaiting,root.PublicWaiting.Body.Return},
        {root.Game.Result,root.Game.Result.Continue}} do
        local panel,first=entry[1],entry[2]
        listen(panel:GetPropertyChangedSignal("Visible"),function()
            if not panel.Visible and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then GuiService.SelectedObject=nil end
            if panel.Visible and self.gamepad then
                self:queuePanelFocus(panel,first)
            end
        end)
    end
    self.presentation=HudPresentation.new(gui)
    -- Disabled units hide their slot; the authored UIListLayout reflows the row,
    -- and controller links are rebuilt over the visible slots.
    local cards=self.game.Controls.Blueprints.Cards
    for _,name in SLOTS do
        local card=cards:FindFirstChild(name)
        if card then listen(card:GetPropertyChangedSignal("Visible"),function()
            if self.cities and self.cities.refreshSlotNavigation then self.cities:refreshSlotNavigation() end
        end) end
    end
    listen(self.game:GetAttributeChangedSignal("GhostStructure"),function() self:placementAction() end)
    listen(UserInputService:GetPropertyChangedSignal("PreferredInput"),function()
        self.inputRevision+=1;self:updateGamepadHelp()
    end)
    listen(self.game:GetPropertyChangedSignal("Visible"),function()
        self.game.GamepadReticle.Visible=false -- PF020: no console crosshair (the target is highlighted instead)
        self:refreshOverlays()
    end)
    -- Collapsing only hides the body; the guide's authored AutomaticSize follows.
    listen(self.game.TutorialGuide:GetAttributeChangedSignal("Collapsed"),function()
        local guide=self.game.TutorialGuide;local collapsed=guide:GetAttribute("Collapsed")==true
        guide.Message.Visible=not collapsed;guide.Progress.Visible=not collapsed
        self:refreshOverlays()
    end)
    listen(self.game:GetAttributeChangedSignal("PFNoticeStackHeight"),function() self:refreshOverlays() end)
    listen(self.game.Attacks:GetPropertyChangedSignal("Visible"),function() self:refreshOverlays() end)
    listen(self.game.NuclearActions:GetPropertyChangedSignal("Visible"),function() self:retireLegacy() end)
    listen(GuiService:GetPropertyChangedSignal("TopbarInset"),function() self:followTopbar() end)
    listen(self.game:GetPropertyChangedSignal("AbsolutePosition"),function() self:followTopbar() end)
    local board=self.game:FindFirstChild("PFLeaderboardRegion")
    if board then listen(board:GetAttributeChangedSignal("PFBoardExpanded"),function() self:followBoard() end) end
    listen(self.game.Controls.Placement:GetPropertyChangedSignal("Visible"),function() self:followBoard() end)
    -- the Premium wing and its grid fly-out (author-pivot-arsenal-wing) move the column too (layoutColumn)
    for _,name in {"PFArsenalWing","PFArsenalGrid"} do
        local item=self.game.Controls:FindFirstChild(name)
        if item and item:IsA("GuiObject") then
            listen(item:GetPropertyChangedSignal("Visible"),function() self:followBoard() end)
            listen(item:GetPropertyChangedSignal("AbsoluteSize"),function() self:followBoard() end)
        end
    end
    -- PF - 3 variant C: the Premium rail (fixed under the board) caps the attack column's top (layoutColumn)
    local rail=self.game:FindFirstChild("PFPremiumRail")
    if rail and rail:IsA("GuiObject") then
        listen(rail:GetPropertyChangedSignal("Visible"),function() self:followBoard() end)
        listen(rail:GetPropertyChangedSignal("AbsoluteSize"),function() self:followBoard() end)
        listen(rail:GetPropertyChangedSignal("AbsolutePosition"),function() self:followBoard() end) -- its authored phone variant
    end
    for _,item in {self.game,self.game.Controls} do listen(item:GetPropertyChangedSignal("AbsoluteSize"),function() self:followBoard() end) end
    -- PF019 W7 S9: a UI size change picks the regions' authored size variants.
    listen(self.game:GetAttributeChangedSignal("PF019UiSizeKey"),function() self:followTopbar();self:followBoard() end)
    local iconBar=self.game:FindFirstChild("PFIconBar")
    if iconBar then listen(iconBar:GetPropertyChangedSignal("AbsoluteSize"),function() self:followTopbar() end) end
    -- The notice column never rises into the tutorial tracker: follow which tracker card shows.
    local tracker=self.game:FindFirstChild("PFTracker")
    if tracker then
        listen(tracker:GetPropertyChangedSignal("Visible"),function() self:followBoard() end)
        for _,card in tracker:GetChildren() do if card:IsA("GuiObject") then
            listen(card:GetPropertyChangedSignal("Visible"),function() self:followBoard() end)
            listen(card:GetPropertyChangedSignal("AbsoluteSize"),function() self:followBoard() end)
        end end
    end
    self:retireLegacy();self:updateGamepadHelp();self:refreshOverlays();self:followTopbar();self:followBoard()
    return self
end

-- Native panel signals/layout can settle after the user moves focus or input mode.
-- Capture that intent now, then require the same ownership and eligible target.
function Methods:queuePanelFocus(panel: GuiObject,first: GuiObject)
    local selected=GuiService.SelectedObject
    if selected and not selected:IsDescendantOf(self.gui) then return end
    local selectionRevision,inputRevision=self.selectionRevision,self.inputRevision
    task.defer(function()
        if self.destroyed or not self.gamepad
            or (self.inputModeOverride or UserInputService.PreferredInput.Name)~="Gamepad"
            or self.selectionRevision~=selectionRevision or self.inputRevision~=inputRevision
            or GuiService.SelectedObject~=selected or GuiService.MenuIsOpen
            or UserInputService:GetFocusedTextBox()~=nil
            or not first:IsDescendantOf(panel) or not HudControls.available(first) then return end
        GuiService.SelectedObject=first
    end)
end

-- MatchController calls this on every settings change; PF019 W7 S11 Hotkey hints follow it.
function Methods:setPreferences(preferences: any)
    self.presentation:setPreferences(preferences);InputPrompts.setPreferences(preferences)
    -- PF020: the in-match selection ring (ReplicatedStorage.PFBattleSelection, authored by
    -- tools/atlas/author-pf020-console.luau) follows the interface accent.
    if not self.selectionFocus and preferences then
        local ok,folder=pcall(function() return game:GetService("ReplicatedStorage"):FindFirstChild("PFBattleSelection") end)
        if ok and folder then self.selectionFocus=require(script.Parent.LobbyAccentFocus).bind(folder,preferences) end
    end
    self:refreshOverlays()
end
function Methods:setBlocked(value: boolean)
    self.blocked=value;self.presentation:setBlocked(value)
    Shell.setActive(self.game:FindFirstChild("PFIconBar"),not value)
end
-- Top-left icon bar actions come from MatchController (existing focus/exit paths).
function Methods:bindIconBar(callbacks: any)
    local bar=self.game:FindFirstChild("PFIconBar")
    if not bar or self.iconBarBound then return end;self.iconBarBound=true
    for _,connection in Shell.bind(bar,callbacks,function() return not self.blocked and not self.destroyed end) do
        table.insert(self.connections,connection)
    end
    Shell.link(bar)
    for _,connection in Shell.holdStay(self.game:FindFirstChild("VariantExitConfirm")) do table.insert(self.connections,connection) end
    Shell.setActive(bar,not self.blocked)
end
-- The bar is authored in the topbar row at x=216 (8px right of the default
-- Unibar). In Play it tracks the free topbar area so a wider or narrower Roblox
-- cluster never overlaps it. Edit mode has no topbar: the authored X stays.
function Methods:followTopbar()
    local bar=self.game:FindFirstChild("PFIconBar")
    local inset=GuiService.TopbarInset
    if self.destroyed or not bar or not bar:IsA("GuiObject") or inset.Width<=0 then return end
    local x=math.floor(inset.Min.X-GuiService:GetGuiInset().X-self.game.AbsolutePosition.X+8+.5)
    if bar.Position.X.Offset~=x or bar.Position.X.Scale~=0 then bar.Position=UDim2.new(0,x,bar.Position.Y.Scale,bar.Position.Y.Offset) end
    -- PF018 top row: Lead reserves the icon row; the trails' basis mirrors it so
    -- the own-stats strip centres on screen whenever it fits.
    local row=self.game:FindFirstChild("PFTopRow")
    if row then
        local reserve=x+math.floor(bar.AbsoluteSize.X+.5)+8 -- laid out, so the UI size scale counts
        for _,name in {"Lead","TrailOpen","TrailCollapsed"} do
            local item=row:FindFirstChild(name)
            if item and item:IsA("GuiObject") and item.Size.X.Offset~=reserve then item.Size=UDim2.new(0,reserve,1,0) end
        end
    end
end
-- PF018 right column. The attack list sits in the bottom-right corner; its
-- top is authored per board state (split under an open board, tall under the
-- toggle) and the top row reserves the board's column or only its toggle.
-- Its corner mode is read from the laid-out dock and board column (like the
-- board's own capacity), every size it picks is authored:
--   Corner: the column clears the dock (tablets, desktop): the whole column.
--   Beside: the column would cross the dock but the space beside it still
--           holds a row (≥ PF018RowMin; Ashton's iPhone): exactly that space.
--   Above:  otherwise (A06): the column, its rows kept above the dock by
--           PF018DockClear, higher still while the placement tray shows.
-- PFBoardExpanded is Builder C's state; unset means open.
function Methods:followBoard()
    if self.destroyed then return end
    Interface.layoutColumn(self.game)
    Interface.layoutNotices(self.game)
end
-- PF019 W7 S9: an authored attribute's variant for the active UI size (Game.PF019UiSizeKey,
-- set by PF019UiSize), else the Normal value.
local function sized(item: Instance,name: string,key: string?): any
    local value=if key and key~="Normal" then item:GetAttribute(name.."_"..key) else nil
    if value==nil then value=item:GetAttribute(name) end
    return value
end
-- The column layout (exported so Edit checks run the real thing); reads laid-out geometry,
-- writes only authored sizes. (The Premium rail's spot under the open board is authored: tools/atlas/author-pf3-rail-anchor.)
function Interface.layoutColumn(ui: Frame)
    local key=ui:GetAttribute("PF019UiSizeKey")
    local board=ui:FindFirstChild("PFLeaderboardRegion")
    local expanded=not board or board:GetAttribute("PFBoardExpanded")~=false
    local attacks=ui.Attacks;local controls=ui.Controls
    local gap=8
    local dockRight=controls.AbsolutePosition.X+controls.AbsoluteSize.X
    -- PIVOT (PF - 1 2026-10-25; MM: the Premium grid's header is never covered): the wing sits right of the dock, so
    -- the dock's edge is the wing's; the grid flies out above the wing (both under Controls)
    local wing,grid=controls:FindFirstChild("PFArsenalWing"),controls:FindFirstChild("PFArsenalGrid")
    if wing and wing:IsA("GuiObject") and wing.Visible then dockRight=math.max(dockRight,wing.AbsolutePosition.X+wing.AbsoluteSize.X) end
    local right=ui.AbsolutePosition.X+ui.AbsoluteSize.X-12
    local columnLeft=if board then board.AbsolutePosition.X else right-200
    local mode=if columnLeft>=dockRight+gap then "Corner"
        elseif right-(dockRight+gap)>=(sized(attacks,"PF018RowMin",key) or math.huge) then "Beside" else "Above"
    local width=sized(attacks,if mode=="Beside" then "PF018BesideWidth" else "PF018ColumnWidth",key)
    local height=sized(attacks,if expanded then "PF018SplitHeight" else "PF018TallHeight",key)
    if typeof(width)=="UDim" and typeof(height)=="UDim" then
        -- Beside: the authored width assumes the bare dock; never wider than the space right of the wing
        if mode=="Beside" then
            local span=ui.AbsoluteSize.X;local authored=width.Scale*span+width.Offset
            local ratio=if attacks.Size.X.Scale*span+attacks.Size.X.Offset>0 then attacks.AbsoluteSize.X/(attacks.Size.X.Scale*span+attacks.Size.X.Offset) else 1
            local room=(right-(dockRight+gap))/math.max(ratio,1e-3)
            if authored>room then width=UDim.new(0,math.floor(room)) end
        end
        -- PF - 3 variant C: the attack rows hug the dock line and grow up; under a visible Premium rail they stop below it
        -- (the column keeps its bottom; only its height shrinks, in authored units like the Beside width above)
        local rail=ui:FindFirstChild("PFPremiumRail")
        if rail and rail:IsA("GuiObject") and rail.Visible and rail.AbsoluteSize.Y>0 then
            local ax,aw=attacks.AbsolutePosition.X,attacks.AbsoluteSize.X
            if ax<rail.AbsolutePosition.X+rail.AbsoluteSize.X and ax+aw>rail.AbsolutePosition.X then
                local span=ui.AbsoluteSize.Y;local authored=height.Scale*span+height.Offset
                local current=attacks.Size.Y.Scale*span+attacks.Size.Y.Offset
                local ratio=if current>0 then attacks.AbsoluteSize.Y/current else 1
                local bottom=attacks.AbsolutePosition.Y+attacks.AbsoluteSize.Y
                local room=(bottom-(rail.AbsolutePosition.Y+rail.AbsoluteSize.Y+gap))/math.max(ratio,1e-3)
                if authored>room then height=UDim.new(0,math.max(0,math.floor(room))) end
            end
        end
        local size=UDim2.new(width,height)
        if attacks.Size~=size then attacks.Size=size end
        local floor=attacks:FindFirstChild("ReferenceWidth");local min=attacks:GetAttribute(if mode=="Beside" then "PF018BesideMin" else "PF018ColumnMin")
        if floor and floor:IsA("UISizeConstraint") and typeof(min)=="number" and floor.MinSize.X~=min then floor.MinSize=Vector2.new(min,floor.MinSize.Y) end
    end
    local clear=attacks:FindFirstChild("PF018DockClear")
    if clear and clear:IsA("GuiObject") then
        clear.Visible=mode=="Above"
        local lift=clear:GetAttribute(if controls.Placement.Visible then "PF018PlacingHeight" else "PF018AboveHeight")
        -- Above: an open Premium grid under the column lifts its rows over the grid's top (its header stays readable)
        if typeof(lift)=="number" and mode=="Above" and grid and grid:IsA("GuiObject") and grid.Visible
            and grid.AbsolutePosition.X+grid.AbsoluteSize.X>attacks.AbsolutePosition.X then
            local span=ui.AbsoluteSize.Y
            local ratio=if attacks.Size.Y.Scale*span+attacks.Size.Y.Offset>0 then attacks.AbsoluteSize.Y/(attacks.Size.Y.Scale*span+attacks.Size.Y.Offset) else 1
            local need=(attacks.AbsolutePosition.Y+attacks.AbsoluteSize.Y)-(grid.AbsolutePosition.Y-gap)
            lift=math.max(lift,math.ceil(need/math.max(ratio,1e-3)))
        end
        if typeof(lift)=="number" and clear.Size.Y.Offset~=lift then clear.Size=UDim2.new(1,0,0,lift) end
    end
    if attacks:GetAttribute("PF018Mode")~=mode then attacks:SetAttribute("PF018Mode",mode) end
    local row=ui:FindFirstChild("PFTopRow")
    local open,collapsed=row and row:FindFirstChild("TrailOpen"),row and row:FindFirstChild("TrailCollapsed")
    if open and open:IsA("GuiObject") then open.Visible=expanded end
    if collapsed and collapsed:IsA("GuiObject") then collapsed.Visible=not expanded end
end
-- The notice column (author-notice-rows): a notice IS a row, and the left column mirrors the right one (Ashton:
-- "these should match", identical sizes). Its width is the attack column's own width UDim (the one layoutColumn just
-- picked: same parent, same UI-size scale, so literally the same width); its height is the column's authored tall height
-- (under the topbar row), cut so it never rises into the visible tutorial tracker card (+2: MM, so a request and an info row both fit under the A06's strip); its bottom spacer copies the
-- column's dock clearance, so both bottom lines match; the lane caps at 3 rows on desktop and 2 on phones.
Interface.NOTICE_MIN_WIDTH=160 -- a notice row narrower than this moves above the dock (layoutNotices)
function Interface.layoutNotices(ui: Frame)
    local region=ui:FindFirstChild("PFNoticeRegion");local lane=region and region:FindFirstChild("PFNotifications")
    local spacer=region and region:FindFirstChild("PFNoticeDockClear");local cap=lane and lane:FindFirstChild("PFLaneCap")
    local attacks=ui.Attacks;local clear=attacks:FindFirstChild("PF018DockClear")
    if not (region and lane and spacer and cap and clear and region:IsA("GuiObject") and spacer:IsA("GuiObject") and clear:IsA("GuiObject") and cap:IsA("UISizeConstraint"))
        or region:GetAttribute("PFNoticeRowVersion")==nil then return end
    -- notices v2 (author-pf4-notices-v2): a fixed column in its desk corner, purely scaled; nothing here moves it
    if region:GetAttribute("PFNoticeV2")~=nil then return end
    local tall=sized(attacks,"PF018TallHeight",ui:GetAttribute("PF019UiSizeKey"))
    if typeof(tall)~="UDim" then return end
    local scaler=region:FindFirstChild("PFUiSize");local scale=if scaler and scaler:IsA("UIScale") and scaler.Scale>0 then scaler.Scale else 1
    -- the tracker card on screen (Desk or Phone), if any: the column starts 2 below it
    local bottom=ui.AbsolutePosition.Y+ui.AbsoluteSize.Y-12*scale
    local top=bottom-(tall.Scale*ui.AbsoluteSize.Y+tall.Offset)*scale
    local tracker=ui:FindFirstChild("PFTracker")
    if tracker and tracker:IsA("GuiObject") and tracker.Visible then
        for _,card in tracker:GetChildren() do
            if card:IsA("GuiObject") and card.Visible and card.AbsoluteSize.Y>0 then top=math.max(top,card.AbsolutePosition.Y+card.AbsoluteSize.Y+2*scale) end
        end
    end
    -- MM 2026-10-08: a notice column under ~160 px can't show a name (the A06 with the board collapsed: the attack column's
    -- Beside width, 117). Then the notices take the attack column's ABOVE geometry instead: its authored column width with
    -- its 200 floor, sitting above the dock (the Above / placing clearance). Never an "A…".
    local key=ui:GetAttribute("PF019UiSizeKey")
    local narrow=attacks.AbsoluteSize.X>0 and attacks.AbsoluteSize.X<Interface.NOTICE_MIN_WIDTH*scale
    local columnWidth=sized(attacks,"PF018ColumnWidth",key)
    local width=if narrow and typeof(columnWidth)=="UDim" then columnWidth else attacks.Size.X
    local size=UDim2.new(width,UDim.new(0,math.max(0,(bottom-top)/scale)))
    if region.Size~=size then region.Size=size end
    -- and the column's width floor / cap (ReferenceWidth: 200-400, the floor layoutColumn picked for the mode; Above's
    -- floor when narrow)
    local floor,bounds=attacks:FindFirstChild("ReferenceWidth"),region:FindFirstChild("PF013Size")
    if floor and bounds and floor:IsA("UISizeConstraint") and bounds:IsA("UISizeConstraint") then
        local columnMin=attacks:GetAttribute("PF018ColumnMin")
        local min,max=Vector2.new(if narrow and typeof(columnMin)=="number" then columnMin else floor.MinSize.X,0),Vector2.new(floor.MaxSize.X,100000)
        if bounds.MinSize~=min then bounds.MinSize=min end
        if bounds.MaxSize~=max then bounds.MaxSize=max end
    end
    local lift=clear:GetAttribute(if ui.Controls.Placement.Visible then "PF018PlacingHeight" else "PF018AboveHeight")
    local spacerSize=if narrow and typeof(lift)=="number" then UDim2.new(1,0,0,lift) else clear.Size
    local spacerShown=narrow or clear.Visible
    if spacer.Visible~=spacerShown then spacer.Visible=spacerShown end
    if spacer.Size~=spacerSize then spacer.Size=spacerSize end
    if region:GetAttribute("PFNoticeAbove")~=narrow then region:SetAttribute("PFNoticeAbove",narrow) end
    local rows=region:GetAttribute(if attacks:GetAttribute("PF018Mode")=="Corner" then "PFNoticeRowsDesk" else "PFNoticeRowsPhone")
    if typeof(rows)=="number" and cap.MaxSize.Y~=rows then cap.MaxSize=Vector2.new(math.huge,rows) end
end
function Methods:iconBarFocus(): GuiObject?
    local bar=self.game:FindFirstChild("PFIconBar");local locate=bar and bar:FindFirstChild("Locate")
    return if locate and locate:IsA("GuiObject") and HudControls.available(locate) then locate else nil
end
-- Meter fills are live values (content), not panel geometry.
function Methods:setMeter(reserveFill: Frame,attackFill: Frame,reserve: number,attacking: number)
    self.presentation:tween(reserveFill,{Size=UDim2.fromScale(reserve,1)},.2)
    self.presentation:tween(attackFill,{Position=UDim2.fromScale(reserve,0),Size=UDim2.fromScale(attacking,1)},.2)
end
function Methods:tweenHud(item: Instance,props: any,duration: number) self.presentation:tween(item,props,duration) end

function Methods:setGamepad(value: boolean)
    if self.gamepad~=value then self.inputRevision+=1 end
    self.gamepad=value;self.game.GamepadReticle.Visible=false -- PF020: no console crosshair
    self:updateGamepadHelp()
    if value then
        local settings=self.root.UserSettings
        for _,entry in {{settings,(settings:GetAttribute("PF019SettingsRevision") and settings.Body.Header.Tabs.Gameplay) or settings.Body.Tabs.Gameplay},
            {self.root.Lobby,self.root.Lobby.Body.Footer.Start},{self.root.Home,self.root.Home.Body.Solo},
            {self.root.PublicWaiting,self.root.PublicWaiting.Body.Return}} do
            if entry[1].Visible then GuiService.SelectedObject=entry[2];break end
        end
    elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.gui) then GuiService.SelectedObject=nil end
    self:refreshOverlays()
end

-- Shorter wording when the authored help strip is at its phone floor.
function Methods:updateGamepadHelp()
    local help=self.game.GamepadHelp
    local a=InputPrompts.buttonName(Enum.KeyCode.ButtonA);local b=InputPrompts.buttonName(Enum.KeyCode.ButtonB)
    local x=InputPrompts.buttonName(Enum.KeyCode.ButtonX);local y=InputPrompts.buttonName(Enum.KeyCode.ButtonY)
    help.Text=if help.AbsoluteSize.X>0 and help.AbsoluteSize.X<520 then a.." Place · "..x.." Menu · "..b.." Back · Triggers Zoom"
        else a.." Select / attack     "..x.." Menu     "..y.." Center     "..b.." Back     Triggers Zoom"
end

-- Retired surfaces stay authored but inert (no clicks, no controller focus).
function Methods:retireLegacy()
    if self.destroyed then return end
    local ui=self.game
    local function retire(item: Instance?)
        if item and item:IsA("GuiButton") then
            if GuiService.SelectedObject==item then GuiService.SelectedObject=nil end
            HudControls.retire(item)
        end
    end
    local navigation=ui:FindFirstChild("Navigation")
    if navigation then navigation.Visible=false;for _,name in {"Focus","ZoomIn","ZoomOut"} do retire(navigation:FindFirstChild(name)) end end
    retire(ui.GameRightSidebar:FindFirstChild("Exit"))
    retire(ui:FindFirstChild("PFCompactQueueToggle"))
    local row=ui.NuclearActions;row.Visible=false;row.Active=false;row.Selectable=false
    for _,button in row.Buttons:GetChildren() do if button:IsA("GuiButton") then button.Active=false;button.Selectable=false end end
    local menu=ui:FindFirstChild("BuildMenu")
    if menu and menu:IsA("GuiObject") then
        menu.Visible=false;menu.Active=false;menu.Selectable=false
        for _,item in menu:GetDescendants() do
            if item:IsA("GuiButton") then item.Active=false;item.Selectable=false;HudControls.clearLinks(item) end
        end
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(menu) then GuiService.SelectedObject=nil end
    end
    ui.Copyright.Visible=false
    if ui:GetAttribute("CompactQueueActive")~="Attacks" then ui:SetAttribute("CompactQueueActive","Attacks") end
end

-- Kept for callers; there is no runtime geometry left to lay out.
function Methods:layout() self:refreshOverlays() end
function Methods:layoutHover() self:refreshOverlays() end

-- Visibility only: the tutorial guide yields to attack rows and to a live
-- notice stack it would cover; controller help hides behind attack rows.
function Methods:refreshOverlays()
    if self.destroyed or self.overlayBusy then return end;self.overlayBusy=true
    local ui=self.game;local guide=ui.TutorialGuide;local attacks=ui.Attacks
    local covered=attacks.Visible and overlaps(guide,attacks)
    local region=ui:FindFirstChild("PFNoticeRegion")
    -- the region is a full-width band; the stack lives in its lane (author-notices-large)
    local notices=region and (region:FindFirstChild("PFNotifications") or region)
    if not covered and notices and notices:IsA("GuiObject") and (ui:GetAttribute("PFNoticeStackHeight") or 0)>0 then
        local stack=ui:GetAttribute("PFNoticeStackHeight") :: number
        local np,ns,gp,gs=notices.AbsolutePosition,notices.AbsoluteSize,guide.AbsolutePosition,guide.AbsoluteSize
        local top=np.Y+ns.Y-stack
        covered=gp.X<np.X+ns.X and np.X<gp.X+gs.X and gp.Y+gs.Y>top
    end
    if guide:GetAttribute("InspectionSuppressed")~=covered then guide:SetAttribute("InspectionSuppressed",covered) end
    -- PF020 (Ashton): the bottom controller hint strip is retired; S11 keeps the per-button glyphs.
    ui.GamepadHelp.Visible=false
    self.overlayBusy=false
end

function Methods:layoutHUD(cities: any): any
    self.cities=cities
    self:retireLegacy();self:placementAction()
    cities:layout()
    if cities.refreshSlotNavigation then cities:refreshSlotNavigation() end
    self:refreshOverlays()
    return {phone=false}
end
function Methods:placementAction()
    local actions=self.game.Controls.Actions
    actions.Visible=false
    for _,name in {"Build","Primary"} do
        local button=actions[name];button.Visible=false;button.Active=false;button.Selectable=false
        if GuiService.SelectedObject==button then GuiService.SelectedObject=nil end
    end
end
-- PF - 4 (Ashton: 19.4M gold yet "+130K/min"; "it better count everything tho, piracy and allat"): the readout is your
-- TOTAL income, the leaderboard's Income/min (StatsGoldRateTracker over goldEarned, which every source adds to: territory,
-- trade ships, trains, piracy, oil, premium buildings, gifts). goldRates is only the territory's per-tick income, so it
-- stands in until the window holds MIN_WINDOW ticks (the match's first seconds, or after a rewind).
local MIN_WINDOW=100
function Methods:update(state: any,format: (number)->string)
    self.phase=state.phase
    local tracker=self.incomeTracker
    if not tracker then tracker=GoldRateTracker.new();self.incomeTracker=tracker end
    local samples=tracker.history[1]
    if samples and #samples>0 and (state.ticks or 0)<samples[#samples].tick then tracker:resetAll();samples=nil end -- a new match
    -- one sample a game second at most (the tracker keeps 240), so the window is the leaderboard's two minutes
    if state.goldEarned and state.goldEarned[1] and state.ticks and (not samples or #samples==0 or state.ticks-samples[#samples].tick>=10) then
        tracker:record(1,{income=state.goldEarned[1]},state.ticks);samples=tracker.history[1]
    end
    local perMin=((state.goldRates and state.goldRates[1]) or 0)*60
    if samples and #samples>=2 and samples[#samples].tick-samples[1].tick>=MIN_WINDOW then perMin=tracker:goldIncomePerMin(1) end
    self.game.Controls.Gold.Income.Text="+"..format(math.max(0,perMin)).."/min"
    self.game.Controls.Gold.Income.TextColor3=HudTheme.Gold
    self:placementAction()
end

function Methods:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.selectionFocus then self.selectionFocus.destroy();self.selectionFocus=nil end
    self.presentation:destroy()
    for _,connection in self.connections do connection:Disconnect() end
end
return Interface
