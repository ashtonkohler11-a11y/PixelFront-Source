--!strict
-- PF019 Phase C (PF - 2): living art for the shop cards. M6 Forge skin, M7 Cobalt
-- boxes (5 tiers), M8 Aurora/Ember effects, plus the M7 Robux button label.
-- PF - 3's page binds each card through the lobby card kit:
--     local art=ShopItemArt.attach(card,"forge"|"cobalt"|"effect",{tier=n}|{id="vfx_aurora"})
--     context.cardKit:bind(card,{set=...,idle=art.idle,onLook=art.onLook})
-- Layers are authored in the place (tools/atlas/author-pf019-shop-art.luau) under
-- "<card>.PFCardBody.PFArtWell.PF019Art". This module only animates them (positions in
-- stage Scale, rotation, transparency); it never sizes the card or the well. The kit
-- runs idle loops only while the card is on screen and ReducedMotion is off.
local Spec=require(game:GetService("ReplicatedStorage").Shared.ShopItemArtSpec)
local Art={}
Art.ROBUX=utf8.char(0xE002) -- Roblox's Robux glyph; Ubuntu Bold draws it inline at digit height
local TAU=math.pi*2

local function rng(seed:number):()->number
    return function()seed=(seed*1664525+1013904223)%4294967296;return seed/4294967296 end
end
local function approach(value:number,target:number,step:number):number
    if value<target then return math.min(target,value+step)end
    return math.max(target,value-step)
end

-- Paths ---------------------------------------------------------------------------
function Art.pathLength(points:{Vector2}):number
    local total=0
    for i=2,#points do total+=(points[i]-points[i-1]).Magnitude end
    return total
end
-- The point `distance` along a polyline, clamped to its ends.
function Art.pointAt(points:{Vector2},distance:number):Vector2
    if distance<=0 then return points[1]end
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local length=(b-a).Magnitude
        if distance<=length then return a+(b-a)*(distance/length)end
        distance-=length
    end
    return points[#points]
end

-- Forge (M6) ------------------------------------------------------------------------
local Forge=Spec.Forge
local forgeEmbers={}
do
    local R=rng(31)
    for i=1,Forge.embers+Forge.hoverEmbers do
        local seam=R()
        table.insert(forgeEmbers,{x=math.floor(R()*Forge.size.X/4)*4,y=if seam<.5 then 96 else 188,off=R(),
            size=if R()<.35 then 4 else 2,color=Forge.emberColors[(i-1)%3+1]})
    end
end
Art.forgeEmbers=forgeEmbers
-- One frame of the Forge loop at phase t in [0,1) and hover hv in [0,1].
function Art.forgeFrame(t:number,hv:number):any
    local frame={pulses={},junctions={},embers={},lit=hv}
    local L=26+8*hv -- dash length, % of the path
    for _,heat in Forge.heat do
        local total=Art.pathLength(heat.points)
        local head=((t+heat.offset)%1)*(100+L)
        for k=0,Forge.trail-1 do
            local d=head-k*L/(Forge.trail-1)
            local visible=d>0 and d<100
            local p=Art.pointAt(heat.points,d/100*total)
            local fall=k/(Forge.trail-1)
            table.insert(frame.pulses,{x=p.X,y=p.Y,size=(36-18*fall)*(1+.15*hv),alpha=if visible then (.95-.6*fall)*(.85+.15*hv)else 0})
        end
    end
    for j,_ in Forge.junctions do
        local k=.35+.65*math.abs(math.sin(math.pi*(t*2+(j-1)*.37)))
        table.insert(frame.junctions,{size=34+10*hv,alpha=(.55+.2*hv)*k,core=.5+.5*k})
    end
    for i,e in forgeEmbers do
        local tt=(t+e.off)%1
        local alpha=math.sin(tt*math.pi)*(.85+.15*hv)
        if i>Forge.embers then alpha*=hv end
        table.insert(frame.embers,{x=e.x+math.sin((tt+e.off)*TAU)*6,y=e.y-tt*(120+30*hv),size=e.size,alpha=alpha})
    end
    local breath=math.sin(t*TAU)
    frame.mark={glow=.35+.25*breath+.2*hv,scale=1+.04*breath}
    return frame
end

-- Cobalt (M7) -----------------------------------------------------------------------
local Cobalt=Spec.Cobalt
local cobaltMotes,cobaltSparks={},{}
for tier,T in Cobalt.tiers do
    local R,S=rng(11+tier),rng(97+tier)
    local motes,sparks={},{}
    for _=1,T.motes+Cobalt.hoverMotes do table.insert(motes,{x=40+R()*248,off=R(),size=if R()<.3 then 4 else 2})end
    for _=1,T.spark+Cobalt.hoverSparks do
        local a,rad=S()*TAU,50+S()*80
        table.insert(sparks,{x=Cobalt.centre.X+math.cos(a)*rad*1.25,y=Cobalt.centre.Y+math.sin(a)*rad*.8,off=S(),size=5+S()*7})
    end
    cobaltMotes[tier]=motes;cobaltSparks[tier]=sparks
end
-- One frame of a Cobalt tier at phase t, hover hv, and wall time now (ribbon shine).
function Art.cobaltFrame(tier:number,t:number,hv:number,now:number):any
    local T=Cobalt.tiers[tier]
    local c=Cobalt.centre
    local frame={rays={},rings={},motes={},sparks={},orbit={}}
    local rayAlpha=(.4+.15*hv)*(.8+.2*hv)
    if T.rays>0 then
        table.insert(frame.rays,{rotation=t*360/T.rays*(if tier>=4 then 2 else 1),alpha=rayAlpha})
        if tier>=5 then table.insert(frame.rays,{rotation=-t*36+17,alpha=rayAlpha*.6})end
    end
    frame.glow=math.min(.9,T.glow+.18*hv)
    if T.ring then for _,off in {0,.5}do
        local u=(t+off)%1
        table.insert(frame.rings,{diameter=2*(50+u*110),alpha=(1-u)*.55})
    end end
    if T.sweep then
        local x=-140+((t*1.6)%1.6)*420
        frame.sweep={x=x+55,alpha=.16*(1+.5*hv)}
    end
    frame.gem={y=c.Y+math.sin(t*TAU)*(if tier>=4 then 3 else 2)-6*hv,size=T.gem*(1+.07*hv)}
    for i=1,T.orbit do
        local a=t*TAU+(i-1)/T.orbit*TAU
        local front=math.sin(a)>0
        table.insert(frame.orbit,{x=c.X+math.cos(a)*112,y=c.Y+math.sin(a)*34-6,front=front,size=if front then 14 else 10,alpha=if front then 1 else .6})
    end
    for i,m in cobaltMotes[tier]do
        local u=(t+m.off)%1
        local alpha=math.sin(u*math.pi)*.85
        if i>T.motes then alpha*=hv end
        table.insert(frame.motes,{x=m.x,y=210-u*190,size=m.size,alpha=alpha})
    end
    for i,s in cobaltSparks[tier]do
        local tw=math.max(0,math.sin((t+s.off)*TAU))
        local alpha=if tw<.05 then 0 else tw
        if i>T.spark then alpha*=hv end
        -- The sparkle cell's star reaches 52 of 128 px, so the image is 2.46x the star radius.
        table.insert(frame.sparks,{x=s.x,y=s.y,size=s.size*tw*(1+.2*hv)*2.46,alpha=alpha})
    end
    if tier>=5 then
        local u=(now%Cobalt.shineEvery)/.8
        frame.shine=if u<=1 then -1+2*u else nil
    end
    return frame
end
-- Bonus label for a pack ("+33%"), or nil for the base pack.
function Art.bonusLabel(pack:any):string?
    if type(pack)~="table"or type(pack.bonusAmount)~="number"or pack.bonusAmount<=0 or type(pack.baseAmount)~="number"or pack.baseAmount<=0 then return nil end
    return "+"..tostring(math.floor(pack.bonusAmount/pack.baseAmount*100+.5)).."%"
end

-- Effects (M8) ----------------------------------------------------------------------
local Effects=Spec.Effects
local auroraStars,emberSparks={},{}
do
    local R=rng(5)
    for _=1,Effects.aurora.stars do table.insert(auroraStars,{x=R()*300,y=R()*120,off=R()})end
    local E=rng(9)
    for _=1,Effects.ember.sparks+Effects.ember.hoverSparks do table.insert(emberSparks,{x=E()*300,off=E(),size=if E()<.3 then 4 else 2})end
end
-- The crest height of aurora curtain ci (1..3) at image x (design px, curtain image space).
function Art.crest(ci:number,x:number):number
    local A=14+(ci-1)*5
    local f,f2=TAU/300*ci,TAU/300*(2*(ci-1)+3)
    return Effects.aurora.curtainImageTop+math.sin(x*f+(ci-1)*1.7)*A+math.sin(x*f2)*A*.35
end
function Art.effectFrame(kind:string,t:number,hv:number,now:number):any
    local frame={kind=kind}
    frame.city={size=32+12*hv,alpha=.35+.2*hv}
    frame.trainX=30+((t*1.3)%1)*Effects.trainSpan
    if kind=="aurora"then
        local A=Effects.aurora
        frame.stars={}
        for _,s in auroraStars do table.insert(frame.stars,{x=s.x,y=s.y,alpha=(.3+.7*math.abs(math.sin((t+s.off)*TAU)))*.8})end
        frame.curtains={}
        local speed=1+hv
        for ci=1,3 do
            local drift=((t*speed)%1)
            local x=if ci%2==1 then -drift*A.period else -(1-drift)*A.period
            -- Curtains hang from their crest line (AnchorPoint y = imageTop/height at curtainBase),
            -- so hover growth keeps the crest in place; a glint rides along each crest.
            local glintX=((t+(ci-1)*.33)%1)*300
            local scaleY=1+.35*hv
            table.insert(frame.curtains,{x=x,scaleY=scaleY,
                glint={x=glintX,y=A.curtainBase[ci]+(Art.crest(ci,glintX-x)-A.curtainImageTop)*scaleY}})
        end
    else
        local E=Effects.ember
        frame.flameFrame=math.floor(now/E.frameSeconds)%E.frames
        frame.flameScale=1+.4*hv
        frame.core=.5+.15*math.sin(now*23)+.1*math.sin(now*37)+.2*hv
        frame.sparks={}
        for i,s in emberSparks do
            local tt=(t*1.5+s.off)%1
            local alpha=math.sin(tt*math.pi)
            if i>E.sparks then alpha*=hv end
            table.insert(frame.sparks,{x=s.x+math.sin((tt+s.off)*6)*5,y=110-tt*105,size=s.size,alpha=alpha,color=E.colors[(i-1)%2+1]})
        end
    end
    return frame
end

-- In-match strip (M8) --------------------------------------------------------------
local Strip=Spec.Strip
local stripMotes={}
local stripK=Strip.size.Y/186 -- the strip was drawn at 700x186
do local R=rng(40);for _=1,Strip.motes do table.insert(stripMotes,{x=300+R()*360,y=(20+R()*120)*stripK,off=R()})end end
function Art.stripFrame(effect:string,t:number,now:number):any
    local frame={trail={},motes={}}
    local total=Art.pathLength(Strip.rail)
    local L=26
    local head=t*(100+L)
    for k=0,Strip.trail-1 do
        local fall=k/(Strip.trail-1)
        local d=head-k*L/(Strip.trail-1)
        local p=Art.pointAt(Strip.rail,d/100*total)
        table.insert(frame.trail,{x=p.X,y=p.Y,size=26-12*fall,alpha=if d>0 and d<100 then .95-.6*fall else 0})
    end
    local swing=math.sin(t*TAU)
    frame.shipX=Strip.ship.X+swing*6
    frame.city=.4+.15*math.sin(t*TAU*2)
    frame.factory=.3+.15*math.sin(t*TAU*2+1.3)
    for _,m in stripMotes do
        if effect=="ember"then
            local u=(t+m.off)%1
            table.insert(frame.motes,{x=m.x+math.sin((u+m.off)*TAU)*4,y=m.y+(20-u*40)*stripK,alpha=math.sin(u*math.pi)*.9})
        else
            table.insert(frame.motes,{x=m.x,y=m.y*.5,alpha=(.3+.7*math.abs(math.sin((t+m.off)*TAU)))*.7})
        end
    end
    return frame
end
-- Robux button (M7 fix): glyph and price as one centred unit on one baseline, Bold.
-- robuxLabel turns the page's purchase state into the label. With no live Marketplace
-- price (Studio, or a failed lookup) it shows the catalog price as a preview rather than
-- a bare dash; a live price always wins. state={priceText?, purchaseState?, targetRobux?}
function Art.robuxLabel(state:any):string
    local s=if type(state)=="table"then state else {}
    local price,phase=s.priceText,s.purchaseState
    if phase=="Owned"then return "✓ Owned"end
    if phase=="Purchasing"then return "Purchasing…"end
    if phase=="Loading"or phase=="Updating"then return "…"end
    if type(price)=="string"and string.match(price,"^%d[%d,]*$")then return Art.robuxText(price)end
    if type(s.targetRobux)=="number"and s.targetRobux>0 then return Art.robuxText(tostring(math.floor(s.targetRobux)))end
    return "Unavailable"
end
function Art.robuxText(price:string):string
    return Art.ROBUX.."\u{2009} "..price
end
function Art.paintRobux(host:Instance,text:string)
    local label=host:FindFirstChild("PFRobuxPrice")
    if label and label:IsA("TextLabel")then label.Text=text end
end

-- Binding ---------------------------------------------------------------------------
-- The authored containers: PF019Art (the stage), PF019Pin (top-right corner box) and
-- PF019Frame (the well's rectangle). Returns a by-name finder across them, or nil.
-- Catalog cards are runtime clones of one template, so their art lives once in a
-- library (ReplicatedStorage.PFShopArt.PFArt_<itemId>) and is cloned into the card's
-- well on attach; fixed cards (Cobalt packs) and the M8 strip are authored in place.
local function libraryGroup(card:Instance,id:any):Instance?
    if type(id)~="string"then return nil end
    -- A card's art well, or a bare host frame (the M8 strip) that takes the group directly.
    local body=card:FindFirstChild("PFCardBody")
    local well=if body then body:FindFirstChild("PFArtWell",true)else card
    if not well then return nil end
    local name="PFArt_"..id
    -- One group shows at a time (the strip swaps effects in the same host).
    for _,other in well:GetChildren()do
        if other.Name~=name and string.sub(other.Name,1,6)=="PFArt_"and other:IsA("GuiObject")then other.Visible=false end
    end
    local group=well:FindFirstChild(name)
    if not group then
        local library=game:GetService("ReplicatedStorage"):FindFirstChild("PFShopArt")
        local source=library and library:FindFirstChild(name)
        if not source then return nil end
        group=source:Clone();group.Parent=well
    end
    (group :: any).Visible=true
    return group
end
Art.libraryGroup=libraryGroup
local function stageOf(card:Instance,id:any?):any?
    -- A library group, a card's art well, or a host frame that holds the art directly (the M8 strip).
    local body=card:FindFirstChild("PFCardBody")
    local group=libraryGroup(card,id)
    local well=if group then group elseif card:FindFirstChild("PF019Art")then card else body and body:FindFirstChild("PFArtWell",true)
    local stage=well and well:FindFirstChild("PF019Art")
    if not stage then return nil end
    -- PF019Inner (author-pf1-cobalt-v3): the Cobalt glow/rays/rings/motes moved into a soft-fade CanvasGroup pair.
    local boxes={stage,well:FindFirstChild("PF019Pin"),well:FindFirstChild("PF019Frame"),well:FindFirstChild("PF019Inner",true)}
    return {FindFirstChild=function(_,name)
        for _,box in boxes do local found=box and box:FindFirstChild(name);if found then return found end end
        return nil
    end}
end
local function at(node:any,x:number,y:number,space:Vector2)node.Position=UDim2.fromScale(x/space.X,y/space.Y)end
local function size(node:any,w:number,h:number,space:Vector2)node.Size=UDim2.fromScale(w/space.X,h/space.Y)end
local function list(stage:Instance,prefix:string):{any}
    local out={}
    local i=1
    while true do
        local node=stage:FindFirstChild(prefix..i)
        if not node then break end
        out[i]=node;i+=1
    end
    return out
end

local function forgeApplier(stage:Instance):(any)->()
    local S=Forge.size
    local lit=stage:FindFirstChild("Lit")
    local pulses,junctions,cores,embers=list(stage,"Pulse"),list(stage,"Junction"),list(stage,"Core"),list(stage,"Ember")
    local mark,markGlow=stage:FindFirstChild("Mark"),stage:FindFirstChild("MarkGlow")
    local markScale=mark and mark:FindFirstChildOfClass("UIScale")
    return function(f:any)
        if lit then lit.ImageTransparency=1-f.lit end
        for i,node in pulses do local p=f.pulses[i];if p then at(node,p.x,p.y,S);size(node,p.size,p.size,S);node.ImageTransparency=1-p.alpha end end
        for i,node in junctions do local j=f.junctions[i];if j then size(node,j.size,j.size,S);node.ImageTransparency=1-j.alpha end end
        for i,node in cores do local j=f.junctions[i];if j then node.BackgroundTransparency=1-j.core end end
        for i,node in embers do local e=f.embers[i];if e then at(node,e.x,e.y,S);size(node,e.size,e.size,S);node.BackgroundTransparency=1-e.alpha end end
        if markGlow then markGlow.ImageTransparency=1-f.mark.glow end
        if markScale then markScale.Scale=f.mark.scale end
    end
end
local function cobaltApplier(stage:Instance,tier:number):(any)->()
    local S=Cobalt.size
    local wheels,rings,motes,sparks,shards=list(stage,"Wheel"),list(stage,"Ring"),list(stage,"Mote"),list(stage,"Spark"),list(stage,"Shard")
    local glow,sweep,gem=stage:FindFirstChild("Glow"),stage:FindFirstChild("Sweep"),stage:FindFirstChild("Gem")
    local shine=stage:FindFirstChild("RibbonShine")
    local shineGradient=shine and shine:FindFirstChildOfClass("UIGradient")
    local gemZ=if gem then (gem :: any).ZIndex else 1
    return function(f:any)
        for i,node in wheels do local r=f.rays[i];if r then node.Rotation=r.rotation;node.ImageTransparency=1-r.alpha end end
        if glow then glow.ImageTransparency=1-f.glow end
        for i,node in rings do local r=f.rings[i];if r then size(node,r.diameter,r.diameter,S);node.ImageTransparency=1-r.alpha end end
        if sweep and f.sweep then at(sweep,f.sweep.x,Cobalt.centre.Y-6,S);sweep.ImageTransparency=1-f.sweep.alpha end
        if gem then at(gem,Cobalt.centre.X,f.gem.y,S);size(gem,f.gem.size,f.gem.size,S)end
        for i,node in shards do local o=f.orbit[i];if o then
            at(node,o.x,o.y,S);size(node,o.size,o.size,S);node.ImageTransparency=1-o.alpha
            node.ImageColor3=if o.front then Cobalt.shardFront else Cobalt.shardBack
            node.ZIndex=if o.front then gemZ+1 else gemZ-1
        end end
        for i,node in motes do local m=f.motes[i];if m then at(node,m.x,m.y,S);size(node,m.size,m.size,S);node.BackgroundTransparency=1-m.alpha end end
        for i,node in sparks do local s=f.sparks[i];if s then at(node,s.x,s.y,S);size(node,s.size,s.size,S);node.ImageTransparency=1-s.alpha end end
        if shineGradient then
            shine.Visible=f.shine~=nil
            if f.shine then shineGradient.Offset=Vector2.new(f.shine,0)end
        end
    end
end
local function effectApplier(stage:Instance,kind:string):(any)->()
    local S=Effects.size
    local stars,curtains,glints,sparks=list(stage,"Star"),list(stage,"Curtain"),list(stage,"Glint"),list(stage,"Spark")
    local cityGlow,train,flames,core=stage:FindFirstChild("CityGlow"),stage:FindFirstChild("Train"),stage:FindFirstChild("Flames"),stage:FindFirstChild("Core")
    local E=Effects.ember
    return function(f:any)
        if cityGlow then size(cityGlow,f.city.size,f.city.size,S);cityGlow.ImageTransparency=1-f.city.alpha end
        if train then train.Position=UDim2.fromScale(f.trainX/S.X,train.Position.Y.Scale)end
        if kind=="aurora"then
            for i,node in stars do local s=f.stars[i];if s then node.BackgroundTransparency=1-s.alpha end end
            for i,node in curtains do local c=f.curtains[i];if c then
                node.Position=UDim2.fromScale(c.x/S.X,node.Position.Y.Scale)
                node.Size=UDim2.fromScale(node.Size.X.Scale,Effects.aurora.curtainHeight*c.scaleY/S.Y)
            end end
            for i,node in glints do local c=f.curtains[i];if c then at(node,c.glint.x,c.glint.y,S)end end
        else
            if flames then
                flames.ImageRectOffset=Vector2.new(0,f.flameFrame*E.flameHeight)
                flames.Size=UDim2.fromScale(flames.Size.X.Scale,E.flameHeight*f.flameScale/S.Y)
            end
            if core then core.ImageTransparency=1-math.clamp(f.core,0,1)end
            for i,node in sparks do local s=f.sparks[i];if s then at(node,s.x,s.y,S);node.BackgroundTransparency=1-s.alpha end end
        end
    end
end

local function stripApplier(stage:any):(any)->()
    local S=Strip.size
    local trail,motes=list(stage,"Trail"),list(stage,"Mote")
    local ship,wake=stage:FindFirstChild("Ship"),stage:FindFirstChild("Wake")
    local cityGlow,factoryGlow=stage:FindFirstChild("CityGlow"),stage:FindFirstChild("FactoryGlow")
    return function(f:any)
        for i,node in trail do local p=f.trail[i];if p then at(node,p.x,p.y,S);size(node,p.size,p.size,S);node.ImageTransparency=1-p.alpha end end
        for i,node in motes do local m=f.motes[i];if m then at(node,m.x,m.y,S);node.BackgroundTransparency=1-m.alpha end end
        if ship then at(ship,f.shipX,Strip.ship.Y,S)end
        if wake then at(wake,f.shipX-50,Strip.ship.Y,S)end
        if cityGlow then cityGlow.ImageTransparency=1-f.city end
        if factoryGlow then factoryGlow.ImageTransparency=1-f.factory end
    end
end

-- attach(card, kind, args) -> {idle, onLook} for cardKit:bind. A card without
-- authored layers gets inert callbacks, so the page can bind before the art lands.
function Art.attach(card:Instance,kind:string,args:any?):any
    args=args or {}
    local libraryId=if kind=="forge"or kind=="effect"then args.id
        elseif kind=="strip"then "strip_"..(if args.effect=="ember"then "ember"else "aurora")else nil
    local stage=stageOf(card,libraryId)
    if not stage then return {}end
    local host=libraryGroup(card,libraryId)or card
    local apply,frameAt,loop
    if kind=="forge"then
        apply=forgeApplier(stage);loop=Forge.loop
        frameAt=function(t,hv,_now)return Art.forgeFrame(t,hv)end
    elseif kind=="strip"then
        local effect=if args.effect=="ember"then "ember"else "aurora"
        apply=stripApplier(stage);loop=Strip.loop
        frameAt=function(t,_hv,now)return Art.stripFrame(effect,t,now)end
    elseif kind=="cobalt"then
        local tier=math.clamp(math.floor(tonumber(args.tier)or 1),1,#Cobalt.tiers)
        apply=cobaltApplier(stage,tier);loop=Cobalt.tiers[tier].loop
        frameAt=function(t,hv,now)return Art.cobaltFrame(tier,t,hv,now)end
    elseif kind=="effect"then
        local effect=if args.id=="vfx_ember"then "ember"else "aurora"
        local scene=effectApplier(stage,effect);loop=Effects[effect].loop
        -- M8: the card's "applies to" icons (PF - 3's text block, PFApplies1..3) light up in
        -- turn, 0.2 s apart, while the card is hot.
        local icons={}
        for i=1,3 do
            local icon=host:FindFirstChild("PFApplies"..i,true)
            if icon and icon:IsA("ImageLabel")then table.insert(icons,{node=icon,rest=icon.ImageColor3,lit=Effects[effect].colors[i]})end
        end
        local hotSince: number?=nil
        apply=function(f:any)
            scene(f)
            if #icons==0 then return end
            if f.hot and not hotSince then hotSince=f.now elseif not f.hot then hotSince=nil end
            for i,icon in icons do
                local on=hotSince~=nil and (f.now-hotSince>=(i-1)*.2 or f.reduced)
                icon.node.ImageColor3=if on then icon.lit else icon.rest
            end
        end
        frameAt=function(t,hv,now)
            local f=Art.effectFrame(effect,t,hv,now)
            f.hot=hv>.5;f.now=now;f.reduced=now==0
            return f
        end
    else
        return {}
    end
    local hv,target,last=0,0,nil
    local function hot(h:any):number
        local s=h.state
        return if s.disabled then 0 elseif s.hover or s.focused or s.pressed then 1 else 0
    end
    local function onLook(h:any,_look:any)
        target=hot(h)
        -- Reduced motion: no idle loop runs, so settle on the still hover/rest frame now.
        if h.kit and h.kit:reduced()then hv=target;apply(frameAt(0,hv,0))end
    end
    local function idle(h:any,now:number)
        local dt=if last then math.clamp(now-last,0,.1)else 0
        last=now
        hv=approach(hv,target,dt/.18)
        apply(frameAt(((now/loop)+(h.phase or 0))%1,hv,now))
    end
    return {idle=idle,onLook=onLook,apply=apply,frameAt=frameAt}
end
-- For hosts outside the card kit (the M8 in-match strip): runs the idle loop while the
-- host is shown, and stops when ReducedMotion is set on any ancestor. Returns a stop function.
function Art.drive(host:Instance,kind:string,args:any?,services:any?):()->()
    local art=Art.attach(host,kind,args)
    if not art.idle then return function()end end
    local s=services or {}
    local heartbeat=s.heartbeat or game:GetService("RunService").Heartbeat
    local clock=s.clock or os.clock
    local h={state={},phase=0,kit={reduced=function()return false end}}
    local shown,lastCheck=false,-math.huge
    local function check():boolean
        local node: any=host
        while node and not node:IsA("LayerCollector")do
            if node:IsA("GuiObject")and not node.Visible then return false end
            if node:GetAttribute("ReducedMotion")==true then return false end
            node=node.Parent
        end
        return node~=nil
    end
    local connection=heartbeat:Connect(function()
        local now=clock()
        if now-lastCheck>=.2 then lastCheck=now;shown=check()end
        if shown then art.idle(h,now)end
    end)
    return function()connection:Disconnect()end
end
return Art
