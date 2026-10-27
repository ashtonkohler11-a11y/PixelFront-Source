--!strict
-- Original Overpass MSDF pixels + structure-level shaders, pinned 93a136a1.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local Data=require(script.Parent.StructureLevelFontData)
local Font={};Font.__index=Font
function Font.new(): any return setmetatable({sources={},images={},scale=nil},Font) end
local function sample(pixels: buffer,width: number,height: number,x: number,y: number,channel: number): number
    x=math.clamp(x,0,width-1);y=math.clamp(y,0,height-1);local x0,y0=math.floor(x),math.floor(y);local x1,y1=math.min(width-1,x0+1),math.min(height-1,y0+1);local fx,fy=x-x0,y-y0
    local function at(xx: number,yy: number): number return buffer.readu8(pixels,(yy*width+xx)*4+channel)/255 end
    return (at(x0,y0)*(1-fx)+at(x1,y0)*fx)*(1-fy)+(at(x0,y1)*(1-fx)+at(x1,y1)*fx)*fy
end
function Font.raster(pixels: buffer,width: number,height: number,glyph: any,scale: number,outlineWidth: number,tint: Color3?,glow: boolean?): (buffer,number,number)
    local w,h=math.max(1,math.ceil(glyph.width*scale)),math.max(1,math.ceil(glyph.height*scale));local output=buffer.create(w*h*4)
    local range=math.max(Data.distanceRange*scale,1);local outline=math.min(outlineWidth,math.max(range*.5-1,0))
    for y=0,h-1 do for x=0,w-1 do
        local sx,sy=(x+.5)/w*glyph.width+.5,(y+.5)/h*glyph.height+.5
        local r,g,b=sample(pixels,width,height,sx,sy,0),sample(pixels,width,height,sx,sy,1),sample(pixels,width,height,sx,sy,2)
        local distance=range*(math.max(math.min(r,g),math.min(math.max(r,g),b))-.5)
        local fill=math.clamp(distance+.5,0,1);local alpha=math.clamp(distance+outline+.5,0,1);local at=(y*w+x)*4;local gray=math.floor(fill*255+.5)
        if glow then
            local extent=math.max(range*.5-outline-.5,0)
            local t=math.clamp((distance+outline+extent)/math.max(extent,.0001),0,1)
            alpha=math.max(alpha,if extent>0 then t*t*.75 else 0)
        end
        buffer.writeu8(output,at,if tint then math.floor(fill*tint.R*255+.5) else gray)
        buffer.writeu8(output,at+1,if tint then math.floor(fill*tint.G*255+.5) else gray)
        buffer.writeu8(output,at+2,if tint then math.floor(fill*tint.B*255+.5) else gray)
        buffer.writeu8(output,at+3,math.floor(alpha*255+.5))
    end end
    return output,w,h
end
function Font:prepare(scale: number,outline: number)
    if self.scale==scale and self.outline==outline then return end
    for _,image in self.images do image:Destroy() end;self.images={};self.scale=scale;self.outline=outline
end
function Font:bind(label: ImageLabel,digit: string)
    local image=self.images[digit]
    if not image then
        local glyph=Data.metrics[digit];local source=self.sources[digit]
        if not source then local pixels,w,h=Icons.pixels(glyph.source);source={pixels=pixels,width=w,height=h};self.sources[digit]=source end
        local pixels,w,h=Font.raster(source.pixels,source.width,source.height,glyph,self.scale,self.outline)
        image=assert(AssetService:CreateEditableImage({Size=Vector2.new(w,h)}),"Unable to render original Overpass level glyph");image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),pixels);self.images[digit]=image
    end
    label.ImageRectOffset=Vector2.zero;label.ImageRectSize=Vector2.zero;label.ImageContent=Content.fromObject(image)
end
function Font.layout(level: number,size: number,settings: any): {any}
    local full=tostring(level);local classic=settings.classicFont;local fontSize=if classic then 16 else Data.fontSize;local base=if classic then 16 else Data.base
    local scale=size*.5*settings.scale/fontSize;local advance=0;local cursors={}
    for index=1,#full do local digit=string.sub(full,index,index);cursors[index]=advance;advance+=if classic then 14 else Data.metrics[digit].xadvance end
    local first,last=string.sub(full,1,1),string.sub(full,-1)
    local left=if classic then 0 else Data.metrics[first].xoffset
    local right=cursors[#full]+(if classic then 16 else Data.metrics[last].xoffset+Data.metrics[last].width)
    local center=(left+right)/2;local result={}
    for index=1,math.min(#full,4) do
        local digit=string.sub(full,index,index);local g=if classic then {xoffset=0,yoffset=0,width=16,height=16,xadvance=14} else Data.metrics[digit]
        table.insert(result,{digit=digit,x=(cursors[index]-center+g.xoffset)*scale,y=-size*.5*(1+settings.offsetY)-scale*base*.6+(-base*.5+g.yoffset)*scale,width=g.width*scale,height=g.height*scale,scale=scale})
    end;return result
end
function Font:dispose() for _,image in self.images do image:Destroy() end;self.images={};self.sources={} end
return Font
