--!strict
-- Studio never accesses the paid wallet's DataStore or prompts for purchases.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local DataStoreService=game:GetService("DataStoreService")
local MarketplaceService=game:GetService("MarketplaceService")
local Remotes=require(game.ReplicatedStorage.Shared.Remotes)
local Catalog=require(game.ReplicatedStorage.Shared.CosmeticCatalog)
local Arsenal=require(game.ReplicatedStorage.Shared.ArsenalCatalog) -- PF044: premium unlocks share the Cobalt wallet
local Profiles=require(script.Parent.CosmeticProfiles)
local Service={}
local started=false
local engine: any=nil
-- PF025 (PF - 3): the VIP box's two prefs, folded into replicated attributes every client draws from:
--   OpenFrontVIPBadge  the gold badge (nameplate, leaderboard, rooms, chat): VIP and "VIP badge" not Hide
--   OpenFrontVIPGold   gold lobbies (a hosted room shines and pins near the top): VIP and "Gold lobbies" on
-- OpenFrontVIP stays the plain ownership (perks such as the Cobalt bonus). Saved prefs arrive through PreferencesService.
local Preferences=require(script.Parent.PreferencesService)
local function vipPresence(player: Player)
    if player.Parent~=Players then return end
    local vip=player:GetAttribute("OpenFrontVIP")==true
    player:SetAttribute("OpenFrontVIPBadge",vip and Preferences.value(player.UserId,"settings.vipBadge")~="hide")
    player:SetAttribute("OpenFrontVIPGold",vip and Preferences.value(player.UserId,"settings.goldLobbies")~="false")
end
Service.vipPresence=vipPresence
-- PF034 Discord feed: who hears about a real Robux purchase (a granted Developer Product receipt, a Game Pass bought in
-- game). Each listener runs on its own thread inside a pcall, after the grant: it can never change or delay one.
local purchaseListeners: {(any)->()}={}
local function purchased(info: any)
    for _,listener in purchaseListeners do task.spawn(function() pcall(listener,info) end) end
end
function Service.onPurchase(listener: (any)->()) table.insert(purchaseListeners,listener) end
-- PF044: who hears about a new Arsenal unlock (MatchService, GlobalLobbyService: the live match grants it at once).
-- listener(userId, owned): owned = every Arsenal item the account has unlocked, {[itemId]=true}
local arsenalListeners: {(number,any)->()}={}
function Service.onArsenal(listener: (number,any)->()) table.insert(arsenalListeners,listener) end

function Service.start()
    Preferences.subscribe(vipPresence)
    if started then return end; started=true
    local studio=RunService:IsStudio()
    local store: any=nil
    local memory: {[string]: any}={}
    if not studio then store=DataStoreService:GetDataStore(Catalog.storeName) end
    local remote=Remotes.server()
    local players: {[number]: Player}={}
    local okAnalytics,Analytics=pcall(require,script.Parent.AnalyticsHooks) -- PF037: every Cobalt grant and spend
    engine=Profiles.new({catalog=Catalog,arsenal=Arsenal,studio=studio,now=os.clock,spawn=task.spawn,wait=task.wait,
        economy=if okAnalytics then Analytics.economy else nil,
        -- PF044 Revive: the 49 R$ product (0 = none yet: never routed) and the hook that applies a paid one to an open offer
        reviveProductId=require(game.ReplicatedStorage.Shared.Config).Revive.ProductId,        revivePurchased=function(userId: number,purchaseId: string) require(script.Parent.ReviveService).purchased(userId,purchaseId) end,
        -- PF044: an Arsenal unlock (Cobalt or Robux) reaches the player's live match (Service.onArsenal listeners)
        arsenalUnlocked=function(userId: number,owned: any)
            for _,listener in arsenalListeners do task.spawn(function() pcall(listener,userId,owned) end) end
        end,
        utcDay=function() return math.floor(DateTime.now().UnixTimestamp/86400) end,
        get=function(key: string) return if studio then Profiles.copy(memory[key]) else store:GetAsync(key) end,
        update=function(key: string,transform: any)
            if not studio then return store:UpdateAsync(key,transform) end
            local result=transform(Profiles.copy(memory[key]))
            if result==nil then return nil end
            memory[key]=Profiles.copy(result); return Profiles.copy(result)
        end,
        reset=if studio then function(key: string) memory[key]=nil end else nil,
        ownsPass=function(userId: number,passId: number)
            if studio then return false end
            return MarketplaceService:UserOwnsGamePassAsync(userId,passId)
        end,
        notify=function(userId: number,packet: any)
            local player=players[userId]
            if player and player.Parent==Players then
                if packet.kind=="Cosmetics" and packet.loaded then
                    for slot in Catalog.slots do player:SetAttribute("OpenFrontCosmetic"..slot,packet.equipped[slot]) end
                    -- PF020: replicated so every client can draw the VIP badge (nameplate, leaderboard, rooms, chat).
                    player:SetAttribute("OpenFrontVIP",packet.vip==true)
                    vipPresence(player) -- PF025: the badge / gold-room attributes follow ownership and the VIP box
                    -- PF020 G8: Lobby Host+ (the lobby service gates the Host+ settings, lock and kick on it).
                    player:SetAttribute("OpenFrontHostPlus",type(packet.passes)=="table" and packet.passes.LobbyHostPlus==true)
                    -- PF020 G1 (PF - 3): CustomFlagService gates saving, equipping and publishing a custom flag on it.
                    player:SetAttribute("OpenFrontCustomFlagPass",type(packet.passes)=="table" and packet.passes.CustomFlag==true)
                end
                remote.CosmeticsState:FireClient(player,packet)
            end
        end,
        broadcast=function(packet: any) remote.CosmeticsState:FireAllClients(packet) end,
        loaded=function(userId: number) for _,listener in loadedListeners do task.spawn(listener,userId) end end, -- PF023 claims
    })
    local function confirmPacks(player: Player)
        if studio then return end
        -- Premium packs and PF020 Game Passes share the confirmation: only real IDs (passId>0) are asked.
        local owned={}
        for _,pack in Catalog.premiumPacks do table.insert(owned,pack) end
        for _,pass in Catalog.passes or {} do table.insert(owned,pass) end
        for _,pass in Catalog.retiredPasses or {} do table.insert(owned,pass) end -- RELEASE: an old buyer keeps its items
        for _,pack in owned do
            if pack.passId<=0 then continue end
            task.spawn(function()
                for attempt=1,3 do
                    if players[player.UserId]~=player then return end
                    if engine:confirmPass(player.UserId,pack.passId) then return end
                    if attempt<3 then task.wait(attempt) end
                end
            end)
        end
    end
    local function add(player: Player) players[player.UserId]=player; engine:add(player.UserId);confirmPacks(player) end
    Players.PlayerAdded:Connect(add)
    for _,player in Players:GetPlayers() do add(player) end
    Players.PlayerRemoving:Connect(function(player: Player)
        if players[player.UserId]~=player then return end
        players[player.UserId]=nil; engine:remove(player.UserId)
    end)
    remote.CosmeticsCommand.OnServerEvent:Connect(function(player: Player,command: any)
        if players[player.UserId]~=player then return end
        -- PF036 group reward: the membership check yields (Groups API), so it runs off the event
        if type(command)=="table" and command.kind=="ClaimGroup" then task.spawn(Service.claimGroup,player);return end
        engine:command(player.UserId,command)
    end)
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player,passId: number,wasPurchased: boolean)
        -- RELEASE: a Studio test purchase can't be confirmed (UserOwnsGamePassAsync), so Studio grants it into its memory
        -- profile straight away (never a DataStore); live servers only trust the ownership check (confirmPacks)
        if studio and wasPurchased and players[player.UserId]==player then
            local pass=Catalog.passForGamePass(passId);local pack=not pass and Catalog.packForPass(passId)
            if pass then engine:grantPass(player.UserId,pass) elseif pack then engine:grantPack(player.UserId,pack) end
            return
        end
        if not studio and wasPurchased and players[player.UserId]==player and (Catalog.packForPass(passId) or Catalog.passForGamePass(passId)) then
            confirmPacks(player)
            purchased({player=player,userId=player.UserId,kind="pass",id=passId}) -- PF034
        end
    end)
    -- One owner for receipts. Keep unknown products pending for future mapping.
    -- RELEASE: Studio test purchases (Roblox calls this in Studio too) are granted into Studio's memory profiles, never a
    -- DataStore, so every Robux button can be tested end to end before publishing
    MarketplaceService.ProcessReceipt=function(receipt: any)
        -- PF034: a receipt this server already granted (Roblox can resend one) is not a new purchase for the feed
        local okFresh,fresh=pcall(function()
            local profile=engine.profiles[receipt.PlayerId]
            return not (profile and profile.loaded and profile.record.receipts[receipt.PurchaseId]~=nil)
        end)
        local ok,granted=pcall(function() return engine:receipt(receipt) end)
        if ok and granted then
            purchased({player=players[receipt.PlayerId],userId=receipt.PlayerId,kind="product",id=receipt.ProductId,purchaseId=receipt.PurchaseId,
                robux=receipt.CurrencySpent,fresh=not okFresh or fresh==true}) -- PF034
        end
        return if ok and granted then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
    end
    if studio then
        -- Server-only bridge for Studio's isolated command environment. These
        -- Bindables are never replicated, created in production, or remote-driven.
        local bridge=Instance.new("Folder");bridge.Name="OpenFrontCosmeticsQA"
        bridge.Parent=game:GetService("ServerStorage")
        for name,callback in {Grant=Service.studioTestGrant,GrantPack=Service.studioTestGrantPack,Reset=Service.studioReset} do
            local command=Instance.new("BindableFunction");command.Name=name
            command.OnInvoke=callback;command.Parent=bridge
        end
    end
    -- PF020 G3 (PF - 3, MM 2026-10-07): VIP V5 is claimed by hand on the Premium card (ClaimVipDaily
    -- through CosmeticsCommand); the old auto-claim loop is gone.
    game:BindToClose(function() engine:close() end)
end

-- PF036 group reward: verify the membership with GetGroupsAsync (Player:IsInGroup caches per session, so a fresh join
-- reads false), then pay once (CosmeticProfiles.claimGroupReward). One check per player at a time, 5 s apart.
local groupChecks: {[Player]: boolean}={}
function Service.claimGroup(player: Player): string
    local reward=Catalog.groupReward
    if not engine or not reward or reward.groupId<=0 or groupChecks[player] then return "failed" end
    groupChecks[player]=true
    task.delay(5,function() groupChecks[player]=nil end)
    local ok,groups=pcall(function() return game:GetService("GroupService"):GetGroupsAsync(player.UserId) end)
    local member=false
    if ok and type(groups)=="table" then for _,g in groups do if type(g)=="table" and g.Id==reward.groupId then member=true end end end
    if not ok then engine:notify(player.UserId,"Couldn't check the group right now. Try again.");return "failed" end
    if not member then engine:notify(player.UserId,"Join the group first, then claim.");return "failed" end
    return engine:claimGroupReward(player.UserId)
end
-- PF021 tutorial reward: MatchService calls this when a tutorial's win fact lands ("granted" | "claimed" | "failed").
function Service.claimTutorialReward(player: Player): string
    if not engine then return "failed" end
    return engine:claimTutorialReward(player.UserId)
end

-- PF039: daily challenge / login streak rewards (DailyService; server-only): ("granted", info) | ("claimed") | ("failed", reason).
function Service.grantRewards(userId: number, receiptKey: string, reward: any): (string, any?)
    if not engine then return "failed",nil end
    return engine:grantRewards(userId,receiptKey,reward)
end
-- PIVOT D11: a match's Cobalt (MatchCobalt), once per match key (MatchRewardsService at the match-end moment; server-only).
function Service.grantMatch(userId: number, matchKey: string, amount: number): (string, number?)
    if not engine then return "failed",nil end
    return engine:grantMatch(userId,matchKey,amount)
end
-- a hook when a profile loads
local loadedListeners: {(number)->()}={}
function Service.onLoaded(listener: (number)->()) table.insert(loadedListeners,listener) end

-- PF023 rewards v3: owns the shop item a 5th level gives? (owned, its shop price), for the result card (the grant
-- itself decides inside the profile transaction).
function Service.owns(userId: number, itemId: string): (boolean, number?)
    local profile=engine and engine.profiles[userId]
    local item=Catalog.byId[itemId]
    return profile~=nil and profile.loaded and profile.record.owned[itemId]==true, item and item.price
end

-- Onboarding: the receipts that say this player has been here ({tutorial, receipts}; nil while loading; failed when unknown).
function Service.history(userId: number): any?
    if not engine then return {failed=true} end
    local profile=engine.profiles[userId]
    if not profile then return nil end
    if not profile.loaded then return if profile.failed then {failed=true} else nil end
    local receipts=0;for _ in profile.record.receipts do receipts+=1 end
    return {tutorial=profile.record.receipts[Catalog.tutorialReward.receipt]~=nil,receipts=receipts}
end

-- PF034 Discord feed: a read-only summary of the wallet (nil while loading; {failed=true} when unknown): the Cobalt
-- balance, the Game Passes and premium packs owned, the Robux product receipts by product id and the tutorial receipt.
-- PF037 growth hooks: the item this player has equipped in a slot (e.g. "Crown"), or nil (not loaded / none).
function Service.equipped(userId: number, slot: string): string?
    local profile=engine and engine.profiles[userId]
    if not profile or not profile.loaded or type(profile.record.equipped)~="table" then return nil end
    local id=profile.record.equipped[slot]
    return if type(id)=="string" then id else nil
end
function Service.summary(userId: number): any?
    if not engine then return {failed=true} end
    local profile=engine.profiles[userId]
    if not profile then return nil end
    if not profile.loaded then return if profile.failed then {failed=true} else nil end
    local record=profile.record
    local passes,products={},{}
    for _,pass in Catalog.passes or {} do if record.owned[pass.id]==true then table.insert(passes,{name=pass.name,passId=pass.passId}) end end
    for _,pack in Catalog.premiumPacks do if record.owned[pack.id]==true then table.insert(passes,{name=pack.name,passId=pack.passId}) end end
    for _,receipt in record.receipts do
        if Catalog.packForProduct(receipt.productId) then products[receipt.productId]=(products[receipt.productId] or 0)+1 end
    end
    return {balance=record.balance,passes=passes,products=products,tutorial=record.receipts[Catalog.tutorialReward.receipt]~=nil}
end

-- PF044: the Arsenal items this player has unlocked ({[itemId]=true}; nil while loading). Server-only, for the in-match
-- build gate (premium items: never AI nations, never Ranked).
function Service.arsenalOwned(userId: number): {[string]: boolean}?
    local profile=engine and engine.profiles[userId]
    if not profile or not profile.loaded then return nil end
    return Arsenal.owned(profile.record.owned)
end
-- A free Arsenal unlock from a server reward (the daily streak). Yields (a wallet write). Once per receiptKey; an owned item
-- pays `fallback` Cobalt instead. Returns (ok, "unlocked" | "credited" | "done"). Server-only: never remote-driven.
function Service.grantArsenal(userId: number,itemId: string,receiptKey: string,fallback: number?): (boolean,string?)
    if not engine then return false,nil end
    return engine:grantArsenal(userId,itemId,receiptKey,fallback or 0)
end

-- PF044 Revive (ReviveService only; server-only): {free, credits} (nil while loading), use one, undo one.
function Service.reviveStatus(userId: number): any?
    return if engine then engine:reviveStatus(userId) else nil
end
function Service.reviveConsume(userId: number, kind: string, purchaseId: string?): string?
    return if engine then engine:reviveConsume(userId,kind,purchaseId) else nil
end
function Service.reviveRefund(userId: number, marker: string): boolean
    return if engine then engine:reviveRefund(userId,marker) else false
end
-- Studio only (ProcessReceipt never runs in Studio): store a fake paid Revive for this player, then run the purchase path
function Service.studioRevivePurchase(userId: number): boolean
    assert(RunService:IsStudio(),"Studio Revive purchases require Studio")
    if not engine then return false end
    local purchaseId="studio-"..game:GetService("HttpService"):GenerateGUID(false)
    return engine:reviveReceipt({PlayerId=userId,PurchaseId=purchaseId,ProductId=1,CurrencySpent=49}) -- it calls revivePurchased
end

function Service.studioTestGrant(userId: number, amount: number): boolean
    assert(RunService:IsStudio(),"Cosmetic test grants require Studio")
    assert(engine,"Cosmetic service is not started")
    return engine:studioGrant(userId,amount)
end

-- Server-only admin grants. Callers (AdminCommands) must already have authorised
-- the sender by UserId; nothing here is reachable from a remote.
function Service.adminGrantCobalt(userId: number, amount: number): (boolean, string)
    if not engine then return false,"Cosmetics are not ready." end
    return engine:adminGrantCobalt(userId,amount)
end
function Service.adminGrantPack(userId: number, entry: any): (boolean, string)
    if not engine then return false,"Cosmetics are not ready." end
    return engine:adminGrantPack(userId,entry)
end

function Service.studioReset(userId: number): boolean
    assert(RunService:IsStudio(),"Cosmetic test resets require Studio")
    assert(engine,"Cosmetic service is not started")
    return engine:studioReset(userId)
end
function Service.studioTestGrantPack(userId: number,packId: string): boolean
    assert(RunService:IsStudio(),"Pack test grants require Studio")
    assert(engine,"Cosmetic service is not started")
    return engine:studioGrantPack(userId,packId)
end

return Service
