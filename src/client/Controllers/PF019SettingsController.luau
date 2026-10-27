--!strict
-- PF019 W7 (approved M5): Settings for the authored tree from tools/atlas/author-pf019-settings.luau
-- (Background.UserSettings with PF019SettingsRevision). SettingsController.new hands off here,
-- so the public API (MatchController, AtlasMenuController, the M13 menu) is unchanged.
-- Content only: rows are authored from Shared.PixelFrontSettingsSpec; this binds them by
-- PFKind/PFSource, fills values and wells, slides knobs/pills/underlines (instant with
-- Reduced motion) and runs rebinding with Swap / Cancel on conflicts. It never sizes or
-- places authored nodes (the sheet's host rect is read from authored attributes).
local UIS=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Tween=game:GetService("TweenService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UserSettings=require(Shared.UserSettings)
local Data=require(Shared.OpenFrontGraphicsData)
local Bindings=require(Shared.PixelFrontInputBindings)
local Capture=require(Shared.PixelFrontInputCapture)
local Accent=require(Shared.PixelFrontAccent)
local Spec=require(Shared.PixelFrontSettingsSpec)
local InputPrompts=require(script.Parent.InputPrompts)
local Sfx=require(script.Parent.Sfx) -- PF043 H
local Controller={};local Methods={};Methods.__index=Methods
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#bdbdbd"),hint=Color3.fromHex("#8c8c8c"),track=Color3.fromHex("#3a3a3a"),
    border=Color3.fromHex("#535353"),raised=Color3.fromHex("#292929"),gold=Color3.fromHex("#ddbf76"),orange=Color3.fromHex("#f59e0b"),
    green=Color3.fromHex("#5fcf6a"),red=Color3.fromHex("#ef6461"),blue=Color3.fromHex("#5f9bff"),yellow=Color3.fromHex("#e7c34a")}
local FAST=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local SLIDE=TweenInfo.new(.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local graphicsSpecs={};for _,spec in Data.controls do graphicsSpecs[spec.id]=spec end
local function listen(self: any,signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
local function shown(node: Instance?,root: Instance): boolean
    if not node or not node.Parent or not node:IsDescendantOf(root) then return false end
    local current: Instance?=node
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current==root then return true end
        current=current.Parent
    end
    return true
end
-- Button glyph colours (A/B/X/Y) and shapes for the controller wells.
local face={ButtonA=C.green,ButtonB=C.red,ButtonX=C.blue,ButtonY=C.yellow}
local short={ButtonA="A",ButtonB="B",ButtonX="X",ButtonY="Y",ButtonL1="LB",ButtonR1="RB",ButtonL2="LT",ButtonR2="RT",ButtonL3="LS",ButtonR3="RS",
    Thumbstick1="LS",Thumbstick2="RS",ButtonSelect="View",ButtonStart="Menu"}

-- Settings › Credits (MM 2026-10-26; Ashton: no licence line; tools/atlas/author-pf3-credits-tab.luau authors the page):
-- the words, filled from Shared.GameIdentity so a rename changes every line. Pure: (page) -> the texts it wrote.
function Controller.creditsText(identity: any): {[string]: string}
    local name=tostring(identity.name)
    return {
        Based=name.." is a modified version of OpenFront. © OpenFront Inc. and Contributors. Changes © "..tostring(identity.year).." "..tostring(identity.studio)..".",
        Assets="Maps, icons and some sprites from OpenFront, licensed under CC BY-SA 4.0.",
        Independent=name.." is not affiliated with or endorsed by OpenFront.",
    }
end
function Controller.fillCredits(page: Instance?)
    if not page then return end
    local ok,Identity=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.GameIdentity) end)
    if not ok then return end
    for key,words in Controller.creditsText(Identity) do
        local label=page:FindFirstChild(key.."Body",true)
        if label and label:IsA("TextLabel") then label.Text=words end
    end
end
function Controller.new(gui: ScreenGui,callbacks: any,session: any): any
    local root=gui:WaitForChild("Background");local ui=root:WaitForChild("UserSettings")
    local self=setmetatable({root=root,ui=ui,body=ui.Body,header=ui.Body.Header,pages=ui.Body.Pages,confirm=root:WaitForChild("SettingsConfirm"),
        menu=root:FindFirstChild("GameMenu"),settings=callbacks.preferences or UserSettings.new(),callbacks=callbacks,audio=callbacks.audio,
        connections={},rows={},activeTab="Gameplay",profile="keyboard",destroyed=false,isMac=callbacks.isMac==true,session=session,
        shownValues={},tweens={}},Methods)
    local header=self.header
    -- PF020 G3: a tab another helper authors (Premium) may not be installed yet; skip it until it is.
    for _,name in Spec.tabs do local tab=header.Tabs:FindFirstChild(name);if tab then listen(self,tab.Activated,function()self:setTab(name)end) end end
    listen(self,header.Close.Activated,function()self:closeSettings()end)
    listen(self,ui.Backdrop.Activated,function()self:closeSettings()end)
    listen(self,header.Reset.Activated,function()self:askReset(self.activeTab)end)
    Controller.fillCredits(self.pages:FindFirstChild("Credits"))
    -- Rows: every authored row carries PFSetting/PFKind/PFSource.
    for _,node in self.pages:GetDescendants() do
        -- PF025: the VIP box's Nameplate style (PFSource "vip") is the equipped cosmetic: PremiumController binds it.
        if node:IsA("Frame") and node:GetAttribute("PFSetting") and node:GetAttribute("PFSource")~="vip" then self:bindSettingRow(node) end
        if node:IsA("Frame") and node:GetAttribute("PFAction") then
            local action,kind=node:GetAttribute("PFAction") :: string,node:GetAttribute("PFKind")
            local well=node:FindFirstChild("Well")
            if well and well:IsA("GuiButton") then
                listen(self,well.Activated,function()self:beginCapture(action,if kind=="pad" then "gamepad" else "keyboard",well)end)
            end
            table.insert(self.rows,{node=node,kind=kind,action=action})
        end
    end
    local controls=self.pages.Controls
    listen(self,controls.Left.ResetBindings.Activated,function()self:askReset(self.profile)end)
    local list=controls.Right.Card1
    listen(self,list.Conflict.Swap.Activated,function()self:resolveConflict(true)end)
    listen(self,list.Conflict.Cancel.Activated,function()self:resolveConflict(false)end)
    listen(self,self.confirm.Body.Cancel.Activated,function()self:finishReset(false)end)
    listen(self,self.confirm.Body.Confirm.Activated,function()self:finishReset(true)end)
    listen(self,UIS.InputChanged,function(input)self:moveSliderDrag(input)end)
    listen(self,UIS.InputEnded,function(input)self:endSliderDrag(input)end)
    listen(self,UIS.WindowFocusReleased,function()self:endSliderDrag();self:endCapture("focus-lost");self:refresh()end)
    listen(self,UIS.GamepadDisconnected,function()self:endCapture("disconnected");self:deviceChanged()end)
    listen(self,UIS.GamepadConnected,function()self:deviceChanged()end)
    listen(self,UIS:GetPropertyChangedSignal("PreferredInput"),function()self:deviceChanged()end)
    listen(self,ui:GetPropertyChangedSignal("Visible"),function()if not ui.Visible then self:endCapture("hidden");self:endSliderDrag();self:finishReset(false);self.conflict=nil end end)
    self.off=self.settings:subscribe(function(key,value)if callbacks.settingsChanged then callbacks.settingsChanged(key,value,self.settings)end;self:refresh()end)
    self.captureOff=Capture.subscribe(function(active)if not active and self.listening then self.listening=nil;self.captureControl=nil;self:refresh()end end)
    self.accentOff=Accent.bind(ui,self.settings);self.confirmAccentOff=Accent.bind(self.confirm,self.settings)
    -- The pre-M13 GameMenu (until PF - 2's M13 menu, PF019GameMenu=true, replaces it).
    if self:legacyMenu() then
        local actions=self.menu.Body.Actions
        listen(self,actions.Settings.Activated,function()self:openPreferences()end)
        listen(self,actions.Exit.Activated,function()self:closeAll(true);if callbacks.exit then callbacks.exit() end end)
        listen(self,self.menu.Body.Header.Back.Activated,function()self:closeMenu()end)
        listen(self,self.menu.Backdrop.Activated,function()self:closeMenu()end)
    end
    -- Settings v2 (author-pf3-settings-v2): Body is the aspect-held canvas; on a phone it starts under Roblox's top bar
    if ui:GetAttribute("PF3SettingsV2") then require(script.Parent.TopbarLine).clearBelow(self.body,self.connections) end
    self:deviceChanged();return self
end

-- ---------------------------------------------------------------- values
local function graphicsPath(row: Instance): (string,string)
    local path=row:GetAttribute("PFPath") :: string
    local a,b=string.match(path,"^([^.]+)%.([^.]+)$")
    return a :: string,b :: string
end
function Methods:read(row: Instance): any
    local id,source=row:GetAttribute("PFSetting") :: string,row:GetAttribute("PFSource")
    local scale=row:GetAttribute("PFScale") or 1
    if source=="pref" then local v=self.settings:get(id);return if type(v)=="number" then v*scale else v end
    if source=="audio" then return self.settings:audioVolume(id)*scale end
    if source=="vfx" then return self.settings:vfxEnabled(id) end
    if source=="accent" then return self.settings:interfaceAccent() end
    if source=="graphics" then
        local a,b=graphicsPath(row);local overrides=self.settings:graphicsOverrides()
        local value=overrides[a] and overrides[a][b]
        return if type(value)=="number" then value else graphicsSpecs[id].default
    end
    return nil
end
function Methods:write(row: Instance,value: any)
    if row:GetAttribute("PFLocked")==true then return end -- PF025: a VIP-box row its pass hasn't unlocked (PremiumController)
    local id,source=row:GetAttribute("PFSetting") :: string,row:GetAttribute("PFSource")
    local scale=row:GetAttribute("PFScale") or 1
    if source=="pref" then self.settings:set(id,if type(value)=="number" then value/scale else value)
    elseif source=="audio" then self.settings:setAudioVolume(id,value/scale)
    elseif source=="vfx" then self.settings:setVfxEnabled(id,value)
    elseif source=="accent" then self.settings:setInterfaceAccent(value)
    elseif source=="graphics" then
        local a,b=graphicsPath(row);local overrides=table.clone(self.settings:graphicsOverrides())
        local section=table.clone(overrides[a] or {});section[b]=value;overrides[a]=section
        self.settings:setGraphicsOverrides(overrides)
    end
end
-- Slider limits: authored on the row, or (graphics rows) from OpenFrontGraphicsData.
function Methods:limits(row: Instance): (number,number,number,number)
    local spec=graphicsSpecs[row:GetAttribute("PFSetting") :: string]
    if row:GetAttribute("PFSource")=="graphics" and spec then return spec.min,spec.max,spec.step,spec.decimals or 0 end
    return row:GetAttribute("PFMin") or 0,row:GetAttribute("PFMax") or 100,row:GetAttribute("PFStep") or 1,0
end
function Methods:format(row: Instance,value: number): string
    local _,_,_,decimals=self:limits(row)
    if row:GetAttribute("PFDisplay")=="multiplier" then return string.format("%.1f×",value/100) end
    local unit=row:GetAttribute("PFUnit") or ""
    return (if decimals>0 then string.format("%."..decimals.."f",value) else tostring(math.floor(value+.5)))..unit
end
function Methods:bindSettingRow(row: Frame)
    local kind=row:GetAttribute("PFKind")
    -- PF043 H: toggles sound on / off; an audio slider's Mute (tools/atlas/author-pf043-audio-mute.luau) mutes its channel
    if kind=="toggle" then listen(self,row.Toggle.Activated,function()
        local on=not self:read(row);self:write(row,on);Sfx.play(if on then "u_on" else "u_off")
    end)
    elseif kind=="choice" then
        for _,option in row.Segments:GetChildren() do
            if option:IsA("GuiButton") then listen(self,option.Activated,function()self:write(row,option:GetAttribute("PFValue"))end) end
        end
    elseif kind=="slider" then
        listen(self,row.Track.InputBegan,function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then self:beginSliderDrag(row,input) end
        end)
        local mute=row:FindFirstChild("Mute")
        if mute and mute:IsA("GuiButton") and row:GetAttribute("PFSource")=="audio" and self.settings.setAudioMuted then
            listen(self,mute.Activated,function()
                local id=row:GetAttribute("PFSetting") :: string
                local muted=not self.settings:audioMuted(id)
                self.settings:setAudioMuted(id,muted);Sfx.play(if muted then "u_off" else "u_on");self:refresh()
            end)
        end
    elseif kind=="swatches" then
        for _,swatch in row.Swatches:GetChildren() do
            if swatch:IsA("GuiButton") then listen(self,swatch.Activated,function()self:write(row,swatch:GetAttribute("PFValue"))end) end
        end
    elseif kind=="device" then
        for _,option in row.Segments:GetChildren() do
            if option:IsA("GuiButton") then listen(self,option.Activated,function()self:setProfile(option:GetAttribute("PFValue") :: string)end) end
        end
    end
    table.insert(self.rows,{node=row,kind=kind})
end

-- ---------------------------------------------------------------- sliders
function Methods:beginSliderDrag(row: Frame,input: InputObject)
    if self.drag or self:isCapturingInput() or not shown(row,self.ui) then return end
    local scroll=self.pages[self.activeTab]
    self.drag={row=row,input=input,scrolling=scroll.ScrollingEnabled,scroll=scroll}
    if input.UserInputType==Enum.UserInputType.Touch then scroll.ScrollingEnabled=false end
    self:updateSlider(Vector2.new(input.Position.X,input.Position.Y))
end
function Methods:updateSlider(position: Vector2)
    local drag=self.drag;if not drag then return end
    local row=drag.row;local minimum,maximum,step=self:limits(row)
    local track=row.Track
    local f=math.clamp((position.X-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
    local value=math.clamp(minimum+math.floor(f*(maximum-minimum)/step+.5)*step,minimum,maximum)
    self:write(row,value)
    -- PF043 H: one tick per 5% of the track, its pitch following the value
    local notch=math.floor((value-minimum)/math.max(1e-6,maximum-minimum)*20+.5)
    if notch~=drag.notch then drag.notch=notch;Sfx.play("u_slider",nil,.85+.3*notch/20) end
end
function Methods:moveSliderDrag(input: InputObject)
    local drag=self.drag;if not drag then return end
    if input==drag.input or (drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then
        self:updateSlider(Vector2.new(input.Position.X,input.Position.Y))
    end
end
function Methods:endSliderDrag(input: InputObject?)
    local drag=self.drag;if not drag then return end
    if input and input~=drag.input and not (drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then return end
    drag.scroll.ScrollingEnabled=drag.scrolling;self.drag=nil
end
-- Gamepad: LB/RB step the focused slider (D-pad stays focus movement).
function Methods:handleInput(input: InputObject): boolean
    if self:isCapturingInput() then return true end
    if not self.ui.Visible or self.confirm.Visible or string.sub(input.UserInputType.Name,1,7)~="Gamepad" then return false end
    if input.KeyCode~=Enum.KeyCode.ButtonL1 and input.KeyCode~=Enum.KeyCode.ButtonR1 then return false end
    local target=Gui.SelectedObject
    while target and target~=self.ui do
        if target:IsA("Frame") and target:GetAttribute("PFKind")=="slider" then
            local minimum,maximum,step=self:limits(target)
            local amount=math.max(step,math.floor((maximum-minimum)/20/step+.5)*step)
            self:write(target,math.clamp(self:read(target)+(if input.KeyCode==Enum.KeyCode.ButtonR1 then amount else -amount),minimum,maximum))
            return true
        end
        target=target.Parent
    end
    return false
end

-- ---------------------------------------------------------------- rebinding
function Controller.formatKey(value: string): string
    if string.sub(value,1,6)=="Shift+" then return "Shift+"..Controller.formatKey(string.sub(value,7)) end
    if value==" " or value=="Space" then return "Space" end
    if string.match(value,"^Digit%d$") then return string.sub(value,6) end
    if string.match(value,"^Key%u$") then return string.sub(value,4) end
    return value
end
local function labelFor(action: string,profile: string): string
    local list=if profile=="gamepad" then Bindings.gamepadActions else Bindings.keyboardActions
    for _,spec in list do if spec.action==action then return if profile=="gamepad" then spec.label else action end end
    return action
end
function Methods:keyLabel(row: Instance,action: string): string
    local label=row:FindFirstChild("Label");return if label and label:IsA("TextLabel") then label.Text else action
end
function Methods:beginCapture(action: string,profile: string,control: GuiObject)
    if not self.ui.Visible or self.confirm.Visible then return end
    self:endCapture("replaced");self:endSliderDrag();self.conflict=nil
    self.listening=action;self.captureProfile=profile;self.captureControl=control
    if UIS.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=control end
    Capture.begin(self,function(code)
        if self.destroyed or not self.ui.Visible then return true end
        return self:offerBinding(action,profile,code)
    end,function()self.listening=nil;self.captureControl=nil;if not self.destroyed then self:refresh()end end,{profile=profile})
    self:refresh()
end
-- A candidate: free → bind; same kind taken → ask Swap / Cancel; wrong kind → keep listening.
function Methods:offerBinding(action: string,profile: string,code: string): boolean
    if profile=="gamepad" then
        if not table.find(Bindings.allowedKeys(action),code) then return false end
        local current=Bindings.resolveGamepad(self.settings)
        for other,value in current do
            if other~=action and value==code then self.conflict={action=action,other=other,code=code,profile=profile};return true end
        end
        local ok=self.settings:rebindGamepad(action,code);return ok
    end
    if self.settings:rebindKeyboardEffective(action,code,code,self.isMac) then return true end
    local current=Bindings.resolveKeyboard(self.settings,self.isMac)
    for other,value in current do
        if other~=action and Bindings.keyboardBindingsOverlap(action,code,other,value) then self.conflict={action=action,other=other,code=code,profile=profile};return true end
    end
    return false
end
function Methods:resolveConflict(swap: boolean)
    local c=self.conflict;self.conflict=nil
    if swap and c then
        if c.profile=="gamepad" then
            local record=Bindings.record(Bindings.resolveGamepad(self.settings))
            record.bindings[c.other]=record.bindings[c.action] or "Null";record.bindings[c.action]=c.code
            self.settings:setGamepadBindings(record)
        else
            local current=Bindings.resolveKeyboard(self.settings,self.isMac)
            local bindings=self.settings:parsedKeybinds()
            local old=current[c.action] or "Null"
            bindings[c.other]={value=old,key=old};bindings[c.action]={value=c.code,key=c.code}
            self.settings:setKeybinds(bindings)
        end
    end
    self:refresh()
    if UIS.PreferredInput==Enum.PreferredInput.Gamepad and c then
        for _,entry in self.rows do if entry.action==c.action then Gui.SelectedObject=entry.node:FindFirstChild("Well");break end end
    end
end
function Methods:endCapture(reason: string?)
    Capture.releaseOwner(self,reason or "cancelled");self.listening=nil;self.captureControl=nil
end
function Methods:isCapturingInput(): boolean return self.listening~=nil and Capture.isCapturingInput() end

-- ---------------------------------------------------------------- reset
local resetCopy={Gameplay="Gameplay settings",Interface="Interface settings",Graphics="Graphics settings",Audio="audio volumes",
    Controls="the feel sliders",keyboard="keyboard keys",gamepad="controller buttons"}
function Methods:askReset(kind: string)
    if kind=="touch" then return end
    self:endCapture("reset");self:endSliderDrag();self.resetKind=kind;self.confirmReturn=Gui.SelectedObject
    self.confirm.Body.Message.Text="Restore "..(resetCopy[kind] or kind).." to defaults?"
    self.confirm.Visible=true;self:refresh()
    if UIS.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=self.confirm.Body.Cancel end
end
function Methods:finishReset(accepted: boolean)
    local kind=self.resetKind;self.resetKind=nil;self.confirm.Visible=false
    if accepted and kind then
        if kind=="gamepad" then self.settings:resetGamepadBindings()
        elseif kind=="keyboard" then self.settings:setKeybinds({})
        elseif kind=="Audio" then self.settings:resetAudio()
        else
            local names,graphics={},false
            for _,row in Spec.tabRows(kind) do
                if row.source=="pref" then table.insert(names,row.id)
                elseif row.source=="vfx" then self.settings:removeCached("settings.vfx."..row.id)
                elseif row.source=="accent" then self.settings:resetInterfaceAccent()
                elseif row.source=="graphics" then graphics=true end
            end
            self.settings:resetKeys(names)
            if graphics then
                local overrides=table.clone(self.settings:graphicsOverrides())
                for _,row in Spec.tabRows(kind) do
                    if row.source=="graphics" and row.path then local section=overrides[row.path[1]];if section then section=table.clone(section);section[row.path[2]]=nil;overrides[row.path[1]]=section end end
                end
                self.settings:setGraphicsOverrides(overrides)
            end
        end
    end
    local target=self.confirmReturn;self.confirmReturn=nil
    if target and shown(target,self.ui) and target:IsA("GuiObject") and target.Selectable then Gui.SelectedObject=target end
    if not self.destroyed then self:refresh() end
end

-- ---------------------------------------------------------------- navigation
function Methods:isGamepad(): boolean return UIS.PreferredInput==Enum.PreferredInput.Gamepad end
function Methods:deviceChanged()
    self:endCapture("device-changed");InputPrompts.invalidate()
    -- M5: opening Settings with a controller starts on the controller list, and Controls
    -- never vanishes on a controller (the tab is always present; the device is a switch).
    self.profile=if UIS.PreferredInput==Enum.PreferredInput.Gamepad then "gamepad" elseif UIS.PreferredInput==Enum.PreferredInput.Touch then "touch" else "keyboard"
    self:refresh()
    if self:isGamepad() and self:isBlocking() and not shown(Gui.SelectedObject,self.ui) then
        Gui.SelectedObject=if self.confirm.Visible then self.confirm.Body.Cancel else self.header.Tabs[self.activeTab]
    end
end
function Methods:setProfile(profile: string)
    if profile~="keyboard" and profile~="gamepad" and profile~="touch" then return end
    self:endCapture("profile-changed");self:endSliderDrag();self.conflict=nil;self.profile=profile;self:refresh()
end
function Methods:setTab(name: string)
    if name=="Appearance" then name="Graphics" elseif name=="Keybinds" then name="Controls" end
    if not table.find(Spec.tabs,name) or not self.pages:FindFirstChild(name) then return end -- PF020 G3: an uninstalled tab
    if name~=self.activeTab then
        self:endCapture("tab-changed");self:endSliderDrag();self.conflict=nil;self.activeTab=name
        self.pages[name].CanvasPosition=Vector2.zero
        if self.callbacks.tabChanged then self.callbacks.tabChanged(name,self) end
    end
    self:refresh()
    if self:isGamepad() then Gui.SelectedObject=self.header.Tabs[name] end
end
function Methods:handleEasterKey(_key: string,_contained: boolean): boolean return false end
function Methods:handleEscape(): boolean
    if self:isCapturingInput() then self:endCapture("back");self:refresh();return true end
    if self.conflict then self:resolveConflict(false);return true end
    if self.confirm.Visible then self:finishReset(false);return true end
    if self.ui.Visible then self:closeSettings();return true end
    if self:legacyMenu() and self.menu.Visible then self:closeMenu();return true end
    return false
end
function Methods:openSettings(onReturn: any)
    self.onReturn=onReturn;if onReturn then self:setTab("Gameplay") end
    if not self.ui.Visible and self.atlasHost==nil then Sfx.play("u_open") end -- PF043 H (the lobby tab has its own tab sound)
    self.focusReturn=Gui.SelectedObject;self.ui.Visible=true;self:refresh()
    if self:isGamepad() then Gui.SelectedObject=self.header.Tabs[self.activeTab] end
end
-- PF020 G3 (PF - 3, per PF - 1): open Settings on a given tab (the Shop's Custom Flag card opens Premium).
function Methods:openSettingsTab(name: string,onReturn: any)
    self:openSettings(onReturn);self:setTab(name)
end
function Methods:setAtlasHost(host: Frame?)
    if self.hostConnection then self.hostConnection:Disconnect();self.hostConnection=nil end;self.atlasHost=host
    local position=if host then host:GetAttribute("PFHostPosition") else nil
    local size=if host then host:GetAttribute("PFHostSize") else nil
    -- Settings v2 (tools/atlas/author-pf3-settings-v2.luau): the sheet stays full-screen; its Body is the aspect-held canvas
    local v2=self.ui:GetAttribute("PF3SettingsV2")~=nil
    -- v2: the same full screen as AtlasMenu (it reaches up under Roblox's bar; Background starts below it), so the canvas sits
    -- where every other v2 screen's does and a phone gets the whole height
    local menu=v2 and self.ui.Parent and self.ui.Parent:FindFirstChild("AtlasMenu")
    local full=if menu and menu:IsA("GuiObject") then {menu.Position,menu.Size} else {UDim2.new(),UDim2.fromScale(1,1)}
    self.ui.Position=if not v2 and typeof(position)=="UDim2" then position else full[1]
    self.ui.Size=if not v2 and typeof(size)=="UDim2" then size else full[2]
    self.ui.Backdrop.Visible=host==nil;self.header.Close.Visible=host==nil
    -- Authored: Reset sits in ×'s place while hosted (× hidden), else left of it.
    local reset=self.header.Reset;local resetAt=reset:GetAttribute(if host then "PF019HostPosition" else "PF019MatchPosition")
    if typeof(resetAt)=="UDim2" and reset.Position~=resetAt then reset.Position=resetAt end
    self:refresh()
end
function Methods:closeSettings(runReturn: boolean?)
    self:endCapture("closed");self:endSliderDrag();self:finishReset(false);self.conflict=nil
    if not self.ui.Visible then return end;self.ui.Visible=false
    if self.atlasHost==nil then Sfx.play("u_close") end -- PF043 H
    local selected=Gui.SelectedObject;if selected and selected:IsDescendantOf(self.ui) then Gui.SelectedObject=nil end
    local target=self.focusReturn;self.focusReturn=nil
    if target and shown(target,self.root) and target:IsA("GuiObject") and target.Selectable then Gui.SelectedObject=target end
    local callback=self.onReturn;self.onReturn=nil;if runReturn~=false and callback then callback() end
end
function Methods:isBlocking(): boolean return self.ui.Visible or self.confirm.Visible or (self:legacyMenu() and self.menu.Visible) end
-- ---------------------------------------------------------------- the in-match menu
-- M13 (PF - 2) owns Background.GameMenu once it carries PF019GameMenu=true; until then the
-- pre-M13 menu is driven here exactly as before.
function Methods:legacyMenu(): boolean
    local menu=self.menu
    return menu~=nil and menu.Parent~=nil and menu:GetAttribute("PF019GameMenu")~=true and menu:FindFirstChild("Body")~=nil
end
function Methods:setMenuReturn(callback: (() -> ())?) self.menuReturn=callback end
function Methods:openMenu(shouldPause: boolean,wasPaused: boolean)
    if not self:legacyMenu() then return end
    self:closeSettings(false);self.session:open(shouldPause,wasPaused);self.menu.Visible=true
    if self:isGamepad() then Gui.SelectedObject=self.menu.Body.Actions.Settings end
end
function Methods:openPreferences(tab: string?)
    if not self:legacyMenu() then
        local back=self.menuReturn
        self:openSettings(function() if back then back() end end)
        self:setTab(tab or "Gameplay");return
    end
    if self.session:handoff() then
        self.menu.Visible=false
        self:openSettings(function()self.session:returnToMenu();self.menu.Visible=true;if self:isGamepad() then Gui.SelectedObject=self.menu.Body.Actions.Settings end end)
        if tab then self:setTab(tab) end
    end
end
function Methods:closeMenu(keepPause: boolean?)
    if not self:legacyMenu() or not self.menu.Visible then return end;self.menu.Visible=false;self.session:close(keepPause)
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.menu) then Gui.SelectedObject=nil end
end
function Methods:closeAll(keepPause: boolean?)
    self:closeSettings(false)
    if not self:legacyMenu() then return end
    if self.menu.Visible or self.session.preferences then self.menu.Visible=false;self.session:close(keepPause) end
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.menu) then Gui.SelectedObject=nil end
end
function Methods:setMapLayers(_layers: {any}) end -- retired customization; ordinary map layers remain
function Methods:toggleTerrain() end
function Methods:setAlternateView(_value: boolean) end
function Methods:previewAudio(_category: string) end
function Methods:setPersistenceStatus(message: string) self.body.Status.Text=message end
function Methods:setAudioControls(audio: any) self.audio=audio end
function Methods:message(value: string)
    self.body.Status.Text=value
    self.toastSerial=(self.toastSerial or 0)+1;local serial=self.toastSerial
    task.delay(3,function()if not self.destroyed and serial==self.toastSerial then self.body.Status.Text="" end end)
end

-- ---------------------------------------------------------------- refresh (content only)
local function reduced(self: any): boolean
    return self.settings:get("reducedMotion")==true
end
function Methods:animate(node: Instance,goal: {[string]: any},key: string)
    local previous=self.tweens[key];if previous then previous:Cancel() end
    if reduced(self) or not self.ui.Visible then for k,v in goal do (node :: any)[k]=v end;return end
    local tween=Tween:Create(node,SLIDE,goal);self.tweens[key]=tween;tween:Play()
end
function Methods:refreshRow(entry: any)
    local row,kind=entry.node,entry.kind
    local accent=Accent.color(self.settings,"accent")
    if kind=="toggle" then
        local on=self:read(row)==true
        row.Toggle.BackgroundColor3=if on then accent else C.track
        -- PF044 r5: the knob's spots as shares of the track (its own margin each side), so it holds at any scale
        local track,knob=row.Toggle,row.Toggle.Knob;local w=track.AbsoluteSize.X
        local margin=(track.AbsoluteSize.Y-knob.AbsoluteSize.Y)/2
        local spot=if w>0 then UDim2.fromScale(if on then (w-knob.AbsoluteSize.X-margin)/w else margin/w,.5)
            elseif on then UDim2.new(1,-27,.5,0) else UDim2.new(0,3,.5,0)
        self:animate(knob,{Position=spot},row:GetFullName())
    elseif kind=="choice" or kind=="device" then
        local value=if kind=="device" then self.profile else self:read(row)
        local options={};for _,o in row.Segments:GetChildren() do if o:IsA("GuiButton") then table.insert(options,o) end end
        table.sort(options,function(a,b) return a.Name<b.Name end)
        local count=#options
        for i,option in options do
            local on=option:GetAttribute("PFValue")==value
            option.TextColor3=if on then C.text else C.muted;option.FontFace=Font.new("rbxasset://fonts/families/Ubuntu.json",if on then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
            if on then -- PF044 r5: the pill's inset as a share of the strip
                local strip,pill=row.Segments,row.Segments.Pill;local sw,sh=strip.AbsoluteSize.X,strip.AbsoluteSize.Y
                local spot=if sw>0 and sh>0 then UDim2.fromScale((i-1)/count+(sw/count-pill.AbsoluteSize.X)/2/sw,(sh-pill.AbsoluteSize.Y)/2/sh)
                    else UDim2.new((i-1)/count,3,0,3)
                self:animate(pill,{Position=spot},row:GetFullName())
            end
        end
        row.Segments.Pill.BackgroundColor3=accent
    elseif kind=="slider" then
        local minimum,maximum=self:limits(row);local value=self:read(row)
        local f=math.clamp((value-minimum)/math.max(1e-6,maximum-minimum),0,1)
        row.Track.Fill.Size=UDim2.fromScale(f,1);row.Track.Knob.Position=UDim2.fromScale(f,.5)
        row.Track.Fill.BackgroundColor3=accent
        row.Value.Text=self:format(row,value)
        -- PF043 H: a muted channel: the speaker shows its slash, the fill dims, the value reads Muted
        local mute=row:FindFirstChild("Mute")
        if mute and row:GetAttribute("PFSource")=="audio" and self.settings.audioMuted then
            local muted=self.settings:audioMuted(row:GetAttribute("PFSetting") :: string)
            local on,off=mute:FindFirstChild("On"),mute:FindFirstChild("Off")
            if on then on.Visible=not muted end;if off then off.Visible=muted end
            row.Track.Fill.BackgroundTransparency=if muted then .65 else 0
            if muted then row.Value.Text="Muted" end
        end
    elseif kind=="swatches" then
        local value=string.lower(self:read(row) or "")
        for _,swatch in row.Swatches:GetChildren() do
            if swatch:IsA("GuiButton") then local s=swatch:FindFirstChild("PFStroke");if s and s:IsA("UIStroke") then s.Transparency=if string.lower(swatch:GetAttribute("PFValue") or "")==value then 0 else 1 end end
        end
    elseif kind=="pad" or kind=="key" then
        local profile=if kind=="pad" then "gamepad" else "keyboard"
        local well=row.Well;local glyph=well.Glyph;local text=glyph.Text;local shape=glyph.Shape
        local current=if profile=="gamepad" then Bindings.resolveGamepad(self.settings)[entry.action] else Bindings.resolveKeyboard(self.settings,self.isMac)[entry.action]
        local listening=self.listening==entry.action and self.captureProfile==profile
        local stroke=well:FindFirstChild("PFStroke")
        if stroke and stroke:IsA("UIStroke") then stroke.Color=if listening then accent else C.border;stroke.Thickness=if listening then 2 else 1 end
        local shapeStroke=shape:FindFirstChild("PFStroke")
        if listening then
            text.Text="Press a "..(if profile=="gamepad" then "button" else "key").."…";text.TextColor3=C.text;shape.Visible=false
        elseif not current or current=="Null" then
            text.Text="None";text.TextColor3=C.hint;shape.Visible=false
        elseif profile=="gamepad" then
            text.Text=short[current] or current;shape.Visible=true
            local color=face[current] or C.text
            text.TextColor3=color;if shapeStroke and shapeStroke:IsA("UIStroke") then shapeStroke.Color=color end
            local round=face[current]~=nil or current=="Thumbstick1" or current=="Thumbstick2" or current=="ButtonL3" or current=="ButtonR3"
            local c=shape:FindFirstChild("PFCorner");if c and c:IsA("UICorner") then c.CornerRadius=if round then UDim.new(.5,0) else UDim.new(0,8) end
            local aspect=shape:FindFirstChild("PFAspect");if aspect and aspect:IsA("UIAspectRatioConstraint") then aspect.AspectRatio=if round then 1 else 1.7 end
        else
            text.Text=Controller.formatKey(current);text.TextColor3=C.text;shape.Visible=true
            if shapeStroke and shapeStroke:IsA("UIStroke") then shapeStroke.Color=C.border end
        end
        local rowStroke=row:FindFirstChild("PFStroke")
        if rowStroke and rowStroke:IsA("UIStroke") then rowStroke.Color=if self.conflict and self.conflict.other==entry.action and self.conflict.profile==profile then C.orange elseif listening then accent else C.border end
    end
end
function Methods:refresh()
    if self.destroyed or self.refreshing then return end;self.refreshing=true
    local accent=Accent.color(self.settings,"accent")
    for _,name in Spec.tabs do
        local tab=self.header.Tabs:FindFirstChild(name);local page=self.pages:FindFirstChild(name)
        if not tab or not page then continue end -- PF020 G3: an uninstalled authored tab
        local on=name==self.activeTab
        -- PF020 G3: Premium is the only gold tab (gold words and outline; gold underline when chosen)
        local gold=Spec.authoredTabs~=nil and Spec.authoredTabs[name]==true
        tab.TextColor3=if on then C.text elseif gold then C.gold else C.muted;tab.BackgroundTransparency=if on then 0 else 1
        local s=tab:FindFirstChild("PFStroke");if s and s:IsA("UIStroke") then s.Transparency=if on or gold then 0 else 1;if gold then s.Color=C.gold end end
        tab.Underline.BackgroundTransparency=if on then 0 else 1;tab.Underline.BackgroundColor3=if gold then C.gold else accent
        page.Visible=on
    end
    self.header.Reset.Visible=not ((Spec.authoredTabs~=nil and Spec.authoredTabs[self.activeTab]==true) or (Spec.plainTabs~=nil and Spec.plainTabs[self.activeTab]==true)) -- nothing to reset on Premium / Credits
    for _,entry in self.rows do self:refreshRow(entry) end
    -- Controls: the chosen device's list, its reset and the conflict banner.
    local controls=self.pages.Controls;local list=controls.Right.Card1
    list.Controller.Visible=self.profile=="gamepad";list.Keyboard.Visible=self.profile=="keyboard";list.Touch.Visible=self.profile=="touch"
    list.Head.Overline.Text=if self.profile=="gamepad" then "CONTROLLER BUTTONS" elseif self.profile=="keyboard" then "KEYBOARD KEYS" else "TOUCH"
    list.Head.Subtitle.Text=if self.profile=="gamepad" then "Every action can be changed from the controller." elseif self.profile=="keyboard" then "Click a key, then press the new one." else "Touch controls are fixed."
    local resetPad=controls.Left.ResetBindings
    resetPad.Visible=self.profile~="touch";resetPad.Text=if self.profile=="gamepad" then "Reset controller buttons" else "Reset keyboard keys"
    local banner=list.Conflict;local c=self.conflict
    banner.Visible=c~=nil
    if c then
        local current=if c.profile=="gamepad" then Bindings.resolveGamepad(self.settings) else Bindings.resolveKeyboard(self.settings,self.isMac)
        local codeName=if c.profile=="gamepad" then (short[c.code] or c.code) else Controller.formatKey(c.code)
        local oldName=current[c.action];oldName=if oldName and oldName~="Null" then (if c.profile=="gamepad" then (short[oldName] or oldName) else Controller.formatKey(oldName)) else "nothing"
        local function name(action: string): string
            for _,entry in self.rows do if entry.action==action then return self:keyLabel(entry.node,action) end end
            return labelFor(action,c.profile)
        end
        banner.Well.Text.Text=codeName
        banner.Title.Text=codeName.." is already "..name(c.other).."."
        banner.Body.Text="Swap them? "..name(c.action).." gets "..codeName.." and "..name(c.other).." gets "..oldName.."."
    end
    local listening=list:FindFirstChild("Listening")
    if listening and listening:IsA("TextLabel") then
        listening.Visible=self.listening~=nil
        listening.Text=if self.captureProfile=="gamepad" then "Press a controller button · B cancels" else "Press a key · Escape cancels"
    end
    self.refreshing=false
    if self.callbacks.refreshGraphics then self.callbacks.refreshGraphics(self) end
end
function Methods:dispose()
    if self.destroyed then return end;self:closeSettings(false);self.destroyed=true;Capture.releaseOwner(self,"disposed")
    for _,connection in self.connections do connection:Disconnect() end;if self.hostConnection then self.hostConnection:Disconnect() end
    for _,off in {self.off,self.captureOff,self.accentOff,self.confirmAccentOff} do if off then off() end end
    for _,tween in self.tweens do tween:Cancel() end
end
return Controller
