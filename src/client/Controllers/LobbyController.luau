--!strict
-- Authored Solo UI controller. Exact pinned configuration contracts live in Shared.
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Settings=require(Shared.OpenFrontLobbySettings)
local Availability=require(Shared.OpenFrontMatchAvailability)
local Picker=require(Shared.OpenFrontMapPickerData)
local Text=require(script.Parent.LobbySettingsPresentation)
local Theme=require(Shared.Theme)
local Icons=require(script.Parent.ReferenceIcons)
local Thumbnails=require(script.Parent.LobbyThumbnails)
local Lobby={}
local Methods={};Methods.__index=Methods
local function listen(self: any,signal: RBXScriptSignal,callback: (...any)->()) table.insert(self.connections,signal:Connect(callback)) end
local function selected(button: TextButton,value: boolean)
    button:SetAttribute("Selected",value);button.BackgroundColor3=if value then Theme.CommandRaised else Theme.PanelRaised
    button.BackgroundTransparency=0;button.Border.Color=if value then Theme.Accent else Theme.Border;button.Border.Transparency=if value then 0 else .5
    button.TextColor3=if value then Theme.Text else Theme.MutedText
end
local function grid(items: {GuiObject},width: number,columns: number,height: number,gap: number): number
    local cell=(width-(columns-1)*gap)/columns
    for index,item in items do item.Position=UDim2.fromOffset(((index-1)%columns)*(cell+gap),math.floor((index-1)/columns)*(height+gap));item.Size=UDim2.fromOffset(cell,height) end
    return if #items==0 then 0 else math.ceil(#items/columns)*(height+gap)-gap
end
function Lobby.new(gui: ScreenGui,callbacks: any): any
    local root=gui:WaitForChild("Background")
    local ui=root:WaitForChild("Lobby") :: Frame
    local catalog=callbacks.catalog or Availability.maps
    local self=setmetatable({ui=ui,root=root,body=ui.Body,scroll=ui.Body.Scroll,sections=ui.Body.Scroll.Sections,
        callbacks=callbacks,catalog=catalog,byType={},byId={},connections={},cards={},activeCards={},options=Settings.defaultOptions(),
        expanded={},activeTab="Featured",search="",starting=false,attempt=0,overlayAttempt=0,thumbnails=Thumbnails.new(),destroyed=false},Methods)
    for _,entry in catalog do self.byType[entry.type]=entry;self.byId[entry.id]=entry end
    self.options=Settings.availableOptions()
    for _,heading in {self.sections.Map.Heading,self.sections.Difficulty.Heading,self.sections.Mode.Heading,self.sections.Options.Heading,self.sections.Units.Heading} do Icons.bind(heading.Badge.Icon,heading.Badge.Icon:GetAttribute("SourceAsset")) end
    for _,child in self.sections.Difficulty.Cards:GetChildren() do if child:IsA("TextButton") then for _,icon in child.Glyphs:GetChildren() do if icon:IsA("ImageLabel") then Icons.bind(icon,icon:GetAttribute("SourceAsset")) end end end end
    for _,group in self.sections.Map.Groups:GetChildren() do
        if not group:IsA("Frame") or not group:FindFirstChild("Cards") then continue end
        if string.sub(group.Name,1,9)=="Category_" then
            local category=string.sub(group.Name,10);listen(self,group.Heading.Activated,function() self.expanded[category]=not self.expanded[category];self:refresh() end)
        end
        for _,card in group.Cards:GetChildren() do
            if not card:IsA("TextButton") then continue end
            table.insert(self.cards,card)
            listen(self,card.Activated,function()
                if self.starting then return end
                if card.Name=="Random" then self.options.useRandomMap=true;self:selectMap(catalog[math.random(1,#catalog)].type,true)
                else self:selectMap(card:GetAttribute("GameMap"),false) end
            end)
            listen(self,card.Favorite.Activated,function() self:toggleFavorite(card:GetAttribute("GameMap")) end)
            listen(self,card.MouseEnter,function() for _,part in card.Thumbnail:GetChildren() do if part:IsA("ImageLabel") then part.ImageTransparency=0 end end end)
            listen(self,card.MouseLeave,function() for _,part in card.Thumbnail:GetChildren() do if part:IsA("ImageLabel") then part.ImageTransparency=if card:GetAttribute("Selected") then 0 else .2 end end end)
        end
    end
    listen(self,self.body.Footer.Start.Activated,function() self:start() end)
    listen(self,self.body.Header.Back.Activated,function() self:close() end)
    listen(self,self.ui.Backdrop.Activated,function() self:close() end)
    listen(self,self.sections.Map.Heading.Search:GetPropertyChangedSignal("Text"),function() self.search=self.sections.Map.Heading.Search.Text;self:refresh() end)
    for _,name in {"Featured","All","Favorites"} do listen(self,self.sections.Map.Tabs[name].Activated,function() self.activeTab=name;self:refresh() end) end
    listen(self,self.sections.Map.ExpandAll.Activated,function()
        local any=false;for _,value in self.expanded do if value then any=true end end
        for _,category in Picker.mapCategoryOrder do if category~="featured" then self.expanded[category]=not any end end;self:refresh()
    end)
    for _,name in Settings.Difficulties do listen(self,self.sections.Difficulty.Cards[name].Activated,function() if self.options.nations~=0 then self.options.selectedDifficulty=name;self:refresh() end end) end
    for _,name in {"FFA","Team"} do listen(self,self.sections.Mode.Cards[name].Activated,function() self.options.gameMode=self.sections.Mode.Cards[name]:GetAttribute("GameMode");self:refresh() end) end
    for index in Settings.TeamOptions do local b=self.sections.Mode.Teams.Cards["Option"..index];listen(self,b.Activated,function() self.options.teamCount=b:GetAttribute("TeamCount");self:refresh() end) end
    local optionCards=self.sections.Options.Cards
    for _,key in Settings.ToggleOptions do listen(self,optionCards[key].Activated,function() if key=="compactMap"then return end;Settings.setToggle(self.options,key,not self.options[key]);self:refresh() end) end
    listen(self,optionCards.ClockSpeed.Activated,function() optionCards.ClockSpeed.ClockChoices.Visible=not optionCards.ClockSpeed.ClockChoices.Visible end)
    for _,value in Settings.ClockSpeeds do listen(self,optionCards.ClockSpeed.ClockChoices[value].Activated,function() self.options.doomsdayClockSpeed=value;optionCards.ClockSpeed.ClockChoices.Visible=false;self:refresh() end) end
    for _,spec in Settings.InputOptions do
        local c=optionCards[spec.key]
        listen(self,c.Activated,function() Settings.setToggle(self.options,spec.key,not self.options[spec.key]);self:refresh();if self.options[spec.key] then c.Value:CaptureFocus();c.Value.SelectionStart=1;c.Value.CursorPosition=#c.Value.Text+1 end end)
        local function input()
            local value=Settings.parseInput(spec.valueKey,c.Value.Text)
            if value~=nil or spec.key=="maxTimer" or spec.key=="goldMultiplier" or spec.key=="startingGold" then self.options[spec.valueKey]=value end
            if value==nil and (spec.key=="goldMultiplier" or spec.key=="startingGold") then c.Value.Text="" end
        end
        if spec.integer then listen(self,c.Value:GetPropertyChangedSignal("Text"),function() local stripped=string.gsub(c.Value.Text,"[eE%+%-]","");if c.Value.Text~=stripped then c.Value.Text=stripped end;input() end)
        else listen(self,c.Value.FocusLost,input) end
    end
    for _,name in {"Bots","Nations"} do
        local c=optionCards[name];local key=if name=="Bots" then "bots" else "nations"
        listen(self,c.Value.FocusLost,function() local value=tonumber(c.Value.Text) or 0;self.options[key]=math.floor(math.clamp(value,0,if key=="bots"then Availability.MaxTribes else Availability.MaxNations));self:refresh() end)
        listen(self,c.Track.Input.InputBegan,function(input: InputObject)
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            self.drag={kind=key,track=c.Track,input=input};self:updateSlider(Vector2.new(input.Position.X,input.Position.Y))
        end)
    end
    for index,unit in Settings.UnitOptions do local c=self.sections.Units.Cards["Unit"..index];listen(self,c.Activated,function() self.options.disabledUnits=Settings.updatedDisabledUnits(self.options.disabledUnits,unit,not table.find(self.options.disabledUnits,unit));self:refresh() end) end
    listen(self,UserInputService.InputChanged,function(input: InputObject) if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseMovement) then self:updateSlider(Vector2.new(input.Position.X,input.Position.Y)) end end)
    listen(self,UserInputService.InputEnded,function(input: InputObject) if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then self.drag=nil end end)
    listen(self,root.LobbyAlert.Body.Close.Activated,function() self:dismissAlert() end)
    listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function() self:refresh() end)
    listen(self,self.scroll:GetPropertyChangedSignal("CanvasPosition"),function() self:refreshThumbnails() end)
    if callbacks.preferences then self.preferenceOff=callbacks.preferences:subscribe(function(key) if key=="map-favorites" then self:refresh() end end) end
    self:holdCover()
    self:refresh();return self
end
function Methods:favorites(): {string}
    local raw=self.callbacks.preferences and self.callbacks.preferences.storage["map-favorites"]
    if not raw then return {} end
    local ok,value=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(value)~="table" or not string.match(raw,"^%s*%[") then return {} end
    local result={};for _,name in value do if type(name)=="string" and self.byType[name] then table.insert(result,name) end end;return result
end
function Methods:toggleFavorite(gameMap: string)
    local favorites=self:favorites();local index=table.find(favorites,gameMap)
    if index then table.remove(favorites,index) else table.insert(favorites,gameMap) end
    if self.callbacks.preferences then self.callbacks.preferences:setCached("map-favorites",HttpService:JSONEncode(favorites)) end
    self:refresh()
end
function Methods:selectMap(gameMap: string,random: boolean?)
    local entry=assert(self.byType[gameMap],"Unknown official map")
    self.options.selectedMap=gameMap;self.options.useRandomMap=random==true
    self.options.defaultNationCount=entry.defaultNationCount
    self.options.nations=Availability.defaultNations(gameMap)
    self:refresh()
end
function Methods:updateSlider(position: Vector2)
    local drag=self.drag;if not drag then return end
    self.options[drag.kind]=math.floor(math.clamp((position.X-drag.track.AbsolutePosition.X)/math.max(1,drag.track.AbsoluteSize.X),0,1)*(if drag.kind=="bots"then Availability.MaxTribes else Availability.MaxNations)+.5);self:refresh()
end
function Methods:refreshThumbnails()
    self.thumbnails:update(self.activeCards,self.scroll,self.ui.Visible)
end
function Methods:refresh()
    if self.destroyed then return end
    Availability.options(self.options)
    local screen=(self.root :: Frame).AbsoluteSize;local desktop=screen.X>=1024
    self.body.Size=if desktop then UDim2.fromOffset(math.min(900,screen.X*.9),math.max(180,screen.Y-64)) else UDim2.fromScale(1,1)
    local width=math.max(120,(if desktop then math.min(900,screen.X*.9) else screen.X)-56)
    local columns=if screen.X>=768 then 3 else 2
    local favorite=self:favorites();local search=string.lower(string.match(self.search,"^%s*(.-)%s*$") or "")
    local searching=search~="";self.sections.Map.Tabs.Visible=not searching;self.sections.Map.ExpandAll.Visible=not searching and self.activeTab=="All"
    self.sections.Map.Tabs.Size=UDim2.new(1,if self.activeTab=="All" then -120 else 0,0,42)
    self.sections.Map.ExpandAll.Position=UDim2.new(1,-112,0,64)
    local anyExpanded=false;for _,value in self.expanded do if value then anyExpanded=true end end
    self.sections.Map.ExpandAll.Text=Text.text(if anyExpanded then "common.collapse_all" else "common.expand_all")
    for _,name in {"Featured","All","Favorites"} do selected(self.sections.Map.Tabs[name],self.activeTab==name) end
    local y=0;local active={};local found=0
    for _,g in self.sections.Map.Groups:GetChildren() do if g:IsA("Frame") and g:FindFirstChild("Cards") then g.Visible=false;for _,c in g.Cards:GetChildren() do if c:IsA("GuiObject") then c.Visible=false end end end end
    local function showGroup(name: string,list: {any},expanded: boolean,category: boolean?)
        local g=self.sections.Map.Groups[name];g.Visible=true;g.Position=UDim2.fromOffset(0,y);local items={}
        if expanded then for _,entry in list do
            local c=g.Cards[entry.id];c.Visible=true;table.insert(items,c);table.insert(active,c)
            selected(c,not self.options.useRandomMap and self.options.selectedMap==entry.type)
            local fav=table.find(favorite,entry.type)~=nil
            if c.Favorite:GetAttribute("Filled")~=fav then Icons.bind(c.Favorite.Icon,if fav then "LobbyStarFilled" else "LobbyStarEmpty");c.Favorite:SetAttribute("Filled",fav) end
            local cell=(width-(columns-1)*16)/columns;c.Thumbnail.Size=UDim2.new(1,-24,0,(cell-24)/2);c.Title.Position=UDim2.fromOffset(12,(cell-24)/2+24)
        end end
        local cardHeight=((width-(columns-1)*16)/columns-24)/2+68
        local h=grid(items,width,columns,cardHeight,16);g.Cards.Position=UDim2.fromOffset(0,if category then 60 else 36);g.Cards.Size=UDim2.new(1,0,0,h)
        g.Size=UDim2.new(1,0,0,(if category then 60 else 36)+h);y+=g.Size.Y.Offset+24
        if not category then g.Heading.BackgroundTransparency=1;g.Heading.Border.Transparency=1;g.Heading.TextSize=12;g.Heading.Size=UDim2.new(1,0,0,24) else selected(g.Heading,expanded) end
    end
    if searching then
        local list={};for _,entry in self.catalog do if string.find(string.lower(entry.name or Text.text(entry.translationKey)),search,1,true) or string.find(string.lower(entry.id),search,1,true) then table.insert(list,entry) end end
        found=#list;if #list>0 then showGroup("Search",list,true);self.sections.Map.Groups.Search.Heading.Text=Text.text("map_component.search_results").." ("..#list..")" end
    elseif self.activeTab=="Featured" then
        local list=table.clone(self.catalog)
        table.sort(list,function(a,b)return (a.featuredRank or math.huge)<(b.featuredRank or math.huge) end)
        showGroup("Featured",list,true);found=#list
    elseif self.activeTab=="Favorites" then
        local list={};for _,name in favorite do table.insert(list,self.byType[name]) end;found=#list
        if #list>0 then showGroup("Favorites",list,true) end
    else
        for _,category in Picker.mapCategoryOrder do if category~="featured" then local list={};for _,entry in self.catalog do if table.find(entry.categories,category) then table.insert(list,entry) end end;if #list>0 then showGroup("Category_"..category,list,self.expanded[category]==true,true) end end end;found=1
    end
    local empty=self.sections.Map.Groups.Empty;empty.Visible=found==0
    if found==0 then empty.Text=Text.text(if searching then "map_component.no_results" else "map_component.favorites_empty");empty.Position=UDim2.fromOffset(0,y);y+=144 end
    local special=self.sections.Map.Groups.Special;special.Visible=true;special.Position=UDim2.fromOffset(0,y);special.Heading.BackgroundTransparency=1;special.Heading.Border.Transparency=1;special.Heading.Size=UDim2.new(1,0,0,24);special.Cards.Position=UDim2.fromOffset(0,36)
    local random=special.Cards.Random;random.Visible=true;selected(random,self.options.useRandomMap);local cell=(width-(columns-1)*16)/columns;random.Size=UDim2.fromOffset(cell,(cell-24)/2+68);random.Thumbnail.Size=UDim2.new(1,-24,0,(cell-24)/2);random.Title.Position=UDim2.fromOffset(12,(cell-24)/2+24);table.insert(active,random);special.Size=UDim2.new(1,0,0,random.Size.Y.Offset+36);y+=special.Size.Y.Offset
    self.activeCards=active;self.sections.Map.Groups.Size=UDim2.new(1,0,0,y);self.sections.Map.Size=UDim2.new(1,0,0,124+y)
    local offset=0
    local function place(s: Frame,height: number) s.Position=UDim2.fromOffset(0,offset);s.Size=UDim2.new(1,0,0,height);offset+=height+24 end
    place(self.sections.Map,124+y)
    local dc={};for _,name in Settings.Difficulties do local b=self.sections.Difficulty.Cards[name];selected(b,self.options.selectedDifficulty==name);b.Active=self.options.nations~=0;b:SetAttribute("SourceDisabled",self.options.nations==0);b.BackgroundTransparency=if self.options.nations==0 then .98 else b.BackgroundTransparency;table.insert(dc,b) end
    local dh=grid(dc,width,if screen.X>=768 then 4 else 2,104,16);place(self.sections.Difficulty,64+dh)
    selected(self.sections.Mode.Cards.FFA,self.options.gameMode=="Free For All");selected(self.sections.Mode.Cards.Team,self.options.gameMode=="Team")
    self.sections.Mode.Teams.Visible=self.options.gameMode=="Team";local th=0
    if self.sections.Mode.Teams.Visible then local items={};for i,value in Settings.TeamOptions do local b=self.sections.Mode.Teams.Cards["Option"..i];selected(b,value==self.options.teamCount);table.insert(items,b) end;th=40+grid(items,width,if screen.X>=768 then 5 else 2,44,12);self.sections.Mode.Teams.Size=UDim2.new(1,0,0,th) end
    place(self.sections.Mode,if th>0 then 156+th else 136)
    local optionCards=self.sections.Options.Cards;local optColumns=if screen.X>=1024 then 4 else 2;local optWidth=(width-(optColumns-1)*16)/optColumns
    for i,name in {"Bots","Nations"} do local c=optionCards[name];local value=if name=="Bots" then self.options.bots else self.options.nations;local maximum=if name=="Bots"then Availability.MaxTribes else Availability.MaxNations;selected(c,value>0);c.Size=UDim2.fromOffset(optWidth*2+16,100);c.Position=UDim2.fromOffset(if optColumns==4 then (i-1)*(optWidth*2+32) else 0,if optColumns==4 then 0 else (i-1)*116);if not c.Value:IsFocused() then c.Value.Text=tostring(value) end;c.Track.Fill.Size=UDim2.fromScale(value/maximum,1);c.Track.Thumb.Position=UDim2.fromScale(value/maximum,.5) end
    local oy=if optColumns==4 then 116 else 232;local opts={};for _,key in Settings.ToggleOptions do local c=optionCards[key];selected(c,self.options[key]);c.Active=key~="compactMap";c.Selectable=key~="compactMap";table.insert(opts,c) end;for _,spec in Settings.InputOptions do local c=optionCards[spec.key];selected(c,self.options[spec.key]);c.Value.Visible=self.options[spec.key];c.Check.Visible=self.options[spec.key];if not c.Value:IsFocused() then c.Value.Text=if self.options[spec.valueKey]~=nil then tostring(self.options[spec.valueKey]) else "" end;table.insert(opts,c) end
    local oh=grid(opts,width,optColumns,100,16);for _,c in opts do c.Position+=UDim2.fromOffset(0,oy) end
    local clock=optionCards.ClockSpeed;clock.Visible=self.options.doomsdayClock;clock.Text=Text.text("doomsday_clock_speed."..self.options.doomsdayClockSpeed);clock.Position=optionCards.doomsdayClock.Position+UDim2.fromOffset(8,62);clock.Size=UDim2.fromOffset(optWidth-16,28)
    place(self.sections.Options,64+oy+oh)
    local unitCards={};for i,unit in Settings.UnitOptions do local c=self.sections.Units.Cards["Unit"..i];selected(c,not table.find(self.options.disabledUnits,unit));table.insert(unitCards,c) end
    local uh=grid(unitCards,width,if screen.X>=1024 then 5 elseif screen.X>=768 then 3 else 2,72,16);place(self.sections.Units,64+uh+24)
    self.sections.Size=UDim2.new(1,-8,0,offset);self.scroll.CanvasSize=UDim2.fromOffset(0,offset)
    self.body.Footer.Start.Text=string.upper(Text.text(if self.starting then "game_settings.starting" else "game_settings.start"));self.body.Footer.Start.Active=not self.starting
    task.defer(function() if not self.destroyed then self:refreshThumbnails() end end)
end
function Methods:show()
    self.ui.Visible=true;self:refresh()
end
function Methods:hide()
    self.ui.Visible=false;self.drag=nil;self:refreshThumbnails()
end
function Methods:close()
    local retiredAttempt=self.attempt
    self.attempt+=1;self.starting=false
    if self.overlayAttempt~=0 then self.overlayAttempt=0;self.root.Starting.Visible=false end
    self.options=Settings.availableOptions()
    self:hide();if self.callbacks.cancel then self.callbacks.cancel(retiredAttempt) end
end
function Methods:handleEscape(): boolean
    local offer=self.root:FindFirstChild("PFTutorialOffer")
    if offer and offer:IsA("GuiObject") and offer.Visible then
        local ok,Offer=pcall(require,script.Parent.TutorialOffer)
        if ok and Offer.dismiss(self.root) then return true end
    end
    if self.root.LobbyAlert.Visible then self:dismissAlert();return true end
    if self.ui.Visible then self:close();return true end
    return false
end
function Methods:dismissAlert()
    self.root.LobbyAlert.Visible=false
    if self.focusTimerAfterAlert then self.focusTimerAfterAlert=false;local input=self.sections.Options.Cards.maxTimer.Value;input:CaptureFocus();input.SelectionStart=1;input.CursorPosition=#input.Text+1 end
    -- A failed start never strands the player: closing its alert gives the lobby menu back.
    if not self.ui.Visible and not self.starting and self.callbacks.alertClosed then self.callbacks.alertClosed() end
end
function Methods:start()
    if self.starting then return end
    Availability.options(self.options)
    local config,errorMessage=Settings.buildConfig(self.options)
    if not config then self.root.LobbyAlert.Body.Message.Text=errorMessage or "";self.root.LobbyAlert.Visible=true;self.focusTimerAfterAlert=true;return end
    self.starting=true;self.attempt+=1;self.overlayAttempt=self.attempt;self.root.Starting.Message.Text=Text.text("game_settings.starting");self.root.Starting.Visible=true;self:refresh()
    if self.callbacks.start then self.callbacks.start(config,self.attempt) end
end
-- PF019 (PF - 3): the Atlas Solo screen (M4) builds its config from the shared settings column
-- (LobbySettingsModel.soloConfig) and starts through the same attempt/overlay/finishStart path.
function Methods:startConfig(config: any): boolean
    if self.starting or type(config)~="table" then return false end
    -- Play again hands a running match's config back: only its settings go (the server refuses unknown keys)
    config=Settings.settingsOnly(config) or config
    self.starting=true;self.attempt+=1;self.overlayAttempt=self.attempt
    do local ok,Cover=pcall(require,script.Parent.TeleportCover);if ok then Cover.map(config.gameMap,"Solo") end end -- a Solo start's hop shows its map
    self.root.Starting.Message.Text=Text.text("game_settings.starting");self.root.Starting.Visible=true
    if self.callbacks.start then self.callbacks.start(config,self.attempt) end
    return true
end
-- PF019 W6 (PF - 2): Solo starts on its own server; the Starting overlay follows the transfer
-- ("Starting your match…", "Retrying the teleport…"). Failure arrives as finishStart(false).
function Methods:transfer(attempt: number,_phase: string?,message: string?)
    if attempt~=self.attempt or self.overlayAttempt~=attempt then return end
    self.root.Starting.Message.Text=if type(message)=="string" and message~="" then message else Text.text("game_settings.starting")
end
-- Onboarding (PF - 2): the first-visit tutorial splash reuses the Starting overlay, server-driven with no attempt:
-- "Starting"/"Retrying" show it, "Offer" opens the invitee card (TutorialOffer), anything else hides it. A player's
-- own start owns the overlay, and the splash never outlives 40 s, so a lost server can't strand it.
-- First-match onboarding (PF - 2 server / PF - 3 UI, 2026-10-26): "FirstMatch" = a brand-new player goes straight into their
-- first (Easy Solo) match: no menu, no intro card; the match's own "Joining your match" screen (JoiningView, forced on the
-- hub) covers the hub at once and the teleport carries on underneath. Any later phase (a failed start) lifts it again.
-- The old "Intro" card is retired (the server no longer sends it; an old server's "Intro" is ignored).
-- The boot cover (PF - 2: every hub player hears FirstMatch or Lobby soon after join): until then the Joining screen with its
-- panel hidden keeps a new player from seeing the menu flash. Lobby lifts it; FirstMatch turns it into "Joining your match";
-- it also lifts when a match takes the screen (Studio plays on this server) and after COVER_GIVE_UP s without word.
Lobby.COVER_GIVE_UP=12 -- past the server's verdict cap (Onboarding.WAIT_SECONDS 10 s from join), so the menu never flashes first
function Methods:cover(): any?
    if self.firstMatch then return self.firstMatch end
    local ok,Joining=pcall(require,script.Parent.JoiningView)
    if not ok then return nil end
    local view=Joining.new(self.root.Parent,{force=true,ready=function() return false end,state=function() return nil end})
    if not view.root then return nil end
    self.firstMatch=view
    local game=self.root:FindFirstChild("Game")
    if game and game:IsA("GuiObject") then
        listen(self,game:GetPropertyChangedSignal("Visible"),function() if game.Visible and self.firstMatch==view then self:liftCover() end end)
    end
    return view
end
function Methods:liftCover()
    local view=self.firstMatch
    self.firstMatch=nil;self.covering=false
    if view then view:fade() end
end
function Methods:holdCover()
    local ok,Joining=pcall(require,script.Parent.JoiningView)
    if not ok or Joining.isMatchServer() then return end
    local view=self:cover();if not view then return end
    if view.panel then view.panel.Visible=false end
    self.covering=true
    task.delay(Lobby.COVER_GIVE_UP,function() if self.covering and self.firstMatch==view and not self.destroyed then self:liftCover() end end)
end
function Methods:splash(phase: string?,message: string?,map: string?)
    if self.destroyed then return end
    if phase=="FirstMatch" then
        do local ok,Offer=pcall(require,script.Parent.TutorialOffer);if ok and Offer.hide then Offer.hide(self.root) end end
        local view=self:cover()
        if view then
            self.covering=false
            if view.panel then view.panel.Visible=true end
            if type(map)=="string" and map~="" then view:map(map,"Your first match") end
            do local ok,Cover=pcall(require,script.Parent.TeleportCover);if ok then Cover.map(map,"Your first match") end end -- the hop shows it too
        end
        return
    end
    if self.firstMatch then self:liftCover() end
    if phase=="Intro" then return end
    if phase=="Offer" then -- the invitee card (a friend's tutorial invite)
        local ok,Offer=pcall(require,script.Parent.TutorialOffer)
        if ok then Offer.show(self.root) end
        return
    end
    do local ok,Offer=pcall(require,script.Parent.TutorialOffer);if ok and Offer.hide then Offer.hide(self.root) end end -- PF043: the server moved on
    if self.starting then return end
    self.splashToken=(self.splashToken or 0)+1
    if phase=="Starting" or phase=="Retrying" then
        local token=self.splashToken
        self.root.Starting.Message.Text=if type(message)=="string" and message~="" then message else Text.text("game_settings.starting")
        self.root.Starting.Visible=true
        task.delay(40,function() if self.splashToken==token then self:splash("Cleared") end end)
    elseif self.overlayAttempt==0 then self.root.Starting.Visible=false end
end
function Methods:finishStart(attempt: number,ok: boolean,message: string?)
    if attempt~=self.attempt then return end
    self.starting=false;self.overlayAttempt=0;self.root.Starting.Visible=false
    if ok then self.options=Settings.availableOptions();self:hide() else self.root.LobbyAlert.Body.Message.Text=message or "";self.root.LobbyAlert.Visible=true;self:refresh() end
end
function Methods:isBlocking(): boolean return self.ui.Visible or self.root.Starting.Visible or self.root.LobbyAlert.Visible end
function Methods:dispose()
    if self.destroyed then return end;self.destroyed=true;self.attempt+=1
    for _,connection in self.connections do connection:Disconnect() end
    if self.preferenceOff then self.preferenceOff() end
    self.thumbnails:dispose();self.ui.Visible=false;self.root.Starting.Visible=false;self.root.LobbyAlert.Visible=false
end
Lobby.defaultConfig=Settings.availableConfig
return Lobby
