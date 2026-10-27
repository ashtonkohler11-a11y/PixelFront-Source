--!strict
-- PF043 B3 (PF - 3; MM accepted r3, board work/pf043/boards/PF043-B3-play-daily.png): the Daily tab. Ashton: "I dont like the
-- daily stuff in the play menu, should be removed and made into its own tab". One screen, no scrolling, few words:
--   Today: three rows (PF - 1's ring, the line, its progress, the reward or a gold Claim), "resets in 6h", All three (+100)
--   Weekly: one row in gold; the group reward (AtlasGroupTile's slot, PFGroupTile, wired by the menu); the login streak link
--   (opens PF - 1's 7-day sheet, DailyView.openStreak). The nav tab's gold dot shows while something waits to be claimed.
-- The layout is authored (tools/atlas/author-pf043-daily-tab.luau, SPACING.md tokens); this fills texts, colours and
-- visibility from DailyClient. A claim asked here plays the reward drop when the server grants it.
local Daily=require(script.Parent.DailyClient)
local View=require(script.Parent.DailyView)
local RewardDrop=require(script.Parent.RewardDrop)
local Page={};Page.__index=Page
Page.HOLD=.6 -- seconds: a long-press on a running daily rerolls it (as the Play chips did)
local hex=Color3.fromHex
local C={text=hex("#f2f2f2"),muted=hex("#9a9a9a"),green=hex("#5fd38a"),ice=hex("#9fc0ff"),dim=hex("#6d717a"),pip=hex("#4a4a4a"),gold=hex("#f1cf7f")}
local function find(root: Instance?,name: string): any return root and root:FindFirstChild(name) end
local function show(item: any,on: boolean) if item then item.Visible=on end end
local function setText(item: any,s: string,color: Color3?) if item then item.Text=s;if color then item.TextColor3=color end end end

-- one challenge row (Today's Row1..3, the Weekly panel): Ring, Line, Progress, Gem + Reward, Claim
function Page.paintRow(row: any,c: any,weekly: boolean)
    if not row then return end
    row.Visible=type(c)=="table"
    if type(c)~="table" then return end
    local done,claimed=c.state=="done",c.state=="claimed"
    View.paintRing(find(row,"Ring"),c,if weekly then "gold" else "cobalt")
    setText(find(row,"Line"),Daily.line(c),if claimed then C.dim else C.text)
    setText(find(row,"Progress"),Daily.progressText(c),if done then C.green elseif claimed then C.dim else C.muted)
    show(find(row,"Claim"),done)
    show(find(row,"Gem"),not done and not claimed)
    show(find(row,"Reward"),not done)
    setText(find(row,"Reward"),if claimed then "Claimed" else Daily.rewardText(c.reward),if claimed then C.dim else C.ice)
    row:SetAttribute("PFDailyState",c.state)
end
-- All three: the pips, the amount, a Claim once all three are done
function Page.paintBonus(b: any,bonus: any)
    if not b then return end
    b.Visible=type(bonus)=="table"
    if type(bonus)~="table" then return end
    local done,claimed=bonus.state=="done",bonus.state=="claimed"
    local n=tonumber(bonus.done) or 0
    for i=1,3 do local p=find(b,"Pip"..i);if p then p.BackgroundColor3=if i<=n then C.green else C.pip end end
    setText(find(b,"Label"),"All three",if claimed then C.dim else C.gold)
    show(find(b,"Claim"),done);show(find(b,"Gem"),not done and not claimed);show(find(b,"Amount"),not done)
    setText(find(b,"Amount"),if claimed then "Claimed" else "+"..tostring(bonus.reward and bonus.reward.cobalt or 100),if claimed then C.dim else C.ice)
    b:SetAttribute("PFDailyState",bonus.state)
end

function Page.new(root: Frame,context: any): any
    local today,weekly=find(root,"Today"),find(root,"Weekly")
    local self: any=setmetatable({root=root,context=context or {},connections={},visible=false,destroyed=false,asked={},
        today=today,weekly=weekly,bonus=find(today,"AllThree"),streak=find(root,"Streak"),dot=(context or {}).dot},Page)
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    -- claims: the piece the button stands for, asked once; the drop plays on the server's grant
    local function claim(target: string,id: any?)
        local key=target.."|"..tostring(id)
        if self.asked[key] then return end
        if Daily.claim(target,id) then self.asked[key]=true end
    end
    for i=1,3 do
        local row=find(today,"Row"..i)
        local function piece(): any local s=Daily.get();return type(s)=="table" and type(s.daily)=="table" and s.daily[i] or nil end
        local key=find(row,"Claim")
        if key then listen(key.Activated,function() local c=piece();if c and c.state=="done" then claim("daily",c.id) end end) end
        -- a long-press on a running daily rerolls it (one reroll a day; the server checks)
        if row and row:IsA("GuiButton") then
            local held=0
            listen(row.MouseButton1Down,function()
                held+=1;local mine=held
                local c=piece();if not c or c.state~="run" then return end
                task.delay(Page.HOLD,function()
                    if held~=mine or self.destroyed then return end
                    held+=1
                    local s=Daily.get()
                    if type(s)=="table" and (tonumber(s.rerolls) or 0)>0 then Daily.reroll(c.id) end
                end)
            end)
            listen(row.MouseButton1Up,function() held+=1 end)
        end
    end
    local bonusKey=find(self.bonus,"Claim")
    if bonusKey then listen(bonusKey.Activated,function() local s=Daily.get();if type(s)=="table" and type(s.bonus)=="table" and s.bonus.state=="done" then claim("bonus") end end) end
    local weeklyKey=find(weekly,"Claim")
    if weeklyKey then listen(weeklyKey.Activated,function() local s=Daily.get();local w=type(s)=="table" and s.weekly;if type(w)=="table" and w.state=="done" then claim("weekly",w.id) end end) end
    if self.streak and self.streak:IsA("GuiButton") then
        listen(self.streak.Activated,function()
            if self.context.openStreak then self.context.openStreak() else View.openStreak() end
        end)
    end
    table.insert(self.connections,{Disconnect=Daily.changed(function() self:paint() end)} :: any)
    table.insert(self.connections,{Disconnect=Daily.claimed(function(result: any)
        local key=tostring(result.target).."|"..tostring(result.id)
        if not self.asked[key] then return end
        self.asked[key]=nil
        if result.status~="granted" then return end
        local label=if result.target=="weekly" then "WEEKLY CHALLENGE" elseif result.target=="bonus" then "ALL THREE" else "DAILY CHALLENGE"
        local e=RewardDrop.entry(result.granted,label);local drop=self.context.gui and RewardDrop.get(self.context.gui)
        if e and drop then drop:play({e}) end
    end)} :: any)
    -- the reset line ticks while the page shows
    listen(game:GetService("RunService").Heartbeat,function()
        if not self.visible or self.destroyed then return end
        local now=os.clock();if now-(self.ticked or 0)<1 then return end
        self.ticked=now
        setText(find(today,"Resets"),Daily.resetText(Daily.get()))
    end)
    pcall(Daily.start)
    self:paint()
    return self
end

function Page:paint()
    if self.destroyed then return end
    local s=Daily.get()
    local daily=type(s)=="table" and type(s.daily)=="table" and s.daily or {}
    for i=1,3 do Page.paintRow(find(self.today,"Row"..i),daily[i],false) end
    Page.paintBonus(self.bonus,type(s)=="table" and s.bonus or nil)
    Page.paintRow(self.weekly,type(s)=="table" and s.weekly or nil,true)
    setText(find(self.today,"Resets"),Daily.resetText(s))
    local streak=type(s)=="table" and type(s.streak)=="table" and s.streak or nil
    if self.streak then
        self.streak.Visible=streak~=nil
        setText(find(self.streak,"Label"),"Login streak · Day "..tostring(streak and streak.today or 1))
        show(find(self.streak,"Dot"),Daily.streakClaimable(s))
    end
    -- the nav tab's gold dot: a finished challenge (or the bonus / weekly) waits
    if self.dot then self.dot.Visible=Daily.claimable(s) end
end

function Page:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible=visible
    if visible then Daily.refresh();self:paint() end
end

function Page:focusActive()
    local Gui=game:GetService("GuiService")
    for i=1,3 do
        local key=find(find(self.today,"Row"..i),"Claim")
        if key and key.Visible then Gui.SelectedObject=key;return end
    end
    for _,key in {find(self.bonus,"Claim"),find(self.weekly,"Claim")} do if key and key.Visible then Gui.SelectedObject=key;return end end
    if self.streak and self.streak:IsA("GuiButton") and self.streak.Visible then Gui.SelectedObject=self.streak end
end

function Page:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    table.clear(self.connections)
end

return Page
