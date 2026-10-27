--!strict
-- PF019: one shared clock for the flag/crown idle loops. Bound ImageLabels show
-- an uploaded sprite sheet; each tick that changes an item's loop frame moves
-- ImageRectOffset on its labels (cheap even for every name label on the map).
-- No art generation, ownership or layout here. ReducedMotion / StaticBackground
-- on any ancestor holds that label on frame 0 (rechecked every few seconds).
local Run=game:GetService("RunService")
local Idle=require(script.Parent.CosmeticIdleArt)
local Animator={}
type Sheet={w: number,h: number,cols: number}
type Binding={id: string,sheet: Sheet,frame: number,still: boolean,destroying: RBXScriptConnection}
local bindings: {[ImageLabel]: Binding}={}
local count=0
local running: RBXScriptConnection?=nil
local clock,sinceCheck=0,0
local function motionAllowed(target: Instance): boolean
    local ancestor: Instance?=target
    while ancestor do
        if ancestor:GetAttribute("ReducedMotion")==true or ancestor:GetAttribute("StaticBackground")==true
            or ancestor:GetAttribute("MotionEnabled")==false then return false end
        ancestor=ancestor.Parent
    end
    return true
end
local function offset(sheet: Sheet,frame: number): Vector2
    return Vector2.new((frame%sheet.cols)*sheet.w,(frame//sheet.cols)*sheet.h)
end
-- Loop frame for item id at time t (seconds); exposed for tests.
function Animator.frameAt(id: string,t: number): number
    local meta=Idle.items[id]
    return math.floor(t/meta.seconds*meta.frames)%meta.frames
end
local function show(target: ImageLabel,binding: Binding,frame: number)
    if binding.frame==frame then return end
    binding.frame=frame;target.ImageRectOffset=offset(binding.sheet,frame)
end
local function step(dt: number)
    clock+=math.min(dt,.25);sinceCheck+=dt
    local recheck=sinceCheck>=3
    if recheck then sinceCheck=0 end
    local frames: {[string]: number}={}
    for target,binding in bindings do
        if recheck then binding.still=not motionAllowed(target) end
        if binding.still then show(target,binding,0);continue end
        if not target.Visible then continue end
        local frame=frames[binding.id]
        if not frame then frame=Animator.frameAt(binding.id,clock);frames[binding.id]=frame end
        show(target,binding,frame)
    end
end
local function sync()
    if count>0 and not running then running=Run.Heartbeat:Connect(step)
    elseif count==0 and running then running:Disconnect();running=nil end
end
function Animator.unbind(target: ImageLabel)
    local binding=bindings[target]
    if not binding then return end
    binding.destroying:Disconnect();bindings[target]=nil;count-=1
    target.ImageRectOffset=Vector2.zero;target.ImageRectSize=Vector2.zero
    sync()
end
-- Show item `id` from its sheet image on target and run its idle loop.
function Animator.bind(target: ImageLabel,id: string,image: string)
    local meta=assert(Idle.items[id],"No idle art for "..id)
    local sheet: Sheet={w=meta.w,h=meta.h,cols=Idle.columns(id)}
    local existing=bindings[target]
    if existing then existing.destroying:Disconnect();bindings[target]=nil;count-=1 end
    target.Image=image;target.ImageRectSize=Vector2.new(meta.w,meta.h)
    local binding: Binding={id=id,sheet=sheet,frame=-1,still=not motionAllowed(target),
        destroying=target.Destroying:Connect(function() Animator.unbind(target) end)}
    bindings[target]=binding;count+=1
    show(target,binding,if binding.still then 0 else Animator.frameAt(id,clock))
    sync()
end
function Animator.release()
    for target in bindings do Animator.unbind(target) end
    if running then running:Disconnect();running=nil end
    clock=0;sinceCheck=0
end
function Animator.debugSnapshot(): any
    return {bindings=count,running=running~=nil,clock=clock}
end
return Animator
