--!strict
local Players=game:GetService("Players")
local Input=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Http=game:GetService("HttpService")
local Marketplace=game:GetService("MarketplaceService")
local Run=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local Shared=game.ReplicatedStorage.Shared
local Catalog=require(Shared.CosmeticCatalog)
local Appearance=require(Shared.CosmeticAppearance)
local Theme=require(Shared.Theme)
local Art=require(script.Parent.CosmeticArt)
local Shop={};Shop.__index=Shop
local function listen(self: any,signal: RBXScriptSignal,callback: any)
    table.insert(self.connections,signal:Connect(callback))
end
local function number(value: number): string
    local s=tostring(math.floor(value));local result=s
    while true do local replacement,n=string.gsub(result,"^(%-?%d+)(%d%d%d)","%1,%2");result=replacement;if n==0 then break end end
    return result
end
-- PF031: deep equality for the profile's small tables (owned ids, the equipped look)
local function same(a: any,b: any): boolean
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for key,value in a do if not same(value,b[key]) then return false end end
    for key in b do if a[key]==nil then return false end end
    return true
end
function Shop.new(gui: ScreenGui,remotes: any,hooks: any): any
    local root=gui.Background;local ui=assert(root:FindFirstChild("CosmeticShop"),"Missing authored CosmeticShop")
    local self=setmetatable({gui=gui,root=root,ui=ui,body=ui.Body,remotes=remotes,hooks=hooks,
        category="Skin",inventory=false,rows={},rowConnections={},connections={},looks={},productInfo={},
        profile={loaded=false,failed=false,balance=0,owned={},equipped={},revision=-1},lastRefresh=-1},Shop)
    listen(self,ui.Body.Close.Activated,function()self:close()end)
    listen(self,ui.Confirmation.Cancel.Activated,function()self:cancelConfirmation()end)
    listen(self,ui.Confirmation.Confirm.Activated,function()self:confirm()end)
    listen(self,ui.Body.OwnedOnly.Activated,function()
        self.inventory=not self.inventory;if self.category=="Currency" or self.category=="Bundle" then self.category="Skin" end
        self.body.Scroll.CanvasPosition=Vector2.zero;self:refresh()
    end)
    for _,category in Catalog.categories do
        listen(self,self.body.Tabs[category].Activated,function()
            if self.ui.Confirmation.Visible then return end
            self.category=category;self.body.Scroll.CanvasPosition=Vector2.zero;self:refresh()
        end)
    end
    for slot in Catalog.slots do
        local slotButton=self.body.Loadout:FindFirstChild(slot)
        if not slotButton then continue end
        listen(self,slotButton.Activated,function()
            if self.ui.Confirmation.Visible then return end
            self.category=slot;self.inventory=true;self.body.Scroll.CanvasPosition=Vector2.zero;self:refresh()
        end)
    end
    for _,entry in {root.Home.Body.Shop,root.GameMenu.Body.Header.Shop} do
        listen(self,entry.Activated,function()self:open()end)
    end
    listen(self,self.body.Scroll:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout()end)
    listen(self,self.body:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout()end)
    listen(self,remotes.CosmeticsState.OnClientEvent,function(packet)self:receive(packet)end)
    -- Prompt completion only unlocks the UI. Entitlements still come from the server.
    listen(self,Marketplace.PromptProductPurchaseFinished,function(userId,productId,purchased)
        if userId==Players.LocalPlayer.UserId then self:finishPrompt("Product",productId,purchased) end
    end)
    listen(self,Marketplace.PromptGamePassPurchaseFinished,function(player,passId,purchased)
        if player==Players.LocalPlayer then self:finishPrompt("Pass",passId,purchased) end
    end)
    listen(self,Input:GetPropertyChangedSignal("PreferredInput"),function()
        if self.ui.Visible and Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=self.ui.Confirmation.Visible and self.ui.Confirmation.Cancel or self.body.Close end
    end)
    listen(self,Gui:GetPropertyChangedSignal("SelectedObject"),function()
        local selected=Gui.SelectedObject
        if not self.ui.Visible or not selected then return end
        local active=if self.ui.Confirmation.Visible then self.ui.Confirmation else self.body
        if not selected:IsDescendantOf(active) then self:focusActive() end
    end)
    self:refresh();remotes.CosmeticsCommand:FireServer({kind="Ready"})
    for _,pack in Catalog.currencyPacks do
        if pack.productId<=0 then continue end
        task.spawn(function()
            local ok,info=pcall(function()return Marketplace:GetProductInfoAsync(pack.productId,Enum.InfoType.Product)end)
            if self.destroyed then return end
            if ok and type(info)=="table" and type(info.PriceInRobux)=="number" and info.IsForSale then self.productInfo[pack.id]=info end
            self:refresh()
        end)
    end
    -- PF020: the Game Passes' live prices (only real IDs are asked; passId 0 stays "--")
    local priced=table.clone(Catalog.premiumPacks);for _,pass in Catalog.passes or {} do table.insert(priced,pass) end
    for _,pack in priced do
        if pack.passId<=0 then continue end
        task.spawn(function()
            local ok,info=pcall(function()return Marketplace:GetProductInfoAsync(pack.passId,Enum.InfoType.GamePass)end)
            if not self.destroyed and ok and type(info)=="table" and type(info.PriceInRobux)=="number" and info.IsForSale then self.productInfo[pack.id]=info;self:refresh() end
        end)
    end
    return self
end
function Shop:isBlocking(): boolean return self.ui.Visible end
function Shop:focusActive()
    if not self.ui.Visible then return end
    Gui.SelectedObject=if self.ui.Confirmation.Visible then self.ui.Confirmation.Cancel else self.body.Close
end
function Shop:open()
    if self.destroyed or self.ui.Visible then return end
    self.previousFocus=Gui.SelectedObject;self.ui.Visible=true
    self:refresh();self.body.Scroll.CanvasPosition=Vector2.zero
    if Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=self.body.Close end
    if os.clock()-self.lastRefresh>5 then self.lastRefresh=os.clock();self.remotes.CosmeticsCommand:FireServer({kind="Ready"}) end
end
function Shop:close()
    self:cancelConfirmation();self.ui.Visible=false
    local prior=self.previousFocus
    if prior and prior.Parent and prior:IsDescendantOf(self.gui) then Gui.SelectedObject=prior else Gui.SelectedObject=nil end
    self.previousFocus=nil
end
function Shop:handleEscape(): boolean
    if not self.ui.Visible then return false end
    if self.ui.Confirmation.Visible then self:cancelConfirmation() else self:close() end
    return true
end
function Shop:receive(packet: any)
    if self.destroyed or type(packet)~="table" then return end
    if packet.kind=="CosmeticLooks" and type(packet.looks)=="table" then
        if packet.full then self.looks={} end
        for userId,look in packet.looks do self.looks[tostring(userId)]=if look==false then nil else Appearance.sanitize(look) end
        if self.hooks.changed then self.hooks.changed(self.looks) end;return
    end
    if packet.kind~="Cosmetics" then return end
    -- PF031 (tab lag): the lobby Shop asks for the profile (Ready) each time it opens; an answer that repeats the
    -- profile already shown changes nothing, so nothing repaints (every refresh rebuilds all the Shop's cards)
    if self:repeats(packet) then return end
    if type(packet.revision)=="number" and packet.revision>=self.profile.revision then
        self.profile={revision=packet.revision,balance=packet.balance or 0,owned=packet.owned or {},equipped=Appearance.sanitize(packet.equipped),loaded=packet.loaded==true,failed=packet.failed==true,
            group=if type(packet.group)=="table" then packet.group else nil} -- PF036: the group reward tile
        self.looks[tostring(Players.LocalPlayer.UserId)]=self.profile.equipped
        if self.hooks.changed then self.hooks.changed(self.looks) end
    elseif not self.profile.loaded then self.profile.failed=packet.failed==true end
    if self.pending and packet.requestId==self.pending then self.pending=nil end
    if packet.message then self.message=packet.message end
    self:refresh()
end
-- PF031: a Cosmetics packet that says only what the shown profile already says (same revision, wallet, owned set and
-- look; no message; not the answer to a pending request; the map's local look still this profile's)
function Shop:repeats(packet: any): boolean
    local profile=self.profile
    if packet.message~=nil or (self.pending~=nil and packet.requestId==self.pending) or packet.revision~=profile.revision then return false end
    if (packet.balance or 0)~=profile.balance or (packet.loaded==true)~=profile.loaded or (packet.failed==true)~=profile.failed then return false end
    local g,h=packet.group,profile.group -- PF036
    if (type(g)=="table")~=(h~=nil) or (h~=nil and type(g)=="table" and (g.claimed~=h.claimed or g.groupId~=h.groupId)) then return false end
    if self.looks[tostring(Players.LocalPlayer.UserId)]~=profile.equipped then return false end
    return same(packet.owned or {},profile.owned) and same(Appearance.sanitize(packet.equipped),profile.equipped)
end
function Shop:request(command: any)
    if self.pending or not self.profile.loaded or self.profile.failed then return end
    local id=Http:GenerateGUID(false);command.requestId=id;self.pending=id;self.message="Updating your inventory…"
    self.remotes.CosmeticsCommand:FireServer(command);self:refresh()
    task.delay(12,function()
        if not self.destroyed and self.pending==id then
            self.pending=nil;self.message="Still waiting for your inventory. Reopen the shop to refresh."
            self.remotes.CosmeticsCommand:FireServer({kind="Ready"});self:refresh()
        end
    end)
end
function Shop:select(item: any)
    if self.ui.Confirmation.Visible or self.pending then return end
    if (item.packOnly or item.passOnly) and not self.profile.owned[item.id] then return end
    if item.category=="Currency" then
        local info=self.productInfo[item.id]
        if Run:IsStudio() or item.productId<=0 or not info or not self.profile.loaded or self.profile.failed then return end
        self.confirmItem=item;self.ui.Confirmation.Title.Text="Buy "..Catalog.currencyName
        self.ui.Confirmation.Detail.Text=number(item.amount).." "..Catalog.currencyName.." for "..number(info.PriceInRobux).." Robux.\n\n"..Catalog.currencyName.." buys cosmetics."
    else
        local price,missing=Catalog.bundlePrice(item,self.profile.owned)
        if #missing==0 then
            if item.category=="Bundle" then return end
            self:request({kind="Equip",itemId=if self.profile.equipped[item.category]==item.id then false else item.id,slot=item.category});return
        end
        if type(price)~="number" then return end -- not for sale yet
        self.confirmItem=item;self.ui.Confirmation.Title.Text="Confirm purchase"
        self.ui.Confirmation.Detail.Text="Buy "..item.name.." for "..number(price).." "..Catalog.currencyName.."?\n\n"..(if item.category=="Bundle" then tostring(#missing).." new cosmetics. Owned items are deducted from the price." else item.description)
    end
    self.ui.Confirmation.Visible=true;self.ui.ConfirmationShade.Visible=true
    self.body.Visible=false
    if Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=self.ui.Confirmation.Cancel end
end
function Shop:cancelConfirmation()
    self.confirmItem=nil;self.ui.Confirmation.Visible=false;self.ui.ConfirmationShade.Visible=false;self.body.Visible=true
    if self.ui.Visible and Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=self.body.Close end
end
function Shop:confirm()
    local item=self.confirmItem;if not item then return end
    self:cancelConfirmation()
    if item.category=="Currency" then
        if Run:IsStudio() or not self.productInfo[item.id] or item.productId<=0 then return end
        pcall(function() require(script.Parent.StatsReport).prompt(tostring(item.id),"shop") end) -- STATS v3
        local ok=pcall(function()Marketplace:PromptProductPurchase(Players.LocalPlayer,item.productId)end)
        self.message=if ok then "Your currency balance updates after Roblox confirms the purchase." else "Purchase prompt unavailable. Please try again."
        self:refresh()
    else self:request({kind="Buy",itemId=item.id}) end
end
-- Atlas owns inline actions. Keep the authenticated request/prompt path here.
function Shop:getState(): any
    return {profile=self.profile,productInfo=self.productInfo,pending=self.pending or self.pendingPrompt,message=self.message}
end
function Shop:finishPrompt(kind: string,id: number,purchased: boolean)
    local pending=self.pendingPrompt
    if not pending or pending.kind~=kind or pending.id~=id then return end
    self.pendingPrompt=nil
    self.message=if purchased then "Waiting for Roblox purchase confirmation." else "Purchase cancelled."
    self:refresh()
end
function Shop:prompt(kind: string,id: number)
    if self.pendingPrompt or Run:IsStudio() then return end
    local pending={kind=kind,id=id};self.pendingPrompt=pending;self.message="Purchase prompt open.";self:refresh()
    pcall(function() require(script.Parent.StatsReport).promptFor(kind,id,"shop") end) -- STATS v3
    local ok=pcall(function()
        if kind=="Pass" then Marketplace:PromptGamePassPurchase(Players.LocalPlayer,id)
        else Marketplace:PromptProductPurchase(Players.LocalPlayer,id) end
    end)
    if not ok and self.pendingPrompt==pending then self.pendingPrompt=nil;self.message="Purchase prompt unavailable. Please try again." end
    self:refresh()
end
function Shop:purchaseConfirmed(itemId: string)
    if self.destroyed or self.pending or self.pendingPrompt or not self.profile.loaded or self.profile.failed then return end
    local premium=Catalog.premiumById[itemId]
    if premium then
        local info=self.productInfo[itemId]
        if Run:IsStudio() or self.profile.owned[itemId] or premium.passId<=0 or not info or info.IsForSale~=true or type(info.PriceInRobux)~="number" then return end
        self:prompt("Pass",premium.passId);return
    end
    -- PF020 G6: a Game Pass (Roblox's own prompt; ownership still comes from the server)
    local pass=Catalog.passById and Catalog.passById[itemId]
    if pass then
        local info=self.productInfo[itemId]
        if Run:IsStudio() or self.profile.owned[itemId] or pass.passId<=0 or not info or info.IsForSale~=true or type(info.PriceInRobux)~="number" then return end
        self:prompt("Pass",pass.passId);return
    end
    local item=Catalog.byId[itemId]
    if item then self:request({kind="Buy",itemId=itemId});return end
    for _,pack in Catalog.currencyPacks do
        if pack.id~=itemId then continue end
        local info=self.productInfo[itemId]
        if Run:IsStudio() or pack.productId<=0 or not info or info.IsForSale~=true or type(info.PriceInRobux)~="number" then return end
        self:prompt("Product",pack.productId);return
    end
end
function Shop:layout()
    local width=math.max(1,self.body.Scroll.AbsoluteSize.X-8)
    local columns=math.max(1,math.floor((width+12)/252))
    local cell=math.floor((width-(columns-1)*12)/columns)
    self.body.Scroll.Content.Grid.CellSize=UDim2.fromOffset(cell,244)
    self.body.Scroll.Content.Grid.FillDirectionMaxCells=columns
    local mobile=self.body.AbsoluteSize.X<560
    self.body.Title.Text=if mobile then "Shop" else "Cosmetic shop"
    self.body.Title.TextSize=if mobile then 16 else 22
    self.body.Title.Size=UDim2.new(1,if mobile then -214 else -250,0,30)
    self.body.Balance.Size=UDim2.fromOffset(if mobile then 128 else 160,34)
    self.body.Balance.Position=UDim2.new(1,if mobile then -192 else -224,0,12)
    self.body.Loadout.Visible=not mobile
    self.body.OwnedOnly.Size=UDim2.fromOffset(if mobile then math.max(108,self.body.AbsoluteSize.X-32) else 108,44)
end
function Shop:refresh()
    if self.destroyed then return end
    if self.hooks.stateChanged then self.hooks.stateChanged(self:getState())end
    for _,connection in self.rowConnections do connection:Disconnect() end;table.clear(self.rowConnections)
    local oldFocus=Gui.SelectedObject;local focusedId=nil
    for id,row in self.rows do if oldFocus and oldFocus:IsDescendantOf(row) then focusedId=id end;row:Destroy() end;self.rows={}
    self.body.Balance.Text=if self.profile.loaded then number(self.profile.balance).." "..Catalog.currencyName else Catalog.currencyName.." · loading"
    self.body.OwnedOnly.Text=if self.inventory then "Inventory ✓" else "Inventory"
    self.body.OwnedOnly.BackgroundColor3=if self.inventory then Theme.Accent else Theme.PanelRaised
    for slot in Catalog.slots do
        local item=Catalog.byId[self.profile.equipped[slot]]
        local slotButton=self.body.Loadout:FindFirstChild(slot)
        if slotButton then slotButton.Text=slot.." · "..(if item then item.name else "default") end
    end
    for _,category in Catalog.categories do self.body.Tabs[category].BackgroundColor3=if category==self.category then Theme.Accent else Theme.PanelRaised end
    local items=if self.category=="Currency" then Catalog.currencyPacks else Catalog.items
    for index,entry in items do
        local item=entry
        if self.category=="Currency" then item=table.clone(entry);item.category="Currency";item.description="For skins, flags, crowns and VFX.";item.colors={"#2dd4bf","#38bdf8"}
        elseif item.category~=self.category or (self.inventory and not self.profile.owned[item.id]) then continue end
        local row=self.ui.Templates.ItemCard:Clone();row.Name=item.id;row.LayoutOrder=index;row.Visible=true;row.Parent=self.body.Scroll.Content;self.rows[item.id]=row
        row.Title.Text=item.name;row.Description.Text=item.description
        if item.category=="Currency" then row.Art.Visible=false else Art.bind(row.Art,item.id) end
        local price,missing=0,{}
        if item.category~="Currency" then price,missing=Catalog.bundlePrice(item,self.profile.owned) end
        local isOwned=item.category~="Currency" and #missing==0
        -- an item without a price yet (Ashton sets prices) is never buyable here and must not break the shop
        local unpriced=item.category~="Currency" and type(price)~="number"
        if unpriced then price=0 end
        local equipped=self.profile.equipped[item.category]==item.id
        row.Price.Text=if item.category=="Currency" then (if self.productInfo[item.id] then number(self.productInfo[item.id].PriceInRobux).." Robux" else "Unavailable") elseif isOwned then "Owned" elseif unpriced then "Not available" else number(price).." "..Catalog.currencyName
        row.Action.Text=if item.category=="Currency" then (if Run:IsStudio() then "Studio preview" else "Buy currency") elseif item.category=="Bundle" and isOwned then "Owned" elseif equipped then "Unequip" elseif isOwned then "Equip" else "Buy"
        local ready=self.profile.loaded and not self.profile.failed and self.pending==nil
        local enabled=ready and (if item.category=="Currency" then not Run:IsStudio() and self.productInfo[item.id]~=nil and item.productId>0 elseif item.category=="Bundle" and isOwned then false elseif (item.packOnly or item.passOnly or unpriced) and not isOwned then false else isOwned or self.profile.balance>=price)
        row.Action.Active=enabled;row.Action.Selectable=enabled;row.Action.BackgroundColor3=if enabled then Theme.Accent else Theme.CommandDivider
        if not enabled and not isOwned and item.category~="Currency" and ready and not unpriced then row.Action.Text="Need "..number(math.max(0,price-self.profile.balance)).." more" end
        if unpriced and not isOwned then row.Action.Text="Not available" end
        if item.packOnly and not isOwned then row.Price.Text="Aurora Pack";row.Action.Text="Pack cosmetic" end
        table.insert(self.rowConnections,row.Action.Activated:Connect(function()self:select(item)end))
        table.insert(self.rowConnections,row.Action.MouseEnter:Connect(function()if enabled then Tween:Create(row.Action,TweenInfo.new(.12),{BackgroundColor3=Theme.Accent:Lerp(Theme.Text,.15)}):Play() end end))
        table.insert(self.rowConnections,row.Action.MouseLeave:Connect(function()row.Action.BackgroundColor3=if enabled then Theme.Accent else Theme.CommandDivider end))
    end
    self.body.Status.Text=if self.profile.failed then "Your inventory is unavailable. Purchases are paused; reopen to retry." elseif not self.profile.loaded then "Loading your inventory…" elseif next(self.rows)==nil then "No owned cosmetics in this category yet." else self.message or "Cosmetics change appearance only. Select an owned item to equip it."
    self:layout()
    if focusedId then
        if self.rows[focusedId] and self.rows[focusedId].Action.Selectable then Gui.SelectedObject=self.rows[focusedId].Action
        elseif self.ui.Visible then self:focusActive() end
    end
end
function Shop:dispose()
    self.destroyed=true;for _,connection in self.connections do connection:Disconnect() end
    for _,connection in self.rowConnections do connection:Disconnect() end
    for _,row in self.rows do row:Destroy() end;Art.release()
end
return Shop
