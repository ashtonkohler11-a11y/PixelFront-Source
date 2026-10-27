--!strict
-- AttackingTroopsController and ControlPanel help presentation; attack alerts retired.
local Shared=game:GetService("ReplicatedStorage").Shared
local Rules=require(Shared.OpenFrontPreferenceRules)
local Text=require(script.Parent.LobbySettingsPresentation)
local Icons=require(script.Parent.ReferenceIcons)
local NumberFont=require(script.Parent.WorldNumberFont)
local Presentation={};Presentation.__index=Presentation
local function retireAlert(self: any)
    self.alertStarted=nil;self.alertKind=nil
    self.alert.Visible=false;self.alert.Active=false;self.alert.Selectable=false
end
function Presentation.new(ui: Frame,world: Frame,preferences: any,callbacks: any): any
    local self=setmetatable({ui=ui,world=world,preferences=preferences,callbacks=callbacks,alert=ui.AlertFrame,help=ui.Controls.HelpMessage,
        attacksParent=world.AttackTroops,template=ui.Templates.AttackTroopLabel,blockedUI=world.BlockedNukeFeedback,
        attacks={},rows={},free={},font=NumberFont.new(),helpAttacks={},nearby={},borderCounter=0},Presentation)
    Icons.bind(self.blockedUI,"WarshipCrosshair");self:reset();return self
end
function Presentation:setPreferences(preferences: any) self.preferences=preferences end
function Presentation:setAlternateView(value: boolean) self.alternateView=value end
function Presentation:update(state: any,alternateView: boolean?)
    self.state=state;self.alternateView=alternateView==true
    -- Legacy/custom preferences cannot restore the retired attack interruption.
    retireAlert(self)
    if self.preferences:get("helpMessages") and self.preferences:gamesPlayed()<20 then
        Rules.trackHelpAttacks(self.helpAttacks,state);self.borderCounter+=1
        if self.borderCounter>=10 then self.borderCounter=0;self.nearby=Rules.nearbyOwners(state) end
        self.notification=Rules.help(state,self.nearby,self.helpAttacks)
    end
    self.help.Visible=self.notification~=nil and (state.counts[1] or 0)>0
    if self.notification then
        local warning=self.notification.type=="warning";self.help.Icon.Text=if warning then "⚠" else "ℹ";self.help.Message.Text=Text.text(self.notification.message)
        self.help.BackgroundColor3=if warning then Color3.fromRGB(255,137,4) else Color3.fromRGB(81,162,255)
        self.help.Border.Color=self.help.BackgroundColor3;self.help.Icon.TextColor3=if warning then Color3.fromRGB(255,184,106) else Color3.fromRGB(142,197,255);self.help.Message.TextColor3=self.help.Icon.TextColor3
    end
    local now=os.clock()*1000
    if self.lastAttackAt and now-self.lastAttackAt<200 then return end;self.lastAttackAt=now
    if not self.preferences:get("attackingTroopsOverlay") or self.alternateView or not state.players[1] then self.attacks={};return end
    local active={}
    for _,attack in state.attacks or {} do
        local incoming=attack.targetOwner==1 and attack.owner~=1
        local outgoing=attack.owner==1 and attack.targetOwner~=0
        if not outgoing and not (incoming and state.players[attack.owner].playerType~="Bot") then continue end
        active[attack.id]=true;local entry=self.attacks[attack.id]
        if not entry then entry={slots={}};self.attacks[attack.id]=entry end
        entry.text=self.callbacks.formatTroops(attack.budget);entry.incoming=incoming
        Rules.reconcile(entry,attack.positions or {},now)
    end
    for id in self.attacks do if not active[id] then self.attacks[id]=nil end end
end
function Presentation:blocked(tile: number)
    self.blockedTile=tile;self.blockedStarted=os.clock()
end
function Presentation:draw(zoom: number)
    local now=os.clock()
    retireAlert(self)
    -- PF013: the help bar's geometry is authored above the slot tray.
    local present={}
    if not self.alternateView then for id,entry in self.attacks do for index,slot in entry.slots do
        local key=tostring(id)..":"..index;present[key]=true;local row=self.rows[key]
        if not row then row=table.remove(self.free);if not row then row={ui=self.template:Clone(),glyphs={}};row.ui.Parent=self.attacksParent end;self.rows[key]=row end
        local t=math.min(1,(now*1000-slot.startMs)/250);slot.curX=slot.srcX+(slot.dstX-slot.srcX)*t;slot.curY=slot.srcY+(slot.dstY-slot.srcY)*t
        row.ui.Position=UDim2.fromOffset((slot.curX+.5)*zoom,(slot.curY+.5)*zoom);row.ui.Visible=true
        if row.text~=entry.text or row.incoming~=entry.incoming then
            local layout=NumberFont.layout(entry.text)
            for glyphIndex,glyph in layout do local label=row.glyphs[glyphIndex]
                if not label then label=row.ui.GlyphTemplate:Clone();label.Parent=row.ui;row.glyphs[glyphIndex]=label end
                self.font:bind(label,glyph.char,entry.incoming);label.Position=UDim2.fromOffset(glyph.x,glyph.y);label.Size=UDim2.fromOffset(glyph.width,glyph.height);label.Visible=true
            end
            for glyphIndex=#layout+1,#row.glyphs do row.glyphs[glyphIndex].Visible=false end
            row.text,row.incoming=entry.text,entry.incoming
        end
    end end end
    for key,row in self.rows do if not present[key] then row.ui.Visible=false;self.rows[key]=nil;table.insert(self.free,row) end end
    if self.blockedTile and self.state then
        local fraction=(now-self.blockedStarted)/.6
        if fraction>=1 then self.blockedTile=nil;self.blockedUI.Visible=false else
            local progress=1-(1-fraction)^2;local tile=self.blockedTile-1;local mapWidth=self.state.map.width
            self.blockedUI.Position=UDim2.fromOffset((tile%mapWidth+.5)*zoom,(math.floor(tile/mapWidth)+.5-progress*2)*zoom)
            self.blockedUI.ImageTransparency=progress*progress;self.blockedUI.Visible=true
        end
    end
end
function Presentation:reset()
    self.attacks={};self.lastAttackAt=nil;retireAlert(self);self.help.Visible=false
    self.helpAttacks={};self.nearby={};self.borderCounter=0;self.notification=nil;self.blockedTile=nil;self.blockedUI.Visible=false
    for _,row in self.rows do row.ui.Visible=false;table.insert(self.free,row) end;self.rows={}
end
function Presentation:dispose() self:reset();self.font:dispose();for _,row in self.free do row.ui:Destroy() end;self.free={} end
return Presentation
