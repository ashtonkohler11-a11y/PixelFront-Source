--!strict
-- PF012/PF013: bottom-left notification stack. Alliance requests/renewals (Accept,
-- Decline, time-left bar, name focuses the camera) sit at the bottom; info
-- notices stack above them and auto-dismiss. It never sends commands itself:
-- callbacks.respond(row,accept) keeps the existing server commands.
-- Geometry is authored: the container fills Builder A's Game.PFNoticeRegion with
-- a bottom-aligned UIListLayout. PF018 (Ashton: "in a list ... snug in the bottom
-- left corner"): both cards are fixed-height glass rows in the attack rows' language
-- (tools/atlas/author-pf018-rows.luau): a semantic rail, an icon badge and a concise
-- message inside an inner Card (CanvasGroup). Code clones, fills, orders
-- (LayoutOrder), hides what no longer fits, and slides the Card in and out (unless
-- the player has reduced motion); it never writes the authored layout.
local Theme=require(script.Parent.BattleHudTheme)
local HudControls=require(script.Parent.BattleHudControls)
local Icons=require(script.Parent.ReferenceIcons)
local Card=require(script.Parent.CountryHoverCard)
local Model=require(script.Parent.HudInspectorModel)
local Emoji=require(script.Parent.DiplomacyEmoji)
local GuiService=game:GetService("GuiService")
local TweenService=game:GetService("TweenService")
local Stack={};Stack.__index=Stack
Stack.ENTER_SECONDS=.28
Stack.LEAVE_SECONDS=.2
local GLASS=Color3.fromRGB(13,16,21)
local URGENT=Color3.fromHex("#f5b942")
-- Parts may sit inside the authored Card (PF018) or directly in older flat cards.
local function part(ui: Instance,name: string): any return ui:FindFirstChild(name,true) end
local function card(ui: Instance): any return ui:FindFirstChild("Card") end
Stack.NOTICE_SECONDS=7
Stack.MAX_NOTICES=6
-- A request row narrower than this (a phone's 200 px column, two 40 px plates) shows the name alone; its badge carries the
-- alliance glyph on the nation's colour (author-notice-rows).
Stack.NARROW_REQUEST=260
-- The requester's name at the authored 12 px minimum (Typography.Font is the measuring face; +8% for the bold weight):
-- whole when it fits, else cut with an ellipsis, never hidden. Cached per name and width.
local TextService=game:GetService("TextService")
local fitCache: {[string]: string}={}
function Stack.fitName(text: string,width: number): string
    if width<=0 or text=="" then return text end
    local key=text.."|"..math.floor(width)
    if fitCache[key] then return fitCache[key] end
    local function wide(s: string): number return TextService:GetTextSize(s,12,Enum.Font.Ubuntu,Vector2.new(10000,100)).X*1.08 end
    local result=text
    if wide(text)>width then
        local chars={};for _,code in utf8.codes(text) do table.insert(chars,utf8.char(code)) end
        while #chars>1 and wide(table.concat(chars).."…")>width do table.remove(chars) end
        result=table.concat(chars).."…"
    end
    fitCache[key]=result
    return result
end
local GLYPHS={ALLIANCE_ACCEPTED="DiplomacyAlliance",ALLIANCE_REQUEST="DiplomacyAlliance",ALLIANCE_EXPIRED="DiplomacyAlliance",RENEW_ALLIANCE="DiplomacyAlliance",
    ALLIANCE_REJECTED="DiplomacyBreak",ALLIANCE_BROKEN="DiplomacyBreak",DONATION_RECEIVED="DiplomacyDonateTroops",DONATION_SENT="DiplomacyDonateTroops",
    ATTACK_REQUEST="DiplomacyTarget",CHAT="QuickChat"}
function Stack.tone(kind: string): string
    if kind=="ALLIANCE_ACCEPTED" or kind=="DONATION_RECEIVED" or kind=="POSITIVE" then return "positive" end
    if kind=="ALLIANCE_REJECTED" or kind=="ALLIANCE_BROKEN" or kind=="ELIMINATED_YOU" or kind=="DANGER" then return "danger" end
    if kind=="ALLIANCE_EXPIRED" or kind=="RENEW_ALLIANCE" or kind=="WARNING" then return "warning" end
    return "accent"
end
function Stack.glyph(kind: string): string return GLYPHS[kind] or "DiplomacyInfo" end
-- PF - 4 notices v2 (Ashton "Good, build it" 2026-10-26; tools/atlas/author-pf4-notices-v2.luau; the templates carry
-- PFNoticeV2): one toast language. Four tones (the cobalt "accent" reads as grey Info), each with its own life; the life bar is
-- the clock (hover pauses it), the feed keeps 3, older toasts sit at 55%, enter = 8 px up + fade, leave = fade.
Stack.V2={
    positive={fg=Color3.fromHex("#ffd36a"),tile=Color3.fromHex("#3a2c0c"),life=Color3.fromHex("#ffd36a"),seconds=5},
    warning={fg=Color3.fromHex("#ffb067"),tile=Color3.fromHex("#3a2f12"),life=Color3.fromHex("#ffb067"),seconds=7},
    danger={fg=Color3.fromHex("#ff9d92"),tile=Color3.fromHex("#3a1c22"),life=Color3.fromHex("#ff6a5a"),seconds=7},
    info={fg=Color3.fromHex("#c9cdd8"),tile=Color3.fromHex("#2a2f3b"),life=Color3.fromHex("#5b6378"),seconds=4},
}
Stack.V2_FEED=3
Stack.V2_OLDER=.45 -- an older toast's GroupTransparency (55% opacity)
Stack.V2_ENTER=.15
Stack.V2_LEAVE=.2
local RING_OK,RING_LATE=Color3.fromHex("#58b85c"),URGENT
function Stack.toneV2(kind: string): string
    local tone=Stack.tone(kind);return if tone=="accent" then "info" else tone
end
local function escape(text: string): string return (string.gsub(string.gsub(string.gsub(text,"&","&amp;"),"<","&lt;"),">","&gt;")) end
-- the ring timer: two half-clips whose stroke gradients turn; left = the fraction of time left (1 = full ring)
function Stack.ring(ring: Instance?,left: number,color: Color3)
    if not ring then return end
    left=math.clamp(left,0,1)
    local right,leftHalf=ring:FindFirstChild("Right"),ring:FindFirstChild("Left")
    for _,clip in {right,leftHalf} do
        local line=clip and clip:FindFirstChild("Line",true);if line and line:IsA("UIStroke") then line.Color=color end
    end
    local function turn(clip: Instance?,rotation: number)
        local sweep=clip and clip:FindFirstChild("Sweep",true);if sweep and sweep:IsA("UIGradient") then sweep.Rotation=rotation end
    end
    turn(right,math.min(left,.5)*360);turn(leftHalf,180+math.max(0,left-.5)*360)
end
-- keyboard keycaps only (touch taps, a pad focuses the buttons)
local UserInputService=game:GetService("UserInputService")
local function keyboard(): boolean
    local last=UserInputService:GetLastInputType()
    return last~=Enum.UserInputType.Touch and not string.find(last.Name,"Gamepad")
end
-- PF019 W7 S5 Alerts: "all" (default) | "important" (danger to you: invasions/attacks and
-- inbound nukes arrive as DANGER, plus betrayals) | "off" (no notices). Request and renewal
-- cards are interactive prompts, not notices, and are never filtered here.
local IMPORTANT={DANGER=true,ALLIANCE_BROKEN=true,ELIMINATED_YOU=true}
function Stack.allows(kind: string?,alerts: any): boolean
    if alerts=="off" then return false end
    return alerts~="important" or IMPORTANT[kind or ""]==true
end

function Stack.new(container: Frame,templates: Instance,callbacks: any): any
    local self=setmetatable({container=container,templates=templates,requestTemplate=templates:FindFirstChild("PFNoticeRequest"),infoTemplate=templates:FindFirstChild("PFNoticeInfo"),
        callbacks=callbacks or {},requests={},requestOrder={},notices={},nextId=0,enabled=false,shownItems={},destroyed=false},Stack)
    assert(self.requestTemplate and self.infoTemplate,"Missing PF012 notification templates")
    container.Visible=false
    self.v2=self.infoTemplate:GetAttribute("PFNoticeV2")~=nil
    if self.v2 then
        -- each tone has its own life: the stack checks its own clock (callbacks.changed re-lays the HUD)
        task.spawn(function()
            while not self.destroyed do
                task.wait(.25)
                if not self.destroyed and #self.notices>0 and self:expire() and self.callbacks.changed then self.callbacks.changed() end
            end
        end)
        -- Y / N answer the request nearest the corner
        self.keyConnection=UserInputService.InputBegan:Connect(function(input,processed)
            if processed or (input.KeyCode~=Enum.KeyCode.Y and input.KeyCode~=Enum.KeyCode.N) or not self:inputAllowed() then return end
            for _,row in self.requestOrder do
                local card=self.requests[row.key]
                if card and card.shown and self.callbacks.respond then self.callbacks.respond(card.row,input.KeyCode==Enum.KeyCode.Y);break end
            end
        end)
    end
    return self
end
function Stack:now(): number return if self.callbacks.now then self.callbacks.now() else os.clock() end
function Stack:motion(): boolean
    return not self.destroyed and not (self.callbacks.reducedMotion and self.callbacks.reducedMotion())
end
-- GroupTransparency does not reach the Card's own UIStroke, so its Edge fades alongside.
local function edgeRest(inner: Instance): (any,number)
    local edge=inner:FindFirstChild("Edge")
    if not edge or not edge:IsA("UIStroke") then return nil,0 end
    local rest=edge:GetAttribute("PF018Rest")
    if type(rest)~="number" then rest=edge.Transparency;edge:SetAttribute("PF018Rest",rest) end
    return edge,rest
end
-- Slide the inner Card in from the corner and fade it up (first time it is shown).
function Stack:enter(item: any)
    local inner=card(item.ui);if not inner or item.entered then return end
    item.entered=true
    local edge,rest=edgeRest(inner)
    if self.v2 then
        -- v2: rise 8 px and fade up to its place in the feed (an older toast stops at 55%)
        local goal=item.alpha or 0
        if not self:motion() then inner.Position=UDim2.new();(inner :: any).GroupTransparency=goal;if edge then edge.Transparency=rest end;return end
        inner.Position=UDim2.fromOffset(0,8);(inner :: any).GroupTransparency=1
        local info=TweenInfo.new(Stack.V2_ENTER,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        TweenService:Create(inner,info,{Position=UDim2.new(),GroupTransparency=goal}):Play()
        if edge then edge.Transparency=1;TweenService:Create(edge,info,{Transparency=rest}):Play() end
        if edge and item.kind=="request" then
            local pulse=TweenInfo.new(.32,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true,Stack.V2_ENTER)
            TweenService:Create(edge,pulse,{Thickness=edge.Thickness+1.5,Transparency=0}):Play()
        end
        return
    end
    if not self:motion() then inner.Position=UDim2.new();if inner:IsA("CanvasGroup") then inner.GroupTransparency=0 end;if edge then edge.Transparency=rest end;return end
    inner.Position=UDim2.fromScale(-1.06,0);if inner:IsA("CanvasGroup") then inner.GroupTransparency=1 end
    local props: any={Position=UDim2.new()};if inner:IsA("CanvasGroup") then props.GroupTransparency=0 end
    local info=TweenInfo.new(Stack.ENTER_SECONDS,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    TweenService:Create(inner,info,props):Play()
    if edge then edge.Transparency=1;TweenService:Create(edge,info,{Transparency=rest}):Play() end
    -- An alliance request lands with one soft pulse after the slide: its own edge thickens and brightens once
    -- (a tight glow on the card, no particles), then settles.
    if edge and item.kind=="request" then
        local pulse=TweenInfo.new(.32,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true,Stack.ENTER_SECONDS)
        TweenService:Create(edge,pulse,{Thickness=edge.Thickness+2.5,Transparency=0}):Play()
    end
end
-- Slide out and fade, then destroy (instantly without motion). Cards are AutomaticSize-Y,
-- so the list closes the gap when the card goes.
function Stack:leave(ui: Instance)
    local inner=card(ui)
    if not inner or not self:motion() or not (ui :: any).Visible then ui:Destroy();return end
    ui.Name=ui.Name.."_Leaving";(ui :: any).Active=false;(ui :: any).Selectable=false
    local props: any={Position=UDim2.fromScale(-1.06,0)};if inner:IsA("CanvasGroup") then props.GroupTransparency=1 end
    if self.v2 then props={GroupTransparency=1} end -- v2: leave = fade in place
    local info=TweenInfo.new(if self.v2 then Stack.V2_LEAVE else Stack.LEAVE_SECONDS,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
    local edge=edgeRest(inner);if edge then TweenService:Create(edge,info,{Transparency=1}):Play() end
    local slide=TweenService:Create(inner,info,props)
    slide.Completed:Connect(function() if ui.Parent then ui:Destroy() end end)
    slide:Play()
end
function Stack:accent(): Color3? return if self.callbacks.accent then self.callbacks.accent() else nil end
function Stack:inputAllowed(): boolean
    return not self.destroyed and HudControls.visible(self.container) and (not self.callbacks.inputAllowed or self.callbacks.inputAllowed())
end
local function hoverPaint(button: any,rest: () -> Color3)
    local connections={}
    table.insert(connections,button.MouseEnter:Connect(function() if button.Active then button.BackgroundColor3=rest():Lerp(Theme.Text,.12) end end))
    table.insert(connections,button.MouseLeave:Connect(function() button.BackgroundColor3=rest() end))
    return connections
end
function Stack:disconnect(item: any)
    for _,connection in item.connections or {} do connection:Disconnect() end
    item.connections={}
end
-- A removed card hands gamepad focus to the next live control in the stack.
function Stack:release(ui: Instance)
    local selected=GuiService.SelectedObject
    if selected and (selected==ui or selected:IsDescendantOf(ui)) then
        GuiService.SelectedObject=nil
        self.focusPending=true
    end
end

function Stack:createRequest(row: any): any
    local ui=self.requestTemplate:Clone();ui.Name="Request_"..row.key;ui.Visible=false;ui.Parent=self.container
    -- Accept is the primary action: interface accent fill, never the neutral HUD repaint.
    local accept,decline=part(ui,"Accept"),part(ui,"Decline")
    if not self.v2 then accept.BackgroundColor3=self:accent() or Theme.Cobalt;accept.BackgroundTransparency=0 end
    local name=part(ui,"Name")
    local card={ui=ui,row=row,kind="request",connections={}}
    local allowed=function() return self:inputAllowed() end
    local function respond(accept: boolean) if self.callbacks.respond and card.row then self.callbacks.respond(card.row,accept) end end
    table.insert(card.connections,accept.Activated:Connect(HudControls.guardedAction(accept,allowed,function() respond(true) end)))
    table.insert(card.connections,decline.Activated:Connect(HudControls.guardedAction(decline,allowed,function() respond(false) end)))
    table.insert(card.connections,name.Activated:Connect(HudControls.guardedAction(name,allowed,function()
        if self.callbacks.focusOwner and card.row then self.callbacks.focusOwner(card.row.owner) end
    end)))
    -- v2: each button keeps its own authored fill (PFRest) and lifts on hover
    local function rest(button: any,fallback: Color3): () -> Color3
        return function() local v=button:GetAttribute("PFRest");return if typeof(v)=="Color3" then v else fallback end
    end
    for _,connection in hoverPaint(accept,if self.v2 then rest(accept,Theme.Raised) else function() return self:accent() or Theme.Cobalt end) do table.insert(card.connections,connection) end
    for _,connection in hoverPaint(decline,if self.v2 then rest(decline,Theme.Raised) else function() return Theme.Raised end) do table.insert(card.connections,connection) end
    local nameRest=name.TextColor3
    table.insert(card.connections,name.MouseEnter:Connect(function() name.TextColor3=self:accent() or Theme.Cobalt end))
    table.insert(card.connections,name.MouseLeave:Connect(function() name.TextColor3=if self.v2 then nameRest else Theme.Text end))
    self.requests[row.key]=card
    return card
end
function Stack:paintRequestV2(card: any,ticks: number)
    local row=card.row;local ui=card.ui;local name=part(ui,"Name")
    name.Text=row.name;name:SetAttribute("SourceTooltip","Show "..row.name.." on the map")
    -- the flag chip: the nation's colour + a lighter diamond (a PixelFront mark)
    local flag=part(ui,"Dot");local color=row.color or Theme.Muted
    flag.BackgroundColor3=color
    local emblem=flag:FindFirstChild("Emblem");if emblem then emblem.BackgroundColor3=color:Lerp(Color3.new(1,1,1),.65) end
    part(ui,"Message").Text=row.message
    local accept,decline=part(ui,"Accept"),part(ui,"Decline")
    accept.Label.Text=row.acceptText;decline.Label.Text=row.declineText
    local caps=keyboard();accept.Cap.Visible=caps;decline.Cap.Visible=caps
    accept:SetAttribute("ActionDescription",row.acceptText.." · "..row.name);decline:SetAttribute("ActionDescription",row.declineText.." · "..row.name)
    local total=math.max(1,row.endTick-row.startTick);local left=math.clamp(row.endTick-ticks,0,total)
    local late=left<=50 -- the last 5 s read amber
    Stack.ring(part(ui,"Ring"),left/total,if late then RING_LATE else RING_OK)
    local timer=part(ui,"Timer");timer.Text=math.ceil(left/10).."s";timer.TextColor3=if late then URGENT else Theme.Text
    ui:SetAttribute("Owner",row.owner);ui:SetAttribute("RequestKind",row.kind);ui:SetAttribute("SecondsLeft",math.ceil(left/10))
end
function Stack:paintRequest(card: any,ticks: number)
    if self.v2 then self:paintRequestV2(card,ticks);return end
    local row=card.row;local ui=card.ui;local name=part(ui,"Name")
    name.Text=row.name;name:SetAttribute("SourceTooltip","Show "..row.name.." on the map")
    local dot=part(ui,"Dot");dot.Visible=row.color~=nil;if row.color then dot.BackgroundColor3=row.color end
    local message=part(ui,"Message");message.Text=row.message
    local width=ui.AbsoluteSize.X;message.Visible=width<=0 or width>=Stack.NARROW_REQUEST
    -- a phone row (< 260 px): no badge (the rail carries the colour), the name at 13 px so it stays readable (it truncates
    -- with an ellipsis rather than hide; author-notice-rows v3 lays the plates out at 34)
    local narrow=width>0 and width<Stack.NARROW_REQUEST
    local holder=part(ui,"BadgeHolder");if holder then holder.Visible=not narrow end
    name.Text=Stack.fitName(row.name,name.AbsoluteSize.X) -- the authored name scales 16 → 12; past 12 it ellipsises
    local accept,decline=part(ui,"Accept"),part(ui,"Decline")
    accept.Text=row.acceptText;decline.Text=row.declineText
    accept:SetAttribute("ActionDescription",row.acceptText.." · "..row.name);decline:SetAttribute("ActionDescription",row.declineText.." · "..row.name)
    local total=math.max(1,row.endTick-row.startTick);local left=math.clamp(row.endTick-ticks,0,total)
    -- The bar fill is a value readout (fraction of the authored track), not layout.
    part(ui,"Bar").Fill.Size=UDim2.fromScale(left/total,1)
    part(ui,"Bar").Fill.BackgroundColor3=if left<=50 then URGENT else self:accent() or Theme.Cobalt -- the last 5 s read amber (a notice row's clock is its bar)
    local timer=part(ui,"Timer");timer.Text=Model.clock(math.ceil(left/10))
    timer.TextColor3=if left<=50 then URGENT else Theme.Text -- the last 5 s read amber
    ui:SetAttribute("Owner",row.owner);ui:SetAttribute("RequestKind",row.kind);ui:SetAttribute("SecondsLeft",math.ceil(left/10))
end
-- rows: ordered {key, owner, kind, name, color?, message, acceptText, declineText, startTick, endTick}
function Stack:setRequests(rows: {any},ticks: number)
    local active={}
    for index,row in rows do
        active[row.key]=true
        local card=self.requests[row.key] or self:createRequest(row)
        card.row=row;card.order=index;self:paintRequest(card,ticks)
    end
    for key,card in self.requests do
        if not active[key] then self:release(card.ui);self:disconnect(card);self:leave(card.ui);self.requests[key]=nil end
    end
    self.requestOrder=table.clone(rows)
end
function Stack:removeRequest(key: string)
    local card=self.requests[key];if not card then return end
    self:release(card.ui);self:disconnect(card);self:leave(card.ui);self.requests[key]=nil
    for index,row in self.requestOrder do if row.key==key then table.remove(self.requestOrder,index);break end end
end

-- notice: {text, kind, focus?, emoji?, glyph?, template?, paint?}; newest first. Roadmap #1: template names another info row in
-- Templates (PFNoticeDaily), paint(ui) fills its extra parts, glyph=false keeps the template's own glyph.
-- v2 toast: the tone paints the icon tile, its glyph, the value and the life bar; notice.rich (RichText) or notice.text;
-- notice.key = a keycap ("1": the build slot that acts on it), keyboard only.
function Stack:pushV2(notice: any): any
    self.nextId+=1
    local tone=Stack.toneV2(notice.kind or "");local look=Stack.V2[tone]
    local record={id=self.nextId,text=notice.text,detail=notice.detail,kind=notice.kind or "",focus=notice.focus,emoji=notice.emoji,glyph=notice.glyph,
        born=self:now(),connections={},tone=tone,life=look.seconds,paused=0}
    local template=type(notice.template)=="string" and self.templates and self.templates:FindFirstChild(notice.template) or self.infoTemplate
    local ui=template:Clone();ui.Name="Notice_"..record.id;ui.Visible=false;ui.Parent=self.container;record.ui=ui
    local message=part(ui,"Message")
    if message then message.Text=if type(notice.rich)=="string" then notice.rich elseif message.RichText then escape(record.text) else record.text end
    local tile=part(ui,"Tile");if tile then tile.BackgroundColor3=look.tile end
    local detail=part(ui,"Detail")
    if detail then detail.Visible=record.detail~=nil;detail.Text=record.detail or "";detail.TextColor3=look.fg end
    local key=part(ui,"Key");if key then key.Visible=type(notice.key)=="string" and keyboard();key.Text=notice.key or "" end
    local glyphNode=part(ui,"Glyph")
    if glyphNode and record.glyph~=false then
        local ok=pcall(function() Icons.bindWhite(glyphNode,record.glyph or Stack.glyph(record.kind)) end)
        glyphNode.Visible=ok;glyphNode.ImageColor3=look.fg
    end
    local index=if record.emoji then table.find(Emoji,record.emoji) else nil
    local emoji=part(ui,"Emoji")
    if emoji then emoji.Visible=false
        if index then local bound=pcall(function() Icons.bind(emoji,"DiplomacyEmoji"..(index-1)) end);emoji.Visible=bound;if glyphNode and bound then glyphNode.Visible=false end end
    end
    local lifeBar=part(ui,"Life");if lifeBar then lifeBar.BackgroundColor3=look.life end
    if type(notice.paint)=="function" then pcall(notice.paint,ui) end
    ui.Selectable=record.focus~=nil;ui.Active=true
    ui:SetAttribute("NoticeKind",record.kind);ui:SetAttribute("Tone",tone);ui:SetAttribute("Focus",record.focus)
    table.insert(record.connections,ui.Activated:Connect(HudControls.guardedAction(ui,function() return self:inputAllowed() end,function()
        if record.focus and self.callbacks.focusOwner then self.callbacks.focusOwner(record.focus) end
    end)))
    -- hover lifts the card and holds its clock (the life bar stops)
    local paintTarget=card(ui) or ui;local rest=paintTarget.BackgroundColor3
    table.insert(record.connections,ui.MouseEnter:Connect(function()
        paintTarget.BackgroundColor3=rest:Lerp(Theme.Text,.08)
        if not record.pauseStart then record.pauseStart=self:now();if record.lifeTween then record.lifeTween:Pause() end end
    end))
    table.insert(record.connections,ui.MouseLeave:Connect(function()
        paintTarget.BackgroundColor3=rest
        if record.pauseStart then record.paused+=self:now()-record.pauseStart;record.pauseStart=nil;if record.lifeTween then record.lifeTween:Play() end end
    end))
    local edge=lifeBar and lifeBar:FindFirstChildOfClass("UIGradient")
    if edge then
        edge.Offset=Vector2.new(.5,0)
        record.lifeTween=TweenService:Create(edge,TweenInfo.new(record.life,Enum.EasingStyle.Linear),{Offset=Vector2.new(-.5,0)})
        record.lifeTween:Play()
    end
    table.insert(self.notices,1,record)
    while #self.notices>Stack.V2_FEED do self:dropNotice(self.notices[#self.notices]) end
    return record
end
function Stack:push(notice: any): any
    if self.v2 then return self:pushV2(notice) end
    self.nextId+=1
    local record={id=self.nextId,text=notice.text,detail=notice.detail,kind=notice.kind or "",focus=notice.focus,emoji=notice.emoji,glyph=notice.glyph,born=self:now(),connections={}}
    local template=type(notice.template)=="string" and self.templates and self.templates:FindFirstChild(notice.template) or self.infoTemplate
    local ui=template:Clone();ui.Name="Notice_"..record.id;ui.Visible=false;ui.Parent=self.container;record.ui=ui
    part(ui,"Message").Text=record.text
    local tone=Stack.tone(record.kind);record.tone=tone
    local color=if tone=="accent" then self:accent() or Theme.Cobalt else Card.toneColor(tone)
    -- PF018 v2 (MM): the key number (troops, gold) gets its own emphasised line so a narrow
    -- card never ellipsizes it; older cards without a Detail line fold it into the message.
    local detail=part(ui,"Detail")
    if detail then
        detail.Visible=record.detail~=nil;detail.Text=record.detail or "";detail.TextColor3=color
        if tone=="accent" then detail:SetAttribute("PFAccentText","text") end
    elseif record.detail then part(ui,"Message").Text=record.text.." · "..record.detail end
    -- Severity tint: rail, the card's edge, the badge disc and its glyph.
    local rail,edge,badge=part(ui,"Rail"),part(ui,"Edge"),part(ui,"Badge")
    rail.BackgroundColor3=color
    if edge then edge.Color=color end
    if badge and badge:GetAttribute("PF018Tinted") then badge.BackgroundColor3=color end
    if tone=="accent" then rail:SetAttribute("PFAccentBackground","accent");if edge then edge:SetAttribute("PFAccentStroke","accent") end end
    local glyphNode=badge.Glyph
    if record.glyph~=false then
        local ok=pcall(function() Icons.bindWhite(glyphNode,record.glyph or Stack.glyph(record.kind)) end)
        glyphNode.Visible=ok;glyphNode.ImageColor3=color
    end
    if tone=="accent" then glyphNode:SetAttribute("PFAccentImage","accent") end
    local index=if record.emoji then table.find(Emoji,record.emoji) else nil
    local emoji=part(ui,"Emoji");emoji.Visible=false
    if index then local bound=pcall(function() Icons.bind(emoji,"DiplomacyEmoji"..(index-1)) end);emoji.Visible=bound end
    if type(notice.paint)=="function" then pcall(notice.paint,ui) end
    ui.Selectable=record.focus~=nil;ui.Active=true
    ui:SetAttribute("NoticeKind",record.kind);ui:SetAttribute("Tone",tone);ui:SetAttribute("Focus",record.focus)
    table.insert(record.connections,ui.Activated:Connect(HudControls.guardedAction(ui,function() return self:inputAllowed() end,function()
        if record.focus and self.callbacks.focusOwner then self.callbacks.focusOwner(record.focus) end
    end)))
    -- Hover lifts the painted card (PF018 Card, or the flat card's own fill).
    local paintTarget=card(ui) or ui
    local rest=if card(ui) then GLASS else Theme.Panel
    table.insert(record.connections,ui.MouseEnter:Connect(function() paintTarget.BackgroundColor3=rest:Lerp(Theme.Text,.08) end))
    table.insert(record.connections,ui.MouseLeave:Connect(function() paintTarget.BackgroundColor3=rest end))
    table.insert(self.notices,1,record)
    while #self.notices>Stack.MAX_NOTICES do self:dropNotice(self.notices[#self.notices]) end
    return record
end
function Stack:dropNotice(record: any)
    local index=table.find(self.notices,record);if index then table.remove(self.notices,index) end
    if record.lifeTween then record.lifeTween:Cancel();record.lifeTween=nil end
    if record.ui then self:release(record.ui);self:disconnect(record);self:leave(record.ui);record.ui=nil end
end
-- Removes notices past their lifetime; returns true when anything changed. v2: each tone's own life, less hovered time,
-- and a hovered toast never leaves.
function Stack:expire(): boolean
    local now=self:now();local changed=false
    for index=#self.notices,1,-1 do
        local record=self.notices[index]
        local done=if record.life then not record.pauseStart and now-record.born-record.paused>=record.life else now-record.born>=Stack.NOTICE_SECONDS
        if done then self:dropNotice(record);changed=true end
    end
    return changed
end
-- PF019 W7 S5: a lowered Alerts setting also drops shown notices it no longer allows.
function Stack:prune(alerts: any): boolean
    local changed=false
    for index=#self.notices,1,-1 do local record=self.notices[index];if not Stack.allows(record.kind,alerts) then self:dropNotice(record);changed=true end end
    return changed
end
function Stack:setEnabled(value: boolean) self.enabled=value end
-- Bottom-up order: requests (priority order) nearest the bottom, then notices
-- newest first. The authored bottom-aligned UIListLayout places them; an item
-- whose authored height no longer fits in the region is hidden (requests win).
-- Returns the number of items shown.
function Stack:refresh(): number
    local container=self.container
    local items={}
    for _,row in self.requestOrder do local card=self.requests[row.key];if card then table.insert(items,card) end end
    for _,record in self.notices do if record.ui then table.insert(items,record) end end
    self.shownItems={}
    if not self.enabled or #items==0 then
        container.Visible=false
        for _,item in items do item.ui.Visible=false end
        self:link(items);return 0
    end
    local layout=container:FindFirstChildOfClass("UIListLayout")
    local gap=if layout then layout.Padding.Offset else 0
    local room=container.AbsoluteSize.Y;local used=0;local full=false
    local newest=self.notices[1]
    for index,item in items do
        local ui=item.ui
        ui.LayoutOrder=#items-index+1
        -- v2: the newest toast (nearest the requests) at full strength, the older ones at 55%
        if self.v2 and item.kind~="request" then
            local alpha=if item==newest then 0 else Stack.V2_OLDER
            if item.alpha~=alpha then
                item.alpha=alpha
                local inner=card(ui)
                if item.entered and inner and inner:IsA("CanvasGroup") then
                    if self:motion() then TweenService:Create(inner,TweenInfo.new(Stack.V2_ENTER),{GroupTransparency=alpha}):Play() else inner.GroupTransparency=alpha end
                end
            end
        end
        local height=ui.AbsoluteSize.Y
        if full or (room>0 and used+height>room) then full=true;ui.Visible=false;item.shown=false;continue end
        ui.Visible=true;item.shown=true;used+=height+gap
        self:enter(item)
        table.insert(self.shownItems,item)
    end
    container.Visible=#self.shownItems>0
    self:link(items)
    return #self.shownItems
end
-- Gamepad graph: top card first, Name → Accept ↔ Decline inside a request.
function Stack:link(items: {any})
    local buttons={}
    for index=#items,1,-1 do
        local item=items[index];local ui=item.ui
        if not item.shown then
            for _,control in {part(ui,"Name"),part(ui,"Accept"),part(ui,"Decline")} do if control then HudControls.clearLinks(control) end end
            if item.kind~="request" then HudControls.clearLinks(ui) end
            continue
        end
        if item.kind=="request" then for _,name in {"Name","Accept","Decline"} do table.insert(buttons,{control=part(ui,name),card=ui}) end
        elseif ui.Selectable then table.insert(buttons,{control=ui,card=ui}) end
    end
    for index,entry in buttons do
        local control=entry.control;HudControls.clearLinks(control)
        local previous=buttons[index-1];local following=buttons[index+1]
        control.NextSelectionUp=if previous then previous.control else control
        control.NextSelectionDown=if following then following.control else control
        control.NextSelectionLeft=control;control.NextSelectionRight=control
    end
    for _,entry in buttons do
        if entry.control.Name=="Accept" then local decline=part(entry.card,"Decline");entry.control.NextSelectionRight=decline;decline.NextSelectionLeft=entry.control end
    end
    self.buttons=buttons
    if self.focusPending then
        self.focusPending=false
        if self.callbacks.gamepad and self.callbacks.gamepad() and GuiService.SelectedObject==nil and self:inputAllowed() then
            for index=#buttons,1,-1 do local control=buttons[index].control;if HudControls.available(control) then GuiService.SelectedObject=control;break end end
        end
    end
end
-- Real occupied rect relative to origin (read from the authored layout) for
-- the hover card's avoidance; nil when nothing is shown.
function Stack:occupied(origin: Vector2): any?
    local box=nil
    for _,item in self.shownItems do
        local p=item.ui.AbsolutePosition-origin;local s=item.ui.AbsoluteSize
        if s.X>0 and s.Y>0 then
            box=if box then Model.rect(math.min(box.x0,p.X),math.min(box.y0,p.Y),math.max(box.x1,p.X+s.X),math.max(box.y1,p.Y+s.Y)) else Model.rect(p.X,p.Y,p.X+s.X,p.Y+s.Y)
        end
    end
    return box
end
-- Height actually used (shown cards plus gaps), read from the authored layout.
function Stack:usedHeight(): number
    local zone=self:occupied(Vector2.zero)
    return if zone then zone.y1-zone.y0 else 0
end
function Stack:counts(): (number,number)
    local requests=0;for _ in self.requests do requests+=1 end
    return requests,#self.notices
end
function Stack:reset()
    for _,request in self.requests do self:release(request.ui);self:disconnect(request);request.ui:Destroy() end
    for _,record in self.notices do if record.ui then self:release(record.ui);self:disconnect(record);record.ui:Destroy();record.ui=nil end end
    for _,child in self.container:GetChildren() do if string.sub(child.Name,-8)=="_Leaving" then child:Destroy() end end
    self.requests={};self.requestOrder={};self.notices={};self.shownItems={};self.container.Visible=false;self.focusPending=false
end
function Stack:destroy()
    if self.destroyed then return end
    if self.keyConnection then self.keyConnection:Disconnect();self.keyConnection=nil end
    self:reset();self.destroyed=true
end
return Stack
