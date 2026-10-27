--!strict
--!native
-- Screen-pixel rasterization of original shockwave.frag.glsl in native UI images.
local Assets=game:GetService("AssetService")
local Math=require(script.Parent.NukeExplosionMath)
local Performance=require(game:GetService("ReplicatedStorage").Shared.Performance)
local Renderer={};Renderer.__index=Renderer
-- The native CPU shader previously evaluated every screen pixel (millions at
-- close zoom). Presentation is now a bounded soft-effect texture, upscaled by
-- the GPU. Simulation/explosion radius and lifetime are unchanged.
local RESOLUTION=128
function Renderer.new(parent: Frame,template: ImageLabel,zIndex: number?): any return setmetatable({parent=parent,template=template,chunks={},zIndex=zIndex or 16,resolution=RESOLUTION},Renderer)end
function Renderer:setBudget(resolution: number)self.resolution=math.clamp(math.floor(resolution),32,RESOLUTION)end
function Renderer:clear()for _,chunk in self.chunks do chunk.ui.Visible=false end end
function Renderer:destroy()for _,chunk in self.chunks do chunk.ui:Destroy();chunk.image:Destroy()end;table.clear(self.chunks)end
function Renderer:draw(sw: any,x: number,y: number,radius: number,alpha: number,time: number,width: number,zoom: number,viewport: Frame,offset: Vector2,pixel: any?)
    self:clear();local extent=radius*zoom;if extent<=0 then return end
    local cx,cy=(x+.5)*zoom+offset.X,(y+.5)*zoom+offset.Y;local size=viewport.AbsoluteSize
    local left,right=math.max(0,math.floor(cx-extent)),math.min(math.ceil(size.X),math.ceil(cx+extent))
    local top,bottom=math.max(0,math.floor(cy-extent)),math.min(math.ceil(size.Y),math.ceil(cy+extent))
    if left>=right or top>=bottom then return end
    local extentX,extentY=right-left,bottom-top
    local step=math.max(1,extentX/self.resolution,extentY/self.resolution)
    local w,h=math.min(RESOLUTION,math.ceil(extentX/step)),math.min(RESOLUTION,math.ceil(extentY/step))
    local chunk=self.chunks.bounded
        if not chunk then
            local image=assert(Assets:CreateEditableImage({Size=Vector2.new(RESOLUTION,RESOLUTION)}),"Shockwave image allocation")
            local ui=self.template:Clone();ui.AnchorPoint=Vector2.zero;ui.ImageContent=Content.fromObject(image);ui.ImageColor3=Color3.new(1,1,1);ui.ImageTransparency=0;ui.ZIndex=self.zIndex;ui.ImageRectOffset=Vector2.zero;ui.Parent=self.parent
            chunk={ui=ui,image=image,bytes=buffer.create(RESOLUTION*RESOLUTION*4),width=RESOLUTION,height=RESOLUTION};self.chunks.bounded=chunk
        end
        buffer.fill(chunk.bytes,0,0)
        local stepX,stepY=extentX/w,extentY/h
        Math.raster(chunk.bytes,RESOLUTION,w,h,left,top,stepX,stepY,cx,cy,extent,sw,radius,alpha,time,width,pixel)
        chunk.image:WritePixelsBuffer(Vector2.zero,Vector2.new(RESOLUTION,RESOLUTION),chunk.bytes)
        chunk.ui.ImageRectSize=Vector2.new(w,h);chunk.ui.Position=UDim2.fromOffset(left-offset.X,top-offset.Y);chunk.ui.Size=UDim2.fromOffset(extentX,extentY);chunk.ui.Visible=true
        Performance.count("fx.shadedPixels",w*h);Performance.count("fx.uploadBytes",RESOLUTION*RESOLUTION*4)
end
return Renderer
