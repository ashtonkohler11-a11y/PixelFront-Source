--!strict
-- PF - 3 Map picker v2 (UI review 2026-10-26; Ashton: the old format, polished: "Good, build it"). Fills
-- Screens.MapPicker.PFPickerV2 (tools/atlas/author-pf3-mappicker-v2.luau): search, All / Favorites with counts, the Random map key
-- and a scrolling grid (5 a row): Random first, then favourites, then the rest; each card the map's art on its stage, name,
-- size · nations, your wins / played and a heart; the chosen map gold-rimmed with a Chosen tag. AtlasMapPicker hands over while
-- the layer exists; same API (open / close / setVisible / update / handleEscape / focusActive / destroy) and the same
-- "map-favorites" preference. Pure helpers V2.order / V2.place / V2.record are tested by tools/test-pf3-mappicker-v2.luau.
local V2={};V2.__index=V2
local Model: any,Preview: any=nil,nil
local C: any,STAGE: any=nil,nil -- built in new() (plain Luau has no Color3)
local function colours()
    local h=Color3.fromHex
    C={text=h("#eef1f6"),dim=h("#9aa3b2"),chip=h("#0d1017"),chipOn=h("#1d2b4a"),blue=h("#4f86ff"),chipRim=h("#2b3240"),heart=h("#ff5d7a"),
        chosen=h("#ffe3a0")}
    STAGE={UnitedStates=h("#1f4166"),Africa=h("#4a3618"),QingChina=h("#1f4a33")}
end
-- inset: room round the cards so a hovered card's scale and rim never clip at the grid's edge
V2.GRID={w=1812,h=852,cardW=344,cardH=376,gap=18,columns=5,inset=10,pad=20}

-- The cards in order: "Random" (All tab only, if the query matches it), then favourites, then (All tab) the rest; each kept
-- only if it matches the query. maps = Model.maps(); matches(info, query) = Model.matches.
function V2.order(maps: {any},favorites: {string},tab: string,query: string,matches: (any,string)->boolean): {any}
    local out={}
    if tab=="All" and matches({name="Random"},query) then table.insert(out,{key="Random"}) end
    for _,info in maps do if table.find(favorites,info.type) and matches(info,query) then table.insert(out,{key=info.type,info=info,favorite=true}) end end
    if tab=="All" then
        for _,info in maps do if not table.find(favorites,info.type) and matches(info,query) then table.insert(out,{key=info.type,info=info,favorite=false}) end end
    end
    return out
end
-- Where card i (1-based) of n sits, in Scale of the grid's canvas (as Join v2): the canvas height in view heights + spots.
function V2.place(n: number,grid: any): (number,{any})
    local cols=grid.columns
    local rows=math.max(1,math.ceil(n/cols))
    local inset=grid.inset or 0
    local contentH=inset+rows*grid.cardH+(rows-1)*grid.gap+grid.pad
    local canvasH=math.max(grid.h,contentH)
    local out={}
    for i=1,n do
        local col,row=(i-1)%cols,(i-1)//cols
        table.insert(out,{x=(inset+col*(grid.cardW+grid.gap))/grid.w,y=(inset+row*(grid.cardH+grid.gap))/canvasH,w=grid.cardW/grid.w,h=grid.cardH/canvasH})
    end
    return canvasH/grid.h,out
end
-- The grid as wide as it really is (UI-REVIEW rule 5a): a phone wider than 16:9 widens the grid but not its height, so it
-- takes as many columns as fit best and the cards keep their shape (a few % smaller or larger). sizeX / sizeY = the grid's
-- AbsoluteSize; on a 16:9 desk it returns the design grid unchanged.
function V2.fit(grid: any,sizeX: number,sizeY: number): any
    local k=if sizeX>0 and sizeY>0 then (sizeX/sizeY)/(grid.w/grid.h) else 1
    local w=grid.w*k;local inset=grid.inset or 0
    local cols=math.max(1,math.floor((w-2*inset+grid.gap)/(grid.cardW+grid.gap)+.5))
    local cardW=(w-2*inset-(cols-1)*grid.gap)/cols
    return {w=w,h=grid.h,cardW=cardW,cardH=grid.cardH*cardW/grid.cardW,gap=grid.gap,columns=cols,inset=inset,pad=grid.pad}
end
-- Your record on a map from the stats view (AtlasStatsModel.view: maps = {id, name, matches, wins}); 0 / 0 when unknown.
function V2.record(view: any,info: any): (number,number)
    for _,m in (type(view)=="table" and view.maps) or {} do
        if m.id==info.type or m.name==info.name then return tonumber(m.wins) or 0,tonumber(m.matches) or 0 end
    end
    return 0,0
end

local function find(root: Instance,path: string): any
    local node: any=root
    for part in string.gmatch(path,"[^.]+") do node=node and node:FindFirstChild(part) end
    return node
end
local function copy(label: any,value: string) if label and label.Text~=value then label.Text=value end end

function V2.new(root: Frame,context: any): any
    Model=Model or require(game:GetService("ReplicatedStorage").Shared.LobbySettingsModel);Preview=Preview or require(script.Parent.LobbyMapPreview)
    if not C then colours() end
    local layer=root:WaitForChild("PFPickerV2")
    local canvas=layer:WaitForChild("Canvas")
    local self: any=setmetatable({root=root,layer=layer,canvas=canvas,context=context,connections={},cards={},cardConnections={},
        query="",tab="All",current=nil,onPick=nil,visible=false,destroyed=false,preview=Preview.new(context.mapSources)},V2)
    self.grid=canvas.Grid;self.bar=canvas.Toolbar;self.input=self.bar.Search.Input
    for _,n in root:GetChildren() do if n:IsA("GuiObject") and n~=layer and n.Name~="PFScrim" then n.Visible=false end end
    layer.Visible=true
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    local back=find(layer,"Top.Back")
    listen(back.Activated,function() self:close(nil) end)
    local hit=back:FindFirstChild("PFHit");if hit then listen(hit.Activated,function() self:close(nil) end) end
    local Line=require(script.Parent.TopbarLine)
    Line.keepRight(layer.Top,self.connections);Line.clearBelow(canvas,self.connections)
    if Line.scaleTitle then Line.scaleTitle(layer.Top:FindFirstChild("Title"),self.connections) end -- R1: the title scales like desk
    listen(self.input:GetPropertyChangedSignal("Text"),function() self.query=self.input.Text;self:render() end)
    listen(self.bar.All.Activated,function() self.tab="All";self:render() end)
    listen(self.bar.Favorites.Activated,function() self.tab="Favorites";self:render() end)
    listen(self.bar.Random.Activated,function() self:pickRandom() end)
    listen(self.grid:GetPropertyChangedSignal("CanvasPosition"),function() self:thumbs() end)
    listen(self.grid:GetPropertyChangedSignal("AbsoluteSize"),function() self:layout() end) -- the column count follows the width
    if context.preferences and context.preferences.subscribe then
        self.preferenceOff=context.preferences:subscribe(function(k) if k=="map-favorites" and self.visible then self:render() end end)
    end
    return self
end
function V2:favorites(): {string}
    local store=self.context.preferences
    local raw=store and store.storage and store.storage["map-favorites"]
    if type(raw)~="string" then return {} end
    local ok,value=pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
    if not ok or type(value)~="table" then return {} end
    local out={};for _,name in value do if type(name)=="string" then table.insert(out,name) end end;return out
end
function V2:toggleFavorite(map: string)
    local list=self:favorites();local index=table.find(list,map)
    if index then table.remove(list,index) else table.insert(list,map) end
    local store=self.context.preferences
    if store and store.setCached then store:setCached("map-favorites",game:GetService("HttpService"):JSONEncode(list)) end
    self:render()
end
function V2:open(current: string?,onPick: (string?)->())
    self.current=current;self.onPick=onPick;self.query="";self.input.Text="";self.tab="All";self.grid.CanvasPosition=Vector2.zero
    self:render()
end
function V2:close(map: string?)
    local callback=self.onPick;self.onPick=nil
    if callback then callback(map) end
end
function V2:pickRandom()
    local maps=Model.maps();if #maps==0 then return end
    self:choose(maps[math.random(1,#maps)].type)
end
function V2:choose(map: string)
    local card=self.cards[map]
    local reduced=self.context.reducedMotion and self.context.reducedMotion()
    if card and not reduced then
        local rim=card.ChosenRim;rim.Visible=true
        local stroke=rim:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Transparency=0;game:GetService("TweenService"):Create(stroke,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=.2}):Play() end
        task.delay(.18,function() if not self.destroyed then self:close(map) end end)
    else self:close(map) end
end
local function paintChip(chip: any,on: boolean,words: string,count: number,heart: boolean)
    chip.BackgroundColor3=if on then C.chipOn else C.chip;chip.TextColor3=if on then C.text else C.dim
    local rim=chip:FindFirstChild("Rim");if rim then rim.Color=if on then C.blue else C.chipRim;rim.Thickness=if on then 2 else 1.5 end
    local tint=if on then "#9cc2ff" else "#7f8a9c"
    copy(chip,(if heart then '<font color="#ff5d7a">♥</font> ' else "")..words..' <font color="'..tint..'">'..count.."</font>")
end
function V2:fill(card: any,entry: any,stats: any)
    local info=entry.info
    copy(card.Info.MapName,info.name)
    card.Info.MapName.TextColor3=if info.type==self.current then C.chosen else C.text
    copy(card.Info.Details,if info.size then info.size.." · "..tostring(info.nations).." nations" else (info.details or ""))
    local wins,played=V2.record(stats,info)
    copy(card.Info.Record,'<font color="#ffd36a">'..wins..'</font><font color="#8d97a6"> wins</font>   '..played..'<font color="#8d97a6"> played</font>')
    local chosen=info.type==self.current
    card.Art.Chosen.Visible=chosen;card.ChosenRim.Visible=chosen
    local stage=STAGE[info.type];if stage then card.Art.BackgroundColor3=stage end
    card.Art.Heart.Text=if entry.favorite then "♥" else "♡";card.Art.Heart.TextColor3=if entry.favorite then C.heart else C.text
    self.preview:set(card.Art.Well,info.type)
end
function V2:render()
    if self.destroyed then return end
    for _,c in self.cardConnections do c:Disconnect() end;table.clear(self.cardConnections)
    for _,card in self.cards do card:Destroy() end;table.clear(self.cards)
    local favorites=self:favorites();local maps=Model.maps()
    paintChip(self.bar.All,self.tab=="All","All maps",#maps,false)
    paintChip(self.bar.Favorites,self.tab=="Favorites","Favorites",#favorites,true)
    local stats=if self.context.getStats then self.context.getStats() else nil
    local templates=self.layer.Templates
    local entries=V2.order(maps,favorites,self.tab,self.query,Model.matches)
    for index,entry in entries do
        local card=(if entry.info then templates.Card else templates.Random):Clone()
        card.Name=entry.key;card.LayoutOrder=index;card.Visible=true;card.Parent=self.grid
        self.cards[entry.key]=card
        if entry.info then
            local map=entry.info.type
            self:fill(card,entry,stats)
            table.insert(self.cardConnections,card.Activated:Connect(function() self:choose(map) end))
            table.insert(self.cardConnections,card.Art.Heart.Activated:Connect(function()
                local pop=card.Art.Heart:FindFirstChild("PFPop")
                if pop and not (self.context.reducedMotion and self.context.reducedMotion()) then
                    pop.Scale=1.25;game:GetService("TweenService"):Create(pop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
                end
                self:toggleFavorite(map)
            end))
        else
            copy(card.Info.MapName,"Random");copy(card.Info.Details,"Any of the "..#maps.." maps")
            table.insert(self.cardConnections,card.Activated:Connect(function() self:pickRandom() end))
        end
        -- hover: a small lift from the card's centre (AnchorPoint .5,.5; the grid's inset keeps it unclipped)
        local zoom=card:FindFirstChild("PFCardZoom")
        if zoom then
            local Tween=game:GetService("TweenService")
            local function to(s: number) if not (self.context.reducedMotion and self.context.reducedMotion()) then Tween:Create(zoom,TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=s}):Play() end end
            table.insert(self.cardConnections,card.MouseEnter:Connect(function() to(1.03) end))
            table.insert(self.cardConnections,card.MouseLeave:Connect(function() to(1) end))
            table.insert(self.cardConnections,card.SelectionGained:Connect(function() to(1.03) end))
            table.insert(self.cardConnections,card.SelectionLost:Connect(function() to(1) end))
        end
    end
    local empty=self.canvas.Empty
    empty.Visible=#entries==0
    copy(empty,if self.tab=="Favorites" and #favorites==0 then "Tap a heart to keep a map here" else "No maps match your search")
    self:layout()
end
function V2:layout()
    if self.destroyed then return end
    local list={};for _,card in self.cards do table.insert(list,card) end
    table.sort(list,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
    local size=self.grid.AbsoluteSize
    local scale,spots=V2.place(#list,V2.fit(V2.GRID,size.X,size.Y))
    -- CanvasSize's Scale reads against the ScrollingFrame's PARENT (the canvas), not the grid: convert, less the scrollbar
    local gs=self.grid.Size
    self.grid.CanvasSize=UDim2.new(gs.X.Scale,-self.grid.ScrollBarThickness,gs.Y.Scale*scale,0)
    self.grid.ScrollBarImageTransparency=if scale>1.001 then .35 else 1 -- the bar shows only when there is more to scroll
    for i,card in list do
        local s=spots[i]
        card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(s.x+s.w/2,s.y+s.h/2);card.Size=UDim2.fromScale(s.w,s.h)
    end
    task.defer(function() self:thumbs() end)
end
function V2:thumbs()
    if self.destroyed then return end
    local wells={};for key,card in self.cards do if key~="Random" then table.insert(wells,card.Art.Well) end end
    self.preview:update(wells,self.grid,self.visible)
end
function V2:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then task.defer(function() self:thumbs() end) else self.input:ReleaseFocus();self.preview:update({},self.grid,false) end
end
function V2:update(_model: any) end
function V2:handleEscape(): boolean
    if self.input:IsFocused() then self.input:ReleaseFocus();return true end
    self:close(nil);return true
end
function V2:focusActive()
    local first=self.cards[self.current or ""] or self.cards.Random
    if first then game:GetService("GuiService").SelectedObject=first end
end
function V2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;for _,c in self.cardConnections do c:Disconnect() end
    if self.preferenceOff then self.preferenceOff() end
    self.preview:dispose()
end
return V2
