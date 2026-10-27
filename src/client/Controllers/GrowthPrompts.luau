--!strict
-- PF037 growth hooks, the client half (no authored UI: Roblox's own prompts and toast). The server (GrowthService) says
-- when, once per account: {kind="Notify"} after the 1st win (ExperienceNotificationService opt-in), {kind="Favorite"}
-- after the 2nd win (AvatarEditorService favorite prompt), {kind="InviteReward", amount, count, cap} when an invited
-- friend finished their first match.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Prompts = {}
local started = false
function Prompts.handle(packet: any)
    if type(packet) ~= "table" then return end
    if packet.kind == "Notify" then
        task.spawn(function()
            local service = game:GetService("ExperienceNotificationService")
            local ok, can = pcall(function() return service:CanPromptOptInAsync() end)
            if ok and can then pcall(function() service:PromptOptIn() end) end
        end)
    elseif packet.kind == "Favorite" then
        pcall(function() game:GetService("AvatarEditorService"):PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true) end)
    elseif packet.kind == "InviteReward" then
        pcall(function()
            StarterGui:SetCore("SendNotification", {Title = "Friend played: +" .. tostring(packet.amount or 50) .. " Cobalt",
                Text = tostring(packet.count or 1) .. " of " .. tostring(packet.cap or 5) .. " friends", Duration = 6})
        end)
    end
end
function Prompts.start()
    if started then return end
    started = true
    task.spawn(function()
        local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes", 60)
        local remote = folder and folder:WaitForChild("GrowthPrompt", 60)
        if remote and remote:IsA("RemoteEvent") then (remote :: RemoteEvent).OnClientEvent:Connect(Prompts.handle) end
    end)
end
return Prompts
