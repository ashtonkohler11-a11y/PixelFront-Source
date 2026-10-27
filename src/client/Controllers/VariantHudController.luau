--!strict
-- Source DoomsdayClockPanel/OvertimePanel readouts and GameRightSidebar timer cues.
local P=require(script.Parent.VariantHudPresentation)
local Data=require(script.Parent.VariantHudData)
local Icons=require(script.Parent.ReferenceIcons)
local Pulse=require(script.Parent.VariantHudPulse)
local TextService=game:GetService("TextService")
local WeightedText=require(script.Parent.BattleHudWeightedText)
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Battle=require(script.Parent.BattleHudTheme)
local Theme=table.clone(require(game:GetService("ReplicatedStorage").Shared.Theme))
Theme.Panel=Battle.Panel;Theme.PanelRaised=Battle.Raised;Theme.Accent=Battle.Cobalt
Theme.Text=Battle.Text;Theme.MutedText=Battle.Muted;Theme.Gold=Battle.Gold;Theme.Danger=Battle.Danger;Theme.Font=Battle.Font
local H={};H.__index=H
local colors=table.clone(Data.colors)
colors["gray-800"]=Battle.Panel;colors["gray-600"]=Battle.Raised;colors["gray-500"]=Battle.Border
colors["gray-400"]=Battle.Muted;colors["gray-300"]=Battle.Muted;colors["gray-200"]=Battle.Text;colors.white=Battle.Text
-- PF013: one composition, so the clock keeps its desktop chrome on every device.
local function clockChrome(_ui: Frame,panel: GuiObject)
    local compact=false
    panel.BackgroundTransparency=panel:GetAttribute("PFRestTransparency") or .04
    local image=panel:FindFirstChild("SourceBackground")
    if image and image:IsA("ImageLabel") then
        if image:GetAttribute("PFHudDesktopVisible")==nil then image:SetAttribute("PFHudDesktopVisible",image.Visible) end
        image.Visible=if compact then false else image:GetAttribute("PFHudDesktopVisible")
    end
end
-- PF013: the game time moved into the top-left icon bar's pill (authored, in the
-- icons' disc colour); the legacy Header.Clock/ClockPanel otherwise.
local function clockNodes(ui: Frame): (TextLabel,GuiObject?)
    local bar=ui:FindFirstChild("PFIconBar");local time=bar and bar:FindFirstChild("Time")
    local label=time and time:FindFirstChild("Clock")
    if label and label:IsA("TextLabel") then return label,time :: GuiObject end
    return ui.Header.Clock,ui:FindFirstChild("ClockPanel") :: GuiObject?
end
local function restColor(panel: GuiObject): Color3 return panel:GetAttribute("PFRestColor") or Theme.Panel end
local function listen(self: any,signal: RBXScriptSignal,callback: any)table.insert(self.connections,signal:Connect(function(...)if not self.destroyed then callback(...)end end))end
function H:measureText(label: any,text: string?,textSize: number?,constraint: Vector2?): Vector2
    if not self.weightedText then
        self.weightedText=WeightedText.new(function()
            if not self.destroyed and self.ui.Parent and self.state then self:layout() end
        end,512)
    end
    return self.weightedText:measure(text or label.Text,textSize or label.TextSize,(constraint or Vector2.new(10000,10000)).X,label.FontFace)
end
local function width(self: any,label: any,text: string?): number
    return self:measureText(label,text).X
end
local function textClass(label: TextLabel,class: string)
    local name=string.match(class,"text%-([%w]+%-%d+)");label.TextColor3=if name then colors[name]else colors.white
    Battle.Typography.apply(label,if string.find(class,"font-bold",1,true)then "Value" else "Label")
end
local function showBar(panel: ImageLabel,model: any,color: Color3)
    panel.Bar.Fill.Size=UDim2.fromScale(model.fillPercent/100,1);panel.Bar.Fill.BackgroundColor3=color
    panel.Bar.Threshold.Position=UDim2.fromScale(model.thresholdPercent/100,0)
end
-- PF-041 (PF - 1; Ashton: "Good, build"): when the clock rows are authored (Doomsday.PFClock / Overtime.PFClock,
-- tools/atlas/author-pf041.luau) each is a meter and ONE number. Doomsday: your land (the fill) against the line (the white
-- tick) on a zoomed scale; stable green, rising amber (an arrow on the line, a ghost tick where it is heading), danger red
-- (a red rim and halo). Overtime: the leader's land toward the gold win line; gold with a crown when it is you. The source
-- readouts stay authored (MatchController validates them) and are hidden.
local CLOCK={green=Color3.fromHex("#4ade80"),amber=Color3.fromHex("#facc15"),red=Color3.fromHex("#f87171"),gold=Color3.fromHex("#ffd77a"),white=Color3.fromHex("#e9e9ea"),cobalt=Color3.fromHex("#5b8cff"),muted=Color3.fromHex("#8f96a0")}
local GLYPH_X={skull=0,crown=56,flag=112}
local function hideSource(row: Instance)
    for _,name in {"Header","Share","Bar","Detail","PulseMask"} do local n=row:FindFirstChild(name);if n and n:IsA("GuiObject") then n.Visible=false end end
end
local function paintClock(clock: Instance,o: {fill: number,line: number,ghost: number?,arrow: boolean,color: Color3,tint: Color3,rim: Color3?,glow: boolean,value: string,valueColor: Color3,glyph: string})
    local meter=clock:FindFirstChild("Meter");local badge=clock:FindFirstChild("Badge");local glass=clock:FindFirstChild("Glass")
    if meter then
        local fill=meter:FindFirstChild("Fill");local line=meter:FindFirstChild("Line");local ghost=meter:FindFirstChild("Ghost");local arrow=meter:FindFirstChild("Arrow")
        if fill then fill.Size=UDim2.fromScale(math.clamp(o.fill,0,1),1);fill.BackgroundColor3=o.color end
        if line then line.Position=UDim2.fromScale(math.clamp(o.line,0,1),.5) end
        if ghost then ghost.Visible=o.ghost~=nil;if o.ghost then ghost.Position=UDim2.fromScale(math.clamp(o.ghost,0,1),.5) end end
        local arrow=line and line:FindFirstChild("Arrow") or arrow -- authored on the Line tick: it rides the line
        if arrow then arrow.Visible=o.arrow end
    end
    if badge then
        badge.BackgroundColor3=o.tint;local r=badge:FindFirstChildOfClass("UIStroke");if r then r.Color=o.tint end
        local g=badge:FindFirstChild("Glyph");if g and g:IsA("ImageLabel") then g.ImageColor3=o.tint;g.ImageRectOffset=Vector2.new(GLYPH_X[o.glyph] or 0,0) end
    end
    if glass then local r=glass:FindFirstChildOfClass("UIStroke");if r then r.Color=o.rim or Color3.new(1,1,1);r.Transparency=if o.rim then .45 else .88 end end
    local glow=clock:FindFirstChild("Glow");if glow and glow:IsA("GuiObject") then glow.Visible=o.glow end
    local value=clock:FindFirstChild("Value");if value and value:IsA("TextLabel") then value.Text=o.value;value.TextColor3=o.valueColor end
end
local function fixed1(n: number): string return string.format("%.1f%%",math.floor(n*10+.5)/10) end
function H.new(ui: Frame,callbacks: any?)
    local self=setmetatable({ui=ui,callbacks=callbacks or {},root=ui:WaitForChild("VariantPanels"),topOffset=0,previousTimer=0,hasShownWarning=false,connections={},destroyed=false,textMeasurements=setmetatable({},{__mode="k"})},H)
    self.doom=self.root.Doomsday;self.overtime=self.root.Overtime
    Icons.bind(self.doom,"VariantHudPanelMask");Icons.bind(self.overtime,"VariantHudPanelMask");Icons.bind(self.doom.Header.Skull,"DoomsdayClockSkull")
    self.pulseImage=assert(game:GetService("AssetService"):CreateEditableImage({Size=Vector2.new(30,30)}),"Clock pulse image unavailable");self.pulseBytes=buffer.create(30*30*4);self.doom.PulseMask.ImageContent=Content.fromObject(self.pulseImage)
    if ui.ClockPanel:FindFirstChild("SourceBackground")then Icons.bind(ui.ClockPanel.SourceBackground,"VariantHudPanelMask")end
    self.clock,self.clockPanel=clockNodes(ui)
    self.pause=ui:FindFirstChild("Pause");self.settings=ui:FindFirstChild("GameRightSidebar")and ui.GameRightSidebar:FindFirstChild("Settings")
    if self.pause and self.pause:FindFirstChild("VariantIcon")then Icons.bind(self.pause.VariantIcon,"VariantSidebarPause")end
    if self.settings and self.settings:FindFirstChild("VariantIcon")then Icons.bind(self.settings.VariantIcon,"VariantSidebarSettings")end
    self.speedPanel=ui:WaitForChild("VariantSpeedPanel");self.exitConfirm=ui:WaitForChild("VariantExitConfirm");self.speedButton=ui.GameRightSidebar.Speed;self.exitButton=ui.GameRightSidebar.Exit
    Icons.bind(self.speedButton.VariantIcon,"VariantSidebarSpeed");Icons.bind(self.exitButton.VariantIcon,"VariantSidebarExit");Icons.bind(self.speedPanel,"VariantHudLeftPanelMask")
    listen(self,self.speedButton.Activated,function()self:toggleSpeed()end);listen(self,self.exitButton.Activated,function()self:requestExit()end)
    for i,choice in Data.speedChoices do local b=self.speedPanel[({"Slow","Normal","Fast","Max"})[i]];b.Text=choice.label
        listen(self,b.Activated,function()self:chooseSpeed(choice.value)end);listen(self,b.MouseEnter,function()b.Border.Color=colors["gray-200"]end);listen(self,b.MouseLeave,function()b.Border.Color=colors["gray-500"]end)
    end
    listen(self,self.exitConfirm.Backdrop.Activated,function()self:finishExit(false)end);listen(self,self.exitConfirm.Body.Cancel.Activated,function()self:finishExit(false)end);listen(self,self.exitConfirm.Body.Confirm.Activated,function()self:finishExit(true)end)
    -- PF019 M13a restyles this prompt (PF019Confirm=true); InGameMenu.bindConfirm owns its hover then.
    for _,name in (if self.exitConfirm:GetAttribute("PF019Confirm")==true then {} else {"Cancel","Confirm"})do local b=self.exitConfirm.Body[name];listen(self,b.MouseEnter,function()if name=="Cancel"then b.BackgroundTransparency=.9;b.TextTransparency=.2 else b.BackgroundColor3=colors["red-700"]end end);listen(self,b.MouseLeave,function()if name=="Cancel"then b.BackgroundTransparency=.95;b.TextTransparency=.4 else b.BackgroundColor3=colors["red-600"]end end)end
    table.insert(self.connections,ui.Destroying:Connect(function()self:destroy()end));self:reset();return self
end
function H:setTopOffset(pixels: number): any
    self.topOffset=pixels;if not self.state then return nil end;local layout=self:layout()
    if self.meta then for _,key in {"stackWidth","stackTop","timerPosition","sidebar"}do self.meta[key]=layout[key]end end
    return layout
end
function H:setPreferences(preferences: any)self.callbacks.preferences=preferences;if self.state then self:_render(self.state,self.owner,os.clock()*1000,true)end end
function H:setPaused(paused: boolean)
    local changed=self.paused~=paused;self.paused=paused
    if self.pause and self.pause:FindFirstChild("VariantIcon")then self.pause.Text="";Icons.bind(self.pause.VariantIcon,if paused then "VariantSidebarPlay"else "VariantSidebarPause")end
    if self.settings then self.settings.Text=""end
    -- Lit re-renders this parent for isPaused; child game/winner/refreshKey
    -- properties remain unchanged, so their panels retain the prior readout.
    if changed and self.state then self:_render(self.state,self.owner,os.clock()*1000,false)end
end
function H:sidebarLayout(buttons: {string}?): any
    buttons=buttons or {"replay","pause","settings","exit"};local positions={};local clock=self.clock
    local measured=width(self,clock,self.timer and self.timer.text or "00:00");local cursor=12+measured
    for _,name in {"replay","pause","settings","fullscreen","exit"}do if table.find(buttons,name)then cursor+=12;positions[name]=Vector2.new(cursor,8);cursor+=20 end end
    return{width=cursor+12,height=36,timer=Vector2.new(12,8),timerWidth=measured,buttons=positions}
end
function H:setSpeed(multiplier: number): boolean
    local valid=false;for _,choice in Data.speedChoices do if choice.value==multiplier then valid=true end end;if not valid then return false end
    self.speedMultiplier=multiplier
    for i,choice in Data.speedChoices do local b=self.speedPanel[({"Slow","Normal","Fast","Max"})[i]];b.BackgroundTransparency=if choice.value==multiplier then 0 else 1 end;return true
end
function H:chooseSpeed(multiplier: number)
    if not self.state or (self.state.gameConfig or {}).gameType~="Singleplayer"then return end
    if self:setSpeed(multiplier)and self.callbacks.speed then self.callbacks.speed(multiplier)end
end
function H:toggleSpeed()
    if not self.state or (self.state.gameConfig or {}).gameType~="Singleplayer"then return end
    self.speedPanel.Visible=not self.speedPanel.Visible;self:layout()
    if self.speedPanel.Visible and string.sub(UserInputService:GetLastInputType().Name,1,7)=="Gamepad" then GuiService.SelectedObject=self.speedPanel.Normal end
end
function H:requestExit()
    if not self.state or self.exitConfirm.Visible then return end
    if self.owner and (self.state.counts[self.owner]or 0)>0 then self.exitConfirm.Visible=true;self:layout()
        if string.sub(UserInputService:GetLastInputType().Name,1,7)=="Gamepad" then GuiService.SelectedObject=self.exitConfirm.Body.Cancel end
    elseif self.callbacks.exit then self.callbacks.exit()end
end
function H:finishExit(confirmed: boolean)
    if not self.exitConfirm.Visible then return end
    if self.faultTexts and not confirmed then return end -- a stopped match has no way back in
    self.exitConfirm.Visible=false
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.exitConfirm) then GuiService.SelectedObject=nil end
    self:clearFault()
    if confirmed and self.callbacks.exit then self.callbacks.exit()end
end
-- PF019 (PF - 2): a server match fault (State MatchFault) reuses this prompt as "Match stopped"
-- with a single Return to lobby action, so a broken match never traps the player.
function H:fault(message: string?)
    local body=self.exitConfirm.Body
    local title=body:FindFirstChild("PFTitle")
    if not self.faultTexts then
        self.faultTexts={title=if title then title.Text else nil,message=body.Message.Text,confirm=body.Confirm.Text}
    end
    if title then title.Text="Match stopped" end
    body.Message.Text=if type(message)=="string" and message~="" then message else "An error stopped this match."
    body.Confirm.Text="Return to lobby";body.Cancel.Visible=false
    self.speedPanel.Visible=false;self.exitConfirm.Visible=true;self:layout()
    if string.sub(UserInputService:GetLastInputType().Name,1,7)=="Gamepad" then GuiService.SelectedObject=body.Confirm end
end
function H:clearFault()
    local saved=self.faultTexts;if not saved then return end
    self.faultTexts=nil
    local body=self.exitConfirm.Body
    local title=body:FindFirstChild("PFTitle")
    if title and saved.title then title.Text=saved.title end
    body.Message.Text=saved.message;body.Confirm.Text=saved.confirm;body.Cancel.Visible=true
end
function H:isBlocking(): boolean return self.exitConfirm.Visible end
function H:modalBlocked(): boolean return self.exitConfirm.Visible end
function H:handleEscape(): boolean
    if self.exitConfirm.Visible then self:finishExit(false);return true end
    if self.speedPanel.Visible then
        self.speedPanel.Visible=false
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.speedPanel) then GuiService.SelectedObject=nil end
        return true
    end
    return false
end
-- PF013 (Builder A): the toolbar, Game speed popover, Leave/Stay popup and the
-- Doomsday/Overtime readouts are authored in the place (Scale/offset geometry
-- with AutomaticSize; tools/atlas/author-pf013-shell.luau). Layout writes nothing;
-- it only reports the source row metrics callers and tests still read.
function H:layout(): any
    local buttons=self.callbacks.sidebarButtons;if type(buttons)=="function"then buttons=buttons()end
    local row=self:sidebarLayout(buttons)
    local top=row.height+6+self.topOffset
    local result={stackWidth=self.root.AbsoluteSize.X,stackTop=top,timerPosition=UDim2.new(1,-self.root.AbsoluteSize.X/2,0,self.topOffset),sidebar=row}
    self.layoutInfo=result;return result
end
function H:_render(state: any,owner: number?,nowMs: number,panels: boolean): any
    if panels then self.doomModel=P.doomsday(state,owner,self.callbacks);self.overtimeModel=P.overtime(state,owner,self.callbacks);self.panelRefreshes+=1 end
    self.timer=P.timerView(state,self.previousTimer)
    self.speedButton.Visible=(state.gameConfig or {}).gameType=="Singleplayer";if not self.speedButton.Visible then self.speedPanel.Visible=false end
    local d,o=self.doomModel,self.overtimeModel;self.doom.Visible=d.visible;self.overtime.Visible=o.visible;self.root.Visible=d.visible or o.visible
    if d.visible then
        self.doom.Header.Title.Text=d.title;self.doom.Header.Status.Text=d.status;textClass(self.doom.Header.Status,d.statusClass)
        self.doom.Share.Hold.Text=d.hold;self.doom.Share.Yours.Text=d.share;self.doom.Share.Yours.Visible=d.live
        local color=if d.team~=nil and self.callbacks.teamColor then self.callbacks.teamColor(d.team)elseif d.team~=nil then Data.teamColors[d.team]else nil
        self.doom.Share.Yours.TextColor3=color or colors[string.sub(d.shareClass,6)];self.doom.Detail.Text=d.detail;self.doom.Detail.Visible=d.detail~="";showBar(self.doom,d,colors["green-400"])
        self.doom.Pulse.Enabled=false;self.doom.PulseMask.Visible=d.edge~=""
        if self.edge~=d.edge then self.edge=d.edge;self.edgeStarted=nowMs/1000 end
    end
    if o.visible then self.overtime.Header.Title.Text=o.title;self.overtime.Header.Status.Text=o.toWin;self.overtime.Detail.Text=o.detail;self.overtime.Detail.Visible=o.leader~=nil;showBar(self.overtime,o,colors[string.sub(o.barClass,4)])end
    -- PF-041: the authored rows
    local doomClock=self.doom:FindFirstChild("PFClock")
    if doomClock and d.visible then
        hideSource(self.doom)
        local danger=d.flagged==true or d.draining==true
        local rising=not danger and (d.nearDanger==true or (d.wave~=nil and d.wave.growing==true))
        local color=if danger then CLOCK.red elseif rising then CLOCK.amber else CLOCK.green
        local you,need=d.yourPct or 0,d.requiredPct or 0
        local ghostPct=if d.wave and d.wave.growing and d.wave.targetPercent then d.wave.targetPercent else nil
        local range=math.min(100,math.max(10,need*3,you*1.25,(ghostPct or 0)*1.4))
        paintClock(doomClock,{fill=you/range,line=need/range,ghost=if ghostPct then ghostPct/range else nil,arrow=ghostPct~=nil,color=color,
            tint=if danger then CLOCK.red else CLOCK.white,rim=if danger then CLOCK.red elseif rising then CLOCK.amber else nil,glow=danger,
            value=if d.live then fixed1(you) else fixed1(need),valueColor=if d.live then color else CLOCK.muted,glyph="skull"})
    end
    local otClock=self.overtime:FindFirstChild("PFClock")
    if otClock and o.visible then
        hideSource(self.overtime)
        local mine=o.leader~=nil and o.leader.isMine==true
        local need=math.max(1,o.requiredPct or 100)
        paintClock(otClock,{fill=(o.leaderPct or 0)/need,line=.995,ghost=nil,arrow=false,color=if mine then CLOCK.gold else CLOCK.cobalt,
            tint=if mine then CLOCK.gold else CLOCK.white,rim=if mine then CLOCK.gold else nil,glow=false,
            value=if o.leader then tostring(o.leaderPctShown or 0).."%" else "—",valueColor=if mine then CLOCK.gold else Color3.new(1,1,1),glyph=if mine then "crown" else "flag"})
    end
    if self.timerClass~=self.timer.timerClass then self.timerClass=self.timer.timerClass;self.timerStarted=nowMs/1000 end
    if self.sidebarFlash~=self.timer.flashSidebar then self.sidebarFlash=self.timer.flashSidebar;self.sidebarStarted=nowMs/1000 end
    local layout=self:layout()
    self.meta={timerText=self.timer.text,timerClass=self.timer.timerClass,sidebarFlash=self.timer.flashSidebar,overtimeNotice=P.overtimeNotice(state),overtimeText=P.text("overtime.started"),
        stackWidth=layout.stackWidth,stackTop=layout.stackTop,timerPosition=layout.timerPosition,sidebar=layout.sidebar}
    return self.meta
end
function H:update(state: any,owner: number?,options: any?): any
    if self.destroyed then return nil end;self.state=state;self.owner=owner
    options=options or {};local nowMs=options.nowMs or os.clock()*1000;local force=options.force==true
    local hasWinner=state.winner~=nil or state.winnerTeam~=nil;local winnerChanged=self.hasWinner~=hasWinner;self.hasWinner=hasWinner
    local before=self.previousTimer;local warning
    if force or self.lastTickAtMs==nil or nowMs-self.lastTickAtMs>=250 then
        self.lastTickAtMs=nowMs;self.clockTicks+=1
        local nextTimer=P.timer(state,self.previousTimer);self.previousTimer=nextTimer.seconds
        if nextTimer.warning and not self.hasShownWarning then self.hasShownWarning=true;warning={text=P.text("game_timer.one_minute_remaining"),color="red",duration=4}end
    end
    if force or self.meta==nil or winnerChanged or before~=self.previousTimer then self:_render(state,owner,nowMs,true)end
    -- HeadsUpMessage has no getTickIntervalMs. Always evaluate its window from
    -- the accepted state, even while timer/panel properties retain their value.
    self.meta.overtimeNotice=P.overtimeNotice(state);self.meta.warning=warning
    return self.meta
end
function H:draw(now: number?)
    if self.destroyed or not self.state then return end;now=now or os.clock()
    if self.doom.Visible and self.edge~="" and not self.doom:FindFirstChild("PFClock") then
        local red=self.edge=="sd-pulse-red";local phase=P.pulse(now-self.edgeStarted,if red then 1 else 1.8)
        local spread=3*phase
        if self.lastSpread~=spread then Pulse.pixels(spread,self.pulseBytes);self.pulseImage:WritePixelsBuffer(Vector2.zero,Vector2.new(30,30),self.pulseBytes);self.lastSpread=spread end
        self.doom.PulseMask.ImageColor3=if red then Color3.fromRGB(248,113,113)else Color3.fromRGB(251,146,60);self.doom.PulseMask.ImageTransparency=1-(if red then .95 else .9)*phase
        self.doom.PulseMask:SetAttribute("SourceSpread",spread)
    end
    local clock=self.clock;local timer=self.timer;local red=Color3.fromRGB(248,113,113)
    clock.TextColor3=if timer.flashText then P.mixBytes({248,113,113},{255,255,255},P.pulse(now-self.timerStarted,1))elseif timer.lastMinute then red else colors.white
    local background=self.clockPanel
    if background then local image=background:FindFirstChild("SourceBackground");if timer.flashSidebar then local phase=P.pulse(now-self.sidebarStarted,1);local color,alpha=P.mixBytes({0,0,0},{185,28,28},phase,.92,.96);local transparency=1-alpha
        if image then image.ImageColor3=color;image.ImageTransparency=transparency;background.BackgroundTransparency=1 else background.BackgroundColor3=color;background.BackgroundTransparency=transparency end
    elseif image then image.ImageColor3=colors["gray-800"];image.ImageTransparency=.08;background.BackgroundTransparency=1 else background.BackgroundColor3=colors["gray-800"];background.BackgroundTransparency=.08 end end
    if background and self.ui.Parent.Parent:GetAttribute("OriginalInterfaceRevision") then
        clockChrome(self.ui,background)
        background.BackgroundColor3=if timer.flashSidebar then restColor(background):Lerp(Theme.Danger,.2*P.pulse(now-self.sidebarStarted,1)) else restColor(background)
    end
end
function H:reset()
    table.clear(self.textMeasurements)
    self.state=nil;self.owner=nil;self.previousTimer=0;self.hasShownWarning=false;self.edge="";self.timerClass="";self.sidebarFlash=false;self.doomModel=nil;self.overtimeModel=nil;self.meta=nil
    self.lastTickAtMs=nil;self.clockTicks=0;self.panelRefreshes=0;self.hasWinner=false;self.paused=false
    self.doom.Visible=false;self.overtime.Visible=false;self.root.Visible=false;self.doom.Pulse.Enabled=false;self.doom.Pulse.Thickness=0;self.doom.Pulse.Transparency=1
    self.doom.PulseMask.Visible=false;self.lastSpread=nil
    self.clock.TextColor3=colors.white;local panel=self.clockPanel;if panel then local image=panel:FindFirstChild("SourceBackground");if image then image.ImageColor3=colors["gray-800"];image.ImageTransparency=.08;panel.BackgroundTransparency=1 else panel.BackgroundColor3=colors["gray-800"];panel.BackgroundTransparency=.08 end end
    if panel and self.ui.Parent.Parent:GetAttribute("OriginalInterfaceRevision") then panel.BackgroundColor3=restColor(panel);clockChrome(self.ui,panel) end
    self.speedPanel.Visible=false;self.exitConfirm.Visible=false;self:clearFault();self:setSpeed(1)
end
function H:destroy()if self.destroyed then return end;self.destroyed=true;if self.weightedText then self.weightedText:destroy() end;for _,c in self.connections do c:Disconnect()end;table.clear(self.connections);table.clear(self.textMeasurements);self.state=nil;self.pulseImage:Destroy()end
return H
