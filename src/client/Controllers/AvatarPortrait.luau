--!strict
-- Static account or explicit preset busts inside Studio-authored ViewportFrames.
local Players = game:GetService("Players")
local Outline = require(script.Parent.AvatarPortraitOutline)
local Presets = require(script.Parent.AvatarPortraitPresets)
export type Subject = number | "DefaultBacon"

export type Options = {
    load: ((number) -> Model)?,
    loadPreset: ((string) -> Model)?,
    spawn: ((() -> ()) -> ())?,
    now: (() -> number)?,
    cacheLimit: number?,
    maxConcurrent: number?,
    failureCooldown: number?,
}

type Handle = {
    viewport: ViewportFrame,
    subject: Subject?,
    connections: {RBXScriptConnection},
    visibilityConnections: {RBXScriptConnection},
    entry: Entry?,
    world: WorldModel?,
    camera: Camera?,
    outline: Outline.Handle?,
    shown: boolean,
    ready: boolean,
}
type Entry = {
    subject: Subject,
    state: string,
    template: Model?,
    retryAt: number,
    touched: number,
    waiters: {[Handle]: boolean},
}

local Manager = {}
Manager.__index = Manager
local AvatarPortrait = {}

local function validSubject(value: Subject?): Subject?
    if value==Presets.DefaultBacon then return value end
    return if type(value) == "number" and value > 0 and value < 2^53 and value % 1 == 0 then value else nil
end
function AvatarPortrait.subject(identity: any): Subject?
    if type(identity)~="table"then return nil end
    -- Any explicit preset prevents accidental fallback to a real account.
    return validSubject(if identity.avatarPreset~=nil then identity.avatarPreset else identity.userId)
end

local function disconnect(connections: {RBXScriptConnection})
    for _, connection in connections do connection:Disconnect() end
    table.clear(connections)
end

local function bounds(part: BasePart): (Vector3, Vector3)
    local cf, size = part.CFrame, part.Size
    local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
    if mesh then
        cf *= CFrame.new(mesh.Offset)
        -- Built-in meshes scale relative to their part. Legacy FileMesh raw asset extents are not
        -- exposed here; retain its handle bounds/headroom rather than downloading another asset.
        if mesh:IsA("BlockMesh") or (mesh:IsA("SpecialMesh") and mesh.MeshType ~= Enum.MeshType.FileMesh) then
            size *= Vector3.new(math.abs(mesh.Scale.X), math.abs(mesh.Scale.Y), math.abs(mesh.Scale.Z))
        end
    end
    local half = size * .5
    local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
    local extent = Vector3.new(
        math.abs(right.X)*half.X + math.abs(up.X)*half.Y + math.abs(look.X)*half.Z,
        math.abs(right.Y)*half.X + math.abs(up.Y)*half.Y + math.abs(look.Y)*half.Z,
        math.abs(right.Z)*half.X + math.abs(up.Z)*half.Y + math.abs(look.Z)*half.Z
    )
    return cf.Position - extent, cf.Position + extent
end

local function bodyPart(model: Model, name: string): BasePart?
    local part = model:FindFirstChild(name)
    return if part and part:IsA("BasePart") then part else nil
end

local function settleAccessories(model: Model)
    -- The public avatar API can return accessory handles at their asset-authoring positions.
    -- A parentless model has not necessarily solved its welds, and anchoring it freezes that pose.
    -- Resolve outward from the already-positioned body without a physics frame or Workspace parent.
    local resolved: {[BasePart]: boolean} = {}
    local accessoryParts: {[BasePart]: boolean} = {}
    local joints: {JointInstance} = {}
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            if descendant:FindFirstAncestorWhichIsA("Accoutrement") then
                accessoryParts[descendant] = true
            else
                resolved[descendant] = true
            end
        elseif descendant:IsA("JointInstance") then
            table.insert(joints, descendant)
        end
    end
    for _ = 1, #joints do
        local progressed = false
        for _, joint in joints do
            local part0, part1 = joint.Part0, joint.Part1
            if not part0 or not part1 then continue end
            local transform = if joint:IsA("Motor6D") then joint.Transform else CFrame.new()
            if accessoryParts[part0] and not resolved[part0] and resolved[part1] then
                part0.CFrame = part1.CFrame * joint.C1 * transform:Inverse() * joint.C0:Inverse()
                resolved[part0] = true
                progressed = true
            elseif accessoryParts[part1] and not resolved[part1] and resolved[part0] then
                part1.CFrame = part0.CFrame * joint.C0 * transform * joint.C1:Inverse()
                resolved[part1] = true
                progressed = true
            end
        end
        if not progressed then break end
    end
end

local function prepare(model: Model)
    assert(model:IsA("Model"), "Avatar API did not return a model")
    assert(bodyPart(model, "Head"), "Avatar is missing its head")
    assert(bodyPart(model, "UpperTorso") or bodyPart(model, "Torso"), "Avatar is missing its torso")
    model.Archivable = true
    settleAccessories(model)
    -- Public avatar assets are visual data; executable scripts, tools and autonomous effects are unnecessary.
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("LuaSourceContainer") or descendant:IsA("Tool") or descendant:IsA("Sound")
            or descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam")
            or descendant:IsA("Light") or descendant:IsA("Animator") then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
        elseif descendant:IsA("Humanoid") then
            descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            descendant.AutoRotate = false
        end
    end
    model:PivotTo(CFrame.new())
end

local function frameCamera(camera: Camera, model: Model)
    local head = assert(bodyPart(model, "Head"))
    local torso = assert(bodyPart(model, "UpperTorso") or bodyPart(model, "Torso"))
    local headLow, headHigh = bounds(head)
    local headCenter = (headLow + headHigh) * .5
    local torsoLow, torsoHigh = bounds(torso)
    local headHeight = math.max(headHigh.Y - headLow.Y, .25)
    local headWidth = math.max(headHigh.X - headLow.X, .25)
    local width = math.max(headWidth * 1.24, (torsoHigh.X - torsoLow.X) * 1.16)
    local lowY = headLow.Y - headHeight * .75
    local highY = headHigh.Y + headHeight * .16
    -- Fit ordinary hats/hair around the head. Oversized wings/props must not shrink the face to a speck.
    for _, child in model:GetChildren() do
        if not child:IsA("Accoutrement") then continue end
        local handle = child:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then continue end
        local low, high = bounds(handle)
        local size = high - low
        if size.Magnitude <= math.max(headWidth, headHeight) * 2.4
            and low.Y >= headLow.Y - headHeight * .35
            and high.Y <= headHigh.Y + headHeight * 1.25
            and math.abs((low.X + high.X) * .5 - headCenter.X) <= headWidth * .8 then
            highY = math.max(highY, high.Y + headHeight * .12)
            width = math.max(width, 2 * math.max(math.abs(low.X-headCenter.X), math.abs(high.X-headCenter.X)))
        end
    end
    local height = math.max(highY - lowY, width) * 1.15
    local center = Vector3.new(headCenter.X, (highY + lowY) * .5, headCenter.Z)
    local depth = math.max(headHigh.Z - headLow.Z, torsoHigh.Z - torsoLow.Z)
    local distance = height * .5 / math.tan(math.rad(28) * .5) + depth * .5
    camera.FieldOfView = 28
    camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, -distance), center)
    camera.Focus = CFrame.new(center)
end

local function visible(viewport: ViewportFrame): boolean
    if not viewport.Parent then return false end
    local ancestor: Instance? = viewport
    while ancestor do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
        if ancestor:IsA("LayerCollector") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    return true
end

function Manager._status(self: any, handle: Handle, status: string)
    if self.bindings[handle.viewport] ~= handle then return end
    handle.viewport:SetAttribute("PortraitStatus", status)
    local fallback = handle.viewport:FindFirstChild("PortraitFallback")
    if fallback and fallback:IsA("GuiObject") then fallback.Visible = status ~= "ready" end
end

function Manager._clear(self: any, handle: Handle)
    Outline.clear(handle.outline);handle.outline=nil
    if handle.camera and handle.viewport.CurrentCamera == handle.camera then handle.viewport.CurrentCamera = nil end
    if handle.world then handle.world:Destroy(); handle.world = nil end
    if handle.camera then handle.camera:Destroy(); handle.camera = nil end
    handle.ready = false
end

function Manager._detach(self: any, handle: Handle)
    local entry = handle.entry
    handle.entry = nil
    if not entry then return end
    entry.waiters[handle] = nil
    if entry.state == "queued" and next(entry.waiters) == nil then
        self.entries[entry.subject] = nil
        local index = table.find(self.queue, entry)
        if index then table.remove(self.queue, index) end
    end
end

function Manager._render(self: any, handle: Handle, template: Model)
    if self.destroyed or self.bindings[handle.viewport] ~= handle or not handle.shown then return end
    self:_clear(handle)
    local ok = pcall(function()
        local world = Instance.new("WorldModel")
        world.Name = "AvatarPortraitWorld"
        handle.world = world
        local avatar = template:Clone()
        avatar.Name = "Avatar"
        avatar.Parent = world
        local camera = Instance.new("Camera")
        camera.Name = "AvatarPortraitCamera"
        handle.camera = camera
        frameCamera(camera, avatar)
        world.Parent = handle.viewport
        camera.Parent = handle.viewport
        handle.viewport.CurrentCamera = camera
        handle.outline=Outline.render(handle.viewport,avatar,camera)
    end)
    if not ok then self:_clear(handle) end
    handle.ready = ok
    self:_status(handle, if ok then "ready" else "fallback")
end

function Manager._trim(self: any)
    local completed = 0
    for _, entry: Entry in self.entries do
        if entry.state == "ready" or entry.state == "failed" then completed += 1 end
    end
    while completed > self.cacheLimit do
        local oldest: Entry? = nil
        for _, entry: Entry in self.entries do
            if (entry.state == "ready" or entry.state == "failed") and (not oldest or entry.touched < oldest.touched) then
                oldest = entry
            end
        end
        if not oldest then break end
        if oldest.template then oldest.template:Destroy() end
        self.entries[oldest.subject] = nil
        completed -= 1
    end
end

function Manager._pump(self: any)
    while not self.destroyed and self.active < self.maxConcurrent and #self.queue > 0 do
        local entry: Entry = table.remove(self.queue, 1)
        entry.state = "loading"
        self.active += 1
        self.requests += 1
        self.spawn(function()
            local model: Model? = nil
            local ok = pcall(function()
                model = if type(entry.subject)=="string" then self.loadPreset(entry.subject) else self.load(entry.subject)
                prepare(assert(model))
            end)
            self.active -= 1
            if self.destroyed then
                if model then model:Destroy() end
                return
            end
            if not ok and model then model:Destroy(); model = nil end
            entry.template = model
            entry.state = if ok then "ready" else "failed"
            entry.retryAt = self.now() + self.failureCooldown
            self.clock += 1
            entry.touched = self.clock
            if not ok then self.failures += 1 end
            local waiters = entry.waiters
            entry.waiters = {}
            for handle in waiters do
                if handle.entry ~= entry then continue end
                handle.entry = nil
                if model then self:_render(handle, model) else self:_status(handle, "fallback") end
            end
            self:_trim()
            self:_pump()
        end)
    end
end

function Manager._request(self: any, handle: Handle)
    if not handle.subject or handle.entry or handle.ready or not handle.shown then return end
    local entry: Entry? = self.entries[handle.subject]
    if entry and entry.state == "failed" and self.now() >= entry.retryAt then
        self.entries[handle.subject] = nil
        entry = nil
    end
    self.clock += 1
    if entry then
        entry.touched = self.clock
        if entry.template then
            self.hits += 1
            self:_render(handle, entry.template)
            return
        elseif entry.state == "failed" then
            self:_status(handle, "fallback")
            return
        end
    else
        entry = {subject=handle.subject, state="queued", template=nil, retryAt=0, touched=self.clock, waiters={}}
        self.entries[handle.subject] = entry
        table.insert(self.queue, entry)
    end
    handle.entry = entry
    entry.waiters[handle] = true
    self:_status(handle, "loading")
    self:_pump()
end

function Manager._visibility(self: any, handle: Handle)
    if self.bindings[handle.viewport] ~= handle then return end
    local shown = visible(handle.viewport)
    if shown == handle.shown then return end
    handle.shown = shown
    if shown then
        self:_request(handle)
    else
        self:_detach(handle)
        self:_clear(handle)
        self:_status(handle, "fallback")
    end
end

function Manager._watchVisibility(self: any, handle: Handle)
    if self.destroyed or self.bindings[handle.viewport] ~= handle then return end
    disconnect(handle.visibilityConnections)
    local ancestor: Instance? = handle.viewport
    while ancestor do
        local property = if ancestor:IsA("GuiObject") then "Visible" elseif ancestor:IsA("LayerCollector") then "Enabled" else nil
        if property then
            table.insert(handle.visibilityConnections, ancestor:GetPropertyChangedSignal(property):Connect(function()
                self:_visibility(handle)
            end))
        end
        ancestor = ancestor.Parent
    end
    self:_visibility(handle)
end

function Manager.bind(self: any, viewport: ViewportFrame, subject: Subject?)
    assert(viewport:IsA("ViewportFrame"), "Bind an authored ViewportFrame")
    if self.destroyed then return end
    local id = validSubject(subject)
    local existing: Handle? = self.bindings[viewport]
    if existing and existing.subject == id then
        self:_request(existing) -- A failed identity may retry after cooldown, never on every refresh.
        return
    end
    self:unbind(viewport)
    local handle: Handle = {viewport=viewport, subject=id, connections={}, visibilityConnections={}, entry=nil,
        world=nil, camera=nil, outline=nil, shown=false, ready=false}
    self.bindings[viewport] = handle
    viewport.Ambient = Color3.fromRGB(180, 191, 211)
    viewport.LightColor = Color3.fromRGB(255, 242, 224)
    viewport.LightDirection = Vector3.new(-1, -.7, -1)
    -- Transparent edges use a black compositing matte, independently of the outer cosmetic frame.
    viewport.BackgroundColor3 = Color3.new(0,0,0)
    viewport:SetAttribute("PortraitUserId",if type(id)=="number"then id else nil)
    viewport:SetAttribute("PortraitPreset",if type(id)=="string"then id else nil)
    self:_status(handle, "fallback")
    table.insert(handle.connections, viewport.Destroying:Connect(function() self:unbind(viewport) end))
    table.insert(handle.connections, viewport.AncestryChanged:Connect(function() self:_watchVisibility(handle) end))
    self:_watchVisibility(handle)
end

function Manager.unbind(self: any, viewport: ViewportFrame)
    local handle: Handle? = self.bindings[viewport]
    if not handle then return end
    self:_detach(handle)
    self:_clear(handle)
    self:_status(handle, "fallback")
    self.bindings[viewport] = nil
    disconnect(handle.connections)
    disconnect(handle.visibilityConnections)
end

function Manager.stats(self: any): {[string]: number}
    local cached, bound, rendered = 0, 0, 0
    for _, entry: Entry in self.entries do
        if entry.state == "ready" or entry.state == "failed" then cached += 1 end
    end
    for _, handle: Handle in self.bindings do
        bound += 1
        if handle.ready then rendered += 1 end
    end
    return {requests=self.requests, cacheHits=self.hits, failures=self.failures, active=self.active,
        queued=#self.queue, cached=cached, bound=bound, rendered=rendered}
end

function Manager.destroy(self: any)
    if self.destroyed then return end
    self.destroyed = true
    for viewport in self.bindings do self:unbind(viewport) end
    for _, entry: Entry in self.entries do
        table.clear(entry.waiters)
        if entry.template then entry.template:Destroy() end
    end
    table.clear(self.entries)
    table.clear(self.queue)
end

-- The injectable instance is for isolated QA; normal controllers share the singleton below.
function AvatarPortrait.new(options: Options?): any
    local config = options or {}
    return setmetatable({
        load=config.load or function(userId: number): Model return Players:CreateHumanoidModelFromUserIdAsync(userId) end,
        loadPreset=config.loadPreset or Presets.create,
        spawn=config.spawn or task.spawn,
        now=config.now or os.clock,
        cacheLimit=math.clamp(math.floor(config.cacheLimit or 24), 1, 64),
        maxConcurrent=math.clamp(math.floor(config.maxConcurrent or 3), 1, 6),
        failureCooldown=math.max(config.failureCooldown or 30, 1),
        entries={}, queue={}, bindings={}, active=0, requests=0, hits=0, failures=0, clock=0, destroyed=false,
    }, Manager)
end

local shared = AvatarPortrait.new()
function AvatarPortrait.bind(viewport: ViewportFrame, subject: Subject?) shared:bind(viewport, subject) end
function AvatarPortrait.unbind(viewport: ViewportFrame) shared:unbind(viewport) end
function AvatarPortrait.stats(): {[string]: number} return shared:stats() end

return AvatarPortrait
