--!strict
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local MatchService=require(script.Parent.MatchService)
local TutorialService={}
local started=false
-- First-match onboarding (Ashton 2026-10-26): /tutorial replays the first-join flow (the loading screen, then straight into
-- the first match) through OnboardingService; where that flow can't run, the old lobby tutorial start (same match).
local function run(player: Player)
    local ok,Onboarding=pcall(require,script.Parent.OnboardingService)
    if ok and type(Onboarding)=="table" and Onboarding.replay and Onboarding.replay(player) then return end
    MatchService.startLobbyTutorial(player)
end
function TutorialService.start()
    if started then return end;started=true
    -- TextSource / Player identities come from Roblox, never text claims.
    local command=Instance.new("TextChatCommand")
    command.Name="OpenFrontTutorialCommand";command.PrimaryAlias="/tutorial"
    command.AutocompleteVisible=false;command.Parent=TextChatService
    command.Triggered:Connect(function(source: TextSource,text: string)
        if not source then return end
        if string.lower(text:match("^%s*(.-)%s*$") or "")~="/tutorial" then return end
        local player=Players:GetPlayerByUserId(source.UserId)
        if player then run(player) end
    end)
    -- Legacy chat still authenticates the Player provided by Roblox.
    if TextChatService.ChatVersion==Enum.ChatVersion.LegacyChatService then
        local function bind(player: Player)
            player.Chatted:Connect(function(text)
                if string.lower(text:match("^%s*(.-)%s*$") or "")=="/tutorial" then run(player) end
            end)
        end
        Players.PlayerAdded:Connect(bind);for _,player in Players:GetPlayers() do bind(player) end
    end
end
return TutorialService
