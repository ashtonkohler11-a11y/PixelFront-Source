--!strict
-- Zero-blur source box-shadow spread around one rounded lower-left corner.
-- Fixed 30px tile: inner24px at3,3, radius8. A9-slice stretches only straight
-- edges; fractional coverage preserves the exact ideal circle/rectangle geometry.
local Mask={}
Mask.size=30;Mask.center=Rect.new(11,11,19,19)
local function primitive(x: number,radius: number): number
    x=math.clamp(x,0,radius);return (x*math.sqrt(math.max(0,radius*radius-x*x))+radius*radius*math.asin(x/radius))/2
end
local function circleArea(x1: number,x2: number,y1: number,y2: number,radius: number): number
    x1=math.clamp(x1,0,radius);x2=math.clamp(x2,0,radius);y1=math.clamp(y1,0,radius);y2=math.clamp(y2,0,radius)
    if x2<=x1 or y2<=y1 then return 0 end
    local full=math.sqrt(math.max(0,radius*radius-y2*y2));local empty=math.sqrt(math.max(0,radius*radius-y1*y1))
    local stop=math.min(x2,full);local area=math.max(0,stop-x1)*(y2-y1)
    local low,high=math.max(x1,full),math.min(x2,empty)
    if high>low then area+=primitive(high,radius)-primitive(low,radius)-y1*(high-low)end;return area
end
local function shapeArea(x: number,y: number,spread: number): number
    local left,right=math.max(x,3-spread),math.min(x+1,27+spread);local top,bottom=math.max(y,3-spread),math.min(y+1,27+spread)
    if right<=left or bottom<=top then return 0 end
    local area=(right-left)*(bottom-top);local cutRight,cutTop=math.min(right,11),math.max(top,19)
    if cutRight>left and bottom>cutTop then
        area-=(cutRight-left)*(bottom-cutTop)
        area+=circleArea(11-cutRight,11-left,cutTop-19,bottom-19,8+spread)
    end;return area
end
function Mask.coverage(x: number,y: number,spread: number): number return math.clamp(shapeArea(x,y,spread)-shapeArea(x,y,0),0,1)end
local function inside(x: number,y: number,spread: number): boolean
    if x<3-spread or x>27+spread or y<3-spread or y>27+spread then return false end
    return x>=11 or y<=19 or (x-11)^2+(y-19)^2<=(8+spread)^2
end
function Mask.contains(x: number,y: number,spread: number): boolean return inside(x,y,spread)and not inside(x,y,0)end
function Mask.pixels(spread: number,bytes: buffer?): buffer
    bytes=bytes or buffer.create(30*30*4)
    for y=0,29 do for x=0,29 do local offset=(y*30+x)*4;buffer.writeu32(bytes,offset,0x00ffffff);buffer.writeu8(bytes,offset+3,math.floor(Mask.coverage(x,y,spread)*255+.5))end end;return bytes
end
return Mask
