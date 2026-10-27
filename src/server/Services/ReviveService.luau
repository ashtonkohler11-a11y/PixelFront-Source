--!strict
-- PF044 Revive offers (Config.Revive; PF-2-revive-spec-2026-10-23.md). MatchService (Solo) and PublicMatchRuntime (Public /
-- custom) open an offer when their human is eliminated and Simulation.reviveEligible holds. This module picks the cost (the
-- account's free one, a saved paid one, or the 49 R$ product), takes the client's Revive, applies a paid receipt to the open
-- offer, and spends / refunds the use in the wallet (CosmeticService). The match applies the Revive itself, between ticks,
-- through offer.hooks.apply(offer) and reports back with Service.applied(offer, ok). Every time here is Service.clock().
--   offer = {id, userId, cost = "free" | "credit" | "robux", deadline, state = "open" | "claiming" | "closed",
--            marker? (the wallet entry spent), hooks = {apply(offer), closed(offer, reason)}}
local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
local Service={}
local offers: {[number]: any}={}
local nextId=0
Service.clock=os.clock -- tests replace it
-- a paid prompt can finish a little after the 15 s ring (Roblox's dialog): the receipt still applies inside this grace
Service.PURCHASE_GRACE=20
function Service.cosmetics(): any? -- tests replace it
    local ok,C=pcall(require,script.Parent.CosmeticService)
    return if ok then C else nil
end
-- "free" | "credit" | "robux", or nil when nothing can pay (wallet not loaded and no product)
function Service.cost(userId: number): string?
    local C=Service.cosmetics()
    local status=if C and C.reviveStatus then C.reviveStatus(userId) else nil
    if status and status.free then return "free" end
    if status and status.credits>0 then return "credit" end
    if (Config.Revive.ProductId or 0)>0 then return "robux" end
    return nil
end
function Service.open(userId: number,hooks: any,_now: number?): any?
    local cost=Service.cost(userId)
    if not cost then return nil end
    nextId+=1
    local offer={id=nextId,userId=userId,cost=cost,deadline=Service.clock()+Config.Revive.OfferSeconds,state="open",hooks=hooks}
    offers[userId]=offer
    return offer
end
function Service.get(userId: number): any? return offers[userId] end
-- the display name of the nation a Revive would rise inside (the largest living nation): the offer card's title
function Service.hostName(state: any): string?
    local best,most=nil,0
    for owner,player in state.players do
        if player.playerType=="Nation" and (state.counts[owner] or 0)>most then best,most=owner,state.counts[owner] end
    end
    if not best then return nil end
    return (state.names and state.names[best]) or state.players[best].name
end
-- Revive or Takeover (Ashton 2026-10-24): killed by a nation = Takeover (Simulation.takeoverTarget), else (a human or tribe
-- kill, or no fair nation) = Revive. solo: no other humans (Takeover's fairness rules off); reviveSolo (default solo): Revive
-- without its time cutoff (Solo matches only). Returns {kind = "takeover", target} | {kind = "revive"} | nil (nothing to offer).
function Service.pick(state: any,owner: number,killer: number?,solo: boolean,reviveSolo: boolean?): any?
    local Simulation=require(game:GetService("ReplicatedStorage").Shared.Simulation)
    if Simulation.takeoverEligible(state,owner,solo) then
        local target=Simulation.takeoverTarget(state,owner,killer,solo)
        if target then return {kind="takeover",target=target} end
    end
    if Simulation.reviveEligible(state,owner,if reviveSolo==nil then solo else reviveSolo) then return {kind="revive"} end
    return nil
end
-- the Takeover card's nation: {owner, name, tiles, land (share of the map's land), troops, gold}
function Service.targetInfo(state: any,nation: number): any
    local troops=state.troops[nation] or 0 -- with its attacks in flight and boats at sea (Simulation.takeOver hands them over)
    for _,attack in state.attacks or {} do if attack.active and attack.owner==nation then troops+=math.floor(attack.budget) end end
    for _,ship in state.ships or {} do if ship.owner==nation and ship.active~=false and ship.troops then troops+=math.floor(ship.troops) end end
    return {owner=nation,name=(state.names and state.names[nation]) or state.players[nation].name,tiles=state.counts[nation] or 0,
        land=(state.counts[nation] or 0)/math.max(1,state.map.landCount),troops=math.floor(troops),gold=math.floor(state.gold[nation] or 0)}
end
function Service.close(offer: any,reason: string)
    if offer.state=="closed" then return end
    offer.state="closed"
    if offers[offer.userId]==offer then offers[offer.userId]=nil end
    if offer.hooks and offer.hooks.closed then pcall(offer.hooks.closed,offer,reason) end
end
-- the open offer's ring ran out (a robux offer keeps PURCHASE_GRACE for a receipt in flight; the client hides it at 15 s)
function Service.expired(offer: any,_now: number?): boolean
    if offer.state~="open" then return false end
    return Service.clock()>offer.deadline+(if offer.cost=="robux" then Service.PURCHASE_GRACE else 0)
end
-- the client's Revive key on a free / credit offer. Yields (the wallet write). Returns (ok, message?).
function Service.claim(userId: number,offerId: any,_now: number?): (boolean,string?)
    local offer=offers[userId]
    if not offer or offer.id~=offerId or offer.state~="open" or offer.cost=="robux" then return false,nil end
    if Service.clock()>offer.deadline then return false,nil end
    offer.state="claiming"
    local C=Service.cosmetics()
    local marker=if C and C.reviveConsume then C.reviveConsume(userId,if offer.cost=="free" then "free" else "credit") else nil
    if not marker then
        if offer.state=="claiming" then offer.state="open" end
        return false,"Couldn't use your Revive. Try again."
    end
    offer.marker=marker
    offer.hooks.apply(offer)
    return true,nil
end
-- a paid receipt (CosmeticProfiles.reviveReceipt has stored it as a credit). Applies it to this player's open robux offer,
-- else it stays saved for their next match.
function Service.purchased(userId: number,purchaseId: string)
    local offer=offers[userId]
    if offer and offer.state=="open" and offer.cost=="robux" and Service.clock()<=offer.deadline+Service.PURCHASE_GRACE then
        offer.state="claiming"
        local C=Service.cosmetics()
        local marker=if C and C.reviveConsume then C.reviveConsume(userId,"credit",purchaseId) else nil
        if marker then offer.marker=marker;offer.hooks.apply(offer);return end
        if offer.state=="claiming" then offer.state="open" end
    end
    Service.saved(userId)
end
-- the match's answer to hooks.apply: ok = revived; not ok = the rules failed meanwhile (the use comes back)
function Service.applied(offer: any,ok: boolean)
    if not ok and offer.marker then
        local C=Service.cosmetics()
        local userId,marker=offer.userId,offer.marker
        if C and C.reviveRefund then task.spawn(function() C.reviveRefund(userId,marker) end) end
    end
    Service.close(offer,if ok then "taken" else "failed")
end
-- a paid Revive that couldn't apply: "Revive saved for your next match" (a Notice on the match State remote). Tests replace it.
function Service.saved(userId: number)
    local player=game:GetService("Players"):GetPlayerByUserId(userId)
    if not player then return end
    local Remotes=require(game:GetService("ReplicatedStorage").Shared.Remotes)
    Remotes.server().State:FireClient(player,{kind="Notice",message="Revive saved for your next match"})
end
return Service
