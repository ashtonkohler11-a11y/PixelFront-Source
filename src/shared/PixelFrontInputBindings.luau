--!strict
-- One semantic profile for Settings, actual strategy dispatch and prompts.
-- Native GUI accept/back/DPad are deliberately outside this gameplay profile.
local HttpService = game:GetService("HttpService")
local Data = require(script.Parent.OpenFrontGraphicsData)
local Bindings = {}
export type Profile = {[string]: string}
local retired = {buildMenuModifier=true,toggleView=true,altKey=true,resetGfx=true}
local keyboardActions = {}
for _, spec in Data.keybinds do
    if not retired[spec.action] then table.insert(keyboardActions,table.freeze(table.clone(spec))) end
end
Bindings.keyboardActions = table.freeze(keyboardActions)
Bindings.retiredKeyboardActions = table.freeze(retired)
-- PF020 console controls (Ashton, 2026-10-07): the triggers step the send ratio, the bumpers
-- cycle the building hotbar, and the right stick's up/down zooms (left/right is free). A
-- "press" control may be any button or trigger.
local actions = {
    {action="primary",label="Map action",kind="button",default="ButtonA"},
    {action="back",label="Cancel map action",kind="button",default="ButtonB"},
    -- 2026-10-08 (Ashton: "square should bring up the right click menu on console"): X / Square opens the radial; the
    -- Warship moved to build-bar slot 7 (the bumper hotbar), so buildWarship left the controller profile (version 3).
    {action="radialMenu",label="Action menu",kind="button",default="ButtonX"},
    {action="centerCamera",label="Center camera",kind="button",default="ButtonY"},
    {action="attackRatioDown",label="Decrease send",kind="press",default="ButtonL2"},
    {action="attackRatioUp",label="Increase send",kind="press",default="ButtonR2"},
    {action="hotbarPrev",label="Hotbar left",kind="press",default="ButtonL1"},
    {action="hotbarNext",label="Hotbar right",kind="press",default="ButtonR1"},
    {action="navigateHud",label="Focus interface",kind="button",default="ButtonSelect"},
    {action="pan",label="Pan map",kind="stick",default="Thumbstick1"},
    {action="zoom",label="Zoom (up/down)",kind="stick",default="Thumbstick2"},
}
-- Version-1 profiles (before PF020): these actions are gone; the ratio moved to the triggers.
local retiredGamepad = table.freeze({finePan=true,zoomIn=true,zoomOut=true})
local movedInV2 = table.freeze({attackRatioDown=true,attackRatioUp=true,hotbarPrev=true,hotbarNext=true,zoom=true})
-- Version-1/2 profiles: buildWarship is gone. Its button carries over to radialMenu when it was X (the default); a
-- profile that moved the Warship elsewhere gets radialMenu = X only if nothing else uses X, else radialMenu stays unbound.
Bindings.VERSION=3
local byAction = {}
for _, spec in actions do byAction[spec.action]=spec;table.freeze(spec) end
Bindings.actions=table.freeze(actions);Bindings.gamepadActions=Bindings.actions
local allowed = table.freeze({
    button=table.freeze({"ButtonA","ButtonB","ButtonX","ButtonY","ButtonL1","ButtonR1","ButtonSelect","ButtonL3","ButtonR3"}),
    stick=table.freeze({"Thumbstick1","Thumbstick2"}),
    trigger=table.freeze({"ButtonL2","ButtonR2"}),
    press=table.freeze({"ButtonA","ButtonB","ButtonX","ButtonY","ButtonL1","ButtonR1","ButtonSelect","ButtonL3","ButtonR3","ButtonL2","ButtonR2"}),
})
function Bindings.allowedKeys(action: string): {string}
    local spec=byAction[action]
    return if spec then allowed[spec.kind] else table.freeze({})
end
function Bindings.defaults(): Profile
    local result={};for _,spec in actions do result[spec.action]=spec.default end;return result
end
Bindings.defaultGamepadBindings=Bindings.defaults
function Bindings.validateGamepad(candidate: any): (Profile?,string?)
    if type(candidate)~="table" or (candidate.version~=1 and candidate.version~=2 and candidate.version~=3) or type(candidate.bindings)~="table" then
        return nil,"Expected a version 3 controller profile"
    end
    for key in candidate do if key~="version" and key~="bindings" then return nil,"Unknown profile field" end end
    local legacy=candidate.version==1
    local result=Bindings.defaults()
    local warship: any=nil -- an old profile's buildWarship control (v1/v2), resolved after the loop
    for action,value in candidate.bindings do
        if action=="buildWarship" and candidate.version~=3 then warship=value;continue end
        -- PF020: a version-1 profile keeps its unchanged actions; the moved ones take the new defaults.
        if legacy and (retiredGamepad[action] or movedInV2[action]) then continue end
        local spec=byAction[action]
        if not spec then return nil,"Unknown controller action" end
        if type(value)~="string" or (value~="Null" and not table.find(allowed[spec.kind],value)) then
            return nil,"Unsupported control for "..spec.label
        end
        result[action]=if value=="Null" then nil else value
    end
    if legacy then
        -- A carried-over control wins over a new default it collides with (that action is left unbound).
        local carried={};for _,spec in actions do if not movedInV2[spec.action] and result[spec.action] then carried[result[spec.action]]=true end end
        for action in movedInV2 do if result[action] and carried[result[action]] then result[action]=nil end end
    end
    if candidate.version~=3 and candidate.bindings.radialMenu==nil then
        -- radialMenu takes X when the Warship had it; otherwise only when X is free (never a collision, never a reject)
        result.radialMenu=nil
        local taken=false;for _,spec in actions do if result[spec.action]=="ButtonX" then taken=true end end
        -- (an old buildWarship on X frees X first, so it carries over; otherwise X is taken only by another action)
        if not taken then result.radialMenu="ButtonX" end
        if warship~=nil and warship~="ButtonX" and warship~="Null" and type(warship)~="string" then return nil,"Unsupported control for Warship" end
    end
    local used={}
    for _,spec in actions do
        local value=result[spec.action]
        if value then
            if used[value] then return nil,"Control already used by "..byAction[used[value]].label end
            used[value]=spec.action
        end
    end
    return result,nil
end
function Bindings.record(profile: Profile): any
    local result={version=Bindings.VERSION,bindings={}}
    for _,spec in actions do result.bindings[spec.action]=profile[spec.action] or "Null" end
    return result
end
local cache: {[any]: any}=setmetatable({},{__mode="k"})
function Bindings.clearCache(preferences: any) cache[preferences]=nil end
function Bindings.resolveGamepad(preferences: any): Profile
    local raw=preferences.storage and preferences.storage["settings.gamepadBindings"]
    local cached=cache[preferences]
    if cached and cached.raw==raw then return table.clone(cached.profile) end
    local profile=nil
    if type(raw)=="string" and #raw<=8192 and string.match(raw,"^%s*{") then
        local ok,parsed=pcall(function() return HttpService:JSONDecode(raw) end)
        if ok then profile=Bindings.validateGamepad(parsed) end
    end
    profile=profile or Bindings.defaults()
    cache[preferences]={raw=raw,profile=profile}
    return table.clone(profile)
end
function Bindings.resolveKeyboard(preferences: any,isMac: boolean): Profile
    local result=table.clone(preferences:keybinds(isMac))
    for action in retired do result[action]=nil end
    return result
end
function Bindings.keyForAction(profile: Profile,action: string): string? return profile[action] end
function Bindings.enumForAction(profile: Profile,action: string): Enum.KeyCode?
    local name=profile[action]
    if not name then return nil end
    local ok,key=pcall(function() return Enum.KeyCode[name] end)
    return if ok then key else nil
end
function Bindings.actionForKey(profile: Profile,key: any): string?
    local name=if type(key)=="string" then key else key.Name
    for _,spec in actions do if profile[spec.action]==name then return spec.action end end
    return nil
end
local buildKeyboardActions=table.freeze({buildCity=true,buildFactory=true,buildPort=true,buildDefensePost=true,buildMissileSilo=true,buildSamLauncher=true,buildWarship=true,buildAtomBomb=true,buildHydrogenBomb=true,buildMIRV=true})
function Bindings.keyboardAliases(action: string,code: string): {string}
    if code=="Null" then return {} end
    local result={code}
    if buildKeyboardActions[action] then
        local prefix=if string.sub(code,1,6)=="Shift+" then "Shift+" else ""
        local plain=string.sub(code,#prefix+1)
        local digit=string.match(plain,"^Digit(%d)$");local keypad=string.match(plain,"^Numpad(%d)$")
        if digit then table.insert(result,prefix.."Numpad"..digit) elseif keypad then table.insert(result,prefix.."Digit"..keypad) end
    end
    return result
end
function Bindings.keyboardBindingsOverlap(action: string,code: string,otherAction: string,otherCode: string): boolean
    for _,left in Bindings.keyboardAliases(action,code) do for _,right in Bindings.keyboardAliases(otherAction,otherCode) do if left==right then return true end end end
    return false
end
local keyCodes={One="Digit1",Two="Digit2",Three="Digit3",Four="Digit4",Five="Digit5",Six="Digit6",Seven="Digit7",Eight="Digit8",Nine="Digit9",Zero="Digit0",
    KeypadOne="Numpad1",KeypadTwo="Numpad2",KeypadThree="Numpad3",KeypadFour="Numpad4",KeypadFive="Numpad5",KeypadSix="Numpad6",KeypadSeven="Numpad7",KeypadEight="Numpad8",KeypadNine="Numpad9",KeypadZero="Numpad0",
    LeftControl="ControlLeft",RightControl="ControlRight",LeftShift="ShiftLeft",RightShift="ShiftRight",LeftAlt="AltLeft",RightAlt="AltRight",LeftMeta="MetaLeft",RightMeta="MetaRight",Return="Enter",Backquote="Backquote",
    Equals="Equal",LeftBracket="BracketLeft",RightBracket="BracketRight",BackSlash="Backslash",Up="ArrowUp",Down="ArrowDown",Left="ArrowLeft",Right="ArrowRight",
    KeypadPlus="NumpadAdd",KeypadMinus="NumpadSubtract",KeypadMultiply="NumpadMultiply",KeypadDivide="NumpadDivide",KeypadPeriod="NumpadDecimal",KeypadEnter="NumpadEnter"}
function Bindings.keyboardCode(key: Enum.KeyCode): string
    local name=key.Name
    return keyCodes[name] or (if #name==1 and string.match(name,"%u") then "Key"..name else name)
end
return table.freeze(Bindings)
