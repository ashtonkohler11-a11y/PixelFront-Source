--!strict
-- PF016 Aurora card (Ashton: retire the moving big star that "looks like transparent
-- boxes"; animated gradients, idle animations, a themed button). Geometry is authored by
-- tools/atlas/author-pf016-shop-vfx (Scale inside PF - 3's card); this module binds
-- content and animates: flowing aurora ribbons, twinkling stars, an occasional shooting
-- star, the crystal-star emblem (glow pulse, orbiting glints), drifting edge sparkles,
-- the rotating prismatic border, an icy shimmer on the Robux button and, when it is
-- pressed, the crystal press (v3, as clear as the Forge lava pour): an icy flash sweeps
-- the button, shockwave rings and a ring of crystal shards and glints burst past its
-- edges onto the card, and the star emblem answers with a glow pulse. The detail drawer
-- keeps its showcase (rays retired).
local PortraitPresets=require(script.Parent.AvatarPortraitPresets)
local Typography=require(game.ReplicatedStorage.Shared.PixelFrontTypography)
local Art=require(script.Parent.AtlasCommerceArt)
local AvatarPortrait=require(script.Parent.AvatarPortrait)
local M=require(script.Parent.ShopVfxMath)
local Runtime=require(script.Parent.ShopPackRuntime)
local Presentation={};Presentation.__index=Presentation
Presentation.Version="PF017A-2026-10-06-v1"
local WHITE=Color3.new(1,1,1)
local function drawDetail(scene: Frame,border: UIStroke,position: UDim2,time: number)
    local gradient=border:FindFirstChild("AuroraGradient");if gradient and gradient:IsA("UIGradient") then gradient.Rotation=(time*22)%360 end
    local emblem=scene:FindFirstChild("Emblem");if emblem and emblem:IsA("GuiObject") then emblem.Position=position+UDim2.fromOffset(0,math.sin(time*.85)*3) end
    local particles=scene:FindFirstChild("Particles")
    if particles then
        for _,particle in particles:GetChildren() do
            if not particle:IsA("Frame") then continue end
            local phase=particle:GetAttribute("Phase") or 0
            particle.Position=UDim2.fromScale(particle:GetAttribute("BaseX") or .5,(particle:GetAttribute("BaseY") or .5)-math.sin(time*.22+phase)*.028)
            particle.BackgroundTransparency=.38+(math.sin(time*1.1+phase)+1)*.25
        end
    end
end
function Presentation.installed(card: Instance): boolean
    local scene=card:FindFirstChild("Aurora");local back=card:FindFirstChild("AuroraBack")
    local front=scene and scene:FindFirstChild("Front")
    return back~=nil and front~=nil and back:GetAttribute("PF016Owner")=="PF016Shop" and front:GetAttribute("PF016Owner")=="PF016Shop"
end
function Presentation.new(shop: Frame,context: any): any
    local card=shop.Scroll.Offers.Pro
    local scene=assert(card:FindFirstChild("Aurora"),"Author the Aurora commerce presentation first")
    local self=setmetatable({shop=shop,card=card,scene=scene,context=context,destroyed=false,sampleProfiles={},detailClock=0,pressDirty=true},Presentation)
    local sampleIdentity=PortraitPresets.sampleIdentity({Flag="flag_aurora",Crown="crown_aurora",Banner="banner_aurora",Frame="frame_aurora"})
    -- Detail drawer (shop.Detail): unchanged content, old showcase motion minus the rays.
    self.showcase=shop.Detail:FindFirstChild("AuroraShowcase")
    if shop.Detail:FindFirstChild("AuroraProfile") then
        Art.bindProfile(shop.Detail.AuroraProfile,sampleIdentity);table.insert(self.sampleProfiles,shop.Detail.AuroraProfile)
    end
    local contents=shop.Detail:FindFirstChild("AuroraContents")
    if contents then for _,slot in contents:GetChildren() do if slot:IsA("Frame") and slot:FindFirstChild("Art") then Art.bindItem(slot.Art,slot:GetAttribute("CosmeticId")) end end end
    self.installedPF016=Presentation.installed(card)
    local front=if self.installedPF016 then scene.Front else scene
    self.front=front
    Typography.applyTree(front);Typography.apply(card.Title,"Heading")
    local profile=if self.installedPF016 then front.Preview.Profile else scene:FindFirstChild("Profile")
    if profile then Art.bindProfile(profile,sampleIdentity);table.insert(self.sampleProfiles,profile) end
    -- PF017 labelled contents: each tile's plate art binds the real cosmetic.
    self.samples={}
    local contents=if self.installedPF016 then front:FindFirstChild("Contents") else nil
    if contents then for _,tile in contents:GetChildren() do
        local art=tile:IsA("Frame") and tile:FindFirstChild("Plate") and tile.Plate:FindFirstChild("Art")
        if not art or not art:IsA("ImageLabel") then continue end
        Art.bindItem(art,art:GetAttribute("CosmeticId"))
        -- The frame cosmetic frames the sample portrait so it never reads as a blank slot.
        local sample=art:FindFirstChild("Sample")
        if sample and sample:IsA("ViewportFrame") then AvatarPortrait.bind(sample,AvatarPortrait.subject(sampleIdentity));table.insert(self.samples,sample) end
    end end
    if self.installedPF016 then
        local back=card.AuroraBack
        local buy=card.Purchase:FindFirstChild("AuroraBuy");self.buy=buy
        local emblem=front.StarEmblem
        local n={ribbons={},stars={},edge={},glints={},border=card.Border:FindFirstChild("AuroraGradient"),shooting=back.Shooting,
            bob=emblem.Bob,halo=emblem.Halo,flare=emblem:FindFirstChild("Flare")}
        n.haloSize=n.halo.Size;if n.flare then n.flareSize=n.flare.Size end
        for index=1,3 do local r=back.Sky["Ribbon"..index];table.insert(n.ribbons,{node=r,hue=r.Hue,y=r.Position.Y.Scale,alpha=r.ImageTransparency}) end
        for _,star in back.Stars:GetChildren() do
            if star:IsA("ImageLabel") then table.insert(n.stars,{node=star,seed=star:GetAttribute("Seed") or 1,size=star.Size}) end
        end
        for _,s in front.Edge:GetChildren() do
            if s:IsA("ImageLabel") then table.insert(n.edge,{node=s,seed=s:GetAttribute("Seed") or 1,x=s:GetAttribute("BaseX") or 0,y=s:GetAttribute("BaseY") or 0,size=s.Size}) end
        end
        for index=1,3 do table.insert(n.glints,emblem.Glints["Glint"..index]) end
        if buy then
            n.sweep=buy.Shimmer.Sweep;n.tone=buy.Base.Tone;n.buyBase=buy.Base;n.locked=buy.Locked;n.burstFrame=buy.Burst;n.burst={};n.shards={};n.rings={}
            n.price=buy:FindFirstChild("PackPrice")
            n.rim=buy.Base.Rim;n.rimThickness=n.rim.Thickness;n.rimAlpha=n.rim.Transparency;n.rimColor=n.rim.Color
            for index=1,10 do local p=buy.Burst["P"..index];table.insert(n.burst,{node=p,size=p.Size}) end
            -- v3 crystal press pools (absent on a v2-authored card: the glints still play).
            n.frost=buy:FindFirstChild("Frost");n.flash=buy:FindFirstChild("Flash");n.band=n.flash and n.flash:FindFirstChild("Band")
            local shards=buy:FindFirstChild("Shards")
            if shards then for index=1,12 do local s=shards["S"..index];table.insert(n.shards,{node=s,size=s.Size}) end end
            local rings=buy:FindFirstChild("Rings")
            if rings then for index=1,2 do local r=rings["Ring"..index];table.insert(n.rings,{node=r,stroke=r.Edge,thickness=r.Edge.Thickness}) end end
        end
        self.nodes=n
    end
    local roots={}
    if self.installedPF016 then table.insert(roots,card.AuroraBack) end
    self.runtime=Runtime.new(card,front,context.menuRoot or shop.Parent,context,function(clock,state) self:draw(clock,state) end,roots)
    if self.showcase then
        self.detailEmblem=self.showcase.Composition:FindFirstChild("Emblem")
        self.detailPosition=if self.detailEmblem then (self.detailEmblem :: GuiObject).Position else UDim2.new()
        self.detailRuntime=Runtime.new(self.showcase,self.showcase.Composition,context.menuRoot or shop.Parent,context,function(clock)
            drawDetail(self.showcase.Composition,self.showcase.Border,self.detailPosition,clock)
        end)
    end
    return self
end
function Presentation:draw(t: number,state: any)
    if self.destroyed or not self.installedPF016 then return end
    local n=self.nodes
    local hot=if state.hot then 1 else 0
    -- The press plays only on a truly buyable button (disabled presses get the clunk).
    local age=state.pressAge
    local pressing=age~=nil and state.enabled
    local answer=if pressing then M.answer(age) else 0
    if n.border then n.border.Rotation=(t*(40+30*hot))%360;n.border.Offset=Vector2.new(math.sin(t*.7)*.15,0) end
    for index,ribbon in n.ribbons do
        ribbon.hue.Offset=Vector2.new(M.flow(t,.045+index*.012,index*.37),0)
        ribbon.node.Position=UDim2.fromScale(.5+math.sin(t*.16+index*1.7)*.06,ribbon.y+math.sin(t*.23+index)*.015)
        ribbon.node.ImageTransparency=ribbon.alpha+.14*(1-M.breathe(t,5+index,index*.2))
    end
    for _,star in n.stars do
        local alpha,scale=M.twinkle(t,star.seed)
        star.node.ImageTransparency=alpha
        star.node.Size=UDim2.fromScale(star.size.X.Scale*scale,star.size.Y.Scale*scale)
        star.node.Rotation=(t*12+star.seed*9)%90
    end
    local active,x,y,alpha,rotation=M.shooting(t,7)
    n.shooting.Visible=active
    if active then n.shooting.Position=UDim2.fromScale(x,y);n.shooting.ImageTransparency=alpha;n.shooting.Rotation=rotation end
    -- Emblem: idle bob and halo breath; the press answer swells the halo, pops the crystal
    -- (scaled about its centre) and flashes a flare over it.
    local pop=.08*answer
    n.bob.Size=UDim2.fromScale(1+pop,1+pop);n.bob.Position=UDim2.fromScale(-pop/2,math.sin(t*.9)*.015-pop/2)
    local glow=M.breathe(t,3)
    n.halo.ImageTransparency=math.max(0,.22+.35*(1-glow)-.08*hot-.4*answer)
    local swell=1+.08*glow+.3*answer
    n.halo.Size=UDim2.fromScale(n.haloSize.X.Scale*swell,n.haloSize.Y.Scale*swell)
    if n.flare then
        n.flare.Visible=answer>.01
        if answer>.01 then
            -- A translucent pulse, never a whiteout: the crystal stays readable through it.
            local scale=.35+.65*answer
            n.flare.Size=UDim2.fromScale(n.flareSize.X.Scale*scale,n.flareSize.Y.Scale*scale);n.flare.ImageTransparency=1-.7*answer;n.flare.Rotation=answer*45
        end
    end
    for index,glint in n.glints do
        local gx,gy,ga=M.orbit(t,index,#n.glints,.9)
        glint.Position=UDim2.fromScale(.5+gx,.5+gy);glint.ImageTransparency=ga*(1-.8*answer);glint.Rotation=(t*40)%360
    end
    for _,s in n.edge do
        local a,scale=M.twinkle(t*.8,s.seed)
        s.node.ImageTransparency=a
        s.node.Position=UDim2.fromScale(s.x+math.sin(t*.6+s.seed)*.012,s.y+math.cos(t*.5+s.seed)*.02)
        s.node.Size=UDim2.fromScale(s.size.X.Scale*scale,s.size.Y.Scale*scale)
    end
    if self.buy then self:drawButton(t,state,pressing) end
end
function Presentation:drawButton(t: number,state: any,pressing: boolean)
    local n=self.nodes
    local age=state.pressAge
    if n.price then
        local label,live=Runtime.priceLabel(state)
        if n.price.Text~=label then n.price.Text=label end
        n.price.TextTransparency=if live and state.enabled then 0 elseif live then .3 else .15
    end
    n.locked.Visible=not state.enabled
    -- The idle shimmer parks while the press flash owns the button.
    local idle=state.enabled and not (pressing and age<.7)
    n.sweep.Offset=Vector2.new(if idle then M.sweep(t,if state.hot then 1.6 else 2.8,.7) else -1.2,0)
    n.tone.Offset=Vector2.new(0,math.sin(t*.8)*.08)
    local clunk=if age~=nil and not state.enabled then math.sin(math.min(age,.3)*60)*(1-math.min(age/.3,1))*.012 else 0
    n.buyBase.Position=UDim2.fromScale(clunk,0)
    -- Pools are hidden once after a press and then skipped until the next one.
    if not pressing and not self.pressDirty then return end
    self.pressDirty=pressing
    -- Icy flash: band sweep over a short whiteout, rim flare.
    local band,frost,rim=-1.2,1,0
    if pressing then band,frost,rim=M.flash(age) end
    if n.flash then n.flash.Visible=pressing and age<.4;if n.band then n.band.Offset=Vector2.new(band,0) end end
    if n.frost then n.frost.Visible=frost<1;n.frost.BackgroundTransparency=frost end
    n.rim.Thickness=n.rimThickness*(1+1.4*rim);n.rim.Transparency=n.rimAlpha*(1-rim);n.rim.Color=n.rimColor:Lerp(WHITE,rim)
    for index,ring in n.rings do
        local grow,fade,visible=0,1,false
        if pressing then grow,fade,visible=M.ring(age,(index-1)*.09) end -- (an if-expression would yield one value)
        ring.node.Visible=visible
        if visible then
            -- Rings grow upward onto the card (their bottom edge stays near the button's).
            ring.node.Size=UDim2.fromScale(1+.45*grow,1+1.1*grow);ring.node.Position=UDim2.fromScale(.5,.5-.4*grow)
            ring.stroke.Transparency=fade;ring.stroke.Thickness=ring.thickness*(1-.6*grow)
        end
    end
    -- Shards fly past the button edges, leaning up and left onto the card; each one
    -- points along its on-screen heading (the button is wide, so aim from pixels).
    local size=n.burstFrame.AbsoluteSize
    for index,s in n.shards do
        local dx,dy,fade,scale,spin,visible=0,0,1,1,0,false
        if pressing then dx,dy,fade,scale,spin,visible=M.shard(age,index,#n.shards,61) end
        s.node.Visible=visible
        if visible then
            local x,y=M.crystalReach(dx,dy)
            s.node.Position=UDim2.fromScale(.5+x,.5+y);s.node.ImageTransparency=fade
            s.node.Size=UDim2.fromScale(s.size.X.Scale*scale,s.size.Y.Scale*scale)
            s.node.Rotation=math.deg(math.atan2(y*size.Y,x*size.X))+spin
        end
    end
    for index,p in n.burst do
        local dx,dy,fade,scale,visible=0,0,1,0,false
        if pressing then dx,dy,fade,scale,visible=M.glint(age,index,#n.burst,23) end
        p.node.Visible=visible
        if visible then
            local x,y=M.crystalReach(dx,dy)
            p.node.Position=UDim2.fromScale(.5+x,.5+y);p.node.ImageTransparency=fade
            p.node.Size=UDim2.fromScale(p.size.X.Scale*scale,p.size.Y.Scale*scale);p.node.Rotation=(age*300+index*36)%360
        end
    end
end
function Presentation:setVisible(value: boolean)
    if self.destroyed then return end
    self.runtime:setVisible(value);if self.detailRuntime then self.detailRuntime:setVisible(value) end
end
function Presentation:refresh() if not self.destroyed then self.runtime:refreshState();self.runtime:sync() end end
-- PF016: internals are authored at Scale; the page's measured layout is no longer needed.
function Presentation:layout(_offerHeight: number,_landscapePhone: boolean?,_width: number?) end
function Presentation:destroy()
    if self.destroyed then return end
    self.destroyed=true
    self.runtime:destroy();if self.detailRuntime then self.detailRuntime:destroy() end
    for _,profile in self.sampleProfiles do Art.unbindProfile(profile) end
    for _,sample in self.samples or {} do AvatarPortrait.unbind(sample) end
end
return Presentation
