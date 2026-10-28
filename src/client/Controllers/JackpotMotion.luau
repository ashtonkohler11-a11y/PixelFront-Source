--!strict
-- PF - 4 (UI lock-in BUILD-OUT, Ashton 2026-10-28 "just build it all"): the life of every Jackpot box (the Starter Pack boxes:
-- PFStarterJackpot on Home, Shop, Armory and the end card; the 2× Cobalt boxes: PF1Jackpot). Every 5 s, while a box shows:
-- its −70% coin ticks 1 -> 1.12 -> 1 (.3 s; on a 2× box, its FOREVER / BEST DEAL tag ticks instead) and one light sweeps
-- its key (the authored PFJPSheen band, tools/atlas/author-pf4-jackpot-sheen.luau). Boxes run a little apart so a screen with
-- two never pulses in sync. All through UiMotion (Reduced motion = still; only while visible; centred scales, R4).
-- Start once from any page (Shop, Armory): JackpotMotion.start(gui).
local Motion=require(script.Parent.UiMotion)
local M={}
M.PERIOD=5
local started=false
local bound: {[Instance]: boolean}=setmetatable({},{__mode="k"}) :: any
local serial=0
local function keyOf(host: Instance): Instance?
    for _,name in {"Key","Buy","Tag"} do local k=host:FindFirstChild(name,true);if k and k:IsA("GuiObject") and k:FindFirstChild("PFJPSheen",true) then return k end end
    return host:FindFirstChild("Key",true) or host:FindFirstChild("Buy",true)
end
local function beat(host: GuiObject)
    local coin=host:FindFirstChild("PFJPCoin",true)
    local tag=coin or host:FindFirstChild("PFJPForever",true) or host:FindFirstChild("PFJPTag",true)
    if tag and tag:IsA("GuiObject") and tag.Visible then Motion.tick(tag,if coin then 1.12 else 1.1,.3) end
    local key=keyOf(host)
    local band=key and key:FindFirstChild("PFJPSheen",true)
    local g=band and band:FindFirstChildOfClass("UIGradient")
    if key and (key :: any).Visible and g then Motion.sweep(g,.6) end
end
function M.bind(host: Instance)
    if bound[host] or not host:IsA("GuiObject") then return end
    if host:GetAttribute("PFStarterJackpot")==nil and host:GetAttribute("PF1Jackpot")==nil then return end
    bound[host]=true;serial+=1
    local offset=(serial%4)*.7
    task.delay(offset,function() if host.Parent then Motion.every(host,M.PERIOD,beat) end end)
end
function M.start(gui: Instance?)
    if started then return end
    local root=gui
    if not root then
        local player=game:GetService("Players").LocalPlayer
        local pg=player and player:FindFirstChildOfClass("PlayerGui")
        root=pg and pg:FindFirstChild("OpenFront")
    end
    if not root then return end
    started=true
    for _,d in root:GetDescendants() do M.bind(d) end
    root.DescendantAdded:Connect(function(d) task.defer(M.bind,d) end)
end
return M
