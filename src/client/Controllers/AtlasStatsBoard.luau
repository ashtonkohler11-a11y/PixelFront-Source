--!strict
-- PF036 (PF - 3): "This week · top 10" on Stats (board 06). PF - 2's StatsCommand {kind="Leaderboard"} reply:
-- {kind, week, wins, land = {{userId, name, value}} (top 10 each), you = {wins, land}}. Weekly wins / land reset
-- Monday 00:00 UTC. Every node is authored by tools/atlas/author-pf036-leaderboard.luau (Content.PFBoard): ten rows,
-- the tabs, your row. Runtime fills content only. PIVOT D15: Levels are removed, so the authored Level tab stays hidden.
local Board = {}
Board.__index = Board
Board.TABS = { "Wins", "Land" }
local KEY = { Wins = "wins", Land = "land" }
local MEDAL: {Color3}? = nil -- built on first paint (the pure view runs in plain Luau tests)

local function int(value: any): number
    local n = tonumber(value)
    return if n and n == n and n > -math.huge and n < math.huge then math.max(0, math.floor(n)) else 0
end
local function grouped(n: number): string
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
local function compact(n: number): string
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 10000 then return string.format("%.1fK", n / 1000) end
    return grouped(n)
end
-- One value as the board shows it.
function Board.format(tab: string, value: number): string
    if tab == "Wins" then return grouped(value) .. (if value == 1 then " win" else " wins") end
    return compact(value) .. (if value == 1 then " tile" else " tiles")
end
-- Monday 00:00 UTC (StatsProfiles.week: (day + 3) // 7).
function Board.resetsIn(now: number): string
    local day = math.floor(now / 86400)
    local nextStart = (7 * ((day + 3) // 7 + 1) - 3) * 86400
    local left = math.max(0, nextStart - math.floor(now))
    local d, h, m = left // 86400, (left % 86400) // 3600, (left % 3600) // 60
    if d > 0 then return "Resets in " .. d .. "d " .. h .. "h" end
    if h > 0 then return "Resets in " .. h .. "h " .. m .. "m" end
    return "Resets in " .. math.max(1, m) .. "m"
end
-- The tab's rows and your line. me = your UserId.
function Board.view(packet: any, tab: string, me: number?, now: number): any
    if type(packet) ~= "table" or packet.kind ~= "Leaderboard" then
        return { status = "loading", rows = {}, resets = Board.resetsIn(now) }
    end
    local list = packet[KEY[tab]]
    local rows = {}
    local place: number? = nil
    for i, entry in (if type(list) == "table" then list else {}) do
        if i > 10 or type(entry) ~= "table" then break end
        local userId = tonumber(entry.userId)
        local value = int(entry.value)
        table.insert(rows, { rank = i, userId = userId, name = tostring(entry.name or "Player"), value = value,
            text = Board.format(tab, value), me = userId ~= nil and userId == me })
        if userId ~= nil and userId == me then place = i end
    end
    local you = type(packet.you) == "table" and packet.you or {}
    local mine = int(if tab == "Wins" then you.wins else you.land)
    if place then mine = math.max(mine, rows[place].value) end -- on the board: the board's number (the tops are cached a minute)
    local note: string
    if place then note = if place == 1 then "First this week" else "#" .. place .. " this week"
    elseif mine == 0 then note = if tab == "Wins" then "Win a match to get on the board" else "Play a match to get on the board"
    elseif #rows >= 10 then
        local gap = rows[10].value - mine + 1
        note = if tab == "Wins" then grouped(gap) .. (if gap == 1 then " win" else " wins") .. " to the top 10"
            else compact(gap) .. " tiles to the top 10"
    else note = "" end
    return { status = if #rows == 0 then "empty" else "ready", rows = rows,
        you = { rank = place, text = Board.format(tab, mine), note = note }, resets = Board.resetsIn(now) }
end

local function node(parent: Instance, name: string): any
    return assert(parent:FindFirstChild(name), "PF036 board node missing: " .. parent:GetFullName() .. "." .. name)
end
local function copy(target: any, value: string)
    if target.Text ~= value then target.Text = value end
end

-- section = Content.PFBoard. context: {request = () -> (), me = UserId, name = your name, theme}.
function Board.new(section: Frame, context: any): any
    local self: any = setmetatable({ root = section, context = context, tab = "Wins", packet = nil, connections = {} }, Board)
    local head = node(section, "Head")
    self.title, self.resets, self.tabs = node(head, "Title"), node(head, "Resets"), node(head, "Tabs")
    self.rows = {}
    for i = 1, 10 do self.rows[i] = node(node(section, if i <= 5 then "Left" else "Right"), "Row" .. i) end
    self.you = node(section, "You")
    self.empty = node(section, "Empty")
    for _, name in Board.TABS do
        local button = node(self.tabs, name)
        table.insert(self.connections, button.Activated:Connect(function() self:setTab(name) end))
    end
    local retired = self.tabs:FindFirstChild("Level")
    if retired and retired:IsA("GuiObject") then retired.Visible = false end
    copy(self.title, "This week · top 10")
    self:paint()
    return self
end
function Board:setTab(tab: string)
    if not table.find(Board.TABS, tab) then return end
    self.tab = tab
    self:paint()
end
function Board:setPacket(packet: any): boolean
    if type(packet) ~= "table" or packet.kind ~= "Leaderboard" then return false end
    self.packet = packet
    self:paint()
    return true
end
function Board:paint()
    MEDAL = MEDAL or { Color3.fromRGB(236, 196, 92), Color3.fromRGB(205, 214, 226), Color3.fromRGB(214, 142, 82) }
    local medals = MEDAL :: {Color3}
    local ctx = self.context
    local v = Board.view(self.packet, self.tab, ctx.me, os.time())
    local theme = ctx.theme or {}
    copy(self.resets, v.resets)
    for _, name in Board.TABS do
        local button = self.tabs[name]
        local on = name == self.tab
        button:SetAttribute("PFSelected", on)
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = if on then Color3.fromRGB(54, 120, 255) else Color3.fromRGB(58, 58, 58) end
        button.BackgroundTransparency = if on then 0 else 1
        button.TextColor3 = if on then Color3.new(1, 1, 1) else (theme.MutedText or Color3.fromRGB(167, 171, 173))
    end
    for i, row in self.rows do
        local r = v.rows[i]
        row.Visible = r ~= nil
        if not r then continue end
        copy(row.Rank.Label, tostring(i))
        local medal = medals[i]
        row.Rank.BackgroundTransparency = if medal then .15 else 1
        if medal then row.Rank.BackgroundColor3 = medal:Lerp(Color3.new(0, 0, 0), .55) end
        row.Rank.Label.TextColor3 = medal or (theme.MutedText or Color3.fromRGB(167, 171, 173))
        local image = if r.userId then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(r.userId) .. "&w=48&h=48" else ""
        if row.Avatar.Image ~= image then row.Avatar.Image = image end
        copy(row.PlayerName, if r.me then r.name .. " (you)" else r.name)
        copy(row.Value, r.text)
        row.Value.TextColor3 = medal or (theme.Text or Color3.fromRGB(238, 238, 235))
    end
    self.empty.Visible = #v.rows == 0
    copy(self.empty, if v.status == "loading" then "Loading this week's boards…" else "No results yet this week." --[[ UI audit build-out (R5): the You row already says how to get on it ]])
    local you = v.you
    self.you.Visible = you ~= nil
    if you then
        self.you.Rank.Visible = you.rank ~= nil
        if you.rank then copy(self.you.Rank.Label, "#" .. you.rank) end
        local me = ctx.me
        local image = if me and me > 0 then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(me) .. "&w=48&h=48" else ""
        if self.you.Avatar.Image ~= image then self.you.Avatar.Image = image end
        copy(self.you.PlayerName, "You")
        copy(self.you.Value, you.text)
        copy(self.you.Note, you.note)
        self.you.Note.Visible = you.note ~= ""
    end
end
function Board:destroy()
    for _, c in self.connections do c:Disconnect() end
    table.clear(self.connections)
end
return Board
