--!strict
-- OpenFront 93a136a1 PlayerPanel, SendResourceModal, PlayerView and status GLSL.
local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local Text=require(script.Parent.DiplomacyText)
local P={}
-- PlayerInfoOverlay.maybeShow: independent of the naval-highlight option.
function P.navalUnitAt(state: any, tile: number?): any?
    if not tile or tile < 1 or tile > state.map.width * state.map.height or state.map.land[tile] then return nil end
    local width = state.map.width
    local x, y = (tile - 1) % width, math.floor((tile - 1) / width)
    local best, distance = nil, 2500
    for _, group in {state.warships or {}, state.tradeShips or {}, state.ships or {}} do
        for _, unit in group do
            if unit.active == false then continue end
            local dx, dy = (unit.tileId - 1) % width - x, math.floor((unit.tileId - 1) / width) - y
            local squared = dx * dx + dy * dy
            if squared < distance or (best and squared == distance and unit.id < best.id) then best, distance = unit, squared end
        end
    end
    return best
end
P.PRESETS={10,25,50,75,100}
-- CSS classes resolve through the pinned Tailwind 4.2.4 OKLCH theme in sRGB.
-- RadialMenuElements colors are source literals and remain separate.
P.CSS={Red200=Color3.fromHex("#ffc9c9"),Red300=Color3.fromHex("#ffa2a2"),Red400=Color3.fromHex("#ff6467"),Red500=Color3.fromHex("#fb2c36"),Amber400=Color3.fromHex("#ffb900"),Yellow400=Color3.fromHex("#fdc700"),Green400=Color3.fromHex("#05df72"),Green500=Color3.fromHex("#00c950"),Emerald200=Color3.fromHex("#a4f4cf"),Emerald300=Color3.fromHex("#5ee9b5"),Emerald400=Color3.fromHex("#00d492"),Emerald500=Color3.fromHex("#00bc7d"),Blue400=Color3.fromHex("#50a2ff"),Indigo300=Color3.fromHex("#a3b3ff"),Indigo400=Color3.fromHex("#7c86ff"),Indigo500=Color3.fromHex("#615fff"),Indigo600=Color3.fromHex("#4f39f6"),Gray200=Color3.fromHex("#e5e7eb"),Zinc50=Color3.fromHex("#fafafa"),Zinc100=Color3.fromHex("#f4f4f5"),Zinc200=Color3.fromHex("#e4e4e7"),Zinc400=Color3.fromHex("#9f9fa9"),Zinc500=Color3.fromHex("#71717b"),Zinc700=Color3.fromHex("#3f3f47"),Zinc800=Color3.fromHex("#27272a")}
P.COLORS={Info=Color3.fromHex("#475569"),Alliance=Color3.fromHex("#4ade80"),Break=Color3.fromHex("#dc2626"),SafeBreak=Color3.fromHex("#d97706"),DonateGold=Color3.fromHex("#f59e0b"),Friendly=P.CSS.Emerald200,Neutral=P.CSS.Zinc200,Hostile=P.CSS.Red200,Distrustful=P.CSS.Red300,ExpiryRed=P.CSS.Red400,ExpiryYellow=P.CSS.Yellow400,ExpiryGreen=P.CSS.Emerald400}
function P.noticeColor(kind: string): Color3
    if kind=="ALLIANCE_ACCEPTED" then return P.CSS.Green400 end
    if kind=="ALLIANCE_REJECTED" or kind=="ALLIANCE_BROKEN" then return P.CSS.Red400 end
    if kind=="ATTACK_REQUEST" or kind=="DONATION_SENT" or kind=="DONATION_RECEIVED" then return P.CSS.Blue400 end
    if kind=="ALLIANCE_EXPIRED" or kind=="RENEW_ALLIANCE" then return P.CSS.Yellow400 end
    if kind=="CHAT" or kind=="ALLIANCE_REQUEST" then return P.CSS.Gray200 end
    return Color3.new(1,1,1)
end
function P.actionStyle(variant: string,hovered: boolean): (Color3,number,Color3,number)
    local text=if variant=="red" then P.CSS.Red400 elseif variant=="green" then P.CSS.Emerald400 elseif variant=="yellow" then Color3.fromHex("#f59e0b") elseif variant=="indigo" then P.CSS.Indigo400 else Color3.new(1,1,1)
    if not hovered then return Color3.new(1,1,1),.96,text,if variant=="normal" then .1 else 0 end
    local background=if variant=="red" then P.CSS.Red500 elseif variant=="green" then P.CSS.Emerald500 elseif variant=="yellow" then Color3.fromHex("#f59e0b") elseif variant=="indigo" then P.CSS.Indigo500 else Color3.new(1,1,1)
    text=if variant=="red" then P.CSS.Red300 elseif variant=="green" then P.CSS.Emerald300 elseif variant=="yellow" then Color3.fromHex("#fbbf24") elseif variant=="indigo" then P.CSS.Indigo300 else Color3.new(1,1,1)
    return background,.9,text,0
end
local function config(name: string,default: number): number return if Config.Diplomacy then Config.Diplomacy[name] or default else default end
function P.text(key: string,params: any?): string
    local value=Text[key] or key
    value=string.gsub(value,"{([%w_]+), plural, one {(.-)} other {(.-)}}",function(name,one,other)
        local count=params and params[name] or 0;return string.gsub(if count==1 then one else other,"#",tostring(count))
    end)
    for name,replacement in params or {} do value=string.gsub(value,"{"..name.."}",function() return tostring(replacement) end) end
    return value
end
function P.duration(seconds: number): string
    local n=math.floor(seconds);if n<=0 then return "0"..P.text("common.duration_second_short") end
    local hours,minutes,remaining=math.floor(n/3600),math.floor((n%3600)/60),n%60;local parts={}
    if hours>0 then table.insert(parts,hours..P.text("common.duration_hour_short")) end
    if minutes>0 then table.insert(parts,minutes..P.text("common.duration_minute_short")) end
    if remaining>0 or #parts==0 then table.insert(parts,remaining..P.text("common.duration_second_short")) end
    return table.concat(parts," ")
end
function P.friendly(state: any,a: number,b: number): boolean
    -- Client PlayerView.isFriendly includes AFK allies, unlike attack validation.
    return a~=b and Diplomacy.friendly(state,a,b,true)
end
function P.embargo(state: any,a: number,b: number): boolean
    return a~=b and (Diplomacy.hasEmbargo(state,a,b) or Diplomacy.hasEmbargo(state,b,a))
end
function P.alliance(state: any,a: number,b: number): any? return if a~=b then Diplomacy.allianceWith(state,a,b) else nil end
function P.requesting(state: any,a: number,b: number): boolean
    for _,request in state.diplomacyRequests or {} do if request.requestor==a and request.recipient==b then return true end end;return false
end
function P.expiryColor(seconds: number?): Color3
    return if seconds==nil then Color3.new(1,1,1) elseif seconds<=30 then P.COLORS.ExpiryRed elseif seconds<=60 then P.COLORS.ExpiryYellow else P.COLORS.ExpiryGreen
end
function P.traitorSeconds(state: any,owner: number): number? local ticks=Diplomacy.traitorRemainingTicks(state,owner);return if ticks>0 then math.ceil(ticks/10) else nil end
function P.extensionFraction(state: any,owner: number,target: number): number
    local a=P.alliance(state,owner,target);if a and a.party==true then return 1 end -- PF044: a party alliance never drains
    return if a then math.clamp(math.max(0,a.expiresAt-state.ticks)/math.max(1,config("ExtensionPromptTicks",300)),0,1) else 1
end
function P.root(state: any,tile: number,hasBuildableAttacks: boolean): {any}
    local owner=state.owners[tile] or 0
    local query=if owner>0 then Diplomacy.interaction(state,1,owner) else nil
    local own=owner==1;local disconnected=owner>0 and state.players[owner].isDisconnected==true
    local friendly=owner>0 and P.friendly(state,1,owner)
    local allied=owner>0 and P.alliance(state,1,owner)~=nil
    local inWindow=query and query.allianceInfo and query.allianceInfo.inExtensionWindow
    return { {name="Info",enabled=owner>0 and state.phase~="Choosing"},
        {name=if own then "Delete" elseif allied and not disconnected then "BreakAlliance" else "Boat",enabled=if own then true elseif allied and not disconnected then query.canBreakAlliance else true},
        {name=if not own and inWindow then "AllianceExtend" else "AllianceRequest",enabled=(if not own and inWindow then query.allianceInfo.canExtend else query and query.canSendAllianceRequest)==true},
        {name=if own then "Build" elseif friendly and not disconnected and not hasBuildableAttacks then "DonateGold" else "Attack",enabled=if friendly and not disconnected and not hasBuildableAttacks then query.canDonateGold and state.phase~="Choosing" else state.phase~="Choosing"} }
end
function P.donation(state: any,target: number,mode: string,percent: number): (number,number,number?)
    local total=if mode=="troops" then state.troops[1] or 0 else state.gold[1] or 0
    local capacity=if mode=="troops" then math.max(0,(state.caps[target] or 0)-(state.troops[target] or 0)) else nil
    if (state.counts[1] or 0)<=0 then total=0 end
    if (state.counts[target] or 0)<=0 then capacity=0 end
    local raw=math.floor(total*math.clamp(percent,0,100)/100)
    local amount=math.clamp(raw,0,if capacity then math.min(total,capacity) else total)
    return amount,total,capacity
end
function P.allies(state: any,owner: number): {any}
    local rows={}
    -- PF044: a party ally (party=true) has no timer: seconds=math.huge sorts it last, party=true shows the "Party" tag
    for _,a in Diplomacy.alliances(state,owner) do local other=if a.requestor==owner then a.recipient else a.requestor;table.insert(rows,{owner=other,name=state.names[other] or state.players[other].name,seconds=if a.party==true then math.huge else math.max(0,math.floor((a.expiresAt-state.ticks)/10)),id=a.id,party=if a.party==true then true else nil}) end
    table.sort(rows,function(a,b) return if a.seconds==b.seconds then string.lower(a.name)<string.lower(b.name) else a.seconds<b.seconds end);return rows
end
function P.borderFlags(state: any,owner: number,tile: number): (boolean,boolean)
    local width,height=state.map.width,state.map.height;local x=(tile-1)%width;local neighbors={}
    if x>0 then table.insert(neighbors,tile-1) end;if x<width-1 then table.insert(neighbors,tile+1) end
    if tile>width then table.insert(neighbors,tile-width) end;if tile<=width*(height-1) then table.insert(neighbors,tile+width) end
    local friendly=false
    for _,id in neighbors do local other=state.owners[id];if other and other>0 and other~=owner then if P.embargo(state,owner,other) then return true,friendly end;if P.friendly(state,owner,other) or P.friendly(state,other,owner) then friendly=true end end end
    return false,friendly
end
function P.tint(color: Color3,embargo: boolean,friendly: boolean): Color3
    if not embargo and not friendly then return color end
    local target=if embargo then Color3.new(1,0,0) else Color3.new(0,1,0)
    return Color3.fromRGB(math.round(color.R*255*.65+target.R*255*.35),math.round(color.G*255*.65+target.G*255*.35),math.round(color.B*255*.65+target.B*255*.35))
end
function P.statusFlash(kind: string,remaining: number,time: number): number
    local window=if kind=="Alliance" then config("ExtensionPromptTicks",300)/10 else 15
    local seconds=remaining/10
    if window<=0 or seconds>window or seconds<=0 then return 1 end
    local elapsed=window-seconds;local phase=time*2+elapsed*elapsed*(if kind=="Alliance" then 1.5/window else .1)
    return .3+.7*(.5+.5*math.cos(phase*6.2832))
end
function P.drainCut(fraction: number): number return .20+(1-fraction)*.624 end
function P.troopBar(total: number,attacking: number,maximum: number): (number,number)
    local reserve=math.clamp(total/math.max(1,maximum),0,1)
    return reserve,math.clamp(attacking/math.max(1,maximum),0,1-reserve)
end
function P.hoverName(width: number,params: any): (number,boolean)
    local desktop=width>=1024
    local pressure=if desktop then {perIcon=2,icon=.5,flag=3.5,betrayal=4.2,alliance=6.7,allianceWrapped=3.9} else {perIcon=2.2,icon=.5,flag=4.2,betrayal=4.6,alliance=8.6,allianceWrapped=4.8}
    local typePressure=if desktop then params.typeAndTeamLen*(12/18)+8/10.8 else params.typeAndTeamLen*(12/14)+4/8.4
    local base=typePressure+params.iconCount*pressure.perIcon+(if params.iconCount>0 then pressure.icon else 0)+(if params.hasFlag then pressure.flag else 0)+(if params.hasBetrayal then pressure.betrayal else 0)
    local capacity=if width<640 then 28.1+(math.max(360,width)-360)*.119 elseif width<768 then 44.8 elseif width<1024 then 41 else 31.1
    local alliancePressure=if params.hasAlliance then pressure.alliance else 0
    local scale=(capacity-base-alliancePressure)/params.nameLength
    local wrapped=params.hasAlliance and scale<.85
    if wrapped then scale=(capacity-base-pressure.allianceWrapped)/params.nameLength end
    return (if desktop then 18 else 14)*math.clamp(math.round(scale*1000)/1000,.65,1),wrapped
end
function P.stringLength(value: string): number
    local count=0;for _,codepoint in utf8.codes(value) do count+=if codepoint>65535 then 2 else 1 end;return count
end
function P.targeted(state: any,owner: number,target: number): boolean
    local function targets(player: number): boolean
        if state.diplomacy then for _,entry in Diplomacy.targets(state,player) do if entry==target then return true end end end
        return state.targets and state.targets[player] and table.find(state.targets[player],target)~=nil or false
    end
    if targets(owner) then return true end
    for _,ally in Diplomacy.allies(state,owner) do if targets(ally) then return true end end
    for _,other in state.playerOrder do if other~=owner and Diplomacy.sameTeam(state,owner,other) and targets(other) then return true end end
    return false
end
-- The status pass asks the same viewer's target question for every plate.
-- Rebuild this union per update; decoded state tables may be mutated in place.
function P.targetedOwners(state: any,owner: number): {[number]: boolean}
    local result={}
    local function add(player: number)
        if state.diplomacy then for _,target in Diplomacy.targets(state,player)do result[target]=true end end
        for _,target in state.targets and state.targets[player]or {}do result[target]=true end
    end
    add(owner)
    for _,ally in Diplomacy.allies(state,owner)do add(ally)end
    for _,other in state.playerOrder do if other~=owner and Diplomacy.sameTeam(state,owner,other)then add(other)end end
    return result
end
function P.emoji(state: any,owner: number): (number?,string?)
    for _,message in Diplomacy.outgoingEmojis(state,owner) do
        if message.recipientID==0 or message.recipientID=="AllPlayers" or message.recipientID==1 then
            local index=table.find(require(script.Parent.DiplomacyEmoji),message.message)
            return if index then index-1 else nil,message.message
        end
    end;return nil,nil
end
function P.status(state: any,owner: number,first: number,targetedOwners: {[number]: boolean}?): {string}
    local result={};if owner==first then table.insert(result,"Crown") end
    if Diplomacy.traitorRemainingTicks(state,owner)>0 then table.insert(result,"Traitor") end
    if state.players[owner].isDisconnected==true then table.insert(result,"Disconnected") end
    if owner~=1 then
        if P.alliance(state,1,owner) then table.insert(result,"Alliance") end
        if P.requesting(state,owner,1) then table.insert(result,"AllianceRequest") end
        if (if targetedOwners then targetedOwners[owner]==true else P.targeted(state,1,owner)) then table.insert(result,"Target") end
        if P.embargo(state,1,owner) then table.insert(result,"Embargo") end
    end
    local nuclear,targeting=false,false
    for _,unit in state.nukes or {} do if unit.owner==owner and unit.active~=false then nuclear=true;if unit.targetTile and state.owners[unit.targetTile]==1 then targeting=true end end end
    if nuclear then table.insert(result,if targeting then "NukeRed" else "NukeWhite") end;return result
end
return P
