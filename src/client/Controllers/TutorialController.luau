--!strict
-- The in-match tutorial. PF021 B (PF - 3): Ashton's approved redesign. The tracker
-- (TutorialTracker, authored by tools/atlas/author-pf021-tutorial.luau) shows step N of 5 with a live
-- goal per step from the server's tutorial snapshot (TutorialProgress) and the DECODED match state
-- (MatchPacketFeed: snapshots after the first are deltas, so the raw State packet can't be read for
-- gold, land or silos). The old TutorialGuide stays authored (MatchController checks it) but is
-- retired from view. Visibility keeps the old rules: hidden while choosing land and behind the
-- build menu, the result, the modals and the menus.
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local Shared=game.ReplicatedStorage:WaitForChild("Shared")
local Remotes=require(Shared.Remotes)
local Feed=require(script.Parent.MatchPacketFeed)
local Model=require(script.Parent.TutorialTrackerModel)
local Tracker=require(script.Parent.TutorialTracker)
local TutorialController={}
local started=false
-- "Digit1" -> "1", "KeyM" -> "M" (the player's own City binding, for "Press 1, then click your land").
function TutorialController.keyLabel(binding: any): string?
    if type(binding)~="string" or binding=="" then return nil end
    return (string.gsub(string.gsub(string.gsub(binding,"^Digit",""),"^Key",""),"^Numpad","Num "))
end
local function motionOff(gui: Instance,preferences: any): boolean
    local nodes={gui,gui:FindFirstChild("Background"),gui:FindFirstChild("Background") and (gui :: any).Background:FindFirstChild("Game")}
    for _,node in nodes do
        if node and (node:GetAttribute("ReducedMotion")==true or node:GetAttribute("Static")==true or node:GetAttribute("StaticBackground")==true
            or node:GetAttribute("MotionEnabled")==false) then return true end
    end
    if preferences and type(preferences.snapshot)=="function" then
        local ok,values=pcall(preferences.snapshot,preferences)
        if ok and type(values)=="table" and (values["settings.reducedMotion"]=="true" or values["settings.staticBackground"]=="true"
            or values["settings.motionEnabled"]=="false") then return true end
    end
    return false
end
function TutorialController.start()
    if started then return end;started=true
    local gui=Players.LocalPlayer.PlayerGui:WaitForChild("OpenFront")
    local gameUI=gui.Background.Game
    local guide=gameUI:WaitForChild("TutorialGuide") :: Frame
    guide.Visible=false -- PF021: retired from view; the tracker replaces it
    local remotes=Remotes.client()
    local matchId=0;local attempt="";local revision=0;local lastStep: number?=nil;local memory={}
    local active=false;local phase=""
    local tracker: any=nil
    tracker=Tracker.new(gameUI,{
        reduced=function() return motionOff(gui,Feed.context.preferences) end,
        play=function(cue: string) local audio=Feed.context.audio;if audio then audio:play(cue) end end,
        exit=function() if matchId>0 then remotes.Command:FireServer({kind="Exit",matchId=matchId}) end end,
    })
    if not tracker then
        warn("[TutorialController] Game.PFTutorial is not authored (run tools/atlas/author-pf021-tutorial.luau); the tutorial tracker is off")
        return
    end
    local function visible()
        tracker:setShown(active and gameUI.Visible and phase~="Choosing"
            and not gameUI.BuildMenu.Visible and not gameUI.Result.Visible
            and not gameUI.QuickChatModal.Visible and not gameUI.DiplomacyPanel.Visible
            and not gameUI.DiplomacyEmojiMenu.Visible
            and not gui.Background.UserSettings.Visible
            and not gui.Background.GameMenu.Visible
            and not gui.Background.RenderDebugJSON.Visible
            and not gameUI.VariantExitConfirm.Visible)
    end
    for _,panel in {gameUI,gameUI.BuildMenu,gameUI.Result,gameUI.QuickChatModal,
        gameUI.DiplomacyPanel,gameUI.DiplomacyEmojiMenu,gui.Background.UserSettings,
        gui.Background.GameMenu,gui.Background.RenderDebugJSON,gameUI.VariantExitConfirm} do
        panel:GetPropertyChangedSignal("Visible"):Connect(visible)
    end
    -- Home packets carry no state (MatchController doesn't publish them): the tutorial ends.
    remotes.State.OnClientEvent:Connect(function(packet)
        if type(packet)=="table" and packet.kind=="Home" and type(packet.matchId)=="number" and packet.matchId>=matchId then
            matchId=packet.matchId;active=false;visible()
        end
    end)
    Feed.subscribe(function(packet: any)
        if type(packet)~="table" or type(packet.matchId)~="number" or packet.matchId<matchId or not packet.state then return end
        local data=packet.tutorial
        if not data then matchId=packet.matchId;active=false;visible();return end
        if type(data.attemptId)~="string" or type(data.revision)~="number" then return end
        if packet.matchId==matchId and data.attemptId==attempt and data.revision<revision then return end
        if packet.matchId~=matchId or data.attemptId~=attempt then
            tracker:reset();memory={};lastStep=nil
        end
        matchId=packet.matchId;attempt=data.attemptId;revision=data.revision
        local preferences=Feed.context.preferences
        local cityKey,siloKey=nil,nil
        if preferences and type(preferences.keybinds)=="function" then
            local ok,binds=pcall(preferences.keybinds,preferences,false)
            if ok and type(binds)=="table" then cityKey=TutorialController.keyLabel(binds.buildCity);siloKey=TutorialController.keyLabel(binds.buildMissileSilo) end
        end
        local view=Model.view({snapshot=data,state=packet.state,memory=memory,mode=UserInputService.PreferredInput.Name,cityKey=cityKey,siloKey=siloKey,
            ownerColor=Feed.context.ownerColor})
        local step=tonumber(data.step) or 1
        tracker:update(view,Model.completions(lastStep,step))
        lastStep=step
        active=true;phase=tostring(packet.state.phase);visible()
    end)
end
return TutorialController
