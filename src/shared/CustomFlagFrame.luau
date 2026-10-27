--!strict
-- PF020 G1 Flag Forge (PF - 3): a custom flag's frame, pure and shared, so the server's validation and
-- every render site agree (approved mockup docs/director/mockups/PF020/G1-flag-forge.png).
-- A frame is {asset, fit, zoom, x, y, backdrop}:
--   asset    the player's own Decal / Image asset id (Roblox has moderated it; display only, never edited)
--   fit      "Fill" (covers the flag), "Fit" (the whole image on the backdrop) or "Crop" (you frame it)
--   zoom     Crop only: 1..3 (1 = the Fill framing)
--   x, y     Crop only: -1..1 from the centre (a tap nudges 0.05)
--   backdrop 1..6: the colour behind Fit and through transparent pixels
-- The image is always the rbxthumb thumbnail, a square of known size (THUMB), so the crop is an
-- ImageRect on it; nothing reads the decal's real size (it is never known on the client).
local Frame={}
Frame.THUMB=420
Frame.ASPECT=3/2 -- every flag well draws 3:2 (60x40 shop, 72x48 banner, 22x14 map label)
Frame.FITS=table.freeze({"Fill","Fit","Crop"})
Frame.ZOOM=table.freeze({min=1,max=3})
Frame.NUDGE=.05
-- the six backdrop swatches (G1: black, white, navy, green, red, gold)
Frame.BACKDROPS=table.freeze({"#11141a","#f2f2f2","#1d3561","#2f7d45","#a52638","#e3c46e"})
Frame.SLOTS=3
local MAX_ASSET=9007199254740991
local fits={Fill=true,Fit=true,Crop=true}

function Frame.default(asset: number): any
    return {asset=asset,fit="Fill",zoom=1,x=0,y=0,backdrop=1}
end
-- An asset id from what a player typed: digits only, or nil.
function Frame.parseId(text: any): number?
    if type(text)=="number" then return if text>=1 and text<=MAX_ASSET and text%1==0 then text else nil end
    if type(text)~="string" then return nil end
    local digits=string.match(text,"^%s*(%d+)%s*$");if not digits or #digits>16 then return nil end
    local id=tonumber(digits)
    return if id and id>=1 and id<=MAX_ASSET then id else nil
end
local function round(value: number,step: number): number return math.floor(value/step+.5)*step end
local KEYS={asset=true,fit=true,zoom=true,x=true,y=true,backdrop=true}
-- A clean frame, or nil and why. Numbers are clamped and rounded so the stored record stays small.
-- Strict (a client's command): any other key, or a number of the wrong kind, rejects the frame.
function Frame.validate(frame: any,strict: boolean?): (any?,string?)
    if type(frame)~="table" then return nil,"frame" end
    if strict then
        for key in frame do if not KEYS[key] then return nil,"keys" end end
        if type(frame.asset)~="number" then return nil,"asset" end
        for _,key in {"zoom","x","y","backdrop"} do if type(frame[key])~="number" or frame[key]~=frame[key] then return nil,key end end
        if frame.backdrop%1~=0 or frame.backdrop<1 or frame.backdrop>#Frame.BACKDROPS then return nil,"backdrop" end
        if frame.zoom<Frame.ZOOM.min or frame.zoom>Frame.ZOOM.max or math.abs(frame.x)>1 or math.abs(frame.y)>1 then return nil,"range" end
    end
    local asset=Frame.parseId(frame.asset);if not asset then return nil,"asset" end
    if not fits[frame.fit] then return nil,"fit" end
    local function number(value: any,lo: number,hi: number,fallback: number): number
        if type(value)~="number" or value~=value then return fallback end
        return math.clamp(value,lo,hi)
    end
    local backdrop=frame.backdrop
    if type(backdrop)~="number" or backdrop%1~=0 or backdrop<1 or backdrop>#Frame.BACKDROPS then backdrop=1 end
    return {asset=asset,fit=frame.fit,zoom=round(number(frame.zoom,Frame.ZOOM.min,Frame.ZOOM.max,1),.01),
        x=round(number(frame.x,-1,1,0),.01),y=round(number(frame.y,-1,1,0),.01),backdrop=backdrop},nil
end
function Frame.thumb(asset: number): string
    return string.format("rbxthumb://type=Asset&id=%d&w=%d&h=%d",asset,Frame.THUMB,Frame.THUMB)
end
-- What a flag well shows: the ImageRect on the thumbnail (offset, size) and whether the image is
-- letterboxed on the backdrop (Fit). `aspect` is the well's width / height (default 3:2).
function Frame.rect(frame: any,aspect: number?): (Vector2,Vector2,boolean)
    local a=aspect or Frame.ASPECT
    local T=Frame.THUMB
    if frame.fit=="Fit" then return Vector2.zero,Vector2.new(T,T),true end
    -- Fill: the largest box of the well's aspect inside the square, centred
    local w,h=if a>=1 then T else T*a,if a>=1 then T/a else T
    local zoom=if frame.fit=="Crop" then math.clamp(frame.zoom or 1,Frame.ZOOM.min,Frame.ZOOM.max) else 1
    w,h=w/zoom,h/zoom
    local x=if frame.fit=="Crop" then math.clamp(frame.x or 0,-1,1) else 0
    local y=if frame.fit=="Crop" then math.clamp(frame.y or 0,-1,1) else 0
    local cx,cy=T/2+x*(T-w)/2,T/2+y*(T-h)/2
    return Vector2.new(cx-w/2,cy-h/2),Vector2.new(w,h),false
end
-- The mockup's words for a position ("Centre", "Up 35%", "Left 20% · Down 10%").
function Frame.positionWords(frame: any): string
    local parts={}
    local y,x=math.floor(math.abs(frame.y or 0)*100+.5),math.floor(math.abs(frame.x or 0)*100+.5)
    if y>0 then table.insert(parts,(if (frame.y or 0)<0 then "Up " else "Down ")..y.."%") end
    if x>0 then table.insert(parts,(if (frame.x or 0)<0 then "Left " else "Right ")..x.."%") end
    return if #parts==0 then "Centre" else table.concat(parts," · ")
end
-- Compact text for a Player attribute (other players draw it): "asset;F|T|C;zoom;x;y;backdrop"
-- (F = Fill, T = Fit, C = Crop).
local TO_CODE={Fill="F",Fit="T",Crop="C"}
local FROM_CODE={F="Fill",T="Fit",C="Crop"}
function Frame.encode(frame: any): string
    local clean=assert(Frame.validate(frame),"invalid frame")
    return string.format("%d;%s;%.2f;%.2f;%.2f;%d",clean.asset,TO_CODE[clean.fit],clean.zoom,clean.x,clean.y,clean.backdrop)
end
function Frame.decode(text: any): any?
    if type(text)~="string" or #text>80 then return nil end
    local asset,fit,zoom,x,y,backdrop=string.match(text,"^(%d+);([FTC]);([%d%.%-]+);([%d%.%-]+);([%d%.%-]+);(%d+)$")
    if not asset then return nil end
    return (Frame.validate({asset=tonumber(asset),fit=FROM_CODE[fit],zoom=tonumber(zoom),x=tonumber(x),y=tonumber(y),backdrop=tonumber(backdrop)}))
end
return table.freeze(Frame)
