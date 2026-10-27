--!strict
--!native
-- Original-design RGB night presentation. The CPU operates on a small target;
-- Roblox stretches it over the sampled map rectangle. Colors/ambient retain
-- the existing light equations, while resolution and cadence are bounded.
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local Raster={}
Raster.MAX_AXIS=160
function Raster.size(width: number,height: number): (number,number)
    local scale=math.max(1,width/Raster.MAX_AXIS,height/Raster.MAX_AXIS)
    return math.max(1,math.min(Raster.MAX_AXIS,math.ceil(width/scale))),math.max(1,math.min(Raster.MAX_AXIS,math.ceil(height/scale)))
end
function Raster.add(bytes: buffer,at: number,r: number,g: number,b: number)
    buffer.writeu8(bytes,at,math.round(math.clamp(buffer.readu8(bytes,at)+r*255,0,255)))
    buffer.writeu8(bytes,at+1,math.round(math.clamp(buffer.readu8(bytes,at+1)+g*255,0,255)))
    buffer.writeu8(bytes,at+2,math.round(math.clamp(buffer.readu8(bytes,at+2)+b*255,0,255)))
end
-- One native call per light, retaining sample coordinates, ordered saturation
-- and byte rounding. The overlay previously interpreted this inner loop and
-- called into add once for every illuminated sample.
function Raster.stamp(bytes: buffer,width: number,height: number,screenWidth: number,screenHeight: number,
    zoom: number,centerX: number,centerY: number,radius: number,intensity: number,power: number,
    r: number,g: number,b: number)
    local minX,maxX=math.max(0,math.floor((centerX-radius*zoom)*width/screenWidth)),math.min(width-1,math.ceil((centerX+radius*zoom)*width/screenWidth))
    local minY,maxY=math.max(0,math.floor((centerY-radius*zoom)*height/screenHeight)),math.min(height-1,math.ceil((centerY+radius*zoom)*height/screenHeight))
    for yy=minY,maxY do for xx=minX,maxX do
        local at=(yy*width+xx)*4
        if bit32.band(buffer.readu32(bytes,at),16777215)==16777215 then continue end
        local distance=math.sqrt(((xx+.5)*screenWidth/width-centerX)^2+((yy+.5)*screenHeight/height-centerY)^2)/zoom
        local brightness=if distance>radius then 0 else (1-distance/radius)^power*intensity
        Raster.add(bytes,at,r*brightness,g*brightness,b*brightness)
    end end
end
function Raster.blend(original: buffer,blurred: buffer,scale: number)
    for at=0,buffer.len(blurred)-1 do
        buffer.writeu8(blurred,at,math.round(buffer.readu8(original,at)*(1-scale)+buffer.readu8(blurred,at)*scale))
    end
end
-- Keep the original fallout sample positions, source color conversion and
-- ordered byte additions, while executing the viewport walk in one native call.
function Raster.fallout(renderer: any,screenWidth: number,screenHeight: number,zoom: number,offset: Vector2,
    width: number,height: number,stateTick: number,bytes: buffer)
    local map=renderer.map;local settings=renderer.graphics
    local tick=renderer.falloutTicks or stateTick
    for yy=0,height-1 do for xx=0,width-1 do
        local x,y=math.floor(((xx+.5)*screenWidth/width-offset.X)/zoom),math.floor(((yy+.5)*screenHeight/height-offset.Y)/zoom)
        if x>=0 and y>=0 and x<map.width and y<map.height then
            local id=y*map.width+x+1
            if renderer.fallout[id]then
                local color=GraphicsMath.falloutLight(x,y,(renderer.falloutHeat[id]or 0)/255,tick,(renderer.displayOwners[id]or 0)>0,settings)
                Raster.add(bytes,(yy*width+xx)*4,color.R,color.G,color.B)
            end
        end
    end end
end
function Raster.compose(renderer: any,screenWidth: number,screenHeight: number,zoom: number,offset: Vector2,
    width: number,height: number,light: buffer,output: buffer)
    local map=renderer.map;local settings=renderer.graphics
    local ambient=settings.lighting.ambient
    local background=Color3.fromHex(settings.terrain.backgroundColor)
    local backgroundWord=math.round(background.R*255)+math.round(background.G*255)*256+math.round(background.B*255)*65536
    for yy=0,height-1 do for xx=0,width-1 do
        local screenX,screenY=(xx+.5)*screenWidth/width,(yy+.5)*screenHeight/height
        local x,y=math.floor((screenX-offset.X)/zoom),math.floor((screenY-offset.Y)/zoom)
        local scene=backgroundWord
        local at=(yy*width+xx)*4
        if x>=0 and y>=0 and x<map.width and y<map.height then
            local id=y*map.width+x+1;local owner=renderer.displayOwners[id]
            local cached=renderer.borderCache[id]
            local highlighted=if settings.passEnabled.borderCompute then owner==renderer.highlighted else cached and cached.highlighted
            if settings.passEnabled.borderStamp and owner>0 and cached and (if highlighted then cached[2] else cached[1]) then
                buffer.writeu32(output,at,0);continue
            end
            local chunk=renderer.chunks[math.floor(y/1024)*renderer.columns+math.floor(x/1024)+1]
            scene=buffer.readu32(chunk.pixels,((y-chunk.y)*chunk.width+x-chunk.x)*4)
        end
        for channel=0,2 do
            local value=bit32.band(bit32.rshift(scene,channel*8),255)
            local brightness=math.min(ambient+buffer.readu8(light,at+channel)/255*(1-ambient),1.2)
            buffer.writeu8(output,at+channel,math.round(math.clamp(value*brightness,0,255)))
        end
        buffer.writeu8(output,at+3,255)
    end end
end
return table.freeze(Raster)
