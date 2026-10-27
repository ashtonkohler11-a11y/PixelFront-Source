--!strict
-- Pinned WorldTextPass and world-text shaders. Uses the original Overpass Bold
-- MSDF bytes/metrics, not a substitute native typeface. Raster only on zoom change.
local AssetService=game:GetService("AssetService")
local HttpService=game:GetService("HttpService")
local Icons=require(script.Parent.ReferenceIcons)
local StockFxMath=require(script.Parent.StockFxMath)
local Renderer={}
Renderer.__index=Renderer
local CAPACITY=256 -- 20x maximum map zoom gives <= 256 pixels per source glyph.
local function put(v: any,key: string,value: any) if v[key]~=value then v[key]=value end end
function Renderer.formatGold(gold: number): string
    local function fixedOne(value: number,suffix: string): string
        -- JS toFixed rounds an exact half upward; C printf used by Luau rounds
        -- ties to even. Keep the binary fraction (2.55 is below its decimal
        -- midpoint), so multiplying the whole number cannot round it to a tie.
        local whole=math.floor(value)
        local tenth=math.floor((value-whole)*10+.5)
        return string.format("%.0f.%d",whole+math.floor(tenth/10),tenth%10)..suffix
    end
    if gold>=1000000 then return fixedOne(gold/1000000,"M") end
    if gold>=1000 then return fixedOne(gold/1000,"K") end
    return tostring(gold)
end
function Renderer.popup(gold: number,tile: number,width: number,elapsed: number): any
    return {text=(if gold>=0 then "+ " else "- ")..Renderer.formatGold(math.abs(gold)),
        x=(tile-1)%width+.5,y=math.floor((tile-1)/width)+.5-3-elapsed*3,
        alpha=math.max(0,1-elapsed/1.5)}
end
function Renderer.new(world: Frame,templates: Folder)
    local data=game:GetService("ReplicatedStorage").OpenFrontIcons.BonusMSDF
    local pixels,width,height=Icons.pixels("BonusMSDF")
    local self=setmetatable({world=world,parent=world:WaitForChild("GoldBonuses"),template=templates:WaitForChild("GoldBonus"),
        glyphTemplate=templates:WaitForChild("GoldBonusGlyph"),metrics=HttpService:JSONDecode(data:GetAttribute("Metrics")),
        pixels=pixels,width=width,height=height,active={},free={},glyphs={},state=nil},Renderer)
    local ok,failure=pcall(function()
        for ch,g in self.metrics.glyphs do if g.width>0 and g.height>0 then
            local image=assert(AssetService:CreateEditableImage({Size=Vector2.new(CAPACITY,CAPACITY)}),"Image memory exhausted: gold glyph")
            self.glyphs[ch]={image=image,content=Content.fromObject(image)}
        end end
    end)
    if not ok then self:destroy();error(failure) end
    return self
end
function Renderer:reset()
    for _,r in self.active do r.ui.Visible=false;table.insert(self.free,r) end
    self.active={};self.cursor=nil;self.state=nil
end
function Renderer:destroy()
    for _,g in self.glyphs do g.image:Destroy() end
    self.glyphs={}
    for _,r in self.active do r.ui:Destroy() end
    for _,r in self.free do r.ui:Destroy() end
    self.active={};self.free={}
end
function Renderer:update(state: any): any
    self.state=state
    local cursor=math.max(self.cursor or 0,state.bonusEventCursor or 0)
    local latest=nil
    if self.cursor~=nil then
        for _,event in state.bonusEvents or {} do
            if event.id<=self.cursor or event.owner~=1 or event.gold==0 then continue end
            local r=table.remove(self.free)
            if not r then local ui=self.template:Clone();ui.Parent=self.parent;r={ui=ui,labels={}} end
            r.event=event;r.conquest=false;r.start=os.clock();r.text=Renderer.popup(event.gold,event.tileId,state.map.width,0).text
            r.ui:SetAttribute("EventId",event.id);r.ui:SetAttribute("Gold",event.gold);r.ui:SetAttribute("TileId",event.tileId)
            table.insert(self.active,r)
            if event.gold>0 then latest=event end
        end
    end
    self.cursor=cursor
    return latest
end
function Renderer:applyConquestEvents(events: {any})
    local now=os.clock()
    for _,event in events do local age=(event.tickAge or 0)*.1;if age>=2.5 then continue end
        local r=table.remove(self.free);if not r then local ui=self.template:Clone();ui.Parent=self.parent;r={ui=ui,labels={}}end
        r.event=event;r.conquest=true;r.start=now-age;r.text="+ "..Renderer.formatGold(event.gold);table.insert(self.active,r)
    end
end
function Renderer:sample(x: number,y: number,channel: number): number
    local x0,y0=math.floor(x),math.floor(y);local dx,dy=x-x0,y-y0
    local function at(px: number,py: number): number
        return buffer.readu8(self.pixels,(math.clamp(py,0,self.height-1)*self.width+math.clamp(px,0,self.width-1))*4+channel)/255
    end
    return (at(x0,y0)*(1-dx)+at(x0+1,y0)*dx)*(1-dy)+(at(x0,y0+1)*(1-dx)+at(x0+1,y0+1)*dx)*dy
end
function Renderer:raster(ch: string,zoom: number): any
    local cache=self.glyphs[ch]
    if not cache or cache.zoom==zoom then return cache end
    local g=self.metrics.glyphs[ch]
    local scale=math.max(6*zoom,.15)/self.metrics.fontSize
    local w,h=math.max(1,math.ceil(g.width*scale)),math.max(1,math.ceil(g.height*scale))
    assert(w<=CAPACITY and h<=CAPACITY,"Gold glyph exceeds supported map zoom")
    local bytes=buffer.create(w*h*4)
    local screenRange=math.max(self.metrics.distanceRange*scale,1)
    local outline=math.min(2,math.max(screenRange*.5-1,0))
    local glowExtent=math.max(screenRange*.5-outline-.5,0)
    local left,weights={},{}
    for x=0,w-1 do
        -- Retain original atlas coordinates through floating-point arithmetic;
        -- relocate only the integer fetch. Compact coordinates can shift a
        -- sample across an 8-bit rounding boundary despite identical texels.
        local ax=g.sourceX+(x+.5)/w*g.width-.5;local integer=math.floor(ax)
        left[x+1]=(integer-g.sourceX+g.x)*4;weights[x+1]=ax-integer
    end
    local read=buffer.readu8;local pixels=self.pixels;local rowBytes=self.width*4
    -- The source subset retains a one-pixel border around each glyph, so
    -- bilinear samples are in bounds. Avoid repeated clamps and closures for
    -- each of twelve channel fetches at every screen pixel.
    for y=0,h-1 do
        local ay=g.sourceY+(y+.5)/h*g.height-.5;local iy=math.floor(ay);local dy=ay-iy;local vy=1-dy;local row=(iy-g.sourceY+g.y)*rowBytes
        for x=0,w-1 do
        local at=row+left[x+1];local dx=weights[x+1];local vx=1-dx
        local r=(read(pixels,at)/255*vx+read(pixels,at+4)/255*dx)*vy+(read(pixels,at+rowBytes)/255*vx+read(pixels,at+rowBytes+4)/255*dx)*dy
        local b=(read(pixels,at+1)/255*vx+read(pixels,at+5)/255*dx)*vy+(read(pixels,at+rowBytes+1)/255*vx+read(pixels,at+rowBytes+5)/255*dx)*dy
        local c=(read(pixels,at+2)/255*vx+read(pixels,at+6)/255*dx)*vy+(read(pixels,at+rowBytes+2)/255*vx+read(pixels,at+rowBytes+6)/255*dx)*dy
        local median=math.max(math.min(r,b),math.min(math.max(r,b),c))
        local distance=screenRange*(median-.5)
        local fill=math.clamp(distance+.5,0,1)
        local out=math.clamp(distance+outline+.5,0,1)
        local glow=if glowExtent>0 then math.clamp((distance+outline+glowExtent)/math.max(glowExtent,.0001),0,1)^2*.75 else 0
        local dest=(y*w+x)*4;local shade=math.round(fill*255)
        buffer.writeu8(bytes,dest,shade);buffer.writeu8(bytes,dest+1,shade);buffer.writeu8(bytes,dest+2,shade)
        buffer.writeu8(bytes,dest+3,math.round(math.max(out,glow)*255))
    end end
    cache.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),bytes)
    cache.zoom=zoom;cache.size=Vector2.new(w,h);cache.screenSize=Vector2.new(g.width*scale,g.height*scale)
    return cache
end
-- PF - 4 (Ashton: "subtle numbers"; at close zoom the source's 6-tile-tall glyphs reached ~48 px and sat over the HUD): the
-- text is TEXT_MIN..TEXT_MAX px tall whatever the zoom (a building icon label's size), and each popup lives LIFE seconds
-- (a conquest's CONQUEST_LIFE), fading out over its last FADE.
Renderer.TEXT_MIN,Renderer.TEXT_MAX,Renderer.LIFE,Renderer.CONQUEST_LIFE,Renderer.FADE=8,13,1,1.6,.35
function Renderer:draw(zoom: number,viewport: Frame)
    if not self.state then return end
    local now=os.clock()
    local textZoom=math.clamp(6*zoom,Renderer.TEXT_MIN,Renderer.TEXT_MAX)/6 -- the glyphs' zoom (raster + layout)
    for i=#self.active,1,-1 do
        local r=self.active[i];local elapsed=now-r.start
        local life=if r.conquest then Renderer.CONQUEST_LIFE else Renderer.LIFE
        if elapsed>=life then r.ui.Visible=false;table.insert(self.free,r);table.remove(self.active,i);continue end
        local p=if r.conquest then StockFxMath.conquestPopup(r.event.gold,r.event.x,r.event.y,elapsed)else Renderer.popup(r.event.gold,r.event.tileId,self.state.map.width,elapsed)
        local center=Vector2.new(p.x*zoom,p.y*zoom)
        -- the trade / train popup rises in screen pixels (12 px above its tile, then 14 px a second), not in tiles, so at a
        -- close zoom it stays by its building instead of climbing several building-heights toward the HUD
        if not r.conquest then
            local tile=r.event.tileId;local w=self.state.map.width
            center=Vector2.new(((tile-1)%w+.5)*zoom,(math.floor((tile-1)/w)+.5)*zoom-12-elapsed*14)
        end
        -- Source only culls by zoom. Let the authored viewport clip glyphs so
        -- long labels at maximum zoom never disappear before their last pixel.
        local show=zoom>=.3
        put(r.ui,"Visible",show)
        if not show then continue end
        put(r.ui,"Position",UDim2.fromOffset(center.X,center.Y))
        local glyphs=self.metrics.glyphs;local scale=math.max(6*textZoom,.15)/self.metrics.fontSize
        local alpha=p.alpha*math.clamp((life-elapsed)/Renderer.FADE,0,1)
        local count=math.min(#r.text,32);local cursors={};local cumulative=0
        for n=1,count do local g=glyphs[string.sub(r.text,n,n)];cursors[n]=cumulative;cumulative+=g.xadvance end
        -- WorldTextPass intentionally uses a zero kerning table.
        local first,last=glyphs[string.sub(r.text,1,1)],glyphs[string.sub(r.text,count,count)]
        local visualCenter=(first.xoffset+cursors[count]+last.xoffset+last.width)*.5
        for n=1,count do
            local ch=string.sub(r.text,n,n);local g=glyphs[ch];local cache=self:raster(ch,textZoom)
            local label=r.labels[n]
            if cache then
                if not label then label=self.glyphTemplate:Clone();label.Parent=r.ui;r.labels[n]=label end
                put(label,"Visible",true);put(label,"ImageContent",cache.content)
                put(label,"ImageRectSize",cache.size);put(label,"Size",UDim2.fromOffset(cache.screenSize.X,cache.screenSize.Y))
                put(label,"Position",UDim2.fromOffset((cursors[n]-visualCenter+g.xoffset)*scale,(-self.metrics.base*.5+g.yoffset)*scale))
                put(label,"ImageTransparency",1-alpha)
            elseif label then label.Visible=false end
        end
        for n,label in r.labels do if n>count then label.Visible=false end end
    end
end
return Renderer
