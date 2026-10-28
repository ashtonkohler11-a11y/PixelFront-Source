--!strict
-- PF019 B1 (PF - 3): M9 Create Lobby (Screens.Create). The map tile + match summary, THE settings
-- column, and the lobby panel (Public / Private, the lobby name, max players) with the players
-- list (you, the host, then open slots). Create Lobby calls the W6 facade
-- (createLobby(settings, {visibility, name})); the waiting Room takes over when model.room
-- arrives (AtlasMenuController opens it). Errors from Create show under the button.
local Tween=game:GetService("TweenService")
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Contract=require(Shared.LobbyContract)
local Column=require(script.Parent.LobbySettingsColumn)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Screen={};Screen.__index=Screen
local CAPTION="Opens the lobby. You can still change every setting."
-- the selected option only (both read as six lines in a phone side card)
-- UI audit build-out (R5): the Public line said what the word already says; Private keeps the one thing a host needs
local HINTS={Public="",Private="Friends join with your code."}
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),error=Color3.fromHex("#ff7a70"),hint=Color3.fromHex("#8c8c8c")}
-- PF020 G8 Lobby Host+ (PF - 2): the HOST+ SETTINGS card and the max-players cap (12 without the pass, the
-- server max with it), on nodes authored by tools/atlas/author-pf020-host-plus.luau. Without the pass the
-- same controls show greyed and every gold tag opens the pass. The server re-checks all of it.
local G={gold=Color3.fromHex("#ddbf76"),goldHi=Color3.fromHex("#ffd77a"),goldFill=Color3.fromHex("#2a2414"),line=Color3.fromHex("#3a3a3a"),
    raised=Color3.fromHex("#262626"),grey=Color3.fromHex("#3a3a3a"),accent=Color3.fromHex("#3678ff"),track=Color3.fromHex("#3a3a3a"),dim=Color3.fromHex("#5a5a5a")}
local PREVIEW={peaceMinutes=3,spectators=4} -- what a player without the pass sees, greyed (the mockup's example values)
-- 2026-10-28 (Ashton: "remove lobby host+ and just make it free"): every host has it (Contract.HostPlus.free), so no tag,
-- no pass, no "Host+" words; the controls are simply live
local function hostPlus(): boolean
    if Contract.HostPlus.free then return true end
    local player=Players.LocalPlayer
    return player~=nil and player:GetAttribute("OpenFrontHostPlus")==true
end
-- The tag: the owner's outline word ("HOST+" / "ACTIVE") or the gold crown tag for everyone else; free: none.
local function paintTag(tag: Instance?,owned: boolean,ownedText: string)
    if not tag then return end
    local t: any=tag
    if Contract.HostPlus.free then t.Visible=false;t.Active=false;t.Selectable=false;return end
    t.BackgroundTransparency=if owned then 1 else 0
    local crown=t:FindFirstChild("Crown");if crown then crown.Visible=not owned end
    local label=t:FindFirstChild("Label");if label then label.Text=if owned then ownedText else "Lobby Host+";label.TextColor3=if owned then G.gold else G.goldHi end
    t.Active=not owned;t.Selectable=not owned
end
-- Match setup v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-setup-v2.luau): Screens.Create.PFSetupV2 takes over while it is
-- authored. LobbySetupV2 runs the shared frame (map, skulls, mode, forces, rules, bans); this runs the Lobby card (Public /
-- Private, the name, max players, Host+: peace timer, spectator seats, team colours) and Create lobby. Same facade calls.
local CreateV2={};CreateV2.__index=CreateV2
function CreateV2.new(root: Frame,context: any): any
    local layer=root:FindFirstChild("PFSetupV2") :: any
    local settings=Model.defaults();settings.maxPlayers=12
    local self: any=setmetatable({root=root,context=context,layer=layer,settings=settings,visibility="Public",connections={},visible=false,destroyed=false,
        pending=false,teamPick=1},CreateV2)
    local lobby=layer.Canvas.Lobby;self.lobby=lobby;self.caption=layer.Canvas.Caption;self.key=layer.Canvas.Create
    self.setup=require(script.Parent.LobbySetupV2).new(layer,{mapSources=context.mapSources,
        onChange=function(next) self.settings=next;self:paint() end,
        onPickMap=function() if not self.pending then context.openPicker(self.settings.gameMap,function(map) if map then self.settings=Model.setMap(self.settings,map) end;self:paint() end) end end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local back=layer.Top.Back
    for _,b in {back,back:FindFirstChild("PFHit")} do if b then listen((b :: any).Activated,function()
        if self.pending and context.facade then context.facade.cancel() end;self.pending=false;if context.back then context.back() end
    end) end end
    -- UI audit R8: the Lobby card's small keys answer on their finger zones too (HitZone; author-pf3-hit-zones)
    local HitZone=require(script.Parent.HitZone)
    for _,name in {"Public","Private"} do listen(HitZone.signal(lobby.Visibility[name]),function() if not self.pending then self.visibility=name;self:paint() end end) end
    local function openPass() if context.openPass then context.openPass(Contract.HostPlus.pass) end end
    local function edit(change: (any)->any) if hostPlus() and not self.pending then self.settings=change(self.settings);self:paint() else openPass() end end
    local max=lobby.MaxPlayers.Stepper
    listen(HitZone.signal(max.Minus),function() if not self.pending then self.settings=Model.stepMaxPlayers(self.settings,-1,hostPlus(),Players.MaxPlayers);self:paint() end end)
    listen(HitZone.signal(max.Plus),function() if not self.pending then self.settings=Model.stepMaxPlayers(self.settings,1,hostPlus(),Players.MaxPlayers);self:paint() end end)
    listen(lobby.PFHostTag.Activated,function() if not hostPlus() then openPass() end end)
    for _,spec in {{"Peace","peaceMinutes"},{"Spectators","spectators"}} do
        local st=lobby[spec[1]].Stepper
        listen(HitZone.signal(st.Minus),function() edit(function(s) return Model.stepHostPlus(spec[2],s,-1) end) end)
        listen(HitZone.signal(st.Plus),function() edit(function(s) return Model.stepHostPlus(spec[2],s,1) end) end)
    end
    -- team colours: a tap moves that team to the next palette colour
    for team=1,Contract.HostPlus.teamColorSlots do
        local chip=lobby:FindFirstChild("Team"..team)
        if chip then listen(HitZone.signal(chip),function()
            edit(function(s)
                local ids=Model.teamColorIds(s);local current=ids[team]
                local index=1;for i,entry in Contract.TeamPalette do if entry.id==current then index=i end end
                return Model.setTeamColor(s,team,Contract.TeamPalette[index%#Contract.TeamPalette+1].id)
            end)
        end) end
    end
    listen(lobby.NameBox.FocusLost,function()
        local text=string.sub(lobby.NameBox.Text,1,Contract.Limits.nameMax);if text~=lobby.NameBox.Text then lobby.NameBox.Text=text end
    end)
    local player=Players.LocalPlayer
    if player then listen(player:GetAttributeChangedSignal("OpenFrontHostPlus"),function()
        if not hostPlus() then self.settings=Model.withoutHostPlus(self.settings) end;self:paint()
    end) end
    listen(HitZone.signal(self.key),function() self:create() end)
    self:paint()
    return self
end
local V2C={text=Color3.fromHex("#eef1f6"),dim=Color3.fromHex("#9aa3b2"),blue=Color3.fromHex("#3b74f0"),muted=Color3.fromHex("#6f7889"),
    gold=Color3.fromHex("#ffd36a"),goldDim=Color3.fromHex("#4d3f1a"),off=Color3.fromHex("#2a303c"),ink=Color3.fromHex("#1a1406")}
function CreateV2:paint()
    if self.destroyed then return end
    self.setup:set(self.settings,self.pending)
    local lobby=self.lobby
    for _,name in {"Public","Private"} do
        local b=lobby.Visibility[name];local on=self.visibility==name
        b.BackgroundColor3=V2C.blue;b.BackgroundTransparency=if on then 0 else 1;b.TextColor3=if on then Color3.new(1,1,1) else V2C.dim
    end
    lobby.VisibilityHint.Text=HINTS[self.visibility]
    local owned=hostPlus()
    local limit=Model.maxPlayersLimit(owned,Players.MaxPlayers)
    if self.settings.maxPlayers>limit then self.settings.maxPlayers=limit end
    lobby.MaxPlayers.Stepper.Value.Text=tostring(self.settings.maxPlayers)
    lobby.PFHostTag.Visible=not owned
    lobby.HostPlusHead.Text=if Contract.HostPlus.free then "MORE OPTIONS" elseif owned then "HOST+ · ACTIVE" else "HOST+"
    local shown=if owned then self.settings else PREVIEW
    local live=owned and not self.pending
    for _,spec in {{"Peace","peaceMinutes"},{"Spectators","spectators"}} do
        local row=lobby[spec[1]];local st=row.Stepper
        st.Value.Text=Model.value(spec[2],shown);st.Value.TextColor3=if owned then Color3.new(1,1,1) else V2C.muted
        row.Label.TextColor3=if owned then V2C.text else V2C.muted
        for _,b in {st.Minus,st.Plus} do b.TextColor3=if live then V2C.text else V2C.muted end
    end
    local ids=Model.teamColorIds(self.settings)
    local team=self.settings.gameMode=="Team"
    -- UI audit build-out (R5): team colours only show in Teams mode (no "apply in Teams mode" note under Free for all)
    for t=1,Contract.HostPlus.teamColorSlots do
        local chip=lobby:FindFirstChild("Team"..t)
        if chip then
            local entry=Contract.teamColor(ids[t])
            chip.Visible=team
            chip.Swatch.BackgroundColor3=if owned and entry then Color3.fromHex(entry.hex) else V2C.off
            chip.Label.TextColor3=if owned and team then V2C.text else V2C.muted
        end
    end
    for _,n in {"TeamsHead","TeamColoursHead","TeamColorsHead","TeamColours"} do local h=lobby:FindFirstChild(n);if h and h:IsA("GuiObject") then h.Visible=team end end
    lobby.TeamsHint.Visible=team
    lobby.TeamsHint.Text=if not owned then "Lobby Host+ sets the team colours" else "Tap a team to change its colour"
    local player=Players.LocalPlayer
    lobby.NameBox.PlaceholderText=(if player then player.DisplayName else "Your").."'s lobby"
    lobby.NameBox.TextEditable=not self.pending
    local label=self.key:FindFirstChild("Label");if label then label.Text=if self.pending then "Creating…" else "Create lobby" end
    self.key.BackgroundColor3=if self.pending then V2C.off else Color3.fromHex("#e0a62e")
    local g=self.key:FindFirstChild("Shade");if g then (g :: any).Enabled=not self.pending end
    self.key.Active=not self.pending
end
function CreateV2:create()
    if self.pending or not self.context.facade then return end
    local settings=if hostPlus() then Model.copy(self.settings) else Model.withoutHostPlus(self.settings)
    local result=self.context.facade.createLobby(settings,{visibility=self.visibility,name=self.lobby.NameBox.Text})
    if type(result)=="table" and result.ok==false then
        self.caption.Text=tostring(result.message or "That request could not be sent. Try again.");self.caption.TextColor3=C.error;return
    end
    self.pending=true;self.caption.Text="Opening your lobby…";self.caption.TextColor3=C.hint;self:paint()
end
function CreateV2:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    if self.pending and model.error and (model.errorOperation=="CreateLobby" or model.errorOperation=="Create") then
        self.pending=false;self.caption.Text=tostring(model.error);self.caption.TextColor3=C.error;self:paint()
    elseif self.pending and model.room then self.pending=false end
end
function CreateV2:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then if not self.pending then self.caption.Text="" end;self:paint() else self.setup:thumbs() end
end
function CreateV2:handleEscape(): boolean
    if self.pending and self.context.facade then self.context.facade.cancel();self.pending=false end
    return false
end
function CreateV2:focusActive() game:GetService("GuiService").SelectedObject=self.key end
function CreateV2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.setup:destroy()
end

function Screen.new(root: Frame,context: any): any
    if root:FindFirstChild("PFSetupV2") then return CreateV2.new(root,context) end
    local settings=Model.defaults();settings.maxPlayers=12
    local self: any=setmetatable({root=root,context=context,settings=settings,visibility="Public",connections={},rows={},visible=false,destroyed=false,
        pending=false,preview=Preview.new(context.mapSources)},Screen)
    local body=Parts.flat(root.Body) -- r5: Left / Center / Right sit inside anchoring groups
    self.mapPanel=body.Left.Panels.MapPanel;self.summary=body.Left.Panels.Summary
    self.lobby=body.Right.Panels.Lobby;self.players=body.Right.Panels.Players;self.actions=body.Right.Actions
    self.column=Column.new(body.Center.Column,{reduced=context.reducedMotion,onChange=function(next) self.settings=next;self:paint() end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    for _,tap in Parts.taps(Parts.find(root,"Header").Back,root) do listen(tap,function() if self.pending and context.facade then context.facade.cancel() end;self.pending=false;if context.back then context.back() end end) end
    Parts.bindMapTile(self.mapPanel,{reduced=context.reducedMotion,editable=function() return not self.pending end,onPick=function()
        context.openPicker(self.settings.gameMap,function(map) if map then self.settings=Model.setMap(self.settings,map) end;self:paint() end)
    end},self.connections)
    for _,name in {"Public","Private"} do listen(self.lobby.Visibility[name].Activated,function() self.visibility=name;self:paint() end) end
    local stepper=self.lobby.MaxPlayers.Stepper
    -- PF020 G8: 12 seats without Lobby Host+, the server max with it.
    listen(stepper.Minus.Activated,function() self.settings=Model.stepMaxPlayers(self.settings,-1,hostPlus(),Players.MaxPlayers);self:paint() end)
    listen(stepper.Plus.Activated,function() self.settings=Model.stepMaxPlayers(self.settings,1,hostPlus(),Players.MaxPlayers);self:paint() end)
    self:bindHostPlus(listen)
    listen(self.lobby.NameBox.FocusLost,function()
        local text=string.sub(self.lobby.NameBox.Text,1,Contract.Limits.nameMax);if text~=self.lobby.NameBox.Text then self.lobby.NameBox.Text=text end
    end)
    local create=self.actions.Create
    listen(create.Activated,function() self:create() end)
    listen(create.MouseButton1Down,function() local p=create:FindFirstChild("PFPress");if p then p.Scale=.97 end end)
    listen(create.MouseButton1Up,function() local p=create:FindFirstChild("PFPress");if p then Tween:Create(p,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end end)
    self:paint()
    return self
end
-- The Max players chip: its own row under the hint (author-pf020-host-plus v4), else the older spot on the label row.
function Screen:maxTag(): any?
    local row=self.lobby:FindFirstChild("PFHostTagRow")
    return (row and row:FindFirstChild("PFHostTag")) or self.lobby.MaxPlayers:FindFirstChild("PFHostTag")
end
function Screen:bindHostPlus(listen: any)
    self.teamPick=1
    local card=Parts.find(self.root.Body,"Right").Panels:FindFirstChild("PFHostPlus")
    local function openPass() if self.context.openPass then self.context.openPass(Contract.HostPlus.pass) end end
    for _,tag in {self:maxTag(),card and card.Head:FindFirstChild("PFHostTag")} do
        if tag then listen(tag.Activated,function() if not hostPlus() then openPass() end end) end
    end
    local player=Players.LocalPlayer
    if player then listen(player:GetAttributeChangedSignal("OpenFrontHostPlus"),function()
        if not hostPlus() then self.settings=Model.withoutHostPlus(self.settings) end;self:paint()
    end) end
    if not card then return end
    local function edit(change: (any)->any) if hostPlus() and not self.pending then self.settings=change(self.settings);self:paint() else openPass() end end
    for team=1,Contract.HostPlus.teamColorSlots do
        local chip=card.Teams:FindFirstChild("Team"..team)
        if chip then listen(chip.Activated,function() if hostPlus() then self.teamPick=team;self:paint() else openPass() end end) end
    end
    for _,entry in Contract.TeamPalette do
        local swatch=card.Swatches:FindFirstChild("Swatch_"..entry.id)
        if swatch then listen(swatch.Activated,function() edit(function(s) return Model.setTeamColor(s,self.teamPick,entry.id) end) end) end
    end
    for _,spec in {{"Peace","peaceMinutes"},{"Spectators","spectators"}} do
        local step=card[spec[1]].Stepper
        listen(step.Minus.Activated,function() edit(function(s) return Model.stepHostPlus(spec[2],s,-1) end) end)
        listen(step.Plus.Activated,function() edit(function(s) return Model.stepHostPlus(spec[2],s,1) end) end)
    end
end
function Screen:paintHostPlus()
    local owned=hostPlus()
    local limit=Model.maxPlayersLimit(owned,Players.MaxPlayers)
    if self.settings.maxPlayers>limit then self.settings.maxPlayers=limit end
    paintTag(self:maxTag(),owned,"HOST+")
    local maxHint=self.lobby:FindFirstChild("PFMaxHint")
    if maxHint then
        maxHint.Text=if Contract.HostPlus.free then "Up to the server max" elseif owned then "Up to the server max with Lobby Host+" else Contract.HostPlus.freeMaxPlayers.." is the most without the pass"
        maxHint.TextColor3=if owned and not Contract.HostPlus.free then G.gold else C.hint
    end
    local card=Parts.find(self.root.Body,"Right").Panels:FindFirstChild("PFHostPlus");if not card then return end
    local stroke=card:FindFirstChildOfClass("UIStroke");if stroke then stroke.Color=if owned then G.gold else G.line end
    paintTag(card.Head:FindFirstChild("PFHostTag"),owned,"ACTIVE")
    card.Head.Overline.TextColor3=if owned then G.gold else C.muted
    local live=owned and not self.pending
    local ids=Model.teamColorIds(self.settings)
    for team=1,Contract.HostPlus.teamColorSlots do
        local chip=card.Teams:FindFirstChild("Team"..team)
        if chip then
            local entry=Contract.teamColor(ids[team])
            chip.Swatch.BackgroundColor3=if owned and entry then Color3.fromHex(entry.hex) else G.grey
            chip.Label.Text="Team "..team..(if entry then " · "..entry.name else "")
            chip.Label.TextColor3=if owned then C.text else C.muted
            local ring=chip:FindFirstChildOfClass("UIStroke")
            if ring then ring.Color=if owned and self.teamPick==team then G.accent else G.line;ring.Thickness=if owned and self.teamPick==team then 2 else 1 end
        end
    end
    local picked=ids[self.teamPick]
    for _,entry in Contract.TeamPalette do
        local swatch=card.Swatches:FindFirstChild("Swatch_"..entry.id)
        if swatch then
            swatch.BackgroundColor3=if owned then Color3.fromHex(entry.hex) else G.raised
            local ring=swatch:FindFirstChildOfClass("UIStroke");if ring then ring.Transparency=if owned and entry.id==picked then 0 else 1 end
            swatch.Active=live
        end
    end
    local shown=if owned then self.settings else PREVIEW
    card.Peace.Stepper.Value.Text=Model.value("peaceMinutes",shown)
    card.Spectators.Stepper.Value.Text=Model.value("spectators",shown)
    for _,name in {"Peace","Spectators"} do -- PF024: the Host+ auto-start perk is gone (Ashton); every lobby starts 5 s after it fills
        local row=card[name];row.Label.TextColor3=if owned then C.text else C.muted;row.Sub.TextColor3=if owned then C.hint else G.dim
    end
    for _,name in {"Peace","Spectators"} do
        local step=card[name].Stepper;step.Value.TextColor3=if owned then C.text else C.muted
        for _,b in {step.Minus,step.Plus} do b.TextColor3=if live then C.text else G.dim;b.Active=live end
    end
end
function Screen:paintPlayers()
    for _,row in self.rows do row:Destroy() end;table.clear(self.rows)
    local player=Players.LocalPlayer
    local name=if player then player.DisplayName else "You"
    local row=self.context.templates.Member:Clone();row.Visible=true;row.LayoutOrder=1;row.Parent=self.players.Rows
    local initial,color=Parts.avatar(name,player and player.UserId)
    row.Avatar.Initial.Text=initial;row.Avatar.BackgroundColor3=color
    row.PlayerName.Text=name.." (you)";Parts.paintTag(row,true,nil) -- PF036 D: the host crown on the avatar
    table.insert(self.rows,row)
    local open=self.settings.maxPlayers-1
    self.players.Overline.Text="PLAYERS · 1 / "..self.settings.maxPlayers
    self.players.Open.Label.Text=open.." open slots"
end
function Screen:paint()
    if self.destroyed then return end
    self.column:set(self.settings,self.pending)
    Parts.paintMap(self.mapPanel,self.preview,self.settings.gameMap,not self.pending)
    Parts.paintSummary(self.summary,self.settings)
    for _,name in {"Public","Private"} do
        local b=self.lobby.Visibility[name];local on=self.visibility==name
        b.BackgroundTransparency=if on then 0 else 1;b.TextColor3=if on then C.text else C.muted
        b.Text=name -- no emoji: the globe drew faint on blue and the colour lock clashed
    end
    self.lobby.VisibilityHint.Text=HINTS[self.visibility]
    self:paintHostPlus() -- PF020 G8 (before the value: it clamps a lost pass back to 12)
    self.lobby.MaxPlayers.Stepper.Value.Text=tostring(self.settings.maxPlayers)
    local player=Players.LocalPlayer
    self.lobby.NameBox.PlaceholderText=(if player then player.DisplayName else "Your").."'s lobby"
    self:paintPlayers()
    local create=self.actions.Create
    Parts.paintKey(create,if self.pending then "dim" else "gold",if self.pending then "Creating…" else "Create Lobby")
    create.Active=not self.pending;create.AutoButtonColor=false
    self:thumbs()
end
function Screen:create()
    if self.pending or not self.context.facade then return end
    -- PF020 G8: a host without Lobby Host+ sends only the standard settings (12 seats at most).
    local settings=if hostPlus() then Model.copy(self.settings) else Model.withoutHostPlus(self.settings)
    local result=self.context.facade.createLobby(settings,{visibility=self.visibility,name=self.lobby.NameBox.Text})
    if type(result)=="table" and result.ok==false then
        self.actions.Caption.Text=tostring(result.message or "That request could not be sent. Try again.");self.actions.Caption.TextColor3=C.error;return
    end
    self.pending=true;self.actions.Caption.Text="Opening your lobby…";self.actions.Caption.TextColor3=C.hint;self:paint()
end
function Screen:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    if self.pending and model.error and (model.errorOperation=="CreateLobby" or model.errorOperation=="Create") then
        self.pending=false;self.actions.Caption.Text=tostring(model.error);self.actions.Caption.TextColor3=C.error;self:paint()
    elseif self.pending and model.room then self.pending=false end -- the Room screen takes over
end
function Screen:thumbs() self.preview:update({self.mapPanel.Tile},Parts.find(self.root.Body,"Left").Panels,self.visible) end
function Screen:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then if not self.pending then self.actions.Caption.Text=CAPTION;self.actions.Caption.TextColor3=C.hint end;self:paint() else self:thumbs() end
end
function Screen:handleEscape(): boolean
    if self.pending and self.context.facade then self.context.facade.cancel();self.pending=false end
    return false
end
function Screen:focusActive() game:GetService("GuiService").SelectedObject=self.actions.Create end
function Screen:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    for _,row in self.rows do row:Destroy() end
    self.column:destroy();self.preview:dispose()
end
return Screen
