--!strict
-- Shows the private result of an owner-only chat command (/cobalt, /pass) as a
-- local system message. The server only fires this to the admin who ran it.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TextChatService=game:GetService("TextChatService")
local StarterGui=game:GetService("StarterGui")
local AdminFeedback={}
local started=false

local function show(message: string)
    local channels=TextChatService:FindFirstChild("TextChannels")
    local channel=channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
    if channel and pcall(function() (channel :: TextChannel):DisplaySystemMessage(message) end) then return end
    pcall(function() StarterGui:SetCore("SendNotification",{Title="Admin",Text=message,Duration=6}) end)
end

function AdminFeedback.start()
    if started then return end;started=true
    task.spawn(function()
        local folder=ReplicatedStorage:WaitForChild("OpenFrontRemotes")
        local event=folder:WaitForChild("AdminFeedback",30) :: RemoteEvent?
        if event then event.OnClientEvent:Connect(function(message: any) if type(message)=="string" then show(message) end end) end
    end)
end

return AdminFeedback
