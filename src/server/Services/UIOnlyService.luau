--!strict
local Players = game:GetService("Players")
local UIOnlyService = {}
local started = false

local function removeCharacter(player: Player, character: Model)
    -- Also reject characters spawned by a future script or a reset attempt.
    if player.Character == character then
        player.Character = nil
    end
    character:Destroy()
end

local function trackPlayer(player: Player)
    player.CharacterAdded:Connect(function(character)
        removeCharacter(player, character)
    end)
    local character = player.Character
    if character then
        removeCharacter(player, character)
    end
    player:SetAttribute("OpenFrontUIOnly", true)
end

function UIOnlyService.start()
    if started then
        return
    end
    started = true
    Players.CharacterAutoLoads = false
    Players:GetPropertyChangedSignal("CharacterAutoLoads"):Connect(function()
        if Players.CharacterAutoLoads then
            Players.CharacterAutoLoads = false
        end
    end)
    Players.PlayerAdded:Connect(trackPlayer)
    for _, player in Players:GetPlayers() do
        trackPlayer(player)
    end
end

return UIOnlyService
