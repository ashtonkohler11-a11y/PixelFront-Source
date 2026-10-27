--!strict
-- PF022 (PF - 3): the in-match player card authored by tools/atlas/author-pf022-player-actions.luau
-- (DiplomacyPanel.PFCard + PFScrim). Fills content from PlayerActionsModel, paints states and wires
-- input; the only geometry it writes is the give slider's thumb. Commands stay in
-- DiplomacyController: every press calls back into it (callbacks.action(id), .close(), .back(),
-- .preset(pct), .confirm(), .slider(input) / .sliderMoved(input)).
local GuiService=game:GetService("GuiService")
local Theme=require(script.Parent.BattleHudTheme)
local HoverCard=require(script.Parent.CountryHoverCard)
local Icons=require(script.Parent.ReferenceIcons)
local Card={};Card.__index=Card
-- ReferenceIcons.content WaitForChild()s a missing name forever: bind only names the place carries.
local storage=game:GetService("ReplicatedStorage")
function Card.bindable(name: string): boolean
    if Icons.Assets[name] then return true end
    local folder=storage:FindFirstChild("OpenFrontIcons")
    return folder~=nil and folder:FindFirstChild(Icons.canonical(name))~=nil
end
Card.SLOTS={3,2,2}
local DISABLED=Color3.fromHex("#1b1b1b")
local REASON=Color3.fromHex("#e7c27a")
function Card.tone(tone: string?,accent: Color3?): Color3
    return if tone=="muted" then Theme.Muted else HoverCard.toneColor(tone,accent)
end
-- The authored nodes, or nil when the place doesn't carry them yet (the controller keeps its old body).
function Card.find(panel: Instance): any?
    local card=panel:FindFirstChild("PFCard");local scrim=panel:FindFirstChild("PFScrim")
    if not (card and scrim and card:FindFirstChild("Actions") and card:FindFirstChild("Give") and card:FindFirstChild("Close")) then return nil end
    -- v3: optional drop-shadow frames behind the card (they show and hide with it)
    local shadows={};for _,name in {"PFCardShadow","PFCardShadowInner"} do local shadow=panel:FindFirstChild(name);if shadow and shadow:IsA("GuiObject") then table.insert(shadows,shadow) end end
    return {card=card,scrim=scrim,shadows=shadows}
end
function Card.new(nodes: any,callbacks: any): any
    local card=nodes.card
    local self=setmetatable({card=card,scrim=nodes.scrim,shadows=nodes.shadows or {},callbacks=callbacks,connections={},slots={},hovered={},view="hidden",model=nil,give=nil},Card)
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(function(...) if not self.destroyed then fn(...) end end)) end
    self.listen=listen
    for g,count in Card.SLOTS do
        local group=card.Actions:FindFirstChild("Group"..g)
        for s=1,count do
            local slot=group and group:FindFirstChild("Slot"..s)
            if slot then
                table.insert(self.slots,{group=g,index=s,node=slot})
                listen(slot.Activated,function() local id=slot:GetAttribute("ActionId");if type(id)=="string" and slot:GetAttribute("Enabled")==true then callbacks.action(id) end end)
                listen(slot.MouseEnter,function() self.hovered[slot]=true;self:paintSlot(slot) end)
                listen(slot.MouseLeave,function() self.hovered[slot]=nil;self:paintSlot(slot) end)
            end
        end
    end
    local give=card.Give
    self.presets={}
    for _,pct in {10,25,50,75,100} do
        local b=give.Presets:FindFirstChild("Percent"..pct)
        if b then self.presets[pct]=b;listen(b.Activated,function() if b:GetAttribute("Enabled")==true then callbacks.preset(pct) end end)
            listen(b.MouseEnter,function() self.hovered[b]=true;self:paintGive() end);listen(b.MouseLeave,function() self.hovered[b]=nil;self:paintGive() end) end
    end
    listen(card.Close.Activated,function() if self.view=="give" then callbacks.back() else callbacks.close() end end)
    listen(give.Cancel.Activated,function() callbacks.back() end)
    listen(give.Send.Activated,function() if give.Send:GetAttribute("Enabled")==true then callbacks.confirm() end end)
    listen(give.Slider.InputBegan,function(input: InputObject) callbacks.slider(input) end)
    for _,b in {card.Close,give.Cancel,give.Send} do
        listen(b.MouseEnter,function() self.hovered[b]=true;self:paintChrome() end);listen(b.MouseLeave,function() self.hovered[b]=nil;self:paintChrome() end)
    end
    self:hide()
    return self
end
function Card:destroy()
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
function Card:visible(): boolean return self.card.Visible end
function Card:hide()
    self.card.Visible=false;self.scrim.Visible=false;self.view="hidden"
    for _,shadow in self.shadows do shadow.Visible=false end
end
function Card:showActions()
    self.card.Visible=true;self.scrim.Visible=true;self.view="actions"
    for _,shadow in self.shadows do shadow.Visible=true end
    self.card.Actions.Visible=true;self.card.Give.Visible=false;self.card.Details.Visible=true
    if self.model then self:renderTitle() end
end
function Card:showGive()
    self.card.Visible=true;self.scrim.Visible=true;self.view="give"
    for _,shadow in self.shadows do shadow.Visible=true end
    self.card.Actions.Visible=false;self.card.Give.Visible=true;self.card.Details.Visible=false
end
function Card:sliderTrack(): GuiObject return self.card.Give.Slider.Track end
function Card:sliderInput(): GuiObject return self.card.Give.Slider end

-- PIVOT (Ashton 2026-10-26: Levels "Remove it"): the PF023 level row, bar and tip stay hidden; the plain subtitle shows
function Card:renderLevel(model: any,accent: Color3?)
    local card=self.card
    for _,name in {"PFLevelRow","PFLevelBar","PFLevelTip"} do local node=card:FindFirstChild(name);if node then node.Visible=false end end
    card.Subtitle.Visible=true
end

-- ---------------------------------------------------------------- left pane + actions
function Card:renderTitle()
    local model=self.model
    self.card.Title.Text=if self.view=="give" and self.give then (if self.give.mode=="troops" then "Give troops" else "Give gold") elseif model and model.own then "Your nation" else "Actions"
end
function Card:render(model: any,accent: Color3?)
    self.model=model;self.accent=accent
    local card=self.card
    card.Dot.Visible=model.color~=nil;if model.color then card.Dot.BackgroundColor3=model.color end
    card.Wash.BackgroundColor3=model.color or Theme.Muted
    local details=card.Details
    card.Nation.Text=model.name
    HoverCard.paintChip(card.Chip,model.chip,accent)
    card.Subtitle.Text=model.subtitle;card.Subtitle.TextColor3=Card.tone(model.subtitleTone,accent)
    self:renderLevel(model,accent)
    card.Border.Color=if model.traitor then Theme.Danger else Theme.Border
    local troops=card.Troops;local bar=model.troopBar
    troops.Visible=bar~=nil
    if bar then
        troops.Value.Text=bar.rich
        troops.Rate.Text=bar.rate or "";troops.Attacking.Text=bar.attackingText or ""
        local meter=troops.Meter
        HoverCard.paintMeter(meter,bar,self.meterOwner==model.owner)
        self:paintGift()
    end
    self.meterOwner=if bar then model.owner else nil
    for index,stat in model.stats do
        local cell=details.Stats:FindFirstChild("Cell"..index)
        if cell then cell.Caption.Text=stat.caption;cell.Value.Text=stat.value;cell.Value.TextColor3=Card.tone(stat.tone,accent) end
    end
    details.Trade.Text=model.trade;details.Trade.TextColor3=Card.tone(model.tradeTone,accent)
    local allies=model.allies;local n=#allies
    details.AlliesTitle.Text="ALLIANCES · "..n
    for index=1,3 do
        local row=details:FindFirstChild("Ally"..index);if not row then continue end
        local entry=allies[index]
        if n==0 and index==1 then row.Visible=true;row.Who.Text="None";row.Who.TextColor3=Theme.Muted;row.Value.Text=""
        elseif n>3 and index==3 then row.Visible=true;row.Who.Text="+"..(n-2).." more";row.Who.TextColor3=Theme.Muted;row.Value.Text=""
        elseif entry then row.Visible=true;row.Who.Text=entry.name;row.Who.TextColor3=Theme.Text;row.Value.Text=entry.value;row.Value.TextColor3=Card.tone(entry.tone,accent)
        else row.Visible=false end
    end
    -- Groups: slot counts are authored (3, 2, 2); a group shows only when the model fills it exactly.
    for g,count in Card.SLOTS do
        local node=card.Actions:FindFirstChild("Group"..g);local group=model.groups[g]
        if not node then continue end
        node.Visible=group~=nil and #group.actions==count
        if not node.Visible then continue end
        node.Caption.Text=group.title
        for s=1,count do
            local slot=node:FindFirstChild("Slot"..s);local a=group.actions[s]
            if not slot or not a then continue end
            slot:SetAttribute("ActionId",a.id);slot:SetAttribute("Enabled",a.enabled);slot:SetAttribute("Tone",a.tone)
            slot.Active=a.enabled;slot.Selectable=a.enabled
            slot.Label.Text=a.label;slot.Sub.Text=a.sub or ""
            if slot:GetAttribute("IconName")~=a.icon then
                local ok=Card.bindable(a.icon) and pcall(Icons.bind,slot.Icon,a.icon);slot.Icon.Visible=ok==true
                slot:SetAttribute("IconName",if ok then a.icon else nil)
            end
            self:paintSlot(slot)
        end
    end
    self:renderTitle()
    self:paintChrome()
end
function Card:paintSlot(slot: any)
    local enabled=slot:GetAttribute("Enabled")==true
    local color=Card.tone(slot:GetAttribute("Tone") :: string?,self.accent)
    local hovered=self.hovered[slot]==true
    slot.BackgroundColor3=if not enabled then DISABLED elseif hovered then Theme.Raised:Lerp(color,.16) else Theme.Raised
    slot.Border.Color=if hovered and enabled then color else Theme.Border
    slot.Border.Transparency=if enabled then .35 else .6
    slot.Icon.ImageColor3=color;slot.Icon.ImageTransparency=if enabled then 0 else .55
    slot.Label.TextColor3=if enabled then Theme.Text else Theme.Muted
    slot.Sub.TextColor3=if enabled then Theme.Muted else REASON
end
function Card:paintChrome()
    local close=self.card.Close
    close.Plate.BackgroundColor3=if self.hovered[close] then Theme.Raised:Lerp(Theme.Danger,.2) else Theme.Raised
    local give=self.card.Give
    give.Cancel.BackgroundColor3=if self.hovered[give.Cancel] then Theme.Raised:Lerp(Theme.Text,.1) else Theme.Raised
    local send=give.Send;local enabled=send:GetAttribute("Enabled")==true
    local accent=self.accent or Theme.Cobalt
    send.BackgroundColor3=if not enabled then DISABLED elseif self.hovered[send] then accent:Lerp(Theme.Text,.12) else accent
    send.Label.TextColor3=if enabled then Theme.Text else Theme.Muted
    send.Sub.TextColor3=if enabled then Theme.Text else REASON
end
-- The give preview on the target's troop meter: Gift reaches (their troops + what they get) / max.
function Card:paintGift()
    local meter=self.card.Troops:FindFirstChild("Meter");local gift=meter and meter:FindFirstChild("Gift")
    local gradient=gift and gift:FindFirstChildOfClass("UIGradient");if not gradient then return end
    local g=self.give;local bar=self.model and self.model.troopBar
    if self.view=="give" and g and g.mode=="troops" and bar and (g.theirMax or 0)>0 then
        gift.Visible=true;gradient.Offset=Vector2.new(math.clamp((g.theirs+g.sends)/g.theirMax,0,1)-.5,0)
    else gift.Visible=false end
end

-- ---------------------------------------------------------------- give view
function Card:renderGive(g: any,percent: number,active: number?)
    self.give=g;self.percent=percent;self.activePreset=active
    local give=self.card.Give
    give.Amount.Text=g.amountText
    give.Percent.Text=tostring(percent).."%"
    local troops=g.mode=="troops"
    local color=if troops then (self.accent or Theme.Cobalt) else Theme.Gold
    local track=give.Slider.Track
    track.Fill.BackgroundColor3=color;track.Thumb.Ring.Color=color
    track.Fill.Edge.Offset=Vector2.new(math.clamp(percent/100,0,1)-.5,0)
    track.Reserve.Visible=troops and g.reserveFraction>0
    track.Reserve.Edge.Offset=Vector2.new(math.clamp(1-g.reserveFraction,0,1)-.5,0)
    track.Room.Visible=g.roomFraction~=nil and g.roomFraction<1
    if g.roomFraction then track.Room.Position=UDim2.fromScale(g.roomFraction,.5) end
    track.Thumb.Position=UDim2.fromScale(math.clamp(percent/100,0,1),.5)
    give.Slider:SetAttribute("Enabled",g.total>0);give.Slider.Selectable=g.total>0
    give.Summary.Keep.Value.Text=g.keepText
    give.Summary.Get.Caption.Text=if g.roomText then "THEY GET · ROOM "..g.roomText else "THEY GET"
    give.Summary.Get.Value.Text="+"..g.amountText;give.Summary.Get.Value.TextColor3=if g.sends>0 then Theme.Positive else Theme.Muted
    give.Note.Text=g.note
    give.Capped.Text=g.capped or "";give.Capped.Visible=g.capped~=nil
    local send=give.Send;send:SetAttribute("Enabled",g.enabled);send.Active=g.enabled;send.Selectable=g.enabled
    send.Label.Text=if g.enabled then "Send "..g.amountText else "Send"
    send.Sub.Text=if g.enabled then (if troops then "troops" else "gold") else (g.reason or "")
    for pct,b in self.presets do b:SetAttribute("Enabled",g.total>0);b.Active=g.total>0;b.Selectable=g.total>0 end
    self:paintGive();self:paintChrome();self:paintGift();self:renderTitle()
end
function Card:paintGive()
    local accent=self.accent or Theme.Cobalt
    for pct,b in self.presets do
        local enabled=b:GetAttribute("Enabled")==true;local active=enabled and pct==self.activePreset
        b.BackgroundColor3=if not enabled then DISABLED elseif active then accent elseif self.hovered[b] then Theme.Raised:Lerp(accent,.16) else Theme.Raised
        b.Border.Color=if active then accent else Theme.Border
        b.Label.TextColor3=if enabled then Theme.Text else Theme.Muted
    end
end

-- ---------------------------------------------------------------- gamepad
-- Rows of selectable buttons for the current view; links Left/Right within a row and Up/Down to the
-- nearest button in the next row.
function Card:rows(): {{GuiObject}}
    local rows={}
    local function add(row: {GuiObject}) if #row>0 then table.insert(rows,row) end end
    add({self.card.Close})
    if self.view=="give" then
        local give=self.card.Give
        if give.Slider.Selectable then add({give.Slider}) end
        local presets={};for _,pct in {10,25,50,75,100} do local b=self.presets[pct];if b and b.Selectable then table.insert(presets,b) end end;add(presets)
        local buttons={give.Cancel};if give.Send.Selectable then table.insert(buttons,give.Send) end;add(buttons)
    else
        for g in Card.SLOTS do
            local node=self.card.Actions:FindFirstChild("Group"..g)
            if node and node.Visible then
                local row={};for _,entry in self.slots do if entry.group==g and entry.node.Selectable then table.insert(row,entry.node) end end;add(row)
            end
        end
    end
    return rows
end
function Card:link(): GuiObject?
    local rows=self:rows()
    for r,row in rows do
        for i,b in row do
            local o=b :: any
            o.NextSelectionLeft=row[math.max(1,i-1)];o.NextSelectionRight=row[math.min(#row,i+1)]
            local function nearest(other: {GuiObject}?): GuiObject
                if not other then return b end
                local x=b.AbsolutePosition.X+b.AbsoluteSize.X/2;local best,distance=other[1],math.huge
                for _,c in other do local d=math.abs(c.AbsolutePosition.X+c.AbsoluteSize.X/2-x);if d<distance then best,distance=c,d end end
                return best
            end
            o.NextSelectionUp=nearest(rows[r-1]);o.NextSelectionDown=nearest(rows[r+1])
        end
    end
    -- First focus: the slider while giving, else the first enabled action (else Close).
    if self.view=="give" then return if rows[2] then rows[2][1] else self.card.Close end
    return if rows[2] then rows[2][1] else self.card.Close
end
-- LB/RB: previous/next action group (actions view) or preset (give view).
function Card:cycle(direction: number): boolean
    if self.view=="give" then return false end
    local rows=self:rows();if #rows<2 then return false end
    local current=GuiService.SelectedObject;local at=1
    for r,row in rows do for _,b in row do if b==current then at=r end end end
    local nextRow=at+direction
    if nextRow<2 then nextRow=#rows elseif nextRow>#rows then nextRow=2 end
    GuiService.SelectedObject=rows[nextRow][1];return true
end
function Card:contains(object: Instance?): boolean return object~=nil and object:IsDescendantOf(self.card) end
return Card
