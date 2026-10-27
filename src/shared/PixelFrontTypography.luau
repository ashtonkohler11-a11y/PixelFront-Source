--!strict
-- Ubuntu family inspected with TextService:GetFamilyInfoAsync on 2026-10-04.
-- Actual faces: Light, Regular, Medium, Bold (normal and italic). Use no
-- synthetic Heavy/Black weight; readable body is Medium and emphasis is Bold.
local TextService = game:GetService("TextService")
local Typography = {}
Typography.Family = "rbxasset://fonts/families/Ubuntu.json"
Typography.Font = Enum.Font.Ubuntu -- Legacy measurement/authoring compatibility only.
Typography.Body = Font.new(Typography.Family, Enum.FontWeight.Medium)
Typography.Heading = Font.new(Typography.Family, Enum.FontWeight.Bold)
Typography.Label = Typography.Heading
Typography.Value = Typography.Heading
Typography.Button = Typography.Heading
local faces = {Body=Typography.Body, Heading=Typography.Heading, Label=Typography.Label,
    Value=Typography.Value, Button=Typography.Button}

local function isText(node: Instance): boolean
    return node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")
end
function Typography.role(node: any): string
    local explicit = node:GetAttribute("PixelFrontTextRole")
    if type(explicit)=="string" and faces[explicit] then return explicit end
    if node:IsA("TextButton") then return "Button" end
    local name = string.lower(node.Name)
    if string.find(name,"title",1,true) or string.find(name,"heading",1,true)
        or string.find(name,"header",1,true) then return "Heading" end
    if string.find(name,"value",1,true) or string.find(name,"amount",1,true)
        or string.find(name,"count",1,true) or string.find(name,"price",1,true)
        or string.find(name,"total",1,true) then return "Value" end
    if name=="label" or name=="name" or name=="displayname" or name=="status"
        or name=="players" or name=="countdown"
        or node.FontFace.Weight.Value>=Enum.FontWeight.SemiBold.Value then return "Label" end
    return "Body"
end
function Typography.face(role: string?): Font
    return faces[role or "Body"] or Typography.Body
end
function Typography.apply(node: any, role: string?): boolean
    if not isText(node) or node:GetAttribute("PixelFrontTypographyExclude")==true then return false end
    local selected = role or Typography.role(node)
    node:SetAttribute("PixelFrontTextRole",selected)
    local face = Typography.face(selected)
    if node.FontFace~=face then node.FontFace=face end
    return true
end
function Typography.applyTree(root: Instance): number
    local count = if Typography.apply(root) then 1 else 0
    for _,node in root:GetDescendants() do if Typography.apply(node) then count+=1 end end
    return count
end
-- This yields while Roblox loads the actual weighted face. Callers that must
-- lay out synchronously should cache results and request them in task.spawn.
function Typography.measure(text: string, size: number, width: number, font: Font?): Vector2
    local params=Instance.new("GetTextBoundsParams")
    params.Text=text;params.Size=size;params.Width=math.max(1,width);params.Font=font or Typography.Body
    local ok,result=pcall(function() return TextService:GetTextBoundsAsync(params) end)
    params:Destroy()
    if not ok then error(result) end
    return result
end
-- Covers the authored GUI and all runtime clones, including legacy .Font writes.
-- Per-node listeners disconnect when their text is destroyed; whole GUI teardown
-- also clears them so repeated match/menu lifecycles retain no stale connections.
function Typography.bind(root: Instance): ()->()
    local connections: {[Instance]: {RBXScriptConnection}}={}
    local stopped=false
    local function unwatch(node: Instance)
        local signals=connections[node]
        if signals then
            for _,connection in signals do connection:Disconnect() end
            connections[node]=nil
        end
    end
    local function watch(node: Instance)
        if stopped or connections[node] or not Typography.apply(node) then return end
        local changing=false
        local signals={}
        connections[node]=signals
        table.insert(signals,node:GetPropertyChangedSignal("FontFace"):Connect(function()
            if changing or stopped then return end
            if node~=root and not node:IsDescendantOf(root) then unwatch(node);return end
            changing=true;Typography.apply(node);changing=false
        end))
        table.insert(signals,node.Destroying:Connect(function()
            unwatch(node)
        end))
    end
    watch(root);for _,node in root:GetDescendants() do watch(node) end
    local added=root.DescendantAdded:Connect(watch)
    local removing=root.DescendantRemoving:Connect(function(node)
        task.defer(function()
            if not stopped and not node:IsDescendantOf(root) then unwatch(node) end
        end)
    end)
    local destroying: RBXScriptConnection?
    local function stop()
        if stopped then return end;stopped=true;added:Disconnect();removing:Disconnect()
        if destroying then destroying:Disconnect() end
        for _,signals in connections do for _,connection in signals do connection:Disconnect() end end
        table.clear(connections)
    end
    destroying=root.Destroying:Connect(stop)
    return stop
end
return table.freeze(Typography)
