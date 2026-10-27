--!strict
-- Presentation and input only. Every match change is decided by the server.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TutorialFeedback=require(script.Parent.TutorialLobbyFeedback)
local GuiService = game:GetService("GuiService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("Theme"))
local Config = require(Shared:WaitForChild("Config"))
local Performance = require(Shared:WaitForChild("Performance"))
local Simulation = require(Shared:WaitForChild("Simulation"))
local MatchTransport = require(Shared:WaitForChild("MatchTransport"))
local SnapshotRecovery=require(script.Parent.MatchSnapshotRecovery)
local PacketFeed=require(script.Parent.MatchPacketFeed) -- PF021 B (PF - 3): decoded packets for the tutorial tracker
local CustomFlagLooks=require(script.Parent.CustomFlagLooks) -- PF020 G1 (PF - 3): equipped custom flags join the looks
local Navigation = require(Shared:WaitForChild("OpenFrontNavigation"))
local MapRenderer = require(script.Parent:WaitForChild("MapRenderer"))
local NameLayout = require(script.Parent:WaitForChild("NameLayout"))
local MapCamera = require(script.Parent:WaitForChild("MapCamera"))
local PlayerNames = require(script.Parent:WaitForChild("PlayerNames"))
local SpawnPhaseView = require(script.Parent:WaitForChild("SpawnPhaseView")) -- PF030: the spawn phase (the banner + the 30 s ring, pins, preview)
local Leaderboard = require(script.Parent:WaitForChild("Leaderboard"))
local NameplateStyle = require(script.Parent:WaitForChild("NameplateStyle"))
local TeamHUDController = require(script.Parent:WaitForChild("TeamHUDController"))
local TeamHUDData = require(script.Parent:WaitForChild("TeamHUDData"))
local VariantHudController = require(script.Parent:WaitForChild("VariantHudController"))
local CityController = require(script.Parent:WaitForChild("CityController"))
local NavalController = require(script.Parent:WaitForChild("NavalController"))
local WarshipController = require(script.Parent:WaitForChild("WarshipController"))
local IndustryRenderer = require(script.Parent:WaitForChild("IndustryRenderer"))
local WeaponsRenderer = require(script.Parent:WaitForChild("WeaponsRenderer"))
local DiplomacyController = require(script.Parent:WaitForChild("DiplomacyController"))
local QuickChatController = require(script.Parent:WaitForChild("QuickChatController"))
local ReferenceIcons = require(script.Parent:WaitForChild("ReferenceIcons"))
local Collections = require(Shared:WaitForChild("OpenFrontCollections"))
local MapData = require(Shared:WaitForChild("MapData"))
local UserSettings = require(Shared:WaitForChild("UserSettings"))
local LobbyController = require(script.Parent:WaitForChild("LobbyController"))
local SettingsController = require(script.Parent:WaitForChild("SettingsController"))
local InputBindings = require(script.Parent:WaitForChild("InputBindings"))
local Availability = require(Shared:WaitForChild("OpenFrontMatchAvailability"))
local GraphicsSettings = require(Shared:WaitForChild("OpenFrontGraphicsSettings"))
local PreferencePresentation=require(script.Parent:WaitForChild("PreferencePresentation"))
local RenderDebugController=require(script.Parent:WaitForChild("RenderDebugController"))
local RenderEffects=require(script.Parent:WaitForChild("RenderEffects"))
local AudioController=require(script.Parent:WaitForChild("AudioController"))
local StockEffectsRenderer=require(script.Parent:WaitForChild("StockEffectsRenderer"))
local ClientNames=require(Shared.OpenFrontClientNames)
local PublicLobbyController=require(script.Parent.PublicLobbyController)
local TroopSendPop=require(script.Parent.TroopSendPop)
-- PF019 W0 hooks live in this module-level table: MatchController.start is at Luau's
-- 200-local-register limit, so W0 adds no locals to it.
local W0: any={}
-- PF019 M13a/M13b (PF - 2): the in-game menu and the locked shop live here too.
local InGameMenu=require(script.Parent.InGameMenu)
local M13: any={}
local RevampInterface=require(script.Parent.RevampInterface)
local RevampInput=require(script.Parent.RevampInput)
local InputPrompts=require(script.Parent.InputPrompts)
local TextBounds=require(script.Parent.BattleHudTextBounds)
local HudControls=require(script.Parent.BattleHudControls)
local BattleHudShell=require(script.Parent.BattleHudShell)
local CosmeticShopController=require(script.Parent.CosmeticShopController)
local AtlasMenuController=require(script.Parent.AtlasMenuController)
local CosmeticAppearance=require(Shared.CosmeticAppearance)

local MatchController = {}
local started = false
-- Pinned OpenFront 93a136a: TransformHandler.ts and InputHandler.ts.
local MIN_SCALE, MAX_SCALE = 0.2, 20
local DRAG_THRESHOLD = 10
local ZOOM_DELTA_DIVISOR = 600

-- Same visible failure contract covers every shared image, including HUD assets
-- created before the map. Returns false without wiring gameplay input on failure.
function MatchController.initializePresentation(initialize: () -> any,onFailure: (any) -> ()): (boolean,any)
    local ok,value=pcall(initialize)
    if not ok then ReferenceIcons.release();onFailure(value) end
    return ok,value
end

-- These are authored Edit-time UI dependencies, not objects created by a server
-- or controller later. Waiting for them cannot repair a stale native template.
function MatchController.authoredUIIssues(gui: ScreenGui): {string}
    local missing: {[string]: boolean} = {}
    local function required(path: string, className: string?): Instance?
        local current: Instance = gui
        local prefix = "OpenFront"
        for _,name in string.split(path,".") do
            prefix ..= "."..name
            local child = current:FindFirstChild(name)
            if not child then missing[prefix]=true;return nil end
            current=child
        end
        if className and not current:IsA(className) then
            missing[prefix.." (expected "..className..")"]=true;return nil
        end
        return current
    end
    local function children(path: string, names: {string}, className: string?)
        for _,name in names do required(path.."."..name,className) end
    end
    local base="Background.Game."
    children(base.."DiplomacyHover.UnitInfo",{"UnitType","Health","Troops"},"TextLabel")
    required("Background","GuiObject");required("Background.Game","Frame")
    required("Background.Home","Frame")
    required("Background.AtlasMenu","Frame")
    required("Background.AtlasMenu.Header.PFRight.Navigation","Frame") -- PF015: tabs live in the authored right group
    children("Background.AtlasMenu.Pages",{"Play","Stats","Shop","Inventory","Settings"},"Frame")
    required("Background.Home.Body.Solo","TextButton")
    required("Background.Home.Body.Settings","TextButton")
    required("Background.Home.Body.Shop","TextButton")
    required("Background.CosmeticShop","Frame")
    required("Background.CosmeticShop.Body.Scroll.Content","Frame")
    required("Background.CosmeticShop.Templates.ItemCard.Action","TextButton")
    required("Background.CosmeticShop.Confirmation.Confirm","TextButton")
    required("Background.GameMenu.Body.Header.Shop","TextButton")
    required("Background.Home.Body.PublicLobbies","ScrollingFrame")
    required("Background.Home.Body.Upcoming","TextButton")
    required("Background.Home.Body.BrowserBack","TextButton")
    required("Background.Home.PublicTemplates.LobbyCard","TextButton")
    required("Background.PublicWaiting.Body.Return","TextButton")
    -- PF013 (Builder C nests leaderboard nodes in authored layout containers):
    -- match these by name and class anywhere under their authored root.
    local function within(root: Instance?,rootPath: string,path: string,className: string?): Instance?
        if not root then return nil end
        local current: Instance?=root;local label="OpenFront."..rootPath
        for index,name in string.split(path,".") do
            label..=(if index==1 then " ⊃ " else ".")..name
            current=if index==1 then (current :: Instance):FindFirstChild(name,true) else (current :: Instance):FindFirstChild(name)
            if not current then missing[label]=true;return nil end
        end
        if className and not (current :: Instance):IsA(className) then missing[label.." (expected "..className..")"]=true;return nil end
        return current
    end
    -- PF013: the leaderboard lives in Builder A's authored PFLeaderboardRegion
    -- once Builder C's native helper has moved it; accept either parent.
    local gameNode=gui:FindFirstChild("Background") and gui.Background:FindFirstChild("Game")
    local region=gameNode and gameNode:FindFirstChild("PFLeaderboardRegion")
    local boardPath=base..(if region and region:FindFirstChild("Leaderboard") then "PFLeaderboardRegion.Leaderboard" else "Leaderboard")
    local board=required(boardPath,"Frame")
    within(board,boardPath,"StatsStack","ScrollingFrame")
    local teamTable=within(board,boardPath,"TeamTable","Frame")
    required(base.."TeamOwnershipBar","Frame");required(base.."TeamOwnershipBar.Tooltip","TextLabel")
    for _,name in {"Toggle","TeamToggle"} do
        within(board,boardPath,name,"TextButton");within(board,boardPath,name..".Icon","ImageLabel")
    end
    within(board,boardPath,"GameID","TextBox")
    for _,name in {"Caption","TeamName"} do within(board,boardPath,"YourTeam."..name,"TextLabel") end
    local playerTable=within(board,boardPath,"Table","Frame")
    for _,entry in {{playerTable,"Table","TextButton"},{teamTable,"TeamTable","Frame"}} do
        local root,rootPath=entry[1],boardPath.." ⊃ "..entry[2]
        if not root then continue end
        local horizontal=root:FindFirstChild("Horizontal")
        if not horizontal or not horizontal:IsA("ScrollingFrame") then missing["OpenFront."..rootPath..".Horizontal (expected ScrollingFrame)"]=true;continue end
        within(horizontal,rootPath..".Horizontal","Content","Frame")
        within(horizontal,rootPath..".Horizontal","Content.Header","Frame")
        within(horizontal,rootPath..".Horizontal","Content.Header.Picker","TextButton")
        within(horizontal,rootPath..".Horizontal","Content.Scroll","ScrollingFrame")
        within(horizontal,rootPath..".Horizontal","Content.Pinned",entry[3])
    end
    required(base.."Templates.LeaderboardRow","TextButton")
    required(base.."Templates.TeamStatsRow","Frame")
    required(base.."Templates.TeamStatsHeader","TextButton")
    required(base.."Templates.TeamStatsCell","TextLabel")
    required(base.."Templates.TeamOwnershipSegment","TextButton")
    children(base.."Templates.TeamOwnershipSegment",{"RightBorder","BottomBorder"},"Frame")
    local cellNames={rank="Rank",clan="Clan",player="Player",playerType="PlayerType",tiles="Tiles",gold="Gold",goldIncomePerMin="GoldIncomePerMin",shipTradeGoldPerMin="ShipTradeGoldPerMin",piracyGoldPerMin="PiracyGoldPerMin",trainTradeGoldPerMin="TrainTradeGoldPerMin",troops="Troops",maxtroops="MaxTroops",cities="Cities",ports="Ports",factories="Factories",silos="Silos",sams="SAMs",warships="Warships",allies="Allies",betrayals="Betrayals"}
    local function header(path: string)
        children(path,{"Icon","SuperscriptIcon"},"ImageLabel")
        children(path,{"Superscript","Sort"},"TextLabel")
        children(path,{"Divider","Bottom"},"Frame")
    end
    header(base.."Templates.TeamStatsHeader")
    children(base.."Templates.TeamStatsCell",{"Divider","Bottom"},"Frame")
    -- Header cells keep the Header frame as parent; row cells may sit in an
    -- inner body frame of the pinned row / row template (PF013 Builder C).
    local headerFrame=playerTable and playerTable:FindFirstChild("Horizontal") and playerTable.Horizontal:FindFirstChild("Content",true)
    headerFrame=headerFrame and headerFrame:FindFirstChild("Header")
    local headerPath=boardPath.." ⊃ Table.Horizontal.Content.Header"
    local pinned=headerFrame and headerFrame.Parent and headerFrame.Parent:FindFirstChild("Pinned")
    local rowTemplate=required(base.."Templates.LeaderboardRow","TextButton")
    for _,column in TeamHUDData.playerColumns do
        local name=cellNames[column.id]
        local head=within(headerFrame,headerPath,name,if column.orderable then "TextButton" else "GuiObject")
        if head and not head:IsA("TextLabel") and not head:IsA("TextButton") then missing["OpenFront."..headerPath.."."..name.." (expected text header)"]=true end
        if head then
            for _,child in {"Icon","SuperscriptIcon"} do within(head,headerPath.."."..name,child,"ImageLabel") end
            for _,child in {"Superscript","Sort"} do within(head,headerPath.."."..name,child,"TextLabel") end
            for _,child in {"Divider","Bottom"} do within(head,headerPath.."."..name,child,"Frame") end
        end
        for _,entry in {{pinned,headerPath.."/Pinned"},{rowTemplate,base.."Templates.LeaderboardRow"}} do
            local cell=within(entry[1],entry[2],name,"TextLabel")
            if cell then for _,child in {"Divider","Bottom"} do within(cell,entry[2].."."..name,child,"Frame") end end
        end
    end
    -- PF013: the column pickers may be overlays inside the leaderboard card.
    for _,pair in {{"PlayerColumnPicker",TeamHUDData.playerColumns},{"TeamColumnPicker",TeamHUDData.columns}} do
        local picker=(gameNode and gameNode:FindFirstChild(pair[1])) or (board and board:FindFirstChild(pair[1],true))
        local pickerPath=if gameNode and gameNode:FindFirstChild(pair[1]) then base..pair[1] else boardPath.." ⊃ "..pair[1]
        if not picker or not picker:IsA("ScrollingFrame") then missing["OpenFront."..pickerPath.." (expected ScrollingFrame)"]=true;continue end
        for _,column in pair[2] do if column.hideable then
            within(picker,pickerPath,column.id,"TextButton");within(picker,pickerPath,column.id..".Check","Frame");within(picker,pickerPath,column.id..".Check.Mark","TextLabel")
        end end
    end
    required("Background.RenderDebug","Frame")
    required("Background.RenderDebug.Title","TextButton");required("Background.RenderDebug.Scroll","ScrollingFrame")
    required("Background.RenderDebugJSON","Frame")
    children("Background.RenderDebugJSON",{"Title","Close","Apply"},"TextButton")
    required("Background.RenderDebugJSON.Error","TextLabel")
    required("Background.RenderDebugJSON.Text","TextBox")
    required(base.."VariantPanels","Frame")
    for _,name in {"Doomsday","Overtime"} do
        local path=base.."VariantPanels."..name
        required(path,"ImageLabel");children(path..".Header",{"Title","Status"},"TextLabel")
        required(path..".Bar","Frame");children(path..".Bar",{"Fill","Threshold"},"Frame")
        required(path..".Detail","TextLabel")
    end
    required(base.."VariantPanels.Doomsday.Header.Skull","ImageLabel")
    required(base.."VariantPanels.Doomsday.PulseMask","ImageLabel")
    children(base.."VariantPanels.Doomsday.Share",{"Hold","Yours"},"TextLabel")
    required(base.."ClockPanel.SourceBackground","ImageLabel")
    required(base.."Pause.VariantIcon","ImageLabel")
    for _,name in {"Settings","Speed","Exit"} do
        required(base.."GameRightSidebar."..name,"TextButton")
        required(base.."GameRightSidebar."..name..".VariantIcon","ImageLabel")
    end
    required(base.."VariantSpeedPanel","ImageLabel");required(base.."VariantSpeedPanel.Title","TextLabel")
    for _,name in {"Slow","Normal","Fast","Max"} do
        required(base.."VariantSpeedPanel."..name,"TextButton")
        required(base.."VariantSpeedPanel."..name..".Border","UIStroke")
    end
    required(base.."VariantExitConfirm","Frame")
    required(base.."VariantExitConfirm.Backdrop","TextButton")
    required(base.."VariantExitConfirm.Body","Frame")
    required(base.."VariantExitConfirm.Body.Message","TextLabel")
    children(base.."VariantExitConfirm.Body",{"Cancel","Confirm"},"TextButton")
    children(base.."Controls.Actions",{"Build","Primary"},"TextButton")
    children(base.."Navigation",{"Focus","ZoomIn","ZoomOut"},"TextButton")
    required(base.."Controls.Gold.Income","TextLabel")
    required(base.."Controls.Blueprints.Cards.City","TextButton")
    required(base.."Controls.Blueprints.Cards.Factory","TextButton")
    required(base.."Controls.Blueprints.Cards.Port","TextButton")
    for _,name in {"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher","AtomBomb","HydrogenBomb","MIRV"} do
        local path=base.."Controls.Blueprints.Cards."..name
        -- Rojo source arrives before Studio's authored PF-005 migration. The
        -- three legacy nuclear buttons remain the startup-compatible fallback;
        -- validate new Cards when present or when native marks completion.
        local root=gui:FindFirstChild("Background")
        local gameRoot=root and root:FindFirstChild("Game")
        local controlsRoot=gameRoot and gameRoot:FindFirstChild("Controls")
        local blueprints=controlsRoot and controlsRoot:FindFirstChild("Blueprints")
        local cardsRoot=blueprints and blueprints:FindFirstChild("Cards")
        if (name=="AtomBomb" or name=="HydrogenBomb" or name=="MIRV")
            and not (cardsRoot and cardsRoot:FindFirstChild(name))
            and (not gameRoot or gameRoot:GetAttribute("PFHudRevision")==nil) then continue end
        required(path,"TextButton");required(path..".Icon","ImageLabel")
        children(path,{"Title","Description","Shortcut","Cost","Count"},"TextLabel")
        required(path..".PromptIcon","ImageLabel");required(path..".Border","UIStroke");required(path..".Scale","UIScale")
    end
    required(base.."Controls.Placement.Cancel","TextButton")
    required(base.."NuclearActions","Frame")
    required(base.."NuclearActions.Buttons","Frame")
    for _,name in {"AtomBomb","HydrogenBomb","MIRV"} do
        local path=base.."NuclearActions.Buttons."..name
        required(path,"TextButton");required(path..".Icon","ImageLabel");required(path..".SpriteBadge","Frame")
        children(path,{"Title","Cost","Currency","Shortcut"},"TextLabel")
        children(path,{"Border","FocusBorder"},"UIStroke");required(path..".Scale","UIScale")
    end
    required(base.."Result.ReturnLobby","TextButton")
    required(base.."GamepadReticle","Frame")
    required(base.."GamepadHelp","TextLabel")
    children(base.."TutorialGuide",{"Title","Message","Progress"},"TextLabel")
    required(base.."TutorialGuide.Hide","TextButton")
    required(base.."QuickChatModal.Body.StepBack","TextButton")
    children(base.."QuickChatModal.Body.Section.Content.Stages",{"Categories","Phrases","Players"},"TextButton")
    required(base.."QuickChatModal.Body.Section.Content.Columns.Categories","ScrollingFrame")
    required("Background.Home.Body.Tagline","TextLabel")
    required("BackdropBleed","Frame")
    local paths={};for path in missing do table.insert(paths,path) end;table.sort(paths)
    return paths
end

-- PF013: Builder C moves the leaderboard into the authored PFLeaderboardRegion.
function MatchController.leaderboardFrame(gameUI: Instance): Frame
    local region=gameUI:FindFirstChild("PFLeaderboardRegion")
    return ((region and region:FindFirstChild("Leaderboard")) or gameUI:WaitForChild("Leaderboard")) :: Frame
end
-- PF013: the map lives in its own ScreenGui (OpenFront's PF013MapLayer names it;
-- ScreenInsets None) behind the HUD, so it fills the whole screen, under the
-- topbar and into the device insets. Fixtures and older places keep it in Game.
function MatchController.mapPanel(gui: Instance,gameUI: Instance,playerGui: Instance): Frame
    local layer=gui:GetAttribute("PF013MapLayer")
    if type(layer)=="string" then return playerGui:WaitForChild(layer):WaitForChild("MapPanel") :: Frame end
    return gameUI:WaitForChild("MapPanel") :: Frame
end
-- The separate map layer shows only while the battle HUD does. OpenFront's navy
-- BackdropBleed (it bleeds past every screen edge) and Background sit above the
-- map, so during a match the bleed hides and Background is clear; in menus both
-- keep their authored look (Background's PF013MenuTransparency). Visibility/colour
-- state only.
function MatchController.bindMapLayer(gameUI: GuiObject,panel: Instance): RBXScriptConnection?
    local layer=panel.Parent
    if not layer or not layer:IsA("ScreenGui") then return nil end
    local background=gameUI.Parent :: any
    local bleed=background and background.Parent and background.Parent:FindFirstChild("BackdropBleed")
    local function sync()
        (layer :: any).Enabled=gameUI.Visible
        if bleed and bleed:IsA("GuiObject") then bleed.Visible=not gameUI.Visible end
        local menu=background and background:GetAttribute("PF013MenuTransparency")
        if type(menu)=="number" then background.BackgroundTransparency=if gameUI.Visible then 1 else menu end
    end
    sync()
    return gameUI:GetPropertyChangedSignal("Visible"):Connect(sync)
end
-- PF013: the game time lives in the top-left icon bar's pill when authored there.
function MatchController.clockLabel(gameUI: Instance): TextLabel?
    local bar=gameUI:FindFirstChild("PFIconBar");local time=bar and bar:FindFirstChild("Time")
    local label=time and time:FindFirstChild("Clock")
    return if label and label:IsA("TextLabel") then label else nil
end
function MatchController.validateAuthoredUI(gui: ScreenGui, report: ((string)->())?): (boolean,{string})
    local paths=MatchController.authoredUIIssues(gui)
    if #paths==0 then return true,paths end
    local detail="[OpenFront] Authored UI is incomplete or incompatible. Restore the native UI migrations before starting Play. Required paths:\n - "..table.concat(paths,"\n - ")
    gui:SetAttribute("OpenFrontMatchReady",false)
    gui:SetAttribute("OpenFrontUIError",detail)
    local background=gui:FindFirstChild("Background")
    local gameUI=background and background:FindFirstChild("Game")
    local panel=gameUI and gameUI:FindFirstChild("MapError")
    local message=panel and panel:FindFirstChild("Message")
    if background and background:IsA("GuiObject") and gameUI and gameUI:IsA("GuiObject") and panel and panel:IsA("GuiObject") and message and message:IsA("TextLabel") then
        -- Reuse the existing setup diagnostic; do not synthesize native content.
        for _,child in background:GetChildren() do if child:IsA("GuiObject") then child.Visible=child==gameUI end end
        for _,child in gameUI:GetChildren() do if child:IsA("GuiObject") then child.Visible=child==panel end end
        background.Visible=true;gui.Enabled=true
        message.Text="Game UI is incomplete. The authored interface must be updated before this session can start."..(if RunService:IsStudio() then " See Studio Output for the missing UI paths." else "")
    end
    (report or warn)(detail)
    return false,paths
end

function MatchController.weaponNotice(event: any,state: any): (string?,boolean)
    local attacker=state.names[event.attacker] or event.name or ""
    if event.kind=="SAMHit" then return "SAM intercepted "..tostring(event.unitType),false end
    if event.type=="NUKE_INBOUND" then return attacker.." - atom bomb inbound",true end
    if event.type=="HYDROGEN_BOMB_INBOUND" then return attacker.." - hydrogen bomb inbound",true end
    if event.type=="MIRV_INBOUND" then return "⚠️⚠️⚠️ "..attacker.." - MIRV INBOUND ⚠️⚠️⚠️",true end
    if event.type=="NUKE_DETONATED" then
        local hydrogen=event.key=="events_display.hydrogen_bomb_detonated" or event.unitType=="Hydrogen Bomb"
        return attacker.." - "..(if hydrogen then "hydrogen bomb" else "atom bomb").." detonated",false
    end
    return nil,false
end

function MatchController.resultPresentation(state: any,spectator: boolean?): (string?,string)
    -- PF020 G8 Lobby Host+ spectator seat: no "you". The server sends Playing until the match ends; the
    -- end phase is owner 1's (the codec ties the winner to it), so the end names the winner neutrally.
    if spectator then
        if state.phase~="Won"and state.phase~="Lost"and state.phase~="Cancelled"then return nil,""end
        if state.winnerTeam then return "Cancelled",tostring(state.winnerTeam).." team has won!"end
        if not state.winner then return "Cancelled","The match is over"end
        local nation=state.players[state.winner]and state.players[state.winner].playerType=="Nation"
        return "Cancelled",(if nation then "Nation "else "")..ClientNames.resolve(state,state.winner).." has won!"
    end
    -- WinModal.tick handles terminal Win updates after the earlier death cue.
    local outcome=if state.phase=="Won"then "Won"elseif state.phase=="Lost"then "Lost"elseif state.phase=="Cancelled"then "Cancelled"else nil
    if outcome==nil and state.phase~="Choosing"and state.counts[1]==0 and state.players[1].spawnTile~=nil then outcome="Died"end
    if outcome==nil then return nil,""end
    if outcome=="Cancelled"then return outcome,"Match cancelled — not all players spawned"end
    if outcome=="Won"then return outcome,if state.winnerTeam then "Your team won!"else "You Won!"end
    if outcome=="Died"then return outcome,"You died"end
    -- Simulation ends a Solo with phase Lost and no winner when you are
    -- eliminated; never name player slot 2 as the winner for that.
    if outcome=="Lost"and state.winner==nil and not state.winnerTeam then return outcome,"You were eliminated" end
    if state.winnerTeam then return outcome,tostring(state.winnerTeam).." team has won!"end
    local winner=state.winner
    local name=ClientNames.resolve(state,winner or 2)
    local nation=winner and state.players[winner]and state.players[winner].playerType=="Nation"
    return outcome,(if nation then "Nation "else "")..name.." has won!"
end

function MatchController.headsUpMessage(state: any, paused: boolean, controller: boolean, overtimeNotice: boolean?): string
    -- HeadsUpMessage.getMessage, supported Solo states at source93a136a1.
    if paused then return if (state.gameConfig or {}).gameType=="Multiplayer" then "Game paused by Lobby Creator" else "Game paused" end
    if overtimeNotice then return "Overtime! The territory needed to win is now dropping." end
    if (state.gameConfig or {}).randomSpawn then return if controller then "Random spawn is enabled. Selecting starting location for you..." else "Random spawn is enabled" end
    if controller and Simulation.tutorialMap(state) then return Simulation.TUTORIAL_SPAWN_HINT end -- the tutorial's mainland start
    return if controller then "Choose a starting location" else "Players are choosing starting locations"
end

function MatchController.resultSounds(state: any,deathShown: boolean,winHandled: boolean,spectator: boolean?): ({string},boolean,boolean)
    -- WinModal.tick performs the death guard before processing its Win update.
    local cues={}
    if spectator then return cues,deathShown,winHandled end -- PF020 G8: a spectator has no win or loss
    local spawned=state.players[1].spawnTile~=nil
    if not deathShown and spawned and state.counts[1]==0 and state.phase~="Choosing"then
        deathShown=true;table.insert(cues,"defeat")
    end
    if not winHandled and (state.phase=="Won"or state.phase=="Lost"or state.phase=="Cancelled")then
        winHandled=true
        if state.phase=="Won"then table.insert(cues,"victory")
        elseif state.phase=="Lost"and not deathShown and spawned then table.insert(cues,"defeat")end
    end
    return cues,deathShown,winHandled
end

local function point(position: Vector3): Vector2
    return Vector2.new(position.X, position.Y)
end

local function label(parent: Instance, name: string): TextLabel
    return parent:WaitForChild(name) :: TextLabel
end

local function button(parent: Instance, name: string): TextButton
    return parent:WaitForChild(name) :: TextButton
end

local function integer(value: number?): string
    return tostring(math.floor(value or 0))
end

-- Exact display thresholds from src/client/Utils.ts:307-360 (internal troops / 10).
local function displayNumber(value: number): string
    local n = math.max(0, value)
    if n >= 1e10 then return string.format("%.1fB", math.floor(n / 1e8) / 10) end
    if n >= 1e9 then return string.format("%.2fB", math.floor(n / 1e7) / 100) end
    if n >= 1e7 then return string.format("%.1fM", math.floor(n / 1e5) / 10) end
    if n >= 1e6 then return string.format("%.2fM", math.floor(n / 1e4) / 100) end
    if n >= 1e5 then return integer(math.floor(n / 1e3)) .. "K" end
    if n >= 1e4 then return string.format("%.1fK", math.floor(n / 100) / 10) end
    if n >= 1e3 then return string.format("%.2fK", math.floor(n / 10) / 100) end
    return integer(n)
end

local function displayTroops(value: number?): string
    return displayNumber((value or 0) / 10)
end

local PF019ScreenShake=require(script.Parent.PF019ScreenShake)
-- BEGIN VIEW TRANSFORM COMMITTER
-- TransformHandler records every clamped input immediately; the reference's
-- requestAnimationFrame consumes the latest transform once. Keep hit testing
-- synchronous while avoiding repeated native hierarchy invalidation per frame.
-- PF019 W7 S15 screen shake (falls back to none where this block runs on its own, e.g. tests).
local ScreenShake=PF019ScreenShake or {active=function(_: number): boolean return false end,offset=function(_: number): Vector2 return Vector2.zero end}
local function newTransformCommitter(world: any, viewport: any): any
    local pending=false
    local pendingOffset,pendingExtent,pendingScale=Vector2.zero,Vector2.zero,1
    return {
        request = function(_self: any, offset: Vector2, extent: Vector2, scale: number)
            pendingOffset,pendingExtent,pendingScale=offset,extent,scale
            pending=true
            Performance.count("ViewTransform.requests",1)
        end,
        commit = function(_self: any)
            if not pending then return end
            local started=Performance.start()
            debug.profilebegin("OpenFront.ViewTransform")
            -- PF019 W7 S15: a nuke's screen shake jitters the committed position only; keep
            -- committing every frame until it fades.
            local now=os.clock()
            pending=ScreenShake.active(now)
            local shaken=pendingOffset+ScreenShake.offset(now)
            local position=UDim2.fromOffset(shaken.X,shaken.Y)
            local size=UDim2.fromOffset(pendingExtent.X,pendingExtent.Y)
            if world.AnchorPoint~=Vector2.zero then world.AnchorPoint=Vector2.zero end
            if world.Position~=position then world.Position=position end
            if world.Size~=size then world.Size=size end
            if viewport:GetAttribute("Zoom")~=pendingScale then viewport:SetAttribute("Zoom",pendingScale) end
            if viewport:GetAttribute("TileSize")~=pendingScale then viewport:SetAttribute("TileSize",pendingScale) end
            debug.profileend()
            Performance.finish("client.viewTransform",started)
            Performance.count("ViewTransform.commits",1)
        end,
    }
end
-- END VIEW TRANSFORM COMMITTER

-- PF020 (MM): each RenderStepped draw stage runs under its own guard. A stage that throws warns once
-- (with its traceback) and every other stage keeps drawing, so one renderer fault never freezes the
-- map. Methods are passed with their arguments (no per-frame closure).
MatchController.drawFailures={} :: {[string]: boolean}
function MatchController.drawStage(name: string, fn: (...any) -> ...any, ...: any): boolean
    debug.profilebegin(name)
    local ok,failure=xpcall(fn,debug.traceback,...)
    debug.profileend()
    if not ok and not MatchController.drawFailures[name] then
        MatchController.drawFailures[name]=true
        warn("[PixelFront] "..name.." failed (shown once; the other draws continue): "..tostring(failure))
    end
    return ok
end
-- PF020 (MM, perf audit): the HUD-only packet stages (leaderboard, diplomacy, quick chat, the
-- preference view, the HUD text and rows) run one frame after their packet, in the same order and
-- each under drawStage's guard. The packet frame (the late-game p95 hitch) then carries only the
-- map. A newer packet first runs any HUD work still pending, so every packet's HUD is applied.
MatchController.frameSerial=0
MatchController.deferred={} :: {any}
function MatchController.defer(name: string, fn: (...any) -> ...any, ...: any)
    table.insert(MatchController.deferred,{name=name,fn=fn,args=table.pack(...),frame=MatchController.frameSerial})
end
function MatchController.runDeferred(now: boolean?)
    local jobs=MatchController.deferred
    if #jobs==0 or (not now and MatchController.frameSerial<jobs[1].frame+2) then return end
    MatchController.deferred={}
    for _,job in jobs do MatchController.drawStage(job.name,job.fn,table.unpack(job.args,1,job.args.n)) end
end

-- BEGIN CLIENT BORDER CACHE (pure helper; exercised by the native fixture test)
local function updateLocalBorders(state: any, previous: Collections.OrderedSet?): Collections.OrderedSet
    local changed = state.changedOwnerIds
    local full = previous == nil or changed == nil
    local borders = if full then Collections.set() else previous :: Collections.OrderedSet
    local function update(id: number)
        local isBorder = false
        if state.owners[id] == 1 then
            for _, neighbor in MapData.neighbors(id, state.map.width, state.map.height) do
                if state.owners[neighbor] ~= 1 then isBorder = true break end
            end
        end
        if isBorder then Collections.add(borders, id) else Collections.remove(borders, id) end
    end
    if full then
        for id, owner in state.owners do if owner == 1 then update(id) end end
    else
        local affected: {[number]: boolean} = {}
        local owners, width, count = state.owners, state.map.width, state.map.width * state.map.height
        for _, id in changed do
            -- Distant AI conquest cannot change the human's border. Inspect its
            -- four neighbors without allocating a table for every global delta.
            if owners[id] == 1 then affected[id] = true else Collections.remove(borders, id) end
            if id > width and owners[id - width] == 1 then affected[id - width] = true end
            if id <= count - width and owners[id + width] == 1 then affected[id + width] = true end
            local x = (id - 1) % width
            if x > 0 and owners[id - 1] == 1 then affected[id - 1] = true end
            if x < width - 1 and owners[id + 1] == 1 then affected[id + 1] = true end
        end
        for id in affected do update(id) end
        Collections.compact(borders)
    end
    return borders
end
-- END CLIENT BORDER CACHE

function MatchController.start()
    -- PF020 (MM): the authored HUD node refs live in one table, so start keeps local-register headroom
    -- (Luau allows 200 live locals per function; start was at the limit).
    local ui: any = {}
    if started then return end
    started = true
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    local gui = playerGui:WaitForChild("OpenFront") :: ScreenGui
    if not MatchController.validateAuthoredUI(gui) then return end
    local background = gui:WaitForChild("Background")
    local homeUI = background:WaitForChild("Home") :: Frame
    local publicLobby: any=nil
    local gameUI = background:WaitForChild("Game") :: Frame
    local interface=RevampInterface.new(gui)
    local gamepadInput: any=nil
    gui.Destroying:Connect(function() interface:destroy();if gamepadInput then gamepadInput:destroy() end end)
    ui.header = gameUI:WaitForChild("Header")
    ui.controls = gameUI:WaitForChild("Controls") :: Frame
    ui.dev = gameUI:WaitForChild("Dev") :: Frame
    local result = gameUI:WaitForChild("Result") :: Frame
    ui.panel = MatchController.mapPanel(gui, gameUI, playerGui)
    MatchController.bindMapLayer(gameUI, ui.panel)
    local viewport = ui.panel:WaitForChild("Viewport") :: Frame
    local world = viewport:WaitForChild("World") :: Frame
    local transformCommitter = newTransformCommitter(world,viewport)
    ui.tiles = world:WaitForChild("Tiles") :: Frame
    local highlight = world:WaitForChild("Highlight") :: Frame
    ui.input = button(viewport, "Input")
    ui.attackTemplate = gameUI:WaitForChild("Templates"):WaitForChild("AttackRow") :: Frame
    ui.title = label(ui.header, "Title")
    ui.status = label(ui.header, "Status")
    ui.troops = label(ui.header, "Troops")
    ui.territory = label(ui.header, "Territory")
    ui.bot = label(ui.header, "Bot")
    ui.clock = MatchController.clockLabel(gameUI) or label(ui.header, "Clock")
    ui.hint = label(ui.controls, "Hint")
    ui.restart = button(ui.controls, "Restart")
    ui.resultContinue = button(result, "Continue")
    ui.devRestart = button(ui.dev, "Restart")
    ui.pause = button(ui.dev, "Pause")
    ui.hostPause = button(gameUI, "Pause")
    ui.speed = button(ui.dev, "Speed")
    ui.slider = ui.controls:WaitForChild("AttackSlider") :: Frame
    ui.sliderTrack = ui.slider:WaitForChild("Track") :: Frame
    ui.sliderFill = ui.sliderTrack:WaitForChild("Fill") :: Frame
    ui.sliderThumb = ui.sliderTrack:WaitForChild("Thumb") :: Frame
    ui.sliderInput = button(ui.slider, "Input")
    ui.ratioValue = label(ui.controls, "RatioValue")
    ui.troopBar = ui.controls:WaitForChild("TroopBar") :: Frame
    ui.reserveFill = ui.troopBar:WaitForChild("Reserve") :: Frame
    ui.attackFill = ui.troopBar:WaitForChild("Attacking") :: Frame
    ui.barText = label(ui.troopBar, "Text")
    ui.mobileReserve = label(ui.troopBar, "MobileReserve")
    ui.mobileCap = label(ui.troopBar, "MobileCap")
    ui.mobileRate = label(ui.troopBar, "MobileRate")
    ui.troopRate = label(ui.controls, "TroopRate")
    ui.attacksUI = gameUI:WaitForChild("Attacks") :: Frame
    ui.attacksList = ui.attacksUI:WaitForChild("List") :: ScrollingFrame
    local radial = gameUI:WaitForChild("Radial") :: Frame
    ui.radialAttack = button(radial, "Attack")
    ui.noticeUI = gameUI:WaitForChild("Notice") :: Frame
    ui.noticeText = label(ui.noticeUI, "Message")
    ui.noticeBorder = ui.noticeUI:WaitForChild("Border") :: UIStroke
    ui.mapError = gameUI:WaitForChild("MapError") :: Frame
    ui.headsUp = gameUI:WaitForChild("HeadsUp") :: Frame
    ui.headsUpText = label(ui.headsUp, "Message")
    do
        local copyright = label(gameUI, "Copyright")
        -- Retain the authored compatibility node without a player-facing credit.
        copyright.Text="";copyright.Visible=false;copyright.Active=false;copyright.Selectable=false
    end
    local remotes = Remotes.client()
    local preferences=UserSettings.new(nil,true) -- PF043 H: sound on by default (the web autoplay rule doesn't apply on Roblox)
    interface:setPreferences(preferences)
    local audio=AudioController.new(preferences)
    PacketFeed.bind({audio=audio,preferences=preferences}) -- PF021 B: the tutorial's cues and motion setting
    local deathSoundShown,winSoundHandled=false,false
    gui.Destroying:Connect(function()audio:dispose()end)
    local lobby: any=nil
    local settingsMenu: any=nil
    local cosmeticShop: any=nil
    local atlasMenu: any=nil
    local homeReady=false
    local latestMatchId=0
    local goHome: (() -> ())?=nil
    local preferencesLoaded=false
    local replacingPreferences=false
    local preferencePatch={}
    local applyGraphics: (() -> ())?=nil
    local resolvedGraphics=GraphicsSettings.fromPreferences(preferences)
    local effects=RenderEffects.new()
    local effectTick: number?=nil
    local renderDebug: any=nil
    local coordinateGrid=false
    local alternateView=false
    local heldKeys: {[string]: boolean}={}
    local preferenceView: any=nil
    local joinedAttempt: number?=nil
    local countedMatches: {[number]: boolean}={}
    local pendingGamesPlayed=0
    local snapshot: any = nil
    -- PF020 v13: the Ready says which packet this client last decoded (gui attribute PFWireSeq: start() is at the
    -- 200-local limit), so the server folds it into a full already in flight
    local snapshotRecovery=SnapshotRecovery.new(function()remotes.Command:FireServer({kind="Ready",haveSeq=gui:GetAttribute("PFWireSeq"),terrain=gui:GetAttribute("PFWireTerrain")})end,Config.Network.ReadyCooldown,os.clock,
        function(matchId,revision,reason)
            gui:SetAttribute("PFSnapshotLastRejectedMatchId",matchId)
            gui:SetAttribute("PFSnapshotLastRejectedRevision",revision)
            gui:SetAttribute("PFSnapshotLastRejectedReason",reason)
        end)
    gui.Destroying:Connect(function()snapshotRecovery:destroy()end)
    -- PF020: a match view never freezes silently (MatchStallWatchdog): stalls are logged with
    -- their reason and resynced; packet errors are caught per packet.
    local stall=require(script.Parent.MatchStallWatchdog).new({now=os.clock,log=warn,
        resync=function(why)gui:SetAttribute("PFMatchStall",why);snapshotRecovery:requestReady()end})
    local cities: any = nil
    local naval: any = nil
    local warships: any = nil
    local industry: any = nil
    local weapons: any = nil
    local stock: any=nil
    local diplomacy: any = nil
    local quickChat: any = nil
    local teamHUD: any = nil
    local variantHUD: any = nil
    stall.leave=function() BattleHudShell.confirmLeave(variantHUD) end -- PF020: the watchdog's Leave offer
    local showNotice: any = nil
    local weaponMessageCursor: number? = nil
    local warshipBox: InputObject? = nil
    local renderer = MapRenderer.new(ui.tiles)
    PacketFeed.context.ownerColor = function(owner: number) return renderer.colors[owner] end -- PF027: the tutorial's target colour
    local rendererReady = false
    local initialFitPending = false
    local mapGeneration = 0
    local attackRows: {[number]: Frame} = {}
    local mapWidth, mapHeight = 0, 0
    local tileSize = 1
    local offset = Vector2.zero
    local lastViewport = Vector2.zero
    local ratio = Config.Combat.DefaultRatio
    local selected: number? = nil
    local hoveredOwner = 0
    local notice, noticeUntil = "", 0
    local gesture: any = nil
    local pinching = false
    local lastPinchDistance = 0
    local mousePosition: Vector2? = nil
    local activeTouches: {[InputObject]: boolean} = {}
    local sliderGesture: InputObject? = nil
    local priorTroopRate: number? = nil
    local radialTarget: number? = nil
    local dismissedOutcome: string? = nil
    local cameraTarget: Vector2? = nil
    local cameraTargetScale: number? = nil
    local hasGoneToPlayer = false
    local keyboardElapsed, cameraElapsed = 0, 0
    local lastCameraCall: number? = nil
    local function setCameraTarget(target: Vector2?, scale: number?)
        cameraTarget, cameraTargetScale = target, scale
        cameraElapsed, lastCameraCall = 0, nil
    end
    local focused = true
    local mobileHUD = false
    local localBorders: Collections.OrderedSet? = nil
    local eligibilityCache: {[number]: boolean} = {}
    local eligibilityPhase: string? = nil
    local names = PlayerNames.new(world:WaitForChild("PlayerNames") :: Frame,
        gameUI.Templates:WaitForChild("PlayerNamePlate") :: Frame, displayTroops,
        gameUI.Templates:FindFirstChild("DiplomacyStatusIcon") :: ImageLabel?)
    names:setBadges(NameplateStyle) -- PF020: the VIP badge and the Animated Nameplate styles
    ui.spawnView = SpawnPhaseView.new(gameUI, world, {colors=function() return renderer.colors end,palettes=function() return renderer.palettes end,
        vote=function() remotes.Command:FireServer({kind="VoteBegin"}) end}) -- PF030 (no-op without its nodes); PF044 vote to begin
    local function presentationFailed(failure: any)
        rendererReady=false
        renderer:destroy()
        names:reset()
        local buildingLayer=world:FindFirstChild("Buildings")
        for _,child in if buildingLayer then buildingLayer:GetChildren() else {} do
            if child:GetAttribute("RuntimeCity")==true then child:Destroy() end
        end
        ui.controls.Visible=false;ui.dev.Visible=false;result.Visible=false;radial.Visible=false
        ui.headsUp.Visible=false;ui.noticeUI.Visible=false;MatchController.leaderboardFrame(gameUI).Visible=false
        local retiredCatalog=gameUI:FindFirstChild("BuildMenu");if retiredCatalog then retiredCatalog.Visible=false end
        gameUI.CityTooltip.Visible=false
        if diplomacy then diplomacy:reset() end
        if quickChat then quickChat:reset() end
        if teamHUD then teamHUD:reset() end
        if variantHUD then variantHUD:reset() end
        gui:SetAttribute("OpenFrontMatchReady",false)
        gui:SetAttribute("OpenFrontMapError",tostring(failure))
        label(ui.mapError,"Message").Text=if RunService:IsStudio() then
            "Game images could not be loaded. Enable Allow Mesh / Image APIs in this experience's Security settings, then restart Play. If it is already enabled, check Studio Output."
            else "Game images could not be loaded in this experience. Please rejoin after its image rendering settings are updated."
        gameUI.Visible=true;ui.mapError.Visible=true
        warn("[OpenFront] Presentation images could not initialize: "..tostring(failure))
    end
    local leaderboardOK,leaderboard = MatchController.initializePresentation(function()
        return Leaderboard.new(MatchController.leaderboardFrame(gameUI),
        gameUI.Templates:WaitForChild("LeaderboardRow") :: TextButton, displayTroops, function(owner: number)
            if not snapshot then return end
            initialFitPending = false
            local location = NameLayout.place(snapshot.state, owner, renderer.owned[owner])
            setCameraTarget(if location then Vector2.new(location.x, location.y) else nil)
        end, displayNumber)
    end,presentationFailed)
    if not leaderboardOK then return end
    gui.Destroying:Connect(function()leaderboard:destroy()end)
    -- PF012 C: leaderboard nation dots use the map's real owner colors.
    leaderboard:setOwnerColor(function(owner: number) return renderer.colors[owner] end)
    leaderboard:setVip(function(userId: number) return NameplateStyle.vipUser(userId) end) -- PF020 V3

    local function isController(): boolean
        return snapshot ~= nil and snapshot.controllerUserId == player.UserId
    end

    local function canAttackAt(id: number): boolean
        if not snapshot then return false end
        local cached = eligibilityCache[id]
        if cached ~= nil then return cached end
        local eligible = Simulation.canAttack(snapshot.state, 1, id)
        eligibilityCache[id] = eligible
        return eligible
    end

    local function canPlay(): boolean
        return gameUI.Visible and rendererReady and snapshot ~= nil and snapshot.state.phase ~= "Choosing" and snapshot.state.counts[1] > 0
    end

    local function inside(position: Vector2): boolean
        local relative = position - viewport.AbsolutePosition
        local size = viewport.AbsoluteSize
        return rendererReady and viewport.Visible and gameUI.Visible and relative.X >= 0 and relative.Y >= 0
            and relative.X < size.X and relative.Y < size.Y
    end

    local function overResult(position: Vector2): boolean
        local relative = position - result.AbsolutePosition
        return result.Visible and relative.X >= 0 and relative.Y >= 0
            and relative.X < result.AbsoluteSize.X and relative.Y < result.AbsoluteSize.Y
    end

    local function isMapPointer(position: Vector2): boolean
        if atlasMenu and atlasMenu:isBlocking()then return false end
        if renderDebug and renderDebug:contains(position)then return false end
        if (lobby and lobby:isBlocking())or (settingsMenu and settingsMenu:isBlocking())then return false end
        if quickChat and quickChat:intercepts() then return false end
        if not inside(position) or GuiService.MenuIsOpen then return false end
        -- Reference wheel/contextmenu listeners belong to the canvas. Global
        -- Roblox events also fire over the HUD, including processed map input.
        -- The official GetGuiObjectsAtPosition sample uses InputObject.Position
        -- directly; apply no second inset conversion here.
        for _, object in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
            local ancestor: Instance?=object
            local pointerEventsNone=false
            while ancestor and ancestor~=playerGui do
                if ancestor:GetAttribute("PointerEventsCapture")==true then break end
                if ancestor:GetAttribute("PointerEventsNone")==true then pointerEventsNone=true;break end
                ancestor=ancestor.Parent
            end
            if pointerEventsNone then continue end
            if object == ui.input or object == world or object:IsDescendantOf(world) then return true end
            -- PF013: with the map on its own layer, the clear Game/Background
            -- containers sit above it without being its ancestors.
            if object == ui.header or object == gameUI or object == gameUI.Parent or ui.input:IsDescendantOf(object) then continue end
            -- HeadsUpMessage wraps both notices in pointer-events:none.
            if object == ui.headsUp or object:IsDescendantOf(ui.headsUp)
                or object == ui.noticeUI or object:IsDescendantOf(ui.noticeUI) then continue end
            return false
        end
        return false
    end

    local function setButtonEnabled(control: TextButton, enabled: boolean)
        control.Active = enabled
        control.Selectable = enabled
        control.AutoButtonColor = enabled
        control.TextTransparency = if enabled then 0 else 0.5
    end

    local function send(kind: string, fields: any?)
        if snapshot and snapshot.online==true and (kind=="Pause"or kind=="GameSpeed"or kind=="Debug"or kind=="Restart")then return false end
        if not snapshot or not isController() or not rendererReady then return false end
        -- PF043 (Ashton: "a 1s debounce so theres no accidental spam"): a repeat troop send inside 1 s fires nothing; the
        -- servers drop it too (SendDebounce). The click still selects / closes the radial, so it never feels dead.
        local debounce = require(Shared:WaitForChild("SendDebounce"))
        -- PF045 v2 (Ashton: the held tick sounded "like trying to open a locked menu"): a dropped repeat is silent; every
        -- accepted troop send plays the march on the click (AudioCues layers a counter / big push on it)
        if debounce.blocked(ui, 1, kind, os.clock()) then return false end
        debounce.stamp(ui, 1, kind, os.clock())
        local command = fields or {}
        command.kind = kind
        command.matchId = snapshot.matchId
        remotes.Command:FireServer(command)
        -- PF045 v3 "instant on input, one input = one hit, size follows magnitude": the confirm plays on the click, sized
        -- by the troop share sent and panned by the target (a refusal comes later from the server)
        local CLICK = {Attack = "g_send", Retaliate = "g_counter", Boat = "n_boat", Build = "b_place", Upgrade = "b_upgrade",
            Delete = "b_delete", Cancel = "g_retreat", BoatRetreat = "g_retreat"}
        local key = CLICK[kind]
        -- PF045 v3.2: a send into wilderness / a tribe / a nation is expansion: a small bright blip (the land's pops follow
        -- in AudioCues); the sized war hit is for attacking a real player
        if kind == "Attack" then
            local s = snapshot.state
            local owner = s and s.owners and s.owners[command.targetId]
            local p = type(owner) == "number" and owner > 0 and s.players and s.players[owner]
            if not p or p.playerType ~= "Human" then key = "g_expandclick" end
        end
        if key then
            local ratio = tonumber(command.ratio) or 0
            local size = if kind == "Boat" then (if ratio >= .5 then 2 else 1) else (if ratio >= .6 then 3 elseif ratio >= .3 then 2 else 1)
            require(script.Parent.Sfx).play(key, nil, nil, nil, {size = size, tile = command.targetId, click = true})
        end
        return true
    end
    local function bindingDown(action: string): boolean
        local binding=preferences:keybinds(false)[action]
        -- Source held actions compare the raw configured value with DOM codes.
        return InputBindings.held(heldKeys,binding)
    end
    local function modalBlocked(): boolean
        local blocked=result.Visible or (atlasMenu and atlasMenu:isBlocking())or (cosmeticShop and cosmeticShop:isBlocking())or (variantHUD and variantHUD:isBlocking())or (renderDebug and renderDebug:isBlocking())or (lobby and lobby:isBlocking())or (settingsMenu and settingsMenu:isBlocking())or (M13.menu and M13.menu:isBlocking())or (quickChat and quickChat:intercepts())or false
        local sheetBlocked=(diplomacy and (diplomacy.panel.Visible or diplomacy.emojiMenu.Visible)) or false
        interface:setBlocked(blocked or sheetBlocked or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()~=nil or not gameUI.Visible or not focused)
        return blocked
    end
    local function attackInputAllowed(): boolean
        return focused and rendererReady and snapshot~=nil and HudControls.visible(gameUI)
            and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox() and not modalBlocked()
            and not (diplomacy and (diplomacy.panel.Visible or diplomacy.emojiMenu.Visible))
    end
    local function attackFocusAllowed(): boolean
        return attackInputAllowed() and HudControls.visible(ui.attacksList) and ui.attacksUI:GetAttribute("PFHudSuppressed")~=true
    end
    local function setAlternateView(value: boolean)
        alternateView=value
        renderer:setAltView(value)
        for _,view in {industry,weapons,naval,warships}do
            if view then
                if view.setAlternateView then view:setAlternateView(value)
                elseif view.setAltView then view:setAltView(value)end
            end
        end
        if cities and cities.buildings then cities.buildings:setAlternateView(value)end
        if preferenceView then preferenceView:setAlternateView(value)end
        if settingsMenu then settingsMenu:setAlternateView(value)end
        if stock then stock:setAltView(value)end
    end

    -- BEGIN VIEW TRANSFORM INPUT
    local function applyTransform()
        if mapWidth == 0 or mapHeight == 0 then return end
        local size = viewport.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return end
        local extent = Vector2.new(mapWidth * tileSize, mapHeight * tileSize)
        -- TransformHandler.clampOffsets: each map corner may reach screen center.
        offset = Vector2.new(
            math.clamp(offset.X, size.X / 2 - extent.X, size.X / 2),
            math.clamp(offset.Y, size.Y / 2 - extent.Y, size.Y / 2)
        )
        lastViewport = size
        transformCommitter:request(offset,extent,tileSize)
    end

    local function resetView(): boolean -- release QA: false when it could not fit (no map yet, or the viewport has no size)
        if mapWidth == 0 then return false end
        local size = viewport.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return false end
        -- GameRenderer.init: centerAll(0.9); the initial fit is not scale-clamped.
        tileSize = math.min(size.X / mapWidth, size.Y / mapHeight) * 0.9
        offset = (size - Vector2.new(mapWidth, mapHeight) * tileSize) / 2
        applyTransform()
        return true
    end

    local function zoomAt(factor: number, screenPosition: Vector2)
        if mapWidth == 0 or tileSize <= 0 then return end
        initialFitPending = false
        setCameraTarget(nil)
        local anchor = screenPosition - viewport.AbsolutePosition
        local mapPoint = (anchor - offset) / tileSize
        -- PF019 W7 S12: zoom speed scales every zoom input (wheel, pinch, keys, triggers).
        tileSize = math.clamp(tileSize * factor ^ preferences:get("zoomSpeed"), MIN_SCALE, MAX_SCALE)
        offset = anchor - mapPoint * tileSize
        applyTransform()
    end

    local function zoomDelta(delta: number, position: Vector2)
        local factor = 1 + delta / ZOOM_DELTA_DIVISOR
        if factor > 0 then zoomAt(1 / factor, position) end
    end

    local function targetAt(screenPosition: Vector2): number?
        if not snapshot or not inside(screenPosition) then return nil end
        local mapPosition = (screenPosition - viewport.AbsolutePosition - offset) / tileSize
        local x, y = math.floor(mapPosition.X), math.floor(mapPosition.Y)
        if x < 0 or y < 0 or x >= mapWidth or y >= mapHeight then return nil end
        local id = y * mapWidth + x + 1
        return id
    end
    -- END VIEW TRANSFORM INPUT

    local function showHighlight(id: number?)
        if not rendererReady then return end
        -- HoverHighlightController highlights the owner, never a destination square.
        -- Its WebGL pass consumes the latest uniform on the next rendered frame;
        -- pointer events change logical hover without repainting between frames.
        local owner = if naval then naval:hoverOwner(id)elseif id and snapshot then snapshot.state.owners[id]else 0
        owner = if owner and owner > 0 then owner else 0
        hoveredOwner = owner
        if diplomacy then diplomacy:hoverAt(id) end
    end

    local function renderAttacks(state: any)
        local present: {[number]: boolean} = {}
        local committed = 0
        local rowOrder = 0
        local outgoingShipsAdded = false
        local function addOutgoingShips()
            if outgoingShipsAdded or not naval then return end
            outgoingShipsAdded = true
            local count = naval:renderRows(ui.attacksList, rowOrder, false)
            -- ControlPanel counts outgoing land attacks only; troops aboard
            -- transports are shown in their rows, not the attack-fill segment.
            rowOrder += count
        end
        local visibleAttacks = {}
        -- AttacksDisplay.ts: enemy outgoing, wilderness outgoing, then incoming.
        -- Tribe attacks deliberately do not create incoming warning rows.
        for group = 1, 3 do
            for _, attack in state.attacks do
                local incoming = attack.targetOwner == 1 and attack.owner ~= 1
                local attacker = state.players and state.players[attack.owner]
                if (group == 1 and attack.owner == 1 and attack.targetOwner ~= 0)
                    or (group == 2 and attack.owner == 1 and attack.targetOwner == 0)
                    or (group == 3 and incoming and attacker and attacker.playerType ~= "Bot") then
                    table.insert(visibleAttacks, attack)
                end
            end
        end
        for _, attack in visibleAttacks do
            if state.counts[1] <= 0 then continue end
            local incoming = attack.owner ~= 1
            if incoming then addOutgoingShips() end
            present[attack.id] = true
            if not incoming then committed += attack.budget end
            rowOrder += 1
            local row = attackRows[attack.id]
            if not row then
                row = ui.attackTemplate:Clone()
                row.Name = "Attack" .. tostring(attack.id)
                row.Visible = true
                row.LayoutOrder = attack.id
                row:SetAttribute("AttackId", attack.id)
                local attackId = attack.id
                button(row, "Cancel").Activated:Connect(HudControls.guardedAction(button(row,"Cancel"),function()
                    return attackFocusAllowed() and canPlay() and isController()
                end,function()
                    if row:GetAttribute("Incoming") then send("Retaliate", { attackId = attackId, ratio = ratio })
                    else send("Cancel", { attackId = attackId }) end
                end))
                button(row, "Focus").Activated:Connect(HudControls.guardedAction(button(row,"Focus"),attackFocusAllowed,function()
                    for _, current in snapshot.state.attacks do
                        if current.id ~= attackId then continue end
                        initialFitPending = false
                        local location = NameLayout.place(snapshot.state, current.owner, renderer.owned[current.owner])
                        setCameraTarget(if location then Vector2.new(location.x, location.y) else nil)
                        break
                    end
                end))
                row.Parent = ui.attacksList
                attackRows[attack.id] = row
            end
            -- PF018: incoming threats sort first (top of the list, visible first when it
            -- scrolls); outgoing rows follow in launch order, newest nearest the corner.
            row.LayoutOrder = if incoming then rowOrder - 100000 else rowOrder
            local target = if incoming then attack.owner else attack.targetOwner
            -- PF018: row parts may sit inside the authored Content strip (any depth).
            local part = function(name: string): any return row:FindFirstChild(name, true) end
            part("Target").Text = if target == 0 then "Wilderness" else ((state.names and state.names[target]) or "")
            row:SetAttribute("OwnerColor", if target ~= 0 and renderer and renderer.colors then renderer.colors[target] else nil) -- rows v2: the flag chip
            part("Troops").Text = (if incoming then "↓ " else "↑ ") .. displayTroops(attack.budget)
            local retreating = attack.retreating == true
            part("Retreating").Visible = retreating
            button(row, "Cancel").Visible = not retreating and isController()
            button(row, "Cancel").Text = if incoming then "⚔" else "×"
            button(row, "Focus").Visible = attack.targetOwner ~= 0
            row:SetAttribute("Retreating", retreating)
            row:SetAttribute("Incoming", incoming)
            -- Colours, glyphs and the action plate follow these attributes (HudControls.layoutAttackRow).
        end
        for id, row in attackRows do
            if not present[id] then row:Destroy(); attackRows[id] = nil end
        end
        addOutgoingShips()
        if naval then local count = naval:renderRows(ui.attacksList, rowOrder, true); rowOrder += count end
        ui.attacksUI.Visible = rowOrder > 0
        -- PF013: the list's authored UIGridLayout/AutomaticSize place the rows;
        -- only each row's content state (target vs retreat text, labels) is set.
        for _,row in ui.attacksList:GetChildren() do
            if row:IsA("Frame") and row.Visible then HudControls.layoutAttackRow(row) end
        end
        HudControls.incomingTag(ui.attacksList, ui.attackTemplate.Parent:FindFirstChild("PFIncomingTag")) -- rows v2
        interface:layoutHover()
        return committed
    end

    local function renderRatio()
        local sliderFraction = (ratio * 100 - 1) / 99
        ui.sliderFill.Size = UDim2.fromScale(sliderFraction, 1)
        ui.sliderThumb.Position = UDim2.fromScale(sliderFraction, 0.5)
        ui.ratioValue.Text = "Send "..integer(math.floor(ratio * 100 + 0.5)) .. "%"
        gameUI:SetAttribute("AttackRatio", ratio)
    end

    local lastHUDSize: Vector2?=nil
    local function layoutHUD()
        if lastHUDSize~=gameUI.AbsoluteSize then
            lastHUDSize=gameUI.AbsoluteSize
            if teamHUD then teamHUD:layout(lastHUDSize) end
        end
        local measured=interface:layoutHUD(cities)
        mobileHUD=measured.phone
        ui.controls:SetAttribute("MobileLayout", mobileHUD)
    end

    local function renderText()
        if not snapshot then return end
        local state = snapshot.state
        local playing = canPlay()
        local controller = isController()
        local hudStarted=Performance.start()
        local committed = renderAttacks(state)
        Performance.finish("client.hud.attacks",hudStarted)
        local cap = state.caps[1]
        local rate = state.troopRates[1]
        hudStarted=Performance.start()
        local variant = if variantHUD then variantHUD:update(state, 1) else nil
        Performance.finish("client.hud.variant",hudStarted)
        hudStarted=Performance.start()
        if teamHUD then teamHUD:update(state) end
        Performance.finish("client.hud.team",hudStarted)
        if variant and variant.warning then showNotice(variant.warning.text, variant.warning.color, variant.warning.duration) end
        hudStarted=Performance.start()
        -- HeadsUpMessage.ts:getMessage/render and resources/lang/en.json.
        -- PF030: during Choosing the spawn banner + ring take the heads-up's place (when authored)
        local spawnShown = ui.spawnView:update(state,{ready=rendererReady,paused=snapshot.paused==true,controller=controller,choosing=snapshot.choosing or state.choosing,waiting=snapshot.waiting})
        ui.headsUp.Visible = rendererReady and not spawnShown and (snapshot.paused or state.phase == "Choosing" or (variant and variant.overtimeNotice))
        -- PF013: the toast's authored AutomaticSize fits its text.
        ui.headsUpText.Text = MatchController.headsUpMessage(state,snapshot.paused==true,controller,variant and variant.overtimeNotice)
        ui.title.Text = ""
        ui.status.Text = ""
        ui.troops.Text = "Troops  " .. displayTroops(state.troops[1]) .. " / " .. displayTroops(cap)
        ui.territory.Text = Leaderboard.territoryText(state,state.counts[1] or 0)
        ui.bot.Text = ""
        if variant then ui.clock.Text = variant.timerText end
        ui.controls.Visible = controller and playing and state.counts[1] > 0
        -- PF020 G8 Lobby Host+ spectator seat: the docks stay hidden (not the controller); a small chip says so.
        local spectatingChip=gameUI:FindFirstChild("PFSpectating")
        if spectatingChip then spectatingChip.Visible=snapshot.spectator==true and result.Visible~=true end
        -- PF-041 (PF - 1): the paused state and the spectating bar (authored Game.PFPaused / PFSpectateBar; PF041MatchStates)
        if ui.states==nil then
            ui.states=require(script.Parent.PF041MatchStates).new(gameUI,{resume=function() send("Pause",{paused=false}) end,
                leave=function() if ui.requestReturn then ui.requestReturn() end end,
                focusOwner=function(owner) if not snapshot then return end;initialFitPending=false;local location=NameLayout.place(snapshot.state,owner,renderer.owned[owner]);setCameraTarget(if location then Vector2.new(location.x,location.y) else nil) end,
                name=function(owner) return if snapshot then ClientNames.resolve(snapshot.state,owner) else "" end,color=function(owner) return renderer.colors[owner] end})
        end
        ui.states:update(snapshot,state,result.Visible,rendererReady)
        Performance.finish("client.hud.text",hudStarted)
        hudStarted=Performance.start()
        layoutHUD()
        Performance.finish("client.hud.layout",hudStarted)
        hudStarted=Performance.start()
        setButtonEnabled(ui.sliderInput, controller and playing)
        renderRatio()
        ui.barText.Text = displayTroops(state.troops[1]) .. " / " .. displayTroops(cap)
        ui.troopRate.Text = "+" .. displayTroops(rate) .. "/s"
        ui.troopRate.TextColor3 = if priorTroopRate == nil or rate >= priorTroopRate
            then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(251, 146, 60)
        priorTroopRate = rate
        ui.mobileReserve.Text = displayTroops(state.troops[1])
        ui.mobileCap.Text = displayTroops(cap)
        ui.mobileRate.Text = ui.troopRate.Text
        ui.mobileRate.TextColor3 = ui.troopRate.TextColor3
        local reserve = math.clamp(state.troops[1] / math.max(cap, 1), 0, 1)
        local attacking = math.clamp(committed / math.max(cap, 1), 0, 1 - reserve)
        interface:setMeter(ui.reserveFill,ui.attackFill,reserve,attacking)
        ui.restart.Visible = false
        ui.dev.Visible = false -- Development actions stay in the explicit settings menu.
        ui.pause.Text = if snapshot.paused then "Resume" else "Pause"
        if variantHUD then variantHUD:setPaused(snapshot.paused==true) end
        if variantHUD then variantHUD:setSpeed(if snapshot.maxSpeed then 0 else 1/(snapshot.speed or 1)) end
        ui.hostPause.Visible = false -- PF013: Pause left the HUD; the pause shortcut stays.
        ui.speed.Text = if snapshot.maxSpeed then "MAX speed"else tostring(snapshot.speed or 1).."× speed"
        local outcome,resultTitle=MatchController.resultPresentation(state,snapshot.spectator==true)
        -- PF021 B: the tutorial's reward card comes first; the match-end screen waits for it
        result.Visible = outcome ~= nil and outcome ~= dismissedOutcome and gameUI:GetAttribute("PFTutorialRewardOpen")~=true
        label(result, "Title").Text=resultTitle
        label(result, "Detail").Text = ""
        ui.resultContinue.Text = if state.counts[1] > 0 then "KEEP PLAYING" else "SPECTATE"
        result:SetAttribute("Outcome", outcome)
        if os.clock() < noticeUntil then
            ui.hint.Text = notice
        elseif not controller then
            ui.hint.Text = "Spectating this match. Drag to pan; scroll or use + / − to zoom."
        elseif state.phase == "Choosing" then
            ui.hint.Text = "Choose a land tile to start. Drag to pan; scroll or use + / − to zoom."
        elseif playing then
            ui.hint.Text = "Click a target to attack · " .. integer(ratio * 100) .. "%"
        else
            ui.hint.Text = ""
        end
        gameUI:SetAttribute("Phase", state.phase)
        gameUI:SetAttribute("MatchId", snapshot.matchId)
        gameUI:SetAttribute("Revision", snapshot.revision)
        gameUI:SetAttribute("ControllerUserId", snapshot.controllerUserId)
        gameUI:SetAttribute("SelectedTarget", selected)
        gameUI:SetAttribute("CommittedTroops", committed)
        interface:update(state,displayNumber)
        modalBlocked()
        cities:refreshBlueprints()
        Performance.finish("client.hud.text",hudStarted)
        hudStarted=Performance.start()
        interface:layout()
        Performance.finish("client.hud.layout",hudStarted)
        -- (the radial centre's enabled look is CityController.refreshDiplomacy's alone; painting it here as well made it
        -- flicker between the two, tester round 2026-10-13)
    end

    local function sizeNotice()
        -- PF013: HeadsUpMessage's fit-content toast (24/16px padding, at least
        -- 200px, wrapping at its cap) is authored AutomaticSize; nothing to size.
    end

    showNotice = function(message: string, color: any, duration: number?)
        -- PF018 (Ashton: notices belong "in a list ... snug in the bottom left corner"):
        -- while the battle stack is live, toasts join it with a severity tone; the old
        -- floating banner remains only for the pre-spawn/dead fallback.
        local stack = diplomacy and diplomacy.stack
        if message ~= "" and stack and stack.enabled and diplomacy.state and (diplomacy.state.counts[1] or 0) > 0 then
            diplomacy:pushNotice(message, if color == "green" then "POSITIVE" elseif typeof(color) == "Color3" then "DANGER" else "WARNING")
            return
        end
        notice = message
        -- Utils.showToast default3500ms; latest HeadsUpMessage replaces the old
        -- message and restarts its timeout. Packet wording remains server-owned.
        local lifetime = duration or 3.5
        noticeUntil = os.clock() + lifetime
        local expires = noticeUntil
        ui.noticeText.Text = message
        local tint = if color == "green" then Color3.fromRGB(34, 197, 94) else Color3.fromRGB(239, 68, 68)
        ui.noticeUI.BackgroundColor3 = tint
        ui.noticeBorder.Color = tint
        sizeNotice()
        ui.noticeUI.Visible = message ~= ""
        task.delay(lifetime, function()
            if noticeUntil == expires then ui.noticeUI.Visible = false end
        end)
    end

    local function selectAt(position: Vector2, groundOnly: boolean?)
        if not snapshot or not isController() or not rendererReady then return end
        local id = targetAt(position)
        if not id then return end
        selected=id -- Owned land can be selected for the explicit Build action.
        local state = snapshot.state
        if state.phase == "Choosing" then
            -- ClientGameRunner:1216 uses isLand (terrain bit7), not isPassable.
            -- Water-centered spawn intents are never emitted by its UI.
            if bit32.band(buffer.readu8(state.map.terrain, id - 1), 128) == 0 then return end
            if state.owners[id] > 0 then return end
            if not Simulation.spawnAllowed(state, id) then return end -- the tutorial's mainland (the hint line says so)
            if not ui.spawnView:confirm(id) then return end -- PF030 touch: the first tap previews, the second starts
            audio:play("spawn")
            send("Spawn", { targetId = id })
        elseif canPlay() then
            if bindingDown("emojiMenuModifier")then diplomacy:openEmoji(snapshot.state.owners[id]);return end
            if cities:confirm(position) then return end
            if not groundOnly and warships:click(position,false) then return end
            if canAttackAt(id) then send("Attack", { targetId = id, ratio = ratio })
            elseif groundOnly or not naval:launch(id, true) then return end
        else
            return
        end
        selected = id
        renderText()
    end

    local function openRadial(position: Vector2)
        if cities.ghostActive then cities:clearGhost();return end
        if not snapshot or not isController() or overResult(position) then return end
        local id = targetAt(position)
        if not id then return end
        if not canPlay() then if snapshot.state.owners[id]>0 then diplomacy:show(id) end;return end
        radialTarget = id
        -- RadialMenu.ts: root menu radius95 plus10px margin; center button radius30. PF022: CityController
        -- fits it between the top row and the dock (scaled down on small screens, shifted at edges).
        cities:placeRadial(position - gameUI.AbsolutePosition)
        radial.Visible = true
        radial:SetAttribute("TargetId", id)
        cities:openRadial(id)
        renderText()
    end

    -- Mobile long-press (Ashton 2026-10-08): a ring fills under a still finger for LONG_PRESS seconds, then the radial
    -- opens there. The ring is the authored Game.PFPressRing (tools/atlas/author-press-ring.luau; code only places it
    -- at the finger and fills it); without it the long-press still works, just without the cue.
    ui.LONG_PRESS=.5
    ui.pressRingShow=function(position: Vector2)
        local ring=gameUI:FindFirstChild("PFPressRing");if not ring or not ring:IsA("GuiObject") then return end
        ring.Position=UDim2.fromOffset(position.X-gameUI.AbsolutePosition.X,position.Y-gameUI.AbsolutePosition.Y)
        ring.Visible=true
        local grow=ring:FindFirstChild("Grow",true) -- the Fill disc's UIScale (authored at full size)
        if grow and grow:IsA("UIScale") then
            if ui.pressTween then ui.pressTween:Cancel() end
            grow.Scale=0
            ui.pressTween=game:GetService("TweenService"):Create(grow,TweenInfo.new(ui.LONG_PRESS,Enum.EasingStyle.Linear),{Scale=1})
            ui.pressTween:Play()
        end
    end
    ui.pressRingHide=function()
        if ui.pressTween then ui.pressTween:Cancel();ui.pressTween=nil end
        local ring=gameUI:FindFirstChild("PFPressRing");if ring and ring:IsA("GuiObject") then ring.Visible=false end
    end
    ui.radialAttack.Activated:Connect(function()
        if cities:back() then return end
        local id = radialTarget
        if id and diplomacy and diplomacy:center(id) then radialTarget=nil;return end
        if id and snapshot and canAttackAt(id) then
            send("Attack", { targetId = id, ratio = ratio })
            radial.Visible = false
            radialTarget = nil
        end
    end)

    -- PF019 W0 (Ashton): on mobile one tap on an attackable target sends at the
    -- current ratio, with no radial confirm, and pops "−N troops" at the tap.
    -- Own land, allies, water and land you'd have to boat to still open the radial. A tap while the radial
    -- is open only dismisses it. (A do-block: this function has no registers to spare.)
    do
        local troopPop = TroopSendPop.new(gameUI)
        W0.clear = function() troopPop:clear() end
        W0.tapSend = function(position: Vector2): boolean
            if not snapshot or not isController() or overResult(position) then return false end
            local id = targetAt(position)
            if not id or not canAttackAt(id) then return false end
            -- Land you can only boat to (an island, a coast across water) opens the radial instead (Ashton): the
            -- land attack would never reach that piece, and the radial has Boat. Required here: no spare locals.
            local state = snapshot.state
            if not require(script.Parent.TapReach).byLand(state.owners, state.map.width, state.map.height, 1, id) then return false end
            if radial.Visible then radial.Visible = false; radialTarget = nil; return true end
            local troops, cap = state.troops[1] or 0, (state.caps and state.caps[1]) or 0
            local human = state.players[1] ~= nil and state.players[1].playerType == "Human" and cap < 1000000000
            selected = id
            -- PF043: a debounced repeat tap still selects, but pops no "-N troops" (nothing left)
            if send("Attack", { targetId = id, ratio = ratio }) then
                troopPop:show(position, TroopSendPop.estimate(troops, cap, ratio, Simulation.TroopReserveShare, human, Config.Combat.ReserveMaxOfTroops), displayTroops)
            end
            renderText()
            return true
        end
        if RunService:IsStudio() then
            -- Studio QA: injected input arrives as mouse, not touch, so captures call the touch hook here.
            local qa = Instance.new("BindableFunction")
            qa.Name = "PF019TapSendQA"
            qa.OnInvoke = function(x: number, y: number, hold: number?)
                if hold then TroopSendPop.LIFETIME = hold; TroopSendPop.FADE_AT = hold - 1 end
                return W0.tapSend(Vector2.new(x, y))
            end
            qa.Parent = gameUI
        end
    end

    local function rebuildMap(state: any)
        deathSoundShown,winSoundHandled=false,false
        hoveredOwner=0
        if stock then stock:reset()end
        names:reset()
        leaderboard:reset()
        cities:reset()
        if naval then naval:reset() end
        if warships then warships:reset() end
        if industry then industry:reset() end
        if weapons then weapons:reset() end
        if diplomacy then diplomacy:reset() end
        if quickChat then quickChat:reset() end
        if teamHUD then teamHUD:reset() end
        if variantHUD then variantHUD:reset() end
        weaponMessageCursor=nil
        warshipBox = nil
        mapGeneration += 1
        local generation = mapGeneration
        initialFitPending = true
        for _, row in attackRows do row:Destroy() end
        attackRows = {}
        mapWidth, mapHeight = state.map.width, state.map.height
        selected = nil
        gesture = nil
        pinching = false
        activeTouches = {}
        radial.Visible = false
        radialTarget = nil
        W0.clear()
        sliderGesture = nil
        priorTroopRate = nil
        dismissedOutcome = nil
        setCameraTarget(nil)
        hasGoneToPlayer = false
        showHighlight(nil)
        rendererReady = false
        gui:SetAttribute("OpenFrontMatchReady", false)
        world.BackgroundColor3 = Theme.MapBackground
        viewport.BackgroundColor3 = Theme.MapBackground
        local ok, failure = pcall(function()
            Navigation.forMap(state.map)
            renderer:setMap(state.map)
        end)
        rendererReady = ok
        ui.mapError.Visible = not ok
        if not ok then
            local detail = tostring(failure)
            warn("[OpenFront] Map renderer could not initialize: " .. detail)
            label(ui.mapError, "Message").Text = if snapshot and snapshot.isStudio then
                "The map could not be loaded. Enable Allow Mesh / Image APIs in this experience's Security settings, then restart Play. If it is already enabled, check Studio Output."
                else "The map could not be loaded in this experience. Please rejoin after its map rendering settings are updated."
            gui:SetAttribute("OpenFrontMapError", detail)
        else
            gui:SetAttribute("OpenFrontMapError", nil)
        end
        viewport:SetAttribute("MapWidth", mapWidth)
        viewport:SetAttribute("MapHeight", mapHeight)
        viewport:SetAttribute("LandCount", state.map.landCount)
        resetView()
        -- StarterGui cloning can initially report the template's authored size.
        -- Wait through one rendered UI layout before finalizing centerAll(.9).
        -- Any user navigation cancels this bootstrap-only correction.
        task.spawn(function()
            RunService.RenderStepped:Wait()
            RunService.RenderStepped:Wait()
            if generation ~= mapGeneration then return end
            -- release QA (PF - 4): while the viewport has no size resetView can't fit; keep trying each frame (up to 5 s) so a
            -- late layout never keeps the previous map's camera and SpawnView never goes out on an unframed view
            local fitted = not initialFitPending or not rendererReady or resetView()
            local waited = 0
            while not fitted and waited < 5 and generation == mapGeneration and initialFitPending do
                waited += RunService.RenderStepped:Wait()
                fitted = resetView()
            end
            if generation ~= mapGeneration then return end
            initialFitPending = false
            -- release QA (PF - 2): the camera now frames this match's map, so a Solo / tutorial pick's clock may start
            -- (MatchService.soloPresent waits for this per match instead of the first Ready ever)
            local view = snapshot
            if rendererReady and view and type(view.matchId) == "number" and view.state and view.state.phase == "Choosing" then
                remotes.Command:FireServer({kind = "SpawnView", matchId = view.matchId})
            end
        end)
    end

    -- Subscribe before Ready so the initial snapshot cannot race the listener.
    local citiesOK,cityController=MatchController.initializePresentation(function()
        return CityController.new(gameUI,world,{send=send,formatNumber=displayNumber,canPlay=canPlay,targetAt=targetAt,isMapPointer=isMapPointer,
            canSelectBlueprint=function()
                return focused and isController() and canPlay() and not modalBlocked() and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                    and (not diplomacy or (not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible))
            end,
            canShowNuclearActions=function()
                return isController() and canPlay() and not modalBlocked() and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                    and (not diplomacy or (not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible))
            end,
            canConfirmPreview=function(position)
                return focused and isController() and canPlay() and not modalBlocked() and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                    and not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible and isMapPointer(position)
            end,
            blueprintEquipped=function()
                gesture=nil;warshipBox=nil
                if warships then warships:cancelBox();warships:clearSelection() end
                if gamepadInput and gamepadInput.gamepad then mousePosition=viewport.AbsolutePosition+viewport.AbsoluteSize/2 end
            end,
            playSound=function(name)audio:play(name)end,
            canAttackAt=canAttackAt,
            diplomacyAction=function(action,tile)
                if not diplomacy or not snapshot then return end
                local owner=snapshot.state.owners[tile]
                if action=="Info" then diplomacy:show(tile) elseif action=="DonateGold" then diplomacy:openSend(owner,"gold",tile)
                elseif action=="AllianceRequest" then diplomacy:request(owner) else diplomacy:command(action,owner) end
            end,
            weaponsGhost=function(kind,tile,position,query,up) if weapons then weapons:setGhost(kind,tile,position,query,up) end end,
            canBoatAt=function(id) return naval and naval:canBoatAt(id) or false end,
            launchBoat=function(id) return naval and naval:launch(id,false) or false end})
    end,presentationFailed)
    if not citiesOK then return end
    cities=cityController
    cities:setPreferences(preferences)
    cities.callbacks.blockedNuke=function(tile)if preferenceView then preferenceView:blocked(tile)end end
    local navalOK,navalController=MatchController.initializePresentation(function()
        return NavalController.new(gameUI,world,{send=function(kind,fields)
                if not attackInputAllowed() then return end
                if kind=="BoatRetreat" then
                    local record=naval and fields and naval.rows[fields.unitId]
                    if not record or not HudControls.available(record.ui.Cancel) or not canPlay() then return end
                end
                send(kind,fields)
            end,canPlay=function()return canPlay() and attackInputAllowed() end,isController=isController,
            ratio=function() return ratio end,targetAt=targetAt,displayTroops=displayTroops,
            focusTile=function(id)
                if not attackFocusAllowed() then return end
                local available=false
                for _,record in naval.rows do
                    local ship=record.ship
                    if ship and (ship.lastTileId or ship.tileId)==id and HudControls.available(record.ui.Focus) then available=true;break end
                end
                if not available then return end
                initialFitPending=false
                setCameraTarget(Vector2.new((id-1)%mapWidth,math.floor((id-1)/mapWidth)))
                cameraElapsed=0
            end})
    end,presentationFailed)
    if not navalOK then return end
    naval=navalController
    naval:setPreferences(preferences)
    local warshipsOK,warshipController=MatchController.initializePresentation(function()
        return WarshipController.new(gameUI,world,{send=send,canPlay=canPlay,targetAt=targetAt,
            tileScreen=function(id)
                return viewport.AbsolutePosition + offset + Vector2.new((id-1)%mapWidth,math.floor((id-1)/mapWidth))*tileSize
            end,openRadial=openRadial})
    end,presentationFailed)
    if not warshipsOK then return end
    warships=warshipController
    local industryOK,industryController=MatchController.initializePresentation(function()
        return IndustryRenderer.new(world,gameUI.Templates)
    end,presentationFailed)
    if not industryOK then return end
    industry=industryController
    gui.Destroying:Connect(function() if industry then industry:destroy() end end)
    local weaponsOK,weaponsController=MatchController.initializePresentation(function() return WeaponsRenderer.new(world,gameUI.Templates,renderer) end,presentationFailed)
    if not weaponsOK then return end
    weapons=weaponsController
    gui.Destroying:Connect(function() if weapons then weapons:destroy() end end)
    local diplomacyOK,diplomacyInstance=MatchController.initializePresentation(function()
        return DiplomacyController.new(gameUI,{send=send,targetAt=targetAt,ratio=function() return ratio end,formatNumber=displayNumber,formatTroops=displayTroops,
            feedInputAllowed=attackInputAllowed,
            -- PF012 B: territory colour dot, cached attack eligibility and "can act now" for the hover card's click hint.
            ownerColor=function(owner) return renderer and renderer.colors and renderer.colors[owner] end,
            canAttackAt=canAttackAt,canAct=function() return canPlay() and isController() end,
            canHover=function() return gameUI.Visible and focused and not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox()
                and GuiService.SelectedObject==nil and not modalBlocked() and mousePosition~=nil and isMapPointer(mousePosition) end,
            directionUp=function() return cities.rocketDirectionUp end,
            flipTrajectory=function() cities.rocketDirectionUp=not cities.rocketDirectionUp;gameUI:SetAttribute("RocketDirectionUp",cities.rocketDirectionUp) end,
            openChat=function(owner) if quickChat then quickChat:open(owner) end end,
            playSound=function(name)audio:play(name)end,
            focusOwner=function(owner)
                if not snapshot then return end
                initialFitPending=false;local location=NameLayout.place(snapshot.state,owner,renderer.owned[owner]);setCameraTarget(if location then Vector2.new(location.x,location.y) else nil)
            end})
    end,presentationFailed)
    if not diplomacyOK then return end;diplomacy=diplomacyInstance
    gui.Destroying:Connect(function() if diplomacy then diplomacy:destroy() end end)
    quickChat=QuickChatController.new(gameUI,{send=send})
    local variantOK,variantInstance=MatchController.initializePresentation(function()
        return VariantHudController.new(gameUI,{formatTroops=displayTroops,preferences=preferences,
            teamColor=function(team)return renderer.graphicsPalette:teamBase(team)end,
            speed=function(multiplier)send("GameSpeed",{action="Set",multiplier=multiplier})end,
            exit=function()if snapshot then remotes.Command:FireServer({kind="Exit",matchId=snapshot.matchId})elseif goHome then goHome() end end})
    end,presentationFailed)
    if not variantOK then return end;variantHUD=variantInstance
    local teamOK,teamInstance=MatchController.initializePresentation(function()
        return TeamHUDController.new(gameUI,preferences,{formatNumber=displayNumber,formatTroops=displayTroops,
            teamColor=function(team)return renderer.graphicsPalette:teamBase(team)end,
            gameID=function()return if snapshot then tostring(snapshot.gameID or snapshot.matchId)else ""end,
            barVisibilityChanged=function(visible)variantHUD:setTopOffset(if visible then 7 else 0)end})
    end,presentationFailed)
    if not teamOK then return end;teamHUD=teamInstance;teamHUD:attachLeaderboard(leaderboard)
    gui.Destroying:Connect(function()teamHUD:destroy();variantHUD:destroy()end)
    preferenceView=PreferencePresentation.new(gameUI,world,preferences,{formatTroops=displayTroops})
    stock=StockEffectsRenderer.new(world,gameUI.Templates,renderer,{
        nameLocation=function(owner)return names.entries[owner]end,
        conquestPopup=function(events)cities.bonuses:applyConquestEvents(events)end})
    stock:setEffects(effects)
    local function applyCosmetics(looks: any, state: any?)
        local current=state or (snapshot and snapshot.state)
        if not current then return end
        local owners=CosmeticAppearance.forState(current,CustomFlagLooks.overlay(looks),Players.LocalPlayer.UserId,preferences:get("showCosmetics")) -- PF019 W7 Show cosmetics from (PF020 G1: + custom flags)
        renderer:setCosmetics(owners);names:setCosmetics(owners);effects:setCosmetics(owners)
        if weapons and weapons.setCosmetics then weapons:setCosmetics(owners) end -- PF020 Nuke FX trails + blasts
    end
    cosmeticShop=CosmeticShopController.new(gui,remotes,{changed=function(looks)applyCosmetics(looks)end,
        stateChanged=function()if atlasMenu then atlasMenu:updateCommerce()end end})
    gui.Destroying:Connect(function()if cosmeticShop then cosmeticShop:dispose()end end)
    gui.Destroying:Connect(CustomFlagLooks.watch(function()if cosmeticShop then applyCosmetics(cosmeticShop.looks)end end)) -- PF020 G1
    gui.Destroying:Connect(function()if stock then stock:destroy()end end)
    gui.Destroying:Connect(function()if preferenceView then preferenceView:dispose()end end)
    gui.Destroying:Connect(function() if quickChat then quickChat:destroy() end end)
    names:setPreferences(preferences);leaderboard:setPreferences(preferences)
    diplomacy:setPreferences(preferences);quickChat:setPreferences(preferences)
    cities.buildings:setPreferences(preferences)
    local function applyResolvedGraphics(graphics: any)
        local overrides=preferences:graphicsOverrides()
        names:setGraphics(graphics);cities.buildings:setGraphics(graphics,overrides)
        if renderer.setGraphics then renderer:setGraphics(graphics,overrides,preferences)end
        if teamHUD then teamHUD:setPalette(overrides.palette or "default");if snapshot then teamHUD:update(snapshot.state,true)end end
        if variantHUD then variantHUD:setPreferences(preferences) end
        if industry.setGraphics then industry:setGraphics(graphics,overrides,preferences)end
        if weapons.setGraphics then weapons:setGraphics(graphics,overrides,preferences)end
        if naval.setGraphics then naval:setGraphics(graphics)end
        if warships.setGraphics then warships:setGraphics(graphics)end
        stock:setGraphics(graphics)
    end
    applyGraphics=function()
        local fresh=GraphicsSettings.fromPreferences(preferences)
        table.clear(resolvedGraphics)
        for key,value in fresh do resolvedGraphics[key]=value end
        applyResolvedGraphics(resolvedGraphics)
    end
    applyGraphics()
    industry:setEffects(effects)
    if cities.buildings.setEffects then cities.buildings:setEffects(effects)end
    if naval.setEffects then naval:setEffects(effects)end
    if weapons.setEffects then weapons:setEffects(effects)end
    local function debugHooks()
        return {getSettings=function()return resolvedGraphics end,
            resolveDefaults=function()return GraphicsSettings.fromPreferences(preferences)end,
            settingsChanged=applyResolvedGraphics,
            setEffectOverride=function(slot,attrs)effects:setOverride(slot,attrs)end,
            effectAvailable=function(slot,kind)
                return ((slot=="structures"or slot=="warship"or slot=="train"or slot=="railroad"or slot=="transportShipTrail"or slot=="nukeTrail")and (kind=="gradient"or kind=="transition"))or slot=="nukeExplosion"
            end}
    end
    renderDebug=RenderDebugController.new(gui,debugHooks())
    gui.Destroying:Connect(function()if renderDebug then renderDebug:dispose()end;effects:destroy()end)

    remotes.State.OnClientEvent:Connect(function(received: any)
        MatchController.runDeferred(true) -- a newer packet: the previous packet's HUD first
        debug.profilebegin("PF.Packet") -- MicroProfiler labels (Ashton's late-game lag dumps)
        local applied,applyError=xpcall(function() local packet=received
        if typeof(packet) ~= "table" then return end
        if packet.kind=="Home"then
            if type(packet.matchId)~="number"or packet.matchId<latestMatchId then return end
            snapshotRecovery:reset()
            latestMatchId=packet.matchId;homeReady=true;if goHome then goHome()end;return
        end
        if packet.kind=="LobbyStarted"then
            if lobby and packet.attempt==lobby.attempt and packet.ok==true then joinedAttempt=packet.attempt end
            if lobby and packet.attempt==lobby.attempt and packet.ok~=true then homeUI.Visible=true end
            if lobby then lobby:finishStart(packet.attempt,packet.ok==true,packet.message)end;return
        end
        if packet.kind=="LobbyTransfer"then if lobby then lobby:transfer(packet.attempt,packet.phase,packet.message)end;return end -- PF019 W6: Solo on its own server
        if packet.kind=="AutoTutorial"then if lobby then lobby:splash(packet.phase,packet.message,packet.map)end;return end -- Onboarding: first-match screen (FirstMatch, packet.map optional) / invitee offer
        if packet.kind=="MatchFault"then -- the server stopped this match: one way out, Return to lobby
            if variantHUD and variantHUD.fault and snapshot and (packet.matchId==nil or packet.matchId==snapshot.matchId)then variantHUD:fault(packet.message)end;return
        end
        if packet.kind=="TutorialNotice" then
            TutorialFeedback.show(tostring(packet.message or ""))
            return
        end
        if packet.kind == "Notice" then
            showNotice(tostring(packet.message or ""), packet.color)
            if packet.refused then require(script.Parent.Sfx).play("u_error") end -- PF043: a refused action (Sfx: 0.5 s cooldown, silent until bound)
            -- the server could not send the player back (a reserved server's teleport failed): the card's key works again
            if ui.returning and string.find(tostring(packet.message or ""),"return to the lobby",1,true) and string.find(tostring(packet.message or ""),"Couldn",1,true) then
                local key=result:FindFirstChild("ReturnLobby",true);if key then key.Text=ui.returning.text;key.Active=true end;ui.returning=nil
                result:SetAttribute("PFReturning",nil) -- PF026: the end card's Return key works again
            end
            return
        end
        -- PF014 B: a send was reduced or refused to keep a regrowth reserve.
        if packet.kind=="ReserveNotice" then if diplomacy and diplomacy.reserveNotice then diplomacy:reserveNotice(packet) end;return end
        if packet.kind=="SendGuard" then if diplomacy and diplomacy.guardNotice then diplomacy:guardNotice(packet) end;return end -- new-player send guard
        if packet.kind == "NavalNotice" and snapshot and type(packet.event) == "table" then
            local event = packet.event
            -- PF012 B: event notices go to the bottom-left stack; command feedback stays a toast.
            local function eventNotice(text: string,kind: string,focus: number?,glyph: string?,color: Color3?,detail: string?)
                if diplomacy and diplomacy.stack then diplomacy:pushNotice(text,kind,focus,glyph,detail)
                else showNotice(text..(if detail then " · "..detail else ""),color) end
            end
            if event.type == "NAVAL_INVASION_INBOUND" then
                -- PF018 v2: the nation and the troop count are never ellipsized; the count gets
                -- the notice's emphasised Detail line.
                eventNotice("Naval invasion · " .. (snapshot.state.names[event.attacker] or ""),"DANGER",event.attacker,"Boat",Color3.fromRGB(248,113,113),displayTroops(event.troops) .. " troops")
            elseif event.key == "events_display.attack_cancelled_retreat" then
                showNotice("Attack cancelled, " .. displayTroops(event.troops) .. " soldiers killed during retreat")
            elseif event.key == "events_display.no_boats_available" then
                showNotice("No boats available, max " .. tostring(event.max))
            elseif event.key == "events_display.trade_ship_captured" then
                eventNotice("Your trade ship was captured by " .. (snapshot.state.names[event.otherOwner] or ""),"DANGER",event.otherOwner,"Boat",Color3.fromRGB(248,113,113))
            elseif event.key == "events_display.received_gold_from_captured_ship" then
                eventNotice("Ship captured from " .. (snapshot.state.names[event.otherOwner] or ""),"POSITIVE",event.otherOwner,"DiplomacyDonateGold",nil,"+" .. displayNumber(event.gold) .. " gold")
            elseif event.key == "events_display.unit_destroyed" then
                eventNotice((if event.unit == "unit_type.warship" then "Warship" else "Boat") .. " destroyed","DANGER",nil,"Boat",Color3.fromRGB(248,113,113))
            end
            return
        end
        if not packet.state or type(packet.matchId)~="number"or packet.matchId<latestMatchId then return end
        stall:packet()
        local localTutorial=packet.tutorialMatch==true and (packet.isStudio==true or packet.lobbyTutorial==true)
        -- PF020: the lobby attempt only filters a NEW start; the running match keeps its packets
        -- whatever the lobby UI does (menus, the Solo screen, Escape).
        if packet.online~=true and packet.hosted~=true and not localTutorial and lobby and packet.lobbyAttempt~=lobby.attempt
            and not (snapshot and packet.matchId==snapshot.matchId) and not stall:adopts(packet.matchId) then stall:dropped("lobby-attempt",packet.matchId);return end
        if snapshot and packet.matchId < snapshot.matchId then return end
        if not snapshotRecovery:allows(packet,snapshot) then stall:dropped("waiting for a full snapshot");return end
        -- Decode owns its top-level view; other RemoteEvent listeners retain
        -- the encoded packet rather than observing this controller's mutations.
        packet=table.clone(packet)
        packet.state=table.clone(packet.state)
        local packetStarted = Performance.start()
        if packetStarted and type(packet.profileSentAt)=="number" then
            Performance.observe("client.delivery",math.max(0,workspace:GetServerTimeNow()-packet.profileSentAt))
        end
        local stageStarted = Performance.start()
        debug.profilebegin("PF.Decode")
        -- PF020 (PF - 3 review): a decode that throws is a rejection too (recovery asks for a full, the stall report says why)
        local decodedOk,decoded,decodeReason = pcall(MatchTransport.decode, packet, snapshot and snapshot.state)
        debug.profileend()
        Performance.finish("client.decode", stageStarted)
        if not decodedOk then decodeReason="decode-error: "..string.sub(tostring(decoded),1,120);decoded=nil end
        -- PF020 v13: a full whose rebuilt terrain fails its checksum makes the next Ready ask for the whole terrain
        if not decoded and string.find(tostring(decodeReason),"full.checksum",1,true) then gui:SetAttribute("PFWireTerrain",true) end
        if not decoded then snapshotRecovery:failed(packet,decodeReason);stall:dropped("decode rejected: "..tostring(decodeReason));return end
        gui:SetAttribute("PFWireSeq",if type(decoded.wireSeq)=="number" then decoded.wireSeq else nil)
        if gui:GetAttribute("PFWireTerrain") then gui:SetAttribute("PFWireTerrain",nil) end
        snapshotRecovery:accepted(packet);stall:applied(packet.matchId,decoded.ticks)
        packet.state = decoded
        local changedMap = not snapshot or packet.matchId ~= snapshot.matchId
            or packet.state.seed ~= snapshot.state.seed
            or packet.state.map.width ~= mapWidth or packet.state.map.height ~= mapHeight
        if changedMap then localBorders = nil end
        local changes = decoded.changedOwnerIds
        if changedMap or changes == nil or #changes > 0 or eligibilityPhase ~= decoded.phase then
            eligibilityCache = {}
        end
        eligibilityPhase = decoded.phase
        stageStarted = Performance.start()
        debug.profilebegin("PF.Borders");localBorders = updateLocalBorders(decoded, localBorders);debug.profileend()
        Performance.finish("client.localBorders", stageStarted)
        -- Presentation-only index; authoritative snapshots remain server-owned.
        -- canAttack reads the same helper path as the server without scanning2M
        -- ownership entries for an enemy menu on every resource-only snapshot.
        decoded.borders = { [1] = localBorders }
        snapshot = packet
        PacketFeed.publish(packet) -- PF021 B: the tutorial tracker reads the decoded state (presentation only)
        debug.profilebegin("PF.MenuObserve");if atlasMenu then atlasMenu:observe(packet) end;debug.profileend()
        if atlasMenu then if not atlasMenu:isLocked()then atlasMenu:hide()end end -- PF019 M13b: the locked shop stays up mid-match
        if effectTick~=packet.state.ticks then effects:flush();effectTick=packet.state.ticks end
        latestMatchId=packet.matchId
        if not localTutorial and (packet.online==true or packet.hosted==true or joinedAttempt==packet.lobbyAttempt)and not countedMatches[packet.matchId]then
            countedMatches[packet.matchId]=true
            if preferencesLoaded then preferences:incrementGamesPlayed()else pendingGamesPlayed+=1 end
            joinedAttempt=nil
        end
        if localTutorial then
            if publicLobby and publicLobby.tutorialStarted then publicLobby:tutorialStarted()end
            joinedAttempt=nil;homeUI.Visible=false;background.PublicWaiting.Visible=false
            background.LobbyAlert.Visible=false
            if lobby then lobby.starting=false;lobby.overlayAttempt=0;lobby:hide() end
            background.Starting.Visible=false
        end
        packet.state.clientPreferences=preferences
        if changedMap and settingsMenu then settingsMenu:setMapLayers(packet.state.map.manifest and packet.state.map.manifest.layers or {})end
        if changedMap then
            audio:startGame()
            noticeUntil = 0
            ui.noticeUI.Visible = false
            rebuildMap(packet.state)
        end
        -- PF020: the renderer stages run under one guard; an error is logged once (watchdog) and
        -- the HUD and clock below still update, so one bad stage can never freeze the view.
        local stagesOk,stageResult=xpcall(function()
        stock:beginFxFrame(packet.state)
        stock:update(packet.state)
        if rendererReady then
            stageStarted = Performance.start()
            renderer:setTeamColors((packet.state.gameConfig or {}).teamColors) -- PF020 G8 Lobby Host+ team colours
            renderer:setPlayers(packet.state.players, packet.state.playerOrder)
            debug.profilebegin("PF.Cosmetics");if cosmeticShop then applyCosmetics(cosmeticShop.looks,packet.state) end;debug.profileend()
            if renderer.updateTerrain then renderer:updateTerrain(packet.state.changedTerrainIds)end
            renderer:setDiplomacy(packet.state)
            renderer:updateFallout(packet.state.falloutTiles,packet.state.changedFalloutIds,packet.state.ticks)
            debug.profilebegin("PF.Owners");renderer:updateOwners(packet.state.owners, packet.state.changedOwnerIds);debug.profileend()
            renderer:setDefensePosts(packet.state.defensePosts)
            Performance.finish("client.raster", stageStarted)
            stageStarted = Performance.start()
            debug.profilebegin("PF.Names");names:update(packet.state, renderer.owned, changedMap or packet.state.changedOwnerIds == nil, renderer.colors);debug.profileend()
            local startLocation = MapCamera.startLocation(packet.state, preferences:get("goToPlayer"), hasGoneToPlayer, renderer.owned[1])
            if startLocation then
                hasGoneToPlayer = true
                initialFitPending = false
                setCameraTarget(Vector2.new(startLocation.x, startLocation.y), 8)
            end
            Performance.finish("client.namesUpdate", stageStarted)
            MatchController.defer("PF.Leaderboard",function(state: any) local started=Performance.start();leaderboard:update(state);Performance.finish("client.leaderboard",started) end,packet.state)
        end
        stageStarted = Performance.start()
        local updateStarted=Performance.start()
        debug.profilebegin("PF.Cities");cities:update(packet.state,renderer.colors,renderer.palettes);debug.profileend()
        Performance.finish("client.update.city",updateStarted)
        debug.profilebegin("PF.Warships");warships:update(packet.state,renderer.colors);debug.profileend()
        debug.profilebegin("PF.Industry");industry:update(packet.state,renderer.colors,renderer.palettes);debug.profileend()
        updateStarted=Performance.start()
        debug.profilebegin("PF.Weapons");weapons:update(packet.state);debug.profileend()
        Performance.finish("client.update.weapons",updateStarted)
        MatchController.defer("PF.Diplomacy",function(state: any) local started=Performance.start();diplomacy:update(state);Performance.finish("client.update.diplomacy",started) end,packet.state)
        MatchController.defer("PF.QuickChat",quickChat.update,quickChat,packet.state,renderer.colors)
        MatchController.defer("PF.PrefView",function(state: any,alternate: boolean) local started=Performance.start();preferenceView:update(state,alternate);Performance.finish("client.update.preferences",started) end,packet.state,alternateView)
        local center=(viewport.AbsoluteSize/2-offset)/tileSize
        local cx,cy=math.floor(center.X),math.floor(center.Y)
        audio:updateAmbience(packet.state,tileSize,if cx>=0 and cy>=0 and cx<mapWidth and cy<mapHeight then cy*mapWidth+cx+1 else nil)
        if weaponMessageCursor~=nil then
            for _,event in packet.state.weaponMessages or {} do
                if event.eventId<=weaponMessageCursor or event.owner~=1 then continue end
                local text,inbound=MatchController.weaponNotice(event,packet.state)
                if text then showNotice(text,if inbound then Color3.fromRGB(248,113,113) else nil) end
            end
        end
        weaponMessageCursor=math.max(weaponMessageCursor or 0,packet.state.weaponMessageCursor or 0)
        Performance.finish("client.citiesUpdate", stageStarted)
        stageStarted = Performance.start()
        local shipsOK,shipsFailure=pcall(function()
            debug.profilebegin("PF.Naval");naval:update(packet.state,renderer.colors,renderer.palettes);debug.profileend()
            stock:commitFxFrame()
        end)
        if not shipsOK then
            stock:abortFxFrame()
            presentationFailed(shipsFailure)
            return "abort"
        end
        Performance.finish("client.shipsUpdate", stageStarted)
        return nil
        end,debug.traceback)
        if not stagesOk then pcall(stock.abortFxFrame,stock);stall:failed(stageResult)
        elseif stageResult=="abort" then return end
        gameUI.Visible = true
        homeUI.Visible = false
        if publicLobby then publicLobby:matchStarted(packet.online)end
        local resultCues
        resultCues,deathSoundShown,winSoundHandled=MatchController.resultSounds(packet.state,deathSoundShown,winSoundHandled,packet.spectator==true)
        for _,cue in resultCues do audio:play(cue)end
        MatchController.defer("PF.HUD",function() local started=Performance.start();renderText();Performance.finish("client.hud",started) end)
        gui:SetAttribute("OpenFrontMatchReady", rendererReady)
        Performance.finish("client.packet", packetStarted)
        end,debug.traceback)
        debug.profileend()
        if not applied then stall:failed(applyError) end
    end)

    local function setRatio(value: number)
        ratio = math.clamp(math.floor(value * 100 + 0.5), 1, 100) / 100
        renderRatio()
    end

    local function changeRatio(points: number)
        local nextRatio = math.clamp(ratio + points / 100, 0.01, 1)
        if ratio == 0.01 and points>0 then nextRatio = points/100 end
        setRatio(nextRatio)
    end

    local function ratioAt(position: Vector2)
        if ui.sliderTrack.AbsoluteSize.X <= 0 then return end
        local fraction = math.clamp((position.X - ui.sliderTrack.AbsolutePosition.X) / ui.sliderTrack.AbsoluteSize.X, 0, 1)
        setRatio((1 + fraction * 99) / 100)
    end
    goHome=function()
        -- Return to lobby (Ashton: "just broken"): every teardown is guarded, so one controller that throws can
        -- never stop the screen flip below and strand the player on the match screen.
        local function safe(label: string,fn: () -> ())
            local ok,err=pcall(fn);if not ok then warn("[OpenFront] return to lobby ("..label.."): "..tostring(err)) end
        end
        safe("recovery",function() snapshotRecovery:reset() end)
        local previousMatchId=snapshot and snapshot.matchId
        safe("audio",function() audio:endGame() end)
        safe("debug",function() if renderDebug then renderDebug:dispose();renderDebug=nil end end)
        safe("effects",function() effects:destroy() end);effectTick=nil
        safe("view",function() setAlternateView(false) end);heldKeys={};coordinateGrid=false;safe("grid",function() renderer:setGridView(false) end)
        mapGeneration+=1;snapshot=nil;rendererReady=false;mapWidth=0;mapHeight=0
        for _,step in {{"map",renderer,"destroy"},{"names",names,"reset"},{"leaderboard",leaderboard,"reset"},{"cities",cities,"reset"},{"naval",naval,"reset"},
            {"warships",warships,"reset"},{"industry",industry,"reset"},{"weapons",weapons,"reset"},{"diplomacy",diplomacy,"reset"},{"quickChat",quickChat,"reset"},
            {"stock",stock,"reset"},{"teamHUD",teamHUD,"reset"},{"variantHUD",variantHUD,"reset"}} do
            safe(step[1],function() step[2][step[3]](step[2]) end)
        end
        safe("gamepad",function() if gamepadInput then gamepadInput:clear() end end)
        safe("interface",function() interface:setBlocked(true) end)
        safe("graphics",function() if applyGraphics then applyGraphics()end end)
        safe("preferences",function() if preferenceView then preferenceView:reset()end end)
        for _,row in attackRows do pcall(row.Destroy,row)end;attackRows={}
        gesture=nil;pinching=false;activeTouches={};sliderGesture=nil;safe("camera",function() setCameraTarget(nil) end);hasGoneToPlayer=false;radialTarget=nil;warshipBox=nil
        if ui.returning then local key=result:FindFirstChild("ReturnLobby",true);if key then key.Text=ui.returning.text;key.Active=true end;ui.returning=nil end
        result:SetAttribute("PFReturning",nil)
        gameUI.Visible=false;gui:SetAttribute("OpenFrontMatchReady",false)
        safe("settings",function() if settingsMenu then settingsMenu:closeAll(true)end end)
        safe("menu",function() if M13.menu then M13.menu:close()end end)
        homeUI.Visible=true;safe("lobby",function() if lobby then lobby:hide()end end)
        if publicLobby then publicLobby:homeShown()end
        -- a menu error must never strand the player on the match screen (Ashton: Return to lobby "breaks")
        if atlasMenu then local ok,err=pcall(atlasMenu.home,atlasMenu,previousMatchId);if not ok then warn("[OpenFront] lobby menu: "..tostring(err)) end end
    end
    settingsMenu=SettingsController.new(gui,{preferences=preferences,audio=audio,
        pause=function(value)send("Pause",{paused=value})end,
        terrain=setAlternateView,
        debug=function()
            if not renderDebug then renderDebug=RenderDebugController.new(gui,debugHooks())end
            renderDebug:toggle()
        end,
        exit=function()if snapshot then remotes.Command:FireServer({kind="Exit",matchId=snapshot.matchId})elseif goHome then goHome() end end,
        ratio=function()return ratio end,
        settingsChanged=function(key)if key=="settings.attackRatio"then setRatio(preferences:get("attackRatio"))end end})
    require(script.Parent.PF019UiSize).bind(gui,preferences) -- PF019 W7 S9 UI size (authored PFUiSize scales)
    lobby=LobbyController.new(gui,{catalog=Availability.maps,preferences=preferences,
        start=function(config,attempt)homeUI.Visible=false;remotes.Command:FireServer({kind="LobbyStart",config=config,attempt=attempt})end,
        settings=function()settingsMenu:openSettings()end,
        cancel=function(attempt)homeUI.Visible=true;remotes.Command:FireServer({kind="Exit",attempt=attempt});if atlasMenu then atlasMenu:show("Play")end end,
        alertClosed=function()if atlasMenu and not snapshot then atlasMenu:show("Play")end end}) -- PF019 W6: a failed Solo start returns to the menu
    homeUI.Body.Solo.Activated:Connect(function()lobby:show()end)
    homeUI.Body.Settings.Activated:Connect(function()settingsMenu:openSettings()end)
    publicLobby=PublicLobbyController.new(gui,remotes,{atlas=true,changed=function(model)if atlasMenu then atlasMenu:updatePublic(model)end end})
    atlasMenu=AtlasMenuController.new(gui,{public=publicLobby,shop=cosmeticShop,settings=settingsMenu,
        solo=function()lobby:show()end,
        soloStart=function(config)return lobby:startConfig(config)end, -- PF019 (PF - 3): the Atlas Solo screen
        createLobby=function(config,roomName)return publicLobby:createPrivate(config,roomName)end,
        joinLobby=function(code)return publicLobby:joinPrivate(code)end,
        startPrivate=function()return publicLobby:startPrivate()end})
    if homeReady then atlasMenu:show("Play")end
    for _,button in {homeUI.Body.Solo,homeUI.Body.Settings} do
        button.MouseEnter:Connect(function()
            if button.Name=="Solo"then button.BackgroundColor3=Theme.Accent:Lerp(Theme.Text,.12)else button.TextColor3=Theme.Accent end
        end)
        button.MouseLeave:Connect(function()
            if button.Name=="Solo"then button.BackgroundColor3=Theme.Accent else button.TextColor3=Theme.Text end
        end)
    end
    local gear=gameUI:WaitForChild("GameRightSidebar"):WaitForChild("Settings") :: TextButton
    ReferenceIcons.bind(gear.Icon,"LobbySettings")
    gear.Activated:Connect(function()if snapshot then gesture=nil;sliderGesture=nil;warshipBox=nil;warships:cancelBox();if M13.menu then M13.menu:open()else settingsMenu:openMenu(((snapshot.state.gameConfig or {}).gameType or "Singleplayer")=="Singleplayer",snapshot.paused==true)end end end)
    local function aimPosition(): Vector2
        if gamepadInput and gamepadInput.gamepad then return viewport.AbsolutePosition+viewport.AbsoluteSize/2 end
        local id=radialTarget or selected
        if id and mapWidth>0 then return viewport.AbsolutePosition+offset+Vector2.new((id-1)%mapWidth+.5,math.floor((id-1)/mapWidth)+.5)*tileSize end
        return viewport.AbsolutePosition+viewport.AbsoluteSize/2
    end
    local function centerPlayer()
        if not snapshot or not rendererReady then return end
        local location=NameLayout.place(snapshot.state,1,renderer.owned[1])
        initialFitPending=false;setCameraTarget(if location then Vector2.new(location.x,location.y) else nil,8)
    end
    local function primaryAction()
        if modalBlocked() then return end
        selectAt(aimPosition())
    end
    local function backAction(): boolean
        if cosmeticShop and cosmeticShop:handleEscape() then return true end
        if result.Visible then dismissedOutcome=result:GetAttribute("Outcome") :: string?;result.Visible=false;return true end
        if variantHUD and variantHUD:handleEscape() then return true end
        if M13.menu and M13.menu:handleEscape() then return true end
        if renderDebug and renderDebug:handleEscape() then return true end
        if settingsMenu and settingsMenu:handleEscape() then return true end
        if lobby and lobby:handleEscape() then return true end
        if atlasMenu and atlasMenu:handleEscape()then return true end
        if leaderboard:handleEscape()then return true end
        if quickChat and quickChat:key(Enum.KeyCode.Escape) then return true end
        if diplomacy:key(Enum.KeyCode.Escape,aimPosition()) then return true end
        if radial.Visible then radial.Visible=false;radialTarget=nil;return true end
        if cities.ghostActive then cities:clearGhost();return true end
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then GuiService.SelectedObject=nil;return true end
        if rendererReady then cities:clearGhost();warships:cancelBox();warshipBox=nil;warships:clearSelection();return true end
        return false
    end
    ui.controls.Actions.Primary.Activated:Connect(function()
        -- The desktop/touch HUD action must never purchase at a previously
        -- selected tile. Blueprint confirmation belongs to the map or reticle.
        if not cities.ghostActive then primaryAction() end
    end)
    -- PF012 top-left icon bar: magnifier = existing focus; leave = authored
    -- exit confirm (Stay/Escape/B/backdrop cancel, Leave sends the old Exit).
    -- The zoom +/- buttons are retired; wheel, pinch, keys and triggers remain.
    -- PF013: the top-right toolbar is gone; its Settings moved into this bar
    -- and opens the same in-match settings menu as the retired gear.
    do -- PF019 M13a: Background.GameMenu marked PF019GameMenu=true is the M13 menu (see InGameMenu).
        local menuRoot=background:FindFirstChild("GameMenu")
        if menuRoot and menuRoot:GetAttribute("PF019GameMenu")==true then
            M13.status=function()
                if not snapshot then return {} end
                local state=snapshot.state;local alive=0
                for owner in state.players do if (state.counts[owner] or 0)>0 then alive+=1 end end
                return {clock=variantHUD and variantHUD.meta and variantHUD.meta.timerText or nil,mode=(state.gameConfig or {}).gameMode,alive=alive}
            end
            -- PF019 M13b: the Shop row opens the real shop locked over the live match; Back / Esc return to it.
            M13.openShop=function() return atlasMenu~=nil and atlasMenu:openLockedShop({status=M13.status}) end
            M13.menu=InGameMenu.new(menuRoot,{
                singleplayer=function() return snapshot~=nil and ((snapshot.state.gameConfig or {}).gameType or "Singleplayer")=="Singleplayer" end,
                paused=function() return snapshot~=nil and snapshot.paused==true end,
                pause=function(value) send("Pause",{paused=value}) end,
                settings=function(back) settingsMenu:setMenuReturn(back);settingsMenu:openPreferences() end,
                shop=function() if not M13.openShop() and cosmeticShop then cosmeticShop:open() end end,
                exit=function() BattleHudShell.confirmLeave(variantHUD) end,
                status=M13.status,
                balance=function() local shop=cosmeticShop and cosmeticShop:getState();return shop and shop.profile and shop.profile.balance end,
            })
            M13.confirm=InGameMenu.bindConfirm(gameUI:FindFirstChild("VariantExitConfirm"))
        end
    end
    -- PF043 (PF - 1; Ashton on the D8b board: "I LOVE this ... only for public matches"): the Leave confirm's requeue body
    -- (tools/atlas/author-pf043-requeue-leave.luau): Find a new match / Back to lobby / Stay on a public match; plain confirm elsewhere
    M13.requeue=require(script.Parent.LeaveRequeue).bind(gameUI:FindFirstChild("VariantExitConfirm"),{
        canRequeue=function() return snapshot~=nil and snapshot.online==true and snapshot.matchKind=="public" and snapshot.spectator~=true and not ui.returning end,
        findNewMatch=function() return ui.findNewMatch~=nil and ui.findNewMatch() end,requeueState=function() return ui.requeueState and ui.requeueState() or nil end,
        stay=function() if variantHUD then variantHUD:finishExit(false) end end,leave=function() if variantHUD then variantHUD:finishExit(true) end end})
    PacketFeed.context.centerPlayer=function() if not modalBlocked() then centerPlayer() end end -- PIVOT D10: ReviveView centres the camera on a revived pocket (Locate's own call)
    PacketFeed.context.resetResult=function() dismissedOutcome=nil end
    PacketFeed.context.openArsenal=function() return atlasMenu~=nil and atlasMenu:openLockedShop({tab="Armory"}) end -- PIVOT Armory: the Premium grid's last cell opens the Armory over the match -- PIVOT D10: a revive is a new life: a later Defeat shows its card again
    interface:bindIconBar({focus=function() if not modalBlocked() then centerPlayer() end end,
        leave=function() if snapshot and not modalBlocked() then BattleHudShell.confirmLeave(variantHUD) end end,
        settings=function() if snapshot and not modalBlocked() then gesture=nil;sliderGesture=nil;warshipBox=nil;warships:cancelBox()
            if M13.menu then M13.menu:open() else
            settingsMenu:openMenu(((snapshot.state.gameConfig or {}).gameType or "Singleplayer")=="Singleplayer",snapshot.paused==true) end end end})
    gamepadInput=RevampInput.new({
        available=function() return gameUI.Visible and rendererReady and snapshot~=nil and focused and not modalBlocked()
            and not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible end,
        device=function(value) interface:setGamepad(value) end,
        primary=primaryAction,focus=centerPlayer,
        -- X / Square: the right-click radial at the aim point (Ashton 2026-10-08); the stick, D-pad, A and B drive it
        radialMenu=function(): boolean
            if radial.Visible then radial.Visible=false;radialTarget=nil;return true end
            if modalBlocked() then return false end
            openRadial(aimPosition());return radial.Visible
        end,
        radialOpen=function(): boolean return radial.Visible end,
        radialAim=function(direction: Vector2) cities:aimRadial(direction) end,
        radialStep=function(step: number) cities:stepRadial(step) end,
        radialConfirm=function() cities:activate(cities.hover) end,
        radialBack=function() if not cities:back() then radial.Visible=false;radialTarget=nil end end,
        ratio=function(direction) changeRatio(direction*preferences:get("attackRatioIncrement")) end,
        hotbar=function(direction) cities:cycleHotbar(direction) end, -- PF020: L1/R1 console hotbar
        ratioFocused=function() return GuiService.SelectedObject==ui.sliderInput and focused and isController() and canPlay()
            and not modalBlocked() and not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible end,
        back=backAction,
        navigate=function()
            if cosmeticShop and cosmeticShop:isBlocking() then cosmeticShop:focusActive();return end
            if atlasMenu and atlasMenu:isBlocking()then atlasMenu:focusActive();return end
            if quickChat and quickChat:intercepts() then quickChat:focusActive();return end
            if diplomacy.panel.Visible or diplomacy.emojiMenu.Visible then diplomacy:focusActive();return end
            if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then GuiService.SelectedObject=nil
            elseif gameUI.Visible and not modalBlocked() then GuiService.SelectedObject=cities:firstBlueprint() or interface:iconBarFocus()
            elseif homeUI.Visible then GuiService.SelectedObject=homeUI.Body.Solo end
        end,
        move=function(delta,zoom)
            initialFitPending=false;setCameraTarget(nil);offset-=delta
            if zoom~=0 then zoomAt(math.exp(zoom*1.8),viewport.AbsolutePosition+viewport.AbsoluteSize/2) else applyTransform() end
            mousePosition=viewport.AbsolutePosition+viewport.AbsoluteSize/2;showHighlight(targetAt(mousePosition))
        end,
    })
    gamepadInput:setPreferences(preferences) -- PF019 W7 S20 stick sensitivity
    local savingScheduled=false
    local function flushPreferences()
        savingScheduled=false;if not preferencesLoaded then return end
        local patch=preferencePatch;preferencePatch={}
        for key,value in patch do remotes.PreferencesCommand:FireServer({kind="Set",key=key,value=value})end
    end
    local preferenceOff=preferences:subscribe(function(key,value)
        interface:setPreferences(preferences)
        if key=="settings.attackRatio"then setRatio(preferences:get("attackRatio"))end
        if (key=="settings.graphics" or key=="settings.graphicsQuality")and applyGraphics then applyGraphics()end
        if key=="settings.anonymousNames"or key=="settings.emojis"then
            names:setPreferences(preferences);leaderboard:setPreferences(preferences)
            if teamHUD and snapshot then teamHUD:update(snapshot.state,true)end
            if variantHUD then variantHUD:setPreferences(preferences)end
            diplomacy:setPreferences(preferences);quickChat:setPreferences(preferences)
        end
        if replacingPreferences then return end
        preferencePatch[key]=if value==nil then false else value
        if not savingScheduled then savingScheduled=true;task.delay(.25,flushPreferences)end
    end)
    remotes.PreferencesState.OnClientEvent:Connect(function(packet)
        if type(packet)~="table"or packet.kind~="Preferences"then return end
        if not preferencesLoaded and packet.loaded==true and type(packet.storage)=="table"then
            local merged=table.clone(packet.storage)
            for key,value in preferencePatch do merged[key]=if value==false then nil else value end
            replacingPreferences=true;preferences:replace(merged);replacingPreferences=false
            preferencesLoaded=true
            for _=1,pendingGamesPlayed do preferences:incrementGamesPlayed()end;pendingGamesPlayed=0
            if preferences:resetAudioOnce()then preferencePatch["settings.audio.resetVersion"]="1"end
            flushPreferences()
        end
        settingsMenu:setPersistenceStatus(if packet.failed then "Settings could not be saved. They remain available for this session."elseif not packet.loaded then "Loading saved settings…"else "")
    end)
    gui.Destroying:Connect(function()preferenceOff();lobby:dispose();settingsMenu:dispose()end)
    remotes.PreferencesCommand:FireServer({kind="Ready"})

    ui.sliderInput.InputBegan:Connect(function(event: InputObject)
        if modalBlocked()then return end
        if not isController() or not canPlay() then return end
        if event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch then
            sliderGesture = event
            ratioAt(point(event.Position))
        end
    end)
    ui.restart.Activated:Connect(function() send("Restart") end)
    ui.devRestart.Activated:Connect(function() send("Restart") end)
    ui.keepWatching=function()
        dismissedOutcome = result:GetAttribute("Outcome") :: string?
        result.Visible = false
    end
    ui.resultContinue.Activated:Connect(function() ui.keepWatching() end)
    -- PF026: the card stays up in a "Returning…" state until Home arrives (goHome) or the server says it could not
    -- (the Notice above); with no answer in 10 s the key works again. With no match to leave, go Home at once.
    ui.requestReturn=function()
        local key=button(result,"ReturnLobby")
        if ui.returning then return end
        if not snapshot then if goHome then goHome() end;return end
        local pending={text=key.Text}
        ui.returning=pending;key.Text="Returning…";key.Active=false
        result:SetAttribute("PFReturning",true) -- PF026: the end card's key shows Returning… (cleared by goHome / the notice / 10 s)
        -- PF043: Play again on a public match goes straight to the next match from this server (requeue); the soonest one
        -- starts within ~15 s, so the busy key holds 20 s instead of 10
        local requeue=ui.requeueNext==true;ui.requeueNext=nil
        remotes.Command:FireServer({kind="Exit",matchId=snapshot.matchId,requeue=if requeue then true else nil})
        task.delay(if requeue then 20 else 10,function() if ui.returning==pending then ui.returning=nil;key.Text=pending.text;key.Active=true;result:SetAttribute("PFReturning",nil) end end)
    end
    button(result,"ReturnLobby").Activated:Connect(function() ui.requestReturn() end)
    -- PF026: the end card (authored Result.PFEnd) drives the same paths. Play again: Solo starts a new Solo with this
    -- match's settings; a public match goes back to the lobby, which joins the next public match of the same mode
    -- (PublicLobbyController reads the teleport setting after the return); custom rooms, tutorials, spectators: hidden.
    require(script.Parent.PF026EndScreen).bind(result,{requestReturn=function() ui.requestReturn() end,keepWatching=function() ui.keepWatching() end,
        requeueState=function() return ui.requeueState and ui.requeueState() or nil end, -- PF043 D1c: the Play again key's countdown
        ownerColor=function(owner: number) return renderer and renderer.colors and renderer.colors[owner] end,
        playAgain=function(info: any)
            if not snapshot or ui.returning then return end
            if info.online then
                if info.kind~="public" then return end
                local mode=type(info.config)=="table" and info.config.gameMode or nil
                pcall(function() game:GetService("TeleportService"):SetTeleportSetting("PF026Requeue",{mode=mode,teams=type(info.config)=="table" and info.config.playerTeams or nil,at=os.time()}) end)
                ui.requeueNext=true -- PF043: the server seats you in the next match from here (the wish above is the fallback home)
                ui.requestReturn()
            elseif lobby and type(info.config)=="table" then
                lobby:startConfig(info.config) -- the lobby's Starting overlay carries the wait; the new match replaces this card
            end
        end})
    -- PF043 (Ashton: "never add friction to leaving"): the Leave confirm's "Find a new match" (PF - 1's board). On a public
    -- match: leave straight into the next public match (the server's direct requeue; home + the lobby's requeue if that
    -- fails). false where it can't (Solo, a custom room, the tutorial, spectating): the caller then does a plain leave.
    ui.findNewMatch=function(): boolean
        if not snapshot or snapshot.online~=true or snapshot.matchKind~="public" or snapshot.spectator==true or ui.returning then return false end
        pcall(function() game:GetService("TeleportService"):SetTeleportSetting("PF026Requeue",{at=os.time()}) end)
        ui.requeueNext=true
        ui.requestReturn()
        return true
    end
    -- PF043: the requeue countdown for the key states, polled per frame (nil until seated): {phase="Seated"|"Starting"|
    -- "Joining"|"Home", seconds? (to the start, live), map?, players?, capacity?} (PublicLobbyController:requeueStatus)
    ui.requeueState=function(): any? return if publicLobby then publicLobby:requeueStatus() else nil end
    ui.pause.Activated:Connect(function() send("Pause") end)
    ui.hostPause.Activated:Connect(function() send("Pause") end)
    ui.speed.Activated:Connect(function() send("Debug", { action = "Speed" }) end)
    button(ui.dev, "Resources").Activated:Connect(function() send("Debug", { action = "Resources" }) end)
    button(ui.dev, "NewSeed").Activated:Connect(function() send("Debug", { action = "NewSeed" }) end)

    ui.input.InputBegan:Connect(function(event: InputObject)
        if modalBlocked()then return end
        if event.UserInputType ~= Enum.UserInputType.MouseButton1 and event.UserInputType ~= Enum.UserInputType.Touch then return end
        if not isMapPointer(point(event.Position)) or overResult(point(event.Position)) or diplomacy.panel.Visible or diplomacy.emojiMenu.Visible then return end
        if radial.Visible then
            radial.Visible = false
            radialTarget = nil
            return
        end
        if canPlay() and event.UserInputType == Enum.UserInputType.MouseButton1
            and bindingDown("boxSelectWarships")then
            cities:clearGhost()
            warshipBox = event
            warships:beginBox(point(event.Position))
            return
        end
        if event.UserInputType == Enum.UserInputType.Touch then
            activeTouches[event] = true
            mousePosition = point(event.Position)
        else
            mousePosition = point(event.Position)
        end
        if gesture then
            -- A second finger must not become a click when a pinch ends.
            gesture.moved = true
            gesture.touchLongPressPending=false
            gesture.longPress=false;ui.pressRingHide()
            local touches: {Vector2} = {}
            for touch in activeTouches do table.insert(touches, point(touch.Position)) end
            if #touches == 2 then
                pinching = true
                lastPinchDistance = (touches[1] - touches[2]).Magnitude
            end
            return
        end
        gesture = { input = event, origin = point(event.Position), last = point(event.Position), moved = false }
        if event.UserInputType==Enum.UserInputType.Touch then
            local touchGesture=gesture
            touchGesture.touchLongPressPending=true
            -- Ashton (2026-10-08): hold still ui.LONG_PRESS and the radial (the right-click menu) opens right there, no
            -- release needed; the ring fills meanwhile. Moving ten pixels or a second finger cancels (as the source's
            -- InputHandler long press); dragging after the radial opened closes it and starts the warship box.
            ui.pressRingShow(touchGesture.origin)
            task.delay(ui.LONG_PRESS,function()
                if gesture==touchGesture and touchGesture.touchLongPressPending and not pinching then
                    touchGesture.touchLongPressPending=false
                    touchGesture.longPress=true
                    ui.pressRingHide()
                    if isMapPointer(touchGesture.origin) and not diplomacy.panel.Visible and not diplomacy.emojiMenu.Visible then
                        openRadial(touchGesture.origin);touchGesture.radialOpened=radial.Visible
                    end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(event: InputObject, _processed: boolean)
        if modalBlocked()then return end
        if event.UserInputType == Enum.UserInputType.MouseMovement or event.UserInputType == Enum.UserInputType.MouseWheel then
            mousePosition = point(event.Position)
        end
        if event.UserInputType == Enum.UserInputType.MouseWheel then
            local position = point(event.Position)
            -- Roblox marks pointer events over our own GUI as processed.
            if isMapPointer(position) and not UserInputService:GetFocusedTextBox() then
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)then
                    local increment=preferences:get("attackRatioIncrement")
                    changeRatio(if event.Position.Z>0 then increment else -increment)
                else
                    -- Device adapter retained from the Roblox prototype: Roblox gives
                    -- notches, while the reference consumes browser/hardware deltaY.
                    -- This is not a claim of identical physical wheel sensitivity.
                    zoomAt(1.2 ^ event.Position.Z, position)
                end
            end
            return
        end
        if warshipBox and not pinching and (event==warshipBox or event.UserInputType == Enum.UserInputType.MouseMovement) then
            warships:updateBox(point(event.Position))
            return
        end
        if sliderGesture then
            if event == sliderGesture or (sliderGesture.UserInputType == Enum.UserInputType.MouseButton1
                and event.UserInputType == Enum.UserInputType.MouseMovement) then
                ratioAt(point(event.Position))
                return
            end
        end
        if event.UserInputType == Enum.UserInputType.Touch and pinching then
            local positions: {Vector2} = {}
            for touch in activeTouches do table.insert(positions, point(touch.Position)) end
            if #positions == 2 then
                local distance = (positions[1] - positions[2]).Magnitude
                local delta = distance - lastPinchDistance
                if math.abs(delta) > 1 then
                    zoomDelta(-delta * 2, (positions[1] + positions[2]) / 2)
                    lastPinchDistance = distance
                end
                if gesture then gesture.last = point(gesture.input.Position) end
            end
            return
        end
        if event.UserInputType==Enum.UserInputType.Touch and cities.ghostActive then mousePosition=point(event.Position) end
        if gesture and not pinching then
            local mouseDrag = gesture.input.UserInputType == Enum.UserInputType.MouseButton1
                and event.UserInputType == Enum.UserInputType.MouseMovement
            if event == gesture.input or mouseDrag then
                local position = point(event.Position)
                local movement=position-gesture.origin
                if gesture.touchLongPressPending and math.abs(movement.X)+math.abs(movement.Y)>=DRAG_THRESHOLD then
                    gesture.touchLongPressPending=false;ui.pressRingHide()
                end
                if gesture.radialOpened then
                    -- the finger rests on the radial it opened; a real drag closes it and becomes the warship box
                    if math.abs(movement.X)+math.abs(movement.Y)<DRAG_THRESHOLD then return end
                    gesture.radialOpened=false
                    if radial.Visible then radial.Visible=false;radialTarget=nil end
                end
                if canPlay()and not cities.ghostActive and (gesture.longPress or bindingDown("boxSelectWarships"))then
                    warshipBox=gesture.input
                    warships:beginBox(gesture.origin)
                    warships:updateBox(position)
                    return
                end
                initialFitPending = false
                setCameraTarget(nil)
                offset += position - gesture.last
                applyTransform()
                gesture.last = position
                -- InputHandler's separate window mousemove listener emits
                -- MouseMoveEvent during dragging too (93a136a:571-578).
                if mouseDrag and not overResult(position) then showHighlight(targetAt(position)) end
                return
            end
        end
        if event.UserInputType == Enum.UserInputType.MouseMovement and not gesture and not overResult(point(event.Position)) then
            showHighlight(targetAt(point(event.Position)))
        end
    end)
    UserInputService.InputEnded:Connect(function(event: InputObject,processed: boolean)
        if event.UserInputType==Enum.UserInputType.Keyboard then
            local code=InputBindings.code(event.KeyCode)
            heldKeys[code]=nil
            if code=="MetaLeft"or code=="MetaRight"or code=="ControlLeft"or code=="ControlRight"then
                for _,key in {"Minus","Equal","NumpadAdd","NumpadSubtract",preferences:keybinds(false).zoomIn,preferences:keybinds(false).zoomOut}do
                    if key then heldKeys[key]=nil end
                end
            end
            if InputBindings.matches(code,UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift),preferences:keybinds(false).toggleView)then setAlternateView(false)end
        end
        if modalBlocked()then return end
        -- InputHandler's ordered table dispatches every matching action on keyup.
        if event.UserInputType==Enum.UserInputType.Keyboard then
            if not rendererReady or GuiService.MenuIsOpen or processed or UserInputService:GetFocusedTextBox()then return end
            local bindings=preferences:keybinds(false)
            local code=InputBindings.code(event.KeyCode)
            local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            local function matches(action: string): boolean
                local binding=if action=="boatAttack" then InputPrompts.boatBinding(bindings[action],bindings) else bindings[action]
                return InputBindings.matches(code,shift,binding)
            end
            if matches("boatAttack")then naval:key(Enum.KeyCode.B,mousePosition)end
            if matches("groundAttack")and mousePosition then selectAt(mousePosition,true)end
            if matches("retaliateAttack")and canPlay()then
                local last
                for _,attack in snapshot.state.attacks or {}do
                    local attacker=snapshot.state.players[attack.owner]
                    if attack.targetOwner==1 and attack.active~=false and attacker and attacker.playerType~="Bot"then last=attack end
                end
                if last then send("Retaliate",{attackId=last.id,ratio=ratio})end
            end
            if matches("centerCamera")and snapshot then
                initialFitPending=false;local location=NameLayout.place(snapshot.state,1,renderer.owned[1])
                setCameraTarget(if location then Vector2.new(location.x,location.y)else nil)
            end
            if matches("selectAllWarships")then warships:key(Enum.KeyCode.F,false)end
            if matches("requestAlliance")then diplomacy:key(Enum.KeyCode.K,mousePosition)end
            if matches("breakAlliance")then diplomacy:key(Enum.KeyCode.L,mousePosition)end
            if matches("pauseGame")then send("Pause")end
            if matches("gameSpeedUp")then send("GameSpeed",{action="Up"})end
            if matches("gameSpeedDown")then send("GameSpeed",{action="Down"})end
            local increment=preferences:get("attackRatioIncrement")
            if matches("attackRatioDown")then changeRatio(-increment)end
            if matches("attackRatioUp")then changeRatio(increment)end
            if matches("swapDirection")then cities:key(Enum.KeyCode.U,mousePosition)end
            if code=="KeyD"and shift then preferences:set("performanceOverlay",not preferences:get("performanceOverlay"))end
            if matches("toggleView")then
                setAlternateView(false)
            end
            local held={};for _,key in UserInputService:GetKeysPressed()do held[InputBindings.code(key.KeyCode)]=true end
            local resetAllowed=InputBindings.resetAllowed(bindings.altKey,{altKey=held.AltLeft==true or held.AltRight==true,ctrlKey=held.ControlLeft==true or held.ControlRight==true,shiftKey=shift,metaKey=held.MetaLeft==true or held.MetaRight==true},held)
            if matches("resetGfx")and resetAllowed and applyGraphics then applyGraphics()end
            local build=InputBindings.build(code,shift,bindings)
            if build and not (bindingDown("boxSelectWarships")and (warshipBox~=nil or warships.single~=nil or #warships.selected>0))then cities:key(build,mousePosition)end
            return
        end
        if warshipBox and (event==warshipBox or event.UserInputType == Enum.UserInputType.MouseButton1) then
            local longPress=gesture and gesture.longPress;ui.pressRingHide()
            activeTouches[event]=nil
            gesture=nil
            warshipBox = nil
            if not warships:finishBox(point(event.Position)) and not longPress then
                if event.UserInputType==Enum.UserInputType.Touch then
                    if not warships:click(point(event.Position),true) then openRadial(point(event.Position)) end
                else selectAt(point(event.Position)) end
            end
            return
        end
        if activeTouches[event] and pinching then
            pinching = false
            gesture = nil
            activeTouches = {}
            warshipBox=nil
            warships:cancelBox()
        end
        activeTouches[event] = nil
        if event == sliderGesture or (sliderGesture and event.UserInputType == Enum.UserInputType.MouseButton1
            and sliderGesture.UserInputType == Enum.UserInputType.MouseButton1) then sliderGesture = nil end
        if event.UserInputType == Enum.UserInputType.MouseButton2 and isMapPointer(point(event.Position)) then
            openRadial(point(event.Position))
            return
        end
        if not gesture then return end
        if event == gesture.input or (event.UserInputType == Enum.UserInputType.MouseButton1
            and gesture.input.UserInputType == Enum.UserInputType.MouseButton1) then
            local completed = gesture
            gesture = nil
            completed.touchLongPressPending=false;ui.pressRingHide()
            if not isMapPointer(point(event.Position)) or diplomacy.panel.Visible or diplomacy.emojiMenu.Visible then return end
            if completed.longPress then return end
            local delta = point(event.Position) - completed.origin
            local isClick = math.abs(delta.X) + math.abs(delta.Y) < DRAG_THRESHOLD
            if isClick and not completed.moved and not pinching and not overResult(point(event.Position)) then
                if event.UserInputType == Enum.UserInputType.Touch and canPlay() then
                    if cities.ghostActive then selectAt(point(event.Position))
                    elseif not warships:click(point(event.Position),true) and not W0.tapSend(point(event.Position)) then openRadial(point(event.Position)) end
                elseif preferences:get("leftClickOpensMenu")and not cities.ghostActive and snapshot and snapshot.state.phase~="Choosing"and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))then
                    openRadial(point(event.Position))
                else
                    selectAt(point(event.Position))
                end
            end
        end
    end)
    UserInputService.InputBegan:Connect(function(event: InputObject,processed: boolean)
        if event.UserInputType==Enum.UserInputType.Keyboard or event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then audio:userGesture()end
        -- Tester round 2026-10-13: a tap or click proves the window has focus. A missed WindowFocused (mobile) left
        -- `focused` false: every HUD button blocked and taps on the map refused while the aim still showed.
        if not focused and (event.UserInputType==Enum.UserInputType.Touch or event.UserInputType==Enum.UserInputType.MouseButton1) then focused=true;cities:refreshBlueprints();modalBlocked() end
        if cosmeticShop and cosmeticShop:isBlocking() then
            if event.KeyCode==Enum.KeyCode.Escape then cosmeticShop:handleEscape()end
            return
        end
        if settingsMenu and settingsMenu:handleInput(event)then return end
        if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
        if event.KeyCode==Enum.KeyCode.Escape then
            if variantHUD and variantHUD:handleEscape()then return end
            if M13.menu and M13.menu:handleEscape()then return end
            if renderDebug and renderDebug:handleEscape()then return end
            if settingsMenu and settingsMenu:handleEscape()then return end
            if lobby and lobby:handleEscape()then return end
            if atlasMenu and atlasMenu:handleEscape()then return end
            if leaderboard:handleEscape()then return end
        end
        if event.KeyCode~=Enum.KeyCode.ButtonB and quickChat and quickChat:key(event.KeyCode)then return end
        if modalBlocked()then return end
        -- Ashton 2026-10-07: Tab shows/hides the leaderboard in a match (Roblox's player list is off).
        if event.KeyCode==Enum.KeyCode.Tab and gameUI.Visible then leaderboard:togglePlayerStats();return end
        if event.UserInputType==Enum.UserInputType.Keyboard and (event.KeyCode==Enum.KeyCode.Escape or event.KeyCode==Enum.KeyCode.Return or event.KeyCode==Enum.KeyCode.KeypadEnter)and diplomacy:key(event.KeyCode,mousePosition)then return end
        if event.KeyCode==Enum.KeyCode.Escape then
            local closingGhostOrBox=cities.ghostActive or warshipBox~=nil
            cities:key(event.KeyCode,mousePosition);warships:cancelBox();warshipBox=nil
            if not closingGhostOrBox then warships:clearSelection()end
            radial.Visible=false;radialTarget=nil;return
        end
        if not rendererReady or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()or event.UserInputType~=Enum.UserInputType.Keyboard then return end
        local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        local code=InputBindings.code(event.KeyCode);local bindings=preferences:keybinds(false)
        if processed then
            -- UIOnlyController sinks avatar movement. Still track map pan keys;
            -- text focus, menus and game modals were rejected above.
            if code==bindings.moveUp or code==bindings.moveDown or code==bindings.moveLeft or code==bindings.moveRight
                or code=="ArrowUp"or code=="ArrowDown"or code=="ArrowLeft"or code=="ArrowRight"then heldKeys[code]=true end
            return
        end
        if InputBindings.matches(code,shift,bindings.toggleView)then setAlternateView(true)end
        if InputBindings.matches(code,shift,bindings.coordinateGrid)then coordinateGrid=not coordinateGrid;renderer:setGridView(coordinateGrid)end
        local browserZoom=(UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta))
            and (code=="Minus"or code=="Equal"or code=="NumpadAdd"or code=="NumpadSubtract")
        if not browserZoom then heldKeys[code]=true end
        if code==bindings.boxSelectWarships then cities:clearGhost()end
        if event.KeyCode==Enum.KeyCode.Return or event.KeyCode==Enum.KeyCode.KeypadEnter then cities:key(event.KeyCode,mousePosition)end
    end)
    RunService.RenderStepped:Connect(function()
        MatchController.frameSerial+=1;MatchController.runDeferred() -- the last packet's HUD stages (PF020)
        if rendererReady then
            local stage=MatchController.drawStage -- PF020: each draw stage guarded (see drawStage)
            stage("PF.Draw.Transform",transformCommitter.commit,transformCommitter)
            if renderer.drawGraphics then stage("PF.Draw.Graphics",renderer.drawGraphics,renderer,tileSize,viewport,snapshot.state)end
            local stageStarted = Performance.start()
            debug.profilebegin("OpenFront.TerritoryDisplay")
            stage("PF.Draw.Highlight",renderer.setHighlightOwner,renderer,hoveredOwner)
            stage("PF.Draw.BuildingHighlight",cities.buildings.setHighlightOwner,cities.buildings,hoveredOwner)
            -- PF020 (Ashton: no console crosshair): on a controller the targeted tile (screen
            -- centre) carries the subtle Highlight outline; the targeted territory keeps its hover.
            do
                local target=if gamepadInput and gamepadInput.gamepad and gameUI.Visible and not result.Visible then targetAt(viewport.AbsolutePosition+viewport.AbsoluteSize/2) else nil
                if target then
                    local side=math.max(tileSize,6);local x,y=(target-1)%mapWidth,(target-1)//mapWidth
                    highlight.Position=UDim2.fromOffset((x+.5)*tileSize-side/2,(y+.5)*tileSize-side/2);highlight.Size=UDim2.fromOffset(side,side)
                end
                if highlight.Visible~=(target~=nil) then highlight.Visible=target~=nil end
            end
            stage("PF.Draw.Territory",renderer.advance,renderer,snapshot.state.phase)
            if stageStarted and math.floor(stageStarted*4)~=gui:GetAttribute("ProfileDisplayQuarter") then
                gui:SetAttribute("ProfileDisplayQuarter",math.floor(stageStarted*4))
                local oldest=0
                for _,arrived in renderer.bucketStarted do oldest=math.max(oldest,os.clock()-arrived) end
                workspace:SetAttribute("OpenFrontDisplayPending",renderer.pendingTileCount)
                workspace:SetAttribute("OpenFrontDisplayOldestMs",oldest*1000)
                local queued=math.max(0,(renderer.paintTail or 0)-(renderer.paintHead or 1)+1)
                local initial=if renderer.fullPaintCursor then math.max(0,mapWidth*mapHeight-renderer.fullPaintCursor+1) else 0
                viewport:SetAttribute("RepaintQueued",queued)
                viewport:SetAttribute("RepaintInitialRemaining",initial)
                viewport:SetAttribute("RepaintPending",queued+initial)
            end
            debug.profileend()
            Performance.finish("client.territoryDisplay", stageStarted)
            stageStarted = Performance.start()
            stage("PF.Draw.Names",names.draw,names,tileSize,viewport,world,hoveredOwner,mousePosition)
            if snapshot.state.phase=="Choosing" then stage("PF.Draw.Spawn",ui.spawnView.draw,ui.spawnView,tileSize,if mousePosition then targetAt(mousePosition) else nil) end
            stage("PF.Draw.PrefView",preferenceView.draw,preferenceView,tileSize)
            Performance.finish("client.namesDraw", stageStarted)
            stageStarted = Performance.start()
            local previewPosition=if gamepadInput and gamepadInput.gamepad then viewport.AbsolutePosition+viewport.AbsoluteSize/2 else mousePosition
            stage("PF.Draw.Cities",cities.draw,cities,tileSize,viewport,previewPosition)
            Performance.finish("client.citiesDraw", stageStarted)
            stageStarted = Performance.start()
            local drawStarted=Performance.start()
            stage("PF.Draw.Naval",naval.draw,naval,tileSize,viewport)
            Performance.finish("client.navalDraw",drawStarted);drawStarted=Performance.start()
            stage("PF.Draw.Warships",warships.draw,warships,tileSize,viewport)
            Performance.finish("client.warshipsDraw",drawStarted);drawStarted=Performance.start()
            stage("PF.Draw.Industry",industry.draw,industry,tileSize,viewport,hoveredOwner)
            Performance.finish("client.industryDraw",drawStarted);drawStarted=Performance.start()
            stage("PF.Draw.Weapons",weapons.draw,weapons,tileSize,viewport)
            Performance.finish("client.weaponsDraw",drawStarted);drawStarted=Performance.start()
            stage("PF.Draw.Stock",stock.draw,stock,tileSize,viewport)
            Performance.finish("client.stockDraw",drawStarted)
            if variantHUD then stage("PF.Draw.VariantHUD",variantHUD.draw,variantHUD) end
            Performance.finish("client.shipsDraw", stageStarted)
        end
    end)
    RunService.Heartbeat:Connect(function(dt: number)
        snapshotRecovery:retry()
        local phase=snapshot and snapshot.state.phase
        local running=gameUI.Visible and phase~=nil and snapshot.paused~=true and not result.Visible and phase~="Choosing" and phase~="Won" and phase~="Lost" and phase~="Cancelled"
        stall:check(running)
        if running then stall:surface(snapshotRecovery:recovering(),showNotice,stall.leave) end
        local blocked=modalBlocked() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()~=nil or not focused
        if blocked then
            heldKeys={};gesture=nil;sliderGesture=nil;warshipBox=nil
            if warships then warships:cancelBox() end
            if diplomacy then diplomacy:hoverAt(nil) end
        end
        if gamepadInput then gamepadInput:step(dt) end
        if not rendererReady or not focused or not snapshot or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox()or modalBlocked()then
            keyboardElapsed = 0
            return
        end
        -- InputHandler.ts:604-656 requests a 1ms repeating browser timer.
        -- HTML timer initialization step5 clamps repeating timers to >=4ms after
        -- nesting>5. Roblox batches these exact 5px/10-unit steps per Heartbeat;
        -- browser scheduling/device timing is still a platform adaptation.
        keyboardElapsed += dt
        local steps = math.floor(keyboardElapsed / 0.004)
        keyboardElapsed -= steps * 0.004
        local function down(key: Enum.KeyCode): boolean return heldKeys[InputBindings.code(key)]==true end
        if not bindingDown("boxSelectWarships")then
            local x = (if bindingDown("moveLeft") or down(Enum.KeyCode.Left) then 5 else 0)
                - (if bindingDown("moveRight") or down(Enum.KeyCode.Right) then 5 else 0)
            local y = (if bindingDown("moveUp") or down(Enum.KeyCode.Up) then 5 else 0)
                - (if bindingDown("moveDown") or down(Enum.KeyCode.Down) then 5 else 0)
            local zoomOut = bindingDown("zoomOut") or down(Enum.KeyCode.Minus) or down(Enum.KeyCode.KeypadMinus)
            local zoomIn = bindingDown("zoomIn") or down(Enum.KeyCode.Equals) or down(Enum.KeyCode.KeypadPlus)
            if x ~= 0 or y ~= 0 or zoomOut or zoomIn then
                initialFitPending = false
                setCameraTarget(nil)
                local center = viewport.AbsolutePosition + viewport.AbsoluteSize / 2
                for _ = 1, steps do
                    offset += Vector2.new(x, y)
                    applyTransform()
                    if zoomOut then zoomDelta(10, center) end
                    if zoomIn then zoomDelta(-10, center) end
                end
            end
        end
        if cameraTarget then
            cameraElapsed += dt
            if cameraElapsed >= 0.016 then
                local now = os.clock()
                local callDt = if lastCameraCall then now - lastCameraCall else 0.016
                lastCameraCall = now
                local complete
                offset, tileSize, complete = MapCamera.step(offset,tileSize,viewport.AbsoluteSize,cameraTarget,cameraTargetScale,callDt)
                if complete then setCameraTarget(nil)else applyTransform()end
                cameraElapsed = 0
            end
        end
    end)
    viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if ui.noticeUI.Visible then sizeNotice() end
        if snapshot then renderText(); leaderboard:layout(gameUI.AbsoluteSize) end
        if mapWidth == 0 then return end
        if initialFitPending then resetView(); return end
        if tileSize <= 0 then resetView(); return end
        local centerCell = (lastViewport / 2 - offset) / tileSize
        local size = viewport.AbsoluteSize
        offset = size / 2 - centerCell * tileSize
        applyTransform()
    end)
    ui.attacksUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if snapshot then layoutHUD() end
    end)
    UserInputService.WindowFocusReleased:Connect(function()
        focused = false
        heldKeys={};setAlternateView(false);warshipBox=nil;warships:cancelBox()
        gesture = nil
        pinching = false
        activeTouches = {}
        sliderGesture = nil
        cities:refreshBlueprints();modalBlocked()
    end)
    UserInputService.WindowFocused:Connect(function() focused = true;cities:refreshBlueprints();modalBlocked() end)
    GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
        if not GuiService.MenuIsOpen then return end
        gesture = nil
        pinching = false
        activeTouches = {}
        sliderGesture = nil
        setCameraTarget(nil)
        keyboardElapsed = 0
    end)
    highlight.Visible = false
    result.Visible = false
    radial.Visible = false
    ui.dev.Visible = false
    ui.noticeUI.Visible = false
    ui.mapError.Visible = false
    ui.headsUp.Visible = false
    gui:SetAttribute("OpenFrontMatchReady", false)
    ui.hint.Text = "Connecting to the match…"
    snapshotRecovery:requestReady()
    -- tester round 2026-10-13: the match's images warm in the background (map layer, HUD, templates); never blocks Ready
    require(script.Parent.MatchWarmup).start({ui.panel, gameUI, gameUI:FindFirstChild("Templates") or gameUI})
    -- "Joining your match" (Ashton 2026-10-14): on a match server the authored Background.PFJoining covers boot until the
    -- match's first drawn frame (connecting → map → ready, then a fade); hubs never show it
    ui.joining = require(script.Parent.JoiningView).new(gui, {ready = function() return rendererReady and gameUI.Visible and snapshot ~= nil end,
        state = function() return snapshot and snapshot.state end})
    -- Roadmap #1 (PF - 1): daily challenges in the match (a notice per finished challenge) and on the end card (DailyView)
    pcall(function()
        local daily = require(script.Parent.DailyView)
        daily.attachMatch(function() return diplomacy end)
        require(script.Parent.FeedNotices).attach(function() return diplomacy end) -- PF045: a feed line for every match sound
        daily.endCard(result, function() return require(script.Parent.PF026EndScreen)._state().matchId end)
    end)
    task.spawn(function()
        while not snapshot and not homeReady do
            task.wait(1)
            if not snapshot then snapshotRecovery:requestReady() end
        end
    end)
    task.spawn(function()
        while gui.Parent do task.wait(5);if snapshot and snapshot.online==true then remotes.Command:FireServer({kind="Heartbeat"})end end
    end)
end

return MatchController
