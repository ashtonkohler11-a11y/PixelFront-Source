--!strict
-- PF028 (PF - 3, Ashton approved the skins board 2026-10-08: "Good, build skins"): the territory-skin cards (96×64) ARE
-- the map. Each card is a 96×64-tile window of one standard scene (work/skins-r2/scene.mjs) painted tile by tile with
-- the very material the map uses (CosmeticAppearance.patternField / patternWord, the seam, the rim, a defense post's
-- darkened area), so the shop / inventory preview matches the land 1:1: same pattern scale, colours, borders and
-- motion. The loop is the map's own (patternMotion: the same steps over the same seconds). The window holds your
-- territory, a same-skin neighbour across the seam, a rival, the coast, a defense post's edge and a rail in the skin's
-- unit colour. CosmeticIdleArt merges these with the flags and crowns (frames, sheets, uploads, CosmeticArt.bind).
local P=require(script.Parent.CosmeticPixelPainter)
local Appearance=require((game :: any).ReplicatedStorage.Shared.CosmeticAppearance)
type Canvas=P.Canvas
type Rgb=P.Rgb
local Skins={}
local W,H=96,64
-- the scene (240×135 tiles) and the card's window in it
local SW,SH=240,135
local CX,CY=100,32
local MARGIN=2
local noise,hash=Appearance.noise,Appearance.hash
local function hex(h: string): Rgb return P.hex(h) end
local function mix(a: Rgb,b: Rgb,t: number): Rgb return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
-- ---------------------------------------------------------------- the scene: terrain (OpenFront's palette)
local OCEAN,DEEP,SHALLOW,SAND=hex("#4785b5"),hex("#3d78a8"),hex("#6a9fc6"),hex("#cccb9e")
local PLAINS,HIGH,MOUNT,SNOW=hex("#bedc8a"),hex("#dccb9e"),hex("#e6dfcc"),hex("#f2efe6")
local function terrainAt(x: number,y: number): (boolean,Rgb)
    local land=noise(x,y,58,7)*.68+noise(x,y,21,8)*.32+(x/SW)*.42-(y/SH)*.1
    if land<.52 then local d=.52-land;return true,if d<.03 then SHALLOW elseif d>.12 then DEEP else OCEAN end
    if land<.545 then return false,SAND end
    local e=noise(x,y,30,9)*.75+noise(x,y,9,10)*.25
    local tint=(noise(x,y,6,11)-.5)*.08
    local c=if e>.78 then SNOW elseif e>.68 then MOUNT elseif e>.52 then mix(PLAINS,HIGH,(e-.52)/.16) else PLAINS
    return false,if tint<0 then mix(c,{0,0,0},-tint) else c
end
-- ---------------------------------------------------------------- the scene: territories
-- blobs on land; a tile goes to the blob it sits deepest inside. 1 = you, 2 = a same-skin neighbour, 3 = a rival, 4 = a tribe
local BLOBS={{cx=118,cy=70,r=46,seed=1.3,owner=1},{cx=186,cy=44,r=30,seed=4.1,owner=2},{cx=192,cy=108,r=27,seed=2.7,owner=3},{cx=80,cy=20,r=13,seed=5.5,owner=4}}
local DEFENSE={x=100,y=82,r=13}
local RIVAL,TRIBE,NEIGHBOUR=hex("#e88fb6"),hex("#d1cdc7"),hex("#e0a34a")
local CLASSIC=hex("#9b6be0") -- Classic's card: you in a player colour (the map paints your own)
local function ownerAt(x: number,y: number,water: boolean): number
    if water then return 0 end
    local best,bv=0,1
    for _,b in BLOBS do
        local a=math.atan2(y-b.cy,x-b.cx)
        -- the JS scene's integer seed (a ^ b.seed*13 truncates), so the shapes are the board's
        local r=b.r*(1+.16*math.sin(3*a+b.seed)+.09*math.sin(7*a+b.seed*2.1)+.05*math.sin(13*a+b.seed*.7))+(noise(x,y,6,math.floor(b.seed*13))-.5)*5
        local v=math.sqrt((x-b.cx)^2+(y-b.cy)^2)/r
        if v<bv then bv=v;best=b.owner end
    end
    return best
end
-- The window's static layer, made once: terrain, owners, seams, rims, the defense area, the static fields per skin.
type Tile={water: boolean,terrain: Rgb,owner: number,border: boolean,rim: boolean,defended: boolean}
local tiles: {[number]: Tile}?=nil
local function scene(): {[number]: Tile}
    if tiles then return tiles end
    local GW,GH=W+2*MARGIN,H+2*MARGIN
    local raw={}
    for gy=0,GH-1 do for gx=0,GW-1 do
        local x,y=CX-MARGIN+gx,CY-MARGIN+gy
        local water,terrain=terrainAt(x,y)
        raw[gy*GW+gx]={water=water,terrain=terrain,owner=ownerAt(x,y,water),border=false,rim=false,defended=false}
    end end
    local function at(gx: number,gy: number): number
        if gx<0 or gy<0 or gx>=GW or gy>=GH then return -1 end
        return raw[gy*GW+gx].owner
    end
    local function seam(gx: number,gy: number): boolean
        local o=at(gx,gy);return o>0 and (at(gx+1,gy)~=o or at(gx-1,gy)~=o or at(gx,gy+1)~=o or at(gx,gy-1)~=o)
    end
    for gy=1,GH-2 do for gx=1,GW-2 do
        local t=raw[gy*GW+gx]
        if t.owner>0 then
            t.border=seam(gx,gy)
            t.rim=not t.border and (seam(gx+1,gy) or seam(gx-1,gy) or seam(gx,gy+1) or seam(gx,gy-1))
            local x,y=CX-MARGIN+gx,CY-MARGIN+gy
            t.defended=t.owner==1 and math.sqrt((x-DEFENSE.x)^2+(y-DEFENSE.y)^2)<=DEFENSE.r
        end
    end end
    local out={}
    for y=0,H-1 do for x=0,W-1 do out[y*W+x]=raw[(y+MARGIN)*GW+x+MARGIN] end end
    tiles=out
    return out
end
local function word(c: Rgb): number
    return bit32.bor(0xFF000000,math.floor(c[1]+.5),bit32.lshift(math.floor(c[2]+.5),8),bit32.lshift(math.floor(c[3]+.5),16))
end
local function unword(w: number): Rgb return {bit32.band(w,255),bit32.band(bit32.rshift(w,8),255),bit32.band(bit32.rshift(w,16),255)} end
-- the unit-colour rail (a railroad between two of your cities) and a stopped train on it
local function rail(c: Canvas,unit: Rgb,map: {[number]: Tile})
    local dark,light,body=mix(unit,{0,0,0},.58),mix(unit,{255,255,255},.55),mix(unit,{0,0,0},.15)
    local function dot(x: number,y: number,col: Rgb)
        local lx,ly=x-CX,y-CY
        if lx<0 or ly<0 or lx>=W or ly>=H or map[ly*W+lx].owner~=1 then return end
        P.put(c,lx,ly,col,.95)
    end
    for x=108,150 do dot(x,78,if x%2==1 then body else dark) end
    for y=56,78 do dot(150,y,if y%2==1 then body else dark) end
    for k=0,2 do
        for dy=-1,1 do for dx=-1,1 do dot(118+k*3+dx,78+dy,if dx==0 and dy==0 then (if k==2 then light else unit) else dark) end end
    end
end
-- One card frame: the window painted at loop phase t.
local function card(pattern: string,t: number): Canvas
    local c=P.canvas(W,H);local map=scene()
    local palette=Appearance.skinPalettes[pattern]
    local base,border=hex(palette.base),hex(palette.border)
    local plainBorder=function(col: Rgb): Rgb return mix(col,{0,0,0},.32) end
    for y=0,H-1 do for x=0,W-1 do
        local tile=map[y*W+x];local wx,wy=CX+x,CY+y
        local col: Rgb=tile.terrain
        if tile.owner==1 or tile.owner==2 then
            if tile.border then
                col=border;if tile.defended and (wx+wy)%2==1 then col=mix(col,{0,0,0},.3) end
            else
                local w=Appearance.patternWord(word(mix(tile.terrain,base,Appearance.TAKEOVER_ALPHA)),pattern,wx,wy,t,Appearance.patternField(pattern,wx,wy))
                if tile.rim then w=Appearance.rimWord(w,pattern) end
                if tile.defended then w=Appearance.scaleWord(w,Appearance.SKIN_DEFENSE_DARKEN) end
                col=unword(w)
            end
        elseif tile.owner>0 then
            local own=if tile.owner==3 then RIVAL else TRIBE
            col=if tile.border then plainBorder(own) else mix(tile.terrain,own,150/255)
        end
        P.put(c,x,y,col)
    end end
    rail(c,hex(palette.unit),map)
    return c
end
-- Classic: OpenFront's plain fill (your colour at 150/255 over the land, a darker seam), the same window. No motion.
local function classic(_t: number): Canvas
    local c=P.canvas(W,H);local map=scene()
    for y=0,H-1 do for x=0,W-1 do
        local tile=map[y*W+x];local col: Rgb=tile.terrain
        if tile.owner>0 then
            local own=if tile.owner==1 then CLASSIC elseif tile.owner==2 then NEIGHBOUR elseif tile.owner==3 then RIVAL else TRIBE
            if tile.border then col=mix(own,{0,0,0},.32);if tile.defended and (CX+x+CY+y)%2==1 then col=mix(col,{0,0,0},.3) end
            else col=mix(tile.terrain,own,150/255);if tile.defended then col=mix(col,{0,0,0},.15) end end
        end
        P.put(c,x,y,col)
    end end
    rail(c,CLASSIC,map)
    return c
end
-- Loop metadata (the map's own loop: one frame per patternMotion step) and painters, merged by CosmeticIdleArt.
local IDS={skin_stripes="stripes",skin_grid="grid",skin_contours="contours",skin_aurora="aurora",skin_forge="forge",skin_stormfront="storm",skin_glacier="glacier"}
Skins.patterns=table.freeze(table.clone(IDS))
local items: {[string]: any}={skin_classic={w=W,h=H,frames=1,seconds=1}}
local painters: {[string]: (number)->Canvas}={skin_classic=classic}
for id,pattern in IDS do
    local motion=Appearance.patternMotion[pattern]
    items[id]={w=W,h=H,frames=motion.steps,seconds=motion.seconds}
    painters[id]=function(t: number): Canvas return card(pattern,t) end
end
Skins.items=items
Skins.painters=painters
-- The window's place in the scene, for harnesses that crop the map render to compare (work/skins-r2: CARD).
Skins.window=table.freeze({x=CX,y=CY,w=W,h=H})
return table.freeze(Skins)
