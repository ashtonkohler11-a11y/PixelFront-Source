--!strict
-- PF029 (PF - 3): the emoji picker and quick chat panels authored by tools/atlas/author-pf029-social.luau
-- (DiplomacyEmojiMenu.PFEmoji, QuickChatModal.PFChat / PFChatCompact). Fills content, paints states, wires
-- input and places the desktop holders at the circle menu; every other size and position is authored.
-- Commands stay in DiplomacyController / QuickChatController: presses call back into them.
local GuiService=game:GetService("GuiService")
local UIS=game:GetService("UserInputService")
local ContextActionService=game:GetService("ContextActionService")
local HttpService=game:GetService("HttpService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Theme=require(script.Parent.BattleHudTheme)
local Icons=require(script.Parent.ReferenceIcons)
local HoverCard=require(script.Parent.CountryHoverCard)
local Hud=require(script.Parent.HudInspectorModel)
local ClientNames=require(Shared.OpenFrontClientNames)
local Config=require(Shared.Config)
local S={}
local SECONDS_PER_TICK=.1 -- 10 simulation ticks a second (a 3000-tick alliance lasts 5:00)
-- Seconds left on the per-recipient quick chat cooldown (Config.QuickChatCooldown ticks), 0 when free.
function S.cooldown(state: any,sender: number,recipient: number): number
    for _,record in (state.quickChat and state.quickChat[sender]) or {} do
        if record.recipient==recipient then return math.max(0,((Config.QuickChatCooldown or 30)-(state.ticks-record.tick))*SECONDS_PER_TICK) end
    end
    return 0
end
-- A nation's share of the land, as the inspector writes it.
function S.land(state: any,owner: number): string return Hud.percent(Hud.landShare(state,owner)) end

-- ---------------------------------------------------------------- shared
local TILE=Color3.fromHex("#26272c");local HOVER=Color3.fromHex("#30323a");local PRESSED=Color3.fromHex("#1a2744")
local ACTIVE=Color3.fromHex("#26324d");local SENT=Color3.fromHex("#173523");local COBALT_HI=Color3.fromHex("#6f9bff")
local WHITE=Color3.new(1,1,1)
-- Who the panel talks to: the name, the owner colour and the relation chip (as the player card shows them).
function S.identity(state: any,owner: number,color: Color3?,preferences: any?): any
    if owner<=0 then return {name="Everyone",color=nil,chip="ALL"} end
    return {name=ClientNames.resolve(state,owner,preferences),color=color,chip=Hud.chip(state,owner,1)}
end
local function fillHeader(holder: any,info: any,accent: Color3?)
    holder.Nation.Text=info.name
    holder.Dot.Visible=info.color~=nil;if info.color then holder.Dot.BackgroundColor3=info.color end
    for _,name in {"Wash","WashLow"} do holder[name].BackgroundColor3=info.color or Theme.Muted end
    HoverCard.paintChip(holder.Chip,info.chip,accent)
end
-- One button's look from its base state plus pointer/selection flags.
local function paint(button: any,base: string,flags: any)
    local state=base
    if base=="rest" or base=="active" then
        if flags.pressed then state="pressed" elseif flags.hover and base=="rest" then state="hover" end
    end
    local border=button:FindFirstChild("Border")
    if state=="hover" then button.BackgroundColor3=HOVER;if border then border.Color=COBALT_HI;border.Transparency=.15 end
    elseif state=="pressed" then button.BackgroundColor3=PRESSED;if border then border.Color=Theme.Cobalt;border.Transparency=.1 end
    elseif state=="active" then button.BackgroundColor3=ACTIVE;if border then border.Color=COBALT_HI;border.Transparency=.15 end
    elseif state=="sent" then button.BackgroundColor3=SENT;if border then border.Color=Color3.fromHex("#3fae73");border.Transparency=.2 end
    else button.BackgroundColor3=TILE;if border then border.Color=WHITE;border.Transparency=.92 end end
    local off=base=="off"
    for _,name in {"Label","Icon","Aux"} do
        local item=button:FindFirstChild(name)
        if item and item:IsA("TextLabel") then item.TextTransparency=if off then .62 else 0
        elseif item and item:IsA("ImageLabel") then item.ImageTransparency=if off then .62 else 0 end
    end
    button:SetAttribute("PFState",state)
end
local function available(item: any): boolean
    if not item or not item.Parent or not item:IsA("GuiObject") or not item.Selectable then return false end
    local node: Instance?=item
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node=node.Parent
    end
    return true
end
S.available=available
-- Wire a button: hover/press flags repaint it; selection shows its focus ring.
local function wire(self: any,button: any,repaint: () -> (),activated: (() -> ())?)
    local flags={hover=false,pressed=false};self.flags[button]=flags
    local function on(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(function(...) if not self.destroyed then fn(...) end end)) end
    on(button.MouseEnter,function() flags.hover=true;repaint() end)
    on(button.MouseLeave,function() flags.hover=false;flags.pressed=false;repaint() end)
    on(button.MouseButton1Down,function() flags.pressed=true;repaint() end)
    on(button.MouseButton1Up,function() flags.pressed=false;repaint() end)
    local focus=button:FindFirstChild("Focus",true)
    if focus then
        on(button.SelectionGained,function() focus.Visible=true end)
        on(button.SelectionLost,function() focus.Visible=false end)
    end
    if activated then on(button.Activated,activated) end
end
-- Place a desktop holder centred on a point (the circle menu), kept inside its parent with an 8 px margin.
local function place(holder: any,point: Vector2?)
    local parent=holder.Parent;local size=parent.AbsoluteSize
    if not point or size.X<=0 then holder.Position=UDim2.fromScale(.5,.5);return end
    local local_=point-parent.AbsolutePosition;local half=holder.AbsoluteSize/2
    local x=math.clamp(local_.X,half.X+8,math.max(half.X+8,size.X-half.X-8))
    local y=math.clamp(local_.Y,half.Y+8,math.max(half.Y+8,size.Y-half.Y-8))
    holder.Position=UDim2.fromOffset(math.floor(x+.5),math.floor(y+.5))
end
-- The circle menu's centre on screen (its last position, even once hidden).
function S.radialPoint(ui: any): Vector2?
    local radial=ui:FindFirstChild("Radial");if not radial then return nil end
    local target=radial:FindFirstChild("CityActions") or radial
    local size=target.AbsoluteSize;if size.X<=0 then return nil end
    return target.AbsolutePosition+size/2
end
local function shoulders(self: any,name: string,handler: (number) -> ())
    if not game:GetService("RunService"):IsClient() then return end
    self.shoulderAction=name.."-"..HttpService:GenerateGUID(false)
    ContextActionService:BindActionAtPriority(self.shoulderAction,function(_,state,input)
        if self.destroyed or not self.holder or not self.holder.Visible or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin then handler(if input.KeyCode==Enum.KeyCode.ButtonL1 then -1 else 1) end
        return Enum.ContextActionResult.Sink
    end,false,Enum.ContextActionPriority.High.Value+4,Enum.KeyCode.ButtonL1,Enum.KeyCode.ButtonR1)
end
-- A fresh open: no hover/press carried over from the last time it closed under the pointer, no stale ring.
local function settle(self: any)
    for button,flags in self.flags do flags.hover=false;flags.pressed=false;local focus=button:FindFirstChild("Focus",true);if focus then focus.Visible=GuiService.SelectedObject==button end end
end
local function teardown(self: any)
    if self.destroyed then return end;self.destroyed=true
    if self.shoulderAction then ContextActionService:UnbindAction(self.shoulderAction) end
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end

-- ---------------------------------------------------------------- emoji
-- 60 game emoji in six tabs, all in a 6 x 3 grid. Recent opens first, seeded with the common ones;
-- a sent emoji moves to its front. Map: the arrows as a compass pad around the target, ranks as a podium.
S.SEED={20,25,0,9,7,26,30,32,41,48,15,18,13,11,50,34,1,8}
S.TABS={
    {icon=29,name="Recent"},
    {icon=0,name="Faces",list={0,1,2,4,7,8,9,10,11,13,14,3,5,6,12}},
    {icon=20,name="Hands",list={20,21,25,15,16,18,19,17,22,23,24}},
    {icon=41,name="Map",list={35,36,37,-1,38,-1,40,41,42,43,39,44,45,46,47,-1,-1,-1}},
    {icon=34,name="Signals",list={26,34,30,31,32,33,29,27,28}},
    {icon=48,name="Things",list={48,49,50,54,51,52,53,55,56,57,58,59}},
}
local recent: {number}=table.clone(S.SEED)
function S.recent(): {number} return recent end
function S.remember(index: number)
    local at=table.find(recent,index);if at then table.remove(recent,at) end
    table.insert(recent,1,index);while #recent>18 do table.remove(recent) end
end
local Emoji={};Emoji.__index=Emoji;S.Emoji=Emoji
function Emoji.find(menu: Instance): any?
    local holder=menu:FindFirstChild("PFEmoji")
    if not (holder and holder:FindFirstChild("Tabs") and holder:FindFirstChild("Grid") and holder:FindFirstChild("Close")) then return nil end
    return holder
end
-- callbacks: send(index), close()
function Emoji.new(holder: any,callbacks: any): any
    local self=setmetatable({holder=holder,callbacks=callbacks,connections={},flags={},tab=1,tiles={},tabs={},destroyed=false},Emoji)
    for i=1,6 do
        local tab=holder.Tabs["Tab"..i];self.tabs[i]=tab;Icons.bind(tab.Icon,"DiplomacyEmoji"..S.TABS[i].icon)
        tab:SetAttribute("ActionDescription",S.TABS[i].name)
        wire(self,tab,function() self:paintTabs() end,function() self:select(i) end)
    end
    for i=1,18 do
        local tile=holder.Grid["Tile"..i];self.tiles[i]=tile
        wire(self,tile,function() self:paintTile(i) end,function()
            local e=tile:GetAttribute("Emoji");if type(e)=="number" and e>=0 then self:send(e) end
        end)
    end
    wire(self,holder.Close,function() end,function() callbacks.close() end)
    shoulders(self,"PFEmojiTabs",function(direction) self:select((self.tab-1+direction)%6+1);self:focusFirst() end)
    self:select(1);return self
end
function Emoji:list(): {number} return if self.tab==1 then recent else S.TABS[self.tab].list end
function Emoji:paintTabs()
    for i,tab in self.tabs do
        local active=i==self.tab;local flags=self.flags[tab]
        tab.BackgroundTransparency=if active or flags.hover then 0 else 1
        tab.BackgroundColor3=if active then Color3.fromHex("#2b2d34") else HOVER
        tab.Border.Transparency=if active then .9 else 1
        tab.Icon.ImageTransparency=if active or flags.hover then 0 else .45
        tab.Underline.Visible=active
    end
end
function Emoji:paintTile(i: number)
    local tile=self.tiles[i];local sent=tile:GetAttribute("Sent")==true
    paint(tile,if sent then "sent" else "rest",self.flags[tile])
    local flags=self.flags[tile];local lift=if flags.hover and not flags.pressed then -1.5 elseif flags.pressed then 1 else 0
    tile.Icon.Position=UDim2.new(7/44,0,7/44,lift);tile.Check.Visible=sent
end
function Emoji:select(tab: number)
    self.tab=tab;local list=self:list()
    for i,tile in self.tiles do
        local e=list[i];local shown=e~=nil and e>=0
        tile.Visible=shown;tile:SetAttribute("Emoji",if shown then e else nil);tile:SetAttribute("Sent",nil)
        if shown then Icons.bind(tile.Icon,"DiplomacyEmoji"..e);tile:SetAttribute("ActionDescription","Send emoji "..e) end
        self:paintTile(i)
    end
    self:paintTabs();self:link()
end
-- Controller graph: the tab row, then the grid (the Map tab's gaps skipped), the close key above.
function Emoji:link()
    local close=self.holder.Close
    local function at(c: number,r: number): any
        local tile=self.tiles[r*6+c+1];return if tile and tile.Visible then tile else nil
    end
    for i,tab in self.tabs do
        tab.NextSelectionLeft=self.tabs[math.max(1,i-1)];tab.NextSelectionRight=self.tabs[math.min(6,i+1)]
        tab.NextSelectionUp=close;tab.NextSelectionDown=at(math.min(5,i-1),0) or self:first()
    end
    for i,tile in self.tiles do
        local c,r=(i-1)%6,(i-1)//6
        local function scan(dc: number,dr: number): any
            local x,y=c+dc,r+dr
            while x>=0 and x<6 and y>=0 and y<3 do local t=at(x,y);if t then return t end;x+=dc;y+=dr end
            return nil
        end
        tile.NextSelectionLeft=scan(-1,0) or tile;tile.NextSelectionRight=scan(1,0) or tile
        tile.NextSelectionUp=scan(0,-1) or self.tabs[self.tab];tile.NextSelectionDown=scan(0,1) or tile
    end
    close.NextSelectionDown=self.tabs[self.tab];close.NextSelectionLeft=self.tabs[6]
end
function Emoji:first(): any?
    for _,tile in self.tiles do if tile.Visible then return tile end end
    return nil
end
function Emoji:focusFirst()
    if string.sub(UIS:GetLastInputType().Name,1,7)~="Gamepad" then return end
    local first=self:first();if available(first) then GuiService.SelectedObject=first end
end
function Emoji:send(index: number)
    for i,tile in self.tiles do if tile:GetAttribute("Emoji")==index then tile:SetAttribute("Sent",true);self:paintTile(i) end end
    S.remember(index)
    self.callbacks.send(index)
end
-- info: S.identity(...); point: where the circle menu was (desktop placement).
function Emoji:open(info: any,point: Vector2?,accent: Color3?)
    settle(self);fillHeader(self.holder,info,accent)
    self:select(1)
    self.holder.Visible=true
    place(self.holder,point)
end
function Emoji:close() self.holder.Visible=false end
function Emoji:visible(): boolean return self.holder.Visible end
function Emoji:destroy() teardown(self) end

-- ---------------------------------------------------------------- quick chat
-- Category chips, phrase chips in pages (8 on desktop, 6 on a phone), tap sends. A phrase that names a
-- player ([P1]) first swaps the grid to the nations by territory; that tap sends. A reopened panel inside
-- the per-recipient cooldown shows the ring and dims the chips.
local Chat={};Chat.__index=Chat;S.Chat=Chat
S.PHONE=540 -- the modal's height at or under which the compact (top-centre) panel shows
function Chat.find(modal: Instance): any?
    local desk,compact=modal:FindFirstChild("PFChat"),modal:FindFirstChild("PFChatCompact")
    if not (desk and compact and desk:FindFirstChild("Grid") and compact:FindFirstChild("Grid")) then return nil end
    return {desk=desk,compact=compact}
end
-- callbacks: categories() -> {key,label}[], phrases(category) -> {key,text,requiresPlayer}[], nations() -> {owner,name,color,land}[],
-- send(key, player?), close(), cooldown() -> seconds left (0 when free)
function Chat.new(nodes: any,callbacks: any): any
    local self=setmetatable({nodes=nodes,callbacks=callbacks,connections={},flags={},page=1,destroyed=false,layouts={}},Chat)
    for _,holder in {nodes.desk,nodes.compact} do
        local layout={holder=holder,cats={},chips={},dots={}}
        for i=1,6 do local cat=holder.Cats["Cat"..i];layout.cats[i]=cat
            wire(self,cat,function() self:paintCats() end,function() local c=self.categories[i];if c then self:selectCategory(c.key) end end) end
        local i=1;while holder.Grid:FindFirstChild("Chip"..i) do
            local chip=holder.Grid["Chip"..i];local index=i;layout.chips[i]=chip
            wire(self,chip,function() self:paintChip(chip) end,function() self:pressChip(index) end);i+=1
        end
        for d=1,3 do layout.dots[d]=holder.Dots["Dot"..d] end
        wire(self,holder.Prev,function() self:paintKeys() end,function() self:turn(-1) end)
        wire(self,holder.Next,function() self:paintKeys() end,function() self:turn(1) end)
        wire(self,holder.Close,function() end,function() callbacks.close() end)
        wire(self,holder.PhraseBar.Back,function() end,function() self:back() end)
        table.insert(self.layouts,layout)
    end
    shoulders(self,"PFChatCategories",function(direction)
        if self.pick then return end
        local at=1;for i,c in self.categories do if c.key==self.category then at=i end end
        self:selectCategory(self.categories[(at-1+direction)%#self.categories+1].key);self:focusFirst()
    end)
    self.categories=callbacks.categories()
    return self
end
function Chat:layout(): any
    local compact=self.nodes.desk.Parent.AbsoluteSize.Y<=S.PHONE
    return if compact then self.layouts[2] else self.layouts[1]
end
function Chat:perPage(): number return #self.current.chips end
function Chat:items(): {any}
    if self.pick then return self.callbacks.nations() end
    return self.callbacks.phrases(self.category)
end
function Chat:pages(): number return math.max(1,math.ceil(#self:items()/self:perPage())) end
function Chat:paintCats()
    for i,cat in self.current.cats do local c=self.categories[i]
        paint(cat,if c and c.key==self.category then "active" else "rest",self.flags[cat])
    end
end
function Chat:paintKeys()
    local pages=self:pages()
    for _,spec in {{self.current.holder.Prev,self.page>1},{self.current.holder.Next,self.page<pages}} do
        local key,on=spec[1],spec[2];local flags=self.flags[key]
        key.Active=on;key.Selectable=on
        key.BackgroundColor3=if on and flags.hover then HOVER else Color3.fromHex(if on then "#2a2b31" else "#222327")
        key.Glyph.TextTransparency=if on then 0 else .75
    end
end
function Chat:paintChip(chip: any)
    local cooling=self.cooling and not self.pick
    paint(chip,if chip:GetAttribute("Sent") then "sent" elseif cooling then "off" else "rest",self.flags[chip])
    chip.Check.Visible=chip:GetAttribute("Sent")==true
end
local function phraseRich(text: string,who: any?): string
    local slot=if who then string.format('<font color="#%s"><b>%s</b></font>',who.color and who.color:ToHex() or "f2f2f2",who.name)
        else '<font color="#aeb3ba"><u>who?</u></font>'
    return (string.gsub(text,"%[P1%]",function() return slot end))
end
S.phraseRich=phraseRich
function Chat:render()
    if self.destroyed or not self.current then return end
    local holder=self.current.holder;local items=self:items();local per=self:perPage()
    self.page=math.clamp(self.page,1,self:pages())
    holder.Cats.Visible=self.pick==nil;holder.PhraseBar.Visible=self.pick~=nil
    if self.pick then holder.PhraseBar.Text.Text=phraseRich(self.pick.text,nil) end
    for i,c in self.categories do local cat=self.current.cats[i];if cat then cat.Label.Text=c.label end end
    for i,chip in self.current.chips do
        local item=items[(self.page-1)*per+i]
        chip.Visible=item~=nil;chip:SetAttribute("Sent",nil);chip:SetAttribute("Item",(self.page-1)*per+i)
        if item then
            if self.pick then
                chip.Label.Text=string.format('<font color="#%s">●</font>  <b>%s</b>',item.color and item.color:ToHex() or "bdbdbd",item.name)
                chip.Aux.Text=item.land or "";chip.Aux.Visible=true
            else chip.Label.Text=phraseRich(item.text,nil);chip.Aux.Visible=false end
            local cooling=self.cooling and not self.pick
            chip.Active=not cooling;chip.Selectable=not cooling
        end
        self:paintChip(chip)
    end
    local pages=self:pages()
    for d,dot in self.current.dots do
        dot.Visible=pages>1 and d<=pages
        dot.BackgroundColor3=if d==self.page then Theme.Gold else WHITE;dot.BackgroundTransparency=if d==self.page then 0 else .78
    end
    holder.Dots.Position=UDim2.new(.5,-(pages*12-6)/2,holder.Dots.Position.Y.Scale,0)
    self:paintCats();self:paintKeys();self:paintCooldown();self:link()
end
function Chat:paintCooldown()
    local left=self.callbacks.cooldown();self.cooling=left>0
    local cool=self.current.holder.Cooldown;cool.Visible=left>0
    if left>0 then cool.Seconds.Text=string.format("%ds",math.ceil(left)) end
end
-- Controller graph: categories (or the back key) on top, the grid, the page keys at its sides.
function Chat:link()
    local holder=self.current.holder;local chips={};for _,c in self.current.chips do if c.Visible and c.Selectable then table.insert(chips,c) end end
    local cols=if #self.current.chips==6 then 3 else 2
    local top=if self.pick then {holder.PhraseBar.Back} else self.current.cats
    for i,node in top do
        node.NextSelectionLeft=top[math.max(1,i-1)];node.NextSelectionRight=top[math.min(#top,i+1)]
        node.NextSelectionUp=holder.Close;node.NextSelectionDown=chips[math.min(#chips,1+math.floor((i-1)*cols/#top))] or node
    end
    local prev,next_=holder.Prev,holder.Next
    for i,chip in chips do
        local c=(i-1)%cols
        chip.NextSelectionLeft=if c>0 then chips[i-1] elseif prev.Selectable then prev else chip
        chip.NextSelectionRight=if c<cols-1 and chips[i+1] then chips[i+1] elseif next_.Selectable then next_ else chip
        chip.NextSelectionUp=chips[i-cols] or top[1];chip.NextSelectionDown=chips[i+cols] or chip
    end
    prev.NextSelectionRight=chips[1] or prev;next_.NextSelectionLeft=chips[math.min(cols,#chips)] or next_
    holder.Close.NextSelectionDown=top[1]
end
function Chat:first(): any?
    for _,chip in self.current.chips do if available(chip) then return chip end end
    if self.pick then return self.current.holder.PhraseBar.Back end
    return self.current.cats[1]
end
function Chat:focusFirst()
    if string.sub(UIS:GetLastInputType().Name,1,7)~="Gamepad" then return end
    local first=self:first();if available(first) then GuiService.SelectedObject=first end
end
function Chat:selectCategory(key: string)
    self.category=key;self.page=1;self.pick=nil;self:render()
end
function Chat:turn(direction: number)
    local pages=self:pages();local nextPage=math.clamp(self.page+direction,1,pages)
    if nextPage==self.page then return end
    self.page=nextPage;self:render()
end
function Chat:pressChip(i: number)
    local items=self:items();local item=items[(self.page-1)*self:perPage()+i];if not item then return end
    local chip=self.current.chips[i]
    if self.pick then
        chip:SetAttribute("Sent",true);self:paintChip(chip)
        self.callbacks.send(self.pick.key,item.owner);return
    end
    if self.cooling then return end
    if item.requiresPlayer then self.pick=item;self.page=1;self:render();self:focusFirst();return end
    chip:SetAttribute("Sent",true);self:paintChip(chip)
    self.callbacks.send(item.key,nil)
end
function Chat:back(): boolean
    if not self.pick then return false end
    self.pick=nil;self.page=1;self:render();self:focusFirst();return true
end
function Chat:open(info: any,point: Vector2?,accent: Color3?,category: string?)
    settle(self);self.categories=self.callbacks.categories()
    self.current=self:layout()
    for _,layout in self.layouts do layout.holder.Visible=layout==self.current end
    fillHeader(self.current.holder,info,accent)
    self.category=category or self.category or (self.categories[1] and self.categories[1].key);self.page=1;self.pick=nil
    self:render()
    if self.current==self.layouts[1] then place(self.current.holder,point) end
end
-- openWithPhrase: the tutorial / preset path straight into a phrase (its "who?" step when it names a player)
function Chat:openPhrase(key: string)
    for _,item in self.callbacks.phrases(self.category) do
        if item.key==key then if item.requiresPlayer then self.pick=item;self.page=1;self:render() end;return end
    end
end
function Chat:refresh() if self.current and self.current.holder.Visible then local was=self.cooling;self:paintCooldown();if was~=self.cooling then self:render() end end end
function Chat:close() for _,layout in self.layouts do layout.holder.Visible=false end;self.pick=nil end
function Chat:visible(): boolean return self.current~=nil and self.current.holder.Visible end
function Chat:destroy() teardown(self) end
return S
