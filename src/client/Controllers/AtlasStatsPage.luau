--!strict
-- Editable static nodes are authored by tools/atlas/author-stats.luau; PF015
-- authors their layout (tools/atlas/author-pf015-pages.luau): one scrolling
-- column of sections, grids that fit their columns to the width, one history
-- row design. Runtime creates only history-row clones and source-map
-- EditableImages, and fills content; it never sizes the page.
local Model = require(script.Parent.AtlasStatsModel)
local GuiService = game:GetService("GuiService")
local AssetService = game:GetService("AssetService")
local Typography = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PixelFrontTypography"))
local Page = {}
Page.__index = Page
-- PIVOT D15: Levels are removed. The authored level hero (PFLevelHero / PFLevelHeroCompact) and the history rows'
-- PFXp / PFLevelUp stay hidden.
local LEVEL_NODES = { "PFLevelHero", "PFLevelHeroCompact" }
local GROUP_IDS = { "Combat", "Economy", "Construction", "Naval", "Nuclear" }
local METRIC_IDS = { "Matches", "Victories", "Rate", "Longest" }
local MAP_METRICS = { "Matches", "Victories", "Rate", "Peak" }
local FILTER_IDS = { "All", "Victory", "Defeat" }
local FALLBACK = {
    PanelRaised = Color3.fromRGB(41, 43, 44), Text = Color3.fromRGB(238, 238, 235),
    MutedText = Color3.fromRGB(167, 171, 173), Accent = Color3.fromRGB(105, 144, 165),
    Positive = Color3.fromRGB(175, 203, 189), Gold = Color3.fromRGB(215, 186, 117),
}

local function node(parent: Instance, name: string): any
    return assert(parent:FindFirstChild(name), "Atlas Stats authored node missing: " .. parent:GetFullName() .. "." .. name)
end
local function copy(target: any, value: any)
    local text = if value == nil then "—" else tostring(value)
    if target.Text ~= text then target.Text = text end
end

function Page.new(pageRoot: Frame, context: any): any
    Typography.applyTree(pageRoot)
    local self: any = setmetatable({ root = pageRoot, context = context or {}, visible = false, destroyed = false,
        filter = "All", rows = {}, connections = {}, images = {}, mapAttempted = false }, Page)
    self.theme = self.context.theme or FALLBACK
    self.header = node(pageRoot, "Header")
    self.scroll = node(pageRoot, "Scroll")
    self.content = node(self.scroll, "Content")
    self.template = node(node(pageRoot, "Templates"), "HistoryRow")
    self.history = node(self.content, "History")
    self.rowRoot = node(self.history, "Rows")
    self.filters = node(self.content, "Filters")
    Typography.apply(self.content.Status, "Body")
    -- These are semantic numeric/category roles even when the template name is specific.
    for _, object in pageRoot:GetDescendants() do
        if object:IsA("TextLabel") then
            local name = object.Name
            if name == "Value" or name == "LeadValue" or object.Parent == self.content.Form.Marks then Typography.apply(object, "Value")
            elseif name == "Label" or name == "LeadLabel" or name == "Identity" or object.Parent == self.history.Header then Typography.apply(object, "Label") end
        end
    end
    for _, name in FILTER_IDS do
        local button = node(self.filters, name)
        table.insert(self.connections, button.Activated:Connect(function() self:setFilter(name) end))
        table.insert(self.connections, button.SelectionGained:Connect(function()
            -- Bring the filters into view (measured from the authored list).
            local top = self.filters.AbsolutePosition.Y - self.content.AbsolutePosition.Y
            self.scroll.CanvasPosition = Vector2.new(0, math.max(0, top - 12))
        end))
    end
    for index, name in FILTER_IDS do
        local button = node(self.filters, name)
        button.NextSelectionLeft = self.filters:FindFirstChild(FILTER_IDS[index - 1] or "")
        button.NextSelectionRight = self.filters:FindFirstChild(FILTER_IDS[index + 1] or "")
        button.NextSelectionUp = self.scroll
    end
    table.insert(self.connections, pageRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:layout() end))
    for _, name in LEVEL_NODES do
        local hero = self.content:FindFirstChild(name)
        if hero and hero:IsA("GuiObject") then hero.Visible = false end
    end
    -- PF036: this week's top 10 (Content.PFBoard, tools/atlas/author-pf036-leaderboard.luau); a place without it skips it.
    local boardRoot = self.content:FindFirstChild("PFBoard")
    if boardRoot then
        local player = game:GetService("Players").LocalPlayer
        self.board = require(script.Parent.AtlasStatsBoard).new(boardRoot, { me = if player then player.UserId else nil, theme = self.theme })
    end
    -- Stats v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-stats-v2.luau): when AtlasMenu.PFStatsV2 is authored it takes over
    -- the page; the old Scroll hides and this page only routes visibility, the model and the board to it.
    local menu = pageRoot:FindFirstAncestor("AtlasMenu")
    local layer = menu and menu:FindFirstChild("PFStatsV2")
    if layer then
        local pages = pageRoot.Parent
        local play = pages and pages:FindFirstChild("Play")
        local templates = play and play:FindFirstChild("Templates")
        local player = game:GetService("Players").LocalPlayer
        local ok, v2 = pcall(function()
            return require(script.Parent.AtlasStatsV2).new(layer, { getIdentity = self.context.getIdentity,
                mapSources = templates and templates:FindFirstChild("Maps"), me = if player then player.UserId else nil })
        end)
        -- the hero carries "Lifetime"; the page top bar's right note (it mirrors Header.Scope) stays empty
        if ok then self.v2 = v2; self.scroll.Visible = false; copy(self.header.Scope, "") else warn("[AtlasStats] v2 unavailable: " .. tostring(v2)) end
    end
    pageRoot.Visible = false
    self:update(if self.context.getStats then self.context.getStats() else { status = "loading" })
    return self
end

function Page:_feedback(button: any)
    if self.destroyed then return end
    local selected = button.Name == self.filter
    button:SetAttribute("PFSelected", selected)
    -- PF019 (MM 2026-10-06): lobby selection is the FIXED cobalt highlight (as the shop tabs); the
    -- interface accent drives only focus rings in the lobby.
    button.BackgroundColor3 = if selected then self.theme.Accent:Lerp(self.theme.Panel, .65) else self.theme.PanelRaised
end

function Page:_loadMaps()
    if self.mapAttempted or not self.visible then return end
    self.mapAttempted = true
    local storage = game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontIcons")
    if not storage then return end
    local Icons = require(script.Parent.ReferenceIcons)
    for _, map in Model.Maps do
        local target = node(node(node(self.content.Maps, map.id), "Art"), "Image")
        if target.Image ~= "" then continue end
        local asset = "LobbyMap" .. map.id .. "Part1"
        if not storage:FindFirstChild(asset) then continue end
        local image: EditableImage? = nil
        local ok = pcall(function()
            local bytes, width, height = Icons.pixels(asset)
            local created = assert(AssetService:CreateEditableImage({ Size = Vector2.new(width, height) }))
            image = created
            created:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), bytes)
            target.ImageContent = Content.fromObject(created)
        end)
        if ok and image then self.images[target] = image
        elseif image then image:Destroy() end
        target:SetAttribute("AtlasMapArtAvailable", ok)
    end
end

function Page:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible = visible
    self.root.Visible = visible
    if self.v2 then
        if visible then
            if self.context.requestLifetime then self.context.requestLifetime() end
            if self.context.requestBoard then self.context.requestBoard() end
            if self.context.getStats then self.v2:update(self.context.getStats()) end
        end
        self.v2:setVisible(visible)
        if not visible then
            local selected = GuiService.SelectedObject
            if selected and selected:IsDescendantOf(self.v2.layer) then GuiService.SelectedObject = nil end
        end
        return
    end
    if visible then
        if self.context.requestLifetime then self.context.requestLifetime() end -- PF036: PF - 2's lifetime record (StatsCommand Ready)
        if self.board and self.context.requestBoard then self.context.requestBoard() end -- PF036: the weekly top 10
        if self.context.getStats then self:update(self.context.getStats()) else self:_render() end
        self:_loadMaps()
        self:layout()
    else
        local selected = GuiService.SelectedObject
        if selected and selected:IsDescendantOf(self.root) then GuiService.SelectedObject = nil end
    end
end

function Page:update(model: any)
    if self.destroyed then return end
    self.model = model or { status = "unavailable" }
    if self.v2 then self.v2:update(self.model); return end
    if self.visible then self:_render() end
end

-- PF036: PF - 2's Leaderboard reply (StatsCommand).
function Page:setBoard(packet: any): boolean
    if self.destroyed then return false end
    if self.v2 then return self.v2:setBoard(packet) end
    if not self.board then return false end
    return self.board:setPacket(packet)
end

function Page:setFilter(filter: string)
    if self.destroyed or not table.find(FILTER_IDS, filter) then return end
    self.filter = filter
    self:_renderHistory()
    self:layout()
end

function Page:_render()
    local raw = self.model or { status = "loading" }
    -- Sparse loading/error envelopes are valid. They must never look like zero career totals.
    local model = if raw.summary then raw else Model.new():view()
    local unavailable = raw.status == "unavailable" or raw.status == "loading"
    local identity = if self.context.getIdentity then self.context.getIdentity() else nil
    copy(self.header.Identity, if identity then identity.displayName or identity.name else "Your record")
    local life = raw.lifetime == true -- PF036: the lifetime record is in (PF - 2's OpenFrontStats_v1)
    copy(self.header.Scope, if life then "Lifetime" else "This session · Lifetime unavailable")
    copy(self.header.Eyebrow, "YOUR RECORD")
    local notice = raw.notice or model.notice
    if raw.status == "loading" then notice = "Loading your session record…"
    elseif raw.status == "unavailable" then notice = "Session stats are unavailable. They will appear when match data is received."
    elseif raw.status == "empty" then notice = if life then "No matches yet. Play a match to begin your record." else "No matches this session. Play a match to begin your record. Lifetime data is unavailable."
    end
    copy(self.content.Status, notice)
    local summary = model.summary
    local career = self.content.Career
    copy(career.Matches.Label, "Matches joined")
    copy(career.Matches.Value, if unavailable then nil else Model.formatNumber(summary.matches))
    copy(career.Matches.Note, if unavailable then "This session" else Model.formatDuration(summary.duration) .. " simulated time")
    copy(career.Victories.Value, if unavailable then nil else Model.formatNumber(summary.wins))
    copy(career.Victories.Note, if unavailable then "This session" else tostring(summary.losses) .. " defeats")
    copy(career.Rate.Value, if unavailable then nil else Model.formatPercent(summary.rate))
    copy(career.Rate.Note, "Decided results only")
    copy(career.Longest.Value, if unavailable then nil else Model.formatDuration(summary.longest))
    copy(career.Longest.Note, "Observed match time")
    for i = 1, 10 do
        local mark = node(self.content.Form.Marks, "Mark" .. i)
        local result = if unavailable then nil else model.recent[i]
        copy(mark, if result == "Victory" then "W" elseif result == "Defeat" then "L" else "—")
        mark.BackgroundColor3 = if result == "Victory" then Color3.fromRGB(50, 73, 66) else Color3.fromRGB(48, 49, 51)
        mark.TextColor3 = if result == "Victory" then self.theme.Positive else self.theme.MutedText
    end
    copy(self.content.Form.Empty, if #model.recent > 0 then "Most recent first · Decided results only" elseif life then "No decided matches yet" else "No decided matches this session")
    for _, record in model.maps do
        local card = node(self.content.Maps, record.id)
        copy(card.Metrics.Matches.Value, if unavailable then nil else Model.formatNumber(record.matches))
        copy(card.Metrics.Victories.Value, if unavailable then nil else Model.formatNumber(record.wins))
        copy(card.Metrics.Rate.Value, if unavailable then nil else Model.formatPercent(record.rate))
        copy(card.Metrics.Peak.Value, if unavailable then nil else Model.formatPercent(record.peakLand))
        card.RateTrack.Fill.Size = UDim2.fromScale(if unavailable then 0 else record.rate or 0, 1)
    end
    for _, group in model.groups do
        local card = node(self.content.Groups, group.id)
        copy(card.LeadValue, if unavailable then nil else group.lead)
        copy(card.LeadLabel, group.label)
        for i, row in group.rows do
            local target = node(card.Rows, "Row" .. i)
            copy(target.Label, row.label)
            copy(target.Value, if unavailable then nil else row.value)
        end
    end
    copy(self.content.MapHeading.Note, if life then "Lifetime · Map records" else "This session · Observed map records")
    copy(self.content.RecordHeading.Note, if life then "Lifetime · — unavailable" else "This session · — unavailable")
    copy(self.content.Footer, if life then "Build counts include upgrades." else "Session totals reset when you reconnect. Build counts include upgrades; peaks come from received snapshots.")
    self:_renderHistory()
    self:layout()
end

function Page:_renderHistory()
    local records = (self.model and self.model.history) or {}
    local life = self.model ~= nil and self.model.lifetime == true -- PF036
    local visible = {}
    for _, record in records do
        if self.filter == "All" or record.result == self.filter then table.insert(visible, record) end
    end
    self.visibleRecords = visible
    for _, name in FILTER_IDS do
        local button = node(self.filters, name)
        button.Underline.Visible = name == self.filter
        button:SetAttribute("Selected", name == self.filter)
        self:_feedback(button)
    end
    for index, record in visible do
        local row = self.rows[index]
        if not row then
            row = self.template:Clone()
            row.Name = "Record" .. tostring(index)
            Typography.applyTree(row)
            for _, name in { "Map", "Result", "Duration", "Peak", "Gold" } do Typography.apply(row[name], "Value") end
            row.Parent = self.rowRoot
            self.rows[index] = row
        end
        row.Visible = true; row.LayoutOrder = index
        row:SetAttribute("MatchId", record.id)
        copy(row.Map, record.mapName)
        copy(row.Mode, record.mode)
        copy(row.Result, record.result)
        row.Result.TextColor3 = if record.result == "Victory" then self.theme.Positive else self.theme.Text
        copy(row.Duration, "Time  " .. Model.formatDuration(record.duration))
        copy(row.Peak, "Peak land  " .. Model.formatPercent(record.peakLand))
        copy(row.Gold, "Gold earned  " .. Model.formatNumber(record.goldEarned))
        copy(row.Played, record.played)
        -- PIVOT D15: no XP line, no level-up pill
        for _, name in { "PFXp", "PFLevelUp" } do
            local retired = row:FindFirstChild(name)
            if retired and retired:IsA("GuiObject") then retired.Visible = false end
        end
        row.Played.Visible = true
    end
    for index = #visible + 1, #self.rows do self.rows[index].Visible = false end
    self.history.Empty.Visible = #visible == 0
    copy(self.history.Empty, if self.model and self.model.status == "loading" then "Loading match history…"
        elseif self.model and self.model.status == "unavailable" then "Match history is unavailable."
        elseif self.filter == "Victory" then (if life then "No victories recorded yet." else "No victories recorded this session.")
        elseif self.filter == "Defeat" then (if life then "No defeats recorded yet." else "No defeats recorded this session.")
        else (if life then "No matches recorded yet." else "No matches recorded this session yet."))
    local total = (self.model and self.model.historyTotal) or #records
    copy(self.history.Footer, "Showing " .. tostring(#visible) .. " of " .. tostring(#records) .. (if life then " recent matches" else " recent session matches") .. (if total > 50 and not life then " · Latest 50 retained in this view" else ""))
    copy(self.content.HistoryHeading.Note, if life then "Latest matches" else "This connection only")
end

-- PF015: the page is authored; nothing to size. Kept for callers that relaid
-- the page on resize (the history header stays hidden: one row design).
function Page:layout(_sizeOverride: Vector2?)
    if self.destroyed then return end
    self.history.Header.Visible = false
end

function Page:destroy()
    if self.destroyed then return end
    self:setVisible(false)
    self.destroyed = true
    for _, connection in self.connections do connection:Disconnect() end
    if self.board then self.board:destroy() end -- PF036
    if self.v2 then self.v2:destroy() end
    for _, row in self.rows do row:Destroy() end
    for target, image in self.images do target.Image = ""; image:Destroy() end
    table.clear(self.connections); table.clear(self.rows); table.clear(self.images)
end

return Page
