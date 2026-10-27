--!strict
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Typography = require(Shared:WaitForChild("PixelFrontTypography"))
local UIOnlyController = {}
local started = false

function UIOnlyController.start()
    if started then
        return
    end
    started = true
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    -- StarterGui normally copies on character spawn; this game has no spawn.
    -- Clone only our persistent GUI, without waiting for CharacterAdded.
    local existing = playerGui:FindFirstChild("OpenFront")
    local gui: ScreenGui
    if existing and existing:IsA("ScreenGui") then
        gui = existing
    else
        local template = StarterGui:WaitForChild("OpenFront") :: ScreenGui
        gui = template:Clone()
        gui.Parent = playerGui
    end
    gui.ResetOnSpawn = false
    gui.Enabled = true
    Typography.bind(gui)
    -- PF013: the full-screen map layer (named by PF013MapLayer) ships the same
    -- way; MatchController shows it only during a match.
    local layerName = gui:GetAttribute("PF013MapLayer")
    if type(layerName) == "string" and not playerGui:FindFirstChild(layerName) then
        local layer = (StarterGui:WaitForChild(layerName) :: ScreenGui):Clone()
        layer.ResetOnSpawn = false
        layer.Parent = playerGui
        Typography.bind(layer)
    end
    -- Preserve authored layout/styling. The temporary status label can be
    -- replaced in Studio without changing the bootstrap.

    -- Sink avatar actions only. Mouse, touch and future map controls stay usable.
    ContextActionService:BindActionAtPriority(
        "OpenFrontBlockAvatarMovement",
        function() return Enum.ContextActionResult.Sink end,
        false,
        Enum.ContextActionPriority.High.Value + 1,
        table.unpack(Enum.PlayerActions:GetEnumItems())
    )
    GuiService.TouchControlsEnabled = false
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
    -- Ashton 2026-10-07: Roblox's player list is off; Tab shows/hides PixelFront's own leaderboard.
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

    local function lockCamera()
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = Config.CameraCFrame
            camera.Focus = CFrame.new(Vector3.zero)
        end
    end
    lockCamera()
    RunService:BindToRenderStep("OpenFrontCamera", Enum.RenderPriority.Camera.Value + 1, lockCamera)

    -- Core scripts may register SetCore a little after this bootstrap.
    task.spawn(function()
        for _ = 1, 50 do
            local ok = pcall(function()
                StarterGui:SetCore("ResetButtonCallback", false)
            end)
            if ok then
                return
            end
            task.wait(0.1)
        end
        warn("[OpenFront] Reset menu did not register; the server still blocks avatars.")
    end)

    player:SetAttribute("OpenFrontUIReady", true)
    print("[OpenFront] UI ready; camera fixed and avatar actions disabled.")
end

return UIOnlyController
