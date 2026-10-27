--!strict
-- PF019 B1 (PF - 3): M4 Solo (Screens.Solo). Left: the map tile (hover "Change map" -> the shared
-- picker) and the match summary, as in M4 and Create Lobby. Centre: THE settings column
-- (LobbySettingsColumn, shared with Create Lobby and the waiting room). Right: "You'll face" (the
-- AI nation / tribe counts, the difficulty ladder with yours lit, the custom rules) and Start Game. Start builds the singleplayer config from the
-- same settings (LobbySettingsModel.soloConfig: compact always, nations <= 25, tribes <= 50)
-- and hands it to the existing Solo start path (context.startSolo). The settings stay as you
-- left them for the next Solo this session.
local Tween=game:GetService("TweenService")
local Model=require(game:GetService("ReplicatedStorage").Shared.LobbySettingsModel)
local Column=require(script.Parent.LobbySettingsColumn)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Screen={};Screen.__index=Screen
local CAPTION="Starts the match against AI nations."

-- Match setup v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-setup-v2.luau): Screens.Solo.PFSetupV2 (LobbySetupV2) takes over
-- while it is authored; the same page API and the same start path.
local SoloV2={};SoloV2.__index=SoloV2
function SoloV2.new(root: Frame,context: any): any
    local layer=root:FindFirstChild("PFSetupV2") :: Frame
    local self: any=setmetatable({root=root,context=context,settings=Model.defaults(),connections={},visible=false,destroyed=false,layer=layer},SoloV2)
    self.setup=require(script.Parent.LobbySetupV2).new(layer,{mapSources=context.mapSources,
        onChange=function(settings) self.settings=settings end,
        onPickMap=function() context.openPicker(self.settings.gameMap,function(map) if map then self.settings=Model.setMap(self.settings,map) end;self:paint() end) end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local back=layer.Top.Back
    for _,b in {back,back:FindFirstChild("PFHit")} do if b then listen((b :: any).Activated,function() if context.back then context.back() end end) end end
    self.start=layer.Canvas.Start;self.caption=layer.Canvas.Caption
    listen(self.start.Activated,function() self:begin() end)
    self:paint()
    return self
end
function SoloV2:paint() if not self.destroyed then self.setup:set(self.settings,false) end end
function SoloV2:begin()
    local config,problem=Model.soloConfig(self.settings)
    if not config then self.caption.Text=problem or "Some settings are not available.";self.caption.TextColor3=Color3.fromHex("#ff7a70");return end
    self.caption.Text=""
    if self.context.startSolo then self.context.startSolo(config) end
end
function SoloV2:update(_model: any) end
function SoloV2:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then self.caption.Text="";self:paint() else self.setup:thumbs() end
end
function SoloV2:handleEscape(): boolean return false end
function SoloV2:focusActive() game:GetService("GuiService").SelectedObject=self.start end
function SoloV2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.setup:destroy()
end

function Screen.new(root: Frame,context: any): any
    if root:FindFirstChild("PFSetupV2") then return SoloV2.new(root,context) end
    local self: any=setmetatable({root=root,context=context,settings=Model.defaults(),connections={},visible=false,destroyed=false,
        preview=Preview.new(context.mapSources)},Screen)
    local body=Parts.flat(root.Body) -- r5: Left / Center / Right sit inside anchoring groups
    -- the summary moved left in lobby-screens v14 (M4); a v13 tree still has it on the right
    self.mapPanel=body.Left.Panels.MapPanel;self.summary=body.Left.Panels:FindFirstChild("Summary") or body.Right.Panels.Summary;self.actions=body.Right.Actions
    self.face=body.Right.Panels:FindFirstChild("Face")
    self.column=Column.new(body.Center.Column,{reduced=context.reducedMotion,onChange=function(settings) self.settings=settings;self:paint() end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    for _,tap in Parts.taps(Parts.find(root,"Header").Back,root) do listen(tap,function() if context.back then context.back() end end) end
    Parts.bindMapTile(self.mapPanel,{reduced=context.reducedMotion,editable=function() return true end,onPick=function()
        context.openPicker(self.settings.gameMap,function(map) if map then self.settings=Model.setMap(self.settings,map) end;self:paint() end)
    end},self.connections)
    local start=self.actions.Start
    listen(start.Activated,function() self:start() end)
    listen(start.MouseButton1Down,function() local p=start:FindFirstChild("PFPress");if p then p.Scale=.97 end end)
    listen(start.MouseButton1Up,function() local p=start:FindFirstChild("PFPress");if p then Tween:Create(p,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end end)
    self:paint()
    return self
end
function Screen:paint()
    if self.destroyed then return end
    self.column:set(self.settings,false)
    Parts.paintMap(self.mapPanel,self.preview,self.settings.gameMap,true)
    Parts.paintSummary(self.summary,self.settings)
    self:paintFace()
    self:thumbs()
end
local TEXT,MUTED,DIM=Color3.fromHex("#f2f2f2"),Color3.fromHex("#9a9a9a"),Color3.fromHex("#6f6f6f")
-- "You'll face": what the AI brings (counts + the difficulty ladder) and every rule you changed.
function Screen:paintFace()
    local face=self.face;if not face then return end
    local s=self.settings
    face.Counts.Nations.Number.Text=tostring(s.nations);face.Counts.Nations.Caption.Text=if s.nations==1 then "AI nation" else "AI nations"
    face.Counts.Tribes.Number.Text=tostring(s.bots);face.Counts.Tribes.Caption.Text=if s.bots==1 then "tribe" else "tribes"
    for _,name in Model.DIFFICULTIES do
        local row=face.Ladder:FindFirstChild(name);if not row then continue end
        local on=s.nations>0 and s.difficulty==name
        row.BackgroundTransparency=if on then 0 else 1
        local stroke=row:FindFirstChild("PFStroke");if stroke then stroke.Transparency=if on then 0 else 1 end
        row.Head.Title.TextColor3=if on then TEXT else MUTED;row.Detail.TextColor3=if on then MUTED else DIM
        for _,icon in row.Head.Icons:GetChildren() do if icon:IsA("ImageLabel") then icon.ImageTransparency=if on then 0 else .55 end end
    end
    face.LadderNote.Visible=s.nations==0
    local lines=Model.ruleLines(s)
    for index=1,8 do
        local line=face.Rules:FindFirstChild("Line"..index)
        if line then line.Visible=lines[index]~=nil;line.Text=lines[index] or "" end
    end
    face.Rules.Standard.Visible=#lines==0
    local more=face.Rules:FindFirstChild("More");if more then more.Visible=#lines>8;more.Text="+"..(#lines-8).." more" end
end
function Screen:start()
    local config,problem=Model.soloConfig(self.settings)
    local caption=self.actions.Caption
    if not config then caption.Text=problem or "Some settings are not available.";caption.TextColor3=Color3.fromHex("#ff7a70");return end
    caption.Text=CAPTION;caption.TextColor3=Color3.fromHex("#8c8c8c")
    if self.context.startSolo then self.context.startSolo(config) end
end
function Screen:thumbs()
    self.preview:update({self.mapPanel.Tile},Parts.find(self.root.Body,"Left").Panels,self.visible)
end
function Screen:update(_model: any) end
function Screen:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then self.actions.Caption.Text=CAPTION;self.actions.Caption.TextColor3=Color3.fromHex("#8c8c8c");self:paint() else self:thumbs() end
end
function Screen:handleEscape(): boolean return false end -- the controller closes the screen
function Screen:focusActive() game:GetService("GuiService").SelectedObject=self.actions.Start end
function Screen:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.column:destroy();self.preview:dispose()
end
return Screen
