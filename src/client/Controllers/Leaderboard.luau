--!strict
-- OpenFront 93a136a: PlayerStats.ts, StatsTable.ts, StatsColumns.ts,
-- StatsConstants.ts, GameLeftSidebar.ts. Default numeric columns include gold.
-- PF010: PixelFront presentation (LeaderboardStyle) and the column picker.
-- PF012: top-right card, nation dots, headshots, pinned local card, row slides.
-- PF013: every size and position is AUTHORED in the place (Scale, aspect
-- ratios, list/grid layouts; tools/atlas/author-pf010-leaderboard.luau). This
-- module only fills content: text, colors, visibility, row clones and their
-- order, sort/selection state, and the row-slide tween of each row's PFBody.
-- The card hugs what it shows: a transparent column of painted pieces, top 10
-- rows at most plus your pinned row (MM 2026-10-05).
-- Data, sort, income, preferences, pooling and owner centering are unchanged.
local Input=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local TweenService=game:GetService("TweenService")
local Players=game:GetService("Players")
local HudTheme=require(script.Parent.BattleHudTheme)
local Icons = require(script.Parent.ReferenceIcons)
local StatsGoldRateTracker=require(script.Parent.StatsGoldRateTracker)
local Model=require(script.Parent.PlayerStatsModel)
local Style=require(script.Parent.LeaderboardStyle)
local ClientNames=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local Accent=require(game:GetService("ReplicatedStorage").Shared.PixelFrontAccent)
local Leaderboard = {}
Leaderboard.__index = Leaderboard
local VIP_GOLD=Color3.fromHex("ffd77a") -- PF020 G5b GOLD.hi
local CELL_NAMES={rank="Rank",clan="Clan",player="Player",playerType="PlayerType",tiles="Tiles",gold="Gold",goldIncomePerMin="GoldIncomePerMin",shipTradeGoldPerMin="ShipTradeGoldPerMin",piracyGoldPerMin="PiracyGoldPerMin",trainTradeGoldPerMin="TrainTradeGoldPerMin",troops="Troops",maxtroops="MaxTroops",cities="Cities",ports="Ports",factories="Factories",silos="Silos",sams="SAMs",warships="Warships",allies="Allies",betrayals="Betrayals"}
local ACCENT_ROLES={"accent","muted","strong","focus","text","onAccent","surface"}
local TITLE_ICON="TeamHUDLeaderboardIconSolidWhite"
local function inside(ui: GuiObject?,p: Vector2): boolean
    if not ui then return false end
    local q,s=ui.AbsolutePosition,ui.AbsoluteSize
    return ui.Visible and p.X>=q.X and p.X<=q.X+s.X and p.Y>=q.Y and p.Y<=q.Y+s.Y
end
local function visibleChain(ui: GuiObject?): boolean
    local item: Instance?=ui
    while item and item:IsA("GuiObject") do if not item.Visible then return false end;item=item.Parent end
    return ui~=nil
end

function Leaderboard.territoryPercentage(state: any,tiles: number): number
    local validTiles=state.map.landCount-(state.falloutCount or 0)
    return if validTiles>0 then tiles/validTiles*100 else 0
end
-- The HUD's "Territory 12.3%" line: a share that would round to 0.0% while land is held reads "<0.1%".
function Leaderboard.territoryText(state: any,tiles: number): string
    local share=Leaderboard.territoryPercentage(state,tiles)
    return if share>0 and share<.05 then "Territory  <0.1%" else string.format("Territory  %.1f%%",share)
end

function Leaderboard.rows(state: any, sortKey: string, ascending: boolean,preferences: any?): {any}
    local rows = {}
    for registration,owner in state.playerOrder or {1,2} do
        if (state.counts[owner] or 0) <= 0 then continue end
        local player=state.players and state.players[owner] or {name=state.names[owner]}
        table.insert(rows,{owner=owner,registration=registration,name=ClientNames.resolve(state,owner,preferences),clan=ClientNames.clan(state,owner,preferences),
            tiles=state.counts[owner],gold=state.gold and state.gold[owner] or 0,maxTroops=state.caps[owner],troops=state.troops[owner]})
    end
    table.sort(rows,function(a,b)
        local left,right=a[sortKey] or 0,b[sortKey] or 0
        if left==right then return a.registration<b.registration end -- JS stable Array.sort.
        return if ascending then left<right else left>right
    end)
    for rank,row in rows do row.rank=rank end
    return rows
end
function Leaderboard:setPreferences(preferences: any)
    if self.unsubscribe then self.unsubscribe() end
    self.preferences=preferences
    self.unsubscribe=preferences:subscribe(function(key)
        if key=="settings.leaderboardColumns" then self:update(self.state,true) end
    end)
    if not self.accentInjected then self:useOwnAccent() end
    if self.state then self:update(self.state,true) end
end
-- PF019 W7 S8 Leaderboard at match start: "collapsed" never auto-opens it at spawn (the
-- player can still open it); "open" (default) keeps the wide-screen auto-open.
function Leaderboard.opensAtStart(preferences: any?): boolean
    return not (preferences and type(preferences.get)=="function" and preferences:get("leaderboardStart")=="collapsed")
end
-- Interface accent follows the PF011B registry API: an injected shared registry
-- when the HUD provides one, otherwise this table's own registry over the same
-- validated preference. No accent storage here; static cobalt without either.
function Leaderboard:attachAccent(registry: any?)
    if self.accentUnsubscribe then self.accentUnsubscribe();self.accentUnsubscribe=nil end
    self.accent=registry
    if registry then self.accentUnsubscribe=registry:subscribe(function() self:refreshPalette() end) end
    self:refreshPalette()
end
function Leaderboard:useOwnAccent()
    if self.ownAccent then self.ownAccent:destroy();self.ownAccent=nil end
    local preferences=self.preferences
    if preferences and type(preferences.interfaceAccent)=="function" then self.ownAccent=Accent.new(preferences) end
    self:attachAccent(self.ownAccent)
end
function Leaderboard:setAccent(registry: any?)
    self.accentInjected=registry~=nil
    if not registry then self:useOwnAccent();return end
    if self.ownAccent then self.ownAccent:destroy();self.ownAccent=nil end
    self:attachAccent(registry)
end
function Leaderboard:refreshPalette()
    local roles=nil
    if self.accent then roles={};for _,role in ACCENT_ROLES do roles[role]=self.accent:color(role) end end
    self.palette=Style.palette(roles)
    if self.destroyed then return end
    self:render()
end
-- Nation colors come from the map renderer (MatchController hook); without
-- one the dot falls back to the muted text color rather than inventing hues.
function Leaderboard:setOwnerColor(source: ((number)->Color3?)?)
    self.ownerColorSource=source
    if self.state and not self.destroyed then self:render() end
end
-- PF020 V3 (PF - 2): MatchController supplies the VIP lookup (userId -> boolean, NameplateStyle.vipUser).
-- A VIP row gets a gold name and the authored PFVip pill after it (G5b). Both follow the headshot,
-- so anonymous names hide them too.
function Leaderboard:setVip(source: ((number)->boolean)?)
    self.vipSource=source
    if self.state and not self.destroyed then self:render() end
end
function Leaderboard:ownerColor(owner: number): Color3
    local source=self.ownerColorSource
    local color=if source then source(owner) else nil
    return if typeof(color)=="Color3" then color else self.palette.muted
end
-- Roblox headshots for humans only; anonymous names hide other players' faces.
function Leaderboard:avatarId(owner: number): number?
    local state=self.state;local player=state and state.players and state.players[owner]
    if not player or player.playerType~="Human" then return nil end
    local own=owner==(state.localOwner or 1)
    if not own and self.preferences and self.preferences:get("anonymousNames") then return nil end
    local id=tonumber(player.clientID)
    if id==nil and own then local localPlayer=Players.LocalPlayer;id=if localPlayer then localPlayer.UserId else nil end
    return if id and id>0 then id else nil
end
function Leaderboard:selectedColumns(): {string}
    return if self.preferences then self.preferences:statsColumns("player") else {"clan","tiles","troops"}
end
function Leaderboard:toggleColumn(id: string)
    local selected=Model.toggleColumn(self:selectedColumns(),id)
    if selected and self.preferences then self.preferences:setStatsColumns("player",selected) end
end
-- TeamHUD refreshes its own content after each leaderboard render.
function Leaderboard:setStackLayout(callback: ((any)->())?) self.stackLayout=callback end
-- PIVOT D16 (Ashton 2026-10-23: "collapsed by default on phones; tap to open; it closes itself after a few seconds"):
-- phones (a game UI under PHONE_WIDTH) start collapsed (showAfterSpawn) and, once opened, fold back AUTO_CLOSE seconds after
-- the last touch on the board; never while the column picker is open. Desktop is unchanged.
Leaderboard.PHONE_WIDTH=960
Leaderboard.AUTO_CLOSE=6
function Leaderboard:phone(): boolean
    local x=self.gameUI and self.gameUI.AbsoluteSize.X or 0
    return x>0 and x<Leaderboard.PHONE_WIDTH
end
function Leaderboard:collapse()
    self.shown=false;self:closePicker(false)
    self:update(self.state,true)
    if self:focusInside(self.ui) and not self:focusInside(self.toggle) then GuiService.SelectedObject=self.toggle end
end
function Leaderboard:armAutoClose()
    self.closeToken=(self.closeToken or 0)+1
    if not (self.shown and self:phone()) then return end
    local token=self.closeToken
    task.delay(Leaderboard.AUTO_CLOSE,function()
        if self.destroyed or token~=self.closeToken or not self.shown then return end
        if self.pickerOpen then self:armAutoClose();return end
        self:collapse()
    end)
end
function Leaderboard:togglePlayerStats()
    self.userToggled=true
    self.shown=not self.shown
    if not self.shown then self:closePicker(false) end
    self:update(self.state,true)
    if not self.shown and self:focusInside(self.ui) and not self:focusInside(self.toggle) then GuiService.SelectedObject=self.toggle end
    self:armAutoClose()
end
function Leaderboard:trigger(): GuiObject
    return if self.columnsButton then self.columnsButton else self.header:FindFirstChild("Picker")
end
function Leaderboard:focusInside(root: Instance?): boolean
    local selected=GuiService.SelectedObject
    return root~=nil and selected~=nil and (selected==root or selected:IsDescendantOf(root))
end
function Leaderboard:openPicker()
    local gamepad=self:focusInside(self.ui)
    self.pickerOpen=true;self.portal.CanvasPosition=Vector2.zero
    self:renderPicker()
    if gamepad and self.overlay.Visible then
        for _,id in self.chipOrder do
            local item=self.portal:FindFirstChild(id)
            if item and item.Active then GuiService.SelectedObject=item;break end
        end
    end
end
function Leaderboard:closePicker(restoreFocus: boolean)
    local focused=self:focusInside(self.overlay)
    self.pickerOpen=false;self:renderPicker()
    if focused or restoreFocus and GuiService.SelectedObject~=nil then
        local trigger=self:trigger()
        GuiService.SelectedObject=if trigger and visibleChain(trigger) then trigger else self.toggle
    end
end
function Leaderboard:togglePicker()
    if self.pickerOpen then self:closePicker(false) else self:openPicker() end
    self:armAutoClose() -- D16: a touch on the board restarts the phone timer
end
-- Input owners route their back action here first; true means it was consumed.
function Leaderboard:back(): boolean
    if not self.pickerOpen then return false end
    self:closePicker(true);return true
end
Leaderboard.handleEscape=Leaderboard.back

-- Pointer/focus/press feedback eases; data refreshes and pooled-row recycling
-- paint instantly so a reused row never fades from another player's state.
-- Rows paint their PFBody (fill + outline), which also carries the slide.
function Leaderboard:rowSurface(color: Color3,_state: any?): Color3
    return Style.surface(self.palette,color,"row")
end
local function bodyOf(ui: Instance): any return ui:FindFirstChild("PFBody") or ui end
function Leaderboard:paintRow(ui: GuiObject,animate: boolean?)
    local state=self.rowState[ui];if not state then return end
    local palette=self.palette;local body=bodyOf(ui)
    local rest=if state.emphasized then palette.accentMuted else palette.panel
    local color=rest
    if state.pressed then color=rest:Lerp(palette.accent,.35)
    elseif self.hovered[ui] or self.focused[ui] then color=rest:Lerp(if state.emphasized then palette.accent else palette.raised,if state.emphasized then .22 else .8) end
    color=self:rowSurface(color,state)
    -- One feedback tween per row: an interrupted or recycled row never lands
    -- an older target over its current owner.
    if state.tween then state.tween:Cancel();state.tween=nil end
    if animate then
        state.tween=TweenService:Create(body,TweenInfo.new(if state.pressed then Style.Motion.press else Style.Motion.hover,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundColor3=color})
        state.tween:Play()
    else body.BackgroundColor3=color end
    -- The local card is outlined in the accent; gamepad focus is a thicker
    -- focus-color ring (on PFBody, never the shell's per-button FocusBorder).
    local stroke=body:FindFirstChild("PFOutline")
    if stroke and stroke:IsA("UIStroke") then
        local focused=self.focused[ui]==true
        stroke.Enabled=state.emphasized==true or focused
        stroke.Color=if focused then palette.focus else palette.accent
        stroke.Thickness=if focused then 2 else 1
        stroke.Transparency=if focused then 0 else .35
    end
end
function Leaderboard:watchRow(ui: GuiButton)
    local function set(map: any,value: boolean) map[ui]=value or nil;self:paintRow(ui,true) end
    table.insert(self.connections,ui.MouseEnter:Connect(function() set(self.hovered,true) end))
    table.insert(self.connections,ui.MouseLeave:Connect(function() set(self.hovered,false) end))
    table.insert(self.connections,ui.SelectionGained:Connect(function() set(self.focused,true) end))
    table.insert(self.connections,ui.SelectionLost:Connect(function() set(self.focused,false) end))
end
function Leaderboard:press(ui: GuiObject)
    local state=self.rowState[ui];if not state then return end
    self:armAutoClose() -- D16: a touch on the board restarts the phone timer
    state.pressToken=(state.pressToken or 0)+1;local token,owner=state.pressToken,state.owner
    state.pressed=true;self:paintRow(ui,true)
    task.delay(Style.Motion.press,function()
        if self.rowState[ui]==state and state.pressToken==token and state.owner==owner then state.pressed=false;self:paintRow(ui,true) end
    end)
end

function Leaderboard.new(sidebar: Frame, template: TextButton, formatTroops: (number) -> string, center: (number) -> (), formatNumber: ((number) -> string)?)
    local function deep(name: string): any return sidebar:FindFirstChild(name,true) end
    local region=sidebar.Parent
    local gameUI=(if region and region.Name=="PFLeaderboardRegion" then region.Parent else region) :: any
    local self=setmetatable({ui=sidebar,tableUI=deep("Table"),template=template,formatTroops=formatTroops,gameUI=gameUI,
        center=center,formatNumber=formatNumber or tostring,sortKey=nil,ascending=false,shown=false,spawnOpened=false,
        showAfterSpawn=gameUI.AbsoluteSize.X>=960,userToggled=false,state=nil,rows={},list={},pool={},rowFor={},
        lastUpdate=-math.huge,goldRateTracker=StatsGoldRateTracker.new(),connections={},pickerOpen=false,
        palette=Style.palette(nil),rowState=setmetatable({},{__mode="k"}),hovered=setmetatable({},{__mode="k"}),focused=setmetatable({},{__mode="k"}),
        chipHover={},chipTweens={}},Leaderboard)
    -- PF013 authored structure (Builder A's region > Leaderboard card).
    assert(self.tableUI and deep("PFStack") and deep("PFStrip") and deep("PFPicker"),"PF013 leaderboard not authored: run tools/atlas/author-pf010-leaderboard.luau")
    self.model=Model.new(self.goldRateTracker)
    self.horizontal=self.tableUI:WaitForChild("Horizontal")
    self.content=self.horizontal:WaitForChild("Content")
    self.header=self.content:WaitForChild("Header")
    self.pinned=self.content:WaitForChild("Pinned")
    self.toggle=deep("Toggle")
    self.strip=deep("PFStrip");self.overlay=deep("PFPicker");self.portal=self.overlay:FindFirstChild("PlayerColumnPicker",true)
    self.skirt=self.strip:FindFirstChild("PFSkirt");self.stats=deep("StatsStack");self.teamOverlay=deep("PFTeamPicker")
    -- Strip pieces searched inside the strip only: the picker bar has its own PFTitle/PFCount.
    self.columnsButton=self.strip:FindFirstChild("PFColumns",true);self.titleUI=self.strip:FindFirstChild("PFTitle",true)
    self.countUI=self.strip:FindFirstChild("PFCount",true);self.iconUI=self.strip:FindFirstChild("PFIcon",true)
    self.moreUI=self.content:FindFirstChild("PFMore");self.closeGlyph=self.toggle:FindFirstChild("PFClose")
    self.bar=self.overlay:FindFirstChild("PFBar")
    self.chipOrder={};do local order=Style.chipOrder(Model.Data.playerColumns)
        for id in order do table.insert(self.chipOrder,id) end;table.sort(self.chipOrder,function(a,b) return order[a]<order[b] end) end
    local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
    connect(self.toggle.Activated,function() self:togglePlayerStats() end)
    connect(self.header:WaitForChild("Picker").Activated,function() self:togglePicker() end)
    if self.columnsButton then connect(self.columnsButton.Activated,function() self:togglePicker() end) end
    local back=self.bar and self.bar:FindFirstChild("PFBack")
    if back then connect(back.Activated,function() self:closePicker(true) end) end
    for _,column in Model.Data.playerColumns do
        local head=self.header:WaitForChild(CELL_NAMES[column.id]);head:SetAttribute("SourceTooltip",column.label)
        head.Active=column.orderable
        if column.orderable then connect(head.Activated,function() self.model:setSort(column.id);self:update(self.state,true) end) end
        if column.hideable then
            local item=self.portal:WaitForChild(column.id)
            connect(item.Activated,function() self:toggleColumn(column.id) end)
            local caption=item:FindFirstChild("PFLabel");if caption then caption.Text=Style.label(column) else item.Text=Style.label(column) end
            local icon=item:FindFirstChild("PFIcon")
            if icon and column.icon then if column.white then Icons.bindWhite(icon,column.icon) else Icons.bind(icon,column.icon) end end
            if icon then icon.Visible=column.icon~=nil end
            local function hover(on: boolean) self.chipHover[column.id]=on or nil;self:paintChip(column,true) end
            connect(item.MouseEnter,function() hover(true) end);connect(item.MouseLeave,function() hover(false) end)
            connect(item.SelectionGained,function() hover(true) end);connect(item.SelectionLost,function() hover(false) end)
        end
    end
    connect(self.pinned.Activated,function()
        local owner=self.pinned:GetAttribute("Owner")
        if typeof(owner)=="number" then self:press(self.pinned);self.center(owner) end
    end)
    self:watchRow(self.pinned)
    connect(Input.InputBegan,function(event)
        if not self.pickerOpen or (event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch) then return end
        local p=Vector2.new(event.Position.X,event.Position.Y)
        if not inside(self.overlay,p) and not inside(self.header:FindFirstChild("Picker"),p) and not inside(self.columnsButton,p) then self:closePicker(false) end
    end)
    -- How many rows fit is read from the laid-out table; re-decide the pin
    -- whenever the authored layout resizes it (device, team table, resize).
    connect(self.content:GetPropertyChangedSignal("AbsoluteSize"),function() if self.state then self:render() end end)
    -- The team table shares the column: its rows leave room for it.
    if self.stats then connect(self.stats:GetPropertyChangedSignal("Visible"),function() if self.state then self:render() end end) end
    -- Either open picker card replaces the table under it.
    if self.teamOverlay then connect(self.teamOverlay:GetPropertyChangedSignal("Visible"),function() self:renderChrome() end) end
    return self
end

-- Match end/teardown hides the table and picker; never leave gamepad focus
-- parked inside them (unrelated focus elsewhere is left alone).
function Leaderboard:releaseFocus()
    if self:focusInside(self.overlay) or self:focusInside(self.tableUI) or self:focusInside(self.columnsButton) then GuiService.SelectedObject=nil end
end
function Leaderboard:reset()
    self:releaseFocus()
    self.model:reset();self.rows={};self.list={};self.state=nil;self.sortKey=nil;self.ascending=false;self.pickerOpen=false
    self.shown,self.spawnOpened=false,false
    self.closeToken=(self.closeToken or 0)+1 -- D16: a pending phone auto-close never reaches the next match
    self.showAfterSpawn=self.gameUI.AbsoluteSize.X>=960;self.userToggled=false
    self.lastUpdate=-math.huge
    -- A new match reuses owner numbers: no row may slide from the last match.
    for owner,ui in self.rowFor do
        self:slide(ui,nil);ui.Visible=false;ui:SetAttribute("PFFree",true);self.rowFor[owner]=nil
        local state=self.rowState[ui];if state then state.slot=nil end
    end
    self.pinned.Visible=false
    self:renderChrome();self:renderPicker()
end

function Leaderboard:cellText(row: any,id: string): string
    return Model.cellText(self.state,row,id,self.formatNumber,self.formatTroops)
end
-- Rank-change slide: the row is already in its new list slot (LayoutOrder);
-- its PFBody starts one slot-height per rank away (Scale of the row) and
-- eases home. Purely content motion; works at any authored size.
function Leaderboard:slide(ui: GuiObject,from: number?)
    local state=self.rowState[ui] or {};self.rowState[ui]=state
    if state.slide then state.slide:Cancel();state.slide=nil end
    local body=bodyOf(ui);if body==ui then return end
    if from==nil or from==0 then body.Position=UDim2.new();return end
    body.Position=UDim2.fromScale(0,from)
    state.slide=TweenService:Create(body,TweenInfo.new(Style.Motion.slide,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.new()})
    state.slide:Play()
end
function Leaderboard:fill(rowUI: TextButton,row: any)
    local palette=self.palette
    local state=self.rowState[rowUI] or {};self.rowState[rowUI]=state
    -- A pooled widget recycled to another owner drops that owner's press and
    -- invalidates its pending release; pointer/focus stay with the widget.
    if state.owner~=row.owner then state.owner=row.owner;state.pressed=false;state.pressToken=(state.pressToken or 0)+1 end
    state.emphasized=row.emphasized==true
    self:paintRow(rowUI)
    rowUI:SetAttribute("Owner",row.owner);rowUI:SetAttribute("Rank",row.rank);rowUI:SetAttribute("Emphasized",row.emphasized)
    local body=bodyOf(rowUI)
    local shown={};for _,column in self.columns do shown[column.id]=true end
    local sortKey=self.model.sortKey
    for _,column in Model.Data.playerColumns do
        local id=column.id;local cell=body:FindFirstChild(CELL_NAMES[id]);if not cell then continue end
        cell.Visible=shown[id]==true
        if not shown[id] then continue end
        local value=self:cellText(row,id);if cell.Text~=value then cell.Text=value end
        if id=="player" then HudTheme.Typography.apply(cell,if row.emphasized then "Label" else "Body") end
        cell.TextColor3=if id=="gold" then palette.gold
            elseif id=="rank" then (if row.rank==1 then palette.gold elseif row.emphasized then palette.text else palette.muted)
            elseif id=="clan" or id=="playerType" then palette.muted
            elseif id=="player" or id==sortKey then palette.text else palette.muted
    end
    local ident=body:FindFirstChild("PFIdent")
    local dot=ident and ident:FindFirstChild("PFDot")
    if dot then dot.Visible=true;dot.BackgroundColor3=self:ownerColor(row.owner) end
    local face=ident and ident:FindFirstChild("PFAvatar")
    local avatar=self:avatarId(row.owner)
    if face then
        face.Visible=avatar~=nil
        if avatar then local image="rbxthumb://type=AvatarHeadShot&id="..avatar.."&w=48&h=48";if face.Image~=image then face.Image=image end end
    end
    local vip=avatar~=nil and self.vipSource~=nil and self.vipSource(avatar)==true
    local pill=body:FindFirstChild("PFVip");if pill and pill.Visible~=vip then pill.Visible=vip end
    local nameCell=if vip then body:FindFirstChild(CELL_NAMES.player) else nil
    if nameCell then nameCell.TextColor3=VIP_GOLD end
    -- PIVOT (Ashton 2026-10-26: Levels "Remove it"): the PF023 level badge and its fixed slot are hidden, so the name
    -- starts right after the avatar (the slot is a list item: hidden, it takes no room)
    for _,name in {"PFLevelSlot","PFLevel"} do local node=body:FindFirstChild(name,true);if node and node:IsA("GuiObject") and node.Visible then node.Visible=false end end
    rowUI:SetAttribute("Avatar",avatar)
end

-- Owner-keyed pool: each living owner keeps one cloned row; dead owners'
-- rows are recycled. Rows are Content items; the authored UIListLayout places
-- them by LayoutOrder (Style.Order.rows+slot, between the labels and "•••").
function Leaderboard:rowWidget(owner: number): TextButton
    local ui=self.rowFor[owner]
    if ui then return ui end
    for _,free in self.pool do if free:GetAttribute("PFFree")==true then ui=free;break end end
    if not ui then
        local widget=self.template:Clone();widget.Name="Row"..(#self.pool+1);widget.Parent=self.content
        table.insert(self.connections,widget.Activated:Connect(function()
            local who=widget:GetAttribute("Owner")
            if typeof(who)=="number" then self:press(widget);self.center(who) end
        end))
        self:watchRow(widget);table.insert(self.pool,widget);ui=widget
    end
    local state=self.rowState[ui] or {};self.rowState[ui]=state;state.slot=nil
    ui:SetAttribute("PFFree",false);self.rowFor[owner]=ui
    return ui :: TextButton
end
function Leaderboard:renderRows()
    if not self.state then return end
    -- Only rows that fit are cloned (top 10 at most; the list never scrolls).
    local limit=if self.fit then self.fit.visible else #self.list
    local live={}
    for index,row in self.list do if index>limit then break end;live[row.owner]=true end
    -- Free rows that left first, so newcomers reuse them instead of cloning.
    for owner,ui in self.rowFor do
        if not live[owner] then self.rowFor[owner]=nil;ui.Visible=false;ui:SetAttribute("PFFree",true);self:slide(ui,nil);self.rowState[ui].slot=nil end
    end
    -- PIVOT (smoke pass, 1080: ranks skipped / rows stacked while re-sorting): a slide only for a lone small swap (at most 2 rows
    -- moving, by 1-2 places, none mid-slide); any bigger re-sort SNAPS every row to its slot, so the list never shows a gap
    local moved=0
    for index,row in self.list do
        if index>limit then break end
        local ui=self.rowFor[row.owner];local st=ui and self.rowState[ui]
        if st and st.slot and st.slot~=index then moved+=1 end
    end
    for index,row in self.list do
        if index>limit then break end
        local ui=self:rowWidget(row.owner);local state=self.rowState[ui]
        local previous=state.slot;state.slot=index
        ui.LayoutOrder=Style.Order.rows+index;ui.Visible=true
        self:fill(ui,row)
        local sliding=state.slide~=nil and state.slide.PlaybackState==Enum.PlaybackState.Playing
        if previous and previous~=index and self.shown and moved<=2 and math.abs(previous-index)<=2 and not sliding then self:slide(ui,previous-index)
        elseif previous~=index or moved>2 then self:slide(ui,nil) end
    end
end

function Leaderboard:paintChip(column: any,animate: boolean)
    local item=self.portal:FindFirstChild(column.id);if not item then return end
    local palette=self.palette;local checked=item:GetAttribute("Checked")==true
    local rest=if checked then palette.accentMuted else palette.raised
    local color=if self.chipHover[column.id] and item.Active then rest:Lerp(palette.accent,if checked then .2 else .12) else rest
    color=Style.surface(palette,color,"chip")
    local running=self.chipTweens[column.id];if running then running:Cancel();self.chipTweens[column.id]=nil end
    if animate then
        local tween=TweenService:Create(item,TweenInfo.new(Style.Motion.hover,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundColor3=color})
        self.chipTweens[column.id]=tween;tween:Play()
    else item.BackgroundColor3=color end
    local caption=item:FindFirstChild("PFLabel");(caption or item).TextColor3=palette.text
    local stroke=item:FindFirstChild("Border");if stroke and not stroke:IsA("UIStroke") then stroke=nil end
    if stroke then stroke.Color=if self.chipHover[column.id] and item.Active then palette.focus elseif checked then palette.accent else palette.border;stroke.Transparency=0 end
    item.Check.BackgroundColor3=if checked then palette.accent else palette.panel
    item.Check.Mark.TextColor3=palette.onAccent
end
function Leaderboard:renderPicker()
    self:renderChrome()
    local open=self.pickerOpen and self.shown
    self.overlay.Visible=open
    if not open then return end
    local palette=self.palette;local selected=self:selectedColumns()
    for _,column in Model.Data.playerColumns do if column.hideable then
        local item=self.portal:FindFirstChild(column.id);local checked=table.find(selected,column.id)~=nil
        item.Check.Mark.Visible=checked;item.Active=not(checked and #selected==1);item:SetAttribute("Disabled",not item.Active);item:SetAttribute("Checked",checked)
        local caption=item:FindFirstChild("PFLabel");(caption or item).TextTransparency=if item.Active then 0 else .5
        if caption then HudTheme.Typography.apply(caption,if checked then "Label" else "Body") end
        self:paintChip(column,false)
    end end
    if self.bar then
        local count=self.bar:FindFirstChild("PFCount");if count then count.Text=#selected.." shown" end
        self.bar.BackgroundColor3=palette.raised
    end
    self.overlay.BackgroundColor3=palette.panel;self.portal.ScrollBarImageColor3=palette.gold
    self.overlay:SetAttribute("PFShown",#selected)
end
-- Header strip and card state. Collapsed, the card is just the Toggle in the
-- top-right corner: the authored strip is right-aligned, so hiding the other
-- strip items, the strip fill and the table leaves the button where it was.
-- An open picker card replaces the table beneath it.
function Leaderboard:renderChrome()
    local palette=self.palette;local expanded=self.shown
    local team=self.ui:FindFirstChild("TeamToggle",true)
    self.strip.BackgroundTransparency=if expanded then 0 else 1;self.strip.BackgroundColor3=palette.panel
    self.strip:SetAttribute("PointerEventsCapture",expanded)
    if self.skirt then self.skirt.Visible=expanded end
    local covered=(self.pickerOpen and expanded) or (self.teamOverlay~=nil and self.teamOverlay.Visible)
    self.tableUI.Visible=expanded and not covered
    for _,item in {self.titleUI,self.countUI,self.iconUI,self.columnsButton} do if item then item.Visible=expanded end end
    if team and not expanded then team.Visible=false end
    local close,glyph=self.closeGlyph,self.toggle:FindFirstChild("Icon")
    if close then close.Visible=expanded;if glyph then glyph.Visible=not expanded end end
    -- PF043 D10 (tools/atlas/author-pf043-leaderboard-phone.luau): open, the close key is a ghost; collapsed, its plate is back (it sits on the map)
    local plate=self.toggle:GetAttribute("PF043Plate")
    if type(plate)=="number" then
        self.toggle.BackgroundTransparency=if expanded then 1 else plate
        for _,s in self.toggle:GetChildren() do if s:IsA("UIStroke") then s.Enabled=not expanded end end
    end
    self.toggle:SetAttribute("SourceTooltip",if expanded then "Hide leaderboard" else "Show leaderboard")
    -- PF018: the attack list below sizes itself from the board's open/collapsed state.
    local region=self.ui.Parent;if region and region.Name=="PFLeaderboardRegion" then region:SetAttribute("PFBoardExpanded",expanded) end
    local trigger=self.columnsButton
    if trigger then
        trigger.BackgroundColor3=Style.surface(palette,if self.pickerOpen then palette.accentMuted else palette.raised,"chip")
        trigger:SetAttribute("Selected",self.pickerOpen)
        local stroke=trigger:FindFirstChild("Border");if stroke and stroke:IsA("UIStroke") then stroke.Color=if self.pickerOpen then palette.accent else palette.border end
        -- PF043 D10: the ghost trigger shows its open state in the glyph
        local bars=trigger:FindFirstChild("PFGlyph");if bars then for _,b in bars:GetChildren() do if b:IsA("Frame") then b.BackgroundColor3=if self.pickerOpen then palette.accent else palette.text end end end
    end
    local legacy=self.header:FindFirstChild("Picker");if legacy then legacy.Visible=trigger==nil end
    if self.iconUI then
        if not self.iconBound then self.iconBound=pcall(Icons.bind,self.iconUI,TITLE_ICON) end
        self.iconUI.ImageColor3=palette.gold
    end
    if self.titleUI then self.titleUI.Text=Style.Title;self.titleUI.TextColor3=palette.text end
    if self.countUI then
        self.countUI.Text=#self.rows.." alive";self.countUI.TextColor3=palette.muted
        self.countUI:SetAttribute("SourceTooltip","Living players")
    end
end
-- Column labels: which show, the sorted one's arrow and accent underline.
function Leaderboard:renderHeader(shown: {[string]: boolean})
    local palette=self.palette
    for _,column in Model.Data.playerColumns do
        local head=self.header:FindFirstChild(CELL_NAMES[column.id])
        head.Visible=shown[column.id]==true
        if not head.Visible then continue end
        local sorted=self.model.sortKey==column.id
        local label=Style.headerLabel(column)
        head.Text=if sorted then label..(if self.model.ascending then " ↑" else " ↓") else label
        head.TextColor3=if sorted then palette.text else palette.muted
        local underline=head:FindFirstChild("Bottom")
        if underline then underline.Visible=sorted;underline.BackgroundColor3=palette.accent end
        head:SetAttribute("Sorted",sorted)
    end
end
-- Content pass: columns, rows, pin, chrome. Never writes a size or position
-- (except each row PFBody's slide tween); the authored layout does the rest.
function Leaderboard:render()
    if self.destroyed then return end
    local selected=self:selectedColumns()
    local clanEmpty=true
    for _,row in self.rows do if row.clan and row.clan~="" then clanEmpty=false;break end end
    -- An empty clan column is skipped, never removed from the saved choice.
    local size=self.content.AbsoluteSize
    local inset=Style.Design.inset/Style.Design.width
    local chosen={}
    for _,column in Model.columns(selected) do
        if column.id~="clan" or not clanEmpty then table.insert(chosen,column) end
    end
    -- Chosen columns that do not fit the laid-out card at their floors are
    -- hidden (visibility only); the saved choice is never changed.
    local ids={};for _,column in chosen do table.insert(ids,column.id) end
    local fits=if size.X>0 then Style.fitColumns(size.X*(1-inset*2),ids) else nil
    self.columns={};local shown={};local dropped=0
    for _,column in chosen do
        if fits==nil or fits[column.id] then table.insert(self.columns,column);shown[column.id]=true else dropped+=1 end
    end
    self.ui:SetAttribute("ClanCollapsed",clanEmpty and table.find(selected,"clan")~=nil)
    self.ui:SetAttribute("PFColumnsDropped",dropped)
    self:renderHeader(shown)
    local localRank=nil;for _,row in self.rows do if row.pinned then localRank=row.rank;break end end
    -- The team table (fixed four-row window) shares the column below the pin.
    local team=if self.stats and self.stats.Visible then size.X/Style.Aspect.team else 0
    local fit=Style.capacity(size.Y-team,size.X*(1-inset*2),#self.rows,localRank);self.fit=fit
    self.list,self.pinnedRow=Style.split(self.rows,fit.pinned)
    self:renderRows()
    local pinned=self.pinnedRow
    if self.moreUI then self.moreUI.Visible=fit.more;self.moreUI.TextColor3=self.palette.muted end
    self.pinned.Visible=pinned~=nil
    if pinned then self:fill(self.pinned,pinned) end
    self.ui:SetAttribute("Expanded",self.shown)
    self.ui:SetAttribute("LivingPlayers",#self.rows)
    self.ui:SetAttribute("PinnedOwner",if pinned then pinned.owner else nil)
    self.ui:SetAttribute("PFVisibleRows",fit.visible)
    self.ui:SetAttribute("PFLeaderboardRevision",Style.Revision)
    if self.stackLayout then self.stackLayout(self) end
    self:renderPicker()
end
-- Compatibility for callers that relaid the board on resize: content only now.
function Leaderboard:layout(_screenSize: Vector2?) self:render() end

function Leaderboard:update(state: any,force: boolean?)
    if not state then return end
    self.state=state
    if not self.spawnOpened and state.phase~="Choosing" then
        self.spawnOpened=true
        self.showAfterSpawn=self.gameUI.AbsoluteSize.X>=960 and Leaderboard.opensAtStart(self.preferences)
        if self.showAfterSpawn and not self.userToggled then self.shown=true end
    end
    if not force and os.clock()-self.lastUpdate<1 then return end
    self.lastUpdate=os.clock()
    -- Source StatsTable.refresh skips hidden tables; every living visible row
    -- still records income even when none of the rate columns is selected.
    if self.shown then self.rows=self.model:update(state,self:selectedColumns(),self.preferences) end
    self.sortKey,self.ascending=self.model.sortKey,self.model.ascending
    self:render()
end

function Leaderboard:destroy()
    self:releaseFocus()
    self.destroyed=true
    if self.unsubscribe then self.unsubscribe() end
    for _,state in self.rowState do
        if state.tween then state.tween:Cancel() end
        if state.slide then state.slide:Cancel() end
    end
    for _,tween in self.chipTweens do tween:Cancel() end
    if self.accentUnsubscribe then self.accentUnsubscribe();self.accentUnsubscribe=nil end
    if self.ownAccent then self.ownAccent:destroy();self.ownAccent=nil end
    for _,connection in self.connections do connection:Disconnect() end
    for _,item in self.pool do item:Destroy() end
    self.pickerOpen=false;self.overlay.Visible=false;self.stackLayout=nil
end
Leaderboard.cellNames=CELL_NAMES

return Leaderboard
