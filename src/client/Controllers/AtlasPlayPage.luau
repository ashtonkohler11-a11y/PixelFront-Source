--!strict
-- Authored Atlas presentation. Backend ownership and the attempt counter stay in PublicLobbyController.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local InputService = game:GetService("UserInputService")
local Thumbnails = require(script.Parent.LobbyThumbnails)
-- PIVOT D15: Levels are removed; the authored PFLevel badge stays hidden.
local function hideRetired(node: Instance?) if node and node:IsA("GuiObject") then node.Visible = false end end
local Page = {}
Page.__index = Page

local KINDS = {"special", "ffa", "team"}
-- PF043: the public cards the server runs (Config.PublicQueue.Cards: Chaos + Standard for now); the authored third card
-- hides until the queue scales back up
local RUNNING = {special = true, ffa = true, team = true}
do
    local ok, config = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Config) end)
    local cards = ok and type(config) == "table" and type(config.PublicQueue) == "table" and config.PublicQueue.Cards
    if type(cards) == "table" then RUNNING = {}; for _, kind in cards do RUNNING[kind] = true end end
end
local MAPS = {"United States", "Africa", "Qing China"}
local MAP_DESCRIPTIONS = {
    ["United States"] = "Link cities with factories. Open new fronts by water.",
    Africa = "Build coastal ports. Protect your trade routes.",
    ["Qing China"] = "Build inland industry. Expand your early foothold.",
}
local MODIFIERS = {
    {"isRandomSpawn", "Random spawn"}, {"isCrowded", "Crowded"}, {"isHardNations", "Hard nations"},
    {"isAlliancesDisabled", "No alliances"}, {"isNukesDisabled", "No nukes"}, {"isSAMsDisabled", "No SAMs"},
    {"isPeaceTime", "4-minute peace"}, {"isWaterNukes", "Water nukes"}, {"isDoomsdayClock", "Doomsday clock"},
}
local function finite(value: any): boolean
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value: any): number?
    return if finite(value) and value >= 0 then math.floor(value) else nil
end
local function format(config: any): string
    if type(config) ~= "table" then return "—" end
    if config.gameMode == "Team" then return "Teams" end
    if config.gameMode == "Free For All" then return "Free-for-all" end
    return "Format unavailable"
end
local function modifiers(config: any): {string}
    local result = {}
    local values = if type(config) == "table" and type(config.publicGameModifiers) == "table" then config.publicGameModifiers else {}
    if finite(values.goldMultiplier) and values.goldMultiplier ~= 1 then
        table.insert(result, tostring(values.goldMultiplier) .. "× gold")
    end
    if finite(values.startingGold) and values.startingGold > 0 then
        local amount = if values.startingGold >= 1000000 then tostring(values.startingGold / 1000000) .. "M" else tostring(values.startingGold)
        table.insert(result, amount .. " starting gold")
    end
    for _, pair in MODIFIERS do if values[pair[1]] then table.insert(result, pair[2]) end end
    return result
end
local function timer(at: any, now: number): string
    if not finite(at) then return "Waiting for players" end
    local seconds = math.max(0, math.ceil(at - now))
    return if seconds == 0 then "Starting…" else string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function counts(packet: any): (number?, number?)
    local config = packet and packet.config
    return integer(packet and packet.numClients), integer(config and config.maxPlayers)
end
local function countText(packet: any): string
    local current, maximum = counts(packet)
    return (if current then tostring(current) else "—") .. " / " .. (if maximum then tostring(maximum) else "—")
end
function Page.new(pageRoot: Frame, context: any): any
    assert(pageRoot:GetAttribute("AtlasAuthorVersion"), "Run tools/atlas/author-play.luau first")
    local self: any = setmetatable({
        root = pageRoot, context = context, theme = context.theme, content = pageRoot.ContentScroll.Content,
        scroll = pageRoot.ContentScroll, layer = pageRoot.DialogLayer, dialog = pageRoot.DialogLayer.Dialog,
        -- PF015: Title and Close sit in the authored PFTitleBar.
        dialogTitle = (pageRoot.DialogLayer.Dialog:FindFirstChild("PFTitleBar") or pageRoot.DialogLayer.Dialog):FindFirstChild("Title"),
        dialogClose = (pageRoot.DialogLayer.Dialog:FindFirstChild("PFTitleBar") or pageRoot.DialogLayer.Dialog):FindFirstChild("Close"),
        templates = pageRoot.Templates, connections = {}, cards = {}, entries = {}, roster = {},
        model = {}, visible = false, destroyed = false, offset = 0, modal = nil, operation = 0,
        thumbnailRenderer = Thumbnails.new(), thumbnailFailed = false, elapsed = 0, pendingSince = nil,
        createDraft = {gameMap = "United States"},
    }, Page)
    local function connect(signal, callback) table.insert(self.connections, signal:Connect(callback)) end
    -- PF024 (MM): the collapsing lines (PFClip holders, author-pf024-playfloor floors them at 11 px) show only when
    -- they fit at that floor; between phone and desktop (720p, a queued gutter) they hide instead of drawing cropped.
    for _, label in pageRoot.ContentScroll.Content:GetDescendants() do
        if not (label:IsA("TextLabel") and label:GetAttribute("PFFloorHide")) then continue end
        local base = label:GetAttribute("PFFloorBase")
        if typeof(base) ~= "number" then base = label.TextTransparency; label:SetAttribute("PFFloorBase", base) end
        local function fit() label.TextTransparency = if label.TextFits then base else 1 end
        connect(label:GetPropertyChangedSignal("TextFits"), fit); fit()
    end
    -- PF021 (PF - 3, MM 2026-10-07: a "<map> / PLAYERS ×" panel flashed over the cards at menu load):
    -- with the W6 Room screen installed (AtlasMenu.Screens.Room), a hub room is that screen's alone;
    -- this page's legacy waiting dialog keeps only the match server's own arrival screen.
    local menu = pageRoot:FindFirstAncestor("AtlasMenu"); local screens = menu and menu:FindFirstChild("Screens")
    self.roomScreen = screens ~= nil and screens:FindFirstChild("Room") ~= nil
    -- PF019 (M1/M2): cards are authored on the global card kit (tools/atlas/author-pf019-play.luau);
    -- LobbyCardKit drives hover/press/focus/idle, this page fills content only.
    self.parts = {}; self.handles = {}; self.progress = {}; self.filled = {}
    for _, kind in KINDS do
        local card = self.content.Cards[kind]
        self.cards[kind] = card
        card.Visible = RUNNING[kind] == true -- PF043 (visibility only; the row's layout is authored)
        local inner = card.PFCardBody.PFCardInner
        local pill = inner.Head.Pill
        local p = {card = card, chaos = kind == "special", kind = inner.Head.Kind, pill = pill, dot = pill.Dot, ring = pill.Ring,
            ringStroke = pill.Ring:FindFirstChildWhichIsA("UIStroke"), pillLabel = pill.Label, well = inner.Well, noMap = inner.Well.NoMap,
            title = inner.Title, meta = inner:FindFirstChild("Meta") or inner.PFClipMeta.Meta, pips = inner.Seats.Pips, players = inner.Seats.Players,
            startsLabel = inner.Clock.StartsLabel, countdown = inner.Clock.Countdown, fill = inner.Bar.Fill, join = inner.Join,
            joinStroke = inner.Join:FindFirstChildWhichIsA("UIStroke"),
            hatch = card.PFCardBody:FindFirstChild("PFCardHatchClip") and card.PFCardBody.PFCardHatchClip:FindFirstChild("PFCardHatch")}
        self.parts[kind] = p
        self:feedback(p.join)
        connect(p.join.Activated, function() self:join(kind) end)
        connect(card.Activated, function() self:join(kind) end)
        if context.cardKit then
            self.handles[kind] = context.cardKit:bind(card, {targets = {p.join},
                idle = function(handle, now) self:idleMatch(kind, handle, now) end,
                onLook = function(handle) self:lookMatch(kind, handle) end})
        end
    end
    for name in {Solo = true, Create = true, Join = true} do
        local card = self.content.Actions[name]
        if context.cardKit then
            local inner = card.PFCardBody.PFCardInner
            local chevron, icon = inner.Chevron, inner.IconWell.Icon
            local base, hot = chevron.Position, false
            self.handles[name] = context.cardKit:bind(card, {onLook = function(handle)
                local now = handle.state.hover == true or handle.state.focused == true
                if now == hot or self.destroyed then return end
                hot = now
                local reduced = context.reducedMotion and context.reducedMotion()
                local info = TweenInfo.new(if reduced then 0 else .15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                TweenService:Create(chevron, info, {Position = if hot then base + UDim2.fromOffset(4, 0) else base,
                    TextColor3 = if hot then self.theme.Text else self.theme.MutedText}):Play()
                -- The pennant flutters once as the card wakes (M1 hover beat).
                if hot and not reduced then TweenService:Create(icon, TweenInfo.new(.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {Rotation = -7}):Play() end
            end})
        end
    end
    for name, action in {Solo = "solo", Create = "create", Join = "code"} do
        local control = self.content.Actions[name]
        self:feedback(control)
        connect(control.Activated, function()
            if not self.visible or self.layer.Visible then return end
            self.lastTrigger = control
            -- PF019: the full Solo (M4) and Create Lobby (M9) screens once installed; the old flows until then.
            if action == "solo" then
                if not (self.context.openScreen and self.context.openScreen("Solo")) then self:callSolo() end
            elseif action == "create" then
                if not (self.context.openScreen and self.context.openScreen("Create")) then self:create() end
            -- PF019: the full Join Lobby screen (PF - 1, M12) once installed; the code dialog until then.
            elseif not (self.context.openScreen and self.context.openScreen("Join")) then
                self:open("code", "Join Lobby", "Enter the six-character code shared by the lobby host.")
            end
        end)
    end
    for _, control in {self.dialogClose, self.dialog.Body.Cancel, self.dialog.Body.Submit, self.dialog.Body.Room.Overview.Leave,
        self.dialog.Body.Room.Overview.Start, self.dialog.Body.CreateOptions.Map} do self:feedback(control) end
    connect(self.dialogClose.Activated, function() self:handleEscape() end)
    connect(self.dialog.Body.Cancel.Activated, function() self:handleEscape() end)
    connect(self.dialog.Body.Room.Overview.Leave.Activated, function() self:cancel() end)
    connect(self.dialog.Body.Room.Overview.Start.Activated, function() self:startPrivate() end)
    connect(self.dialog.Body.CreateOptions.Map.Activated, function()
        if self.modal ~= "create" then return end
        local index = table.find(MAPS, self.createDraft.gameMap) or 1
        self.createDraft.gameMap = MAPS[index % #MAPS + 1]; self:renderCreate()
    end)
    connect(self.dialog.Body.Submit.Activated, function() self:submit() end)
    connect(self.dialog.Body.Code.FocusLost, function(enter) if enter and self.visible and self.modal == "code" then self:submit() end end)
    connect(pageRoot:GetPropertyChangedSignal("AbsoluteSize"), function() self:layout() end)
    connect(InputService:GetPropertyChangedSignal("PreferredInput"), function() self:layout() end)
    connect(pageRoot.Destroying, function() self:destroy() end)
    connect(RunService.Heartbeat, function(dt)
        if self.destroyed or not self.visible then return end
        if self.modal == "waiting" then self:glintRoster() end
        self.elapsed += dt
        if self.elapsed < .25 then return end
        self.elapsed = 0; self:updateTime(); self:updateThumbnails()
        if self.pendingSince and os.clock() - self.pendingSince > 20 and self.modal == "pending" then
            self.dialog.Body.Message.Text = "Still connecting. You can cancel and choose another match."
        end
    end)
    self:layout(); self:update({}); self:setVisible(false)
    return self
end

function Page:feedback(button: TextButton)
    -- Keep the crisp focus affordance; PFMenuMotion owns hover/press animation.
    local focus = button:FindFirstChild("Focus")
    if not focus then return end
    for _, pair in {
        {button.SelectionGained, function() if not self.destroyed and focus.Parent then focus.Transparency = 0 end end},
        {button.SelectionLost, function() if not self.destroyed and focus.Parent then focus.Transparency = 1 end end},
    } do table.insert(self.connections, pair[1]:Connect(pair[2])) end
end

function Page:now(): number return os.clock() + self.offset end

function Page:mapPreview(card: TextButton, map: any)
    if card:GetAttribute("AtlasMap") == map then return end
    card:SetAttribute("AtlasMap", map)
    local old = card:FindFirstChild("Thumbnail")
    local z = old.ZIndex
    for _, child in old:GetChildren() do if child.Name ~= "PFCardZoom" then child:Destroy() end end -- PF019: keep the hover zoom
    local source = if type(map) == "string" then self.templates.Maps:FindFirstChild(map) else nil
    if not source and self.context.thumbnailSources and map then
        local supplied = self.context.thumbnailSources[map]
        source = supplied and (supplied:FindFirstChild("Thumbnail") or supplied)
    end
    if source then
        for key, value in source:GetAttributes() do old:SetAttribute(key, value) end
        for _, child in source:GetChildren() do
            local clone = child:Clone(); clone.Parent = old
            if clone:IsA("GuiObject") then clone.ZIndex = z + 1 end
            for _, descendant in clone:GetDescendants() do if descendant:IsA("GuiObject") then descendant.ZIndex = z + 1 end end
        end
    end
    if card:FindFirstChild("NoMap") then card.NoMap.Visible = source == nil end
end

-- PF015 wraps the desktop-only labels in clipping holders (PFClip<Name>) so
-- they vanish on phones instead of drawing 1px text.
local function clipped(root: Instance, name: string): any
    return root:FindFirstChild(name) or (root:FindFirstChild("PFClip" .. name) :: any)[name]
end

-- PF019 idle loops (M1 sheet 2): only where they carry meaning. The kit calls these only
-- while the card is on screen, the menu is up and ReducedMotion is off.
function Page:idleMatch(kind: string, handle: any, now: number)
    local p = self.parts[kind]
    if p.pill.Visible and p.live then
        -- LIVE: a ring grows from the dot to ~2.7x and fades, 1.2s loop.
        local t = (now / 1.2 + handle.phase) % 1
        local s = .32 * (1 + 1.7 * t)
        p.ring.Size = UDim2.fromScale(s, s)
        if p.ringStroke then p.ringStroke.Transparency = .15 + .85 * t end
    end
    if p.chaos and p.hatch then
        -- Chaos hatch drifts 24px every 4s, linear and seamless (16px pitch).
        p.hatch.Position = UDim2.fromOffset(-((now * 6 + handle.phase * 16) % 16), 0)
    end
end
-- The whole card is one target: Join brightens with the card (M1).
function Page:lookMatch(kind: string, handle: any)
    local p = self.parts[kind]
    if self.destroyed or not p.joinStroke then return end
    local hot = (handle.state.hover == true or handle.state.focused == true) and self.entries[kind] ~= nil
    local enabled = self.entries[kind] ~= nil
    local info = TweenInfo.new(if self.context.reducedMotion and self.context.reducedMotion() then 0 else .15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local rest = if p.chaos then self.theme.Gold else self.theme.Border
    TweenService:Create(p.joinStroke, info, {Color = if not enabled then Color3.fromHex("#3d3d3d") elseif hot and not p.chaos then Color3.fromHex("#8c8c8c") else rest,
        Thickness = if hot then 2 else 1}):Play()
    TweenService:Create(p.join, info, {BackgroundColor3 = if hot then self.theme.PanelRaised else self.theme.Panel}):Play()
end

function Page:slots(card: TextButton, packet: any)
    local current, maximum = counts(packet)
    -- Segment count is the real capacity for approved small queues; larger queues use a proportional meter.
    local segments = if maximum and maximum > 0 then math.min(maximum, 24) else 0
    local container = self.parts[card.Name].pips
    if container:GetAttribute("Segments") ~= segments then
        for _, child in container:GetChildren() do if child:GetAttribute("AtlasDynamic") then child:Destroy() end end
        for index = 1, segments do
            local segment = self.templates.Slot:Clone(); segment.Name = tostring(index)
            segment:SetAttribute("AtlasDynamic", true); segment.Visible = true; segment.LayoutOrder = index; segment.Parent = container
        end
        container:SetAttribute("Segments", segments)
    end
    local filled = if maximum and maximum > 0 and current then math.ceil(math.clamp(current / maximum, 0, 1) * segments) else 0
    local before = self.filled[card.Name] or filled
    self.filled[card.Name] = filled
    local reduced = self.context.reducedMotion and self.context.reducedMotion()
    for _, segment in container:GetChildren() do
        if segment:IsA("Frame") then
            -- M1: filled seats are white (gold on Chaos), empty seats a quiet grey. No accent
            -- colour at rest; cobalt stays the focus colour.
            local index = tonumber(segment.Name) or math.huge
            local occupied = index <= filled
            segment.BackgroundColor3 = if occupied then (if card.Name == "special" then self.theme.Gold else self.theme.Text) else Color3.fromHex("#3a3a3a")
            -- A player joins: the new pip pops 1.0 -> 1.3 -> 1.0 (Back Out, 0.25s).
            local pop = segment:FindFirstChild("PFPop")
            if pop and occupied and index > before and not reduced and self.visible then
                pop.Scale = 1.3
                TweenService:Create(pop, TweenInfo.new(.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
            end
        end
    end
end

-- The queued key's look (cobalt fill, light text) over the authored one, which comes back when the queue ends.
local QUEUED = {fill = Color3.fromHex("#3678ff"), ink = Color3.fromHex("#ffffff")}
function Page:paintQueued(p: any)
    local join = p.join
    if join:GetAttribute("PFBaseFill") == nil then
        join:SetAttribute("PFBaseFill", join.BackgroundColor3); join:SetAttribute("PFBaseFillT", join.BackgroundTransparency)
    end
    join.BackgroundColor3 = if p.queued then QUEUED.fill else join:GetAttribute("PFBaseFill")
    join.BackgroundTransparency = if p.queued then 0 else join:GetAttribute("PFBaseFillT")
    if p.joinStroke then p.joinStroke.Enabled = not p.queued end
    local clock = p.countdown.Parent
    if clock then clock.Visible = not p.queued end
end
-- PF043 B3 (board PF043-B2 searching): while a card waits for its next match a soft cobalt glint sweeps its time line
-- (Bar.PFSweep, authored by tools/atlas/author-pf043-daily-tab.luau); reduced motion holds it still
function Page:paintSweep(p: any, searching: boolean)
    local sweep = p.fill.Parent and p.fill.Parent:FindFirstChild("PFSweep")
    if not sweep then return end
    sweep.Visible = searching
    if searching and not p.sweepTween then
        local reduced = self.context.reducedMotion and self.context.reducedMotion()
        sweep.Position = UDim2.fromScale(if reduced then .375 else 0, 0)
        if not reduced then
            p.sweepTween = TweenService:Create(sweep, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), {Position = UDim2.fromScale(.75, 0)})
            p.sweepTween:Play()
        end
    elseif not searching and p.sweepTween then
        p.sweepTween:Cancel(); p.sweepTween = nil
    end
end

function Page:renderCards()
    local anyQueued = false
    for _, kind in KINDS do
        local card, p = self.cards[kind], self.parts[kind]
        local queue = self.model.queues and self.model.queues[kind]
        local entry = if type(queue) == "table" then queue[1] else nil
        if type(entry) ~= "table" or type(entry.config) ~= "table" or type(entry.id) ~= "string" then entry = nil end
        self.entries[kind] = entry
        if entry and (not integer(entry.config.maxPlayers) or entry.config.maxPlayers < 1) then entry = nil; self.entries[kind] = nil end
        local config = entry and entry.config
        self:mapPreview(p.well, config and config.gameMap)
        p.noMap.Text = if config then "Loading the map…" else "Waiting for a public match"
        -- Title = the map; one meta line says what kind of match it is (M1).
        p.title.Text = if config then tostring(config.gameMap or "Public match") else "Finding a match…"
        local meta = {}
        if config then
            if kind == "special" then table.insert(meta, "Chaos rules") end
            table.insert(meta, format(config))
            for _, label in modifiers(config) do if #meta < 4 then table.insert(meta, label) end end
        end
        p.meta.Text = table.concat(meta, " · ")
        -- LIVE once the countdown runs (the ring pulses); OPEN while it waits for players.
        p.live = entry ~= nil and finite(entry.startsAt)
        p.pill.Visible = entry ~= nil
        p.pillLabel.Text = if p.live then "LIVE" else "OPEN"
        p.dot.BackgroundColor3 = if p.live then Color3.fromHex("#4ade80") else Color3.fromHex("#8c8c8c")
        if p.ringStroke then p.ringStroke.Transparency = 1 end
        -- PF043 B3: no dashes while a card waits for its next match
        p.players.Text = if entry then countText(entry) .. " players" else "Finding players"
        self:paintSweep(p, entry == nil)
        self:slots(card, entry)
        local current, capacity = counts(entry)
        local full = current and capacity and capacity > 0 and current >= capacity
        -- PF024 J2: the match you queue for (the dock carries it while you browse) offers Leave queue here too
        local room = self.model.room
        local queued = entry ~= nil and type(room) == "table" and room.kind == "public" and room.id == entry.id
        -- PF036: a party member's cards read "Leader picks" behind the gold crown (the leader queues for the party)
        local follower = self:partyFollower()
        -- PF043 B3 (board PF043-B2/B3): the queue rides on its card. The key turns cobalt and reads "In queue · 0:18 ✕"
        -- (updateTime fills the timer; a tap leaves), the card's own clock steps aside (one timer), and the page tells
        -- the queue dock it can hide while Play shows (PFQueuedOnCard)
        p.queued = queued and not follower
        if p.queued then anyQueued = true end
        p.join.Text = if not entry then "Join match" elseif follower then "Leader picks" elseif p.queued then "In queue" elseif full then "Lobby full" else "Join match"
        self:paintQueued(p)
        local crown = p.join:FindFirstChild("PFLeaderCrown")
        if crown then crown.Visible = follower and entry ~= nil end
        p.join.Active = entry ~= nil and not self.layer.Visible
        p.join.Selectable = entry ~= nil and not self.layer.Visible
        card.Active = p.join.Active
        local enabledText = p.join:GetAttribute("PFEnabledText")
        p.join.TextColor3 = if not entry or follower then self.theme.MutedText elseif p.queued then QUEUED.ink elseif typeof(enabledText) == "Color3" then enabledText else self.theme.Text
        p.join.TextTransparency = 0
        local handle = self.handles[kind]
        if handle then handle:setDisabled(entry == nil); self:lookMatch(kind, handle) end
    end
    if self.root:GetAttribute("PFQueuedOnCard") ~= anyQueued then self.root:SetAttribute("PFQueuedOnCard", anyQueued) end
    clipped(self.content, "Status").Text = tostring(self.model.status or "Public matchmaking")
end

function Page:updateTime()
    local now = self:now()
    for _, kind in KINDS do
        local entry, p = self.entries[kind], self.parts[kind]
        local timed = entry ~= nil and finite(entry.startsAt)
        p.countdown.Text = if timed then timer(entry.startsAt, now) else ""
        p.startsLabel.Text = if not entry then "" elseif timed then "Starts in" else "Waiting for players"
        if p.queued then p.join.Text = if timed then "In queue · " .. timer(entry.startsAt, now) .. "   ×" else "In queue   ×" end -- × (Ubuntu has no ✕)
        -- The countdown bar fills linearly; its length is the longest countdown seen for this queue.
        local fraction = 0
        if timed then
            local remaining = math.max(0, entry.startsAt - now)
            local total = math.max(self.progress[entry.id] or 0, remaining, 1)
            self.progress[entry.id] = total
            fraction = 1 - remaining / total
        end
        p.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
    end
    local waiting = self.model.waiting
    if waiting then
        self.dialog.Body.Room.Overview.Countdown.Text = if waiting.isPrivate and not finite(waiting.startsAt) then (if self.starting then "Starting…" else "Host starts the match") else timer(waiting.startsAt, now)
    end
end

function Page:invoke(name: string, ...: any): (boolean, any)
    local callback = self.context[name]
    if type(callback) ~= "function" then return false, {ok = false, message = "This action is not available yet."} end
    local ok, result = pcall(callback, ...)
    if not ok then return false, {ok = false, message = "The request could not be completed. Please try again."} end
    if type(result) == "table" and result.ok == false then return false, result end
    return true, result
end

local JOIN_GAP = 3.25 -- PF024: LobbyContract.RateLimits.JoinPublic (3 s) plus a little clock slack
-- PF036: in a party of two or more, only the leader queues.
function Page:partyFollower(): boolean
    local party = self.model.party
    return type(party) == "table" and type(party.size) == "number" and party.size > 1 and party.isLeader ~= true
end
function Page:join(kind: string)
    if self.destroyed or not self.visible or self.layer.Visible then return end
    local entry = self.entries[kind]
    if not entry then return end
    if self:partyFollower() then return end
    self.lastTrigger = self.parts[kind].join; self.retryKind = kind; self.retryAction = nil
    -- PF024 J2: already queued for a public match: its card leaves the queue; another card switches to it
    -- (leave first; the join follows once the room has closed, within a few seconds)
    local room = self.model.room
    if type(room) == "table" and room.kind == "public" then
        self.switchTo = if room.id ~= entry.id then {kind = kind, at = os.clock()} else nil
        self:invoke("cancelPublic")
        return
    end
    local current, capacity = counts(entry)
    if current and capacity and current >= capacity then
        self:open("full", "Lobby full", "This match is full. Choose another public match or wait for the next queue update.")
        return
    end
    if finite(entry.startsAt) and entry.startsAt <= self:now() then
        self:open("full", "Match starting", "This match is starting. Choose another match while the queues refresh.")
        self:invoke("refreshQueues"); return
    end
    self:open("pending", "Joining…", "Requesting a place in the match. You can cancel while connecting.")
    self.pendingSince = os.clock()
    local operation = self.operation
    -- PF024 (Ashton's playtest "Could not join / Please wait a moment"): the server takes one JoinPublic per 3 s
    -- (LobbyContract.RateLimits) and answers RateLimited inside it; a queue switch or Cancel -> Join can land there.
    -- The page paces the send instead (the Joining dialog covers the wait; Cancel still works).
    local function send()
        if self.destroyed or operation ~= self.operation then return end
        self.lastJoinAt = os.clock()
        local ok, result = self:invoke("joinPublic", entry.id)
        if not self.destroyed and operation == self.operation and not ok then
            self:open("error", "Could not join", tostring(result.message))
        end
    end
    local wait = JOIN_GAP - (os.clock() - (self.lastJoinAt or -math.huge))
    if wait > 0 then task.delay(wait, send) else send() end
end

function Page:callSolo()
    local ok, result = self:invoke("solo")
    if not ok then self:open("message", "Solo", tostring(result.message)) end
end

function Page:renderCreate()
    local fields = self.dialog.Body.CreateOptions
    fields.Map.Text = self.createDraft.gameMap .. "  ›"
end

function Page:create()
    if not self.createNameSeeded then
        self.createNameSeeded = true
        local identity = self.model.identity or (self.context.getIdentity and self.context.getIdentity())
        if identity and type(identity.displayName) == "string" then
            local name = identity.displayName
            local boundary = utf8.offset(name, 25)
            if boundary then name = string.sub(name, 1, boundary - 1) end
            self.dialog.Body.CreateOptions.LobbyName.Text = name .. "'s lobby"
        end
    end
    self:open("create", "Create Lobby", "Bring your friends. Choose a name and map for your lobby.")
    self:renderCreate()
end

function Page:submit()
    if not self.visible or not self.layer.Visible then return end
    if self.modal == "error" then
        if self.retryAction == "create" then self:create()
        elseif self.retryAction == "code" then self:open("code", "Join Lobby", "Enter the six-character code shared by the lobby host.")
        elseif self.retryKind then local kind = self.retryKind; self:close(); self:join(kind) end
        return
    end
    if self.modal ~= "code" and self.modal ~= "create" then return end
    local callback, payload, roomName
    self.retryKind = nil; self.retryAction = self.modal
    if self.modal == "create" then
        payload = table.clone(self.createDraft)
        roomName = string.match(self.dialog.Body.CreateOptions.LobbyName.Text, "^%s*(.-)%s*$") or ""
        local length = utf8.len(roomName)
        if not length or length < 1 or length > 32 or #roomName > 128 or string.find(roomName, "%c") then
            self.dialog.Body.Message.Text = "Enter a lobby name using 1–32 characters, without line breaks."
            return
        end
        callback = "createLobby"
    else
        payload = string.upper(string.match(self.dialog.Body.Code.Text, "^%s*(.-)%s*$") or "")
        if #payload ~= 6 or not string.match(payload, "^[A-Z0-9]+$") then
            self.dialog.Body.Message.Text = "Enter the six letters or numbers in the lobby code."
            return
        end
        self.dialog.Body.Code.Text = payload; callback = "joinLobby"
    end
    self:open("pending", if callback == "createLobby" then "Creating lobby…" else "Joining lobby…", "Connecting to the lobby service. You can cancel while connecting.")
    self.pendingSince = os.clock()
    local operation = self.operation
    local ok, result = self:invoke(callback, payload, roomName)
    if self.destroyed or operation ~= self.operation then return end
    if not ok then self:open("error", "Could not connect", tostring(result.message)) end
end

function Page:setBackgroundInput(enabled: boolean)
    for _, kind in KINDS do
        local button = self.parts[kind].join
        button.Active = enabled and self.entries[kind] ~= nil; button.Selectable = button.Active
        self.cards[kind].Active = button.Active
    end
    for _, button in self.content.Actions:GetChildren() do if button:IsA("TextButton") then button.Active = enabled; button.Selectable = enabled end end
    self.scroll.ScrollingEnabled = enabled
end

function Page:open(kind: string, title: string, message: string)
    self.operation += 1; self.modal = kind; self.pendingSince = nil
    self.dialog.Body.Code:ReleaseFocus(); self.dialog.Body.CreateOptions.LobbyName:ReleaseFocus()
    self.dialog.Body.CanvasPosition = Vector2.zero
    self.layer.Visible = true
    -- PF024 (Ashton: "this popup is super long just make it normal proportions"): short modals take the authored
    -- compact width; only the match server's arrival roster (waiting) keeps the wide one (Dialog PFCompactWidth /
    -- PFWideWidth, author-pf024-dialog). An older place without them keeps its single cap.
    local cap = self.dialog:FindFirstChild("PFSize")
    local width = self.dialog:GetAttribute(if kind == "waiting" then "PFWideWidth" else "PFCompactWidth")
    if cap and cap:IsA("UISizeConstraint") and type(width) == "number" then cap.MaxSize = Vector2.new(width, math.huge) end
    self.dialogTitle.Text = title
    local body = self.dialog.Body
    body.Message.Text = message; body.Message.Visible = kind ~= "waiting"
    body.Code.Visible = kind == "code"; body.Room.Visible = kind == "waiting"; body.CreateOptions.Visible = kind == "create"
    body.Submit.Visible = kind == "code" or kind == "create" or kind == "error" and (self.retryKind ~= nil or self.retryAction ~= nil)
    body.Submit.Text = if kind == "error" then "Try again" elseif kind == "create" then "Create lobby" else "Join lobby"
    body.Submit.Active = true; body.Submit.Selectable = true
    body.Cancel.Visible = kind ~= "waiting"
    body.Cancel.Text = if kind == "pending" then "Cancel joining" else "Back"
    self:setBackgroundInput(false)
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then GuiService.SelectedObject = self.dialogClose end
    self:layout(); self.root:SetAttribute("ModalOpen", true)
end

function Page:close()
    self.operation += 1; self.modal = nil; self.pendingSince = nil; self.returning = false; self.starting = false
    self.dialog.Body.Code:ReleaseFocus(); self.dialog.Body.CreateOptions.LobbyName:ReleaseFocus()
    self.layer.Visible = false; self.root:SetAttribute("ModalOpen", false)
    self:setBackgroundInput(self.visible)
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.layer) then
        GuiService.SelectedObject = if self.visible and self.lastTrigger and self.lastTrigger.Selectable then self.lastTrigger else nil
    end
end

function Page:cancel()
    if self.returning then return end
    self.lastError = nil
    local online = self.model.waiting ~= nil or self.model.online == true
    local ok, result = self:invoke("cancelPublic")
    if not ok then
        if online then self.dialog.Body.Room.Overview.Message.Text = tostring(result.message)
        else self:open("message", "Could not cancel", tostring(result.message)) end
        return
    end
    if online then
        self.returning = true
        self.dialog.Body.Room.Overview.Message.Text = "Returning to the lobby…"
        self.dialog.Body.Room.Overview.Leave.Text = "Returning…"
    else self:close() end
end

function Page:startPrivate()
    local waiting = self.model.waiting
    if not self.visible or self.modal ~= "waiting" or not waiting or not waiting.isPrivate or not waiting.canStart or self.starting or not self.dialog.Body.Room.Overview.Start.Visible then return end
    self.starting = true; self.lastError = nil; self.dialog.Body.Room.Overview.Start.Text = "Starting…"
    local ok, result = self:invoke("startPrivate")
    if not ok then self.starting = false; self:renderWaiting(waiting); self.dialog.Body.Room.Overview.Message.Text = tostring(result.message) end
end

function Page:handleEscape(): boolean
    if not self.layer.Visible then return false end
    if self.modal == "pending" or self.modal == "waiting" then self:cancel() else self:close() end
    return true
end

function Page:isModalOpen(): boolean
    return self.visible and self.layer.Visible
end

function Page:focusActive(): GuiObject?
    if not self.visible or self.destroyed then return nil end
    local target: GuiObject? = nil
    if self.layer.Visible then
        if self.modal == "waiting" then
            local overview = self.dialog.Body.Room.Overview
            target = if overview.Start.Visible and overview.Start.Selectable then overview.Start else overview.Leave
        elseif self.modal == "create" then target = self.dialog.Body.CreateOptions.Map
        elseif self.modal == "code" then target = self.dialog.Body.Code
        elseif self.dialog.Body.Submit.Visible then target = self.dialog.Body.Submit
        else target = self.dialog.Body.Cancel end
    else
        for _, kind in KINDS do if self.parts[kind].join.Selectable then target = self.parts[kind].join; break end end
        if not target then target = self.content.Actions.Solo end
    end
    GuiService.SelectedObject = target
    return target
end

-- PF020 V3 (PF - 2): a VIP arrival (roster[i].vip, from GlobalLobbyService) gets the gold name and the
-- authored VIP pill (tools/atlas/author-pf020-vip-arrival.luau; PF - 3's room pill structure). The glint
-- is LobbyScreenParts.vipGlint's rule (one 0.6 s pass every 6 s, pills >= 20 px tall), inlined so this
-- page keeps its dependencies; none under reduced motion.
local VIP_NAME = Color3.fromHex("#ffd77a")
function Page:glintRoster()
    if self.context.reducedMotion and self.context.reducedMotion() then return end
    local k = (os.clock() % 6) / .6
    local offset = if k <= 1 then -1 + 2 * k else 1
    for _, row in self.roster do
        local pill = row:FindFirstChild("PFVip")
        local sweep = pill and pill.Visible and pill.AbsoluteSize.Y >= 20 and pill:FindFirstChild("Face") and pill.Face:FindFirstChild("Glint") and pill.Face.Glint:FindFirstChild("Sweep")
        if sweep then sweep.Offset = Vector2.new(offset, 0) end
    end
end

function Page:renderRoster(packet: any)
    local room = self.dialog.Body.Room
    local list = packet.roster
    local hasRoster = type(list) == "table"
    local identities = {}
    if hasRoster then
        for _, identity in list do if type(identity) == "table" then table.insert(identities, identity) end end
    elseif self.model.online and self.context.getIdentity then
        local identity = table.clone(self.context.getIdentity())
        identity.isLocal = true
        local profile = self.model.profile or (self.context.getProfile and self.context.getProfile())
        identity.equipped = profile and profile.equipped
        identity.cosmetics = profile and profile.identityCosmetics
        table.insert(identities, identity)
    end
    local localIdentity = self.model.identity or (self.context.getIdentity and self.context.getIdentity()) or {}
    for index, identity in identities do
        local row = self.roster[index]
        if not row then row = self.templates.PlayerRow:Clone(); row.Name = "Player" .. index; row.Parent = room.Roster.Rows; self.roster[index] = row end
        local name = tostring(identity.displayName or identity.name or "Player")
        local isLocal = identity.isLocal == true or identity.userId ~= nil and tostring(identity.userId) == tostring(localIdentity.userId)
        row.Nameplate.DisplayName.Text = name
        row.Title.Text = ""; row.Context.Text = if isLocal then "YOU" else ""
        if self.context.applyProfile then
            local payload = table.clone(identity); payload.displayName = name; payload.context = if isLocal then "YOU" else ""
            self.context.applyProfile(row, payload)
        end
        local vip = identity.vip == true
        self.nameColor = self.nameColor or self.templates.PlayerRow.Nameplate.DisplayName.TextColor3
        row.Nameplate.DisplayName.TextColor3 = if vip then VIP_NAME else self.nameColor
        local pill = row:FindFirstChild("PFVip"); if pill then pill.Visible = vip end
        -- PF023 L4: the level badge before the name (PF - 2's roster[i].level; you fall back to your own)
        hideRetired(row.Nameplate:FindFirstChild("PFLevel", true))
        row.LayoutOrder = index; row.Visible = true
    end
    for index = #self.roster, #identities + 1, -1 do self.roster[index]:Destroy(); table.remove(self.roster, index) end
    room.Roster.Note.Text = if hasRoster then "Waiting for the match to start." else "Full player details are not available from this lobby yet."
    room.Roster.Count.Text = countText(packet)
end

function Page:renderWaiting(packet: any)
    if self.modal ~= "waiting" then self:open("waiting", "Waiting room", "") end
    local config = packet.config or {}
    local overview = self.dialog.Body.Room.Overview
    local mods = modifiers(config)
    -- A room name is displayed only after the backend returns its filtered value.
    self.dialogTitle.Text = tostring(packet.roomName or config.gameMap or "Waiting room")
    overview.Kind.Text = format(config) .. (if #mods > 0 then " · " .. table.concat(mods, " · ") else "")
    overview.Map.Text = tostring(config.gameMap or "Verifying match…")
    overview.Count.Text = "Players   " .. countText(packet)
    local localIdentity = self.model.identity or (self.context.getIdentity and self.context.getIdentity()) or {}
    local isHost = packet.hostUserId ~= nil and tostring(packet.hostUserId) == tostring(localIdentity.userId)
    if not self.returning then
        overview.Message.Text = if packet.isPrivate and not isHost and not finite(packet.startsAt) then "Waiting for the host to start the match." else tostring(packet.message or "Waiting for the match to start.")
    end
    overview.Leave.Text = if self.returning then "Returning…" else "Leave lobby  ←"
    overview.RoomCode.Visible = packet.isPrivate == true
    overview.RoomCode.Text = if packet.roomCode then "ROOM CODE   " .. tostring(packet.roomCode) else ""
    overview.Start.Visible = packet.isPrivate == true and isHost
    overview.Start.Active = packet.canStart == true and not self.starting
    overview.Start.Selectable = overview.Start.Active
    overview.Start.Text = if self.starting then "Starting…" elseif packet.canStart then "Start match  →" else "Waiting for arrivals…"
    overview.Start.TextTransparency = if overview.Start.Active then 0 else .35
    self:mapPreview(overview.Preview, config.gameMap)
    self:renderRoster(packet); self:layout()
end

function Page:update(model: any)
    if self.destroyed or type(model) ~= "table" then return end
    local previous = self.model
    -- Backend adapters may mutate their model in place between notifications.
    self.model = table.clone(model)
    local newError = model.error ~= nil and model.error ~= self.lastError
    self.lastError = model.error
    if finite(model.serverNow) then self.offset = model.serverNow - (if finite(model.receivedAt) then model.receivedAt else os.clock()) end
    self:renderCards()
    if model.tutorialActive then self:close();self:updateTime();return end
    if previous.tutorialActive then self:close() end
    local waiting = model.waiting
    if waiting and waiting.hub and self.roomScreen then waiting = nil end -- PF021: the Room screen shows hub rooms
    if waiting then
        if newError then self.returning = false; self.starting = false end
        self:renderWaiting(waiting)
        if newError then self.dialog.Body.Room.Overview.Message.Text = tostring(model.error) end
    elseif model.room then
        -- PF024: in a room now (the Joined / Room screen or the queue dock shows it): the joining dialog is done
        if self.modal == "pending" or self.modal == "waiting" then self:close() end
    elseif model.joining then
        if self.modal ~= "pending" then self:open("pending", "Joining…", "Connecting to the match server…"); self.pendingSince = os.clock() end
    elseif self.modal == "pending" and (newError or previous.joining and not model.joining) then
        self:open("error", if self.retryAction == "create" then "Could not create lobby" else "Could not join", tostring(model.error or model.status or "The join request ended. Please try again."))
    elseif self.modal == "waiting" then self:close() end
    self:updateTime(); self:setBackgroundInput(self.visible and not self.layer.Visible)
    -- PF024 J2: a queue switch joins the other match once the old room has gone (never after a few seconds)
    local switch = self.switchTo
    if switch and not model.room and not model.joining and not model.pending then
        self.switchTo = nil
        if os.clock() - switch.at < 6 then self:join(switch.kind) end
    end
end

-- PF015: the Play page is AUTHORED (tools/atlas/author-pf015-pages.luau): one
-- composition fitted to the A06 and desktop anchors, dialogs that hug their
-- content and scroll. Nothing here sizes the page; a resize only refreshes
-- the countdowns and the map previews' contain-fit.
function Page:layout(_sizeOverride: Vector2?)
    if self.destroyed then return end
    self:updateTime(); self:updateThumbnails()
end

function Page:containThumbnail(card: TextButton)
    local thumbnail = card:FindFirstChild("Thumbnail")
    if not thumbnail then return end
    local width = thumbnail:GetAttribute("OriginalWidth")
    local height = thumbnail:GetAttribute("OriginalHeight")
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then return end
    -- Match the approved overview fit. The shared renderer retains cover for legacy/Stats uses.
    -- PF019: the hover zoom (PFCardZoom) scales the thumbnail; fit its unscaled box.
    local zoom = thumbnail:FindFirstChild("PFCardZoom")
    local size = thumbnail.AbsoluteSize / (if zoom and zoom.Scale > 0 then zoom.Scale else 1)
    local padding = if card.Name == "Preview" then 9 else math.clamp(math.floor(size.Y * .06), 4, 14)
    if size.X <= padding * 2 or size.Y <= padding * 2 then return end
    local scale = math.min((size.X - padding * 2) / width, (size.Y - padding * 2) / height)
    local dx, dy = (size.X - width * scale) / 2, (size.Y - height * scale) / 2
    for _, part in thumbnail:GetChildren() do
        if part:IsA("ImageLabel") and part:GetAttribute("SourceAsset") then
            part.AnchorPoint = Vector2.zero
            part.Position = UDim2.fromOffset(dx + (part:GetAttribute("SourceX") or 0) * scale, dy + (part:GetAttribute("SourceY") or 0) * scale)
            part.Size = UDim2.fromOffset((part:GetAttribute("SourceWidth") or width) * scale, (part:GetAttribute("SourceHeight") or height) * scale)
        end
    end
    thumbnail:SetAttribute("AtlasPreviewFit", "Contain")
    thumbnail:SetAttribute("AtlasPreviewPadding", padding)
end

function Page:updateThumbnails()
    if self.destroyed or self.thumbnailFailed then return end
    -- PF031: behind another lobby tab the decoded map previews stay bound (re-decoding three maps on every return to
    -- Play was a hitch); the menu hiding or a screen opening over it (setVisible without hold) releases them.
    if self.holdThumbnails and not self.visible then return end
    local cards = {}
    -- PF019: the renderer and the fit work on each card's map well (it holds Thumbnail/NoMap).
    for _, kind in KINDS do table.insert(cards, self.parts[kind].well) end
    local renderer = self.thumbnailRenderer
    -- One renderer call owns all live bindings, including the waiting preview.
    if self.modal == "waiting" then cards = {self.dialog.Body.Room.Overview.Preview} end
    local viewport = if self.modal == "waiting" then self.dialog.Body else self.scroll
    local ok = pcall(function()
        renderer:update(cards, viewport, self.visible)
        -- Keep allocation/culling/disposal ownership shared, but finish this page's local geometry.
        for _, card in cards do self:containThumbnail(card) end
    end)
    if not ok then
        self.thumbnailFailed = true
        renderer:dispose()
        for _, kind in KINDS do
            self.parts[kind].noMap.Visible = true
            self.parts[kind].noMap.Text = "Terrain preview unavailable"
        end
        clipped(self.content, "Status").Text = "Map previews could not load. Match details remain available."
    end
end

function Page:setVisible(visible: boolean, hold: boolean?)
    if self.destroyed then return end
    self.visible = visible; self.root.Visible = visible
    self.holdThumbnails = not visible and hold == true -- PF031: a tab switch keeps the map previews (updateThumbnails)
    self:setBackgroundInput(visible and not self.layer.Visible)
    if not visible then
        self.dialog.Body.Code:ReleaseFocus()
        self.dialog.Body.CreateOptions.LobbyName:ReleaseFocus()
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then GuiService.SelectedObject = nil end
    end
    self:updateThumbnails()
end

function Page:destroy()
    if self.destroyed then return end
    self.destroyed = true; self.operation += 1
    for _, connection in self.connections do connection:Disconnect() end; table.clear(self.connections)
    self.thumbnailRenderer:dispose()
    for _, row in self.roster do row:Destroy() end; table.clear(self.roster)
    for _, p in self.parts do if p.sweepTween then p.sweepTween:Cancel(); p.sweepTween = nil end end -- PF043 B3
    self.root:SetAttribute("ModalOpen", false)
end

return Page
