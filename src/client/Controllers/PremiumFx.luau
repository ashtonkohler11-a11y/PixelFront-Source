--!strict
-- PF - 4 (2026-10-25, Ashton: "all premium buildings have a visual ... a /s on the bank ... artillery should literally shoot
-- a shell, tesla should have a zap on the troops it hits"): the premium items' in-match effects, drawn on the map's World in
-- our pixel style. Presentation only; nothing here changes the match.
--   from the sim's fx feed (PremiumItems.packet .fx, exact tiles):
--     (Ashton's FX review: the economy buildings show a small number + a pulse on their own icon, no coin / gem / wrench
--     graphics; the Tesla's arc leaves the coil's centre beneath its icon. The lines below predate that where they differ.)
--     zap      Tesla Coil: a jagged cyan arc from the coil's tip to the attack front / boat it hits, a tip flash, edge sparks
--     shell    Artillery: muzzle flash, a grey shell arcing to the victim's land, a dust puff + "-1.5%" (owner / victim);
--              shells a Tesla stops in part get a white arc from that coil mid-flight
--     warden_fire / warden   Warden: a heavy lob with its ground shadow, then the blast and "-6%"
--   events: train (Training Camp pulse + "+5K"), payout (Stock Exchange burst), captured / destroyed (notices)
--   (the Longshot, Insurance Office and Bounty Office are retired: their effects are gone)
--   from the buildings + the match state (client timers):
--     Bank           a coin and "+2.5K/s" float up every 3 s (owner; a faint coin for others)
--     Tax Office     coins fly from up to 3 of your Cities to it every 3 s, then "+X/s" (owner only)
--     guild_save Shipping Co. (Ashton 2026-10-27, "Only when it saves one"): one shield pops over your trade ship at the
--              moment a raider's capture of it is blocked, a glint, then "Saved" (owner only; no periodic shield)
--     Eng. Yard      a rocking wrench and sparks on your buildings under construction (owner only)
--   the launches (PremiumBuildPlaceholder draws the Blitz / Titan / Airdrop sprites and the rings):
--     Blitz a short hot trail; Titan a heavy smoke trail and a white flash before its shockwave; Airdrop 3 parachutes.
-- Cheap on phones: one RenderStepped loop, pooled frames, at most MAX_ACTIVE effects at once (extra ones are skipped).
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes=require(Shared:WaitForChild("Remotes"))
local Config=require(Shared:WaitForChild("Config"))
local Feed=require(script.Parent.MatchPacketFeed)
local Notices=require(script.Parent.FeedNotices)
local Arsenal=require(Shared:WaitForChild("ArsenalCatalog"))
local okRenderer,BuildingRenderer=pcall(require,script.Parent.BuildingRenderer)
local Math=require(script.Parent.PremiumFxMath)
local okGeo,Geo=pcall(require,script.Parent.FrameGeometry) -- PF - 4 perf: one layout read a frame, not one per renderer
local MATCH=Config.Arsenal.Match
local STEP=Config.Match.StepSeconds
local M={}
-- one switch per item (Ashton reviews each effect from the captures; false = that item's effect is off)
local ON: {[string]: boolean}={tesla_coil=true,artillery=true,airdrop=true,blitz_bomb=true,titan_bomb=true,
    bank=true,tax_office=true,trade_guild=true,engineering_yard=true,
    warden=true,barracks=true,stock_exchange=true,training_camp=true} -- the reshuffle's four (PF - 4, Ashton "build them")
local TROOP,TROOP_INK=Color3.fromRGB(168,200,255),Color3.fromRGB(10,20,48) -- troop numbers (HUD units: internal ÷ 10)
M.ON=ON
local MAX_ACTIVE=60
local Z=45 -- above the premium markers (20-25) and shots (40)
local BELOW=19 -- just under the premium markers
local GOLD,GOLD_INK=Color3.fromRGB(255,214,92),Color3.fromRGB(60,38,0)
local RED,RED_INK=Color3.fromRGB(255,110,92),Color3.fromRGB(60,10,6)
local CYAN,CYAN_CORE=Color3.fromRGB(90,220,255),Color3.fromRGB(235,252,255)
-- ---------------------------------------------------------------- pixel art (rects on a small grid; letters = palette keys)
local ART: {[string]: any}={
    coin={w=7,h=7,rects={{1,0,5,7,"r"},{0,1,7,5,"r"},{2,1,3,5,"b"},{1,2,5,3,"b"},{5,2,1,3,"d"},{2,5,3,1,"d"},{3,2,1,3,"d"},{2,2,1,1,"l"}}},
    shield={w=7,h=8,rects={{0,0,7,5,"o"},{1,5,5,1,"o"},{2,6,3,1,"o"},{3,7,1,1,"o"},{1,1,5,4,"b"},{2,5,3,1,"b"},{3,6,1,1,"b"},{1,1,1,3,"l"},{3,2,1,2,"g"}}},
    wrench={w=10,h=10,rects={ -- an open jaw (two prongs) on a thick diagonal handle; a dark shadow one pixel down-right
        {6,1,1,3,"d"},{9,1,1,3,"d"},{7,3,2,1,"d"},{5,4,4,1,"d"},{4,5,3,1,"d"},{3,6,3,1,"d"},{2,7,3,1,"d"},{1,8,3,1,"d"},{1,9,2,1,"d"},
        {5,0,1,3,"s"},{8,0,1,3,"s"},{6,2,2,1,"s"},{4,3,4,1,"s"},{3,4,3,1,"s"},{2,5,3,1,"s"},{1,6,3,1,"s"},{0,7,3,1,"s"},{0,8,2,1,"s"},
        {5,0,1,1,"l"},{8,0,1,1,"l"},{4,3,1,1,"l"}}},
    shell={w=5,h=3,rects={{0,0,4,3,"d"},{4,1,1,1,"d"},{1,0,1,3,"g"},{3,0,1,1,"l"}}},
    chute={w=7,h=9,rects={{1,0,5,1,"c"},{0,1,7,2,"c"},{0,2,1,1,"k"},{3,1,1,2,"k"},{6,2,1,1,"k"},
        {0,3,1,1,"x"},{6,3,1,1,"x"},{1,4,1,1,"x"},{5,4,1,1,"x"},{2,5,1,1,"x"},{4,5,1,1,"x"},{2,6,3,3,"w"},{2,6,3,1,"x"}}},
}
local PALETTE: {[string]: any}={
    coin={r=Color3.fromRGB(122,74,0),b=Color3.fromRGB(255,201,58),d=Color3.fromRGB(217,154,26),l=Color3.fromRGB(255,241,160)},
    green={r=Color3.fromRGB(22,84,40),b=Color3.fromRGB(95,224,138),d=Color3.fromRGB(52,168,90),l=Color3.fromRGB(214,255,224)},
    shield={o=Color3.fromRGB(18,48,74),b=Color3.fromRGB(158,201,255),l=Color3.fromRGB(232,244,255),g=Color3.fromRGB(255,206,84)},
    wrench={d=Color3.fromRGB(40,44,52),s=Color3.fromRGB(200,208,220),l=Color3.fromRGB(255,255,255)},
    shell={d=Color3.fromRGB(46,46,46),g=Color3.fromRGB(200,160,64),l=Color3.fromRGB(150,150,150)},
}
local function short(n: number): string
    n=math.floor(n+.5)
    if n>=1e6 then return (string.gsub(string.format("%.1fM",n/1e6),"%.0M","M")) end
    if n>=1e4 then return string.format("%dK",n//1000) end
    if n>=1e3 then return (string.gsub(string.format("%.1fK",n/1e3),"%.0K","K")) end
    return tostring(n)
end
function M.start()
    local player=Players.LocalPlayer
    local playerGui=player:WaitForChild("PlayerGui")
    local gui=playerGui:WaitForChild("OpenFront")
    local gameUI=gui:WaitForChild("Background"):WaitForChild("Game") :: GuiObject
    local MatchController=require(script.Parent.MatchController)
    local world=MatchController.mapPanel(gui,gameUI,playerGui):WaitForChild("Viewport"):WaitForChild("World") :: GuiObject
    local remotes=Remotes.client()
    local layer=Instance.new("Frame");layer.Name="PFPremiumFx";layer.BackgroundTransparency=1;layer.Size=UDim2.fromScale(1,1);layer.ZIndex=Z
    layer.Parent=world
    -- beneath the premium building icons (PremiumBuildPlaceholder's markers sit at ZIndex 20-25): the Tesla's arc
    local below=Instance.new("Frame");below.Name="PFPremiumFxBelow";below.BackgroundTransparency=1;below.Size=UDim2.fromScale(1,1)
    below.ZIndex=BELOW;below.Parent=world
    local authoredCost=world:FindFirstChild("GhostCost")
    local font=if authoredCost and authoredCost:IsA("TextLabel") then authoredCost.FontFace else Font.fromEnum(Enum.Font.GothamBlack)
    local latest: any=nil -- the Premium packet
    local receivedAt=os.clock()
    local state: any=nil -- the match state (MatchPacketFeed)
    -- ------------------------------------------------------------ pools
    local pools: {[string]: {GuiObject}}={}
    local function take(kind: string): any
        local list=pools[kind];local obj: any=list and table.remove(list)
        if obj then obj.Visible=true;if obj.Parent~=layer then obj.Parent=layer end;return obj end
        if kind=="px" then
            local f=Instance.new("Frame");f.BorderSizePixel=0;f.AnchorPoint=Vector2.new(.5,.5);f.ZIndex=Z;obj=f
        elseif kind=="text" then
            local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.AnchorPoint=Vector2.new(.5,1);t.AutomaticSize=Enum.AutomaticSize.XY
            t.Size=UDim2.fromOffset(0,0);t.FontFace=font;t.ZIndex=Z+2
            local s=Instance.new("UIStroke");s.Thickness=1.5;s.LineJoinMode=Enum.LineJoinMode.Miter;s.Parent=t;obj=t
        else -- a pixel-art sprite: one Frame per rect, sized in scale, so the box's size is the art's size
            local art=ART[kind];local box=Instance.new("Frame");box.BackgroundTransparency=1;box.AnchorPoint=Vector2.new(.5,.5);box.ZIndex=Z+1
            for i,r in art.rects do
                local f=Instance.new("Frame");f.Name=r[5]..i;f.BorderSizePixel=0;f.ZIndex=Z+1
                f.Position=UDim2.fromScale(r[1]/art.w,r[2]/art.h);f.Size=UDim2.fromScale(r[3]/art.w,r[4]/art.h);f.Parent=box
            end
            obj=box
        end
        obj:SetAttribute("PFKind",kind);obj.Parent=layer
        return obj
    end
    local function give(obj: any)
        obj.Visible=false;obj.Rotation=0
        local kind=obj:GetAttribute("PFKind") :: string
        local list=pools[kind];if not list then list={};pools[kind]=list end
        table.insert(list,obj)
    end
    -- paint a sprite: its palette (+ an owner colour for "c") and one transparency for all of it
    local function paint(box: any,palette: any,alpha: number)
        for _,f in box:GetChildren() do
            local key=string.sub(f.Name,1,1);local c=palette[key]
            if c then f.BackgroundColor3=c;f.BackgroundTransparency=alpha;f.Visible=true else f.Visible=false end
        end
    end
    -- ------------------------------------------------------------ geometry (World pixels, recomputed every frame)
    local function zoom(): number return (if okGeo then Geo.worldSize(world) else world.AbsoluteSize).X/math.max(1,latest and latest.width or 1) end
    local function unit(): number -- one art pixel: a tenth of a base building at this zoom (1.5 to 5 px)
        local z=zoom();local base=if okRenderer then (BuildingRenderer :: any).presentationSize(z,nil) else 24
        return math.clamp(base/10,1.5,5)
    end
    local function at(tile: number): Vector2
        local w=latest.width;local z=zoom()
        return Vector2.new(((tile-1)%w+.5)*z,((tile-1)//w+.5)*z)
    end
    local function place(obj: any,p: Vector2) obj.Position=UDim2.fromOffset(p.X,p.Y) end
    local function px(color: Color3,size: number,alpha: number?): any
        local f=take("px");f.ZIndex=Z;f.BackgroundColor3=color;f.BackgroundTransparency=alpha or 0;f.Size=UDim2.fromOffset(size,size);return f
    end
    local function text(words: string,color: Color3,ink: Color3,small: boolean?): any
        local t=take("text");t.Text=words;t.TextColor3=color;t.TextTransparency=0
        t.TextSize=if small then math.clamp(math.round(unit()*3),9,14) else math.clamp(math.round(unit()*4),11,18)
        local s=t:FindFirstChildOfClass("UIStroke") :: UIStroke;s.Color=ink;s.Transparency=0
        return t
    end
    local function fadeText(t: any,alpha: number) t.TextTransparency=alpha;(t:FindFirstChildOfClass("UIStroke") :: UIStroke).Transparency=alpha end
    -- ------------------------------------------------------------ the effect loop
    local active: {any}={}
    local function play(duration: number,parts: {any},step: (number)->(),done: (()->())?): boolean
        if #active>=MAX_ACTIVE then for _,p in parts do give(p) end;return false end
        table.insert(active,{t0=os.clock(),dur=duration,parts=parts,step=step,done=done})
        step(0)
        return true
    end
    local function clearAll() for _,e in active do for _,p in e.parts do give(p) end end;table.clear(active) end
    -- sparks: n pixels thrown out of p, falling a little
    local function sparks(getP: ()->Vector2,n: number,colors: {Color3},reach: number,duration: number,size: number?)
        local u=unit();local parts,dirs={},{}
        for i=1,n do
            local a=math.random()*math.pi*2
            table.insert(dirs,Vector2.new(math.cos(a),math.sin(a))*(reach*(.6+math.random()*.4)))
            table.insert(parts,px(colors[(i-1)%#colors+1],math.max(1,math.round(size or u))))
        end
        play(duration,parts,function(a)
            local p=getP()
            for i,f in parts do
                place(f,p+dirs[i]*a+Vector2.new(0,u*3*a*a));f.BackgroundTransparency=math.clamp((a-.4)/.6,0,1)
            end
        end)
    end
    -- a jagged arc (a few rotated pixel strips, a glow under a white core), re-jagged three times as it lives
    -- under=true: drawn beneath the building icons (Ashton: the Tesla's arc comes "from the middle, but under the icon")
    local function bolt(getA: ()->Vector2,getB: ()->Vector2,duration: number,under: boolean?)
        local u=unit();local n=6;local cores,glows={},{}
        for _=1,n do table.insert(glows,px(CYAN,1,.35));table.insert(cores,px(CYAN_CORE,1)) end
        local parts=table.clone(glows);for _,c in cores do table.insert(parts,c) end
        for _,c in cores do c.ZIndex=Z+1 end
        if under then for _,f in parts do f.Parent=below;f.ZIndex=BELOW end end
        local jag: {number}={};local stage=-1
        play(duration,parts,function(a)
            local A,B=getA(),getB();local d=B-A;local len=d.Magnitude;if len<1 then return end
            local normal=Vector2.new(-d.Y,d.X)/len
            local s=math.floor(a*3)
            if s~=stage then stage=s;for i=1,n-1 do jag[i]=(math.random()*2-1)*math.min(len*.14,u*4) end;jag[0]=0;jag[n]=0 end
            local fade=math.clamp((a-.55)/.45,0,1)
            for i=1,n do
                local p0=A+d*((i-1)/n)+normal*jag[i-1];local p1=A+d*(i/n)+normal*jag[i]
                local seg=p1-p0;local mid=(p0+p1)/2;local rot=math.deg(math.atan2(seg.Y,seg.X))
                local g,c=glows[i],cores[i]
                g.Position=UDim2.fromOffset(mid.X,mid.Y);g.Size=UDim2.fromOffset(seg.Magnitude+u,u*3);g.Rotation=rot;g.BackgroundTransparency=.35+.65*fade
                c.Position=UDim2.fromOffset(mid.X,mid.Y);c.Size=UDim2.fromOffset(seg.Magnitude+1,math.max(1,u*.9));c.Rotation=rot;c.BackgroundTransparency=fade
            end
        end)
    end
    local function flash(getP: ()->Vector2,color: Color3,size: number,duration: number,under: boolean?)
        local f=px(color,size,.1)
        if under then f.Parent=below;f.ZIndex=BELOW end
        play(duration,{f},function(a) place(f,getP());local s=size*(1+a*.8);f.Size=UDim2.fromOffset(s,s);f.BackgroundTransparency=.1+.9*a end)
    end
    -- a rising number (and a sprite beside it when given)
    local function pop(getP: ()->Vector2,words: string,color: Color3,ink: Color3,duration: number,rise: number?,alpha: number?,small: boolean?)
        local t=text(words,color,ink,small);local u=unit();local lift=(rise or 6)*u;local base=alpha or 0
        play(duration,{t},function(a)
            local p=getP()-Vector2.new(0,u*3+lift*(1-(1-a)^2));place(t,p)
            fadeText(t,base+(1-base)*math.clamp((a-.6)/.4,0,1))
        end)
    end
    -- Ashton (FX review): no new coin / gem graphics for the economy buildings; "a subtle number then a visual to the icon".
    -- pulse(b): the building's own map icon (PremiumBuildPlaceholder's marker "P"..id) swells 16% and its owner-tinted
    -- body warms toward `color` for half a second, then settles back (a UIScale, so the placeholder's own sizing stands)
    local markers: Instance?=nil
    local pulsing: {[number]: boolean}={}
    local function pulse(b: any,color: Color3)
        if not markers or not markers.Parent then markers=world:FindFirstChild("PF044PremiumPlaceholder") end
        local m=markers and markers:FindFirstChild("P"..tostring(b.id))
        if not m or pulsing[b.id] then return end
        local s=m:FindFirstChild("PFPulse") :: UIScale?
        if not s then local x=Instance.new("UIScale");x.Name="PFPulse";x.Parent=m;s=x end
        local scale=s :: UIScale
        local mask=m:FindFirstChild("Mask") :: ImageLabel?
        local base=if mask then mask.ImageColor3 else nil
        local started=play(.5,{},function(a)
            local k=math.sin(math.pi*a);scale.Scale=1+.16*k
            if mask and base then mask.ImageColor3=base:Lerp(color,.55*k) end
        end,function()
            scale.Scale=1;if mask and base then mask.ImageColor3=base end;pulsing[b.id]=nil
        end)
        if started then pulsing[b.id]=true end
    end
    -- ------------------------------------------------------------ the sim's fx
    local function mine(owner: any): boolean return owner==1 end
    local function fixed(tile: number): ()->Vector2 return function() return at(tile) end end
    local function zap(e: any)
        if type(e.from)~="number" or type(e.tile)~="number" then return end
        local coil=fixed(e.from);local hit=fixed(e.tile)
        bolt(coil,hit,.32,true) -- from the coil's centre, beneath its icon
        flash(coil,CYAN_CORE,unit()*6,.2,true) -- a glow behind the icon as it fires
        sparks(hit,5,{CYAN_CORE,CYAN,Color3.fromRGB(255,255,170)},unit()*5,.4)
    end
    local function shell(e: any)
        if type(e.from)~="number" or type(e.tile)~="number" then return end
        local gun,land=fixed(e.from),fixed(e.tile)
        local u=unit()
        -- the muzzle: a short orange flash and a grey smoke pixel or two
        flash(function() return gun()-Vector2.new(0,u*2) end,Color3.fromRGB(255,190,80),u*3,.16)
        sparks(function() return gun()-Vector2.new(0,u*2) end,3,{Color3.fromRGB(150,150,150),Color3.fromRGB(110,110,110)},u*3,.6)
        local s=take("shell");s.Size=UDim2.fromOffset(u*4,u*2.4);paint(s,PALETTE.shell,0)
        local stopped=false
        local flight=math.clamp((at(e.tile)-at(e.from)).Magnitude/(u*60),.6,1.1)
        local function where(a: number): (Vector2,number)
            local A,B=gun()-Vector2.new(0,u*2),land();local h=math.clamp((B-A).Magnitude*.35,u*6,u*40)
            local p=A:Lerp(B,a)-Vector2.new(0,4*h*a*(1-a))
            local dp=(B-A)-Vector2.new(0,4*h*(1-2*a))
            return p,math.deg(math.atan2(dp.Y,dp.X))
        end
        play(flight,{s},function(a)
            local p,rot=where(a);place(s,p);s.Rotation=rot
            local grow=.8*(1+.35*math.sin(math.pi*a));s.Size=UDim2.fromOffset(u*5*grow,u*3*grow)
            -- the victim's Tesla takes a bite out of it: a white arc to the shell mid-flight
            if e.coil and not stopped and a>=.62 then
                stopped=true
                local q=where(.62);bolt(fixed(e.coil),function() return q end,.22,true);sparks(function() return q end,4,{Color3.new(1,1,1),CYAN},u*3,.3)
            end
        end,function()
            -- the hit: a dust puff, a dark scorch, the number (for the gunner and the one hit)
            local p=land
            local dust={Color3.fromRGB(201,178,138),Color3.fromRGB(150,140,124),Color3.fromRGB(226,210,170)}
            sparks(p,9,dust,u*6,.8,u*1.8)
            flash(p,Color3.fromRGB(255,214,140),u*3,.14)
            local scorch=px(Color3.fromRGB(40,32,24),u*3,.3)
            play(1.2,{scorch},function(a) place(scorch,p());scorch.BackgroundTransparency=.3+.7*a end)
            -- Ashton: "display a number on pvp buildings when they are attacking" (the troops it took; gunner and victim see it)
            if (mine(e.owner) or mine(e.victim)) and (e.amount or 0)>0 then pop(p,"-"..short(e.amount).." troops",RED,RED_INK,1.2,6) end
        end)
    end
    -- ------------------------------------------------------------ the reshuffle's four (approved boards PREMIUM3-* + Take B)
    local function buildingAt(tile: number,item: string): any?
        for _,b in latest.buildings do if b.tile==tile and b.item==item then return b end end
        return nil
    end
    local wardenShown: {[number]: number}={} -- a Warden's ring shows a moment after it fires (touch has no hover)
    -- Warden (PF - 2's contract: fx warden_fire {from, tile, land} = the lob; fx warden {tile, amount, pct} = the hit): a heavy
    -- shell high over the land, its shadow on the ground under it; the hit is a blast on the attack's front and "-6%"
    local function wardenFire(e: any)
        if type(e.from)~="number" or type(e.tile)~="number" then return end
        local gun,front=fixed(e.from),fixed(e.tile);local u=unit()
        local b=buildingAt(e.from,"warden");if b then wardenShown[b.id]=os.clock()+2.5 end
        flash(function() return gun()-Vector2.new(0,u*2) end,Color3.fromRGB(255,200,110),u*4,.2)
        sparks(function() return gun()-Vector2.new(0,u*3) end,4,{Color3.fromRGB(150,150,150),Color3.fromRGB(100,100,100)},u*4,.8,u*1.4)
        local s=take("shell");paint(s,PALETTE.shell,0)
        local shadow=px(Color3.fromRGB(20,16,12),u*2,.55)
        -- it lands at tick `land` (fire + ShellTicks); the hit itself arrives as its own fx
        local flight=if type(e.land)=="number" and type(e.tick)=="number" then math.max(.4,(e.land-e.tick)*STEP-(os.clock()-receivedAt)) else 1.5
        play(flight,{s,shadow},function(a)
            local A,B=gun()-Vector2.new(0,u*2),front();local h=math.clamp((B-A).Magnitude*.45,u*10,u*70)
            local p=A:Lerp(B,a)-Vector2.new(0,4*h*a*(1-a))
            local dp=(B-A)-Vector2.new(0,4*h*(1-2*a))
            place(s,p);s.Rotation=math.deg(math.atan2(dp.Y,dp.X))
            local grow=1.25*(1+.45*math.sin(math.pi*a));s.Size=UDim2.fromOffset(u*5*grow,u*3*grow)
            place(shadow,A:Lerp(B,a));local k=u*(1.2+1.2*(1-math.sin(math.pi*a)));shadow.Size=UDim2.fromOffset(k*1.6,k)
        end)
    end
    local function wardenHit(e: any)
        if type(e.tile)~="number" then return end
        local front=fixed(e.tile);local u=unit()
        if (e.amount or 0)<=0 then -- the attack ended mid-air: a dust puff, no number
            sparks(front,6,{Color3.fromRGB(201,178,138),Color3.fromRGB(150,140,124)},u*5,.7,u*1.4);return
        end
        -- the blast: a white-hot core, an orange ring, dust thrown out, a dark scorch that lingers
        flash(front,Color3.new(1,1,.9),u*4,.12)
        flash(front,Color3.fromRGB(255,150,60),u*7,.35)
        sparks(front,12,{Color3.fromRGB(255,190,90),Color3.fromRGB(201,178,138),Color3.fromRGB(120,110,100)},u*9,.9,u*1.8)
        local scorch=px(Color3.fromRGB(36,28,22),u*5,.25)
        play(1.6,{scorch},function(a) place(scorch,front());scorch.BackgroundTransparency=.25+.75*a end)
        if (mine(e.owner) or mine(e.victim)) and type(e.pct)=="number" and e.pct>0 then
            pop(front,"-"..string.format("%.0f",e.pct/10).."%",RED,RED_INK,1.2,6)
        end
    end
    -- Barracks (no FX feed: the contract's packet.barracks {bonus, raw, fadeEnds}): when its raw bonus rises (you took land
    -- from a rival), the front you're attacking from flashes, blue sparks run to the hall, the hall pulses. Its ring + "+X%"
    -- are drawn every frame from packet.barracks (stepRings).
    local function barracksSurge(fromTile: number,hallTile: number)
        local strip,hall=fixed(fromTile),fixed(hallTile);local u=unit()
        flash(strip,Color3.fromRGB(200,225,255),u*3,.45)
        local run={};for k=1,6 do table.insert(run,px(Color3.fromRGB(150,195,255),math.max(1,u*1.2),0)) end
        play(.8,run,function(a)
            local A,B=strip(),hall();local d=B-A
            local bend=if d.Magnitude<1 then Vector2.zero else Vector2.new(-d.Y,d.X).Unit*math.min(d.Magnitude*.12,u*6)
            for k,f in run do
                local q=math.clamp(a*1.6-(k-1)*.1,0,1)
                place(f,A:Lerp(B,q)+bend*math.sin(math.pi*q));f.BackgroundTransparency=if q<=0 or q>=1 then 1 else 0
            end
        end,function() local b=buildingAt(hallTile,"barracks");if b then pulse(b,Color3.fromRGB(110,165,255)) end end)
    end
    -- Stock Exchange matured (event payout {amount}): the icon pulses gold, gold pixels burst out of it, a small "+gold" (owner)
    local function stockPayout(e: any)
        if type(e.tile)~="number" then return end
        local b=buildingAt(e.tile,"stock_exchange");if b then pulse(b,GOLD) end
        if not mine(e.owner) then return end
        local p=fixed(e.tile);local u=unit()
        sparks(p,10,{Color3.fromRGB(255,214,92),Color3.fromRGB(255,241,160),Color3.fromRGB(217,154,26)},u*7,.7,u*1.3)
        pop(p,"+"..short(e.amount or 0),GOLD,GOLD_INK,1.4,6,nil,true)
    end
    -- Training Camp (Take B; event train {tile, troops, cost}): the camp's own icon swells with a troop-blue glow; the owner
    -- sees "+5K" (troops ÷ 10, the HUD's units)
    local function train(e: any)
        if type(e.tile)~="number" then return end
        local b=buildingAt(e.tile,"training_camp");if b then pulse(b,Color3.fromRGB(110,165,255)) end
        if not mine(e.owner) then return end
        local p=fixed(e.tile)
        flash(p,Color3.fromRGB(120,170,255),unit()*7,.5,true)
        pop(p,"+"..short((e.troops or 0)/10),TROOP,TROOP_INK,1,5,nil,true)
    end
    -- Shipping Co. (PF - 2's fx guild_save {owner, ship, tile, by} = a raider's capture of that trade ship was just blocked):
    -- one shield pops over the ship (it rides along with it), a white flash behind, a glint sweeps it, then "Saved"
    local function guildSave(e: any)
        if not mine(e.owner) or type(e.tile)~="number" then return end
        local u=unit();local id=e.ship;local last=e.tile
        local function over(): Vector2
            for _,s in (state and state.tradeShips) or {} do
                if s.id==id and type(s.tileId)=="number" then last=s.tileId;break end
            end
            return at(last)-Vector2.new(0,u*8)
        end
        flash(over,Color3.fromRGB(205,230,255),u*9,.25)
        local sh=take("shield");sh.ClipsDescendants=true;paint(sh,PALETTE.shield,0)
        local glint=px(Color3.new(1,1,1),1,.2);glint.Parent=sh;glint.AnchorPoint=Vector2.new(.5,.5);glint.Rotation=0
        play(1.4,{glint,sh},function(a)
            local k=Math.shieldScale(a);sh.Size=UDim2.fromOffset(u*7*k,u*8*k);place(sh,over())
            local g=Math.glint(a)
            glint.Position=UDim2.fromScale(-.2+1.4*g,.5);glint.Size=UDim2.new(0,math.max(1,u*1.5),1.2,0);glint.Visible=g>0 and g<1
            local fade=Math.fade(a)
            for _,f in sh:GetChildren() do if f~=glint and f.Visible then f.BackgroundTransparency=fade end end
        end,function() glint.Parent=layer end)
        pop(function() return over()-Vector2.new(0,u*3) end,"Saved",Color3.fromRGB(190,225,255),Color3.fromRGB(10,28,52),1.3,5,nil,true)
    end
    local FX: {[string]: (any)->()}={zap=zap,shell=shell,warden_fire=wardenFire,warden=wardenHit,guild_save=guildSave}
    local FX_ITEM: {[string]: string}={zap="tesla_coil",shell="artillery",
        warden_fire="warden",warden="warden",guild_save="trade_guild"}
    -- the reshuffle's events (packet.events: notices + sounds elsewhere; these are their map moments)
    local EVENT_FX: {[string]: (any)->()}={payout=stockPayout,train=train}
    -- ------------------------------------------------------------ the launches (polish beside the placeholder's sprites)
    -- PF - 2's capture rule: an economy building changes hands ("captured"), a PvP one is "destroyed"; the captor and the
    -- victim each get a feed line and a word over the tile
    local function captureFx(e: any)
        local name=(Arsenal.byId[e.item] and Arsenal.byId[e.item].name) or "building"
        local line,color,ink,kind,glyph=nil,RED,RED_INK,"WARNING","DiplomacySoldierAttack"
        if e.kind=="captured" and mine(e.owner) then line,color,ink,kind,glyph="Captured "..name.."!",GOLD,GOLD_INK,"POSITIVE","TeamHUDClaimIcon"
        elseif e.kind=="captured" and mine(e.from) then line="Your "..name.." was captured"
        elseif e.kind=="destroyed" and mine(e.from) then line="Your "..name.." was destroyed"
        elseif e.kind=="destroyed" and mine(e.owner) then line,color,ink,kind,glyph=name.." destroyed",GOLD,GOLD_INK,"POSITIVE","TeamHUDClaimIcon" end
        -- spec §4: a Stock Exchange captured mid-investment reads as a raid (the captor takes the stake)
        if e.kind=="captured" and e.item=="stock_exchange" and type(e.raid)=="number" and e.raid>0 then
            if mine(e.owner) then line="Raided "..name.." +"..short(e.raid).." gold" elseif mine(e.from) then line=name.." raided -"..short(e.raid).." gold" end
        end
        if e.kind=="destroyed" and e.item=="stock_exchange" and mine(e.from) and type(e.lost)=="number" and e.lost>0 then
            line=name.." destroyed -"..short(e.lost).." gold"
        end
        if not line then return end
        local say=Notices.say;if say then say(line,kind,glyph,if mine(e.owner) then e.from else e.owner) end
        if type(e.tile)=="number" then
            local p=fixed(e.tile);flash(p,color,unit()*5,.25)
            pop(p,line,color,ink,2,8)
        end
    end
    local function eventFx(e: any)
        if e.kind=="captured" or e.kind=="destroyed" then captureFx(e);return end
        if type(e.tile)~="number" or not ON[e.item] then return end
        if EVENT_FX[e.kind] then EVENT_FX[e.kind](e);return end
        local u=unit();local p=fixed(e.tile)
        if e.kind=="detonate" and e.item=="titan_bomb" then -- a white flash before the orange shockwave
            local f=px(Color3.new(1,1,1),1,0);local big=zoom()*60
            play(.35,{f},function(a) place(f,p());local s=big*(.4+.6*a);f.Size=UDim2.fromOffset(s,s);f.BackgroundTransparency=a end)
        elseif e.kind=="airdrop" and e.landed then -- three parachutes float down onto the drop
            local tint=Feed.context and Feed.context.ownerColor and Feed.context.ownerColor(e.owner)
            local colors=table.clone(PALETTE.shield);colors.c=if typeof(tint)=="Color3" then tint else Color3.fromRGB(143,231,255)
            colors.k=(colors.c :: Color3):Lerp(Color3.new(0,0,0),.3);colors.x=Color3.fromRGB(230,230,230);colors.w=Color3.fromRGB(138,90,42)
            for i,off in {Vector2.new(-5,1),Vector2.new(0,-1),Vector2.new(5,2)} do
                local c=take("chute");c.Size=UDim2.fromOffset(u*7,u*9);paint(c,colors,0)
                play(1.2,{c},function(a)
                    local sway=math.sin(a*6+i)*u
                    place(c,p()+off*u+Vector2.new(sway,-u*14*(1-a)));c.Rotation=math.sin(a*6+i)*8
                    for _,f in c:GetChildren() do if f.Visible then f.BackgroundTransparency=math.clamp((a-.8)/.2,0,1) end end
                end)
            end
        elseif e.kind=="intercepted" and e.item=="airdrop" then -- the plane bursts
            sparks(p,8,{Color3.fromRGB(255,170,60),Color3.fromRGB(90,90,90),Color3.new(1,1,1)},u*6,.7)
        end
    end
    -- trails behind Blitz / Titan (each shot read from the packet, between packets interpolated)
    local trailAt: {[number]: number}={}
    local function shotPos(p: any): (Vector2,Vector2)
        local now=latest.ticks+(os.clock()-receivedAt)/STEP
        local t=math.clamp((now-p.launched)/math.max(1,p.arrive-p.launched),0,1)
        local A,B=at(p.from),at(p.to)
        return A:Lerp(B,t),(B-A).Unit
    end
    local function stepShots()
        if not latest then return end
        local seen={}
        local u=unit()
        for _,p in latest.projectiles or {} do
            if not ON[p.item] then continue end
            seen[p.id]=true
            if p.item=="blitz_bomb" or p.item=="titan_bomb" then
                local titan=p.item=="titan_bomb"
                local every=if titan then .06 else .025
                if os.clock()-(trailAt[p.id] or 0)>=every then
                    trailAt[p.id]=os.clock()
                    local head,dir=shotPos(p);local spot=head-dir*u*(if titan then 8 else 6)
                    if titan then
                        local s=u*(3+math.random()*2);local f=px(Color3.fromRGB(70+math.random(0,20),70,72),s,.15)
                        play(1.3,{f},function(a) place(f,spot);local k=s*(1+a*1.2);f.Size=UDim2.fromOffset(k,k);f.BackgroundTransparency=.15+.85*a end)
                    else
                        -- a hot white-yellow core that cools to orange and shrinks: a short, fast streak
                        local s=u*2.5;local f=px(Color3.fromRGB(255,240,170),s,0)
                        play(.4,{f},function(a)
                            place(f,spot);local k=s*(1-.6*a);f.Size=UDim2.fromOffset(k,k)
                            f.BackgroundColor3=Color3.fromRGB(255,240,170):Lerp(Color3.fromRGB(230,80,40),math.min(1,a*2));f.BackgroundTransparency=a
                        end)
                    end
                end
            end
        end
        for id in trailAt do if not seen[id] then trailAt[id]=nil end end
    end
    -- ------------------------------------------------------------ the buildings' timers
    local nextAt: {[string]: number}={}
    local function due(key: string,every: number): boolean
        local now=os.clock();local t=nextAt[key]
        if not t then nextAt[key]=now+every*(.3+math.random()*.7);return false end -- staggered first beat
        if now<t then return false end
        nextAt[key]=now+every;return true
    end
    local cityTurn=0
    local function ownStructures(): {any}
        local list={}
        for _,key in {"cities","ports","factories","defensePosts","missileSilos","samLaunchers"} do
            for _,unit_ in (state and state[key]) or {} do if mine(unit_.owner) and unit_.active~=false then table.insert(list,unit_) end end
        end
        return list
    end
    local function stepBuildings()
        if not latest or not state then return end
        local u=unit()
        local owns: {[string]: any}={}
        -- PF - 2's industry ramp (packet.industry.share: 0 until From, full from Full): the "+X/s" shows what it pays NOW,
        -- and a Bank / Tax Office that pays nothing yet stays quiet
        local share=(type(latest.industry)=="table" and tonumber(latest.industry.share)) or 1
        for _,b in latest.buildings do
            local done=latest.ticks>=b.built and ON[b.item]
            if mine(b.owner) and done then owns[b.item]=b end
            -- Bank / Tax Office, every 3 s: the icon pulses (anyone's) and, for the owner, a small "+X/s" rises off it
            local top=function() return at(b.tile)-Vector2.new(0,u*3) end
            if b.item=="bank" and done and share>0 and due("bank"..b.id,3) then
                pulse(b,GOLD)
                if mine(b.owner) then pop(top,"+"..short(MATCH.bank.GoldPerSecond*share).."/s",GOLD,GOLD_INK,1.3,5,nil,true) end
            elseif b.item=="tax_office" and done and share>0 and mine(b.owner) and due("tax"..b.id,3) then
                local levels=0
                for _,city in state.cities or {} do
                    if mine(city.owner) and city.active~=false and not city.underConstruction then levels+=city.level or 1 end
                end
                if levels>0 then
                    pulse(b,GOLD)
                    pop(top,"+"..short(MATCH.tax_office.GoldPerCityLevel*math.min(MATCH.tax_office.MaxLevels,levels)*share).."/s",GOLD,GOLD_INK,1.3,5,nil,true)
                end
            end
        end
        -- Engineering Yard: your buildings under construction get a quiet tick of work (two tiny sparks; a premium site's own
        -- icon pulses instead), and the Yard's icon pulses with them
        if owns.engineering_yard and due("yard",1.5) then
            local shown=0
            for _,s in ownStructures() do
                if shown>=6 then break end
                if s.underConstruction and type(s.tileId)=="number" then
                    shown+=1;sparks(fixed(s.tileId),2,{Color3.fromRGB(255,216,74),Color3.new(1,1,1)},u*3,.3,math.max(1,u*.8))
                end
            end
            for _,b in latest.buildings do if mine(b.owner) and latest.ticks<b.built and shown<6 then shown+=1;pulse(b,Color3.fromRGB(255,216,74)) end end
            if shown>0 then pulse(owns.engineering_yard,Color3.fromRGB(255,216,74)) end
        end
    end
    -- ------------------------------------------------------------ rings + labels that live with a building (every frame)
    -- a ring is N pixel strips round a centre, drawn beneath the icons; `fill` (0..1, clockwise from the top) shows its share
    local keep: {[string]: any}={}
    local function kept(key: string,make: ()->any): any
        local k=keep[key];if not k then k=make();keep[key]=k end
        k.seen=true;return k
    end
    local function ringParts(n: number): any
        local parts={};for _=1,n do local f=take("px");f.Parent=below;f.ZIndex=BELOW;table.insert(parts,f) end
        return {parts=parts,n=n}
    end
    local function drawRing(r: any,c: Vector2,radius: number,thick: number,color: Color3,alpha: number,fill: number,dashed: boolean)
        local seg=2*math.pi*radius/r.n
        for i,f in r.parts do
            local on=(i-.5)/r.n<=fill and (not dashed or i%2==1)
            f.Visible=on
            if on then
                local a=-math.pi/2+(i-.5)/r.n*2*math.pi
                f.Position=UDim2.fromOffset(c.X+math.cos(a)*radius,c.Y+math.sin(a)*radius);f.Rotation=math.deg(a)+90
                f.Size=UDim2.fromOffset(math.max(1,seg*(if dashed then 1 else 1.2)),thick)
                f.BackgroundColor3=color;f.BackgroundTransparency=alpha
            end
        end
    end
    local function keptText(key: string,words: string,color: Color3,ink: Color3,p: Vector2,alpha: number?): any
        local k=kept(key,function() local t=take("text");return {parts={t},t=t} end)
        local t=k.t;t.Text=words;t.TextColor3=color;t.TextSize=math.clamp(math.round(unit()*3),9,14)
        local s=t:FindFirstChildOfClass("UIStroke") :: UIStroke;s.Color=ink;fadeText(t,alpha or 0);place(t,p)
        return k
    end
    local UIS=game:GetService("UserInputService")
    local function hovered(b: any): boolean
        local markers_=world:FindFirstChild("PF044PremiumPlaceholder");local m=markers_ and markers_:FindFirstChild("P"..tostring(b.id))
        if not m or not m:IsA("GuiObject") then return false end
        local mouse=UIS:GetMouseLocation()-game:GetService("GuiService"):GetGuiInset()
        local p,s=m.AbsolutePosition,m.AbsoluteSize
        return mouse.X>=p.X and mouse.Y>=p.Y and mouse.X<=p.X+s.X and mouse.Y<=p.Y+s.Y
    end
    local function stepRings()
        for _,k in keep do k.seen=false end
        local z=zoom();local u=unit();local close=z>=2 -- zoomed right out: rings only, no words
        local base=if okRenderer then (BuildingRenderer :: any).presentationSize(z,nil) else 24
        local now=latest.ticks+(os.clock()-receivedAt)/STEP
        for _,b in latest.buildings do
            if not ON[b.item] or latest.ticks<b.built then continue end
            local c=at(b.tile);local rIcon=base*.62+u
            local bar=latest.barracks
            if b.item=="barracks" and mine(b.owner) and type(bar)=="table" and (bar.bonus or 0)>0 and type(bar.fadeEnds)=="number" then
                -- the blue ring drains with the fade ((fadeEnds - ticks) / 600 of it); "+X%" over the hall, X decaying with it
                local left=(bar.fadeEnds-now)*STEP;local atPacket=math.max(STEP,(bar.fadeEnds-latest.ticks)*STEP)
                if left>0 then
                    local r=kept("ring"..b.id,function() return ringParts(36) end)
                    drawRing(r,c,rIcon,math.max(1.5,u*1.1),Color3.fromRGB(90,150,255),0,math.clamp(left/60,0,1),false)
                    if close then keptText("lab"..b.id,"+"..string.format("%.0f",bar.bonus*100*math.clamp(left/atPacket,0,1)).."%",TROOP,TROOP_INK,c-Vector2.new(0,rIcon+u*2)) end
                end
            elseif b.item=="stock_exchange" and type(b.invest)=="table" and type(b.invest.ends)=="number" and b.invest.ends>now then
                -- the countdown ring (everyone: it reads as a raid target; red with "At risk" while an attack is close) and the
                -- time under it
                local inv=b.invest;local left=(inv.ends-now)*STEP;local risk=inv.risk==true
                local span=math.max(1,(inv.ends-(tonumber(inv.started) or inv.ends-1800))*STEP)
                local r=kept("ring"..b.id,function() return ringParts(36) end)
                drawRing(r,c,rIcon,math.max(1.5,u*1.1),if risk then RED else GOLD,0,math.clamp(left/span,0,1),false)
                if close then
                    keptText("lab"..b.id,string.format("%d:%02d",left//60,math.floor(left%60)),if risk then RED else GOLD,if risk then RED_INK else GOLD_INK,c+Vector2.new(0,rIcon+u*6))
                    if risk then keptText("risk"..b.id,"At risk",RED,RED_INK,c-Vector2.new(0,rIcon+u*2)) end
                end
            elseif b.item=="warden" then
                -- the range: a gold dashed ring, on hover, or for a moment after it fires (touch has no hover)
                local shown=hovered(b) or os.clock()<(wardenShown[b.id] or 0)
                if shown then
                    local range=(MATCH :: any).warden and (MATCH :: any).warden.Range or 66
                    local r=kept("range"..b.id,function() return ringParts(96) end)
                    local fade=if hovered(b) then 0 else math.clamp(1-((wardenShown[b.id] or 0)-os.clock())/.6,0,1)
                    drawRing(r,c,range*z,math.max(1,u*.8),Color3.fromRGB(255,206,84),.15+.85*fade,1,true)
                end
            end
        end
        for key,k in keep do if not k.seen then for _,p in k.parts do give(p) end;keep[key]=nil end end
    end
    -- ------------------------------------------------------------ packets
    local lastFx: number?=nil
    local lastEvent: number?=nil
    local lastMatch: any=nil
    local lastRaw: number?=nil;local lastSurge=0 -- the Barracks' last raw bonus, its last spark run
    local function reset() latest=nil;lastFx=nil;lastEvent=nil;lastRaw=nil;clearAll();table.clear(nextAt);table.clear(wardenShown)
        for key,k in keep do for _,p in k.parts do give(p) end;keep[key]=nil end end
    Feed.subscribe(function(p: any) if type(p)=="table" and type(p.state)=="table" then state=p.state end end)
    remotes.State.OnClientEvent:Connect(function(packet: any)
        if type(packet)~="table" then return end
        if packet.kind=="Home" then reset();return end
        if packet.kind~="Premium" then return end
        if type(packet.matchId)=="number" and type(lastMatch)=="number" and packet.matchId<lastMatch then return end -- an older match's
        if lastMatch~=nil and packet.matchId~=lastMatch then reset() end
        lastMatch=packet.matchId
        local first=latest==nil
        latest=packet;receivedAt=os.clock()
        local visible=gameUI.Visible
        -- each new fx / event once (the first packet of a match only sets the marks)
        local topFx=lastFx or 0
        local zapped: {[string]: any}={} -- one troop number per coil per zap tick (its arcs' total), at its first arc's front
        for _,e in packet.fx or {} do
            if type(e.id)~="number" then continue end
            if not first and lastFx~=nil and e.id>lastFx and visible and FX[e.kind] and ON[FX_ITEM[e.kind]] then
                FX[e.kind](e)
                if e.kind=="zap" and (mine(e.owner) or mine(e.victim)) and type(e.tile)=="number" then
                    local key=tostring(e.from)..":"..tostring(e.tick)
                    local g=zapped[key];if g then g.amount+=e.amount or 0 else zapped[key]={tile=e.tile,amount=e.amount or 0} end
                end
            end
            topFx=math.max(topFx,e.id)
        end
        lastFx=topFx
        for _,g in zapped do if g.amount>0 then pop(fixed(g.tile),"-"..short(g.amount).." troops",CYAN_CORE,Color3.fromRGB(8,40,60),1.1,5) end end
        local topEvent=lastEvent or 0
        for _,e in packet.events or {} do
            if type(e.id)~="number" then continue end
            if not first and lastEvent~=nil and e.id>lastEvent and visible then eventFx(e) end
            topEvent=math.max(topEvent,e.id)
        end
        lastEvent=topEvent
        -- Barracks: its raw bonus rose since the last packet = you took land from a rival: sparks run from the front you're
        -- attacking from to the hall (at most one run every 1.5 s)
        local bar=packet.barracks
        local raw=type(bar)=="table" and tonumber(bar.raw) or nil
        if raw and lastRaw and raw>lastRaw+1e-6 and visible and not first and ON.barracks and os.clock()-lastSurge>=1.5 and state then
            local hall=nil;for _,b in packet.buildings or {} do if b.item=="barracks" and mine(b.owner) then hall=b.tile;break end end
            local front=nil
            for _,a in state.attacks or {} do
                local t=a.targetOwner or 0;local kind=t>0 and state.players and state.players[t] and state.players[t].playerType
                if a.owner==1 and (kind=="Human" or kind=="Nation") and type(a.sourceTile)=="number" then front=a.sourceTile;break end
            end
            if hall and front then lastSurge=os.clock();barracksSurge(front,hall) end
        end
        lastRaw=raw
    end)
    Run.RenderStepped:Connect(function()
        if #active>0 then
            local now=os.clock()
            for i=#active,1,-1 do
                local e=active[i];local a=(now-e.t0)/e.dur
                if a>=1 then
                    active[i]=active[#active];active[#active]=nil
                    for _,p in e.parts do give(p) end
                    if e.done then e.done() end
                else e.step(a) end
            end
        end
        if latest and gameUI.Visible then stepShots();stepBuildings();stepRings()
        elseif next(keep) then for key,k in keep do for _,p in k.parts do give(p) end;keep[key]=nil end end
    end)
    M.debug={layer=layer,active=active,play=function(e: any) local f=FX[e.kind];if f and latest then f(e) end end}
end
return M
