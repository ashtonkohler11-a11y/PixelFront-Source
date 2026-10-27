--!strict
-- Gamepad map controls coexist with Roblox's native GUI selection. A map action
-- is never sent while a textbox/menu/selected GUI owns the input.
-- API evidence: https://create.roblox.com/docs/input/gamepad and GuiService.
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Bindings = require(game:GetService("ReplicatedStorage").Shared.PixelFrontInputBindings)
local Input = {}
local Methods = {}; Methods.__index = Methods
local ACTION = "OpenFrontStrategyGamepad"
-- PF019 W7: every control a binding may use (buttons, both sticks, both triggers) plus the
-- D-pad for the send-ratio focus. Which action a control performs comes from the saved
-- controller profile (Settings, Controls), so rebinding on a controller takes effect live.
local KEYS = {Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY,
    Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonSelect, Enum.KeyCode.ButtonL3, Enum.KeyCode.ButtonR3,
    Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight,
    Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2}
-- KeyCode name -> semantic action for a controller profile (action -> KeyCode name).
function Input.actionMap(profile: {[string]: string}): {[string]: string}
    local map={}
    for action,key in profile do if type(key)=="string" and key~="Null" then map[key]=action end end
    return map
end

-- Release QA (MM, 2026-10-26): a drifting pad dragged the tutorial's camera into a map corner (the A06 off-centre bug), so
-- the deadzone is .25 (was .18) and each stick is ignored until it has rested inside it once since the last device change
-- (Methods:rearm); a healthy stick is already at rest then, so normal play is unchanged.
Input.DEAD = .25
function Input.axis(value: Vector2): Vector2
    local length = value.Magnitude
    if length <= Input.DEAD then return Vector2.zero end
    return value.Unit * math.min(1, (length - Input.DEAD) / (1 - Input.DEAD))
end
-- PF020: the zoom stick's up/down (its left/right is free), same deadzone; up zooms in.
function Input.zoomAxis(y: number): number
    local size=math.abs(y)
    if size<=Input.DEAD then return 0 end
    return math.sign(y)*math.min(1,(size-Input.DEAD)/(1-Input.DEAD))
end
-- how far a stick input counts toward its action: the pan stick's whole tilt, the zoom stick's up/down
local function tilt(action: string, position: any): number
    return if action=="pan" then Vector2.new(position.X,position.Y).Magnitude else math.abs(position.Y)
end

function Input.new(callbacks: any): any
    local self = setmetatable({callbacks=callbacks, stick=Vector2.zero, zoom=0,
        gamepad=false, connections={}, destroyed=false,action=ACTION.."-"..HttpService:GenerateGUID(false),
        actions=Input.actionMap(Bindings.defaults()),armed={}}, Methods)
    local function device()
        local gamepad=UserInputService.PreferredInput==Enum.PreferredInput.Gamepad
        self:rearm()
        if self.gamepad~=gamepad then self:clear();self.gamepad=gamepad;callbacks.device(gamepad) end
    end
    table.insert(self.connections,UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(device))
    table.insert(self.connections,UserInputService.WindowFocusReleased:Connect(function() self:clear() end))
    table.insert(self.connections,UserInputService.TextBoxFocused:Connect(function() self:clear() end))
    table.insert(self.connections,GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function() if GuiService.MenuIsOpen then self:clear() end end))
    table.insert(self.connections,GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function() if GuiService.SelectedObject then self:clear() end end))
    table.insert(self.connections,UserInputService.GamepadConnected:Connect(device))
    table.insert(self.connections,UserInputService.GamepadDisconnected:Connect(function() self:clear();device() end))
    device()
    ContextActionService:BindActionAtPriority(self.action,function(_,state,input)
        local key=input.KeyCode
        local action=self.actions[key.Name]
        local ending=state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel
        if action=="pan" or action=="zoom" then
            -- the drift guard: a stick counts only after it has rested inside the deadzone once
            if ending or tilt(action,input.Position)<=Input.DEAD then self.armed[key.Name]=true end
            local live=not ending and self.armed[key.Name]==true
            if action=="pan" then self.stick=if live then Input.axis(Vector2.new(input.Position.X,-input.Position.Y)) else Vector2.zero
            else self.zoom=if live then Input.zoomAxis(input.Position.Y) else 0 end
        end
        local horizontal=key==Enum.KeyCode.DPadLeft or key==Enum.KeyCode.DPadRight
        local shoulder=action=="attackRatioDown" or action=="attackRatioUp" or action=="hotbarPrev" or action=="hotbarNext"
        -- The radial (X / Square): the D-pad's left / right walks its items while it is open
        if horizontal and callbacks.radialOpen and callbacks.radialOpen() and not GuiService.MenuIsOpen then
            if state==Enum.UserInputState.Begin and callbacks.radialStep then callbacks.radialStep(if key==Enum.KeyCode.DPadLeft then -1 else 1) end
            return Enum.ContextActionResult.Sink
        end
        if horizontal or shoulder then
            local ratioFocused=not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                and callbacks.ratioFocused and callbacks.ratioFocused()
            if ratioFocused then
                local down=key==Enum.KeyCode.DPadLeft or action=="attackRatioDown" or action=="hotbarPrev"
                if state==Enum.UserInputState.Begin then callbacks.ratio(if down then -1 else 1) end
                return Enum.ContextActionResult.Sink
            end
            if horizontal then return Enum.ContextActionResult.Pass end
        end
        if action==nil then return Enum.ContextActionResult.Pass end
        if state~=Enum.UserInputState.Begin then
            return if self:mapAvailable() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
        end
        if action=="back" then
            if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
            -- B in the radial goes back one ring, then closes it
            if callbacks.radialOpen and callbacks.radialOpen() and callbacks.radialBack then callbacks.radialBack();return Enum.ContextActionResult.Sink end
            if callbacks.back() then return Enum.ContextActionResult.Sink end
        end
        if action=="navigateHud" then
            if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
            callbacks.navigate();return Enum.ContextActionResult.Sink
        end
        -- X / Square opens the same radial as right-click and the mobile long-press at the aim point (the screen
        -- centre on a controller); pressing it again closes it. It never confirms anything by itself.
        if action=="radialMenu" then
            if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
            return if callbacks.radialMenu and callbacks.radialMenu() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
        end
        if not self:mapAvailable() then return Enum.ContextActionResult.Pass end
        if action=="primary" then
            -- A confirms the radial's highlighted item while it is open
            if callbacks.radialOpen and callbacks.radialOpen() and callbacks.radialConfirm then callbacks.radialConfirm() else callbacks.primary() end
        elseif action=="centerCamera" then callbacks.focus()
        elseif action=="attackRatioDown" then callbacks.ratio(-1)
        elseif action=="attackRatioUp" then callbacks.ratio(1)
        elseif action=="hotbarPrev" then if callbacks.hotbar then callbacks.hotbar(-1) end
        elseif action=="hotbarNext" then if callbacks.hotbar then callbacks.hotbar(1) end end
        return Enum.ContextActionResult.Sink
    end,false,Enum.ContextActionPriority.High.Value+2,table.unpack(KEYS))
    return self
end

function Methods:mapAvailable(): boolean
    return not self.destroyed and self.gamepad and not GuiService.MenuIsOpen
        and not UserInputService:GetFocusedTextBox() and GuiService.SelectedObject==nil
        and self.callbacks.available()
end

-- PF019 W7 S20 Stick sensitivity: the pan stick's map speed scales by sensitivity/.6, so the
-- default .6 is exactly the old 650 px/s. Not the deadzone, not the zoom stick (S12 zoom speed).
function Input.speed(sensitivity: any): number
    return if type(sensitivity)=="number" and sensitivity>0 and sensitivity<math.huge then sensitivity/.6 else 1
end
-- MatchController hands the settings in once; later changes follow the subscription.
function Methods:setPreferences(preferences: any)
    if self.preferencesOff then self.preferencesOff();self.preferencesOff=nil end
    local function read()
        self.speed=Input.speed(if preferences and type(preferences.get)=="function" then preferences:get("stickSensitivity") else nil)
        -- PF019 W7: the controller profile from Settings (defaults when none is saved).
        local ok,profile=pcall(function() return if preferences then Bindings.resolveGamepad(preferences) else Bindings.defaults() end)
        self.actions=Input.actionMap(if ok and profile then profile else Bindings.defaults());self:clear()
    end
    read()
    if preferences and type(preferences.subscribe)=="function" then
        self.preferencesOff=preferences:subscribe(function(key) if key=="settings.stickSensitivity" or key=="settings.gamepadBindings" then read() end end)
    end
end

function Methods:step(dt: number)
    if not self:mapAvailable() then self:clear();return end
    -- the radial is open: the pan stick points at its items instead of moving the map
    if self.callbacks.radialOpen and self.callbacks.radialOpen() then
        if self.stick.Magnitude>=.5 and self.callbacks.radialAim then self.callbacks.radialAim(self.stick) end
        return
    end
    local delta=self.stick*650*(self.speed or 1)*math.min(dt,.05)
    local zoom=self.zoom*math.min(dt,.05)
    if delta.Magnitude>0 or zoom~=0 then self.callbacks.move(delta,zoom) end
end

function Methods:clear() self.stick=Vector2.zero;self.zoom=0 end
-- after a device change each stick must rest once before it counts; one resting now (read from the pad) is armed at once
function Methods:rearm()
    table.clear(self.armed)
    local ok,pads=pcall(function() return UserInputService:GetConnectedGamepads() end)
    if not ok or type(pads)~="table" or #pads==0 then
        for _,name in {"Thumbstick1","Thumbstick2"} do self.armed[name]=true end -- no pad: nothing can drift
        return
    end
    for _,pad in pads do
        local read,states=pcall(function() return UserInputService:GetGamepadState(pad) end)
        if not read then continue end
        for _,stick in states do
            local name=stick.KeyCode.Name
            if name=="Thumbstick1" or name=="Thumbstick2" then
                local action=self.actions[name]
                local resting=if action=="pan" or action=="zoom" then tilt(action,stick.Position)<=Input.DEAD else true
                if resting and self.armed[name]==nil then self.armed[name]=true elseif not resting then self.armed[name]=false end
            end
        end
    end
end
function Methods:destroy()
    if self.destroyed then return end;self.destroyed=true;self:clear()
    if self.preferencesOff then self.preferencesOff();self.preferencesOff=nil end
    ContextActionService:UnbindAction(self.action)
    for _,connection in self.connections do connection:Disconnect() end
end
return Input
