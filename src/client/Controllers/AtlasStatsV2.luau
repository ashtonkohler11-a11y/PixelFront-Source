--!strict
-- PF - 3 Stats v2 (UI review 2026-10-26; Ashton: "Good, build it"). Fills AtlasMenu.PFStatsV2 (tools/atlas/author-pf3-stats-v2.luau):
-- the hero (you, four numbers, the last 10 as map chips), this week's top 10 (podium 1-3, rows 4-10, your row), the three maps,
-- the Built strip. Content only: every node is authored (Scale, aspect-held, no text floors). The data is AtlasStatsModel's
-- view and PF - 2's Leaderboard packet (AtlasStatsBoard.view). V2.view is pure (plain-Luau tested: tools/test-pf3-stats-v2.luau).
local V2 = {}
V2.__index = V2
local BUILT = { "City", "Port", "Factory", "DefensePost", "MissileSilo", "SAMLauncher" }
V2.BUILT = BUILT

local function int(v: any): number
    local n = tonumber(v)
    return if n and n == n and n > -math.huge and n < math.huge then math.max(0, math.floor(n)) else 0
end
local function grouped(n: number): string
    local out = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
local function count(n: number): string
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 10000 then return string.format("%.1fK", n / 1000) end
    return grouped(n)
end
local function pct(f: any): string
    local n = tonumber(f)
    if not n or n ~= n then return "—" end
    return tostring(math.floor(math.clamp(n, 0, 1) * 100 + .5)) .. "%"
end

-- model: AtlasStatsModel:view(). Returns what the page shows.
function V2.view(model: any): any
    model = if type(model) == "table" then model else {}
    local summary = if type(model.summary) == "table" then model.summary else {}
    local loading = model.status == "loading" or model.status == "unavailable" or model.summary == nil
    local best: number? = tonumber(model.peakLand)
    local maps = {}
    for _, record in (if type(model.maps) == "table" then model.maps else {}) do
        local peak = tonumber(record.peakLand)
        if peak and (best == nil or peak > best) then best = peak end
        table.insert(maps, { name = tostring(record.name or "—"), wins = int(record.wins), played = int(record.matches),
            best = if peak then pct(peak) else "—", frac = if peak then math.clamp(peak, 0, 1) else 0 })
    end
    -- the last 10 decided results, newest first, with the map each was on
    local chips = {}
    for _, entry in (if type(model.history) == "table" then model.history else {}) do
        if #chips >= 10 then break end
        if type(entry) == "table" and (entry.result == "Victory" or entry.result == "Defeat") then
            table.insert(chips, { map = tostring(entry.mapName or ""), win = entry.result == "Victory" })
        end
    end
    local built = {}
    local source = if type(model.built) == "table" then model.built else {}
    for _, kind in BUILT do table.insert(built, { kind = kind, text = count(int(source[kind])) }) end
    return {
        loading = loading,
        scope = if model.lifetime == true then "Lifetime" else "This session",
        matches = if loading then "—" else grouped(int(summary.matches)),
        wins = if loading then "—" else grouped(int(summary.wins)),
        rate = if loading or summary.rate == nil then "—" else pct(summary.rate),
        land = if loading or best == nil then "—" else pct(best),
        landFrac = if best then math.clamp(best, 0, 1) else 0,
        chips = chips, maps = maps, built = built,
    }
end

local function find(root: Instance, path: string): any
    local node: any = root
    for part in string.gmatch(path, "[^.]+") do node = node and node:FindFirstChild(part) end
    return node
end
local function copy(label: any, value: string) if label and label.Text ~= value then label.Text = value end end
local function headshot(userId: number?): string
    return if userId and userId > 0 then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150" else ""
end
local function setImage(image: any, value: string) if image and image.Image ~= value then image.Image = value end end

-- layer = AtlasMenu.PFStatsV2. context: {getIdentity?, mapSources?, me = UserId?, requestBoard?}
function V2.new(layer: Frame, context: any): any
    local Board = require(script.Parent.AtlasStatsBoard)
    local Preview = require(script.Parent.LobbyMapPreview)
    local Icons = require(script.Parent.ReferenceIcons)
    local canvas = layer:WaitForChild("Canvas")
    local self: any = setmetatable({ layer = layer, canvas = canvas, context = context or {}, Board = Board, tab = "Wins", packet = nil,
        model = nil, visible = false, destroyed = false, connections = {}, preview = Preview.new(context and context.mapSources) }, V2)
    self.wells = {}
    for i = 1, 10 do table.insert(self.wells, find(canvas, "Hero.Trail.Chip" .. i)) end
    for i = 1, 3 do table.insert(self.wells, find(canvas, "Maps.Map" .. i .. ".Well")) end
    for _, name in Board.TABS do
        local button = find(canvas, "Week.Tabs." .. name)
        if button then table.insert(self.connections, button.Activated:Connect(function() self:setTab(name) end)) end
    end
    for _, kind in BUILT do
        local icon = find(canvas, "Built." .. kind .. ".Icon")
        if icon then pcall(Icons.bindWhite, icon, kind) end
    end
    table.insert(self.connections, canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:thumbs() end))
    -- on a phone Roblox's top bar reaches below y 76/1080: the canvas starts under it (the aspect lock shrinks it, centred)
    require(script.Parent.TopbarLine).clearBelow(canvas, self.connections)
    layer.Visible = false
    return self
end

function V2:thumbs()
    if self.destroyed then return end
    self.preview:update(self.wells, self.canvas, self.visible)
end
function V2:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible = visible
    self.layer.Visible = visible
    if visible then self:paint(); self:paintBoard() end
    task.defer(function() self:thumbs() end)
end
function V2:update(model: any)
    if self.destroyed then return end
    self.model = model
    if self.visible then self:paint() end
end
function V2:setBoard(packet: any): boolean
    if self.destroyed or type(packet) ~= "table" or packet.kind ~= "Leaderboard" then return false end
    self.packet = packet
    if self.visible then self:paintBoard() end
    return true
end
function V2:setTab(tab: string)
    if not table.find(self.Board.TABS, tab) then return end
    self.tab = tab
    self:paintBoard()
end

function V2:paint()
    local canvas = self.canvas
    local v = V2.view(self.model)
    local identity = if self.context.getIdentity then self.context.getIdentity() else nil
    local me = self.context.me
    copy(find(canvas, "Hero.PlayerName"), if identity then tostring(identity.displayName or identity.name or "You") else "You")
    copy(find(canvas, "Hero.Scope"), v.scope)
    setImage(find(canvas, "Hero.Avatar"), headshot(me))
    copy(find(canvas, "Hero.Matches.Value"), v.matches)
    copy(find(canvas, "Hero.Victories.Value"), v.wins)
    copy(find(canvas, "Hero.Rate.Value"), v.rate)
    copy(find(canvas, "Hero.Land.Value"), v.land)
    local landFill = find(canvas, "Hero.Land.Bar.Fill"); if landFill then landFill.Size = UDim2.fromScale(v.landFrac, 1) end
    local gold, loss, empty = Color3.fromHex("#e0b84a"), Color3.fromHex("#3a2228"), Color3.fromHex("#262d3a")
    for i = 1, 10 do
        local chip = find(canvas, "Hero.Trail.Chip" .. i)
        if not chip then continue end
        local c = v.chips[i]
        self.preview:set(chip, if c then c.map else nil)
        local rim = chip:FindFirstChild("Rim"); if rim then rim.Color = if c and c.win then gold elseif c then loss else empty end
        local dim = chip:FindFirstChild("Dim"); if dim then dim.Visible = not (c and c.win) end
        local crown = chip:FindFirstChild("Crown"); if crown then crown.Visible = c ~= nil and c.win end
        local none = chip:FindFirstChild("NoMap"); if none then none.Visible = false end
    end
    for i = 1, 3 do
        local card = find(canvas, "Maps.Map" .. i)
        local m = v.maps[i]
        if not card then continue end
        card.Visible = m ~= nil
        if not m then continue end
        copy(card.MapName, m.name)
        copy(card.Wins, grouped(m.wins) .. (if m.wins == 1 then " win" else " wins"))
        copy(card.Played, grouped(m.played) .. " played")
        copy(card.Best, m.best .. " best land")
        local fill = find(card, "Bar.Fill"); if fill then fill.Size = UDim2.fromScale(m.frac, 1) end
        self.preview:set(card.Well, m.name)
    end
    for _, b in v.built do copy(find(canvas, "Built." .. b.kind .. ".Value"), b.text) end
    if self.visible then task.defer(function() self:thumbs() end) end
end

function V2:paintBoard()
    local canvas = self.canvas
    local me = self.context.me
    local v = self.Board.view(self.packet, self.tab, me, os.time())
    copy(find(canvas, "Week.Resets"), v.resets)
    for _, name in self.Board.TABS do
        local b = find(canvas, "Week.Tabs." .. name)
        if not b then continue end
        local on = name == self.tab
        b.BackgroundTransparency = if on then 0 else 1
        b.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromHex("#9aa3b2")
        local rim = b:FindFirstChild("Rim"); if rim then rim.Color = if on then Color3.fromHex("#4f86ff") else Color3.fromHex("#2b3240") end
    end
    for rank = 1, 3 do
        local pod = find(canvas, "Week.Pod" .. rank)
        local r = v.rows[rank]
        if not pod then continue end
        copy(pod.PlayerName, if r then (if r.me then r.name .. " (you)" else r.name) else "—")
        copy(pod.Value, if r then r.text else "")
        setImage(pod.Avatar, if r then headshot(r.userId) else "")
    end
    for rank = 4, 10 do
        local row = find(canvas, "Week.Row" .. rank)
        local r = v.rows[rank]
        if not row then continue end
        row.Visible = r ~= nil
        if not r then continue end
        copy(row.PlayerName, if r.me then r.name .. " (you)" else r.name)
        copy(row.Value, r.text)
        setImage(row.Avatar, headshot(r.userId))
    end
    local you = find(canvas, "Week.You")
    if you then
        local y = v.you
        you.Visible = y ~= nil
        if y then
            copy(you.Rank, if y.rank then "#" .. tostring(y.rank) else "—")
            copy(you.Value, y.text)
            copy(you.Note, y.note)
            setImage(you.Avatar, headshot(me))
        end
    end
    local empty = find(canvas, "Week.Empty")
    if empty then
        empty.Visible = #v.rows == 0
        copy(empty, if v.status == "loading" then "Loading this week's boards…" else "No results yet this week." --[[ UI audit build-out (R5): the You row already says how to get on it ]])
    end
end

function V2:destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, c in self.connections do c:Disconnect() end
    table.clear(self.connections)
    self.preview:dispose()
end
return V2
