--!strict
-- PF011 authored Settings; public menu/session API retained. Shared lease owns capture.
local UIS=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UserSettings=require(Shared.UserSettings)
local Render=require(Shared.OpenFrontGraphicsSettings)
local Data=require(Shared.OpenFrontGraphicsData)
local Bindings=require(Shared.PixelFrontInputBindings)
local Capture=require(Shared.PixelFrontInputCapture)
local Accent=require(Shared.PixelFrontAccent)
local Typography=require(Shared.PixelFrontTypography)
local Surface=require(Shared.AtlasTheme)
local Layout=require(script.Parent.PixelFrontSettingsLayout)
local Presentation=require(script.Parent.PixelFrontSettingsPresentation)
local GraphicsController=require(script.Parent.GraphicsController)
local InputPrompts=require(script.Parent.InputPrompts)
local Controller={};local Methods={};Methods.__index=Methods
local Session={};Session.__index=Session
local function listen(self: any,signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
local function shown(node: Instance?,root: Instance): boolean
    if not node or not node.Parent or not node:IsDescendantOf(root) then return false end
    local current: Instance?=node
    while current do
        if current:GetAttribute("PFSettingRetired")==true then return false end
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current==root then return true end
        current=current.Parent
    end
    return true
end
function Controller.retire(node: Instance?)
    if not node then return end
    node:SetAttribute("PFSettingRetired",true);node:SetAttribute("AdvancedControl",false);node:SetAttribute("SourceDisabled",true)
    if node:IsA("GuiObject") then node.Visible=false;node.Active=false;node.Selectable=false end
    if node:IsA("GuiButton") then node.Interactable=false end
    for _,name in {"Toggle","Bind","Reset","Unbind","Select","Delete","Apply","Copy","Save","Test","Value"} do
        local control=node:FindFirstChild(name)
        if control and control:IsA("GuiObject") then control.Active=false;control.Selectable=false end
        if control and control:IsA("GuiButton") then control.Interactable=false end
        if control and control:IsA("TextBox") and control:IsFocused() then control:ReleaseFocus() end
    end
    local track=node:FindFirstChild("Track");local input=if track then track:FindFirstChild("Input") else nil
    if input and input:IsA("GuiButton") then input.Active=false;input.Selectable=false;input.Interactable=false end
    if Gui.SelectedObject==node or (Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(node)) then Gui.SelectedObject=nil end
end
function Controller.retireRows(scroll: Instance): number
    local count=0
    for section,ids in Layout.retired do local container=scroll:FindFirstChild(section)
        if container then for _,id in ids do local row=container:FindFirstChild(id);if row then Controller.retire(row);count+=1 end end end
    end
    local graphics=scroll:FindFirstChild("Graphics")
    if graphics then
        local retained={};for _,spec in Render.controls do retained[spec.id]=true end
        for _,spec in Data.controls do if not retained[spec.id]then local row=graphics:FindFirstChild(spec.id);if row then Controller.retire(row);count+=1 end end end
        for _,row in graphics:GetChildren() do if string.match(row.Name,"^Section%d+$") and row:GetAttribute("AdvancedControl")==true then Controller.retire(row)end end
        Controller.retire(graphics:FindFirstChild("naval-highlight-toggle"))
    end
    local audio=scroll:FindFirstChild("Audio")
    if audio then for _,channel in UserSettings.AudioChannels do local row=audio:FindFirstChild(channel)
        if row then Controller.retire(row:FindFirstChild("Test"));Controller.retire(row:FindFirstChild("PreviewHint")) end
    end end
    return count
end
function Controller.newMenuSession(pause: (boolean)->()): any
    return setmetatable({visible=false,preferences=false,shouldPause=false,wasPaused=false,pause=pause},Session)
end
function Session:open(shouldPause: boolean,wasPaused: boolean)
    self.visible=true;self.preferences=false;self.shouldPause=shouldPause;self.wasPaused=wasPaused
    if shouldPause and not wasPaused then self.pause(true) end
end
function Session:handoff(): boolean
    if not self.visible then return false end;self.visible=false;self.preferences=true;return true
end
function Session:returnToMenu() self.preferences=false;self.visible=true end
function Session:close(keepPause: boolean?)
    self.visible=false;self.preferences=false
    if not keepPause and self.shouldPause and not self.wasPaused then self.pause(false) end
end
function Controller.new(gui: ScreenGui,callbacks: any): any
    local root=gui:WaitForChild("Background");local ui=root:WaitForChild("UserSettings")
    -- PF019 W7: the approved M5 sheet (tools/atlas/author-pf019-settings.luau) has its own
    -- controller with this same API; the pre-W7 sheet keeps everything below.
    if ui:GetAttribute("PF019SettingsRevision") then
        return require(script.Parent.PF019SettingsController).new(gui,callbacks,Controller.newMenuSession(function(value)if callbacks.pause then callbacks.pause(value)end end))
    end
    local self=setmetatable({root=root,menu=root:WaitForChild("GameMenu"),ui=ui,body=ui.Body,scroll=ui.Body.Scroll,
        confirm=root:WaitForChild("SettingsConfirm"),settings=callbacks.preferences or UserSettings.new(),callbacks=callbacks,
        audio=callbacks.audio,connections={},sliderInfo={},activeTab="Gameplay",profile="keyboard",destroyed=false,watched={},
        session=Controller.newMenuSession(function(value)if callbacks.pause then callbacks.pause(value)end end)},Methods)
    self.isMac=callbacks.isMac==true
    Controller.retireRows(self.scroll)
    for _,name in {"SettingsJSON","SettingsEasterMessage","SettingsColorPicker"} do Controller.retire(root:FindFirstChild(name)) end
    -- PF019 C1 (PF - 2) rebuilds Background.GameMenu as the M13 menu and marks it
    -- PF019GameMenu=true; that menu is theirs (wiring, styling, geometry, Escape). Only
    -- the pre-M13 GameMenu is driven from here.
    if self:legacyMenu() then
        local actions=self.menu.Body.Actions
        if actions.Settings:FindFirstChild("Title")then actions.Settings.Title.Text="Settings"end
        if actions.Settings:FindFirstChild("Description")then actions.Settings.Description.Text="Adjust your view, sound and controls."end
        for _,name in {"Terrain","Debug","Development","SectionDivider1","SectionDivider2","Contributors","OpenFront"} do Controller.retire(actions:FindFirstChild(name)) end
        listen(self,actions.Settings.Activated,function()self:openPreferences()end)
        listen(self,actions.Exit.Activated,function()self:closeAll(true);if callbacks.exit then callbacks.exit()end end)
        listen(self,self.menu.Body.Header.Back.Activated,function()self:closeMenu()end)
        listen(self,self.menu.Backdrop.Activated,function()self:closeMenu()end)
    end
    listen(self,self.body.Header.Back.Activated,function()self:closeSettings()end)
    listen(self,self.ui.Backdrop.Activated,function()self:closeSettings()end)
    for _,name in Layout.tabs do listen(self,self.body.Tabs[name].Activated,function()self:setTab(name)end) end
    for _,spec in Layout.gameplay do local row=self.scroll.Gameplay:FindFirstChild(spec.id)
        if row then listen(self,row.Toggle.Activated,function()self.settings:set(spec.id,not self.settings:get(spec.id))end) end
    end
    self.addSlider=function(row,read,write,format)self:addSliderControl(row,read,write,format)end
    self:addSliderControl(self.scroll.Gameplay.attackRatio,function()return math.floor((if callbacks.ratio then callbacks.ratio()else self.settings:get("attackRatio"))*100+.5)end,function(value)self.settings:set("attackRatio",value/100)end,function(value)return tostring(value).."%"end)
    local increment=self.scroll.Gameplay.attackRatioIncrement
    listen(self,increment.Select.Activated,function()self:toggleChoices(increment.Choices)end)
    for _,value in {1,2,5,10,20} do listen(self,increment.Choices["Option"..value].Activated,function()self.settings:set("attackRatioIncrement",value);self:closeChoices();self:refresh()end) end
    for _,channel in UserSettings.AudioChannels do
        self:addSliderControl(self.scroll.Audio[channel],function()return math.floor(self.settings:audioVolume(channel)*100+.5)end,function(value)self.settings:setAudioVolume(channel,value/100)end,function(value)return tostring(value).."%"end)
    end
    listen(self,self.scroll.Audio.Reset.Activated,function()self:askReset("audio")end)
    self.graphics=GraphicsController.new(self)
    for _,spec in Bindings.keyboardActions do self:bindRow(self.scroll.Keybinds:FindFirstChild(spec.action),spec.action,"keyboard") end
    local pad=self.scroll.Keybinds:FindFirstChild("ControllerBindings")
    if pad then for _,spec in Bindings.gamepadActions do self:bindRow(pad:FindFirstChild(spec.action),spec.action,"gamepad")end end
    local profiles=self.scroll.Keybinds:FindFirstChild("Profiles")
    if profiles then for _,entry in {{"Keyboard","keyboard"},{"Controller","gamepad"},{"Touch","touch"}} do listen(self,profiles[entry[1]].Activated,function()self:setProfile(entry[2])end)end end
    local reset=self.scroll.Keybinds:FindFirstChild("ProfileReset");if reset then listen(self,reset.Activated,function()self:askReset(self.profile)end)end
    local cancel=self.ui:FindFirstChild("CaptureCancel");if cancel then listen(self,cancel.Activated,function()self:endCapture("cancelled");self:refresh()end)end
    listen(self,self.confirm.Body.Cancel.Activated,function()self:finishReset(false)end)
    listen(self,self.confirm.Body.Confirm.Activated,function()self:finishReset(true)end)
    listen(self,UIS.InputChanged,function(input)self:moveSliderDrag(input)end)
    listen(self,UIS.InputEnded,function(input)self:endSliderDrag(input)end)
    listen(self,UIS.WindowFocusReleased,function()self:endSliderDrag();self:endCapture("focus-lost");self:closeChoices();self:refresh()end)
    listen(self,UIS.GamepadDisconnected,function()self:endCapture("disconnected");self:deviceChanged()end)
    listen(self,UIS.GamepadConnected,function()self:deviceChanged()end)
    listen(self,UIS:GetPropertyChangedSignal("PreferredInput"),function()self:deviceChanged()end)
    listen(self,UIS.TextBoxFocused,function()self:endCapture("text-focus");self:refresh()end)
    listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function()self:refresh()end)
    listen(self,self.ui:GetPropertyChangedSignal("Visible"),function()if not self.ui.Visible then self:endCapture("hidden");self:endSliderDrag();self:finishReset(false);self:closeChoices()end end)
    listen(self,Gui:GetPropertyChangedSignal("SelectedObject"),function()
        local selected=Gui.SelectedObject
        if self.listening and selected~=self.captureControl then self:endCapture("selection-changed");self:refresh()end
        if selected and shown(selected,self.ui) then self:scrollToControl(selected)end
    end)
    self.off=self.settings:subscribe(function(key,value)if callbacks.settingsChanged then callbacks.settingsChanged(key,value,self.settings)end;self:refresh()end)
    self.captureOff=Capture.subscribe(function(active)if not active and self.listening then self.listening=nil;self.captureControl=nil;self.captureRelease=nil;self:refresh()end end)
    self.accentOff=Accent.bind(self.ui,self.settings);self.confirmAccentOff=Accent.bind(self.confirm,self.settings)
    self.motion=Presentation.new(self.ui,self.settings);self.confirmMotion=Presentation.new(self.confirm,self.settings)
    Typography.applyTree(self.ui);Typography.applyTree(self.confirm)
    if self:legacyMenu() then self.menuAccentOff=Accent.bind(self.menu,self.settings);self.menuMotion=Presentation.new(self.menu,self.settings);Typography.applyTree(self.menu) end
    self:deviceChanged();return self
end
function Methods:isGamepad(): boolean return UIS.PreferredInput==Enum.PreferredInput.Gamepad end
-- True for the pre-M13 GameMenu this controller drives; false once PF - 2's M13 menu
-- (PF019GameMenu=true) owns Background.GameMenu.
function Methods:legacyMenu(): boolean
    local menu=self.menu
    return menu~=nil and menu:GetAttribute("PF019GameMenu")~=true and menu:FindFirstChild("Body")~=nil
end
-- PF019 C1/C2 contract: the M13 menu passes a function that re-opens it; Back from the
-- in-match Settings sheet calls it (instead of re-showing the pre-M13 menu).
function Methods:setMenuReturn(callback: (() -> ())?) self.menuReturn=callback end
local function legacyFocus(self: any): GuiObject? return if self:legacyMenu() then self.menu.Body.Actions.Settings else nil end
function Methods:deviceChanged()
    self:endCapture("device-changed");InputPrompts.invalidate()
    self.profile=if UIS.PreferredInput==Enum.PreferredInput.Gamepad then "gamepad" elseif UIS.PreferredInput==Enum.PreferredInput.Touch then "touch" else "keyboard"
    self:refresh()
    if self:isGamepad() and self:isBlocking() and not shown(Gui.SelectedObject,self.ui) then
        Gui.SelectedObject=if self.confirm.Visible then self.confirm.Body.Cancel elseif self.ui.Visible then self.body.Tabs[self.activeTab] else legacyFocus(self)
    end
end
function Methods:bindRow(row: any,action: string,profile: string)
    if not row then return end
    listen(self,row.Bind.Activated,function()self:beginCapture(action,profile,row.Bind)end)
    listen(self,row.Unbind.Activated,function()
        self:endCapture("unbind")
        if profile=="keyboard" then self:setBinding(action,"Null","") else local ok,reason=self.settings:rebindGamepad(action,"Null");if not ok then self:message(reason or "Cannot clear this binding.")end end
        self:refresh()
    end)
    listen(self,row.Reset.Activated,function()
        self:endCapture("reset")
        if profile=="keyboard" then local default=UserSettings.defaultKeybinds(self.isMac)[action];self:setBinding(action,default or "Null",default or "")
        else local ok,reason=self.settings:rebindGamepad(action,Bindings.defaultGamepadBindings()[action]);if not ok then self:message(reason or "Another action uses the default button. Clear it first.")end end
        self:refresh()
    end)
end
function Methods:message(value: string)
    self.ui.SettingsMessage.Text=value;self.ui.SettingsMessage.Visible=true
    self.toastSerial=(self.toastSerial or 0)+1;local serial=self.toastSerial
    task.delay(3,function()if not self.destroyed and serial==self.toastSerial then self.ui.SettingsMessage.Visible=false end end)
end
function Methods:setBinding(action: string,value: string,key: string): boolean
    -- Raw rebind preserves keyboard record formats and conflicts; no new storage writer.
    if not self.settings:rebindKeyboardEffective(action,value,key,self.isMac) then self:message("That key is already assigned. Clear its other action first.");return false end
    return true
end
local keyNames={} -- Retained method boundary; shared resolver owns key codes.
function Controller.code(key: Enum.KeyCode): string return Bindings.keyboardCode(key) end
function Controller.formatKey(value: string): string
    if string.sub(value,1,6)=="Shift+" then return "Shift+"..Controller.formatKey(string.sub(value,7))end
    if value==" " or value=="Space" then return "Space"end
    if string.match(value,"^Digit%d$") then return string.sub(value,6)end
    if string.match(value,"^Key%u$") then return string.sub(value,4)end
    return value
end
function Methods:beginCapture(action: string,profile: string,control: GuiObject)
    if not self.ui.Visible or self.confirm.Visible then return end
    self:endCapture("replaced");self:endSliderDrag();self:closeChoices()
    self.listening=action;self.captureProfile=profile;self.captureControl=control
    if self:isGamepad() then Gui.SelectedObject=control end
    self.captureRelease=Capture.begin(self,function(code)
        if self.destroyed or not self.ui.Visible then return true end
        if profile=="keyboard" then return self:setBinding(action,code,code)end
        local ok,reason=self.settings:rebindGamepad(action,code)
        if not ok then self:message(reason or "That button cannot be assigned to this action.")end
        return ok
    end,function()self.listening=nil;self.captureControl=nil;self.captureRelease=nil;if not self.destroyed then self:refresh()end end,{profile=profile})
    self:refresh()
end
function Methods:endCapture(reason: string?)
    Capture.releaseOwner(self,reason or "cancelled");self.listening=nil;self.captureControl=nil;self.captureRelease=nil
    local hint=self.ui:FindFirstChild("CaptureHint");if hint then hint.Visible=false end
    local cancel=self.ui:FindFirstChild("CaptureCancel");if cancel then cancel.Visible=false end
end
function Methods:isCapturingInput(): boolean return self.listening~=nil and Capture.isCapturingInput() end
function Methods:handleInput(input: InputObject): boolean
    if self:isCapturingInput() then return true end -- Candidate processing is in the shared early CAS lease.
    if self.ui.Visible and not self.confirm.Visible and string.sub(input.UserInputType.Name,1,7)=="Gamepad" then
        local target=Gui.SelectedObject
        while target and target~=self.ui do local slider=self.sliderInfo[target]
            if slider and (input.KeyCode==Enum.KeyCode.ButtonL1 or input.KeyCode==Enum.KeyCode.ButtonR1) then
                local minimum,maximum=target:GetAttribute("Min"),target:GetAttribute("Max");local step=target:GetAttribute("Step") or 1
                local amount=math.max(step,math.floor((maximum-minimum)/20/step+.5)*step)
                slider.write(math.clamp(slider.read()+(if input.KeyCode==Enum.KeyCode.ButtonR1 then amount else -amount),minimum,maximum));self:refresh();return true
            end;target=target.Parent
        end
    end
    return false
end
function Methods:handleEasterKey(_key: string,_contained: boolean): boolean return false end
function Methods:handleEscape(): boolean
    if self:isCapturingInput() then self:endCapture("back");self:refresh();return true end
    if self.confirm.Visible then self:finishReset(false);return true end
    if self.ui.Visible and self:closeChoices() then self:refresh();return true end
    if self.ui.Visible then self:closeSettings();return true end
    if self:legacyMenu() and self.menu.Visible then self:closeMenu();return true end
    return false
end
function Methods:setProfile(profile: string)
    if profile~="keyboard" and profile~="gamepad" and profile~="touch" then return end
    self:endCapture("profile-changed");self:closeChoices();self:endSliderDrag();self.profile=profile;self.scroll.CanvasPosition=Vector2.zero;self:refresh()
end
function Methods:setTab(name: string)
    if name=="Appearance" then name="Graphics"elseif name=="Controls"then name="Keybinds"end
    if not table.find(Layout.tabs,name) or name==self.activeTab then return end
    self:endCapture("tab-changed");self:endSliderDrag();self:closeChoices();self.activeTab=name;self.scroll.CanvasPosition=Vector2.zero
    if self.callbacks.tabChanged then self.callbacks.tabChanged(name,self)end
    self:refresh();if self:isGamepad() then Gui.SelectedObject=self.body.Tabs[name]end
end
function Methods:toggleChoices(choices: GuiObject)
    local wasOpen=choices.Visible;self:closeChoices();choices.Visible=not wasOpen;self:refresh()
    if choices.Visible and self:isGamepad() then for _,child in choices:GetChildren()do if child:IsA("GuiButton") and child.Active then Gui.SelectedObject=child;break end end end
end
function Methods:closeChoices(): boolean
    local closed=false
    for _,section in {self.scroll.Gameplay,self.scroll.Graphics} do for _,row in section:GetChildren()do local choices=row:FindFirstChild("Choices")
        if choices and choices:IsA("GuiObject") and choices.Visible then choices.Visible=false;closed=true
            if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(choices)then Gui.SelectedObject=row:FindFirstChild("Select")end
        end
    end end;return closed
end
function Methods:addSliderControl(row: any,read: any,write: any,format: any)
    if not row then return end;self.sliderInfo[row]={read=read,write=write,format=format}
    listen(self,row.Track.Input.InputBegan,function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then self:beginSliderDrag(row,input,write)end end)
    if row.Value:IsA("TextBox") then listen(self,row.Value.FocusLost,function()
        local value=tonumber(row.Value.Text);if value and value==value and math.abs(value)<math.huge then local step=row:GetAttribute("Step") or 1;local minimum=row:GetAttribute("Min");write(math.clamp(minimum+math.floor((value-minimum)/step+.5)*step,minimum,row:GetAttribute("Max")))end;self:refresh()
    end)end
end
function Methods:beginSliderDrag(row: GuiObject,input: InputObject,write: any)
    if self.drag or self:isCapturingInput() or not shown(row,self.ui)then return end
    self.drag={row=row,input=input,write=write,scrolling=self.scroll.ScrollingEnabled}
    if input.UserInputType==Enum.UserInputType.Touch then self.scroll.ScrollingEnabled=false end
    self:updateSlider(Vector2.new(input.Position.X,input.Position.Y))
end
function Methods:updateSlider(position: Vector2)
    local drag=self.drag;if not drag then return end
    local row=drag.row;local minimum,maximum=row:GetAttribute("Min"),row:GetAttribute("Max");local step=row:GetAttribute("Step")or 1
    local fraction=math.clamp((position.X-row.Track.AbsolutePosition.X)/math.max(1,row.Track.AbsoluteSize.X),0,1)
    drag.write(math.clamp(minimum+math.floor(fraction*(maximum-minimum)/step+.5)*step,minimum,maximum));self:refresh()
end
function Methods:moveSliderDrag(input: InputObject)
    local drag=self.drag;if not drag then return end
    if input==drag.input or (drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)then self:updateSlider(Vector2.new(input.Position.X,input.Position.Y))end
end
function Methods:endSliderDrag(input: InputObject?)
    local drag=self.drag;if not drag then return end
    if input and input~=drag.input and not (drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1)then return end
    self.scroll.ScrollingEnabled=drag.scrolling;self.drag=nil
end
function Methods:askReset(kind: string)
    if kind=="touch" then return end
    self:endCapture("reset");self:endSliderDrag();self:closeChoices();self.resetKind=kind;self.confirmReturn=Gui.SelectedObject
    self.confirm.Body.Message.Text="Restore "..(if kind=="gamepad"then "controller bindings"elseif kind=="keyboard"then "keyboard bindings"elseif kind=="audio"then "audio volumes"else "appearance preferences").." to defaults?"
    self.confirm.Visible=true;self:refresh();if self:isGamepad()then Gui.SelectedObject=self.confirm.Body.Cancel end
end
function Methods:finishReset(accepted: boolean)
    local kind=self.resetKind;self.resetKind=nil;self.confirm.Visible=false
    if accepted and kind then
        if kind=="audio"then self.settings:resetAudio()
        elseif kind=="gamepad"then self.settings:resetGamepadBindings()
        elseif kind=="keyboard"then self.settings:setKeybinds({})
        elseif kind=="appearance"then self.settings:setGraphicsOverrides({});self.settings:resetVfx();self.settings:resetInterfaceAccent();self.settings:set("emojis",true)end
    end
    local target=self.confirmReturn;self.confirmReturn=nil
    if target and shown(target,self.ui) and target.Selectable then Gui.SelectedObject=target end
    if not self.destroyed then self:refresh()end
end
function Methods:openMenu(shouldPause: boolean,wasPaused: boolean)
    if not self:legacyMenu() then return end
    self:closeSettings(false);self.session:open(shouldPause,wasPaused);self.menu.Visible=true;self:refresh()
    if self:isGamepad()then Gui.SelectedObject=self.menu.Body.Actions.Settings end
end
-- In-match Settings. Tab: "Gameplay" by default. With the M13 menu, Back runs the
-- callback from setMenuReturn; with the pre-M13 menu it re-shows that menu.
function Methods:openPreferences(tab: string?)
    if not self:legacyMenu() then
        local back=self.menuReturn
        self:openSettings(function() if back then back() end end)
        self:setTab(tab or "Gameplay");return
    end
    if self.session:handoff()then self.menu.Visible=false;self:openSettings(function()self.session:returnToMenu();self.menu.Visible=true;self:refresh();if self:isGamepad()then Gui.SelectedObject=self.menu.Body.Actions.Settings end end)
        if tab then self:setTab(tab) end
    end
end
function Methods:closeMenu(keepPause: boolean?)
    if not self:legacyMenu() or not self.menu.Visible then return end;self.menu.Visible=false;self.session:close(keepPause)
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.menu)then Gui.SelectedObject=nil end
    if self.menuMotion then self.menuMotion:refresh()end
end
function Methods:openSettings(onReturn: any)
    self.onReturn=onReturn;if onReturn then self:setTab("Gameplay")end
    self.focusReturn=Gui.SelectedObject;self.ui.Visible=true;self:refresh();if self:isGamepad()then Gui.SelectedObject=self.body.Tabs[self.activeTab]end
end
function Methods:setAtlasHost(host: Frame?)
    if self.hostConnection then self.hostConnection:Disconnect();self.hostConnection=nil end;self.atlasHost=host
    -- PF015: the Atlas host's rect inside Background is authored on the host
    -- (PFHostPosition/PFHostSize, tools/atlas/author-pf015-pages.luau); nothing
    -- is measured. The sheet still lays out its rows from the host size (the
    -- same engine serves the in-match settings).
    local position=if host then host:GetAttribute("PFHostPosition") else nil
    local size=if host then host:GetAttribute("PFHostSize") else nil
    self.ui.Position=if typeof(position)=="UDim2" then position else UDim2.new()
    self.ui.Size=if typeof(size)=="UDim2" then size else UDim2.fromScale(1,1)
    self.ui.Backdrop.Visible=host==nil;self.ui.BackgroundTransparency=1
    if host then self.hostConnection=host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()self:refresh()end)end
    self:refresh()
end
function Methods:closeSettings(runReturn: boolean?)
    self:endCapture("closed");self:endSliderDrag();self:closeChoices();self:finishReset(false)
    if not self.ui.Visible then return end;self.ui.Visible=false
    local selected=Gui.SelectedObject;if selected and selected:IsDescendantOf(self.ui)then Gui.SelectedObject=nil end
    local target=self.focusReturn;self.focusReturn=nil;if target and shown(target,self.root) and target.Selectable then Gui.SelectedObject=target end
    local callback=self.onReturn;self.onReturn=nil;if runReturn~=false and callback then callback()end
    if self.motion then self.motion:refresh()end
end
function Methods:closeAll(keepPause: boolean?)
    self:closeSettings(false)
    if not self:legacyMenu() then return end
    if self.menu.Visible or self.session.preferences then self.menu.Visible=false;self.session:close(keepPause)end
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.menu)then Gui.SelectedObject=nil end
    if self.menuMotion then self.menuMotion:refresh()end
end
function Methods:isBlocking(): boolean return self.ui.Visible or (self:legacyMenu() and self.menu.Visible) or self.confirm.Visible end
function Methods:setMapLayers(_layers: {any}) end -- Retired customization; ordinary map layers remain.
function Methods:toggleTerrain() end
function Methods:setAlternateView(_value: boolean) end
function Methods:previewAudio(_category: string) end
function Methods:setPersistenceStatus(message: string)self.body.Persistence.Text=message;self:refresh()end
function Methods:setAudioControls(audio: any)self.audio=audio;self:refresh()end
function Methods:scrollToControl(control: GuiObject)
    local node: Instance?=control.Parent
    while node and node~=self.body do
        if node:IsA("ScrollingFrame")then
            local top=control.AbsolutePosition.Y-node.AbsolutePosition.Y;local bottom=top+control.AbsoluteSize.Y
            local change=if top<4 then top-4 elseif bottom>node.AbsoluteSize.Y-4 then bottom-node.AbsoluteSize.Y+4 else 0
            node.CanvasPosition=Vector2.new(0,math.clamp(node.CanvasPosition.Y+change,0,math.max(0,node.AbsoluteCanvasSize.Y-node.AbsoluteSize.Y)))
        end;node=node.Parent
    end
end
function Methods:watchControl(node: Instance)
    if self.watched[node] or not node:IsA("GuiButton")then return end;self.watched[node]=true
    listen(self,node.SelectionGained,function()self:scrollToControl(node)end)
end
function Methods:layoutSettingRow(row: any,width: number,_compact: boolean,dense: boolean?): number
    local size=if dense then 13 else 15
    if row:GetAttribute("SectionHeading")==true then row.TextSize=size;return 26 end
    if row.Name=="Profiles"then for i,name in {"Keyboard","Controller","Touch"}do row[name].Position=UDim2.new((i-1)/3,0,0,0);row[name].Size=UDim2.new(1/3,-4,0,44)end;return 44 end
    if row.Name=="ProfileReset" or row.Name=="Reset"then return 44 end
    local title=row:FindFirstChild("Title");local description=row:FindFirstChild("Description")
    local toggle=row:FindFirstChild("Toggle");local track=row:FindFirstChild("Track");local bind=row:FindFirstChild("Bind");local select=row:FindFirstChild("Select")
    if title then title.TextSize=size;title.Position=UDim2.fromOffset(12,9);title.Size=UDim2.fromOffset(math.max(1,width-(if toggle then 86 else 24)),22);title.TextWrapped=true end
    if description then description.TextSize=if dense then 11 else 12;description.Position=UDim2.fromOffset(12,32);description.Size=UDim2.fromOffset(math.max(1,width-(if toggle then 86 else 24)),30);description.TextWrapped=true;description.Visible=description.Text~=""end
    local h=68
    if toggle then toggle.Position=UDim2.new(1,-68,0,12);toggle.Size=UDim2.fromOffset(56,44);toggle.Knob.Size=UDim2.fromOffset(22,22);toggle.Knob.Position=UDim2.fromOffset(if toggle:GetAttribute("PFSelected")==true then 28 else 6,11)
    elseif track then
        if row:IsA("GuiButton")then row.Selectable=false end
        h=94;row.Value.Position=UDim2.new(1,-66,0,9);row.Value.Size=UDim2.fromOffset(54,24)
        if title then title.Size=UDim2.new(1,-90,0,22)end
        row.Track.Position=UDim2.fromOffset(14,72);row.Track.Size=UDim2.new(1,-28,0,4)
        row.Track.Input.Position=UDim2.fromOffset(0,-20);row.Track.Input.Size=UDim2.new(1,0,0,44);row.Track.Input.Selectable=true
    elseif bind then
        h=86;if description then description.Visible=false end;local actionWidth=(width-40)/3
        for i,name in {"Bind","Reset","Unbind"}do row[name].Position=UDim2.fromOffset(12+(i-1)*(actionWidth+8),34);row[name].Size=UDim2.fromOffset(actionWidth,44);row[name].TextSize=if dense then 11 else 12 end
    elseif select then
        h=86;if description then description.Visible=false end;select.Position=UDim2.fromOffset(12,34);select.Size=UDim2.new(1,-24,0,44)
        local choices=row:FindFirstChild("Choices")
        if choices then local options={};for _,option in choices:GetChildren()do if option:IsA("GuiButton") and option.Visible then table.insert(options,option)end end
            table.sort(options,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
            for i,option in options do option.Position=UDim2.fromOffset(0,(i-1)*44);option.Size=UDim2.new(1,0,0,44)end
            choices.Position=UDim2.fromOffset(12,82);choices.Size=UDim2.new(1,-24,0,#options*44)
            if choices:IsA("ScrollingFrame")then choices.CanvasSize=UDim2.fromOffset(0,#options*44)end;if choices.Visible then h+=#options*44+8 end
        end
    elseif row.Name=="InterfaceAccent"then
        local swatches=row.Swatches;local n=#Accent.Swatches;local cols=math.max(1,math.min(n,math.floor((width-24)/52)))
        swatches.Position=UDim2.fromOffset(12,62);swatches.Size=UDim2.new(1,-24,0,math.ceil(n/cols)*52)
        for i in Accent.Swatches do local button=swatches:FindFirstChild("Swatch"..i);if button then button.Position=UDim2.fromOffset(((i-1)%cols)*52,math.floor((i-1)/cols)*52);button.Size=UDim2.fromOffset(44,44)end end
        row.Default.Position=UDim2.new(1,-100,0,8);row.Default.Size=UDim2.fromOffset(88,44);if title then title.Size=UDim2.new(1,-122,0,22)end
        h=70+math.ceil(n/cols)*52
    elseif row.Name=="PF011NativeGuide"then row.TextSize=if dense then 11 else 12;row.TextWrapped=true;h=32
    elseif row.Name=="AppearanceReset"then h=44
    end;return h
end
function Methods:focusGraph()
    local root=if self.confirm.Visible then self.confirm.Body elseif self.ui.Visible then self.body elseif self:legacyMenu() and self.menu.Visible then self.menu.Body else nil
    if not root then return end
    local nodes={}
    for _,control in root:GetDescendants()do
        if (control:IsA("GuiButton") or control:IsA("TextBox")) and control.Selectable and control.Active and shown(control,root)then
            self:watchControl(control);table.insert(nodes,{control=control,x=control.AbsolutePosition.X+control.AbsoluteSize.X/2,y=control.AbsolutePosition.Y+control.AbsoluteSize.Y/2})
        end
    end
    for control,neighbors in Layout.neighbors(nodes)do for direction,target in neighbors do control["NextSelection"..direction]=target end end
    local selected=Gui.SelectedObject
    if selected and selected:IsDescendantOf(self.root) and self:isBlocking() and (not shown(selected,root) or not selected.Active or not selected.Selectable)then
        Gui.SelectedObject=if self.confirm.Visible then self.confirm.Body.Cancel elseif self.ui.Visible then self.body.Tabs[self.activeTab]else legacyFocus(self)
    end
end
function Methods:toggle(button: any,value: boolean)
    button:SetAttribute("PFSelected",value);button.BackgroundColor3=if value then Accent.color(self.settings,"accent")else Surface.Background
    button.Knob.BackgroundColor3=if value then Accent.color(self.settings,"onAccent")else Surface.MutedText
end
function Methods:styleSurfaces()
    -- Exact Atlas/PF005 neutrals. Roles never tint an entire panel/card.
    self.ui.BackgroundTransparency=1;self.ui.Backdrop.BackgroundColor3=Surface.Background
    local legacy=self:legacyMenu()
    if legacy then self.menu.Backdrop.BackgroundColor3=Surface.Background;self.menu.Body.BackgroundColor3=Surface.Panel end
    self.confirm.BackgroundColor3=Surface.Background
    self.body.BackgroundColor3=Surface.Panel;self.confirm.Body.BackgroundColor3=Surface.Panel
    local function well(node: any,card: boolean?)
        if not node then return end
        node.BackgroundColor3=if card then Surface.PanelRaised else Surface.Panel
        local border=node:FindFirstChild("Border");if border and border:IsA("UIStroke")then border.Color=Surface.Border;border.Transparency=.25 end
        local corner=node:FindFirstChild("Corner");if corner and corner:IsA("UICorner")then corner.CornerRadius=UDim.new(0,if card then 4 else 6)end
    end
    well(self.body);if legacy then well(self.menu.Body) end;well(self.confirm.Body)
    local function row(node: any)
        if not node then return end;well(node,true)
        if node:FindFirstChild("Title")then node.Title.TextColor3=Surface.Text end
        if node:FindFirstChild("Description")then node.Description.TextColor3=Surface.MutedText end
        for _,name in {"Select","Bind","Reset","Unbind","Default"}do local control=node:FindFirstChild(name);if control then well(control,true);control.TextColor3=Surface.Text end end
        local toggle=node:FindFirstChild("Toggle");if toggle then local c=toggle:FindFirstChild("Corner");if c then c.CornerRadius=UDim.new(0,4)end end
        local track=node:FindFirstChild("Track");if track then track.BackgroundColor3=Surface.Background end
    end
    for _,spec in Layout.gameplay do row(self.scroll.Gameplay:FindFirstChild(spec.id))end
    row(self.scroll.Gameplay.attackRatio);row(self.scroll.Gameplay.attackRatioIncrement)
    for _,channel in UserSettings.AudioChannels do row(self.scroll.Audio:FindFirstChild(channel))end
    for _,spec in Render.controls do row(self.scroll.Graphics:FindFirstChild(spec.id))end
    row(self.scroll.Graphics:FindFirstChild("InterfaceAccent"));row(self.scroll.Graphics:FindFirstChild("emojis"))
    for _,category in {"nuclear","train","warship","transport"}do row(self.scroll.Graphics:FindFirstChild("Vfx_"..category))end
    for _,spec in Bindings.keyboardActions do row(self.scroll.Keybinds:FindFirstChild(spec.action))end
    local pad=self.scroll.Keybinds:FindFirstChild("ControllerBindings");if pad then for _,spec in Bindings.gamepadActions do row(pad:FindFirstChild(spec.action))end end
    for _,button in {self.body.Header.Back,if legacy then self.menu.Body.Header.Back else nil,self.confirm.Body.Cancel,self.confirm.Body.Confirm}do if button then well(button,true);button.TextColor3=Surface.Text end end
    local function style(root: Instance)
        for _,node in root:GetDescendants()do
            if node.Name=="PFMenuMotion" or node.Name=="PF011Frontier" then continue end
            local own=node:GetAttribute("PF011Owner")==Layout.owner
            if own and node:IsA("UIStroke")and node.Name=="Border"then node.Color=Surface.Border
            elseif own and node:IsA("GuiObject")then
                if node:IsA("TextLabel")or node:IsA("TextButton")or node:IsA("TextBox")then
                    if node.Name~="Check"and node:GetAttribute("SectionHeading")~=true then node.TextColor3=if node.Name=="Description"then Surface.MutedText else Surface.Text end
                end
                if node:IsA("GuiButton")and not node:GetAttribute("AccentHex")and node.Name~="Toggle"and node.Name~="Input"then node.BackgroundColor3=Surface.PanelRaised end
                if node.Name=="Track"then node.BackgroundColor3=Surface.Background end
            end
        end
    end
    -- Restrict the generic pass to A-owned nodes, leaving foreign/PF006 art intact.
    style(self.body);style(self.confirm.Body)
end
function Methods:refreshBindings()
    local container=self.scroll.Keybinds;local profiles=container:FindFirstChild("Profiles")
    if profiles then for _,entry in {{"Keyboard","keyboard"},{"Controller","gamepad"},{"Touch","touch"}}do profiles[entry[1]]:SetAttribute("PFSelected",self.profile==entry[2]);profiles[entry[1]].TextColor3=if self.profile==entry[2]then Surface.Text else Surface.MutedText end end
    local pad=container:FindFirstChild("ControllerBindings");if pad then pad.Visible=self.profile=="gamepad"end
    local touch=container:FindFirstChild("TouchGuide");if touch then touch.Visible=self.profile=="touch"end
    local native=if pad then pad:FindFirstChild("PF011NativeGuide")else nil
    if native then native.Text="Interface: "..InputPrompts.buttonName(Enum.KeyCode.ButtonA).." selects · "..InputPrompts.buttonName(Enum.KeyCode.ButtonB).." goes back · DPad moves focus. These stay fixed."end
    local reset=container:FindFirstChild("ProfileReset");if reset then reset.Visible=self.profile~="touch";reset.Text=if self.profile=="gamepad"then "Reset controller bindings"else "Reset keyboard bindings"end
    local keyboard=Bindings.resolveKeyboard(self.settings,self.isMac);local defaults=UserSettings.defaultKeybinds(self.isMac)
    local gamepad=Bindings.resolveGamepad(self.settings);local padDefaults=Bindings.defaultGamepadBindings()
    local function update(row: any,action: string,value: string?,default: string?,profile: string)
        if not row then return end
        local prompt=if value and value~="Null"then (if profile=="keyboard"then Controller.formatKey(value)else InputPrompts.buttonName(Enum.KeyCode[value]))else "None"
        row.Bind.Text=if self.listening==action and self.captureProfile==profile then "Listening…"else prompt
        local glyph=row.Bind:FindFirstChild("Glyph")
        if glyph then local content=if profile=="gamepad"and value and self.listening~=action then InputPrompts.image(Enum.KeyCode[value])else "";glyph.Image=content;glyph.Visible=content~="";if glyph.Visible then row.Bind.Text=""end end
        row.Reset.Active=value~=default;row.Reset.Selectable=row.Reset.Active;row.Reset.Interactable=row.Reset.Active
    end
    for _,spec in Bindings.keyboardActions do local row=container:FindFirstChild(spec.action);if row then row.Visible=self.profile=="keyboard";if row.Visible then update(row,spec.action,keyboard[spec.action],defaults[spec.action],"keyboard")end end end
    if pad then for _,spec in Bindings.gamepadActions do update(pad:FindFirstChild(spec.action),spec.action,gamepad[spec.action],padDefaults[spec.action],"gamepad")end end
end
function Methods:refresh()
    if self.destroyed or self.refreshing then return end;self.refreshing=true;Controller.retireRows(self.scroll);self:styleSurfaces()
    local size=if self.atlasHost then self.atlasHost.AbsoluteSize else self.root.AbsoluteSize
    local g=Layout.sheet(size.X,size.Y,self.atlasHost~=nil);self.geometry=g
    self.body.AnchorPoint=Vector2.new(.5,.5);self.body.Position=UDim2.fromScale(.5,.5);self.body.Size=UDim2.fromOffset(g.width,g.height)
    self.body.Header.Visible=g.header>0;self.body.Header.Position=UDim2.fromOffset(g.side,4);self.body.Header.Size=UDim2.new(1,-g.side*2,0,44)
    self.body.Header.Back.Size=UDim2.fromOffset(44,44);self.body.Header.Title.Text="Settings";self.body.Header.Title.TextSize=if g.dense then 20 else 24
    self.body.Tabs.Position=UDim2.fromOffset(g.side,g.tabsY);self.body.Tabs.Size=UDim2.new(1,-g.side*2,0,44)
    -- The save line reserves its band only while it has something to say; otherwise the
    -- rows run to the sheet's inner bottom padding (PF015 review; authored in phase 3).
    local saving=self.body.Persistence.Text~=""
    self.scroll.Position=UDim2.fromOffset(g.side,g.scrollY);self.scroll.Size=UDim2.new(1,-g.side*2,0,g.scrollHeight+(if saving then 0 else 20))
    self.body.Persistence.Visible=saving;self.body.Persistence.Position=UDim2.new(0,g.side,1,-26);self.body.Persistence.Size=UDim2.new(1,-g.side*2,0,20);self.body.Persistence.TextSize=11
    local divider=self.body:FindFirstChild("Divider");if divider then divider.Visible=g.header>0;divider.Position=UDim2.fromOffset(g.side,g.tabsY-4);divider.Size=UDim2.new(1,-g.side*2,0,1)end
    for i,name in Layout.tabs do local button=self.body.Tabs[name];button.Visible=true;button.Position=UDim2.new((i-1)/4,0,0,0);button.Size=UDim2.new(.25,0,0,44);button.Text=Layout.tabLabels[name];button.TextSize=if g.dense then 13 else 15
        button:SetAttribute("PFSelected",name==self.activeTab);button.TextColor3=if name==self.activeTab then Surface.Text else Surface.MutedText
        button.Underline.Visible=name==self.activeTab;button.Underline.BackgroundColor3=Accent.color(self.settings,"accent");self.scroll[name].Visible=name==self.activeTab
    end
    for _,spec in Layout.gameplay do local row=self.scroll.Gameplay:FindFirstChild(spec.id);if row then row.Title.Text=spec.title;row.Description.Text=spec.description;self:toggle(row.Toggle,self.settings:get(spec.id))end end
    self.scroll.Gameplay.attackRatioIncrement.Select.Text=tostring(self.settings:get("attackRatioIncrement")).."% steps"
    if self.graphics then self.graphics:refresh()end
    for row,info in self.sliderInfo do
        local value=info.read();local minimum,maximum=row:GetAttribute("Min"),row:GetAttribute("Max")
        local fraction=math.clamp((value-minimum)/math.max(.001,maximum-minimum),0,1);row.Track.Fill.Size=UDim2.fromScale(fraction,1);row.Track.Thumb.Position=UDim2.fromScale(fraction,.5)
        row.Track.Fill.BackgroundColor3=Accent.color(self.settings,"accent");row.Track.Thumb.BackgroundColor3=Accent.color(self.settings,"focus")
        if not row.Value:IsA("TextBox") or not row.Value:IsFocused()then row.Value.Text=if info.format then info.format(value)else tostring(value)end
    end
    self:refreshBindings()
    for _,name in Layout.tabs do local container=self.scroll[name];container.Position=UDim2.fromOffset(0,0);local rows={}
        for _,row in container:GetChildren()do
            if row:IsA("GuiObject") and row.Visible and row:GetAttribute("PFSettingRetired")~=true and row.Name~="ControllerBindings" and row.Name~="TouchGuide"then table.insert(rows,row)end
        end
        if name=="Keybinds"then local group=container:FindFirstChild(if self.profile=="gamepad"then "ControllerBindings"else "TouchGuide")
            if group and group.Visible then for _,row in group:GetChildren()do if row:IsA("GuiObject") and row.Visible then table.insert(rows,row)end end end
        end
        table.sort(rows,function(a,b)return if a.LayoutOrder==b.LayoutOrder then a.Name<b.Name else a.LayoutOrder<b.LayoutOrder end)
        local descriptors={};local cell=(g.contentWidth-g.gap*(g.columns-1))/g.columns
        for _,row in rows do local full=row:GetAttribute("PF011FullWidth")==true or row:GetAttribute("SectionHeading")==true or row.Name=="Profiles" or row.Name=="InterfaceAccent"
            table.insert(descriptors,{id=row,height=self:layoutSettingRow(row,if full then g.contentWidth else cell,false,g.dense),full=full})
        end
        local positions,height=Layout.grid(descriptors,g.contentWidth,g.columns,g.gap)
        for _,groupName in {"ControllerBindings","TouchGuide"}do local group=container:FindFirstChild(groupName);if group then group.Position=UDim2.new();group.Size=UDim2.fromOffset(g.contentWidth,height)end end
        for row,rect in positions do
            local aspect=row:FindFirstChild("PF011CardAspect");if aspect then aspect.AspectRatio=rect.width/math.max(1,rect.height)end
            row.Position=UDim2.fromOffset(rect.x,rect.y);row.Size=UDim2.fromOffset(rect.width,rect.height)
        end
        container.Size=UDim2.fromOffset(g.contentWidth,height);if name==self.activeTab then self.scroll.CanvasSize=UDim2.fromOffset(0,height+8)end
    end
    if self:legacyMenu() then -- the pre-M13 menu only; the M13 menu is authored (PF - 2)
        local actions=self.menu.Body.Actions;actions.Settings.Position=UDim2.fromOffset(0,0);actions.Exit.Position=UDim2.fromOffset(0,76)
        self.menu.Body.Header.Back.Size=UDim2.fromOffset(44,44);self.menu.Body.Header.Back.Position=UDim2.new(1,-44,0,0)
        self.menu.Body.Size=UDim2.fromOffset(math.min(360,size.X*.75),math.min(280,size.Y*.86));self.menu.Body.CanvasSize=UDim2.fromOffset(0,240)
    end
    self.confirm.Body.Size=UDim2.fromOffset(math.min(420,size.X-24),math.min(200,size.Y-24))
    local hint=self.ui:FindFirstChild("CaptureHint");if hint then hint.Visible=self.listening~=nil;hint.Text=if self.captureProfile=="gamepad"then "Press a controller button · B cancels"else "Press a key · Escape cancels";hint.Position=UDim2.new(.5,0,1,-58);hint.Size=UDim2.fromOffset(math.min(360,size.X-120),44)end
    local cancel=self.ui:FindFirstChild("CaptureCancel");if cancel then cancel.Visible=self.listening~=nil;cancel.Position=UDim2.new(1,-100,1,-58);cancel.Size=UDim2.fromOffset(88,44)end
    self.refreshing=false
    if not self.focusQueued then self.focusQueued=true;task.defer(function()self.focusQueued=false;if not self.destroyed then self:focusGraph()end end)end
    if self.motion then self.motion:refresh();if self.menuMotion then self.menuMotion:refresh()end;self.confirmMotion:refresh()end
    if self.callbacks.refreshGraphics then self.callbacks.refreshGraphics(self)end
end
function Methods:dispose()
    if self.destroyed then return end;self:closeAll();self.destroyed=true;Capture.releaseOwner(self,"disposed")
    for _,connection in self.connections do connection:Disconnect()end;if self.hostConnection then self.hostConnection:Disconnect()end
    for _,off in {self.off,self.captureOff,self.accentOff,self.confirmAccentOff,self.menuAccentOff}do if off then off()end end
    if self.graphics then self.graphics:dispose()end
    for _,motion in {self.motion,self.menuMotion,self.confirmMotion}do if motion then motion:dispose()end end
end
return Controller
