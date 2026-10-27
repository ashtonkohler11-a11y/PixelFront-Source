--!strict
-- Local system feedback only; never SendAsync or a global chat broadcast.
local Chat = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local Feedback = {}
function Feedback.show(message: string): boolean
    local channels = Chat:FindFirstChild("TextChannels")
    local channel = channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
    if channel then
        local ok = pcall(function() channel:DisplaySystemMessage(message) end)
        if ok then return true end
    end
    local ok = pcall(function() StarterGui:SetCore("SendNotification", {Title = "Tutorial", Text = message, Duration = 5}) end)
    return ok
end
return table.freeze(Feedback)
