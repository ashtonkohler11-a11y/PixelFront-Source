--!strict
-- PF012: truthful country/unit data shared by the cursor hover card and the top
-- inspector strip, plus the card placement rule. Pure: no instances, no commands.
local Shared=game:GetService("ReplicatedStorage").Shared
local Rules=require(Shared.OpenFrontDiplomacy)
local ClientNames=require(Shared.OpenFrontClientNames)
local Simulation=require(Shared.Simulation) -- PF021: the shared troop reserve share
local Model={}
Model.Revision="PF012-2026-10-05-v1"
Model.ME=1

-- Only an active land attack between the two owners, in either direction.
function Model.atWar(state: any,a: number,b: number): boolean
    for _,attack in state.attacks or {} do
        if attack.active~=false and not attack.retreated and ((attack.owner==a and attack.targetOwner==b) or (attack.owner==b and attack.targetOwner==a)) then return true end
    end
    return false
end
-- YOU > ALLY > AT WAR > TRIBE > NEUTRAL; the first one that is true wins.
function Model.chip(state: any,owner: number,me: number?): string
    me=me or Model.ME
    if owner==me then return "YOU" end
    if Rules.friendly(state,me :: number,owner,true) then return "ALLY" end
    if Model.atWar(state,me :: number,owner) then return "AT WAR" end
    local player=state.players and state.players[owner]
    if player and player.playerType=="Bot" then return "TRIBE" end
    return "NEUTRAL"
end
function Model.kind(player: any?): string?
    if not player then return nil end
    return if player.playerType=="Nation" then "Nation" elseif player.playerType=="Bot" then "Tribe" elseif player.playerType=="Human" then "Player" else nil
end
-- MapRenderer.terrainColor bands: bit7 land, bit6 shore, low five bits magnitude.
function Model.terrain(state: any,tile: number?): string?
    local map=state.map
    if not tile or not map or type(map.terrain)~="buffer" or tile<1 or tile>buffer.len(map.terrain) then return nil end
    local value=buffer.readu8(map.terrain,tile-1)
    if bit32.band(value,128)==0 then return nil end
    local magnitude=bit32.band(value,31)
    if magnitude==31 then return nil end
    if bit32.band(value,64)~=0 then return "Coast" end
    return if magnitude<10 then "Plains" elseif magnitude<20 then "Highland" else "Mountains"
end
-- Same denominator as the leaderboard and the world-share readout.
function Model.landShare(state: any,owner: number): number
    local valid=((state.map and state.map.landCount) or 0)-(state.falloutCount or 0)
    return if valid>0 then (state.counts[owner] or 0)/valid*100 else 0
end
-- UI audit 2026-10-28 (one land share, three formats on one screen): the leaderboard's format everywhere: one decimal, and
-- "<0.1%" while any land is held below it (tester round 2026-10-13, BILLY: land never reads 0.0% while any is held)
function Model.percent(value: number): string
    if value~=value or value<=0 then return "0%" end
    if value<.05 then return "<0.1%" end
    return string.format("%.1f%%",math.floor(value*10+.5)/10)
end
function Model.clock(seconds: number): string
    local whole=math.max(0,math.floor(seconds))
    return string.format("%d:%02d",whole//60,whole%60)
end
function Model.allianceSeconds(state: any,owner: number,me: number?): number?
    me=me or Model.ME
    if owner==me then return nil end
    local alliance=Rules.allianceWith(state,me :: number,owner)
    return if alliance then math.max(0,math.floor((alliance.expiresAt-state.ticks)/10)) else nil
end
-- PF044: a party alliance (PartyAllies, party=true) lasts the whole match: shown as a "Party" tag, never a timer
function Model.partyAlly(state: any,owner: number,me: number?): boolean
    me=me or Model.ME
    if owner==me then return false end
    local alliance=Rules.allianceWith(state,me :: number,owner)
    return alliance~=nil and alliance.party==true
end
function Model.expiryTone(seconds: number?): string
    return if seconds==nil then "none" elseif seconds<=30 then "danger" elseif seconds<=60 then "warning" else "positive"
end

-- PF021 (PF - 3; Ashton: "a troop and max troop bar when hovering nations"): troops vs
-- the server's max troops for ANY owner (state.caps = Simulation.capacity, sent every
-- snapshot), plus the troops away attacking (OpenFront's PlayerInfoOverlay bar: home in
-- cobalt, attacking in gold). floor = the reserve humans can't attack below (none for bots).
function Model.troopBar(state: any,owner: number,options: any): any?
    local player=state.players and state.players[owner]
    local cap=state.caps and state.caps[owner] or 0
    if not player or cap<=0 then return nil end
    local troops=state.troops and state.troops[owner] or 0
    local attacking=0
    for _,attack in state.attacks or {} do if attack.owner==owner then attacking+=attack.budget or 0 end end
    local home=math.clamp(troops/cap,0,1);local away=math.clamp(attacking/cap,0,1-home)
    local format=options.formatTroops
    local rate=state.troopRates and state.troopRates[owner] or 0
    local text=format(troops).." / "..format(cap)
    local bar={troops=troops,max=cap,attacking=attacking,home=home,away=away,text=text,
        rich="<b>"..format(troops).."</b><font color=\"#9a9a9a\"> / "..format(cap).."</font>",
        rate=if rate>0 then "+"..format(rate).."/s" else nil,
        attackingText=if attacking>=1 then format(attacking).." attacking" else nil,
        floor=if player.playerType=="Human" and cap<1000000000 and cap>0 then Simulation.reserveOf(troops,cap)/cap else nil} -- PF043: the actual reserve
    bar.key=string.format("%s|%.4f|%.4f|%s|%s",text,home,away,bar.rate or "",bar.attackingText or "")
    return bar
end
-- options: me, tile, formatNumber, formatTroops, ratio, canAct, canAttack(tile),
-- leftClickOpensMenu, placing, preferences, color(owner)->Color3?
function Model.country(state: any,owner: number,options: any): any?
    local player=state.players and state.players[owner]
    if not player or owner<=0 then return nil end
    local me=options.me or Model.ME
    local chip=Model.chip(state,owner,me)
    local kind=Model.kind(player)
    local terrain=if options.tile then Model.terrain(state,options.tile) else nil
    local subtitle=if kind and terrain then kind.." · "..terrain elseif kind then kind else nil
    local alliance=Model.allianceSeconds(state,owner,me)
    local gold=state.gold and state.gold[owner] or 0
    local rows={
        {id="troops",label="Troops",value=options.formatTroops(state.troops[owner] or 0)},
        {id="land",label="Land",value=Model.percent(Model.landShare(state,owner))},
        {id="gold",label="Gold",value=options.formatNumber(gold),tone="gold"},
    }
    if alliance and Model.partyAlly(state,owner,me) then table.insert(rows,{id="alliance",label="Alliance",short="Ally",value="Party",tone="positive"})
    elseif alliance then table.insert(rows,{id="alliance",label="Alliance ends",short="Ally",value=Model.clock(alliance),tone=Model.expiryTone(alliance)}) end
    local attack: string?=nil
    local reach: string?=nil -- PIVOT onboarding board: a rival you can't reach over land says how you can
    if owner~=me and options.tile and not options.placing and (options.canAct==nil or options.canAct()) and options.canAttack then
        if options.canAttack(options.tile) then
            local amount=(state.troops[me] or 0)*(options.ratio or 0)
            if amount>=1 then attack=(if options.leftClickOpensMenu then "Shift+click: attack with " else "Click: attack with ")..options.formatTroops(amount) end
        elseif chip~="ALLY" and (state.counts and (state.counts[me] or 0)>0) then
            reach="No border · send a boat"
        end
    end
    -- PF - 4 (HUD 1 redesign, Ashton "Good, build it"): the v2 card's parts. Stat tiles, the badge's alliance clock, a
    -- versus line against a rival you can attack, and the footer's actions (the card picks mouse / pad / touch keys)
    local sendAmount=if attack then (state.troops[me] or 0)*(options.ratio or 0) else nil
    local badge=chip
    if alliance and Model.partyAlly(state,owner,me) then badge="ALLY · PARTY" elseif alliance then badge="ALLY · "..Model.clock(alliance) end
    local actions={}
    if sendAmount then table.insert(actions,{id="primary",text=(if chip=="TRIBE" then "Take it · " else "Attack ")..options.formatTroops(sendAmount),alt=options.leftClickOpensMenu==true}) end
    if reach then table.insert(actions,{id="reach",text=reach,tone="warning"}) end
    if options.tile and not options.placing then table.insert(actions,{id="more",text=if owner==me then "Actions" else "More"}) end
    return {kind="country",owner=owner,name=ClientNames.resolve(state,owner,options.preferences),color=if options.color then options.color(owner) else nil,
        chip=chip,badge=badge,subtitle=subtitle,rows=rows,attack=attack,reach=reach,more=if options.tile and not options.placing then "Right-click for more actions" else nil,
        troopBar=Model.troopBar(state,owner,options),
        tiles={land=Model.percent(Model.landShare(state,owner)),gold=options.formatNumber(gold)},
        versus=if sendAmount and chip~="TRIBE" then Model.versus(state,owner,sendAmount,options) else nil,
        actions=actions}
end
-- The versus line: what you'd send against what they hold, and a plain verdict (a hint, not the combat maths): an even
-- fight from 0.8x their troops, an easy win from 1.5x; short of that, the Send share that would reach 0.8x
function Model.versus(state: any,owner: number,send: number,options: any): any
    local hold=state.troops and state.troops[owner] or 0
    local mine=state.troops and state.troops[options.me or Model.ME] or 0
    local share=if send+hold>0 then send/(send+hold) else 1
    local verdict,tone
    if hold<=0 or send>=hold*1.5 then verdict,tone="Easy win","positive"
    elseif send>=hold*.8 then verdict,tone="Even fight","warning"
    else
        local need=if mine>0 then math.ceil(hold*.8/mine*10)*10 else math.huge
        verdict=if need<=100 then "Too strong · raise Send to "..need.."%" else "Too strong · grow first"
        tone="danger"
    end
    return {sendText="You send "..options.formatTroops(send),holdText=options.formatTroops(hold).." hold",share=share,verdict=verdict,tone=tone,
        key=string.format("%.3f|%s",share,verdict)}
end
-- Open land under the cursor (no owner): the smallest card, only when a click there does something
function Model.openLand(state: any,tile: number,options: any): any?
    if not tile or (state.owners and (state.owners[tile] or 0)>0) then return nil end
    local terrain=Model.terrain(state,tile);if not terrain then return nil end
    local text=nil
    if state.phase=="Choosing" then text="Start here"
    elseif not options.placing and options.canAttack and options.canAttack(tile) then text="Expand here" end
    if not text then return nil end
    return {kind="land",owner=0,name="Open land",chip="",badge=nil,subtitle=terrain.." · nobody's",rows={},color=Color3.fromRGB(138,143,153),
        actions={{id="primary",text=text}}}
end
function Model.unitKind(state: any,unit: any): string
    local kind=unit.unitType or (if table.find(state.warships or {},unit) then "Warship" elseif table.find(state.tradeShips or {},unit) then "Trade Ship" else "Transport")
    return if kind=="Transport" or kind=="Transport Ship" then "Transport ship" elseif kind=="Trade Ship" then "Trade ship" else kind
end
function Model.unit(state: any,unit: any,options: any): any?
    local player=state.players and state.players[unit.owner]
    if not player then return nil end
    local kind=Model.unitKind(state,unit)
    local rows={}
    if unit.health~=nil then table.insert(rows,{id="health",label="Health",value=tostring(unit.health)}) end
    if kind=="Transport ship" then table.insert(rows,{id="troops",label="Troops",value=options.formatTroops(unit.troops or 0)}) end
    if type(unit.speed)=="number" then table.insert(rows,{id="speed",label="Speed",value=tostring(unit.speed)}) end
    return {kind="unit",owner=unit.owner,name=ClientNames.resolve(state,unit.owner,options.preferences),color=if options.color then options.color(unit.owner) else nil,
        chip=Model.chip(state,unit.owner,options.me or Model.ME),subtitle=kind,rows=rows,attack=nil,more=nil}
end

-- "Latvia was eliminated by Kazakhstan". Tribes and the local player's own
-- elimination return nil. Returns text, focus owner, notice kind.
function Model.elimination(state: any,victim: number?,captor: number?,gold: number?,options: any): (string?,number?,string?)
    local me=options.me or Model.ME
    local player=victim and state.players and state.players[victim]
    if not victim or not player or victim==me or player.playerType=="Bot" then return nil,nil,nil end
    local victimName=ClientNames.resolve(state,victim,options.preferences)
    if captor==me then
        local bonus=if gold and gold>0 and options.formatNumber then " (+"..options.formatNumber(gold).." gold)" else ""
        return "You eliminated "..victimName..bonus,nil,"ELIMINATION"
    end
    if captor and state.players[captor] then
        return victimName.." was eliminated by "..ClientNames.resolve(state,captor,options.preferences),captor,"ELIMINATION"
    end
    return victimName.." was eliminated",nil,"ELIMINATION"
end

local function overlaps(a: any,b: any): boolean
    return a.x0<b.x1 and a.x1>b.x0 and a.y0<b.y1 and a.y1>b.y0
end
Model.overlaps=overlaps
function Model.rect(x0: number,y0: number,x1: number,y1: number): any return {x0=x0,y0=y0,x1=x1,y1=y1} end
-- Offset from the cursor: right/below by default, flipped to the other side at
-- a screen edge (never slid back under the cursor), only sliding vertically.
-- Rejected when it would cover the pointed spot or any avoided HUD rect; nil
-- means "do not show" (the inspector strip still carries the same stats).
function Model.place(width: number,height: number,cursor: Vector2,bounds: any,avoid: {any},gap: number?): Vector2?
    local g=gap or 18
    if width>bounds.x1-bounds.x0 or height>bounds.y1-bounds.y0 then return nil end
    local cx,cy=cursor.X,cursor.Y
    local spot=Model.rect(cx-12,cy-12,cx+12,cy+12)
    local right,left=cx+g,cx-g-width
    local candidates={{right,cy+g},{left,cy+g},{right,cy-g-height},{left,cy-g-height},{right,cy-height/2},{left,cy-height/2}}
    local function try(x: number,y: number,slideX: boolean): Vector2?
        if not slideX and (x<bounds.x0 or x+width>bounds.x1) then return nil end
        x=math.clamp(x,bounds.x0,bounds.x1-width);y=math.clamp(y,bounds.y0,bounds.y1-height)
        local box=Model.rect(x,y,x+width,y+height)
        if overlaps(box,spot) then return nil end
        for _,zone in avoid do if overlaps(box,zone) then return nil end end
        return Vector2.new(math.floor(x+.5),math.floor(y+.5))
    end
    for _,candidate in candidates do local hit=try(candidate[1],candidate[2],false);if hit then return hit end end
    -- Too narrow for either side: allow a horizontal slide as a last resort.
    for _,candidate in candidates do local hit=try(candidate[1],candidate[2],true);if hit then return hit end end
    return nil
end
return table.freeze(Model)
