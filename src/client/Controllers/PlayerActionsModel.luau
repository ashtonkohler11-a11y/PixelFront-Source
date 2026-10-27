--!strict
-- PF022 (PF - 3): truthful data for the in-match player card, its give sheet and the radial's
-- disabled-slice reasons. Pure: no instances, no commands. Enabled flags come straight from
-- OpenFrontDiplomacy (the same queries the commands use); a reason is derived only to explain a
-- disabled action, by reading the same per-player records the rules read (requestHistory,
-- sentDonations, targets, outgoingEmojis, lastEmbargoAllTick), so a countdown ends when the rule does.
local Shared=game:GetService("ReplicatedStorage").Shared
local Rules=require(Shared.OpenFrontDiplomacy)
local GameConfig=require(Shared.OpenFrontGameConfig)
local Simulation=require(Shared.Simulation)
local Hud=require(script.Parent.HudInspectorModel)
local ClientNames=require(Shared.OpenFrontClientNames)
local M={}
M.Revision="PF022-2026-10-07-v1"
M.ME=1
-- OpenFrontDiplomacy's tuning(): the match config first, then the source defaults.
local DEFAULTS={RequestCooldownTicks=300,DonationCooldownTicks=100,EmbargoAllCooldownTicks=100,TraitorTicks=300,ExtensionPromptTicks=300}
function M.tuning(state: any,name: string): number
    local config=GameConfig.forState(state)
    return (config.Diplomacy and config.Diplomacy[name]) or DEFAULTS[name]
end
local TARGET_COOLDOWN,EMOJI_COOLDOWN=150,50 -- OpenFrontDiplomacy.canTarget / canSendEmoji
function M.clock(seconds: number): string
    local whole=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",whole//60,whole%60)
end
local function record(state: any,owner: number): any return state.diplomacy and state.diplomacy[owner] end
local function alive(state: any,owner: number): boolean return (state.counts[owner] or 0)>0 end
local function offline(state: any,owner: number): boolean return state.players[owner]~=nil and state.players[owner].isDisconnected==true end
local function seconds(ticks: number): number return math.max(0,ticks)/10 end
local function wait(prefix: string,remaining: number): string return prefix.." "..M.clock(seconds(remaining)) end

-- Why an alliance request can't be sent now (nil when it can). Mirrors canSendAllianceRequest.
function M.allianceReason(state: any,a: number,b: number): string?
    if Rules.canSendAllianceRequest(state,a,b) then return nil end
    local config=GameConfig.forState(state)
    if config.Diplomacy and config.Diplomacy.Enabled==false then return "Alliances off" end
    if not alive(state,a) then return "You're out" end
    if offline(state,b) then return "Offline" end
    if offline(state,a) then return "Reconnecting" end
    if Rules.sameTeam(state,a,b) then return "Teammate" end
    if Rules.allianceWith(state,a,b) then return "Allied" end
    for _,request in Rules.outgoingRequests(state,a) do if request.recipient==b then return "Asked" end end
    local recent=nil
    for _,request in (record(state,a) or {}).requestHistory or {} do if request.recipient==b and (recent==nil or request.createdAt>recent) then recent=request.createdAt end end
    if recent then return wait("Wait",M.tuning(state,"RequestCooldownTicks")-(state.ticks-recent)) end
    return "Not now"
end
-- Why a gift can't be sent now (nil when it can). Mirrors canDonate.
function M.giftReason(state: any,a: number,b: number,kind: string): string?
    local can=if kind=="gold" then Rules.canDonateGold(state,a,b) else Rules.canDonateTroops(state,a,b)
    if can then return nil end
    if not alive(state,a) then return "You're out" end
    if not alive(state,b) then return "Eliminated" end
    if not Rules.friendly(state,a,b) then return "Allies only" end
    local config=GameConfig.forState(state)
    if state.players[b].playerType=="Human" and config.Diplomacy and config.Diplomacy[if kind=="gold" then "DonateGold" else "DonateTroops"]==false then return "Gifts off" end
    local latest=nil
    for _,gift in (record(state,a) or {}).sentDonations or {} do if gift.recipient==b and (latest==nil or gift.tick>latest) then latest=gift.tick end end
    if latest then return wait("Wait",M.tuning(state,"DonationCooldownTicks")-(state.ticks-latest)) end
    return "Not now"
end
function M.targetReason(state: any,a: number,b: number): string?
    if Rules.canTarget(state,a,b) then return nil end
    if Rules.friendly(state,a,b) then return "Allied" end
    local latest=nil
    for _,entry in (record(state,a) or {}).targets or {} do if latest==nil or entry.tick>latest then latest=entry.tick end end
    if latest then return wait("Wait",TARGET_COOLDOWN-(state.ticks-latest)) end
    return "Not now"
end
function M.emojiReason(state: any,a: number,b: number): string?
    if Rules.canSendEmoji(state,a,b) then return nil end
    local latest=nil
    for _,msg in (record(state,a) or {}).outgoingEmojis or {} do if msg.recipientID==b and (latest==nil or msg.createdAt>latest) then latest=msg.createdAt end end
    if latest then return wait("Wait",EMOJI_COOLDOWN-(state.ticks-latest)) end
    return "Not now"
end
function M.embargoAllReason(state: any,a: number): string?
    if Rules.canEmbargoAll(state,a) then return nil end
    local last=(record(state,a) or {}).lastEmbargoAllTick or -1
    local remaining=M.tuning(state,"EmbargoAllCooldownTicks")-(state.ticks-last)
    if last>=0 and remaining>0 then return wait("Wait",remaining) end
    return "No one to stop"
end

-- One action button: id (the controller's handler), label, sub (detail or reason), icon name,
-- tone (positive | danger | gold | accent | text), enabled.
local function action(id: string,label: string,icon: string,tone: string,enabled: boolean,reason: string?,detail: string?): any
    return {id=id,label=label,icon=icon,tone=tone,enabled=enabled,sub=if enabled then detail else reason,reason=if enabled then nil else reason}
end
-- The card for `owner` as seen by the local player. options: formatNumber, formatTroops,
-- preferences, color(owner), directionUp(), playing (match running and the local player alive).
-- PF023: the local player's user id (the own owner's clientID can be empty in Solo).
function M.localUserId(): number?
    local localPlayer=game:GetService("Players").LocalPlayer
    return if localPlayer then localPlayer.UserId else nil
end
function M.card(state: any,owner: number,options: any): any?
    local player=state.players and state.players[owner]
    if not player or owner<=0 then return nil end
    local me=M.ME;local own=owner==me
    local playing=options.playing~=false and state.phase~="Choosing" and alive(state,me)
    local chip=Hud.chip(state,owner,me)
    local traitor=Rules.traitorRemainingTicks(state,owner)
    local subtitle=Hud.kind(player) or "Nation"
    local tone="muted"
    if traitor>0 then subtitle..=" · Traitor "..M.clock(seconds(traitor));tone="danger"
    elseif not own and player.playerType=="Nation" and not Rules.friendly(state,me,owner) then
        local relation=Rules.relation(state,owner,me)
        subtitle..=" · "..(if relation==0 then "Hostile" elseif relation==1 then "Distrustful" elseif relation==3 then "Friendly" else "Neutral")
        tone=if relation<=1 then "danger" elseif relation==3 then "positive" else "muted"
    end
    if offline(state,owner) then subtitle..=" · Offline" end
    local alliance=Hud.allianceSeconds(state,owner,me)
    local data=record(state,owner) or {}
    local stats={
        {id="gold",caption="GOLD",value=options.formatNumber(state.gold and state.gold[owner] or 0),tone="gold"},
        {id="land",caption="LAND",value=Hud.percent(Hud.landShare(state,owner))},
        if alliance and Hud.partyAlly(state,owner,me) then {id="alliance",caption="ALLIANCE",value="Party",tone="positive"} -- PF044: no timer
        elseif alliance then {id="alliance",caption="ALLIANCE",value=Hud.clock(alliance),tone=Hud.expiryTone(alliance)}
        else {id="betrayals",caption="BETRAYALS",value=tostring(data.betrayalCount or 0),tone=if (data.betrayalCount or 0)>0 then "danger" else nil},
    }
    local embargoed=Rules.hasEmbargo(state,owner,me)
    local allies={}
    for _,a in Rules.alliances(state,owner) do
        local other=if a.requestor==owner then a.recipient else a.requestor
        local left=math.max(0,math.floor((a.expiresAt-state.ticks)/10))
        if a.party==true then -- PF044: a party ally shows a "Party" tag, sorted after every timed alliance
            table.insert(allies,{owner=other,name=ClientNames.resolve(state,other,options.preferences),seconds=math.huge,value="Party",tone="positive",party=true})
        else table.insert(allies,{owner=other,name=ClientNames.resolve(state,other,options.preferences),seconds=left,value=Hud.clock(left),tone=Hud.expiryTone(left)}) end
    end
    table.sort(allies,function(x,y) return if x.seconds==y.seconds then string.lower(x.name)<string.lower(y.name) else x.seconds<y.seconds end)
    local groups={}
    local out=if not alive(state,me) then "You're out" elseif state.phase=="Choosing" then "Spawning" else nil
    if own then
        local up=options.directionUp==nil or options.directionUp()
        local stopReason=out or M.embargoAllReason(state,me)
        table.insert(groups,{id="nation",title="YOUR NATION",actions={
            action("Trajectory","Rocket arc","AtomBomb","text",playing,out,if up then "Arc up" else "Arc down"),
            action("StopTradingAll","Stop all trade","DiplomacyStopTrade","gold",playing and stopReason==nil,stopReason,"Every nation"),
            action("StartTradingAll","Resume trade","DiplomacyStartTrade","positive",playing and stopReason==nil,stopReason,"Every nation"),
        }})
        table.insert(groups,{id="social",title="SOCIAL",actions={
            action("Emoji","Emote","DiplomacyEmoji","text",playing and Rules.canSendEmoji(state,me,0),out or M.emojiReason(state,me,0),"To everyone"),
            action("Chat","Quick chat","QuickChat","text",playing,out,"Send a phrase"),
        }})
    else
        local query=Rules.interaction(state,me,owner)
        local info=query.allianceInfo
        local diplomacy
        if info and info.inExtensionWindow then
            diplomacy=action("AllianceExtend","Extend","DiplomacyAlliance","positive",playing and info.canExtend==true,
                out or (if info.myPlayerAgreedToExtend then "Waiting" else "Not now"),if info.otherAgreedToExtend then "They agreed" else "Ends "..Hud.clock(alliance or 0))
        elseif query.canBreakAlliance then
            -- breakAlliance marks the breaker a traitor unless the ally already is one or is offline.
            local safe=Rules.isTraitor(state,owner) or offline(state,owner)
            diplomacy=action("BreakAlliance","Break","DiplomacyBreak","danger",playing,out,if safe then "No penalty" else "Traitor "..math.floor(M.tuning(state,"TraitorTicks")/10).."s")
        else
            local reason=out or M.allianceReason(state,me,owner)
            diplomacy=action("AllianceRequest","Ally","DiplomacyAlliance","positive",playing and query.canSendAllianceRequest,reason,"Ask to ally")
        end
        local trade=action("Trade",if query.canEmbargo then "Stop trade" else "Trade",if query.canEmbargo then "DiplomacyStopTrade" else "DiplomacyStartTrade",
            if query.canEmbargo then "gold" else "positive",playing,out,if embargoed then "They stopped" elseif query.canEmbargo then "Block ships" else "Allow ships")
        local target=action("Target","Target","DiplomacyTarget","danger",playing and query.canTarget,out or M.targetReason(state,me,owner),"Mark for allies")
        table.insert(groups,{id="diplomacy",title="DIPLOMACY",actions={diplomacy,trade,target}})
        table.insert(groups,{id="give",title="GIVE",actions={
            action("DonateTroops","Troops","DiplomacyDonateTroops","accent",playing and query.canDonateTroops,out or M.giftReason(state,me,owner,"troops"),"Send troops"),
            action("DonateGold","Gold","DiplomacyDonateGold","gold",playing and query.canDonateGold,out or M.giftReason(state,me,owner,"gold"),"Send gold"),
        }})
        table.insert(groups,{id="social",title="SOCIAL",actions={
            action("Emoji","Emote","DiplomacyEmoji","text",playing and query.canSendEmoji,out or M.emojiReason(state,me,owner),"Send an emoji"),
            action("Chat","Quick chat","QuickChat","text",playing,out,"Send a phrase"),
        }})
    end
    return {owner=owner,own=own,name=ClientNames.resolve(state,owner,options.preferences),color=if options.color then options.color(owner) else nil,
        chip=chip,subtitle=subtitle,subtitleTone=tone,traitor=traitor>0,
        -- PF023 L4: a human's Roblox user id (the level badge reads that Player's OpenFrontLevel)
        userId=if player.playerType=="Human" then (tonumber(player.clientID) or (if own then M.localUserId() else nil)) else nil,
        troopBar=Hud.troopBar(state,owner,{formatTroops=options.formatTroops}),
        stats=stats,trade=if embargoed then "They stopped trading with you" elseif Rules.hasEmbargo(state,me,owner) then "You stopped trading" else "Trading active",
        tradeTone=if embargoed or Rules.hasEmbargo(state,me,owner) then "gold" else "muted",
        allies=allies,groups=groups}
end

-- PF014: the share of max troops a human always keeps at home (attacks, boats and troop gifts).
function M.reserve(state: any,owner: number): number
    local player=state.players and state.players[owner]
    local cap=state.caps and state.caps[owner] or 0
    if not player or player.playerType~="Human" or cap<=0 or cap>=1000000000 then return 0 end
    return Simulation.reserveOf(state.troops and state.troops[owner] or 0,cap) -- PF043: up to 20% of max, never over half of what you hold
end
-- The give sheet. amount is the requested amount (DiplomacyPresentation.donation: share of the
-- giver's total, clamped to the ally's room for troops). sends = what the server will actually move
-- (Simulation.reserveClamp keeps the reserve home).
function M.give(state: any,target: number,mode: string,amount: number,options: any): any
    local me=M.ME;local troops=mode=="troops"
    local total=if troops then state.troops[me] or 0 else state.gold[me] or 0
    local room=if troops then math.max(0,(state.caps[target] or 0)-(state.troops[target] or 0)) else nil
    if (state.counts[target] or 0)<=0 then room=0 end
    local reserve=if troops then M.reserve(state,me) else 0
    local sendable=math.max(0,total-reserve)
    local sends=math.floor(math.max(0,math.min(amount,sendable,room or math.huge)))
    local format=if troops then options.formatTroops else options.formatNumber
    local reason=nil
    if total<=0 then reason=if troops then "No troops to give" else "No gold to give"
    elseif room==0 then reason="They're at max troops"
    elseif troops and sendable<1 then reason="All in your reserve"
    elseif sends<1 then reason="Pick an amount" end
    local note
    if troops then
        note=format(reserve).." always stays home (up to "..math.floor(Simulation.TroopReserveShare*100+.5).."% of your max troops)"
        if reserve<=0 then note="No reserve: every troop can be sent" end
    else note="Gold has no reserve" end
    local capped=nil
    if troops and amount>sendable and sendable>=1 then capped="Reserve keeps "..format(reserve).." home"
    elseif room and amount>=room and room>0 then capped="Their room: "..format(room) end
    return {mode=mode,total=total,amount=amount,sends=sends,keep=math.max(0,total-sends),room=room,reserve=reserve,sendable=sendable,
        reserveFraction=if troops and total>0 then math.clamp(reserve/total,0,1) else 0,
        roomFraction=if room and total>0 then math.clamp(room/total,0,1) else nil,
        theirs=if troops then state.troops[target] or 0 else state.gold[target] or 0,theirMax=if troops then state.caps[target] or 0 else nil,
        enabled=reason==nil,reason=reason,note=note,capped=capped,roomText=if room and room>0 then format(room) else nil,
        amountText=format(sends),keepText=format(math.max(0,total-sends)),
        title=(if troops then "Give troops to " else "Give gold to ")..ClientNames.resolve(state,target,options.preferences)}
end

-- Radial root slices: the reason shown on a disabled slice (nil = enabled or no reason).
function M.sliceReason(state: any,name: string,owner: number): string?
    local me=M.ME
    if state.phase=="Choosing" then return if name=="Info" then nil else "Spawning" end
    if owner<=0 then return nil end
    if name=="AllianceRequest" then local r=M.allianceReason(state,me,owner);return if r then (if string.sub(r,1,5)=="Wait " then "Ally in "..string.sub(r,6) else r) else nil end
    if name=="AllianceExtend" then
        local info=Rules.allianceInfo(state,me,owner)
        return if info and info.canExtend then nil elseif info and info.myPlayerAgreedToExtend then "Waiting" else nil
    end
    if name=="DonateGold" then local r=M.giftReason(state,me,owner,"gold");return if r then (if string.sub(r,1,5)=="Wait " then "Gift in "..string.sub(r,6) else r) else nil end
    return nil
end
return table.freeze(M)
