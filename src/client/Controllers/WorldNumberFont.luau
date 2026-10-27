--!strict
-- WorldTextPass attack label shaping and original Overpass MSDF, pinned93a136a1.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local Raster=require(script.Parent.StructureLevelFont)
local Data=require(script.Parent.StructureLevelFontData)
local Font={};Font.__index=Font
function Font.new(): any return setmetatable({images={},sources={}},Font) end
function Font.layout(text: string): {any}
    local scale=17/Data.fontSize;local cursors={};local advance=0;local last=nil
    for index=1,math.min(#text,32) do
        local char=string.sub(text,index,index);local glyph=Data.metrics[char];assert(glyph,"Unexpected world-number glyph")
        cursors[index]=advance;local kern=0
        if last then for _,pair in Data.kernings do if pair.first==string.byte(last) and pair.second==string.byte(char) then kern=pair.amount;break end end end
        advance+=glyph.xadvance+kern;last=char
    end
    local len=#cursors;if len==0 then return {} end
    local first,final=Data.metrics[string.sub(text,1,1)],Data.metrics[string.sub(text,len,len)]
    local center=(first.xoffset+cursors[len]+final.xoffset+final.width)*.5;local result={}
    for index=1,len do local char=string.sub(text,index,index);local glyph=Data.metrics[char]
        table.insert(result,{char=char,x=(cursors[index]-center+glyph.xoffset)*scale,y=(-Data.base*.5+glyph.yoffset)*scale,width=glyph.width*scale,height=glyph.height*scale})
    end
    return result
end
function Font:bind(ui: ImageLabel,char: string,incoming: boolean)
    local key=char..tostring(incoming);local image=self.images[key]
    if not image then
        local glyph=Data.metrics[char];local source=self.sources[char]
        if not source then local pixels,w,h=Icons.pixels(glyph.source);source={pixels=pixels,width=w,height=h};self.sources[char]=source end
        local pixels,w,h=Raster.raster(source.pixels,source.width,source.height,glyph,17/Data.fontSize,1.2,if incoming then Color3.fromRGB(248,113,113) else Color3.fromRGB(63,169,245),true)
        image=assert(AssetService:CreateEditableImage({Size=Vector2.new(w,h)}),"Unable to render original Overpass attack label")
        image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),pixels);self.images[key]=image
    end
    ui.ImageContent=Content.fromObject(image);ui.ImageRectOffset=Vector2.zero;ui.ImageRectSize=Vector2.zero
end
function Font:dispose() for _,image in self.images do image:Destroy() end;self.images={};self.sources={} end
return Font
