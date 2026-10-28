--!strict
-- PF030 (PF - 1; Ashton picked variant A, "the ring alone"): the spawn phase. Fills the authored Game.PFSpawn (the
-- banner + the 30 s ring), the nation start pins and the landing preview (tools/atlas/author-pf030-spawn.luau).
--   the ring   drains with the seconds left (the server's choosing.deadlineTick, 10 ticks a second); amber with a soft
--              pulse in the last 5 s; when everyone present has picked it snaps full green, a check, GO, and the banner
--              reads "Starting · Everyone has picked"
--   the pins   each nation's (and every other player's) start, a small pin in its colour; tribes stay their quiet dots
--   your ring  (Ashton 2026-10-11: "I dont like the new spawn hover icon, I like it similar to openfront") no hover
--              preview. Once you have picked, OpenFront's breathing self ring sits on your start: SpawnOverlayPass +
--              spawn-overlay.frag.glsl, render-settings spawnOverlay (selfMinRad 10, selfMaxRad 30 tiles, scale
--              .5 -> 1.15 with the breath, opacity 65% -> 100%, white -> gold #FFD600 when teamless, your tint in teams,
--              animSpeed .008/ms). The radial profile is the authored texture Templates.PFSpawnBreath.
--              Click or tap spawns at once (OpenFront); a new click moves your start. No "too close" (PF - 2).
--   the dot    (Ashton 2026-10-12: "a little preview dot during the starting stage, thats just basically what your dot
--              will be when you spawn, and red if its over ocean/nonplaceable") under the cursor. Then: "the preview dot
--              should look like the image 2 dot ... the actual pixel circle". So it IS your start, pixel for pixel: the
--              tiles Simulation.spawnArea would give you (the server's own rule), painted with your territory palette
--              (fill per terrain value + the border colour, MapRenderer's words) into a small EditableImage drawn
--              Pixelated at the map's zoom. Red where you cannot start: the same pixel disc in red. Mouse / gamepad
--              only (a tap spawns at once). Templates.PFSpawnDot (an ImageLabel).
-- Data: the packet's choosing = {deadlineTick?, present, picked, allPicked, you="choosing"|"picked"|nil} (PF - 2;
-- nil once Playing). deadlineTick is nil until the first human has loaded: the ring full, no number.
-- Without the authored nodes it does nothing (MatchController keeps its heads-up line).
local UserInputService=game:GetService("UserInputService")
local AssetService=game:GetService("AssetService")
local Simulation=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Simulation"))
local GameConfig=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("OpenFrontGameConfig"))
local BeginVoteView=require(script.Parent:WaitForChild("BeginVoteView")) -- PF044: the vote to begin waits before the pick
local View={};View.__index=View
local hex=Color3.fromHex
-- UI audit build-out 2026-10-28: the shared motion kit (PF - 4's UiMotion); nil where it can't load (test fakes)
local Motion: any=(function() local ok,mod=pcall(function() return require(script.Parent.UiMotion) end);return if ok and type(mod)=="table" and type(mod.tween)=="function" then mod else nil end)()
-- the countdown's last 3 s tick the ring once a second; GO pops 1.3 -> 1 (one beat per new value)
local function beat(node: any,go: boolean,secs: number?)
    if not Motion or not node then return end
    local key=if go then "GO" elseif secs and secs<=3 then tostring(math.ceil(secs)) else nil
    if key==nil or node:GetAttribute("PFBeat")==key then return end
    node:SetAttribute("PFBeat",key)
    if go then Motion.pop(node,1.3,.2) else Motion.tick(node,1.12,.3) end
end
local WHITE,AMBER,GREEN,RED=hex("#ffffff"),hex("#ffae48"),hex("#7ee08a"),hex("#ef5350")
local GOLD=Color3.new(1,.84,0) -- OpenFront's teamless self ring (WebGLFrameBuilder.syncSpawnOverlay)
local TICKS_PER_SECOND=10
local BREATH_SPEED,SELF_MAX_RAD=8,30 -- animSpeed .008 rad/ms; selfMaxRad (tiles)

function View.new(gameUI: Instance,world: Instance?,callbacks: any?): any
    local root=gameUI:FindFirstChild("PFSpawn")
    local templates=gameUI:FindFirstChild("Templates")
    local layer=world and world:FindFirstChild("PFSpawnLayer")
    local self=setmetatable({root=root,gameUI=gameUI,templates=templates,layer=layer,callbacks=callbacks or {},pins={},breath=nil,
        dot=nil,shown=false,state=nil,started=os.clock()},View)
    self.begin=BeginVoteView.new(gameUI,callbacks) -- PF044 (no-op without Game.PFBeginVote)
    -- first-match onboarding (PF - 2): packet.tutorial.spawnHint, the start to suggest: a tile id (y*width+x+1, as state.owners)
    local okFeed,Feed=pcall(require,script.Parent.MatchPacketFeed)
    if okFeed then
        self.feedOff=Feed.subscribe(function(packet: any)
            local t=type(packet)=="table" and packet.tutorial
            if type(t)=="table" then self.hint=if type(t.spawnHint)=="number" then t.spawnHint else nil end
        end)
    end
    return self
end
function View:enabled(): boolean return self.root~=nil end

-- seconds left in the spawn phase (nil: no clock to show)
function View.secondsLeft(state: any,choosing: any?): number?
    if type(choosing)=="table" then
        if type(choosing.deadlineTick)~="number" then return nil end -- not started yet: a full ring, no number
        return math.max(0,math.ceil((choosing.deadlineTick-(state.ticks or 0))/TICKS_PER_SECOND))
    end
    -- an older server (no choosing on the packet): the old spawn-turn clock; solo has none
    local config=GameConfig.forState(state)
    if config.Match.GameType=="Singleplayer" then return nil end
    local turns=if state.gameConfig and state.gameConfig.randomSpawn then 150 else 200
    return math.max(0,math.ceil((turns-(state.ticks or 0))/TICKS_PER_SECOND))
end
function View.allPicked(choosing: any?): boolean
    if type(choosing)~="table" then return false end
    if choosing.allPicked==true then return true end
    return type(choosing.present)=="number" and choosing.present>0 and type(choosing.picked)=="number" and choosing.picked>=choosing.present
end
-- the banner's words: {title, sub}
function View.words(state: any,choosing: any?,controller: boolean): (string,string)
    if View.allPicked(choosing) then return "Starting","Everyone has picked" end
    if (state.gameConfig or {}).randomSpawn then return "Random spawn",if controller then "Placing you…" else "" end
    if not controller then return "Players are choosing","Starts soon" end
    if Simulation.tutorialMap(state) then return Simulation.TUTORIAL_SPAWN_HINT,"Click any free land" end
    if type(choosing)=="table" and choosing.you=="picked" then return "Choose your start","Start set · click to move it" end
    return "Choose your start","Click any free land"
end

-- the variant for this screen (Phone below its height)
function View:variant(): (any,boolean)
    local root=self.root
    local phone=root.AbsoluteSize.Y>0 and root.AbsoluteSize.Y<(root:GetAttribute("PFPhoneHeight") or 520)
    local desk,ph=root:FindFirstChild("Desk"),root:FindFirstChild("Phone")
    if desk then desk.Visible=not phone or ph==nil end
    if ph then ph.Visible=phone end
    return (if phone and ph then ph else desk),phone
end
local function setRing(ring: any,p: number,color: Color3)
    p=math.clamp(p,0,1)
    for _,side in {"Right","Left"} do
        local clip=ring.Drain:FindFirstChild(side);local arc=clip and clip:FindFirstChild("Arc")
        local stroke=arc and arc:FindFirstChild("Stroke");local cut=stroke and stroke:FindFirstChild("Cut")
        if stroke then stroke.Color=color;stroke.Enabled=p>0 end
        if cut then cut.Rotation=if side=="Right" then math.min(p,.5)*360 else 180+math.max(0,p-.5)*360 end
    end
end
-- UIStroke is in px: the ring's strokes follow its drawn size
local function strokes(ring: any)
    local k=ring:GetAttribute("PFStrokeK") or .08
    local t=math.max(2,ring.AbsoluteSize.X*k)
    if ring:GetAttribute("PFStrokeAt")==t then return end
    ring:SetAttribute("PFStrokeAt",t)
    ring.Track.Stroke.Thickness=t
    local glow=ring:FindFirstChild("Glow") -- a round glow: its 9-slice edges half its size (else a square)
    if glow and glow.AbsoluteSize.X>0 then glow.SliceScale=glow.AbsoluteSize.X/52 end -- (edges just under half: at half or more the centre slice inverts into a seam)
    for _,side in {"Right","Left"} do local arc=ring.Drain[side].Arc;arc.Stroke.Thickness=t end
end

-- PIVOT onboarding (tools/atlas/author-pivot-spawn.luau; Ashton approved the board): with Game.PFSpawn.Guide authored, a quiet
-- header (title, one line, the seconds + a slim bar) stands in for the PF030 banner + ring; a subtle pulse marks a good open spot
-- (land all round it, farthest from every start so far); on desktop a card names the hovered tile (terrain, nations / tribes
-- near, quiet or contested). One tap / click still places (PF030).
local function touching(): boolean return UserInputService:GetLastInputType()==Enum.UserInputType.Touch end
local function clockText(secs: number): string return string.format("%d:%02d",secs//60,secs%60) end
function View:updateGuide(state: any,o: any,guide: any)
    for _,name in {"Desk","Phone"} do local v=self.root:FindFirstChild(name);if v then v.Visible=false end end
    -- UI review 2026-10-26 (PF - 3; tools/atlas/author-pf3-pick-card.luau): the Pick card, in the tutorial mission card's
    -- language, stands in for the Header when authored; the countdown stays in it, at its right (Ashton: "keep the clock on
    -- its original place"), now a ring
    local pick=guide:FindFirstChild("Pick")
    local head=if pick then pick else guide.Header
    if pick then guide.Header.Visible=false;pick.Visible=true end
    local title,sub=View.words(state,o.choosing,self.controller)
    if title=="Choose your start" then title="Pick your start" end
    local tap=touching()
    if sub=="Click any free land" then sub=if tap then "Tap open land to place your capital." else "Click open land to place your capital." end
    if sub=="Start set · click to move it" and tap then sub="Start set · tap to move it" end
    if head.Title.Text~=title then head.Title.Text=title end
    if head.Line.Text~=sub then head.Line.Text=sub end
    local go=View.allPicked(o.choosing)
    local secs=View.secondsLeft(state,o.choosing)
    local full=if type(o.choosing)=="table" and type(o.choosing.seconds)=="number" and o.choosing.seconds>0 then o.choosing.seconds else 30
    local amber=not go and secs~=nil and secs<=5
    local color=if go then GREEN elseif amber then AMBER else hex("#ffd77a")
    if pick then
        local ring=pick.Ring;strokes(ring)
        setRing(ring,if go or secs==nil then 1 else math.clamp(secs/full,0,1),color)
        ring.Number.Text=if go then "GO" elseif secs then clockText(secs) else "";ring.Number.TextColor3=color
        beat(ring,go,secs)
        pick.Medal.Ring.Color=if go then GREEN else hex("#ffd36a")
        self.pulseRing=nil
        return
    end
    head.Time.Text=if go then "GO" elseif secs then clockText(secs) else ""
    beat(head.Time,go,secs)
    head.Time.TextColor3=color;head.Bar.Fill.BackgroundColor3=color
    head.Bar.Fill.Size=UDim2.fromScale(if go or secs==nil then 1 else math.clamp(secs/full,0,1),1)
    self.pulseRing=nil
end
-- the good spot: a land tile with land all round it (8 ways at 12 and 24 tiles) that you may start on, farthest from every
-- start so far. Recomputed when the starts change (at most every 2 s); nil on random spawn or once you have picked.
function View:goodSpot(state: any): number?
    local map=state.map;if not map then return nil end
    local starts={};local key=""
    for owner,p in state.players do if owner~=1 and type(p)=="table" and p.spawnTile then table.insert(starts,p.spawnTile);key..=p.spawnTile.."," end end
    if self.goodKey==key or (self.goodAt and os.clock()-self.goodAt<2) then return self.good end
    self.goodKey,self.goodAt=key,os.clock()
    local w,h=map.width,map.height
    -- land you can hold: the land bit, and not the impassable height 31 (live test: the dark off-map land south of the US map)
    local function land(x: number,y: number): boolean
        if x<0 or y<0 or x>=w or y>=h then return false end
        local v=buffer.readu8(map.terrain,y*w+x)
        return bit32.band(v,128)~=0 and bit32.band(v,31)~=31
    end
    local pts={};for _,t in starts do table.insert(pts,{(t-1)%w,(t-1)//w}) end
    -- the candidates (land all round, a start allowed) depend only on the map: found once per map
    if self.candidatesFor~=map then
        self.candidatesFor=map;self.candidates={}
        local step=math.max(6,math.floor(math.max(w,h)/120))
        local dirs={{-1,0},{1,0},{0,-1},{0,1},{-.7,-.7},{.7,-.7},{-.7,.7},{.7,.7}}
        for y=24,h-25,step do for x=24,w-25,step do
            if not land(x,y) then continue end
            local ok=true
            for _,r in {12,24} do for _,d in dirs do if not land(math.floor(x+d[1]*r),math.floor(y+d[2]*r)) then ok=false;break end end;if not ok then break end end
            if ok and Simulation.spawnAllowed(state,y*w+x+1) then table.insert(self.candidates,{x,y}) end
        end end
    end
    local best,bestD=nil,-1
    for _,c in self.candidates do
        local x,y=c[1],c[2];local tile=y*w+x+1
        if (state.owners[tile] or 0)>0 then continue end
        local near=math.huge;for _,p in pts do local dx,dy=p[1]-x,p[2]-y;local d=dx*dx+dy*dy;if d<near then near=d end end
        if near>bestD then best,bestD=tile,near end
    end
    self.good=best
    return best
end
-- the hovered tile's card words
local function terrainName(value: number): string
    local m=bit32.band(value,31)
    return if m<10 then "Open plains" elseif m<20 then "Highlands" else "Mountains"
end
function View:probe(state: any,tile: number): any
    local w=state.map.width;local x,y=(tile-1)%w,(tile-1)//w
    local nations,tribes,contested=0,0,false
    for owner,p in state.players do
        if owner==1 or type(p)~="table" or not p.spawnTile then continue end
        local dx,dy=(p.spawnTile-1)%w-x,(p.spawnTile-1)//w-y;local d=math.sqrt(dx*dx+dy*dy)
        if d>110 then continue end
        if p.playerType=="Bot" then tribes+=1 else nations+=1;if d<=90 then contested=true end end
    end
    return {terrain=terrainName(buffer.readu8(state.map.terrain,tile-1)),nations=nations,tribes=tribes,contested=contested}
end

-- per render: shows the prompt during Choosing (returns whether it shows; MatchController then hides its heads-up)
function View:update(state: any,o: any): boolean
    -- PF044: while the match waits for players (o.waiting) the vote card shows and the pick banner waits
    local waitingShown=self.begin:update(state,o)
    if not self.root then return waitingShown end
    self.state=state;self.choosing=o.choosing;self.controller=o.controller==true
    local show=o.ready==true and state.phase=="Choosing" and o.paused~=true and not waitingShown
    self.root.Visible=show;self.shown=show
    if not show then self:clearMarks();return waitingShown end
    local guide=self.root:FindFirstChild("Guide")
    if guide then self:updateGuide(state,o,guide);return true end
    local v,phone=self:variant()
    if not v then return false end
    local title,sub=View.words(state,o.choosing,self.controller)
    local banner=v.Banner
    if banner.Title.Text~=title then banner.Title.Text=title end
    local subNode=banner:FindFirstChild("Sub");if subNode and subNode.Text~=sub then subNode.Text=sub end
    local ring=v.Ring;strokes(ring)
    local go=View.allPicked(o.choosing)
    local secs=View.secondsLeft(state,o.choosing)
    local waiting=type(o.choosing)=="table" and secs==nil -- the 30 s not running yet
    ring.Visible=secs~=nil or go or waiting
    local amber=not go and secs~=nil and secs<=5
    local color=if go then GREEN elseif amber then AMBER else WHITE
    -- the ring drains against the phase's real length (choosing.seconds: 30, the tutorial's 10; an older server: 30)
    local full=if type(o.choosing)=="table" and type(o.choosing.seconds)=="number" and o.choosing.seconds>0 then o.choosing.seconds else 30
    setRing(ring,if go or waiting then 1 else math.clamp((secs or 0)/full,0,1),color)
    ring.Number.Visible=not go and not waiting;ring.Check.Visible=go
    ring.Number.Text=tostring(secs or 0);ring.Number.TextColor3=if amber then AMBER else hex("#f2f2f2")
    ring.Unit.Text=if go then "GO" else "SEC";ring.Unit.TextColor3=if go then GREEN elseif amber then AMBER else hex("#aeb3bb")
    ring.Unit.Visible=(go or not phone) and not waiting
    ring.Glow.Visible=go or amber;ring.Glow.ImageColor3=color
    ring.Glow.ImageTransparency=if go then .55 elseif amber then .6 else 1
    self.pulseRing=if amber then ring else nil -- the soft pulse runs in draw (per frame)
    return true
end

-- ------------------------------------------------------------------ the map marks
function View:clearMarks()
    for _,pin in self.pins do pin:Destroy() end;table.clear(self.pins)
    if self.breath then self.breath.Visible=false end
    if self.dot then self.dot.Visible=false end
    if self.pulse then self.pulse.Visible=false end
    if self.card then self.card.Visible=false end
    if self.tip then self.tip.Visible=false end
end
-- PIVOT onboarding: the good-spot pulse and (desk) the hovered tile's card, in the map layer (they pan with the map)
function View:drawGuide(state: any,zoom: number,hoverTile: number?)
    if not self.root:FindFirstChild("Guide") or not self.layer or not self.templates then return end
    local w=state.map.width
    local share=math.clamp((self.gameUI :: any).AbsoluteSize.Y/1080,.45,1) -- the screen's share (the phone standard's glyph floor)
    local me=state.players[1]
    local picked=type(me)=="table" and me.spawnTile~=nil
    -- the first match's server hint takes the good spot's place (and gets the "Click here" tip below)
    local hint=if self.hint and self.controller and not picked and self.hint>=1 and self.hint<=w*state.map.height then self.hint else nil
    local spot=if hint then hint elseif self.controller and not picked and not (state.gameConfig or {}).randomSpawn then self:goodSpot(state) else nil
    if spot and not self.pulse then
        local template=self.templates:FindFirstChild("PFGoodPulse");if template then self.pulse=template:Clone();self.pulse.Parent=self.layer end
    end
    local p=self.pulse
    if p then
        p.Visible=spot~=nil
        if spot then
            local s=(spot :: number)-1;local d=40*share
            local breath=.5+.5*math.sin((os.clock()-self.started)*3)
            p.Size=UDim2.fromOffset(d,d);p.Position=UDim2.fromOffset((s%w+.5)*zoom,(s//w+.5)*zoom)
            p.Outer.Size=UDim2.fromScale(.8+.4*breath,.8+.4*breath);p.Outer.Line.Transparency=.45+.5*breath
        end
    end
    -- the "Click here" tip over the hint (Templates.PFClickHere), bobbing gently; Tap on touch
    if hint and not self.tip then
        local template=self.templates:FindFirstChild("PFClickHere");if template then self.tip=template:Clone();self.tip.Parent=self.layer end
    end
    local tip=self.tip
    if tip then
        tip.Visible=hint~=nil
        if hint then
            local s=(hint :: number)-1
            local bob=3*math.sin((os.clock()-self.started)*4)
            -- phone = desk purely scaled: the screen's share, no floor (on an A06 a floor drew it into the Pick card)
            local k=(self.gameUI :: any).AbsoluteSize.Y/1080
            local scale=tip:FindFirstChild("PFScale");if scale then scale.Scale=k end
            tip.Position=UDim2.fromOffset((s%w+.5)*zoom,(s//w+.5)*zoom-(26+bob)*k)
            local label=tip:FindFirstChild("Label",true)
            if label and label:IsA("TextLabel") then local words=if touching() then "Tap here" else "Click here";if label.Text~=words then label.Text=words end end
        end
    end
    -- the card: mouse only (a tap places at once), on land you can see
    local tile=hoverTile
    local verdict=if tile then View.check(state,tile) else "invalid"
    local show=self.controller and not touching() and tile~=nil and verdict~="invalid" and not (state.gameConfig or {}).randomSpawn
    if show and not self.card then
        local template=self.templates:FindFirstChild("PFTileCard");if template then self.card=template:Clone();self.card.Parent=self.layer end
    end
    local c=self.card;if not c then return end
    c.Visible=show
    if not show then return end
    local info=self:probe(state,tile :: number)
    local cs=math.max(share,.65);local scale=c:FindFirstChild("PFScale");if scale then scale.Scale=cs end
    local t=(tile :: number)-1
    c.Position=UDim2.fromOffset((t%w+.5)*zoom+24*cs,(t//w+.5)*zoom+18*cs)
    c.Terrain.Text=info.terrain;c.Nations.Text=tostring(info.nations);c.Tribes.Text=tostring(info.tribes)
    local quiet=not info.contested
    local tone=if quiet then hex("#a0c4a7") else AMBER
    c.VerdictDot.BackgroundColor3=tone;c.Verdict.TextColor3=tone
    c.Verdict.Text=if quiet then "Quiet corner" else "Contested: rivals close by"
    c.Action.Text=if verdict=="taken" then "Taken" elseif verdict=="offland" then "You can't start here"
        elseif picked then "Click to move your start here" else "Click to place your capital here"
end
-- the preview dot under the cursor (see the header): your start's pixels where you can start, red where you cannot
local RED_FILL,RED_BORDER=0xFF5053EF,0xFF1C1CB7 -- #ef5350 / #b71c1c as RGBA words (R + G·256 + B·65536 + A·2^24)
local function word(c: Color3): number
    return math.round(c.R*255)+math.round(c.G*255)*256+math.round(c.B*255)*65536+4278190080
end
-- paints the n x n tiles around the hovered tile (box origin = tile - r) into the dot's EditableImage
function View:paintDot(state: any,tile: number,ok: boolean,palette: any?,color: Color3)
    local map=state.map;local w=map.width
    local radius=GameConfig.forState(state).Match.SpawnRadius or 4
    local r=math.ceil(radius)+1;local n=2*r+1
    local cx,cy=(tile-1)%w,(tile-1)//w
    if not self.dotImage or self.dotSize~=n then
        if self.dotImage then self.dotImage:Destroy() end
        self.dotImage=AssetService:CreateEditableImage({Size=Vector2.new(n,n)});self.dotSize=n
        self.dotPixels=buffer.create(n*n*4)
        if self.dotImage and self.dot then self.dot.ImageContent=Content.fromObject(self.dotImage) end
    end
    local pixels=self.dotPixels;buffer.fill(pixels,0,0)
    local inside={}
    if ok then
        for _,t in Simulation.spawnArea(state,tile,false) or {} do inside[t]=true end
    else -- the same disc spawnArea draws (centre offset -.5), every tile, in red
        for dy=-r,r do for dx=-r,r do
            local x,y=cx+dx,cy+dy
            if x>=0 and y>=0 and x<w and y<map.height and (dx+.5)^2+(dy+.5)^2<=radius^2 then inside[y*w+x+1]=true end
        end end
    end
    local border=if ok then (if palette and palette.border then palette.border else word(color)) else RED_BORDER
    for t in inside do
        local x,y=(t-1)%w,(t-1)//w
        local px,py=x-cx+r,y-cy+r
        if px<0 or py<0 or px>=n or py>=n then continue end
        local edge=not inside[t-1] or not inside[t+1] or not inside[t-w] or not inside[t+w] or x==0 or x==w-1
        local value=buffer.readu8(map.terrain,t-1)
        local fill=if ok then (if palette and palette.fill and palette.fill[value] then palette.fill[value] else word(color)) else RED_FILL
        buffer.writeu32(pixels,(py*n+px)*4,if edge then border else fill)
    end
    if self.dotImage then self.dotImage:WritePixelsBuffer(Vector2.zero,Vector2.new(n,n),pixels) end
end
function View:drawDot(state: any,zoom: number,hoverTile: number?,colors: any)
    local touch=UserInputService:GetLastInputType()==Enum.UserInputType.Touch
    local show=self.controller==true and hoverTile~=nil and not touch and not (state.gameConfig or {}).randomSpawn
    if not self.dot and show then
        local template=self.templates:FindFirstChild("PFSpawnDot")
        if template then self.dot=template:Clone();self.dot.Parent=self.layer;self.dotKey=nil end
    end
    local d=self.dot;if not d then return end
    if d.Visible~=show then d.Visible=show end
    if not show then return end
    local tile=hoverTile :: number;local w=state.map.width
    local ok=View.check(state,tile)=="ok"
    local palettes=self.callbacks.palettes and self.callbacks.palettes() or {}
    local palette=palettes[1];local color=colors[1] or GOLD
    -- repaint only when the tile, its verdict or your colours change (the owners around it change the shape too)
    local key=tile..(if ok then "+" else "-")..tostring(palette)..color:ToHex()..tostring(math.floor(os.clock()*4))
    if key~=self.dotKey then self.dotKey=key;self:paintDot(state,tile,ok,palette,color) end
    local r=(self.dotSize or 0)//2
    d.AnchorPoint=Vector2.zero
    d.Size=UDim2.fromOffset((self.dotSize or 0)*zoom,(self.dotSize or 0)*zoom)
    d.Position=UDim2.fromOffset(((tile-1)%w-r)*zoom,((tile-1)//w-r)*zoom)
end
-- "ok" | "taken" | "offland" (off the tutorial's mainland) | "invalid" (water) for a tile, and who holds it
function View.check(state: any,tile: number?): (string,number?)
    if not tile or not state or not state.map then return "invalid",nil end
    local map=state.map
    if bit32.band(buffer.readu8(map.terrain,tile-1),128)==0 then return "invalid",nil end
    if not Simulation.spawnAllowed(state,tile) then return "offland",nil end
    if (state.owners[tile] or 0)>0 then return "taken",state.owners[tile] end
    return "ok",nil
end
-- whether a click / tap sends the spawn: always (OpenFront spawns on the first click or tap; a new one moves it)
function View:confirm(_tile: number): boolean
    return true
end
-- per frame: the pins at the starts, the preview dot and your breathing ring
function View:draw(zoom: number,hoverTile: number?)
    if not self.shown then return end
    local pr=self.pulseRing
    if pr and pr.Parent then pr.Glow.ImageTransparency=1-(.25+.35*(.5+.5*math.sin((os.clock()-self.started)*math.pi*2))) end
    if not self.layer or not self.templates then return end
    local state=self.state;if not state or not state.map then return end
    local w=state.map.width
    local colors=self.callbacks.colors and self.callbacks.colors() or {}
    local seen={}
    -- UI audit build-out 2026-10-28: a pin under the pick card or the icon bar hides (it peeked out from under them)
    local covers={}
    local screen=self.gameUI and self.gameUI.AbsoluteSize or Vector2.zero
    local guide=self.root:FindFirstChild("Guide")
    for _,c in (if guide then guide:GetChildren() else {}) do
        if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.X<screen.X*.6 then table.insert(covers,c) end
    end
    local bar=self.gameUI and self.gameUI:FindFirstChild("PFIconBar");if bar and bar:IsA("GuiObject") and bar.Visible then table.insert(covers,bar) end
    local function covered(pin: any): boolean
        local p,s=pin.AbsolutePosition,pin.AbsoluteSize
        for _,c in covers do
            local q,z=c.AbsolutePosition,c.AbsoluteSize
            if p.X<q.X+z.X and p.X+s.X>q.X and p.Y<q.Y+z.Y and p.Y+s.Y>q.Y then return true end
        end
        return false
    end
    for owner,player in state.players do
        if owner==1 or type(player)~="table" or not player.spawnTile or player.playerType=="Bot" then continue end
        seen[owner]=true
        local pin=self.pins[owner]
        if not pin then
            local template=self.templates:FindFirstChild("PFSpawnPin");if not template then break end
            pin=template:Clone();pin.Name="Pin"..owner;pin.Visible=true;pin.Parent=self.layer;self.pins[owner]=pin
        end
        local color=colors[owner] or hex("#c9ced6")
        pin.Head.BackgroundColor3=color;pin.Point.BackgroundColor3=color
        local s=player.spawnTile-1
        pin.Position=UDim2.fromOffset((s%w+.5)*zoom,(s//w+.5)*zoom)
        pin.Visible=not covered(pin)
    end
    for owner,pin in self.pins do if not seen[owner] then pin:Destroy();self.pins[owner]=nil end end
    self:drawDot(state,zoom,hoverTile,colors)
    self:drawGuide(state,zoom,hoverTile)
    -- your ring (OpenFront's self breath): only once you have a start
    local me=state.players[1]
    local tile=if self.controller and type(me)=="table" then me.spawnTile else nil
    if not self.breath and tile then
        local template=self.templates:FindFirstChild("PFSpawnBreath")
        if template then self.breath=template:Clone();self.breath.Parent=self.layer end
    end
    local b=self.breath;if not b then return end
    b.Visible=tile~=nil
    if not tile then return end
    local breath=.5+.5*math.sin((os.clock()-self.started)*BREATH_SPEED)
    local d=2*SELF_MAX_RAD*(.5+.65*breath)*zoom
    local t=(tile :: number)-1
    b.Size=UDim2.fromOffset(d,d);b.Position=UDim2.fromOffset((t%w+.5)*zoom,(t//w+.5)*zoom)
    local base=if (state.gameConfig or {}).gameMode=="Team" then (colors[1] or GOLD) else GOLD
    b.ImageColor3=WHITE:Lerp(base,breath)
    b.ImageTransparency=1-(.65+.35*breath)
end
function View:destroy()
    self.begin:destroy()
    self:clearMarks()
    if self.breath then self.breath:Destroy();self.breath=nil end
    if self.dot then self.dot:Destroy();self.dot=nil end
    if self.dotImage then self.dotImage:Destroy();self.dotImage=nil end
    if self.pulse then self.pulse:Destroy();self.pulse=nil end
    if self.card then self.card:Destroy();self.card=nil end
    if self.tip then self.tip:Destroy();self.tip=nil end
    if self.feedOff then self.feedOff();self.feedOff=nil end
end
return View
