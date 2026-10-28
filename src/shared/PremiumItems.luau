--!strict
-- PF044 Arsenal in match (PF - 2 2026-10-24; docs/director/MONETIZATION-SETS.md). Phase 1: the Industry buildings (v4);
-- Phase 2: the Warfare v4 Tesla Coil and Artillery (with the v4 anti-stack rules); Phase 3: Airdrop, Blitz Bomb,
-- Titan Bomb (Silo launches flown here as premium projectiles, never in state.nukes, so the wire codec is untouched).
-- Deterministic sim side. Only players granted an owned set (MatchService: humans who unlocked the item; never nations,
-- never Ranked or the tutorial) can build. Tuning: Config.Arsenal.Match.
--   PremiumItems.grant(state, owner, owned)         owned = {[itemId]=true} (CosmeticService.arsenalOwned)
--   PremiumItems.build(state, owner, itemId, tile)  -> (ok, message)   a building on your land
--   PremiumItems.launch(state, owner, itemId, tile) -> (ok, message)   Airdrop / Blitz / Titan from your nearest ready Silo
--   PremiumItems.use(state, owner, itemId)          -> (ok, message)   Train (Training Camp) / Invest (Stock Exchange): one tap
--   PremiumItems.packet(state, viewer)              the "Premium" State packet (MatchService sends it beside the snapshot)
-- Premium reshuffle (2026-10-25, PREMIUM-RESHUFFLE-SPEC.md "CLIENT CONTRACT"): Warden, Barracks, Training Camp, Stock Exchange;
-- the Longshot, Bounty Office and Insurance Office are RETIRED and their code removed (ArsenalCatalog.RETIRED maps their owners).
-- Simulation calls state.premium.tick(state) once per tick (before executions), state.premium.conquered(state, from, to) from
-- conquer() while a Barracks stands, and state.premium.growth(state, owner) from its troop growth
-- while a Barracks stands, so Simulation needs no require of this module. While a Trade Guild (Shipping Co.) stands,
-- OpenFrontTrade calls state.premium.tradeGold(state, owner, gold) and OpenFrontWarships state.premium.tradeSafe(state, ship).
local Config=require(script.Parent.Config)
local Diplomacy=require(script.Parent.OpenFrontDiplomacy)
local Nukes=require(script.Parent.OpenFrontNukes)
local Weapons=require(script.Parent.OpenFrontWeapons)
local M={}
local MATCH=Config.Arsenal.Match
-- the buildings and launches built so far, in dock order
M.BUILDINGS=table.freeze({"tesla_coil","artillery","warden","barracks","training_camp","bank","engineering_yard","tax_office","trade_guild","stock_exchange"})
M.LAUNCHES=table.freeze({"airdrop","blitz_bomb","titan_bomb"})
local IS_BUILDING={};for _,id in M.BUILDINGS do IS_BUILDING[id]=true end
local IS_LAUNCH={};for _,id in M.LAUNCHES do IS_LAUNCH[id]=true end
-- the economy buildings: captured, they change hands (the PvP ones are destroyed)
local ECONOMY=table.freeze({bank=true,engineering_yard=true,tax_office=true,trade_guild=true,stock_exchange=true})
M.ECONOMY=ECONOMY
local NUKE_KIND=table.freeze({blitz_bomb="Blitz Bomb",titan_bomb="Titan Bomb"})
local EVENTS_KEPT=32
local TICKS_PER_SECOND=math.floor(1/Config.Match.StepSeconds+.5)

local function addGold(state: any,owner: number,amount: number)
    state.gold[owner]+=amount;state.goldEarned[owner]+=amount
end
local function ensure(state: any): any
    local p=state.premium
    if p then return p end
    p={owned={},buildings={},counts={},nextId=1,version=0,stats={},yards={},shelled={},guilds={},
        projectiles={},events={},nextEvent=1,airdropAt={},fx={},nextFx=1,drops={},
        barracks={},momentum={},scale={},shells={},wardenHit={},trainedAt={},earn={},
        guildSaves={},tick=M.tick,conquered=M.conquered,growth=M.growth,tradeGold=M.tradeGold,tradeSafe=M.tradeSafe,guildSaved=M.guildSaved,
        dropSafe=M.dropSafe}
    state.premium=p
    return p
end
-- PF - 4 in-match FX (presentation only): what a building just did, with exact tiles, for the client's effects
-- {id, tick, kind = zap / shell / warden_fire / warden, owner, from?, tile, victim?, amount, pct? (per mille), coil?, land?}
-- guild_save (PF - 4's contract): {owner = the trade ship's owner, ship = its id, tile, by = the warship's owner}
local FX_KEPT=24
local function emit(state: any,p: any,entry: any)
    entry.id=p.nextFx;p.nextFx+=1;entry.tick=state.ticks
    table.insert(p.fx,entry)
    if #p.fx>FX_KEPT then table.remove(p.fx,1) end
    p.version+=1
end
local function stats(p: any,owner: number): any
    local s=p.stats[owner]
    if not s then s={minted=0,zapped=0,shelled=0,intercepted=0,taxed=0,traded=0,warded=0,trained=0,
        invested=0,exchange=0};p.stats[owner]=s end
    return s
end
-- premium item bans (Ashton 2026-10-26): the match config's disabledPremium (Arsenal item ids, validated by
-- OpenFrontLobbySettings.validateConfig). A banned item is never granted and can't be built, launched or used in that match;
-- unlocks / ownership are untouched.
function M.banned(state: any,itemId: any): boolean
    local list=state.gameConfig and state.gameConfig.disabledPremium
    return type(list)=="table" and table.find(list,itemId)~=nil
end
local BANNED="Banned in this match."
function M.grant(state: any,owner: number,owned: any)
    if type(owned)~="table" or not state.players[owner] or state.players[owner].playerType~="Human" then return end
    local set={}
    for _,id in M.BUILDINGS do if owned[id]==true and not M.banned(state,id) then set[id]=true end end
    for _,id in M.LAUNCHES do if owned[id]==true and not M.banned(state,id) then set[id]=true end end
    if next(set)==nil then return end
    local p=ensure(state);p.owned[owner]=set;p.version+=1
end
function M.owns(state: any,owner: number,itemId: string): boolean
    local p=state.premium
    return p~=nil and p.owned[owner]~=nil and p.owned[owner][itemId]==true
end
function M.count(state: any,owner: number,itemId: string): number
    local p=state.premium
    local c=p and p.counts[owner]
    return if c then c[itemId] or 0 else 0
end
-- the gold the next copy / launch costs (nil: at the max building count; a launch's last cost repeats)
function M.cost(state: any,owner: number,itemId: string): number?
    local tune=MATCH[itemId]
    if not tune then return nil end
    local n=M.count(state,owner,itemId)+1
    if IS_LAUNCH[itemId] then return tune.Costs[math.min(n,#tune.Costs)] end
    return tune.Costs[n]
end
-- the economy buildings' output share at this point of the match (Config.Arsenal.Match.IndustryRamp: 0 until From seconds of
-- play, full from Full; linear between). Absent = always full.
local function industryRamp(state: any): number
    local R=MATCH.IndustryRamp
    if not R then return 1 end
    return math.clamp(((state.elapsed or 0)-R.From)/math.max(1,R.Full-R.From),0,1)
end
local function constructionTicks(p: any,owner: number): number
    return if p.yards[owner] then math.floor(MATCH.ConstructionTicks/2) else MATCH.ConstructionTicks
end
function M.build(state: any,owner: number,itemId: any,tile: any): (boolean,string)
    if type(itemId)~="string" or not IS_BUILDING[itemId] then return false,"Unknown premium building." end
    if M.banned(state,itemId) then return false,BANNED end
    if not M.owns(state,owner,itemId) then return false,"Unlock it in the Shop first." end
    if state.phase~="Playing" then return false,"Wait for the match to start." end
    if type(tile)~="number" or tile%1~=0 or tile<1 or tile>#state.owners or not state.map.land[tile] or state.owners[tile]~=owner then
        return false,"Build it on your own land." end
    local cost=M.cost(state,owner,itemId)
    if not cost then return false,"You've built the most of these." end
    if state.gold[owner]<cost then return false,"Not enough gold." end
    local p=state.premium
    local w=state.map.width
    local x,y=(tile-1)%w,(tile-1)//w
    for _,b in p.buildings do
        local bx,by=(b.tile-1)%w,(b.tile-1)//w
        if math.abs(bx-x)+math.abs(by-y)<MATCH.Spacing then return false,"Too close to another premium building." end
    end
    state.gold[owner]-=cost
    local counts=p.counts[owner] or {};p.counts[owner]=counts;counts[itemId]=(counts[itemId] or 0)+1
    table.insert(p.buildings,{id=p.nextId,owner=owner,item=itemId,tile=tile,born=state.ticks,built=state.ticks+constructionTicks(p,owner)})
    p.nextId+=1;p.version+=1
    return true,"Building."
end
-- how many times a maturing building has doubled (0 while under construction; no Industry v4 item matures)
function M.doublings(state: any,b: any): number
    local tune=MATCH[b.item]
    if not tune or not tune.DoubleSeconds or state.ticks<b.built then return 0 end
    return math.min(tune.MaxDoublings,(state.ticks-b.built)//(tune.DoubleSeconds*TICKS_PER_SECOND))
end
local function d2(state: any,a: number,b: number): number
    local w=state.map.width
    local dx,dy=(a-1)%w-(b-1)%w,(a-1)//w-(b-1)//w
    return dx*dx+dy*dy
end
-- Tesla Coil, once a second: zap the biggest enemy attack with a front tile in range, enemy transports and warships in range
local function teslaFire(state: any,p: any,b: any)
    local T=MATCH.tesla_coil
    local r2=T.Range*T.Range
    local best,bestBudget,bestTile=nil,0,nil
    for _,at in state.attacks do
        if at.active and at.targetOwner==b.owner and at.owner~=b.owner and at.budget>bestBudget then
            for t in at.border do if d2(state,t,b.tile)<=r2 then best,bestBudget,bestTile=at,at.budget,t;break end end
        end
    end
    local s=stats(p,b.owner)
    local arcs=0 -- the FX: at most 3 arcs a coil a second
    if best then
        local z=math.min(best.budget,math.max(T.ZapMin,math.floor(best.budget*T.ZapPercent)))
        best.budget-=z;s.zapped+=z
        emit(state,p,{kind="zap",owner=b.owner,from=b.tile,tile=bestTile,victim=best.owner,amount=z});arcs+=1
    end
    for _,ship in state.ships do
        if ship.active~=false and ship.owner~=b.owner and ship.tileId and ship.targetTileId and state.owners[ship.targetTileId]==b.owner
            and d2(state,ship.tileId,b.tile)<=r2 and (ship.troops or 0)>0 then
            local z=math.floor(ship.troops*T.BoatPercent);ship.troops-=z;s.zapped+=z
            if arcs<3 then emit(state,p,{kind="zap",owner=b.owner,from=b.tile,tile=ship.tileId,victim=ship.owner,amount=z});arcs+=1 end
        end
    end
    for _,ship in state.warships do
        if ship.active~=false and ship.owner~=b.owner and ship.tileId and d2(state,ship.tileId,b.tile)<=r2
            and not Diplomacy.friendly(state,b.owner,ship.owner) then
            ship.health-=T.WarshipDamage -- Warships removes it at <= 0
            if arcs<3 then emit(state,p,{kind="zap",owner=b.owner,from=b.tile,tile=ship.tileId,victim=ship.owner,amount=0});arcs+=1 end
        end
    end
end
-- the unallied nations / humans with land within a gun's range ({[owner]=the tile its shell lands on: theirs, nearest
-- half the range out}), scanned once per tick per gun
local function reach(state: any,p: any,g: any): {[number]: number}
    local cached=p.reach and p.reach[g.id]
    if cached and cached.tick==state.ticks then return cached.set end
    local w,h,R=state.map.width,state.map.height,MATCH.artillery.Range
    local x0,y0=(g.tile-1)%w,(g.tile-1)//w
    local mid=(R*.55)^2
    local seen,set,score={},{},{}
    for dy=-R,R do
        for dx=-R,R do
            local x,y=x0+dx,y0+dy
            local r2=dx*dx+dy*dy
            if r2>R*R or x<0 or y<0 or x>=w or y>=h then continue end
            local o=state.owners[y*w+x+1]
            if o>0 and o~=g.owner then
                if seen[o]==nil then
                    local kind=state.players[o] and state.players[o].playerType
                    seen[o]=(kind=="Nation" or kind=="Human") and (state.counts[o] or 0)>0 and not Diplomacy.friendly(state,g.owner,o)
                end
                if seen[o] then
                    local sc=math.abs(r2-mid)
                    if not score[o] or sc<score[o] then score[o]=sc;set[o]=y*w+x+1 end
                end
            end
        end
    end
    p.reach=p.reach or {};p.reach[g.id]={tick=state.ticks,set=set}
    return set
end
-- Artillery, every EverySeconds: shell every unallied nation/human with land in range (the v4 anti-stack rules)
local function artilleryFire(state: any,p: any,b: any,guns: {any},teslas: {any})
    local A=MATCH.artillery
    local R=A.Range
    local victims={}
    local land=reach(state,p,b)
    for o in land do table.insert(victims,o) end
    table.sort(victims)
    local s=stats(p,b.owner)
    for _,victim in victims do
        -- rule b: this gun's rank among its owner's guns that reach this victim (by building id): x Decay^(rank-1)
        local rank=1
        for _,g in guns do if g.owner==b.owner and g.id<b.id and reach(state,p,g)[victim] then rank+=1 end end
        local before=state.troops[victim]
        local hit=before*A.Percent*A.Decay^(rank-1)
        -- the victim's Tesla Coil in range of this gun stops Intercept of the shell
        local coil=nil
        for _,t in teslas do if t.owner==victim and d2(state,t.tile,b.tile)<=R*R then local blocked=hit*A.Intercept;hit-=blocked;s.intercepted+=blocked;coil=t.tile;break end end
        -- rule c: at most Ceiling of the victim's troops per EverySeconds window, from all guns combined
        local window=p.shelled[victim]
        if not window or state.ticks-window.start>=A.EverySeconds*TICKS_PER_SECOND then
            window={start=state.ticks,cap=state.troops[victim]*A.Ceiling,taken=0};p.shelled[victim]=window
        end
        hit=math.floor(math.min(hit,window.cap-window.taken,state.troops[victim]))
        if hit>0 then
            state.troops[victim]-=hit;window.taken+=hit;s.shelled+=hit
            emit(state,p,{kind="shell",owner=b.owner,from=b.tile,tile=land[victim],victim=victim,amount=hit,
                pct=math.floor(hit/math.max(1,before)*1000+.5),coil=coil})
        end
    end
end
-- Warden, every EverySeconds: one shell at each enemy attack on its owner with a front tile within Range, aimed at the front
-- tile nearest the Warden; it lands ShellTicks later (landShells)
local function wardenFire(state: any,p: any,b: any)
    local W=MATCH.warden
    local r2=W.Range*W.Range
    for _,at in state.attacks do
        if at.active and at.targetOwner==b.owner and at.owner~=b.owner and (at.budget or 0)>0 then
            local best,bestD=nil,math.huge
            for t in at.border do
                local d=d2(state,t,b.tile)
                if d<=r2 and (d<bestD or (d==bestD and t<best)) then best,bestD=t,d end
            end
            if best then
                local land=state.ticks+W.ShellTicks
                table.insert(p.shells,{owner=b.owner,from=b.tile,tile=best,attack=at,victim=at.owner,land=land})
                emit(state,p,{kind="warden_fire",owner=b.owner,from=b.tile,tile=best,victim=at.owner,land=land})
            end
        end
    end
end
-- the Warden shells landing this tick: Percent of the attack's troops (at least Min), an owner's later shell on the same
-- attack in one window x Decay, at most Ceiling of the attack per window (all Wardens); an ended attack takes nothing
local function landShells(state: any,p: any)
    local W=MATCH.warden
    local span=W.EverySeconds*TICKS_PER_SECOND
    local kept={}
    for _,shell in p.shells do
        if state.ticks<shell.land then table.insert(kept,shell);continue end
        local at=shell.attack
        local before=at.budget or 0
        local hit=0
        if at.active and before>0 then
            local window=p.wardenHit[at]
            if not window or state.ticks-window.start>=span then window={start=state.ticks,cap=before*W.Ceiling,taken=0,n=0};p.wardenHit[at]=window end
            hit=math.floor(math.min(math.max(before*W.Percent*W.Decay^window.n,W.Min),window.cap-window.taken,before))
            if hit>0 then at.budget-=hit;window.taken+=hit;window.n+=1;local s=stats(p,shell.owner);s.warded+=hit else hit=0 end
        end
        emit(state,p,{kind="warden",owner=shell.owner,from=shell.from,tile=shell.tile,victim=shell.victim,amount=hit,
            pct=if before>0 then math.floor(hit/before*1000+.5) else 0})
    end
    p.shells=kept
    -- forget windows of finished attacks / closed windows (lookups only, so the order never matters)
    for at,window in p.wardenHit do if not at.active or state.ticks-window.start>=span then p.wardenHit[at]=nil end end
end
-- Phase 3 ---------------------------------------------------------------------------------------------------------------
local function event(p: any,entry: any)
    entry.id=p.nextEvent;p.nextEvent+=1
    table.insert(p.events,entry)
    if #p.events>EVENTS_KEPT then table.remove(p.events,1) end
    p.version+=1
end
local function spawnProtected(state: any): boolean
    if state.spawnImmunityActive then return state.spawnImmunityActive() end
    return state.ticks-(state.startTick or 0)<((Config.Match :: any).SpawnImmunityTicks or 0)
end
local function shielded(state: any,owner: number): boolean -- a Revive shield (Simulation.reviveShielded, without the require)
    local entry=state.revive and state.revive[owner]
    return entry~=nil and entry.ended==nil and state.ticks<entry.untilTick
end
-- the owner's nearest ready Missile Silo to `tile` (within `range` when given)
local function readySilo(state: any,owner: number,tile: number,range: number?): any?
    local best,bestD=nil,math.huge
    for _,silo in Nukes.ownedSilos(state,owner) do
        if Weapons.canLaunch(silo) then
            local d=d2(state,silo.tileId,tile)
            if (not range or d<=range*range) and d<bestD then best,bestD=silo,d end
        end
    end
    return best
end
local function addProjectile(state: any,p: any,owner: number,item: string,from: number,to: number,arrive: number,extra: any?)
    local shot={id=p.nextId,owner=owner,item=item,from=from,to=to,launched=state.ticks,arrive=arrive,hits=0}
    p.nextId+=1
    if extra then for k,v in extra do shot[k]=v end end
    table.insert(p.projectiles,shot);p.version+=1
    return shot
end
-- Airdrop / Blitz Bomb / Titan Bomb from the nearest ready Silo
function M.launch(state: any,owner: number,itemId: any,tile: any): (boolean,string)
    if type(itemId)~="string" or not IS_LAUNCH[itemId] then return false,"Unknown premium launch." end
    if M.banned(state,itemId) then return false,BANNED end
    if not M.owns(state,owner,itemId) then return false,"Unlock it in the Shop first." end
    if state.phase~="Playing" or (state.counts[owner] or 0)<=0 then return false,"Wait for the match to start." end
    if type(tile)~="number" or tile%1~=0 or tile<1 or tile>#state.owners then return false,"Pick a target on the map." end
    if spawnProtected(state) then return false,"Wait for spawn protection to end." end
    local tune=MATCH[itemId]
    local p=state.premium
    local cost=M.cost(state,owner,itemId) :: number
    if state.gold[owner]<cost then return false,"Not enough gold." end
    local target=state.owners[tile] or 0
    local troops=0
    if itemId=="airdrop" then
        if not state.map.land[tile] or target==owner then return false,"Drop on land you don't own." end
        if target>0 and (Diplomacy.friendly(state,owner,target) or shielded(state,target)) then return false,"You can't drop on them." end
        if state.ticks-(p.airdropAt[owner] or -math.huge)<tune.Cooldown*TICKS_PER_SECOND then return false,"Airdrop is reloading." end
        troops=math.floor(state.troops[owner]*tune.Share)
        if troops<1 then return false,"Not enough troops." end
    end
    local silo=readySilo(state,owner,tile,if itemId=="airdrop" then tune.Range else nil)
    if not silo then return false,if itemId=="airdrop" then "No ready Missile Silo within range." else "No ready Missile Silo." end
    state.gold[owner]-=cost
    local counts=p.counts[owner] or {};p.counts[owner]=counts;counts[itemId]=(counts[itemId] or 0)+1
    Weapons.launchSilo(state,silo)
    if itemId=="airdrop" then
        state.troops[owner]-=troops;p.airdropAt[owner]=state.ticks
    elseif state.nukeDiplomacy then state.nukeDiplomacy(owner,NUKE_KIND[itemId],tile) end -- allies break as for a nuke
    if target>0 and state.revive and state.revive[owner] and state.revive[owner].ended==nil then
        local kind=state.players[target] and state.players[target].playerType
        if kind=="Human" or kind=="Nation" then state.revive[owner].ended="attack" end -- an attack ends your own Revive shield
    end
    local flight=math.max(1,math.ceil(math.sqrt(d2(state,silo.tileId,tile))/tune.Speed))
    addProjectile(state,p,owner,itemId,silo.tileId,tile,state.ticks+flight,{troops=if troops>0 then troops else nil})
    event(p,{kind="launch",item=itemId,owner=owner,tile=tile})
    return true,"Launched."
end
-- a projectile's position now (a straight line from its launch to its target)
local function position(state: any,shot: any): (number,number)
    local w=state.map.width
    local fx,fy,tx,ty=(shot.from-1)%w,(shot.from-1)//w,(shot.to-1)%w,(shot.to-1)//w
    local f=math.clamp((state.ticks-shot.launched)/math.max(1,shot.arrive-shot.launched),0,1)
    return fx+(tx-fx)*f,fy+(ty-fy)*f
end
local function land(state: any,p: any,shot: any)
    local owner=shot.owner
    if NUKE_KIND[shot.item] then
        -- an inactive stand-in unit: Nukes.detonate's removeUnit is then a no-op (no dead-unit event for an unknown type)
        Nukes.detonate(state,{nuke={unitType=NUKE_KIND[shot.item],active=false,owner=owner},tileId=shot.to,owner=owner})
        event(p,{kind="detonate",item=shot.item,owner=owner,tile=shot.to})
    elseif shot.item=="airdrop" then
        local target=state.owners[shot.to] or 0
        local blocked=not state.map.land[shot.to] or target==owner or (target>0 and (Diplomacy.friendly(state,owner,target) or shielded(state,target)))
            or (state.counts[owner] or 0)<=0 or not state.navalApi
        if blocked then state.troops[owner]+=shot.troops -- the plane brings them home
        else
            state.navalApi.conquer(shot.to,owner)
            table.insert(state.pendingExecutions,{kind="Attack",owner=owner,targetOwner=target,amount=shot.troops,sourceTile=shot.to,removeTroops=false})
            p.drops=p.drops or {};p.drops[owner]={tile=shot.to,at=state.ticks} -- dropSafe: its pocket fights first
        end
        event(p,{kind="airdrop",item="airdrop",owner=owner,tile=shot.to,landed=not blocked})
    end
end
-- 2026-10-28 (run-pf044-premium caught it): an Airdrop lands as a one-tile pocket inside enemy land, and the cluster update
-- (Simulation: encircled pockets are annexed) could take it back the next tick, before its troops had moved: a paid drop
-- that did nothing. The pocket isn't annexed while its own fight runs: the landing attack (sourceTile = the drop) is active,
-- or it landed under 1 s ago (that attack launches from the next tick's queue). After that the normal rule applies.
function M.dropSafe(state: any,owner: number): boolean
    local p=state.premium;local drop=p and p.drops and p.drops[owner]
    if not drop then return false end
    if state.ticks-drop.at<=TICKS_PER_SECOND then return true end
    for _,a in state.attacks do if a.active and a.owner==owner and a.sourceTile==drop.tile then return true end end
    p.drops[owner]=nil
    return false
end
-- fly every projectile one tick: enemy SAMs in range shoot it (their normal reload), arrivals land
local function flyProjectiles(state: any,p: any)
    local targetable2=Config.Nuclear.TargetableRange^2
    local kept={}
    for _,shot in p.projectiles do
        local x,y=position(state,shot)
        local w=state.map.width
        local fx,fy,tx,ty=(shot.from-1)%w,(shot.from-1)//w,(shot.to-1)%w,(shot.to-1)//w
        local alive=true
        if (x-fx)^2+(y-fy)^2<=targetable2 or (x-tx)^2+(y-ty)^2<=targetable2 then
            for _,sam in state.samLaunchers or {} do
                if sam.owner~=shot.owner and Weapons.canLaunch(sam) and not Diplomacy.friendly(state,sam.owner,shot.owner) then
                    local sx,sy=(sam.tileId-1)%w,(sam.tileId-1)//w
                    if (sx-x)^2+(sy-y)^2<=Weapons.dynamicSamRange(sam,state.ticks)^2 then
                        Weapons.launchSilo(state,sam);shot.hits+=1
                        if shot.hits>=(MATCH[shot.item].SamHits or 1) then
                            alive=false
                            if shot.item=="airdrop" then event(p,{kind="intercepted",item=shot.item,owner=shot.owner,tile=math.floor(y)*w+math.floor(x)+1,troops=shot.troops})
                            else event(p,{kind="intercepted",item=shot.item,owner=shot.owner,tile=math.floor(y)*w+math.floor(x)+1}) end
                            local s=stats(p,sam.owner);s.intercepted+=1
                        else event(p,{kind="hit",item=shot.item,owner=shot.owner,tile=math.floor(y)*w+math.floor(x)+1}) end
                        break
                    end
                end
            end
        end
        if alive and state.ticks>=shot.arrive then land(state,p,shot);alive=false end
        if alive then table.insert(kept,shot) else p.version+=1 end
    end
    p.projectiles=kept
end
-- Premium reshuffle -----------------------------------------------------------------------------------------------------
-- the owner's building of this item (its first; nil: none)
local function own(p: any,owner: number,item: string): any?
    for _,b in p.buildings do if b.owner==owner and b.item==item then return b end end
    return nil
end
-- Barracks: (bonus now, momentum after its fade, size scale)
local function momentum(state: any,p: any,owner: number): (number,number,number)
    local m=p.momentum[owner]
    if not m then return 0,0,0 end
    local raw=m.raw*math.max(0,1-(state.ticks-m.at)/(MATCH.barracks.FadeSeconds*TICKS_PER_SECOND))
    local scale=p.scale[owner] or 0
    return raw*scale,raw,scale
end
-- the troop growth bonus (0..Cap) of a Barracks owner (Simulation's populationGrowth, while one stands)
function M.growth(state: any,owner: number): number
    local p=state.premium
    if not p or not p.barracks[owner] then return 0 end
    return (momentum(state,p,owner))
end
-- once a second: each Barracks owner's size scale against the median alive nation/human (full at <= FullAt x, 0 at ZeroAt x;
-- 0 for a #1 with >= LeaderLead x the #2's land)
local function sizeScale(state: any,p: any,owners: any)
    local B=MATCH.barracks
    local lands={}
    for o=1,#state.players do
        local kind=state.players[o] and state.players[o].playerType
        if (kind=="Nation" or kind=="Human") and (state.counts[o] or 0)>0 then table.insert(lands,state.counts[o]) end
    end
    table.sort(lands)
    local n=#lands
    if n==0 then return end
    local median=if n%2==1 then lands[(n+1)//2] else (lands[n//2]+lands[n//2+1])/2
    local second=lands[n-1] or 0
    for owner in owners do
        local c=state.counts[owner] or 0
        local s=math.clamp((B.ZeroAt-c/math.max(1,median))/(B.ZeroAt-B.FullAt),0,1)
        if n>1 and c>=lands[n] and c>=second*B.LeaderLead then s=0 end
        p.scale[owner]=s
    end
end
-- Training Camp: what a press gives now (troops, gold)
local function trainOffer(state: any,owner: number): (number,number)
    local T=MATCH.training_camp
    local maximum=if state.maxTroopsFor then state.maxTroopsFor(owner) else state.troops[owner]
    local n=math.max(0,math.min(math.floor(maximum*T.Share),math.floor(maximum-state.troops[owner])))
    return n,n*T.GoldPerTroop
end
-- Stock Exchange: what a tap invests now and what it would return (stake, payout); income = the last StakeSeconds of
-- earned gold (Exchange payouts and raids left out, so a payout never feeds the next stake)
-- the profit share a stake earns now ((Return - 1) x the IndustryRamp); the packet's invest option carries it as `gain`, so
-- the client's "You get back" for a picked amount is stake + floor(stake x gain), exactly as here
local function investGain(state: any): number
    return (MATCH.stock_exchange.Return-1)*industryRamp(state)
end
local function investOffer(state: any,p: any,owner: number): (number,number)
    local S=MATCH.stock_exchange
    local ring=p.earn[owner]
    local income=if ring and #ring>=2 then math.max(0,(ring[#ring]-ring[1])/(#ring-1)) else 0
    local stake=math.floor(math.min(income*S.StakeSeconds,S.StakeCap,state.gold[owner]))
    if stake<=0 then return 0,0 end
    return stake,stake+math.floor(stake*investGain(state))
end
-- Train / Invest (UsePremium): one tap, no target. amount (Invest only; PF - 3's pick, Ashton's "pick amount"): the gold to
-- stake, floored and clamped to 1..the max allowed now (investOffer); nil = the max
function M.use(state: any,owner: number,itemId: any,amount: any?): (boolean,string)
    if itemId~="training_camp" and itemId~="stock_exchange" then return false,"Unknown premium action." end
    if M.banned(state,itemId) then return false,BANNED end
    if state.phase~="Playing" or (state.counts[owner] or 0)<=0 then return false,"Wait for the match to start." end
    local p=state.premium
    local b=p and own(p,owner,itemId)
    if not b then return false,if itemId=="training_camp" then "Build a Training Camp first." else "Build a Stock Exchange first." end
    if state.ticks<b.built then return false,"Wait for it to finish building." end
    local s=stats(p,owner)
    if itemId=="training_camp" then
        if state.ticks<(p.trainedAt[owner] or -math.huge)+MATCH.training_camp.Cooldown*TICKS_PER_SECOND then return false,"Training Camp is reloading." end
        local troops,cost=trainOffer(state,owner)
        if troops<=0 then return false,"Your troops are full." end
        if state.gold[owner]<cost then return false,"Not enough gold." end
        state.gold[owner]-=cost;state.troops[owner]+=troops;p.trainedAt[owner]=state.ticks;s.trained+=troops
        event(p,{kind="train",item="training_camp",owner=owner,tile=b.tile,troops=troops,cost=cost})
        return true,"Troops trained."
    end
    if b.invest then return false,"Already invested." end
    local stake,payout=investOffer(state,p,owner)
    if stake<=0 then return false,"Nothing to invest yet." end
    if amount~=nil then
        if type(amount)~="number" or amount~=amount or math.abs(amount)==math.huge then return false,"Pick an amount." end
        stake=math.clamp(math.floor(amount),1,stake)
        payout=stake+math.floor(stake*investGain(state))
    end
    state.gold[owner]-=stake;s.invested+=stake
    b.invest={stake=stake,payout=payout,started=state.ticks,ends=state.ticks+MATCH.stock_exchange.Seconds*TICKS_PER_SECOND,risk=false}
    event(p,{kind="invest",item="stock_exchange",owner=owner,tile=b.tile,stake=stake,payout=payout,ends=b.invest.ends})
    return true,"Invested."
end
-- once a second: Stock Exchange payouts, the earned-gold rings and the "at risk" flag (an enemy attack front within RiskRange)
local function exchangeSecond(state: any,p: any,exchanges: {any})
    local S=MATCH.stock_exchange
    local seen={}
    for _,b in exchanges do
        if not seen[b.owner] then
            seen[b.owner]=true
            local ring=p.earn[b.owner] or {};p.earn[b.owner]=ring
            table.insert(ring,state.goldEarned[b.owner]-stats(p,b.owner).exchange)
            if #ring>S.StakeSeconds+1 then table.remove(ring,1) end
        end
        local invest=b.invest
        if not invest then continue end
        if state.ticks>=invest.ends then
            addGold(state,b.owner,invest.payout);local s=stats(p,b.owner);s.exchange+=invest.payout
            event(p,{kind="payout",item="stock_exchange",owner=b.owner,tile=b.tile,amount=invest.payout})
            b.invest=nil;continue
        end
        local r2,risk=S.RiskRange*S.RiskRange,false
        for _,at in state.attacks do
            if at.active and at.targetOwner==b.owner and at.owner~=b.owner then
                for t in at.border do if d2(state,t,b.tile)<=r2 then risk=true;break end end
                if risk then break end
            end
        end
        if risk~=invest.risk then invest.risk=risk;p.version+=1 end
    end
end
function M.tick(state: any)
    local p=state.premium
    if not p then return end
    if #p.projectiles>0 then flyProjectiles(state,p) end
    if p.shells and #p.shells>0 then landShells(state,p) end
    -- the Guild pool pays out at most PayPerSecond, once a second (lumpy trade gold spread over time; nothing is lost, and
    -- gold already owed still pays if the building falls)
    if p.pools and state.ticks%TICKS_PER_SECOND==0 then
        for owner,pool in p.pools do
            local s=stats(p,owner)
            if pool.guild>0 then local pay=math.min(pool.guild,MATCH.trade_guild.PayPerSecond or math.huge);pool.guild-=pay;addGold(state,owner,pay);s.traded+=pay end
        end
    end
    if #p.buildings==0 then return end
    -- captured (Ashton 2026-10-25): an economy building goes to a nation/human captor and works for it (counting toward
    -- the captor's max; at that max it is destroyed); a PvP building (Tesla, Artillery, Warden, Barracks, Training Camp) is always destroyed, so
    -- a defense can't be turned on its owner. A tribe captor or a gone owner: destroyed.
    local kept,changed={},false
    for _,b in p.buildings do
        local now=state.owners[b.tile]
        if now==b.owner and (state.counts[b.owner] or 0)>0 then table.insert(kept,b);continue end
        changed=true
        local kind=now>0 and state.players[now] and state.players[now].playerType
        local tune=MATCH[b.item]
        if ECONOMY[b.item] and (kind=="Human" or kind=="Nation") and tune and M.count(state,now,b.item)<#tune.Costs then
            local counts=p.counts[now] or {};p.counts[now]=counts;counts[b.item]=(counts[b.item] or 0)+1
            -- the copy leaves the victim's count (so retaking it works); a destroyed one still counts toward its builder's max
            local lost=p.counts[b.owner];if lost and (lost[b.item] or 0)>0 then lost[b.item]-=1 end
            -- a Stock Exchange mid-countdown (Ashton 2026-10-25: "Captor gets it"): the captor takes the stake, not the profit
            local raid=nil
            if b.invest then raid=b.invest.stake;addGold(state,now,raid);local s=stats(p,now);s.exchange+=raid;b.invest=nil end
            event(p,{kind="captured",item=b.item,owner=now,from=b.owner,tile=b.tile,raid=raid})
            b.owner=now
            table.insert(kept,b)
        else
            event(p,{kind="destroyed",item=b.item,owner=if now>0 then now else 0,from=b.owner,tile=b.tile,lost=if b.invest then b.invest.stake else nil})
        end
    end
    if changed then p.buildings=kept;p.version+=1 end
    local yards,teslas,guns,taxes,guilds,barracks,exchanges={},{},{},{},{},{},{}
    for _,b in p.buildings do
        if b.item=="stock_exchange" then table.insert(exchanges,b) end -- its income ring starts while it's being built
        if state.ticks<b.built then continue end
        if b.item=="tesla_coil" then table.insert(teslas,b)
        elseif b.item=="artillery" then table.insert(guns,b)
        elseif b.item=="warden" then
            if state.ticks>b.built and (state.ticks-b.built)%(MATCH.warden.EverySeconds*TICKS_PER_SECOND)==0 then wardenFire(state,p,b) end
        elseif b.item=="barracks" then barracks[b.owner]=true
        elseif b.item=="bank" then
            -- whole gold only (crash fix 2026-10-27): during the IndustryRamp the per-tick share is fractional, and the wire
            -- codec rejects a fractional goldEarned (MatchTransport "Invalid source goldEarned" stopped the match); the
            -- remainder carries on the building, so the total paid is unchanged
            b.carry=(b.carry or 0)+MATCH.bank.GoldPerSecond*industryRamp(state)/TICKS_PER_SECOND
            local perTick=math.floor(b.carry);b.carry-=perTick
            if perTick>0 then addGold(state,b.owner,perTick);local s=stats(p,b.owner);s.minted+=perTick end
        elseif b.item=="engineering_yard" then yards[b.owner]=true
        elseif b.item=="tax_office" then taxes[b.owner]=true
        elseif b.item=="trade_guild" then guilds[b.owner]=true end
    end
    p.yards,p.guilds,p.barracks=yards,guilds,barracks
    p.barracksActive=next(barracks)~=nil
    p.conquerActive=p.barracksActive -- Simulation's conquer() hook
    p.guildActive=next(guilds)~=nil
    if state.ticks%TICKS_PER_SECOND==0 then
        if #exchanges>0 then exchangeSecond(state,p,exchanges) end
        -- Barracks: the size scale, and a packet a second while a bonus is live (the client interpolates the fade)
        if p.barracksActive then
            sizeScale(state,p,barracks)
            for owner in barracks do local _,raw=momentum(state,p,owner);if raw>0 then p.version+=1;break end end
        end
    end
    -- Tax Office: every second, GoldPerCityLevel for each finished City level its owner holds (at most MaxLevels)
    if next(taxes) and state.ticks%TICKS_PER_SECOND==0 then
        local levels={}
        for _,city in state.cities or {} do
            if taxes[city.owner] and city.active~=false and not city.underConstruction then levels[city.owner]=(levels[city.owner] or 0)+(city.level or 1) end
        end
        for owner in taxes do
            local gain=math.floor(MATCH.tax_office.GoldPerCityLevel*math.min(MATCH.tax_office.MaxLevels,levels[owner] or 0)*industryRamp(state))
            if gain>0 then addGold(state,owner,gain);local s=stats(p,owner);s.taxed+=gain end
        end
    end
    -- Tesla Coils zap once a second, Artillery fires every EverySeconds (each on its own clock from when it was built)
    for _,b in teslas do
        if state.ticks>b.built and (state.ticks-b.built)%TICKS_PER_SECOND==0 then teslaFire(state,p,b) end
    end
    local every=MATCH.artillery.EverySeconds*TICKS_PER_SECOND
    for _,b in guns do
        if state.ticks>b.built and (state.ticks-b.built)%every==0 then artilleryFire(state,p,b,guns,teslas) end
    end
    -- Engineering Yard: one extra construction tick on each of its owner's builds
    if next(yards) then
        for _,execution in state.executions do
            if yards[execution.owner] and type(execution.remaining)=="number" and execution.remaining>1
                and type(execution.kind)=="string" and string.sub(execution.kind,1,5)=="Build" then execution.remaining-=1 end
        end
        for _,b in p.buildings do if yards[b.owner] and state.ticks<b.built-1 then b.built-=1 end end
    end
end
-- an owner's Guild gold not yet paid out
local function pool(p: any,owner: number): any
    p.pools=p.pools or {}
    local o=p.pools[owner];if not o then o={guild=0};p.pools[owner]=o end
    return o
end
-- conquer() hook (while any Barracks stands): `to` takes a tile from `from`, before the counts change; a Barracks owner gains
-- PerTile momentum (at most Cap) for a tile from a nation/human, its fade restarting from this capture
function M.conquered(state: any,from: number,to: number,_tile: number?)
    local p=state.premium
    if not p.barracks[to] then return end
    local kind=state.players[from] and state.players[from].playerType
    if kind~="Nation" and kind~="Human" then return end
    local B=MATCH.barracks
    local _,raw=momentum(state,p,to)
    local m=p.momentum[to]
    if m then m.raw,m.at=math.min(B.Cap,raw+B.PerTile),state.ticks else p.momentum[to]={raw=math.min(B.Cap,B.PerTile),at=state.ticks} end
end
-- OpenFrontTrade hook (while a Trade Guild stands): `owner`'s Port just earned `gold` from a trade ship (not piracy)
function M.tradeGold(state: any,owner: number,gold: number)
    local p=state.premium
    if not p or not p.guilds[owner] then return end
    local s=stats(p,owner)
    local owed=pool(p,owner)
    local extra=math.min(MATCH.trade_guild.Cap-s.traded-owed.guild,math.floor(gold*MATCH.trade_guild.GoldBonus*industryRamp(state)))
    if extra>0 then owed.guild+=extra end -- paid out by the tick at PayPerSecond (the Cap counts what's owed too)
end
-- OpenFrontWarships hook (while a Trade Guild stands): true = this trade ship can't be captured (its owner has a Guild and
-- it is within SafeRange of one of its owner's Ports)
function M.tradeSafe(state: any,ship: any): boolean
    local p=state.premium
    if not p or not p.guilds[ship.owner] then return false end
    local w,r=state.map.width,MATCH.trade_guild.SafeRange
    local sx,sy=(ship.tileId-1)%w,(ship.tileId-1)//w
    for _,port in state.ports or {} do
        if port.owner==ship.owner and port.active~=false then
            local px,py=(port.tileId-1)%w,(port.tileId-1)//w
            if (px-sx)^2+(py-sy)^2<=r*r then return true end
        end
    end
    return false
end
-- OpenFrontWarships hook: a warship would have targeted this trade ship but the Shipping Co. kept it safe (tradeSafe true,
-- past every other exclusion). The fx guild_save, at most once per GUILD_SAVE_SECONDS a ship (targeting re-runs every tick)
local GUILD_SAVE_SECONDS=10
function M.guildSaved(state: any,ship: any,warship: any)
    local p=state.premium
    if not p then return end
    p.guildSaves=p.guildSaves or {}
    local key=ship.id or ship
    local last=p.guildSaves[key]
    if last and state.ticks-last<GUILD_SAVE_SECONDS*TICKS_PER_SECOND then return end
    p.guildSaves[key]=state.ticks
    emit(state,p,{kind="guild_save",owner=ship.owner,ship=ship.id,tile=ship.tileId,by=warship and warship.owner or nil})
end
-- the State packet for one viewer: every premium building on the map + the viewer's own build options
function M.packet(state: any,viewer: number): any?
    local p=state.premium
    if not p then return nil end
    local buildings={}
    for _,b in p.buildings do
        local invest=b.invest -- a Stock Exchange mid-countdown: everyone sees it (a raid target)
        table.insert(buildings,{id=b.id,owner=b.owner,item=b.item,tile=b.tile,built=b.built,level=M.doublings(state,b),
            invest=if invest then {stake=invest.stake,payout=invest.payout,started=invest.started,ends=invest.ends,risk=invest.risk} else nil})
    end
    local options={}
    -- build options only while the viewer can build (the placeholder row hides on the spawn screen, the end card, spectating)
    if p.owned[viewer] and state.phase=="Playing" and (state.counts[viewer] or 0)>0 then
        for _,id in M.BUILDINGS do
            if not p.owned[viewer][id] then continue end
            -- once built, the Training Camp's slot is Train and the Stock Exchange's is Invest
            local b=if id=="training_camp" or id=="stock_exchange" then own(p,viewer,id) else nil
            if b and id=="training_camp" then
                local troops,cost=trainOffer(state,viewer)
                table.insert(options,{item=id,kind="train",troops=troops,cost=cost,full=troops<=0,built=b.built,
                    readyTick=math.max(b.built,(p.trainedAt[viewer] or -math.huge)+MATCH.training_camp.Cooldown*TICKS_PER_SECOND)})
            elseif b then
                local stake,payout=investOffer(state,p,viewer)
                table.insert(options,{item=id,kind="invest",stake=stake,payout=payout,gain=investGain(state),readyTick=b.built,
                    active=if b.invest then {stake=b.invest.stake,payout=b.invest.payout,ends=b.invest.ends} else nil})
            else
                table.insert(options,{item=id,kind="build",cost=M.cost(state,viewer,id),count=M.count(state,viewer,id),max=#MATCH[id].Costs})
            end
        end
        for _,id in M.LAUNCHES do
            if p.owned[viewer][id] then
                local ready=if id=="airdrop" then (p.airdropAt[viewer] or -math.huge)+MATCH.airdrop.Cooldown*TICKS_PER_SECOND else nil
                table.insert(options,{item=id,kind="launch",cost=M.cost(state,viewer,id),count=M.count(state,viewer,id),readyTick=ready})
            end
        end
    end
    local projectiles={}
    for _,shot in p.projectiles do
        table.insert(projectiles,{id=shot.id,owner=shot.owner,item=shot.item,from=shot.from,to=shot.to,launched=shot.launched,arrive=shot.arrive,hits=shot.hits})
    end
    local events={}
    for _,e in p.events do table.insert(events,table.clone(e)) end
    -- the FX of the last 2 s (a packet goes out on each new one; the client plays each id once)
    local fx={}
    for _,e in p.fx do if e.tick>=state.ticks-2*TICKS_PER_SECOND then table.insert(fx,table.clone(e)) end end
    local s=p.stats[viewer]
    -- the viewer's Barracks bonus (only while one stands): bonus now (0..cap, after the size fade), the momentum and the size
    -- scale apart, and the tick it fades to 0 (the HUD chip's ring)
    local barracks=nil
    if p.barracks and p.barracks[viewer] then
        local bonus,raw,scale=momentum(state,p,viewer)
        local m=p.momentum[viewer]
        barracks={bonus=bonus,raw=raw,scale=scale,cap=MATCH.barracks.Cap,
            fadeEnds=if m and raw>0 then m.at+MATCH.barracks.FadeSeconds*TICKS_PER_SECOND else state.ticks}
    end
    return {kind="Premium",version=p.version,ticks=state.ticks,width=state.map.width,height=state.map.height,buildings=buildings,options=options,
        projectiles=projectiles,events=events,fx=fx,barracks=barracks,
        -- the economy buildings' output ramp (Bank / Tax / Bounty / Guild): match seconds of play `from` (0%) → `full` (100%),
        -- and `share` now (0..1), for the hover card / Armory line "Full output at 8:00"
        industry=if MATCH.IndustryRamp then {from=MATCH.IndustryRamp.From,full=MATCH.IndustryRamp.Full,share=industryRamp(state)} else nil,
        stats=if s then {minted=math.floor(s.minted),zapped=s.zapped,shelled=s.shelled,
            intercepted=math.floor(s.intercepted),taxed=s.taxed,traded=s.traded,warded=s.warded,trained=s.trained,invested=s.invested,
            exchange=s.exchange} else nil}
end
return M
