--!strict
--!native
-- NationEmojiBehavior and response helpers, OpenFrontIO 93a136a1.
-- All emoji indices below are the source flattenedEmojiTable's zero-based IDs.
local Random = require(script.Parent.OpenFrontRandom)
local Emoji = {}
Emoji.Lists = table.freeze({
    AssistAccept = {20,25,41}, AssistLowRelation = {12,24}, AssistTargetMe = {6,32}, AssistTargetAlly = {27,21},
    AggressiveAttack = {10}, Attack = {9}, WarshipRetaliation = {52}, Nuke = {33,31},
    GotInsulted = {14,9,11,5,7}, Love = {48,1,2}, Confused = {57,11}, Brag = {38,39,19},
    CharmAllies = {25,3,19}, Clown = {11,24}, Rat = {59}, Overwhelmed = {32,26,8,6,7,5,13,15},
    Congratulate = {16}, Scared = {18,6}, Bored = {12}, Handshake = {25}, DonationOK = {20},
    DonationTooSmall = {57,12}, Greet = {15},
})
local function chance(random: any, odds: number): boolean return Random.int(random,0,odds)==0 end
local function pick(random: any, list: {number}): number return list[Random.int(random,0,#list)+1] end
local function brain(state: any, owner: number): any
    local nation=state.nations[owner]
    nation.lastEmojiSent=nation.lastEmojiSent or {}
    return nation
end
local function shouldSend(state: any, owner: number, target: number, limit: boolean): boolean
    if target==0 then return true end
    if state.players[owner].playerType=="Bot" or state.players[target].playerType~="Human" then return false end
    if limit then
        local nation=brain(state,owner)
        if state.ticks-(nation.lastEmojiSent[target] or -300)<=300 then return false end
        -- The source stamps this before canSendEmoji; a blocked send still uses the AI cooldown.
        nation.lastEmojiSent[target]=state.ticks
    end
    return true
end
function Emoji.send(state: any, owner: number, target: number, list: {number}, api: any): boolean
    if not shouldSend(state,owner,target,false) or not api.canSendEmoji(owner,target) then return false end
    api.queueEmoji(owner,target,pick(brain(state,owner).random,list))
    return true
end
function Emoji.maybeSend(state: any, owner: number, target: number, list: {number}, api: any): boolean
    return shouldSend(state,owner,target,true) and Emoji.send(state,owner,target,list,api)
end
function Emoji.maybeSendAttack(state: any, owner: number, target: number, api: any): boolean
    if not shouldSend(state,owner,target,true) then return false end
    local random=brain(state,owner).random
    if api.relation(owner,target)>=2 then
        if not chance(random,2) then return false end
        return Emoji.send(state,owner,target,Emoji.Lists.AggressiveAttack,api)
    end
    if not chance(random,4) then return false end
    return Emoji.send(state,owner,target,Emoji.Lists.Attack,api)
end
function Emoji.casual(state: any, owner: number, api: any)
    local nation=brain(state,owner)
    if nation.emojiGameOver then return end
    local random, lists=nation.random,Emoji.Lists
    local incoming={}
    for _,attack in state.attacks do if attack.active and attack.targetOwner==owner then table.insert(incoming,attack) end end
    if chance(random,16) and #incoming>0 then
        local total=0;for _,attack in incoming do total+=attack.budget end
        if total>=state.troops[owner]*3 then Emoji.send(state,owner,0,lists.Overwhelmed,api) end
    end
    if chance(random,8) and #incoming>0 and state.troops[owner]>0 then
        for _,attack in incoming do
            if state.players[attack.owner].playerType=="Human" and attack.budget<state.troops[owner]*0.1 then
                Emoji.maybeSend(state,owner,attack.owner,if chance(random,2) then lists.Confused else lists.Bored,api)
            end
        end
    end
    if state.winner~=nil then
        nation.emojiGameOver=true
        if state.gameConfig and state.gameConfig.gameMode=="Team" then
            if state.winner~=state.players[owner].team then Emoji.send(state,owner,0,lists.Congratulate,api) end
        else
        local largest,maximum=nil,-1
        for _,other in state.playerOrder do
            if state.counts[other]>0 and state.players[other].playerType=="Nation" and state.counts[other]>maximum then
                largest,maximum=other,state.counts[other]
            end
        end
        if largest==owner and type(state.winner)=="number" then Emoji.send(state,owner,state.winner,lists.Congratulate,api) end
        end
    end
    if chance(random,300) then
        local largest,maximum=nil,-1
        for _,other in state.playerOrder do if state.counts[other]>0 and state.counts[other]>maximum then largest,maximum=other,state.counts[other] end end
        if largest==owner then Emoji.send(state,owner,0,lists.Brag,api) end
    end
    if chance(random,250) then
        local humans={};for _,other in api.allies(owner) do if state.players[other].playerType=="Human" then table.insert(humans,other) end end
        if #humans>0 then
            local other=humans[Random.int(random,0,#humans)+1]
            Emoji.send(state,owner,other,if chance(random,3) then lists.Love else lists.CharmAllies,api)
        end
    end
    if chance(random,40) then
        local traitors={}
        for _,other in state.playerOrder do
            if state.counts[other]>0 and state.players[other].playerType=="Human" and not api.friendly(other,owner) and api.isTraitor(other) then table.insert(traitors,other) end
        end
        if #traitors>0 then Emoji.send(state,owner,traitors[Random.int(random,0,#traitors)+1],lists.Clown,api) end
    end
    if state.ticks>=6000 and chance(random,10000) then
        local small={}
        for _,other in state.playerOrder do
            if state.players[other].playerType=="Human" and state.counts[other]>0 and state.counts[other]<state.map.landCount*0.01 then table.insert(small,other) end
        end
        if #small>0 then Emoji.send(state,owner,small[Random.int(random,0,#small)+1],lists.Rat,api) end
    end
    if state.ticks<=600 and chance(random,250) then
        local humans={};for _,other in api.nearby(owner) do if other>0 and state.players[other].playerType=="Human" then table.insert(humans,other) end end
        if #humans>0 then Emoji.send(state,owner,humans[Random.int(random,0,#humans)+1],lists.Greet,api) end
    end
end
function Emoji.respondToEmoji(state: any, random: any, sender: number, recipient: number, emoji: string, api: any)
    if recipient==0 or state.players[recipient].playerType~="Nation" or not api.canSendEmoji(recipient,sender) then return end
    local list=nil
    -- PixelFront: the insult is index 14 "😤" (source middle-finger emoji, Roblox Community Standards).
    if emoji=="😤" then api.updateRelation(recipient,sender,-100);list=Emoji.Lists.GotInsulted end
    if emoji=="🤡" then api.updateRelation(recipient,sender,-10);list=Emoji.Lists.Confused end
    if table.find({"🕊️","🏳️","❤️","🥰","👏"},emoji) then
        if not state.gameConfig or state.gameConfig.difficulty=="Easy" then api.updateRelation(recipient,sender,15) end
        list=if api.relation(sender,recipient)>=2 then Emoji.Lists.Love else Emoji.Lists.Confused
    end
    if list then api.queueEmoji(recipient,sender,pick(random,list)) end
end
function Emoji.respondToMIRV(state: any, random: any, target: number, api: any)
    if not chance(random,8) or not api.canSendEmoji(target,0) then return end
    api.queueEmoji(target,0,pick(random,Emoji.Lists.Overwhelmed))
end
return table.freeze(Emoji)
