--!strict
-- PF020 G1 Flag Forge (PF - 3): wires CustomFlagProfiles to Roblox. Its own DataStore (Studio keeps a
-- memory store), the pass from CosmeticService's replicated OpenFrontCustomFlagPass attribute,
-- GetProductInfo for the id check, the equipped frame published as the OpenFrontCustomFlag attribute
-- (every client validates it with CustomFlagFrame before drawing), and the CustomFlag remotes.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local DataStoreService=game:GetService("DataStoreService")
local MarketplaceService=game:GetService("MarketplaceService")
local Remotes=require(game.ReplicatedStorage.Shared.Remotes)
local Profiles=require(script.Parent.CustomFlagProfiles)
local Service={}
local started=false
local engine: any=nil
local function clone(value: any): any
    if type(value)~="table" then return value end
    local result={};for k,v in value do result[k]=clone(v) end;return result
end
function Service.start()
    if started then return end;started=true
    local studio=RunService:IsStudio()
    local store: any=if studio then nil else DataStoreService:GetDataStore(Profiles.STORE)
    local memory: {[string]: any}={}
    local remote=Remotes.server()
    local players: {[number]: Player}={}
    engine=Profiles.new({
        get=function(key: string) return if studio then clone(memory[key]) else store:GetAsync(key) end,
        update=function(key: string,transform: any)
            if not studio then return store:UpdateAsync(key,transform) end
            local result=transform(clone(memory[key]))
            if result==nil then return nil end
            memory[key]=clone(result);return clone(result)
        end,
        productInfo=function(asset: number) return pcall(MarketplaceService.GetProductInfo,MarketplaceService,asset,Enum.InfoType.Asset) end,
        owns=function(userId: number)
            local player=players[userId]
            return player~=nil and player:GetAttribute("OpenFrontCustomFlagPass")==true
        end,
        publish=function(userId: number,code: string?)
            local player=players[userId]
            if player and player.Parent==Players and player:GetAttribute("OpenFrontCustomFlag")~=code then player:SetAttribute("OpenFrontCustomFlag",code) end
        end,
        notify=function(userId: number,packet: any)
            local player=players[userId]
            if player and player.Parent==Players then remote.CustomFlagState:FireClient(player,packet) end
        end,
        now=os.clock,spawn=task.spawn,
    })
    local function add(player: Player)
        players[player.UserId]=player;engine:add(player.UserId)
        player:GetAttributeChangedSignal("OpenFrontCustomFlagPass"):Connect(function()
            if players[player.UserId]==player then engine:passChanged(player.UserId) end
        end)
    end
    Players.PlayerAdded:Connect(add)
    for _,player in Players:GetPlayers() do add(player) end
    Players.PlayerRemoving:Connect(function(player: Player)
        if players[player.UserId]~=player then return end
        players[player.UserId]=nil;engine:remove(player.UserId)
    end)
    remote.CustomFlagCommand.OnServerEvent:Connect(function(player: Player,command: any)
        if players[player.UserId]==player then engine:command(player.UserId,command) end
    end)
end
return Service
