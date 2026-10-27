--!strict
-- PF044 vote to begin (PF - 3; Ashton 2026-10-24: "the vote to start is when everyone loads into the game, like after they
-- leave the lobby, since theres a lot of loading in issues for mobile users, theres a vote to literally begin the match").
-- Fills the authored Game.PFBeginVote (tools/atlas/author-pf044-begin.luau; bottom centre, one Scale + aspect layout on
-- every device): Body = a clone of the PF030 banner (PFSpawn.Desk, same size everywhere): the title, a seat per player
-- (loaded = their colour, loading = a turning arc) + "x of y loaded", the ring (the 30 s cap, or the vote's green 5);
-- under it the Vote key (+ votes/needed). Hit covers both: tap anywhere on it = vote.
-- While it shows, the match clock pill (PFIconBar.Time) waits: the clock starts at the pick.
-- Data: the packet's waiting = {seats={owner,loaded}, loaded, total, votes, needed, open, opensIn?, capIn, you, canVote}
-- (PublicMatchRuntime; nil once the pick runs). The seconds count down locally from the packet's arrival.
local Config=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local View={};View.__index=View
local hex=Color3.fromHex
local WHITE,GREEN,GREY=hex("#ffffff"),hex("#7ee08a"),hex("#c9ced6")
local COBALT_TOP,COBALT_BOTTOM,QUIET=hex("#5b93ff"),hex("#2a62e0"),hex("#181a20")

function View.new(gameUI: Instance,callbacks: any?): any
    local root=gameUI:FindFirstChild("PFBeginVote")
    local self=setmetatable({root=root,gameUI=gameUI,callbacks=callbacks or {},seats={},last=nil,at=os.clock(),voted=false,
        shown=false,hidClock=false,clockWas=true,conns={}},View)
    if root then
        root.Visible=false
        self.conns={}
        for _,name in {"Hit","Vote"} do
            local button=root:FindFirstChild(name)
            if button and button:IsA("GuiButton") then
                button:SetAttribute("PFSound",false) -- PF045 v2: only a real vote sounds (View:vote), never a tap after it
                table.insert(self.conns,button.Activated:Connect(function() self:vote() end))
            end
        end
    end
    return self
end
function View:enabled(): boolean return self.root~=nil end
function View:vote()
    local w=self.last
    if not self.shown or type(w)~="table" or w.canVote~=true or w.you==true or self.voted or w.opensIn~=nil then return end
    self.voted=true -- shown at once; the server's next packet confirms it (w.you)
    if self.callbacks.vote then self.callbacks.vote() end
    require(script.Parent.Sfx).play("u_vote")
end
-- the PF030 ring (SpawnPhaseView's drain: two half-arcs whose Cut rotates)
local function setRing(ring: any,p: number,color: Color3)
    p=math.clamp(p,0,1)
    for _,side in {"Right","Left"} do
        local clip=ring.Drain:FindFirstChild(side);local arc=clip and clip:FindFirstChild("Arc")
        local stroke=arc and arc:FindFirstChild("Stroke");local cut=stroke and stroke:FindFirstChild("Cut")
        if stroke then stroke.Color=color;stroke.Enabled=p>0 end
        if cut then cut.Rotation=if side=="Right" then math.min(p,.5)*360 else 180+math.max(0,p-.5)*360 end
    end
end
-- UIStroke is in px: strokes follow the drawn size (the ring's own PFStrokeK; the seats' rims too)
local function strokes(ring: any)
    local k=ring:GetAttribute("PFStrokeK") or .08
    local t=math.max(2,ring.AbsoluteSize.X*k)
    if ring:GetAttribute("PFStrokeAt")==t then return end
    ring:SetAttribute("PFStrokeAt",t)
    ring.Track.Stroke.Thickness=t
    local glow=ring:FindFirstChild("Glow")
    if glow and glow.AbsoluteSize.X>0 then glow.SliceScale=glow.AbsoluteSize.X/52 end
    for _,side in {"Right","Left"} do local arc=ring.Drain[side].Arc;arc.Stroke.Thickness=t end
end
-- the match clock waits for the pick
function View:clock(hide: boolean)
    local bar=self.gameUI:FindFirstChild("PFIconBar");local time=bar and bar:FindFirstChild("Time")
    if not time or not time:IsA("GuiObject") then return end
    if hide and not self.hidClock then self.hidClock=true;self.clockWas=time.Visible;time.Visible=false
    elseif not hide and self.hidClock then self.hidClock=false;time.Visible=self.clockWas end
end
function View:seat(i: number): GuiObject?
    local row=self.root.Body.Banner.Seats
    local node=self.seats[i]
    if node and node.Parent then return node end
    local template=row:FindFirstChild("Seat");if not template then return nil end
    node=template:Clone();node.Name="Seat"..i;node.LayoutOrder=i;node.Parent=row;self.seats[i]=node
    return node
end
-- per render: returns whether it shows (SpawnPhaseView then keeps the pick banner hidden)
function View:update(state: any,o: any): boolean
    local root=self.root;if not root then return false end
    local w=o.waiting
    local show=o.ready==true and state.phase=="Choosing" and o.paused~=true and type(w)=="table"
    root.Visible=show;self.shown=show;self:clock(show)
    if not show then
        if type(w)~="table" then self.voted=false;self.last=nil;self.goSounded=false end
        return false
    end
    if w~=self.last then self.last=w;self.at=os.clock() end
    if w.you==true then self.voted=true end
    local elapsed=os.clock()-self.at
    local opens=if type(w.opensIn)=="number" then math.max(0,w.opensIn-elapsed) else nil
    local cap=math.max(0,(if type(w.capIn)=="number" then w.capIn else 0)-elapsed)
    local go=opens~=nil
    if go and not self.goSounded then self.goSounded=true;require(script.Parent.Sfx).play("u_go") end -- the vote passed: starting
    local card=root.Body.Banner
    local title=if go then "Starting" else "Waiting for players"
    if card.Title.Text~=title then card.Title.Text=title end
    -- the seats: yours first (owner 1 on your wire), loaded = your colour, loading = a turning arc
    local colors=self.callbacks.colors and self.callbacks.colors() or {}
    local seats=if type(w.seats)=="table" then w.seats else {}
    local spin=(os.clock()*300)%360
    for i,seat in seats do
        local node: any=self:seat(i);if not node then break end
        node.Visible=true
        local loaded=seat.loaded==true
        node.BackgroundTransparency=if loaded then 0 else 1
        node.BackgroundColor3=colors[seat.owner] or GREY
        local rim=node:FindFirstChildOfClass("UIStroke")
        if rim then rim.Thickness=math.max(1,node.AbsoluteSize.X*.09);rim.Transparency=if not loaded then .7 elseif seat.owner==1 then 0 else .65 end
        local turn=node:FindFirstChild("Spin")
        if turn then
            turn.Visible=not loaded
            if not loaded then turn.Rotation=spin;local arc=turn:FindFirstChildOfClass("UIStroke");if arc then arc.Thickness=math.max(1.5,node.AbsoluteSize.X*.14) end end
        end
    end
    for i=#seats+1,#self.seats do if self.seats[i] then self.seats[i].Visible=false end end
    local count=card.Seats:FindFirstChild("Count")
    if count then count.Text=string.format(if go then "%d/%d in" else "%d/%d loaded",w.loaded or 0,w.total or #seats) end
    -- the ring: the cap counting down, then the vote's green 5
    local ring=root.Body.Ring;strokes(ring)
    local full=if go then (Config.PublicQueue.VoteDelay or 5) else (Config.PublicQueue.LoadCap or 30)
    local left=if go then opens or 0 else cap
    setRing(ring,left/full,if go then GREEN else WHITE)
    ring.Number.Text=tostring(math.ceil(left));ring.Number.Visible=true;ring.Number.TextColor3=hex("#f2f2f2")
    local check=ring:FindFirstChild("Check");if check then check.Visible=false end
    ring.Unit.Text="SEC";ring.Unit.Visible=true;ring.Unit.TextColor3=if go then GREEN else hex("#aeb3bb")
    local glow=ring:FindFirstChild("Glow");if glow then glow.Visible=go;glow.ImageColor3=GREEN;glow.ImageTransparency=.55 end
    -- the key: Vote to begin (cobalt) -> Voted (quiet, green rim); gone once it passed or for a spectator / a loader
    local key=root.Vote
    key.Visible=not go and w.canVote==true
    local voted=self.voted
    local label=key.Label;local text=if voted then "Voted" else "Vote to begin" -- title case: fits the 10 dp floor on an A06
    if label.Text~=text then label.Text=text end
    key.BackgroundColor3=if voted then QUIET else WHITE
    local gradient=key:FindFirstChildOfClass("UIGradient")
    if gradient then gradient.Enabled=not voted;gradient.Color=ColorSequence.new(COBALT_TOP,COBALT_BOTTOM) end
    local rim=key:FindFirstChildOfClass("UIStroke")
    if rim then rim.Enabled=voted;rim.Color=GREEN;rim.Thickness=math.max(1,key.AbsoluteSize.Y*.03) end
    -- votes / needed (only once two have loaded: a lone vote can't start it)
    local chip=key:FindFirstChild("Chip")
    if chip then
        chip.Visible=w.open==true
        local votes=(w.votes or 0)+(if voted and w.you~=true then 1 else 0)
        chip.Label.Text=string.format("%d/%d",votes,w.needed or 1)
        chip.Label.TextColor3=if voted then GREEN else WHITE
        chip.BackgroundColor3=if voted then hex("#1f3a2a") else hex("#0a1946")
    end
    return true
end
function View:destroy()
    for _,conn in self.conns do conn:Disconnect() end;table.clear(self.conns)
    self:clock(false)
    for _,node in self.seats do node:Destroy() end;table.clear(self.seats)
end
return View
