--!strict
-- Original responsive composer; pinned phrase/recipient/reference state stays intact.
local Shared=game:GetService("ReplicatedStorage").Shared
local Catalog=require(Shared.QuickChatCatalog)
local P=require(script.Parent.QuickChatPresentation)
local Colors=require(script.Parent.NationColors)
local Battle=require(script.Parent.BattleHudTheme)
local TextBounds=require(script.Parent.BattleHudTextBounds)
-- PF029: the authored panels (desktop + compact) and the per-recipient cooldown they show.
local Social: any=nil -- soft: harnesses without it keep the three-column body
do local ok,result=pcall(function() return require(script.Parent.SocialPanels) end);if ok then Social=result end end
local Theme=table.clone(require(Shared.Theme))
Theme.Panel=Battle.Panel;Theme.PanelRaised=Battle.Raised;Theme.Background=Battle.Panel
Theme.Border=Battle.Border;Theme.Accent=Battle.Cobalt;Theme.Text=Battle.Text;Theme.MutedText=Battle.Muted
Theme.Gold=Battle.Gold;Theme.Danger=Battle.Danger;Theme.Font=Battle.Font
local TextService=game:GetService("TextService")
local GuiService=game:GetService("GuiService")
local UIS=game:GetService("UserInputService")
local Q={};Q.__index=Q
local function listen(self: any,signal: RBXScriptSignal,callback: any,pool: any?)
    table.insert(pool or self.connections,signal:Connect(function(...)if not self.destroyed then callback(...)end end))
end
local function contains(root: Instance,item: Instance?): boolean return item~=nil and item:IsDescendantOf(root) end
local function available(item: GuiObject?): boolean
    if not item or not item.Parent or not item.Selectable then return false end
    local node: Instance?=item
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node=node.Parent
    end
    return true
end
local function feedback(self: any,button: GuiObject,pool: any?)
    local border=button:FindFirstChild("FocusBorder")
    if not border then return end
    listen(self,button.SelectionGained,function()border.Enabled=true end,pool)
    listen(self,button.SelectionLost,function()border.Enabled=false end,pool)
    listen(self,button.MouseEnter,function()border.Enabled=true end,pool)
    listen(self,button.MouseLeave,function()border.Enabled=GuiService.SelectedObject==button end,pool)
end
function Q.new(ui: Frame,callbacks: any)
    P.preferences=callbacks.preferences
    local self=setmetatable({ui=ui,callbacks=callbacks,modal=ui:WaitForChild("QuickChatModal"),connections={},rowConnections={},phraseRows={},playerRows={},players={},search="",sort=false,required=false,destroyed=false,page="Categories",gamepad=false},Q)
    self.body=self.modal.Body;self.content=self.body.Section.Content;self.columns=self.content.Columns;self.stages=self.content.Stages
    listen(self,self.modal.Backdrop.Activated,function()self:close()end)
    listen(self,self.body.Close.Activated,function()self:close()end)
    listen(self,self.body.StepBack.Activated,function()self:key(Enum.KeyCode.Escape)end)
    listen(self,self.content.Send.Activated,function()self:sendMessage()end)
    for _,category in Catalog.CategoryOrder do
        local button=self.columns.Categories[category]
        listen(self,button.Activated,function()self:selectCategory(category)end);feedback(self,button)
    end
    for _,name in {"Categories","Phrases","Players"} do
        local button=self.stages[name]
        listen(self,button.Activated,function()self:showPage(name)end);feedback(self,button)
    end
    for _,button in {self.body.Close,self.body.StepBack,self.content.Send,self.columns.Players.Sort,self.columns.Players.Search} do feedback(self,button) end
    listen(self,self.columns.Players.Sort.Activated,function()self.sort=not self.sort;self:render()end)
    listen(self,self.columns.Players.Search:GetPropertyChangedSignal("Text"),function()
        if self.updatingSearch then return end;self.search=P.lower(self.columns.Players.Search.Text);self:render()
    end)
    listen(self,ui:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout();self:focusActive()end)
    listen(self,GuiService:GetPropertyChangedSignal("SelectedObject"),function()self:revealSelection()end)
    local function device(kind: Enum.UserInputType)
        self.gamepad=string.sub(kind.Name,1,7)=="Gamepad"
        if self.gamepad then self:focusActive() end
    end
    listen(self,UIS.LastInputTypeChanged,device);device(UIS:GetLastInputType())
    listen(self,ui.Destroying,function()self:destroy()end)
    -- PF029: when the place carries the authored panels they replace the three-column body (kept as the fallback).
    local nodes=if Social then Social.Chat.find(self.modal) else nil
    if nodes then
        self.panel=Social.Chat.new(nodes,{
            categories=function()
                -- the board order: social first, the long Warnings list late
                local out={};for _,key in {"greet","help","attack","defend","warnings","misc"} do if Catalog.Categories[key] then table.insert(out,{key=key,label=if key=="misc" then "Misc" else P.text("chat.cat."..key)}) end end;return out
            end,
            phrases=function(category: string)
                local out={};for _,item in Catalog.Categories[category] or {} do table.insert(out,{key=item.key,text=P.text("chat."..item.key),requiresPlayer=item.requiresPlayer}) end;return out
            end,
            nations=function()
                local out={};if not self.state then return out end
                for _,owner in P.sortedPlayers(self.state,self.players,true,"") do
                    if owner~=self.recipient then table.insert(out,{owner=owner,name=P.name(self.state,owner),color=self.colors and self.colors[owner],land=Social.land(self.state,owner)}) end
                end
                return out
            end,
            send=function(key: string,player: number?)
                if self.sender and self.recipient then
                    local fields={targetOwner=self.recipient,quickChatKey=key};if player then fields.targetPlayer=player end
                    self.callbacks.send("QuickChat",fields)
                end
                self:close()
            end,
            close=function() self:close() end,
            cooldown=function(): number
                return if self.state and self.recipient then Social.cooldown(self.state,1,self.recipient) else 0
            end})
        self.body.Visible=false
    end
    self:render();return self
end
function Q:setPreferences(preferences: any)
    self.callbacks.preferences=preferences;P.preferences=preferences
    if self.modal.Visible then self:render() end
end
function Q:destroyRows()
    for _,connection in self.rowConnections do connection:Disconnect()end;table.clear(self.rowConnections)
    for _,row in self.phraseRows do row:Destroy()end;for _,row in self.playerRows do row:Destroy()end
    table.clear(self.phraseRows);table.clear(self.playerRows)
end
function Q:destroy()
    if self.destroyed then return end
    if contains(self.modal,GuiService.SelectedObject) then GuiService.SelectedObject=nil end
    if self.panel then self.panel:destroy() end
    self.destroyed=true;self:destroyRows()
    for _,connection in self.connections do connection:Disconnect()end;table.clear(self.connections);self.state=nil
end
function Q:update(state: any,colors: any?)
    if self.destroyed then return end;self.state=state
    if colors then self.colors=colors
    elseif not self.colors then
        local allocator=Colors.new();self.colors={}
        for _,owner in state.playerOrder do local player=state.players[owner];self.colors[owner]=if player.playerType=="Nation" then allocator:assign(player.id) elseif player.playerType=="Bot" then Theme.Bot else Theme.playerColor(player.id) end
    end
    if self.panel and self.modal.Visible then self.panel:refresh() end -- PF029: the cooldown ring counts down
end
function Q:beginOpen(recipient: number)
    if not self.modal.Visible then self.returnSelection=GuiService.SelectedObject end
    self.recipient=recipient;self.sender=1;self.players=P.playersAtOpen(self.state);self.modal.Visible=true
    self.ui.Radial.Visible=false
end
-- PF029: the authored panel opens where the circle menu was (the compact one top centre on a phone).
function Q:openPanel(recipient: number,category: string?)
    local point=Social.radialPoint(self.ui)
    self:beginOpen(recipient)
    self.panel:open(Social.identity(self.state,recipient,self.colors and self.colors[recipient],self.callbacks.preferences),point,nil,category)
    self.focusRequest=nil;self:focusActive()
end
function Q:open(recipient: number)
    if not self.state or not self.state.players[recipient] then return end
    if self.panel then self:openPanel(recipient);return end
    self:beginOpen(recipient);self.page="Categories";self.focusRequest="Categories";self:render()
end
function Q:openWithSelection(category: string,key: string,recipient: number)
    if not self.state or not self.state.players[recipient] then return end
    if self.panel then
        self:openPanel(recipient,category)
        local phrase=Catalog.ByKey[category.."."..key] or Catalog.ByKey[key];if phrase then self.panel:openPhrase(phrase.key) end
        return
    end
    self:beginOpen(recipient);self:selectCategory(category);self:selectPhrase(key);self:render()
end
function Q:close()
    if self.panel then self.panel:close() end
    self.category=nil;self.phraseText=nil;self.preview=nil;self.required=false;self.modal.Visible=false;self.page="Categories"
    self.columns.Players.Search:ReleaseFocus()
    if contains(self.modal,GuiService.SelectedObject) then GuiService.SelectedObject=if available(self.returnSelection) then self.returnSelection else nil end
    self.returnSelection=nil;self.focusRequest=nil;self:render()
end
function Q:reset()
    self:close();self.state=nil;self.players={};self.recipient=nil;self.sender=nil;self.colors=nil
end
function Q:selectCategory(category: string)
    if not Catalog.Categories[category] then return end
    self.category=category;self.phraseText=nil;self.preview=nil;self.required=false
    self.page="Phrases";self.focusRequest="Phrases";self.columns.Phrases.Scroll.CanvasPosition=Vector2.zero;self:render()
end
function Q:selectPhrase(key: string)
    if not self.category then return end
    local phrase=Catalog.ByKey[self.category.."."..key] or Catalog.ByKey[key]
    if not phrase or phrase.category~=self.category then return end
    self.quickChatKey=phrase.key;self.template=P.text("chat."..phrase.key);self.phraseText=self.template;self.preview="chat."..phrase.key;self.required=phrase.requiresPlayer
    self.page=if self.required then "Players" else "Phrases";self.focusRequest=if self.required then "Players" else "Send";self:render()
end
function Q:selectPlayer(owner: number)
    if not self.preview or not self.state or not table.find(self.players,owner) then return end
    self.preview=if self.template then P.replacePlayer(self.template,P.name(self.state,owner)) else nil
    self.selectedPlayer=owner;self.required=false;self.focusRequest="Send";self:render()
end
function Q:sendEnabled(): boolean return self.preview~=nil and (not self.required or self.selectedPlayer~=nil)end
function Q:sendMessage()
    if not self:sendEnabled() then return end
    if self.sender and self.recipient and self.quickChatKey then
        local fields={targetOwner=self.recipient,quickChatKey=self.quickChatKey};if self.selectedPlayer then fields.targetPlayer=self.selectedPlayer end
        self.callbacks.send("QuickChat",fields)
    end
    self.preview=nil;self.category=nil;self.required=false;self:close()
end
function Q:canShow(name: string): boolean
    return name=="Categories" or (name=="Phrases" and self.category~=nil) or (name=="Players" and (self.required or self.selectedPlayer~=nil))
end
function Q:showPage(name: string)
    if not self:canShow(name) then return end
    if name~="Players" then self.columns.Players.Search:ReleaseFocus() end
    self.page=name;self.focusRequest=name;self:layout();self:focusActive()
end
function Q:key(key: Enum.KeyCode): boolean
    if not self.modal.Visible then return false end
    if key==Enum.KeyCode.Escape or key==Enum.KeyCode.ButtonB then
        if self.panel then if not self.panel:back() then self:close() end;return true end -- PF029: B steps out of "who?" first
        if UIS:GetFocusedTextBox()==self.columns.Players.Search then
            self.columns.Players.Search:ReleaseFocus();self.focusRequest="Players";self:focusActive();return true
        end
        if self.compact and self.page~="Categories" then self:showPage(if self.page=="Players" and self.category then "Phrases" else "Categories")
        else self:close() end
        return true
    end
    return false
end
function Q:intercepts(): boolean return self.modal.Visible end
function Q:row(parent: ScrollingFrame,text: string,index: number,selected: boolean,owner: number?): TextButton
    local row=self.ui.Templates.QuickChatOption:Clone();row.Name=if owner then "Player"..owner else "Phrase"..index;row.Text=text;row.Visible=true;row.Parent=parent
    row.BackgroundColor3=if selected then Theme.PanelRaised:Lerp(Theme.Accent,.2) else Theme.PanelRaised
    row.TextColor3=Theme.Text;row.TextSize=16;Battle.Typography.apply(row,"Button");row.Active=true;row.Selectable=true
    row:SetAttribute("Selected",selected);row:SetAttribute("Owner",owner);row.Size=UDim2.new(1,-6,0,44);row.LayoutOrder=index
    if owner then local border=row.TerritoryBorder;border.Enabled=true;border.Color=self.colors[owner] end
    feedback(self,row,self.rowConnections);return row
end
function Q:render()
    if self.destroyed then return end
    local previous=GuiService.SelectedObject
    local owner=if contains(self.columns.Players.Scroll,previous) then previous:GetAttribute("Owner") else nil
    local phrase=if contains(self.columns.Phrases.Scroll,previous) then previous:GetAttribute("QuickChatKey") else nil
    self:destroyRows()
    self.body.Title.Text=P.text("chat.title");self.columns.Categories.Title.Text=P.text("chat.category");self.columns.Phrases.Title.Text=P.text("chat.phrase");self.columns.Players.Title.Text=P.text("chat.player")
    for _,category in Catalog.CategoryOrder do
        local b=self.columns.Categories[category];b.Text=P.text("chat.cat."..category)
        b.BackgroundColor3=if self.category==category then Theme.PanelRaised:Lerp(Theme.Accent,.2) else Theme.PanelRaised;b:SetAttribute("Selected",self.category==category)
    end
    self.columns.Players.Sort.Check.Mark.Visible=self.sort
    self.columns.Players.Search.PlaceholderText=P.text("chat.search")
    self.updatingSearch=true;if self.columns.Players.Search.Text~=self.search then self.columns.Players.Search.Text=self.search end;self.updatingSearch=false
    if self.category then
        for index,item in Catalog.Categories[self.category] do
            local text=P.text("chat."..item.key);local row=self:row(self.columns.Phrases.Scroll,text,index,self.phraseText==text)
            row:SetAttribute("QuickChatKey",item.key);table.insert(self.phraseRows,row)
            listen(self,row.Activated,function()self:selectPhrase(item.phraseKey)end,self.rowConnections)
        end
    end
    if self.state and self:canShow("Players") then
        for index,id in P.sortedPlayers(self.state,self.players,self.sort,self.search) do
            local row=self:row(self.columns.Players.Scroll,P.name(self.state,id),index,self.selectedPlayer==id,id);table.insert(self.playerRows,row)
            listen(self,row.Activated,function()self:selectPlayer(id)end,self.rowConnections)
        end
    end
    self.content.Preview.Text=if self.preview then P.text(self.preview) else P.text("chat.build")
    local active=self:sendEnabled();self.content.Send.Text=P.text("chat.send");self.content.Send.Active=active;self.content.Send.Selectable=active
    self.content.Send.BackgroundColor3=if active then Theme.Accent else Theme.PanelRaised;self.content.Send.TextColor3=if active then Theme.Background else Theme.MutedText;self.content.Send:SetAttribute("Enabled",active)
    self.modal:SetAttribute("Recipient",self.recipient);self.modal:SetAttribute("ReferencePlayer",self.selectedPlayer);self.modal:SetAttribute("QuickChatKey",self.quickChatKey);self.modal:SetAttribute("Category",self.category)
    self:layout()
    if self.gamepad and self.modal.Visible and not self.focusRequest then
        for _,row in if owner then self.playerRows else self.phraseRows do
            if (owner and row:GetAttribute("Owner")==owner) or (phrase and row:GetAttribute("QuickChatKey")==phrase) then self.focusRequest=row;break end
        end
    end
    self:focusActive()
end
function Q:focusActive()
    if self.destroyed or not self.gamepad or not self.modal.Visible or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() then return end
    if self.panel then -- PF029: keep a live selection inside the panel, else its first chip
        if self.panel:visible() then
            local selected=GuiService.SelectedObject;local holder=self.panel.current and self.panel.current.holder
            if not (holder and contains(holder,selected) and available(selected)) then local first=self.panel:first();if available(first) then GuiService.SelectedObject=first end end
        end
        return
    end
    local request=self.focusRequest;self.focusRequest=nil
    local target=request
    if type(request)=="string" then
        if request=="Send" then target=self.content.Send
        elseif request=="Categories" then target=self.columns.Categories[Catalog.CategoryOrder[1]]
        elseif request=="Phrases" then target=self.phraseRows[1]
        elseif request=="Players" then target=self.playerRows[1] or self.columns.Players.Sort end
    end
    if not available(target) then
        if contains(self.body,GuiService.SelectedObject) and available(GuiService.SelectedObject) then return end
        target=if self.page=="Phrases" then self.phraseRows[1] elseif self.page=="Players" then self.playerRows[1] or self.columns.Players.Sort else self.columns.Categories[Catalog.CategoryOrder[1]]
    end
    GuiService.SelectedObject=if available(target) then target else self.body.Close
    self:revealSelection()
end
function Q:revealSelection()
    if not self.modal.Visible then return end
    local selected=GuiService.SelectedObject
    if not contains(self.columns,selected) then return end
    local parent=selected.Parent
    if not parent:IsA("ScrollingFrame") or parent==self.columns or parent.AbsoluteSize.Y<=0 then return end
    local top=selected.Position.Y.Offset;local bottom=top+selected.Size.Y.Offset;local current=parent.CanvasPosition.Y
    local wanted=if top<current then top elseif bottom>current+parent.AbsoluteSize.Y then bottom-parent.AbsoluteSize.Y else current
    parent.CanvasPosition=Vector2.new(0,math.clamp(wanted,0,math.max(0,parent.CanvasSize.Y.Offset-parent.AbsoluteSize.Y)))
end
function Q:layoutNavigation()
    local groups={};local nodes={self.body.Close}
    if self.body.StepBack.Visible then table.insert(nodes,self.body.StepBack) end
    if self.stages.Visible then for _,name in {"Categories","Phrases","Players"} do if self.stages[name].Selectable then table.insert(nodes,self.stages[name]) end end end
    if self.columns.Categories.Visible then local group={};for _,category in Catalog.CategoryOrder do table.insert(group,self.columns.Categories[category])end;table.insert(groups,group)end
    if self.columns.Phrases.Visible then table.insert(groups,self.phraseRows)end
    if self.columns.Players.Visible then local group={self.columns.Players.Sort,self.columns.Players.Search};for _,row in self.playerRows do table.insert(group,row)end;table.insert(groups,group)end
    for _,group in groups do for _,node in group do table.insert(nodes,node)end end
    if self.content.Send.Selectable then table.insert(nodes,self.content.Send)end
    for index,node in nodes do
        node.SelectionOrder=index;node.NextSelectionUp=nodes[math.max(1,index-1)];node.NextSelectionDown=nodes[math.min(#nodes,index+1)]
        node.NextSelectionLeft=node.NextSelectionUp;node.NextSelectionRight=node.NextSelectionDown
    end
    if not self.compact then
        for i,group in groups do for j,node in group do
            local left,right=groups[i-1],groups[i+1]
            node.NextSelectionLeft=if left and #left>0 then left[math.min(j,#left)] else node
            node.NextSelectionRight=if right and #right>0 then right[math.min(j,#right)] else self.content.Send.Selectable and self.content.Send or node
        end end
    end
end
function Q:layout()
    if self.destroyed then return end
    local size=self.ui.AbsoluteSize;local width=math.max(240,math.min(960,size.X-24));local height=math.max(240,math.min(540,size.Y-24))
    self.compact=size.X<960 or size.Y<560
    if self.compact then width=math.max(240,size.X-16);height=math.max(240,size.Y-16) end
    self.body.Size=UDim2.fromOffset(width,height);self.body.StepBack.Visible=self.compact and self.page~="Categories"
    self.body.Title.Position=UDim2.fromOffset(if self.body.StepBack.Visible then 64 else 16,12)
    self.body.Title.Size=UDim2.new(1,if self.body.StepBack.Visible then -128 else -80,0,36)
    local availableWidth=width-24;local contentHeight=height-60
    self.stages.Visible=self.compact and contentHeight>=280;self.stages.Size=UDim2.new(1,-24,0,44)
    for index,name in {"Categories","Phrases","Players"} do
        local button=self.stages[name];local active=self:canShow(name)
        button.Position=UDim2.fromOffset((index-1)*(availableWidth+6)/3,0);button.Size=UDim2.fromOffset((availableWidth-12)/3,44)
        button.Text=P.text(if name=="Categories" then "chat.category" elseif name=="Phrases" then "chat.phrase" else "chat.player")
        button.Active=active;button.Selectable=active;button.TextColor3=if active then Theme.Text else Theme.MutedText
        button.BackgroundColor3=if self.page==name then Theme.PanelRaised:Lerp(Theme.Accent,.2) else Theme.PanelRaised
    end
    local inlineFooter=self.compact and size.X>=640
    local previewWidth=if inlineFooter then availableWidth-128 else availableWidth
    local function measured() if not self.destroyed and self.ui.Parent then self:layout() end end
    local previewHeight=math.clamp(TextBounds.measure(self.content.Preview,previewWidth-24,measured).Y+20,44,76)
    local columnsY=if self.stages.Visible then 54 else 12
    if self.compact and not inlineFooter then previewHeight=math.min(previewHeight,math.max(44,contentHeight-56-8-columnsY-12-98)) end
    local sendY=contentHeight-56;local previewY=sendY-previewHeight-8
    if inlineFooter then previewY=contentHeight-previewHeight-12;sendY=previewY+(previewHeight-44)/2 end
    self.content.Send.Position=UDim2.new(1,-128,0,sendY);self.content.Send.Size=UDim2.fromOffset(116,44)
    self.content.Preview.Position=UDim2.fromOffset(12,previewY);self.content.Preview.Size=UDim2.fromOffset(previewWidth,previewHeight)
    local columnsHeight=math.max(44,previewY-columnsY-12)
    self.columns.Position=UDim2.fromOffset(12,columnsY);self.columns.Size=UDim2.new(1,-24,0,columnsHeight);self.columns.CanvasSize=UDim2.fromOffset(0,0);self.columns.CanvasPosition=Vector2.zero
    self.content.CanvasSize=UDim2.fromOffset(0,0);self.content.CanvasPosition=Vector2.zero
    local visible={}
    for _,name in {"Categories","Phrases","Players"} do
        local column=self.columns[name];column.Visible=self:canShow(name) and (not self.compact or self.page==name)
        column.Title.Visible=not self.compact
        if column.Visible then table.insert(visible,column)end
    end
    local columnWidth=if self.compact then availableWidth else (availableWidth-math.max(0,#visible-1)*12)/math.max(1,#visible)
    for index,column in visible do column.Position=UDim2.fromOffset((index-1)*(columnWidth+12),0);column.Size=UDim2.fromOffset(columnWidth,columnsHeight)end
    local categoryStart=if self.compact then 0 else 32
    for index,category in Catalog.CategoryOrder do local button=self.columns.Categories[category];button.Position=UDim2.fromOffset(0,categoryStart+(index-1)*50);button.Size=UDim2.new(1,-6,0,44)end
    self.columns.Categories.CanvasSize=UDim2.fromOffset(0,categoryStart+#Catalog.CategoryOrder*50-6)
    local players=self.columns.Players
    players.Sort.Text=if self.compact then "Territory" else P.text("chat.sort_by_territory")
    if self.compact then
        players.Sort.Position=UDim2.fromOffset(0,0);players.Sort.Size=UDim2.fromOffset(110,44)
        players.Search.Position=UDim2.fromOffset(118,0);players.Search.Size=UDim2.new(1,-124,0,44)
    else
        players.Sort.Position=UDim2.fromOffset(0,32);players.Sort.Size=UDim2.new(1,-6,0,44)
        players.Search.Position=UDim2.fromOffset(0,82);players.Search.Size=UDim2.new(1,-6,0,44)
    end
    for _,entry in {{node=self.columns.Phrases,rows=self.phraseRows,top=if self.compact then 0 else 32},{node=players,rows=self.playerRows,top=if self.compact then 54 else 134}} do
        local node=entry.node;local rowWidth=math.max(1,node.Size.X.Offset-30);local y=0
        for _,row in entry.rows do
            local rowHeight=math.max(44,TextBounds.measure(row,rowWidth,measured).Y+20)
            row.Position=UDim2.fromOffset(0,y);row.Size=UDim2.new(1,-6,0,rowHeight);y+=rowHeight+6
        end
        node.Scroll.Position=UDim2.fromOffset(0,entry.top);node.Scroll.Size=UDim2.new(1,0,1,-entry.top)
        node.Scroll.CanvasSize=UDim2.fromOffset(0,math.max(0,y-6))
    end
    self:layoutNavigation()
    self.modal:SetAttribute("HorizontalOverflow",false);self.modal:SetAttribute("Desktop",not self.compact);self.modal:SetAttribute("ActiveStage",self.page)
end
return Q
