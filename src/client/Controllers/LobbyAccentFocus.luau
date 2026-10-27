--!strict
-- PF019 (PF - 3, MM 2026-10-06): in the lobby the interface accent (M5 Interface) drives ONLY the
-- keyboard / gamepad focus visuals; selection states keep the fixed cobalt of M1/M2/M3. This binds just
-- the "focus"-role accent tags under the menu (PFAccentStroke / PFAccentBackground = "focus") to a
-- PixelFrontAccent registry, including nodes cloned in later (rows, tiles). Every other accent tag in
-- the lobby keeps its authored colour. The card kit owns its gold selected ring and re-asserts it on
-- subscribe (LobbyCardKit:accentChanged).
local Accent=require(game:GetService("ReplicatedStorage").Shared.PixelFrontAccent)
local Focus={}

-- extraRoots: authored focus visuals that live outside the menu (the gamepad selection ring template in
-- ReplicatedStorage.PFLobbySelection, shared by every lobby button as its SelectionImageObject).
function Focus.bind(root: Instance,preferences: any,extraRoots: {Instance}?): any?
    if type(preferences)~="table" or type(preferences.interfaceAccent)~="function" or type(preferences.subscribe)~="function" then return nil end
    local registry=Accent.new(preferences)
    local releases: {[Instance]: {()->()}}={}
    local function add(node: Instance)
        if releases[node] then return end
        for tag,property in Accent.propertyTags do
            if node:GetAttribute(tag)=="focus" then
                local ok,release=pcall(function() return registry:register(node,property,"focus") end)
                if ok then releases[node]=releases[node] or {};table.insert(releases[node],release) end
            end
        end
    end
    local function remove(node: Instance)
        local list=releases[node];if not list then return end;releases[node]=nil
        for _,release in list do release() end
    end
    for _,node in root:GetDescendants() do add(node) end
    local connections={root.DescendantAdded:Connect(add),root.DescendantRemoving:Connect(remove)}
    for _,extra in extraRoots or {} do add(extra);for _,node in extra:GetDescendants() do add(node) end end
    local handle={}
    function handle.color(): Color3 return registry:color("focus") end
    function handle.subscribe(callback: (any)->()): ()->() return registry:subscribe(callback) end
    function handle.count(): number local n=0;for _ in releases do n+=1 end;return n end
    function handle.destroy()
        for _,connection in connections do connection:Disconnect() end
        table.clear(releases);registry:destroy()
    end
    return handle
end

return table.freeze(Focus)
