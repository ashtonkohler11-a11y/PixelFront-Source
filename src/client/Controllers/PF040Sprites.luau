--!strict
-- PF-040 (PF - 1; Ashton: nuke aim "Good, build", warship selection "Good, build"): the one baked sprite sheet
-- (work/pf040/ingame/sheet.cjs v2, rbxassetid://132334514909526). Map pieces are pixel art at 1 px = 1 tile and are shown
-- Pixelated at Size = px * zoom, so each ring stays a crisp 1-tile band at any zoom; nothing here is drawn per frame.
--   ringR / discR (R = 8, 13, 21, 56, 70; 64 is the SAM ring, scaled to the live range), brackets, ping0..5 (map px)
--   reticle (52 px) and intercept (21 px) are UI-space sprites shown at their own size
local Sprites={}
Sprites.SHEET="rbxassetid://132334514909526"
local RECTS={brackets={282,278,17,17},disc13={32,278,29,29},disc21={467,146,45,45},disc56={250,146,115,115},disc64={0,146,131,131},disc70={146,0,143,143},disc8={262,278,19,19},intercept={240,278,21,21},ping0={62,278,25,25},ping1={88,278,25,25},ping2={114,278,25,25},ping3={140,278,25,25},ping4={166,278,25,25},ping5={192,278,25,25},reticle={366,146,52,52},ring13={0,278,31,31},ring21={419,146,47,47},ring56={132,146,117,117},ring64={290,0,133,133},ring70={0,0,145,145},ring8={218,278,21,21}}
Sprites.RECTS=RECTS
-- the ring / disc radii baked into the sheet (anything else takes the SAM ring scaled)
Sprites.RADII={[8]=true,[13]=true,[21]=true,[56]=true,[70]=true}
-- shows sprite `name` on an ImageLabel (only writes what changed)
function Sprites.bind(image: ImageLabel,name: string)
    local r=RECTS[name];if not r then return end
    if image.Image~=Sprites.SHEET then image.Image=Sprites.SHEET end
    local offset,size=Vector2.new(r[1],r[2]),Vector2.new(r[3],r[4])
    if image.ImageRectOffset~=offset then image.ImageRectOffset=offset end
    if image.ImageRectSize~=size then image.ImageRectSize=size end
    if image.ResampleMode~=Enum.ResamplerMode.Pixelated then image.ResampleMode=Enum.ResamplerMode.Pixelated end
    if image.ScaleType~=Enum.ScaleType.Stretch then image.ScaleType=Enum.ScaleType.Stretch end
end
-- a ring of `radius` tiles (exact sprite when baked, else the SAM ring scaled): the sprite name and its size in tiles
function Sprites.ring(radius: number): (string,number)
    local R=math.floor(radius+.5)
    if Sprites.RADII[R] then return "ring"..R,2*R+5 end
    return "ring64",133*radius/64
end
function Sprites.disc(radius: number): (string,number)
    local R=math.floor(radius+.5)
    if Sprites.RADII[R] then return "disc"..R,2*R+3 end
    return "disc64",131*radius/64
end
return Sprites
