--!strict
-- One client-local lease plus physical-press quarantine across capture release.
local CAS=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Http=game:GetService("HttpService")
local Bindings=require(script.Parent.PixelFrontInputBindings)
local Capture={}
local active: any=nil
local listeners: {[number]: (boolean,string)->()}={}
local nextId=0
local generation=0
local suppressed: {[string]: boolean}={}
local releaseBarrier: {[string]: any}={}
local endingConnection: RBXScriptConnection?=nil
local quarantineConnections={}
local function inputId(input: InputObject): string return input.UserInputType.Name..":"..input.KeyCode.Name end
local function notify(reason: string)
    for _,callback in table.clone(listeners) do callback(active~=nil,reason) end
end
local function clearQuarantine()
    table.clear(suppressed)
    if endingConnection then endingConnection:Disconnect();endingConnection=nil end
    for _,connection in quarantineConnections do connection:Disconnect() end;table.clear(quarantineConnections)
end
local function endPress(input: InputObject)
    local id=inputId(input)
    if active then active.attempted[id]=nil end
    if not suppressed[id] then return end
    suppressed[id]=nil
    -- Preserve the captured release for later consumers of the same signal.
    -- A synchronous InputEnded watcher must not reopen gameplay mid-event.
    local token={};releaseBarrier[id]=token
    task.defer(function()
        if releaseBarrier[id]==token then releaseBarrier[id]=nil;notify("released") end
    end)
    if next(suppressed)==nil then clearQuarantine() end
end
local function watchEnd()
    if endingConnection then return end
    endingConnection=UIS.InputEnded:Connect(endPress)
    -- Sticks/triggers may report neutral through Change after the capture CAS
    -- binding is removed. Do not require an engine End event for analog release.
    table.insert(quarantineConnections,UIS.InputChanged:Connect(function(input: InputObject)
        if not suppressed[inputId(input)] then return end
        local key=input.KeyCode
        local stick=key==Enum.KeyCode.Thumbstick1 or key==Enum.KeyCode.Thumbstick2
        local trigger=key==Enum.KeyCode.ButtonL2 or key==Enum.KeyCode.ButtonR2
        if (stick and Vector2.new(input.Position.X,input.Position.Y).Magnitude<=.18)
            or (trigger and math.abs(input.Position.Z)<=.05) or input.UserInputState==Enum.UserInputState.Cancel then endPress(input) end
    end))
    local function lost() clearQuarantine();table.clear(releaseBarrier);notify("released") end
    table.insert(quarantineConnections,UIS.WindowFocusReleased:Connect(lost))
    table.insert(quarantineConnections,UIS.GamepadDisconnected:Connect(lost))
    table.insert(quarantineConnections,UIS.TextBoxFocused:Connect(lost))
    table.insert(quarantineConnections,Gui:GetPropertyChangedSignal("MenuIsOpen"):Connect(function() if Gui.MenuIsOpen then lost() end end))
end
function Capture.isCapturingInput(): boolean return active~=nil end
Capture.active=Capture.isCapturingInput
function Capture.isSuppressed(input: InputObject?): boolean
    return active~=nil or (if input then suppressed[inputId(input)]==true or releaseBarrier[inputId(input)]~=nil else next(suppressed)~=nil or next(releaseBarrier)~=nil)
end
function Capture.subscribe(callback: (boolean,string)->()): ()->()
    nextId+=1;local id=nextId;listeners[id]=callback;return function() listeners[id]=nil end
end
function Capture.releaseOwner(owner: any,reason: string?)
    if active and active.owner==owner then active.release(reason or "cancelled") end
end
function Capture.begin(owner: any,onCandidate: (string,InputObject)->boolean,onCancel: ((string)->())?,options: any?): (string?)->()
    generation+=1;local currentGeneration=generation
    if active then active.release("replaced") end
    -- A cancellation callback can begin a newer lease. Its ownership wins.
    if generation~=currentGeneration then return function() end end
    local profile=if options then options.profile else "keyboard"
    assert(profile=="keyboard" or profile=="gamepad","Unknown capture input profile")
    local lease={owner=owner,connections={},attempted={},action="PixelFrontCapture-"..Http:GenerateGUID(false),released=false}
    local function release(reason: string?)
        if lease.released then return end;lease.released=true
        CAS:UnbindAction(lease.action)
        for _,connection in lease.connections do connection:Disconnect() end
        if active==lease then active=nil end
        local why=reason or "cancelled"
        if why=="blur" or why=="disconnect" or why=="menu" or why=="textbox" then
            clearQuarantine();table.clear(releaseBarrier)
        end
        notify(why)
        if why~="accepted" and onCancel then onCancel(why) end
    end
    lease.release=release;active=lease
    local keys={Enum.UserInputType.Keyboard}
    for i=1,8 do table.insert(keys,Enum.UserInputType["Gamepad"..i]) end
    CAS:BindActionAtPriority(lease.action,function(_,state: Enum.UserInputState,input: InputObject)
        if lease.released then return Enum.ContextActionResult.Pass end
        if input.KeyCode==Enum.KeyCode.ButtonStart or Gui.MenuIsOpen then
            if Gui.MenuIsOpen then release("menu") end
            return Enum.ContextActionResult.Pass
        end
        local name=input.UserInputType.Name
        local gamepad=string.sub(name,1,7)=="Gamepad"
        local keyboard=name=="Keyboard"
        if not gamepad and not keyboard then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then lease.attempted[inputId(input)]=nil;endPress(input);return Enum.ContextActionResult.Sink end
        local analog=gamepad and (input.KeyCode==Enum.KeyCode.Thumbstick1 or input.KeyCode==Enum.KeyCode.Thumbstick2 or input.KeyCode==Enum.KeyCode.ButtonL2 or input.KeyCode==Enum.KeyCode.ButtonR2)
        local meaningful=analog and (math.abs(input.Position.Z)>=.6 or Vector2.new(input.Position.X,input.Position.Y).Magnitude>=.65)
        local crossed=meaningful and state==Enum.UserInputState.Change
        if analog and not meaningful then
            local neutral=if input.KeyCode==Enum.KeyCode.Thumbstick1 or input.KeyCode==Enum.KeyCode.Thumbstick2 then Vector2.new(input.Position.X,input.Position.Y).Magnitude<=.18 else math.abs(input.Position.Z)<=.05
            if neutral then lease.attempted[inputId(input)]=nil;endPress(input) end
            return Enum.ContextActionResult.Sink
        end
        if state~=Enum.UserInputState.Begin and not crossed then return Enum.ContextActionResult.Sink end
        suppressed[inputId(input)]=true;watchEnd()
        if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then release("cancelled");return Enum.ContextActionResult.Sink end
        if (profile=="gamepad" and gamepad) or (profile=="keyboard" and keyboard) then
            if lease.attempted[inputId(input)] then return Enum.ContextActionResult.Sink end
            lease.attempted[inputId(input)]=true
            local code=if gamepad then input.KeyCode.Name else Bindings.keyboardCode(input.KeyCode)
            local modifier=code=="ShiftLeft" or code=="ShiftRight" or code=="ControlLeft" or code=="ControlRight" or code=="AltLeft" or code=="AltRight" or code=="MetaLeft" or code=="MetaRight"
            if keyboard and not modifier
                and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) then code="Shift+"..code end
            if input.KeyCode~=Enum.KeyCode.Unknown then
                local ok,accepted=pcall(onCandidate,code,input)
                if not ok then release("failed") elseif accepted==true then release("accepted") end
            end
        end
        return Enum.ContextActionResult.Sink
    end,false,Enum.ContextActionPriority.High.Value+100,table.unpack(keys))
    table.insert(lease.connections,UIS.WindowFocusReleased:Connect(function() release("blur") end))
    table.insert(lease.connections,UIS.TextBoxFocused:Connect(function() release("textbox") end))
    table.insert(lease.connections,UIS.GamepadDisconnected:Connect(function() release("disconnect") end))
    table.insert(lease.connections,Gui:GetPropertyChangedSignal("MenuIsOpen"):Connect(function() if Gui.MenuIsOpen then release("menu") end end))
    notify("begin")
    if Gui.MenuIsOpen then release("menu") elseif UIS:GetFocusedTextBox() then release("textbox") end
    return release
end
return table.freeze(Capture)
