--!strict
-- PF020 G1 Flag Forge (PF - 3): every player's equipped custom flag (the server's OpenFrontCustomFlag
-- attribute, published only while they own the pass) merged into the cosmetic looks by userId, so it
-- rides the same path as the Flag slot: CosmeticAppearance.forState applies "Show cosmetics from"
-- and keeps it only if CustomFlagFrame decodes it. Nothing here trusts the attribute beyond that.
local Players=game:GetService("Players")
local Frame=require(game:GetService("ReplicatedStorage").Shared.CustomFlagFrame)
local Looks={}
Looks.ATTRIBUTE="OpenFrontCustomFlag"
-- A copy of the looks (userId string -> look) with each live custom flag added as look.customFlag.
-- `players` is injectable for tests (defaults to Players:GetPlayers()).
function Looks.overlay(looks: any,players: {any}?): {[string]: any}
    local result={}
    for key,look in looks or {} do result[key]=look end
    for _,player in players or Players:GetPlayers() do
        local code=player:GetAttribute(Looks.ATTRIBUTE)
        if type(code)=="string" and Frame.decode(code) then
            local key=tostring(player.UserId)
            local look=table.clone(result[key] or {})
            look.customFlag=code;result[key]=look
        end
    end
    return result
end
-- Calls back whenever any player's custom flag changes, arrives or leaves. Returns a disconnect.
function Looks.watch(callback: ()->()): ()->()
    local connections: {RBXScriptConnection}={}
    local function track(player: Player)
        table.insert(connections,player:GetAttributeChangedSignal(Looks.ATTRIBUTE):Connect(callback))
        if player:GetAttribute(Looks.ATTRIBUTE)~=nil then callback() end
    end
    table.insert(connections,Players.PlayerAdded:Connect(track))
    table.insert(connections,Players.PlayerRemoving:Connect(function(player: Player)
        if player:GetAttribute(Looks.ATTRIBUTE)~=nil then task.defer(callback) end
    end))
    for _,player in Players:GetPlayers() do track(player) end
    return function() for _,c in connections do c:Disconnect() end;table.clear(connections) end
end
return Looks
