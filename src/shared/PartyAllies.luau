--!strict
-- PF044 party auto-ally (PF - 3; pivot 2026-10-23 §0b, Ashton: "have the party system auto ally you with your friends";
-- confirmed "auto-allied at the start, but can be broken/betrayed like normal alliances"). Humans who came in the same
-- party start the match allied with each other: a normal alliance otherwise (it can be broken and betrayed like any
-- other). Teammates (Teams mode) are already friendly, and a match with alliances off makes none.
-- Ashton 2026-10-24: party alliances last the WHOLE match (still breakable): one expires at the match's hard time limit
-- (plus the spawn phase), so it never runs out first; the alliance timer shows the match's time left.
-- humans = the frozen manifest's {userId, party?}. Run once on a fresh state (PublicMatchRuntime.new). Returns the count.
local Diplomacy=require(script.Parent.OpenFrontDiplomacy)
local GameConfig=require(script.Parent.OpenFrontGameConfig)
local PartyAllies={}
function PartyAllies.apply(state: any,humans: {any}): number
    local config=GameConfig.forState(state)
    if config.Diplomacy and config.Diplomacy.Enabled==false then return 0 end
    local owners={}
    for owner,player in state.players do if player.playerType=="Human" then owners[player.clientID]=owner end end
    local groups,names={},{}
    for _,human in humans do
        local owner=type(human)=="table" and type(human.party)=="string" and human.party~="" and owners[tostring(human.userId)]
        if owner then
            if not groups[human.party] then groups[human.party]={};table.insert(names,human.party) end
            table.insert(groups[human.party],owner)
        end
    end
    table.sort(names) -- the same alliance ids on every run of the same match
    -- the whole match in ticks (10 a second): the hard time limit + 2 min for the spawn phase; 4 h if a match has none
    local limit=config.Match and config.Match.HardTimeLimitSeconds
    local wholeMatch=math.floor(((if type(limit)=="number" and limit==limit and limit<math.huge then limit else 14400)+120)*10)
    local made=0
    for _,name in names do
        local list=groups[name];table.sort(list)
        for i=1,#list do for j=i+1,#list do
            local a,b=list[i],list[j]
            if not Diplomacy.sameTeam(state,a,b) and not Diplomacy.allianceWith(state,a,b) then
                local request=Diplomacy.createRequest(state,a,b)
                if request then
                    Diplomacy.acceptRequest(state,request);made+=1
                    local alliance=Diplomacy.allianceWith(state,a,b)
                    -- party=true (PF - 2): the client shows a "Party" tag, not a timer, and the alliance never offers an extend
                    if alliance then alliance.expiresAt=state.ticks+wholeMatch;alliance.party=true end
                end
            end
        end end
    end
    return made
end
return table.freeze(PartyAllies)
