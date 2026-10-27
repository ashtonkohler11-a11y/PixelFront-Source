--!strict
-- Native GameLeftSidebar/TeamStats/SpawnTimer adapter, pinned source93a136a1.
-- PF013: the team table, its header/rows/pinned row, the TeamToggle and the
-- team column picker are AUTHORED inside the leaderboard card
-- (tools/atlas/author-pf010-leaderboard.luau). This module fills content and
-- visibility only. The ownership bar segments and their hover tooltip keep
-- data-driven positions (they chart live team shares).
local RunService=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Battle=require(script.Parent.BattleHudTheme)
local WeightedText=require(script.Parent.BattleHudWeightedText)
local Model=require(script.Parent.TeamHUDModel)
local Palette=require(script.Parent.GraphicsPalette)
local Icons=require(script.Parent.ReferenceIcons)
local Names=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local Controller={};Controller.__index=Controller
local function sourceEase(x: number): number
    -- CSS ease-in-out is cubic-bezier(.42,0,.58,1), not a Roblox easing enum.
    local low,high=0,1
    for _=1,32 do local t=(low+high)/2;local bx=3*(1-t)^2*t*.42+3*(1-t)*t^2*.58+t^3;if bx<x then low=t else high=t end end
    local t=(low+high)/2;return 3*(1-t)*t^2+t^3
end
local function inside(ui: GuiObject?,p: Vector2): boolean
    if not ui then return false end
    local q,s=ui.AbsolutePosition,ui.AbsoluteSize
    return ui.Visible and p.X>=q.X and p.X<=q.X+s.X and p.Y>=q.Y and p.Y<=q.Y+s.Y
end
-- PF013: the card lives in Builder A's PFLeaderboardRegion (old place: Game).
local function board(gameUI: Instance): any
    local region=gameUI:FindFirstChild("PFLeaderboardRegion")
    return (region and region:FindFirstChild("Leaderboard")) or gameUI:WaitForChild("Leaderboard")
end
function Controller.new(gameUI: GuiObject,preferences: any,callbacks: any?): any
    local sidebar=board(gameUI)
    local self=setmetatable({gameUI=gameUI,sidebar=sidebar,preferences=preferences,callbacks=callbacks or {},
        model=Model.new(),palette=Palette.new(),shown=false,playerTeam=nil,playerColor=Color3.new(1,1,1),state=nil,lastUpdate=-math.huge,
        rows={},list={},pool={},rowFor={},segments={},tweens={},connections={},pickerOpen=false,barVisible=false,immunityVisible=false,hoveredIndex=nil},Controller)
    local function deep(name: string): any return sidebar:FindFirstChild(name,true) end
    self.stack=deep("StatsStack");self.ui=self.stack:WaitForChild("TeamTable")
    self.horizontal=self.ui:WaitForChild("Horizontal");self.content=self.horizontal:WaitForChild("Content")
    self.header=self.content:WaitForChild("Header");self.scroll=self.content:WaitForChild("Scroll");self.pinned=self.content:WaitForChild("Pinned")
    self.teamToggle=deep("TeamToggle");self.toggle=deep("Toggle");self.yourTeam=deep("YourTeam");self.gameID=deep("GameID")
    self.bar=gameUI:WaitForChild("TeamOwnershipBar")
    self.portal=deep("TeamColumnPicker") or gameUI:WaitForChild("TeamColumnPicker")
    self.overlay=deep("PFTeamPicker") or self.portal
    self.templates=gameUI:WaitForChild("Templates");self.formatNumber=assert(self.callbacks.formatNumber,"Source number formatter required")
    self.formatTroops=assert(self.callbacks.formatTroops,"Source troop formatter required")
    assert(type(self.formatNumber)=="function" and type(self.formatTroops)=="function","Team HUD presentation formatters must be functions")
    local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
    connect(self.teamToggle.Activated,function() self:toggleTeam() end)
    connect(self.header.Picker.Activated,function() self.pickerOpen=not self.pickerOpen;self:renderPicker() end)
    for _,column in Model.Data.columns do
        if column.hideable then connect(self.portal[column.id].Activated,function() self:toggleColumn(column.id) end) end
        -- Header cells are authored (one per column); a missing one is cloned
        -- from the template as content and placed by the authored layout.
        local head=self.header:FindFirstChild(column.id)
        if not head then head=self.templates.TeamStatsHeader:Clone();head.Name=column.id;head.Parent=self.header end
        head.Visible=false;head:SetAttribute("SourceTooltip",column.label);head.Text=column.headerText
        local icon=head:FindFirstChild("Icon");if icon then icon.Visible=false end
        if icon and column.icon and head:GetAttribute("PFLeaderboardOwner")==nil then
            icon.Visible=true;if column.white then Icons.bindWhite(icon,column.icon) else Icons.bind(icon,column.icon) end
        end
        if head.Text=="" then head.Text=string.upper(column.label) end
        head.Active=column.orderable
        if column.orderable then connect(head.Activated,function() self.model:setSort(column.id);self:update(self.state,true) end) end
    end
    connect(Input.InputBegan,function(event)
        if not self.pickerOpen or (event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch) then return end
        local p=Vector2.new(event.Position.X,event.Position.Y)
        if not inside(self.overlay,p) and not inside(self.header.Picker,p) then self.pickerOpen=false;self:renderPicker() end
    end)
    connect(RunService.Heartbeat,function()
        local now=os.clock()
        for index,transition in self.tweens do
            local alpha=math.clamp((now-transition.started)/.1,0,1);local eased=sourceEase(alpha)
            local item=self.segments[index];item.Position=transition.position:Lerp(transition.targetPosition,eased);item.Size=transition.size:Lerp(transition.targetSize,eased)
            if alpha>=1 then item.Position=transition.targetPosition;item.Size=transition.targetSize;self.tweens[index]=nil end
        end
    end)
    self.unsubscribe=preferences:subscribe(function(key)
        if key=="settings.teamStatsColumns" then self:update(self.state,true) end
    end)
    self:reset();return self
end
function Controller:teamColor(team: string): Color3
    return if self.callbacks.teamColor then self.callbacks.teamColor(team) else self.palette:teamBase(team)
end
function Controller:setPalette(name: string) self.paletteName=name;self.palette=Palette.new(name);if self.state then self:updateBar(self.state) end end
-- The player table stays where it is authored; the team table sits under it
-- in the same card. TeamHUD refreshes its content after each board render.
function Controller:attachLeaderboard(leaderboard: any)
    self.leaderboard=leaderboard;self.playerTable=leaderboard.tableUI
    self.model:setGoldRateTracker(leaderboard.goldRateTracker)
    leaderboard:setStackLayout(function() self:render() end)
    self:render()
end
function Controller:toggleTeam()
    if not self.state or self.state.gameConfig.gameMode~="Team" then return end
    self.shown=not self.shown;self.scroll.CanvasPosition=Vector2.zero
    if not self.shown then self.pickerOpen=false end
    self:update(self.state,true)
end
function Controller:toggleColumn(id: string)
    local nextColumns=Model.toggleColumn(self.preferences:statsColumns("team"),id)
    if nextColumns then self.preferences:setStatsColumns("team",nextColumns) end
end
function Controller:setImmunityBarVisible(visible: boolean) self.immunityVisible=visible end
function Controller:hover(index: number?)
    self.hoveredIndex=index;self:layoutTooltip(self.gameUI.AbsoluteSize)
end
function Controller:updateBar(state: any)
    self.strip=Model.strip(state)
    local visible=#self.strip>0
    self.bar.Visible=visible
    if visible~=self.barVisible then
        self.barVisible=visible;if self.callbacks.barVisibilityChanged then self.callbacks.barVisibilityChanged(visible) end
    end
    for index,row in self.strip do
        local item=self.segments[index]
        if not item then
            item=self.templates.TeamOwnershipSegment:Clone();item.Name="Segment"..index;item.Parent=self.bar;self.segments[index]=item
            table.insert(self.connections,item.MouseEnter:Connect(function() self:hover(index) end))
            table.insert(self.connections,item.MouseLeave:Connect(function() if self.hoveredIndex==index then self:hover(nil) end end))
        end
        -- Live team shares: segment position/width ARE the data (chart).
        item.Visible=true;item.BackgroundColor3=self:teamColor(row.team);item:SetAttribute("Team",row.team);item:SetAttribute("Ratio",row.ratio)
        -- PF-041: on the authored glass bar (TeamOwnershipBar PF041) the segment fills the bar's height, carries its share
        -- ("Tribes 60%" / "22%") where it fits, and your team gets a white edge + a caret
        local glassBar=self.bar:GetAttribute("PF041")==true
        local position,size=UDim2.fromScale(row.left,0),if glassBar then UDim2.fromScale(row.ratio,1) else UDim2.new(row.ratio,0,0,9)
        if glassBar then
            local mine=state.players[1]~=nil and state.players[1].team==row.team
            local label=item:FindFirstChild("PFLabel");local you=item:FindFirstChild("PFYou");local caret=item:FindFirstChild("PFCaret")
            if label and label:IsA("TextLabel") then
                local pct=tostring(math.floor(row.ratio*100+.5)).."%"
                local tribes=row.team=="Bot" or row.team=="Tribes"
                label.Text=if tribes then "Tribes "..pct else pct
                label.Visible=self.bar.AbsoluteSize.X*row.ratio>=(if tribes then 64 else 40)
            end
            if you and you:IsA("UIStroke") then you.Enabled=mine end
            if caret and caret:IsA("GuiObject") then caret.Visible=mine end
            item.BackgroundTransparency=if row.team=="Bot" then .45 else 0
        end
        if item:GetAttribute("LastTeam")~=row.team then
            self.tweens[index]=nil;item.Position=position;item.Size=size;item:SetAttribute("LastTeam",row.team)
        elseif item:GetAttribute("LastLeft")~=row.left or item:GetAttribute("LastRatio")~=row.ratio then
            self.tweens[index]={started=os.clock(),position=item.Position,size=item.Size,targetPosition=position,targetSize=size}
        end
        item:SetAttribute("LastLeft",row.left);item:SetAttribute("LastRatio",row.ratio)
    end
    for index=#self.strip+1,#self.segments do self.segments[index].Visible=false;self.tweens[index]=nil end
    if self.hoveredIndex and self.hoveredIndex>#self.strip then self.hoveredIndex=nil end
    self:layoutTooltip(self.gameUI.AbsoluteSize)
end
-- Hover tooltip over a share segment: follows the hovered segment (dynamic).
function Controller:layoutTooltip(size: Vector2)
    local text,x=Model.tooltip(self.strip or {},self.hoveredIndex or 0,size.X)
    local tooltip=self.bar.Tooltip;tooltip.Visible=text~=nil and self.barVisible
    if text and x then
        tooltip.Text=text;tooltip.Position=UDim2.fromOffset(x,14)
        if not self.weightedText then self.weightedText=WeightedText.new(function() end,512) end
        local measure=self.weightedText:measure(text,12,112,Battle.Typography.Body)
        tooltip.Size=UDim2.fromOffset(math.min(128,measure.X+16),measure.Y+8)
    end
end
function Controller:cellText(row: any,id: string): string
    if id=="rank" then return tostring(row.rank) end
    if id=="team" then return row.name end
    local value=row.values[id] or 0
    if id=="tiles" then
        local valid=self.state.map.landCount-(self.state.falloutCount or 0)
        return Model.formatPercentage(if valid>0 then value/valid else 0)
    end
    return if id=="troops" or id=="maxtroops" then self.formatTroops(value) else self.formatNumber(value)
end
function Controller:fill(item: Frame,row: any)
    item:SetAttribute("Team",row.team);item:SetAttribute("Rank",row.rank);item:SetAttribute("Emphasized",row.emphasized)
    local shown={};for _,column in self.columns do shown[column.id]=true end
    for _,column in Model.Data.columns do
        local cell=item:FindFirstChild(column.id)
        if not shown[column.id] then if cell then cell.Visible=false end;continue end
        if not cell then cell=self.templates.TeamStatsCell:Clone();cell.Name=column.id;cell.Parent=item end
        cell.Visible=true;cell.Text=self:cellText(row,column.id);Battle.Typography.apply(cell,if column.id=="team" then "Label" else "Value")
        cell.TextColor3=if column.id=="gold" then Battle.Gold elseif column.id=="rank" and not row.emphasized then Battle.Muted else Battle.Text
        cell.TextXAlignment=if column.align=="start" or column.id=="team" then Enum.TextXAlignment.Left elseif column.id=="rank" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Right
        local divider=cell:FindFirstChild("Divider");if divider then divider.Visible=false end
        local bottom=cell:FindFirstChild("Bottom");if bottom then bottom.Visible=false end
    end
    item.BackgroundColor3=if row.emphasized then Battle.Raised:Lerp(Battle.Cobalt,.24) else Battle.Panel
    item.BackgroundTransparency=if row.emphasized then 0 else 1
end
-- Every team gets a row clone (a handful at most); the authored list layout
-- orders them by LayoutOrder.
function Controller:renderRows()
    if not self.state then return end
    local live={}
    for index,row in self.list do
        live[row.team]=true
        local item=self.rowFor[row.team]
        if not item then
            for _,free in self.pool do if free:GetAttribute("PFFree")==true then item=free;break end end
            if not item then
                local widget=self.templates.TeamStatsRow:Clone();widget.Name="Row"..(#self.pool+1);widget.Parent=self.scroll;table.insert(self.pool,widget);item=widget
                table.insert(self.connections,widget.MouseEnter:Connect(function() widget.BackgroundColor3=Battle.Raised:Lerp(Battle.Cobalt,.12);widget.BackgroundTransparency=.2 end))
                table.insert(self.connections,widget.MouseLeave:Connect(function() widget.BackgroundTransparency=if widget:GetAttribute("Emphasized")==true then 0 else 1 end))
            end
            item:SetAttribute("PFFree",false);self.rowFor[row.team]=item
        end
        item.LayoutOrder=index;item.Visible=true;self:fill(item,row)
    end
    for team,item in self.rowFor do if not live[team] then self.rowFor[team]=nil;item.Visible=false;item:SetAttribute("PFFree",true) end end
end
function Controller:renderPicker()
    local open=self.pickerOpen and self.shown and self.stack.Visible
    self.overlay.Visible=open;if self.overlay~=self.portal then self.portal.Visible=true end
    if not open then return end
    local selected=self.preferences:statsColumns("team")
    for _,column in Model.Data.columns do if column.hideable then
        local item=self.portal[column.id];local checked=table.find(selected,column.id)~=nil
        item.Check.Mark.Visible=checked;item.Active=not(checked and #selected==1);item:SetAttribute("Disabled",not item.Active)
        local caption=item:FindFirstChild("PFLabel");(caption or item).TextTransparency=if item.Active then 0 else .5
        item.Check.BackgroundColor3=if checked then Battle.Cobalt else Battle.Panel
    end end
end
-- Content pass: which columns show, header text/sort, rows, the pinned own
-- team, and the card pieces TeamHUD owns (TeamToggle, YourTeam, team table).
function Controller:render()
    if self.destroyed or self.arranging then return end;self.arranging=true
    local teamMode=self.state~=nil and self.state.gameConfig.gameMode=="Team"
    local boardShown=self.leaderboard==nil or self.leaderboard.shown
    self.columns=Model.columns(self.preferences:statsColumns("team"))
    local shown={};for _,column in self.columns do shown[column.id]=true end
    for _,column in Model.Data.columns do
        local head=self.header:FindFirstChild(column.id)
        if head then
            head.Visible=shown[column.id]==true
            local sorted=self.model.sortKey==column.id
            local sort=head:FindFirstChild("Sort");if sort then sort.Visible=false end
            head.TextColor3=if sorted then Battle.Text else Battle.Muted
            head:SetAttribute("Sorted",sorted)
        end
    end
    self.list,self.pinnedRow=Model.pinnedRows(self.rows)
    self:renderRows()
    self.pinned.Visible=self.pinnedRow~=nil
    if self.pinnedRow then self:fill(self.pinned,self.pinnedRow) end
    self.stack.Visible=self.shown and teamMode and boardShown
    self.ui.Visible=self.stack.Visible
    self.teamToggle.Visible=teamMode and boardShown
    Icons.bind(self.teamToggle.Icon,if self.shown then "TeamHUDTeamIconSolidWhite" else "TeamHUDTeamIconRegularWhite")
    Icons.bind(self.toggle.Icon,if boardShown and self.leaderboard~=nil then "TeamHUDLeaderboardIconSolidWhite" else "TeamHUDLeaderboardIconRegularWhite")
    local yourVisible=teamMode and self.yourTeamVisible==true and boardShown
    local yourLabel=Model.teamLabel(self.playerTeam,self.teamClanTag).." ⦿"
    self.yourTeam.Visible=yourVisible;self.yourTeam.TeamName.Text=yourLabel;self.yourTeam.TeamName.TextColor3=self.playerColor
    self.yourTeam.Caption.Text=Model.Data.yourTeam
    if self.gameID then self.gameID.Visible=false;self.gameID.Text="" end
    if not self.stack.Visible and GuiService and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.stack) then GuiService.SelectedObject=self.toggle end
    self.sidebar:SetAttribute("TeamStatsExpanded",self.ui.Visible);self.ui:SetAttribute("PinnedTeam",if self.pinnedRow then self.pinnedRow.team else nil);self.ui:SetAttribute("Teams",#self.rows)
    self:layoutTooltip(self.gameUI.AbsoluteSize);self:renderPicker()
    self.arranging=false
end
-- Compatibility for callers that relaid the HUD on resize: content only now.
function Controller:layout(_size: Vector2?) self:render() end
function Controller:update(state: any,force: boolean?)
    if not state then return end;self.state=state;self:updateBar(state)
    local now=os.clock();local refresh=force or now-self.lastUpdate>=1 or self.lastPhase~=state.phase
    if refresh then
        self.lastUpdate=now
        if self.playerTeam==nil and state.players[1] and state.players[1].team~=nil then self.playerTeam=state.players[1].team;self.playerColor=self:teamColor(self.playerTeam) end
        self.yourTeamVisible=state.gameConfig.gameMode=="Team" and state.phase=="Choosing"
        local teammates={};for _,owner in state.playerOrder do if state.players[owner].team==self.playerTeam then table.insert(teammates,{clanTag=Names.clan(state,owner,self.preferences)}) end end
        self.teamClanTag=Model.resolveTeamClanTag(teammates)
        if self.shown and state.gameConfig.gameMode=="Team" then self.rows=self.model:update(state,self.preferences:statsColumns("team")) end
        self.lastPhase=state.phase;self:render()
    end
end
function Controller:reset()
    self.palette=Palette.new(self.paletteName or "default")
    self.model:reset();self.shown=false;self.playerTeam=nil;self.teamClanTag=nil;self.playerColor=Color3.new(1,1,1);self.rows={};self.list={};self.strip={};self.state=nil;self.lastUpdate=-math.huge;self.yourTeamVisible=false;self.hoveredIndex=nil;self.pickerOpen=false;self.immunityVisible=false
    self.lastPhase=nil
    self.scroll.CanvasPosition=Vector2.zero
    for team,item in self.rowFor do item.Visible=false;item:SetAttribute("PFFree",true);self.rowFor[team]=nil end
    self.ui.Visible=false;self.stack.Visible=false;self.bar.Visible=false;self.overlay.Visible=false;self.yourTeam.Visible=false;self.teamToggle.Visible=false
    if self.gameID then self.gameID.Visible=false end
    for _,item in self.segments do item.Visible=false end
    table.clear(self.tweens)
    if self.barVisible and self.callbacks.barVisibilityChanged then self.callbacks.barVisibilityChanged(false) end;self.barVisible=false
end
function Controller:destroy()
    self.destroyed=true;if self.weightedText then self.weightedText:destroy() end
    self:reset();if self.unsubscribe then self.unsubscribe() end
    for _,connection in self.connections do connection:Disconnect() end
    if self.leaderboard then self.leaderboard:setStackLayout(nil) end
    for _,item in self.pool do item:Destroy() end;for _,item in self.segments do item:Destroy() end
    for _,column in Model.Data.columns do
        local head=self.header:FindFirstChild(column.id)
        if head and head:GetAttribute("PFLeaderboardOwner")==nil then head:Destroy() end
    end
end
Controller.sourceEase=sourceEase
return Controller
