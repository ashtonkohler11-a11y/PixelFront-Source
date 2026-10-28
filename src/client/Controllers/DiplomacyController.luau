--!strict
-- Original player-panel/input design with retained OpenFront diplomacy commands.
local Shared=game:GetService("ReplicatedStorage").Shared
local Rules=require(Shared.OpenFrontDiplomacy)
local Config=require(Shared.Config)
local Theme=table.clone(require(Shared.Theme))
local HudTheme=require(script.Parent.BattleHudTheme)
Theme.Panel=HudTheme.Panel;Theme.PanelRaised=HudTheme.Raised;Theme.Border=HudTheme.Border
Theme.Accent=HudTheme.Cobalt;Theme.Gold=HudTheme.Gold;Theme.Danger=HudTheme.Danger
Theme.Text=HudTheme.Text;Theme.MutedText=HudTheme.Muted;Theme.Positive=HudTheme.Positive
local P=require(script.Parent.DiplomacyPresentation)
local Icons=require(script.Parent.ReferenceIcons)
local Emoji=require(script.Parent.DiplomacyEmoji)
local ReserveHint=require(script.Parent.TroopReserveHint)
local Chat=require(script.Parent.QuickChatPresentation)
local ClientNames=require(Shared.OpenFrontClientNames)
local HudControls=require(script.Parent.BattleHudControls)
-- PF012: cursor card, top inspector strip and bottom-left notification stack.
local Model=require(script.Parent.HudInspectorModel)
local HoverCard=require(script.Parent.CountryHoverCard)
local InspectorStrip=require(script.Parent.HudInspectorStrip)
local NoticeStack=require(script.Parent.HudNotificationStack)
-- PF022: the authored player card (actions + give sheet) and its truthful model.
local ActionModel=require(script.Parent.PlayerActionsModel)
local ActionCard=require(script.Parent.PlayerActionsCard)
-- PF029: the authored emoji panel (tabs, 44 px tiles, no scrolling) and its quick chat sibling.
local Social: any=nil -- soft: harnesses without it keep the PF012 grid
do local ok,result=pcall(function() return require(script.Parent.SocialPanels) end);if ok then Social=result end end
local Accent=require(Shared.PixelFrontAccent)
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local ContextActionService=game:GetService("ContextActionService")
local HttpService=game:GetService("HttpService")
local D={};D.__index=D
local function enabled(button: TextButton,value: boolean,fade: boolean?)
    button.Active=value;button.Selectable=value;button.AutoButtonColor=false;button.TextTransparency=if fade~=false and not value then .5 else 0;button:SetAttribute("Enabled",value)
end
local function paintAction(button: TextButton,variant: string,hovered: boolean)
    local color=if variant=="red" then Theme.Danger elseif variant=="yellow" then Theme.Gold elseif variant=="green" then Theme.Positive elseif variant=="indigo" then Theme.Accent else Theme.Text
    button.BackgroundColor3=if hovered then Theme.PanelRaised:Lerp(color,.12) else Theme.PanelRaised
    button.BackgroundTransparency=0;button.TextColor3=color;button.TextTransparency=if button.Active then 0 else .5;button.AutoButtonColor=false;button:SetAttribute("SourceVariant",variant)
    local border=button:FindFirstChild("Border");if border and border:IsA("UIStroke") then border.Color=if hovered then Theme.Accent else Theme.Border;border.Transparency=.15 end
end
local function available(button: GuiObject?): boolean
    return HudControls.available(button)
end
local function contains(container: Instance,button: GuiObject?): boolean
    return button~=nil and button:IsDescendantOf(container)
end
local function richColor(color: Color3,text: string): string
    return '<font color="#'..color:ToHex()..'">'..text..'</font>'
end
local function listen(self: any,signal: RBXScriptSignal,callback: any)
    table.insert(self.connections,signal:Connect(function(...) if not self.destroyed then callback(...) end end))
end
local preferences: any=nil
local function ownerName(state: any,owner: number): string return ClientNames.resolve(state,owner,preferences) end
-- PF019 W7 settings read from the injected preferences (nil = the setting's default).
local function setting(name: string): any return if preferences and type(preferences.get)=="function" then preferences:get(name) else nil end
-- PF019 W7 S6 Quick chat and emotes from others: "everyone" | "allies" (allied or same team) |
-- "off". Your own always show. Same rule as DiplomacyStatusRenderer.fromShown (name emotes).
function D.fromShown(state: any,sender: any,mode: any): boolean
    if sender==1 or (mode~="allies" and mode~="off") then return true end
    return mode=="allies" and type(sender)=="number" and state.players[sender]~=nil and P.friendly(state,1,sender)
end
-- PF019 W7 S4 Alliance requests: "everyone" | "friends" (Roblox friends) | "none". A request
-- the player doesn't take is declined for them: no card and no sound. true = show, false =
-- decline, nil = still asking Roblox whether the sender is a friend (the card waits).
function D:allianceRequestAllowed(owner: number): boolean?
    local mode=setting("allianceRequests")
    if mode~="friends" and mode~="none" then return true end
    if mode=="none" or not self.state then return false end
    local player=self.state.players[owner];local userId=player and player.playerType=="Human" and tonumber(player.clientID)
    if not userId then return false end
    self.friendCache=self.friendCache or {}
    local known=self.friendCache[userId]
    if known==true or known==false then return known end
    if known==nil then
        self.friendCache[userId]="pending"
        task.spawn(function()
            local ok,friend=pcall(function() return game:GetService("Players").LocalPlayer:IsFriendsWith(userId) end)
            self.friendCache[userId]=ok and friend==true
            if not self.destroyed then self:refreshEvents() end
        end)
    end
    return nil
end
function D.new(ui: Frame,callbacks: any)
    preferences=callbacks.preferences;Chat.preferences=preferences
    local self=setmetatable({ui=ui,callbacks=callbacks,panel=ui:WaitForChild("DiplomacyPanel"),hover=ui:WaitForChild("DiplomacyHover"),feed=ui:WaitForChild("DiplomacyFeed"),emojiMenu=ui:WaitForChild("DiplomacyEmojiMenu"),connections={},rows={},requestRows={},renewChecked={},dismissed={},state=nil,destroyed=false},D)
    -- PF012 retires the old top hover and right-side queue; both stay authored.
    self.hover.Visible=false;self.feed.Visible=false
    self:initHud()
    self.reserveHint=ReserveHint.new(ui,callbacks.formatTroops)
    self.body=self.panel.Body;self.content=self.body.Content;self.sendUI=self.body.Send
    -- PF022: when the place carries the authored card it replaces the PF012 body (kept as the fallback).
    -- sendUI.Visible stays the "giving" flag either way; only drawing and geometry move to the card.
    local cardNodes=ActionCard.find(self.panel)
    if cardNodes then
        self.actionCard=ActionCard.new(cardNodes,{
            action=function(id: string) self:cardAction(id) end,close=function() self:hide() end,back=function() self:closeSend() end,
            preset=function(pct: number) self.sendPercent=pct;self.sendAmount=nil;self.manualSendAmount=nil;self:refreshSend() end,
            confirm=function() self:confirmSend() end,slider=function(input: InputObject) self:beginSlider(input) end})
        self.body.Visible=false
    end
    -- PF029: when the place carries the authored emoji panel it replaces the PF012 grid (kept as the fallback).
    local emojiHolder=if Social then Social.Emoji.find(self.emojiMenu) else nil
    if emojiHolder then
        self.emojiPanel=Social.Emoji.new(emojiHolder,{
            send=function(index: number) if self.state and self.emojiTarget then self:command("Emoji",self.emojiTarget,{emoji=index});self:closeEmoji();self:hide() end end,
            close=function() self:closeEmoji() end})
        self.emojiMenu.Body.Visible=false
    end
    listen(self,self.panel.Backdrop.Activated,function() self:hide() end);listen(self,self.body.Close.Activated,function() self:hide() end)
    listen(self,self.sendUI.Close.Activated,function() self:closeSend() end);listen(self,self.sendUI.Cancel.Activated,function() self:closeSend() end)
    listen(self,self.sendUI.Confirm.Activated,function() self:confirmSend() end)
    listen(self,self.emojiMenu.Backdrop.Activated,function() self:closeEmoji() end);listen(self,self.emojiMenu.Body.Close.Activated,function() self:closeEmoji() end)
    for i=0,59 do local button=self.emojiMenu.Body.Scroll["Emoji"..i]
        listen(self,button.Activated,function() if self.state and self.emojiTarget then self:command("Emoji",self.emojiTarget,{emoji=i});self:closeEmoji();self:hide() end end)
        listen(self,button.MouseEnter,function() button.BackgroundColor3=Theme.PanelRaised:Lerp(Theme.Accent,.12) end)
        listen(self,button.MouseLeave,function() button.BackgroundColor3=Theme.PanelRaised end)
    end
    for _,pct in P.PRESETS do listen(self,self.sendUI["Percent"..pct].Activated,function() self.sendPercent=pct;self.sendAmount=nil;self:refreshSend() end) end
    for _,pct in P.PRESETS do local b=self.sendUI["Percent"..pct];listen(self,b.MouseEnter,function() if b.Active and self.sendPercent~=pct then b.BackgroundColor3=Theme.PanelRaised:Lerp(Theme.Accent,.12);b.TextColor3=Theme.Text end end);listen(self,b.MouseLeave,function() self:refreshSend() end) end
    listen(self,self.sendUI.Track.Input.InputBegan,function(input: InputObject)
        self:beginSlider(input)
    end)
    listen(self,UIS.InputChanged,function(input: InputObject)
        if input.UserInputType==Enum.UserInputType.MouseMovement then self.pointer=Vector2.new(input.Position.X,input.Position.Y);self:placeCard() end
        self:moveSlider(input)
    end)
    listen(self,UIS.InputEnded,function(input: InputObject) self:endSlider(input) end)
    listen(self,UIS.WindowFocusReleased,function() self.sliderInput=nil end)
    local actions=self.content.Actions
    self.actionHovered={}
    for _,name in {"Chat","Emoji","DonateTroops","DonateGold","Target","Trade","BreakAlliance","AllianceRequest","StopTradingAll","StartTradingAll"} do
        local b=actions[name];listen(self,b.MouseEnter,function() self.actionHovered[name]=true;paintAction(b,b:GetAttribute("SourceVariant") or "normal",true) end)
        listen(self,b.MouseLeave,function() self.actionHovered[name]=nil;paintAction(b,b:GetAttribute("SourceVariant") or "normal",false) end)
    end
    for _,b in {self.body.Close,self.sendUI.Close,self.emojiMenu.Body.Close} do
        b.AutoButtonColor=false;listen(self,b.MouseEnter,function() b.BackgroundColor3=Theme.PanelRaised:Lerp(Theme.Danger,.2) end);listen(self,b.MouseLeave,function() b.BackgroundColor3=Theme.PanelRaised end)
    end
    for _,b in {self.sendUI.Cancel} do b.AutoButtonColor=false;listen(self,b.MouseEnter,function() b.BackgroundColor3=Theme.PanelRaised:Lerp(Theme.Text,.1) end);listen(self,b.MouseLeave,function() b.BackgroundColor3=Theme.PanelRaised end) end
    listen(self,self.sendUI.Confirm.MouseEnter,function() if self.sendUI.Confirm.Active then self.sendUI.Confirm.BackgroundColor3=Theme.Accent:Lerp(Theme.Text,.12) end end)
    listen(self,self.sendUI.Confirm.MouseLeave,function() self.sendUI.Confirm.BackgroundColor3=Theme.Accent end)
    for name,asset in {DonateTroops="DonateTroops",DonateGold="DonateGold",Target="Target",Emoji="Emoji"} do Icons.bind(actions[name].Icon,"Diplomacy"..asset) end
    Icons.bind(actions.Chat.Icon,"QuickChat")
    Icons.bind(actions.BreakAlliance.Icon,"DiplomacyBreak");Icons.bind(actions.AllianceRequest.Icon,"DiplomacyAlliance")
    for _,entry in {{self.content.Resources.Gold.Icon,"💰"},{self.content.Resources.Troops.Icon,"🛡️"},{self.content.Betrayals.Icon,"⚠️"},{self.content.Trading.Icon,"⚓"}} do Icons.bind(entry[1],"DiplomacyEmoji"..((table.find(Emoji,entry[2]) or 1)-1)) end
    listen(self,actions.DonateTroops.Activated,function() if self:allowed("canDonateTroops") then self:openSend(self.panelOwner,"troops",self.panelTile) end end)
    listen(self,actions.DonateGold.Activated,function() if self:allowed("canDonateGold") then self:openSend(self.panelOwner,"gold",self.panelTile) end end)
    listen(self,actions.Target.Activated,function() if self:allowed("canTarget") then self:command("Target",self.panelOwner);self:hide() end end)
    listen(self,actions.Emoji.Activated,function() if self.panelOwner then self:openEmoji(self.panelOwner) end end)
    listen(self,actions.Chat.Activated,function() if self.panelOwner and self.callbacks.openChat then self.callbacks.openChat(self.panelOwner);self:hide() end end)
    listen(self,actions.AllianceRequest.Activated,function() if self:allowed("canSendAllianceRequest") then self:request(self.panelOwner);self:hide() end end)
    listen(self,actions.BreakAlliance.Activated,function() if self:allowed("canBreakAlliance") then self:command("BreakAlliance",self.panelOwner);self:hide() end end)
    listen(self,actions.Trade.Activated,function() if self.state and self.panelOwner and self.panelOwner~=1 then local query=Rules.interaction(self.state,1,self.panelOwner);self:command("Embargo",self.panelOwner,{action=if query.canEmbargo then "start" else "stop"});self:hide() end end)
    listen(self,actions.StopTradingAll.Activated,function() if self.state and Rules.canEmbargoAll(self.state,1) then self:command("EmbargoAll",nil,{action="start"}) end end)
    listen(self,actions.StartTradingAll.Activated,function() if self.state and Rules.canEmbargoAll(self.state,1) then self:command("EmbargoAll",nil,{action="stop"}) end end)
    listen(self,self.content.Trajectory.Activated,function() if self.callbacks.flipTrajectory then self.callbacks.flipTrajectory();self:refreshPanel() end end)
    listen(self,ui:GetPropertyChangedSignal("AbsoluteSize"),function() self:layout() end)
    listen(self,ui.Controls.Placement:GetPropertyChangedSignal("Visible"),function() self:refreshHud() end)
    -- The authored notice region resizes with the device; re-check what fits.
    if self.stack then listen(self,self.stack.container:GetPropertyChangedSignal("AbsoluteSize"),function() self:refreshHud() end) end
    if self.card then listen(self,self.card.node:GetPropertyChangedSignal("AbsoluteSize"),function() self:placeCard() end) end
    -- Touch has no hover: the tapped (radial) country drives the inspector.
    listen(self,ui.Radial:GetPropertyChangedSignal("Visible"),function() self:refreshInspection() end)
    listen(self,ui.Radial:GetAttributeChangedSignal("TargetId"),function() self:refreshInspection() end)
    listen(self,ui.Destroying,function() self:destroy() end)
    self.gamepad=string.sub(UIS:GetLastInputType().Name,1,7)=="Gamepad"
    listen(self,UIS.LastInputTypeChanged,function(kind: Enum.UserInputType)
        self.gamepad=string.sub(kind.Name,1,7)=="Gamepad"
        if self.gamepad then self:focusActive() end
        self:refreshInspection()
    end)
    -- The slider alone owns left/right while selected; the strategy map keeps
    -- the normal shoulders/trigger bindings everywhere else.
    if game:GetService("RunService"):IsClient() then
        self.sliderAction="OpenFrontDonationSlider-"..HttpService:GenerateGUID(false)
        ContextActionService:BindActionAtPriority(self.sliderAction,function(_,state,input)
            if self.destroyed or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() or not self.sendUI.Visible or self.emojiMenu.Visible or GuiService.SelectedObject~=self:sliderNode() then return Enum.ContextActionResult.Pass end
            if state==Enum.UserInputState.Begin then self:adjustSend(if input.KeyCode==Enum.KeyCode.DPadLeft then -1 else 1) end
            return Enum.ContextActionResult.Sink
        end,false,Enum.ContextActionPriority.High.Value+3,Enum.KeyCode.DPadLeft,Enum.KeyCode.DPadRight)
        -- PF022: LB/RB on the open card: previous/next action group, or the previous/next preset while giving.
        if self.actionCard then
            self.cardShoulders="OpenFrontPlayerCard-"..HttpService:GenerateGUID(false)
            ContextActionService:BindActionAtPriority(self.cardShoulders,function(_,state,input)
                if self.destroyed or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() or not self.panel.Visible or self.emojiMenu.Visible or not self.actionCard:visible() then return Enum.ContextActionResult.Pass end
                if state==Enum.UserInputState.Begin then self:cardShoulder(if input.KeyCode==Enum.KeyCode.ButtonL1 then -1 else 1) end
                return Enum.ContextActionResult.Sink
            end,false,Enum.ContextActionPriority.High.Value+3,Enum.KeyCode.ButtonL1,Enum.KeyCode.ButtonR1)
        end
    end
    self:layout();return self
end
function D:setPreferences(value: any)
    preferences=value;self.callbacks.preferences=value;Chat.preferences=value
    self:bindAccent()
    -- PF019 W7 S5: lowering Alerts also clears shown notices it no longer allows.
    if self.alertsOff then self.alertsOff();self.alertsOff=nil end
    if value and type(value.subscribe)=="function" then self.alertsOff=value:subscribe(function(key)
        if key=="settings.alerts" and not self.destroyed and self.stack and self.stack:prune(setting("alerts")) then self:refreshHud() end
    end) end
    if self.state then self:refreshPanel();self:refreshInspection(true) end
end
function D:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.reserveHint then self.reserveHint:destroy() end
    self.ui:SetAttribute("DiplomacyRequestCards",0);self.ui:SetAttribute("DiplomacyNotices",0)
    if self.sliderAction then ContextActionService:UnbindAction(self.sliderAction) end
    if self.cardShoulders then ContextActionService:UnbindAction(self.cardShoulders) end
    if self.actionCard then self.actionCard:destroy() end
    if self.emojiPanel then self.emojiPanel:destroy() end
    local selected=GuiService.SelectedObject
    if contains(self.panel,selected) or contains(self.emojiMenu,selected) or contains(self.feed,selected) or (self.stack and contains(self.stack.container,selected)) then GuiService.SelectedObject=nil end
    self.sliderInput=nil
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    for _,r in self.rows do r:Destroy() end
    if self.stack then self.stack:destroy() end;if self.card then self.card:hide() end;if self.strip then self.strip:hide() end
    if self.strip and self.strip.destroy then self.strip:destroy() end
    if self.accentRegistry then self.accentRegistry:destroy();self.accentRegistry=nil end
    if self.alertsOff then self.alertsOff();self.alertsOff=nil end
    self.rows={};self.requestRows={};self.state=nil
end
-- PF012 surfaces are authored by tools/atlas/author-pf012-hover.luau. Missing
-- nodes degrade to no card/strip/stack instead of failing the match HUD.
function D:initHud()
    local ui=self.ui;local templates=ui:FindFirstChild("Templates")
    -- PF018: Builder A's inspector region sits inside the authored top row (Game.PFTopRow).
    local inspectorRegion,noticeRegion=ui:FindFirstChild("PFInspectorRegion",true),ui:FindFirstChild("PFNoticeRegion")
    local hover=ui:FindFirstChild("PFCountryHover")
    local inspector=inspectorRegion and inspectorRegion:FindFirstChild("PFInspector")
    local stack=noticeRegion and noticeRegion:FindFirstChild("PFNotifications")
    if not (hover and inspector and stack and templates and templates:FindFirstChild("PFNoticeRequest") and templates:FindFirstChild("PFNoticeInfo")) then
        warn("PF013 hover/notice nodes are missing; run tools/atlas/author-pf012-hover.luau");return
    end
    self.card=HoverCard.new(hover);self.strip=InspectorStrip.new(inspector)
    self.stack=NoticeStack.new(stack,templates,{
        respond=function(row,accept) self:respond(row,accept) end,
        focusOwner=function(owner) if self.callbacks.focusOwner then self.callbacks.focusOwner(owner) end end,
        inputAllowed=function() return self:feedInputAllowed() end,
        gamepad=function() return self.gamepad==true end,
        accent=function() return self:accentColor("accent") end,
        changed=function() if not self.destroyed then self:refreshHud() end end, -- notices v2: a toast's own life ended

        -- PF018: notices slide in/out unless the player turned motion down (same rule as the HUD).
        reducedMotion=function()
            if not preferences or type(preferences.snapshot)~="function" then return false end
            local values=preferences:snapshot()
            return values["settings.reducedMotion"]=="true" or values["settings.staticBackground"]=="true" or values["settings.motionEnabled"]=="false"
        end,
    })
    self:bindAccent()
end
function D:bindAccent()
    if self.accentRegistry then self.accentRegistry:destroy();self.accentRegistry=nil end
    if not self.card or not preferences or type(preferences.interfaceAccent)~="function" then return end
    local registry=Accent.new(preferences);self.accentRegistry=registry
    for _,root in {self.card.node,self.strip.node,self.stack.container} do registry:bindRoot(root) end
    if self.actionCard then registry:bindRoot(self.actionCard.card) end
    registry:subscribe(function() self:refreshInspection(true) end)
end
function D:accentColor(role: string): Color3?
    return if self.accentRegistry then self.accentRegistry:color(role) else nil
end
-- PF013: panel, send and emoji geometry is authored in the place (author-pf012-hover).
-- Only focus graphs and content refreshes remain here.
local EMOJI_COLUMNS=5
function D:layout()
    self:layoutSend()
    self:refreshHud()
    local body=self.emojiMenu.Body;local columns=EMOJI_COLUMNS;self.emojiColumns=columns
    for index=0,59 do local button=body.Scroll["Emoji"..index]
        button.NextSelectionUp=if index<columns then body.Close else body.Scroll["Emoji"..(index-columns)]
        button.NextSelectionDown=if index+columns<60 then body.Scroll["Emoji"..(index+columns)] else button
        button.NextSelectionLeft=if index%columns>0 then body.Scroll["Emoji"..(index-1)] else button
        button.NextSelectionRight=if index%columns<columns-1 and index<59 then body.Scroll["Emoji"..(index+1)] else button
    end
    body.Close.NextSelectionDown=body.Scroll.Emoji0
    if self.state then self:refreshPanel() end
end
function D:layoutSend()
    local send=self.sendUI
    local buttons={send.Close}
    for _,pct in P.PRESETS do table.insert(buttons,send["Percent"..pct]) end
    send.Track.Input:SetAttribute("ActionDescription","Use left or right to adjust the donation by 5 percent")
    table.insert(buttons,send.Track.Input);table.insert(buttons,send.Cancel);table.insert(buttons,send.Confirm)
    self.sendButtons=buttons
    self:linkSelection(buttons)
    send.Track.Input.NextSelectionLeft=send.Track.Input;send.Track.Input.NextSelectionRight=send.Track.Input
end
function D:feedInputAllowed(): boolean
    return not self.destroyed and self.stack~=nil and HudControls.visible(self.stack.container) and not GuiService.MenuIsOpen and not UIS:GetFocusedTextBox()
        and not (self.panel and self.panel.Visible) and not (self.emojiMenu and self.emojiMenu.Visible)
        and (not self.callbacks.feedInputAllowed or self.callbacks.feedInputAllowed())
end
-- Requests and notices stack bottom-up in the authored region. The old queue
-- attributes stay pinned at zero so nothing switches to the retired rail.
function D:refreshHud()
    if self.destroyed then return end
    self.ui:SetAttribute("DiplomacyRequestCards",0);self.ui:SetAttribute("DiplomacyNotices",0)
    if not self.stack then return end
    local state=self.state
    self.stack:setEnabled(state~=nil and state.phase~="Choosing" and (state.counts[1] or 0)>0)
    self.stack:refresh()
    local requests,notices=self.stack:counts()
    self.ui:SetAttribute("PFNoticeStackHeight",math.floor(self.stack:usedHeight()+.5));self.ui:SetAttribute("PFNoticeRequests",requests);self.ui:SetAttribute("PFNoticeCount",notices)
    self:refreshInspection()
end
function D:linkSelection(buttons: {GuiObject})
    local active={}
    for _,button in buttons do
        HudControls.clearLinks(button)
        if available(button) then table.insert(active,button) end
    end
    for index,button in active do
        local previous=active[math.max(1,index-1)];local following=active[math.min(#active,index+1)]
        button.SelectionOrder=index;button.NextSelectionUp=previous;button.NextSelectionDown=following
        button.NextSelectionLeft=previous;button.NextSelectionRight=following
    end
end
function D:focusActive()
    if not self.gamepad or self.destroyed or not self.ui.Visible or GuiService.MenuIsOpen then return end
    local scope,first
    if self.emojiMenu.Visible then scope=self.emojiMenu;first=if self.emojiPanel then self.emojiPanel:first() else self.emojiMenu.Body.Scroll.Emoji0
    elseif self.panel.Visible and self.actionCard then scope=self.actionCard.card;first=self.actionCard:link() -- PF022
    elseif self.panel.Visible and self.sendUI.Visible then scope=self.sendUI;first=self.sendUI.Track.Input
    elseif self.panel.Visible then scope=self.panel;first=self.body.Close
    else return end
    task.defer(function()
        if self.destroyed or not self.gamepad or not scope.Visible then return end
        local selected=GuiService.SelectedObject
        if available(selected) and contains(scope,selected) then return end
        if available(first) then GuiService.SelectedObject=first
        elseif scope==self.sendUI and available(self.sendUI.Close) then GuiService.SelectedObject=self.sendUI.Close end
    end)
end
function D:restoreSelection(scope: GuiObject,previous: GuiObject?)
    if not contains(scope,GuiService.SelectedObject) then return end
    GuiService.SelectedObject=if available(previous) then previous else nil
end
function D:command(kind: string,target: number?,fields: any?)
    local payload=fields or {};if target~=nil then payload.targetOwner=target end;self.callbacks.send(kind,payload)
end
function D:playSound(name: string)
    if self.callbacks.playSound then self.callbacks.playSound(name) end
end
function D:requestAction(kind: string,owner: number,accept: boolean)
    if kind=="request" then
        self:playSound(if accept then "alliance-accepted" else "alliance-declined")
        self:command(if accept then "AllianceRequest" else "AllianceReject",owner)
    elseif accept then self:command("AllianceExtend",owner) end
end
function D:allowed(field: string): boolean
    return self.state~=nil and self.panelOwner~=nil and Rules.interaction(self.state,1,self.panelOwner)[field]==true
end
function D:request(owner: number)
    if not self.state or not Rules.interaction(self.state,1,owner).canSendAllianceRequest then return end
    if not P.requesting(self.state,owner,1) then self:addNotice(P.text("events_display.alliance_request_sent",{name=ownerName(self.state,owner)}),owner,self.state.ticks,"ALLIANCE_REQUEST") end
    self:command("AllianceRequest",owner)
end
function D:show(tile: number)
    if not self.state or not self.state.owners[tile] or self.state.owners[tile]<=0 then return end
    if not self.panel.Visible then self.panelReturn=GuiService.SelectedObject end
    self.panelTile=tile;self.panelOwner=self.state.owners[tile];self.panel.Visible=true;self.sendUI.Visible=false;self.hover.Visible=false
    if self.card then self.cardSignature=nil;self.card:hide() end
    self.content.Visible=true;self.body.Close.Visible=true
    if self.actionCard then self.actionCard:showActions() end
    self.ui.Radial.Visible=false;self:refreshPanel();self:focusActive()
end
function D:hide()
    if self.actionCard then self.actionCard:hide() end
    self.panel.Visible=false;self.sendUI.Visible=false;self.sendMode=nil;self.sendTarget=nil;self.sliderInput=nil
    self.content.Visible=true;self.body.Close.Visible=true
    self:restoreSelection(self.panel,self.panelReturn);self.panelReturn=nil;self.sendReturn=nil
end
function D:openSend(owner: number,mode: string,tile: number?)
    if not self.state then return end
    local query=Rules.interaction(self.state,1,owner);if not query[if mode=="troops" then "canDonateTroops" else "canDonateGold"] then return end
    if not self.panel.Visible then self.panelReturn=GuiService.SelectedObject end
    self.sendReturn=GuiService.SelectedObject
    self.panelTile=tile;self.panelOwner=owner;self.panel.Visible=true;self.sendMode=mode;self.sendTarget=owner;self.sendPercent=math.floor((self.callbacks.ratio and self.callbacks.ratio() or 1)*100+.5);self.sendAmount=nil;self.sendBinding=nil;self.manualSendAmount=nil;self.sendUI.Visible=true
    self.content.Visible=false;self.body.Close.Visible=false
    if self.actionCard then self.actionCard:showGive() end
    self:refreshPanel();self:focusActive()
end
function D:closeSend()
    self.sendUI.Visible=false;self.sendMode=nil;self.sendTarget=nil;self.sliderInput=nil
    self.content.Visible=true;self.body.Close.Visible=true
    if self.actionCard and self.panel.Visible then self.actionCard:showActions() end
    self:restoreSelection(self.sendUI,self.sendReturn);self.sendReturn=nil
    self:refreshPanel();self:focusActive()
end
function D:beginSlider(input: any): boolean
    if self.sliderInput or not self.sendUI.Visible or not self.panel.Visible or self.emojiMenu.Visible then return false end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return false end
    self.sliderInput=input;self:sliderAt(Vector2.new(input.Position.X,input.Position.Y));return true
end
function D:moveSlider(input: any): boolean
    local active=self.sliderInput
    if not active or (input~=active and not (active.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)) then return false end
    self:sliderAt(Vector2.new(input.Position.X,input.Position.Y));return true
end
function D:endSlider(input: any)
    if input==self.sliderInput or (self.sliderInput and self.sliderInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then self.sliderInput=nil end
end
function D:adjustSend(direction: number): boolean
    if not self.panel.Visible or not self.sendUI.Visible or self.emojiMenu.Visible or not self.state or not self.sendTarget then return false end
    local total=if self.sendMode=="troops" then self.state.troops[1] else self.state.gold[1]
    if total<=0 then return true end
    -- Keep the requested percentage so small balances can accumulate a 5% step
    -- even when the resulting whole-unit amount has not increased yet. A cap
    -- still lets Left immediately reduce the actual available donation.
    local _,_,cap=P.donation(self.state,self.sendTarget,self.sendMode,100)
    local current=self.sendPercent or math.floor((self.sendAmount or 0)/total*100+.5)
    if cap then current=math.min(current,math.ceil(math.min(total,cap)/total*100)) end
    self.sendPercent=math.clamp(current+direction*5,0,100);self.sendAmount=nil;self.manualSendAmount=nil;self:refreshSend();return true
end
function D:sliderAt(position: Vector2)
    if not self.sendUI.Visible or not self.state or not self.sendTarget then return end
    local track=if self.actionCard then self.actionCard:sliderTrack() else self.sendUI.Track
    local ratio=math.clamp((position.X-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
    local total=if self.sendMode=="troops" then self.state.troops[1] else self.state.gold[1]
    local raw=math.floor(total*ratio+.5);self.sendPercent=if total>0 then math.floor(raw/total*100+.5) else 0;self.manualSendAmount=raw;self:refreshSend()
end
function D:refreshSend()
    if not self.sendTarget or not self.sendMode or not self.state then return end
    if (self.state.counts[1] or 0)<=0 or (self.state.counts[self.sendTarget] or 0)<=0 then self:closeSend();return end
    local amount,total,cap=P.donation(self.state,self.sendTarget,self.sendMode,self.sendPercent or 100)
    local binding=self.sendBinding
    local bindingChanged=not binding or binding.total~=total or binding.mode~=self.sendMode or binding.target~=self.sendTarget
    if self.manualSendAmount~=nil then amount=math.clamp(self.manualSendAmount,0,if cap then math.min(total,cap) else total);self.manualSendAmount=nil
    elseif not bindingChanged and self.sendAmount~=nil then amount=self.sendAmount end
    self.sendBinding={total=total,mode=self.sendMode,target=self.sendTarget}
    self.sendAmount=amount;local format=if self.sendMode=="troops" then self.callbacks.formatTroops else self.callbacks.formatNumber
    local percent=if total>0 then math.floor(amount/total*100+.5) else 0
    if self.actionCard then -- PF022: the card draws the give sheet (what the server will really move)
        local give=ActionModel.give(self.state,self.sendTarget,self.sendMode,amount,{formatNumber=self.callbacks.formatNumber,formatTroops=self.callbacks.formatTroops,preferences=preferences})
        self.actionCard:renderGive(give,percent,if table.find(P.PRESETS,self.sendPercent or -1) then self.sendPercent else nil)
        self.sendUI:SetAttribute("Amount",amount);self.sendUI:SetAttribute("Percent",percent)
        if contains(self.actionCard.card,GuiService.SelectedObject) then
            self.actionCard:link()
            if not available(GuiService.SelectedObject) then self:focusActive() end
        end
        return
    end
    self.sendUI.Title.Text=P.text(if self.sendMode=="troops" then "send_troops_modal.title_with_name" else "send_gold_modal.title_with_name",{name=ownerName(self.state,self.sendTarget)})
    self.sendUI.Available.Text=P.text("common.available").."  "..format(total)
    self.sendUI.Amount.Text=tostring(percent).."% • "..format(amount)
    local keepColor=if self.sendMode=="troops" and total-amount<math.floor(total*.3) then Theme.Gold else Theme.Positive
    self.sendUI.Summary.RichText=true;self.sendUI.Summary.TextColor3=Theme.Text
    self.sendUI.Summary.Text=P.text("common.send").." "..richColor(Theme.Accent,format(amount)).." · "..P.text("common.summary_keep").." "..richColor(keepColor,format(math.max(0,total-amount)))
    local color=if self.sendMode=="troops" then Theme.Accent else Theme.Gold
    self.sendUI.Track.Fill.BackgroundColor3=color;self.sendUI.Track.Thumb.BackgroundColor3=color
    self.sendUI.Track.Fill.Size=UDim2.fromScale(percent/100,1);self.sendUI.Track.Thumb.Position=UDim2.fromScale(percent/100,.5)
    local capPercent=if cap and total>0 then math.floor(math.min(cap,total)/total*100+.5) else 0
    self.sendUI.Track.Cap.Visible=cap~=nil;self.sendUI.Track.CapLabel.Visible=cap~=nil
    self.sendUI.Track.Cap.Position=UDim2.fromScale(capPercent/100,.5);self.sendUI.Track.CapLabel.Position=UDim2.fromScale(capPercent/100,1)
    for _,pct in P.PRESETS do local b=self.sendUI["Percent"..pct];local active=pct==self.sendPercent;enabled(b,total>0,false);b.BackgroundColor3=if active and total>0 then Theme.Accent else Theme.PanelRaised;b.BackgroundTransparency=if total>0 then 0 else .3;b.TextColor3=if total<=0 then Theme.MutedText else Theme.Text;local border=b:FindFirstChild("Border");if border and border:IsA("UIStroke") then border.Color=if active and total>0 then Theme.Accent else Theme.Border;border.Transparency=0 end end
    enabled(self.sendUI.Confirm,total>0 and amount>0);self.sendUI.Confirm.BackgroundTransparency=if total>0 and amount>0 then 0 else .5;self.sendUI:SetAttribute("Amount",amount);self.sendUI:SetAttribute("Percent",percent)
    enabled(self.sendUI.Track.Input,total>0,false)
    self.sendUI.Confirm.BackgroundColor3=Theme.Accent;self.sendUI.Confirm.TextColor3=Theme.Text
    if self.sendButtons then self:linkSelection(self.sendButtons) end
    self.sendUI.Track.Input.NextSelectionLeft=self.sendUI.Track.Input;self.sendUI.Track.Input.NextSelectionRight=self.sendUI.Track.Input
    if contains(self.sendUI,GuiService.SelectedObject) and not available(GuiService.SelectedObject) then self:focusActive() end
end
function D:confirmSend()
    if not self.state or not self.sendTarget or not self.sendMode or not self.sendAmount or self.sendAmount<=0 then return end
    if (self.state.counts[1] or 0)<=0 or (self.state.counts[self.sendTarget] or 0)<=0 then self:closeSend();return end
    local _,total,cap=P.donation(self.state,self.sendTarget,self.sendMode,100)
    local amount=math.clamp(self.sendAmount,0,if cap then math.min(total,cap) else total)
    if amount<=0 then return end
    local query=Rules.interaction(self.state,1,self.sendTarget)
    if not query[if self.sendMode=="troops" then "canDonateTroops" else "canDonateGold"] then return end
    self:command(if self.sendMode=="troops" then "DonateTroops" else "DonateGold",self.sendTarget,{amount=amount});self:hide()
end
-- PF022 ------------------------------------------------------------------------------------------------
function D:sliderNode(): GuiObject return if self.actionCard then self.actionCard:sliderInput() else self.sendUI.Track.Input end
function D:refreshCard()
    local state,owner=self.state,self.panelOwner
    local model=ActionModel.card(state,owner,{formatNumber=self.callbacks.formatNumber,formatTroops=self.callbacks.formatTroops,preferences=preferences,
        color=function(o: number) return self:ownerColor(o) end,directionUp=self.callbacks.directionUp})
    if not model then self:hide();return end
    self.actionCard:render(model,self:accentColor("accent"))
    self:refreshSend()
    if contains(self.actionCard.card,GuiService.SelectedObject) then
        self.actionCard:link()
        if not available(GuiService.SelectedObject) then self:focusActive() end
    end
end
-- Card presses run the same commands and rules as the PF012 panel's buttons.
function D:cardAction(id: string)
    local state,owner=self.state,self.panelOwner;if not state or not owner then return end
    if id=="AllianceRequest" then if self:allowed("canSendAllianceRequest") then self:request(owner);self:hide() end
    elseif id=="AllianceExtend" then local info=Rules.interaction(state,1,owner).allianceInfo;if info and info.canExtend then self:command("AllianceExtend",owner);self:hide() end
    elseif id=="BreakAlliance" then if self:allowed("canBreakAlliance") then self:command("BreakAlliance",owner);self:hide() end
    elseif id=="Trade" then if owner~=1 then local query=Rules.interaction(state,1,owner);self:command("Embargo",owner,{action=if query.canEmbargo then "start" else "stop"});self:hide() end
    elseif id=="Target" then if self:allowed("canTarget") then self:command("Target",owner);self:hide() end
    elseif id=="DonateTroops" then if self:allowed("canDonateTroops") then self:openSend(owner,"troops",self.panelTile) end
    elseif id=="DonateGold" then if self:allowed("canDonateGold") then self:openSend(owner,"gold",self.panelTile) end
    elseif id=="Emoji" then self:openEmoji(owner)
    elseif id=="Chat" then if self.callbacks.openChat then self.callbacks.openChat(owner);self:hide() end
    elseif id=="Trajectory" then if self.callbacks.flipTrajectory then self.callbacks.flipTrajectory();self:refreshPanel() end
    elseif id=="StopTradingAll" or id=="StartTradingAll" then
        if Rules.canEmbargoAll(state,1) then self:command("EmbargoAll",nil,{action=if id=="StopTradingAll" then "start" else "stop"}) end
    end
end
-- LB/RB: the previous/next preset while giving, else the previous/next action group.
function D:cardShoulder(direction: number)
    if not self.actionCard then return end
    if not self.sendUI.Visible then self.actionCard:cycle(direction);return end
    local current=self.sendPercent or 0;local nextPct=nil
    if direction>0 then for _,pct in P.PRESETS do if pct>current then nextPct=pct;break end end
    else for i=#P.PRESETS,1,-1 do if P.PRESETS[i]<current then nextPct=P.PRESETS[i];break end end end
    if nextPct then self.sendPercent=nextPct;self.sendAmount=nil;self.manualSendAmount=nil;self:refreshSend() end
end
function D:openEmoji(owner: number)
    if not self.state or owner<=0 then return end
    self.emojiTarget=if owner==1 then 0 else owner
    if not Rules.canSendEmoji(self.state,1,self.emojiTarget) then return end
    if not self.emojiBound then for i=0,59 do Icons.bind(self.emojiMenu.Body.Scroll["Emoji"..i].Icon,"DiplomacyEmoji"..i) end;self.emojiBound=true end
    self.emojiReturn=GuiService.SelectedObject
    if self.emojiPanel then
        -- PF029: the panel opens where the circle menu was; opened from the player card it takes the card's place
        local point=Social.radialPoint(self.ui)
        if self.panel.Visible then self:hide() end
        self.emojiPanel:open(Social.identity(self.state,self.emojiTarget,self:ownerColor(self.emojiTarget),preferences),point,self:accentColor("accent"))
    end
    self.emojiMenu.Visible=true;self.ui.Radial.Visible=false;self:focusActive()
end
function D:closeEmoji()
    if self.emojiPanel then self.emojiPanel:close() end
    self.emojiMenu.Visible=false
    self:restoreSelection(self.emojiMenu,self.emojiReturn);self.emojiReturn=nil
    if self.panel.Visible then self:focusActive() end
end
function D:refreshPanel()
    if not self.state or not self.panel.Visible or not self.panelOwner then return end
    if self.panelTile then self.panelOwner=self.state.owners[self.panelTile];if not self.panelOwner or self.panelOwner<=0 then self:hide();return end end
    if self.actionCard then self:refreshCard();return end -- PF022
    local owner=self.panelOwner;local player=self.state.players[owner];local query=Rules.interaction(self.state,1,owner);local c=self.content
    c.PlayerName.Text=ownerName(self.state,owner);c.Identity.Text=P.text(if player.playerType=="Nation" then "player_type.nation" elseif player.playerType=="Bot" then "player_type.bot" else "player_type.player")
    c.Resources.Gold.Text="     "..self.callbacks.formatNumber(self.state.gold[owner]).." "..P.text("player_panel.gold")
    c.Resources.Troops.Text="     "..self.callbacks.formatTroops(self.state.troops[owner]).." "..P.text("player_panel.troops")
    local seconds=P.traitorSeconds(self.state,owner);local relation=if owner~=1 then Rules.relation(self.state,owner,1) else 2
    c.Relation.Visible=seconds~=nil or (owner~=1 and player.playerType=="Nation" and not P.alliance(self.state,1,owner))
    local badge=if seconds then "Traitor" elseif relation==0 then "Hostile" elseif relation==1 then "Distrustful" elseif relation==3 then "Friendly" else "Neutral"
    c.Relation.Text="       "..P.text(if seconds then "player_panel.traitor" else "relation."..string.lower(badge))..(if seconds then " • "..P.duration(seconds) else "")
    c.Relation.TextColor3=if seconds then P.CSS.Red200 else P.COLORS[badge];c.Relation.RelationIcon.Visible=badge~="Neutral"
    c.Relation.BackgroundColor3=if seconds or badge=="Hostile" then P.CSS.Red500 elseif badge=="Distrustful" then P.CSS.Red300 elseif badge=="Friendly" then P.CSS.Emerald500 else P.CSS.Zinc500;c.Relation.BackgroundTransparency=.9
    local relationBorder=c.Relation:FindFirstChild("Border");if relationBorder and relationBorder:IsA("UIStroke") then relationBorder.Color=if seconds or badge=="Hostile" then P.CSS.Red400 elseif badge=="Distrustful" then P.CSS.Red300 elseif badge=="Friendly" then P.CSS.Emerald400 else P.CSS.Zinc400;relationBorder.Transparency=if badge=="Distrustful" then .6 else .7 end
    if badge~="Neutral" then Icons.bind(c.Relation.RelationIcon,if seconds then "DiplomacyTraitor" else "DiplomacyRelation"..badge) end
    c.Trajectory.Visible=owner==1 and (self.state.counts[1] or 0)>0;c.Trajectory.Text=P.text("player_panel.flip_rocket_trajectory").."\n"..P.text(if self.callbacks.directionUp and self.callbacks.directionUp() then "player_panel.arc_up" else "player_panel.arc_down")
    local data=self.state.diplomacy[owner];c.Betrayals.Text="     "..P.text("player_panel.betrayals").."                       "..data.betrayalCount
    c.Trading.Text="     "..P.text("player_panel.trading").."                       "..P.text(if Rules.hasEmbargo(self.state,owner,1) then "player_panel.stopped" else "player_panel.active")
    c.Trading.TextColor3=if Rules.hasEmbargo(self.state,owner,1) then P.CSS.Amber400 else P.CSS.Blue400
    for _,row in self.rows do row:Destroy() end;self.rows={};local allies=P.allies(self.state,owner)
    c.AlliancesTitle.Text=P.text("player_panel.alliances").."   "..#allies
    if #allies==0 then local row=self.ui.Templates.DiplomacyAllyRow:Clone();row.Text=P.text("common.none");row.Visible=true;row.Parent=c.Allies;table.insert(self.rows,row) end
    for i,ally in allies do local row=self.ui.Templates.DiplomacyAllyRow:Clone();row.LayoutOrder=i;row.RichText=true;local escaped=string.gsub(string.gsub(string.gsub(ally.name,"&","&amp;"),"<","&lt;"),">","&gt;");row.Text=escaped.."   "..(if ally.party then richColor(P.COLORS.ExpiryGreen,"Party") else richColor(P.expiryColor(ally.seconds),P.duration(ally.seconds)));row.TextColor3=P.CSS.Zinc100;row.Visible=true;row.Parent=c.Allies;table.insert(self.rows,row) end
    local alliance=P.alliance(self.state,1,owner);local remaining=if alliance then math.max(0,math.floor((alliance.expiresAt-self.state.ticks)/10)) else nil
    if alliance and alliance.party==true then c.Expiry.Visible=true;c.Expiry.Text="Party";c.Expiry.TextColor3=P.COLORS.ExpiryGreen -- PF044: no timer
    else c.Expiry.Visible=remaining~=nil;c.Expiry.Text=if remaining then P.text("player_panel.alliance_time_remaining").."    "..P.duration(remaining) else "";c.Expiry.TextColor3=P.expiryColor(remaining) end
    local a=c.Actions;local alive=(self.state.counts[1] or 0)>0 and self.state.phase~="Choosing";a.Visible=alive
    a.Chat.Visible=true;enabled(a.Chat,true,false);a.Chat.Text=P.text("player_panel.chat")
    for field,name in {canDonateTroops="DonateTroops",canDonateGold="DonateGold",canTarget="Target",canBreakAlliance="BreakAlliance",canSendAllianceRequest="AllianceRequest"} do a[name].Visible=query[field]==true;enabled(a[name],query[field]==true,false) end
    a.Emoji.Visible=Rules.canSendEmoji(self.state,1,if owner==1 then 0 else owner)
    a.Trade.Visible=owner~=1;a.Trade.Text=P.text(if query.canEmbargo then "player_panel.stop_trade" else "player_panel.start_trade")
    Icons.bind(a.Trade.Icon,if query.canEmbargo then "DiplomacyStopTrade" else "DiplomacyStartTrade")
    a.BreakAlliance.Text=P.text("player_panel.break_alliance");a.AllianceRequest.Text=P.text("player_panel.send_alliance")
    for _,name in {"StopTradingAll","StartTradingAll"} do a[name].Visible=owner==1;enabled(a[name],Rules.canEmbargoAll(self.state,1),false) end
    for _,name in {"Chat","Emoji","DonateTroops","DonateGold","Target","Trade","BreakAlliance","AllianceRequest","StopTradingAll","StartTradingAll"} do local variant=if name=="Trade" then (if query.canEmbargo then "yellow" else "green") elseif name=="StopTradingAll" then "yellow" elseif name=="StartTradingAll" then "green" elseif name=="BreakAlliance" then "red" elseif name=="AllianceRequest" then "indigo" else "normal";paintAction(a[name],variant,self.actionHovered[name]==true) end
    self.body.Border.Color=if seconds then Theme.Danger else Theme.Border;self.body.Border.Transparency=.15
    -- Rows collapse through the authored UIListLayout; actions flow through the
    -- authored UIGridLayout in LayoutOrder. Only the focus order is built here.
    local navigation={self.body.Close}
    if c.Trajectory.Visible then table.insert(navigation,c.Trajectory) end
    if a.Visible then
        for _,name in {"Chat","Emoji","Target","DonateTroops","DonateGold","Trade","BreakAlliance","AllianceRequest","StopTradingAll","StartTradingAll"} do
            if a[name].Visible then table.insert(navigation,a[name]) end
        end
    end
    self:linkSelection(navigation)
    self:refreshSend()
    if not self.sendUI.Visible and contains(self.panel,GuiService.SelectedObject) and not available(GuiService.SelectedObject) then self:focusActive() end
end
function D:addNotice(text: string,focus: number?,_tick: number?,kind: string?,emoji: string?,glyph: string?,detail: string?)
    -- Every notice (diplomacy events, pushNotice toasts) passes here: PF019 W7 S5 Alerts filter.
    if not self.stack or not NoticeStack.allows(kind,setting("alerts")) then return end
    self.stack:push({text=text,focus=focus,kind=kind or "",emoji=emoji,glyph=glyph,detail=detail})
    task.delay(NoticeStack.NOTICE_SECONDS+.05,function()
        if not self.destroyed and self.stack and self.stack:expire() then self:refreshHud() end
    end)
    if not self.updating then self:refreshHud() end
end
-- Roadmap #1 (PF - 1): a notice with its own template and painter (the daily challenge row, PFNoticeDaily): {text, kind,
-- template, paint(ui), glyph=false keeps the template's glyph}. The same Alerts filter and lifetime as addNotice.
function D:addRichNotice(notice: any)
    if not self.stack or not NoticeStack.allows(notice.kind,setting("alerts")) then return end
    self.stack:push(notice)
    task.delay(NoticeStack.NOTICE_SECONDS+.05,function()
        if not self.destroyed and self.stack and self.stack:expire() then self:refreshHud() end
    end)
    if not self.updating then self:refreshHud() end
end
-- Public seam for other HUD notices (Builder A may route event toasts here).
-- PF014: the server kept the troop reserve on a send (reduced or refused).
function D:reserveNotice(packet: any)
    if self.reserveHint then self.reserveHint:show(packet) end
    if packet.refused then require(script.Parent.Sfx).play("u_error") end -- PF043: a send refused by the reserve
    -- Release (new-player send guard, Ashton 2026-10-26): a new player (the server sets newPlayer: < 5 matches, not Ranked)
    -- learns once a match why some troops stayed home; experienced players never see it
    -- Ashton's tips rule (TipMemory): it only explains, so it retires after 3 shows; off after 5 matches like every beginner tip
    if packet.newPlayer==true and not self.reserveTipShown then
        local okT,Tips=pcall(require,script.Parent.TipMemory)
        if okT and not (Tips :: any).allowed("reserve") then return end
        self.reserveTipShown=true;self:pushNotice("Some troops stay home to defend","INFO")
        if okT then (Tips :: any).seen("reserve") end
    end
end
-- MM (Ashton's RoWorld test: 4 fronts at once, home army ~22% of max): a new player (OpenFrontMatches < 5; Ranked opens at
-- 25, so never there) with FrontsMin+ outgoing attacks running and home troops under FrontsHome of max (state.caps) gets the
-- same once-per-match reserve tip (Config.Combat.NewPlayerGuard). Pure ratios, any map size.
function D:frontsTip(state: any)
    if self.reserveTipShown or not state or not state.attacks or not state.caps then return end
    local ok,guard,c,matches=pcall(function()
        local shared=game:GetService("ReplicatedStorage").Shared
        return require(shared.NewPlayerGuard),require(shared.Config).Combat.NewPlayerGuard,game:GetService("Players").LocalPlayer:GetAttribute("OpenFrontMatches")
    end)
    if not ok or not guard.eligible(matches,false) then return end
    local cap=state.caps[1];local troops=state.troops and state.troops[1]
    if type(cap)~="number" or cap<=0 or type(troops)~="number" or troops>=cap*c.FrontsHome then return end
    local fronts=0
    for _,attack in state.attacks do if attack.owner==1 and attack.active~=false then fronts+=1 end end
    if fronts>=c.FrontsMin then self:reserveNotice({newPlayer=true}) end
end
-- Release (new-player send guard): the server shrank a rapid repeat send (NewPlayerGuard); only its tip step shows a toast
function D:guardNotice(packet: any)
    if type(packet)~="table" or packet.tip~=true then return end
    -- Ashton's tips rule (TipMemory): retires after 3 shows; off after 5 matches (the server's guard stops there too)
    local okT,Tips=pcall(require,script.Parent.TipMemory)
    if okT and not (Tips :: any).allowed("guard") then return end
    self:pushNotice("Let your troops grow back","WARNING")
    if okT then (Tips :: any).seen("guard") end
end
function D:pushNotice(text: string,kind: string?,focus: number?,glyph: string?,detail: string?)
    if self.state and (self.state.counts[1] or 0)>0 then self:addNotice(text,focus,self.state.ticks,kind,nil,glyph,detail) end
end
function D:event(event: any)
    -- Both original event layers stop their update groups for a dead/local-absent player.
    local s=self.state;if not s or not s.players[1] or (s.counts[1] or 0)<=0 then return end
    local tick=s.ticks;local name=function(owner) return ownerName(s,owner) end
    if event.type=="AllianceRequest" and event.recipientID==1 then
        if Rules.allianceWith(s,event.requestorID,event.recipientID)==nil and self:allianceRequestAllowed(event.requestorID)==true then self:playSound("alliance-suggested") end
    elseif event.type=="AllianceRequestReply" and event.request.requestorID==1 then
        self:addNotice(P.text("events_display.alliance_request_status",{name=name(event.request.recipientID),status=P.text(if event.accepted then "events_display.alliance_accepted" else "events_display.alliance_rejected")}),event.request.recipientID,tick,if event.accepted then "ALLIANCE_ACCEPTED" else "ALLIANCE_REJECTED")
        self:playSound(if event.accepted then "alliance-accepted" else "alliance-declined")
    elseif event.type=="BrokeAlliance" then
        if s.players[event.betrayedID].isDisconnected then return end
        if event.traitorID==1 and not Rules.isTraitor(s,event.betrayedID) then
            self:playSound("alliance-broken")
            self:addNotice(P.text("events_display.betrayal_description",{name=name(event.betrayedID),malusPercent=50,durationText=P.text("events_display.duration_seconds_plural",{seconds=(Config.Diplomacy and Config.Diplomacy.TraitorTicks or 300)/10})}),event.betrayedID,tick,"ALLIANCE_BROKEN")
        elseif event.betrayedID==1 then
            self:playSound("alliance-broken");self:addNotice(P.text("events_display.betrayed_you",{name=name(event.traitorID)}),event.traitorID,tick,"ALLIANCE_BROKEN") end
    elseif event.type=="AllianceExpired" then local other=if event.player1ID==1 then event.player2ID elseif event.player2ID==1 then event.player1ID else nil;if other and (s.counts[1] or 0)>0 and (s.counts[other] or 0)>0 then self:addNotice(P.text("events_display.alliance_expired",{name=name(other)}),other,tick,"ALLIANCE_EXPIRED") end
    elseif event.type=="DonateEvent" then
        local sender=if type(event.senderId)=="number" then event.senderId else self.ownerById[event.senderId];local recipient=if type(event.recipientId)=="number" then event.recipientId else self.ownerById[event.recipientId]
        if sender~=1 and recipient~=1 then return end;local received=recipient==1;local other=if received then sender else recipient;local gold=event.donationType=="gold"
        local key=if received then (if gold then "received_gold_from_player" else "received_troops_from_player") else (if gold then "sent_gold_to_player" else "sent_troops_to_player")
        self:addNotice(P.text("events_display."..key,{name=name(other),gold=self.callbacks.formatNumber(event.amount),troops=self.callbacks.formatTroops(event.amount)}),other,tick,if received then "DONATION_RECEIVED" else "DONATION_SENT",nil,if gold then "DiplomacyDonateGold" else "DiplomacyDonateTroops")
    elseif event.type=="DisplayMessage" and (event.owner==nil or event.owner==1) then
        local params=table.clone(event.params or {});if event.otherOwner then params.name=name(event.otherOwner) end
        self:addNotice(P.text(event.message,params),event.otherOwner,tick,event.messageType)
    elseif event.type=="DisplayChatEvent" then
        if event.isFrom and not D.fromShown(s,event.recipient,setting("quickChat")) then return end -- PF019 W7 S6 (sender = recipient)
        -- PF029: two lines in the PF027 row: who ("Sent to …" for your own), then the phrase
        local message,focus=Chat.notice(s,event,1)
        if message then
            local body=Chat.text("chat."..event.category.."."..event.key)
            if event.target then body=Chat.replacePlayer(body,if s.players[event.target] then Chat.name(s,event.target) else tostring(event.target)) end
            local who=if event.recipient then Chat.name(s,event.recipient) else ""
            self:addNotice(if event.isFrom then who else "Sent to "..who,focus,tick,"CHAT",nil,nil,body);self:playSound("message")
        end
    elseif event.type=="TargetPlayer" and P.friendly(s,1,event.playerID) then
        self:addNotice(P.text("events_display.attack_request",{name=name(event.playerID),target=name(event.targetID)}),event.targetID,tick,"ATTACK_REQUEST")
    elseif event.type=="Emoji" then
        -- PF019 W7 S6 (the Emojis switch is retired): others' emotes follow Quick chat and emotes.
        local emoji=event.emoji or event;if not D.fromShown(s,emoji.senderID,setting("quickChat")) then return end
        -- PF029: the emoji is the row's badge; the words are just who ("Sent to …" for your own)
        if emoji.recipientID==1 then self:addNotice(name(emoji.senderID),emoji.senderID,tick,"CHAT",emoji.message)
        elseif emoji.senderID==1 and emoji.recipientID~=0 and emoji.recipientID~="AllPlayers" then self:addNotice("Sent to "..name(emoji.recipientID),emoji.recipientID,tick,"CHAT",emoji.message) end
    end
    if (event.type=="AllianceExtension" and event.playerID==1) or event.type=="BrokeAlliance" then
        local id=event.allianceID;for _,row in table.clone(self.requestRows) do if row.allianceId==id then self:removeRequestRow(row.key) end end
        if self.renewCreated then self.renewCreated[id]=nil end
        if event.type=="BrokeAlliance" then self.renewChecked[id]=nil end
    end
end
function D:respond(row: any,accept: boolean)
    self:requestAction(row.kind,row.owner,accept)
    self.dismissed[row.key]=true
    self:removeRequestRow(row.key)
    self:refreshHud()
end
function D:removeRequestRow(key: string)
    for index,row in self.requestRows do if row.key==key then table.remove(self.requestRows,index);break end end
    if self.stack then self.stack:removeRequest(key) end
end
function D:refreshEvents()
    if not self.state then return end;local tick=self.state.ticks;local rows={}
    local duration=Config.Diplomacy and Config.Diplomacy.RequestDurationTicks or 200
    for _,request in self.state.diplomacyRequests or {} do
        if request.recipient~=1 or (self.state.counts[request.requestor] or 0)<=0 or tick-request.createdAt>=duration then continue end
        local key="request"..request.requestor..":"..request.createdAt
        local allowed=self:allianceRequestAllowed(request.requestor)
        if allowed==false and not self.dismissed[key] then self.dismissed[key]=true;self:command("AllianceReject",request.requestor) end
        if allowed~=true then continue end
        if not self.dismissed[key] then table.insert(rows,{key=key,owner=request.requestor,kind="request",createdAt=request.createdAt,priority=0,startTick=request.createdAt,endTick=request.createdAt+duration}) end
    end
    local existingAlliances={};local window=Config.Diplomacy and Config.Diplomacy.ExtensionPromptTicks or 300
    for _,a in Rules.alliances(self.state,1) do
        existingAlliances[a.id]=true;local key="renew"..a.id
        if a.party==true then continue end -- PF044: a party alliance lasts the match: no renew prompt
        if a.expiresAt<=tick+window and (self.renewChecked[a.id] or 0)<tick-window then self.renewChecked[a.id]=tick;self.dismissed[key]=nil;self.renewCreated=self.renewCreated or {};self.renewCreated[a.id]=tick end
        if self.renewCreated and self.renewCreated[a.id] and not self.dismissed[key] then
            table.insert(rows,{key=key,owner=if a.requestor==1 then a.recipient else a.requestor,kind="renew",createdAt=self.renewCreated[a.id],priority=100000,allianceId=a.id,
                startTick=math.min(self.renewCreated[a.id],a.expiresAt-1),endTick=a.expiresAt})
        end
    end
    for id in self.renewChecked do if not existingAlliances[id] then self.renewChecked[id]=nil;if self.renewCreated then self.renewCreated[id]=nil end end end
    table.sort(rows,function(a,b) return if a.priority==b.priority then a.createdAt>b.createdAt else a.priority>b.priority end)
    for _,row in rows do
        row.name=ownerName(self.state,row.owner);row.color=self:ownerColor(row.owner)
        row.message=if row.kind=="request" then "wants an alliance" else "alliance is about to expire"
        row.acceptText=if row.kind=="request" then "Accept" else P.text("events_display.renew_alliance")
        row.declineText=if row.kind=="request" then "Decline" else P.text("events_display.ignore")
    end
    self.requestRows=rows
    if self.stack then self.stack:setRequests(rows,tick) end
    if not self.updating then self:refreshHud() end
end
-- Conquest events mean the victim's last land fell. Tribes are skipped (noise);
-- the local player's own elimination is the result screen's job.
function D:eliminations(state: any)
    local cursor=math.max(self.conquestCursor or 0,state.conquestEventCursor or 0)
    for _,event in state.conquestEvents or {} do
        if self.conquestCursor~=nil and event.id>self.conquestCursor then
            local victim=self.ownerById[event.conqueredId];local captor=self.ownerById[event.conquerorId]
            local text,focus,kind=Model.elimination(state,victim,captor,event.gold,{formatNumber=self.callbacks.formatNumber,preferences=preferences})
            if text then self:addNotice(text,focus,state.ticks,kind) end
        end
        cursor=math.max(cursor,event.id)
    end
    self.conquestCursor=cursor
end
function D:update(state: any)
    if self.destroyed then return end
    self.state=state;self.ownerById={};for owner,player in state.players do self.ownerById[player.id]=owner end
    self:frontsTip(state)
    self.updating=true
    -- ActionableEvents checks expiry windows before its update groups.
    self:refreshEvents()
    if self.eventCursor~=nil then
        local rank={DisplayMessage=1,DisplayChatEvent=2,AllianceRequestReply=3,BrokeAlliance=4,TargetPlayer=5,Emoji=6,UnitIncoming=7,AllianceExpired=8,DonateEvent=9,AllianceExtension=10,AllianceRequest=11}
        local fresh={};for _,event in state.diplomacyEvents or {} do if event.eventId>self.eventCursor then table.insert(fresh,event) end end
        table.sort(fresh,function(a,b) return if rank[a.type]==rank[b.type] then a.eventId<b.eventId else (rank[a.type] or 100)<(rank[b.type] or 100) end)
        for _,event in fresh do self:event(event) end
    end
    self.eventCursor=math.max(self.eventCursor or 0,state.diplomacyEventCursor or 0)
    if state.players[1] and (state.counts[1] or 0)>0 then self:eliminations(state) else self.conquestCursor=math.max(self.conquestCursor or 0,state.conquestEventCursor or 0) end
    self:refreshPanel();self:refreshEvents()
    self.updating=false
    self:refreshHud()
end
function D:reset()
    self.hoverUnitId=nil;self.hoverTile=nil
    self.reserveTipShown=nil
    self:closeEmoji();self:hide();self.hover.Visible=false;self.feed.Visible=false;self.eventCursor=nil;self.conquestCursor=nil;self.panelOwner=nil;self.panelTile=nil;self.hoverOwner=nil;self.state=nil;self.renewChecked={};self.renewCreated={};self.dismissed={}
    if contains(self.feed,GuiService.SelectedObject) or (self.stack and contains(self.stack.container,GuiService.SelectedObject)) then GuiService.SelectedObject=nil end
    self.requestRows={};self.cardSignature=nil;self.stripSignature=nil;self.attackCache=nil
    if self.stack then self.stack:reset() end;if self.card then self.card:hide() end;if self.strip then self.strip:hide() end
    self.ui:SetAttribute("DiplomacyRequestCards",0);self.ui:SetAttribute("DiplomacyNotices",0)
    self.ui:SetAttribute("PFNoticeStackHeight",0);self.ui:SetAttribute("PFNoticeRequests",0);self.ui:SetAttribute("PFNoticeCount",0)
end
function D:hoverAt(tile: number?)
    if tile==nil or (self.callbacks.canHover and not self.callbacks.canHover()) or not self.state or self.panel.Visible or self.emojiMenu.Visible then
        if self.hoverOwner or self.hoverUnitId or self.hoverTile then self.hoverOwner=nil;self.hoverUnitId=nil;self.hoverTile=nil;self:refreshInspection() end
        return
    end
    self.hoverTile=tile
    local unit=P.navalUnitAt(self.state,tile)
    if unit then self.hoverOwner=nil;self.hoverUnitId=unit.id
    else
        self.hoverUnitId=nil
        local owner=self.state.owners[tile];self.hoverOwner=if owner and owner>0 then owner else nil
    end
    self:refreshInspection()
end
function D:ownerColor(owner: number): Color3?
    if not self.callbacks.ownerColor then return nil end
    local ok,color=pcall(self.callbacks.ownerColor,owner)
    return if ok and typeof(color)=="Color3" then color else nil
end
-- Attack eligibility for an owned tile depends only on its owner; cache it per
-- snapshot tick so hovering never repeats the border scan.
function D:canAttack(tile: number): boolean
    local state=self.state;if not state then return false end
    local owner=state.owners[tile];if not owner or owner<=0 then return false end
    if self.attackCacheState~=state or self.attackCacheTick~=state.ticks or not self.attackCache then self.attackCache={};self.attackCacheState=state;self.attackCacheTick=state.ticks end
    local cached=self.attackCache[owner];if cached~=nil then return cached end
    local ok,result=pcall(function()
        if self.callbacks.canAttackAt then return self.callbacks.canAttackAt(tile) end
        return require(Shared.Simulation).canAttack(state,1,tile)
    end)
    local value=ok and result==true;self.attackCache[owner]=value
    return value
end
function D:mouseMode(): boolean
    local kind=UIS:GetLastInputType()
    return kind==Enum.UserInputType.MouseMovement or kind==Enum.UserInputType.MouseButton1 or kind==Enum.UserInputType.MouseButton2
        or kind==Enum.UserInputType.MouseButton3 or kind==Enum.UserInputType.MouseWheel or kind==Enum.UserInputType.Keyboard
end
function D:modelOptions(tile: number?): any
    local state=self.state
    return {me=1,tile=tile,formatNumber=self.callbacks.formatNumber,formatTroops=self.callbacks.formatTroops,
        ratio=if self.callbacks.ratio then self.callbacks.ratio() else 0,
        canAct=self.callbacks.canAct or function() return state.phase~="Choosing" and (state.counts[1] or 0)>0 end,
        canAttack=function(target: number) return self:canAttack(target) end,
        leftClickOpensMenu=preferences~=nil and preferences:get("leftClickOpensMenu")==true,
        placing=self.ui.Controls.Placement.Visible or self.ui:GetAttribute("GhostStructure")~=nil,
        preferences=preferences,color=function(owner: number) return self:ownerColor(owner) end}
end
function D:findUnit(id: number?): any?
    if not id or not self.state then return nil end
    for _,group in {self.state.warships or {},self.state.tradeShips or {},self.state.ships or {}} do
        for _,unit in group do if unit.id==id and unit.active~=false then return unit end end
    end
    return nil
end
-- Hovered (mouse or gamepad reticle) > tapped radial target > open panel > own.
function D:inspectedOwner(): number?
    local state=self.state;if not state then return nil end
    local unit=self:findUnit(self.hoverUnitId)
    if unit and state.players[unit.owner] then return unit.owner end
    if self.hoverOwner and state.players[self.hoverOwner] then return self.hoverOwner end
    local radial=self.ui:FindFirstChild("Radial")
    if radial and radial:IsA("GuiObject") and radial.Visible then
        local tile=radial:GetAttribute("TargetId");local owner=if type(tile)=="number" then state.owners[tile] else nil
        if owner and owner>0 and state.players[owner] then return owner end
    end
    if self.panel.Visible and self.panelOwner and state.players[self.panelOwner] then return self.panelOwner end
    if state.phase~="Choosing" and (state.counts[1] or 0)>0 then return 1 end
    return nil
end
local function signature(data: any,extra: string?): string
    local parts={data.kind,tostring(data.owner),data.name,data.chip,data.subtitle or "",data.attack or "",data.more or "",if data.color then data.color:ToHex() else "",extra or "",if data.troopBar then data.troopBar.key else ""} -- PF021: the troop meter re-renders on its own changes
    for _,row in data.rows do table.insert(parts,row.id.."="..row.value..":"..(row.tone or "")) end
    -- PF - 4: the v2 card's parts (badge, tiles, versus, actions) re-render on their own changes
    table.insert(parts,data.badge or "");if data.versus then table.insert(parts,data.versus.key) end
    if data.tiles then table.insert(parts,data.tiles.land..":"..data.tiles.gold) end
    for _,a in data.actions or {} do table.insert(parts,a.id.."="..a.text) end
    return table.concat(parts,"|")
end
function D:refreshInspection(force: boolean?)
    if not self.card or self.destroyed then return end
    local state=self.state;local accent=self:accentColor("text")
    -- Cursor card: mouse only, over owned land or a ship; none while a building is being placed (UI audit 2026-10-28: it
    -- popped up over your own land under the ghost)
    local cardData=nil
    local placing=self.ui.Controls.Placement.Visible or self.ui:GetAttribute("GhostStructure")~=nil
    if state and self:mouseMode() and not self.panel.Visible and not self.emojiMenu.Visible and not placing then
        local unit=self:findUnit(self.hoverUnitId)
        if unit then cardData=Model.unit(state,unit,self:modelOptions(nil))
        elseif self.hoverOwner then cardData=Model.country(state,self.hoverOwner,self:modelOptions(self.hoverTile))
        elseif self.hoverTile and self.card.node:FindFirstChild("PFFooter") then cardData=Model.openLand(state,self.hoverTile,self:modelOptions(self.hoverTile)) end -- PF - 4: the v2 card's open land
    end
    if cardData then
        local key=signature(cardData)
        if force or key~=self.cardSignature then self.cardSignature=key;self.card:render(cardData,accent) end
        self:placeCard()
    else
        self.cardSignature=nil;self.card:hide()
    end
    local owner=self:inspectedOwner()
    local data=if owner and state then Model.country(state,owner,self:modelOptions(nil)) else nil
    local key=if data then signature(data) else nil
    if force or key~=self.stripSignature then self.stripSignature=key;self.strip:render(data,accent) end
end
-- Card avoids the dock, the real notification stack, the strip and HUD panels.
function D:avoidRects(): {any}
    local origin=self.ui.AbsolutePosition;local zones={}
    local function add(object: Instance?)
        if object and object:IsA("GuiObject") and HudControls.visible(object) then
            local p,s=object.AbsolutePosition-origin,object.AbsoluteSize
            if s.X>0 and s.Y>0 then table.insert(zones,Model.rect(p.X,p.Y,p.X+s.X,p.Y+s.Y)) end
        end
    end
    local controls=self.ui.Controls;add(controls);add(controls:FindFirstChild("Blueprints"));add(controls:FindFirstChild("Placement"))
    -- PF013: the leaderboard lives in Builder C's authored region.
    local board=self.ui:FindFirstChild("PFLeaderboardRegion");add(board and board:FindFirstChild("Leaderboard"))
    add(self.ui:FindFirstChild("PFInspectorRegion",true)) -- PF018: inside Builder A's top row
    for _,name in {"PFIconBar","Leaderboard","Attacks","Radial","GameRightSidebar","ClockPanel","Pause","TutorialGuide","VariantPanels","VariantSpeedPanel","TeamOwnershipBar","Notice","HeadsUp"} do
        add(self.ui:FindFirstChild(name))
    end
    if self.stack then local zone=self.stack:occupied(origin);if zone then table.insert(zones,zone) end end
    return zones
end
function D:placeCard()
    if not self.card or not self.cardSignature then return end
    if not self.pointer then self.card.node.Visible=false;return end
    -- The pointer and AbsolutePosition share Roblox's inset-excluded space, so when
    -- Game starts at the screen top (DeviceSafeInsets) the topbar row is the
    -- Game-local band above -origin.Y; the card stays below it.
    local size,origin=self.ui.AbsoluteSize,self.ui.AbsolutePosition
    self.card:place(self.pointer-origin,Model.rect(8,math.max(0,-origin.Y)+8,size.X-8,size.Y-8),self:avoidRects())
end
function D:center(tile: number): boolean
    if not self.state then return false end;local owner=self.state.owners[tile]
    if owner and owner>0 and owner~=1 and P.friendly(self.state,1,owner) and not self.state.players[owner].isDisconnected then
        local query=Rules.interaction(self.state,1,owner)
        if query.canDonateTroops then local amount=math.floor((self.callbacks.ratio and self.callbacks.ratio() or 1)*self.state.troops[1]);if amount>0 then self:command("DonateTroops",owner,{amount=amount}) end end
        self.ui.Radial.Visible=false;return true
    end;return false
end
function D:key(key: Enum.KeyCode,position: Vector2?): boolean
    local back=key==Enum.KeyCode.Escape or key==Enum.KeyCode.ButtonB
    if back and self.emojiMenu.Visible then self:closeEmoji();return true end
    if self.sendUI.Visible then
        if back then self:closeSend();return true
        elseif key==Enum.KeyCode.Return or key==Enum.KeyCode.KeypadEnter then self:confirmSend();return true
        elseif GuiService.SelectedObject==self:sliderNode() and (key==Enum.KeyCode.DPadLeft or key==Enum.KeyCode.DPadRight) then return self:adjustSend(if key==Enum.KeyCode.DPadLeft then -1 else 1) end
    end
    if back and self.panel.Visible then self:hide();return true end
    if not self.state or self.state.phase=="Choosing" or not position then return false end
    if key~=Enum.KeyCode.K and key~=Enum.KeyCode.L then return false end
    local tile=self.callbacks.targetAt(position);local owner=if tile then self.state.owners[tile] else 0;if not owner or owner<=0 then return true end
    local query=Rules.interaction(self.state,1,owner)
    if key==Enum.KeyCode.K then if query.canSendAllianceRequest then self:request(owner) elseif query.allianceInfo and query.allianceInfo.canExtend then self:command("AllianceExtend",owner) end
    elseif query.canBreakAlliance then self:command("BreakAlliance",owner) end;return true
end
return D
