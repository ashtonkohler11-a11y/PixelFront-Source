--!strict
-- Animates editable PFMenuMotion layers only. Existing controllers own every action.
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Gui = game:GetService("GuiService")
local Math = require(script.Parent.AtlasMenuMotionMath)

export type Options = {extraRoots: {GuiObject}?}
type Piece = {node: GuiObject, channel: string, step: number, active: number, rest: number,
    idle: boolean, travel: boolean, position: UDim2, alpha: number?}
type Surface = {host: GuiObject, layer: Frame, role: string, pieces: {Piece}, connections: {RBXScriptConnection},
    watched: {[Instance]: boolean}, pointer: boolean, focused: boolean, pressed: InputObject?,
    pulseUntil: number, progress: number, goal: number, shown: boolean, disabled: boolean,
    selected: boolean, idle: boolean, serial: number, phase: string, automatic: boolean?}
type Watch = {references: number, connections: {RBXScriptConnection}}
local Engine = {}; Engine.__index = Engine
local Motion = {}
Motion.version="PF006-motion-v1"
local owners: {[Instance]: any} = setmetatable({}, {__mode="k"}) :: any
local CHANNELS = {cell=true, frontier=true, rail=true, band=true, beacon=true, coin=true, corner=true}
local MAX_SURFACES, MAX_PIECES, MAX_CELLS, MAX_IDLE = 512, 60, 48, 8

local function disconnect(connections: {RBXScriptConnection})
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
end
local function attributeNumber(node: Instance, name: string, default: number): number
    local value=node:GetAttribute(name)
    return if type(value)=="number" and value==value then math.clamp(value,0,1) else default
end
local function inTemplate(node: Instance): boolean
    local ancestor: Instance?=node
    while ancestor do
        if ancestor.Name=="Templates" then return true end
        ancestor=ancestor.Parent
    end
    return false
end
local function isPress(input: InputObject): boolean
    return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch
        or input.KeyCode==Enum.KeyCode.ButtonA or input.KeyCode==Enum.KeyCode.Return or input.KeyCode==Enum.KeyCode.Space
end
local function selected(host: GuiObject, passive: boolean): boolean
    local value=host:GetAttribute("PFSelected")
    -- Play map previews use legacy Selected for thumbnail rendering, not queue choice.
    return if value~=nil then value==true else not passive and host:GetAttribute("Selected")==true
end

function Motion.new(root: Frame, options: Options?): any
    if owners[root] then owners[root]:destroy() end
    local self: any=setmetatable({root=root, extras=if options then options.extraRoots or {} else {},
        surfaces={}, watches={}, connections={}, moving={}, idle={}, pressed={}, visible=false, destroyed=false,
        scheduled=false, total=0, serial=0, frame=nil, reduced=false, static=false, draws=0, overBudget=0,nextIdleAt=0},Engine)
    owners[root]=self
    local function listen(signal: RBXScriptSignal, callback: any)
        table.insert(self.connections,signal:Connect(callback))
    end
    local function refresh()self:_schedule()end
    listen(root:GetPropertyChangedSignal("Visible"),refresh)
    for _, scope in self:_scopes() do
        listen(scope.DescendantAdded,function(node: Instance)
            if node.Name=="PFMenuMotion" then
                task.defer(function()if not self.destroyed and node.Parent then self:_bind(node);self:_schedule()end end)
            end
        end)
        for _, node in scope:GetDescendants() do self:_bind(node) end
    end
    for _, name in {"ReducedMotion","StaticBackground","AtlasPage"} do listen(root:GetAttributeChangedSignal(name),refresh) end
    local pages=root:FindFirstChild("Pages")
    local play=pages and pages:FindFirstChild("Play")
    if play then listen(play:GetAttributeChangedSignal("ModalOpen"),refresh) end
    listen(Gui:GetPropertyChangedSignal("SelectedObject"),function()
        for _, surface: Surface in self.surfaces do
            local chosen=Gui.SelectedObject
            surface.focused=chosen~=nil and (chosen==surface.host or (surface.layer:GetAttribute("PFDecorOnly")==true and chosen:IsDescendantOf(surface.host)))
                and Input.PreferredInput~=Enum.PreferredInput.Touch
        end
        self:_schedule()
    end)
    listen(Input:GetPropertyChangedSignal("PreferredInput"),function()
        for _, surface: Surface in self.surfaces do
            surface.pointer=false
            local chosen=Gui.SelectedObject
            surface.focused=chosen~=nil and (chosen==surface.host or (surface.layer:GetAttribute("PFDecorOnly")==true and chosen:IsDescendantOf(surface.host)))
                and Input.PreferredInput~=Enum.PreferredInput.Touch
        end
        self:_schedule()
    end)
    listen(Input.InputEnded,function(input: InputObject)
        for surface: Surface, active: InputObject in self.pressed do
            if input==active or (input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType==active.UserInputType and input.KeyCode==active.KeyCode) then
                surface.pressed=nil;surface.pulseUntil=if self.reduced then 0 else os.clock()+.14;self.pressed[surface]=nil
            end
        end
        self:_schedule()
    end)
    listen(Input.WindowFocusReleased,function()
        for _, surface: Surface in self.surfaces do
            surface.pressed=nil;surface.pointer=false;surface.pulseUntil=0
        end
        table.clear(self.pressed);self:_schedule()
    end)
    listen(root.Destroying,function()self:destroy()end)
    self:refresh()
    return self
end

function Engine:_scopes(): {GuiObject}
    local result={self.root}
    for _, extra in self.extras do if extra.Parent and not extra:IsDescendantOf(self.root) then table.insert(result,extra) end end
    return result
end
function Engine:_schedule()
    if self.destroyed or self.scheduled then return end
    self.scheduled=true
    task.defer(function()
        if self.destroyed then return end
        self.scheduled=false;self:refresh()
    end)
end
function Engine:_watch(surface: Surface, node: Instance)
    if surface.watched[node] then return end
    surface.watched[node]=true
    local prior: Watch?=self.watches[node]
    if prior then prior.references+=1;return end
    local watch: Watch={references=1,connections={}};self.watches[node]=watch
    local function listen(signal: RBXScriptSignal)
        table.insert(watch.connections,signal:Connect(function()self:_schedule()end))
    end
    if node:IsA("GuiObject") then
        for _, name in {"Visible","AbsolutePosition","AbsoluteSize","ClipsDescendants"} do listen(node:GetPropertyChangedSignal(name)) end
        if node:IsA("ScrollingFrame") then
            listen(node:GetPropertyChangedSignal("CanvasPosition"));listen(node:GetPropertyChangedSignal("AbsoluteWindowSize"))
        end
        listen(node:GetAttributeChangedSignal("SourceDisabled"))
    elseif node:IsA("LayerCollector") then listen(node:GetPropertyChangedSignal("Enabled")) end
end
function Engine:_unwatch(surface: Surface)
    for node in surface.watched do
        local watch: Watch?=self.watches[node]
        if watch then
            watch.references-=1
            if watch.references<=0 then disconnect(watch.connections);self.watches[node]=nil end
        end
    end
    table.clear(surface.watched)
end
function Engine:_ancestors(surface: Surface)
    self:_unwatch(surface)
    local ancestor: Instance?=surface.host
    while ancestor do self:_watch(surface,ancestor);ancestor=ancestor.Parent end
end
function Engine:_bind(node: Instance)
    if self.destroyed or node.Name~="PFMenuMotion" or not node:IsA("Frame") or self.surfaces[node] or inTemplate(node) then return end
    local host=node.Parent
    local role=node:GetAttribute("PFMotionRole")
    if not host or not host:IsA("GuiObject") or type(role)~="string" or not Math.Styles[role] then return end
    if self.total>=MAX_SURFACES then self.overBudget+=1;node.Visible=false;return end
    local pieces: {Piece}={};local cells=0
    for _, piece in node:GetDescendants() do
        local channel=piece:GetAttribute("PFChannel")
        if not piece:IsA("GuiObject") or type(channel)~="string" or not CHANNELS[channel] then continue end
        if #pieces>=MAX_PIECES or (channel=="cell" and cells>=MAX_CELLS) then self.overBudget+=1;piece.Visible=false;continue end
        if channel=="cell" then cells+=1 end
        table.insert(pieces,{node=piece,channel=channel,step=attributeNumber(piece,"PFStep",0),
            active=attributeNumber(piece,"PFBaseAlpha",.8),rest=attributeNumber(piece,"PFRestAlpha",1),
            idle=piece:GetAttribute("PFIdle")==true,travel=piece:GetAttribute("PFTravel")==true,
            position=piece.Position,alpha=nil})
    end
    if #pieces==0 then return end
    self.serial+=1
    local surface: Surface={host=host,layer=node,role=role,pieces=pieces,connections={},watched={},pointer=false,
        focused=Gui.SelectedObject==host and Input.PreferredInput~=Enum.PreferredInput.Touch,pressed=nil,pulseUntil=0,
        progress=0,goal=0,shown=false,disabled=false,selected=selected(host,node:GetAttribute("PFDecorOnly")==true),idle=false,serial=self.serial,phase="hidden",
        automatic=if host:IsA("GuiButton") then host.AutoButtonColor else nil}
    self.surfaces[node]=surface;self.total+=1
    node:SetAttribute("PFPhase","hidden");node:SetAttribute("PFProgress",0)
    local function listen(signal: RBXScriptSignal, callback: any)table.insert(surface.connections,signal:Connect(callback))end
    local function refresh()self:_schedule()end
    listen(node:GetAttributeChangedSignal("PFMotionRole"),function()
        local nextRole=node:GetAttribute("PFMotionRole")
        if type(nextRole)=="string" and Math.Styles[nextRole] and nextRole~=surface.role then
            surface.role=nextRole;surface.progress=0;surface.pulseUntil=0;self:_schedule()
        end
    end)
    for _, name in {"PFSelected","Selected","SourceDisabled"} do listen(host:GetAttributeChangedSignal(name),refresh) end
    if host:IsA("GuiButton") and node:GetAttribute("PFDecorOnly")~=true then
        -- Shared Settings also serves in-match preferences; only own hover while Atlas is visible.
        listen(host:GetPropertyChangedSignal("AutoButtonColor"),function()
            if surface.shown and host.AutoButtonColor then surface.automatic=true;host.AutoButtonColor=false end
            if not surface.shown then surface.automatic=host.AutoButtonColor end
        end)
        for _, name in {"Active","Interactable","Selectable"} do listen(host:GetPropertyChangedSignal(name),refresh) end
    end
    -- Passive survey/card surfaces observe pointer/press too; they never enable input or actions.
    listen(host.MouseEnter,function()
        if Input.PreferredInput~=Enum.PreferredInput.Touch and self:_policy(surface) then surface.pointer=true;self:_schedule()end
    end)
    listen(host.MouseLeave,function()surface.pointer=false;self:_schedule()end)
    if host:IsA("GuiButton") then
        listen(host.SelectionGained,function()surface.focused=Input.PreferredInput~=Enum.PreferredInput.Touch;self:_schedule()end)
        listen(host.SelectionLost,function()surface.focused=false;self:_schedule()end)
    end
    listen(host.InputBegan,function(input: InputObject)
            local shown,disabled=self:_policy(surface)
            if shown and not disabled and isPress(input) then
                if input.UserInputType==Enum.UserInputType.Touch then surface.pointer=false;surface.focused=false end
                surface.pressed=input;surface.pulseUntil=0;self.pressed[surface]=input;self:_schedule()
            end
    end)
    listen(host.Destroying,function()self:_unbind(surface)end)
    listen(node.Destroying,function()self:_unbind(surface)end)
    listen(node.AncestryChanged,function()if node.Parent~=host then self:_unbind(surface)end end)
    listen(host.AncestryChanged,function()
        if self.destroyed then return end
        if not host.Parent then self:_unbind(surface)else self:_ancestors(surface);self:_schedule()end
    end)
    self:_ancestors(surface)
end
function Engine:_unbind(surface: Surface)
    if self.surfaces[surface.layer]~=surface then return end
    self.surfaces[surface.layer]=nil;self.total-=1
    self.moving[surface]=nil;self.idle[surface]=nil;self.pressed[surface]=nil
    disconnect(surface.connections);self:_unwatch(surface)
    if surface.host.Parent and surface.host:IsA("GuiButton") and surface.layer:GetAttribute("PFDecorOnly")~=true then
        surface.host.AutoButtonColor=surface.automatic==true
    end
    if surface.layer.Parent then surface.layer.Visible=false end
    self:_schedule()
end

function Engine:_policy(surface: Surface): (boolean, boolean)
    local host=surface.host
    if not self.visible or not self.root.Parent or not self.root.Visible or not host.Parent or surface.layer.Parent~=host then return false,false end
    local rootAncestor: Instance?=self.root.Parent
    while rootAncestor do
        if rootAncestor:IsA("GuiObject") and not rootAncestor.Visible then return false,false end
        if rootAncestor:IsA("LayerCollector") and not rootAncestor.Enabled then return false,false end
        rootAncestor=rootAncestor.Parent
    end
    local inside=host==self.root or host:IsDescendantOf(self.root)
    local extra=false
    if not inside then
        for _, scope in self.extras do if host==scope or host:IsDescendantOf(scope) then extra=true;break end end
        if not extra or self.root:GetAttribute("AtlasPage")~="Settings" then return false,false end
    end
    -- PF011 keeps the same Settings roots and authors its own control frontier
    -- before construction. Existing PF006 layers stay authored but dormant.
    -- Do not touch PF011 artwork or own the control's ordinary feedback.
    if extra and host:IsA("GuiButton") then
        local frontier=host:FindFirstChild("PF011Frontier")
        if frontier and frontier:IsA("Frame") and frontier:GetAttribute("PF011Owner")=="PF011Settings" then return false,false end
    end
    -- Settings export/confirm overlays are siblings; the active dialog owns their visual foreground.
    if self.root:GetAttribute("AtlasPage")=="Settings" then
        for _, scope in self.extras do
            if (scope.Name=="SettingsConfirm" or scope.Name=="SettingsJSON") and scope.Visible
                and host~=scope and not host:IsDescendantOf(scope) then return false,false end
        end
    end
    local pages=self.root:FindFirstChild("Pages")
    local play=pages and pages:FindFirstChild("Play")
    local dialog=play and play:FindFirstChild("DialogLayer")
    if self.root:GetAttribute("AtlasPage")=="Play" and play and play:GetAttribute("ModalOpen")==true and dialog
        and host~=dialog and not host:IsDescendantOf(dialog) then return false,false end
    local pos,size=host.AbsolutePosition,host.AbsoluteSize
    if size.X<=0 or size.Y<=0 then return false,false end
    -- Intersect every clipping rectangle, not only the immediate vertical scroll parent.
    local x1,y1,x2,y2=pos.X,pos.Y,pos.X+size.X,pos.Y+size.Y
    local disabled=host:IsA("GuiButton") and surface.layer:GetAttribute("PFDecorOnly")~=true and (not host.Active or not host.Interactable)
    local ancestor: Instance?=host
    while ancestor do
        if ancestor:IsA("GuiObject") then
            if not ancestor.Visible then return false,disabled end
            if ancestor:GetAttribute("SourceDisabled")==true then disabled=true end
            if ancestor~=host and ancestor.ClipsDescendants then
                local p=ancestor.AbsolutePosition
                local s=if ancestor:IsA("ScrollingFrame") then ancestor.AbsoluteWindowSize or ancestor.AbsoluteSize else ancestor.AbsoluteSize
                x1=math.max(x1,p.X);y1=math.max(y1,p.Y);x2=math.min(x2,p.X+s.X);y2=math.min(y2,p.Y+s.Y)
                if x2<=x1 or y2<=y1 then return false,disabled end
            end
        elseif ancestor:IsA("LayerCollector") and not ancestor.Enabled then return false,disabled end
        ancestor=ancestor.Parent
    end
    local p,s=self.root.AbsolutePosition,self.root.AbsoluteSize
    return Math.intersects(x1,y1,x2-x1,y2-y1,p.X,p.Y,s.X,s.Y),disabled
end
function Engine:_phase(surface: Surface, now: number): string
    if not surface.shown then return "hidden" elseif surface.disabled then return "disabled"
    elseif surface.pressed then return "pressed" elseif surface.selected and not surface.pointer and not surface.focused then return "selected"
    elseif surface.progress<surface.goal then return "advancing" elseif surface.progress>surface.goal then return "retreating"
    elseif surface.goal>0 or surface.pulseUntil>now then return "held" else return "rest" end
end
function Engine:_draw(surface: Surface, now: number)
    if not surface.layer.Parent then return end
    local phase=self:_phase(surface,now)
    if surface.phase~=phase then surface.phase=phase;surface.layer:SetAttribute("PFPhase",phase) end
    surface.layer:SetAttribute("PFProgress",math.floor(surface.progress*100)/100)
    if not surface.shown then surface.layer.Visible=false;return end
    surface.layer.Visible=true
    local style=Math.style(surface.role)
    local progress=if surface.disabled then 0 else surface.progress
    local glint=if surface.idle and not surface.disabled then Math.idle(now,style.idlePeriod,(surface.serial*1.71)%style.idlePeriod) else 0
    for _, piece in surface.pieces do
        local node=piece.node
        if not node.Parent then continue end
        local amount=if piece.channel=="cell" then Math.cell(piece.step,progress,style.edge)
            elseif piece.channel=="frontier" then progress*math.clamp(1-math.abs(piece.step-progress)*4,0,1)
            elseif piece.channel=="band" then progress*.7
            elseif piece.channel=="coin" or piece.channel=="beacon" then math.max(progress*.85,if piece.idle then glint*.55 else 0)
            else progress
        if piece.idle and piece.channel=="band" then amount=math.max(amount,glint*.25) end
        if surface.pressed and (piece.channel=="corner" or piece.channel=="beacon") then amount=1 end
        local alpha=Math.alpha(piece.rest,piece.active,amount)
        if piece.alpha~=alpha then
            if node:IsA("ImageLabel") then node.ImageTransparency=alpha else node.BackgroundTransparency=alpha end
            piece.alpha=alpha;self.draws+=1
        end
        if piece.travel and (piece.channel=="frontier" or piece.channel=="beacon") then
            local position=if self.reduced or surface.disabled then piece.position
                else piece.position+UDim2.fromOffset(math.floor(Math.ease(progress)*3),0)
            if node.Position~=position then node.Position=position end
        end
    end
end
function Engine:_clock()
    local work=next(self.moving)~=nil or next(self.idle)~=nil
    if work and not self.frame then self.frame=Run.Heartbeat:Connect(function(dt: number)self:_step(dt)end)
    elseif not work and self.frame then self.frame:Disconnect();self.frame=nil end
end
function Engine:_step(dt: number)
    if self.destroyed then return end
    local now=os.clock()
    if next(self.idle)~=nil and now>=self.nextIdleAt then self:refresh() end
    for surface: Surface in self.moving do
        if not surface.shown or surface.disabled then self.moving[surface]=nil;continue end
        if surface.pulseUntil>0 and now>=surface.pulseUntil then
            surface.pulseUntil=0
            surface.goal=if surface.pointer or surface.focused or surface.pressed then 1 elseif surface.selected then Math.style(surface.role).selected else 0
        end
        local style=Math.style(surface.role)
        surface.progress=Math.advance(surface.progress,surface.goal,dt,if surface.goal>surface.progress then style.enter else style.leave)
        self:_draw(surface,now)
        if surface.progress==surface.goal and surface.pulseUntil==0 then self.moving[surface]=nil end
    end
    for surface: Surface in self.idle do if not self.moving[surface] then self:_draw(surface,now) end end
    self:_clock()
end
function Engine:refresh()
    if self.destroyed then return end
    self.reduced=self.root:GetAttribute("ReducedMotion")==true
    self.static=self.root:GetAttribute("StaticBackground")==true
    table.clear(self.idle)
    local now=os.clock();local eligible={}
    -- Stable discovery order with rotating bounded slots prevents later pages/cards starving.
    local ordered={}
    for _, surface: Surface in self.surfaces do table.insert(ordered,surface) end
    table.sort(ordered,function(a: Surface,b: Surface)return a.serial<b.serial end)
    for _, surface: Surface in ordered do
        local wasShown=surface.shown
        surface.shown,surface.disabled=self:_policy(surface)
        if surface.host:IsA("GuiButton") and surface.layer:GetAttribute("PFDecorOnly")~=true then
            if surface.shown then
                if not wasShown then surface.automatic=surface.host.AutoButtonColor end
                surface.host.AutoButtonColor=false
            elseif wasShown then surface.host.AutoButtonColor=surface.automatic==true end
        end
        surface.selected=selected(surface.host,surface.layer:GetAttribute("PFDecorOnly")==true)
        if not surface.shown or surface.disabled then
            surface.pointer=false;surface.pressed=nil;surface.pulseUntil=0;self.pressed[surface]=nil
            surface.progress=0;surface.goal=0;self.moving[surface]=nil
        else
            local chosen=Gui.SelectedObject
            surface.focused=chosen~=nil and (chosen==surface.host or (surface.layer:GetAttribute("PFDecorOnly")==true and chosen:IsDescendantOf(surface.host)))
                and Input.PreferredInput~=Enum.PreferredInput.Touch
            if surface.layer:GetAttribute("PFDecorOnly")==true and not wasShown and not self.reduced and not self.static then surface.pulseUntil=now+.7 end
            surface.goal=if surface.pointer or surface.focused or surface.pressed or (not self.reduced and surface.pulseUntil>now) then 1
                elseif surface.selected then Math.style(surface.role).selected else 0
            if self.reduced then surface.progress=surface.goal;surface.pulseUntil=0;self.moving[surface]=nil
            elseif surface.goal~=surface.progress or surface.pulseUntil>0 then self.moving[surface]=true end
        end
        surface.idle=false
        if surface.shown and not surface.disabled and not self.reduced and not self.static then
            for _, piece in surface.pieces do if piece.idle then
                table.insert(eligible,surface);break
            end end
        end
    end
    if #eligible>0 then
        local start=(math.floor(now/3)*MAX_IDLE)%#eligible
        for offset=1,math.min(MAX_IDLE,#eligible) do
            local surface: Surface=eligible[(start+offset-1)%#eligible+1]
            surface.idle=true;self.idle[surface]=true
        end
    end
    self.nextIdleAt=(math.floor(now/3)+1)*3
    for _, surface: Surface in ordered do self:_draw(surface,now) end
    self:_clock()
end
function Engine:setVisible(value: boolean)
    if self.destroyed then return end
    -- PF031 (tab lag): the same visibility again (every lobby tab click) needs only the deferred refresh the page
    -- switch has already scheduled (its AtlasPage / Visible watchers); a real show or hide still refreshes at once
    if value==self.visible then self:_schedule();return end
    self.visible=value;self:refresh()
end
function Engine:debugSnapshot(): any
    local phases,roles={},{};local pieces,visible,moving,idle,watches=0,0,0,0,0
    for _, surface: Surface in self.surfaces do
        phases[surface.phase]=(phases[surface.phase]or 0)+1;roles[surface.role]=(roles[surface.role]or 0)+1
        pieces+=#surface.pieces;if surface.shown then visible+=1 end
    end
    for _ in self.moving do moving+=1 end;for _ in self.idle do idle+=1 end;for _ in self.watches do watches+=1 end
    return {version=Motion.version,surfaces=self.total,pieces=pieces,visible=visible,moving=moving,idle=idle,watches=watches,
        connected=self.frame~=nil,reduced=self.reduced,static=self.static,phases=phases,roles=roles,draws=self.draws,
        overBudget=self.overBudget,destroyed=self.destroyed}
end
function Engine:destroy()
    if self.destroyed then return end
    self.destroyed=true
    if self.frame then self.frame:Disconnect();self.frame=nil end
    disconnect(self.connections)
    local surfaces={};for _, surface: Surface in self.surfaces do table.insert(surfaces,surface) end
    for _, surface: Surface in surfaces do self:_unbind(surface) end
    table.clear(self.moving);table.clear(self.idle);table.clear(self.pressed)
    if owners[self.root]==self then owners[self.root]=nil end
end
function Motion.inspect(root: Frame): any
    local engine=owners[root]
    return if engine then engine:debugSnapshot() else nil
end
return Motion
