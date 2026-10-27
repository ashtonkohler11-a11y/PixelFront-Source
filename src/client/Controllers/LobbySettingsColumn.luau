--!strict
-- PF019 B1 (PF - 3): THE settings column (approved M4/M9), shared by the Solo, Create Lobby and
-- waiting Room screens. Binds one authored Column (tools/atlas/author-pf019-lobby-screens.luau)
-- to a W6 settings table: :set(settings, readOnly) paints every control from LobbySettingsModel;
-- inputs produce a NEW settings table through options.onChange(settings, key). Read-only (a
-- room member) shows the host's choices with every control inert. Content and colour only:
-- the slider fill/knob follow the value inside their authored track (Scale), nothing is sized.
local Input=game:GetService("UserInputService")
local Tween=game:GetService("TweenService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Contract=require(Shared.LobbyContract)
local Availability=require(Shared.OpenFrontMatchAvailability)
local Icons=require(script.Parent.ReferenceIcons)
local Column={};Column.__index=Column
local C={on=Color3.fromHex("#3678ff"),off=Color3.fromHex("#3a3a3a"),text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),
    dim=Color3.fromHex("#5a5a5a"),line=Color3.fromHex("#3a3a3a"),red=Color3.fromHex("#ff5a52"),redSoft=Color3.fromHex("#3a1a1a"),raised=Color3.fromHex("#262626")}
export type Options={onChange: (any,string)->(), reduced: (()->boolean)?}

function Column.new(root: ScrollingFrame,options: Options): any
    local self: any=setmetatable({root=root,options=options,settings=Model.defaults(),readOnly=false,connections={},drag=nil,destroyed=false},Column)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local function change(nextSettings: any,key: string)
        if self.readOnly or self.destroyed then return end
        self.settings=nextSettings;self:paint();options.onChange(nextSettings,key)
    end
    self.change=change
    local mode=root.Mode
    listen(mode.ModeSeg.FFA.Activated,function() change(Model.setMode(self.settings,"Free For All"),"gameMode") end)
    listen(mode.ModeSeg.Team.Activated,function() change(Model.setMode(self.settings,"Team"),"gameMode") end)
    for _,value in Model.TEAM_CHIPS do
        local chip=mode.Teams:FindFirstChild(if value=="Humans Vs Nations" then "TeamHvN" else "Team"..tostring(value))
        if chip then listen(chip.Activated,function() change(Model.setTeams(self.settings,value),"playerTeams") end) end
    end
    for _,name in Contract.Difficulties do
        listen(root.Nations.Difficulty[name].Activated,function() change(Model.setDifficulty(self.settings,name),"difficulty") end)
    end
    -- sliders: press anywhere on the hit strip, drag to set
    for _,spec in {{row=root.Nations.NationsSlider,key="nations",max=Availability.MaxNations},{row=root.Nations.TribesSlider,key="bots",max=Availability.MaxTribes}} do
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
    -- steppers
    local function stepperOf(row: Instance): any return row:FindFirstChild("Stepper") end
    local steppers={{root.Economy.StartingGold,"startingGold"},{root.Economy.GoldIncome,"goldMultiplier"},
        {root.Rules.Grid.Left.AllianceLength,"customAllianceDuration"},{root.Rules.Grid.Right.TimeLimit,"maxTimerValue"},{root.Rules.Grid.Right.Overtime,"overtime"}}
    for _,pair in steppers do
        local stepper=stepperOf(pair[1]);local key=pair[2]
        listen(stepper.Minus.Activated,function() change(Model.step(key,self.settings,-1),key) end)
        listen(stepper.Plus.Activated,function() change(Model.step(key,self.settings,1),key) end)
    end
    local speed=stepperOf(root.Rules.Grid.Right.DoomsdaySpeed)
    listen(speed.Minus.Activated,function() change(Model.stepClock(self.settings,-1),"doomsdayClock") end)
    listen(speed.Plus.Activated,function() change(Model.stepClock(self.settings,1),"doomsdayClock") end)
    -- switches
    local switches={{root.Economy.InfiniteGold,"infiniteGold"},{root.Economy.InfiniteTroops,"infiniteTroops"},{root.Economy.InstantBuild,"instantBuild"},
        {root.Rules.Grid.Left.RandomSpawn,"randomSpawn"},{root.Rules.Grid.Left.DonateGold,"donateGold"},{root.Rules.Grid.Left.DonateTroops,"donateTroops"},
        {root.Rules.Grid.Right.TimeLimit,"maxTimerValue"},{root.Rules.Grid.Right.Doomsday,"doomsdayClock"},{root.Rules.Grid.Right.Overtime,"overtime"}}
    self.switches=switches
    for _,pair in switches do
        local key=pair[2];listen(pair[1].Switch.Activated,function() change(Model.toggle(key,self.settings),key) end)
    end
    -- weapon bans
    for _,tile in root.Bans.Tiles:GetChildren() do
        if not tile:IsA("TextButton") then continue end
        local unit=tile:GetAttribute("Unit")
        if type(unit)=="string" then listen(tile.Activated,function() change(Model.toggleUnit(self.settings,unit),"disabledUnits") end)
            local icon=tile:FindFirstChild("Icon");local source=icon and icon:GetAttribute("SourceAsset")
            if icon and type(source)=="string" then pcall(Icons.bind,icon,source) end
        elseif tile.Name=="Clear" then listen(tile.Activated,function() change(Model.clearBans(self.settings),"disabledUnits") end) end
    end
    self:paint()
    return self
end
function Column:dragTo(x: number)
    local drag=self.drag;if not drag then return end
    local track=drag.spec.row.Track
    local t=math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
    local value=math.floor(t*drag.spec.max+.5)
    if value==self.settings[drag.spec.key] then return end
    local nextSettings=if drag.spec.key=="nations" then Model.setNations(self.settings,value) else Model.setBots(self.settings,value)
    self.change(nextSettings,drag.spec.key)
end
-- Paint every control from the current settings (instant; colour/text/visibility + slider fill).
function Column:set(settings: any,readOnly: boolean?)
    self.settings=Model.normalize(settings);self.readOnly=readOnly==true;self:paint() -- PF021: "default"/"disabled" nations become counts
end
local function lit(button: any,on: boolean,filled: boolean?)
    button.BackgroundTransparency=if on and filled~=false then 0 else 1
    button.TextColor3=if on then C.text else C.muted
end
local function chip(button: any,on: boolean)
    button.BackgroundColor3=if on then Color3.fromHex("#1a2238") else C.raised
    button.TextColor3=if on then C.text else C.muted
    local stroke=button:FindFirstChildOfClass("UIStroke");if stroke then stroke.Color=if on then C.on else C.line;stroke.Thickness=if on then 2 else 1 end
end
function Column:paint()
    local s=self.settings;local root=self.root;local ro=self.readOnly
    local function interactive(node: any,on: boolean) if node:IsA("GuiButton") then node.Active=on;node.Selectable=on;node.AutoButtonColor=false end end
    -- mode
    local team=s.gameMode=="Team"
    lit(root.Mode.ModeSeg.FFA,not team);lit(root.Mode.ModeSeg.Team,team)
    for _,value in Model.TEAM_CHIPS do
        local c=root.Mode.Teams:FindFirstChild(if value=="Humans Vs Nations" then "TeamHvN" else "Team"..tostring(value))
        if c then chip(c,team and s.playerTeams==value);c.Visible=true;interactive(c,not ro) end
    end
    root.Mode.Teams.Visible=team
    -- nations (AI)
    for _,name in Contract.Difficulties do local b=root.Nations.Difficulty[name];lit(b,s.difficulty==name);interactive(b,not ro and s.nations>0) end
    root.Nations.DifficultyHint.Text=if s.nations==0 then "No nations: difficulty does not apply." else (Model.DIFFICULTY_HINTS[s.difficulty] or "")
    for _,spec in {{root.Nations.NationsSlider,"nations",Availability.MaxNations},{root.Nations.TribesSlider,"bots",Availability.MaxTribes}} do
        local row,key,max=spec[1],spec[2],spec[3]
        local t=if max>0 then math.clamp(s[key]/max,0,1) else 0
        row.Value.Text=Model.value(key,s)
        row.Track.Fill.Size=UDim2.fromScale(t,1);row.Track.Knob.Position=UDim2.fromScale(t,.5)
        row.Track.Knob.Visible=not ro;interactive(row.Hit,not ro)
    end
    -- steppers
    local function stepper(row: any,key: string,on: boolean)
        local st=row.Stepper
        st.Value.Text=if key=="doomsdayClock" then Model.value("doomsdayClock",s) else Model.value(key,s)
        st.Value.TextColor3=if on then C.text else C.dim
        for _,pair in {{st.Minus,-1},{st.Plus,1}} do
            local can=on and not ro and (if key=="doomsdayClock" then true else Model.canStep(key,s,pair[2]))
            pair[1].TextColor3=if can then C.text else C.dim;interactive(pair[1],can)
        end
        st.Visible=not (ro and not on)
    end
    stepper(root.Economy.StartingGold,"startingGold",true);stepper(root.Economy.GoldIncome,"goldMultiplier",true)
    stepper(root.Rules.Grid.Left.AllianceLength,"customAllianceDuration",true)
    stepper(root.Rules.Grid.Right.TimeLimit,"maxTimerValue",s.maxTimerValue~=nil)
    stepper(root.Rules.Grid.Right.Overtime,"overtime",s.overtime~=nil)
    stepper(root.Rules.Grid.Right.DoomsdaySpeed,"doomsdayClock",s.doomsdayClock~=nil)
    root.Rules.Grid.Right.DoomsdaySpeed.Label.TextColor3=if s.doomsdayClock~=nil then Color3.fromHex("#d9d9d9") else C.dim
    -- switches (knob slides 0.12s)
    local reduced=self.options.reduced and self.options.reduced()
    for _,pair in self.switches do
        local sw=pair[1].Switch;local on=Model.isOn(pair[2],s)
        sw.BackgroundColor3=if on then C.on else C.off;interactive(sw,not ro)
        local goal=UDim2.new(if on then 1 else 0,if on then -22 else 4,.5,0)
        if reduced or self.painted==nil then sw.Knob.Position=goal else Tween:Create(sw.Knob,TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=goal}):Play() end
    end
    -- weapon bans
    local banned=0
    for _,tile in root.Bans.Tiles:GetChildren() do
        if not tile:IsA("TextButton") then continue end
        local unit=tile:GetAttribute("Unit")
        if type(unit)=="string" then
            local on=table.find(s.disabledUnits,unit)~=nil;if on then banned+=1 end
            tile.BackgroundColor3=if on then C.redSoft else C.raised
            local stroke=tile:FindFirstChildOfClass("UIStroke");if stroke then stroke.Color=if on then C.red else C.line;stroke.Thickness=if on then 2 else 1 end
            tile.Slash.Visible=on;tile.Banned.Visible=on;tile.UnitName.TextColor3=if on then Color3.fromHex("#ff8a80") else Color3.fromHex("#d9d9d9")
            local icon=tile:FindFirstChild("Icon");if icon then icon.ImageTransparency=if on then .55 else 0 end
            interactive(tile,not ro)
        elseif tile.Name=="Clear" then interactive(tile,not ro and #s.disabledUnits>0);tile.TextColor3=if not ro and #s.disabledUnits>0 then C.text else C.dim;tile.Visible=not ro end
    end
    root.Bans.Head.Count.Text=if banned>0 then banned.." banned" else ""
    root.Bans.Head.Hint.Text=if ro then "The host chooses the weapon bans." else "Click a weapon to ban it for everyone in the match."
    for _,b in {root.Mode.ModeSeg.FFA,root.Mode.ModeSeg.Team} do interactive(b,not ro) end
    self.painted=true
end
function Column:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
return Column
