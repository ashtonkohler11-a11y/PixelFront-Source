--!strict
-- OpenFront terrain palette + unmodified terrain bytes, composited in Roblox.
-- Ported from ColorUtils.ts and terrain/territory/border shaders at 93a136a.
local AssetService = game:GetService("AssetService")
local Theme = require(game:GetService("ReplicatedStorage").Shared.Theme)
local Performance = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("Performance"))
local NationColors = require(script.Parent.NationColors)
local GraphicsSettings=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local GraphicsPalette=require(script.Parent.GraphicsPalette)
local GraphicsOverlay=require(script.Parent.GraphicsOverlay)
local MapLayers=require(script.Parent.MapLayers)
local UserSettings=require(game:GetService("ReplicatedStorage").Shared.UserSettings)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local DiplomacyPresentation = require(script.Parent.DiplomacyPresentation)
local Config=require(game:GetService("ReplicatedStorage").Shared.Config) -- the defense post coverage radius (DefensePost.Range)
local Renderer = {}
Renderer.__index = Renderer
-- EditableImage supports 1024px; two World images retain all source pixels.
local CHUNK = 1024
local UPLOAD_REGION = 128
local MASK_WIDTH = 32
-- TerritoryPass.ts/render-settings.json: one of nine display buckets per frame.
local DRIP_BUCKET_COUNT = 9
-- Original-design renderer: a large diplomacy/defense/fallout recolor must not
-- monopolize one frame. Logical ownership stays immediate; pixels settle FIFO.
local PAINT_TILES_PER_FRAME = 2048
local PAINT_SECONDS_PER_FRAME = .003
local UPLOAD_CALLS_PER_FRAME = 8
local UPLOAD_BYTES_PER_FRAME = 262144
local UPLOAD_SECONDS_PER_FRAME = .002
-- PF019 M14: animated territory skins repaint their owners' tiles a step at a time, on a
-- budget (a rolling sweep for huge empires); unchanged pixels are not uploaded.
local SKIN_TILES_PER_FRAME = 4096
-- PF020 takeover: skins repaint more tiles per step (and upload them), so the sweep yields at 1 ms.
local SKIN_SECONDS_PER_FRAME = .001

function Renderer.bucketForRef(ref: number): number
    return ((ref*2654435761)%4294967296)%DRIP_BUCKET_COUNT
end

local function rgb(color: Color3): (number, number, number)
    return math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255)
end

local CosmeticCatalog=require(game.ReplicatedStorage.Shared.CosmeticCatalog)
local CosmeticAppearance=require(game.ReplicatedStorage.Shared.CosmeticAppearance)

local function packed(r: number, g: number, b: number): number
    return math.round(r) + math.round(g) * 256 + math.round(b) * 65536 + 4278190080
end

local function terrainColor(value: number): Color3
    local land, shore = bit32.band(value, 128) ~= 0, bit32.band(value, 64) ~= 0
    local m = bit32.band(value, 31)
    if land and m == 31 then return Theme.MapBackground end
    if land and shore then return Theme.Sand end
    if land then
        if m < 10 then
            local r, g, b = rgb(Theme.Land)
            return Color3.fromRGB(r, g - 2 * m, b)
        elseif m < 20 then
            local r, g, b = rgb(Theme.Highland)
            local delta = 2 * (m - 10)
            return Color3.fromRGB(math.min(255, r + delta), math.min(255, g + delta), math.min(255, b + delta))
        else
            local r, g, b = rgb(Theme.Mountain)
            local delta = math.floor(m / 2)
            return Color3.fromRGB(math.min(255, r + delta), math.min(255, g + delta), math.min(255, b + delta))
        end
    end
    local r, g, b = rgb(Theme.Ocean)
    if shore then return Color3.fromRGB(math.round(.7*r+76.5), math.round(.7*g+76.5), math.round(.7*b+76.5)) end
    local depth = math.min(m, 10)
    return Color3.fromRGB(math.max(0,r-depth), math.max(0,g-depth), math.max(0,b-depth))
end

local function borderColor(color: Color3): Color3
    -- colord.darken(.125) changes HSL lightness, not RGB brightness.
    local h, s, v = color:ToHSV()
    local light = v * (1 - s / 2)
    local saturation = if light == 0 or light == 1 then 0 else (v-light)/math.min(light,1-light)
    light = math.max(0, light - .125)
    v = light + saturation * math.min(light, 1-light)
    return Color3.fromHSV(h, if v == 0 then 0 else 2*(1-light/v), v)
end

local baseColors, basePacked = {}, {}
for value = 0, 255 do
    local color = terrainColor(value)
    baseColors[value] = color
    basePacked[value] = packed(rgb(color))
end
-- PF020 skins full takeover: a skinned owner's whole territory palette (fill, hover, defended,
-- every border) comes from the skin's own colours (CosmeticAppearance.skinPalettes); the owner
-- colour is ignored. Shared by every owner wearing that skin.
local function buildTakeoverPalette(skin: any,settings: any,terrain: any): any
    local base,light=Color3.fromHex(skin.base),Color3.fromHex(skin.light or skin.hoverBorder)
    local border,hoverBorder=Color3.fromHex(skin.border),Color3.fromHex(skin.hoverBorder)
    local result: any={fill={},hoverFill={},defenseFill={},defenseHoverFill={},takeoverBase=base,takeoverLight=light}
    for _,relation in {"","Friendly","Embargo"}do
        for _,hover in {false,true}do for _,checker in {false,true}do
            local key=relation..(if checker then "Defense"else "")..(if hover then "Hover"else "").."Border"
            if relation==""and not checker then key=if hover then "hoverBorder"else "border"
            elseif relation==""then key=if hover then "defenseHoverBorder"else "defenseBorder"end
            result[key]=GraphicsMath.word(GraphicsMath.border(if hover then hoverBorder else border,settings,false,checker,relation))
        end end
    end
    local darken=settings.mapOverlay.territoryDefenseDarken
    for value=0,255 do
        local fill=terrain[value]:Lerp(base,CosmeticAppearance.TAKEOVER_ALPHA);local hover=fill:Lerp(light,.14)
        result.fill[value]=GraphicsMath.word(fill);result.hoverFill[value]=GraphicsMath.word(hover)
        result.defenseFill[value]=GraphicsMath.word(Color3.new(fill.R*darken,fill.G*darken,fill.B*darken))
        result.defenseHoverFill[value]=GraphicsMath.word(Color3.new(hover.R*darken,hover.G*darken,hover.B*darken))
    end
    return result
end
local function buildPalette(owner: number, color: Color3,settings: any?,terrain: any?,paletteData: any?)
    settings=settings or GraphicsSettings.resolve();terrain=terrain or baseColors
    if paletteData then
        local hex="#"..color:ToHex():lower()
        local border=if owner==1 then Color3.fromHex(settings.theme.focusedBorderColor)else Color3.fromHex(assert(paletteData.borders[hex],"Missing source border color"))
        local result: any={fill={},hoverFill={},defenseFill={},defenseHoverFill={}}
        for _,relation in {"","Friendly","Embargo"}do
            for _,hover in {false,true}do for _,checker in {false,true}do
                local key=relation..(if checker then "Defense"else "")..(if hover then "Hover"else "").."Border"
                if relation==""and not checker then key=if hover then "hoverBorder"else "border"
                elseif relation==""then key=if hover then "defenseHoverBorder"else "defenseBorder"end
                result[key]=GraphicsMath.word(GraphicsMath.border(border,settings,hover,checker,relation))
            end end
        end
        for value=0,255 do for _,hover in {false,true}do for _,defended in {false,true}do
            local target=if hover then (if defended then result.defenseHoverFill else result.hoverFill)else (if defended then result.defenseFill else result.fill)
            target[value]=GraphicsMath.word(GraphicsMath.fill(color,terrain[value],settings,hover,defended))
        end end end
        return result
    end
    -- PlayerView.borderColor gives the local player the focused border color.
    local border = if owner == 1 then Color3.fromHex("#e6e6e6") else borderColor(color)
    border = Color3.fromRGB(rgb(border))
    local hoverBorder=border:Lerp(Color3.new(1,1,1),.25)
    local result = { border=packed(rgb(border)), hoverBorder=packed(rgb(hoverBorder)),
        defenseBorder=packed(rgb(Color3.new(border.R*.7,border.G*.7,border.B*.7))),
        defenseHoverBorder=packed(rgb(Color3.new(hoverBorder.R*.7,hoverBorder.G*.7,hoverBorder.B*.7))),
        fill={}, hoverFill={}, defenseFill={},defenseHoverFill={} }
    for _,relation in {"Friendly","Embargo"} do
        local tint=DiplomacyPresentation.tint(border,relation=="Embargo",relation=="Friendly")
        local hoverTint=tint:Lerp(Color3.new(1,1,1),.25)
        result[relation.."Border"]=packed(rgb(tint));result[relation.."HoverBorder"]=packed(rgb(hoverTint))
        result[relation.."DefenseBorder"]=packed(rgb(Color3.new(tint.R*.7,tint.G*.7,tint.B*.7)))
        result[relation.."DefenseHoverBorder"]=packed(rgb(Color3.new(hoverTint.R*.7,hoverTint.G*.7,hoverTint.B*.7)))
    end
    for hover = 0, 1 do
        local r, g, b = color.R, color.G, color.B
        if hover == 1 then
            r, g, b = math.clamp((r-.5)*1.15+.5,0,1), math.clamp((g-.5)*1.15+.5,0,1), math.clamp((b-.5)*1.15+.5,0,1)
        end
        local luminance = .299*r + .587*g + .114*b
        local fill = Color3.new(luminance+(r-luminance)*.85,luminance+(g-luminance)*.85,luminance+(b-luminance)*.85)
        for value = 0, 255 do
            local composite = baseColors[value]:Lerp(fill, .588)
            local palette = if hover == 1 then result.hoverFill else result.fill
            palette[value] = packed(rgb(composite))
            -- Territory shader darkens the owner fill BEFORE saturation/alpha.
            local defended=baseColors[value]:Lerp(Color3.new(fill.R*.85,fill.G*.85,fill.B*.85),.588)
            local defensePalette=if hover==1 then result.defenseHoverFill else result.defenseFill
            defensePalette[value]=packed(rgb(defended))
        end
    end
    return result
end

function Renderer:setDiplomacy(state: any)
    self.diplomacyState=state
    -- Decoded tables may mutate in place; retain pairs only until the next
    -- state update, including when alliance/embargo/team inputs change.
    self.borderRelationships={}
    local previous=self.relationSignatures or {};local signatures={};local changed={}
    for _,owner in state.playerOrder or {} do
        local data=state.diplomacy and state.diplomacy[owner]
        local parts={}
        if data then
            for _,id in data.allianceIds do table.insert(parts,"a"..id) end
            for _,id in data.embargoOrder do table.insert(parts,"e"..id) end
        end
        local signature=table.concat(parts,",");signatures[owner]=signature
        if previous[owner]~=signature and (previous[owner]~=nil or signature~="") then changed[owner]=true end
    end
    self.relationSignatures=signatures
    for owner in changed do
        -- Relationship tints affect cardinal borders only in the normal view.
        -- A late alliance previously repainted every tile in a huge empire.
        local affected=if self.altView then self.owned[owner] else self.borderTiles[owner]
        for id in affected or {} do
            self.defenseDirty[id]=true
            local width=self.map.width;local x=(id-1)%width
            if x>0 then self.defenseDirty[id-1]=true end;if x<width-1 then self.defenseDirty[id+1]=true end
            if id>width then self.defenseDirty[id-width]=true end;if id<=width*(self.map.height-1) then self.defenseDirty[id+width]=true end
        end
    end
    -- Alternate-view affiliation is relative to the viewer, including owners
    -- whose own recorded diplomacy signature did not change.
    if self.altView and changed[1] then self:dirtyAll() end
end

local botPalette=buildPalette(0,Theme.Bot)
local defaultPalettes={ [1]=buildPalette(1,Theme.Player),[2]=botPalette }

function Renderer.new(parent: Frame)
    local buckets={}
    for i=1,DRIP_BUCKET_COUNT do buckets[i]={} end
    return setmetatable({ parent=parent, chunks={}, dirty={}, map=nil, owners=nil, owned={}, ownerIndex={},
        displayOwners=nil,displayOwned={},displayMasks={},dripBuckets=buckets,bucketStarted={},currentBucket=1,pendingTileCount=0,
        uploadBuffers={},uploadBufferKeys={},uploadBufferCursor=1,uploadChunkCursor=1,
        paletteIds={}, palettes=table.clone(defaultPalettes), colors={}, nationAllocator=NationColors.new(), highlighted=0,
        defensePosts={},defenseCoverage={},defenseDirty={},fallout={},falloutBuckets={},falloutHeat={},falloutTicks=nil,borderCache={},borderTiles={},borderTileOwners={},
        paintQueue={},paintQueued={},paintHead=1,paintTail=0,falloutVersion=0,displayVersion=0,falloutDisplayVersion=0,
        graphics=GraphicsSettings.resolve(),graphicsOverrides={},baseColors=baseColors,basePacked=basePacked,altView=false,gridView=false,
        skinPhase={},skinFields={},skinSweeps={},skinSweepOrder={},skinSwept={},skinMotionCheck=-math.huge,skinReduced=false }, Renderer)
end

function Renderer:dirtyAll()
    if not self.map or not self.displayOwners then return end
    -- Feed a complete palette/alternate-view repaint over successive frames,
    -- rather than allocating a million-entry dirty table in the input handler.
    self.fullPaintCursor=1
end
function Renderer:setGraphics(settings: any,overrides: any?,preferences: any?)
    self.graphicsConfigured=true
    self.graphics=settings;self.graphicsOverrides=overrides or {};self.preferences=preferences
    self.baseColors={};self.basePacked={}
    for value=0,255 do local c=GraphicsMath.terrain(value,settings);self.baseColors[value]=c;self.basePacked[value]=GraphicsMath.word(c)end
    -- Source ThemeProvider keeps separate allocation pools for both palettes;
    -- switching away and back reuses its existing assignments for this match.
    self.graphicsPalettes=self.graphicsPalettes or {}
    local name=self.graphicsOverrides.palette or "default"
    -- PF019 W7: tribes are always the flat Bot colour; an old stored classicBotColors is ignored here
    -- too (Ashton 2026-10-07: tribes showed multicoloured from a pre-W7 save).
    self.graphicsPalettes[name]=self.graphicsPalettes[name] or GraphicsPalette.new(name,false)
    self.graphicsPalette=self.graphicsPalettes[name];self.graphicsPalette.classic=false
    self.graphicsPalette:setTeamColors(self.teamColorHexes) -- PF020 G8 Host+ team colours
    self.paletteIds={};self.takeoverPalettes={}
    self:setPlayers(self.players,self.playerOrder)
    if self.mapLayers then UserSettings.pushMapLayerState(self.graphicsOverrides,self.map.manifest and self.map.manifest.layers or {},function(id,visible)self.mapLayers:setVisible(id,visible)end,function(id,alpha)self.mapLayers:setAlpha(id,alpha)end)end
    self:dirtyAll();self.gridDirty=true;self.lightDirty=true
end
function Renderer:setAltView(active: boolean)
    if self.altView==active then return end
    self.altView=active;self:dirtyAll();self.gridDirty=true;self.lightDirty=true
end
function Renderer:setTerrainView(active: boolean)self:setAltView(active)end
function Renderer:setGridView(active: boolean)self.gridView=active;self.gridDirty=true end
function Renderer:setCoordinateGrid(active: boolean)self:setGridView(active)end
function Renderer:updateTerrain(changed: {number}?)
    if changed==nil then self:dirtyAll()else for _,id in changed do self.defenseDirty[id]=true end end
    self.lightDirty=true
end

-- PF020 G8: Lobby Host+ team colours from the match config (nil = the source palette).
function Renderer:setTeamColors(hexes: {string}?)
    local key=if hexes then table.concat(hexes,",") else ""
    if self.teamColorKey==key then return end
    self.teamColorKey=key;self.teamColorHexes=hexes
    for _,palette in self.graphicsPalettes or {} do palette:setTeamColors(hexes) end
    self.paletteIds={}
    if self.players then self:setPlayers(self.players,self.playerOrder);self:dirtyAll() end
end
-- PF028 (Ashton: "your skin is your color, you shouldnt spawn white warships when ur storm"): in FFA (no team) a player
-- showing a skin with a unit colour takes that colour as its owner colour, the one every unit, structure and swatch
-- reads (renderer.colors). Classic / unskinned / team modes / "Show cosmetics" filtered keep the owner colour.
function Renderer.ownerColor(base: Color3, player: any, skin: any?): Color3
    if player and player.team==nil and type(skin)=="table" and type(skin.unit)=="string" then
        local ok,color=pcall(Color3.fromHex,skin.unit)
        if ok then return color end
    end
    return base
end
-- The skin palette this owner shows (nil: Classic, no skin, or filtered out by "Show cosmetics from").
function Renderer:skinFor(owner: number): any?
    local look=self.cosmeticLooks and self.cosmeticLooks[owner]
    local item=look and look.Skin and CosmeticCatalog.byId[look.Skin]
    return item and CosmeticAppearance.skinPalettes[item.pattern]
end
function Renderer:setPlayers(players: {[number]: any}?, order: {number}?)
    if not players then return end
    self.players,self.playerOrder=players,order
    for _, owner in order or {1,2} do
        local player = players[owner]
        if not player then continue end
        local takeover=self:takeoverPalette(owner)
        local skin=self:skinFor(owner)
        local identity=player.id..":"..tostring(player.team)..":"..tostring(takeover and takeover.pattern)..":"..tostring(skin and skin.unit)
        if self.paletteIds[owner] == identity then continue end
        self.paletteIds[owner] = identity
        if self.graphicsPalette then
            self.colors[owner]=self.graphicsPalette:assign(player)
            self.palettes[owner]=buildPalette(owner,self.colors[owner],self.graphics,self.baseColors,self.graphicsPalette.data)
        elseif player.playerType == "Bot" then
            self.colors[owner] = Theme.Bot
            self.palettes[owner] = botPalette
        elseif player.playerType == "Human" then
            self.colors[owner] = Theme.playerColor(player.id)
            self.palettes[owner] = buildPalette(owner, self.colors[owner])
        else
            self.colors[owner] = self.nationAllocator:assign(player.id)
            self.palettes[owner] = buildPalette(owner, self.colors[owner])
        end
        if takeover then self.palettes[owner]=takeover.palette end
        self.colors[owner]=Renderer.ownerColor(self.colors[owner],player,skin) -- PF028: after the palette, which the takeover replaces
    end
end
-- The takeover palette for this owner's equipped skin (nil for Classic / no skin / alt view data).
function Renderer:takeoverPalette(owner: number): any?
    local look=self.cosmeticLooks and self.cosmeticLooks[owner]
    local item=look and look.Skin and CosmeticCatalog.byId[look.Skin]
    local skin=item and CosmeticAppearance.skinPalettes[item.pattern]
    if not skin or not self.graphics or not self.baseColors or not self.baseColors[0] then return nil end
    self.takeoverPalettes=self.takeoverPalettes or {}
    local cached=self.takeoverPalettes[item.pattern]
    if not cached then
        cached={pattern=item.pattern,palette=buildTakeoverPalette(skin,self.graphics,self.baseColors)}
        self.takeoverPalettes[item.pattern]=cached
    end
    return cached
end

function Renderer:destroy()
    if self.graphicsOverlay then self.graphicsOverlay:destroy();self.graphicsOverlay=nil end
    for _, chunk in self.chunks do chunk.label:Destroy(); chunk.image:Destroy() end
    self.chunks = {}
    table.clear(self.dirty)
    self.owners = nil
    self.owned = {}
    self.ownerIndex = {}
    self.displayOwners=nil;self.displayOwned={};self.displayMasks={}
    for _,bucket in self.dripBuckets do table.clear(bucket) end
    self.currentBucket=1;self.pendingTileCount=0
    table.clear(self.bucketStarted)
    table.clear(self.uploadBuffers);table.clear(self.uploadBufferKeys);self.uploadBufferCursor=1;self.uploadChunkCursor=1
    self.paletteIds, self.colors, self.nationAllocator = {}, {}, NationColors.new()
    self.palettes=table.clone(defaultPalettes)
    self.defensePosts={};self.defenseCoverage={};self.defenseDirty={}
    self.fallout={};self.falloutBuckets={};self.falloutHeat={};self.falloutTicks=nil
    self.borderCache={}
    self.borderTiles={};self.borderTileOwners={}
    self.paintQueue={};self.paintQueued={};self.paintHead=1;self.paintTail=0
    self.fullPaintCursor=nil
    self.falloutVersion=0;self.displayVersion=0;self.falloutDisplayVersion=0
    self.diplomacyState=nil;self.relationSignatures={};self.borderRelationships={}
    self.mapLayers=nil
    self.graphicsPalettes={};self.graphicsPalette=nil;self.players=nil;self.playerOrder=nil;self.teamColorKey=nil;self.teamColorHexes=nil
    if self.gridParent then self.gridParent:Destroy();self.gridParent=nil end
    if self.glow then self.glow.label:Destroy();self.glow.image:Destroy();self.glow=nil end
    if self.nightChunks then for _,chunk in self.nightChunks do chunk.label:Destroy();chunk.image:Destroy()end;self.nightChunks=nil end
end

function Renderer:updateFallout(tiles: {[number]: boolean}?,changed: {number}?,tick: number)
    self.falloutVersion+=1
    local previousTick=self.falloutTicks
    if previousTick then local decay=math.max(0,tick-previousTick)*self.graphics.falloutBloom.heatDecayPerTick;if decay>0 then for id,value in self.falloutHeat do local nextValue=math.round(math.max(0,value-decay));self.falloutHeat[id]=if nextValue>0 then nextValue else nil end end end
    self.falloutTicks=tick
    if changed==nil then
        local dirty={};for id in self.fallout do dirty[id]=true end;for id in tiles or {} do dirty[id]=true end
        local old=self.fallout;self.fallout=table.clone(tiles or {});self.falloutBuckets={}
        -- HeatManager's first tile-state copy deliberately does not stamp heat;
        -- subsequent full replacements preserve unchanged heat transitions.
        for id in dirty do if old[id]~=self.fallout[id] then self.falloutHeat[id]=if previousTick and self.fallout[id] then 255 else nil end end
        for id in dirty do self.defenseDirty[id]=true end
        return
    end
    for _,id in changed do local index=Renderer.bucketForRef(id-1)+1;local bucket=self.falloutBuckets[index];if not bucket then bucket={};self.falloutBuckets[index]=bucket end;table.insert(bucket,{id=id,value=tiles and tiles[id]==true}) end
end

function Renderer:setDefensePosts(posts: {any}?)
    if not self.map then return end
    local nextPosts={}
    for _,post in posts or {} do
        if post.active~=false and not post.underConstruction then nextPosts[post.id]={tileId=post.tileId,owner=post.owner} end
    end
    local function stamp(post: any,delta: number)
        local width,height=self.map.width,self.map.height
        local x,y=(post.tileId-1)%width,math.floor((post.tileId-1)/width)
        local coverage=self.defenseCoverage[post.owner]
        if not coverage then coverage={};self.defenseCoverage[post.owner]=coverage end
        -- the coverage disc = the defense bonus (OpenFrontStructures: distance² <= DefensePost.Range², 24 since the x0.8 pass)
        local range=Config.DefensePost.Range
        for dy=-range,range do
            local yy=y+dy;if yy<0 or yy>=height then continue end
            local extent=math.floor(math.sqrt(range*range-dy*dy))
            for xx=math.max(0,x-extent),math.min(width-1,x+extent) do
                local id=yy*width+xx+1;local count=(coverage[id] or 0)+delta
                coverage[id]=if count>0 then count else nil
                self.defenseDirty[id]=true
            end
        end
    end
    for id,post in self.defensePosts do
        local nextPost=nextPosts[id]
        if not nextPost or nextPost.tileId~=post.tileId or nextPost.owner~=post.owner then stamp(post,-1) end
    end
    for id,post in nextPosts do
        local previous=self.defensePosts[id]
        if not previous or previous.tileId~=post.tileId or previous.owner~=post.owner then stamp(post,1) end
    end
    self.defensePosts=nextPosts
end

function Renderer:setMap(map: any)
    self:destroy()
    if self.graphicsConfigured then self:setGraphics(self.graphics,self.graphicsOverrides,self.preferences)end
    self.map = map
    self.skinFields={};table.clear(self.skinSweeps);table.clear(self.skinSweepOrder);table.clear(self.skinSwept)
    self.mapLayers=MapLayers.load(map)
    UserSettings.pushMapLayerState(self.graphicsOverrides,map.manifest and map.manifest.layers or {},function(id,visible)self.mapLayers:setVisible(id,visible)end,function(id,alpha)self.mapLayers:setAlpha(id,alpha)end)
    self.columns = math.ceil(map.width / CHUNK)
    for y = 0, map.height - 1, CHUNK do
        for x = 0, map.width - 1, CHUNK do
            local width, height = math.min(CHUNK,map.width-x), math.min(CHUNK,map.height-y)
            local pixels = buffer.create(width*height*4)
            for yy = 0, height - 1 do
                for xx = 0, width - 1 do
                    local value = buffer.readu8(map.terrain, (y+yy)*map.width+x+xx)
                    local c=self.mapLayers:composite(if self.graphics.passEnabled.terrain then self.baseColors[value]else Color3.fromHex(self.graphics.terrain.backgroundColor),x+xx,y+yy,value)
                    buffer.writeu32(pixels,(yy*width+xx)*4,GraphicsMath.word(c))
                end
            end
            local ok, image = pcall(function()
                return AssetService:CreateEditableImage({Size=Vector2.new(width,height)})
            end)
            if not ok or not image then
                self:destroy()
                error(if ok then "Roblox editable-image budget could not fit the official map" else tostring(image))
            end
            image:WritePixelsBuffer(Vector2.zero,Vector2.new(width,height),pixels)
            local label = Instance.new("ImageLabel")
            label.Name = string.format("Map_%d_%d",x,y)
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Position = UDim2.fromScale(x/map.width,y/map.height)
            label.Size = UDim2.fromScale(width/map.width,height/map.height)
            label.ResampleMode = Enum.ResamplerMode.Pixelated
            label.ImageContent = Content.fromObject(image)
            label.Parent = self.parent
            -- These are CPU buffers, not additional EditableImages. Maintain both
            -- exact shader results as territory changes, so hover does no tile scan.
            local normalPixels,hoverPixels=buffer.create(width*height*4),buffer.create(width*height*4)
            buffer.copy(normalPixels,0,pixels);buffer.copy(hoverPixels,0,pixels)
            table.insert(self.chunks,{image=image,label=label,pixels=pixels,normalPixels=normalPixels,hoverPixels=hoverPixels,
                x=x,y=y,width=width,height=height,maskColumns=math.ceil(width/MASK_WIDTH),
                regionColumns=math.ceil(width/UPLOAD_REGION),regions={},dirtyRegions={},deferredRegions={}})
        end
    end
end

local function markDirty(chunk: any,xx: number,yy: number,endX: number)
    -- A32px mask fits inside one128px upload region and one1024px image.
    local regionId=math.floor(yy/UPLOAD_REGION)*chunk.regionColumns+math.floor(xx/UPLOAD_REGION)+1
    local region=chunk.regions[regionId]
    if not region then region={};chunk.regions[regionId]=region end
    if not region.minX then
        region.minX,region.maxX,region.minY,region.maxY=xx,endX,yy,yy
        table.insert(chunk.dirtyRegions,regionId)
    else
        region.minX,region.maxX=math.min(region.minX,xx),math.max(region.maxX,endX)
        region.minY,region.maxY=math.min(region.minY,yy),math.max(region.maxY,yy)
    end
end

function Renderer:updateDisplayMask(id: number,previous: number,owner: number)
    local w=self.map.width
    local x,y=(id-1)%w,math.floor((id-1)/w)
    local index=math.floor(y/CHUNK)*self.columns+math.floor(x/CHUNK)+1
    local chunk=self.chunks[index]
    local xx,yy=x-chunk.x,y-chunk.y
    local key=yy*chunk.maskColumns+math.floor(xx/MASK_WIDTH)+1
    local bit=bit32.lshift(1,xx%MASK_WIDTH)
    if previous>0 then
        local playerMasks=self.displayMasks[previous]
        local masks=playerMasks and playerMasks[index]
        if masks then
            local remaining=bit32.band(masks[key] or 0,bit32.bnot(bit))
            masks[key]=if remaining~=0 then remaining else nil
        end
    end
    if owner>0 then
        local playerMasks=self.displayMasks[owner]
        if not playerMasks then playerMasks={};self.displayMasks[owner]=playerMasks end
        local masks=playerMasks[index]
        if not masks then masks={};playerMasks[index]=masks end
        masks[key]=bit32.bor(masks[key] or 0,bit)
    end
end

local function borderFlags(owners: {number},w: number,h: number,x: number,y: number,radius: number): (boolean,boolean)
    if math.floor(radius)~=1 then return GraphicsMath.borderFlags(owners,w,h,x,y,radius)end
    local id=y*w+x+1;local owner=owners[id]
    if x==0 or y==0 or x==w-1 or y==h-1 then return true,true end
    if owners[id-w]~=owner or owners[id+w]~=owner or owners[id-1]~=owner or owners[id+1]~=owner then return true,true end
    return false,owners[id-w-1]~=owner or owners[id-w+1]~=owner or owners[id+w-1]~=owner or owners[id+w+1]~=owner
end

-- PF028: a skinned territory's rim, the tile just inside its seam: an interior tile (its four neighbours its own, which
-- the caller has checked) with a cardinal neighbour that is itself a seam tile. Two same-skin neighbours then meet at
-- seam, rim, seam, rim (CosmeticAppearance.rimWord).
local function skinRim(owners: {number},w: number,h: number,x: number,y: number): boolean
    local owner=owners[y*w+x+1]
    for direction=1,4 do
        local nx,ny=x,y
        if direction==1 then nx-=1 elseif direction==2 then nx+=1 elseif direction==3 then ny-=1 else ny+=1 end
        if nx<=0 or ny<=0 or nx>=w-1 or ny>=h-1 then return true end
        local n=ny*w+nx+1
        if owners[n-1]~=owner or owners[n+1]~=owner or owners[n-w]~=owner or owners[n+w]~=owner then return true end
    end
    return false
end
-- PF028: a skinned tile's finish after its pattern: the rim lit, a defense post's area darkened (pattern kept).
local function skinFinish(word: number,pattern: string,rim: boolean,dark: number?): number
    if rim then word=CosmeticAppearance.rimWord(word,pattern) end
    if dark then word=CosmeticAppearance.scaleWord(word,dark) end
    return word
end
local RIM_RING={{2,0},{-2,0},{0,2},{0,-2},{1,1},{1,-1},{-1,1},{-1,-1}}

local function borderRelation(renderer: any,owners: {number},w: number,h: number,x: number,y: number): string
    local id=y*w+x+1;local owner=owners[id];local friendly=false
    renderer.borderRelationships=renderer.borderRelationships or {}
    local pairs=renderer.borderRelationships[owner]
    if not pairs then pairs={};renderer.borderRelationships[owner]=pairs end
    for direction=1,4 do
        local adjacent
        if direction==1 then if y==0 then continue end;adjacent=id-w
        elseif direction==2 then if y==h-1 then continue end;adjacent=id+w
        elseif direction==3 then if x==0 then continue end;adjacent=id-1
        else if x==w-1 then continue end;adjacent=id+1 end
        local other=owners[adjacent]
        if other==0 or other==owner then continue end
        local relation=pairs[other]
        if relation==nil then
            local ally,embargo=GraphicsMath.relationship(renderer.diplomacyState,owner,other)
            relation=if embargo then 2 elseif ally then 1 else 0
            pairs[other]=relation
        end
        if relation==2 then return "Embargo"end
        friendly=friendly or relation==1
    end
    return if friendly then "Friendly"else ""
end

function Renderer:setCosmetics(looks: any)
    local prior=self.cosmeticLooks or {};self.cosmeticLooks=looks
    -- PF028: the owners wearing a skin (their rim moves with a transfer up to two tiles away; see drainBucket)
    self.skinRims={}
    for owner,look in looks do
        local item=look and look.Skin and CosmeticCatalog.byId[look.Skin]
        if item and CosmeticAppearance.skinPalettes[item.pattern] then self.skinRims[owner]=true end
    end
    -- PF020 takeover: a changed skin swaps the owner's whole palette (setPlayers rebuilds it).
    local repalette=false
    for owner in self.paletteIds or {} do
        local old,new=prior[owner],looks[owner]
        if (old and old.Skin)~=(new and new.Skin) then self.paletteIds[owner]=nil;repalette=true end
    end
    if repalette and self.players then self:setPlayers(self.players,self.playerOrder) end
    for owner,tiles in self.displayOwned do
        local old,new=prior[owner],looks[owner]
        if (old and old.Skin)~=(new and new.Skin) then
            -- PF019 M14: queue the repaint itself (advance() clears self.dirty before queuing it),
            -- and forget the last sweep so a held (reduced-motion) skin is swept in again.
            self.skinSwept[owner]=nil
            -- PF020: and drop a sweep in progress, or its commit would copy the old skin's planes
            -- back over the repainted territory
            if self.skinSweeps[owner] then
                self.skinSweeps[owner]=nil
                local at=table.find(self.skinSweepOrder,owner);if at then table.remove(self.skinSweepOrder,at) end
            end
            for id in tiles do
                if not self.paintQueued[id] then self.paintTail+=1;self.paintQueue[self.paintTail]=id;self.paintQueued[id]=true end
            end
        end
    end
end

function Renderer:paint(id: number)
    local map, owners = self.map, self.displayOwners
    local x, y = (id-1)%map.width, math.floor((id-1)/map.width)
    local owner = owners[id]
    local value = buffer.readu8(map.terrain,id-1)
    local passes=self.graphics.passEnabled
    local terrain,normalColor
    if passes.terrain and #self.mapLayers.records==0 then
        -- These colors are already source-quantized when graphics settings
        -- build the256-entry terrain palette. No per-tile conversion is needed.
        terrain,normalColor=self.baseColors[value],self.basePacked[value]
    else
        local base=if passes.terrain then self.baseColors[value]else Color3.fromHex(self.graphics.terrain.backgroundColor)
        terrain=GraphicsMath.color(GraphicsMath.word(self.mapLayers:composite(base,x,y,value)))
        normalColor=GraphicsMath.word(terrain)
    end
    local hoverColor=normalColor
    local planeNormal: number?,planeHover: number?=nil,nil -- PF020: a skin sweep's step for the planes
    if owner > 0 then
        local cached=self.borderCache[id]
        if passes.borderCompute then
            local normal,hover=borderFlags(owners,map.width,map.height,x,y,self.graphics.mapOverlay.highlightThicken)
            if normal or hover then
                cached=cached or {};cached[1],cached[2]=normal,hover
                cached.relation=if normal then borderRelation(self,owners,map.width,map.height,x,y)else ""
                cached.highlighted=owner==self.highlighted
            else
                -- Broad interiors need neither border data nor a per-tile Lua
                -- table. Retaining hundreds of thousands caused avoidable GC.
                cached=nil
            end
            self.borderCache[id]=cached
        end
        local border,hoverBorder=passes.borderStamp and cached~=nil and cached[1],passes.borderStamp and cached~=nil and cached[2]
        if not passes.borderCompute and cached then local held=passes.borderStamp and (if cached.highlighted then cached[2]else cached[1]);border,hoverBorder=held,held end
        local palette=self.palettes[owner]
        local coverage=self.defenseCoverage[owner]
        local defended=coverage~=nil and coverage[id]~=nil
        local checker=defended and (x+y)%2==1
        local relation=if cached then cached.relation or ""else ""
        local borderPixel=if relation~="" then palette[relation..(if checker then "DefenseBorder" else "Border")] else (if checker then palette.defenseBorder else palette.border)
        local hoverBorderPixel=if relation~="" then palette[relation..(if checker then "DefenseHoverBorder" else "HoverBorder")] else (if checker then palette.defenseHoverBorder else palette.hoverBorder)
        if not passes.borderCompute and cached then if cached.highlighted then borderPixel=hoverBorderPixel else hoverBorderPixel=borderPixel end end
        local look=self.cosmeticLooks and self.cosmeticLooks[owner]
        local skin=look and CosmeticCatalog.byId[look.Skin]
        -- Ashton (2026-10-08): a defense post must not cut a hole in a skin. PF028 (the approved skins board): a skinned
        -- owner's defended area keeps the pattern and its animation, the whole area darkened by SKIN_DEFENSE_DARKEN after
        -- the pattern (below), its seam checkered like any defended border.
        local skinned=skin~=nil and skin.pattern~="none" and not self.altView
        local shaded=if skinned then false else defended
        normalColor=if border then borderPixel elseif not passes.territory then normalColor elseif shaded then palette.defenseFill[value] else palette.fill[value]
        hoverColor=if hoverBorder then hoverBorderPixel elseif not passes.territory then hoverColor elseif shaded then palette.defenseHoverFill[value] else palette.hoverFill[value]
        if terrain~=self.baseColors[value]then
            local base=palette.takeoverBase
            if base then
                -- PF020 takeover: the skin's base, never the owner colour, over a layered terrain.
                local fill=terrain:Lerp(base,CosmeticAppearance.TAKEOVER_ALPHA);local hover=fill:Lerp(palette.takeoverLight,.14)
                if shaded then local k=self.graphics.mapOverlay.territoryDefenseDarken;fill=Color3.new(fill.R*k,fill.G*k,fill.B*k);hover=Color3.new(hover.R*k,hover.G*k,hover.B*k) end
                if not border and passes.territory then normalColor=GraphicsMath.word(fill) end
                if not hoverBorder and passes.territory then hoverColor=GraphicsMath.word(hover) end
            else
                if not border and passes.territory then normalColor=GraphicsMath.word(GraphicsMath.fill(self.colors[owner],terrain,self.graphics,false,defended))end
                if not hoverBorder and passes.territory then hoverColor=GraphicsMath.word(GraphicsMath.fill(self.colors[owner],terrain,self.graphics,true,defended))end
            end
        end
        if skinned and passes.territory and not self.fallout[id] then
            local pattern=skin.pattern
            -- the step this owner's territory is showing (its last committed sweep), so a tile
            -- repainted mid-sweep (won, border change) matches its neighbours
            local phase,field=self.skinSwept[owner] or self.skinPhase[pattern] or 0,self:skinField(pattern,id,x,y)
            -- ...and, while a sweep paints the next step, the planes take that step, so the commit
            -- (copyOwnerPlane) never brings back an older step on a tile repainted behind the sweep
            local sweep=self.skinSweeps[owner]
            -- PF028: the rim (the tile just inside the seam) and a defense post's darkened area, after the pattern
            local rim=passes.borderStamp and not border and skinRim(owners,map.width,map.height,x,y)
            local hoverRim=rim and not hoverBorder
            local dark=if defended then CosmeticAppearance.SKIN_DEFENSE_DARKEN else nil
            if sweep and sweep.phase~=phase then
                planeNormal=if border then normalColor else skinFinish(CosmeticAppearance.patternWord(normalColor,pattern,x,y,sweep.phase,field),pattern,rim,dark)
                planeHover=if hoverBorder then hoverColor else skinFinish(CosmeticAppearance.patternWord(hoverColor,pattern,x,y,sweep.phase,field),pattern,hoverRim,dark)
            end
            if not border then normalColor=skinFinish(CosmeticAppearance.patternWord(normalColor,pattern,x,y,phase,field),pattern,rim,dark) end
            if not hoverBorder then hoverColor=skinFinish(CosmeticAppearance.patternWord(hoverColor,pattern,x,y,phase,field),pattern,hoverRim,dark) end
        end
        if self.altView then
            local state=self.diplomacyState
            local friendly,embargo=GraphicsMath.relationship(state,1,owner)
            local affiliation=GraphicsMath.affiliation(self.graphics,owner==1,friendly,embargo)
            normalColor=GraphicsMath.word(if border then affiliation elseif passes.territory then GraphicsMath.fill(self.colors[owner],terrain,self.graphics,false,false,affiliation)else terrain)
            hoverColor=GraphicsMath.word(if hoverBorder then affiliation elseif passes.territory then GraphicsMath.fill(self.colors[owner],terrain,self.graphics,false,false,affiliation)else terrain)
        end
        if passes.territory and self.fallout[id] and not border then
            normalColor=GraphicsMath.word(terrain:Lerp(GraphicsMath.staleNuke(x,y,self.graphics),self.graphics.mapOverlay.staleNukeAlpha))
        end
        if passes.territory and self.fallout[id] and not hoverBorder then hoverColor=normalColor end
    elseif passes.territory and self.fallout[id] then
        normalColor=GraphicsMath.word(terrain:Lerp(GraphicsMath.staleNuke(x,y,self.graphics),self.graphics.mapOverlay.staleNukeAlpha));hoverColor=normalColor
    end
    local previousBorderOwner=self.borderTileOwners[id]
    local cachedBorder=self.borderCache[id]
    local borderOwner=if owner>0 and cachedBorder and (cachedBorder[1] or cachedBorder[2]) then owner else nil
    if previousBorderOwner~=borderOwner then
        if previousBorderOwner then self.borderTiles[previousBorderOwner][id]=nil end
        if borderOwner then
            local borders=self.borderTiles[borderOwner]
            if not borders then borders={};self.borderTiles[borderOwner]=borders end
            borders[id]=true
        end
        self.borderTileOwners[id]=borderOwner
    end
    self:writeTile(x,y,owner,normalColor,hoverColor)
    if planeNormal then self:writePlanes(x,y,planeNormal,planeHover :: number) end
end

-- PF020: the normal/hover planes only; the shown pixels wait for copyOwnerPlane (a skin sweep's commit).
function Renderer:writePlanes(x: number,y: number,normalColor: number,hoverColor: number)
    local chunk=self.chunks[math.floor(y/CHUNK)*self.columns+math.floor(x/CHUNK)+1]
    local offset=((y-chunk.y)*chunk.width+(x-chunk.x))*4
    buffer.writeu32(chunk.normalPixels,offset,normalColor)
    buffer.writeu32(chunk.hoverPixels,offset,hoverColor)
end
function Renderer:writeTile(x: number,y: number,owner: number,normalColor: number,hoverColor: number)
    local index = math.floor(y/CHUNK)*self.columns+math.floor(x/CHUNK)+1
    local chunk = self.chunks[index]
    local xx, yy = x-chunk.x, y-chunk.y
    local offset=(yy*chunk.width+xx)*4
    buffer.writeu32(chunk.normalPixels,offset,normalColor)
    buffer.writeu32(chunk.hoverPixels,offset,hoverColor)
    local color=if owner==self.highlighted then hoverColor else normalColor
    if buffer.readu32(chunk.pixels,offset)==color then return end
    buffer.writeu32(chunk.pixels,offset,color)
    markDirty(chunk,xx,yy,xx)
end

-- ---------------------------------------------------------------- PF019 M14 skins
-- A tile's static pattern value (CosmeticAppearance.patternField), cached per map in a
-- u16 buffer (65535 = not computed). Only the noise skins have one.
function Renderer:skinField(pattern: string,id: number,x: number,y: number): number?
    if pattern~="contours" and pattern~="aurora" and pattern~="storm" and pattern~="grid" and pattern~="glacier" then return nil end
    local cache=self.skinFields[pattern]
    if not cache then cache=buffer.create(self.map.width*self.map.height*2);buffer.fill(cache,0,255);self.skinFields[pattern]=cache end
    local value=buffer.readu16(cache,(id-1)*2)
    if value==65535 then value=CosmeticAppearance.patternField(pattern,x,y);buffer.writeu16(cache,(id-1)*2,value) end
    return value
end
-- One tile's pattern step at the sweep's step (phase). Interior plain-terrain tiles (defended ones too: their checker
-- half darkens under the pattern, as in paint()) take the fast path (the same words paint() produces) into the planes, so
-- nothing shows until the sweep commits; any other tile is painted in full.
function Renderer:repattern(id: number,x: number,y: number,owner: number,pattern: string,phase: number)
    local passes=self.graphics.passEnabled
    if self.borderCache[id]~=nil or self.altView or self.fallout[id] or not passes.territory or not passes.terrain or #self.mapLayers.records>0 then self:paint(id);return end
    -- PF028: a rim tile (a cardinal neighbour is a seam tile) is painted in full, like the seam itself
    local cache,w=self.borderCache,self.map.width
    local west,east,north,south=cache[id-1],cache[id+1],cache[id-w],cache[id+w]
    if (west and west[1]) or (east and east[1]) or (north and north[1]) or (south and south[1]) then self:paint(id);return end
    local coverage=self.defenseCoverage[owner]
    local value=buffer.readu8(self.map.terrain,id-1)
    local palette=self.palettes[owner]
    local field=self:skinField(pattern,id,x,y)
    local normal=CosmeticAppearance.patternWord(palette.fill[value],pattern,x,y,phase,field)
    local hover=CosmeticAppearance.patternWord(palette.hoverFill[value],pattern,x,y,phase,field)
    if coverage~=nil and coverage[id]~=nil then
        local k=CosmeticAppearance.SKIN_DEFENSE_DARKEN;normal=CosmeticAppearance.scaleWord(normal,k);hover=CosmeticAppearance.scaleWord(hover,k)
    end
    self:writePlanes(x,y,normal,hover)
end
-- Reduced motion (or a static background) holds every skin at rest. Read at most every 2 s.
function Renderer:skinMotionReduced(): boolean
    local now=os.clock()
    if now-self.skinMotionCheck<2 then return self.skinReduced end
    self.skinMotionCheck=now
    local preferences=self.preferences;local reduced=false
    if preferences then
        local ok,snapshot=pcall(function() return preferences:snapshot() end)
        if ok and type(snapshot)=="table" then
            reduced=snapshot["settings.reducedMotion"]=="true" or snapshot["settings.staticBackground"]=="true" or snapshot["settings.motionEnabled"]=="false"
        end
    end
    self.skinReduced=reduced;return reduced
end
-- Steps each animated skin (CosmeticAppearance.patternMotion) and sweeps its owners' tiles:
-- one sweep per owner over a snapshot of its 32-tile mask blocks (masks are read live, so
-- tiles won or lost mid-sweep stay correct). A step that lands mid-sweep starts one more
-- pass when the sweep ends, so a huge empire rolls through steps instead of stalling.
-- PF020 (Ashton: a big Aurora empire read as horizontal streaks): a sweep paints every tile at
-- ITS step into the normal/hover planes only, and when it ends the whole territory is copied to
-- the shown pixels at once (copyOwnerPlane) and uploaded that frame. A territory never shows two
-- steps; a huge one simply steps less often.
function Renderer:advanceSkins()
    local looks,map=self.cosmeticLooks,self.map
    if not looks or not map or not self.displayOwners then return end
    local now,reduced=os.clock(),self:skinMotionReduced()
    for owner,look in looks do
        local skin=look and look.Skin and CosmeticCatalog.byId[look.Skin]
        local motion=skin and CosmeticAppearance.patternMotion[skin.pattern]
        if not motion then continue end
        local pattern=skin.pattern
        local step=if reduced then 0 else math.floor(now*motion.steps/motion.seconds)%motion.steps
        local phase=step/motion.steps
        self.skinPhase[pattern]=phase
        local sweep=self.skinSweeps[owner]
        if sweep then continue end
        if self.skinSwept[owner]==phase then continue end
        local blocks={}
        for index,masks in self.displayMasks[owner] or {} do for key in masks do blocks[#blocks+1]=index;blocks[#blocks+1]=key end end
        self.skinSweeps[owner]={pattern=pattern,phase=phase,blocks=blocks,cursor=1}
        table.insert(self.skinSweepOrder,owner)
    end
    local started=os.clock();local done=0
    while #self.skinSweepOrder>0 do
        local owner=self.skinSweepOrder[1];local sweep=self.skinSweeps[owner]
        local look=looks[owner];local skin=look and look.Skin and CosmeticCatalog.byId[look.Skin]
        if not sweep or not skin or skin.pattern~=sweep.pattern then
            table.remove(self.skinSweepOrder,1);self.skinSweeps[owner]=nil;continue
        end
        local masksByChunk=self.displayMasks[owner]
        local blocks=sweep.blocks
        while sweep.cursor<#blocks do
            local index,key=blocks[sweep.cursor],blocks[sweep.cursor+1];sweep.cursor+=2
            local masks=masksByChunk and masksByChunk[index];local mask=masks and masks[key]
            if not mask then continue end
            local chunk=self.chunks[index]
            local baseX,y=chunk.x+((key-1)%chunk.maskColumns)*MASK_WIDTH,chunk.y+(key-1)//chunk.maskColumns
            while mask~=0 do
                local bit=bit32.countrz(mask);mask=bit32.band(mask,mask-1)
                local x=baseX+bit
                self:repattern(y*map.width+x+1,x,y,owner,sweep.pattern,sweep.phase);done+=1
            end
            if done>=SKIN_TILES_PER_FRAME or os.clock()-started>=SKIN_SECONDS_PER_FRAME then break end
        end
        if sweep.cursor<#blocks then break end
        table.remove(self.skinSweepOrder,1);self.skinSweeps[owner]=nil
        -- Commit: the whole territory shows the new step together. Remember the step this sweep
        -- painted; a newer step starts the next sweep.
        self:copyOwnerPlane(owner,owner==self.highlighted);self.skinCommitted=true
        self.skinSwept[owner]=sweep.phase
        if done>=SKIN_TILES_PER_FRAME or os.clock()-started>=SKIN_SECONDS_PER_FRAME then break end
    end
    if done>0 then Performance.count("MapRenderer.skinTiles",done) end
end

function Renderer:uploadBuffer(bytes: number): buffer
    local cached=self.uploadBuffers[bytes]
    if cached then Performance.count("MapRenderer.bufferCacheHits",1);return cached end
    -- API calls copy their input synchronously. Bound staging memory to 128
    -- region sizes and reuse equal-area buffers across chunks/rectangles.
    local cursor=self.uploadBufferCursor
    local previous=self.uploadBufferKeys[cursor]
    if previous then self.uploadBuffers[previous]=nil;Performance.count("MapRenderer.bufferEvictions",1) end
    cached=buffer.create(bytes)
    Performance.count("MapRenderer.bufferAllocations",1)
    Performance.count("MapRenderer.bufferAllocBytes",bytes)
    self.uploadBuffers[bytes]=cached;self.uploadBufferKeys[cursor]=bytes
    self.uploadBufferCursor=cursor%128+1
    return cached
end

function Renderer:flush(force: boolean?)
    local started=Performance.start()
    local deadline=os.clock()+UPLOAD_SECONDS_PER_FRAME
    local calls,bytes=0,0
    local lastChunk=nil
    for chunkOffset=0,#self.chunks-1 do
        local chunkIndex=((self.uploadChunkCursor or 1)+chunkOffset-1)%#self.chunks+1
        local chunk=self.chunks[chunkIndex]
        local deferred=chunk.deferredRegions or {};table.clear(deferred)
        for _,regionId in chunk.dirtyRegions do
            local region=chunk.regions[regionId]
            if not region.minX then continue end -- Earlier successful uploads on retry.
            -- Outward 8px alignment leaves only 97 possible staging sizes on
            -- World. All fit in the cache; copied clean pixels are unchanged.
            local minX,minY=math.floor(region.minX/8)*8,math.floor(region.minY/8)*8
            local endX=math.min(chunk.width,math.ceil((region.maxX+1)/8)*8)
            local endY=math.min(chunk.height,math.ceil((region.maxY+1)/8)*8)
            local width,height=endX-minX,endY-minY
            local size=width*height*4
            if not force and calls>0 and (calls>=UPLOAD_CALLS_PER_FRAME or bytes+size>UPLOAD_BYTES_PER_FRAME or os.clock()>=deadline) then
                deferred[#deferred+1]=regionId
                continue
            end
            local pixels = self:uploadBuffer(width*height*4)
            for y=0,height-1 do
                buffer.copy(pixels,y*width*4,chunk.pixels,((y+minY)*chunk.width+minX)*4,width*4)
            end
            chunk.image:WritePixelsBuffer(Vector2.new(minX,minY),Vector2.new(width,height),pixels)
            Performance.count("MapRenderer.uploadBytes",width*height*4)
            Performance.count("MapRenderer.uploadCalls",1)
            calls+=1;bytes+=size
            lastChunk=chunkIndex
            region.minX,region.minY,region.maxX,region.maxY=nil,nil,nil,nil
        end
        local previous=chunk.dirtyRegions;chunk.dirtyRegions=deferred;chunk.deferredRegions=previous
    end
    if lastChunk then self.uploadChunkCursor=lastChunk%#self.chunks+1 end
    Performance.finish("MapRenderer.flush",started)
end

function Renderer:updateOwners(owners: {number}, changed: {number}?)
    -- GameView ownership is immediate. Name placement and input continue using
    -- these logical indexes while TerritoryPass owns a separate display state.
    self.owners = owners
    if changed == nil then
        self.displayVersion+=1
        self.falloutDisplayVersion+=1
        table.clear(self.paintQueue);table.clear(self.paintQueued);self.paintHead=1;self.paintTail=0
        self.displayOwners=table.clone(owners)
        for _,bucket in self.dripBuckets do table.clear(bucket) end
        table.clear(self.bucketStarted)
        self.currentBucket=1;self.pendingTileCount=0
        for _, territory in self.displayOwned do for id in territory do self:paint(id) end end
        self.owned = {}
        self.ownerIndex = {}
        self.displayOwned={};self.displayMasks={}
        for id, owner in owners do
            if owner > 0 then
                self.owned[owner]=self.owned[owner] or {};self.owned[owner][id]=true;self.ownerIndex[id]=owner
                self.displayOwned[owner]=self.displayOwned[owner] or {};self.displayOwned[owner][id]=true
                self:updateDisplayMask(id,0,owner)
                self:paint(id)
            end
        end
        self:flush(true)
    else
        for _,id in changed do
            local previous = self.ownerIndex[id]
            if previous and self.owned[previous] then self.owned[previous][id] = nil end
            local owner = owners[id]
            self.ownerIndex[id] = if owner > 0 then owner else nil
            if owner > 0 then
                self.owned[owner] = self.owned[owner] or {}
                self.owned[owner][id] = true
            end
            local bucketId=Renderer.bucketForRef(id-1)+1
            local bucket=self.dripBuckets[bucketId]
            if #bucket==0 then self.bucketStarted[bucketId]=Performance.start() end
            -- Capture the arriving value; later logical snapshots mutate owners.
            bucket[#bucket+1]=id;bucket[#bucket+1]=owner
            self.pendingTileCount+=1
        end
        Performance.count("MapRenderer.queuedTiles",#changed)
    end
end

function Renderer:drainBucket(index: number)
    local bucket=self.dripBuckets[index]
    local display,owned,dirty=self.displayOwners,self.displayOwned,self.dirty
    local w,h=self.map.width,self.map.height
    local fallout=self.falloutBuckets[index]
    if fallout then
        for _,event in fallout do local previous=self.fallout[event.id]==true;if previous~=event.value then self.fallout[event.id]=if event.value then true else nil;self.falloutHeat[event.id]=if event.value then 255 else nil;dirty[event.id]=true end end
        self.falloutBuckets[index]=nil
        self.falloutVersion+=1
    end
    for i=1,#bucket,2 do
        local id,owner=bucket[i],bucket[i+1]
        local previous=display[id]
        display[id]=owner
        if previous==owner then continue end
        -- Bloom only depends on owned/unowned fallout samples. Other battles
        -- must not invalidate its identical buffer on every display bucket.
        if self.fallout[id] and (previous>0)~=(owner>0) then self.falloutDisplayVersion+=1 end
        if previous>0 and owned[previous] then owned[previous][id]=nil end
        if owner>0 then owned[owner]=owned[owner] or {};owned[owner][id]=true end
        self:updateDisplayMask(id,previous,owner)
        local x,y=(id-1)%w,math.floor((id-1)/w)
        dirty[id]=true
        local radius=math.min(10,math.floor(self.graphics.mapOverlay.highlightThicken))
        if radius>1 then
            for yy=math.max(0,y-radius),math.min(h-1,y+radius)do for xx=math.max(0,x-radius),math.min(w-1,x+radius)do
                local nearby=yy*w+xx+1;local nearbyOwner=display[nearby]
                if nearbyOwner>0 and (nearbyOwner==previous or nearbyOwner==owner)then dirty[nearby]=true end
            end end
        end
        local north=if y>0 then display[id-w] else 0
        local south=if y<h-1 then display[id+w] else 0
        local west=if x>0 then display[id-1] else 0
        local east=if x<w-1 then display[id+1] else 0
        -- A third owner's geometry remains a border, but its relationship tint
        -- may change when this neighboring tile transfers ally -> enemy.
        -- Empty pixels alone are independent of neighboring ownership.
        if north>0 and y>0 then dirty[id-w]=true end
        if south>0 and y<h-1 then dirty[id+w]=true end
        if west>0 and x>0 then dirty[id-1]=true end
        if east>0 and x<w-1 then dirty[id+1]=true end
        -- Cache every owner's highlighted result, including currently unhovered
        -- diagonal borders. Map-edge pixels already have a cardinal border. So
        -- do pixels where either shared cardinal neighbor differs from its owner.
        -- A later own/cardinal transfer in this batch marks that pixel itself.
        if y>1 and x>1 then
            local diagonal=display[id-w-1]
            if diagonal>0 and (diagonal==previous or diagonal==owner) and north==diagonal and west==diagonal then dirty[id-w-1]=true end
        end
        if y>1 and x<w-2 then
            local diagonal=display[id-w+1]
            if diagonal>0 and (diagonal==previous or diagonal==owner) and north==diagonal and east==diagonal then dirty[id-w+1]=true end
        end
        if y<h-2 and x>1 then
            local diagonal=display[id+w-1]
            if diagonal>0 and (diagonal==previous or diagonal==owner) and south==diagonal and west==diagonal then dirty[id+w-1]=true end
        end
        if y<h-2 and x<w-2 then
            local diagonal=display[id+w+1]
            if diagonal>0 and (diagonal==previous or diagonal==owner) and south==diagonal and east==diagonal then dirty[id+w+1]=true end
        end
        -- PF028: a skinned territory's rim sits one tile inside its seam, so a transfer can move it two tiles away
        local rims=self.skinRims
        if rims and (rims[previous] or rims[owner]) then
            for _,offset in RIM_RING do
                local xx,yy=x+offset[1],y+offset[2]
                if xx<0 or yy<0 or xx>=w or yy>=h then continue end
                local nearby=yy*w+xx+1;local nearbyOwner=display[nearby]
                if nearbyOwner>0 and (nearbyOwner==previous or nearbyOwner==owner) and rims[nearbyOwner] then dirty[nearby]=true end
            end
        end
    end
    local count=#bucket/2
    if count>0 then self.displayVersion+=1 end
    self.pendingTileCount-=count
    if count>0 then Performance.finish("MapRenderer.queueAge",self.bucketStarted[index]) end
    self.bucketStarted[index]=nil
    table.clear(bucket)
    Performance.count("MapRenderer.drainedTiles",count)
end

function Renderer:advance(phase: string?,force: boolean?)
    if not self.displayOwners then return end
    local started=Performance.start()
    table.clear(self.dirty)
    if self.fullPaintCursor then
        local count=self.map.width*self.map.height
        local capacity=if force then count else math.min(PAINT_TILES_PER_FRAME,math.max(0,4096-(self.paintTail-self.paintHead+1)))
        if capacity>0 then
            local last=math.min(count,self.fullPaintCursor+capacity-1)
            for id=self.fullPaintCursor,last do self.dirty[id]=true end
            self.fullPaintCursor=if last<count then last+1 else nil
        end
    end
    for id in self.defenseDirty do self.dirty[id]=true end
    table.clear(self.defenseDirty)
    local drainStarted=Performance.start()
    if phase=="Choosing" then
        for i=1,DRIP_BUCKET_COUNT do self:drainBucket(i) end
    else
        self:drainBucket(self.currentBucket)
        -- Empty buckets advance too; this is render-frame cadence, not tick time.
        self.currentBucket=self.currentBucket%DRIP_BUCKET_COUNT+1
    end
    Performance.finish("MapRenderer.drain",drainStarted)
    for id in self.dirty do
        if not self.paintQueued[id] then
            self.paintTail+=1;self.paintQueue[self.paintTail]=id;self.paintQueued[id]=true
        end
    end
    local paintStarted=Performance.start();local painted=0
    local deadline=os.clock()+PAINT_SECONDS_PER_FRAME
    while self.paintHead<=self.paintTail do
        local id=self.paintQueue[self.paintHead]
        self.paintQueue[self.paintHead]=nil;self.paintQueued[id]=nil;self.paintHead+=1
        self:paint(id);painted+=1
        if not force and (painted>=PAINT_TILES_PER_FRAME or painted%32==0 and os.clock()>=deadline) then break end
    end
    if self.paintHead>self.paintTail then
        table.clear(self.paintQueue);self.paintHead=1;self.paintTail=0
    elseif self.paintHead>8192 then
        local remaining=self.paintTail-self.paintHead+1
        for index=1,remaining do self.paintQueue[index]=self.paintQueue[self.paintHead+index-1] end
        for index=remaining+1,self.paintTail do self.paintQueue[index]=nil end
        self.paintHead=1;self.paintTail=remaining
    end
    Performance.finish("MapRenderer.paint",paintStarted)
    if not force then self:advanceSkins() end
    Performance.count("MapRenderer.paintedTiles",painted)
    Performance.count("MapRenderer.paintBacklog",self.paintTail-self.paintHead+1)
    -- a committed skin step uploads in full this frame (no partial, mixed-step territory)
    local committed=self.skinCommitted==true;self.skinCommitted=false
    self:flush(force or committed)
    Performance.finish("MapRenderer.advance",started)
end

function Renderer:flushAllDripBuckets()
    -- Source Choosing/seek path drains in bucket order without moving the cursor.
    self:advance("Choosing",true)
end

function Renderer:copyOwnerPlane(owner: number,highlighted: boolean)
    local playerMasks=self.displayMasks[owner]
    if not playerMasks then return end
    local blocks,spans,pixels=0,0,0
    for index,masks in playerMasks do
        local chunk=self.chunks[index]
        local source=if highlighted then chunk.hoverPixels else chunk.normalPixels
        for key,mask in masks do
            local xx,yy=((key-1)%chunk.maskColumns)*MASK_WIDTH,math.floor((key-1)/chunk.maskColumns)
            local first,last=bit32.countrz(mask),31-bit32.countlz(mask)
            local remaining=mask
            while remaining~=0 do
                local start=bit32.countrz(remaining)
                local length=bit32.countrz(bit32.bnot(bit32.rshift(remaining,start)))
                local offset=(yy*chunk.width+xx+start)*4
                buffer.copy(chunk.pixels,offset,source,offset,length*4)
                spans+=1;pixels+=length
                local finish=start+length
                remaining=if finish>=MASK_WIDTH then 0 else bit32.band(remaining,bit32.lshift(4294967295,finish))
            end
            markDirty(chunk,xx+first,yy,xx+last)
            blocks+=1
        end
    end
    Performance.count("MapRenderer.hoverBlocks",blocks)
    Performance.count("MapRenderer.hoverSpans",spans)
    Performance.count("MapRenderer.hoverPixels",pixels)
end

function Renderer:setHighlightOwner(owner: number?)
    local nextOwner = owner or 0
    if nextOwner < 0 then nextOwner=0 end
    if self.highlighted == nextOwner or not self.owners then return end
    local started=Performance.start()
    debug.profilebegin("OpenFront.HoverHighlight")
    local old = self.highlighted
    self.highlighted = nextOwner
    if self.graphics.passEnabled.borderCompute then
        for _,id in {old,nextOwner}do for tile in self.borderTiles[id]or {}do local cached=self.borderCache[tile];if cached then cached.highlighted=id==nextOwner end end end
    end
    -- PF - 4 (Ashton: "late game skin ripping"): while a skin sweep is part-way, an owner's normal / hover planes hold two
    -- steps (the swept 32-tile mask rows at the new one, the rest at the shown one), so copying them now showed horizontal
    -- streaks until the commit. A mid-sweep owner skips the copy; its commit copies the plane for self.highlighted, so the
    -- hover lands with the next step instead.
    if old > 0 and not self.skinSweeps[old] then self:copyOwnerPlane(old,false) end
    if nextOwner > 0 and not self.skinSweeps[nextOwner] then self:copyOwnerPlane(nextOwner,true) end
    self:flush()
    debug.profileend()
    Performance.count("MapRenderer.hoverChanges",1)
    Performance.finish("MapRenderer.highlight",started)
end

function Renderer:drawGraphics(zoom: number,viewport: Frame,state: any)
    self.graphicsOverlay=self.graphicsOverlay or GraphicsOverlay.new(self)
    self.graphicsOverlay:draw(zoom,viewport,state)
end

return Renderer
