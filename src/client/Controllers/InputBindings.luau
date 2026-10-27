--!strict
-- InputHandler.parseKeybind/keybindMatchesEvent/resolveBuildKeybind at93a136a1.
local SettingsController=require(script.Parent.SettingsController)
local Bindings={}
local builds={
    {"buildCity",Enum.KeyCode.One},{"buildFactory",Enum.KeyCode.Two},{"buildPort",Enum.KeyCode.Three},
    {"buildDefensePost",Enum.KeyCode.Four},{"buildMissileSilo",Enum.KeyCode.Five},{"buildSamLauncher",Enum.KeyCode.Six},
    {"buildAtomBomb",Enum.KeyCode.Eight},{"buildHydrogenBomb",Enum.KeyCode.Nine},{"buildWarship",Enum.KeyCode.Seven},{"buildMIRV",Enum.KeyCode.Zero},
}
function Bindings.matches(code: string,shift: boolean,binding: string?): boolean
    if not binding then return false end
    local requiresShift=string.sub(binding,1,6)=="Shift+"
    return shift==requiresShift and code==(if requiresShift then string.sub(binding,7)else binding)
end
function Bindings.parse(binding: string?): any
    local shift=binding~=nil and string.sub(binding,1,6)=="Shift+"
    return {shift=shift,code=if shift then string.sub(binding :: string,7) else binding}
end
function Bindings.held(activeKeys: {[string]: boolean},binding: string?): boolean
    return binding~=nil and activeKeys[binding]==true
end
function Bindings.resetAllowed(binding: string?,flags: any,activeKeys: {[string]: boolean}): boolean
    if binding=="AltLeft" or binding=="AltRight" then return flags.altKey and not flags.ctrlKey end
    if binding=="ControlLeft" or binding=="ControlRight" then return flags.ctrlKey end
    if binding=="ShiftLeft" or binding=="ShiftRight" then return flags.shiftKey end
    if binding=="MetaLeft" or binding=="MetaRight" then return flags.metaKey end
    return Bindings.held(activeKeys,binding)
end
local function digit(code: string?): string?
    if not code then return nil end
    return string.match(code,"^Digit(%d)$")or string.match(code,"^Numpad(%d)$")
end
function Bindings.build(code: string,shift: boolean,bindings: {[string]: string}): Enum.KeyCode?
    for _,entry in builds do if Bindings.matches(code,shift,bindings[entry[1]])then return entry[2]end end
    local inputDigit=digit(code);if not inputDigit then return nil end
    for _,entry in builds do
        local binding=bindings[entry[1]]
        local requiresShift=binding~=nil and string.sub(binding,1,6)=="Shift+"
        local bound=if requiresShift then string.sub(binding :: string,7)else binding
        if shift==requiresShift and digit(bound)==inputDigit then return entry[2]end
    end
    return nil
end
function Bindings.code(key: Enum.KeyCode): string return SettingsController.code(key)end
return table.freeze(Bindings)
