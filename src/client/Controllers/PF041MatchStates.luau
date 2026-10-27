--!strict
-- PF-041 (PF - 1; Ashton 2026-10-16 via MM: "Good, build"; board work/pf040/boards/3-PF041-match-states.png): two match
-- states, content only (the layout is authored by tools/atlas/author-pf041.luau):
--   Paused: Game.PFPaused dims the map under one centre panel; the host (a Solo: offline) gets Resume, everyone else just
--     "Paused". It replaces the heads-up's "Game paused" line.
--   Spectating: Game.PFSpectateBar in the dock's place, for a spectator seat or a player who was eliminated and kept
--     watching: who you follow (their colour and name), ‹ › follow the next / previous player still alive (the camera goes
--     to them), Leave goes home. It replaces the small PFSpectating chip.
-- MatchController calls update() once per HUD pass. Missing nodes (an older place): nothing happens.
local M={};M.__index=M
-- callbacks: resume(), leave(), focusOwner(owner), name(owner): string, color(owner): Color3?
function M.new(gameUI: Instance,callbacks: any): any
    local self=setmetatable({ui=gameUI,callbacks=callbacks,paused=gameUI:FindFirstChild("PFPaused"),bar=gameUI:FindFirstChild("PFSpectateBar"),
        chip=gameUI:FindFirstChild("PFSpectating"),headsUp=gameUI:FindFirstChild("HeadsUp"),dim=gameUI:FindFirstChild("PFPausedDim"),follow=nil,spawned=false,alive={}},M)
    local function on(root: Instance?,path: {string},fn: ()->())
        local node=root
        for _,name in path do node=node and node:FindFirstChild(name) end
        if node and node:IsA("GuiButton") then node.Activated:Connect(fn) end
    end
    on(self.paused,{"Host","Resume"},function() if callbacks.resume then callbacks.resume() end end)
    on(self.bar,{"Prev"},function() self:cycle(-1) end)
    on(self.bar,{"Next"},function() self:cycle(1) end)
    on(self.bar,{"Leave"},function() if callbacks.leave then callbacks.leave() end end)
    return self
end
-- the players still in it, biggest first (you excluded unless a spectator seat follows owner 1's view)
function M:aliveOwners(state: any,spectator: boolean): {number}
    local list={}
    for _,owner in state.playerOrder or {} do
        local p=state.players[owner]
        if p and (state.counts[owner] or 0)>0 and p.playerType~="Bot" and (spectator or owner~=1) then table.insert(list,owner) end
    end
    table.sort(list,function(a,b) return (state.counts[a] or 0)>(state.counts[b] or 0) end)
    return list
end
function M:cycle(step: number)
    local list=self.alive;if #list==0 then return end
    local i=table.find(list,self.follow or -1) or 0
    i=((i-1+step)%#list)+1
    self.follow=list[i];self:paintFollow()
    if self.callbacks.focusOwner then self.callbacks.focusOwner(self.follow) end
end
function M:paintFollow()
    local bar=self.bar;if not bar or not self.follow then return end
    local name=bar:FindFirstChild("Name");local swatch=bar:FindFirstChild("Swatch")
    if name and name:IsA("TextLabel") then name.Text=if self.callbacks.name then self.callbacks.name(self.follow) else tostring(self.follow) end
    local color=self.callbacks.color and self.callbacks.color(self.follow)
    if swatch and swatch:IsA("GuiObject") and color then swatch.BackgroundColor3=color end
end
function M:update(snapshot: any,state: any,resultVisible: boolean,ready: boolean)
    if not snapshot or not state then return end
    -- paused
    local paused=ready and snapshot.paused==true
    if self.paused and self.paused:IsA("GuiObject") then
        self.paused.Visible=paused
        if self.dim and self.dim:IsA("GuiObject") then self.dim.Visible=paused end
        if paused then
            local host=snapshot.online~=true -- online matches pause from the lobby creator's side; a Solo resumes here
            local h,gst=self.paused:FindFirstChild("Host"),self.paused:FindFirstChild("Guest")
            if h and h:IsA("GuiObject") then h.Visible=host end;if gst and gst:IsA("GuiObject") then gst.Visible=not host end
            if self.headsUp and self.headsUp:IsA("GuiObject") and state.phase~="Choosing" then self.headsUp.Visible=false end
        end
    end
    -- spectating
    if (state.counts[1] or 0)>0 then self.spawned=true end
    local spectator=snapshot.spectator==true
    local watching=ready and not resultVisible and state.phase=="Playing" and (spectator or (self.spawned and (state.counts[1] or 0)==0))
    local bar=self.bar
    if bar and bar:IsA("GuiObject") then
        bar.Visible=watching
        if watching then
            self.alive=self:aliveOwners(state,spectator)
            if not self.follow or not table.find(self.alive,self.follow) then self.follow=self.alive[1] end
            self:paintFollow()
        end
        if self.chip and self.chip:IsA("GuiObject") and watching then self.chip.Visible=false end
    end
end
return M
