--!strict
-- Authored Atlas templates; wallet and equipment mutations use authenticated adapters.
local Gui=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Shared
local Catalog=require(Shared.CosmeticCatalog)
local Commerce=require(Shared.CosmeticCommerce)
local Flags=require(Shared.CommerceFlags) -- PF019: reversible switches (Passes hidden until the gamepass pass)
local Targets=require(Shared.CosmeticTargets)
local Typography=require(Shared.PixelFrontTypography)
local Art=require(script.Parent.AtlasCommerceArt)

local AuroraPresentation=require(script.Parent.AuroraShopPresentation)
local ForgePresentation=require(script.Parent.ForgeStarterShopPresentation)
local CardModel=require(script.Parent.ShopCardModel) -- PF019 M2: overline, set colour, one action
local TopBar=require(script.Parent.ShopTopBar) -- PF019 M3: the shop top bar's life
local ShopItemArt=require(script.Parent.ShopItemArt) -- PF019 Phase C (PF - 2): living art in the card wells
local BuyModel=require(script.Parent.ShopBuyModel) -- PF019 Cobalt buy: did the buy really go through (pure)
local BuyFx=require(script.Parent.ShopBuyFx) -- PF019 Cobalt buy: the key's pending / success / failure looks
-- Catalog cards with PF - 2's living art (ShopItemArt.attach clones the one group a card needs).
-- PF028: the Forge Territory card is the map's material (CosmeticSkinArt) like every skin, so no forge stage over it
local ITEM_ART={vfx_aurora="effect",vfx_ember="effect"}
local Page={};Page.__index=Page
local KIND_NAMES=Commerce.kindNames
local ROBUX_ICON="rbxasset://textures/ui/common/robux.png"
local COBALT_ICON="rbxassetid://120204330036909"
local function number(value: any): string
    if type(value)~="number" or value~=value then return "--" end
    local result=tostring(math.floor(value))
    while true do local replacement,count=string.gsub(result,"^(%-?%d+)(%d%d%d)","%1,%2");result=replacement;if count==0 then break end end
    return result
end
local function listens(self: any,signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
local function ready(self: any): boolean return self.profile.loaded==true and self.profile.failed~=true and not self.model.pending end
local function owned(self: any): any return if self.profile.loaded and type(self.profile.owned)=="table" then self.profile.owned else {} end
-- PF019: the detail panel's buttons speak the template key language (raised dark key + rim,
-- cobalt only for an equipped state, flat when it can't act); not a flat accent slab.
local function enabled(button: TextButton,value: boolean,theme: any,equippedState: boolean?)
    button.Active=value;button.Selectable=value;button.AutoButtonColor=false
    button.BackgroundColor3=if equippedState then Color3.fromHex("#3678ff") elseif value then Color3.fromHex("#2e2e2e") else Color3.fromHex("#222222")
    button.TextColor3=if value or equippedState then theme.Text else theme.MutedText
    local rim=button:FindFirstChild("PFKeyRim") or button:FindFirstChild("Border")
    if rim and rim:IsA("UIStroke") then rim.Color=if equippedState then Color3.fromHex("#9cc2ff") elseif value then Color3.fromHex("#5c5c5c") else Color3.fromHex("#3a3a3a") end
end
-- The Shop tabs players see: every category, minus Passes while CommerceFlags.passesVisible is off.
local SHOP_CATEGORIES=(function()
    local list={};for _,name in Commerce.shopCategories do if name~="Passes" or Flags.passesVisible then table.insert(list,name) end end
    return table.freeze(list)
end)()
local function category(self: any,scope: string): string return if scope=="Shop" then self.shopCategory else self.inventoryCategory end
local function motionOff(self: any): boolean return self.context.reducedMotion~=nil and self.context.reducedMotion() end
local NOTE_SECONDS=1.6 -- a failed buy's words stay on the key this long
local NOTE_HEX="#ff9a9a" -- the failure words' colour
local function pendingItem(item: any): boolean return item.pending==true or item.category=="Offer" end
-- PF020 (PF - 2): a pass-only cosmetic (the VIP Gilded set, nameplate styles) "Comes with" its pass.
local function passName(item: any): string?
    if not item.passOnly then return nil end
    local pass=Catalog.passById and Catalog.passById[item.passOnly]
    return if pass then pass.name else "a pass"
end
local function packOnlyLabel(item: any): string
    for _,pack in Catalog.premiumPacks do
        if table.find(pack.items,item.id)then return pack.name end
    end
    for _,pack in Catalog.earnedPacks or {} do if table.find(pack.items,item.id) then return pack.name end end -- PIVOT Glacier
    return "Pack exclusive"
end
-- PF017: a pack-only item links to its pack card (Discover › Offers) in the pack's
-- own colour instead of showing a dead price button. PIVOT Glacier: the earned pack has no card, only its colour.
local PACK_LINKS={pack_aurora={card="Pro",color="#72f4ce"},pack_starter={card="Starter",color="#ffae48"},pack_glacier={color="#a9d4f2"}}
local function packOf(item: any): any
    for _,pack in Catalog.premiumPacks do if table.find(pack.items,item.id) then return pack end end
    for _,pack in Catalog.earnedPacks or {} do if table.find(pack.items,item.id) then return pack end end
    return nil
end
-- PIVOT Glacier (Ashton: "they should be in their categories, but 1st"): an earned pack's items lead their own category
-- rows and tabs, and their key opens the Daily reward instead of a pack card.
local function earnedOf(item: any): any
    for _,pack in Catalog.earnedPacks or {} do if table.find(pack.items,item.id) then return pack end end
    return nil
end
-- an earned nameplate's well shows its plate (CosmeticPackArt.packs.<pack>.plate, 426x99) with your name on the glass,
-- the same seat as the Icicle board; the generic swatch stays under it, hidden
-- 2026-10-26 (Ashton dropped the Animated Nameplate pass): the Neon / Ember / Prism / Frost styles are Cobalt items, so their
-- cards show the same plate with no pack: a dark glass plate with your name in the item's style
local function plateArt(row: any,item: any,pack: any?)
    local okArt,PackArt=pcall(function() return require(Shared:FindFirstChild("CosmeticPackArt") :: any) end)
    local packArt=pack and okArt and type(PackArt)=="table" and (PackArt :: any).packs and (PackArt :: any).packs[pack.id]
    local art=row:FindFirstChild("Art",true)
    if not art or not art:IsA("ImageLabel") then return end
    local image=packArt and packArt.plate
    if not image and not item.style then return end
    local plate=Instance.new("ImageLabel");plate.Name="PFPlate";plate.BackgroundTransparency=1;plate.Image=image or ""
    if not image then
        plate.BackgroundTransparency=.1;plate.BackgroundColor3=Color3.fromHex("#0d1018")
        local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(.2,0);corner.Parent=plate
        local rim=Instance.new("UIStroke");rim.Color=Color3.fromHex("#3a4356");rim.Thickness=1;rim.Parent=plate
    end
    plate.ScaleType=Enum.ScaleType.Fit;plate.ResampleMode=Enum.ResamplerMode.Pixelated;plate.AnchorPoint=Vector2.new(.5,.5)
    plate.Position=art.Position;plate.Size=art.Size;plate.ZIndex=art.ZIndex+1
    if art.AnchorPoint~=Vector2.new(.5,.5) then plate.Position=art.Position+UDim2.fromScale(art.Size.X.Scale*(.5-art.AnchorPoint.X),art.Size.Y.Scale*(.5-art.AnchorPoint.Y)) end
    local aspect=Instance.new("UIAspectRatioConstraint");aspect.AspectRatio=426/99;aspect.Parent=plate
    local name=Instance.new("TextLabel");name.Name="Name";name.BackgroundTransparency=1;name.TextScaled=true;name.TextColor3=Color3.new(1,1,1)
    name.FontFace=Font.new("rbxasset://fonts/families/Ubuntu.json",Enum.FontWeight.Bold);name.Position=UDim2.fromScale(.14,.17);name.Size=UDim2.fromScale(.72,.5);name.ZIndex=plate.ZIndex+1
    local me=game:GetService("Players").LocalPlayer;name.Text=if me then me.Name else "Player"
    local gradient=Instance.new("UIGradient");gradient.Name="PFStyle";gradient.Rotation=12;gradient.Parent=name
    local okStyle,Style=pcall(require,script.Parent.NameplateStyle)
    if okStyle and type(Style)=="table" and (Style :: any).apply then (Style :: any).apply(gradient,item.style or "icicle") end
    name.Parent=plate;plate.Parent=art.Parent;art.Visible=false
end
local function openDaily()
    local ok,View=pcall(require,script.Parent.DailyView)
    if ok and type(View)=="table" and (View :: any).openStreak then (View :: any).openStreak() end
end
-- PF015 authors both pages' category tabs inside their header rows
-- (Header.PFTabs), and the Inventory grid + identity sidebar inside one body
-- row (PFBody); before that install they sat at the page root.
-- PF - 1 2026-10-25 (Ashton: the Shop's title + categories up top, one bar): the Shop's Header lives in AtlasMenu.PFShopTop.Row
-- now (author-pf1-shop-onebar); the content keeps an ObjectValue PFHeaderRef to it.
local function headerOf(ui: any): any
    local header=ui:FindFirstChild("Header");if header then return header end
    local ref=ui:FindFirstChild("PFHeaderRef");return ref and ref.Value
end
local function categoriesOf(ui: any): any return ui:FindFirstChild("Categories") or headerOf(ui):FindFirstChild("Categories",true) end
local function scrollOf(ui: any): any return ui:FindFirstChild("Scroll") or ui.PFBody.Scroll end
local function itemById(id: string?): any return if id then Catalog.byId[id] or Catalog.premiumById[id] else nil end
-- PF019: kit cards (Shop items, bundles) keep their content under PFCardBody.
local function hostOf(card: any): any
    local body=card:FindFirstChild("PFCardBody")
    return if body then (body:FindFirstChild("PFContent") or body) else card
end
-- PF019 Inventory: a slot tile opens its category; an empty category points to the Shop.
local SLOT_TABS={Skin={"Skins",nil},Flag={"Profile","Flag"},Crown={"Profile","Crown"},Frame={"Profile","Frame"},Banner={"Profile","Banner"},VFX={"Effects","Global"},
    Buildings={"Buildings",nil},Missiles={"Missiles",nil}} -- PF023 P1 (PF - 1): the plate chips and Profile slots
local SLOT_DEFAULTS={Skin="Classic"}
local EMPTY_TITLES={All="Nothing here yet",Bundles="No bundles yet",Profile="No profile items yet",Effects="No effects yet",Buildings="No building looks yet",
    Skins="No skins yet",Missiles="No Nuke FX yet"}
local STRIP_EFFECTS={vfx_aurora="aurora",vfx_ember="ember"}
-- M2 set colours for the Cobalt tiers: cobalt, and gold for the Vault.
local COBALT_SETS={"#7fb2ff","#7fb2ff","#8fc1ff","#a8ccff","#ffd36a"} -- Cobalt v3 (UI review 2026-10-26): lighter up the tiers
-- PF017-B: a bundle template's colours (AtlasBundleModel.look), the same paint the
-- authoring helper applies; colours only, the template's layout is authored.
-- PF019: on the kit the bundle colour is the card's set colour (hover border + glow).
local function paintBundle(card: any,look: any)
    local accent,highlight=Color3.fromHex(look.accent),Color3.fromHex(look.highlight)
    local host=hostOf(card)
    if host:FindFirstChild("PFStroke") then host.PFStroke.Color=accent end
    card:SetAttribute("PFCardSet",accent)
    host.PFGlow.BackgroundColor3=accent;host.PFAccent.PFGradient.Color=ColorSequence.new(accent,highlight)
    host.Badge.BackgroundColor3=highlight
    local layer=host.Purchase.BundleBuy
    layer.Base.Tone.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHex(look.tone[1])),ColorSequenceKeypoint.new(.55,Color3.fromHex(look.tone[2])),ColorSequenceKeypoint.new(1,Color3.fromHex(look.tone[3]))})
    layer.Base.Rim.Color=Color3.fromHex(look.rim);layer.Shimmer.BackgroundColor3=Color3.fromHex(look.shine)
    layer.PackPrice.Shade.Color=Color3.fromHex(look.shade);layer.PriceRow.Digits.Shade.Color=Color3.fromHex(look.shade)
end
function Page.new(pageRoot: Frame,context: any): any
    local inventoryRoot=assert(context.inventoryRoot,"Atlas commerce needs Inventory root")
    local self=setmetatable({shopRoot=pageRoot,inventoryRoot=inventoryRoot,context=context,
        shop=assert(pageRoot:FindFirstChild("AtlasCommerceContent")),inventory=assert(inventoryRoot:FindFirstChild("AtlasCommerceContent")),
        page="Shop",visible=false,shopCategory="All",inventoryCategory="All",filters={Shop="All",Inventory="All"},
        connections={},rowConnections={},rows={Shop={},Inventory={}},sections={},model={},profile={},destroyed=false},Page)
    self.theme=assert(context.theme);self.identity=self.inventory:FindFirstChild("Identity") or self.inventory.PFBody.Identity
    Typography.applyTree(self.shop);Typography.applyTree(self.inventory)
    Typography.apply(self.identity.Detail.Title,"Heading")
    Typography.apply(self.identity.Detail.Description,"Body");Typography.apply(self.identity.Detail.Status,"Label")
    for _,ui in {self.shop,self.inventory} do
        local template=hostOf(ui.Templates.ItemCard);Typography.apply(template.Kind,"Label");Typography.apply(template.State,"Label")
    end
    Typography.apply(headerOf(self.shop).Wallet.Caption,"Label")
    for _,name in {"Starter","Pro"} do Typography.apply(self.shop.Scroll.Offers[name].Footer,"Label") end
    for _,card in self.shop.Scroll.Passes.Cards:GetChildren() do if card:IsA("GuiObject") then
        Typography.apply(card.Kind,"Label");Typography.apply(card.State,"Label")
    end end
    for index=1,5 do Typography.apply(hostOf(self.shop.Scroll.Currency.Packs["Pack"..index]).Bonus,"Label") end
    assert(self.shop:FindFirstChild("Secondary") and self.shop.Templates:FindFirstChild("Section"),"Install PF003 commerce migration first")
    self.aurora=AuroraPresentation.new(self.shop,context)
    -- PF017-B: the bundles are an authored Skins-style row (Scroll.PFBundles,
    -- author-pf017-bundles); this page binds their copy, member art, owned marks and
    -- purchase. Optional, so places without the row (and fixture runners) keep the
    -- catalog cards.
    local bundles=self.shop.Scroll:FindFirstChild("PFBundles")
    if bundles then
        self.bundleCards=bundles;self.bundleModel=require(script.Parent.AtlasBundleModel) :: any
        local strip=bundles:FindFirstChild("Scroll") or bundles;self.bundleStrip=strip
        -- The row grows with the catalog: a bundle added after the helper ran is a
        -- copy of the authored PFTemplate, painted in its own colours.
        local spare=strip:FindFirstChild("PFTemplate")
        -- PF020 G7 (PF - 3): a bundle with more members than the template has tiles waits for its own
        -- authored card (the Tempest Bundle has five; a 2x2 copy would hide one).
        local tiles=0
        if spare then for _,tile in hostOf(spare).Members:GetChildren() do if string.match(tile.Name,"^Member%d+$") then tiles+=1 end end end
        for index,item in self.bundleModel.bundles() do
            if spare and not strip:FindFirstChild(item.id) and #item.items<=tiles then
                local card=spare:Clone();card.Name=item.id;card.LayoutOrder=index;card.Visible=true
                paintBundle(card,self.bundleModel.look(item.id));card.Parent=strip
            end
        end
        if bundles:FindFirstChild("Left") and bundles:FindFirstChild("Right") then
            -- Same paging as the catalog rows' ‹ › buttons; touch drags the row natively.
            local function move(direction: number)
                strip.CanvasPosition=Vector2.new(math.clamp(strip.CanvasPosition.X+direction*math.max(240,strip.AbsoluteSize.X*.8),0,math.max(0,strip.AbsoluteCanvasSize.X-strip.AbsoluteWindowSize.X)),0)
            end
            listens(self,bundles.Left.Activated,function()move(-1)end)
            listens(self,bundles.Right.Activated,function()move(1)end)
        end
        local BundleButton=require(script.Parent.BundleShopButton) :: any
        self.bundleButtons={}
        -- UI review 2026-10-26 Bundles v2 (author-pf1-bundles-v2): like the Cobalt tiers, the hovered card grows from its centre
        -- (PFHover 1.02) and the others ease to .985; no lift
        local bundleScales={}
        for _,card in strip:GetChildren() do local s=card:FindFirstChild("PFHover");if s and s:IsA("UIScale") then bundleScales[card]=s end end
        local function bundleHover(hot: Instance?)
            if motionOff(self) and hot then return end
            local quick,Tween=TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),game:GetService("TweenService")
            for card,s in bundleScales do Tween:Create(s,quick,{Scale=if hot==nil then 1 elseif card==hot then 1.02 else .985}):Play() end
        end
        for _,card in strip:GetChildren() do
            local item=Catalog.byId[card.Name];local host=hostOf(card)
            if item and item.category=="Bundle" and host:FindFirstChild("Purchase") then
                listens(self,host.Purchase.Activated,function()self:purchaseItem(item)end)
                -- PF017: the shared pack-button language (shimmer, locked veil, price label).
                local button=BundleButton.new(host,context,context.menuRoot or pageRoot.Parent)
                if button then table.insert(self.bundleButtons,button) end
                -- PF019: the bundle card on the kit (its colour is the set colour).
                if context.cardKit and host~=card then
                    local look=self.bundleModel.look(item.id)
                    -- PF020 G7 (PF - 3): a storm card's wash brightens and its key's bolt lights while hot.
                    local wash,bolt=host:FindFirstChild("PFWash"),host.Purchase:FindFirstChild("PFBolt",true)
                    local storm=if wash or bolt then function(_: any,kit: any) self:stormHover(wash,bolt,kit.lift>0 or kit.ring==0) end else nil
                    local handle=context.cardKit:bind(card,{set=Color3.fromHex(look.accent),targets={host.Purchase},onLook=storm})
                    if bundleScales[card] and handle and handle.style then handle.style.lift=0 end
                end
                if bundleScales[card] then
                    for _,target in {card,host.Purchase} do
                        listens(self,target.MouseEnter,function() if Input.PreferredInput~=Enum.PreferredInput.Touch then bundleHover(card) end end)
                        listens(self,target.MouseLeave,function() bundleHover(nil) end)
                    end
                end
            end
        end
    end
    -- PF025 (PF - 1): the pack + bundle cards' scenes, price language, hover and owned looks (content only; a place
    -- without tools/atlas/author-pf025-shop-cards is untouched)
    pcall(function() (require(script.Parent.PF025ShopCards) :: any).bind(pageRoot,self.shop) end)
    -- PF016 (PF - 2) decides whether its authored Forge layer is installed.
    if ForgePresentation.installed and ForgePresentation.installed(self.shop.Scroll.Offers.Starter) then
        self.forge=ForgePresentation.new(self.shop,context)
    end
    self:closeDetail(false)
    -- PF019 M3: the authored top bar (author-pf019-topbar) slides its tab pill, counts Cobalt up,
    -- opens Cobalt from "+" and cycles tabs with LB / RB.
    if TopBar.installed(headerOf(self.shop)) then
        self.topBar=TopBar.new(headerOf(self.shop),{tabs=categoriesOf(self.shop),reduced=context.reducedMotion,
            onAdd=function() if self.visible and self.page=="Shop" then self:selectCategory("Shop","Currency") end end,
            onCycle=function(direction: number)
                if not self.visible or self.page~="Shop" then return end
                local list=SHOP_CATEGORIES;local index=table.find(list,self.shopCategory) or 1
                local nextName=list[(index-1+direction)%#list+1];self:selectCategory("Shop",nextName)
                if Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=categoriesOf(self.shop)[nextName] end
            end})
    end
    -- the Inventory's Header may live in AtlasMenu.PFPageTop.Row (author-pf1-inventory-onebar; the content's PFHeaderRef)
    if TopBar.installed(headerOf(self.inventory)) then
        self.invBar=TopBar.new(headerOf(self.inventory),{tabs=categoriesOf(self.inventory),reduced=context.reducedMotion,
            onCycle=function(direction: number)
                if not self.visible or self.page~="Inventory" then return end
                local list=Commerce.inventoryCategories;local index=table.find(list,self.inventoryCategory) or 1
                local nextName=list[(index-1+direction)%#list+1];self:selectCategory("Inventory",nextName)
                if Input.PreferredInput==Enum.PreferredInput.Gamepad then Gui.SelectedObject=categoriesOf(self.inventory)[nextName] end
            end})
    end
    listens(self,headerOf(self.shop).NavigateInventory.Activated,function()context.navigate("Inventory")end)
    listens(self,headerOf(self.inventory).NavigateShop.Activated,function()context.navigate("Shop")end)
    for _,scope in {"Shop","Inventory"} do
        local ui=if scope=="Shop" then self.shop else self.inventory
        local categories=if scope=="Shop" then SHOP_CATEGORIES else Commerce.inventoryCategories
        for _,name in categories do
            listens(self,categoriesOf(ui)[name].Activated,function()self:selectCategory(scope,name)end)
        end
        for _,button in ui.Secondary:GetChildren() do
            if not button:IsA("TextButton") then continue end
            local parent,filter=string.match(button.Name,"^(%w+)_(%w+)$")
            if parent and filter then listens(self,button.Activated,function()
                if category(self,scope)~=parent then return end
                self.filters[scope]=Commerce.validFilter(parent,filter);self.selectedId=nil
                scrollOf(ui).CanvasPosition=Vector2.zero;self:refreshRows();self:layout()
            end) end
        end
    end
    for _,name in {"Starter","Pro"} do
        local card=self.shop.Scroll.Offers[name]
        listens(self,card.Purchase.Activated,function()
            if name=="Pro" then self:purchaseItem(Catalog.premiumPacks[1])
            elseif name=="Starter" and Catalog.premiumById.pack_starter then self:purchaseItem(Catalog.premiumById.pack_starter) end
        end)
    end
    -- UI review 2026-10-26 Cobalt v3 (author-pf1-cobalt-v3): the hovered tier grows from its centre (PFHover 1.02), the
    -- others ease to .985; no lift (the kit's 4px rise would move it).
    local tierScales={}
    for index=1,5 do local s=self.shop.Scroll.Currency.Packs["Pack"..index]:FindFirstChild("PFHover");if s then tierScales[index]=s end end
    local function tierHover(hot: number?)
        if motionOff(self) and hot then return end
        local quick,Tween=TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),game:GetService("TweenService")
        for index,s in tierScales do Tween:Create(s,quick,{Scale=if hot==nil then 1 elseif index==hot then 1.02 else .985}):Play() end
    end
    for index=1,5 do
        local card=self.shop.Scroll.Currency.Packs["Pack"..index]
        if context.cardKit and card:FindFirstChild("PFCardBody") then
            local host=hostOf(card);local set=Color3.fromHex(COBALT_SETS[index])
            if host:FindFirstChild("Kind") then host.Kind.TextColor3=set end
            local art=ShopItemArt.attach(card,"cobalt",{tier=index})
            local handle=context.cardKit:bind(card,{set=set,targets={host.Purchase},idle=art.idle,onLook=art.onLook})
            if tierScales[index] and handle and handle.style then handle.style.lift=0 end
        end
        if tierScales[index] then
            for _,target in {card,hostOf(card).Purchase} do
                listens(self,target.MouseEnter,function() if Input.PreferredInput~=Enum.PreferredInput.Touch then tierHover(index) end end)
                listens(self,target.MouseLeave,function() tierHover(nil) end) -- card -> its key fires leave then enter: it settles hot
            end
        end
        listens(self,hostOf(card).Purchase.Activated,function()
            local item=table.clone(Catalog.currencyPacks[index]);item.category="Currency";self:purchaseItem(item)
        end)
    end
    -- Cobalt v3: the 2x Cobalt strip under the tiers buys the pass
    local x2=self.shop.Scroll.Currency:FindFirstChild("PF2xStrip")
    if x2 and Catalog.passById and Catalog.passById.pass_2x_cobalt then
        listens(self,x2.Buy.Activated,function()self:purchaseItem(Catalog.passById.pass_2x_cobalt)end)
    end
    listens(self,self.shop.Scroll.Passes.Cards.Aurora.Purchase.Activated,function()self:purchaseItem(Catalog.premiumPacks[1])end)
    -- PF020 G6 (PF - 2): the authored Passes rows (author-pf020-passes): the VIP hero band and the
    -- three pass cards. Optional, so places without them (and fixture runners) keep the PF015 section.
    local g6vip,g6cards=self.shop.Scroll:FindFirstChild("PFPassesVip"),self.shop.Scroll:FindFirstChild("PFPassesCards")
    if g6vip and g6cards then
        self.g6={vip=g6vip,cards=g6cards}
        listens(self,g6vip.Band.Buy.Activated,function()self:purchaseItem(Catalog.passById.pass_vip)end)
        for _,card in g6cards:GetChildren() do
            local pass=Catalog.passById[card:GetAttribute("PassId")]
            if not pass then continue end
            listens(self,card.Buy.Activated,function()self:purchaseItem(pass)end)
            listens(self,card.Action.Activated,function()self:passAction(pass)end)
        end
    end
    listens(self,self.identity.Detail.Action.Activated,function()self:equipSelected()end)
    listens(self,self.identity.Detail.Default.Activated,function()self:resetTarget(false)end)
    listens(self,self.identity.Detail.Inherit.Activated,function()self:resetTarget(true)end)
    -- PF019 "Your look": the slot tiles open their category; the empty state visits the Shop.
    local slotTiles=self.identity:FindFirstChild("PFSlots")
    if slotTiles then for _,tile in slotTiles:GetChildren() do
        if tile:IsA("TextButton") then listens(self,tile.Activated,function() self:openSlot(tile:GetAttribute("Category")) end) end
    end end
    local emptyPanel=scrollOf(self.inventory):FindFirstChild("PFEmpty")
    if emptyPanel then listens(self,emptyPanel.Go.Activated,function() self:visitShop() end) end
    listens(self,Gui:GetPropertyChangedSignal("SelectedObject"),function()self:focusChanged()end)
    listens(self,Input:GetPropertyChangedSignal("PreferredInput"),function()
        if self.visible and Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive() end
    end)
    self:update(if context.getCommerceState then context.getCommerceState() else {})
    return self
end
function Page:selectCategory(scope: string,name: string)
    if scope=="Shop" then self.shopCategory=name else self.inventoryCategory=name;self.selectedId=nil end
    self.filters[scope]=Commerce.validFilter(name,nil)
    local ui=if scope=="Shop" then self.shop else self.inventory
    scrollOf(ui).CanvasPosition=Vector2.zero;ui.Secondary.CanvasPosition=Vector2.zero
    self:refreshRows();self:layout()
end
function Page:invoke(name: string,...: any)
    local callback=self.context[name]
    if type(callback)~="function" then self.localMessage="This action is unavailable.";self:refreshStatus();return end
    local ok,result=pcall(callback,...)
    if not ok then warn("[Atlas commerce] "..name..": "..tostring(result));self.localMessage="That request could not be sent. Try again."
    elseif type(result)=="table" and type(result.message)=="string" then self.localMessage=result.message else self.localMessage=nil end
    if self.context.getCommerceState then self:update(self.context.getCommerceState()) else self:refreshStatus() end
end
function Page:update(model: any)
    if self.destroyed then return end
    self.model=if type(model)=="table" then model else {}
    self.profile=if type(self.model.profile)=="table" then self.model.profile else {}
    self.productInfo=if type(self.model.productInfo)=="table" then self.model.productInfo else {}
    self:resolveBuy()
    if self.model.page=="Shop" or self.model.page=="Inventory" then self:setPage(self.model.page) end
    self:refreshRows();self:refreshCurrency();self:refreshPasses();self:refreshProfile();self:refreshStatus();self:layout()
    if self.forge then self.forge:refresh()end
end
function Page:setPage(name: string)
    if name~="Shop" and name~="Inventory" then return end
    self.page=name;self.shopRoot.Visible=self.visible and name=="Shop";self.inventoryRoot.Visible=self.visible and name=="Inventory"
    self.aurora:setVisible(self.visible and name=="Shop")
    if self.topBar then self.topBar:setVisible(self.visible and name=="Shop") end
    if self.invBar then self.invBar:setVisible(self.visible and name=="Inventory") end
    for _,button in self.bundleButtons or {} do button:setVisible(self.visible and name=="Shop") end
    if self.forge then self.forge:setVisible(self.visible and name=="Shop")end
end
-- PF031: the menu names the tab it shows (Shop or Inventory). Showing a tab never rebuilds the cards: they repaint in
-- update, when the shop's data changes. Only the pass cards' keys read the menu's way back live, so they repaint here.
function Page:setVisible(value: boolean,page: string?)
    if self.destroyed then return end
    if page=="Shop" or page=="Inventory" then self.page=page end
    local changed=self.visible~=value;self.visible=value;self:setPage(self.page)
    if value then
        if self.page=="Shop" then self:refreshG6() end
        self:layout();if changed and self.context.refreshCommerce then self.context.refreshCommerce()end
        if changed and Input.PreferredInput==Enum.PreferredInput.Gamepad then self:focusActive()end end
end
function Page:status(): string
    if self.profile.failed then return "Inventory unavailable. Return to this page to retry." end
    if not self.profile.loaded then return "Loading your inventory…" end
    if self.model.pending then return "Updating your inventory…" end
    return self.localMessage or self.model.message or ""
end
function Page:refreshStatus()
    self.shop.Status.Text=self:status();self.inventory.Status.Text=self:status()
    local walletText=if self.profile.failed then "Unavailable" elseif self.profile.loaded then number(self.profile.balance) else "Loading…"
    if self.topBar then self.topBar:setBalance(if self.profile.loaded and not self.profile.failed then self.profile.balance else nil,walletText)
    else headerOf(self.shop).Wallet.Amount.Text=walletText end
    headerOf(self.shop).Wallet.Caption.Text=Catalog.currencyName
    local count=0;for id,value in owned(self) do if value and Catalog.byId[id] and Catalog.byId[id].category~="Bundle" then count+=1 end end
    headerOf(self.inventory).OwnedCount.Text=if self.profile.failed then "Unavailable" elseif self.profile.loaded then number(count).." owned" else "Loading…"
    -- PF019 M3 bar: the owned count rides on the "All items" tab (the chip is hidden; phones need the room)
    local allTab=self.invBar and categoriesOf(self.inventory):FindFirstChild("All")
    if allTab then allTab.Text=if self.profile.loaded and not self.profile.failed then "All items · "..number(count) else "All items" end
end
function Page:isEquipped(item: any,scope: string): boolean
    local look=self.profile.equipped or {}
    if item.category=="VFX" and category(self,scope)=="Effects" then local target=self.filters[scope]
        return if target=="Global" then look.VFX==item.id else (look.effectTargets or {})[target]==item.id end
    return look[item.category]==item.id
end
-- Return a canonical price and state; never infer Roblox prices from setup targets.
function Page:purchaseState(item: any): (boolean,string,string,string)
    local robux=item.category=="Currency" or item.category=="PremiumPack" or item.category=="Offer" or item.category=="Pass"
    local currency=if robux then "Robux" else "Cobalt"
    if pendingItem(item) then return false,"--",currency,"Not available" end
    -- Free catalog cosmetics are owned by everyone (Catalog.defaultOwned), even before the profile loads.
    local default=item.price==0 and not item.packOnly and not item.passOnly and item.category~="Bundle" and Catalog.byId[item.id]~=nil
    if item.category~="Currency" and (owned(self)[item.id] or default) then return false,if self:isEquipped(item,"Shop") then "Equipped" else "Owned",currency,"Owned" end
    local price=nil
    if robux then
        local info=self.productInfo[item.id]
        local id=if item.category=="PremiumPack" or item.category=="Pass" then item.passId else item.productId
        if id and id>0 and info and type(info.PriceInRobux)=="number" and info.PriceInRobux>=0 and info.IsForSale==true then price=info.PriceInRobux end
    elseif not item.packOnly and not item.passOnly then
        local missing;price,missing=Catalog.bundlePrice(item,owned(self))
        if #missing==0 and self.profile.loaded then return false,"Owned",currency,"Owned" end
    end
    local state=if item.packOnly then packOnlyLabel(item) elseif item.passOnly then "Comes with "..(passName(item) or "a pass") elseif self.profile.failed then "Unavailable" elseif not self.profile.loaded then "Loading" elseif self.model.pending then "Updating" elseif price==nil then "Not available" elseif robux and Run:IsStudio() then "Studio preview" elseif not robux and (self.profile.balance or 0)<price then "Need Cobalt" else "Available"
    return ready(self) and price~=nil and not item.packOnly and not item.passOnly and (if robux then not Run:IsStudio() else (self.profile.balance or 0)>=price),number(price),currency,state
end
-- Cards whose price button is painted by an authored layer (PF016/PF017 pack and bundle
-- buttons): the layer's PackPrice draws the price and its states.
local function themedButton(card: any): boolean
    local parent=card.Parent
    local bundle=parent~=nil and (parent.Name=="PFBundles" or (parent.Parent~=nil and parent.Parent.Name=="PFBundles"))
    return parent~=nil and (parent.Name=="Offers" or bundle) and hostOf(card).Purchase:FindFirstChild("PackPrice",true)~=nil
end
-- PF017: catalog buy buttons speak PF - 2's PF017-A Cobalt language (the CobaltBuy layer
-- from author-pf017-catalog-cards): crystal + digits hugging for a price, words otherwise,
-- the locked veil when it can't be bought. Static: no idle shimmer across a whole grid.
local function paintCobaltButton(button: any,canBuy: boolean,price: string): boolean
    local layer=button:FindFirstChild("CobaltBuy");if not layer then return false end
    local digits=string.match(price,"^%d[%d,]*$")~=nil
    button.BackgroundTransparency=1;button.Amount.Visible=false;button.PriceIcon.Visible=false
    layer.PriceRow.Visible=digits;layer.PackPrice.Visible=not digits
    if digits then layer.PriceRow.Digits.Text=price else layer.PackPrice.Text=price end
    layer.Locked.Visible=not canBuy
    return true
end
-- PF019 M2: the item card's ONE action on its CobaltBuy key (author-pf019-cards). Colour and
-- words only; ShopCardModel words it, purchaseState decides what can really be bought.
local ACTION_LOOKS={
    buy={tone={"#3a3a3a","#2e2e2e","#252525"},rim="#5c5c5c",text="#f2f2f2"},   -- raised + gem
    equip={tone={"#3a3a3a","#2e2e2e","#252525"},rim="#5c5c5c",text="#f2f2f2"}, -- raised
    equipped={tone={"#4a8cff","#3678ff","#2a5fd6"},rim="#9cc2ff",text="#ffffff"}, -- cobalt
    short={tone={"#262626","#242424","#222222"},rim="#3d3d3d",text="#8c8c8c"},  -- dim, still live
    owned={tone={"#262626","#242424","#222222"},rim="#3d3d3d",text="#8c8c8c"},
    wait={tone={"#262626","#242424","#222222"},rim="#3d3d3d",text="#8c8c8c"},
    -- PF021 A: a failed buy's note (Need Cobalt / Try again): a red rim on a red-dark key
    note={tone={"#33201f","#2a1d1d","#221717"},rim="#e0605a",text=NOTE_HEX,rimThickness=1.5}}
local function paintAction(button: any,action: any)
    local layer=button:FindFirstChild("CobaltBuy");if not layer then return end
    local look=ACTION_LOOKS[action.kind] or ACTION_LOOKS.wait
    button.Visible=true;button.BackgroundTransparency=1;button.AutoButtonColor=false
    button.Active=action.active;button.Selectable=action.active
    button.Amount.Visible=false;button.PriceIcon.Visible=false
    layer.Base.Tone.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHex(look.tone[1])),ColorSequenceKeypoint.new(.55,Color3.fromHex(look.tone[2])),ColorSequenceKeypoint.new(1,Color3.fromHex(look.tone[3]))})
    layer.Base.Rim.Color=Color3.fromHex(look.rim);layer.Base.Rim.Thickness=look.rimThickness or 1;layer.Locked.Visible=false
    -- A price is gem + digits hugging as one unit; plain words (Equip, Equipped) fill the key.
    -- "Need N more" reads "Need ◆N more" in that same row (PF - 1 2026-10-25, Ashton: "the 'need 275 more' text looks like
    -- its lacking a cobalt icon"): PriceRow's Lead / Tail words around the gem; older keys keep PFShort (gem at the left).
    local row=layer.PriceRow
    local lead,tail=row:FindFirstChild("Lead"),row:FindFirstChild("Tail")
    local inline=action.kind=="short" and lead~=nil and tail~=nil
    local short=layer:FindFirstChild("PFShort")
    local shortShown=action.kind=="short" and short~=nil and not inline
    if short then short.Visible=shortShown end
    if lead then lead.Visible=inline;lead.TextColor3=Color3.fromHex(look.text) end
    if tail then tail.Visible=inline;tail.TextColor3=Color3.fromHex(look.text) end
    row.Visible=(action.gem or inline) and not shortShown;layer.PackPrice.Visible=not (action.gem or inline)
    row.Crystal.ImageTransparency=if action.kind=="buy" then 0 elseif inline then .2 else .45
    local words=if shortShown then short.Words elseif action.gem or inline then row.Digits else layer.PackPrice
    words.Text=if inline then string.match(action.text,"^Need (.-) more$") or action.text else action.text
    words.TextColor3=Color3.fromHex(look.text)
    button:SetAttribute("PFAction",action.kind)
end
function Page:bindPurchase(card: any,item: any)
    local canBuy,price,currency,state=self:purchaseState(item)
    card.Active=false;card.Selectable=false;card.AutoButtonColor=false
    local host=hostOf(card)
    local button=host.Purchase
    button.Visible=true;button.Active=canBuy;button.Selectable=canBuy;button.AutoButtonColor=canBuy
    button.BackgroundColor3=if currency=="Robux" then Color3.fromHex("258447") else Color3.fromHex("2460CA")
    -- PF016 paints the two Offers cards' price buttons (ForgeBuy/AuroraBuy layers).
    button.BackgroundTransparency=if themedButton(card) then 1 elseif canBuy then 0 else .45
    button:SetAttribute("PurchaseState",state);button:SetAttribute("Currency",currency);button:SetAttribute("ItemId",item.id)
    button.Amount.Text=price;button.Amount.TextColor3=if canBuy then self.theme.Text else self.theme.MutedText
    button.PriceIcon.Image=if currency=="Robux" then ROBUX_ICON else COBALT_ICON
    button.PriceIcon.Visible=price~="Owned" and price~="Equipped"
    -- PF017: the pack cards' PF016 layer draws the price (inline Robux glyph) and its states.
    if themedButton(card) then
        button:SetAttribute("PriceText",price);button.Amount.Visible=false;button.PriceIcon.Visible=false
    else
        paintCobaltButton(button,canBuy,price)
    end
    -- PF019 M7: the Cobalt tier keys carry PF - 2's Robux glyph + price label (PFRobuxHost).
    local robuxHost=button:FindFirstChild("PFRobuxHost")
    if robuxHost and robuxHost:FindFirstChild("PFRobuxPrice") then
        button.Amount.Visible=false;button.PriceIcon.Visible=false
        -- PF - 2's label: live digits with the glyph, state words, or the catalog price as a preview (never a bare dash)
        ShopItemArt.paintRobux(robuxHost,ShopItemArt.robuxLabel({priceText=price,purchaseState=state,targetRobux=item.targetRobux}))
    end
    if host:FindFirstChild("State") then host.State.Text=if state=="Available" or state=="Owned" then "" else state end
    if host:FindFirstChild("Price") then host.Price.Visible=false end
    if host:FindFirstChild("Arrow") then host.Arrow.Visible=false end
end
-- PF017: pack-only items. The authored PFPackLink (author-pf017-pack-links) replaces
-- the price button: "In <Pack> ›" in the pack's colour, or "✓ Owned" once granted.
-- Content and colour only; its box is authored in Templates.ItemCard.
function Page:bindPackLink(card: any,item: any): any?
    local link=card:FindFirstChild("PFPackLink");local pack=packOf(item)
    if not link or not pack then return nil end
    local _,price=self:purchaseState(item)
    local owned=price=="Owned" or price=="Equipped"
    local entry=PACK_LINKS[pack.id]
    local color=if owned then self.theme.Positive elseif entry then Color3.fromHex(entry.color) else self.theme.Accent
    card.Purchase.Visible=false;link.Visible=true
    if card:FindFirstChild("State") then card.State.Text="" end
    link.Text=if owned then "✓ "..price else "In "..pack.name.." ›"
    link.TextColor3=color;link.BackgroundColor3=color
    local stroke=link:FindFirstChild("PFLinkStroke");if stroke then stroke.Color=color;stroke.Transparency=if owned then .7 else .35 end
    link.Active=not owned;link.Selectable=not owned;link.AutoButtonColor=false
    return link
end
-- PF019 M2: word and paint a kit card's one action (ShopCardModel); returns the action.
function Page:bindAction(row: any,item: any,body: any): any
    local canBuy,_,_,state=self:purchaseState(item)
    local mine=owned(self)
    local default=item.price==0 and not item.packOnly and not item.passOnly and Catalog.byId[item.id]~=nil
    local isOwned=mine[item.id]==true or default
    local price=if item.packOnly or item.passOnly then nil else (Catalog.bundlePrice(item,mine))
    local action=CardModel.action({owned=isOwned,equipped=isOwned and self:isEquipped(item,"Shop"),canEquip=Catalog.slots[item.category]==true and mine[item.id]==true,
        ready=ready(self),packOnly=item.packOnly==true,passName=passName(item),price=price,balance=self.profile.balance,canBuy=canBuy,state=state})
    local link=body:FindFirstChild("PFPackLink");local pack=packOf(item)
    if action.kind=="pack" and link and pack then
        local entry=PACK_LINKS[pack.id];local color=if entry then Color3.fromHex(entry.color) else self.theme.Accent
        body.Purchase.Visible=false;body.Purchase:SetAttribute("PFAction","pack")
        local earned=earnedOf(item) -- PIVOT Glacier: earned on a daily day, never sold
        link.Visible=true;link.Text=if earned then "Day "..tostring(earned.daily).." daily ›" else action.text;link.TextColor3=color;link.BackgroundColor3=color
        local stroke=link:FindFirstChild("PFLinkStroke");if stroke then stroke.Color=color;stroke.Transparency=.2 end
        link.Active=true;link.Selectable=true;link.AutoButtonColor=false
    else
        if link then link.Visible=false;link.Active=false;link.Selectable=false end
        paintAction(body.Purchase,action)
    end
    body.Purchase:SetAttribute("PurchaseState",state);body.Purchase:SetAttribute("ItemId",item.id)
    return action
end
-- Discover opens with the pack cards at the top, so selecting it brings the pack into view.
function Page:showPack(pack: any)
    if not pack or self.destroyed then return end
    self:selectCategory("Shop","All")
    local entry=PACK_LINKS[pack.id];local card=entry and entry.card and self.shop.Scroll.Offers:FindFirstChild(entry.card)
    if card and Input.PreferredInput==Enum.PreferredInput.Gamepad and card.Purchase.Selectable then Gui.SelectedObject=card.Purchase end
end
-- PF019 M2: the card's one action. Buy goes through purchaseItem (and its own guard); short on
-- Cobalt opens the Cobalt tab; Equip equips from the Shop (global, or the Effects tab's target).
function Page:cardAction(item: any,button: any)
    local kind=button:GetAttribute("PFAction")
    if kind=="buy" then self:purchaseItem(item)
    elseif kind=="short" then if self.visible and self.page=="Shop" then self:selectCategory("Shop","Currency") end
    elseif kind=="equip" then self:equipItem(item) end
end
function Page:equipItem(item: any)
    if not self.visible or self.page~="Shop" or not ready(self) or not owned(self)[item.id] or not Catalog.slots[item.category] then return end
    if self:isEquipped(item,"Shop") then return end
    local target=if item.category=="VFX" and self.shopCategory=="Effects" and self.filters.Shop~="Global" then self.filters.Shop else nil
    self:invoke("equip",item.id,item.category,target)
end
function Page:purchaseItem(item: any)
    if not self.visible or self.page~="Shop" or not self:purchaseState(item) then return end
    -- PF019 Cobalt buy: a Cobalt-priced buy is followed to the server's answer (the key's dots,
    -- then its success or failure look). Robux prompts keep Roblox's own flow.
    if item.category~="Currency" and item.category~="PremiumPack" and item.category~="Offer" and item.category~="Pass" then
        local price=(Catalog.bundlePrice(item,owned(self)))
        self.buy=BuyModel.start(item.id,price,self.profile.balance);self.buyResult=nil
        self:logBuy("pending",item.id)
    end
    -- Only the dedicated price button reaches this callback. The adapter serializes requests.
    self:invoke("purchase",item.id)
end
-- PF019 Cobalt buy: a QA trail of what the keys showed (pending / success / fail).
function Page:logBuy(kind: string,id: string)
    self.buyLog=self.buyLog or {};table.insert(self.buyLog,{kind=kind,id=id,at=os.clock()})
    if #self.buyLog>40 then table.remove(self.buyLog,1) end
end
-- Judge the buy from the commerce state the server drives (ShopBuyModel): success only once the
-- answered, server-confirmed profile owns the item. The rebuilt card plays the verdict once.
function Page:resolveBuy()
    local verdict,outcome=BuyModel.resolve(self.buy,self.model)
    if verdict~="success" and verdict~="fail" then return end
    local buy=self.buy;self.buy=nil
    self.buyResult={id=buy.id,kind=verdict,words=outcome and outcome.words,from=if buy.price then number(buy.price) else nil,at=os.clock()}
    self:logBuy(verdict,buy.id)
end
-- A failed buy's words on a catalog key (Need Cobalt / Try again): PF021 A's red note look.
local function paintNote(button: any,words: string)
    paintAction(button,{kind="note",text=words,active=false,gem=false})
end
-- The bought card's key: while pending, the dimmed price the card already shows (Updating) under
-- the light sweep; then (once) the success or failure play on the rebuilt card. Deferred one frame
-- so the play starts from the card's laid-out place.
function Page:buyLook(item: any,button: any,card: any,handle: any?)
    if self.buy and self.buy.id==item.id then
        BuyFx.pending(button,{reduced=motionOff(self),card=card,handle=handle})
        return
    end
    local result=self.buyResult
    if not result or result.id~=item.id then return end
    if result.kind=="fail" and result.noteUntil and os.clock()<result.noteUntil then paintNote(button,result.words or "Try again") end
    if result.played or os.clock()-result.at>2 then return end
    result.played=true
    if result.kind=="success" then
        task.defer(function()
            if not self.destroyed and button.Parent then BuyFx.success(button,{reduced=motionOff(self),from=result.from,card=card,handle=handle}) end
        end)
    else
        result.noteUntil=os.clock()+NOTE_SECONDS;paintNote(button,result.words or "Try again")
        task.defer(function() if not self.destroyed and button.Parent then BuyFx.fail(button,{reduced=motionOff(self),words=result.words}) end end)
        task.delay(NOTE_SECONDS+.05,function() self:clearNote(item,result) end)
    end
end
-- The note's moment is over: the key says its real action again (repainted, no rebuild).
function Page:clearNote(item: any,result: any)
    if self.destroyed or self.buyResult~=result then return end
    self.buyResult=nil
    local row=self.rows.Shop[item.id];local body=row and row:FindFirstChild("PFCardBody")
    if body then self:bindAction(row,item,body) end
    if item.category=="Bundle" then self:refreshBundles() end
end
-- Bundle cards are authored and never rebuilt: their BundleShopButton dims the price while pending by
-- itself; the success / failure plays and the failure's words (PFBuyNote) go on their key.
function Page:bundleBuyLook(item: any,card: any)
    local key=hostOf(card):FindFirstChild("Purchase");if not key then return end
    -- PF021 A: the bought bundle's key sweeps while pending (its button dims the price itself);
    -- authored cards are never rebuilt, so the sweep is ended here once the buy is answered.
    if self.buy and self.buy.id==item.id then BuyFx.pending(key,{reduced=motionOff(self),card=card});return end
    BuyFx.stop(key,"pending")
    local result=self.buyResult
    local note=if result and result.id==item.id and result.kind=="fail" and result.noteUntil and os.clock()<result.noteUntil then result.words else nil
    if not result or result.id~=item.id or result.played or os.clock()-result.at>2 then key:SetAttribute("PFBuyNote",note);return end
    result.played=true
    if result.kind=="success" then
        key:SetAttribute("PFBuyNote",nil)
        BuyFx.success(key,{reduced=motionOff(self),card=card})
    else
        result.noteUntil=os.clock()+NOTE_SECONDS;key:SetAttribute("PFBuyNote",result.words or "Try again")
        BuyFx.fail(key,{reduced=motionOff(self),words=result.words})
        task.delay(NOTE_SECONDS+.05,function() self:clearNote(item,result) end)
    end
end
function Page:refreshCurrency()
    -- PF017: no overline on either pack card ("MAKE YOUR MARK" removed).
    for _,name in {"Starter","Pro"} do local overline=self.shop.Scroll.Offers[name].Overline;overline.Text="";overline.Visible=false end
    for index=1,5 do
        local card=self.shop.Scroll.Currency.Packs["Pack"..index]
        local pack=Catalog.currencyPacks[index];local item=table.clone(pack);item.category="Currency"
        local host=hostOf(card)
        host.Title.Text=number(pack.amount)
        local pill=host:FindFirstChild("PFBonusPill",true)
        if pill then
            -- Cobalt v3: the split ("2,500 + 500 bonus", the bonus gold), the pill carries the %; no "Cobalt" row
            host.Amount.Visible=false
            host.Bonus.Visible=true
            host.Bonus.Text=if pack.bonusAmount>0 then number(pack.baseAmount).." + <font color=\"#ffd36a\">"..number(pack.bonusAmount).." bonus</font>" else "Base amount"
            local pct=ShopItemArt.bonusLabel(pack)
            pill.Visible=pct~=nil
            if pct then pill.Label.Text=if index==#Catalog.currencyPacks then pct.." · Best value" else pct end
        elseif host~=card then
            -- M7 rows on the kit card: "Cobalt", then "2,500 + 500 bonus" (gold) or "Base amount"
            host.Amount.Text="Cobalt"
            host.Bonus.Visible=true
            host.Bonus.Text=if pack.bonusAmount>0 then number(pack.baseAmount).." + "..number(pack.bonusAmount).." bonus" else "Base amount"
            host.Bonus.TextColor3=if pack.bonusAmount>0 then Color3.fromHex("#ddbf76") else self.theme.MutedText
        else
            host.Amount.Text="Cobalt total"
            host.Bonus.Visible=pack.bonusAmount>0;host.Bonus.Text="+"..number(pack.bonusAmount).." BONUS"
        end
        local art=host:FindFirstChild("Art") or host:FindFirstChild("Art",true)
        if art then Art.bindPremium(art,pack.art) end
        self:bindPurchase(card,item)
        -- the v3 key's green comes from its gradient (PFKeyTone), so its base is white
        if host.Purchase:FindFirstChild("PFKeyTone") then host.Purchase.BackgroundColor3=Color3.new(1,1,1) end
    end
    local x2=self.shop.Scroll.Currency:FindFirstChild("PF2xStrip")
    local pass=Catalog.passById and Catalog.passById.pass_2x_cobalt
    if x2 and pass then
        local mine=owned(self)[pass.id]==true
        local canBuy,price,_,state=self:purchaseState(pass)
        x2.Buy.Visible=not mine;x2.BuyShadow.Visible=not mine;x2.PFActive.Visible=mine
        x2.Buy.Active=canBuy;x2.Buy.AutoButtonColor=false;x2.Buy.BackgroundTransparency=if canBuy then 0 else .35
        ShopItemArt.paintRobux(x2.Buy,ShopItemArt.robuxLabel({priceText=price,purchaseState=state,targetRobux=pass.robux}))
    end
    self:bindPurchase(self.shop.Scroll.Offers.Pro,Catalog.premiumPacks[1])
    self:bindPurchase(self.shop.Scroll.Offers.Starter,Catalog.premiumById.pack_starter or {id="pending_Starter",category="Offer",pending=true})
end
-- PF020 G6 (PF - 2): what an owned pass card says and does (the mockup's owned face: "Owned", the
-- line, and the card's action on a cobalt key).
local PASS_OWNED={
    pass_custom_flag={line="3 flag slots",action="Set image"},
    pass_lobby_host_plus={line="4 perks · Create Lobby",action="Host a lobby"}}
-- A pass's green Robux key: Roblox's live price once the pass has a real ID; "--" and disabled until then.
local function paintPassKey(self: any,button: any,item: any)
    local canBuy,price=self:purchaseState(item)
    button.Text=ShopItemArt.robuxText(if string.match(price,"^%d[%d,]*$") then price else "--")
    button.Active=canBuy;button.Selectable=canBuy;button.AutoButtonColor=canBuy
    button:SetAttribute("ItemId",item.id)
end
function Page:refreshG6()
    local g6=self.g6;if not g6 then return end
    local mine=owned(self)
    -- VIP: the Robux key, or "VIP active" with a tick on every perk
    local band=g6.vip.Band;local vipOwned=mine.pass_vip==true
    band.Buy.Visible=not vipOwned;band.VipActive.Visible=vipOwned
    band.Caption.Text=if vipOwned then "Owned · thank you for supporting PixelFront" else "Yours forever · works in every match"
    band.Caption.Visible=not vipOwned -- PF025: owned, the daily Cobalt strip sits under "VIP active" (PremiumController)
    for _,cell in band.Perks:GetChildren() do local check=cell:FindFirstChild("Check");if check then check.Visible=vipOwned end end
    if not vipOwned then paintPassKey(self,band.Buy,Catalog.passById.pass_vip) end
    for _,card in g6.cards:GetChildren() do
        local pass=Catalog.passById[card:GetAttribute("PassId")]
        -- a pass the catalog no longer sells (the Animated Nameplate, 2026-10-26) leaves the row; the row's list closes the gap
        if not pass then if card:IsA("GuiObject") and card:GetAttribute("PassId")~=nil then card.Visible=false end;continue end
        local isOwned=mine[pass.id]==true;local look=PASS_OWNED[pass.id] or {line="Yours",action="Open"}
        card.Buy.Visible=not isOwned;card.Action.Visible=isOwned
        card.Kicker.Text=if isOwned then "Owned" else "Gamepass"
        card.Line.Text=if isOwned then look.line else "Yours forever"
        local accentHi=card:GetAttribute("AccentHi")
        card.Line.TextColor3=if isOwned or typeof(accentHi)~="Color3" then self.theme.Text else accentHi
        local edge=card:FindFirstChild("PFStroke")
        if edge then edge.Color=Color3.fromHex(if isOwned then "#3678ff" else "#535353");edge.Thickness=if isOwned then 2 else 1 end
        if isOwned then
            -- bought from a lobby flow: the key goes back to it ("Back to Create")
            local back=self.context.passReturn and self.context.passReturn()
            card.Action.Text=if back and back.passId==pass.id and back.words then back.words else look.action
            card.Action.Active=true;card.Action.Selectable=true;card.Action.AutoButtonColor=true
        else paintPassKey(self,card.Buy,pass) end
    end
end
-- An owned card's action: Custom Flag opens PF - 3's Flag Forge, Lobby Host+ the Create Lobby screen.
-- (The Animated Nameplate pass is retired, 2026-10-26: its styles are Cobalt items.)
function Page:passAction(pass: any)
    if not self.visible or self.page~="Shop" or not owned(self)[pass.id] then return end
    local back=self.context.passReturn and self.context.passReturn()
    if back and back.passId==pass.id and self.context.returnToFlow then self.context.returnToFlow();return end
    if pass.id=="pass_custom_flag" then
        local module=script.Parent:FindFirstChild("PremiumController")
        if module then (require(module) :: any).openFlagForge() end
    elseif pass.id=="pass_lobby_host_plus" then
        if self.context.openScreen then self.context.openScreen("Create") end
    end
end
-- PF020 (MM): a lobby flow's pass tag lands here: the Passes tab with that pass's card in view (on a
-- gamepad, its key selected). Without the G6 rows or the Passes tab, the Shop opens as before.
function Page:showPass(passId: string)
    if self.destroyed or not self.g6 or not Flags.passesVisible then return end
    local target=if passId=="pass_vip" then self.g6.vip else nil
    if not target then for _,card in self.g6.cards:GetChildren() do if card:GetAttribute("PassId")==passId then target=card end end end
    if not target then return end
    self:selectCategory("Shop","Passes")
    task.defer(function()
        if self.destroyed or not self.visible or self.shopCategory~="Passes" then return end
        local scroll=scrollOf(self.shop)
        local y=target.AbsolutePosition.Y-scroll.AbsolutePosition.Y+scroll.CanvasPosition.Y
        local most=math.max(0,scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteWindowSize.Y)
        scroll.CanvasPosition=Vector2.new(0,math.clamp(y-16,0,most))
        if Input.PreferredInput==Enum.PreferredInput.Gamepad then
            local host=target:FindFirstChild("Band") or target
            local key=if host.Buy.Visible then host.Buy else host:FindFirstChild("Action")
            if key and key.Selectable then Gui.SelectedObject=key end
        end
    end)
end
function Page:refreshPasses()
    self:refreshG6()
    local cards=self.shop.Scroll.Passes.Cards
    for _,item in Commerce.passTemplates do
        local card=cards[item.card]
        card.Title.Text=item.name;card.Kind.Text="Permanent pass - template";card.Description.Text=item.description
        self:bindPurchase(card,item);card.State.Text="Not available yet"
        card.Active=false;card.Selectable=false;card.AutoButtonColor=false
    end
    local pack=Catalog.premiumPacks[1];local card=cards.Aurora
    card.Title.Text=pack.name;card.Kind.Text="Permanent pass";card.Description.Text="7 cosmetics + 10,000 Cobalt once"
    Art.bindPremium(card,pack.art);self:bindPurchase(card,pack)
    card.Active=false;card.Selectable=false;card.AutoButtonColor=false
end
function Page:refreshTabs(scope: string)
    local ui=if scope=="Shop" then self.shop else self.inventory
    local selected=category(self,scope);local valid=if scope=="Shop" then SHOP_CATEGORIES else Commerce.inventoryCategories
    -- PF019 M3: on the authored bar the tabs are flat text; ShopTopBar paints them and slides the pill.
    local bar=if scope=="Shop" then self.topBar else self.invBar
    for _,button in categoriesOf(ui):GetChildren() do if button:IsA("TextButton") then
        button.Visible=table.find(valid,button.Name)~=nil;button.Active=button.Visible;button.Selectable=button.Visible
        if not bar then
            button.BackgroundColor3=if button.Name==selected then self.theme.Accent:Lerp(self.theme.Panel,.65) else self.theme.Panel
            button.TextColor3=if button.Name==selected then self.theme.Text else self.theme.MutedText
            button.Underline.Visible=button.Name==selected
        else button.Underline.Visible=false end
        button:SetAttribute("PFSelected",button.Name==selected)
    end end
    if bar then bar:setActive(selected) end
    local tabs=Commerce.secondary(selected);self.filters[scope]=Commerce.validFilter(selected,self.filters[scope])
    ui.Secondary.Visible=#tabs>0
    for _,button in ui.Secondary:GetChildren() do if button:IsA("TextButton") then
        local parent,filter=string.match(button.Name,"^(%w+)_(%w+)$")
        button.Visible=parent==selected and table.find(tabs,filter)~=nil;button.Active=button.Visible;button.Selectable=button.Visible
        local active=button.Visible and filter==self.filters[scope]
        button.BackgroundColor3=if active then self.theme.Accent:Lerp(self.theme.Panel,.65) else self.theme.Panel
        button.TextColor3=if active then self.theme.Text else self.theme.MutedText
        button.Underline.Visible=active
        button:SetAttribute("PFSelected",active)
    end end
end
function Page:refreshRows()
    local focusId,focusScope,focusAction=nil,nil,false
    local selected=Gui.SelectedObject
    local scrollPositions={}
    for id,section in self.sections do scrollPositions[id]=section.Scroll.CanvasPosition end
    -- PF019 Cobalt buy (Ashton: buying "moves my screen up to cobalt"): every commerce answer rebuilds
    -- these rows, and reading the bar's tab boxes mid-rebuild lays the short list out, so the clamp
    -- pulled the Shop up to Cobalt. Both pages' lists keep their place (restored once rebuilt; only
    -- selectCategory / a filter, which zero it before calling here, move them).
    local keep={}
    for _,ui in {self.shop,self.inventory} do local scroll=scrollOf(ui);keep[scroll]=scroll.CanvasPosition end
    for scope,rows in self.rows do for id,row in rows do
        if selected and (selected==row or selected:IsDescendantOf(row)) then focusId=id;focusScope=scope;focusAction=selected==row:FindFirstChild("Purchase",true) end
    end end
    for _,connection in self.rowConnections do connection:Disconnect() end;table.clear(self.rowConnections)
    -- Destruction can move native selection to another row. Capture once, then
    -- clear our selection before rebuilding so that fallback cannot replace it.
    if focusId then Gui.SelectedObject=nil end
    for _,rows in self.rows do for _,row in rows do row:Destroy() end end
    for _,section in self.sections do section:Destroy() end
    self.rows={Shop={},Inventory={}};self.sections={};self.rowHandles={}
    for _,scope in {"Shop","Inventory"} do
        local inventory=scope=="Inventory";local ui=if inventory then self.inventory else self.shop
        self:refreshTabs(scope)
        local selected=category(self,scope);local filter=self.filters[scope]
        local grid=if inventory then scrollOf(ui).Grid else ui.Scroll.Catalog.Grid
        local discover=not inventory and selected=="All"
        if not inventory then
            ui.Scroll.Catalog.Sections.Visible=discover;grid.Visible=not discover
            ui.Scroll.Catalog.Heading.Visible=false
        end
        local entries=table.clone(Catalog.items)
        if inventory then for _,pack in Catalog.premiumPacks do table.insert(entries,pack) end end
        -- PF023 (MM): level rewards live in Catalog.levelItems (never sold): the Inventory lists the ones you own.
        if inventory then for _,levelItem in Catalog.levelItems or {} do if owned(self)[levelItem.id] then table.insert(entries,levelItem) end end end
        if not inventory then
            -- earned-pack items first: the card order (LayoutOrder=count) puts them at the head of each row / tab
            local first,rest={},{}
            for _,entry in entries do table.insert(if earnedOf(entry) then first else rest,entry) end
            table.move(rest,1,#rest,#first+1,first);entries=first
        end
        local count=0
        for _,item in entries do
            if not Commerce.matches(item,selected,filter) then continue end
            if not inventory and item.passOnly and not Flags.passesVisible then continue end -- PF020: shown with the Passes tab
            if not inventory and self.bundleCards and item.category=="Bundle" then continue end -- shown as PFBundles cards
            if inventory and not owned(self)[item.id] then continue end
            count+=1;local parent=grid
            if discover then
                local sectionId=item.category
                local section=self.sections[sectionId]
                if not section then
                    local descriptor,index=nil,nil
                    for i,entry in Commerce.sections do if entry.id==item.category then descriptor=entry;index=i;break end end
                    if not descriptor then continue end
                    -- PF017: Discover rows sit directly in the Shop list (after Catalog), so
                    -- their authored height follows the window: whole rows on a phone.
                    section=ui.Templates.Section:Clone();section.Name=sectionId;section.LayoutOrder=50+index;section.Visible=true;section.Parent=ui.Scroll
                    Typography.applyTree(section)
                    -- author-pf1-discover-rows: the Heading sits in a Head row (Heading · Count · Rule)
                    local heading=section:FindFirstChild("Heading",true);if heading then heading.Text=descriptor.label end
                    self.sections[sectionId]=section
                    local function move(direction: number)
                        section.Scroll.CanvasPosition=Vector2.new(math.clamp(section.Scroll.CanvasPosition.X+direction*math.max(240,section.Scroll.AbsoluteSize.X*.8),0,math.max(0,section.Scroll.AbsoluteCanvasSize.X-section.Scroll.AbsoluteWindowSize.X)),0)
                    end
                    table.insert(self.rowConnections,section.Left.Activated:Connect(function()move(-1)end))
                    table.insert(self.rowConnections,section.Right.Activated:Connect(function()move(1)end))
                    section.Scroll.CanvasPosition=scrollPositions[sectionId] or Vector2.zero
                end
                parent=section.Scroll
            end
            local row=ui.Templates.ItemCard:Clone();row.Name=item.id;row.LayoutOrder=count;row.Visible=true;row.Parent=parent;self.rows[scope][item.id]=row
            Typography.applyTree(row)
            -- PF019: Shop cards are the M2 kit card (content under PFCardBody); Inventory cards keep
            -- their template until the Inventory build. Overline = the category word in the set colour.
            local body=row:FindFirstChild("PFCardBody") or row
            local pack=packOf(item);local set=Color3.fromHex(CardModel.setHex(item,pack and pack.id))
            body.Title.Text=item.name;body.Kind.Text=CardModel.overline(item.category);body.Kind.TextColor3=set
            Art.bindItem(row,if Catalog.byId[item.id] then item.id else nil) -- (2026-10-26: Levels removed; a Title binds like any item)
            local earnedPack=earnedOf(item);if item.category=="Nameplate" and (earnedPack or item.style) then plateArt(row,item,earnedPack) end
            local artNode=row:FindFirstChild("Art",true)
            if item.art and artNode and Art.bindPremium(artNode,item.art) then
                local fallback=row:FindFirstChild("ArtFallback",true);if fallback then fallback.Visible=false end
                local backdrop=row:FindFirstChild("ArtBackdrop",true);if backdrop then backdrop.Visible=false end
            end
            local focusStroke=row:FindFirstChild("FocusStroke")
            if focusStroke then focusStroke.Enabled=true;focusStroke.Color=self.theme.Accent;focusStroke.Transparency=1 end
            if inventory and body~=row then
                -- PF019 Inventory: the same M2 card. The key equips (Equip / the Equipped state /
                -- Owned for bundles and packs); the card itself selects the item for the panel.
                local equippedNow=self:isEquipped(item,scope)
                local action=CardModel.inventoryAction({equippable=Catalog.slots[item.category]==true,equipped=equippedNow,ready=ready(self)})
                paintAction(body.Purchase,action)
                local link=body:FindFirstChild("PFPackLink");if link then link.Visible=false;link.Active=false;link.Selectable=false end
                row.Active=true;row.Selectable=true;row.AutoButtonColor=false
                local key=body.Purchase
                table.insert(self.rowConnections,row.Activated:Connect(function()
                    self.selectedId=item.id;self:refreshSelection();self.identity.CanvasPosition=Vector2.zero
                end))
                table.insert(self.rowConnections,key.Activated:Connect(function()
                    if key:GetAttribute("PFAction")=="equip" then self.selectedId=item.id;self:equipFromCard(item) end
                end))
                if self.context.cardKit then
                    local artKind=ITEM_ART[item.id]
                    local art=if artKind then ShopItemArt.attach(row,artKind,{id=item.id}) else {}
                    local handle=self.context.cardKit:bind(row,{set=set,targets={key},idle=art.idle,onLook=art.onLook})
                    self.rowHandles[row]=handle
                    -- the equip motion: the card that was just equipped animates into its cobalt look
                    local motion=self.pendingEquip and self.pendingEquip.id==item.id and equippedNow and os.clock()-self.pendingEquip.at<6
                    if motion then
                        self.pendingEquip=nil
                        task.defer(function() if not self.destroyed and row.Parent then handle:setEquipped(true);self:equipFlash(row) end end)
                    else handle:setEquipped(equippedNow) end
                    handle:setSelected(self.selectedId==item.id)
                end
            elseif inventory then
                row.Purchase.Visible=false;row.Price.Visible=false;row.Arrow.Visible=true
                row.State.Text=if self:isEquipped(item,scope) then "Equipped" else "Owned"
                row.State.TextColor3=if self:isEquipped(item,scope) then self.theme.Positive else self.theme.MutedText
                table.insert(self.rowConnections,row.Activated:Connect(function()
                    -- The identity sidebar is authored beside the grid on every screen.
                    self.selectedId=item.id;self:refreshSelection();self.identity.CanvasPosition=Vector2.zero
                end))
            elseif body~=row then
                -- PF019 M2: one action, never a dead button (ShopCardModel); the kit drives the looks.
                row.Active=false;row.Selectable=false;row.AutoButtonColor=false
                local action=self:bindAction(row,item,body)
                local purchaseButton=body.Purchase
                table.insert(self.rowConnections,purchaseButton.Activated:Connect(function()self:cardAction(item,purchaseButton)end))
                local link=body:FindFirstChild("PFPackLink")
                local earned=earnedOf(item)
                if link then table.insert(self.rowConnections,link.Activated:Connect(function()
                    if link.Visible and link.Active then if earned then openDaily() else self:showPack(pack) end end
                end)) end
                local handle=nil
                if self.context.cardKit then
                    local artKind=ITEM_ART[item.id]
                    local art=if artKind then ShopItemArt.attach(row,artKind,{id=item.id}) else {}
                    handle=self.context.cardKit:bind(row,{set=set,targets={purchaseButton,link},idle=art.idle,onLook=art.onLook})
                    handle:setEquipped(action.kind=="equipped")
                end
                self:buyLook(item,purchaseButton,row,handle) -- PF019 Cobalt buy: dots, then the verdict's play
            else
                row.Active=false;row.Selectable=false;row.AutoButtonColor=false;self:bindPurchase(row,item)
                table.insert(self.rowConnections,row.Purchase.Activated:Connect(function()self:purchaseItem(item)end))
                -- PF017: an owned item says so on its state line, with no dead button.
                local _,ownedText,_,ownership=self:purchaseState(item)
                if ownership=="Owned" and not item.packOnly then
                    -- The authored PFOwned line spans the button's row (readable on a phone).
                    row.Purchase.Visible=false
                    local line=row:FindFirstChild("PFOwned")
                    if line then line.Visible=true;line.Text="✓ "..ownedText;line.TextColor3=self.theme.Positive;row.State.Text=""
                    else row.State.Text="✓ "..ownedText;row.State.TextColor3=self.theme.Positive end
                end
                local link=if item.packOnly then self:bindPackLink(row,item) else nil
                if link then table.insert(self.rowConnections,link.Activated:Connect(function()if link.Active then self:showPack(packOf(item))end end)) end
            end
            if body~=row then continue end -- the kit ring is the focus look
            local link=if inventory then nil else row:FindFirstChild("PFPackLink")
            local focus=if inventory then row elseif link and link.Visible then link else row.Purchase
            local function focusStroke()
                if not self.destroyed and row.Parent then row.FocusStroke.Transparency=if Gui.SelectedObject==focus or (inventory and self.selectedId==item.id)then 0 else 1 end
            end
            table.insert(self.rowConnections,focus.SelectionGained:Connect(focusStroke))
            table.insert(self.rowConnections,focus.SelectionLost:Connect(focusStroke))
        end
        -- the Discover rows (author-pf1-discover-rows): each Head counts its cards; PFFade shows while more is off to the right
        if discover then
            for _,section in self.sections do
                local n=0;for _,c in section.Scroll:GetChildren() do if c:IsA("GuiButton") and c.Visible then n+=1 end end
                local countLabel=section:FindFirstChild("Count",true);if countLabel then countLabel.Text=tostring(n) end
                local fade=section:FindFirstChild("PFFade")
                if fade then
                    local strip=section.Scroll
                    local function more()
                        if fade.Parent then fade.Visible=strip.AbsoluteCanvasSize.X-strip.AbsoluteWindowSize.X-strip.CanvasPosition.X>8 end
                    end
                    table.insert(self.rowConnections,strip:GetPropertyChangedSignal("CanvasPosition"):Connect(more))
                    table.insert(self.rowConnections,strip:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(more))
                    task.defer(more)
                end
            end
        end
        local empty=Commerce.empty(selected,filter,inventory)
        if inventory then
            -- The header carries the owned count; this line speaks only for loading, failure and empty states.
            local countLabel=scrollOf(ui).Count
            countLabel.Text=if self.profile.failed then "Inventory unavailable." elseif not self.profile.loaded then "Loading inventory…" elseif count==0 then empty else tostring(count).." items"
            countLabel.Visible=self.profile.failed==true or not self.profile.loaded or count==0
            -- PF019: an empty category says so in one panel and points to the Shop.
            local emptyPanel=scrollOf(ui):FindFirstChild("PFEmpty")
            if emptyPanel then
                local showEmpty=self.profile.loaded==true and not self.profile.failed and count==0
                emptyPanel.Visible=showEmpty
                if showEmpty then
                    countLabel.Visible=false
                    emptyPanel.Title.Text=EMPTY_TITLES[selected] or "Nothing here yet"
                    emptyPanel.Body.Text="Find them in the Shop."
                    emptyPanel.Go.Visible=true
                end
            end
            -- the approved Inventory board: a "More in the Shop" tile ends a grid that has cards (author-pf1-inventory-more's
            -- Templates.PFMoreTile; the Shop's own tab for this category opens)
            local moreTemplate=ui.Templates:FindFirstChild("PFMoreTile")
            if moreTemplate and count>0 and self.profile.loaded and not self.profile.failed then
                local tile=moreTemplate:Clone();tile.Name="PFMoreTile";tile.LayoutOrder=count+1;tile.Visible=true;tile.Parent=grid
                self.rows[scope].PFMoreTile=tile
                table.insert(self.rowConnections,tile.Activated:Connect(function() self:visitShop() end))
            end
        else ui.Scroll.Catalog.Empty.Text=empty;ui.Scroll.Catalog.Empty.Visible=count==0 and selected~="Currency" and selected~="Bundles" and selected~="Passes" end
    end
    self.shop.Scroll.Offers.Visible=self.shopCategory=="All" or self.shopCategory=="Bundles"
    self.shop.Scroll.Currency.Visible=self.shopCategory=="All" or self.shopCategory=="Currency"
    local passesShown=Flags.passesVisible and (self.shopCategory=="All" or self.shopCategory=="Passes")
    -- PF020 G6: the authored VIP band + pass cards replace the PF015 section where they exist
    if self.g6 then self.g6.vip.Visible=passesShown;self.g6.cards.Visible=passesShown end
    self.shop.Scroll.Passes.Visible=passesShown and not self.g6
    -- Catalog holds the category-tab grid; Discover's rows are siblings in the Shop list.
    self.shop.Scroll.Catalog.Visible=self.shopCategory~="Currency" and self.shopCategory~="Passes" and self.shopCategory~="All" and not (self.bundleCards and self.shopCategory=="Bundles")
    self:refreshBundles()
    self.aurora:setVisible(self.visible and self.page=="Shop")
    if self.forge then self.forge:setVisible(self.visible and self.page=="Shop")end
    self:refreshSelection()
    -- PF019 Cobalt buy: put every list back where it was (a row's sideways scroll too: it was set
    -- before the row had cards, so it clamped to the start). Read the canvas first so the clamp
    -- sees the rebuilt length.
    for id,section in self.sections do if scrollPositions[id] then keep[section.Scroll]=scrollPositions[id] end end
    for scroll,position in keep do
        if scroll.Parent and scroll.CanvasPosition~=position then local _=scroll.AbsoluteCanvasSize;scroll.CanvasPosition=position end
    end
    if focusId and focusScope and self.visible then
        local row=self.rows[focusScope][focusId]
        -- PF019 kit cards keep their action under PFCardBody.
        local action=row and row:FindFirstChild("Purchase",true)
        Gui.SelectedObject=if row then (if focusAction and action and action.Selectable then action else if row.Selectable then row else nil) else nil
    end
end
-- PF020 G7 (PF - 3): the Tempest card's hover (the G7 board: the wash brightens, the key's bolt lights),
-- eased like the kit's own hover. The card kit decides when it is hot; values: AtlasBundleModel.STORM.
function Page:stormHover(wash: any,bolt: any,hot: boolean)
    if self.destroyed then return end
    local S=self.bundleModel.STORM
    local info=TweenInfo.new(if motionOff(self) then 0 else .18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    local Tween=game:GetService("TweenService")
    if wash then Tween:Create(wash,info,{ImageTransparency=if hot then S.washHot else S.washRest}):Play() end
    if bolt then Tween:Create(bolt,info,{ImageColor3=Color3.fromHex(if hot then S.boltHot else S.boltRest)}):Play() end
end
function Page:refreshBundles()
    local band=self.bundleCards;if not band then return end
    -- Discover (below the pack cards) and the Bundles tab.
    band.Visible=self.shopCategory=="All" or self.shopCategory=="Bundles"
    local mine=if self.profile.loaded and not self.profile.failed then owned(self) else {}
    for _,card in (self.bundleStrip or band):GetChildren() do
        local item=Catalog.byId[card.Name]
        -- PF020 G7 (PF - 3): a card authored ahead of its catalog entry stays hidden until the entry lands.
        if card:GetAttribute("PFCatalogGated")==true and card:IsA("GuiObject") then card.Visible=item~=nil and item.category=="Bundle" end
        if not item or item.category~="Bundle" then continue end
        local view=self.bundleModel.describe(item.id,mine)
        local host=hostOf(card)
        -- PF020 G7: the storm wash runs its item's idle loop (bound once; PFWashItem names the item).
        local wash=host:FindFirstChild("PFWash")
        if wash and wash:IsA("ImageLabel") then
            self.washes=self.washes or setmetatable({},{__mode="k"})
            local washItem=wash:GetAttribute("PFWashItem")
            if self.washes[wash]~=washItem then self.washes[wash]=washItem;Art.bindItem(wash,if type(washItem)=="string" then washItem else nil) end
        end
        host.Title.Text=view.name;host.Badge.Label.Text=view.badge;host.Value.Text=view.value
        for _,tile in host.Members:GetChildren() do
            local index=tonumber(string.match(tile.Name,"^Member(%d+)$"));if not index then continue end
            local member=view.members[index];tile.Visible=member~=nil
            if member then
                tile.Kind.Text=string.upper(member.kind)..(if member.owned then ' <font color="#4ade80">✓</font>' else "")
                tile.ItemName.Text=member.name;tile.Well.Owned.Visible=member.owned
                Art.bindItem(tile.Well,member.id)
            end
        end
        self:bindPurchase(card,item)
        self:bundleBuyLook(item,card) -- PF019 Cobalt buy
    end
end
function Page:refreshProfile()
    local identity=if self.context.getIdentity then table.clone(self.context.getIdentity() or {}) else {}
    identity.equipped=self.profile.equipped or {};identity.cosmetics=self.profile.identityCosmetics;Art.bindProfile(self.identity.Profile,identity)
    for _,slot in {"Banner","Frame","Nameplate","Title"} do
        local descriptor=identity.cosmetics and identity.cosmetics[string.lower(slot)];local item=Catalog.byId[identity.equipped[slot]]
        self.identity.Slots[slot].Text=if item then item.name elseif type(descriptor)=="table" and type(descriptor.name)=="string" then descriptor.name else "Default"
    end
    -- PF019 "Your look": the in-match preview and the six slot tiles follow what you wear, live.
    local look=identity.equipped
    local match=self.identity:FindFirstChild("PFMatch")
    if match then
        local stage=match.Stage
        Art.bindItem(stage.PFSkin,look.Skin or "skin_classic")
        Art.bindItem(stage.Label.PFCrownMark,look.Crown);Art.bindItem(stage.Label.NameRow.PFFlagMark,look.Flag)
        stage.Label.NameRow.PlayerName.Text=identity.displayName or identity.name or "Player"
    end
    local slotTiles=self.identity:FindFirstChild("PFSlots")
    if slotTiles then for _,tile in slotTiles:GetChildren() do
        if not tile:IsA("TextButton") then continue end
        local category=tile:GetAttribute("Category");local id=look[category]
        local item=if type(id)=="string" then Catalog.byId[id] else nil
        Art.bindItem(tile.Well,if item then id elseif category=="Skin" then "skin_classic" else nil)
        tile.ItemName.Text=if item then item.name else (SLOT_DEFAULTS[category] or "None")
        tile.ItemName.TextColor3=if item then self.theme.Text else self.theme.MutedText
    end end
end
-- A slot tile opens its category (Profile kinds open the Profile tab on that filter).
function Page:openSlot(category: string?)
    local route=category and SLOT_TABS[category];if not route or not self.visible then return end
    self:selectCategory("Inventory",route[1])
    if route[2] then self.filters.Inventory=Commerce.validFilter(route[1],route[2]);self:refreshRows();self:layout() end
end
-- The empty state's one button: the same category in the Shop.
function Page:visitShop()
    local category=self.inventoryCategory;local filter=self.filters.Inventory
    if self.context.navigate then self.context.navigate("Shop") end
    local target=if table.find(SHOP_CATEGORIES,category) then category else "All"
    self:selectCategory("Shop",target)
    if target=="Profile" and filter then self.filters.Shop=Commerce.validFilter("Profile",filter);self:refreshRows();self:layout() end
end
function Page:effectTarget(): string?
    return if self.inventoryCategory=="Effects" and self.filters.Inventory~="Global" then self.filters.Inventory else nil
end
function Page:refreshSelection()
    local item=itemById(self.selectedId)
    if not item or not owned(self)[item.id] or not Commerce.matches(item,self.inventoryCategory,self.filters.Inventory) then self.selectedId=nil;item=nil end
    if not item then for _,list in {Catalog.items,Catalog.levelItems or {}} do for _,entry in list do -- PF023: owned level items too
        if owned(self)[entry.id] and Commerce.matches(entry,self.inventoryCategory,self.filters.Inventory) then self.selectedId=entry.id;item=entry;break end
    end;if item then break end end end
    local detail=self.identity.Detail;local target=self:effectTarget();local label=target and Targets.byId[target].label
    -- PF019: the overline rule here too (category word in the set colour); an effect target keeps its words
    detail.Kind.Text=if label then string.upper(label).." EFFECT" elseif item then CardModel.overline(item.category) else ""
    detail.Kind.TextColor3=if item then Color3.fromHex(CardModel.setHex(item,(packOf(item) or {}).id)) else self.theme.MutedText
    detail.Title.Text=if item then item.name else "Choose a cosmetic"
    detail.Description.Text=if item then item.description else Commerce.empty(self.inventoryCategory,self.filters.Inventory,true)
    detail.Price.Text=if item then "Owned" else ""
    local overrides=(self.profile.equipped or {}).effectTargets or {}
    local currentEffect=target and Catalog.byId[overrides[target]]
    detail.Status.Text=if not ready(self) then self:status() elseif target then (if overrides[target]==nil then "Using global default" elseif overrides[target]==false then "Default - no effect" else (if currentEffect then currentEffect.name else "Effect").." equipped for "..label) elseif item and item.category=="Buildings" then "Applies to all six buildings" elseif item and item.category=="Missiles" then "Trail + explosion on every nuke: Atom, Hydrogen, MIRV" else ""
    Art.bindItem(detail,if item and Catalog.byId[item.id] then item.id else nil)
    local art=detail:FindFirstChild("PFArt") or detail
    if item and item.art and Art.bindPremium(art.Art,item.art) then
        art.ArtFallback.Visible=false;art.ArtBackdrop.Visible=false
    end
    -- PF019: no placeholder art and no dead button while nothing is chosen (the grid's empty state speaks)
    if art~=detail then art.Visible=item~=nil end
    detail.Action.Visible=item~=nil
    -- PF019 M8: PF - 2's in-match strip for the selected effect (driven only while shown).
    local strip=detail:FindFirstChild("PFEffectStrip")
    if strip then
        local effect=if item then STRIP_EFFECTS[item.id] else nil
        if effect~=self.stripEffect then
            if self.stopStrip then self.stopStrip();self.stopStrip=nil end
            self.stripEffect=effect
            if effect then self.stopStrip=ShopItemArt.drive(strip,"strip",{effect=effect}) end
        end
        strip.Visible=effect~=nil
    end
    local equipped=item and self:isEquipped(item,"Inventory")
    detail.Action.Text=if not item then "Select an item" elseif not Catalog.slots[item.category] then "Bundle owned" elseif equipped and target then "Equipped" elseif equipped then "Unequip" elseif label then "Equip for "..label else "Equip"
    enabled(detail.Action,item~=nil and ready(self) and Catalog.slots[item.category]==true and not (target~=nil and equipped),self.theme,target~=nil and equipped)
    detail.Default.Visible=target~=nil;detail.Inherit.Visible=target~=nil
    enabled(detail.Default,target~=nil and ready(self) and overrides[target]~=false,self.theme)
    enabled(detail.Inherit,target~=nil and ready(self) and overrides[target]~=nil,self.theme)
    for id,row in self.rows.Inventory do
        row:SetAttribute("PFSelected",id==self.selectedId)
        local rowItem=itemById(id)
        row:SetAttribute("PFEquipped",rowItem~=nil and self:isEquipped(rowItem,"Inventory"))
        local handle=self.rowHandles and self.rowHandles[row]
        if handle then handle:setSelected(id==self.selectedId)
        elseif row:FindFirstChild("FocusStroke") then row.FocusStroke.Transparency=if id==self.selectedId or Gui.SelectedObject==row then 0 else 1 end
    end
end
function Page:equipSelected()
    local item=itemById(self.selectedId)
    if not ready(self) or not item or not owned(self)[item.id] or not Catalog.slots[item.category] then return end
    local target=if item.category=="VFX" then self:effectTarget() else nil
    if target and self:isEquipped(item,"Inventory") then return end
    self:invoke("equip",if not target and self:isEquipped(item,"Inventory") then false else item.id,item.category,target)
end
-- PF019 Inventory: equip from a card's key (global, or the Effects filter's target), then play
-- the equip motion when the profile confirms it (the card key + border, the look preview).
function Page:equipFromCard(item: any)
    if not ready(self) or not owned(self)[item.id] or not Catalog.slots[item.category] then return end
    local target=if item.category=="VFX" then self:effectTarget() else nil
    if self:isEquipped(item,"Inventory") then return end
    self.pendingEquip={id=item.id,category=item.category,at=os.clock()}
    self:invoke("equip",item.id,item.category,target)
end
local function reduced(self: any): boolean return self.context.reducedMotion~=nil and self.context.reducedMotion() end
-- The key's cobalt flash + a small settle of the card (M2 equipped look arrives with the kit).
function Page:equipFlash(row: any)
    if reduced(self) then return end
    local Tween=game:GetService("TweenService")
    local body=row:FindFirstChild("PFCardBody");if not body then return end
    local flash=body.Purchase:FindFirstChild("PFFlash",true)
    if flash then flash.BackgroundTransparency=.2;Tween:Create(flash,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play() end
    local scale=body:FindFirstChild("PFCardScale")
    if scale then scale.Scale=1.05;Tween:Create(scale,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    self:previewPop(itemById(row.Name))
end
-- The look preview answers too: the equipped slot pops (PFPop) and the preview sweeps once.
function Page:previewPop(item: any?)
    if not item or reduced(self) then return end
    local Tween=game:GetService("TweenService")
    local slot=self.identity:FindFirstChild("PFSlot_"..item.category,true)
    local pop=slot and slot:FindFirstChild("PFPop",true)
    if pop then pop.Scale=1.14;Tween:Create(pop,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    local sweep=self.identity:FindFirstChild("PFSweep",true)
    if sweep and sweep:IsA("UIGradient") then sweep.Offset=Vector2.new(-1,0);Tween:Create(sweep,TweenInfo.new(.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Offset=Vector2.new(1,0)}):Play() end
end
function Page:resetTarget(inherit: boolean)
    local target=self:effectTarget();if not target or not ready(self) then return end
    self:invoke("equip",false,"VFX",target,if inherit then true else nil)
end
-- Kept as no-ops for compatibility with the shell and prior art lifecycle. No Shop opener.
function Page:openDetail(_item: any,_opener: any) end
function Page:refreshDetail() end
function Page:closeDetail(_restore: boolean?)
    self.detailItem=nil;self.shop.Detail.Visible=false;self.shop.DetailShade.Visible=false
end
function Page:handleEscape(): boolean return false end
function Page:focusActive()
    if not self.visible then return end
    local ui=if self.page=="Inventory" then self.inventory else self.shop;Gui.SelectedObject=categoriesOf(ui)[category(self,self.page)]
end
function Page:focusChanged()
    if not self.visible or self.destroyed or not Gui.SelectedObject then return end
    local selected=Gui.SelectedObject;local ui=if self.page=="Inventory" then self.inventory else self.shop
    local scrolls={categoriesOf(ui),ui.Secondary}
    for _,section in self.sections do table.insert(scrolls,section.Scroll) end
    table.insert(scrolls,scrollOf(ui))
    if self.page=="Inventory" then table.insert(scrolls,self.identity) end
    for _,scroll in scrolls do if selected:IsDescendantOf(scroll) then
        local delta=selected.AbsolutePosition-scroll.AbsolutePosition;local canvas=scroll.CanvasPosition
        if scroll.ScrollingDirection==Enum.ScrollingDirection.X then
            -- The right margin clears the authored edge fade on the Shop tab strip.
            if delta.X<8 then canvas+=Vector2.new(delta.X-8,0) elseif delta.X+selected.AbsoluteSize.X>scroll.AbsoluteWindowSize.X-36 then canvas+=Vector2.new(delta.X+selected.AbsoluteSize.X-scroll.AbsoluteWindowSize.X+36,0) end
        else
            if delta.Y<6 then canvas+=Vector2.new(0,delta.Y-6) elseif delta.Y+selected.AbsoluteSize.Y>scroll.AbsoluteWindowSize.Y-6 then canvas+=Vector2.new(0,delta.Y+selected.AbsoluteSize.Y-scroll.AbsoluteWindowSize.Y+6) end
        end
        scroll.CanvasPosition=Vector2.new(math.max(0,canvas.X),math.max(0,canvas.Y))
    end end
end

-- PF015: the Shop page is AUTHORED (tools/atlas/author-pf015-menus.luau): one
-- header row (title, category tabs, wallet, Inventory), the filter row, the
-- scroll filling the rest, fit-within pack bands and tap-size item cards. The
-- Inventory page is authored the same way (tools/atlas/author-pf015-pages.luau):
-- header row, filter row, then the grid beside the identity sidebar, whose
-- detail texts hug their content in a list. PF016 authors the pack cards'
-- internals at Scale. No geometry is computed here; layout() only keeps the
-- static copy the shell expects.
function Page:layout(_sizeOverride: Vector2?)
    if self.destroyed then return end
    self.shop.Detail.Visible=false;self.shop.DetailShade.Visible=false
    local offers=self.shop.Scroll.Offers
    -- PF017: the Cobalt chip owns the pack cards' footer row (no repeated pack name).
    for _,name in {"Starter","Pro"} do offers[name].Footer.Visible=false end
end

function Page:destroy()
    if self.destroyed then return end
    -- GUI Destroying may be deferred until descendants are gone. Teardown must not
    -- navigate the authored hierarchy through setVisible/closeDetail.
    self.destroyed=true; self.visible=false
    self.aurora:destroy()
    if self.topBar then self.topBar:destroy() end
    if self.invBar then self.invBar:destroy() end
    if self.stopStrip then self.stopStrip();self.stopStrip=nil end
    for _,button in self.bundleButtons or {} do button:destroy() end
    if self.forge then self.forge:destroy()end
    Art.unbindProfile(self.identity)
    self.detailItem=nil; self.confirmation=false; self.opener=nil
    for _, connection in self.connections do connection:Disconnect() end
    for _, connection in self.rowConnections do connection:Disconnect() end
    for _, rows in self.rows do for _, row in rows do row:Destroy() end end
    if self.shopRoot.Parent then self.shopRoot.Visible=false end
    if self.inventoryRoot.Parent then self.inventoryRoot.Visible=false end
    table.clear(self.connections); table.clear(self.rowConnections)
    for _,section in self.sections do section:Destroy() end
    self.rows={Shop={},Inventory={}};self.sections={}
end

return Page
