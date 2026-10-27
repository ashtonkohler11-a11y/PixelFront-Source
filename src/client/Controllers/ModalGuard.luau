--!strict
-- PIVOT (Ashton 2026-10-24, on the daily sheet: "can still hover on the stuff in the back"): while a modal sheet shows,
-- nothing behind it hovers or clicks. lock(overlay) switches Interactable off on every sibling of the overlay and of each
-- of its ancestors up to the ScreenGui; other modal layers (PFModal) are left alone, so a reward drop over the daily
-- sheet still works. unlock restores exactly what it changed (counted, so stacked sheets unwind in any order).
-- watch(gui) follows the authored sheets' Visible: the daily sheet, the reward drop, How to play, the tutorial intro,
-- the Leave confirm, the nameplate picker and Match found. Content only: no layout, no visibility of its own.
local Guard={}
Guard.SHEETS=table.freeze({{"Background","PFStreak"},{"Background","PFRewardDrop"},{"Background","PFHowTo"},{"Background","PFTutorialOffer"},
    {"Background","PFNameplatePicker"},{"Background","PFMatchFound"},{"Background","Game","VariantExitConfirm"}})
local held: {[Instance]: {GuiObject}}={}
local count: {[Instance]: number}={}
local function modal(node: Instance): boolean return node:GetAttribute("PFModal")==true end
function Guard.locked(overlay: Instance): boolean return held[overlay]~=nil end
function Guard.lock(overlay: Instance?)
    if not overlay or held[overlay] then return end
    overlay:SetAttribute("PFModal",true)
    local list: {GuiObject}={}
    local node: Instance?=overlay
    while node and node.Parent and not node:IsA("LayerCollector") do
        for _,sibling in node.Parent:GetChildren() do
            if sibling~=node and sibling:IsA("GuiObject") and not modal(sibling) then
                count[sibling]=(count[sibling] or 0)+1
                if count[sibling]==1 then sibling:SetAttribute("PFModalPre",sibling.Interactable);sibling.Interactable=false end
                table.insert(list,sibling)
            end
        end
        node=node.Parent
    end
    held[overlay]=list
end
function Guard.unlock(overlay: Instance?)
    local list=overlay and held[overlay]
    if not overlay or not list then return end
    held[overlay]=nil
    for _,sibling in list do
        count[sibling]=(count[sibling] or 1)-1
        if count[sibling]<=0 then
            count[sibling]=nil
            local pre=sibling:GetAttribute("PFModalPre")
            sibling.Interactable=if type(pre)=="boolean" then pre else true
            sibling:SetAttribute("PFModalPre",nil)
        end
    end
end
-- lock while the overlay is visible (marked modal up front, so no other sheet ever switches it off)
function Guard.follow(overlay: GuiObject?): RBXScriptConnection?
    if not overlay then return nil end
    overlay:SetAttribute("PFModal",true)
    local function sync() if overlay.Visible and overlay.Parent then Guard.lock(overlay) else Guard.unlock(overlay) end end
    local c=overlay:GetPropertyChangedSignal("Visible"):Connect(sync)
    overlay.Destroying:Connect(function() Guard.unlock(overlay) end)
    sync()
    return c
end
local watched: {[Instance]: boolean}={}
-- true while a shown sheet covers node (the lock's own test, read from the sheets' Visible, so it already holds in the
-- frame a sheet opens; the lock itself waits for the deferred Visible signal). Focus code asks this before selecting.
function Guard.covers(node: Instance): boolean
    for overlay in watched do
        if (overlay :: any).Visible and overlay.Parent and node~=overlay and not node:IsDescendantOf(overlay) then
            local gui=overlay:FindFirstAncestorWhichIsA("LayerCollector")
            if gui and node:IsDescendantOf(gui) then return true end
        end
    end
    return false
end
function Guard.watch(gui: Instance)
    for _,path in Guard.SHEETS do
        local node: Instance?=gui
        for _,name in path do node=node and node:FindFirstChild(name) end
        if node and node:IsA("GuiObject") and not watched[node] then watched[node]=true;Guard.follow(node) end
    end
end
-- the player's OpenFront (cloned into PlayerGui at join); sheets authored later are picked up as they appear
function Guard.start()
    local player=game:GetService("Players").LocalPlayer
    local pg=player and player:WaitForChild("PlayerGui")
    local gui=pg and pg:WaitForChild("OpenFront",60)
    if not gui then return end
    Guard.watch(gui)
    gui.DescendantAdded:Connect(function(d) if d.Name:sub(1,2)=="PF" or d.Name=="VariantExitConfirm" then task.defer(Guard.watch,gui) end end)
end
return Guard
