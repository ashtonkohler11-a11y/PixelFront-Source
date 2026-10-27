--!strict
-- Approved per-user preferences, exclusively in the new OpenFrontUserSettings_v1 namespace.
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local Remotes=require(game.ReplicatedStorage.Shared.Remotes)
local Profiles=require(script.Parent.PreferencesProfiles)
local Preferences={}
local started=false
local engine: any=nil
-- PF025 (PF - 3): who wants to hear a player's saved preferences change (CosmeticService folds the VIP box's
-- vipBadge / goldLobbies into replicated attributes). Called with the Player after a load and after every Set.
local listeners: {(Player)->()}={}
local function changed(player: Player?) if player then for _,listener in listeners do task.spawn(listener,player) end end end
function Preferences.start()
    if started then return end;started=true
    local store=DataStoreService:GetDataStore("OpenFrontUserSettings_v1")
    local remote=Remotes.server();local players: {[number]: Player}={}
    local profiles=Profiles.new({now=os.clock,spawn=task.spawn,delay=task.delay,wait=task.wait,
        active=function(userId: number) local player=players[userId];return player~=nil and player.Parent==Players end,
        get=function(key: string) return store:GetAsync(key) end,
        update=function(key: string,transform: any) return store:UpdateAsync(key,transform) end,
        notify=function(userId: number,packet: any)
            local player=players[userId];if player and player.Parent==Players then remote.PreferencesState:FireClient(player,packet);changed(player) end
        end,
    })
    engine=profiles
    local function load(player: Player) players[player.UserId]=player;profiles:add(player.UserId) end
    Players.PlayerAdded:Connect(load);for _,player in Players:GetPlayers() do load(player) end
    remote.PreferencesCommand.OnServerEvent:Connect(function(player: Player,command: any)
        if players[player.UserId]==player and profiles:command(player.UserId,command) and type(command)=="table" and command.kind=="Set" then changed(player) end
    end)
    Players.PlayerRemoving:Connect(function(player: Player)
        profiles:remove(player.UserId);if players[player.UserId]==player then players[player.UserId]=nil end
    end)
    game:BindToClose(function() profiles:close() end)
end
-- Onboarding: the saved gamesPlayed (nil while loading; {failed=true} when the store couldn't be read).
function Preferences.history(userId: number): any?
    if not engine then return {failed=true} end
    local profile=engine.profiles[userId]
    if not profile then return nil end
    if not profile.loaded then return if profile.failed then {failed=true} else nil end
    return {gamesPlayed=tonumber(profile.storage.gamesPlayed) or 0}
end
-- PF025: a saved preference's raw stored value ("settings.vipBadge" -> "hide"), nil when unset or not loaded.
function Preferences.value(userId: number,key: string): string?
    if not engine then return nil end
    local profile=engine.profiles[userId]
    if not profile or not profile.loaded then return nil end
    return profile.storage[key]
end
function Preferences.subscribe(listener: (Player)->()) table.insert(listeners,listener) end
return Preferences