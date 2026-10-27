--!strict
-- PF034 Discord feed: tells the server once what this device is (touch, keyboard, mouse, gamepad, VR, a console's
-- ten-foot UI, the screen size), so the #joins / #leaves posts can say Phone, Tablet, PC or Console. The server
-- validates it (DiscordFeed.device) and only ever uses it for those posts. Fire and forget: never blocks the game.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VRService = game:GetService("VRService")
local DeviceReport = {}
local started = false

function DeviceReport.start()
    if started then return end
    started = true
    task.spawn(function()
        local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes", 60)
        local remote = folder and folder:WaitForChild("ClientInfo", 60)
        if not remote or not remote:IsA("RemoteEvent") then return end
        local camera = workspace.CurrentCamera
        for _ = 1, 20 do -- the viewport is 1x1 for a moment while the client boots
            camera = workspace.CurrentCamera
            if camera and camera.ViewportSize.X > 1 then break end
            task.wait(0.25)
        end
        local size = if camera then camera.ViewportSize else Vector2.new(0, 0)
        local okTen, tenFoot = pcall(function() return GuiService:IsTenFootInterface() end)
        remote:FireServer({kind = "Device", touch = UserInputService.TouchEnabled, keyboard = UserInputService.KeyboardEnabled,
            mouse = UserInputService.MouseEnabled, gamepad = UserInputService.GamepadEnabled, vr = VRService.VREnabled,
            tenFoot = okTen and tenFoot == true, w = math.floor(size.X), h = math.floor(size.Y)})
    end)
end

return DeviceReport
