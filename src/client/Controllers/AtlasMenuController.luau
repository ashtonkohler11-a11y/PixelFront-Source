--!strict
-- Shared authored menu shell. Backend ownership remains in existing controllers.
-- PF015: the shell's geometry (one 58px topbar row of brand, tabs and profile;
-- pages under it; backdrop/ambient/header bleeding into the device's unsafe
-- strips) is AUTHORED in the place by tools/atlas/author-pf015-menus.luau.
-- This module only fills content and visibility; it never sizes the shell.
local Players=game:GetService("Players")
local Input=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Theme=require(Shared.AtlasTheme)
local Typography=require(Shared.PixelFrontTypography)
local PlayPage=require(script.Parent.AtlasPlayPage)
local Parts=require(script.Parent.LobbyScreenParts) -- PF044 r5: header hit boxes (Parts.taps)
local TopbarLine=require(script.Parent.TopbarLine) -- PF044 r5: clear Roblox's top-bar pill
local CommercePage=require(script.Parent.AtlasCommercePage)
local StatsPage=require(script.Parent.AtlasStatsPage)
local StatsModel=require(script.Parent.AtlasStatsModel)
local ProfileArt=require(script.Parent.AtlasCommerceArt)
local AmbientScene=require(script.Parent.AtlasAmbientScene)
local MenuMotion=require(script.Parent.AtlasMenuMotion)
local NavIcons=require(script.Parent.AtlasNavIcons)
local CardKit=require(script.Parent.LobbyCardKit) -- PF019: one card kit for every lobby box
local AccentFocus=require(script.Parent.LobbyAccentFocus) -- PF019 (PF - 3): the accent drives lobby focus visuals only
local LockedShop=require(script.Parent.LockedShop) -- PF019 M13b (PF - 2): the shop over a live match
local PlateView=require(script.Parent.AtlasProfilePlate) -- PF023 P1 (PF - 1): the top-right profile plate
local Routes=require(script.Parent.LobbyRoutes) -- PF025 (PF - 3): openPass for the Settings VIP box
local ModalGuard=require(script.Parent.ModalGuard) -- a shown sheet keeps the gamepad focus (focusActive)
-- PF019 full-screen flows live in the authored AtlasMenu.Screens (author-pf019-screens): one child
-- per flow, each driven by its own page module. While one is open the Header and Pages hide and
-- the battlefield keeps playing behind. A flow appears only once its node AND module both exist.
local SCREEN_MODULES={Join="AtlasJoinPage", -- PF - 1 (M12)
    Solo="AtlasSoloScreen",Create="AtlasCreateScreen",Room="AtlasRoomScreen",MapPicker="AtlasMapPicker", -- PF - 3 (M4/M9)
    Profile="AtlasProfileScreen", -- PF023 P1 (PF - 1): the plate's tap: your equipped look, one tap per slot
    Joined="AtlasJoinedScreen"} -- PF024 J1 (PF - 3): a member of someone else's custom room (the host keeps Room)
local Controller={};Controller.__index=Controller
-- PF020: the owned pass card's way back to the lobby flow its tag came from
local RETURN_WORDS={Create="Back to Create",Room="Back to your room",Join="Back to Join",Solo="Back to Solo"}
-- the nav tabs; a place without the authored Levels tab (author-pf023-levels-tab) keeps the first five
local GOLD_LABEL=Color3.fromHex("#f1cf7f") -- PF043 B3: the Shop tab's label
-- PIVOT 2026-10-23 (docs/director/PIVOT-2026-10-23.md): Levels are removed ("it adds more clutter and is hard to understand") and
-- the daily challenges with them, so the Levels and Daily tabs are retired: a place that still has them authored hides them.
local ALL_TABS={"Play","Stats","Shop","Inventory","Settings"}
local RETIRED_TABS={"Daily","Levels"}
local LEGACY_TABS={"Play","Stats","Shop","Inventory","Settings"}
local function listen(self,signal,callback)table.insert(self.connections,signal:Connect(callback))end
function Controller.new(gui: ScreenGui,hooks: any): any
    local root=assert(gui.Background:FindFirstChild("AtlasMenu"),"Missing authored AtlasMenu")
    local self=setmetatable({gui=gui,root=root,header=root.Header,pages=root.Pages,hooks=hooks,connections={},page="Play",visible=false,stats=StatsModel.new()},Controller)
    self.profileRoot=self.header:FindFirstChild("Profile",true)
    self.navigation=self.header:FindFirstChild("Navigation",true)
    self.names={}
    for _,name in ALL_TABS do if self.navigation and self.navigation:FindFirstChild(name) and root.Pages:FindFirstChild(name) then table.insert(self.names,name) end end
    for _,name in RETIRED_TABS do
        for _,node in {self.navigation and self.navigation:FindFirstChild(name),root.Pages:FindFirstChild(name)} do if node and node:IsA("GuiObject") then node.Visible=false end end
    end
    local player=Players.LocalPlayer
    self.cardKit=CardKit.new(root)
    -- PF044 r5 (PF - 3; MM 2026-10-24): a Screens label that can't fit at its text floor first takes its shorter text
    -- (PFShortText, e.g. "+ Create"), then, if it still can't, steps aside (PFFloorHide). Static labels only (the text
    -- at load is the full one); checked again whenever the label's box changes size.
    local screensRoot=root:FindFirstChild("Screens")
    if screensRoot then for _,label in screensRoot:GetDescendants() do
        if not (label:IsA("TextLabel") and (label:GetAttribute("PFShortText") or label:GetAttribute("PFFloorHide"))) then continue end
        local full,short,base=label.Text,label:GetAttribute("PFShortText"),label.TextTransparency
        local function fit()
            label.Text=full;label.TextTransparency=base
            task.defer(function()
                if label.TextFits then return end
                if typeof(short)=="string" then label.Text=short end
                task.defer(function() if not label.TextFits and label:GetAttribute("PFFloorHide") then label.TextTransparency=1 end end)
            end)
        end
        table.insert(self.connections,label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit));fit()
    end end
    -- PF044 r5 (MM 2026-10-24): the top-left cluster stays right of Roblox's top-bar pill (GuiService.TopbarInset), and a
    -- left column that starts under the pill starts below it (TopbarLine: the one sanctioned runtime position)
    local homeRoot=root:FindFirstChild("PFHome")
    for _,name in {"TopLeft","PFTopHits"} do local node=homeRoot and homeRoot:FindFirstChild(name);if node and node:IsA("GuiObject") then TopbarLine.keepRight(node,self.connections) end end
    if screensRoot then
        for _,name in {"Solo","Create","Room","MapPicker","Join"} do
            local screen=screensRoot:FindFirstChild(name);if not screen then continue end
            local header=Parts.find(screen,"Header")
            local first=if name=="Join" then header and Parts.find(header,"LeftGroup") else header
            if first and first:IsA("GuiObject") then TopbarLine.keepRight(first,self.connections) end
            local body=screen:FindFirstChild("Body");local left=body and name~="Join" and name~="MapPicker" and Parts.find(body,"Left")
            if left and left:IsA("GuiObject") then TopbarLine.clearBelow(left,self.connections) end
        end
    end
    -- PF019 (MM 2026-10-06): lobby selection is fixed cobalt; the interface accent drives only the focus
    -- visuals ("focus"-role tags, cloned rows included). The kit keeps its gold selected ring.
    local selection=game:GetService("ReplicatedStorage"):FindFirstChild("PFLobbySelection") -- the gamepad selection ring (author-pf019-selection)
    self.accentFocus=AccentFocus.bind(root,hooks.settings and hooks.settings.settings,if selection then {selection} else nil)
    if self.accentFocus then self.accentFocus.subscribe(function() self.cardKit:accentChanged() end) end
    local common={theme=Theme,menuRoot=root,backgroundRoot=gui.Background,cardKit=self.cardKit,
        navigate=function(name)self:navigate(name)end,
        reducedMotion=function()return root:GetAttribute("ReducedMotion")==true end,
        getIdentity=function()return {userId=player.UserId,displayName=player.DisplayName,name=player.Name}end,
        getLooks=function()return hooks.shop.looks end,
        getProfile=function()return hooks.shop.profile end,
        applyProfile=function(row,identity)ProfileArt.bindProfile(row,identity)end}
    self.ambientRoot=assert(root:FindFirstChild("Ambient"),"Missing authored shared Atlas ambient layer")
    self.ambient=AmbientScene.new(self.ambientRoot,common)
    self.settingsSurfaces={}
    local settingsUI=gui.Background:FindFirstChild("UserSettings")
    self.settingsUI=settingsUI
    local motionExtras={}
    for _,name in {"UserSettings","SettingsConfirm","SettingsJSON"}do
        local panel=gui.Background:FindFirstChild(name)
        if panel and panel:IsA("GuiObject")then table.insert(motionExtras,panel)end
    end
    self.motion=MenuMotion.new(root,{extraRoots=motionExtras})
    if settingsUI then
        local surfaces={settingsUI};for _,v in settingsUI:GetDescendants()do table.insert(surfaces,v)end
        for _,v in surfaces do if v:IsA("GuiObject")and type(v:GetAttribute("AtlasMenuTransparency"))=="number"then self.settingsSurfaces[v]=v.BackgroundTransparency end end
    end
    local play=table.clone(common)
    play.thumbnailSources=hooks.public.sources
    play.joinPublic=function(id)return hooks.public:joinPublic(id)end
    play.cancelPublic=function()hooks.public:cancelPublic()end
    play.cancelJoin=play.cancelPublic;play.leaveLobby=play.cancelPublic
    play.refreshQueues=function()hooks.public:refreshQueues()end
    play.solo=function()self:hide();hooks.solo()end
    play.createLobby=function(config,roomName)return hooks.createLobby(config,roomName)end
    play.joinLobby=function(code)return hooks.joinLobby(code)end
    play.startPrivate=function()return hooks.startPrivate()end
    play.openScreen=function(name)return self:openScreen(name)end
    self.play=PlayPage.new(self.pages.Play,play)
    -- PF019 Screens. The facade calls go through closures (PF - 2's W6 contract, PublicLobbyController).
    self.screensRoot=root:FindFirstChild("Screens");self.screenPages={};self.screen=nil
    if self.screensRoot then
        local screenContext=table.clone(common)
        screenContext.thumbnailSources=hooks.public.sources
        screenContext.back=function()self:closeScreen()end
        -- PF019 (PF - 3): the lobby screens' shared pieces
        screenContext.templates=self.screensRoot:FindFirstChild("PFTemplates")
        screenContext.mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps")
        screenContext.preferences=hooks.settings and hooks.settings.settings -- per-player store (map favourites)
        screenContext.getStats=function()return self.stats and self.stats:view()end -- PF - 3 map picker v2: your wins / played per map
        screenContext.openScreen=function(name)return self:openScreen(name)end
        screenContext.openSlot=function(category)self:openSlot(category)end -- PF023 P1: a Profile slot -> its Inventory tab
        screenContext.openStats=function() -- PF - 3 Profile v2: Stats ›
            if self.destroyed or self.locked then return end
            self:closeScreen();self:navigate("Stats")
        end
        screenContext.getCommerce=function()return hooks.shop:getState()end
        -- PF020 G8: a gold "Lobby Host+" tag opens the Shop (the Passes tab shows once CommerceFlags.passesVisible).
        -- PF020 (MM): a lobby flow's pass tag opens the Shop on that pass (the Passes tab, its card in
        -- view); once the pass is yours, the card's key offers the way back to the flow (passReturn).
        screenContext.openPass=function(passId)
            local from=self.screen
            -- set first: show() refreshes the lobby, which would otherwise hand a room host straight back
            self.passReturn=if from then {screen=from,passId=passId,words=RETURN_WORDS[from] or "Back"} else nil
            self:closeScreen();self:show("Shop")
            self:updateCommerce()
            if self.commerce.showPass then self.commerce:showPass(passId) end
        end
        Routes.openPass=screenContext.openPass -- PF025: the Settings VIP box opens a pass's Shop card
        -- PF020 G8: a pass is on sale once Ashton gives it a real Game Pass ID (passId 0 = "--", disabled).
        screenContext.passOnSale=function(passId)
            local Catalog=require(Shared.CosmeticCatalog)
            local pass=Catalog.passById and Catalog.passById[passId]
            return pass~=nil and type(pass.passId)=="number" and pass.passId>0
        end
        screenContext.openPicker=function(current,callback)
            local picker=self.screenPages.MapPicker;local from=self.screen
            if not picker then callback(nil);return end
            self:openScreen("MapPicker")
            picker:open(current,function(map)
                callback(map)
                if from and self.screenPages[from] then self:openScreen(from) else self:closeScreen() end
            end)
        end
        screenContext.startSolo=function(config)
            self:hide()
            if hooks.soloStart then hooks.soloStart(config) else hooks.solo() end
        end
        screenContext.facade={
            refresh=function()return hooks.public:refresh()end,
            joinLobby=function(id)return hooks.public:joinLobby(id)end,
            joinCode=function(code)return hooks.public:joinCode(code)end,
            cancel=function()return hooks.public:cancel()end,
            createLobby=function(settings,options)return hooks.public:createLobby(settings,options)end,
            updateLobby=function(patch)return hooks.public:updateLobby(patch)end,
            startLobby=function()return hooks.public:startLobby()end,
            leaveLobby=function()return hooks.public:leaveLobby()end,
            lockLobby=function(locked)return hooks.public:lockLobby(locked)end, -- PF020 G8 Lobby Host+
            kickMember=function(userId)return hooks.public:kickMember(userId)end,
            invite=function()return hooks.public:invite()end,
            getState=function()return hooks.public:getState()end}
        for name,moduleName in SCREEN_MODULES do
            local node,module=self.screensRoot:FindFirstChild(name),script.Parent:FindFirstChild(moduleName)
            if node and module then
                local ok,result=pcall(function()return (require(module) :: any).new(node,screenContext)end)
                if ok then self.screenPages[name]=result;result:setVisible(false) else warn("[AtlasMenu] "..name.." screen unavailable: "..tostring(result))end
            end
        end
        self.screensRoot.Visible=false
    end
    -- PF024 J2 (PF - 3): the public queue is a dock over the lobby, not a screen: the player keeps browsing. It floats on
    -- top (Background.PFQueue since author-pf024-lobby v7; AtlasMenu.PFQueue before) and never moves a page.
    local queueRoot=root:FindFirstChild("PFQueue") or (root.Parent and root.Parent:FindFirstChild("PFQueue"))
    local dockModule=script.Parent:FindFirstChild("AtlasQueueDock")
    if queueRoot and dockModule then
        local joined=self.screensRoot and self.screensRoot:FindFirstChild("Joined")
        local templates=joined and joined:FindFirstChild("Templates")
        local ok,dock=pcall(function()return (require(dockModule) :: any).new(queueRoot,{reducedMotion=common.reducedMotion,
            mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps"),
            pipTemplate=templates and templates:FindFirstChild("Pip"),facade={leaveLobby=function()return hooks.public:leaveLobby()end}})end)
        if ok then self.dock=dock else warn("[AtlasMenu] queue dock unavailable: "..tostring(dock))end
    end
    -- PF043 (PF - 3): "Match found · joining 3" over the hub in a public match's last 3 s; tap = go now, ✕ = cancel
    -- (tools/atlas/author-pf043-match-found.luau; inert until Background.PFMatchFound is authored)
    local foundRoot=root.Parent and root.Parent:FindFirstChild("PFMatchFound")
    local foundModule=script.Parent:FindFirstChild("MatchFoundView")
    if foundRoot and foundModule then
        local ok,view=pcall(function()return (require(foundModule) :: any).new(foundRoot,{reducedMotion=common.reducedMotion,
            mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps"),
            facade={goNow=function()return hooks.public:goNow()end,leaveLobby=function()return hooks.public:leaveLobby()end}})end)
        if ok then self.matchFound=view else warn("[AtlasMenu] match found unavailable: "..tostring(view))end
    end
    -- PF043 B4 (PF - 3): Nameplate in Your look: the tile, the IN MATCH name's style and the picker
    -- (tools/atlas/author-pf043-nameplate.luau; inert until Background.PFNameplatePicker is authored)
    do
        local pickerRoot=root.Parent and root.Parent:FindFirstChild("PFNameplatePicker")
        local identity=self.pages.Inventory:FindFirstChild("PFNameplate",true)
        local pickerModule=script.Parent:FindFirstChild("NameplatePicker")
        if pickerRoot and identity and pickerModule then
            local inMatch=identity.Parent and identity.Parent:FindFirstChild("PFMatch")
            local matchName=inMatch and inMatch:FindFirstChild("PlayerName",true) -- the IN MATCH strip's name (not the profile card's)
            local ok,picker=pcall(function()return (require(pickerModule) :: any).new({tile=identity,inMatch=matchName,root=pickerRoot},{
                remotes=require(game:GetService("ReplicatedStorage").Shared.Remotes).client(),reducedMotion=common.reducedMotion,
                openPass=function(passId)if Routes.openPass then Routes.openPass(passId)end end})end)
            if ok then
                self.nameplate=picker
                Routes.openNameplate=function()self:show("Inventory");picker:setOpen(true)end -- the pass card's Choose style
            else warn("[AtlasMenu] nameplate picker unavailable: "..tostring(picker))end
        end
    end
    -- PF036 (PF - 3): the Party button left of the plate, its card, a friend's invite and the queue's party marks
    -- (tools/atlas/author-pf036-parties.luau). The leader picks the match; the Play page shows members "Leader picks".
    local partyLayer=root:FindFirstChild("PFPartyLayer")
    local partyButton=self.header:FindFirstChild("PFParty",true)
    local partyModule=script.Parent:FindFirstChild("AtlasPartyPanel")
    if partyLayer and partyButton and partyModule then
        local pill=queueRoot and queueRoot:FindFirstChild("Pill")
        local ok,panel=pcall(function()return (require(partyModule) :: any).new({button=partyButton,card=partyLayer.Card,pointer=partyLayer.Pointer,
            notice=partyLayer:FindFirstChild("Notice") or (root:FindFirstChild("PFHome") and root.PFHome:FindFirstChild("PFPartyNotice",true)), -- PF044: under the home Party card
            tab=queueRoot and queueRoot:FindFirstChild("PFPartyTab"),pillStack=pill and pill:FindFirstChild("PFPartyStack"),
            friends=root:FindFirstChild("PFInvite")}, -- PF - 5 Invite friends (tools/atlas/author-pf5-main.luau)
            {facade={partyOpen=function()return hooks.public:partyOpen()end,partyJoin=function(code)return hooks.public:partyJoin(code)end,
                partyLeave=function()return hooks.public:partyLeave()end,partyKick=function(id)return hooks.public:partyKick(id)end,
                partyInvite=function()return hooks.public:partyInvite()end,dismissPartyInvite=function()return hooks.public:dismissPartyInvite()end,
                partyInviteFriend=function(id,inGame,onSent)return hooks.public:partyInviteFriend(id,inGame,onSent)end}})end)
        if ok then self.party=panel else warn("[AtlasMenu] party panel unavailable: "..tostring(panel))end
    end
    -- PF036 (PF - 3): the rejoin banner (tools/atlas/author-pf036-rejoin.luau): Play's heading slot, or the phone strip
    local playContent=self.pages.Play:FindFirstChild("ContentScroll") and self.pages.Play.ContentScroll:FindFirstChild("Content")
    local rejoinModule=script.Parent:FindFirstChild("AtlasRejoinBanner")
    if playContent and playContent:FindFirstChild("PFRejoin") and playContent:FindFirstChild("PFRejoinStrip") and rejoinModule then
        local ok,banner=pcall(function()return (require(rejoinModule) :: any).new({desk=playContent.PFRejoin,strip=playContent.PFRejoinStrip,menu=root,
            mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps")},
            {facade={rejoin=function()return hooks.public:rejoin()end,dismissRejoin=function()return hooks.public:dismissRejoin()end}})end)
        if ok then self.rejoinBanner=banner else warn("[AtlasMenu] rejoin banner unavailable: "..tostring(banner))end
    end
    -- PF036 (PF - 3): the group reward tile (tools/atlas/author-pf036-group.luau): under Solo, or first in the phone's daily strip;
    -- hidden while no group is configured (Catalog.groupReward.groupId 0)
    do
        local strip=playContent and playContent:FindFirstChild("PFDailyStrip")
        local desk,inStrip=playContent and playContent:FindFirstChild("PFGroupTile"),strip and strip:FindFirstChild("PFGroupTile")
        -- PF043 B3: once the Daily tab is authored the reward lives on its page (one slot on every screen)
        local dailySlot=table.find(self.names,"Daily") and self.pages:FindFirstChild("Daily") and self.pages.Daily:FindFirstChild("PFGroupTile",true)
        if dailySlot then desk,inStrip=dailySlot,nil end
        local groupModule=script.Parent:FindFirstChild("AtlasGroupTile")
        if groupModule and (desk or inStrip) then
            local ok,tile=pcall(function()return (require(groupModule) :: any).new({desk=desk,strip=inStrip},{
                claim=function()hooks.shop.remotes.CosmeticsCommand:FireServer({kind="ClaimGroup"})end,
                reward=function(n) -- PF043: the group reward plays the reward drop
                    local okDrop,Drop=pcall(require,script.Parent.RewardDrop);local drop=okDrop and (Drop :: any).get(root:FindFirstAncestorOfClass("ScreenGui")) or nil
                    if drop and n>0 then drop:play({{kind="cobalt",amount=n,label="GROUP REWARD"}}) end
                end,
                phone=function()return inStrip~=nil and root.AbsoluteSize.Y>0 and root.AbsoluteSize.Y<=540 end})end) -- DailyView.PHONE
            if ok then self.groupTile=tile;listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function()tile:paint()end)
            else warn("[AtlasMenu] group tile unavailable: "..tostring(tile))end
        end
    end
    -- PF036 (PF - 3): Ranked v2: the Play page's Public | Ranked tabs, the 1v1 / 2v2 / FFA switch and the Ranked area
    -- (tools/atlas/author-pf036-ranked.luau; PF - 2's RankedState / RankedCommand)
    do
        local rankedModule=script.Parent:FindFirstChild("AtlasRankedPage")
        if rankedModule and playContent and playContent:FindFirstChild("PFRanked") then
            local ok,page=pcall(function()return (require(rankedModule) :: any).new(playContent,{menu=root,
                mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps")})end)
            if ok then self.rankedPage=page else warn("[AtlasMenu] ranked page unavailable: "..tostring(page))end
        end
    end
    local commerce=table.clone(common);commerce.inventoryRoot=self.pages.Inventory
    commerce.getCommerceState=function()return hooks.shop:getState()end
    commerce.getProductInfo=function()return hooks.shop.productInfo end
    commerce.purchase=function(id)hooks.shop:purchaseConfirmed(id)end
    commerce.equip=function(id,slot,target,inherit)hooks.shop:request({kind="Equip",itemId=id,slot=slot,target=target,inherit=inherit});require(script.Parent.Sfx).play("u_equip")end -- PF043 H
    commerce.refreshCommerce=function()hooks.shop.remotes.CosmeticsCommand:FireServer({kind="Ready"})end
    -- PF020 G6 (PF - 2): an owned pass card's action (Lobby Host+ -> Create Lobby; Animated Nameplate ->
    -- Settings' Premium tab). Never mid-match (the lobby stays hidden in locked mode).
    commerce.openScreen=function(name)
        if self.locked then return false end
        self:navigate("Play");return self:openScreen(name)
    end
    commerce.openSettingsTab=function(name)
        if self.locked or not hooks.settings then return end
        self:navigate("Settings");hooks.settings:setTab(name)
    end
    -- PF020 (MM): back to the lobby flow a pass tag came from (a room that ended meanwhile: Play)
    commerce.passReturn=function()return self.passReturn end
    commerce.returnToFlow=function()
        local back=self.passReturn;self.passReturn=nil
        if not back or self.locked then return end
        self:navigate("Play")
        if back.screen=="Room" and not hooks.public:getState().room then return end
        self:openScreen(back.screen)
    end
    self.commerce=CommercePage.new(self.pages.Shop,commerce)
    -- PF019 M13b (PF - 2): locked mode (nil until author-pf019-locked-shop has run).
    self.lockedShop=LockedShop.new(root,{back=function()self:closeLockedShop(true)end})
    -- PF043 F (PF - 1): the Shop's Free rewards row (tools/atlas/author-pf043-free-rewards.luau), the one daily claim place: the login
    -- streak + the VIP bonus, one Claim (it plays the reward drop); the Shop tab's dot lights while it's claimable
    do
        local content=self.commerce and self.commerce.shop
        local shopScroll=content and (content:FindFirstChild("Scroll") or (content:FindFirstChild("PFBody") and content.PFBody:FindFirstChild("Scroll")))
        local freeModule=script.Parent:FindFirstChild("FreeRewardsRow")
        if freeModule and shopScroll and (shopScroll:FindFirstChild("PFFreeRewards") or shopScroll:FindFirstChild("PFFreeRewardsPhone")) then
            local nav=self.header:FindFirstChild("Navigation",true);local shopTab=nav and nav:FindFirstChild("Shop")
            local ok,row=pcall(function()return (require(freeModule) :: any).new({desk=shopScroll:FindFirstChild("PFFreeRewards"),phone=shopScroll:FindFirstChild("PFFreeRewardsPhone"),
                offers=shopScroll:FindFirstChild("Offers"),dot=shopTab and shopTab:FindFirstChild("PFDailyDot")},{
                phone=function()return root.AbsoluteSize.Y>0 and root.AbsoluteSize.Y<=540 end,gui=root:FindFirstAncestorOfClass("ScreenGui"),
                command=function(p)hooks.shop.remotes.CosmeticsCommand:FireServer(p)end,getVip=function()hooks.shop:purchaseConfirmed("pass_vip")end,
                openStreak=function()local okView,View=pcall(require,script.Parent.DailyView);if okView and (View :: any).openStreak then (View :: any).openStreak() end end})end)
            if ok then self.freeRewards=row;listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function()row:paint()end)
            else warn("[AtlasMenu] free rewards unavailable: "..tostring(row))end
        end
    end
    -- PIVOT D12 (PF - 1; Ashton picked "A: Shelves"): the Shop's own top bar, PFShopTop (tools/atlas/author-pivot-arsenal.luau);
    -- nil until installed. 2026-10-26: the old Arsenal page (Pages.Shop.PFArsenal) is retired; the bar no longer needs it.
    do
        local arsenalModule=script.Parent:FindFirstChild("AtlasArsenalPage")
        if arsenalModule and root:FindFirstChild("PFShopTop") then
            local nav=self.header:FindFirstChild("Navigation",true);local shopTab=nav and nav:FindFirstChild("Shop")
            local ok,page=pcall(function()return (require(arsenalModule) :: any).new(root,{shopPage=self.pages.Shop,header=self.header,
                content=self.commerce and self.commerce.shop,remotes=hooks.shop.remotes,refreshCommerce=commerce.refreshCommerce,
                openCobalt=function()if self.commerce and self.commerce.selectCategory then self.commerce:selectCategory("Shop","Currency") end end, -- UX audit #6
                freeDot=shopTab and shopTab:FindFirstChild("PFDailyDot",true),back=function()self:shopBack()end, -- in a match: back to it
                openFree=function()local okView,View=pcall(require,script.Parent.DailyView);if okView and (View :: any).openStreak then (View :: any).openStreak() end end})end)
            if ok then self.arsenal=page else warn("[AtlasMenu] arsenal unavailable: "..tostring(page))end
        end
    end
    -- PIVOT Armory (PF - 1; Ashton 2026-10-25): AtlasMenu.PFArmory (tools/atlas/author-pivot-armory.luau), the premium showroom;
    -- the home's Armory key opens it, and so does the in-match Premium grid (openLockedShop {tab="Armory"}). nil until installed.
    do
        local armoryModule=script.Parent:FindFirstChild("AtlasArmoryPage")
        if armoryModule and root:FindFirstChild("PFArmory") then
            local ok,page=pcall(function()return (require(armoryModule) :: any).new(root,{remotes=hooks.shop.remotes,
                back=function()if self.locked then self:closeLockedShop(true) else self:navigate("Play") end end,
                play=function()if self.locked then self:closeLockedShop(true) else self:navigate("Play") end end,
                inMatch=function()return self.locked~=nil end,
                -- UX audit #6: the wallet's + lands on the Cobalt packs, not Discover
                openCobalt=function()if not self.locked then self:navigate("Shop");self.shopReturn="Armory";if self.commerce and self.commerce.selectCategory then self.commerce:selectCategory("Shop","Currency") end end end})end)
            if ok then self.armory=page else warn("[AtlasMenu] armory unavailable: "..tostring(page))end
        end
    end
    -- PF044 r5 (PF - 3; MM 2026-10-24): Inventory and Stats take the same top bar instead of the old nav (Back · title ·
    -- the page's note); tools/atlas/author-pf044-page-top.luau, nil until installed
    do
        local barModule=script.Parent:FindFirstChild("AtlasPageTop")
        if barModule and root:FindFirstChild("PFPageTop") then
            local statsHeader=self.pages.Stats:FindFirstChild("Header")
            local ok,bar=pcall(function()return (require(barModule) :: any).new(root,{header=self.header,back=function()self:navigate("Play")end,
                statsScope=statsHeader and statsHeader:FindFirstChild("Scope")})end)
            if ok then self.pageTop=bar else warn("[AtlasMenu] page top bar unavailable: "..tostring(bar))end
        end
    end
    local stats=table.clone(common);stats.getStats=function()return self.stats:view()end
    -- PF036: PF - 2's lifetime record (OpenFrontRemotes.StatsCommand, found lazily): Ready when the page opens (the server
    -- spaces it 2 s), the reply merges into the model (AtlasStatsModel.setLifetime)
    local function statsRemote(): RemoteEvent?
        local folder=game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontRemotes")
        local remote=folder and folder:FindFirstChild("StatsCommand")
        if remote and remote:IsA("RemoteEvent") and not self.statsHooked then
            self.statsHooked=true
            listen(self,remote.OnClientEvent,function(packet)
                if self.stats:setLifetime(packet) and self.visible and self.page=="Stats" then self.statsPage:update(self.stats:view()) end
                if type(packet)=="table" and packet.kind=="Leaderboard" then self.statsPage:setBoard(packet) end -- PF036
            end)
        end
        return if remote and remote:IsA("RemoteEvent") then remote else nil
    end
    stats.requestLifetime=function()
        if os.clock()-(self.lifetimeAsked or -math.huge)<2.5 then return end
        local remote=statsRemote();if remote then self.lifetimeAsked=os.clock();remote:FireServer({kind="Ready"}) end
    end
    -- PF036: the weekly top 10 (PF - 2's Leaderboard: 5 s server cooldown, tops cached a minute), asked when Stats opens
    stats.requestBoard=function()
        if os.clock()-(self.boardAsked or -math.huge)<30 then return end
        local remote=statsRemote();if remote then self.boardAsked=os.clock();remote:FireServer({kind="Leaderboard"}) end
    end
    stats.openScreen=function(name)return self:openScreen(name)end -- PF023 L3: "View reward track"
    self.statsPage=StatsPage.new(self.pages.Stats,stats)
    -- PF043 B3 (PF - 3): the Daily tab (tools/atlas/author-pf043-daily-tab.luau): today's three, All three, the weekly, the
    -- group reward and the login streak link, moved off the Play page
    if table.find(self.names,"Daily") then
        local dailyModule=script.Parent:FindFirstChild("AtlasDailyPage")
        local dot=self.navigation.Daily:FindFirstChild("PFDailyDot",true)
        local ok,page=pcall(function()return (require(dailyModule :: any) :: any).new(self.pages.Daily,{gui=gui,dot=dot})end)
        if ok then self.dailyPage=page else warn("[AtlasMenu] daily page unavailable: "..tostring(page))end
    end
    -- PF044 (PF - 3; Ashton approved the main screen 2026-10-24): AtlasMenu.PFHome (tools/atlas/author-pf044-home.luau) is
    -- the Play tab now: big PLAY SOLO + Easy / Medium / Hard, Custom matches (Join + Create), the public list, the party.
    -- While it shows (Play, no screen open) the Header and Pages hide, as for a screen (syncHome).
    do
        local homeRoot=root:FindFirstChild("PFHome");local homeModule=script.Parent:FindFirstChild("AtlasHomePage")
        if homeRoot and homeModule then
            local SettingsModel=require(Shared.LobbySettingsModel)
            local function soloScreen():any return self.screenPages and self.screenPages.Solo end
            local home=table.clone(common)
            home.mapSources=self.pages.Play:FindFirstChild("Templates") and self.pages.Play.Templates:FindFirstChild("Maps")
            home.soloDifficulty=function()local s=soloScreen();return s and s.settings and s.settings.difficulty end
            home.setSoloDifficulty=function(mode)
                local s=soloScreen();if s and s.settings then s.settings=SettingsModel.setDifficulty(s.settings,mode);if s.paint then pcall(s.paint,s) end end
            end
            -- one tap: the Solo screen's settings (as the sliders sheet left them) at the picked mode
            home.playSolo=function(mode)
                local s=soloScreen()
                local settings=SettingsModel.setDifficulty(if s and s.settings then s.settings else SettingsModel.defaults(),mode)
                if s then s.settings=settings end
                local config=SettingsModel.soloConfig(settings);if not config then return false end
                self:hide();if hooks.soloStart then hooks.soloStart(config) else hooks.solo() end
                return true
            end
            home.soloSettings=function()return self:openScreen("Solo")end
            home.customMatches=function()return self:openScreen("Join")end
            home.openShop=function()self:navigate("Shop")end
            -- build-out: the Home Shop card's balance + lands on the Cobalt packs (like the Armory wallet's)
            home.openCobalt=function()self:navigate("Shop");if self.commerce and self.commerce.selectCategory then self.commerce:selectCategory("Shop","Currency") end end
            home.openArmory=function()self:openArmory()end -- PIVOT Armory (PF - 3's key)
            home.openLook=function()self:navigate("Inventory")end
            home.openStats=function()self:navigate("Stats")end
            home.openSettings=function()self:navigate("Settings")end
            -- How to play (PF - 1's sheet) registers Routes.howToPlay; until then the ? keys stay hidden
            home.hasHowToPlay=function()return type((Routes :: any).howToPlay)=="function"end
            home.howToPlay=function()local open=(Routes :: any).howToPlay;if type(open)=="function" then open() end end
            home.joinPublic=function(id)return hooks.public:joinPublic(id)end
            home.cancelPublic=function()hooks.public:cancelPublic()end
            home.partyInvite=function()if self.party then self.party:openFriends() end end -- PF - 5: the Invite friends screen
            local ok,page=pcall(function()return (require(homeModule) :: any).new(homeRoot,home)end)
            if ok then self.homePage=page else warn("[AtlasMenu] main screen unavailable: "..tostring(page))end
            -- PF - 3 (MM 2026-10-26): your own seat in the Party card opens Profile (tools/atlas/author-pf3-profile-entry.luau)
            local profileHit=homeRoot:FindFirstChild("PFProfileHit",true)
            if profileHit and profileHit:IsA("GuiButton") then listen(self,profileHit.Activated,function()self:openScreen("Profile")end) end
        end
        -- Custom matches' Create: the Join screen's key (author-pf044-home)
        local joinNode=self.screensRoot and self.screensRoot:FindFirstChild("Join")
        local createKey=joinNode and joinNode:FindFirstChild("PFCreate",true)
        if createKey and createKey:IsA("GuiButton") then for _,tap in Parts.taps(createKey,joinNode) do listen(self,tap,function()self:openScreen("Create")end) end end
        -- UI audit build-out (R21: the empty list was a dead end): the empty state's own big Create lobby (author-pf3-build-lobby);
        -- both keys get the shared press juice (UiMotion)
        local emptyCreate=joinNode and joinNode:FindFirstChild("PFEmptyCreate",true)
        if emptyCreate and emptyCreate:IsA("GuiButton") then for _,tap in Parts.taps(emptyCreate,joinNode) do listen(self,tap,function()self:openScreen("Create")end) end end
        local okM,UiMotion=pcall(function() return require(script.Parent.UiMotion) end)
        if okM and type(UiMotion)=="table" then
            for _,key in {createKey,emptyCreate} do if key and key:IsA("GuiButton") then table.insert(self.connections,(UiMotion :: any).press(key)) end end
        end
    end
    root:SetAttribute("MenuFont","Ubuntu")
    root:SetAttribute("ReducedMotion",false)
    Typography.applyTree(root)
    -- Retained graphics/static-background preferences are independent. Only the
    -- superseded menu font/motion strip is removed by the authored migration.
    local preferences=self.pages.Settings:FindFirstChild("AtlasPreferences")
    if preferences then preferences.Visible=false end
    for _,attribute in {"ReducedMotion","StaticBackground"}do
        listen(self,root:GetAttributeChangedSignal(attribute),function()self:syncAmbient()end)
    end
    listen(self,root:GetPropertyChangedSignal("Visible"),function()self:syncAmbient()end)
    listen(self,gui:GetPropertyChangedSignal("Enabled"),function()self:syncAmbient()end)
    for _,name in self.names do
        local b=self.navigation[name]
        listen(self,b.Activated,function()self:navigate(name)end)
    end
    listen(self,self.pages.Play:GetAttributeChangedSignal("ModalOpen"),function()self:syncNavigation()end)
    -- PF020 G1 (PF - 3): equipping a custom flag re-draws the profile chip's flag
    listen(self,Players.LocalPlayer:GetAttributeChangedSignal("OpenFrontCustomFlag"),function()self:updateCommerce()end)
    listen(self,Gui:GetPropertyChangedSignal("SelectedObject"),function()
        local activePlay=self.pages:FindFirstChild("Play")
        if self.destroyed or not self.visible or self.page~="Play" or not activePlay or activePlay:GetAttribute("ModalOpen")~=true then return end
        local selected=Gui.SelectedObject
        if selected and selected:IsDescendantOf(self.header)then self:focusActive()end
    end)
    listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout()end)
    listen(self,Input:GetPropertyChangedSignal("PreferredInput"),function()if self.visible and Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive()end end)
    listen(self,gui.Destroying,function()self:destroy()end)
    listen(self,root.Destroying,function()self:destroy()end)
    -- PF023 P1 (PF - 1): the authored plate (a button) gets its view; an older place keeps the PF015 chip.
    if self.profileRoot and self.profileRoot:IsA("GuiButton") then
        -- display only (Ashton 2026-10-08: no hover/click menu on the plate; the Profile sheet stays dormant)
        self.plate=PlateView.new(self.profileRoot,{displayOnly=true,reducedMotion=common.reducedMotion})
        -- Roadmap #1 (PF - 1): the daily chips on Play, the login streak popup and the plate's gold dot (DailyView)
        pcall(function()require(script.Parent.DailyView).lobby(gui)end)
    end
    local nameLabel,detailLabel=self.profileRoot:FindFirstChild("DisplayName",true),self.profileRoot:FindFirstChild("Detail",true)
    if nameLabel then nameLabel.Text=player.DisplayName end
    if detailLabel then detailLabel.Text="@"..player.Name end
    self:updateCommerce();self:updatePublic();self:layout();self:syncAmbient();return self
end
-- (PF023: mountPlate, a runtime clone of the plate for the L1 Levels screen, is gone with that screen: the Levels tab
-- replaced it, and the clone wrote layout at runtime. Code only fills authored slots.)
-- PF023 P1: a plate chip or a Profile slot opens that slot's Inventory tab.
function Controller:openSlot(category: string)
    if self.destroyed or self.locked or not self.visible then return end
    self:closeScreen();self:navigate("Inventory")
    if self.page=="Inventory" and self.commerce.openSlot then self.commerce:openSlot(category) end
end
function Controller:syncAmbient()
    if self.destroyed or not self.root.Parent then return end
    local visible=self.visible and self.root.Visible and self.gui.Enabled
    local scene=visible and not self.locked -- PF019 M13b: the live match shows behind the locked shop
    self.ambient:update({paused=not scene,reducedMotion=self.root:GetAttribute("ReducedMotion")==true,
        staticBackground=self.root:GetAttribute("StaticBackground")==true})
    self.ambient:setVisible(scene)
    self.motion:setVisible(visible)
    self.cardKit:setActive(visible)
end
function Controller:setSettingsSurfaces(embedded:boolean)
    for node,original in self.settingsSurfaces do
        if node.Parent then node.BackgroundTransparency=if embedded then node:GetAttribute("AtlasMenuTransparency")else original end
    end
end
-- Content only (PF015): the authored right group shrinks the profile chip away
-- on narrow screens by itself; the Settings page hosts the shared panel.
function Controller:layout(_sizeOverride: Vector2?)
    if self.destroyed or not self.root.Parent then return end
    if self.visible and self.page=="Settings"then self.hooks.settings:setAtlasHost(self.pages.Settings.ContentHost)end
end
function Controller:updatePublic(model: any?)
    if self.destroyed then return end
    local nextModel=model or self.hooks.public:getState()
    if nextModel.waiting and not self.visible then self:show("Play")end
    self.play:update(nextModel)
    for _,page in self.screenPages or {}do page:update(nextModel)end
    -- PF019: the waiting Room takes over while you host a custom room; PF024: a member of someone else's gets
    -- Joined (J1), and a public match is the queue dock (J2) with the lobby still browsable. The screen closes
    -- when the room does (the map picker may sit over the Room for the host).
    local room=nextModel.room
    local public=type(room)=="table" and room.kind=="public"
    local want=if room and not public then (if self.screenPages and self.screenPages.Joined and not self:roomHost(room) then "Joined" else "Room") else nil
    local page=want and self.screenPages and self.screenPages[want]
    -- (PF020: not while the host is buying a pass from the room; the card's key takes them back)
    local buying=self.passReturn~=nil and self.passReturn.screen=="Room" and self.page=="Shop" and not self.screen
    if page and self.screen~=want and self.screen~="MapPicker" and not buying then
        if not self.visible then self:show("Play") end
        self:openScreen(want)
    elseif not want and (self.screen=="Room" or self.screen=="Joined" or self.screen=="MapPicker") and self.roomOpened then
        -- the room ended under the player: the screen shows why for a moment (host left, start failed…)
        local name=self.screen;local open=self.screenPages[name]
        local shown=(name=="Room" or name=="Joined") and open.showClosed and open:showClosed(nextModel,function() if self.screen==name then self:closeScreen() end end)
        if not shown then self:closeScreen() end
    end
    self.roomOpened=room~=nil and not public
    if self.dock then self.dock:update(nextModel) end
    if self.matchFound then self.matchFound:update(nextModel) end -- PF043
    if self.party then self.party:update(nextModel) end -- PF036
    if self.rejoinBanner then self.rejoinBanner:update(nextModel) end -- PF036
    if self.homePage then self.homePage:update(nextModel) end -- PF044
    -- PF024: any open sheet closes safely at a public match's teleport (a lobby flow, Settings, the Play dialog)
    local transfer=nextModel.transfer
    if public and type(transfer)=="table" and transfer.phase=="Teleporting" and transfer~=self.lastTeleport then
        self.lastTeleport=transfer
        if self.screen then self:closeScreen() end
        if self.visible and self.page~="Play" then self:navigate("Play") end
        if self.play.close then self.play:close() end
    end
end
-- PF024: whether you host this custom room (the contract marks you in members; hostUserId as the fallback).
function Controller:roomHost(room: any): boolean
    for _,member in room.members or {} do if member.isYou and member.isHost then return true end end
    return room.hostUserId==Players.LocalPlayer.UserId
end
function Controller:updateCommerce()
    if self.destroyed then return end
    local state=self.hooks.shop:getState();state.page=self.page
    self.commerce:update(state)
    if self.groupTile then self.groupTile:update(state.profile.group) end -- PF036
    if self.freeRewards then self.freeRewards:update(state) end -- PF043 F
    if self.homePage then self.homePage:updateCommerce(state) end -- PF044: the Cobalt balance
    local player=Players.LocalPlayer
    local identity={userId=player.UserId,displayName=player.DisplayName,name=player.Name,equipped=state.profile.equipped,cosmetics=state.profile.identityCosmetics}
    if self.plate then
        self.plateIdentity=identity;self.plate:bind(identity)
    else ProfileArt.bindProfile(self.profileRoot,identity) end
    self:layout()
    self:updatePublic()
end
function Controller:observe(packet: any)
    if type(packet)=="table" and packet.spectator==true then return end -- PF020 G8: a spectated match isn't the player's
    self.stats:observe(packet)
    if self.visible and self.page=="Stats"then self.statsPage:update(self.stats:view())end
end
function Controller:home(matchId: number?)
    if matchId then self.stats:leave(matchId)end
    self:show("Play")
end
function Controller:show(page: string?)
    if self.destroyed or not self.root.Parent then return end
    self:unlock()
    self.visible=true;self.root.Visible=true
    self.gui.Background.Home.Visible=false;self.gui.Background.PublicWaiting.Visible=false
    self:navigate(page or "Play")
end
function Controller:hide()
    if not self.visible then return end
    self:unlock()
    self:closeScreen()
    self.visible=false;self.root.Visible=false
    if self.homePage then self.homePage:setVisible(false) end -- PF044
    self:syncAmbient();self:setSettingsSurfaces(false)
    self.play:setVisible(false);self.commerce:setVisible(false);self.statsPage:setVisible(false)
    if self.arsenal then self.arsenal:sync("",false) end -- PIVOT D12
    if self.armory then self.armory:setVisible(false) end -- PIVOT Armory
    if self.pageTop then self.pageTop:sync("",false) end -- PF044 r5
    if self.dailyPage then self.dailyPage:setVisible(false) end -- PF043 B3
    if self.page=="Settings"then self.hooks.settings:closeSettings(false);self.hooks.settings:setAtlasHost(nil)end
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.root)then Gui.SelectedObject=nil end
end
-- PF019: open a full-screen flow (false when its node/module isn't installed: callers fall back).
function Controller:openScreen(name: string): boolean
    local page=self.screenPages and self.screenPages[name]
    if self.destroyed or not self.visible or not page or self.locked then return false end
    if self.screen and self.screen~=name then self:closeScreen()end
    self.screen=name
    for _,child in self.screensRoot:GetChildren()do if child:IsA("GuiObject")then child.Visible=child.Name==name end end
    self.screensRoot.Visible=true;self.header.Visible=false;self.pages.Visible=false
    self.play:setVisible(false)
    self:syncHome() -- PF044: a screen covers the main screen
    page:setVisible(true);page:update(self.hooks.public:getState())
    if Input.PreferredInput==Enum.PreferredInput.Gamepad then page:focusActive()end
    return true
end
function Controller:closeScreen()
    local name=self.screen;if not name then return end
    self.screen=nil
    local page=self.screenPages[name];if page then page:setVisible(false)end
    if self.screensRoot then self.screensRoot.Visible=false end
    self.header.Visible=true;self.pages.Visible=true
    if Gui.SelectedObject and self.screensRoot and Gui.SelectedObject:IsDescendantOf(self.screensRoot)then Gui.SelectedObject=nil end
    self:syncHome() -- PF044: back to the main screen when Play is the page
    if self.visible then self.play:setVisible(self.page=="Play" and not self.homePage);if Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive()end end
end
-- PF044: the main screen (AtlasMenu.PFHome) is the Play tab. It shows while the menu is up on Play with no screen open
-- (and not in the locked mid-match shop); the Header and Pages hide behind it, as they do for a screen.
function Controller:syncHome()
    local home=self.homePage;if not home or self.destroyed then return end
    local on=self.visible and self.page=="Play" and self.screen==nil and not self.locked
    if on then self.header.Visible=false;self.pages.Visible=false
    elseif self.screen==nil then self.header.Visible=true;self.pages.Visible=true end
    if home.visible~=on then home:setVisible(on) end
end
function Controller:navigate(name: string)
    local names=self.names or LEGACY_TABS
    if self.destroyed or not self.root.Parent or not table.find(names,name)or not self.visible then return end
    if self.locked and name~="Shop"then return end -- PF019 M13b: the lobby stays hidden mid-match
    if name~="Shop" then self.passReturn=nil;self.shopReturn=nil end -- PF020: leaving the Shop forgets a pass's way back
    self:closeScreen()
    if name~=self.page and self.page=="Play" and self.pages.Play:GetAttribute("ModalOpen")==true then return end
    if self.page=="Settings" and name~="Settings"then self.hooks.settings:closeSettings(false);self.hooks.settings:setAtlasHost(nil);self:setSettingsSurfaces(false)end
    local was=if self.armory and self.armory.visible then "Armory" else self.page -- STATS v3: a UI open (below)
    self.page=name;self.root:SetAttribute("AtlasPage",name)
    for _,n in names do
        local button=self.navigation[n];local selected=n==name
        self.pages[n].Visible=selected;button.Underline.Visible=selected
        button:SetAttribute("PFSelected",selected)
        -- PF023: the Levels-tab installer moves each Label into a LabelClip (phone folding), so find it at any depth
        -- PF043 B3: a gold tab (the Shop: its Glyph carries PFTint="gold") keeps a gold label
        local gold=button.Glyph:GetAttribute("PFTint")=="gold"
        local label=button:FindFirstChild("Label",true);if label and label:IsA("TextLabel")then label.TextColor3=if selected then Theme.Text elseif gold then GOLD_LABEL else Theme.MutedText end
        NavIcons.paint(button.Glyph,selected) -- PF017: per-piece tones (AtlasNavIcons)
    end
    -- PF031 (Ashton: "lag when I click from tab to tab"): a tab click only shows its page. Play keeps its decoded map
    -- previews while another tab is up (hide() releases them); the Shop/Inventory cards repaint when the shop's data
    -- changes (stateChanged -> updateCommerce), never on a click: rebuilding every card on each switch was the hitch.
    self.play:setVisible(name=="Play" and not self.homePage,true) -- PF044: the main screen replaces the old Play page
    self:syncHome()
    self:updatePublic();self.commerce:setVisible(name=="Shop"or name=="Inventory",name) -- (a host's room still takes the screen back)
    self.statsPage:setVisible(name=="Stats") -- showing Stats renders it
    -- PIVOT Armory: the Shop page carries the Armory (openArmory, or a match's grid: locked.tab "Armory"); any other visit is Cosmetics
    local armory=name=="Shop" and (self.wantArmory==true or (self.locked~=nil and self.locked.tab=="Armory"));self.wantArmory=nil
    if self.armory then self.armory:setVisible(armory==true,self.locked and self.locked.item) end
    local now=if armory then "Armory" else name;if now~=was then pcall(function() require(script.Parent.StatsReport).open(now) end) end
    if self.arsenal then self.arsenal:sync(name,self.locked~=nil,armory) end -- PIVOT D12: the Shop's top bar takes the Header's place
    if self.pageTop then self.pageTop:sync(name,self.locked~=nil) end -- PF044 r5: Inventory / Stats too
    if self.dailyPage then self.dailyPage:setVisible(name=="Daily") end -- PF043 B3
    if name=="Settings"then self:setSettingsSurfaces(true);self.hooks.settings:setAtlasHost(self.pages.Settings.ContentHost);self.hooks.settings:openSettings(function()if self.visible then self:navigate("Play")end end)end
    if Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive()end
    self:syncNavigation();self:syncAmbient()
end
function Controller:syncNavigation()
    local activePlay=self.pages:FindFirstChild("Play")
    local navigation=self.navigation
    if self.destroyed or not activePlay or not navigation then return end
    local blocked=self.page=="Play" and activePlay:GetAttribute("ModalOpen")==true
    for _,button in navigation:GetChildren()do if button:IsA("GuiButton")then button.Active=not blocked;button.Selectable=not blocked end end
    if blocked and Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive()end
end
function Controller:isBlocking(): boolean return self.visible end
function Controller:focusActive()
    if not self.visible then return end
    -- a modal sheet over the menu (ModalGuard: Interactable off behind it) keeps the focus; selecting behind it is invalid
    if ModalGuard.covers(self.root) then return end
    local node: Instance?=self.root
    while node and node:IsA("GuiObject") do if not node.Interactable then return end;node=node.Parent end
    if self.screen and self.screenPages[self.screen]then self.screenPages[self.screen]:focusActive();return end
    if self.homePage and self.homePage.visible then self.homePage:focusActive();return end -- PF044
    if self.page=="Play" and self.pages.Play:GetAttribute("ModalOpen")==true and self.play.focusActive then self.play:focusActive();return end
    if self.armory and self.armory.visible then self.armory:focusActive();return end -- PIVOT Armory
    if (self.page=="Shop"or self.page=="Inventory") and self.commerce.focusActive then self.commerce:focusActive();return end
    Gui.SelectedObject=self.navigation[self.page]
end
function Controller:handleEscape(): boolean
    if not self.visible then return false end
    if self.party and self.party:handleEscape() then return true end -- PF036: the party card closes first
    if self.nameplate and self.nameplate:handleEscape() then return true end -- PF043 B4: the nameplate picker
    if self.armory and self.armory.visible and not self.locked then self:navigate("Play");return true end -- PIVOT Armory
    if self.locked then
        if self.commerce.handleEscape and self.commerce:handleEscape()then return true end
        self:closeLockedShop(true);return true
    end
    if self.screen then
        -- The screen unwinds its own layers first (PF - 1: code popover, drawer, pending join).
        local page=self.screenPages[self.screen]
        if not (page and page:handleEscape())then self:closeScreen()end
        return true
    end
    local active=if self.page=="Play"then self.play elseif self.page=="Stats"then self.statsPage else self.commerce
    if active.handleEscape and active:handleEscape()then return true end
    if self.page=="Shop" and self.shopReturn then self:shopBack();return true end
    if self.page~="Play"then self:navigate("Play");return true end
    return true
end
-- PF019 M13b (PF - 2): the shop over a live match. The real Shop page with the lobby Header
-- hidden, the ambient off (the match keeps running behind a scrim) and LockedShop's banner +
-- "Back to battle" key; navigation is held on Shop. Back / Esc / B call options.onBack.
-- false when locked mode isn't installed (the caller falls back).
function Controller:openLockedShop(options: any?): boolean
    if self.destroyed or not self.root.Parent or not self.lockedShop then return false end
    self:closeScreen()
    self.locked=options or {};self.visible=true;self.root.Visible=true;self.header.Visible=false
    self:navigate("Shop")
    if self.page~="Shop"then self:hide();return false end
    self.lockedShop:show(self.locked)
    -- UX audit #4: the end card's Next unlock opens the Shop on that item's tab (options.category, a Shop category)
    if type(self.locked.category)=="string" and self.commerce.selectCategory then self.commerce:selectCategory("Shop",self.locked.category) end
    return true
end
-- PIVOT Armory: the premium showroom from the lobby (the Shop page with AtlasMenu.PFArmory over it)
function Controller:openArmory(): boolean
    if self.destroyed or not self.visible or not self.armory or self.locked then return false end
    self.wantArmory=true;self:navigate("Shop")
    return self.armory.visible
end
-- UI audit (PF - 3, 2026-10-28): the Shop's Back goes where the Shop was opened from: the Armory's wallet + returns to the
-- Armory (it used to drop the player on Home); a match's locked shop goes back to the battle
function Controller:shopBack()
    if self.locked then self:closeLockedShop(true);return end
    if self.shopReturn=="Armory" then self.shopReturn=nil;if self:openArmory() then return end end
    self:navigate("Play")
end
function Controller:closeLockedShop(back: boolean?)
    local locked=self.locked;if not locked then return end
    self:hide()
    if back and locked.onBack then locked.onBack()end
end
function Controller:isLocked(): boolean return self.locked~=nil end
function Controller:unlock()
    if not self.locked then return end
    self.locked=nil;self.header.Visible=true
    if self.lockedShop then self.lockedShop:hide()end
end
function Controller:destroy()
    if self.destroyed then return end;self.destroyed=true;self.visible=false
    if self.lockedShop then self.lockedShop:destroy()end
    for _,c in self.connections do c:Disconnect()end
    self.motion:destroy();self:setSettingsSurfaces(false);self.ambient:destroy();self.cardKit:destroy();if self.accentFocus then self.accentFocus.destroy() end
    if self.plate then self.plate:destroy() else ProfileArt.unbindProfile(self.profileRoot) end
    -- Explicit shell disposal may leave the shared Settings controller/GUI alive.
    -- Deferred full-GUI destruction may already have removed its authored body.
    local settingsUI=self.settingsUI
    if self.page=="Settings"and self.gui.Parent and settingsUI and settingsUI.Parent
        and settingsUI:FindFirstChild("Body")and settingsUI:FindFirstChild("Backdrop")and not self.hooks.settings.destroyed then
        self.hooks.settings:closeSettings(false);self.hooks.settings:setAtlasHost(nil)
    end
    if self.root.Parent then self.root.Visible=false end
    self.play:destroy();self.commerce:destroy();self.statsPage:destroy()
    if self.dailyPage then self.dailyPage:destroy() end -- PF043 B3
    for _,page in self.screenPages or {}do page:destroy()end
    if self.dock then self.dock:destroy() end -- PF024
    if self.matchFound then self.matchFound:destroy() end -- PF043
    if self.nameplate then self.nameplate:destroy() end -- PF043 B4
    if self.party then self.party:destroy() end -- PF036
    if self.rejoinBanner then self.rejoinBanner:destroy() end -- PF036
    if self.groupTile then self.groupTile:destroy() end -- PF036
    if self.freeRewards then self.freeRewards:destroy() end -- PF043 F
    if self.rankedPage then self.rankedPage:destroy() end -- PF036
    if self.homePage then self.homePage:destroy() end -- PF044
    if self.arsenal then self.arsenal:destroy() end -- PIVOT D12
    if self.armory then self.armory:destroy() end -- PIVOT Armory
    if self.pageTop then self.pageTop:destroy() end -- PF044 r5
end
return Controller
