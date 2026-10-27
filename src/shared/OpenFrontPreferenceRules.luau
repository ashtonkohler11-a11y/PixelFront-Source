--!strict
-- AlertFrame and ControlPanel help rules, OpenFront93a136a1.
local Diplomacy=require(script.Parent.OpenFrontDiplomacy)
local MapData=require(script.Parent.MapData)
local Rules={}
function Rules.newAlert(): any return {seen={},outgoing={},lastAlertTick=-1,eventCursor=nil} end
function Rules.alerts(tracker: any,state: any,enabled: boolean): {string}
    local result={};local tick=state.ticks or 0
    if not state.players[1] or (state.counts[1] or 0)<=0 then tracker.seen={};tracker.outgoing={};tracker.lastAlertTick=-1;return result end
    for _,attack in state.attacks or {} do
        if attack.owner==1 and attack.targetOwner~=0 and not attack.retreating then
            local previous=tracker.outgoing[attack.targetOwner]
            if previous==nil or tick-previous>=150 then tracker.outgoing[attack.targetOwner]=tick end
        end
    end
    for owner,at in tracker.outgoing do if tick-at>150 then tracker.outgoing[owner]=nil end end
    local function activate(kind: string)
        if enabled then tracker.lastAlertTick=tick;table.insert(result,kind) end
    end
    if tracker.eventCursor~=nil then
        for _,event in state.diplomacyEvents or {} do
            if (event.eventId or 0)>tracker.eventCursor and event.type=="BrokeAlliance" and event.betrayedID==1 then activate("betrayal") end
        end
    end
    tracker.eventCursor=math.max(tracker.eventCursor or 0,state.diplomacyEventCursor or 0)
    local inCooldown=tracker.lastAlertTick~=-1 and tick-tracker.lastAlertTick<150
    local incoming={};local threshold=(state.troops[1] or 0)/5
    for _,attack in state.attacks or {} do
        if attack.targetOwner~=1 then continue end
        incoming[attack.id]=true
        if not attack.retreating and not tracker.seen[attack.id] then
            local attacker=state.players[attack.owner]
            if attacker and attacker.playerType~="Bot" then
                local ourTick=tracker.outgoing[attack.owner]
                local retaliation=ourTick~=nil and tick-ourTick<150
                if not inCooldown and not retaliation and attack.budget>=threshold then activate("land-attack") end
            end
            tracker.seen[attack.id]=true
        end
    end
    for id in tracker.seen do if not incoming[id] then tracker.seen[id]=nil end end
    return result
end
function Rules.nearbyOwners(state: any): {number}
    local seen={};local result={};local neighbors={}
    -- PF020 bandwidth (PF - 2): the client's own derived border (MatchController updateLocalBorders ->
    -- state.borders[1], the same tiles the server sent as localBorderTiles; v13 no longer sends them)
    local derived=type(state.borders)=="table" and state.borders[1]
    local tiles=if type(derived)=="table" and type(derived.values)=="table" then derived.values else state.localBorderTiles or {}
    for _,tile in tiles do
        if tile==0 then continue end
        MapData.neighbors(tile,state.map.width,state.map.height,neighbors)
        for _,neighbor in neighbors do local owner=state.owners[neighbor] or 0
            if owner~=0 and owner~=1 and not seen[owner] then seen[owner]=true;table.insert(result,owner) end
        end
    end
    return result
end
function Rules.trackHelpAttacks(previous: any,state: any)
    for _,attack in state.attacks or {} do if attack.owner==1 and attack.targetOwner~=0 and not attack.retreating then previous[attack.targetOwner]=state.ticks end end
    for owner,tick in previous do if state.ticks-tick>300 then previous[owner]=nil end end
end
function Rules.help(state: any,nearby: {number},lastAttack: any): any?
    local troops=state.troops[1] or 0
    -- This private singleplayer port cannot enter the source Public/Team-only army-limit branch.
    if troops<10000 and troops>0 then return {type="warning",message="control_panel.low_troops_warning"} end
    for _,owner in nearby do
        local player=state.players[owner];if not player or (state.counts[owner] or 0)<=0 then continue end
        local last=lastAttack[owner] or -1
        if last>=0 and (state.ticks-last)/10<=15 then continue end
        local allied=Diplomacy.allianceWith(state,1,owner)~=nil
        if allied and Diplomacy.isTraitor(state,owner) then return {type="info",message="control_panel.traitor_neighbor_info"} end
        if player.isDisconnected and allied then return {type="info",message="control_panel.allied_afk_neighbor_info"} end
        if player.isDisconnected and Diplomacy.sameTeam(state,1,owner) then return {type="info",message="control_panel.teammate_afk_neighbor_info"} end
    end
    return nil
end
function Rules.alignClusters(nextPositions: {any},previous: {any})
    if #nextPositions~=2 or #previous~=2 then return end
    local function distance(slot: any,point: any): number return math.abs(point.x-slot.dstX)+math.abs(point.y-slot.dstY) end
    if distance(previous[1],nextPositions[2])+distance(previous[2],nextPositions[1])<distance(previous[1],nextPositions[1])+distance(previous[2],nextPositions[2]) then nextPositions[1],nextPositions[2]=nextPositions[2],nextPositions[1] end
end
function Rules.reconcile(entry: any,positions: {any},now: number)
    local nextPositions={};for _,point in positions do table.insert(nextPositions,table.clone(point)) end
    Rules.alignClusters(nextPositions,entry.slots)
    while #entry.slots>#nextPositions do table.remove(entry.slots) end
    for index,nextPoint in nextPositions do
        local slot=entry.slots[index]
        if not slot then
            entry.slots[index]={curX=nextPoint.x,curY=nextPoint.y,srcX=nextPoint.x,srcY=nextPoint.y,dstX=nextPoint.x,dstY=nextPoint.y,startMs=now}
        else
            local t=math.min(1,(now-slot.startMs)/250);local x,y=slot.srcX+(slot.dstX-slot.srcX)*t,slot.srcY+(slot.dstY-slot.srcY)*t
            if math.sqrt((nextPoint.x-x)^2+(nextPoint.y-y)^2)>200 then x,y=nextPoint.x,nextPoint.y end
            slot.curX,slot.curY,slot.srcX,slot.srcY,slot.dstX,slot.dstY,slot.startMs=x,y,x,y,nextPoint.x,nextPoint.y,now
        end
    end
end
return Rules
