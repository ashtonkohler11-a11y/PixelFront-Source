--!strict
-- PF036 Ranked v2 (PF - 3; board docs/director/mockups/PF036/08-ranked-v2.png; contract docs/director/coordination/
-- PF036-ranked-contract.md): the Play page's Public | Ranked tabs, the 1v1 / 2v2 / FFA switch and the Ranked area.
-- Nodes: tools/atlas/author-pf036-ranked.luau (Content.PFPlayTabs, PFModeSwitch, PFRanked.Desk / Phone). Content only:
-- texts, colours, the emblem cells, visibility. The view comes from AtlasRankedModel; PF - 2's server sends RankedState and
-- takes RankedCommand {Ready | Search{mode} | Cancel}. On the Ranked tab the public cards hide and PF - 1's daily chips
-- step aside (Content's PFDailyHidden attribute, their DailyView); the rejoin banner owns the heading line while it shows.
local Model = require(script.Parent.AtlasRankedModel)
local Preview = require(script.Parent.LobbyMapPreview)
-- PF - 2's shared ladder + rotation (Shared/RankedRules); required on first use, so a place without it still loads
local rules: any = nil
local function Rules(): any?
    if rules == nil then
        local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        local module = shared and shared:FindFirstChild("RankedRules")
        local ok, result = pcall(function() return require(module :: any) end)
        rules = if module and ok then result else false
    end
    return rules or nil
end
local Page = {}
Page.__index = Page
Page.PHONE = 540 -- the menu height at or under which the Phone layout shows (DailyView.PHONE)
Page.READY_GAP = 5
local ROMAN = { "I", "II", "III" }
-- emblem2's tier colours (work/pf036-lobby/emblem2.mjs): the plate rim (mid), its numeral and the bar (hi)
local TIER = {
    [0] = { mid = "#a8652f", hi = "#e7a96b" }, { mid = "#9aa6b6", hi = "#eef3f9" }, { mid = "#d29a2c", hi = "#ffe390" },
    { mid = "#33b3a5", hi = "#b5f7ee" }, { mid = "#4f86ef", hi = "#cfe0ff" }, { mid = "#8c4fe0", hi = "#e9d4ff" },
}
local C = { text = Color3.fromHex("#f2f2f2"), muted = Color3.fromHex("#9a9a9a"), body = Color3.fromHex("#d0d0d6"), cobalt = Color3.fromHex("#3678ff"),
    goldHi = Color3.fromHex("#ffd77a"), goldFill = Color3.fromHex("#2a2414"), ink = Color3.new(1, 1, 1), warn = Color3.fromHex("#ff9a8f") }

local function copy(label: any, value: string) if label and label.Text ~= value then label.Text = value end end

-- an emblem node (sheet cell + Plate.Label): tier 0..5, div 1..3; nil tier hides it (placements, unknown)
function Page.paintEmblem(node: any, tier: number?, div: number?)
    if not node then return end
    node.Visible = tier ~= nil
    if tier == nil then return end
    node.ImageRectOffset = Vector2.new(tier * 160, 0)
    local plate = node:FindFirstChild("Plate")
    if plate then
        -- small emblems (the YOUR RANKS row, the You / Them line) carry PFNoPlate: their label already names the division
        plate.Visible = tier < 5 and div ~= nil and ROMAN[div] ~= nil and node:GetAttribute("PFNoPlate") ~= true
        local colours = TIER[tier]
        local rim = plate:FindFirstChildOfClass("UIStroke"); if rim then rim.Color = Color3.fromHex(colours.mid) end
        local label = plate:FindFirstChild("Label")
        if label then label.Text = ROMAN[div or 1] or ""; label.TextColor3 = Color3.fromHex(colours.hi) end
    end
end

-- content = Play's ContentScroll.Content; context: {menu, mapSources, notify?}
function Page.new(content: Frame, context: any): any
    local self: any = setmetatable({ content = content, context = context, connections = {}, tab = "Public", mode = "1v1",
        state = nil, askedAt = -math.huge, destroyed = false, preview = Preview.new(context.mapSources) }, Page)
    self.tabs = content:FindFirstChild("PFPlayTabs")
    self.switch = content:FindFirstChild("PFModeSwitch")
    self.area = content:FindFirstChild("PFRanked")
    self.cards = content:FindFirstChild("Cards")
    self.status = content:FindFirstChild("PFClipStatus")
    local function listen(signal: RBXScriptSignal, fn: any) table.insert(self.connections, signal:Connect(fn)) end
    for _, name in { "Public", "Ranked" } do
        local b = self.tabs and self.tabs:FindFirstChild(name)
        if b then listen(b.Activated, function() self:setTab(name) end) end
    end
    if self.switch then
        for _, b in self.switch:GetChildren() do
            if b:IsA("GuiButton") and b:GetAttribute("PFMode") then listen(b.Activated, function() self:setMode(b:GetAttribute("PFMode")) end) end
        end
    end
    for _, variant in { "Desk", "Phone" } do
        local root = self.area and self.area:FindFirstChild(variant)
        local action = root and root:FindFirstChild("Queue") and root.Queue:FindFirstChild("Action")
        if action then listen(action.Activated, function() self:act() end) end
        local ranks = root and root:FindFirstChild("Rank") and root.Rank:FindFirstChild("Ranks")
        if ranks then for _, cell in ranks:GetChildren() do
            if cell:IsA("GuiButton") and cell:GetAttribute("PFMode") then listen(cell.Activated, function() self:setMode(cell:GetAttribute("PFMode")) end) end
        end end
    end
    if context.menu then listen(context.menu:GetPropertyChangedSignal("AbsoluteSize"), function() self:paint() end) end
    listen(content:GetAttributeChangedSignal("PFRejoinShown"), function() self:paint() end)
    -- the search clock, once a second while searching
    local last = 0
    listen(game:GetService("RunService").Heartbeat, function()
        if self.tab ~= "Ranked" or not (self.state and self.state.search) then return end
        local now = os.time(); if now ~= last then last = now; self:paint() end
    end)
    -- the tabs appear only with PF - 2's ranked server (its RankedCommand remote); until then Play keeps its plain heading
    task.spawn(function()
        local folder = game:GetService("ReplicatedStorage"):WaitForChild("OpenFrontRemotes", 60)
        local command = folder and folder:WaitForChild("RankedCommand", math.huge)
        if command and not self.destroyed then self.enabled = true; self:paint() end
    end)
    self:paint()
    return self
end
function Page:remote(name: string): RemoteEvent?
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontRemotes")
    local r = folder and folder:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then
        if name == "RankedState" and not self.hooked then
            self.hooked = true
            table.insert(self.connections, r.OnClientEvent:Connect(function(packet) self:receive(packet) end))
        end
        return r
    end
    return nil
end
function Page:ready()
    self:remote("RankedState")
    if os.clock() - self.askedAt < Page.READY_GAP then return end
    local command = self:remote("RankedCommand")
    if command then self.askedAt = os.clock(); command:FireServer({ kind = "Ready" }) end
end
function Page:receive(packet: any)
    if self.destroyed or type(packet) ~= "table" or packet.kind ~= "Ranked" then return end
    self.state = packet
    -- a search running elsewhere: the switch follows it
    if type(packet.search) == "table" and table.find(Model.MODES, packet.search.mode) then self.mode = packet.search.mode end
    self:paint()
end
function Page:setTab(tab: string)
    if self.destroyed or (tab ~= "Public" and tab ~= "Ranked") then return end
    self.tab = tab
    if tab == "Ranked" then self:ready() end
    self:paint()
end
function Page:setMode(mode: any)
    if not table.find(Model.MODES, mode) then return end
    self.mode = mode
    self:paint()
end
function Page:act()
    local command = self:remote("RankedCommand"); if not command then return end
    local v = Model.view(self.state, self.mode, os.time())
    if v.status ~= "ready" then return end
    if v.searching or v.searchOther then command:FireServer({ kind = "Cancel" }) else command:FireServer({ kind = "Search", mode = self.mode }) end
end
function Page:isPhone(): boolean
    local menu = self.context.menu
    return menu ~= nil and menu.AbsoluteSize.Y > 0 and menu.AbsoluteSize.Y <= Page.PHONE
end
function Page:paint()
    if self.destroyed then return end
    local ranked = self.enabled == true and self.tab == "Ranked"
    local rejoin = self.content:GetAttribute("PFRejoinShown") == true
    -- the heading line: the tabs replace the plain heading once ranked is live (the rejoin banner owns both while it shows)
    if self.enabled and not rejoin and self.tabs and not self.tabs.Visible then
        self.tabs.Visible = true
        local heading = self.content:FindFirstChild("Heading"); if heading then heading.Visible = false end
    end
    -- the tabs and the heading line
    if self.tabs then
        for _, name in { "Public", "Ranked" } do
            local b = self.tabs:FindFirstChild(name); if not b then continue end
            local on = name == self.tab
            if b:FindFirstChild("Label") then b.Label.TextColor3 = if on then C.text else C.muted end
            if b:FindFirstChild("Underline") then b.Underline.Visible = on end
        end
    end
    if self.cards then self.cards.Visible = not ranked end
    if self.status then self.status.Visible = not ranked end
    if self.content:GetAttribute("PFDailyHidden") ~= (if ranked then true else nil) then self.content:SetAttribute("PFDailyHidden", if ranked then true else nil) end
    if self.switch then
        self.switch.Visible = ranked and not rejoin
        for _, b in self.switch:GetChildren() do
            if not b:IsA("GuiButton") then continue end
            local on = b:GetAttribute("PFMode") == self.mode
            b.BackgroundTransparency = if on then 0 else 1
            if b:FindFirstChild("Label") then b.Label.TextColor3 = if on then C.ink else C.muted end
        end
    end
    if not self.area then return end
    self.area.Visible = ranked
    if not ranked then self.preview:update({}, self.content, false); return end
    local phone = self:isPhone()
    local root = self.area:FindFirstChild(if phone then "Phone" else "Desk")
    local other = self.area:FindFirstChild(if phone then "Desk" else "Phone")
    if other then other.Visible = false end
    if not root then return end
    root.Visible = true
    local v = Model.view(self.state, self.mode, os.time())
    -- the rank card
    local rank = root:FindFirstChild("Rank")
    if rank then
        copy(rank:FindFirstChild("Eyebrow"), if phone then "RANKED " .. string.upper(self.mode) else v.eyebrow)
        copy(rank:FindFirstChild("Days"), if phone then (string.match(v.days, "^(%d+) days") and string.match(v.days, "^(%d+)") .. " d" or v.days) else v.days)
        Page.paintEmblem(rank:FindFirstChild("Emblem"), v.card.tier, v.card.div)
        copy(rank:FindFirstChild("Name"), v.card.name)
        local barNode = rank:FindFirstChild("Bar")
        if barNode then barNode.Visible = v.card.fraction ~= nil or v.card.placement == true end -- no floor yet: no bar
        if barNode and barNode:FindFirstChild("Fill") then
            barNode.Fill.Size = UDim2.fromScale(v.card.fraction or 0, 1)
            barNode.Fill.BackgroundColor3 = Color3.fromHex(if v.card.tier then TIER[v.card.tier].hi else "#3678ff")
        end
        copy(rank:FindFirstChild("Rating"), v.card.rating or "")
        copy(rank:FindFirstChild("Next"), v.card.next or "")
        local ranks = rank:FindFirstChild("Ranks")
        if ranks then
            for _, r in v.ranks do
                local cell = ranks:FindFirstChild("R" .. r.mode); if not cell then continue end
                cell.BackgroundTransparency = if r.selected then 0 else 1
                local rim = cell:FindFirstChildOfClass("UIStroke"); if rim then rim.Transparency = if r.selected then 0 else 1 end
                Page.paintEmblem(cell:FindFirstChild("Emblem"), r.tier, r.div)
                copy(cell:FindFirstChild("Label"), r.label)
                if cell:FindFirstChild("Label") then cell.Label.TextColor3 = if r.selected then C.text else C.body end
            end
        end
        local bestTier = self.state and type(self.state.best) == "table" and Model.tierIndex(self.state.best.tier) or nil
        local best = rank:FindFirstChild("Best")
        if best then copy(best, v.best); best.TextColor3 = Color3.fromHex(if bestTier then TIER[bestTier].hi else "#9a9a9a") end
    end
    -- the queue card
    local queue = root:FindFirstChild("Queue")
    if queue then
        copy(queue:FindFirstChild("Eyebrow"), "RANKED " .. string.upper(self.mode))
        local search = self.state and self.state.search
        local found = self.state and self.state.found
        local map = (v.found and found and found.map) or (v.searching and search and search.map) or nil
        -- MM (b): idle, the mode's current rotation map (the same everywhere: RankedRules.rotation)
        local idleSize: string? = nil
        local rot = self.state and type(self.state.rotation) == "table" and self.state.rotation[self.mode]
        if map == nil and not v.locked and type(rot) == "table" and type(rot.map) == "string" then
            map = rot.map; idleSize = if rot.mapSize == "Compact" then "Compact" else "Normal" -- PF - 2's RankedState.rotation (authoritative)
        end
        if map == nil and not v.locked then -- fallback: the same rule client-side
            local R = Rules()
            if R and R.rotation then
                local ok, m, size = pcall(R.rotation, self.mode, os.time())
                if ok and type(m) == "string" then map = m; idleSize = size end
            end
        end
        -- the chip follows the map actually shown (idle: the rotation's size; searching: the server's mapSize)
        local mapSize = queue:FindFirstChild("MapSize")
        if mapSize then mapSize.Visible = map ~= nil and (if idleSize then idleSize == "Compact" else v.compact); copy(mapSize:FindFirstChild("Label"), "COMPACT MAP") end
        local well = queue:FindFirstChild("Map")
        if well then
            self.preview:set(well, map)
            local none = well:FindFirstChild("NoMap")
            if none then none.Visible = map == nil; copy(none, "The map rotates every 10 minutes") end
            self.preview:update({ well }, self.content, map ~= nil)
        end
        copy(queue:FindFirstChild("Title"), if map then (if v.map ~= "" then v.map else map .. (if idleSize == "Compact" then " · Compact" else "")) else (if self.mode == "FFA" then "Free for all" else "Ranked " .. self.mode))
        local line = queue:FindFirstChild("Line")
        if line then
            copy(line, v.notice or v.line)
            line.TextColor3 = if v.notice then C.warn else C.muted
        end
        local you = queue:FindFirstChild("You")
        if you then
            Page.paintEmblem(you:FindFirstChild("Emblem"), v.card.tier, v.card.div)
            copy(you:FindFirstChild("Label"), "You · " .. v.card.name)
        end
        local them = queue:FindFirstChild("Them")
        local searchText = if v.found then "Match found · joining" elseif v.searching then v.searchText else ""
        if them then
            them.Visible = v.searching or v.found
            local foe = found and type(found.teams) == "table" and Page.opponent(found.teams, game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer.UserId)
            Page.paintEmblem(them:FindFirstChild("Emblem"), foe and Model.tierIndex(foe.tier) or nil, foe and tonumber(foe.division))
            copy(them:FindFirstChild("Label"), if foe then tostring(foe.name) else searchText)
        end
        if queue:FindFirstChild("Vs") then queue.Vs.Visible = v.searching or v.found end
        copy(queue:FindFirstChild("Search"), searchText) -- the phone card's line
        local action = queue:FindFirstChild("Action")
        local lock = queue:FindFirstChild("Locked")
        if lock then lock.Visible = v.locked; copy(lock, v.lockText or "") end
        if action then
            action.Visible = not v.locked and not v.found and v.status ~= "loading"
            local cancel = v.searching or v.searchOther ~= nil
            copy(action:FindFirstChild("Label"), if v.searchOther then "Cancel " .. v.searchOther .. " search" elseif cancel then "Cancel search" else "Find match")
            action.BackgroundColor3 = if cancel then C.goldFill else C.cobalt
            local rim = action:FindFirstChildOfClass("UIStroke"); if rim then rim.Color = if cancel then C.goldHi else C.cobalt end
            if action:FindFirstChild("Label") then action.Label.TextColor3 = if cancel then C.goldHi else C.ink end
        end
    end
end
-- the first player on a team without you (the 1v1 / 2v2 reveal before the teleport)
function Page.opponent(teams: any, me: number?): any?
    for _, team in teams do
        if type(team) ~= "table" then continue end
        local mine = false
        for _, p in team do if type(p) == "table" and p.userId == me then mine = true end end
        if not mine then for _, p in team do if type(p) == "table" then return p end end end
    end
    return nil
end
function Page:destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, c in self.connections do c:Disconnect() end
    table.clear(self.connections)
    self.preview:dispose()
    if self.content:GetAttribute("PFDailyHidden") then self.content:SetAttribute("PFDailyHidden", nil) end
end
return Page
