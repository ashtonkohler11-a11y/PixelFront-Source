--!strict
-- PF019 B1 (PF - 3): the M9 map picker (Screens.MapPicker, author-pf019-lobby-screens). Shared by
-- Solo, Create Lobby and the waiting room: search, All / Favorites, a Random tile and a Random
-- button, one tile per real map (the available list; 3 today) on the global card kit (hover lift
-- + thumbnail zoom 1.05). The heart keeps a map in Favorites, per player, in the preferences
-- store the legacy Solo screen already used ("map-favorites"); favourites pin to the front.
-- Choosing a map flashes the tile's cobalt ring and returns to the screen that opened it.
-- Content only: tiles are clones of the authored PFTemplates.MapTile.
local Tween=game:GetService("TweenService")
local HttpService=game:GetService("HttpService")
local Model=require(game:GetService("ReplicatedStorage").Shared.LobbySettingsModel)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Picker={};Picker.__index=Picker
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),accent=Color3.fromHex("#3678ff"),heart=Color3.fromHex("#ff5a6e"),line=Color3.fromHex("#3a3a3a"),pill=Color3.fromHex("#1a2238")}

function Picker.new(root: Frame,context: any): any
    -- Map picker v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-mappicker-v2.luau): the polished grid takes over while it is authored
    if root:FindFirstChild("PFPickerV2") then return require(script.Parent.AtlasMapPickerV2).new(root,context) end
    local self: any=setmetatable({root=root,context=context,tiles={},handles={},connections={},tileConnections={},query="",tab="All",
        current=nil,onPick=nil,visible=false,destroyed=false,preview=Preview.new(context.mapSources)},Picker)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local toolbar=root.Toolbar
    for _,tap in Parts.taps((root:FindFirstChild("Header") or root:FindFirstChild("Header",true)).Back,root) do -- r5: Header sits in LeftGroup
        listen(tap,function() self:close(nil) end) end
    listen(toolbar.Search:GetPropertyChangedSignal("Text"),function() self.query=toolbar.Search.Text;self:render() end)
    listen(toolbar.All.Activated,function() self.tab="All";self:render() end)
    listen(toolbar.Favorites.Activated,function() self.tab="Favorites";self:render() end)
    listen(toolbar.Random.Activated,function() self:pickRandom() end)
    listen(root.Grid:GetPropertyChangedSignal("CanvasPosition"),function() self:thumbs() end)
    listen(root.Grid:GetPropertyChangedSignal("AbsoluteSize"),function() self:thumbs() end)
    if context.preferences and context.preferences.subscribe then
        self.preferenceOff=context.preferences:subscribe(function(key) if key=="map-favorites" and self.visible then self:render() end end)
    end
    return self
end
function Picker:favorites(): {string}
    local store=self.context.preferences
    local raw=store and store.storage and store.storage["map-favorites"]
    if type(raw)~="string" then return {} end
    local ok,value=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(value)~="table" then return {} end
    local result={};for _,name in value do if type(name)=="string" then table.insert(result,name) end end;return result
end
function Picker:toggleFavorite(map: string)
    local list=self:favorites();local index=table.find(list,map)
    if index then table.remove(list,index) else table.insert(list,map) end
    local store=self.context.preferences
    if store and store.setCached then store:setCached("map-favorites",HttpService:JSONEncode(list)) end
    self:render()
end
-- Open over `current`; `onPick(map)` receives the choice (nil = closed without a choice).
function Picker:open(current: string?,onPick: (string?)->())
    self.current=current;self.onPick=onPick;self.query="";self.root.Toolbar.Search.Text="";self.tab="All"
    self:render()
end
function Picker:close(map: string?)
    local callback=self.onPick;self.onPick=nil
    if callback then callback(map) end
end
function Picker:pickRandom()
    local maps=Model.maps();if #maps==0 then return end
    self:choose(maps[math.random(1,#maps)].type)
end
function Picker:choose(map: string)
    local tile=self.tiles[map]
    local reduced=self.context.reducedMotion and self.context.reducedMotion()
    if tile and not reduced then
        local ring=tile.PFCardBody.PFCardRing.PFRingStroke
        ring.Transparency=0;Tween:Create(ring,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1}):Play()
        task.delay(.18,function() if not self.destroyed then self:close(map) end end)
    else self:close(map) end
end
local function paintTab(button: any,on: boolean)
    button.BackgroundColor3=if on then C.pill else Color3.fromHex("#262626");button.TextColor3=if on then C.text else C.muted
    local stroke=button:FindFirstChildOfClass("UIStroke");if stroke then stroke.Color=if on then C.accent else C.line;stroke.Thickness=if on then 2 else 1 end
end
function Picker:render()
    if self.destroyed then return end
    for _,c in self.tileConnections do c:Disconnect() end;table.clear(self.tileConnections)
    for _,tile in self.tiles do tile:Destroy() end;table.clear(self.tiles)
    local favorites=self:favorites();local maps=Model.maps()
    local toolbar=self.root.Toolbar
    toolbar.All.Text="All maps · "..#maps;toolbar.Favorites.Text="♥ Favorites · "..#favorites
    paintTab(toolbar.All,self.tab=="All");paintTab(toolbar.Favorites,self.tab=="Favorites")
    local pickerHeader=self.root:FindFirstChild("Header") or self.root:FindFirstChild("Header",true) -- r5: Header sits in LeftGroup
    pickerHeader.TitleBox.Subtitle.Text=#maps.." maps. Tap one to use it; the heart keeps it in Favorites."
    local template=self.context.templates.MapTile
    local order=0
    local function add(key: string,info: any?)
        order+=1
        local tile=template:Clone();tile.Name=key;tile.LayoutOrder=order;tile.Visible=true;tile.Parent=self.root.Grid
        local body=tile.PFCardBody;self.tiles[key]=tile
        if info then
            -- size and nations only on a tile (the region is search text; the check badge and blue name mark the current map)
            tile.TileName.Text=info.name;tile.Details.Text=if info.size then info.size.." · "..tostring(info.nations).." nations" else info.details
            tile.TileName.TextColor3=if info.type==self.current then Color3.fromHex("#9cc2ff") else C.text
            body.Check.Visible=info.type==self.current
            local fav=table.find(favorites,info.type)~=nil
            body.Heart.Text=if fav then "♥" else "♡";body.Heart.TextColor3=if fav then C.heart else C.text
            self.preview:set(body,info.type)
            table.insert(self.tileConnections,tile.Activated:Connect(function() self:choose(info.type) end))
            table.insert(self.tileConnections,body.Heart.Activated:Connect(function()
                local pop=body.Heart:FindFirstChild("PFPop")
                if pop and not (self.context.reducedMotion and self.context.reducedMotion()) then pop.Scale=1.25;Tween:Create(pop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
                self:toggleFavorite(info.type)
            end))
        else
            tile.TileName.Text="Random";tile.Details.Text="Any of the "..#maps.." maps"
            body.Dice.Visible=true;body.Heart.Visible=false;body.Check.Visible=false
            table.insert(self.tileConnections,tile.Activated:Connect(function() self:pickRandom() end))
        end
        if self.context.cardKit then self.context.cardKit:bind(tile,{targets={}}) end
    end
    if self.tab=="All" and Model.matches({name="Random"},self.query) then add("Random",nil) end
    -- favourites pin to the front
    local ordered={}
    for _,info in maps do if table.find(favorites,info.type) then table.insert(ordered,info) end end
    if self.tab=="All" then for _,info in maps do if not table.find(favorites,info.type) then table.insert(ordered,info) end end end
    for _,info in ordered do if Model.matches(info,self.query) then add(info.type,info) end end
    task.defer(function() self:thumbs() end)
end
function Picker:thumbs()
    if self.destroyed then return end
    local wells={}
    for key,tile in self.tiles do if key~="Random" then table.insert(wells,tile.PFCardBody) end end
    self.preview:update(wells,self.root.Grid,self.visible)
end
function Picker:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then task.defer(function() self:thumbs() end) else self.preview:update({},self.root.Grid,false) end
end
function Picker:update(_model: any) end
function Picker:handleEscape(): boolean self:close(nil);return true end
function Picker:focusActive()
    local first=self.tiles[self.current or ""] or self.tiles.Random
    if first then game:GetService("GuiService").SelectedObject=first end
end
function Picker:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;for _,c in self.tileConnections do c:Disconnect() end
    if self.preferenceOff then self.preferenceOff() end
    self.preview:dispose()
end
return Picker
