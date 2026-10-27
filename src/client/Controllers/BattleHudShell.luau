--!strict
-- PF012 top-left icon bar. It sits in the Roblox topbar row, right of Roblox's
-- own buttons, at their size. It only routes to existing actions: the camera
-- focus on your country, the authored exit confirmation and (PF013, after the
-- top-right toolbar was removed) the existing in-match settings menu.
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Theme=require(script.Parent.BattleHudTheme)
local Controls=require(script.Parent.BattleHudControls)
local Shell={}
-- PIVOT D1: Help (the gold "?", tools/atlas/author-pivot-howto.luau) opens the How to play sheet (HowToPlay)
Shell.Buttons=table.freeze({"Locate","Leave","Settings","Help"})
-- Measured in Play (2026-10-05): Roblox's discs are 44px, 8px apart, 12px
-- below the top of the 58px topbar row; the Unibar ends at x=208.
-- Sampled from Roblox's own discs over the topbar row: (17,18,22), opaque.
Shell.RestColor=Color3.fromRGB(17,18,22);Shell.HoverColor=Color3.fromRGB(40,42,48);Shell.PressColor=Color3.fromRGB(56,59,66)
Shell.Descriptions=table.freeze({Locate="Find my country",Leave="Leave match",Settings="Settings",Help="How to play"})

-- PF013: the bar, its discs and the game-time pill are authored in the Roblox
-- topbar row (x 216, y 12; 44px, 8px apart). Only controller links are set here.
function Shell.link(bar: Instance)
    local previous: any=nil
    for _,name in Shell.Buttons do
        local button: any=bar:FindFirstChild(name)
        if not button then continue end
        button.NextSelectionUp=button
        button.NextSelectionLeft=previous or button
        button.NextSelectionRight=button
        if previous then previous.NextSelectionRight=button end
        previous=button
    end
end

function Shell.setActive(bar: Instance?,active: boolean)
    if not bar then return end
    for _,name in Shell.Buttons do
        local button=bar:FindFirstChild(name)
        if button and button:IsA("GuiButton") then
            button.Active=active and Controls.visible(button);button.Selectable=button.Active
            if not button.Active and GuiService.SelectedObject==button then GuiService.SelectedObject=nil end
        end
    end
end

-- Hover/press feedback mirrors Roblox's topbar: the dark disc lightens a step.
-- (Rest colour also authored natively; the runtime only steps it.)
function Shell.bind(bar: Instance,callbacks: any,allowed: ()->boolean): {RBXScriptConnection}
    local connections={}
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(connections,signal:Connect(fn)) end
    for _,name in Shell.Buttons do
        local button=bar:FindFirstChild(name)
        local help=callbacks.help or function() local ok,H=pcall(require,script.Parent:FindFirstChild("HowToPlay") :: any);if ok and H then (H :: any).open() end end
        local action=({Locate=callbacks.focus,Leave=callbacks.leave,Settings=callbacks.settings,Help=help} :: any)[name]
        if not button or not button:IsA("GuiButton") or not action then continue end
        local hovered,pressed=false,false
        local function paint()
            button.BackgroundTransparency=0
            button.BackgroundColor3=if pressed then Shell.PressColor elseif hovered or GuiService.SelectedObject==button then Shell.HoverColor else Shell.RestColor
        end
        button:SetAttribute("ActionDescription",Shell.Descriptions[name]);button:SetAttribute("SourceTooltip",Shell.Descriptions[name])
        listen(button.Activated,Controls.guardedAction(button,function()
            return allowed() and not GuiService.MenuIsOpen and UserInputService:GetFocusedTextBox()==nil
        end,action))
        listen(button.MouseEnter,function() hovered=true;paint() end)
        listen(button.MouseLeave,function() hovered=false;pressed=false;paint() end)
        listen(button.MouseButton1Down,function() pressed=true;paint() end)
        listen(button.MouseButton1Up,function() pressed=false;paint() end)
        listen(GuiService:GetPropertyChangedSignal("SelectedObject"),paint)
        local focus=button:FindFirstChild("FocusBorder")
        if focus and focus:IsA("UIStroke") then focus.Color=Theme.Cobalt end
        paint()
    end
    return connections
end

-- Stay is the solid default. The source exit confirm's own hover handlers fade
-- its Cancel into a ghost; restore it right after they run.
function Shell.holdStay(confirm: Instance?): {RBXScriptConnection}
    local connections={}
    local body=confirm and confirm:FindFirstChild("Body");local stay=body and body:FindFirstChild("Cancel")
    if not stay or not stay:IsA("GuiButton") then return connections end
    local function restore()
        task.defer(function()
            if stay.Parent then (stay :: any).BackgroundTransparency=0;(stay :: any).TextTransparency=0 end
        end)
    end
    for _,signal in {stay.MouseEnter,stay.MouseLeave,(confirm :: any):GetPropertyChangedSignal("Visible")} do
        table.insert(connections,signal:Connect(restore))
    end
    restore()
    return connections
end

-- Always ask, even while spectating: the leave icon is a double check by design.
-- Reuses the authored VariantExitConfirm and its existing Stay/Leave handlers.
function Shell.confirmLeave(variantHUD: any): boolean
    if not variantHUD or not variantHUD.state or not variantHUD.exitConfirm then return false end
    local confirm=variantHUD.exitConfirm
    if confirm.Visible then return false end
    confirm.Visible=true;variantHUD:layout()
    if string.sub(UserInputService:GetLastInputType().Name,1,7)=="Gamepad" then
        GuiService.SelectedObject=confirm.Body.Cancel
    end
    return true
end

return table.freeze(Shell)
