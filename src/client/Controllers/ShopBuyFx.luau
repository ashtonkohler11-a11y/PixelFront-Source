--!strict
-- PF019 Cobalt buy (PF - 3), redone for PF021 A to the mockup Ashton approved
-- (docs/director/mockups/PF021/A-cobalt-buy-redo.png; "I would prefer a blue glow and subtle
-- sparkles with a clean animation"). One module for every Cobalt key: the M2 catalog card
-- (CobaltBuy layer) and the bundle cards (BundleBuy layer).
--   * pending: the page shows the price dimmed (no dots); a soft light sweeps the key and its rim
--     and the card's border lean cobalt.
--   * success, 0.55 s: a soft cobalt glow blooms around the card (in by 0.16, holds to 0.26, out by
--     0.55) with the card's border and the key's rim; the paid price slides up 6 px and fades
--     (0.04-0.20) as Equip slides in from 6 px below (0.10-0.26); four small sparkles twinkle on
--     the card (0.10-0.45). No burst, no pop, no white flash.
--   * fail: the page paints the red note (Need Cobalt, 1.6 s); a soft red glow at the key and one
--     3 px nudge.
-- Truthful: the page calls success / fail only on ShopBuyModel's verdict on the server's answer.
-- ReducedMotion: the glow fades in and out, nothing moves (no sweep, slide, sparkles or nudge).
-- Every look is a pose of time (Fx.now), so QA can freeze any frame. Plays end themselves and put
-- back what they borrowed; the sweep, sparkles, halo and the outgoing price are temporary instances.
local Run=game:GetService("RunService")
local Assets=require(game.ReplicatedStorage.Shared.LobbyCardAssets)
local Fx: any={}
-- PF - 3's audio (Sfx, silent until bound); no script under the offline fx runner
local function sound(key: string) if script then require(script.Parent.Sfx).play(key) end end
Fx.now=os.clock
Fx.last=nil
Fx.DURATION=table.freeze({success=.55,fail=.6,sweep=1.1})
Fx.LIFT=6 -- px the price leaves upward and Equip comes up from (the key is 36 px on every device)
Fx.NUDGE=3 -- px, the failure's one sideways nudge
-- The four sparkles, from the mockup's 176 x 215 card: centre (fractions of the card), arm length
-- (fraction of the card's width), start and life (s).
Fx.SPARKS=table.freeze({
    table.freeze({26/176,22/215,9/176,.10,.30}),
    table.freeze({150/176,96/215,7/176,.12,.30}),
    table.freeze({140/176,190/215,6/176,.18,.26}),
    table.freeze({18/176,150/215,5/176,.20,.22})})
Fx.SPARKLES=#Fx.SPARKS
-- PF - 2's shop VFX sheet (ShopItemArtSpec.Cells): the 4-point star (arms 52 px of the 128 px
-- cell) and the soft horizontal sweep band.
local SHEET="rbxassetid://118312288651391"
local SPARKLE_CELL={Vector2.new(640,64),Vector2.new(128,128)}
local STAR_REACH=128/52 -- image side per arm length
local COBALT=Color3.fromHex("#4d8dff") -- the bloom
local BORDER=Color3.fromHex("#6fa0ff") -- the card's border at the peak
local ICE=Color3.fromHex("#9cc2ff") -- the key's rim and the sweep
local SPARK=Color3.fromHex("#cfe1ff")
local RED=Color3.fromHex("#e0605a")
local plays: {any}={}
local connection: RBXScriptConnection?=nil

local function clamp01(x: number): number return math.clamp(x,0,1) end
local function outCubic(x: number): number x=clamp01(x);return 1-(1-x)^3 end
local function inOutQuad(x: number): number x=clamp01(x);return if x<.5 then 2*x*x else 1-(-2*x+2)^2/2 end
local function layerOf(key: Instance): any return key:FindFirstChild("CobaltBuy") or key:FindFirstChild("BundleBuy") end
local function alive(node: Instance?): boolean return node~=nil and node.Parent~=nil end
-- The bloom over time: in by 0.16, held to 0.26, gone by 0.55.
function Fx.bloom(t: number): number
    if t<.16 then return outCubic(t/.16) elseif t<.26 then return 1 end
    return (1-clamp01((t-.26)/.29))^1.5
end
-- The rims start half-way (the server's yes) and then ride the bloom.
function Fx.rim(t: number): number
    if t<.16 then return .5+.5*outCubic(t/.16) end
    return Fx.bloom(t)
end

function Fx.step()
    local now=Fx.now()
    for i=#plays,1,-1 do
        local play=plays[i];local t=now-play.start
        local over=play.stopped or (if play.duration then t>=play.duration else not alive(play.key))
        if over then table.remove(plays,i);play.finish()
        else local ok,err=pcall(play.pose,t);if not ok then table.remove(plays,i);pcall(play.finish);warn("[ShopBuyFx] "..tostring(err)) end end
    end
    if #plays==0 and connection then connection:Disconnect();connection=nil end
end
-- One play per key: a new one ends the old first (it puts its borrowed looks back). With a kind,
-- only a play of that kind ends (the bundle keys end their pending sweep this way).
function Fx.stop(key: Instance,kind: string?)
    for i=#plays,1,-1 do
        local play=plays[i]
        if play.key==key and (kind==nil or play.kind==kind) then table.remove(plays,i);play.finish() end
    end
end
local function add(play: any): any
    Fx.stop(play.key)
    play.start=Fx.now();table.insert(plays,play);Fx.last=play
    if not connection then connection=Run.Heartbeat:Connect(Fx.step) end
    play.pose(0)
    return play
end
-- What a play borrows from the card and the key, and how it puts them back: the card's glow and
-- border (the kit handle re-applies its own look afterwards) and the key's rim.
local function borrow(key: GuiObject,layer: any,opts: any): any
    local card=opts.card
    local body=card and card:FindFirstChild("PFCardBody")
    local glow=card and card:FindFirstChild("PFCardGlow")
    local stroke=body and body:FindFirstChild("PFCardStroke")
    local rim=layer:FindFirstChild("Base") and layer.Base:FindFirstChild("Rim")
    local b: any={glow=glow,stroke=stroke,rim=rim,handle=opts.handle}
    if glow then b.glowRest={glow.ImageTransparency,glow.ImageColor3} end
    if stroke then b.strokeRest={stroke.Color,stroke.Thickness} end
    if rim then b.rimRest={rim.Color,rim.Thickness} end
    -- glow: 0..1 of the bloom; lean: 0..1 of the cobalt border and rim
    b.pose=function(glowAmount: number?,lean: number,color: Color3?)
        if glow and glowAmount and alive(glow) then glow.ImageColor3=color or COBALT;glow.ImageTransparency=1-.8*glowAmount end
        if stroke and alive(stroke) then
            stroke.Color=b.strokeRest[1]:Lerp(color or BORDER,lean);stroke.Thickness=b.strokeRest[2]+(2-b.strokeRest[2])*clamp01(lean)
        end
        if rim and alive(rim) then rim.Color=b.rimRest[1]:Lerp(color or ICE,lean);rim.Thickness=b.rimRest[2]*(1+.5*lean) end
    end
    b.finish=function()
        if glow and alive(glow) then glow.ImageTransparency=b.glowRest[1];glow.ImageColor3=b.glowRest[2] end
        if stroke and alive(stroke) then stroke.Color=b.strokeRest[1];stroke.Thickness=b.strokeRest[2] end
        if rim and alive(rim) then rim.Color=b.rimRest[1];rim.Thickness=b.rimRest[2] end
        if b.handle and not b.handle.destroyed then b.handle:_apply() end
    end
    return b
end
-- A text's own shade stroke fades with it.
local function fadeText(label: any,shadeRest: number?,amount: number)
    label.TextTransparency=amount
    local shade=label:FindFirstChild("Shade")
    if shade and shadeRest then shade.Transparency=shadeRest+(1-shadeRest)*amount end
end

-- pending: a soft light sweeps the key (the page shows the price dimmed); the rims lean cobalt.
-- opts: reduced, card, handle.
function Fx.pending(key: GuiObject,opts: any?): any?
    local o=opts or {}
    local layer=layerOf(key);if not layer then return nil end
    -- an authored (bundle) key asked again while still pending keeps its running sweep
    for _,play in plays do if play.key==key and play.kind=="pending" then return play end end
    local base=layer:FindFirstChild("Base")
    local looks=borrow(key,layer,o)
    local sweep: Frame?=nil;local gradient: UIGradient?=nil
    if base and not o.reduced then
        local made=Instance.new("Frame");made.Name="PFBuySweep";made.Size=UDim2.fromScale(1,1);made.BorderSizePixel=0
        made.BackgroundColor3=ICE;made.BackgroundTransparency=0;made.ZIndex=base.ZIndex;made.Active=false
        local corner=Instance.new("UICorner");local own=base:FindFirstChildWhichIsA("UICorner")
        corner.CornerRadius=if own then own.CornerRadius else UDim.new(0,8);corner.Parent=made
        -- a slanted band at .28, the rest clear
        local g=Instance.new("UIGradient");g.Rotation=-18
        g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.38,1),NumberSequenceKeypoint.new(.5,.72),
            NumberSequenceKeypoint.new(.62,1),NumberSequenceKeypoint.new(1,1)})
        g.Parent=made;made.Parent=base;sweep=made;gradient=g
    end
    local play: any={kind="pending",key=key}
    play.pose=function(t: number)
        looks.pose(nil,.35)
        -- one pass in 0.8 s, then a short rest, while the server answers
        if gradient and alive(sweep) then
            local k=(t%Fx.DURATION.sweep)/.8
            gradient.Offset=Vector2.new(if k<=1 then -.75+1.5*inOutQuad(k) else 1.2,0)
        end
    end
    play.finish=function()
        if sweep then sweep:Destroy() end
        looks.finish()
    end
    return add(play)
end

-- success: the bloom, the clean price -> Equip slide and four sparkles. opts: reduced, from (the
-- price that was paid, slid out), card (the kit card: glow + border + sparkles), handle (its kit
-- handle, re-applied after).
function Fx.success(key: GuiObject,opts: any?): any?
    local o=opts or {}
    local layer=layerOf(key);if not layer then return nil end
    sound(if layer.Name=="BundleBuy" then "u_pack" else "u_buy") -- a pack opens / a Cobalt buy
    local looks=borrow(key,layer,o)
    -- The slide: a copy of the price row (gem + the digits that were paid) lifts and fades while the
    -- key's new words come up from below.
    local slide: any=nil
    local row=layer:FindFirstChild("PriceRow")
    if not o.reduced and type(o.from)=="string" and row and layer.Name=="CobaltBuy" then
        local incoming=if layer.PackPrice.Visible then layer.PackPrice elseif row.Visible then row else nil
        if incoming then
            local old=row:Clone();old.Name="PFSlideOut";old.Visible=true
            local digits=old:FindFirstChild("Digits")
            if digits then digits.Text=o.from;digits.TextColor3=Color3.fromHex("#f2f2f2");digits.TextTransparency=0 end
            local crystal=old:FindFirstChild("Crystal");if crystal then crystal.ImageTransparency=0 end
            old.Parent=layer
            local inShade=incoming:FindFirstChild("Shade");local outShade=digits and digits:FindFirstChild("Shade")
            slide={old=old,digits=digits,crystal=crystal,oldBase=old.Position,outShade=if outShade then outShade.Transparency else nil,
                incoming=incoming,inBase=incoming.Position,inShade=if inShade then inShade.Transparency else nil}
        end
    end
    -- The sparkles sit on the card itself (all four inside its bounds, so no clip cuts them).
    local card=o.card
    local holder: Frame?=nil;local sparks={}
    if card and not o.reduced then
        local made=Instance.new("Frame");made.Name="PFBuySparkles";made.BackgroundTransparency=1;made.BorderSizePixel=0
        made.Size=UDim2.fromScale(1,1);made.ZIndex=30;made.Active=false
        local w=card.AbsoluteSize.X
        for i,s in Fx.SPARKS do
            local image=Instance.new("ImageLabel");image.Name="Sparkle"..i;image.BackgroundTransparency=1
            image.Image=SHEET;image.ImageRectOffset=SPARKLE_CELL[1];image.ImageRectSize=SPARKLE_CELL[2]
            image.ImageColor3=SPARK;image.ScaleType=Enum.ScaleType.Fit;image.AnchorPoint=Vector2.new(.5,.5)
            image.Position=UDim2.fromScale(s[1],s[2]);image.ZIndex=30;image.Active=false;image.Visible=false
            image.Parent=made
            table.insert(sparks,{image=image,side=s[3]*w*STAR_REACH,start=s[4],life=s[5]})
        end
        made.Parent=card;holder=made
    end
    local play: any={kind="success",key=key,duration=Fx.DURATION.success}
    play.pose=function(t: number)
        local bloom=Fx.bloom(t)
        looks.pose(bloom,if o.reduced then bloom else Fx.rim(t))
        if slide and alive(slide.old) and alive(slide.incoming) then
            local out=outCubic((t-.04)/.16);local come=outCubic((t-.10)/.16)
            slide.old.Position=slide.oldBase+UDim2.fromOffset(0,-Fx.LIFT*out)
            if slide.digits then fadeText(slide.digits,slide.outShade,out) end
            if slide.crystal then slide.crystal.ImageTransparency=out end
            slide.incoming.Position=slide.inBase+UDim2.fromOffset(0,Fx.LIFT*(1-come))
            if slide.incoming:IsA("TextLabel") then fadeText(slide.incoming,slide.inShade,1-come) end
        end
        for _,s in sparks do
            -- each grows in fast and twinkles out, in place
            local k=(t-s.start)/s.life
            s.image.Visible=k>0 and k<1
            if k>0 and k<1 then
                local wave=math.sin(math.pi*k)
                local size=s.side*wave^.6;s.image.Size=UDim2.fromOffset(size,size)
                s.image.ImageTransparency=1-wave^.4;s.image.Rotation=20*k
            end
        end
    end
    play.finish=function()
        if slide then
            slide.old:Destroy()
            if alive(slide.incoming) then
                slide.incoming.Position=slide.inBase
                if slide.incoming:IsA("TextLabel") then fadeText(slide.incoming,slide.inShade,0) end
            end
        end
        if holder then holder:Destroy() end
        looks.finish()
    end
    return add(play)
end

-- fail: a soft red glow at the key and one 3 px nudge (the page holds the red note's words).
function Fx.fail(key: GuiObject,opts: any?): any?
    local o=opts or {}
    local layer=layerOf(key);if not layer then return nil end
    if o.words=="Need Cobalt" then sound("u_broke") end -- 0.5 s cooldown in SoundList
    local base=layer.Position
    -- the halo: the card glow's 9-slice at an 8 px spread around the key, behind its face
    local halo=Instance.new("ImageLabel");halo.Name="PFBuyHalo";halo.BackgroundTransparency=1;halo.Active=false
    halo.Image=Assets.glow;halo.ScaleType=Enum.ScaleType.Slice;halo.SliceCenter=Assets.glowSlice;halo.SliceScale=8/Assets.glowInset
    halo.AnchorPoint=Vector2.new(.5,.5);halo.Position=UDim2.fromScale(.5,.5);halo.Size=UDim2.new(1,16,1,16)
    halo.ImageColor3=RED;halo.ImageTransparency=1;halo.ZIndex=math.max(1,layer.ZIndex-1);halo.Parent=key
    local play: any={kind="fail",key=key,duration=Fx.DURATION.fail}
    play.pose=function(t: number)
        local glowAmount=if t<.08 then outCubic(t/.08) elseif t<.3 then 1 else 1-outCubic((t-.3)/.3)
        if alive(halo) then halo.ImageTransparency=1-.55*glowAmount end
        if not o.reduced and alive(layer) then
            local nudge=if t<.1 then outCubic(t/.1) else 1-inOutQuad((t-.1)/.2)
            layer.Position=base+UDim2.fromOffset(Fx.NUDGE*nudge,0)
        end
    end
    play.finish=function()
        if alive(layer) then layer.Position=base end
        halo:Destroy()
    end
    return add(play)
end

return Fx
