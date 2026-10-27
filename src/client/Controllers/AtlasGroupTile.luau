--!strict
-- PF036 group reward (PF - 3, board docs/director/mockups/PF036/04-group-reward.png): join the PixelFront group once for
-- Cobalt (and a title when one is configured). Two authored slots with the same parts (tools/atlas/author-pf036-group.luau):
-- desk = Play Content.PFGroupTile under Solo; strip = Content.PFDailyStrip.PFGroupTile (phones, PF - 1's strip, first).
-- States: join (not in the group: Join opens Roblox's group prompt), claim (in the group: Claim asks the server, which checks
-- membership again), done (+N Cobalt for a few seconds, then the tile goes). Hidden while no group is configured (the
-- profile has no `group`: Catalog.groupReward.groupId 0) or once claimed. Content only: texts, colours, visibility.
local Tile={};Tile.__index=Tile
Tile.DONE_SECONDS=3
Tile.RECHECK=10 -- seconds between membership checks while the tile shows
local C: any=nil -- the colours, built on first paint (the pure state/texts run in plain Luau tests)
local function colours(): any
    C=C or {cobalt=Color3.fromHex("#3678ff"),gold=Color3.fromHex("#ddbf76"),goldHi=Color3.fromHex("#ffd77a"),ink=Color3.fromHex("#ffffff"),
        goldInk=Color3.fromHex("#2a2414"),rim=Color3.fromHex("#3a3a3a"),done=Color3.fromHex("#9fe0b5")}
    return C
end

-- The tile's state for a profile `group` ({claimed, amount, groupId, title}) and a membership answer (nil = not known yet).
function Tile.state(group: any, member: boolean?, doneUntil: number?, now: number): string
    if doneUntil and now < doneUntil then return "done" end
    if type(group) ~= "table" or type(group.groupId) ~= "number" or group.groupId <= 0 or group.claimed == true then return "hidden" end
    if member == nil then return "hidden" end -- no flicker from Join to Claim while the first check runs
    return if member then "claim" else "join"
end
function Tile.texts(group: any, state: string): any
    local amount = tostring(if type(group) == "table" and tonumber(group.amount) then group.amount else 0)
    local reward = amount .. " Cobalt" .. (if type(group) == "table" and group.title then " + a group title" else "")
    if state == "join" then return {title = "Join the group", reward = reward, short = amount, action = "Join"} end
    if state == "claim" then return {title = "You joined the group", reward = reward, short = amount, action = "Claim"} end
    if state == "done" then return {title = "+" .. amount .. " Cobalt", reward = "", action = ""} end
    return {title = "", reward = "", action = ""}
end

-- slots: {desk = Frame?, strip = Frame?}; context: {claim = () -> (), phone = () -> boolean, stripShown = () -> boolean}
function Tile.new(slots: any, context: any): any
    local self: any = setmetatable({slots = slots, context = context, connections = {}, group = nil, member = nil, checkedAt = -math.huge,
        checking = false, doneUntil = nil, destroyed = false, claimedAmount = nil}, Tile)
    for _, slot in {slots.desk, slots.strip} do
        local action = slot and slot:FindFirstChild("Action")
        if action then table.insert(self.connections, action.Activated:Connect(function() self:act() end)) end
    end
    self:paint()
    return self
end
function Tile:check(force: boolean?)
    local group = self.group
    if self.destroyed or self.checking or type(group) ~= "table" or not group.groupId or group.groupId <= 0 or group.claimed then return end
    if not force and os.clock() - self.checkedAt < Tile.RECHECK then return end
    self.checking = true; self.checkedAt = os.clock()
    task.spawn(function()
        local player = game:GetService("Players").LocalPlayer
        local ok, inGroup = pcall(function() return player:IsInGroupAsync(group.groupId) end)
        self.checking = false
        if self.destroyed then return end
        if ok then self.member = inGroup == true end
        self:paint()
    end)
end
function Tile:update(group: any)
    if self.destroyed then return end
    local was = self.group
    -- a claim landing: the profile's group flips to claimed; show the +N for a moment
    if type(was) == "table" and not was.claimed and type(group) == "table" and group.claimed and self.claiming then
        if self.context.reward then -- PF043 (Ashton: "all of them"): the reward drop
            self.context.reward(tonumber(group.amount) or 0)
        else
            self.doneUntil = os.clock() + Tile.DONE_SECONDS; self.claimedAmount = group.amount
            task.delay(Tile.DONE_SECONDS + .05, function() if not self.destroyed then self:paint() end end)
        end
    end
    self.claiming = false
    self.group = group
    self:check(false)
    self:paint()
end
function Tile:act()
    local state = Tile.state(self.group, self.member, self.doneUntil, os.clock())
    if state == "join" then
        local id = self.group.groupId
        task.spawn(function()
            pcall(function() game:GetService("GroupService"):PromptJoinAsync(id) end)
            if not self.destroyed then self:check(true) end
        end)
    elseif state == "claim" and not self.claiming then
        self.claiming = true; self:paint()
        if self.context.claim then self.context.claim() end
        task.delay(8, function() if self.claiming and not self.destroyed then self.claiming = false; self:paint() end end)
    end
end
function Tile:paintSlot(slot: any, shown: boolean, state: string, short: boolean?)
    if not slot then return end
    local C = colours()
    slot.Visible = shown
    if not shown then return end
    local t = Tile.texts(if state == "done" then {amount = self.claimedAmount, title = false} else self.group, state)
    local title = slot:FindFirstChild("Title"); if title then title.Text = t.title; title.TextColor3 = if state == "done" then C.done else C.ink end
    local reward = slot:FindFirstChild("Reward")
    if reward then
        reward.Visible = state ~= "done"
        local amount = reward:FindFirstChild("Amount"); if amount then amount.Text = if short then (t.short or "") else t.reward end -- the phone chip: the number only
    end
    local action = slot:FindFirstChild("Action")
    if action then
        action.Visible = state ~= "done"
        local label = action:FindFirstChild("Label") or action
        label.Text = if self.claiming then "…" else t.action
        local gold = state == "claim"
        action.BackgroundColor3 = if gold then C.goldInk else C.cobalt
        label.TextColor3 = if gold then C.goldHi else C.ink
        local stroke = action:FindFirstChildOfClass("UIStroke"); if stroke then stroke.Color = if gold then C.gold else C.cobalt end
    end
    local rim = slot:FindFirstChildOfClass("UIStroke"); if rim then rim.Color = if state == "claim" then C.gold else C.rim end
end
function Tile:paint()
    if self.destroyed then return end
    local state = Tile.state(self.group, self.member, self.doneUntil, os.clock())
    local on = state ~= "hidden"
    local phone = self.context.phone and self.context.phone() or false
    self:paintSlot(self.slots.desk, on and not phone, state)
    self:paintSlot(self.slots.strip, on and phone, state, true)
end
function Tile:destroy()
    self.destroyed = true
    for _, c in self.connections do c:Disconnect() end
    table.clear(self.connections)
end
return Tile
