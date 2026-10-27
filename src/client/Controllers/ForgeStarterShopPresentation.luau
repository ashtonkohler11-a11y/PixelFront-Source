--!strict
-- PF016/PF017-A Forge Starter card. Geometry is authored by
-- tools/atlas/author-pf016-shop-vfx (Scale inside PF - 3's card); this module only binds
-- content and animates. PF017 (Ashton: the emblem spark spray "looks vibecoded"): the
-- sparks and the lava cracks are gone. What remains is calm and intentional: warm light
-- flowing across the charcoal card, a breathing heat edge, the emblem's glow and bob, a
-- few embers rising from the emblem column, an idle molten shimmer on the Robux button
-- and the lava pour (rising fill, spark burst) when it is pressed. The button's
-- price label shows the truthful purchase state the page publishes.
local PortraitPresets=require(script.Parent.AvatarPortraitPresets)
local Typography=require(game.ReplicatedStorage.Shared.PixelFrontTypography)
local Art=require(script.Parent.AtlasCommerceArt)
local AvatarPortrait=require(script.Parent.AvatarPortrait)
local Frames=require(script.Parent.ForgeFrameAnimator)
local M=require(script.Parent.ShopVfxMath)
local Runtime=require(script.Parent.ShopPackRuntime)
local Presentation={};Presentation.__index=Presentation
Presentation.Version="PF017A-2026-10-06-v1"
-- Embers rise from the emblem column (card x .62-.97), not across the item labels.
local EMBER_X,EMBER_W,EMBER_Y=.62,.35,.6
-- nil until the PF016 Forge layers are authored (the page then shows the plain card).
function Presentation.installed(card: Instance): boolean
    local front,back=card:FindFirstChild("Forge"),card:FindFirstChild("ForgeBack")
    return front~=nil and back~=nil and front:GetAttribute("PF016Owner")=="PF016Shop" and back:GetAttribute("PF016Owner")=="PF016Shop"
end
function Presentation.new(shop: Frame,context: any): any?
    local card=shop.Scroll.Offers.Starter
    if not Presentation.installed(card) then return nil end
    local front,back=card.Forge,card.ForgeBack
    local buy=card.Purchase:FindFirstChild("ForgeBuy")
    local self=setmetatable({shop=shop,card=card,front=front,back=back,buy=buy,context=context,framePreviews={},samples={},destroyed=false},Presentation)
    Typography.applyTree(front)
    local identity=PortraitPresets.sampleIdentity({Flag="flag_forge",Frame="frame_forge"})
    local profile=front.Preview.Profile;self.profile=profile
    Art.bindProfile(profile,identity)
    -- Labelled contents: each tile's plate art binds the real cosmetic.
    for _,tile in front.Contents:GetChildren() do
        local art=tile:IsA("Frame") and tile:FindFirstChild("Plate") and tile.Plate:FindFirstChild("Art")
        if not art or not art:IsA("ImageLabel") then continue end
        local id=art:GetAttribute("CosmeticId");Art.bindItem(art,id)
        if id=="frame_forge" then table.insert(self.framePreviews,art) end
        -- The frame cosmetic frames the sample portrait so it never reads as a blank slot.
        local sample=art:FindFirstChild("Sample")
        if sample and sample:IsA("ViewportFrame") then AvatarPortrait.bind(sample,AvatarPortrait.subject(identity));table.insert(self.samples,sample) end
    end
    -- Node cache (no per-frame lookups).
    local n={molten=back.Molten.Flow,heat=back.Heat,heatFlow=back.Heat.Flow,embers={},emblemBob=front.Emblem.Bob,glow=front.Emblem.Glow}
    for _,ember in back.Embers:GetChildren() do
        if ember:IsA("ImageLabel") then table.insert(n.embers,{node=ember,seed=ember:GetAttribute("Seed") or 1,size=ember.Size}) end
    end
    n.glowSize=n.glow.Size
    if buy then
        n.buyBase=buy.Base;n.sweep=buy.Shimmer.Sweep;n.fill=buy.Fill;n.locked=buy.Locked;n.price=buy:FindFirstChild("PackPrice");n.burst={}
        for index=1,10 do table.insert(n.burst,buy.Burst["P"..index]) end
    end
    self.nodes=n
    self.runtime=Runtime.new(card,front,context.menuRoot or shop.Parent,context,function(clock,state) self:draw(clock,state) end,{back})
    return self
end
function Presentation:draw(t: number,state: any)
    if self.destroyed then return end
    local n=self.nodes
    local hot=if state.hot then 1 else 0
    n.molten.Offset=Vector2.new(M.flow(t,.06),0)
    n.heat.Transparency=.12+.45*(1-M.breathe(t,2.6))-.1*hot
    n.heatFlow.Rotation=(t*35)%360
    for _,ember in n.embers do
        local x,y,alpha,size=M.ember(t,ember.seed,1)
        local base=ember.size
        ember.node.Position=UDim2.fromScale(EMBER_X+x*EMBER_W,y*EMBER_Y);ember.node.ImageTransparency=alpha
        ember.node.Size=UDim2.fromScale(base.X.Scale*size,base.Y.Scale*size)
    end
    n.emblemBob.Position=UDim2.fromScale(0,math.sin(t*1.1)*.018)
    local glow=M.breathe(t,2.4)
    n.glow.ImageTransparency=.18+.32*(1-glow)-.1*hot
    n.glow.Size=UDim2.fromScale(n.glowSize.X.Scale*(1+.06*glow),n.glowSize.Y.Scale*(1+.06*glow))
    if self.buy then self:drawButton(t,state) end
end
function Presentation:drawButton(t: number,state: any)
    local n=self.nodes
    if n.price then
        local label,live=Runtime.priceLabel(state)
        if n.price.Text~=label then n.price.Text=label end
        n.price.TextTransparency=if live and state.enabled then 0 elseif live then .3 else .15
    end
    n.locked.Visible=not state.enabled
    n.sweep.Offset=Vector2.new(if state.enabled then M.sweep(t,if state.hot then 1.8 else 3.2) else -1.2,0)
    local age=state.pressAge
    local pouring=age~=nil and state.enabled
    local fill,fade,active=0,1,false
    if pouring then fill,fade,active=M.pour(age) end
    n.fill.Visible=active
    n.fill.Size=UDim2.fromScale(1,fill);n.fill.BackgroundTransparency=fade
    -- PF017: no drips. On A06 the button sits on the card's bottom edge and the Shop
    -- scroll clips right below it, so drips read as cut-off ticks; the rising fill and
    -- the burst carry the pour.
    for index,p in n.burst do
        local dx,dy,alpha,visible=0,0,1,false
        if pouring then dx,dy,alpha,visible=M.burst(age-.3,index,#n.burst,77,.5,.6) end
        p.Visible=visible
        if visible then p.Position=UDim2.fromScale(.5+dx*1.1,.5+dy*1.9);p.ImageTransparency=alpha*alpha;p.Rotation=math.deg(math.atan2(dy,dx)) end
    end
    -- A disabled press gets a short "clunk" instead of a pour (no fake purchase feel).
    local clunk=if age~=nil and not state.enabled then math.sin(math.min(age,.3)*60)*(1-math.min(age/.3,1))*.012 else 0
    n.buyBase.Position=UDim2.fromScale(clunk,0)
end
function Presentation:setVisible(value: boolean) if not self.destroyed then self.runtime:setVisible(value) end end
function Presentation:refresh() if not self.destroyed then self.runtime:refreshState();self.runtime:sync() end end
-- PF016: internals are authored at Scale; the page's measured layout is no longer needed.
function Presentation:layout(_offerHeight: number,_landscapePhone: boolean?,_width: number?) end
function Presentation:destroy()
    if self.destroyed then return end
    self.destroyed=true
    self.runtime:destroy()
    Art.unbindProfile(self.profile)
    for _,target in self.framePreviews do Frames.unbind(target) end;table.clear(self.framePreviews)
    for _,sample in self.samples do AvatarPortrait.unbind(sample) end
end
return Presentation
