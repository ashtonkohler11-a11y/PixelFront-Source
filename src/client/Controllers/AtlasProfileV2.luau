--!strict
-- PF - 3 Profile v2 (UI review 2026-10-26; Ashton approved board 06c: "Good, build it"). Fills Screens.Profile.PFProfileV2
-- (tools/atlas/author-pf3-profile-v2.luau). AtlasProfileScreen hands over while the layer exists; same screen API.
--   Hero    AtlasCommerceArt.bindProfile paints BannerArt / FrameArt / Crown / Flag / the avatar and DisplayName (the authored names);
--           here: your name ON your equipped nameplate (NameplateStyle: the plate's fill / rim / inner line / stars / caps, the name's
--           animated gradient; VIP without a style = static gold), the @handle, Matches / Wins / Best land, Stats ›.
--   Locker  the nine slots (3 x 3): each tile the item's own art (CosmeticArt) + its name; empty = "+" and a gold Shop chip; a tap
--           opens that slot's Inventory tab (context.openSlot), as before.
-- Pure helpers (V2.slotView, V2.plateLook, V2.numbers) are tested by tools/test-pf3-profile-v2.luau.
local V2={};V2.__index=V2
V2.ORDER={"Banner","Frame","Crown","Nameplate","Flag","Skin","VFX","Buildings","Missiles"}
local NEUTRAL={fill={"262c38","171b24"},transparency=.1,rim="3a4252",inner=nil,stars=false}

-- A slot's tile: {on, words, shop}. byId = Catalog.byId.
function V2.slotView(equipped: any,byId: any,slot: string): any
    local id=type(equipped)=="table" and equipped[slot] or nil
    local item=if type(id)=="string" then byId[id] else nil
    if item and item.category==slot then return {on=true,id=id,words=item.name,shop=false} end
    return {on=false,id=nil,words="",shop=true}
end
-- The plate under the name for a style key (nil = none): a style with a plate (NameplateStyle.plates) takes its fill, rim,
-- inner line, stars and caps; any other = the quiet glass pill.
function V2.plateLook(style: string?,plates: any): any
    local spec=if style then plates[style] else nil
    if not spec then return NEUTRAL end
    return {fill=spec.fill,transparency=spec.transparency,rim=spec.rim,inner=spec.inner,innerTransparency=spec.innerTransparency,
        stars=spec.stars==true,capL=spec.capL,capR=spec.capR}
end
-- The three lifetime numbers from the stats view (AtlasStatsModel.view).
function V2.numbers(view: any): (string,string,string)
    local s=type(view)=="table" and view.summary or nil
    local matches=s and tonumber(s.matches) or 0
    local wins=s and tonumber(s.wins) or 0
    -- best land: a 0..1 share, the best of the lifetime peak and each map's (as Stats v2)
    local land=type(view)=="table" and tonumber(view.peakLand) or nil
    for _,m in (type(view)=="table" and type(view.maps)=="table" and view.maps) or {} do
        local p=tonumber(m.peakLand);if p and (land==nil or p>land) then land=p end
    end
    return tostring(matches),tostring(wins),if land and land==land then tostring(math.floor(math.clamp(land,0,1)*100+.5)).."%" else "—"
end

local function find(root: Instance,path: string): any
    local node: any=root
    for part in string.gmatch(path,"[^.]+") do node=node and node:FindFirstChild(part) end
    return node
end

function V2.new(root: Frame,context: any): any
    local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
    local Catalog=require(Shared:WaitForChild("CosmeticCatalog"))
    local Style=require(script.Parent.NameplateStyle)
    local layer=root:WaitForChild("PFProfileV2")
    local canvas=layer:WaitForChild("Canvas")
    local self: any=setmetatable({root=root,layer=layer,canvas=canvas,context=context,connections={},visible=false,destroyed=false,
        Catalog=Catalog,Style=Style,CommerceArt=require(script.Parent.AtlasCommerceArt),Art=require(script.Parent.CosmeticArt),
        style=nil,tiles={}},V2)
    for _,n in root:GetChildren() do if n:IsA("GuiObject") and n~=layer and n.Name~="PFScrim" then n.Visible=false end end
    layer.Visible=true
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    local back=find(layer,"Top.Back")
    listen(back.Activated,function() if context.back then context.back() end end)
    local hit=back:FindFirstChild("PFHit");if hit then listen(hit.Activated,function() if context.back then context.back() end end) end
    local Line=require(script.Parent.TopbarLine)
    Line.keepRight(layer.Top,self.connections);Line.clearBelow(canvas,self.connections)
    local stats=find(canvas,"Hero.Stats")
    if stats then listen(stats.Activated,function() if context.openStats then context.openStats() end end) end
    local GOLD,LINE=Color3.fromHex("#ddbf76"),Color3.new(1,1,1)
    for _,slot in V2.ORDER do
        local tile=find(canvas,"Locker.Slot_"..slot)
        if not tile then continue end
        self.tiles[slot]=tile
        local rim=tile:FindFirstChild("Rim")
        local function lit(on: boolean) if rim then rim.Color=if on then GOLD else LINE;rim.Transparency=if on then 0 else .93 end end
        listen(tile.Activated,function() if context.openSlot then context.openSlot(slot) end end)
        listen(tile.MouseEnter,function() lit(true) end);listen(tile.MouseLeave,function() lit(false) end)
        listen(tile.SelectionGained,function() lit(true) end);listen(tile.SelectionLost,function() lit(false) end)
    end
    -- the styled name animates while the screen shows (one gradient; writes only on change)
    listen(game:GetService("RunService").RenderStepped,function()
        if self.visible and self.style then local g=find(canvas,"Hero.NamePlate.DisplayName.Style");if g then Style.animate(g,self.style,os.clock()) end end
    end)
    self:refresh()
    return self
end

function V2:paintPlate(style: string?)
    local plate=find(self.canvas,"Hero.NamePlate");if not plate then return end
    local Style=self.Style
    local look=V2.plateLook(style,Style.plates)
    local fillNode=plate.Fill
    local g=fillNode:FindFirstChild("Fill")
    if g then
        local points={};for i,v in look.fill do table.insert(points,ColorSequenceKeypoint.new((i-1)/math.max(1,#look.fill-1),Color3.fromHex(v))) end
        if #points==1 then table.insert(points,ColorSequenceKeypoint.new(1,Color3.fromHex(look.fill[1]))) end
        g.Color=ColorSequence.new(points)
    end
    fillNode.BackgroundTransparency=look.transparency
    local rim=fillNode:FindFirstChild("Rim");if rim then rim.Color=Color3.fromHex(look.rim) end
    local line=find(fillNode,"Inner.Line")
    if line then line.Transparency=if look.inner then (look.innerTransparency or 0) else 1;if look.inner then line.Color=Color3.fromHex(look.inner) end end
    local stars=fillNode:FindFirstChild("Stars");if stars then stars.Visible=look.stars end
    -- the caps: step 0 of the plate's glint strip (CosmeticLevelArt / CosmeticPackArt)
    local Shared=game:GetService("ReplicatedStorage").Shared
    local function cap(id: string?): any
        if not id then return nil end
        for _,name in {"CosmeticPackArt","CosmeticLevelArt"} do
            local m=Shared:FindFirstChild(name)
            local ok,art=pcall(function() return require(m :: any) end)
            local c=ok and art and art.caps and art.caps[id]
            if c and c.image~="" then return c end
        end
        return nil
    end
    for side,id in {CapL=look.capL,CapR=look.capR} do
        local node=plate:FindFirstChild(side)
        if node then
            local c=cap(id)
            node.Visible=c~=nil
            if c then node.Image=c.image;node.ImageRectOffset=Vector2.zero;node.ImageRectSize=Vector2.new(c.w,c.h) end
        end
    end
    -- the name: the style's gradient over white (NameplateStyle.apply), or plain white
    local name=plate.DisplayName
    name.TextColor3=Color3.new(1,1,1)
    local grad=name:FindFirstChild("Style");if grad then Style.apply(grad,style) end
end

function V2:refresh()
    if self.destroyed then return end
    local Players=game:GetService("Players")
    local player=Players.LocalPlayer
    local state=if self.context.getCommerce then self.context.getCommerce() else nil
    local profile=if type(state)=="table" and type(state.profile)=="table" then state.profile else {}
    local equipped=if type(profile.equipped)=="table" then profile.equipped else {}
    local hero=self.canvas.Hero
    self.CommerceArt.bindProfile(hero,{userId=player and player.UserId,displayName=player and player.DisplayName,name=player and player.Name,
        equipped=equipped,cosmetics=profile.identityCosmetics})
    -- no frame worn: a thin rim keeps the avatar box tidy
    local frameArt=find(hero,"Bust.FrameArt");local avatarRim=find(hero,"Bust.AvatarBack.AvatarRim")
    if avatarRim then avatarRim.Enabled=not (frameArt and frameArt.Visible) end
    find(hero,"FlagBack").Visible=find(hero,"FlagBack.Flag").Visible
    hero.Handle.Text=if player then "@"..player.Name else ""
    -- the nameplate: the equipped style, else VIP gold, else plain
    local style=self.Style.of(equipped.Nameplate)
    if not style and player and self.Style.vipUser(player.UserId) then style="vip" end
    self.style=style
    self:paintPlate(style)
    local m,w,l=V2.numbers(if self.context.getStats then self.context.getStats() else nil)
    hero.Matches.Value.Text=m;hero.Wins.Value.Text=w;hero.BestLand.Value.Text=l
    for _,slot in V2.ORDER do
        local tile=self.tiles[slot];if not tile then continue end
        local view=V2.slotView(equipped,self.Catalog.byId,slot)
        local art=find(tile,"Well.Art")
        if art then self.Art.bind(art,view.id);art.Visible=view.on end
        find(tile,"Well.Plus").Visible=not view.on
        tile.ItemName.Visible=view.on;tile.ItemName.Text=view.words
        tile.Chevron.Visible=view.on;tile.Shop.Visible=view.shop
    end
end
function V2:update(_model: any) if self.visible then self:refresh() end end
function V2:setVisible(value: boolean)
    self.visible=value
    if value then self:refresh() end
end
function V2:focusActive()
    local first=self.tiles.Banner
    if first then game:GetService("GuiService").SelectedObject=first end
end
function V2:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    table.clear(self.connections)
    self.CommerceArt.unbindProfile(self.canvas.Hero)
end
return V2
