--!strict
-- PF - 4 (UI lock-in BUILD-OUT, Ashton 2026-10-28: "just build it all"): the ONE shared UI motion kit. Sheets and pages open and
-- close, numbers count up, lists stagger in, buttons get hover/press juice, things pop, tick, breathe, sheen and shake, all
-- through here, so every screen feels the same (Rivals snap .12-.25 s, PS99 count-ups .4-.6 s; timings: UiMotionMath).
-- Rules it keeps for every caller:
--   R4  every scale is a UIScale, so a node with AnchorPoint .5,.5 grows from its centre (Studio warns once per node that
--       isn't centred, unless the node says its anchor is deliberate: attribute PFMotionAnchor=true). The kit never sizes anything. A node a list/grid layout places never gets a UIScale (it would reflow
--       its row): a kit card scales its PFCardBody.PFCardScale, anything else laid out is left still. A node that already
--       has another UIScale (a layout one) is left still too.
--   Statics: a node's motion scale is a UIScale named PFMotionScale (or an installer's PFHover / PFPop / PFPress); an installer
--       may author it, else the kit adds a PFMotionScale once.
--   Reduced motion (settings.reducedMotion via setPreferences, or ReducedMotion=true / MotionEnabled=false on an
--       ancestor): every change lands at once, loops don't run.
--   Never in the way: a tap / click anywhere finishes what's running (opens, closes, count-ups, staggers, pops). Nothing
--       here blocks input; a closing sheet hides itself after .1 s.
-- API (node = a GuiObject):
--   UiMotion.open(node, {scrim?, from?})          show + pop .94 -> 1 (Back .2 s); a CanvasGroup fades too; a scrim fades in
--   UiMotion.close(node, {scrim?}, done?)         .1 s to .96 (+ fade), then Visible=false, then done()
--   UiMotion.count(label, to, {from?, time?, prefix?, suffix?, format?})
--                                                 count from the last shown value (first call: lands at once unless from)
--   UiMotion.stagger(nodes, {from?, step?})       entrance: each scales .92 -> 1 (Quart .18 s), 30 ms apart (<= .3 s total)
--   UiMotion.press(button, {hover?, press?, target?, scale?, rest?}) -> handle   hover 1.03 / focus, press .95, release Back;
--                                                 rest = the resting scale (number or function); handle.refresh(), handle.Disconnect()
--   UiMotion.sparkle(node, color?)                the Shop buy's four-star twinkle inside node (.45 s, temporary)
--   UiMotion.pair(cards, {grow?, give?, targets?}) -> handle      paired hover: hovered 1.02, the rest .985 (R4)
--   UiMotion.pop(node, peak?, time?)              one-shot peak -> 1 (Back)
--   UiMotion.tick(node, peak?, time?)             1 -> peak -> 1
--   UiMotion.shake(node, px?, time?)              a short sideways nudge (Position; put back after)
--   UiMotion.fill(bar, share, {axis?, time?})     a bar's fill eases to share (Size scale; content, not layout)
--   UiMotion.sweep(gradient, time?)               one sheen pass: UIGradient Offset.X -1.2 -> 1.2
--   UiMotion.breathe(node, {period?, amp?}) -> stop()     scale 1 <-> 1+amp (default 2.4 s, .03) while visible
--   UiMotion.sheen(gradient, {period?, sweep?}) -> stop() a sheen every period (default 4.5 s) while visible
--   UiMotion.every(node, period, fn) -> stop()           fn(node) every period s while visible (e.g. a coin tick)
--   UiMotion.glow(stroke, {lo?, hi?, period?}) -> stop()  a rim's Transparency breathes lo <-> hi while visible
--   UiMotion.tween(node, props, time, style?, dir?)       a plain tween that respects reduced motion
--   UiMotion.reduced(node?), UiMotion.setPreferences(prefs), UiMotion.skipAll(), UiMotion.scaleOf(node, create?)
local Run=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Input=game:GetService("UserInputService")
local Math=require(script.Parent.UiMotionMath)
local Motion={}
Motion.Math=Math
local prefs: any=nil
local warned: {[Instance]: boolean}=setmetatable({},{__mode="k"}) :: any
local serial: {[Instance]: number}=setmetatable({},{__mode="k"}) :: any
-- running "sequence" motion a tap finishes: {tween, node, goal, after?}
local running: {[any]: any}={}
local counts: {[Instance]: any}={}
local loops: {[any]: any}={}
local shakes: {[Instance]: any}={}
local beat: RBXScriptConnection?=nil
local lastVis=0

function Motion.setPreferences(p: any) prefs=p end
function Motion.reduced(node: Instance?): boolean
    if prefs then
        local ok,v=pcall(function() return prefs:get("reducedMotion") end)
        if ok and v==true then return true end
    end
    local n: Instance?=node
    while n do
        if n:GetAttribute("ReducedMotion")==true or n:GetAttribute("MotionEnabled")==false then return true end
        n=n.Parent
    end
    return false
end
local function shown(node: Instance): boolean
    local n: Instance?=node
    while n do
        if n:IsA("GuiObject") and not n.Visible then return false end
        if n:IsA("LayerCollector") then return n.Enabled end
        n=n.Parent
    end
    return false
end
local function laidOut(node: Instance): boolean
    local p=node.Parent
    return p~=nil and p:FindFirstChildWhichIsA("UIGridStyleLayout")~=nil
end
-- the UIScale a node animates with (see the header); nil = leave it still
local MOTION_SCALES={"PFMotionScale","PFHover","PFHoverScale","PFPop","PFPress"} -- the installers' own motion UIScales
function Motion.scaleOf(node: GuiObject,create: boolean?): UIScale?
    for _,name in MOTION_SCALES do
        local own=node:FindFirstChild(name)
        if own and own:IsA("UIScale") then return own end
    end
    local body=node:FindFirstChild("PFCardBody");local cs=body and body:FindFirstChild("PFCardScale")
    if cs and cs:IsA("UIScale") then return cs end
    if laidOut(node) then return nil end
    if node:FindFirstChildWhichIsA("UIScale") then return nil end
    if create==false then return nil end
    -- (an anchor kept on purpose, e.g. an aspect-constrained tray that can't re-anchor without moving: PFMotionAnchor=true)
    if Run:IsStudio() and not warned[node] and node.AnchorPoint~=Vector2.new(.5,.5) and node:GetAttribute("PFMotionAnchor")~=true then
        warned[node]=true;warn("[UiMotion] "..node:GetFullName().." scales from AnchorPoint "..tostring(node.AnchorPoint).." (R4 wants .5,.5)")
    end
    local s=Instance.new("UIScale");s.Name="PFMotionScale";s.Parent=node
    return s
end

local function step(dt: number)
    local now=os.clock()
    for label,c in counts do
        local v=Math.count(c.from,c.to,now-c.start,c.time)
        if v~=c.shown then c.shown=v;(label :: any).Text=c.render(v) end
        if v==c.to then counts[label]=nil;label:SetAttribute("PFCountValue",c.to) end
    end
    for node,s in shakes do
        local x=Math.shake(now-s.start,s.time,s.px)
        if now-s.start>=s.time then shakes[node]=nil;(node :: any).Position=s.base
        else (node :: any).Position=s.base+UDim2.fromOffset(math.round(x),0) end
    end
    local check=now-lastVis>=.25
    if check then lastVis=now end
    for key,l in loops do
        if check then
            local on=l.node.Parent~=nil and shown(l.node) and not Motion.reduced(l.node)
            if on~=l.on then l.on=on;if not on then l.rest() end end
            if l.node.Parent==nil then loops[key]=nil end
        end
        if l.on then l.frame(now-l.start) end
    end
    if next(counts)==nil and next(shakes)==nil and next(loops)==nil and beat then beat:Disconnect();beat=nil end
end
local function wake() if not beat then beat=Run.Heartbeat:Connect(step) end end

-- a plain tween that lands at once under reduced motion; seq=true: a tap finishes it
local function play(node: Instance,props: {[string]: any},time: number,style: Enum.EasingStyle?,dir: Enum.EasingDirection?,seq: boolean?,after: (()->())?,delay: number?): Tween?
    if time<=0 or Motion.reduced(node) then
        for k,v in props do (node :: any)[k]=v end
        if after then after() end
        return nil
    end
    local t=TweenService:Create(node,TweenInfo.new(time,style or Enum.EasingStyle.Quad,dir or Enum.EasingDirection.Out,0,false,delay or 0),props)
    if seq then
        local rec={tween=t,node=node,goal=props,after=after}
        running[rec]=true
        t.Completed:Once(function(state)
            if running[rec] then running[rec]=nil;if state==Enum.PlaybackState.Completed and after then after() end end
        end)
    elseif after then t.Completed:Once(function(state) if state==Enum.PlaybackState.Completed then after() end end) end
    t:Play()
    return t
end
function Motion.tween(node: Instance,props: {[string]: any},time: number,style: Enum.EasingStyle?,dir: Enum.EasingDirection?): Tween?
    return play(node,props,time,style,dir)
end
-- a tap / click finishes every running sequence (opens, closes, pops, staggers, count-ups)
function Motion.skipAll()
    for rec in running do
        running[rec]=nil;rec.tween:Cancel()
        for k,v in rec.goal do (rec.node :: any)[k]=v end
        if rec.after then rec.after() end
    end
    for label,c in counts do counts[label]=nil;(label :: any).Text=c.render(c.to);label:SetAttribute("PFCountValue",c.to) end
end
Input.InputBegan:Connect(function(input: InputObject)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then Motion.skipAll() end
end)

local function scrimBase(scrim: GuiObject): number
    local b=scrim:GetAttribute("PFMotionBase")
    if type(b)~="number" then b=scrim.BackgroundTransparency;scrim:SetAttribute("PFMotionBase",b) end
    return b :: number
end
function Motion.open(node: GuiObject,opts: any?)
    local o=opts or {}
    serial[node]=(serial[node] or 0)+1
    local scrim: GuiObject?=o.scrim
    local s=Motion.scaleOf(node)
    node.Visible=true
    if scrim then local b=scrimBase(scrim);scrim.Visible=true;scrim.BackgroundTransparency=if Motion.reduced(node) then b else 1;play(scrim,{BackgroundTransparency=b},Math.SCRIM,nil,nil,true) end
    if s then s.Scale=if Motion.reduced(node) then 1 else (o.from or Math.FROM);play(s,{Scale=1},Math.OPEN,Enum.EasingStyle.Back,Enum.EasingDirection.Out,true) end
    if node:IsA("CanvasGroup") then node.GroupTransparency=if Motion.reduced(node) then 0 else 1;play(node,{GroupTransparency=0},Math.OPEN*.8,nil,nil,true) end
end
function Motion.close(node: GuiObject,opts: any?,done: (()->())?)
    local o=opts or {}
    local mine=(serial[node] or 0)+1;serial[node]=mine
    local scrim: GuiObject?=o.scrim
    local s=Motion.scaleOf(node)
    local function finish()
        if serial[node]~=mine then return end -- opened again meanwhile
        node.Visible=false
        if s then s.Scale=1 end
        if node:IsA("CanvasGroup") then node.GroupTransparency=0 end
        if scrim then scrim.Visible=false;scrim.BackgroundTransparency=scrimBase(scrim) end
        if done then done() end
    end
    if not node.Visible or Motion.reduced(node) then finish();return end
    if scrim then scrimBase(scrim);play(scrim,{BackgroundTransparency=1},Math.CLOSE,nil,Enum.EasingDirection.In,true) end
    if node:IsA("CanvasGroup") then play(node,{GroupTransparency=1},Math.CLOSE,nil,Enum.EasingDirection.In,true) end
    if s then play(s,{Scale=Math.CLOSE_TO},Math.CLOSE,nil,Enum.EasingDirection.In,true,finish)
    elseif not node:IsA("CanvasGroup") then finish()
    else task.delay(Math.CLOSE,finish) end
end
function Motion.count(label: TextLabel,to: number,opts: any?)
    local o=opts or {}
    local render=o.format or function(v: number) return (o.prefix or "")..Math.commas(v)..(o.suffix or "") end
    local last=label:GetAttribute("PFCountValue")
    local from=if type(o.from)=="number" then o.from elseif counts[label] then counts[label].shown elseif type(last)=="number" then last else nil
    counts[label]=nil
    if from==nil or from==to or Motion.reduced(label) then label.Text=render(to);label:SetAttribute("PFCountValue",to);return end
    counts[label]={from=from,to=to,start=os.clock(),time=o.time or Math.COUNT,render=render,shown=from}
    label.Text=render(from);wake()
end
function Motion.stagger(nodes: {GuiObject},opts: any?)
    local o=opts or {}
    local list={}
    for _,n in nodes do if n.Visible then table.insert(list,n) end end
    for i,n in list do
        local s=Motion.scaleOf(n);if not s then continue end
        if Motion.reduced(n) then s.Scale=1;continue end
        s.Scale=o.from or Math.ENTER_FROM
        play(s,{Scale=1},Math.ENTER,Enum.EasingStyle.Quart,Enum.EasingDirection.Out,true,nil,Math.delay(i,#list,o.step))
    end
end
function Motion.pop(node: GuiObject,peak: number?,time: number?)
    local s=Motion.scaleOf(node);if not s or Motion.reduced(node) then return end
    s.Scale=peak or 1.08
    play(s,{Scale=1},time or Math.POP,Enum.EasingStyle.Back,Enum.EasingDirection.Out,true)
end
function Motion.tick(node: GuiObject,peak: number?,time: number?)
    local s=Motion.scaleOf(node);if not s or Motion.reduced(node) then return end
    local t=TweenService:Create(s,TweenInfo.new((time or Math.TICK)/2,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true),{Scale=peak or 1.12})
    t:Play()
end
function Motion.shake(node: GuiObject,px: number?,time: number?)
    if Motion.reduced(node) or laidOut(node) then return end
    local s=shakes[node]
    shakes[node]={base=if s then s.base else node.Position,start=os.clock(),time=time or Math.SHAKE,px=px or Math.SHAKE_PX}
    wake()
end
function Motion.fill(bar: GuiObject,share: number,opts: any?)
    local o=opts or {}
    share=math.clamp(share,0,1)
    local size=bar.Size
    local goal=if o.axis=="Y" then UDim2.new(size.X,UDim.new(share,0)) else UDim2.new(UDim.new(share,0),size.Y)
    play(bar,{Size=goal},o.time or Math.FILL)
end
function Motion.sweep(gradient: UIGradient,time: number?)
    if Motion.reduced(gradient) then return end
    gradient.Offset=Vector2.new(-1.2,gradient.Offset.Y)
    play(gradient,{Offset=Vector2.new(1.2,gradient.Offset.Y)},time or Math.SWEEP,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
end
local function loop(node: Instance,frame: (number)->(),rest: ()->()): ()->()
    local key={}
    loops[key]={node=node,frame=frame,rest=rest,start=os.clock(),on=false}
    lastVis=0;wake()
    return function() if loops[key] then loops[key]=nil;rest() end end
end
function Motion.breathe(node: GuiObject,opts: any?): ()->()
    local o=opts or {}
    local s=Motion.scaleOf(node);if not s then return function() end end
    local period,amp=o.period or 2.4,o.amp or .03
    return loop(node,function(t) s.Scale=Math.breathe(t,period,amp) end,function() s.Scale=1 end)
end
function Motion.sheen(gradient: UIGradient,opts: any?): ()->()
    local o=opts or {}
    local period,sweep=o.period or 4.5,o.sweep or 1.1
    local host=gradient.Parent or gradient
    return loop(host,function(t) gradient.Offset=Vector2.new(Math.sheen(t,period,sweep),gradient.Offset.Y) end,
        function() gradient.Offset=Vector2.new(1.2,gradient.Offset.Y) end)
end
-- a rim that glows softly: a UIStroke's Transparency breathes lo <-> hi (default 0 <-> .55, 2.4 s) while its owner shows
function Motion.glow(stroke: UIStroke,opts: any?): ()->()
    local o=opts or {}
    local lo,hi,period=o.lo or 0,o.hi or .55,o.period or 2.4
    local host=stroke.Parent or stroke
    return loop(host,function(t) stroke.Transparency=lo+(hi-lo)*(Math.breathe(t,period,1)-1) end,function() stroke.Transparency=lo end)
end
function Motion.every(node: GuiObject,period: number,fn: (GuiObject)->()): ()->()
    local last=-1
    return loop(node,function(t) local k=math.floor(t/period);if k~=last then last=k;if k>0 then fn(node) end end end,function() last=-1 end)
end

-- a success twinkle: the Shop buy's four small sparkles (ShopBuyFx's star cell) inside the node, .45 s, then gone (temporary)
local SPARK_SHEET,SPARK_CELL="rbxassetid://118312288651391",{Vector2.new(640,64),Vector2.new(128,128)}
local SPARKS={{.15,.12,.05,.10,.30},{.85,.45,.04,.12,.30},{.8,.88,.035,.18,.26},{.1,.7,.03,.20,.22}}
function Motion.sparkle(node: GuiObject,color: Color3?)
    if Motion.reduced(node) or not node.Parent then return end
    local holder=Instance.new("Frame");holder.Name="PFMotionSparkles";holder.BackgroundTransparency=1;holder.Size=UDim2.fromScale(1,1)
    holder.ZIndex=node.ZIndex+20;holder.Active=false
    local w=node.AbsoluteSize.X;local list={}
    for i,s in SPARKS do
        local img=Instance.new("ImageLabel");img.Name="Sparkle"..i;img.BackgroundTransparency=1;img.Image=SPARK_SHEET
        img.ImageRectOffset=SPARK_CELL[1];img.ImageRectSize=SPARK_CELL[2];img.ImageColor3=color or Color3.fromHex("#cfe3ff")
        img.ScaleType=Enum.ScaleType.Fit;img.AnchorPoint=Vector2.new(.5,.5);img.Position=UDim2.fromScale(s[1],s[2]);img.ZIndex=holder.ZIndex
        img.Visible=false;img.Parent=holder
        table.insert(list,{img=img,side=s[3]*w*128/52,start=s[4],life=s[5]})
    end
    holder.Parent=node
    local key={}
    loops[key]={node=node,on=true,start=os.clock(),rest=function() holder:Destroy() end,frame=function(t: number)
        for _,s in list do
            local k=(t-s.start)/s.life;s.img.Visible=k>0 and k<1
            if k>0 and k<1 then local wave=math.sin(math.pi*k);local size=s.side*wave^.6;s.img.Size=UDim2.fromOffset(size,size);s.img.ImageTransparency=1-wave^.4;s.img.Rotation=20*k end
        end
        if t>.5 then loops[key]=nil;holder:Destroy() end
    end}
    wake()
end
-- hover / focus / press juice for one button (R4: its own centred scale, or opts.target's / opts.scale)
function Motion.press(button: GuiObject,opts: any?): any
    local o=opts or {}
    local s: UIScale?=o.scale or (if o.target then Motion.scaleOf(o.target) else Motion.scaleOf(button))
    local cons={}
    local handle: any={Disconnect=function() for _,c in cons do c:Disconnect() end;table.clear(cons) end,refresh=function() end}
    if not s then return handle end
    local scale=s :: UIScale
    local hot,down=false,false
    -- o.rest: the scale at rest (a number, or a function: a selected card holds 1.03); handle.refresh() re-reads it
    local function rest(): number return if type(o.rest)=="function" then o.rest() elseif type(o.rest)=="number" then o.rest else 1 end
    local function look()
        local goal=if down then (o.press or Math.PRESS) elseif hot then math.max(o.hover or Math.HOVER,rest()) else rest()
        if down then play(scale,{Scale=goal},Math.PRESS_TIME)
        else play(scale,{Scale=goal},if hot then Math.HOVER_TIME else Math.RELEASE,if hot then nil else Enum.EasingStyle.Back) end
    end
    handle.refresh=look
    local function on(sig: RBXScriptSignal,fn: any) table.insert(cons,sig:Connect(fn)) end
    on(button.MouseEnter,function() if Input.PreferredInput~=Enum.PreferredInput.Touch then hot=true;look() end end)
    on(button.MouseLeave,function() hot=false;down=false;look() end)
    on(button.SelectionGained,function() hot=true;look() end)
    on(button.SelectionLost,function() hot=false;look() end)
    on(button.InputBegan,function(input: InputObject)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then down=true;look() end
    end)
    on(button.InputEnded,function(input: InputObject)
        if down and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA) then
            down=false;if input.UserInputType==Enum.UserInputType.Touch then hot=false end;look()
        end
    end)
    return handle
end
-- paired hover (R4): the hovered card grows, its siblings give way
function Motion.pair(cards: {GuiObject},opts: any?): any
    local o=opts or {}
    local scales={}
    for i,c in cards do local t=o.targets and o.targets[i] or c;scales[i]=Motion.scaleOf(t) end
    local cons={}
    local hot: number?=nil
    local function paint() for i,s in scales do play(s,{Scale=Math.pair(i,hot,o.grow,o.give)},Math.PAIR_TIME) end end
    for i,c in cards do
        table.insert(cons,c.MouseEnter:Connect(function() if Input.PreferredInput~=Enum.PreferredInput.Touch then hot=i;paint() end end))
        table.insert(cons,c.MouseLeave:Connect(function() if hot==i then hot=nil;paint() end end))
        table.insert(cons,c.SelectionGained:Connect(function() hot=i;paint() end))
        table.insert(cons,c.SelectionLost:Connect(function() if hot==i then hot=nil;paint() end end))
    end
    return {Disconnect=function() for _,c in cons do c:Disconnect() end;table.clear(cons) end}
end
return Motion
