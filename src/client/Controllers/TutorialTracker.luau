--!strict
-- PF027 (PF - 1; Ashton: "Good, build"): the in-match tutorial tracker, to the approved board
-- (docs/director/mockups/PF027/PF027-tutorial.png). It fills the nodes tools/atlas/author-pf027-tracker.luau
-- authors (Game.PFTracker: Desk, Phone) from TutorialTrackerModel's view; it never builds or sizes layout.
--   * always open (no fold): Desk on desktop, the Phone strip on short screens (the authored variant, picked)
--   * one grid for all 7 steps: STEP n/7 + segments, a hero tile in real game art, the goal line, ONE progress item:
--     Save (numbers + a bar toward the target, whose art rides the bar's end; Ready: "Ready, build it!" + the key),
--     Track (the nuke's 4 stops SAVE → BUILD → ARM → FIRE), Act (step 1's one action)
--   * the saving target is the hero: the map sprite on your plate with its price tag (City, Missile Silo, Atom Bomb)
--   * step done (1.1 s, no particles): the bar lands, a sweep crosses (.12), the stamp lands (.26, ×1.6 → 1.14 → 1,
--     the chime), the segment turns gold (.6), the next step slides in already live (.85). A step that was already true
--     when it came up: a quick check (.5 s). Reduced motion: no sweep or slide; the stamp fades in still.
--   * the live tick: when the bar grows, its edge flashes and "+0.4K" rises under it (held under reduced motion)
--   * final: the win's stamp, then the PF021 reward card (Game.PFTutorialReward) before the match-end screen.
-- Every motion is a pose of time (Tracker.now), so QA can freeze any frame.
-- UI review 2026-10-26 (PF - 3; Ashton approved the mission card: "Good, build it"): with Game.PFTracker.Mission authored
-- (tools/atlas/author-pf3-mission-card.luau) the step is a mission card in the slim strip's place: the step's glyph in its
-- colour, STEP n OF 7, the goal, one line (the stage's action for the nuke and the fights), the live progress or step 1's
-- action, the seven steps along its foot; a finished step stamps ("15K TROOPS ✓"); the last step shows its 500 Cobalt.
local Run=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Art=require(Shared.TutorialTrackerArt)
local Icons=require(Shared.PixelFrontIconAssets)
local Tracker={};Tracker.__index=Tracker
Tracker.now=os.clock
local STEPS=#Art.Steps
local QUICK=.5
local PAYOFF=1.1
local SPRITE={City="rbxassetid://73205582263885",MissileSilo="rbxassetid://127047540763704",["Atom Bomb"]=Icons.AtomBomb_White}
local C={gold="#ffd77a",coin="#ddbf76",label="#9aa1ab",dim="#5d636c",track="#3a3d44",amber="#ffae48",you="#b46ee0",youDeep="#6d3d8c",
    grey="#6b6f78",greyDeep="#3d4047",done="#d8c3a0"}
local function c3(value: string): Color3 return Color3.fromHex(value) end
local function clamp01(x: number): number return math.clamp(x,0,1) end
local function outCubic(x: number): number x=clamp01(x);return 1-(1-x)^3 end
local function outBack(x: number): number x=clamp01(x);local k=1.7;return 1+(k+1)*(x-1)^3+k*(x-1)^2 end
local function seq(a: string,b: string): ColorSequence return ColorSequence.new(c3(a),c3(b)) end

-- The tribe / nation bar in the target's map colour (MM: the same as the chip and the hero), the step colour without one:
-- a lit top to a deep end, like the other bars.
function Tracker.targetBar(view: any): ColorSequence
    local goal=view.goal or {}
    local value=goal.ownerColor or view.color or "#e0607e"
    local base=if typeof(value)=="Color3" then value else c3(value)
    return ColorSequence.new(base:Lerp(Color3.new(1,1,1),.35),base:Lerp(Color3.new(0,0,0),.3))
end
-- A hard-cut fill (the helper's fill()): show `f` of it.
function Tracker.setFill(item: Instance?,f: number)
    local cut=item and item:FindFirstChild("Cut")
    if cut then (cut :: UIGradient).Offset=Vector2.new(clamp01(f)-.5,0) end
end
-- Ring arc: p of the circle from 12 o'clock, clockwise (the helper's ring()).
function Tracker.setRing(ring: Instance?,p: number,color: Color3?)
    if not ring then return end
    p=clamp01(p)
    for _,side in {"Right","Left"} do
        local clip=ring:FindFirstChild(side);local arc=clip and clip:FindFirstChild("Arc")
        local stroke=arc and arc:FindFirstChildOfClass("UIStroke");local cut=stroke and stroke:FindFirstChild("Cut")
        if stroke and color then (stroke :: UIStroke).Color=color end
        if cut then (cut :: UIGradient).Rotation=if side=="Right" then math.min(p,.5)*360 else 180+math.max(0,p-.5)*360 end
        if stroke then (stroke :: UIStroke).Enabled=p>0 end
    end
end
local function setText(label: Instance?,value: string,color: Color3?)
    if not label then return end
    local l=label :: TextLabel
    if l.Text~=value then l.Text=value end
    if color then l.TextColor3=color end
end
-- 0.4K / 12.5K / 1.20M: the HUD's short figures (for the tick)
local function short(v: number): string
    v=math.max(0,v)
    local function fig(x: number): string
        if x>=100 then return string.format("%d",math.floor(x+1e-9)) elseif x>=10 then return string.format("%.1f",math.floor(x*10+1e-9)/10) end
        return string.format("%.1f",math.floor(x*10+1e-9)/10)
    end
    if v>=1e6 then return fig(v/1e6).."M" elseif v>=1e3 then return fig(v/1e3).."K" end
    return tostring(math.floor(v))
end
local function plain(eta: any): string -- the model's etaText, or its older "≈ 41 s"
    if type(eta)~="string" then return "" end
    return (string.gsub(eta,"^≈%s*",""))
end

function Tracker.new(gameUI: any,context: any): any?
    local root=gameUI:FindFirstChild("PFTracker")
    if not root then return nil end
    local self: any=setmetatable({gameUI=gameUI,root=root,context=context or {},reward=gameUI:FindFirstChild("PFTutorialReward"),
        desk=root.Desk,phone=root.Phone,slim=root:FindFirstChild("Slim"),mission=root:FindFirstChild("Mission"),shown=false,isPhone=false,view=nil,display=nil,payoff=nil,queue={},rewardShown=false,rewardDismissed=false,
        connections={},destroyed=false,last=nil,tickAt=nil,tickText="",base={}},Tracker)
    -- the authored rest positions of what slides (the payoff's last beat)
    for _,v in {self.desk,self.phone} do
        for _,name in {"Title","Tile","Progress","Save","Track","Act"} do
            local node=v:FindFirstChild(name);if node then self.base[node]=node.Position end
        end
    end
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    listen(gameUI:GetPropertyChangedSignal("AbsoluteSize"),function() self:layout() end)
    if self.reward then
        local card=self.reward.Holder.Fit.Card
        listen(card.Play.Activated,function() self:leave() end)
        listen(card.Back.Activated,function() self:leave() end)
    end
    self:layout()
    return self
end
function Tracker:reduced(): boolean
    local ok,value=pcall(function() return self.context.reduced and self.context.reduced() end)
    return ok and value==true
end
function Tracker:play(cue: string) if self.context.play then pcall(self.context.play,cue) end end

-- Phone or desktop: the authored variant, picked by the screen's height (never sized here).
function Tracker:layout()
    local height=self.gameUI.AbsoluteSize.Y
    self.isPhone=height>0 and height<(self.root:GetAttribute("PhoneHeight") or 640)
    -- the mission card (UI review) on every screen when authored: phone = desk purely scaled
    if self.mission then
        self.desk.Visible=false;self.phone.Visible=false;if self.slim then self.slim.Visible=false end
        self.mission.Visible=true;return
    end
    -- PIVOT (author-pivot-tracker-slim; Ashton approved the onboarding board): the one slim strip on every screen when authored
    if self.slim then self.desk.Visible=false;self.phone.Visible=false;self.slim.Visible=true;return end
    self.desk.Visible=not self.isPhone;self.phone.Visible=self.isPhone
end
function Tracker:applyVisible()
    -- once the tutorial is complete (and its last payoff has played) the reward card takes over
    local done=self.payoff==nil and self.view~=nil and self.view.complete==true
    self.root.Visible=self.shown and not done
end
function Tracker:setShown(value: boolean)
    if self.shown==value then return end
    self.shown=value;self:applyVisible()
    if value and not self.heartbeat then self.heartbeat=Run.Heartbeat:Connect(function() self:tick() end)
    elseif not value and self.heartbeat then self.heartbeat:Disconnect();self.heartbeat=nil end
end

-- ---------------------------------------------------------------- what the step is saving for / where the nuke is
-- The saving target of a city / nuke goal: the model's goal.saving, or derived from the older fields.
function Tracker.saving(view: any): any?
    local goal=view.goal or {}
    if goal.saving then return goal.saving end
    if view.key=="city" and goal.cost then
        return {kind="City",price=goal.cost,priceText=short(goal.cost),gold=goal.gold,goldText=goal.amount,f=goal.f,ready=goal.ready,etaText=plain(goal.eta)}
    end
    return nil
end
-- The nuke's stop (1 SAVE, 2 BUILD, 3 ARM, 4 FIRE), from stageIndex or the older 0/1/2 stage.
function Tracker.stop(goal: any): number
    if type(goal.stageIndex)=="number" then return math.clamp(goal.stageIndex,1,4) end
    local stage=goal.stage
    if stage==2 then return 4 elseif stage==1 then return 3 end
    return if (goal.gold or 0)>=(goal.siloCost or math.huge) then 2 else 1
end
local function nukeStopF(goal: any,stop: number,saving: any?): number
    if stop==3 then return goal.arm or 0 end
    if stop==4 and goal.ready then return 1 end
    return if saving then saving.f or 0 else 0
end

-- ---------------------------------------------------------------- the hero (real art)
function Tracker:fillHero(h: any,view: any,desk: boolean)
    local goal,key=view.goal or {},view.key
    for _,name in {"Wild","Target","Win","Troops","Buy","Arm","Bomb"} do h[name].Visible=false end
    h.Terrain.Visible=key=="wilderness" or key=="tribe" or key=="nation" or key=="win"
    local function buy(kind: string,saving: any?)
        local b=h.Buy;b.Visible=true
        local ready=saving~=nil and saving.ready==true
        b.Plate.Sprite.Image=SPRITE[kind] or SPRITE.City
        b.Glow.ImageTransparency=if ready then .45 else 1
        local tag=b:FindFirstChild("Tag")
        if tag then
            tag.Tone.Color=if ready then seq("#ffe39a","#d9a23c") else seq("#2b2c30","#1c1d21")
            tag.Rim.Color=c3(if ready then "#fff2c8" else "#4a4d55")
            tag.Coin.Visible=not ready;tag.Price.Visible=not ready;tag.Ready.Visible=ready
            setText(tag.Price,if saving then saving.priceText or "" else "")
        end
    end
    if key=="wilderness" then h.Wild.Visible=true
    elseif key=="troops" then h.Troops.Visible=true
    elseif key=="city" then buy("City",Tracker.saving(view))
    elseif key=="tribe" or key=="nation" then
        h.Target.Visible=true
        local color=c3(goal.ownerColor or view.color)
        for _,row in h.Target.Theirs:GetChildren() do if row:IsA("GuiObject") then row.BackgroundColor3=color end end
    elseif key=="nuke" then
        local stop=Tracker.stop(goal);local saving=Tracker.saving(view)
        if stop<=2 then buy("MissileSilo",saving or {priceText=short(goal.siloCost or 0),ready=stop==2})
        elseif stop==3 then
            local a=h.Arm;a.Visible=true
            Tracker.setRing(a.Ring,goal.arm or 0,c3(C.amber))
            local secs=a:FindFirstChild("Secs");if secs then setText(secs,tostring(goal.armSeconds or "").." s") end
        elseif goal.ready or goal.reloading or not saving then h.Bomb.Visible=true;h.Bomb.Glow.ImageTransparency=if goal.ready then .58 else 1
        else buy("Atom Bomb",saving) end
    else h.Win.Visible=true end
end

-- ---------------------------------------------------------------- the progress items
-- what the Save row shows for this step: {icon, amount, of, f, ready, eta, kind (the target art) | disc (its text)}
function Tracker.saveRow(view: any): any
    local goal,key=view.goal or {},view.key
    if key=="city" then
        local s=Tracker.saving(view) or {}
        return {icon="Coin",amount=s.goldText or goal.amount or "",of=s.priceText or "",f=s.f or goal.f or 0,ready=s.ready==true,eta=plain(s.etaText or goal.etaText or goal.eta),kind="City",value=s.gold}
    elseif key=="troops" then
        local of=(string.gsub(goal.targetText or string.gsub(goal.of or "","^of ",""),"%.0([KM])$","%1")) -- 15.0K reads 15K (the board)
        return {icon="Soldier",amount=goal.amount or "",of=of,f=goal.f or 0,ready=goal.ready==true,eta=plain(goal.etaText or goal.eta),disc=of,color="#d9fffa",
            bar={"#7ee6da","#2e9e92"},value=goal.troops}
    elseif key=="tribe" or key=="nation" then
        if goal.none then return {icon="Rival",amount=goal.name or "",of="",f=0,ready=false,eta="",disc="",color="#c9ced6",bar={"#ff9db2","#b33d5a"},plainAmount=true} end
        local pct=goal.landLeftPct or math.floor(((goal.left or 1)*100)+.5)
        return {icon="Rival",amount=pct.."%",of="left",f=1-(goal.left or pct/100),ready=false,eta="",disc="",color="#ffd6df",bar={"#ff9db2","#b33d5a"},noSlash=true}
    elseif key=="win" then
        local line=goal.line or .8
        return {icon="Crown",amount=goal.pct or "",of=(math.floor(line*100+.5)).."%",f=if line<=0 then 1 else math.min(1,(goal.f or 0)/line),ready=false,eta="",
            disc=(math.floor(line*100+.5)).."%",color="#dfe9ff",bar={"#8fb6ff","#3678ff"}}
    end
    return {icon="Coin",amount="",of="",f=0,ready=false,eta=""}
end
function Tracker:fillSave(save: any,view: any,desk: boolean)
    local row=Tracker.saveRow(view)
    for _,name in {"Coin","Soldier","Rival","Crown"} do save[name].Visible=name==row.icon and not row.ready end
    if row.icon=="Rival" then save.Rival.BackgroundColor3=c3((view.goal or {}).ownerColor or view.color) end
    local text=if row.plainAmount then '<font color="#c9ced6">'..row.amount..'</font>'
        elseif row.noSlash then row.amount..' <font color="#9aa1ab">'..row.of..'</font>'
        else row.amount..' <font color="#9aa1ab">/ '..row.of..'</font>'
    setText(save.Amount,text,c3(row.color or C.gold));save.Amount.Visible=not row.ready
    local bar=save.Bar
    local colors=row.bar or {"#ffe39a","#d9a23c"}
    bar.Fill.Cut.Color=if row.icon=="Rival" then Tracker.targetBar(view) else seq(colors[1],colors[2])
    Tracker.setFill(bar.Fill,if row.ready then 1 else row.f)
    if desk then
        Tracker.setFill(bar.Sheen,if row.ready then 1 else row.f)
        local eta=row.eta~="" and not row.ready
        save.Eta.Visible=eta;save.Clock.Visible=eta;save.HandA.Visible=eta;save.HandB.Visible=eta
        setText(save.Eta,row.eta)
        save.EndPlate.Visible=row.kind~=nil;save.EndDisc.Visible=row.kind==nil and row.disc~=nil and row.disc~=""
        if row.kind then save.EndPlate.Sprite.Image=SPRITE[row.kind] or SPRITE.City;save.EndPlate.Glow.ImageTransparency=if row.ready then .5 else 1 end
        if save.EndDisc.Visible then setText(save.EndDisc.Text,row.disc) end
        save.Ready.Visible=row.ready
        if row.ready then
            local goal=view.goal or {}
            local key=type(goal.line)=="string" and string.match(goal.line,"^Press (%S+),") or nil
            save.Ready.Key.Visible=key~=nil
            if key then setText(save.Ready.Key.Face.Label,key) end
        end
    else
        save.Ready.Visible=row.ready
    end
    return row
end
-- The nuke's stage in words (v2, Ashton's playtest: "this should say save for missile silo, player doesnt know they have
-- to build a silo first"): the action line, the savings row while saving (the silo, then the bomb), the bound key at BUILD.
function Tracker.nukeWords(goal: any,stop: number,saving: any?): (string,boolean)
    if stop==1 then return "Save for a Missile Silo",true
    elseif stop==2 then return "Build a Missile Silo",false
    elseif stop==3 then return "Silo arming · "..tostring(goal.armSeconds or "").." s",false
    elseif goal.ready then return "Fire! Pick a bomb",false
    elseif goal.reloading then return "Silo reloading",false end
    return "Save for an Atom Bomb",saving~=nil
end
-- The bound key for the action (the model's goal.key, or "Press X, ..." in its line); nil on touch / gamepad.
function Tracker.actionKey(goal: any): string?
    if type(goal.key)=="string" and goal.key~="" then return goal.key end
    return if type(goal.line)=="string" then string.match(goal.line,"^Press (%S+),") else nil
end
function Tracker:fillTrack(track: any,view: any,desk: boolean)
    local goal=view.goal or {}
    local stop=Tracker.stop(goal);local saving=Tracker.saving(view);local f=nukeStopF(goal,stop,saving)
    local words,showSaving=Tracker.nukeWords(goal,stop,saving)
    local numbers=if saving then (saving.goldText or "")..' <font color="#9aa1ab">/ '..(saving.priceText or "")..'</font>' else ""
    for i=1,3 do Tracker.setFill(track["Link"..i].Fill,if i<stop then 1 elseif i==stop then f else 0) end
    for i,name in {"Save","Build","Arm","Fire"} do
        local done,cur=i<stop,i==stop
        if desk then
            local s=track[name];local node=s.Node
            s.Halo.Visible=cur;s.Check.Visible=done
            node.Grow.Scale=if cur then 1.25 else 1
            node.BackgroundColor3=c3(if done then "#3a2a12" elseif cur then "#2a1d0c" else "#1d1f23")
            node.Rim.Color=c3(if done or cur then C.amber else C.track);node.Rim.Thickness=if cur then 2 else 1.5
            local art=node.Art
            if art:IsA("ImageLabel") then art.ImageTransparency=if done or cur then 0 else .62
            else Tracker.setRing(art,if done then 1 elseif cur then goal.arm or 0 else 0,c3("#ffffff")) end
        else
            local dot=track[name];dot.BackgroundColor3=c3(if done or cur then C.amber else C.track);dot.Grow.Scale=if cur then 1.45 else 1
        end
    end
    if desk and not track:FindFirstChild("Line") then
        -- a v1 card (author-pf027-tracker v1, before the action line): the old stop labels carry the stage
        local short=if stop==1 then (if saving then saving.goldText or "SAVE" else "SAVE") elseif stop==2 then "BUILD IT"
            elseif stop==3 then "ARM "..tostring(goal.armSeconds or "").." s" elseif goal.ready then "FIRE!" elseif goal.reloading then "RELOAD" else "FIRE"
        for i,name in {"Save","Build","Arm","Fire"} do
            local text=track:FindFirstChild(name.."Label")
            if text then setText(text,if i==stop then short else string.upper(name),c3(if i==stop then (if i==1 then C.gold else C.amber) elseif i<stop then C.done else C.dim)) end
        end
    elseif desk then
        setText(track.Line,words,c3(if stop==4 and goal.ready then C.amber else "#f2f2f2"))
        local key=if stop==2 then Tracker.actionKey(goal) else nil
        track.Key.Visible=key~=nil;if key then setText(track.Key.Face.Label,key) end
        local nums=track.Nums;nums.Visible=showSaving
        if showSaving and saving then
            setText(nums.Amount,numbers)
            local eta=plain(saving.etaText or goal.etaText)
            nums.Eta.Visible=eta~="";nums.Clock.Visible=eta~="";nums.HandA.Visible=eta~="";nums.HandB.Visible=eta~=""
            setText(nums.Eta,eta)
        end
    else
        setText(track.Label,words)
        local nums=track:FindFirstChild("Nums") -- v2 only
        if nums then nums.Visible=showSaving and saving~=nil;setText(nums,numbers) end
    end
end

-- Tribe / nation in words (v2, MM): what to do, then the land left. Phones get the short form.
function Tracker.fightWords(view: any,phone: boolean?): string
    local goal=view.goal or {}
    if goal.none then return if view.key=="tribe" then "Expand until you touch a tribe" else "Expand until you touch a nation" end
    if view.key=="tribe" then return "Take all of their land" end
    return if phone then "Crack them, take every tile" else "Crack them, then take every tile"
end
function Tracker:fillFight(box: any,view: any)
    local goal=view.goal or {}
    setText(box.Line,Tracker.fightWords(view,false))
    box.Rival.BackgroundColor3=c3(goal.ownerColor or view.color);box.Rival.Visible=not goal.none
    local pct=goal.landLeftPct or math.floor(((goal.left or 1)*100)+.5)
    setText(box.Amount,if goal.none then "" else pct..'% <font color="#9aa1ab">left</font>')
    box.Bar.Fill.Cut.Color=Tracker.targetBar(view)
    Tracker.setFill(box.Bar.Fill,if goal.none then 0 else 1-(goal.left or pct/100))
end
-- ---------------------------------------------------------------- the fill
function Tracker:fillVariant(v: any,view: any,desk: boolean)
    local color=c3(view.color)
    setText(v.Step,if desk then "STEP "..view.step.."/"..view.total else view.step.."/"..view.total,color)
    setText(v.Title,view.title)
    if desk then
        for i=1,STEPS do
            local seg=v.Segments["Seg"..i]
            Tracker.setFill(seg.Done,if i<=view.done then 1 else 0)
            seg.Live.BackgroundColor3=color
            Tracker.setFill(seg.Live,if i==view.done+1 then math.max(.12,view.ghost or 0) else 0)
            seg.Flash.BackgroundTransparency=1
        end
    end
    self:fillHero(v.Tile.Hero,view,desk)
    local key=view.key
    local box=if desk then v.Progress else v
    local fight=(key=="tribe" or key=="nation") and box:FindFirstChild("Fight") or nil -- v2 card: the verb layout
    box.Act.Visible=key=="wilderness";box.Track.Visible=key=="nuke";box.Save.Visible=key~="wilderness" and key~="nuke" and fight==nil
    local fightBox=box:FindFirstChild("Fight");if fightBox then fightBox.Visible=fight~=nil end
    local goal=view.goal or {}
    local ready=false
    if goal.waiting then
        box.Save.Visible=false;box.Track.Visible=false
    elseif key=="wilderness" then
        local words=if goal.headline and string.find(goal.headline,"^Tap") then "Tap any grey land" elseif goal.headline and string.find(goal.headline,"^Aim") then "Aim at grey land, attack" else "Click any grey land"
        setText(box.Act:IsA("TextLabel") and box.Act or box.Act.Text,if desk then words else (string.gsub(words,"^Click","Tap") :: string))
    elseif key=="nuke" then self:fillTrack(box.Track,view,desk);ready=goal.ready==true
    elseif fight then self:fillFight(fight,view)
    else ready=self:fillSave(box.Save,view,desk).ready end
    -- the phone's Save row says the tribe / nation verb in place of the numbers (the bar stays)
    local verb=box.Save:FindFirstChild("Verb")
    if verb then
        local words=if (key=="tribe" or key=="nation") and not goal.waiting then Tracker.fightWords(view,true) else nil
        verb.Visible=words~=nil;if words then setText(verb,words);box.Save.Amount.Visible=false;box.Save.Rival.Visible=false end
    end
    -- the card's rim glow: the ready moment (gold), the launch (amber); quiet otherwise
    if not self.payoff then
        v.Glow.ImageColor3=c3(if key=="nuke" then C.amber else C.coin)
        v.Glow.ImageTransparency=if ready then .65 else 1
        v.Panel.Rim.Color=c3(if ready then (if key=="nuke" then C.amber else C.coin) else "#2c2f35")
    end
end
-- PIVOT: the slim strip: Step, Title, one bar + its numbers (the step's save row, the land left, the nuke's stage or the action)
function Tracker:fillSlim(s: any,view: any)
    local color=c3(view.color)
    setText(s.Step,view.step.."/"..view.total,c3(C.coin))
    setText(s.Title,view.title)
    s.Foot.BackgroundColor3=color
    local goal,key=view.goal or {},view.key
    local f,numbers,bar=0,"",true
    if goal.waiting then bar=false
    elseif key=="wilderness" then bar=false;numbers=if goal.headline and string.find(goal.headline,"^Tap") then "Tap any grey land" else "Click any grey land"
    elseif key=="nuke" then
        local stop=Tracker.stop(goal);local saving=Tracker.saving(view)
        f=nukeStopF(goal,stop,saving);numbers=(Tracker.nukeWords(goal,stop,saving))
        if stop==1 or (stop==4 and not goal.ready and saving) then numbers=(saving and saving.goldText or "").." / "..(saving and saving.priceText or "") end
    elseif (key=="tribe" or key=="nation") and goal.none then bar=false;numbers=Tracker.fightWords(view,true)
    elseif key=="tribe" or key=="nation" then
        local pct=goal.landLeftPct or math.floor(((goal.left or 1)*100)+.5);f=1-(goal.left or pct/100);numbers=pct.."% left"
    else
        local row=Tracker.saveRow(view);f=if row.ready then 1 else row.f;numbers=if row.ready then "Ready" else row.amount.." / "..row.of
    end
    s.Bar.Visible=bar;s.Bar.Fill.BackgroundColor3=color;s.Bar.Fill.Size=UDim2.fromScale(clamp01(f),1)
    setText(s.Numbers,numbers)
end
-- ---------------------------------------------------------------- the mission card (UI review)
-- The step's glyph: the tutorial sheet's cell, the City from the settings glyph atlas (the sheet has no city). (image, offset, size)
local GLYPH={wilderness="frontier",expand="frontier",troops="troops",tribe="tent",nation="shield",nuke="missile",win="crown"}
local ICON_ATLAS="rbxassetid://132870288449938" -- 96 px cells, 8 a row; swords = 8, flag = 12, building = 25
local ATLAS_GLYPH={city=25,capital=12,attackNation=8}
function Tracker.missionGlyph(key: string?): (string,Vector2,Vector2)
    local cell=ATLAS_GLYPH[key or ""]
    if cell then return ICON_ATLAS,Vector2.new((cell%8)*96,(cell//8)*96),Vector2.new(96,96) end
    return Art.sheet,Art.rectOffset(GLYPH[key or ""] or "star"),Vector2.new(Art.cell,Art.cell)
end
-- What the card's right side shows: {kind = "act" | "progress" | "reward" | "none", amount?, words?, f (the current
-- segment's fill), hint? (a line in place of the step's own)}.
function Tracker.missionRight(view: any): any
    local goal,key=view.goal or {},view.key
    if goal.waiting then return {kind="none",f=0} end
    if key=="capital" then
        return {kind="act",words=goal.headline or "Click open land",f=0}
    elseif key=="expand" then
        return {kind="progress",f=goal.f or 0,amount=(goal.amount or "")..'<font color="#8d97a6"> / '..(goal.of or "")..' land</font>'}
    elseif key=="attackNation" then
        if goal.none then return {kind="none",f=0,hint="Expand until you touch a nation"} end
        return {kind="act",words=goal.headline or "Click their land",f=.12,hint="Attack "..tostring(goal.name)..". No need to win."}
    elseif key=="wilderness" then
        local tap=type(goal.headline)=="string" and string.find(goal.headline,"^Tap")~=nil
        return {kind="act",words=if tap then "Tap any grey land" else "Click any grey land",f=view.ghost or 0}
    elseif key=="win" then
        return {kind="reward",f=Tracker.saveRow(view).f}
    elseif key=="nuke" then
        local stop=Tracker.stop(goal);local saving=Tracker.saving(view)
        local words=Tracker.nukeWords(goal,stop,saving)
        local numbers=(stop==1 or (stop==4 and not goal.ready)) and saving~=nil
        return {kind=if numbers then "progress" else "none",f=nukeStopF(goal,stop,saving),hint=words,
            amount=if numbers and saving then (saving.goldText or "")..'<font color="#8d97a6"> / '..(saving.priceText or "")..'</font>' else nil}
    elseif (key=="tribe" or key=="nation") and goal.none then
        return {kind="none",f=0,hint=Tracker.fightWords(view,false)}
    elseif key=="tribe" or key=="nation" then
        local pct=goal.landLeftPct or math.floor(((goal.left or 1)*100)+.5)
        return {kind="progress",f=1-(goal.left or pct/100),hint=Tracker.fightWords(view,false),amount=pct..'%<font color="#8d97a6"> left</font>'}
    end
    local row=Tracker.saveRow(view)
    return {kind="progress",f=if row.ready then 1 else row.f,amount=if row.ready then "Ready" else row.amount..'<font color="#8d97a6"> / '..row.of..'</font>'}
end
function Tracker:fillMission(m: any,view: any)
    local color=c3(view.color)
    local meta=Art.Steps[view.step] or {}
    setText(m.Eyebrow,"STEP "..view.step.." OF "..view.total,color)
    setText(m.Title,view.title)
    local right=Tracker.missionRight(view)
    setText(m.Hint,right.hint or meta.hint or "")
    local image,offset,size=Tracker.missionGlyph(view.key)
    local g=m.Medal.Glyph;g.Image=image;g.ImageRectOffset=offset;g.ImageRectSize=size
    m.Medal.Ring.Color=color;m.Medal.BackgroundColor3=color:Lerp(c3("#141a24"),.6)
    m.Pr.Visible=right.kind=="progress";m.Act.Visible=right.kind=="act";m.Reward.Visible=right.kind=="reward"
    if right.kind=="progress" then
        setText(m.Pr.Amount,right.amount or "")
        m.Pr.Bar.Fill.BackgroundColor3=color;m.Pr.Bar.Fill.Size=UDim2.fromScale(clamp01(right.f),1)
    elseif right.kind=="act" then
        setText(m.Act.Text,right.words,color);m.Act.Cursor.ImageColor3=color
        m.Act.BackgroundColor3=color:Lerp(c3("#0d1018"),.86);m.Act.Rim.Color=color
    end
    for i=1,STEPS do
        local fill=m.Track["Seg"..i].Fill
        local done=i<=view.done
        fill.BackgroundColor3=if done then c3(C.gold) else color
        Tracker.setFill(fill,if done then 1 elseif i==view.done+1 then math.max(.12,clamp01(right.f)) else 0)
    end
end
function Tracker:fill(view: any)
    if view.complete then return end
    if self.mission then self:fillMission(self.mission,view) end
    if self.slim then self:fillSlim(self.slim,view) end
    self:fillVariant(self.desk,view,true)
    self:fillVariant(self.phone,view,false)
    -- the live tick: the bar grew on the same step
    local row=if view.key=="city" or view.key=="troops" or view.key=="nuke" then Tracker.saveRow(view) else nil
    local value=if view.key=="nuke" then (Tracker.saving(view) or {}).gold else row and row.value
    if type(value)=="number" and self.last and self.last.step==view.step and self.last.key==view.key and value>self.last.value and not self:reduced() then
        self.tickAt=Tracker.now();self.tickText="+"..short(value-self.last.value);self.tickF=row and row.f or 0
    end
    self.last=if type(value)=="number" then {step=view.step,key=view.key,value=value} else nil
end

-- ---------------------------------------------------------------- live updates and payoffs
-- A new view from the server's snapshot + state. `completions` = steps newly done since the last view.
function Tracker:update(view: any,completions: {number}?)
    self.view=view
    for index,step in completions or {} do table.insert(self.queue,{step=step,quick=index>1}) end
    if not self.payoff and #self.queue>0 then self:startPayoff() end
    if not self.payoff then
        self.display=view
        if view.complete then self:openReward(view) else self:fill(view) end
    end
    self:applyVisible()
end
local function variants(self: any): {any} return {self.desk,self.phone} end
function Tracker:startPayoff()
    local entry=table.remove(self.queue,1)
    local meta=Art.Steps[entry.step]
    self.payoff={step=entry.step,quick=entry.quick,start=Tracker.now(),key=meta.key,chimed=false,switched=false,
        reduced=self:reduced(),duration=if entry.quick then QUICK else PAYOFF}
    self.tickAt=nil
    local color=c3(meta.color)
    for _,v in variants(self) do
        local stamp=v.Stamp
        setText(stamp.Text,meta.stamp,color)
        stamp.Back.Rim.Color=color;stamp.Inner.Rim.Color=color;stamp.Check.BackgroundColor3=color;stamp.Glow.ImageColor3=color
        stamp.Visible=false
        v.Glow.ImageColor3=color
    end
    self:pose(0)
end
-- The payoff at t seconds. Before the switch the completed step is on screen; then the next slides in.
function Tracker:pose(t: number)
    local p=self.payoff;if not p then return end
    local reduced=p.reduced
    local meta=Art.Steps[p.step]
    local color=c3(meta.color)
    local SWITCH=if p.quick then .3 else .85
    for _,v in variants(self) do
        local desk=v==self.desk
        if t<SWITCH then
            -- the bar lands full; the rim glows up in the step's colour
            if desk then
                local save=v.Progress.Save
                if save.Visible then Tracker.setFill(save.Bar.Fill,1);Tracker.setFill(save.Bar.Sheen,1) end
            else Tracker.setFill(v.Save.Bar.Fill,1) end
            local glow=if p.quick then .3 elseif t<.26 then .35*clamp01(t/.26) elseif t<.6 then .8-.5*clamp01((t-.26)/.34) else .3*(1-clamp01((t-.6)/(SWITCH-.6)))
            v.Glow.ImageTransparency=1-glow;v.Panel.Rim.Color=c3("#2c2f35"):Lerp(color,math.min(1,glow*1.4))
            -- the sweep crosses (.12 → .45)
            if desk then
                local sweep=v.Clip.Sweep
                local k=(t-.12)/.33
                sweep.Visible=not reduced and not p.quick and k>=0 and k<=1
                if sweep.Visible then sweep.Position=UDim2.fromScale(-.25+1.3*outCubic(k),-20/148) end
            end
            -- the stamp lands (.26): ×1.6 → 1.14 (.34) → 1 (.6), -8° → -6°; reduced: fades in, still
            local stamp=v.Stamp
            stamp.Visible=not p.quick and t>=.26
            if stamp.Visible then
                local k1,k2=clamp01((t-.26)/.08),clamp01((t-.34)/.26)
                stamp.Slam.Scale=if reduced then 1 else (if t<.34 then 1.6-.46*outCubic(k1) else 1.14-.14*outCubic(k2))
                stamp.Rotation=if reduced then -6 else -8+2*outCubic(k2)
                local alpha=if reduced then clamp01((t-.26)/.2) else clamp01((t-.26)/.05)
                stamp.Back.BackgroundTransparency=1-alpha;stamp.Text.TextTransparency=1-alpha;stamp.Check.BackgroundTransparency=1-alpha
                stamp.Check.Mark.ImageTransparency=1-alpha;stamp.Back.Rim.Transparency=1-alpha;stamp.Inner.Rim.Transparency=1-.55*alpha
                stamp.Glow.ImageTransparency=1-.45*alpha
            end
            -- the segment: a flash as the stamp lands, then gold (.6)
            if desk then
                local seg=v.Segments["Seg"..p.step]
                seg.Flash.BackgroundTransparency=if p.quick or t<.26 or t>.45 then 1 else .5+.5*clamp01((t-.26)/.19)
                Tracker.setFill(seg.Done,if p.quick then clamp01(t/.2) elseif t<.6 then 0 else outCubic((t-.6)/.15))
            end
        else
            v.Stamp.Visible=false
            if v==self.desk then v.Clip.Sweep.Visible=false end
            v.Glow.ImageTransparency=1;v.Panel.Rim.Color=c3("#2c2f35")
        end
    end
    -- the mission card: the rim takes the step's colour, the stamp lands (.26) over the right side, the segment turns gold (.6)
    local m=self.mission
    if m then
        if t<SWITCH then
            local show=not p.quick and t>=.26
            m.Rim.Color=color;m.Rim.Transparency=.25
            if show then
                m.Pr.Visible=false;m.Act.Visible=false;m.Reward.Visible=false
                local stamp=m.Stamp;stamp.Visible=true
                setText(stamp,meta.stamp.." ✓",color);stamp.Rim.Color=color
                local k1,k2=clamp01((t-.26)/.08),clamp01((t-.34)/.26)
                stamp.Slam.Scale=if reduced then 1 else (if t<.34 then 1.6-.46*outCubic(k1) else 1.14-.14*outCubic(k2))
                stamp.TextTransparency=if reduced then 1-clamp01((t-.26)/.2) else 0
            end
            local seg=m.Track:FindFirstChild("Seg"..p.step)
            if seg and (p.quick or t>=.6) then seg.Fill.BackgroundColor3=c3(C.gold);Tracker.setFill(seg.Fill,1) end
        else
            m.Stamp.Visible=false;m.Rim.Color=Color3.new(1,1,1);m.Rim.Transparency=.92
        end
    end
    if not p.chimed and t>=(if p.quick then .1 else .26) then p.chimed=true;if not p.quick then self:play(if p.key=="win" then "tutorial-complete" else "tutorial-step") end end
    if t>=SWITCH then
        if not p.switched then
            p.switched=true
            if not p.chimed then p.chimed=true;if not p.quick then self:play(if p.key=="win" then "tutorial-complete" else "tutorial-step") end end
            local view=self.view
            if view and not view.complete then self.display=view;self:fill(view) end
        end
        -- the next step slides in (14 px, .85 → 1.1), already live
        local slide=if reduced or p.quick then 0 else 14*(1-outBack((t-SWITCH)/(p.duration-SWITCH)))
        for node,base in self.base do node.Position=base+UDim2.fromOffset(slide,0) end
    end
end
function Tracker:finishPayoff()
    local p=self.payoff
    if not p then return end
    self:pose(p.duration) -- the switch (and a skipped chime) land
    self.payoff=nil
    for node,base in self.base do node.Position=base end
    for _,v in variants(self) do v.Stamp.Visible=false end
    if self.mission then self.mission.Stamp.Visible=false;self.mission.Rim.Color=Color3.new(1,1,1);self.mission.Rim.Transparency=.92 end
    self.desk.Clip.Sweep.Visible=false
    if #self.queue>0 then self:startPayoff();return end
    local view=self.view
    if view then
        self.display=view
        if view.complete then self:openReward(view) else self:fill(view) end
    end
    self:applyVisible()
end
-- The quiet motions: step 1's click point pulses (1.6 s), the bar's tick (edge flash .35 s, "+N" rises .6 s).
function Tracker:breathe(now: number)
    local view=self.display
    if not view or view.complete or self.payoff then return end
    local reduced=self:reduced()
    if view.key=="wilderness" then
        local pulse=self.desk.Progress.Act.Pulse
        local k=if reduced then 0 else (now%1.6)/1.6
        pulse.PFPulse.Scale=1+.8*k;pulse.PFStroke.Transparency=.2+.8*k
    end
    local save=self.desk.Progress.Save
    local age=if self.tickAt then now-self.tickAt else math.huge
    save.Bar.Edge.Visible=age<.35
    if save.Bar.Edge.Visible then
        save.Bar.Edge.Position=UDim2.new(self.tickF or 0,0,-3/14,0);save.Bar.Edge.BackgroundTransparency=clamp01(age/.35)
    end
    save.Plus.Visible=age<.6
    if save.Plus.Visible then
        setText(save.Plus,self.tickText)
        save.Plus.Position=UDim2.new(math.clamp((self.tickF or 0)*192/218-30/218,0,1-60/218),0,54/62,-6*outCubic(age/.6))
        save.Plus.TextTransparency=clamp01((age-.3)/.3)
    end
end
function Tracker:tick()
    if self.destroyed then return end
    local now=Tracker.now()
    if self.payoff then
        local t=now-self.payoff.start
        if t>=self.payoff.duration then self:finishPayoff() else self:pose(t) end
    end
    self:breathe(now)
end

-- ---------------------------------------------------------------- the reward card (PF021)
function Tracker:rewardWords(reward: any?): (string,string)
    local status=reward and reward.status
    local amount=tostring((reward and reward.amount) or 500)
    if status=="granted" then return amount,"Cobalt reward"
    elseif status=="claimed" then return amount,"Cobalt · already claimed"
    elseif status=="failed" then return "--","Reward unavailable right now" end
    return "…","Cobalt reward on its way"
end
function Tracker:openReward(view: any)
    if not self.reward or self.rewardDismissed then return end
    -- PF043 (Ashton: "all of them"): the moment you get it is the reward drop; the card (its actions) follows when the drop closes
    local reward=view and view.reward
    -- the first match: a /tutorial replay reads "claimed" (once per account) and still plays the drop (Ashton: the authentic flow)
    if type(reward)=="table" and (reward.status=="granted" or (self.mission and reward.status=="claimed")) and not self.dropPlayed then
        local ok,Drop=pcall(require,script.Parent.RewardDrop)
        local drop=ok and (Drop :: any).get(self.gameUI:FindFirstAncestorOfClass("ScreenGui")) or nil
        if drop then
            self.dropPlayed=true;self.dropping=true
            drop:play({{kind="cobalt",amount=tonumber(reward.amount) or 500,label="TUTORIAL REWARD"}},function() self.dropping=false;if not self.destroyed then self:openReward(view) end end)
            return
        end
    end
    if self.dropping then return end
    -- the first match (the mission card): the match plays on, so the +500 drop is the whole ending: no reward card (its keys
    -- leave the match); the card has already gone (complete). A pending grant waits so its drop still plays when it lands.
    if self.mission then
        local status=type(reward)=="table" and reward.status or nil
        if status==nil or status=="pending" then return end
        self.rewardDismissed=true;self:applyVisible();return
    end
    local card=self.reward.Holder.Fit.Card
    local amount,label=self:rewardWords(view.reward)
    setText(card.Reward.Amount,amount);setText(card.Reward.Label,label)
    if not self.rewardShown then
        self.rewardShown=true
        self.reward.Visible=true;self.gameUI:SetAttribute("PFTutorialRewardOpen",true)
    end
    self:applyVisible()
end
function Tracker:closeReward()
    if not self.reward then return end
    self.rewardDismissed=true;self.reward.Visible=false;self.gameUI:SetAttribute("PFTutorialRewardOpen",nil)
end
-- Both card actions return to the lobby (the server's Exit, as Result's Return to lobby does).
function Tracker:leave()
    self:closeReward()
    if self.context.exit then pcall(self.context.exit) end
end
-- A new attempt (or a new match): forget the payoffs, the tick and the reward.
function Tracker:reset()
    self.queue={};self.payoff=nil;self.view=nil;self.display=nil;self.last=nil;self.tickAt=nil
    for node,base in self.base do node.Position=base end
    self.rewardShown=false;self.rewardDismissed=false;self.dropPlayed=false;self.dropping=false -- PF043
    if self.reward then self.reward.Visible=false end
    self.gameUI:SetAttribute("PFTutorialRewardOpen",nil)
    self:applyVisible()
end
function Tracker:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.heartbeat then self.heartbeat:Disconnect();self.heartbeat=nil end
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.gameUI:SetAttribute("PFTutorialRewardOpen",nil)
end
return Tracker
