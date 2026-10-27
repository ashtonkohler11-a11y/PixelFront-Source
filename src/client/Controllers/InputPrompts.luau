--!strict
-- Native glyphs follow Roblox's connected controller family, including PS/Xbox.
-- https://create.roblox.com/docs/reference/engine/classes/UserInputService#GetImageForKeyCode
local UserInputService = game:GetService("UserInputService")
local Prompts = {}
local images: {[Enum.KeyCode]: string} = {}
local names: {[string]: string}={ButtonSquare="□",ButtonCross="×",ButtonCircle="○",ButtonTriangle="△",
    ButtonX="X",ButtonA="A",ButtonB="B",ButtonY="Y",ButtonL1="LB",ButtonR1="RB",ButtonL2="LT",ButtonR2="RT",ButtonSelect="View"}

function Prompts.mode(input: Enum.UserInputType?): string
    if input then
        if string.sub(input.Name,1,7)=="Gamepad" then return "Gamepad" end
        return if input==Enum.UserInputType.Touch then "Touch" else "KeyboardAndMouse"
    end
    return UserInputService.PreferredInput.Name
end

function Prompts.invalidate()
    table.clear(images)
end

function Prompts.image(key: Enum.KeyCode): string
    if images[key] == nil then
        local ok, value = pcall(function() return UserInputService:GetImageForKeyCode(key) end)
        images[key] = if ok then value else ""
    end
    return images[key]
end

function Prompts.buttonName(key: Enum.KeyCode): string
    local ok,value=pcall(function() return UserInputService:GetStringForKeyCode(key) end)
    if ok and names[value] then return names[value] end
    return names[key.Name] or key.Name
end

function Prompts.boatBinding(binding: string?, bindings: {[string]: string}?): string?
    -- No catalog owns B; honor the actual configured boat action unchanged.
    return binding
end

-- PF019 W7 S11 Hotkey hints: Off hides the key/button hint glyphs. RevampInterface:setPreferences
-- hands the settings in (MatchController calls it on every settings change).
local preferences: any=nil
function Prompts.setPreferences(value: any) preferences=value end
function Prompts.hintsShown(): boolean
    return not (preferences and type(preferences.get)=="function" and preferences:get("hotkeyHints")==false)
end

function Prompts.apply(button: Instance, keyboard: string, key: Enum.KeyCode, mode: string?)
    local label=button:FindFirstChild("Shortcut")
    local icon=button:FindFirstChild("PromptIcon")
    if not label or not label:IsA("TextLabel") then return end
    local device=mode or Prompts.mode()
    local hideTouch=device=="Touch" and button:GetAttribute("PFHideTouchPrompt")==true
    local hints=Prompts.hintsShown()
    local glyph=if device=="Gamepad" then Prompts.image(key) else ""
    local hasIcon=icon~=nil and icon:IsA("ImageLabel")
    if icon and icon:IsA("ImageLabel") then
        icon.Image=glyph;icon.Visible=hints and not hideTouch and device=="Gamepad" and glyph~=""
    end
    label.Text=if device=="Gamepad" then Prompts.buttonName(key) elseif device=="Touch" then "Tap" else keyboard
    label.Visible=hints and not hideTouch and (device~="Gamepad" or glyph=="" or not hasIcon)
end

return Prompts
