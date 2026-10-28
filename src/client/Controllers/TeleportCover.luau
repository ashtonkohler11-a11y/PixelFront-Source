--!strict
-- PF - 3 (MM 2026-10-27, bounce audit #1: every server hop showed Roblox's generic teleport screen). Every teleport of
-- ours carries PixelFront's own "Joining your match" screen through the hop: a clone of the authored
-- Background.PFJoining (tools/atlas/author-pf-joining.luau), its first step running, set with
-- TeleportService:SetTeleportGui. Both ends already show that same screen (JoiningView on a match server, the boot
-- cover on a hub), so hub → match → hub reads as one screen. On a match server the trip is home: "Back to the lobby".
-- Content only: the authored layout is cloned as is; this fills the words and the map.
local Players=game:GetService("Players")
local TeleportService=game:GetService("TeleportService")
local JoiningView=require(script.Parent.JoiningView)
local M={}
M.HOME_TITLE="Back to the lobby"
local current: any=nil -- {screen, view}

-- The teleport screen from the authored joining screen, or nil when it isn't installed.
function M.build(gui: Instance): (ScreenGui?,any)
    local background=gui:FindFirstChild("Background")
    local source=background and background:FindFirstChild("PFJoining")
    if not source or not source:IsA("GuiObject") then return nil,nil end
    local screen=Instance.new("ScreenGui")
    screen.Name="PFTeleportGui";screen.IgnoreGuiInset=true;screen.ResetOnSpawn=false;screen.DisplayOrder=1000
    screen.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    local copy=source:Clone()
    copy.Visible=true;copy.Position=UDim2.fromScale(0,0);copy.Size=UDim2.fromScale(1,1);copy.Parent=screen
    local panel=copy:FindFirstChild("Panel")
    if panel and panel:IsA("GuiObject") then panel.Visible=true end
    if panel and panel:IsA("CanvasGroup") then panel.GroupTransparency=0 end
    -- JoiningView's own painting (steps, map art) on the copy: it reads only root / panel
    local view=setmetatable({root=copy,panel=panel,o={},phase="off",started=os.clock(),connections={}},JoiningView)
    view:setStep(1)
    if JoiningView.isMatchServer() then
        local title=panel and panel:FindFirstChild("Title")
        if title and title:IsA("TextLabel") then title.Text=M.HOME_TITLE end
    end
    return screen,view
end
-- The map on the teleport screen (a Solo start, the first match): its land art and name, like the arriving screen.
function M.map(name: string?,modeText: string?)
    if not current or type(name)~="string" or name=="" then return end
    current.name,current.mode=name,modeText
    local line=if current.note then (if modeText then modeText.." · " else "")..current.note else modeText
    pcall(function() current.view.mapName=nil;current.view:map(name,line) end)
end
-- A line after the map's ("Africa · Solo · You left your party"): a Solo start that took you out of your party.
function M.note(words: string)
    if not current then return end
    current.note=words
    if current.name then M.map(current.name,current.mode) end
end
function M.start()
    local gui=Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("OpenFront",30)
    if not gui then return end
    local screen,view=M.build(gui)
    if not screen then return end
    current={screen=screen,view=view}
    local ok,failure=pcall(function() TeleportService:SetTeleportGui(screen) end)
    if not ok then warn("[OpenFront] Teleport screen unavailable: "..tostring(failure)) end
end
return M
