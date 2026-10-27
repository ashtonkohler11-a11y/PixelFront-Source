--!strict
-- OpenFront93a136a: ClientGameRunner boat intents and AttacksDisplay boat rows.
local Naval=require(game:GetService("ReplicatedStorage").Shared.OpenFrontNaval)
local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local Names=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local ShipRenderer=require(script.Parent.ShipRenderer)
local Controller={}
Controller.__index=Controller
local QUERY_CACHE_LIMIT=128
function Controller.eta(ship: any,ticks: number): string
    local plan=ship.motionPlan
    if not plan then return "" end
    local remaining=plan.startTick+#plan.path*plan.ticksPerStep-ticks
    if remaining<=0 then return "0s" end
    local seconds=math.ceil(remaining/10);local minutes=math.floor(seconds/60);seconds%=60
    return (if minutes>0 then minutes.."m" else "")..(if seconds>0 then seconds.."s" else "")
end
function Controller.new(ui: Frame,world: Frame,callbacks: any)
    return setmetatable({ui=ui,world=world,callbacks=callbacks,state=nil,cache={},cacheKeys={},cacheCursor=1,rows={},freeRows={},
        renderer=ShipRenderer.new(world,ui.Templates),template=ui.Templates:WaitForChild("BoatRow")},Controller)
end
function Controller:invalidateQueries(state: any)
    -- TransportShipUtils only reads static geography, ordered departure shores,
    -- this owner's alive/cap state, the clicked owner, and candidate land shores
    -- in Manhattan radius50. Resource income/unrelated captures keep exact hits.
    local context=self.queryContext
    local shores=Naval.orderedBorders(state,1)
    local shipCount=Naval.unitCount(state,1)
    local alive=(state.counts[1] or 0)>0
    local friendships={}
    if state.diplomacy then for _,owner in state.playerOrder do if owner~=1 and Diplomacy.friendly(state,1,owner) then table.insert(friendships,owner) end end end
    local friendlySignature=table.concat(friendships,",")
    local immunity=state.phase=="Choosing" or (state.ticks or 0)-(state.startTick or 0)<(Config.Match.SpawnImmunityTicks or 50)
    local changes=state.changedOwnerIds
    if not context or context.map~=state.map or context.phase~=state.phase or context.alive~=alive
        or context.shores~=shores or context.shipCount~=shipCount or context.maxShips~=Config.Naval.MaxShips
        or context.friendlySignature~=friendlySignature or context.immunity~=immunity or changes==nil then
        self.cache={};self.cacheKeys={};self.cacheCursor=1
    elseif next(self.cache) and #changes>0 then
        local nearbyShores={};local width=state.map.width
        for _,tile in changes do
            self.cache[tile]=nil -- clicked-owner dependencies, including inland clicks
            if bit32.band(buffer.readu8(state.map.terrain,tile-1),192)==192 then
                table.insert(nearbyShores,{(tile-1)%width,math.floor((tile-1)/width)})
            end
        end
        if #nearbyShores>0 then
            for tile in self.cache do
                local x,y=(tile-1)%width,math.floor((tile-1)/width)
                for _,shore in nearbyShores do
                    if math.abs(x-shore[1])+math.abs(y-shore[2])<=50 then self.cache[tile]=nil;break end
                end
            end
        end
    end
    self.queryContext={map=state.map,phase=state.phase,alive=alive,shores=shores,shipCount=shipCount,maxShips=Config.Naval.MaxShips,friendlySignature=friendlySignature,immunity=immunity}
end
function Controller:update(state: any,colors: any,palettes: any)
    self:invalidateQueries(state)
    self.state=state;self.colors=colors;self.palettes=palettes
    self.renderer:update(state,colors,palettes)
end
function Controller:setPreferences(preferences: any) self.preferences=preferences end
function Controller:setGraphics(settings: any) self.graphics=settings;self.renderer:setGraphics(settings) end
function Controller:setAlternateView(value: boolean) self.renderer:setAlternateView(value) end
function Controller:setEffects(effects: any) self.renderer:setEffects(effects) end
function Controller:hoverOwner(tile: number?): number
    local state=self.state
    if not state or not tile or tile<1 or tile>state.map.width*state.map.height then return 0 end
    if state.map.land[tile] then return math.max(0,state.owners[tile] or 0) end
    local units={}
    for _,group in {state.warships or {},state.tradeShips or {},state.ships or {}} do
        for _,unit in group do if unit.active~=false then table.insert(units,unit) end end
    end
    -- GameView._units preserves global unit creation order, reflected by these IDs.
    table.sort(units,function(a,b) return a.id<b.id end)
    local width=state.map.width;local x,y=(tile-1)%width,math.floor((tile-1)/width)
    local nearest,owner=2500,0
    for _,unit in units do
        local at=unit.tileId;local dx,dy=(at-1)%width-x,math.floor((at-1)/width)-y;local distance=dx*dx+dy*dy
        if distance<nearest then nearest=distance;owner=unit.owner end
    end
    return owner
end
function Controller:canBoatAt(tile: number): number | boolean
    if not self.state or not self.callbacks.canPlay() then return false end
    local cached=self.cache[tile]
    if cached==nil then
        cached=Naval.canBuildTransportShip(self.state,1,tile)
        local old=self.cacheKeys[self.cacheCursor]
        if old then self.cache[old]=nil end
        self.cacheKeys[self.cacheCursor]=tile;self.cacheCursor=self.cacheCursor%QUERY_CACHE_LIMIT+1
        self.cache[tile]=cached
    end
    return cached
end
function Controller:launch(tile: number,auto: boolean?): boolean
    if not self.callbacks.canPlay() then return false end
    local spawn=self:canBoatAt(tile)
    if spawn==false then return false end
    if auto then
        if not self.state.map.land[tile] then return false end
        local width=self.state.map.width
        local dx=(tile-1)%width-((spawn :: number)-1)%width
        local dy=math.floor((tile-1)/width)-math.floor(((spawn :: number)-1)/width)
        if dx*dx+dy*dy>=10000 then return false end
    end
    self.callbacks.send("Boat",{targetId=tile,ratio=self.callbacks.ratio()})
    return true
end
function Controller:key(key: Enum.KeyCode,position: Vector2?): boolean
    if key~=Enum.KeyCode.B or not position or not self.callbacks.canPlay() then return false end
    local tile=self.callbacks.targetAt(position)
    if tile then self:launch(tile,false) end
    return true
end
function Controller:makeRow(ship: any,parent: ScrollingFrame)
    local record=table.remove(self.freeRows)
    if not record then
        local ui=self.template:Clone();ui.Parent=parent;ShipRenderer.bindSprite(ui:FindFirstChild("Ship",true))
        record={ui=ui}
        ui.Cancel.Activated:Connect(function()
            local current=record.ship
            if current and current.owner==1 and not current.isRetreating and self.callbacks.canPlay() then
                self.callbacks.send("BoatRetreat",{unitId=current.id})
            end
        end)
        ui.Focus.Activated:Connect(function()
            if record.ship then self.callbacks.focusTile(record.ship.lastTileId or record.ship.tileId) end
        end)
    end
    record.ship=ship;record.ui.Name="Boat"..ship.id;self.rows[ship.id]=record
    return record
end
-- Root retains the one grid/layout manager. Call once in each source slot:
-- outgoing after land rows, incoming after incoming armies. Return added rows.
function Controller:renderRows(parent: ScrollingFrame,startOrder: number,incoming: boolean): (number,number)
    if not self.state then return 0,0 end
    local count,committed=0,0
    local present={}
    for _,ship in self.state.ships or {} do
        local isIncoming=ship.owner~=1 and ship.originalTargetOwner==1
        local include=if incoming then isIncoming else ship.owner==1
        if ship.active==false or not include or self.state.counts[1]<=0 then continue end
        count+=1;present[ship.id]=true
        if not incoming then committed+=ship.troops end
        local record=self.rows[ship.id] or self:makeRow(ship,parent);record.ship=ship
        -- PF018: incoming boats sort with the incoming armies, above outgoing rows.
        local row=record.ui;row.Visible=true;row.LayoutOrder=(if incoming then -100000 else 0)+startOrder+count
        row:SetAttribute("UnitId",ship.id);row:SetAttribute("Incoming",incoming);row:SetAttribute("Retreating",ship.isRetreating)
        local target=if incoming then ship.owner else math.max(0,self.state.owners[ship.targetTileId] or 0)
        -- PF018: parts sit inside the authored row (any depth); the authored flex strip
        -- places them, so no geometry is written here. Colours follow HudControls.layoutAttackRow.
        local part=function(name: string): any return row:FindFirstChild(name,true) end
        part("Target").Text=if target==0 then "Wilderness" else Names.resolve(self.state,target,self.preferences)
        part("Troops").Text=(if incoming then "↓ " else "↑ ")..self.callbacks.displayTroops(ship.troops)
        local eta=Controller.eta(ship,self.state.ticks);part("ETA").Text=eta;part("ETA").Visible=eta~=""
        part("Retreating").Visible=not incoming and ship.isRetreating;row.Cancel.Visible=not incoming and not ship.isRetreating and self.callbacks.isController()
        row.Focus.Visible=true
        ShipRenderer.tintSprite(part("Ship"),ship.owner,self.colors,self.palettes)
    end
    for id,record in self.rows do
        local priorIncoming=record.ui:GetAttribute("Incoming")==true
        if priorIncoming==incoming and not present[id] then record.ui.Visible=false;record.ship=nil;self.rows[id]=nil;table.insert(self.freeRows,record) end
    end
    return count,committed
end
function Controller:draw(zoom: number,viewport: Frame) self.renderer:draw(zoom,viewport) end
function Controller:reset()
    self.renderer:reset();self.state=nil;self.cache={};self.cacheKeys={};self.cacheCursor=1;self.queryContext=nil
    for _,record in self.rows do record.ui.Visible=false;record.ship=nil;table.insert(self.freeRows,record) end
    self.rows={}
end
return Controller
