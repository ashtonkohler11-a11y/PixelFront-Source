--!strict
-- OpenFront 93a136a: StructurePass/StructureLevelPass/BarPass and render-settings.
-- Original revamp fits the retained glyphs inside smaller, bounded structure markers.
local Icons=require(script.Parent.ReferenceIcons)
local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
local Industry=require(script.Parent.IndustryRenderer)
local GraphicsSettings=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local LevelFont=require(script.Parent.StructureLevelFont)
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local IconStorage=game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontIcons")
-- PF028 buildings v2 (PF - 3): one uploaded sprite per kind × set (BuildingSprites), the same pixels as the shop tile.
-- Soft: without it (harnesses, before the sheets exist) the composed plate + glyph draws as before.
local Sprites: any=nil
do local ok,result=pcall(function() return require((game :: any):GetService("ReplicatedStorage").Shared.BuildingSprites) end);if ok then Sprites=result end end
-- PF - 4 building animations (Ashton 2026-10-27): a site rises in its owner's colours, paced by construction, then lands
-- (BuildAnim). Soft: without it, the grey plate + progress bar as before.
local okAnim,BuildAnim=pcall(require,script.Parent.BuildAnim)
local okAnimMath,BuildAnimMath=pcall(require,script.Parent.BuildAnimMath)
local okGeo,Geo=pcall(require,script.Parent.FrameGeometry) -- PF - 4 perf: one layout read a frame, not one per renderer
local PB:(string)->(),PE:()->()=(debug :: any).profilebegin or function(_: string) end,(debug :: any).profileend or function() end -- microprofile labels (no-ops outside Roblox)
local ANIM=okAnim and okAnimMath
local Renderer={}
Renderer.__index=Renderer
local function invalidateDraw(self: any)
    self.drawRevision=(self.drawRevision or 0)+1
    -- Reset/setters must not retain an obsolete snapshot or effect renderer
    -- while the match is idle and no following draw replaces the cache.
    self.lastDrawState=nil;self.lastDrawEffects=nil;self.lastDrawGraphics=nil
end
function Renderer.iconSize(zoom: number,settings: any?): number
    settings=settings or {iconSize=60,dotsZoomThreshold=1.2,dotScale=.3,iconGrowZoom=7,iconScaleFactorZoomedOut=3}
    return settings.iconSize*(if zoom<=settings.dotsZoomThreshold then settings.dotScale elseif zoom<settings.iconGrowZoom then math.min(1,zoom/settings.iconScaleFactorZoomedOut) else zoom/settings.iconGrowZoom)
end
function Renderer.presentationSize(zoom: number,settings: any?): number
    local source=Renderer.iconSize(zoom,settings)
    -- Preserve the useful low-zoom dot; close views should reveal land, not
    -- keep growing one marker until it obscures an entire build neighborhood.
    return if zoom<=(if settings then settings.dotsZoomThreshold else 1.2) then math.min(source*.7,12) else math.min(source*.72,64)
end
function Renderer.glyphFill(kind: string): number
    return if kind=="DefensePost" then .58 elseif kind=="SAMLauncher" then .62 else .64
end
function Renderer.glyphAsset(kind: string): string
    -- Additive native import restores the complete source atlas cell. Old fallback permits
    -- boot while the sole native owner installs it; it is not corrected-native acceptance.
    if not IconStorage then IconStorage=game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontIcons")end
    local asset=IconStorage and IconStorage:FindFirstChild(kind.."MapGlyph")
    return if asset and asset:GetAttribute("PF008WorldGlyphVersion")=="2026-10-04-world-glyph-v1" then kind.."MapGlyph" else kind.."Glyph"
end
function Renderer.artPadding(): number return 1.2 end
local function fitArt(image: ImageLabel)
    image.AnchorPoint=Vector2.new(.5,.5);image.Position=UDim2.fromScale(.5,.5)
    image.ImageRectOffset=Vector2.zero;image.ImageRectSize=Vector2.zero;image.ScaleType=Enum.ScaleType.Fit
end
function Renderer.progress(city: any,ticks: number): number?
    if city.deletionMarkedTick then return math.clamp((city.deletionMarkedTick-ticks)/300,0,1) end
    if city.underConstruction then return math.clamp((ticks-city.createdTick)/(if city.unitType=="Port" then Config.Port.ConstructionTicks elseif city.unitType=="Defense Post" or city.unitType=="DefensePost" then Config.DefensePost.ConstructionTicks elseif city.unitType=="Factory" then Config.Factory.ConstructionTicks elseif city.unitType=="Missile Silo" or city.unitType=="MissileSilo" then Config.MissileSilo.ConstructionTicks elseif city.unitType=="SAM Launcher" or city.unitType=="SAMLauncher" then Config.SAMLauncher.ConstructionTicks else Config.City.ConstructionTicks),0,1) end
    if city.unitType=="Missile Silo" or city.unitType=="MissileSilo" or city.unitType=="SAM Launcher" or city.unitType=="SAMLauncher" then
        local timers=city.missileTimerQueue or {};if #timers==0 then return nil end
        local cooldown=if city.unitType=="SAM Launcher" or city.unitType=="SAMLauncher" then Config.SAMLauncher.CooldownTicks else Config.MissileSilo.CooldownTicks
        local value=(city.level-#timers)/city.level;for _,tick in timers do value+=(ticks-tick)/cooldown/city.level end
        value=math.clamp(value,0,1);return if value<1 then value else nil
    end
    return nil
end
local function multiply(c: Color3,n: number): Color3 return Color3.new(c.R*n,c.G*n,c.B*n) end
local function packedColor(value: number): Color3
    return Color3.fromRGB(bit32.band(value,255),bit32.band(bit32.rshift(value,8),255),bit32.band(bit32.rshift(value,16),255))
end
local function record(template: Frame,parent: Frame,name: string)
    local ui=template:Clone();ui.Name=name;ui.Parent=parent
    ui:SetAttribute("RuntimeCity",true)
    local art=ui:WaitForChild("Art")
    Icons.bind(art.Icon,Renderer.glyphAsset("City"))
    local padding=Renderer.artPadding()
    art.AnchorPoint=Vector2.new(.5,.5);art.Position=UDim2.fromScale(.5,.5);art.Size=UDim2.fromScale(padding,padding)
    -- Compensate the expanded capture rect, retaining effective badge and glyph sizes.
    art.Circle.Size=UDim2.fromScale(.9/padding,.9/padding);art.Fill.Size=UDim2.fromScale(.9/padding,.9/padding) -- no border ring (Ashton 2026-10-07): the fill takes its footprint
    art.Deletion.AnchorPoint=Vector2.new(.5,.5);art.Deletion.Position=UDim2.fromScale(.5,.5)
    art.Deletion.Size=UDim2.fromScale(1/padding,1/padding)
    for _,image in {art.Icon,art.ShapeBorder,art.ShapeFill}do fitArt(image)end
    art.Icon:SetAttribute("PF008GlyphAsset",Renderer.glyphAsset("City"))
    local digits={}
    for i=1,4 do local d=ui.Level[tostring(i)];Icons.bind(d,"LevelDigits");digits[i]=d end
    -- PF028: the sprite (a set's frame, or Classic's tinted plate mask) and Classic's bevel/glyph overlay, sized to the
    -- marker (the art group is padded), above the composed plate and below the deletion mark
    local function spriteLabel(name: string,z: number): ImageLabel
        local label=Instance.new("ImageLabel");label.Name=name;label.BackgroundTransparency=1;label.BorderSizePixel=0
        label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromScale(1/padding,1/padding)
        label.ScaleType=Enum.ScaleType.Stretch;label.ZIndex=z;label.Visible=false;label.Parent=art
        return label
    end
    local sprite: ImageLabel?,spriteOver: ImageLabel?=nil,nil
    if Sprites then
        local z=art.Icon.ZIndex or 1
        sprite,spriteOver=spriteLabel("PF028Sprite",z),spriteLabel("PF028SpriteOver",z+1)
        art.Deletion.ZIndex=math.max(art.Deletion.ZIndex or 1,z+2)
    end
    return {ui=ui,art=art,circle=art.Circle,fill=art.Fill,icon=art.Icon,deletion=art.Deletion,bar=ui.Progress,
        progressFill=ui.Progress.Fill,level=ui.Level,digits=digits,shapeBorder=art:WaitForChild("ShapeBorder"),shapeFill=art:WaitForChild("ShapeFill"),
        sprite=sprite,spriteOver=spriteOver}
end
-- PF-040 (Ashton: nuke aim "Good, build"): the aim's authored sprites in the IndustryRangeLayer (tools/atlas/author-pf040.luau):
-- the blast disc, the inner core, the inner and outer pixel rings (1 tile + keyline) and the UI-size reticle. Absent on an
-- older place: the old range texture and cost label stay.
local PFSprites=require(script.Parent.PF040Sprites)
-- PIVOT (MM): a blast that covers your own land shows red (no block; NukeSelfHit, the aim chip says "Hits your land")
local NukeSelfHit=require(script.Parent.NukeSelfHit)
local BLAST_SELF=Color3.fromHex("#ff5a4f")
local BLAST_WHITE,BLAST_CORE,BLAST_PEACH,BLAST_DEAD,BLAST_DEAD_LT,RETICLE_NO=Color3.new(1,1,1),Color3.fromHex("#ff7a45"),Color3.fromHex("#ffb08a"),Color3.fromHex("#9aa0a8"),Color3.fromHex("#b9bec6"),Color3.fromHex("#ff8a7a")
local function blastNodes(world: Frame): any?
    local layer=world:FindFirstChild("IndustryRangeLayer");if not layer then return nil end
    local names={disc="PFBlastDisc",core="PFBlastCore",inner="PFBlastInner",outer="PFBlastOuter",reticle="PFAimReticle"};local nodes={}
    for key,name in names do local node=layer:FindFirstChild(name);if not node or not node:IsA("ImageLabel") then return nil end;nodes[key]=node end
    return nodes
end
function Renderer.new(world: Frame,template: Frame)
    local parent=world:WaitForChild("Buildings") :: Frame
    return setmetatable({world=world,parent=parent,template=template,pool={},state=nil,drawRevision=0,graphics=GraphicsSettings.resolve(),levelFont=LevelFont.new(),started=os.clock(),highlightOwner=0,
        ghost=record(template,parent,"CityGhost"),upgrade=record(template,parent,"UpgradeTarget"),
        crosshair=world:WaitForChild("WarshipCrosshair"),cost=world:WaitForChild("GhostCost"),amount=world:WaitForChild("GhostAmount"),
        range=world:WaitForChild("IndustryRangeLayer"):WaitForChild("IndustryGhostRange"),industry=Industry.new(world,template.Parent),
        blast=blastNodes(world)},Renderer)
end
local function restoreEffects(effects: any,r: any)
    effects:frameRestore(r.fill);effects:restore(r.icon,Renderer.glyphAsset(r.kind or "City"))
    if r.kind and r.kind~="City"then effects:restore(r.shapeFill,r.kind.."ShapeFill")end
end
function Renderer:setEffects(effects: any)
    if self.effects==effects then return end
    if self.effects then for _,r in self.pool do restoreEffects(self.effects,r)end;restoreEffects(self.effects,self.ghost);restoreEffects(self.effects,self.upgrade)end
    self.effects=effects
    invalidateDraw(self)
    for _,r in self.pool do r.lastZoom=nil end
    self.industry:setEffects(effects)
end
function Renderer:setHighlightOwner(owner: number)
    if self.highlightOwner==owner then return end;self.highlightOwner=owner
    invalidateDraw(self)
    for _,r in self.pool do r.lastZoom=nil end
end
-- Source shader gate; the editor supplies an equipped effect only for owner 1.
function Renderer.structureEffectVisible(owner: number,hoverOwner: number,localOwner: number,underConstruction: boolean,altView: boolean,equipped: boolean): boolean
    return equipped and not altView and not underConstruction and owner>0 and(owner==hoverOwner or owner==localOwner)
end
function Renderer.effectGlyphColor(fill: Color3,settings: any,tint: Color3?): Color3
    local result=Color3.new(settings.iconR,settings.iconG,settings.iconB)
    if settings.iconDarken>0 then
        local value=math.clamp((fill.R*.299+fill.G*.587+fill.B*.114-.25)/.2,0,1)
        result=result:Lerp(multiply(fill,settings.iconDarken),value*value*(3-2*value))
    end
    return if tint then result:Lerp(tint,.5)else result
end
function Renderer:setPreferences(preferences: any) self.preferences=preferences;invalidateDraw(self) end
function Renderer:setAlternateView(value: boolean)
    if self.altView==value then return end;self.altView=value
    invalidateDraw(self)
    for _,r in self.pool do r.lastZoom=nil end
end
function Renderer:setGraphics(settings: any,overrides: any?)
    self.graphics=settings;self.overrides=overrides
    invalidateDraw(self)
    for _,r in self.pool do r.lastZoom=nil end
    if self.industry.setGraphics then self.industry:setGraphics(settings,overrides) end
end
function Renderer:reset()
    invalidateDraw(self)
    for _,r in self.pool do r.ui:Destroy() end
    self.pool={};self.state=nil;self:hideGhost();self.industry:reset();self.levelFont:dispose()
end
function Renderer:hideBlast() if self.blast then for _,node in self.blast do node.Visible=false end end end
function Renderer:hideGhost()
    self.ghost.ui.Visible=false;self.upgrade.ui.Visible=false;self.crosshair.Visible=false;self.cost.Visible=false;self.amount.Visible=false;self.range.Visible=false
    self:hideBlast()
    self.industry:setGhost(nil)
end
local function kindOf(unit: any): string local kind=unit.unitType or "City";return if kind=="Defense Post" then "DefensePost" elseif kind=="Missile Silo" then "MissileSilo" elseif kind=="SAM Launcher" then "SAMLauncher" elseif kind=="Atom Bomb" then "AtomBomb" elseif kind=="Hydrogen Bomb" then "HydrogenBomb" else kind end
local function glyph(kind: string): string return Renderer.glyphAsset(kind) end
local function bindKind(r: any,kind: string)
    if r.kind==kind then return end
    Icons.bind(r.icon,glyph(kind))
    r.icon:SetAttribute("PF008GlyphAsset",glyph(kind))
    if kind~="City" then Icons.bind(r.shapeBorder,kind.."Shape");Icons.bind(r.shapeFill,kind.."ShapeFill") end
    r.kind=kind
end
function Renderer:update(state: any,colors: any,palettes: any)
    -- A caller may refresh colors or reuse/mutate its state table, so every update makes the next draw visit the pool.
    -- PF032 (late game: every visible building was repainted after every packet, ~40-50 property writes each): the
    -- visit repaints only a record whose inputs changed. The record (decoded records are replaced, never edited), its
    -- owner colour and palette border and its alternate-view relation are compared below (a change clears lastZoom);
    -- ticks repaint dynamic records (construction, deletion, cooldown); setters, hover and effect revisions repaint
    -- everything as before; a record showing a structure effect still repaints on every update, as it always did.
    self.lastDrawState=nil;self.updateSerial=(self.updateSerial or 0)+1
    self.state=state;self.colors=colors;self.palettes=palettes
    local seen,relationships={},{}
    local structures=table.clone(state.cities or {})
    for _,port in state.ports or {} do table.insert(structures,port) end
    for _,factory in state.factories or {} do table.insert(structures,factory) end
    for _,post in state.defensePosts or {} do table.insert(structures,post) end
    for _,silo in state.missileSilos or {} do table.insert(structures,silo) end
    for _,sam in state.samLaunchers or {} do table.insert(structures,sam) end
    for _,city in structures do
        local r=self.pool[city.id]
        if not r then r=record(self.template,self.parent,"City"..city.id);self.pool[city.id]=r end
        local changed=r.city~=city;r.city=city;seen[city.id]=true
        local palette=palettes[city.owner];local paletteBorder=palette and palette.border
        if r.lastColor~=colors[city.owner] or r.lastPaletteBorder~=paletteBorder then r.lastZoom=nil end
        r.lastColor=colors[city.owner];r.lastPaletteBorder=paletteBorder
        if self.altView and self.graphics.altView.recolorStructures then
            local relation=relationships[city.owner]
            if relation==nil then
                local friendly,embargo=GraphicsMath.relationship(state,1,city.owner)
                relation=(if friendly then 1 else 0)+(if embargo then 2 else 0);relationships[city.owner]=relation
            end
            if r.lastRelation~=relation then r.lastZoom=nil;r.lastRelation=relation end
        end
        local kind=kindOf(city)
        bindKind(r,kind)
        if changed then
            r.ui:SetAttribute("UnitId",city.id);r.ui:SetAttribute("Owner",city.owner);r.ui:SetAttribute("Level",city.level)
            r.ui:SetAttribute("UnderConstruction",city.underConstruction);r.ui:SetAttribute("DeletionDeadline",city.deletionMarkedTick)
        end
    end
    for id,r in self.pool do if not seen[id] then r.ui:Destroy();self.pool[id]=nil end end
    PB("PF.Cities.Industry");self.industry:update(state,colors,palettes);PE()
end
-- PF020 (Ashton's late game: ~100+ ms a frame with an effect-equipped empire). A structure effect
-- is drawn from frames shared by every building of a kind (RenderEffects.paintShared, one paint per
-- effect step); the City plate's gradient moves once per effect step (EFFECT_HZ).
local EFFECT_HZ=15
local TEMPEST_RIM=Color3.fromRGB(127,232,255) -- PF020 Tempest Buildings: the storm-glass rim (#7fe8ff)
local function paintEffect(self: any,r: any,kind: string,effects: any,effectSlot: string,tint: Color3?,force: boolean,glyphColor: Color3?)
    local structure=self.graphics.structure
    local shapeScale=if kind=="Port" or kind=="Factory" then 1.08 elseif kind=="SAMLauncher" then 1.15 elseif kind=="MissileSilo" then 1.18 else 1
    local iconFill=Renderer.glyphFill(kind)
    local time=os.clock()-self.started;local step=math.floor(time*EFFECT_HZ)
    local transform=if tint then function(c: Color3): Color3 return c:Lerp(tint,.5)end else nil
    -- keys name each transform, so every building of a kind shares one painted frame
    local tintKey=if tint then "tint:"..tint:ToHex() else ""
    if kind~="City" then effects:frameRestore(r.fill);effects:paint(r.shapeFill,kind.."ShapeFill",effectSlot,time,0,0,1,"structure",nil,transform,nil,if tint then tintKey else nil)
    elseif force or r.effectStep~=step then r.effectStep=step;effects:framePaint(r.fill,effectSlot,step/EFFECT_HZ,nil,transform,.9) end -- .9: the fill takes the old ring footprint
    if glyphColor and effects.tempest and effects:tempest(effectSlot)=="effect" then
        -- PF020 Tempest effect (light only): the glyph keeps its own colour; arcs crackle over it
        effects:paint(r.icon,glyph(kind),effectSlot,time,0,0,1,"structure",nil,function(_c: Color3): Color3 return glyphColor end,iconFill/shapeScale,"tglyph:"..glyphColor:ToHex())
        return
    end
    effects:paint(r.icon,glyph(kind),effectSlot,time,0,0,1,"structure",nil,function(c: Color3): Color3 return Renderer.effectGlyphColor(c,structure,tint)end,iconFill/shapeScale,
        "glyph:"..structure.iconR..","..structure.iconG..","..structure.iconB..","..structure.iconDarken..tintKey)
end
local function effectsFor(self: any,city: any): (any,string)
    local effects=self.effects and (if self.effects.forOwner then self.effects:forOwner(city.owner) else self.effects)
    local kind=kindOf(city);local target=if kind=="SAMLauncher" then "AirDefense" else kind
    return effects,if effects and effects.targetSlot then effects:targetSlot("structures",target) else "structures"
end
-- PF028: the loop frame every set sprite shows now (one clock for the whole map: buildings of a set move together)
local function spriteFrame(self: any): number
    return math.floor((os.clock()-self.started)*Sprites.frames/Sprites.seconds)%Sprites.frames
end
local function showSpriteFrame(r: any,frame: number)
    local sheet=r.spriteSheet;local i=r.spriteKind*Sprites.frames+frame;local cell=sheet.cell
    r.sprite.ImageRectOffset=Vector2.new((i%sheet.cols)*cell,(i//sheet.cols)*cell);r.spriteFrame=frame
end
function Renderer:paint(r: any,city: any,zoom: number,position: Vector2,alpha: number,tint: Color3?)
    local structure=self.graphics.structure;local levelSettings=self.graphics.structureLevel
    local size=Renderer.presentationSize(zoom,structure)
    local kind=kindOf(city);local shapeScale=if kind=="Port" or kind=="Factory" then 1.08 elseif kind=="SAMLauncher" then 1.15 elseif kind=="MissileSilo" then 1.18 else 1
    r.ui.Size=UDim2.fromOffset(size,size);r.ui.Position=UDim2.fromOffset(position.X,position.Y);r.ui.Visible=true
    local color=self.colors[city.owner] or Color3.new(1,1,1)
    local palette=self.palettes[city.owner]
    local border=if city.owner==1 or not palette then color else packedColor(palette.border)
    if self.altView and self.graphics.altView.recolorStructures and not city.underConstruction then
        local friendly,embargo=GraphicsMath.relationship(self.state,1,city.owner)
        color=GraphicsMath.affiliation(self.graphics,city.owner==1,friendly,embargo,true);border=color
    end
    local grey=city.underConstruction and not ANIM -- PF - 4: an animated site keeps its owner colours (it rises instead)
    local fill=if grey then Color3.fromRGB(198,198,198) else multiply(color,structure.fillDarken)
    border=if grey then Color3.fromRGB(127,127,127) else multiply(border,structure.borderDarken)
    local glyphColor=Color3.new(structure.iconR,structure.iconG,structure.iconB)
    if structure.iconDarken>0 and fill.R*.299+fill.G*.587+fill.B*.114>=.25 then glyphColor=multiply(fill,structure.iconDarken) end
    if tint then fill=fill:Lerp(tint,.5);border=border:Lerp(tint,.5);glyphColor=glyphColor:Lerp(tint,.5) end
    r.circle.BackgroundColor3=border;r.fill.BackgroundColor3=fill;r.icon.ImageColor3=glyphColor
    local polygon=kind~="City"
    -- Ashton 2026-10-07: no player-coloured border ring on buildings; the plate is its fill alone.
    r.circle.Visible=false;r.fill.Visible=not polygon;r.shapeBorder.Visible=false;r.shapeFill.Visible=polygon
    if polygon then
        r.shapeBorder.ImageColor3=border;r.shapeFill.ImageColor3=fill
        local paddedScale=shapeScale/Renderer.artPadding()
        r.shapeBorder.Size=UDim2.fromScale(paddedScale,paddedScale);r.shapeFill.Size=UDim2.fromScale(paddedScale,paddedScale)
    end
    local iconFill=Renderer.glyphFill(kind)
    local paddedFill=iconFill/Renderer.artPadding()
    r.icon.Size=UDim2.fromScale(paddedFill,paddedFill)
    local effects,effectSlot=effectsFor(self,city)
    local equipped=effects~=nil and effects:has(effectSlot) and (city.owner==1 or self.effects.forOwner~=nil)
    r.effectActive=Renderer.structureEffectVisible(city.owner,self.highlightOwner,1,city.underConstruction==true,self.altView==true and self.graphics.altView.recolorStructures,equipped)
    -- PF028: the sprite this marker shows: its owner's Buildings set (while the effect gate shows it), else Classic;
    -- a structure VFX without a Buildings set keeps the composed plate and its effect
    local spriteSheet: any,spriteMode: string?=nil,nil
    if Sprites and Sprites.kindIndex[kind]~=nil then
        local px=Sprites.size(size)
        local set=if r.effectActive and effects then Sprites.setOf[effects.buildingCosmeticId or ""] else nil
        if set then spriteSheet=Sprites.sets[set][px];spriteMode="set"
        elseif not r.effectActive then spriteSheet=Sprites.classic[px];spriteMode="classic" end
        if spriteSheet and spriteSheet.image=="" then spriteSheet,spriteMode=nil,nil end
    end
    if effects then
        if r.effectActive and spriteMode~="set" then paintEffect(self,r,kind,effects,effectSlot,tint,true,glyphColor)
        else restoreEffects(effects,r);r.fill.BackgroundColor3=fill;r.icon.ImageColor3=glyphColor;if polygon then r.shapeFill.ImageColor3=fill end end
    end
    -- PF020 Tempest Buildings (MM bar pass): a thin storm-glass rim, never the owner colour, separates
    -- the plate from any land (the City's ring sits just outside its fill; polygons use their border art)
    local rim=spriteMode==nil and r.effectActive==true and effects~=nil and effects.tempest~=nil and effects:tempest(effectSlot)=="buildings"
    if rim then
        if polygon then r.shapeBorder.Visible=true;r.shapeBorder.ImageColor3=TEMPEST_RIM
        else
            local padding=Renderer.artPadding()
            r.circle.Visible=true;r.circle.BackgroundColor3=TEMPEST_RIM;r.circle.Size=UDim2.fromScale(.97/padding,.97/padding)
        end
    elseif r.tempestRim and not polygon then local padding=Renderer.artPadding();r.circle.Size=UDim2.fromScale(.9/padding,.9/padding) end
    r.tempestRim=rim
    r.art.GroupTransparency=1-alpha
    r.icon.Visible=zoom>structure.dotsZoomThreshold;r.icon.ImageTransparency=1-structure.iconAlpha;r.deletion.Visible=city.deletionMarkedTick~=nil and alpha==1
    if spriteMode then
        -- PF028: the sprite IS the building (plate + glyph); the composed pieces hide
        r.circle.Visible=false;r.fill.Visible=false;r.shapeBorder.Visible=false;r.shapeFill.Visible=false;r.icon.Visible=false
        local k=Sprites.kindIndex[kind];local cell=spriteSheet.cell
        r.sprite.Image=spriteSheet.image;r.sprite.ImageRectSize=Vector2.new(cell,cell);r.sprite.Visible=true
        if spriteMode=="set" then
            r.sprite.ImageColor3=if tint then Color3.new(1,1,1):Lerp(tint,.5) else Color3.new(1,1,1)
            r.spriteSheet,r.spriteKind=spriteSheet,k;showSpriteFrame(r,spriteFrame(self))
            r.spriteOver.Visible=false
        else
            -- Classic: the plate mask in the fill colour (the owner colour, under-construction grey, alt view, a ghost's
            -- tint), the bevel and engraved glyph over it (hidden at dot zoom, like the glyph)
            r.spriteSheet=nil
            r.sprite.ImageRectOffset=Vector2.new(k*cell,0);r.sprite.ImageColor3=fill
            r.spriteOver.Image=spriteSheet.image;r.spriteOver.ImageRectSize=Vector2.new(cell,cell);r.spriteOver.ImageRectOffset=Vector2.new((6+k)*cell,0)
            r.spriteOver.ImageColor3=Color3.new(1,1,1);r.spriteOver.ImageTransparency=1-structure.iconAlpha;r.spriteOver.Visible=zoom>structure.dotsZoomThreshold
        end
    elseif r.sprite then
        r.sprite.Visible=false;r.spriteOver.Visible=false;r.spriteSheet=nil
    end
    local progress=Renderer.progress(city,self.state.ticks)
    r.dynamic=progress~=nil
    -- PF - 4: a real map record (not the placement ghost / upgrade preview) animates its construction; its bar hides
    local animated=ANIM and alpha==1 and r~=self.ghost and r~=self.upgrade
    if animated then
        (BuildAnim :: any).site(r.ui,r.art,if city.underConstruction then progress else nil,
            {premium=false,mine=city.owner==1,fresh=(BuildAnimMath :: any).fresh(city.createdTick,self.state.ticks),px=size})
        if city.underConstruction then progress=nil end
    end
    r.bar.Visible=progress~=nil and alpha==1
    if progress then
        local barWidth=math.clamp(size*.8,18,52);local barHeight=math.clamp(size*.09,3,5)
        r.bar.Position=UDim2.new(.5,-barWidth*.5,.5,size*.52);r.bar.Size=UDim2.fromOffset(barWidth,barHeight)
        r.progressFill.Position=UDim2.fromOffset(1,1);r.progressFill.Size=UDim2.fromOffset((barWidth-2)*progress,math.max(1,barHeight-2))
        r.progressFill.BackgroundColor3=if progress<.25 then Color3.new(.91,.098,.098) elseif progress<.5 then Color3.new(.941,.478,.098)
            elseif progress<.75 then Color3.new(.792,.906,.059) else Color3.new(.173,.937,.071)
    end
    r.level.Visible=city.level>1 and zoom>structure.dotsZoomThreshold and alpha==1
    if r.level.Visible then
        local layout=LevelFont.layout(city.level,size,levelSettings)
        r.level.AnchorPoint=Vector2.zero;r.level.Position=UDim2.fromScale(.5,.5);r.level.Size=UDim2.fromOffset(0,0)
        if not levelSettings.classicFont then self.levelFont:prepare(layout[1].scale,levelSettings.outlineWidth) end
        for i,d in r.digits do
            local item=layout[i];d.Visible=item~=nil
            if d.Visible then
                if levelSettings.classicFont then Icons.bind(d,"LevelDigits");d.ImageRectOffset=Vector2.new((tonumber(item.digit) :: number)*16,64);d.ImageRectSize=Vector2.new(16,16)
                else self.levelFont:bind(d,item.digit) end
                d.AnchorPoint=Vector2.zero;d.Position=UDim2.fromOffset(item.x,item.y);d.Size=UDim2.fromOffset(item.width,item.height)
                d.ImageTransparency=1-alpha
            end
        end
    end
end
function Renderer:draw(zoom: number,viewport: Frame)
    if not self.state then return end
    local offset=if okGeo then Geo.offset(self.world,viewport) else self.world.AbsolutePosition-viewport.AbsolutePosition
    local viewportSize=if okGeo then Geo.viewportSize(viewport) else viewport.AbsoluteSize
    local effects=self.effects
    local equipped=effects~=nil and (if effects.hasAny then effects:hasAny("structures") else effects:has("structures"))
    local effectRevision=if effects then effects.revision else nil
    local width=self.state.map.width
    local margin=Renderer.presentationSize(zoom,self.graphics.structure)*1.6
    -- Between packets, stationary structures have no new projection or paint
    -- work. Animated structure effects retain the original per-frame cadence;
    -- a previously active visible record also gets its normal cleanup draw.
    if not equipped and not self.lastDrawActiveEffect and self.lastDrawRevision==self.drawRevision
        and self.lastDrawState==self.state and self.lastDrawTicks==self.state.ticks and self.lastDrawWidth==width
        and self.lastDrawZoom==zoom and self.lastDrawOffset==offset and self.lastDrawViewport==viewportSize
        and self.lastDrawGraphics==self.graphics and self.lastDrawEffects==effects and self.lastDrawEffectRevision==effectRevision
        and self.lastDrawMargin==margin then return end
    local activeEffect=false
    -- PF020: every shared structure-effect frame steps once per draw (within RenderEffects' budget)
    if equipped and effects.advanceShared then effects:advanceShared(os.clock()-self.started) end
    for _,r in self.pool do
        local id=r.city.tileId-1
        local p=Vector2.new((id%self.state.map.width+.5)*zoom,(math.floor(id/self.state.map.width)+.5)*zoom)
        local screen=offset+p
        if screen.X < -margin or screen.Y < -margin or screen.X>viewportSize.X+margin or screen.Y>viewportSize.Y+margin then
            r.ui.Visible=false
        elseif r.lastZoom~=zoom or r.lastCity~=r.city or(r.dynamic and r.lastTicks~=self.state.ticks)or not r.ui.Visible
            or r.lastRevision~=self.drawRevision or r.lastEffectRevision~=effectRevision or r.lastGraphics~=self.graphics
            or r.lastHighlight~=self.highlightOwner or r.lastAlt~=self.altView or r.lastEffects~=effects
            or (r.effectActive==nil and equipped) or (r.effectActive and r.lastUpdate~=self.updateSerial) then
            self:paint(r,r.city,zoom,p,1,nil)
            r.lastZoom=zoom;r.lastCity=r.city;r.lastTicks=self.state.ticks;r.lastUpdate=self.updateSerial
            r.lastRevision,r.lastEffectRevision,r.lastGraphics,r.lastHighlight,r.lastAlt,r.lastEffects=self.drawRevision,effectRevision,self.graphics,self.highlightOwner,self.altView,effects
            if r.effectActive then activeEffect=true end
        elseif r.effectActive then
            -- PF020: unchanged building, animated effect. Its plate and glyph show shared frames that
            -- advanceShared steps below; only a City's gradient plate moves here, once per step.
            -- PF028: a set sprite steps its loop frame instead (one ImageRectOffset when the frame changes)
            if r.spriteSheet then
                local frame=spriteFrame(self);if r.spriteFrame~=frame then showSpriteFrame(r,frame) end
            elseif (r.kind or kindOf(r.city))=="City" then
                local step=math.floor((os.clock()-self.started)*EFFECT_HZ)
                if r.effectStep~=step then
                    local fx,slot=effectsFor(self,r.city)
                    if fx then r.effectStep=step;fx:framePaint(r.fill,slot,step/EFFECT_HZ,nil,nil,.9) end
                end
            end
            activeEffect=true
        end
    end
    self.lastDrawRevision=self.drawRevision;self.lastDrawState=self.state;self.lastDrawTicks=self.state.ticks;self.lastDrawWidth=width
    self.lastDrawZoom=zoom;self.lastDrawOffset=offset;self.lastDrawViewport=viewportSize;self.lastDrawMargin=margin
    self.lastDrawGraphics=self.graphics;self.lastDrawEffects=effects;self.lastDrawEffectRevision=effectRevision;self.lastDrawActiveEffect=activeEffect
end
function Renderer:drawGhost(zoom: number,position: Vector2,query: any,multiplier: number,formatNumber: (number)->string)
    local upgrade=query.canUpgrade~=false
    multiplier=if upgrade or query.type=="Atom Bomb" then multiplier else 1
    local canPlace=query.canBuild~=false or upgrade
    local tint=if upgrade then Color3.new(0,.8,0) elseif not canPlace then Color3.new(.8,.2,.2) else nil
    local kind=kindOf({unitType=query.type})
    if kind=="MIRV" and self.blast then
        -- PF-040: MIRV aims with the reticle; its cost and status are in the aim bar
        self.ghost.ui.Visible=false;self.upgrade.ui.Visible=false;self.amount.Visible=false;self.range.Visible=false;self.crosshair.Visible=false;self.cost.Visible=false;self.industry:setGhost(nil)
        local blast=self.blast;for key,node in blast do node.Visible=key=="reticle" end
        local tx,ty=math.floor(position.X/zoom),math.floor(position.Y/zoom)
        PFSprites.bind(blast.reticle,"reticle");blast.reticle.Position=UDim2.fromOffset((tx+.5)*zoom,(ty+.5)*zoom);blast.reticle.Size=UDim2.fromOffset(52,52)
        blast.reticle.ImageColor3=if query.canBuild~=false then BLAST_WHITE else RETICLE_NO
        return
    end
    self:hideBlast()
    if kind=="Warship" or kind=="MIRV" then
        self.ghost.ui.Visible=false;self.upgrade.ui.Visible=false;self.amount.Visible=false;self.range.Visible=false;self.industry:setGhost(nil)
        if not self.crosshairBound then Icons.bind(self.crosshair,"WarshipCrosshair");self.crosshairBound=true end
        self.crosshair.ImageColor3=if query.canBuild~=false then Color3.new(.9,.15,.15) else Color3.new(.4,.1,.1)
        self.crosshair.Position=UDim2.fromOffset(position.X,position.Y);self.crosshair.Visible=true
        -- the cost sits above the ghost, the "xN" above that (UI audit 2026-10-28: below it, it covered your nation's name)
        self.cost.Text=formatNumber(query.cost);self.cost.TextColor3=if self.state.gold[1]<query.cost then Color3.new(1,.3,.3) elseif not canPlace then Color3.new(.6,.6,.6) else Color3.new(1,1,1)
        self.cost.Position=UDim2.fromOffset(position.X,position.Y-25);self.cost.Visible=query.cost>0 and (not self.preferences or self.preferences:get("cursorCostLabel"))
        return
    end
    if kind=="AtomBomb" or kind=="HydrogenBomb" then
        self.ghost.ui.Visible=false;self.upgrade.ui.Visible=false;self.crosshair.Visible=false;self.industry:setGhost(nil)
        -- the blast's outer radius from Config.Nuclear (PixelFront x0.7, PF-033: 21 / 70); the source ring textures
        -- (rendered at 30 / 100) are sized to it
        local radius=if kind=="AtomBomb" then Config.Nuclear.AtomOuter else Config.Nuclear.HydrogenOuter
        if self.blast then
            -- PF-040: the blast as the map draws land: the outer zone (a faint white disc, the 1-tile white ring and its dark
            -- keyline), the inner core (orange disc + peach ring), the reticle on the tile; grey with red brackets when it
            -- can't launch. Snapped to the tile. The cost is in the aim bar, never over the buildings.
            local cost=query.cost*multiplier;local ok=canPlace and self.state.gold[1]>=cost and (kind~="AtomBomb" or (query.readyMissileCount or 0)>=multiplier)
            local inner=if kind=="AtomBomb" then Config.Nuclear.AtomInner else Config.Nuclear.HydrogenInner
            self.crosshair.Visible=false;self.range.Visible=false;self.cost.Visible=false;self.amount.Visible=false
            local tx,ty=math.floor(position.X/zoom),math.floor(position.Y/zoom);local at=UDim2.fromOffset((tx+.5)*zoom,(ty+.5)*zoom)
            local blast=self.blast
            local selfHit=ok and NukeSelfHit.covers(self.state,ty*self.state.map.width+tx+1,radius)
            local function show(node: ImageLabel,name: string,tiles: number,color: Color3,transparency: number)
                PFSprites.bind(node,name);node.Position=at;node.Size=UDim2.fromOffset(tiles*zoom,tiles*zoom);node.ImageColor3=color;node.ImageTransparency=transparency;node.Visible=true
            end
            local dn,dt=PFSprites.disc(radius);show(blast.disc,dn,dt,if selfHit then BLAST_SELF else BLAST_WHITE,if selfHit then .82 elseif ok then .91 else .95)
            local cn,ct=PFSprites.disc(inner);show(blast.core,cn,ct,if ok then BLAST_CORE else BLAST_DEAD,if ok then .74 else .88)
            local iname,itiles=PFSprites.ring(inner);show(blast.inner,iname,itiles,if ok then BLAST_PEACH else BLAST_DEAD_LT,if ok then .15 else .45)
            local oname,otiles=PFSprites.ring(radius);show(blast.outer,oname,otiles,if selfHit then BLAST_SELF elseif ok then BLAST_WHITE else BLAST_DEAD,if ok then .05 else .3)
            PFSprites.bind(blast.reticle,"reticle");blast.reticle.Position=at;blast.reticle.Size=UDim2.fromOffset(52,52);blast.reticle.ImageColor3=if ok then BLAST_WHITE else RETICLE_NO;blast.reticle.ImageTransparency=0;blast.reticle.Visible=true
            return
        end
        Icons.bind(self.range,"WeaponsRange"..(if kind=="AtomBomb" then 30 else 100))
        self.range.Visible=true;self.range.Position=UDim2.fromOffset(position.X,position.Y);self.range.Size=UDim2.fromOffset((radius+1)*2*zoom,(radius+1)*2*zoom)
        local cost=query.cost*multiplier;local affordable=self.state.gold[1]>=cost and (kind~="AtomBomb" or (query.readyMissileCount or 0)>=multiplier)
        local color=if not affordable then Color3.new(1,.3,.3) elseif not canPlace then Color3.new(.6,.6,.6) else Color3.new(1,1,1)
        self.cost.Text=formatNumber(cost);self.cost.TextColor3=color;self.cost.Position=UDim2.fromOffset(position.X,position.Y-25);self.cost.Visible=cost>0 and (not self.preferences or self.preferences:get("cursorCostLabel"))
        self.amount.Text="x"..multiplier;self.amount.TextColor3=color;self.amount.Position=UDim2.fromOffset(position.X,position.Y-45);self.amount.Visible=multiplier>1
        return
    end
    self.crosshair.Visible=false
    bindKind(self.ghost,kind)
    self:paint(self.ghost,{owner=1,level=1,underConstruction=false,unitType=kind},zoom,position,.5,tint)
    self.upgrade.ui.Visible=false
    if upgrade then
        for _,city in (if kind=="Port" then self.state.ports or {} elseif kind=="Factory" then self.state.factories or {} elseif kind=="DefensePost" then self.state.defensePosts or {} elseif kind=="MissileSilo" then self.state.missileSilos or {} elseif kind=="SAMLauncher" then self.state.samLaunchers or {} else self.state.cities) do
            if city.id==query.canUpgrade then
                local id=city.tileId-1
                local p=Vector2.new((id%self.state.map.width+.5)*zoom,(math.floor(id/self.state.map.width)+.5)*zoom)
                bindKind(self.upgrade,kind)
                self:paint(self.upgrade,city,zoom,p,.6,Color3.new(0,.8,0));break
            end
        end
    end
    -- The rail reach / defense radius from Config (PixelFront x0.8: 88 / 24); the source ring textures (rendered at 110 /
    -- 30) are sized to it.
    local radius=if kind=="Factory" then Config.Train.StationMaxRange elseif kind=="DefensePost" then Config.DefensePost.Range else 0
    self.range.Visible=radius>0
    if radius>0 then
        Icons.bind(self.range,"IndustryRange"..(if kind=="Factory" then 110 else 30))
        local center=position
        if upgrade then for _,city in self.state.factories or {} do if city.id==query.canUpgrade then local id=city.tileId-1;center=Vector2.new((id%self.state.map.width+.5)*zoom,(math.floor(id/self.state.map.width)+.5)*zoom);break end end end
        self.range.Position=UDim2.fromOffset(center.X,center.Y);self.range.Size=UDim2.fromOffset((radius+1)*2*zoom,(radius+1)*2*zoom)
    end
    self.industry:setGhost(query)
    local cost=if upgrade and query.upgradeCosts then query.upgradeCosts[multiplier] or query.cost else query.cost
    local color=if self.state.gold[1]<cost then Color3.new(1,.3,.3) elseif not canPlace then Color3.new(.6,.6,.6) else Color3.new(1,1,1)
    self.cost.Text=formatNumber(cost);self.cost.TextColor3=color;self.cost.Position=UDim2.fromOffset(position.X,position.Y-25);self.cost.Visible=cost>0 and (not self.preferences or self.preferences:get("cursorCostLabel"))
    self.amount.Text="x"..multiplier;self.amount.TextColor3=color;self.amount.Position=UDim2.fromOffset(position.X,position.Y-45);self.amount.Visible=multiplier>1
end
return Renderer
