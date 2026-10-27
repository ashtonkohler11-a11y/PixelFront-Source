--!strict
-- PF043 H (PF - 3; the approved list A1-A3, A8): the quiet beds under the map. They follow the camera and the zoom (like
-- Civilization VII mixes by zoom level), beside the source building beds (OpenFrontAmbience: city / factory / silo / SAM).
--   A1 wind      the whole match; a little louder zoomed in, and it gives way to the shore
--   A2 shore     zoom 8+ with land and water both in view (strongest at an even mix)
--   A3 battle    active fronts in view: gain min(1, fronts / 4)
--   A8 fallout   fallout in view, fading out as it clears
-- Each bed glides to its new level over 2 s. Beds.mix is the pure part (tested).
local Beds={};Beds.__index=Beds
Beds.FADE=2000 -- ms
Beds.STEP=.04 -- a level change smaller than this waits (no fade churn every packet)
local function isLand(state: any,tile: number): boolean?
    local terrain=state.map and state.map.terrain
    if not terrain or tile<1 or tile>buffer.len(terrain) then return nil end
    return bit32.band(buffer.readu8(terrain,tile-1),128)~=0
end
-- The beds' levels for a view: scale = px per tile, centerTile = the view's centre, view = its size in px.
function Beds.mix(state: any,scale: number,centerTile: number?,view: Vector2): {[string]: number}
    local out={a_wind=0,a_shore=0,a_battle=0,a_fallout=0}
    if type(state)~="table" or not state.map or not centerTile or scale<=0 then return out end
    local width,height=state.map.width,state.map.height
    local cx,cy=(centerTile-1)%width,math.floor((centerTile-1)/width)
    local halfW,halfH=view.X/2/scale,view.Y/2/scale
    local zoom=math.clamp((scale-2)/18,0,1)
    -- shore: a 6 x 4 sample of the view (zoom 8+)
    local shore=0
    if scale>=8 then
        local land,total=0,0
        for i=0,5 do for j=0,3 do
            local x=math.floor(cx-halfW+(i+.5)*halfW/3);local y=math.floor(cy-halfH+(j+.5)*halfH/2)
            if x<0 or y<0 or x>=width or y>=height then continue end
            local l=isLand(state,y*width+x+1);if l==nil then continue end
            total+=1;if l then land+=1 end
        end end
        if total>0 then local w=land/total;shore=math.clamp(1-math.abs(2*w-1),0,1)*math.clamp((scale-8)/4,0,1) end
    end
    out.a_shore=shore
    out.a_wind=(.55+.45*zoom)*(1-.7*shore)
    -- fronts in view
    local fronts=0
    for _,attack in state.attacks or {} do
        local tile=attack.sourceTile
        if type(tile)~="number" then continue end
        local x,y=(tile-1)%width,math.floor((tile-1)/width)
        if math.abs(x-cx)<=halfW and math.abs(y-cy)<=halfH then fronts+=1 end
    end
    out.a_battle=math.min(1,fronts/4)
    -- fallout in view: a 10 x 6 sample
    if (state.falloutCount or 0)>0 and state.falloutTiles then
        local hit=0
        for i=0,9 do for j=0,5 do
            local x=math.floor(cx-halfW+(i+.5)*halfW/5);local y=math.floor(cy-halfH+(j+.5)*halfH/3)
            if x<0 or y<0 or x>=width or y>=height then continue end
            if state.falloutTiles[y*width+x+1] then hit+=1 end
        end end
        out.a_fallout=math.min(1,hit/8)
    end
    return out
end
-- Is a tile inside the view (with a small pad)? Others' far-off impacts, intercepts and sinkings only sound when it is (AudioCues).
Beds.PAD=.1
function Beds.inView(state: any,scale: number,centerTile: number?,view: Vector2,tile: any): boolean
    if type(state)~="table" or not state.map or not centerTile or scale<=0 or type(tile)~="number" then return false end
    local width=state.map.width
    local cx,cy=(centerTile-1)%width,math.floor((centerTile-1)/width)
    local x,y=(tile-1)%width,math.floor((tile-1)/width)
    local pad=1+Beds.PAD
    return math.abs(x-cx)<=view.X/2/scale*pad and math.abs(y-cy)<=view.Y/2/scale*pad
end
function Beds.new(audio: any): any return setmetatable({audio=audio,loops={},levels={}},Beds) end
-- the last view the map reported (AudioCues asks it about event tiles)
function Beds:sees(state: any,tile: any): boolean
    local v=self.view
    return v~=nil and Beds.inView(state,v.scale,v.centerTile,v.size,tile)
end
-- PF045 v3 pan: -1 (the view's left edge) .. 1 (its right edge) for a tile; off-screen tiles sit at the edge (so an
-- attack from off-screen right sounds from the right). Soft: Beds.PAN of full.
Beds.PAN=.7
function Beds.panOfView(width: number,scale: number,centerTile: number?,view: Vector2,tile: any): number?
    if not centerTile or scale<=0 or type(tile)~="number" or width<=0 then return nil end
    local cx=(centerTile-1)%width;local x=(tile-1)%width
    local half=view.X/2/scale;if half<=0 then return nil end
    return math.clamp((x-cx)/half,-1,1)*Beds.PAN
end
function Beds:panOf(tile: any): number?
    local v=self.view
    return v and v.width and Beds.panOfView(v.width,v.scale,v.centerTile,v.size,tile)
end
function Beds:update(state: any,scale: number,centerTile: number?)
    local camera=workspace.CurrentCamera
    local view=if camera then camera.ViewportSize else Vector2.new(1280,720)
    self.view={scale=scale,centerTile=centerTile,size=view,width=type(state)=="table" and state.map and state.map.width or nil}
    if type(state)~="table" or state.phase=="Won" or state.phase=="Lost" then return end
    local mix=Beds.mix(state,scale,centerTile,view)
    for key,level in mix do
        local loop=self.loops[key]
        if loop==nil and level>0 then
            loop=self.audio:loop(key,0);self.loops[key]=loop or false
            if loop then loop:start() end
        end
        if loop and math.abs(level-(self.levels[key] or 0))>=Beds.STEP then
            self.levels[key]=level;loop:setGain(level,Beds.FADE)
        end
    end
end
function Beds:stop()
    for _,loop in self.loops do if loop then loop:stop(500) end end
    table.clear(self.loops);table.clear(self.levels)
end
return Beds
