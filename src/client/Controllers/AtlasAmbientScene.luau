--!strict
-- OF-019A: one shell-owned staged battlefield, never a live match simulation.
-- All GUI/assets are persistent authored content; runtime only binds and animates.
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")
local Ambient = {}
Ambient.__index = Ambient
local WIDTH, HEIGHT, FRAME_STEP = 1920, 980, 1 / 30
local FLIGHT_SECONDS, EVENT_SECONDS = 5.8, 14
local ATTRIBUTE_NAMES = {"ReducedMotion", "Static", "StaticBackground", "AtlasReducedMotion", "AtlasStatic", "MotionEnabled"}
local function child(parent: Instance, name: string): any
    local value = parent:FindFirstChild(name)
    assert(value, "Missing authored Atlas battlefield child: " .. name)
    return value
end
local function path(points: {{number}}): any
    local vertices, lengths, total = {}, {0}, 0
    for index, p in points do
        vertices[index] = Vector2.new(p[1], p[2])
        if index > 1 then total += (vertices[index] - vertices[index - 1]).Magnitude; lengths[index] = total end
    end
    assert(#vertices >= 2 and total > 0, "Invalid Atlas route")
    return {points = vertices, lengths = lengths, length = total}
end
local function along(route: any, distance: number): Vector2
    local d, low, high = math.clamp(distance, 0, route.length), 2, #route.lengths
    while low < high do
        local middle = math.floor((low + high) / 2)
        if route.lengths[middle] < d then low = middle + 1 else high = middle end
    end
    local a, b = route.points[low - 1], route.points[low]
    return a:Lerp(b, (d - route.lengths[low - 1]) / math.max(route.lengths[low] - route.lengths[low - 1], .0001))
end
local function travel(unit: any, clock: number): (number, boolean)
    local duration = unit.path.length / unit.speed
    local half = duration + (if unit.kind == "warship" then 0 else 2.2)
    local cycle = (clock + unit.phase) % (half * 2)
    local reverse = cycle >= half
    local distance = math.min(cycle % half, duration) * unit.speed
    return if reverse then unit.path.length - distance else distance, reverse
end
local function visibleInTree(root: Instance): boolean
    local ancestor: Instance? = root
    while ancestor do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
        if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    return true
end
function Ambient._point(self: any, p: Vector2): Vector2
    return Vector2.new(self.mapOffset + (p.X + .5) * self.mapScale, (p.Y + .5) * self.mapScale)
end
function Ambient._place(self: any, ui: GuiObject, p: Vector2)
    local v = self:_point(p)
    ui.Position = UDim2.fromOffset(math.round(v.X), math.round(v.Y))
end
function Ambient.new(root: Frame, context: any): any
    assert(root:IsA("Frame") and root:GetAttribute("AtlasAuthorVersion") == 2, "Author OF019A shared battlefield before mounting")
    local scene, assets = child(root, "Scene"), child(root, "Assets")
    local data = HttpService:JSONDecode(child(assets, "SceneData").Value)
    local self: any = setmetatable({root = root, context = context or {}, scene = scene, data = data,
        fitScale = child(scene, "FitScale"), terrain = child(scene, "Terrain"), effects = child(scene, "Effects"),
        mapScale = HEIGHT / data.metadata.height, mapOffset = (WIDTH - data.metadata.width * HEIGHT / data.metadata.height) / 2,
        connections = {}, images = {}, labels = {}, boats = {}, trains = {}, buildings = {}, silos = {}, frontiers = {}, fx = {},
        visible = false, paused = false, reduced = false, static = false, destroyed = false, clock = 0, accumulated = 0,
        frameCount = 0, serial = 0, nextEvent = 61, event = nil, heartbeat = nil, lastPublished = -1,
        terrainImage = nil, worldImage = nil, artReady = false,
    }, Ambient)
    root.Visible = false
    local contents, failures = {}, {}
    for _, name in {"Terrain", "WorldAtlas"} do
        local ok, failure = pcall(function()
            local value = child(assets, name)
            local width, height = value:GetAttribute("Width"), value:GetAttribute("Height")
            assert(width > 0 and width <= 1024 and height > 0 and height <= 1024, "Invalid battlefield image size")
            local compressed = EncodingService:Base64Decode(buffer.fromstring(value.Value))
            assert(EncodingService:GetDecompressedBufferSize(compressed, Enum.CompressionAlgorithm.Zstd) == width * height * 4, "Invalid battlefield image bytes")
            local pixels = EncodingService:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
            local image = assert(AssetService:CreateEditableImage({Size = Vector2.new(width, height)}), "Battlefield image memory unavailable: " .. name)
            table.insert(self.images, image)
            image:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
            contents[name] = Content.fromObject(image)
            if name == "Terrain" then self.terrainImage = image else self.worldImage = image end
        end)
        if not ok then table.insert(failures, tostring(failure)) end
    end
    self.artReady = contents.WorldAtlas ~= nil
    for _, ui in scene:GetDescendants() do
        if ui:IsA("ImageLabel") then
            table.insert(self.labels, ui)
            local content = contents[ui:GetAttribute("AtlasImage") or "WorldAtlas"]
            if content then ui.ImageContent = content else ui.Visible = false; ui:SetAttribute("AtlasAssetMissing", true) end
        end
    end
    root:SetAttribute("AtlasAmbientStatus", if #failures == 0 then "Ready" else "ArtUnavailable")
    if #failures > 0 then warn("Atlas battlefield art: " .. table.concat(failures, "; ")) end
    for index, boat in data.boats do
        table.insert(self.boats, {ui = child(child(scene, "Boats"), "Boat" .. index), kind = boat.kind,
            path = path(boat.points), phase = boat.phase + (index - 1) * 5, speed = boat.speed})
    end
    for index, rail in data.rails do
        local units, folder = {}, child(child(scene, "Trains"), "Train" .. index)
        for unit = 0, 6 do table.insert(units, child(folder, "Unit" .. unit)) end
        table.insert(self.trains, {units = units, path = path(rail.points), phase = 12 + (index - 1) * 7, speed = 8 + (index - 1) % 3})
    end
    for index, building in data.buildings do
        table.insert(self.buildings, child(child(scene, "Buildings"), "Building" .. index))
        if building.kind == "MissileSilo" then table.insert(self.silos, {point = Vector2.new(building.p[1], building.p[2]), owner = building.owner}) end
    end
    assert(#self.silos == 2, "Battlefield requires two silo origins")
    for index, frontier in data.frontiers do
        local units = {}
        for part = 1, #frontier.points do table.insert(units, child(child(scene, "Frontier"), "Side" .. index .. "Tile" .. part)) end
        table.insert(self.frontiers, units)
    end
    for _, ui in self.effects:GetChildren() do if ui:IsA("GuiObject") then self.fx[ui.Name] = ui end end
    table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:layout() end))
    table.insert(self.connections, root.Destroying:Connect(function() self:destroy() end))
    local ancestor: Instance? = root
    while ancestor do
        if ancestor:IsA("GuiObject") then
            table.insert(self.connections, ancestor:GetPropertyChangedSignal("Visible"):Connect(function() self:_syncMotion() end))
        elseif ancestor:IsA("ScreenGui") then
            table.insert(self.connections, ancestor:GetPropertyChangedSignal("Enabled"):Connect(function() self:_syncMotion() end))
        end
        ancestor = ancestor.Parent
    end
    local observedRoots = {root}
    if self.context.menuRoot and self.context.menuRoot ~= root then table.insert(observedRoots, self.context.menuRoot) end
    for _, observed in observedRoots do
        for _, name in ATTRIBUTE_NAMES do
            table.insert(self.connections, observed:GetAttributeChangedSignal(name):Connect(function() self:_syncMotion() end))
        end
    end
    self:layout(); self:_draw(false); self:_syncMotion()
    return self
end
function Ambient.layout(self: any, sizeOverride: Vector2?)
    if self.destroyed then return end
    local size = sizeOverride or self.root.AbsoluteSize
    -- Cover the actual terrain image, not the wider reference canvas. The latter
    -- includes centered horizontal padding that otherwise becomes grey gutters.
    local terrainWidth = self.data.metadata.width * self.mapScale
    -- Two screen pixels of bleed per side absorb integer UDim offsets and DPI rounding.
    self.fitScale.Scale = if size.X > 0 and size.Y > 0 then math.max((size.X + 4) / terrainWidth, size.Y / HEIGHT) else 1
end
function Ambient._motionEnabled(self: any): boolean
    if self.reduced or self.static then return false end
    local roots = {self.root}
    if self.context.menuRoot then table.insert(roots, self.context.menuRoot) end
    for _, observed in roots do
        if observed:GetAttribute("ReducedMotion") == true or observed:GetAttribute("Static") == true or observed:GetAttribute("StaticBackground") == true
            or observed:GetAttribute("AtlasReducedMotion") == true or observed:GetAttribute("AtlasStatic") == true or observed:GetAttribute("MotionEnabled") == false then return false end
    end
    if type(self.context.reducedMotion) == "function" then
        local ok, value = pcall(self.context.reducedMotion)
        if not ok or value == true then return false end
    end
    return true
end
function Ambient._syncMotion(self: any)
    if self.destroyed then return end
    local enabled = self:_motionEnabled()
    if not enabled then self.event = nil; self:_draw(false) end
    local run = self.visible and not self.paused and enabled and visibleInTree(self.root)
    if run and not self.heartbeat then
        self.accumulated = 0
        self.heartbeat = RunService.Heartbeat:Connect(function(dt: number)
            if not visibleInTree(self.root) or not self:_motionEnabled() then self:_syncMotion(); return end
            local elapsed = math.clamp(dt, 0, .1)
            self.clock += elapsed; self.accumulated += elapsed
            if self.event and self.clock - self.event.started >= EVENT_SECONDS then self.event = nil end
            if not self.event and self.clock >= self.nextEvent then self:_launch() end
            if self.accumulated >= FRAME_STEP then self.accumulated %= FRAME_STEP; self:_draw(true) end
        end)
    elseif not run and self.heartbeat then
        self.heartbeat:Disconnect(); self.heartbeat = nil; self.accumulated = 0
    end
    self.root:SetAttribute("AtlasMotionRunning", run)
end
function Ambient._launch(self: any)
    local index = self.serial % #self.silos + 1
    self.serial += 1
    local silo, target = self.silos[index], self.data.targets[index]
    self.event = {started = self.clock, source = silo.point, target = Vector2.new(target[1], target[2]), owner = silo.owner, serial = self.serial}
    self.nextEvent = self.clock + 61 + self.serial % 3 * 7
    self.root:SetAttribute("AtlasEventSerial", self.serial)
end
function Ambient._missilePoint(self: any, event: any, t: number): Vector2
    local a, b = event.source, event.target
    local arc = math.min(if event.serial % 2 == 1 then 60 else 190, math.abs(b.X - a.X) * .34)
    return a:Lerp(b, t) + Vector2.new(0, -math.sin(math.pi * t) * arc)
end
function Ambient._sheet(self: any, ui: ImageLabel, name: string, point: Vector2, age: number, frames: number, duration: number, scale: number, alpha: number)
    if not self.artReady or age < 0 or age > duration then ui.Visible = false; return end
    local r = self.data.rects[name]
    local frame = math.min(frames - 1, math.floor(age / duration * frames))
    ui.ImageRectOffset = Vector2.new(r.x + frame * r.width / frames, r.y)
    ui.ImageRectSize = Vector2.new(r.width / frames, r.height)
    ui.Size = UDim2.fromOffset(r.width / frames * self.mapScale * scale, r.height * self.mapScale * scale)
    self:_place(ui, point); ui.ImageTransparency = 1 - math.clamp(alpha, 0, 1); ui.Visible = true
end
function Ambient._draw(self: any, moving: boolean)
    for _, boat in self.boats do
        local distance = travel(boat, self.clock)
        self:_place(boat.ui, along(boat.path, distance)); boat.ui.Visible = self.artReady
    end
    for _, train in self.trains do
        local distance, reverse = travel(train, self.clock)
        for index, ui in train.units do
            local d = distance + (if reverse then 1 else -1) * (index - 1) * 2
            ui.Visible = self.artReady and d >= 0 and d <= train.path.length
            if ui.Visible then self:_place(ui, along(train.path, d)) end
        end
    end
    local cycle, side = self.clock % 26, math.floor(self.clock / 26) % #self.frontiers + 1
    for index, units in self.frontiers do
        local alpha = if moving and index == side and cycle <= 9 then .2 * math.max(0, math.min(1, cycle, 9 - cycle)) else 0
        for part, ui in units do
            ui.Visible = alpha > 0 and part <= math.floor(cycle * 3)
            ui.BackgroundTransparency = 1 - alpha
        end
    end
    for _, ui in self.fx do ui.Visible = false end
    if moving and self.event and self.artReady then self:_drawEvent() end
    if not moving or not self.event then self.root:SetAttribute("AtlasEventPhase", "Idle") end
    local eventActive = self.event ~= nil
    if self.publishedEventActive ~= eventActive then
        self.publishedEventActive = eventActive; self.root:SetAttribute("AtlasEventActive", eventActive)
    end
    self.frameCount += 1
    if self.clock - self.lastPublished >= 1 then
        self.lastPublished = self.clock
        self.root:SetAttribute("AtlasSceneClock", self.clock); self.root:SetAttribute("AtlasFrameCount", self.frameCount)
    end
end
function Ambient._drawEvent(self: any)
    local event = self.event
    local age = self.clock - event.started
    if age < FLIGHT_SECONDS then
        local t = age / FLIGHT_SECONDS
        for index = 1, 15 do
            local ui = self.fx["Trail" .. index]
            self:_place(ui, self:_missilePoint(event, math.max(0, t - index * .005)))
            ui.BackgroundTransparency = 1 - .55 * (1 - index / 16); ui.Visible = true
        end
        local hot = math.floor(((self.clock * 3 + .37) % 1) * 4)
        local r, ui = self.data.rects["atom:" .. hot], self.fx.Missile
        ui.ImageRectOffset = Vector2.new(r.x, r.y); ui.ImageRectSize = Vector2.new(r.width, r.height)
        self:_place(ui, self:_missilePoint(event, t)); ui.Visible = true
        self.root:SetAttribute("AtlasEventPhase", "Flight")
        return
    end
    self.root:SetAttribute("AtlasEventPhase", "Impact")
    age -= FLIGHT_SECONDS
    self:_sheet(self.fx.Explosion, "NukeExplosion", event.target, age, 9, 1.35, .85, .85)
    if age < 3.5 then
        local center, radius = self:_point(event.target), (5 + age * 22) * self.mapScale
        for index = 1, 40 do
            local a, b = (index - 1) / 40 * math.pi * 2, index / 40 * math.pi * 2
            local first = center + Vector2.new(math.cos(a), math.sin(a)) * radius
            local last = center + Vector2.new(math.cos(b), math.sin(b)) * radius
            local delta, ui = last - first, self.fx["Ring" .. index]
            ui.Position = UDim2.fromOffset((first.X + last.X) / 2, (first.Y + last.Y) / 2)
            ui.Size = UDim2.fromOffset(delta.Magnitude + .5, 1.2 * self.mapScale)
            ui.Rotation = math.deg(math.atan2(delta.Y, delta.X)); ui.BackgroundTransparency = 1 - .24 * (1 - age / 3.5); ui.Visible = true
        end
    end
    for index = 0, 3 do
        local p = event.target + Vector2.new(math.cos(index * 2.5) * 9, -math.min(8, age * 1.5) + math.sin(index * 2.5) * 7)
        self:_sheet(self.fx["Smoke" .. (index + 1)], if index % 2 == 1 then "NukeSmokeFire" else "NukeBigSmoke", p, age - index * .21, 5, 6.2, 1.5, .68 * math.max(0, 1 - age / 9))
    end
    self:_sheet(self.fx.Fire, "NukeFire", event.target + Vector2.new(0, 10), age, 6, 4.4, 1.5, .6)
end
function Ambient.setVisible(self: any, visible: boolean)
    if self.destroyed then return end
    self.visible = visible == true; self.root.Visible = self.visible; self:_syncMotion()
end
function Ambient.update(self: any, state: any)
    if self.destroyed then return end
    state = state or {}
    if type(state.paused) == "boolean" then self.paused = state.paused end
    if type(state.reducedMotion) == "boolean" then self.reduced = state.reducedMotion end
    if type(state.staticBackground) == "boolean" then self.static = state.staticBackground
    elseif type(state.static) == "boolean" then self.static = state.static end
    self:_syncMotion()
end
function Ambient.destroy(self: any)
    if self.destroyed then return end
    self.destroyed = true
    if self.heartbeat then self.heartbeat:Disconnect(); self.heartbeat = nil end
    for _, connection in self.connections do connection:Disconnect() end
    table.clear(self.connections)
    for _, image in self.images do image:Destroy() end
    table.clear(self.images); self.terrainImage = nil; self.worldImage = nil
    self.event = nil; self.visible = false
    if self.root and self.root.Parent then pcall(function() self.root.Visible = false; self.root:SetAttribute("AtlasMotionRunning", false) end) end
    for _, label in self.labels do if label and label.Parent then pcall(function() label.Image = "" end) end end
end
return Ambient
