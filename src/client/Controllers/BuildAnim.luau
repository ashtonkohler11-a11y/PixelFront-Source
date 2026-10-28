--!strict
-- PF - 4 building animations, the GUI half (Ashton approved 2026-10-27, slowed to the real build time; timing in
-- BuildAnimMath). Callers pass their own instances; everything this module adds is a child named PFBuild* and is
-- removed again, so it never touches authored layout.
--   BuildAnim.site(marker, art, progress, opts)  every paint of a map building: marker = the building's frame (its box),
--       art = the part that rises (a CanvasGroup / ImageLabel), progress = 0..1 while under construction, nil once
--       standing. opts = {premium, mine, fresh, px}: mine plays the full completion burst (others: a small pop only),
--       fresh = a standing building just created with no build time (plays the short rise), px = the marker size.
--   BuildAnim.press(card, premium)               the bar / rail card squash when picked
--   BuildAnim.confirm(card, premium, costText?)  the card's confirm when the build is placed (+ the "-cost" chip)
--   BuildAnim.forget(marker)                     a marker is being destroyed
local RunService=game:GetService("RunService")
local Math=require(script.Parent.BuildAnimMath)
local M={}

local WHITE=Color3.new(1,1,1)
local GOLD={Color3.fromHex("#fff6c8"),Color3.fromHex("#ffd84a"),Color3.fromHex("#f5b318"),Color3.fromHex("#b9770c")}
local DUST={Color3.fromHex("#fffaf2"),Color3.fromHex("#d8c4ab"),Color3.fromHex("#9c8268")}
local GOLD_DUST={Color3.fromHex("#fff6d6"),Color3.fromHex("#f0c860"),Color3.fromHex("#b37a1c")}
local SCAFFOLD=Color3.fromHex("#6b4f3c")
local BRACKET=Color3.fromHex("#3d2a2a")
local Z=40 -- above the building's own art

type Site={marker: GuiObject,art: any,pop: GuiObject,premium: boolean,mine: boolean,born: number,parts: {GuiObject}?,
    burstAt: number?,burst: {GuiObject}?,instantAt: number?,px: number,progress: number?}
local sites: {[GuiObject]: Site}=setmetatable({},{__mode="k"}) :: any
type Card={card: GuiObject,premium: boolean,pressAt: number?,confirmAt: number?,parts: {GuiObject}?,chip: TextLabel?,chipAt: number?}
local cards: {[GuiObject]: Card}=setmetatable({},{__mode="k"}) :: any
local loop: RBXScriptConnection?=nil

local function frame(parent: Instance,name: string,color: Color3,z: number?): Frame
    local f=Instance.new("Frame");f.Name=name;f.BorderSizePixel=0;f.BackgroundColor3=color;f.ZIndex=z or Z;f.Parent=parent
    return f
end
local function px(n: number): number return math.max(1,math.round(n)) end

-- ------------------------------------------------------------------ the reveal (a stepped transparency gradient)
-- `art` is one GuiObject or a list (a premium marker's stacked sprite layers); the first one pops
local function layers(art: any): {GuiObject} return if typeof(art)=="Instance" then {art} else art end
local function reveal(art: any,progress: number?)
    local seq: NumberSequence?=nil
    if progress~=nil then
        local keys={};for _,k in Math.revealKeys(progress) do table.insert(keys,NumberSequenceKeypoint.new(k[1],k[2])) end
        seq=NumberSequence.new(keys)
    end
    for _,a in layers(art) do
        local g=a:FindFirstChild("PFBuildReveal") :: UIGradient?
        if seq==nil then if g then g:Destroy() end
        else
            if not g then local n=Instance.new("UIGradient");n.Name="PFBuildReveal";n.Rotation=90;n.Parent=a;g=n end
            (g :: UIGradient).Transparency=seq
        end
    end
end

-- ------------------------------------------------------------------ the construction site: brackets, build line, posts
local function clearParts(list: {GuiObject}?) if list then for _,p in list do p:Destroy() end end end
local function buildParts(s: Site): {GuiObject}
    local m=s.marker;local color=if s.premium then GOLD[3] else BRACKET
    local parts={}
    for i=1,8 do local f=frame(m,"PFBuildBracket"..i,color);table.insert(parts,f) end -- 4 corners x 2 arms
    local line=frame(m,"PFBuildLine",if s.premium then GOLD[1] else WHITE);line.AnchorPoint=Vector2.new(.5,.5);table.insert(parts,line)
    for i=1,2 do local post=frame(m,"PFBuildPost"..i,if s.premium then GOLD[4] else SCAFFOLD);post.AnchorPoint=Vector2.new(.5,1);table.insert(parts,post) end
    return parts
end
local function layoutParts(s: Site,now: number)
    local parts=s.parts;if not parts then return end
    local t=px(s.px*.06);local pad=Math.bracketPad(now-s.born);local arm=.24
    local corners={{0,0,1,1},{1,0,-1,1},{0,1,1,-1},{1,1,-1,-1}}
    for i,c in corners do
        local x=c[1]+(if c[1]==0 then -pad else pad);local y=c[2]+(if c[2]==0 then -pad else pad)
        local h,v=parts[i*2-1],parts[i*2]
        h.AnchorPoint=Vector2.new(if c[3]>0 then 0 else 1,if c[4]>0 then 0 else 1);h.Position=UDim2.fromScale(x,y);h.Size=UDim2.new(arm,0,0,t)
        v.AnchorPoint=h.AnchorPoint;v.Position=UDim2.fromScale(x,y);v.Size=UDim2.new(0,t,arm,0)
    end
    local q=Math.risen(s.progress or 0);local line=parts[9];local done=q>=1
    line.Visible=not done;line.Position=UDim2.fromScale(.5,Math.lineY(s.progress or 0));line.Size=UDim2.new(.66,0,0,px(s.px*.05))
    for i=1,2 do
        local post=parts[9+i];post.Visible=not done
        post.Position=UDim2.fromScale(if i==1 then -.02 else 1.02,Math.PLATE_BOTTOM);post.Size=UDim2.new(0,t,math.min(.92,q*.9+.14),0)
    end
end

-- ------------------------------------------------------------------ the completion burst
local function startBurst(s: Site,now: number)
    clearParts(s.burst);s.burstAt=now
    local m=s.marker;local parts={}
    local rim=frame(m,"PFBuildRim",WHITE,Z-1);rim.BackgroundTransparency=1;rim.AnchorPoint=Vector2.new(.5,.5);rim.Position=UDim2.fromScale(.5,.5)
    local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(.5,0);corner.Parent=rim
    local stroke=Instance.new("UIStroke");stroke.Color=if s.premium then GOLD[2] else WHITE;stroke.Thickness=px(s.px*.09);stroke.Parent=rim
    table.insert(parts,rim)
    if s.mine then
        local cols=if s.premium then GOLD_DUST else DUST
        local dirs=if s.premium then {{-1,.95},{1,.95},{0,1.05},{-1.25,.7},{1.25,.7}} else {{-1,.95},{1,.95},{0,1.05}}
        for i,d in dirs do
            local puff=frame(m,"PFBuildDust"..i,cols[2]);puff.BackgroundTransparency=1;puff:SetAttribute("DX",d[1]);puff:SetAttribute("DY",d[2])
            for j,c in cols do local b=frame(puff,"B"..j,c);b.AnchorPoint=Vector2.new(.5,.5) end
            table.insert(parts,puff)
        end
        if s.premium then
            local ring=frame(m,"PFBuildRing",GOLD[2],Z-2);ring.BackgroundTransparency=1;ring.AnchorPoint=Vector2.new(.5,.5);ring.Position=UDim2.fromScale(.5,.5)
            local rs=Instance.new("UIStroke");rs.Color=GOLD[2];rs.Thickness=px(s.px*.07);rs.Parent=ring
            local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(.3,0);rc.Parent=ring
            table.insert(parts,ring)
            local shine=frame(m,"PFBuildShine",GOLD[1],Z+1);shine.AnchorPoint=Vector2.new(.5,.5);shine.Position=UDim2.fromScale(.5,.5);shine.Size=UDim2.fromScale(.9,.9)
            local sc=Instance.new("UICorner");sc.CornerRadius=UDim.new(.5,0);sc.Parent=shine
            local sg=Instance.new("UIGradient");sg.Name="Band";sg.Rotation=25;sg.Parent=shine
            sg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.42,1),NumberSequenceKeypoint.new(.5,.35),NumberSequenceKeypoint.new(.58,1),NumberSequenceKeypoint.new(1,1)})
            table.insert(parts,shine)
            local glint=frame(m,"PFBuildGlint",WHITE,Z+2);glint.BackgroundTransparency=1;glint.AnchorPoint=Vector2.new(.5,.5);glint.Position=UDim2.fromScale(.9,.12)
            for j=1,2 do local arm=frame(glint,"Arm"..j,GOLD[1],Z+2);arm.AnchorPoint=Vector2.new(.5,.5);arm.Position=UDim2.fromScale(.5,.5) end
            table.insert(parts,glint)
        end
    end
    local scale=s.pop:FindFirstChild("PFBuildPop") :: UIScale?
    if not scale then local n=Instance.new("UIScale");n.Name="PFBuildPop";n.Parent=s.pop;scale=n end
    s.burst=parts
end
local function stepBurst(s: Site,now: number): boolean
    local b=Math.burst(now-(s.burstAt :: number),s.premium)
    local scale=s.pop:FindFirstChild("PFBuildPop") :: UIScale?
    if scale then scale.Scale=if s.mine then b.pop else 1+(b.pop-1)*.5 end
    for _,p in s.burst or {} do
        if p.Name=="PFBuildRim" then
            p.Visible=b.rim.on;p.Size=UDim2.fromScale(.9*b.rim.grow,.9*b.rim.grow)
            local st=p:FindFirstChildOfClass("UIStroke");if st then st.Transparency=b.rim.alpha end
        elseif p.Name=="PFBuildRing" and b.ring then
            p.Visible=b.ring.on;p.Size=UDim2.fromScale(b.ring.grow,b.ring.grow*.82)
            local st=p:FindFirstChildOfClass("UIStroke");if st then st.Transparency=b.ring.alpha end
        elseif p.Name=="PFBuildShine" and b.shine then
            p.Visible=b.shine.on;local g=p:FindFirstChild("Band") :: UIGradient?;if g then g.Offset=Vector2.new(b.shine.x,0) end
        elseif p.Name=="PFBuildGlint" and b.glint then
            p.Visible=b.glint.on;p.Size=UDim2.fromScale(b.glint.size,b.glint.size)
            local t=px(s.px*.05)
            for j,arm in p:GetChildren() do if arm:IsA("Frame") then arm.Size=if arm.Name=="Arm1" then UDim2.new(1,0,0,t) else UDim2.new(0,t,1,0) end end
        elseif string.sub(p.Name,1,11)=="PFBuildDust" then
            p.Visible=b.dust.on
            local dx,dy=p:GetAttribute("DX") :: number,p:GetAttribute("DY") :: number
            local k=b.dust.k;local r=.13+k*.09
            p.Position=UDim2.fromScale(.5+dx*(.42+k*.32),dy+(-.04*k));p.Size=UDim2.fromScale(r*2,r*1.3);p.AnchorPoint=Vector2.new(.5,.5)
            local i=0
            for _,c in p:GetChildren() do
                if c:IsA("Frame") then
                    i+=1;c.BackgroundTransparency=b.dust.alpha
                    -- a little stepped cloud: a light top block, a mid body, a dark foot (pixel squares, no sprays)
                    c.Position=UDim2.fromScale(({.42,.5,.62})[i],({.3,.58,.82})[i]);c.Size=UDim2.fromScale(({.55,.95,.6})[i],({.5,.55,.3})[i])
                end
            end
        end
    end
    if b.done then clearParts(s.burst);s.burst=nil;s.burstAt=nil;if scale then scale:Destroy() end;return false end
    return true
end

-- ------------------------------------------------------------------ the bar / rail cards
local function cardParts(c: Card): {GuiObject}
    if c.parts then return c.parts end
    local card=c.card;local parts={}
    local over=frame(card,"PFBuildConfirm",WHITE,(card.ZIndex or 1)+5);over.BackgroundTransparency=1;over.Size=UDim2.fromScale(1,1)
    local corner=card:FindFirstChildOfClass("UICorner");if corner then corner:Clone().Parent=over end
    local st=Instance.new("UIStroke");st.Color=if c.premium then GOLD[2] else WHITE;st.Thickness=2;st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;st.Transparency=1;st.Parent=over
    if c.premium then
        -- the light that runs once round the border: a gradient on the stroke with one bright arc
        local g=Instance.new("UIGradient");g.Name="Run"
        g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,GOLD[3]),ColorSequenceKeypoint.new(.5,GOLD[1]),ColorSequenceKeypoint.new(1,GOLD[3])})
        g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.85),NumberSequenceKeypoint.new(.4,.55),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(.6,.55),NumberSequenceKeypoint.new(1,.85)})
        g.Parent=st
        local shine=frame(over,"Shine",GOLD[1],(card.ZIndex or 1)+5);shine.Size=UDim2.fromScale(1,1);shine.BackgroundTransparency=.55
        if corner then corner:Clone().Parent=shine end
        local sg=Instance.new("UIGradient");sg.Name="Band";sg.Rotation=20
        sg.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.4,1),NumberSequenceKeypoint.new(.5,.1),NumberSequenceKeypoint.new(.6,1),NumberSequenceKeypoint.new(1,1)})
        sg.Parent=shine
    end
    table.insert(parts,over);c.parts=parts
    return parts
end
local function stepCard(c: Card,now: number): boolean
    local busy=false
    local scale=c.card:FindFirstChild("PFBuildPress") :: UIScale?
    if c.pressAt then
        local t=now-c.pressAt
        if not scale then local n=Instance.new("UIScale");n.Name="PFBuildPress";n.Parent=c.card;scale=n end
        if t>=Math.PRESS.up then (scale :: UIScale).Scale=1;c.pressAt=nil else (scale :: UIScale).Scale=Math.pressScale(t);busy=true end
    end
    if c.confirmAt then
        local f=Math.confirm(now-c.confirmAt,c.premium);local over=cardParts(c)[1]
        local st=over:FindFirstChildOfClass("UIStroke")
        if st then
            st.Transparency=f.rim
            local g=st:FindFirstChild("Run") :: UIGradient?;if g then g.Rotation=f.angle end
        end
        local shine=over:FindFirstChild("Shine") :: Frame?
        if shine then shine.Visible=not f.done;local g=shine:FindFirstChild("Band") :: UIGradient?;if g and f.shine then g.Offset=Vector2.new(f.shine,0) end end
        if f.done then c.confirmAt=nil else busy=true end
    end
    if c.chip and c.chipAt then
        local rise,alpha,done=Math.float(now-c.chipAt,c.premium)
        c.chip.Position=UDim2.new(.5,0,0,-4-rise);c.chip.TextTransparency=alpha
        local s=c.chip:FindFirstChildOfClass("UIStroke");if s then s.Transparency=alpha end
        if done then c.chip:Destroy();c.chip=nil;c.chipAt=nil else busy=true end
    end
    if not busy then
        if scale then scale:Destroy() end
        clearParts(c.parts);c.parts=nil
    end
    return busy
end

-- ------------------------------------------------------------------ one loop for everything that moves
local function tick()
    local now=os.clock();local any=false
    for marker,s in sites do
        if not marker.Parent then sites[marker]=nil;continue end
        if s.instantAt then
            local p=Math.instantRise(now-s.instantAt)
            if p then s.progress=p;reveal(s.art,p);layoutParts(s,now);any=true
            else s.instantAt=nil;s.progress=nil;reveal(s.art,nil);clearParts(s.parts);s.parts=nil;startBurst(s,now) end
        elseif s.parts and now-s.born<Math.SNAP_SECONDS+.05 then layoutParts(s,now);any=true end
        if s.burstAt then if stepBurst(s,now) then any=true end end
        -- a site still under construction stays (its completion paint needs it); finished, idle ones go
        if not s.burstAt and not s.instantAt and not s.parts and s.progress==nil then sites[marker]=nil end
    end
    for card,c in cards do
        if not card.Parent then cards[card]=nil;continue end
        if stepCard(c,now) then any=true else cards[card]=nil end
    end
    if not any and loop then loop:Disconnect();loop=nil end
end
local function run() if not loop then loop=RunService.RenderStepped:Connect(tick) end end

-- ------------------------------------------------------------------ API
function M.site(marker: GuiObject,art: any,progress: number?,opts: any)
    local pop: GuiObject=(opts and opts.pop) or layers(art)[1]
    local s=sites[marker]
    if progress==nil and not s then
        -- a standing building: nothing to do, unless it was just built with no construction time
        if not (opts and opts.fresh) or marker:GetAttribute("PFBuildSeen") then
            if not marker:GetAttribute("PFBuildSeen") then marker:SetAttribute("PFBuildSeen",true) end
            reveal(art,nil)
            return
        end
        marker:SetAttribute("PFBuildSeen",true)
        local n: Site={marker=marker,art=art,pop=pop,premium=opts.premium==true,mine=opts.mine==true,born=os.clock(),px=opts.px or 24,instantAt=os.clock(),progress=0}
        n.parts=if n.mine then buildParts(n) else nil;sites[marker]=n
        reveal(art,0);layoutParts(n,os.clock());run();return
    end
    marker:SetAttribute("PFBuildSeen",true)
    if not s then
        local n: Site={marker=marker,art=art,pop=pop,premium=opts and opts.premium==true or false,mine=opts and opts.mine==true or false,born=os.clock(),px=opts and opts.px or 24}
        s=n;sites[marker]=n
    end
    local site=s :: Site
    site.art=art;site.pop=pop;site.px=opts and opts.px or site.px
    if site.instantAt then return end -- the short rise owns the reveal until it lands
    if progress~=nil then
        site.progress=progress;reveal(art,progress)
        -- the scaffold only for your own sites (others: the rise alone, so a busy enemy map stays quiet)
        if site.mine and not site.parts then site.parts=buildParts(site);run() end
        layoutParts(site,os.clock())
    elseif site.progress~=nil then
        site.progress=nil;reveal(art,nil);clearParts(site.parts);site.parts=nil
        startBurst(site,os.clock());run()
    end
end
function M.forget(marker: GuiObject)
    local s=sites[marker];if not s then return end
    clearParts(s.parts);clearParts(s.burst);sites[marker]=nil
end
function M.press(card: GuiObject,premium: boolean)
    local c=cards[card] or {card=card,premium=premium};c.premium=premium;c.pressAt=os.clock();cards[card]=c;run()
end
function M.confirm(card: GuiObject,premium: boolean,costText: string?)
    local c=cards[card] or {card=card,premium=premium};c.premium=premium;c.confirmAt=os.clock();cards[card]=c
    if costText and costText~="" then
        if c.chip then c.chip:Destroy() end
        local chip=Instance.new("TextLabel");chip.Name="PFBuildCost";chip.BackgroundTransparency=1;chip.AnchorPoint=Vector2.new(.5,1)
        chip.Size=UDim2.fromOffset(90,18);chip.Position=UDim2.new(.5,0,0,-4);chip.ZIndex=(card.ZIndex or 1)+6
        chip.Font=Enum.Font.GothamBlack;chip.TextSize=14;chip.Text="−"..costText
        chip.TextColor3=if premium then GOLD[2] else WHITE
        local s=Instance.new("UIStroke");s.Color=if premium then Color3.fromHex("#3a2606") else Color3.fromHex("#1b1d22");s.Thickness=2;s.Parent=chip
        chip.Parent=card;c.chip=chip;c.chipAt=os.clock()
    end
    run()
end
return M
