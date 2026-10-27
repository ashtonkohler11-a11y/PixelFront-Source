--!strict
-- PF019 W0 (Ashton): on mobile, one tap on a target sends troops at the current
-- ratio, and a small animated "−N troops" pop appears at the tap point.
-- Content and motion only: Game.Templates.PFTroopPop is authored in the place
-- (tools/atlas/author-pf019-troop-pop.luau). Each pop is a clone placed above the
-- finger so the hand doesn't cover it. Without the template the send still happens.
local TweenService=game:GetService("TweenService")
local Pop={}
Pop.__index=Pop
Pop.LIFT=.07       -- share of the screen height above the tap point
Pop.RISE=.05       -- share of the screen height it floats up
Pop.LIFETIME=.95   -- seconds on screen
Pop.FADE_AT=.45    -- seconds before the fade starts
Pop.MAX=4          -- live pops at once; the oldest goes first

-- Troops a send at `ratio` moves. Mirrors the server's PF014 home reserve
-- (Simulation.reserveClamp) using the replicated cap, so the pop matches the send.
-- reserveMax (PF043, Config.Combat.ReserveMaxOfTroops): the reserve never holds back more than this share of the troops
-- held (Simulation.reserveOf); nil = no such cap
function Pop.estimate(troops: number, cap: number, ratio: number, reserveShare: number, keepsReserve: boolean, reserveMax: number?): number
    if troops~=troops or ratio~=ratio or troops<=0 or ratio<=0 then return 0 end
    local requested=troops*ratio
    if keepsReserve then
        local reserve=math.floor(cap*reserveShare)
        if reserveMax then reserve=math.min(reserve,math.floor(troops*reserveMax)) end
        requested=math.min(requested,math.max(0,troops-reserve))
    end
    return math.max(0,math.floor(requested))
end
function Pop.text(sent: number, format: (number)->string): string
    return "<b>\u{2212}"..format(sent).."</b> <font color=\"#cbd5e1\">troops</font>"
end
function Pop.new(gameUI: any, services: any?)
    local s=services or {}
    return setmetatable({ui=gameUI,active={},tween=s.tween or function(target,info,goals)TweenService:Create(target,info,goals):Play()end,
        delay=s.delay or task.delay},Pop)
end
function Pop:template(): any?
    local templates=self.ui:FindFirstChild("Templates")
    local template=templates and templates:FindFirstChild("PFTroopPop")
    return if template and template:IsA("TextLabel")then template else nil
end
function Pop:show(screen: Vector2, sent: number, format: (number)->string): any?
    local template=self:template()
    local size,origin=self.ui.AbsoluteSize,self.ui.AbsolutePosition
    if not template or sent<1 or size.X<=0 or size.Y<=0 then return nil end
    local x=math.clamp(screen.X-origin.X,size.X*.08,size.X*.92)
    local y=math.max(size.Y*.08,screen.Y-origin.Y-size.Y*Pop.LIFT)
    local pop=template:Clone()
    pop.Name="PFTroopPopLive";pop.Text=Pop.text(sent,format);pop.Position=UDim2.fromOffset(x,y);pop.Visible=true
    pop.Parent=self.ui
    table.insert(self.active,pop)
    while #self.active>Pop.MAX do table.remove(self.active,1):Destroy()end
    local scale=pop:FindFirstChildOfClass("UIScale")
    if scale then
        scale.Scale=.6
        self.tween(scale,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
    end
    self.tween(pop,TweenInfo.new(Pop.LIFETIME,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(x,y-size.Y*Pop.RISE)})
    local fade=TweenInfo.new(Pop.LIFETIME-Pop.FADE_AT,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,Pop.FADE_AT)
    self.tween(pop,fade,{TextTransparency=1})
    local stroke=pop:FindFirstChildOfClass("UIStroke")
    if stroke then self.tween(stroke,fade,{Transparency=1})end
    self.delay(Pop.LIFETIME+.05,function()
        local index=table.find(self.active,pop)
        if index then table.remove(self.active,index)end
        pop:Destroy()
    end)
    return pop
end
function Pop:clear()
    for _,pop in self.active do pop:Destroy()end
    self.active={}
end
return Pop
