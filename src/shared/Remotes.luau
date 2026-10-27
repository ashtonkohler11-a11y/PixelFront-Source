--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = {}

export type Bundle = { Command: RemoteEvent, State: RemoteEvent, PreferencesCommand: RemoteEvent, PreferencesState: RemoteEvent, LobbyCommand: RemoteEvent, LobbyState: RemoteEvent, CosmeticsCommand: RemoteEvent, CosmeticsState: RemoteEvent, CustomFlagCommand: RemoteEvent, CustomFlagState: RemoteEvent }

function Remotes.server(): Bundle
    assert(RunService:IsServer(), "Only the server creates remotes")
    local folder = ReplicatedStorage:FindFirstChild("OpenFrontRemotes")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "OpenFrontRemotes"
        folder.Parent = ReplicatedStorage
    end
    local function remote(name: string): RemoteEvent
        local existing = folder:FindFirstChild(name)
        if existing then
            assert(existing:IsA("RemoteEvent"), "Unexpected remote class: " .. name)
            return existing
        end
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = folder
        return event
    end
    return { Command = remote("Command"), State = remote("State"),PreferencesCommand=remote("PreferencesCommand"),PreferencesState=remote("PreferencesState"),LobbyCommand=remote("LobbyCommand"),LobbyState=remote("LobbyState"),CosmeticsCommand=remote("CosmeticsCommand"),CosmeticsState=remote("CosmeticsState"),
        CustomFlagCommand=remote("CustomFlagCommand"),CustomFlagState=remote("CustomFlagState") } -- PF020 G1 Flag Forge
end

function Remotes.client(): Bundle
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    return {
        Command = folder:WaitForChild("Command") :: RemoteEvent,
        State = folder:WaitForChild("State") :: RemoteEvent,
        PreferencesCommand=folder:WaitForChild("PreferencesCommand") :: RemoteEvent,
        PreferencesState=folder:WaitForChild("PreferencesState") :: RemoteEvent,
        LobbyCommand=folder:WaitForChild("LobbyCommand") :: RemoteEvent,
        LobbyState=folder:WaitForChild("LobbyState") :: RemoteEvent,
        CosmeticsCommand=folder:WaitForChild("CosmeticsCommand") :: RemoteEvent,
        CosmeticsState=folder:WaitForChild("CosmeticsState") :: RemoteEvent,
        CustomFlagCommand=folder:WaitForChild("CustomFlagCommand") :: RemoteEvent, -- PF020 G1 Flag Forge
        CustomFlagState=folder:WaitForChild("CustomFlagState") :: RemoteEvent,
    }
end

return Remotes
