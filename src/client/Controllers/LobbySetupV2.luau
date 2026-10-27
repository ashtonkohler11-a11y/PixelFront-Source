--!strict
-- PF - 3 match setup v2 (UI review 2026-10-26; Ashton approved Solo / Create / Room v2). Binds one Screens.<name>.PFSetupV2
-- (tools/atlas/author-pf3-setup-v2.luau) to a W6 settings table, like LobbySettingsColumn does for the old column:
-- :set(settings, readOnly) paints everything from LobbySettingsModel; inputs produce a NEW settings table through
-- options.onChange(settings, key). Content and colour only (authored, Scale-laid); the slider fill/knob follow the value.
--   map stage + Change › (options.onPickMap) · skull cards · mode tiles + team chips · Nations / Tribes sliders
--   12 rule tiles (switches; ‹ value › steppers, Time limit runs Off ‹ 5 .. 120 ›) + Reset · bans: base weapons + premium items
-- V2.rules / V2.bans / V2.stepRule are pure (the model passed in): tools/test-pf3-setup-v2.luau.
local V2={};V2.__index=V2
V2.RULES={{"startingGold","v"},{"goldMultiplier","v"},{"customAllianceDuration","v"},{"maxTimerValue","v"},{"infiniteGold","t"},
    {"infiniteTroops","t"},{"instantBuild","t"},{"randomSpawn","t"},{"donateGold","t"},{"donateTroops","t"},{"doomsdayClock","t"},{"overtime","t"}}
V2.RULE_KEYS={"startingGold","goldMultiplier","customAllianceDuration","maxTimerValue","infiniteGold","infiniteTroops","instantBuild",
    "randomSpawn","donateGold","donateTroops","doomsdayClock","overtime"}

-- One stepper press. Time limit has an Off below its first value: ‹ at the first value turns it off, › from Off turns it on.
function V2.stepRule(M: any,key: string,settings: any,direction: number): any
    if key=="maxTimerValue" then
        if settings.maxTimerValue==nil then return if direction>0 then M.toggle(key,settings) else M.copy(settings) end
        if direction<0 and not M.canStep(key,settings,-1) then return M.toggle(key,settings) end
    end
    return M.step(key,settings,direction)
end
-- The 12 tiles as shown: {key, kind, on, text, minus, plus}.
function V2.rules(M: any,settings: any): {any}
    local out={}
    for _,spec in V2.RULES do
        local key,kind=spec[1],spec[2]
        if kind=="t" then table.insert(out,{key=key,kind=kind,on=M.isOn(key,settings)})
        else
            local off=key=="maxTimerValue" and settings.maxTimerValue==nil
            local words=if off then "Off" else M.value(key,settings)
            if words=="Default" then words=if key=="startingGold" then "Normal" else "Default" end
            table.insert(out,{key=key,kind=kind,on=not off,text=words,
                minus=if key=="maxTimerValue" then not off else M.canStep(key,settings,-1),
                plus=if key=="maxTimerValue" then (off or M.canStep(key,settings,1)) else M.canStep(key,settings,1)})
        end
    end
    return out
end
-- Bans: {units = {[unit] = banned}, premium = {[id] = banned}, count}.
function V2.bans(settings: any): any
    local units,premium,count={},{},0
    for _,u in settings.disabledUnits or {} do units[u]=true;count+=1 end
    for _,id in settings.disabledPremium or {} do premium[id]=true;count+=1 end
    return {units=units,premium=premium,count=count}
end
-- Reset: the 12 rules back to the contract defaults (everything else kept).
function V2.resetRules(M: any,settings: any): any
    local result=M.copy(settings);local defaults=M.defaults()
    for _,key in V2.RULE_KEYS do result[key]=defaults[key] end
    return result
end

local function find(root: Instance,path: string): any
    local node: any=root
    for part in string.gmatch(path,"[^.]+") do node=node and node:FindFirstChild(part) end
    return node
end
-- layer = Screens.<name>.PFSetupV2. options: {onChange(settings, key), onPickMap(), mapSources?, reduced?()}
function V2.new(layer: Frame,options: any): any
    local Input=game:GetService("UserInputService")
    local Shared=game:GetService("ReplicatedStorage").Shared
    local M=require(Shared.LobbySettingsModel)
    local Availability=require(Shared.OpenFrontMatchAvailability)
    local Icons=require(script.Parent.ReferenceIcons)
    local Preview=require(script.Parent.LobbyMapPreview)
    local canvas=layer:WaitForChild("Canvas")
    local self: any=setmetatable({layer=layer,canvas=canvas,options=options,M=M,Availability=Availability,settings=M.defaults(),readOnly=false,
        connections={},drag=nil,destroyed=false,preview=Preview.new(options.mapSources)},V2)
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    local function change(next: any,key: string)
        if self.readOnly or self.destroyed then return end
        self.settings=next;self:paint();options.onChange(next,key)
    end
    self.change=change
    local Line=require(script.Parent.TopbarLine)
    Line.keepRight(layer.Top,self.connections);Line.clearBelow(canvas,self.connections)
    listen(find(canvas,"MapCard.Change").Activated,function() if not self.readOnly and options.onPickMap then options.onPickMap() end end)
    for _,d in {"Easy","Medium","Hard","Impossible"} do listen(find(canvas,"Nations."..d).Activated,function() if self.settings.nations>0 then change(M.setDifficulty(self.settings,d),"difficulty") end end) end
    listen(find(canvas,"Mode.FFA").Activated,function() change(M.setMode(self.settings,"Free For All"),"gameMode") end)
    listen(find(canvas,"Mode.Team").Activated,function() change(M.setMode(self.settings,"Team"),"gameMode") end)
    for _,v in M.TEAM_CHIPS do
        local chip=find(canvas,"Mode.Teams."..(if v=="Humans Vs Nations" then "TeamHvN" else "Team"..tostring(v)))
        if chip then listen(chip.Activated,function() change(M.setTeams(self.settings,v),"playerTeams") end) end
    end
    for _,spec in {{row=find(canvas,"Forces.NationsSlider"),key="nations",max=Availability.MaxNations},{row=find(canvas,"Forces.TribesSlider"),key="bots",max=Availability.MaxTribes}} do
        local s: any=spec
        listen(s.row.Hit.InputBegan,function(input: InputObject)
            if self.readOnly then return end
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            self.drag={spec=s,input=input};self:dragTo(input.Position.X)
        end)
    end
    listen(Input.InputChanged,function(input: InputObject)
        local drag=self.drag;if not drag then return end
        if input==drag.input or input.UserInputType==Enum.UserInputType.MouseMovement then self:dragTo(input.Position.X) end
    end)
    listen(Input.InputEnded,function(input: InputObject)
        local drag=self.drag;if not drag then return end
        if input==drag.input or input.UserInputType==Enum.UserInputType.MouseButton1 then self.drag=nil end
    end)
    for _,spec in V2.RULES do
        local key,kind=spec[1],spec[2]
        local tile=find(canvas,"Rules.Grid.Tile_"..key)
        if not tile then continue end
        if kind=="t" then
            for _,b in {tile:FindFirstChild("Switch"),tile:FindFirstChild("Hit")} do if b then listen(b.Activated,function() change(M.toggle(key,self.settings),key) end) end end
        else
            listen(tile.Step.Minus.Activated,function() change(V2.stepRule(M,key,self.settings,-1),key) end)
            listen(tile.Step.Plus.Activated,function() change(V2.stepRule(M,key,self.settings,1),key) end)
        end
    end
    listen(find(canvas,"Rules.Reset").Activated,function() change(V2.resetRules(M,self.settings),"rules") end)
    -- bans: base weapons (the old tiles' art) and premium items (PremiumSprites.icons)
    local okSprites,Sprites=pcall(function() return require(Shared.PremiumSprites) end)
    for _,tile in canvas.Bans:GetChildren() do
        if not tile:IsA("TextButton") then continue end
        local unit,premium=tile:GetAttribute("Unit"),tile:GetAttribute("Premium")
        local icon=tile:FindFirstChild("Icon")
        if type(unit)=="string" then
            listen(tile.Activated,function() change(M.toggleUnit(self.settings,unit),"disabledUnits") end)
            local src=tile:GetAttribute("SourceAsset");if icon and type(src)=="string" then pcall(Icons.bind,icon,src) end
        elseif type(premium)=="string" then
            listen(tile.Activated,function() change(M.togglePremium(self.settings,premium),"disabledPremium") end)
            local rect=okSprites and Sprites.icons.rects[premium]
            if icon and rect then icon.Image=Sprites.icons.image;icon.ImageRectOffset=Vector2.new(rect.x,rect.y);icon.ImageRectSize=Vector2.new(rect.w,rect.h) end
        elseif tile.Name=="Clear" then listen(tile.Activated,function() change(M.clearBans(self.settings),"disabledUnits") end) end
    end
    listen(canvas:GetPropertyChangedSignal("AbsoluteSize"),function() self:thumbs() end)
    self:paint()
    return self
end
function V2:dragTo(x: number)
    local drag=self.drag;if not drag then return end
    local track=drag.spec.row.Track
    local t=math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
    local value=math.floor(t*drag.spec.max+.5)
    if value==self.settings[drag.spec.key] then return end
    self.change(if drag.spec.key=="nations" then self.M.setNations(self.settings,value) else self.M.setBots(self.settings,value),drag.spec.key)
end
function V2:set(settings: any,readOnly: boolean?)
    self.settings=self.M.normalize(settings);self.readOnly=readOnly==true;self:paint()
end
local C: any=nil
local function colours()
    local h=Color3.fromHex
    C={text=h("#eef1f6"),dim=h("#9aa3b2"),muted=h("#7a8392"),tile=h("#121722"),rim=h("#262d3a"),blue=h("#5b8cff"),blueA=h("#2a5bd7"),blueB=h("#1d3f9a"),
        red=h("#e5484d"),redA=h("#3a1820"),redB=h("#1f0e13"),skull=h("#c2475a"),skullOn=h("#ff6b7a"),chipRim=h("#2b3240"),
        onA=h("#1b3a78"),onB=h("#13275a"),offA=h("#141a26"),offB=h("#10141d"),discOn=h("#5b8cff"),discOff=h("#1a2030"),glyphOff=h("#7d879a"),
        swOn=h("#9fc0ff"),swOff=h("#2a303c"),knobOff=h("#8d97a6"),nameOff=h("#aab3c2"),ban=h("#ff5468"),banA=h("#2a1218"),banName=h("#ff7a88"),
        base=h("#151b27"),baseRim=h("#262d3a"),prem=h("#1d1a12"),premRim=h("#4d3f1a"),unitName=h("#c3cbd8")}
end
local function interactive(node: any,on: boolean) if node and node:IsA("GuiButton") then node.Active=on;node.Selectable=on;node.AutoButtonColor=false end end
local function setShade(node: any,a: Color3,b: Color3) local g=node:FindFirstChild("Shade");if g then g.Color=ColorSequence.new(a,b) end end
function V2:paint()
    if self.destroyed then return end
    if not C then colours() end
    local s,M,canvas,ro=self.settings,self.M,self.canvas,self.readOnly
    -- map
    local info=M.mapInfo(s.gameMap)
    find(canvas,"MapCard.MapName").Text=info.name
    local change=find(canvas,"MapCard.Change");change.Visible=not ro;interactive(change,not ro)
    self.preview:set(find(canvas,"MapCard.Well"),s.gameMap)
    -- difficulty
    for _,d in {"Easy","Medium","Hard","Impossible"} do
        local c=find(canvas,"Nations."..d);local on=s.nations>0 and s.difficulty==d
        c.BackgroundColor3=if on then C.redA else C.tile
        local rim=c:FindFirstChild("Rim");if rim then rim.Color=if on then C.red else C.rim;rim.Thickness=if on then 2 else 1.5 end
        for _,g in c.Skulls:GetChildren() do if g:IsA("ImageLabel") then g.ImageColor3=if on then C.skullOn else C.skull;g.ImageTransparency=if s.nations>0 then 0 else .6 end end
        interactive(c,not ro and s.nations>0)
    end
    -- mode
    local team=s.gameMode=="Team"
    for _,pair in {{"FFA",not team},{"Team",team}} do
        local t=find(canvas,"Mode."..pair[1]);local on=pair[2]
        t.BackgroundColor3=if on then C.blueA else C.tile
        local rim=t:FindFirstChild("Rim");if rim then rim.Color=if on then C.blue else C.rim;rim.Thickness=if on then 2 else 1.5 end
        t.Label.TextColor3=if on then Color3.new(1,1,1) else C.dim;t.Glyph.ImageColor3=if on then Color3.new(1,1,1) else C.dim
        interactive(t,not ro)
    end
    local teams=find(canvas,"Mode.Teams")
    for _,v in M.TEAM_CHIPS do
        local chip=teams:FindFirstChild(if v=="Humans Vs Nations" then "TeamHvN" else "Team"..tostring(v))
        if not chip then continue end
        local on=team and s.playerTeams==v
        chip.BackgroundColor3=C.blueA;chip.BackgroundTransparency=if on then 0 else 1
        chip.TextColor3=if on then Color3.new(1,1,1) elseif team then C.dim else C.muted
        local rim=chip:FindFirstChild("Rim");if rim then rim.Color=if on then C.blue else C.chipRim end
        interactive(chip,team and not ro)
    end
    teams.Key.TextTransparency=if team then 0 else .55
    -- forces
    for _,spec in {{"Forces.NationsSlider","nations",self.Availability.MaxNations},{"Forces.TribesSlider","bots",self.Availability.MaxTribes}} do
        local row=find(canvas,spec[1]);local v=s[spec[2]];local t=if spec[3]>0 then math.clamp(v/spec[3],0,1) else 0
        row.Value.Text=tostring(v);row.Track.Fill.Size=UDim2.fromScale(t,1);row.Track.Knob.Position=UDim2.fromScale(t,.5)
        row.Track.Knob.Visible=not ro;interactive(row.Hit,not ro)
    end
    -- rules
    for _,r in V2.rules(M,s) do
        local tile=find(canvas,"Rules.Grid.Tile_"..r.key);if not tile then continue end
        local lit=r.kind=="t" and r.on
        tile.BackgroundColor3=if lit then C.onA else C.offA;setShade(tile,if lit then C.onA else C.offA,if lit then C.onB else C.offB)
        local rim=tile:FindFirstChild("Rim");if rim then rim.Color=if lit then C.blue else C.rim;rim.Thickness=if lit then 2 else 1 end
        tile.RuleName.TextColor3=if lit then Color3.new(1,1,1) else C.nameOff
        if r.kind=="t" then
            local disc=tile.Disc;disc.BackgroundColor3=if r.on then C.discOn else C.discOff;disc.Glyph.ImageColor3=if r.on then Color3.new(1,1,1) else C.glyphOff
            local sw=tile.Switch;sw.BackgroundColor3=if r.on then C.swOn else C.swOff
            sw.Knob.BackgroundColor3=if r.on then Color3.new(1,1,1) else C.knobOff
            sw.Knob.Position=UDim2.fromScale(if r.on then 32/64 else 4/64,4/36)
            interactive(sw,not ro);interactive(tile:FindFirstChild("Hit"),not ro)
        else
            tile.Step.Value.Text=r.text
            for _,pair in {{tile.Step.Minus,r.minus},{tile.Step.Plus,r.plus}} do
                local can=pair[2] and not ro
                pair[1].TextColor3=if can then Color3.fromHex("#c3cbd8") else Color3.fromHex("#4a5160");interactive(pair[1],can)
            end
        end
    end
    local reset=find(canvas,"Rules.Reset");reset.Visible=not ro;interactive(reset,not ro)
    -- bans
    local b=V2.bans(s)
    for _,tile in canvas.Bans:GetChildren() do
        if not tile:IsA("TextButton") then continue end
        local unit,premium=tile:GetAttribute("Unit"),tile:GetAttribute("Premium")
        if type(unit)~="string" and type(premium)~="string" then
            if tile.Name=="Clear" then tile.Visible=not ro;interactive(tile,not ro and b.count>0);tile.TextColor3=if b.count>0 then C.dim else C.muted end
            continue
        end
        local banned=if type(unit)=="string" then b.units[unit]==true else b.premium[premium]==true
        local isPrem=type(premium)=="string"
        tile.BackgroundColor3=if banned then C.banA elseif isPrem then C.prem else C.base
        local rim=tile:FindFirstChild("Rim");if rim then rim.Color=if banned then C.red elseif isPrem then C.premRim else C.baseRim;rim.Thickness=if banned then 2 else 1 end
        tile.Slash.Visible=banned
        tile.Icon.ImageTransparency=if banned then .7 else 0
        tile.UnitName.TextColor3=if banned then C.banName else C.unitName
        interactive(tile,not ro)
    end
    self:thumbs()
end
function V2:thumbs()
    if self.destroyed then return end
    self.preview:update({find(self.canvas,"MapCard.Well")},self.canvas,self.layer.Visible and (self.layer.Parent :: any).Visible)
end
function V2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.preview:dispose()
end
return V2
