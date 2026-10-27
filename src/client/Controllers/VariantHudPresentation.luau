--!strict
-- Exact configured clock panel decisions at pinned OpenFront93a136a1.
local Shared=game:GetService("ReplicatedStorage").Shared
local Doom=require(Shared.OpenFrontDoomsday)
local Victory=require(Shared.OpenFrontVictory)
local Names=require(Shared.OpenFrontClientNames)
local Data=require(script.Parent.VariantHudData)
local P={}
function P.text(key: string,values: any?): string
    local result=Data.locale[key]or key
    for name,value in values or {}do result=string.gsub(result,"{"..name.."}",function()return tostring(value)end)end
    return result
end
function P.time(seconds: number): string
    local h,m,s=math.floor(seconds/3600),math.floor(seconds%3600/60),math.floor(seconds%60)
    return if h~=0 then string.format("%02d:%02d:%02d",h,m,s)else string.format("%02d:%02d",m,s)
end
function P.elapsed(state: any): number return if state.phase=="Choosing"then 0 else math.max(0,state.ticks-(state.startTick or 0))/10 end
function P.teamName(team: string): string local key="team_colors."..string.lower(team);local result=P.text(key);return if result==key then team else result end
-- Number.toFixed(1) rounds the represented positive binary value, ties upward.
-- Split its integer mantissa so multiplying by5 does not lose low bits.
function P.fixed1(value: number): string
    local fraction,exponent=math.frexp(value);local mantissa=fraction*2^53
    local hi=math.floor(mantissa/2^32)*5;local lo=(mantissa%2^32)*5
    hi+=math.floor(lo/2^32);lo%=2^32;local shift=52-exponent;local whole,up
    if shift>32 then local divisor=2^(shift-32);whole=math.floor(hi/divisor);up=hi%divisor>=divisor/2
    elseif shift>0 then local divisor=2^shift;whole=hi*2^(32-shift)+math.floor(lo/divisor);up=lo%divisor>=divisor/2
    else whole=value*10;up=false end
    if up then whole+=1 end
    return string.format("%.0f.%d",math.floor(whole/10),whole%10)
end
function P.number(value: number): string
    local n=math.max(0,value)
    if n>=10000000000 then return string.format("%.1fB",math.floor(n/100000000)/10)
    elseif n>=1000000000 then return string.format("%.2fB",math.floor(n/10000000)/100)
    elseif n>=10000000 then return string.format("%.1fM",math.floor(n/100000)/10)
    elseif n>=1000000 then return string.format("%.2fM",math.floor(n/10000)/100)
    elseif n>=100000 then return tostring(math.floor(n/1000)).."K"
    elseif n>=10000 then return string.format("%.1fK",math.floor(n/100)/10)
    elseif n>=1000 then return string.format("%.2fK",math.floor(n/10)/100)
    else return tostring(math.floor(n))end
end
local function alive(state: any,owner: number?): boolean return owner~=nil and state.players[owner]~=nil and (state.counts[owner]or 0)>0 end
local function winner(state: any): boolean return state.winner~=nil or state.winnerTeam~=nil end
function P.doomsday(state: any,owner: number?,callbacks: any?): any
    callbacks=callbacks or {};local raw=state.gameConfig or {};local cfg=Doom.config(raw)
    if not cfg.enabled or winner(state)then return{visible=false}end
    local live=alive(state,owner);local me=owner and state.players[owner];local team=me and me.team
    local teamGame=(raw.gameMode or "Free For All")~="Free For All"
    local tiles=if owner then state.counts[owner]or 0 else 0
    if me and teamGame and team~=nil then tiles=0;for _,other in state.playerOrder do local p=state.players[other];if p.team==team and alive(state,other)and p.playerType~="Bot"then tiles+=state.counts[other]end end end
    local land=(state.landCount or state.map.landCount)-(state.falloutCount or 0);local elapsed=math.floor(P.elapsed(state));cfg.teamGame=teamGame
    local required=Doom.requiredTiles(cfg,land,elapsed);local wave=Doom.waveState(cfg,elapsed)
    local requiredPct=if land>0 then required/land*100 else 0;local yourPct=if land>0 then tiles/land*100 else 0
    local flagged=owner~=nil and Doom.inClock(state,owner);local seconds=if owner then math.floor(Doom.ticksUnder(state,owner)/10)else 0
    local draining=flagged and seconds>=cfg.warnSeconds;local decaying=draining and owner~=nil and Doom.isRotting(state,owner)
    local near=live and not flagged and required>0 and yourPct<=requiredPct*1.1;local red=flagged or near
    local zone=if wave.done then P.text("doomsday_clock.final",{pct=wave.currentPercent})elseif wave.growing then P.text("doomsday_clock.growing",{pct=wave.targetPercent,time=P.time(wave.secondsToTarget)})else P.text("doomsday_clock.next_wave",{pct=wave.targetPercent,time=P.time(wave.secondsToNextGrowth)})
    local status,statusClass,detail="","",zone
    if live and draining and me and decaying then status=P.text("doomsday_clock.decaying",{rate=Doom.rotQuota(state.counts[owner],seconds,cfg)});statusClass="text-red-500 font-bold"
    elseif live and draining and me then
        local maximum=state.caps[owner];local past=seconds-cfg.warnSeconds;local floor=Doom.floor(maximum,past,cfg);local chunk=Doom.drain(maximum,past,cfg)
        local rate=math.max(0,math.min(state.troops[owner]-floor,chunk));local display=if callbacks.formatTroops then callbacks.formatTroops(rate)else P.number(rate/10)
        status=P.text("doomsday_clock.collapsing",{rate=display});statusClass="text-red-400 font-bold"
    elseif live and flagged then status=P.text("doomsday_clock.unstable");statusClass="text-red-400 font-bold";detail=P.text("doomsday_clock.decay_in",{secs=math.max(0,cfg.warnSeconds-seconds)})
    elseif live then status=P.text("doomsday_clock.stable");statusClass=if near then "text-orange-300 font-bold"else "text-green-400"end
    local share=if live then (if team~=nil then P.text("doomsday_clock.your_team",{team=P.teamName(team),pct=P.fixed1(yourPct)})else P.text("doomsday_clock.you",{pct=P.fixed1(yourPct)}))else ""
    return{visible=true,live=live,title=P.text("doomsday_clock.title"),status=status,statusClass=statusClass,detail=detail,zoneDetail=zone,
        hold=P.text("doomsday_clock.hold",{pct=P.fixed1(requiredPct)}),share=share,team=team,shareClass=if red then "text-red-300"else "text-green-300",
        yourPct=yourPct,requiredPct=requiredPct,fillPercent=math.min(100,yourPct),thresholdPercent=math.min(100,requiredPct),flagged=flagged,draining=draining,decaying=decaying,nearDanger=near,
        edge=if red then "sd-pulse-red"elseif wave.waveFlash then "sd-pulse-orange"else "",wave=wave}
end
function P.firstPlace(state: any,owner: number?,callbacks: any?): any?
    callbacks=callbacks or {};local raw=state.gameConfig or {};local me=owner and state.players[owner]
    if (raw.gameMode or "Free For All")=="Free For All"then
        local top;for _,other in state.playerOrder do if alive(state,other)and(not top or state.counts[other]>state.counts[top])then top=other end end
        if not top then return nil end
        return{name=if callbacks.displayName then callbacks.displayName(top)else Names.resolve(state,top,callbacks.preferences),tiles=state.counts[top],isMine=me~=nil and state.players[top].id==me.id}
    end
    local order,totals={},{}
    for _,other in state.playerOrder do local team=state.players[other].team;if alive(state,other)and team~=nil then if totals[team]==nil then totals[team]=0;table.insert(order,team)end;totals[team]+=state.counts[other]end end
    local top;for _,team in order do if not top or totals[team]>totals[top]then top=team end end
    if not top or top=="Bot"then return nil end
    return{name=P.teamName(top),tiles=totals[top],isMine=me~=nil and me.team==top}
end
function P.overtime(state: any,owner: number?,callbacks: any?): any
    local raw=state.gameConfig or {};local cfg=raw.overtime or {};local elapsed=math.floor(P.elapsed(state))
    if not cfg.enabled or winner(state)or elapsed<(cfg.startMinutes or 30)*60 then return{visible=false}end
    local land=(state.landCount or state.map.landCount)-(state.falloutCount or 0);local required=Victory.threshold(raw,elapsed);local leader=P.firstPlace(state,owner,callbacks)
    local pct=if land>0 and leader then leader.tiles/land*100 else 0
    return{visible=true,title=P.text("overtime.title"),requiredPct=required,leader=leader,leaderPct=pct,leaderPctShown=math.floor(pct),fillPercent=math.min(100,pct),thresholdPercent=math.min(100,required),
        barClass=if leader and owner~=nil and not leader.isMine then "bg-red-400"else "bg-green-400",toWin=P.text("overtime.to_win",{pct=required}),
        detail=if leader then P.text("overtime.first_place",{name=leader.name,pct=math.floor(pct)})else ""}
end
function P.timer(state: any,previous: number?): any
    local raw=state.gameConfig or {};local max=raw.maxTimerValue;local spawn=state.phase=="Choosing";local seconds
    if spawn then seconds=if (raw.gameType or "Singleplayer")=="Singleplayer"then (max or 0)*60 else math.max(0,math.ceil(((if raw.randomSpawn then 150 else 200)-state.ticks)/10))
    elseif winner(state)then seconds=previous or 0
    elseif max~=nil then seconds=math.max(0,max*60-math.floor(P.elapsed(state)))else seconds=math.floor(P.elapsed(state))end
    return P.timerView(state,seconds)
end
function P.timerView(state: any,seconds: number): any
    local raw=state.gameConfig or {};local active=raw.maxTimerValue~=nil and state.phase~="Choosing"and not winner(state)and seconds>0
    return{seconds=seconds,text=P.time(seconds),lastMinute=active and seconds<=60,flashText=active and seconds<=30,flashSidebar=active and seconds<=10,
        timerClass=if active and seconds<=30 then "game-end-timer-flash"elseif active and seconds<=60 then "game-end-timer-last-minute"else "",warning=active and seconds<=60}
end
function P.overtimeNotice(state: any): boolean local cfg=(state.gameConfig or {}).overtime or {};local elapsed=P.elapsed(state);local start=(cfg.startMinutes or 30)*60;return cfg.enabled==true and state.phase~="Choosing"and elapsed>=start and elapsed<start+5 end
function P.ease(value: number): number
    if value<=0 then return 0 elseif value>=1 then return 1 elseif value==.5 then return .5 end
    local low,high=0,1
    for _=1,32 do local t=(low+high)/2;local x=3*(1-t)^2*t*.42+3*(1-t)*t^2*.58+t^3;if x<value then low=t else high=t end end
    local t=(low+high)/2;return 3*(1-t)*t^2+t^3
end
function P.pulse(elapsed: number,duration: number): number local phase=(elapsed%duration)/duration;return P.ease(if phase<=.5 then phase*2 else (1-phase)*2)end
function P.mixBytes(from: {number},to: {number},phase: number,fromAlpha: number?,toAlpha: number?): (Color3,number)
    local a,b=fromAlpha or 1,toAlpha or 1;local alpha=a+(b-a)*phase;local rgb={}
    for i=1,3 do rgb[i]=if alpha>0 then math.floor((from[i]*a*(1-phase)+to[i]*b*phase)/alpha+.5)else 0 end
    return Color3.fromRGB(rgb[1],rgb[2],rgb[3]),alpha
end
return P
