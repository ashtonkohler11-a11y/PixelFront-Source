--!strict
-- OpenFront 93a136a: GameRunner.ts:239-263; NameBoxCalculator.ts;
-- name-pass/index.ts and name.vert.glsl; render-settings.json:218-239.
-- Native font rasterization uses verified weighted Ubuntu. Placement,
-- cadence, interpolation, owner colors and troop values use source rules;
-- original-design screen bounds keep developed empires readable at every zoom.
local Typography=require(game:GetService("ReplicatedStorage").Shared.PixelFrontTypography)
local TextBounds=require(script.Parent.BattleHudTextBounds)
local Theme = require(game:GetService("ReplicatedStorage").Shared.Theme)
local Performance = require(game:GetService("ReplicatedStorage").Shared.Performance)
local NameLayout = require(script.Parent.NameLayout)
local DiplomacyStatusRenderer = require(script.Parent.DiplomacyStatusRenderer)
local ClientNames=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local GraphicsSettings=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local Names = {}
local CosmeticArt=require(script.Parent.CosmeticArt)
local CustomFlagView=require(script.Parent.CustomFlagView) -- PF020 G1 (PF - 3)
local okGeo,Geo=pcall(require,script.Parent.FrameGeometry) -- PF - 4 perf: one layout read a frame, not one per renderer
local Players=game:GetService("Players")
local Catalog=require(game:GetService("ReplicatedStorage").Shared.CosmeticCatalog)
local FIRST_LAYOUT_SECONDS=.012 -- per update, for names laid out the first time (see Names:update)
Names.__index = Names
local function glow(label: TextLabel): {TextLabel}
    local layers={}
    for index=1,8 do local copy=label:Clone();local style=copy:FindFirstChild("PFStyle");if style then style:Destroy() end;copy.Name=label.Name.."HoverGlow"..index;copy.ZIndex=math.max(1,label.ZIndex-1);copy.TextTransparency=1;copy.TextColor3=Color3.new(1,1,1);copy.Outline.Color=Color3.new(1,1,1);copy.Outline.Transparency=1;copy.Visible=false;copy.Parent=label.Parent;table.insert(layers,copy) end
    return layers
end

-- statusTemplate is passed explicitly: since PF013 the map (and this names layer)
-- lives in its own ScreenGui, so a "Game" ancestor no longer exists here.
function Names.new(parent: Frame, template: Frame, formatTroops: (number) -> string, statusTemplate: ImageLabel?)
    if not statusTemplate then
        local ui=parent:FindFirstAncestor("Game");statusTemplate=ui and ui:FindFirstChild("Templates") and ui.Templates:FindFirstChild("DiplomacyStatusIcon") :: any
    end
    return setmetatable({ parent=parent, template=template, formatTroops=formatTroops,
        status=if statusTemplate then DiplomacyStatusRenderer.new(statusTemplate) else nil,
        slots={}, entries={}, layoutCaches={}, state=nil, graphics=GraphicsSettings.resolve(),phase=0, lastTick=-1, lastPhase=nil }, Names)
end
function Names:setPreferences(preferences: any)
    self.preferences=preferences;if self.status then self.status:setPreferences(preferences) end
    self:refreshPresentation()
end
function Names:measureName(owner: number,slot: any)
    local function commit()
        if self.slots[owner]~=slot or not slot.ui.Parent then return end
        slot.nameWidth=TextBounds.measure(slot.name,10000).X
    end
    slot.nameWidth=TextBounds.measure(slot.name,10000,commit).X
    slot.measuredName=slot.name.Text;slot.measuredNameFace=slot.name.FontFace
end
function Names:measureTroops(owner: number,slot: any)
    local function commit()
        if self.slots[owner]~=slot or not slot.ui.Parent then return end
        slot.troopWidth=TextBounds.measure(slot.troops,10000).X
    end
    slot.troopWidth=TextBounds.measure(slot.troops,10000,commit).X
    slot.measuredTroopText=slot.troops.Text;slot.measuredTroopFace=slot.troops.FontFace
end
function Names:setGraphics(settings: any)
    self.graphics=settings;if self.status then self.status:setGraphics(settings) end
    for _,slot in self.slots do slot.geometry.base=-1;slot.atRest=false;slot.renderedFont=nil;slot.renderedFade=nil end
    self:refreshPresentation()
end
-- PF020 (PF - 2): MatchController passes NameplateStyle, which supplies the VIP lookup and the
-- Animated Nameplate styles. Without it (headless harnesses) plates show neither.
function Names:setBadges(badges: any)
    self.badges=badges
    if self.cosmeticLooks then self:setCosmetics(self.cosmeticLooks) end
end
function Names:setCosmetics(looks: any)
    self.cosmeticLooks=looks
    local badges=self.badges;local restyled=false
    for owner,slot in self.slots do
        local look=looks[owner] or {}
        -- PF023 (PF - 1): a level nameplate (L90 / L190) sits on a plate; the flag, level badge and crown move out
        -- past its caps (NameplateStyle.PLATE_PAD in the 48 px design space)
        local plateStyle=if badges and badges.plateOf and slot.ui:FindFirstChild("PFLevelPlate") then badges.plateOf(badges.of(look.Nameplate)) else nil
        slot.platePad=if plateStyle then badges.PLATE_PAD else 0
        for _,pair in {{"Flag","CosmeticFlag"},{"Crown","CosmeticCrown"}} do
            local icon=slot.ui:FindFirstChild(pair[2]);local id=look[pair[1]]
            -- PF020 G1 (PF - 3): an equipped custom flag takes the Flag's place (validated in CosmeticAppearance)
            local custom=if pair[1]=="Flag" then look.customFlag else nil
            local key=custom or id
            if icon and slot["cosmetic"..pair[1]]~=key then
                if custom then CosmeticArt.bind(icon,nil);CustomFlagView.paint(icon,custom) else CustomFlagView.clear(icon);CosmeticArt.bind(icon,id) end
                slot["cosmetic"..pair[1]]=key
            end
            if icon and pair[1]=="Flag" then
                icon.AnchorPoint=Vector2.new(1,.5)
                icon.Position=UDim2.fromOffset(-slot.nameWidth/2-10-(slot.levelWidth or 0)-slot.platePad,0) -- PF023: the flag sits left of the level badge
            elseif icon and not self.status then
                -- the #1 crown sits above the name, where the authored default crown pip sits (applyCrowns shows it).
                -- With the status row (every match) the crown takes the source crown's slot there instead and fades
                -- on hover like it (DiplomacyStatusRenderer.draw; Ashton 2026-10-12).
                icon.AnchorPoint=Vector2.new(.5,1);icon.Position=UDim2.fromOffset(0,-20)
            end
        end
        if not badges then continue end
        -- V3 (G5b mockup): a VIP's plate shows a warm underglow and a gold name. (The crown pip is the #1 crown now:
        -- Ashton 2026-10-08, "vip crown should just add as an accessory, not be a seperate crown"; applyCrowns.)
        local vip=self.state~=nil and badges.isVip(self.state,owner)
        local underglow=slot.ui:FindFirstChild("PFVipGlow")
        if underglow then
            if underglow.Visible~=vip then underglow.Visible=vip end
            -- The 9-slice halo (all falloff at the authored 60 px height) hugs the measured name.
            if vip then underglow.Size=UDim2.fromOffset(slot.nameWidth+40,60) end
        end
        -- G9b: an equipped Animated Nameplate style wins; otherwise a VIP's name is gold.
        local style=badges.of(look.Nameplate) or (if vip then "vip" else nil)
        local gradient=slot.name:FindFirstChild("PFStyle")
        if not gradient then style=nil end
        if slot.nameStyle~=style then
            if gradient then badges.apply(gradient,style) end
            slot.nameStyle=style;slot.styleGradient=gradient;restyled=true
        end
        if not gradient then plateStyle=nil;slot.platePad=0 end
        if slot.levelPlate~=plateStyle then -- PF023 (PF - 1)
            if badges.showPlate then badges.showPlate(slot.ui,plateStyle) end
            slot.levelPlate=plateStyle;slot.levelKey=nil;restyled=true -- re-place the flag outside the plate
        end
    end
    self:applyCrowns()
    if restyled then self:refreshPresentation() end
end
-- Ashton (2026-10-08): "crowns should show in lobby and everything but in game, it just sits on the #1 player ... all
-- crowns just equip for the #1 crown". In a match only the leaderboard's #1 (most land; ties by registration, as the
-- leaderboard sorts) wears a crown, above the name: their equipped crown (any crown, the Gilded Crown included), else
-- the default gold crown (the authored PFVipCrown pip). Nobody else shows one. A challenger takes the crown only with
-- CROWN_MARGIN more land than the holder, so near-ties never flicker.
Names.CROWN_MARGIN=1.02
function Names.crownLeader(state: any,current: number?): number?
    local best,bestCount,bestOrder=nil,0,math.huge
    for registration,owner in state.playerOrder or {1,2} do
        local count=state.counts[owner] or 0
        if count>bestCount or (count>0 and count==bestCount and registration<bestOrder) then best,bestCount,bestOrder=owner,count,registration end
    end
    if current~=nil and best~=nil and current~=best then
        local held=state.counts[current] or 0
        if held>0 and bestCount<held*Names.CROWN_MARGIN then return current end
    end
    return best
end
function Names:applyCrowns()
    local holder=self.crownHolder;local looks=self.cosmeticLooks or {}
    for owner,slot in self.slots do
        local top=owner==holder
        local id=(looks[owner] or {}).Crown
        local equipped=top and type(id)=="string" and Catalog.byId[id]~=nil and Catalog.byId[id].category=="Crown"
        local icon,pip=slot.ui:FindFirstChild("CosmeticCrown"),slot.ui:FindFirstChild("PFVipCrown")
        if icon and icon.Visible~=equipped then icon.Visible=equipped end
        local default=top and not equipped
        if pip and pip.Visible~=default then pip.Visible=default end
    end
end
-- PIVOT (Ashton 2026-10-26: Levels "Remove it"): the PF023 level badge left of the name is gone (hidden, no width), so
-- the cosmetic flag sits right against the name. (The L90 / L190 level nameplates are owned cosmetics: they stay.)
function Names:placeLevel(owner: number,slot: any,player: any)
    local key=tostring(slot.nameWidth)..":"..tostring(slot.platePad)
    if slot.levelKey==key then return end
    slot.levelKey=key;slot.levelWidth=0
    local badge=slot.ui:FindFirstChild("PFLevel");if badge then badge.Visible=false end
    local flag=slot.ui:FindFirstChild("CosmeticFlag")
    if flag then flag.Position=UDim2.fromOffset(-slot.nameWidth/2-10-(slot.platePad or 0),0) end
end
function Names:refreshPresentation()
    if not self.state then return end
    local settings=(self.graphics or GraphicsSettings.resolve()).name
    for owner,slot in self.slots do
        local player=self.state.players[owner];local text=ClientNames.resolve(self.state,owner,self.preferences)
        if slot.name.Text~=text then slot.name.Text=text end
        if slot.measuredName~=text or slot.measuredNameFace~=slot.name.FontFace then self:measureName(owner,slot) end
        self:placeLevel(owner,slot,player)
        if slot.presentationName~=text then
            for _,layer in slot.nameGlow do layer.Text=text end
            slot.presentationName=text
        end
        local color=(self.colors and self.colors[owner]) or (if player.playerType=="Bot" then Theme.Bot else Theme.playerColor(player.id))
        local shade=if player.playerType=="Human" then 0 elseif player.playerType=="Nation" then settings.nameShadeNation else settings.nameShadeBot
        local fill=if settings.fillUsePlayerColor then color else Color3.new(shade,shade,shade)
        local outline=if settings.outlineUsePlayerColor then color else Color3.new(settings.outlineR,settings.outlineG,settings.outlineB)
        -- A styled name renders white: its PFStyle gradient supplies the colour (PF020 G9b).
        local nameFill=if slot.nameStyle then Color3.new(1,1,1) else fill
        if slot.presentationFill~=fill or slot.presentationNameFill~=nameFill then
            slot.name.TextColor3=nameFill;slot.troops.TextColor3=fill;slot.presentationFill=fill;slot.presentationNameFill=nameFill
        end
        if slot.presentationOutline~=outline then slot.nameStroke.Color=outline;slot.troopStroke.Color=outline;slot.presentationOutline=outline end
    end
end

function Names:reset()
    if self.status then self.status:reset() end
    for _, slot in self.slots do slot.ui:Destroy() end
    self.slots, self.entries, self.layoutCaches = {}, {}, {}
    self.phase, self.lastTick, self.lastPhase = 0, -1, nil
end

function Names:update(state: any, owned: {[number]: {[number]: boolean}}, full: boolean?, colors: {[number]: Color3}?)
    self.state = state;self.colors=colors
    local now = os.clock()
    local profiling=Performance.start()~=nil
    local layoutElapsed,layoutCalls,troopChanges,troopWrites=0,0,0,0
    local fallbackElapsed,fallbackTiles,sampledCells,histogramRows=0,0,0,0
    local tick = state.ticks or math.floor((state.elapsed or 0) * 10 + .5)
    local recalculate = full or self.lastPhase ~= state.phase or tick < 3 or (tick ~= self.lastTick and tick % 30 == 0)
    local order = state.playerOrder or {1, 2}
    local phase = self.phase
    self.phase = (phase + 1) % 4
    -- Tester round 2026-10-13 (Tenzo: the first 30-40 s of a match lag on mobile): a name's first layout builds its
    -- cache (~11 ms each on PC), and the first full packet laid out all ~60 at once (0.7 s on PC, seconds on a phone).
    -- New layouts now share a per-update budget, yours first; the rest follow in the next updates.
    local firstLayouts=0;local firstDeadline=os.clock()+FIRST_LAYOUT_SECONDS;local ownDone=false
    if not self.layoutCaches[1] and state.counts[1] and state.counts[1]>0 then
        local cache=NameLayout.newCache();self.layoutCaches[1]=cache;self.entries[1]=NameLayout.place(state,1,owned[1],cache);firstLayouts+=1;ownDone=true
    end
    for index, owner in order do
        local player = state.players and state.players[owner]
            or { id=if owner==1 then "human-1" else "bot-2", name=state.names[owner], playerType=if owner==1 then "Human" else "Bot" }
        local alive = (state.counts[owner] or 0) > 0
        local slot = self.slots[owner]
        if not alive then
            if slot then
                slot.alive=false
                if slot.lastVisible then slot.ui.Visible=false;slot.lastVisible=false end
            end
            continue
        end
        -- over this update's first-layout budget: this name waits for the next update
        if self.layoutCaches[owner]==nil and not self.entries[owner] and firstLayouts>0 and os.clock()>firstDeadline then continue end
        if owner==1 and ownDone then
            -- yours: laid out above, this update
        elseif recalculate or not self.entries[owner] then
            local layoutStarted=if profiling then os.clock() else 0
            local cache=self.layoutCaches[owner]
            if not cache then cache=NameLayout.newCache();self.layoutCaches[owner]=cache;firstLayouts+=1 end
            cache.profile=profiling
            self.entries[owner] = NameLayout.place(state, owner, owned[owner],cache)
            if profiling then
                layoutElapsed+=os.clock()-layoutStarted
                fallbackElapsed+=cache.fallbackSeconds;fallbackTiles+=cache.fallbackTiles
                sampledCells+=cache.sampledCells;histogramRows+=cache.histogramRows
            end
            layoutCalls+=1
        elseif state.phase == "Choosing" and player.playerType ~= "Bot" then
            self.entries[owner] = NameLayout.spawn(state, owner,self.layoutCaches[owner])
        end
        local entry = self.entries[owner]
        if not entry then continue end
        if not slot then
            local ui = self.template:Clone()
            ui.Name = "Owner" .. owner
            ui:SetAttribute("Owner", owner)
            ui.Parent = self.parent
            local name = ui:WaitForChild("PlayerName") :: TextLabel
            local troops = ui:WaitForChild("Troops") :: TextLabel
            local uiScale = ui:WaitForChild("Scale") :: UIScale
            local nameStroke = name:WaitForChild("Outline") :: UIStroke
            local troopStroke = troops:WaitForChild("Outline") :: UIStroke
            name.Text = ClientNames.resolve(state,owner,self.preferences)
            Typography.apply(name,"Label");Typography.apply(troops,"Value")
            local shade = if player.playerType=="Human" then 0 elseif player.playerType=="Nation" then .3 else .4
            local color = if colors and colors[owner] then colors[owner] elseif player.playerType=="Bot" then Theme.Bot else Theme.playerColor(player.id)
            name.TextColor3=Color3.new(shade,shade,shade)
            troops.TextColor3=name.TextColor3
            nameStroke.Color,troopStroke.Color=color,color
            slot = { ui=ui, name=name, troops=troops, src={x=0,y=0,size=0}, target={x=0,y=0,size=0}, start=now,
                -- Allocate the sixteen native halo labels only when this plate
                -- is actually hovered, rather than for every nation and tribe.
                uiScale=uiScale,nameStroke=nameStroke,troopStroke=troopStroke,nameGlow={},troopGlow={},
                geometry={x=0,y=0,size=0,font=1,lineHeight=.75,base=1},atRest=false,lastVisible=false,
                alive=true, bucket=-1, nameWidth=#name.Text*48*.7 }
            self.slots[owner] = slot;self.crownDirty=true
            self:measureName(owner,slot)
        end
        -- Shape exact weighted text only at source-update cadence and only
        -- after visible text is committed. Render/draw remains non-yielding;
        -- zoom-culled plates retain the existing conservative width estimate.
        if slot.lastVisible and slot.renderedTroopText==slot.lastTroopText
            and (slot.measuredTroopText~=slot.troops.Text or slot.measuredTroopFace~=slot.troops.FontFace) then
            self:measureTroops(owner,slot)
        end
        slot.alive = true
        if not full and (index-1)%4 ~= phase and slot.bucket >= 0 then continue end
        if entry.x ~= slot.target.x or entry.y ~= slot.target.y or entry.size ~= slot.target.size then
            local t = if full then 1 else math.min(1-math.exp(-10*(now-slot.start)),1)
            for _, key in {"x","y","size"} do slot.src[key] += (slot.target[key]-slot.src[key])*t end
            if full then slot.src=table.clone(entry) end
            slot.target,slot.start=entry,now
            slot.atRest=false
        end
        local bucket = math.floor((now+((index-1)%5)*.1)/.5)
        if full or bucket ~= slot.bucket then
            slot.bucket = bucket
            local troopText=self.formatTroops(state.troops[owner] or 0)
            if troopText~=slot.lastTroopText then
                slot.lastTroopText=troopText
                -- One troop-font em per byte conservatively covers formatted
                -- numbers/suffixes without shaping text on hidden plates.
                slot.troopWidth=#troopText*28.8
                troopChanges+=1
                -- Keep the source's desired-value cadence while avoiding native
                -- text shaping for a plate that is already zoom-culled.
                if slot.lastVisible then
                    slot.troops.Text=troopText;slot.renderedTroopText=troopText
                    troopWrites+=1
                end
            end
        end
    end
    self.lastTick,self.lastPhase=tick,state.phase
    local presentationStarted=Performance.start()
    self:refreshPresentation()
    Performance.finish("PlayerNames.presentation",presentationStarted)
    -- the crown holder first: the status row reserves the #1 crown's slot for the same player the crown sits on
    local holder=Names.crownLeader(state,self.crownHolder)
    local crownChanged=holder~=self.crownHolder or self.crownDirty
    self.crownHolder=holder;self.crownDirty=false
    local statusStarted=Performance.start()
    if self.status and state.diplomacy then self.status:update(state,self.slots,if holder~=nil then holder else false) end
    Performance.finish("PlayerNames.status",statusStarted)
    if profiling and layoutCalls>0 then Performance.finish("PlayerNames.layout",os.clock()-layoutElapsed) end
    if profiling and fallbackElapsed>0 then Performance.finish("PlayerNames.fallback",os.clock()-fallbackElapsed) end
    Performance.count("PlayerNames.layoutCalls",layoutCalls)
    Performance.count("PlayerNames.fallbackTiles",fallbackTiles)
    Performance.count("PlayerNames.sampledCells",sampledCells)
    Performance.count("PlayerNames.histogramRows",histogramRows)
    Performance.count("PlayerNames.troopChanges",troopChanges)
    Performance.count("PlayerNames.troopWrites",troopWrites)
    if self.cosmeticLooks then self:setCosmetics(self.cosmeticLooks) elseif crownChanged then self:applyCrowns() end
end

function Names:draw(scale: number, viewport: Frame, world: Frame, highlighted: number, mouse: Vector2?)
    if not self.state then return end
    local now = os.clock()
    local map = self.state.map
    local settings=(self.graphics or GraphicsSettings.resolve()).name
    local viewportPosition,viewportSize,worldPosition
    if okGeo then
        viewportPosition,viewportSize,worldPosition=Geo.viewportPosition(viewport) or Vector2.zero,Geo.viewportSize(viewport),Geo.worldPosition(world)
    else
        viewportPosition,viewportSize,worldPosition=viewport.AbsolutePosition or Vector2.zero,viewport.AbsoluteSize,world.AbsolutePosition
    end
    local width = math.max(viewportSize.X,1)
    local worldX,worldY=worldPosition.X,worldPosition.Y
    local mouseX,mouseY=if mouse then mouse.X else 0,if mouse then mouse.Y else 0
    local fadeOwner = 0
    -- NamePass.hitTestNamePlate chooses the first registered matching plate,
    -- including plates below the zoom cull. Overlaps never fade every owner.
    for _,owner in self.state.playerOrder or {1,2} do
        local slot = self.slots[owner]
        if not slot or not slot.alive then continue end
        local geometry=slot.geometry
        if not slot.atRest then
            local t=math.clamp(1-math.exp(-10*(now-slot.start)),0,1)
            geometry.x=slot.src.x+(slot.target.x-slot.src.x)*t
            geometry.y=slot.src.y+(slot.target.y-slot.src.y)*t
            geometry.size=slot.src.size+(slot.target.size-slot.src.size)*t
            local base=math.max(1,math.floor(geometry.size))
            if base~=geometry.base then
                geometry.base=base
                geometry.font=math.max(4,math.floor(base*settings.nameScaleFactor))*math.min(base*.25,settings.nameScaleCap)
                geometry.lineHeight=geometry.font*36/48
            end
            -- No epsilon or shortened animation: cache only the exact endpoint.
            slot.atRest=geometry.x==slot.target.x and geometry.y==slot.target.y and geometry.size==slot.target.size
        end
        local screenHeight=geometry.lineHeight*scale*2/width
        local boost=if slot.targeted and screenHeight<settings.cullThreshold then settings.cullThreshold/math.max(screenHeight,.0000001) else 1
        local troopWidth=slot.troopWidth or #(slot.lastTroopText or "")*28.8
        geometry.screenFont,geometry.screenWidth=NameLayout.screenFont(geometry.font,scale,boost,
            math.max(slot.nameWidth,troopWidth),slot.statusCount or 0,viewportSize.X,viewportSize.Y)
        if fadeOwner==0 and mouse then
            local centerX,centerY=worldX+geometry.x*scale,worldY+geometry.y*scale
            local halfW=geometry.screenWidth/2*geometry.screenFont/48
            local lineHeight=geometry.screenFont*36/48
            if mouseX>=centerX-halfW and mouseX<=centerX+halfW
                and mouseY>=centerY-lineHeight*(if (slot.statusCount or 0)>0 then 1.4 else .6) and mouseY<=centerY+lineHeight*1.4 then fadeOwner=owner end
        end
    end
    for owner,slot in self.slots do
        if not slot.alive then continue end
        local geometry=slot.geometry
        local screenHeight=geometry.lineHeight*scale*2/width
        local centerX,centerY=worldX+geometry.x*scale,worldY+geometry.y*scale
        local screenFont=geometry.screenFont
        local halfWidth=geometry.screenWidth/2*screenFont/48
        local margin=screenFont*36/48*2
        local onScreen=centerX+halfWidth>=viewportPosition.X and centerX-halfWidth<=viewportPosition.X+viewportSize.X
            and centerY+margin>=viewportPosition.Y and centerY-margin<=viewportPosition.Y+viewportSize.Y
        local visible=onScreen and (screenHeight>=settings.cullThreshold or slot.targeted or owner==highlighted)
        if visible and slot.lastTroopText~=nil and slot.renderedTroopText~=slot.lastTroopText then
            -- Commit before reveal so zoom and hover show the newest desired text
            -- on their very first visible frame, even between source update buckets.
            slot.troops.Text=slot.lastTroopText;slot.renderedTroopText=slot.lastTroopText
            Performance.count("PlayerNames.revealTroopWrites",1)
        end
        if visible~=slot.lastVisible then slot.ui.Visible=visible;slot.lastVisible=visible end
        if not visible then continue end
        if slot.nameStyle and self.badges then self.badges.animate(slot.styleGradient,slot.nameStyle,now) end
        if slot.levelPlate and self.badges and self.badges.animatePlate then self.badges.animatePlate(slot.ui,slot.levelPlate,now,slot.nameWidth) end -- PF023
        if geometry.x~=slot.renderedX or geometry.y~=slot.renderedY then
            slot.ui.Position=UDim2.fromScale(geometry.x/map.width,geometry.y/map.height)
            slot.renderedX,slot.renderedY=geometry.x,geometry.y
        end
        if screenFont~=slot.renderedFont then
            slot.uiScale.Scale=screenFont/48
            local thickness=settings.outlineWidth/(screenFont/48)
            slot.nameStroke.Thickness,slot.troopStroke.Thickness=thickness,thickness
            slot.renderedFont=screenFont
        end
        if geometry.size~=slot.renderedSize then
            slot.ui:SetAttribute("WorldSize",geometry.size)
            slot.renderedSize=geometry.size
        end
        local faded=owner==fadeOwner
        if faded~=slot.renderedFade then
            local transparency=if faded then 1-settings.hoverFadeAlpha else 0
            slot.name.TextTransparency,slot.troops.TextTransparency=transparency,transparency
            slot.nameStroke.Transparency,slot.troopStroke.Transparency=transparency,transparency
            slot.renderedFade=faded
        end
        -- Native text glyphs use concentric strokes for the source white SDF
        -- halo. The source width/peak and squared fade are screen-space values.
        local highlightedGlow=owner==highlighted and settings.hoverGlowAlpha>0 and settings.hoverGlowWidth>0
        if highlightedGlow and #slot.nameGlow==0 then slot.nameGlow=glow(slot.name);slot.troopGlow=glow(slot.troops) end
        local glowChanged=slot.glowShown~=highlightedGlow or highlightedGlow and
            (slot.glowFont~=screenFont or slot.glowFade~=faded or slot.glowName~=slot.name.Text or slot.glowTroops~=slot.troops.Text
            or slot.glowAlpha~=settings.hoverGlowAlpha or slot.glowWidth~=settings.hoverGlowWidth
            or slot.glowOutline~=settings.outlineWidth or slot.glowFadeAlpha~=settings.hoverFadeAlpha)
        if glowChanged then
            for _,layers in {slot.nameGlow,slot.troopGlow} do
                local previous=0
                for index,layer in layers do
                    layer.Visible=highlightedGlow
                    if not highlightedGlow then continue end
                    layer.Text=if layers==slot.nameGlow then slot.name.Text else slot.troops.Text
                    local target=(index/8)^2*settings.hoverGlowAlpha*(if faded then settings.hoverFadeAlpha else 1)
                    local alpha=(target-previous)/math.max(1-previous,.000001);previous=target
                    layer.Outline.Transparency=1-alpha
                    layer.Outline.Thickness=(settings.outlineWidth+settings.hoverGlowWidth*(9-index)/8)/(screenFont/48)
                end
            end
            slot.glowShown=highlightedGlow;slot.glowFont=screenFont;slot.glowFade=faded
            slot.glowName=slot.name.Text;slot.glowTroops=slot.troops.Text
            slot.glowAlpha=settings.hoverGlowAlpha;slot.glowWidth=settings.hoverGlowWidth
            slot.glowOutline=settings.outlineWidth;slot.glowFadeAlpha=settings.hoverFadeAlpha
        end
    end
    if self.status then self.status:draw(self.slots,fadeOwner,now) end
end
return Names
