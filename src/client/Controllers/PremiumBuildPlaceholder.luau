--!strict
-- PLACEHOLDER (PF044 Arsenal Phase 1, PF - 2 2026-10-24). TEMPORARY UI: PF - 1 replaces all of this in Phase 4 with
-- authored dock slots and the real map sprites (MONETIZATION-SETS.md "In-match visual spec"). Built at runtime on purpose,
-- so nothing here is authored content to preserve.
--   * a small "ARSENAL (placeholder)" row of buttons, one per premium building this player owns (name + next gold cost);
--   * click a button, then a tile of your land: BuildPremium {unitType = item id, targetId = tile};
--   * each premium building on the map is a coloured square with its letter (and level pips where an item has levels).
-- Reads the server's "Premium" State packet (PremiumItems.packet); never touches the match snapshot.
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes=require(Shared:WaitForChild("Remotes"))
local Arsenal=require(Shared:WaitForChild("ArsenalCatalog"))
-- PIVOT D12 Phase 4 (PF - 1): the map markers are the real sprites now (Shared.PremiumSprites: mask tinted by the owner
-- colour + overlay + the gold accent), sized like the base buildings (BuildingRenderer.presentationSize at the World's zoom;
-- faint while building, level-ups as gold pips).
-- PIVOT D12 Phase 4 (MM approved the frame): the slots are the authored Arsenal wing (Game.Controls.PFArsenalWing,
-- tools/atlas/author-pivot-arsenal-wing.luau): one Cards.Slot clone per option (icon from PremiumSprites.icons, the next
-- gold cost); arming one shares the dock's placement (CityController.premiumPlacement: the Placement panel words it, Cancel /
-- Esc / a blueprint end it). The Phase 1 bar is only a fallback for a place without the wing.
local Sprites=require(Shared:WaitForChild("PremiumSprites"))
local Feed=require(script.Parent.MatchPacketFeed)
local Match=require(Shared:WaitForChild("Config")).Arsenal.Match
local okRenderer,BuildingRenderer=pcall(require,script.Parent.BuildingRenderer)
-- PF - 4 building animations (Ashton 2026-10-27): a premium site rises in gold, paced by its construction, then lands
local okBuildAnim,BuildAnim=pcall(require,script.Parent.BuildAnim)
local okBuildAnimMath,BuildAnimMath=pcall(require,script.Parent.BuildAnimMath)
local ANIM=okBuildAnim and okBuildAnimMath
local M={}
-- the no-sprite fallback squares (premium reshuffle 2026-10-26: Longshot, Insurance and Bounty retired)
local LETTER={bank="$",tax_office="%",trade_guild="S",engineering_yard="E",tesla_coil="T",artillery="A",warden="W",barracks="B",training_camp="C",stock_exchange="X"}
local COLOR={bank=Color3.fromRGB(245,197,66),tax_office=Color3.fromRGB(230,210,150),trade_guild=Color3.fromRGB(255,225,120),engineering_yard=Color3.fromRGB(150,160,175),
    tesla_coil=Color3.fromRGB(90,230,255),artillery=Color3.fromRGB(132,148,82),warden=Color3.fromRGB(176,180,190),barracks=Color3.fromRGB(120,160,240),
    training_camp=Color3.fromRGB(200,170,110),stock_exchange=Color3.fromRGB(110,220,140)}
-- the dock's shares (author-pivot-arsenal-wing): one card, the gap between cards, each side pad, of the dock's width
local CARD,GAP,SIDE=0.0943396,0.00628931,0.00925926
-- the hover card's one line per item (the Shop's Arsenal facts, short); the costs ladder from Config.Arsenal.Match
local EFFECT={tesla_coil="Zaps the biggest enemy attack in range: −1.5% a second",artillery="Shells rivals in range: −1.5% troops every 10 s",
    airdrop="Drops 15% of your troops on land behind their lines",blitz_bomb="2.3× an Atom Bomb's blast, flies 1.5× faster · 1 SAM Launcher hit stops it",
    titan_bomb="1.6× a Hydrogen Bomb's blast · needs 2 SAM Launcher hits",bank="+2.5K gold a second · up to 2 · full output at 8:00",
    tax_office="+200 gold a second per City level (up to 12) · full output at 8:00",trade_guild="+12% trade gold · safe trade ships near your Ports · full output at 8:00",
    engineering_yard="Every build of yours finishes 2× faster",
    -- premium reshuffle (2026-10-25; PREMIUM-RESHUFFLE-SPEC.md)
    warden="A heavy shell on every attack on you inside its 66-tile ring: −6% every 20 s",
    barracks="Captures speed up your troop growth, up to +15%; it fades within a minute",
    training_camp="Then Train from its card: gold into troops, 45 s apart",
    stock_exchange="Then Invest from its card: 1.6× back in 3 minutes; a raider takes the stake"}
-- the slot / button order: Warfare, then Industry in its shelf order (the Armory rail's); an action sits right after its building
local ORDER={"tesla_coil","training_camp","artillery","barracks","blitz_bomb","airdrop","warden","titan_bomb",
    "engineering_yard","bank","tax_office","stock_exchange","trade_guild"}
-- once built, a Training Camp / Stock Exchange option is its action (PF - 2's packet: kind "train" / "invest", the same item id)
local ICON_OF={}
-- seconds as the slots show them: "45s", or "2:14" from a minute up
local function clock(seconds: number): string
    seconds=math.max(0,math.ceil(seconds))
    if seconds<60 then return seconds.."s" end
    return string.format("%d:%02d",seconds//60,seconds%60)
end
local function short(n: number): string
    if n>=1e6 then return string.format("%.1fM",n/1e6) elseif n>=1e3 then return string.format("%dK",math.floor(n/1e3)) end
    return tostring(n)
end
function M.start()
    local player=Players.LocalPlayer
    local playerGui=player:WaitForChild("PlayerGui")
    local gui=playerGui:WaitForChild("OpenFront")
    local gameUI=gui:WaitForChild("Background"):WaitForChild("Game") :: GuiObject
    local MatchController=require(script.Parent.MatchController)
    local panel=MatchController.mapPanel(gui,gameUI,playerGui)
    local world=panel:WaitForChild("Viewport"):WaitForChild("World") :: GuiObject
    local remotes=Remotes.client()
    local City=require(script.Parent.CityController)
    local controls=gameUI:FindFirstChild("Controls")
    local wing=controls and controls:FindFirstChild("PFArsenalWing") :: any
    -- v4 (Ashton picked "option 2", MM 2026-10-25): Controls.PFArsenalGrid holds the owned items (its Cards.Slot is the template,
    -- Cards.ShopCell the last cell); the wing holds only Cards.PremiumKey (opens the grid) or, owning nothing, Cards.ShopTile.
    -- Game.PFArsenalShade closes the grid on a tap outside. A v3 place (Slot in the wing) keeps the row.
    local grid=controls and controls:FindFirstChild("PFArsenalGrid") :: any
    -- PF - 3 variant C (Ashton 2026-10-27: "C is perfect just make sure its a scroll frame and showing like 3 at a time"):
    -- Game.PFPremiumRail (author-pf3-premium-rail) replaces the wing + grid: every premium item as a hero card in its List
    -- (owned first, then locked; the last row opens the Armory), the Invest card beside it. With the rail, "wing" is the rail.
    local rail=gameUI:FindFirstChild("PFPremiumRail") :: any
    if rail then wing=rail;grid=nil end
    local slotTemplate=(rail and rail.Templates:FindFirstChild("Card")) or (grid and grid.Cards:FindFirstChild("Slot")) or (wing and wing:FindFirstChild("Cards") and wing.Cards:FindFirstChild("Slot"))
    if not slotTemplate then wing=nil;grid=nil;rail=nil end
    local premiumKey=grid and wing.Cards:FindFirstChild("PremiumKey");local shopTile=grid and wing.Cards:FindFirstChild("ShopTile")
    local shopCell=grid and grid.Cards:FindFirstChild("ShopCell");local shade=grid and gameUI:FindFirstChild("PFArsenalShade")
    local gridOpen=false
    -- v6: the Stock Exchange's Invest card (paintInvest); with the rail it sits in rail.InvestHolder
    local investCard=(if rail then rail:FindFirstChild("PFInvestCard",true) else grid and grid:FindFirstChild("PFInvestCard")) :: any
    local investOpen=false
    local function setGrid(open: boolean)
        if not grid then return end
        gridOpen=open;grid.Visible=open;if shade then shade.Visible=open end
        if not open then investOpen=false;if investCard then investCard.Visible=false end end
        if premiumKey then premiumKey:SetAttribute("BlueprintSelected",open) end
        if not open then City.premiumTip(nil) end
    end
    -- the Shop (the tile with nothing owned, the grid's last cell): the in-match Shop over the live match, on Arsenal
    -- (MatchController's MatchPacketFeed.context.openArsenal: AtlasMenu's locked shop; Back returns to the match)
    local function openShop(item: string?)
        setGrid(false);investOpen=false;if investCard then investCard.Visible=false end
        local open=Feed.context and Feed.context.openArsenal
        if open then pcall(open,item) end -- the rail's locked card opens the Armory on that item
    end
    if grid then
        if premiumKey then premiumKey.Activated:Connect(function() setGrid(not gridOpen) end) end
        for _,k in {shopTile,shopCell} do if k then k.Activated:Connect(function() openShop() end) end end
        if shade then shade.Activated:Connect(function() setGrid(false) end) end
    end
    local screen=Instance.new("ScreenGui");screen.Name="PF044ArsenalPlaceholder";screen.ResetOnSpawn=false;screen.DisplayOrder=50
    screen.Enabled=false;screen.Parent=playerGui
    local bar=Instance.new("Frame");bar.Name="Bar";bar.AnchorPoint=Vector2.new(.5,1);bar.Position=UDim2.new(.5,0,1,-150)
    bar.Size=UDim2.fromOffset(0,40);bar.AutomaticSize=Enum.AutomaticSize.X;bar.BackgroundColor3=Color3.fromRGB(20,24,30);bar.BackgroundTransparency=.15
    bar.Parent=screen
    local list=Instance.new("UIListLayout");list.FillDirection=Enum.FillDirection.Horizontal;list.Padding=UDim.new(0,6);list.Parent=bar
    local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,6);pad.PaddingRight=UDim.new(0,6);pad.PaddingTop=UDim.new(0,4);pad.PaddingBottom=UDim.new(0,4);pad.Parent=bar
    local tag=Instance.new("TextLabel");tag.Name="Tag";tag.Size=UDim2.fromOffset(150,32);tag.BackgroundTransparency=1;tag.TextColor3=Color3.fromRGB(255,170,80)
    tag.Font=Enum.Font.GothamBold;tag.TextSize=13;tag.Text="ARSENAL (placeholder)";tag.LayoutOrder=0;tag.Parent=bar
    -- PIVOT D12 (PF - 2's live test: the placing click also reached the map and sent an attack): while placing, a full-screen
    -- invisible catcher under the bar takes the click. MatchController's isMapPointer sees a GuiObject over the map and leaves it.
    local catcher=Instance.new("TextButton");catcher.Name="PlacementCatcher";catcher.Text="";catcher.AutoButtonColor=false;catcher.BackgroundTransparency=1
    catcher.Size=UDim2.fromScale(1,1);catcher.ZIndex=0;catcher.Visible=false;catcher.Selectable=false;catcher.Parent=screen
    -- with the wing, the catcher lies on the map's own layer (over the Viewport, not in World): the HUD above it (the dock,
    -- the wing, Placement's Cancel) keeps its clicks, and isMapPointer still sees a non-map object and leaves the click
    if wing then catcher.ZIndex=50;catcher.Parent=panel end
    local holdCatcher=0 -- the catcher outlives the placing click a moment, so the map's own InputEnded still meets it
    local layer=Instance.new("Folder");layer.Name="PF044PremiumPlaceholder";layer.Parent=world
    local latest: any=nil
    local placing: string?=nil
    local buttons: {[string]: TextButton}={}
    local optionKind: {[string]: string}={}
    local markers: {[number]: Frame}={}
    -- PF - 4: a site's whole build time = what was left when it was first seen (the packet has only the finish tick; an
    -- Engineering Yard halves it), capped at the configured construction ticks
    local buildTotal: {[number]: number}={}
    local okArsenal,ArsenalConfig=pcall(function() return (require(Shared:WaitForChild("Config")) :: any).Arsenal.Match end)
    local CONSTRUCTION=(okArsenal and ArsenalConfig and ArsenalConfig.ConstructionTicks) or 50
    local arm: (item: string)->()
    local act: (item: string)->() -- an action slot (Train / Invest): no placing (defined below)
    local paintSlots: (()->())?=nil -- the slots' live states (defined below, with the match timing)
    local liveState: any=nil -- the match state (gold, silos) from MatchPacketFeed
    local drawLater: (()->())?=nil
    local lastPhase: any=nil
    -- premium is off in the tutorial and in Ranked (MatchService grants none; CosmeticService's build gate): no wing, no Shop
    -- tile there (MM QA 2026-10-26, RELEASE-QA §5 #7: the tutorial dock showed "Arm…"). The packet's tutorialMatch, the config's
    -- gameType "Ranked", or a server premiumOff flag
    local premiumOff=false
    Feed.subscribe(function(p: any) if type(p)=="table" and type(p.state)=="table" then
        local off=p.premiumOff==true or p.tutorialMatch==true or (p.state.gameConfig or {}).gameType=="Ranked"
        if off~=premiumOff then premiumOff=off;if drawLater then task.defer(drawLater) end end
        liveState=p.state;if paintSlots then paintSlots() end
        -- no Premium packet yet (nobody owns an item): the Shop tile follows the match state (drawn when its phase changes)
        if latest==nil and drawLater and p.state.phase~=lastPhase then lastPhase=p.state.phase;drawLater() end
    end end)
    -- a slow, faint gold shine across a slot, once per hover (nothing at rest; none with reduced motion)
    local TweenService=game:GetService("TweenService")
    local function shine(slot: any)
        local band=slot:FindFirstChild("PFShine");local gradient=band and band:FindFirstChildOfClass("UIGradient")
        if not gradient or gameUI:GetAttribute("PFHudMotionRunning")==false then return end
        band.Visible=true;gradient.Offset=Vector2.new(-1.2,0)
        local t=TweenService:Create(gradient,TweenInfo.new(.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Offset=Vector2.new(1.2,0)})
        t.Completed:Once(function() band.Visible=false end);t:Play()
    end
    -- ---------------------------------------------------------------- the rail (variant C): hero cards, owned then locked
    local Rail=require(script.Parent.PremiumRail)
    local okShowcase,Showcase=pcall(require,script.Parent.ArmoryShowcase)
    local catalogIds={};for _,it in Arsenal.items do table.insert(catalogIds,it.id) end
    local locks: {[string]: any}={} -- the locked items' cards
    local allRow: any=nil
    -- a card's face: the Armory hero's first frame (greyed when locked), the name, the rim
    local function railLook(card: any,item: string,locked: boolean)
        local hero=okShowcase and (Showcase :: any).items[item]
        card.Art.Image=if hero then hero.sheet else ""
        -- locked: the art shows at ~40% under the lock (UI audit build-out 2026-10-28: at 78/255 the cards read as black boxes)
        card.Art.ImageColor3=if locked then Color3.fromRGB(118,120,128) else Color3.new(1,1,1)
        -- the label is the child "Name" (card.Name is the card's own Name string): FindFirstChild
        local label=card:FindFirstChild("Name")
        if label then
            label.Text=(Arsenal.byId[item] and Arsenal.byId[item].name) or item
            label.TextColor3=if locked then Color3.fromRGB(201,207,219) else Color3.new(1,1,1)
        end
        card.Lock.Visible=locked;card.Icon.Visible=not locked
        local rim=card:FindFirstChild("Rim")
        if rim then rim.Color=if locked then Color3.fromRGB(47,55,71) else Color3.fromRGB(255,211,106);rim.Transparency=if locked then 0 else .45 end
        -- UI audit build-out 2026-10-28 (UiMotion): a card you own breathes its gold rim softly (.45 -> .85, 2.4 s, inside the
        -- card) while it shows; once per card
        if rim and rim:IsA("UIStroke") and not locked and not card:GetAttribute("PFRimGlow") then
            local ok,Motion=pcall(function() return require(script.Parent.UiMotion) end)
            if ok and type(Motion)=="table" and type(Motion.glow)=="function" then card:SetAttribute("PFRimGlow",true);Motion.glow(rim,{lo=.45,hi=.85}) end
        end
    end
    -- a locked item: tap opens the Armory on it; hover (desk) shows its tip
    local function lockedCard(item: string): any
        local card=locks[item];if card then return card end
        card=slotTemplate:Clone();card.Name="Locked_"..item;card.Visible=true
        card:SetAttribute("PFPremiumItem",item);card:SetAttribute("PFRailLocked",true)
        railLook(card,item,true)
        local it=Arsenal.byId[item]
        card.Cost.Text=Rail.lockedChip(it and it.cobalt);card.Cost.TextColor3=Color3.fromRGB(223,232,255)
        card.Cost.BackgroundColor3=Color3.fromRGB(18,28,58)
        local chipRim=card.Cost:FindFirstChild("Rim");if chipRim then chipRim.Color=Color3.fromRGB(60,95,184) end
        card.Activated:Connect(function() City.premiumTip(nil);openShop(item) end)
        card.MouseEnter:Connect(function() City.premiumTip(card) end)
        card.MouseLeave:Connect(function() City.premiumTip(nil) end)
        card.Parent=rail.List;locks[item]=card
        return card
    end
    -- every row's place in the List's canvas (pure scale), the head's count; packet nil = nothing owned
    local function paintRail(packet: any?)
        if not rail then return end
        local owned={};for _,o in (packet and packet.options) or {} do owned[o.item]=true end
        for id,card in locks do if owned[id] then card:Destroy();locks[id]=nil end end
        if not allRow then
            allRow=rail.Templates.All:Clone();allRow.Visible=true;allRow.Parent=rail.List
            allRow.Activated:Connect(function() openShop() end)
        end
        local rows=Rail.rows(ORDER,owned,catalogIds)
        local scale,spots=Rail.layout(rows,Rail.SPEC)
        local n=0
        for i,row in rows do
            local node=if row.kind=="all" then allRow elseif row.kind=="owned" then buttons[row.id] else lockedCard(row.id)
            if not node then continue end
            if row.kind=="owned" then n+=1 end
            local s=spots[i];node.Position=UDim2.fromScale(s.x,s.y);node.Size=UDim2.fromScale(s.w,s.h)
        end
        -- CanvasSize's Scale reads against the ScrollingFrame's parent (the rail): the List's own share, times the content
        local ls=rail.List.Size
        rail.List.CanvasSize=UDim2.new(ls.X.Scale,0,ls.Y.Scale*scale,0)
        rail.Head.Count.Text=n.." / "..#catalogIds
        local label=allRow:FindFirstChild("Label");if label then label.Text="All "..#catalogIds.." in the Armory ›" end
    end
    local function draw()
        local packet=latest
        if rail and not packet then -- the rail, owning nothing (no Premium packet): every item locked, while playing
            local playing=gameUI.Visible and liveState~=nil and liveState.phase=="Playing" and not premiumOff
            rail.Visible=playing;screen.Enabled=false;investOpen=false;if investCard then investCard.Visible=false end
            if playing then paintRail(nil) end
            for id,m in markers do m:Destroy();markers[id]=nil end
            return
        end
        if grid and not packet then -- v4: owning nothing (no Premium packet): just the Shop tile, while playing
            local playing=gameUI.Visible and liveState~=nil and liveState.phase=="Playing" and not premiumOff
            wing.Visible=playing;premiumKey.Visible=false;shopTile.Visible=true
            screen.Enabled=false;if gridOpen then setGrid(false) end
            for id,m in markers do m:Destroy();markers[id]=nil end
            return
        end
        local show=packet~=nil and gameUI.Visible and (#packet.options>0 or grid~=nil or rail~=nil) and not premiumOff -- v4: the Shop tile shows with nothing owned
        screen.Enabled=show;bar.Visible=wing==nil -- with the wing the ScreenGui keeps only the aim note
        if wing then wing.Visible=show end
        if rail and not show then investOpen=false;if investCard then investCard.Visible=false end end
        if grid and not show and gridOpen then setGrid(false) end
        catcher.Visible=show and (placing~=nil or os.clock()<holdCatcher)
        if not packet then for id,f in markers do f:Destroy();markers[id]=nil end;return end
        local seen={}
        -- Phase 3: "build" / "launch" per item (reshuffle: "train" / "invest" once the building stands)
        local entries=table.clone(packet.options)
        for _,option in entries do
            seen[option.item]=true
            optionKind[option.item]=option.kind or "build"
            local b=buttons[option.item]
            if not b and wing then
                local item=option.item
                local slot=slotTemplate:Clone();slot.Name=item;slot.Visible=true
                slot.LayoutOrder=table.find(ORDER,item) or 20
                local rect=Sprites.icons and Sprites.icons.rects[ICON_OF[item] or item]
                if rect then slot.Icon.Image=Sprites.icons.image;slot.Icon.ImageRectOffset=Vector2.new(rect.x,rect.y);slot.Icon.ImageRectSize=Vector2.new(rect.w,rect.w) end
                slot.Active=true;slot:SetAttribute("PFPremiumItem",item)
                if rail then railLook(slot,item,false) end
                -- the base slot's hover card on desk (the dock's BlueprintTooltip) + the shine; on touch the same card on a long
                -- press (its release never arms)
                local suppress,holding=0,0
                slot.Activated:Connect(function() if os.clock()<suppress then return end;if optionKind[item]=="train" or optionKind[item]=="invest" then act(item) else arm(item) end end)
                slot.MouseEnter:Connect(function() slot:SetAttribute("Hovered",true);City.premiumTip(slot);shine(slot) end)
                slot.MouseLeave:Connect(function() slot:SetAttribute("Hovered",nil);City.premiumTip(nil) end)
                local function touchInput(input: InputObject): boolean
                    return input.UserInputType==Enum.UserInputType.Touch or (input.UserInputType==Enum.UserInputType.MouseButton1 and UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
                end
                slot.InputBegan:Connect(function(input: InputObject)
                    if not touchInput(input) then return end
                    local id=os.clock();holding=id
                    task.delay(.45,function()
                        if holding~=id then return end
                        suppress=math.huge;slot:SetAttribute("PFLongPress",true);City.premiumTip(slot)
                    end)
                end)
                slot.InputEnded:Connect(function(input: InputObject)
                    if not touchInput(input) then return end
                    holding=0
                    if slot:GetAttribute("PFLongPress") then slot:SetAttribute("PFLongPress",nil);City.premiumTip(nil);suppress=os.clock()+.3 end
                end)
                slot.Parent=if rail then rail.List elseif grid then grid.Cards else wing.Cards;b=slot;buttons[item]=slot
            end
            if not b then
                b=Instance.new("TextButton");b.Name=option.item;b.Size=UDim2.fromOffset(150,32);b.Font=Enum.Font.GothamBold;b.TextSize=13
                b.TextColor3=Color3.new(1,1,1);b.AutoButtonColor=true;b.LayoutOrder=table.find(ORDER,option.item) or 20
                local item=option.item
                b.Activated:Connect(function() arm(item) end)
                b.Parent=bar;buttons[option.item]=b
            end
            local name=(Arsenal.byId[option.item] and Arsenal.byId[option.item].name) or option.item
            local cooling=type(option.readyTick)=="number" and option.readyTick>packet.ticks
            if wing then
                (b :: any):SetAttribute("PFPremiumName",name) -- its states: paintSlots
            else
                b.Text=if cooling then name.." (cooldown)" elseif option.cost then name.." "..short(option.cost) else name.." (max)"
                b.BackgroundColor3=if placing==option.item then Color3.fromRGB(60,120,200) else Color3.fromRGB(45,52,62)
            end
        end
        for id,b in buttons do if not seen[id] then b:Destroy();buttons[id]=nil end end
        if rail then -- variant C: owned + locked cards in the List
            if show then paintRail(packet) end
            if paintSlots then paintSlots() end
        elseif grid then -- v4: the key (owned items) or the Shop tile (nothing owned); the grid's header counts them
            local n=#entries
            premiumKey.Visible=n>0;shopTile.Visible=n==0
            local owned=#packet.options
            local count=premiumKey:FindFirstChild("Count");if count then count.Text="×"..owned;count.Visible=owned>0 end
            grid.Header.Text="Premium · "..owned.." owned"
            if n==0 and gridOpen then setGrid(false) end
            if paintSlots then paintSlots() end
        elseif wing then -- v3: as wide as its slots (up to 5; more scroll)
            local n=math.clamp(#entries,1,5);local share=n*CARD+(n-1)*GAP+2*SIDE
            if math.abs(wing.Size.X.Scale-share)>1e-4 then
                wing.Size=UDim2.new(share,0,wing.Size.Y.Scale,wing.Size.Y.Offset)
                local row=wing.Cards:FindFirstChildOfClass("UIListLayout");if row then row.Padding=UDim.new(GAP/share,0) end
                local pad=wing.Cards:FindFirstChildOfClass("UIPadding");if pad then pad.PaddingLeft=UDim.new(SIDE/share,0);pad.PaddingRight=UDim.new(SIDE/share,0) end
            end
            for _,slot in buttons do (slot :: any).Size=UDim2.new(CARD/share,0,1,0) end
            if paintSlots then paintSlots() end
        end
        local live={}
        local sprites=Sprites.ready()
        -- the base buildings' display size at this zoom (px per tile = the World's width / the map's)
        local zoom=world.AbsoluteSize.X/math.max(1,packet.width)
        local basePx=if okRenderer then (BuildingRenderer :: any).presentationSize(zoom,nil) else 24
        local sheet=Sprites.sheet(basePx)
        for _,building in packet.buildings do
            live[building.id]=true
            local f=markers[building.id]
            if not f then
                f=Instance.new("Frame");f.Name="P"..building.id;f.AnchorPoint=Vector2.new(.5,.5);f.BorderSizePixel=0;f.ZIndex=20
                if sprites then
                    f.BackgroundTransparency=1
                    for i,name in Sprites.layers do
                        local img=Instance.new("ImageLabel");img.Name=name;img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.ZIndex=20+i;img.Parent=f
                    end
                    local pips=Instance.new("Frame");pips.Name="Pips";pips.BackgroundTransparency=1;pips.AnchorPoint=Vector2.new(.5,1)
                    pips.Position=UDim2.new(.5,0,0,-1);pips.Size=UDim2.fromScale(1,.16);pips.ZIndex=24;pips.Parent=f
                    local list=Instance.new("UIListLayout");list.FillDirection=Enum.FillDirection.Horizontal;list.HorizontalAlignment=Enum.HorizontalAlignment.Center
                    list.Padding=UDim.new(.04,0);list.Parent=pips
                    for i=1,3 do
                        local p=Instance.new("Frame");p.Name="Pip"..i;p.Size=UDim2.fromScale(.15,1);p.BackgroundColor3=Color3.fromRGB(255,211,106);p.BorderSizePixel=0;p.ZIndex=25
                        local a=Instance.new("UIAspectRatioConstraint");a.AspectRatio=1;a.DominantAxis=Enum.DominantAxis.Height;a.Parent=p
                        local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=p
                        local s=Instance.new("UIStroke");s.Color=Color3.fromRGB(90,61,0);s.Thickness=1;s.Parent=p
                        p.Parent=pips
                    end
                else
                    local text=Instance.new("TextLabel");text.Name="Letter";text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextScaled=true
                    text.Font=Enum.Font.GothamBlack;text.TextColor3=Color3.fromRGB(20,20,20);text.ZIndex=21;text.Parent=f
                end
                f.Parent=layer;markers[building.id]=f
            end
            local x,y=(building.tile-1)%packet.width,(building.tile-1)//packet.width
            f.Position=UDim2.fromScale((x+.5)/packet.width,(y+.5)/packet.height)
            local building_=packet.ticks<building.built -- under construction: faint
            local cell=sheet.items[building.item]
            if sprites and cell then
                local px=math.round(basePx*(Sprites.scale[building.item] or 1))
                f.Size=UDim2.fromOffset(px,px)
                local owner=Feed.context and Feed.context.ownerColor and Feed.context.ownerColor(building.owner)
                for i,name in Sprites.layers do
                    local img=f:FindFirstChild(name) :: ImageLabel
                    if img.Image~=sheet.image then img.Image=sheet.image end
                    img.ImageRectOffset=Vector2.new(cell.x+(i-1)*cell.cell,cell.y);img.ImageRectSize=Vector2.new(cell.cell,cell.cell)
                    img.ImageTransparency=if building_ and not ANIM then .5 else 0
                    if name=="Mask" then img.ImageColor3=if typeof(owner)=="Color3" then owner else Color3.fromRGB(150,150,150) end
                end
                if ANIM then
                    local total=buildTotal[building.id]
                    if not total then total=math.clamp(building.built-packet.ticks,1,CONSTRUCTION);buildTotal[building.id]=total end
                    local layers={};for _,name in Sprites.layers do local img=f:FindFirstChild(name);if img then table.insert(layers,img) end end
                    (BuildAnim :: any).site(f,layers,(BuildAnimMath :: any).premiumProgress(building.built,packet.ticks,total),
                        {premium=true,mine=building.owner==1,fresh=false,px=px,pop=f})
                end
                local pips=f:FindFirstChild("Pips")
                if pips then for i=1,3 do (pips :: any)["Pip"..i].Visible=i<=(building.level or 0) end end
            else
                f.Size=UDim2.fromScale(6/packet.width,6/packet.height)
                f.BackgroundColor3=COLOR[building.item] or Color3.new(1,1,1)
                f.BackgroundTransparency=if building_ then .55 else 0 -- faint while under construction
                local letter=f:FindFirstChild("Letter") :: TextLabel?
                if letter then letter.Text=(LETTER[building.item] or "?")..(if (building.level or 0)>0 then string.rep("+",building.level) else "") end
            end
        end
        for id,f in markers do if not live[id] then f:Destroy();markers[id]=nil;buildTotal[id]=nil end end
    end
    -- ---------------------------------------------------------------- Phase 3: projectiles in flight + event FX
    -- projectiles {id, owner, item, from, to, launched, arrive, hits}: a straight line, pos = lerp(from, to, progress), drawn
    -- with PremiumSprites.weapons (Blitz / Titan: the owner-tinted bands + the fixed Accent; the Airdrop plane, turned to its
    -- heading). events {id, kind, item, owner, tile, landed?}: one-shot rings (detonate / intercepted / airdrop / hit).
    local Tween=game:GetService("TweenService")
    local okConfig,Config=pcall(require,Shared:WaitForChild("Config"))
    local STEP=(okConfig and (Config :: any).Match and (Config :: any).Match.StepSeconds) or .1
    local receivedAt=os.clock()
    local shots: {[number]: any}={}
    local lastEvent: number?=nil
    local SIZE={blitz_bomb=13,titan_bomb=17,airdrop=16} -- tiles (the base nukes draw 13)
    local function ownerColor(owner: any): Color3
        local c=Feed.context and Feed.context.ownerColor and Feed.context.ownerColor(owner)
        return if typeof(c)=="Color3" then c else Color3.fromRGB(150,150,150)
    end
    local function tileXY(tile: number,w: number): (number,number) return (tile-1)%w,(tile-1)//w end
    local function shotFrame(p: any): any
        local w=Sprites.weapons;if w.image=="" then return nil end
        local f=Instance.new("Frame");f.Name="Shot"..p.id;f.BackgroundTransparency=1;f.AnchorPoint=Vector2.new(.5,.5);f.ZIndex=40
        local function layer(name: string,rect: any,color: Color3?)
            local img=Instance.new("ImageLabel");img.Name=name;img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=w.image
            img.ImageRectOffset=Vector2.new(rect.x,rect.y);img.ImageRectSize=Vector2.new(rect.w,rect.h);img.ResampleMode=Enum.ResamplerMode.Pixelated
            if color then img.ImageColor3=color end;img.ZIndex=41;img.Parent=f
        end
        local col=ownerColor(p.owner)
        if p.item=="airdrop" then layer("Plane",w.rects["Airdrop.43"])
        else
            local key=if p.item=="titan_bomb" then "TitanBomb" else "BlitzBomb"
            layer("Territory",w.rects[key..".Territory"],col:Lerp(Color3.new(1,1,1),.45));layer("Mid",w.rects[key..".Mid"],col);layer("Accent",w.rects[key..".Accent"])
        end
        f.Parent=layer and world;return f
    end
    local function fx(e: any,packet: any)
        if type(e.tile)~="number" then return end
        local radius=({detonate=(if e.item=="titan_bomb" then 105 else 32),intercepted=5,airdrop=12,hit=6})[e.kind];if not radius then return end
        local color=({detonate=Color3.fromRGB(255,150,50),intercepted=Color3.new(1,1,1),airdrop=Color3.fromRGB(143,231,255),hit=Color3.fromRGB(255,200,90)})[e.kind]
        local x,y=tileXY(e.tile,packet.width)
        local r=Instance.new("Frame");r.Name="FX"..tostring(e.id);r.AnchorPoint=Vector2.new(.5,.5);r.BackgroundColor3=color;r.BackgroundTransparency=.55;r.ZIndex=39
        r.Position=UDim2.fromScale((x+.5)/packet.width,(y+.5)/packet.height);r.Size=UDim2.fromScale(radius*.4/packet.width,radius*.4/packet.height)
        local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=r
        local st=Instance.new("UIStroke");st.Color=color;st.Thickness=2;st.Parent=r
        r.Parent=world
        local info=TweenInfo.new(if e.kind=="detonate" then .9 else .5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        Tween:Create(r,info,{Size=UDim2.fromScale(radius*2/packet.width,radius*2/packet.height),BackgroundTransparency=1}):Play()
        Tween:Create(st,info,{Transparency=1}):Play()
        task.delay(info.Time+.05,function() r:Destroy() end)
    end
    local function sync(packet: any)
        -- events: replay only the ones newer than the last seen (the first packet only sets the mark)
        local top=lastEvent or 0
        for _,e in packet.events or {} do
            if type(e.id)=="number" then
                if lastEvent~=nil and e.id>lastEvent then fx(e,packet) end
                top=math.max(top,e.id)
            end
        end
        lastEvent=top
        local seen={}
        for _,p in packet.projectiles or {} do
            seen[p.id]=true
            if not shots[p.id] then local f=shotFrame(p);if f then shots[p.id]={frame=f,p=p} end else shots[p.id].p=p end
        end
        for id,s in shots do if not seen[id] then s.frame:Destroy();shots[id]=nil end end
    end
    -- the premium nukes' aim (MM): a blast ring under the cursor while placing (Blitz 32 / Titan 88 tiles: Config), red with "Hits your
    -- land" when it covers your own territory (NukeSelfHit on the match state from MatchPacketFeed; no block)
    local NukeSelfHit=require(script.Parent.NukeSelfHit)
    local matchState: any=nil
    Feed.subscribe(function(p: any) if type(p)=="table" and type(p.state)=="table" then matchState=p.state end end)
    local BLAST={blitz_bomb=32,titan_bomb=105}
    -- touch: the pinned target (pin + Launch, as the base nukes); nil = nothing pinned yet
    local pinned: number?=nil
    local function touch(): boolean return UserInputService.TouchEnabled and not UserInputService.MouseEnabled end
    local aimRing=Instance.new("Frame");aimRing.Name="PFPremiumAim";aimRing.AnchorPoint=Vector2.new(.5,.5);aimRing.BackgroundColor3=Color3.new(1,1,1)
    aimRing.BackgroundTransparency=.92;aimRing.Visible=false;aimRing.ZIndex=38
    do local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=aimRing;local st=Instance.new("UIStroke");st.Name="Rim";st.Color=Color3.new(1,1,1);st.Thickness=2;st.Parent=aimRing end
    aimRing.Parent=world
    local aimNote=Instance.new("TextLabel");aimNote.Name="AimNote";aimNote.BackgroundColor3=Color3.fromRGB(12,14,20);aimNote.BackgroundTransparency=.15
    aimNote.TextColor3=Color3.fromHex("#ff5a4f");aimNote.Font=Enum.Font.GothamBold;aimNote.TextSize=13;aimNote.Text="Hits your land";aimNote.Size=UDim2.fromOffset(112,22)
    aimNote.AnchorPoint=Vector2.new(.5,0);aimNote.Visible=false;aimNote.ZIndex=60;aimNote.Parent=screen
    do local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.3,0);c.Parent=aimNote end
    game:GetService("RunService").RenderStepped:Connect(function()
        local packet=latest;local radius=placing and BLAST[placing]
        local onTouch=touch()
        if packet and radius and screen.Enabled and (pinned or not onTouch) then
            local m=UserInputService:GetMouseLocation()-game:GetService("GuiService"):GetGuiInset()
            local size,origin=world.AbsoluteSize,world.AbsolutePosition
            local x,y=math.floor((m.X-origin.X)/size.X*packet.width),math.floor((m.Y-origin.Y)/size.Y*packet.height)
            if onTouch and pinned then -- the ring sits on the pin; the note under it
                x,y=(pinned-1)%packet.width,(pinned-1)//packet.width
                m=Vector2.new(origin.X+(x+.5)/packet.width*size.X,origin.Y+(y+.5)/packet.height*size.Y+radius/packet.height*size.Y)
            end
            local inside=x>=0 and y>=0 and x<packet.width and y<packet.height
            local hit=inside and NukeSelfHit.covers(matchState,y*packet.width+x+1,radius)
            aimRing.Visible=inside;aimNote.Visible=hit
            aimRing.Position=UDim2.fromScale((x+.5)/packet.width,(y+.5)/packet.height);aimRing.Size=UDim2.fromScale(radius*2/packet.width,radius*2/packet.height)
            local col=if hit then Color3.fromHex("#ff5a4f") else Color3.new(1,1,1)
            aimRing.BackgroundColor3=col;aimRing.BackgroundTransparency=if hit then .85 else .92;(aimRing:FindFirstChild("Rim") :: UIStroke).Color=col
            aimNote.Position=UDim2.fromOffset(m.X,m.Y+18)
        else aimRing.Visible=false;aimNote.Visible=false end
    end)
    -- ---------------------------------------------------------------- the placement ghost (MM: as the base buildings')
    -- BuildingRenderer:drawGhost's look: the sprite at half transparency following the cursor, red where it can't go, the
    -- cost under it (a clone of the authored GhostCost), a range ring (a clone of IndustryGhostRange, the same ring textures):
    -- Tesla 24 / Artillery 22 / Warden 66 at the cursor, Airdrop 100 round your nearest
    -- silo. The checks mirror PremiumItems.build / launch, so the reason is the server's: Max n / Not your land / Too close.
    local Icons=require(script.Parent.ReferenceIcons)
    local Nukes=require(Shared:WaitForChild("OpenFrontNukes"))
    local RANGE={tesla_coil=Match.tesla_coil.Range,artillery=Match.artillery.Range,airdrop=Match.airdrop.Range}
    if (Match :: any).warden and (Match :: any).warden.Range then RANGE.warden=(Match :: any).warden.Range end -- PF - 4: the Warden's 66-tile ring while placing
    local ghostLayer=Instance.new("Folder");ghostLayer.Name="PFPremiumGhost";ghostLayer.Parent=world
    local ghost=Instance.new("Frame");ghost.Name="Ghost";ghost.AnchorPoint=Vector2.new(.5,.5);ghost.BackgroundTransparency=1;ghost.Visible=false;ghost.ZIndex=40
    for i,name in Sprites.layers do
        local img=Instance.new("ImageLabel");img.Name=name;img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.ZIndex=40+i;img.Parent=ghost
    end
    ghost.Parent=ghostLayer
    local authoredCost=world:FindFirstChild("GhostCost");local ghostCost=authoredCost and authoredCost:Clone()
    if ghostCost then ghostCost.Name="PremiumGhostCost";ghostCost.Visible=false;ghostCost.Parent=ghostLayer end
    local rangeLayer=world:FindFirstChild("IndustryRangeLayer");local authoredRange=rangeLayer and rangeLayer:FindFirstChild("IndustryGhostRange")
    local ghostRange=authoredRange and authoredRange:Clone()
    if ghostRange then ghostRange.Name="PremiumGhostRange";ghostRange.Visible=false;ghostRange.Parent=rangeLayer end
    local placeReason: string?=nil -- the hovered tile's refusal (word() shows it in the placement bar)
    local onReason: (()->())?=nil
    local function hideGhost() ghost.Visible=false;if ghostCost then ghostCost.Visible=false end;if ghostRange then ghostRange.Visible=false end end
    local function landAt(st: any,tile: number): boolean
        return typeof(st.map.terrain)=="buffer" and bit32.band(buffer.readu8(st.map.terrain,tile-1),128)~=0
    end
    local function nearestSilo(st: any,tile: number): (any?,number)
        local w=st.map.width;local x,y=(tile-1)%w,(tile-1)//w;local best,bd=nil,math.huge
        for _,silo in Nukes.ownedSilos(st,1) do
            local sx,sy=(silo.tileId-1)%w,(silo.tileId-1)//w;local d=math.sqrt((sx-x)^2+(sy-y)^2)
            if d<bd then best,bd=silo,d end
        end
        return best,bd
    end
    -- PremiumItems.build / launch, from the client's view: nil = it can go there
    local function refusal(item: string,tile: number): string?
        local st,packet=liveState,latest;if not st or not packet then return nil end
        local o=nil;for _,v in packet.options do if v.item==item then o=v;break end end
        local w=st.map.width
        if not o then return nil end
        local owner=st.owners[tile] or 0
        if o.kind=="build" then
            if owner~=1 or not landAt(st,tile) then return "Not your land" end
            if not o.cost then return "Max "..#(Match[item] and Match[item].Costs or {}) end
            if st.gold[1]<o.cost then return "Need "..short(o.cost-st.gold[1]).." more gold" end
            local x,y=(tile-1)%w,(tile-1)//w
            for _,b in packet.buildings do
                local bx,by=(b.tile-1)%w,(b.tile-1)//w
                if math.abs(bx-x)+math.abs(by-y)<Match.Spacing then return "Too close to a premium building" end
            end
            return nil
        end
        if o.cost and st.gold[1]<o.cost then return "Need "..short(o.cost-st.gold[1]).." more gold" end
        if item=="airdrop" then
            if not landAt(st,tile) or owner==1 then return "Drop on land you don't own" end
            if type(o.readyTick)=="number" and o.readyTick>packet.ticks then return "Airdrop is reloading" end
            local _,d=nearestSilo(st,tile);if d>Match.airdrop.Range then return "No Missile Silo within 100" end
        end
        return City.siloReason(st)
    end
    game:GetService("RunService").RenderStepped:Connect(function()
        local packet,st=latest,liveState
        if not placing or not packet or not st or not screen.Enabled then if ghost.Visible or (ghostRange and ghostRange.Visible) then hideGhost() end;return end
        local item=placing :: string
        local kind=optionKind[item]
        local onTouch=touch()
        local size,origin=world.AbsoluteSize,world.AbsolutePosition
        local w,h=packet.width,packet.height
        local zoom=size.X/math.max(1,w)
        -- the tile: the cursor's on desk; on touch the pin (a launch) or nothing yet
        local tile: number?=nil;local at: Vector2?=nil
        if onTouch then
            if pinned then tile=pinned;at=Vector2.new(((pinned-1)%w+.5)*zoom,((pinned-1)//w+.5)*zoom) end
        else
            local m=UserInputService:GetMouseLocation()-game:GetService("GuiService"):GetGuiInset()
            local x,y=math.floor((m.X-origin.X)/zoom),math.floor((m.Y-origin.Y)/zoom)
            if x>=0 and y>=0 and x<w and y<h and catcher.Visible then tile=y*w+x+1;at=m-origin end
        end
        local reason=if tile then refusal(item,tile) else nil
        if reason~=placeReason then placeReason=reason;if onReason then onReason() end end
        if not tile or not at then hideGhost();return end
        -- the sprite (buildings only; a launch's aim is the blast ring / the plane's line)
        local cell=nil;local sheet=nil
        if kind=="build" and Sprites.ready() then
            local basePx=if okRenderer then (BuildingRenderer :: any).presentationSize(zoom,nil) else 24
            sheet=Sprites.sheet(basePx);cell=sheet.items[item]
            if cell then
                local px=math.round(basePx*(Sprites.scale[item] or 1))
                ghost.Size=UDim2.fromOffset(px,px);ghost.Position=UDim2.fromOffset(at.X,at.Y)
                local own=Feed.context and Feed.context.ownerColor and Feed.context.ownerColor(1)
                local bad=Color3.new(.8,.2,.2)
                for i,name in Sprites.layers do
                    local img=ghost:FindFirstChild(name) :: ImageLabel
                    if img.Image~=sheet.image then img.Image=sheet.image end
                    img.ImageRectOffset=Vector2.new(cell.x+(i-1)*cell.cell,cell.y);img.ImageRectSize=Vector2.new(cell.cell,cell.cell)
                    img.ImageTransparency=.5
                    img.ImageColor3=if reason then (if name=="Mask" then bad else Color3.new(1,1,1):Lerp(bad,.5)) elseif name=="Mask" and typeof(own)=="Color3" then own else Color3.new(1,1,1)
                end
                ghost.Visible=true
            end
        end
        if not cell then ghost.Visible=false end
        -- the cost under it (as GhostCost: red when short, grey when it can't go)
        local o=nil;for _,v in packet.options do if v.item==item then o=v;break end end
        if ghostCost and kind=="build" and o and o.cost then
            ghostCost.Text=short(o.cost);ghostCost.Position=UDim2.fromOffset(at.X,at.Y-25)
            ghostCost.TextColor3=if st.gold[1]<o.cost then Color3.new(1,.3,.3) elseif reason then Color3.new(.6,.6,.6) else Color3.new(1,1,1)
            ghostCost.Visible=true
        elseif ghostCost then ghostCost.Visible=false end
        -- the range ring
        local radius=RANGE[item]
        if ghostRange and radius then
            local center=at
            if item=="airdrop" then
                local silo=nearestSilo(st,tile);if silo then local id=silo.tileId-1;center=Vector2.new((id%w+.5)*zoom,(id//w+.5)*zoom) else center=nil end
            end
            if center then
                Icons.bind(ghostRange,"IndustryRange"..(if radius>=60 then 110 else 30))
                ghostRange.Position=UDim2.fromOffset(center.X,center.Y);ghostRange.Size=UDim2.fromOffset((radius+1)*2*zoom,(radius+1)*2*zoom)
                ghostRange.ImageColor3=if reason then Color3.new(1,.45,.45) else Color3.new(1,1,1)
                ghostRange.Visible=true
            else ghostRange.Visible=false end
        elseif ghostRange then ghostRange.Visible=false end
    end)
    game:GetService("RunService").RenderStepped:Connect(function()
        local packet=latest;if not packet or next(shots)==nil then return end
        local now=packet.ticks+(os.clock()-receivedAt)/STEP
        for _,s in shots do
            local p=s.p;local fx0,fy0=tileXY(p.from,packet.width);local tx,ty=tileXY(p.to,packet.width)
            local t=math.clamp((now-p.launched)/math.max(1,p.arrive-p.launched),0,1)
            local x,y=fx0+(tx-fx0)*t,fy0+(ty-fy0)*t
            local n=SIZE[p.item] or 13
            s.frame.Position=UDim2.fromScale((x+.5)/packet.width,(y+.5)/packet.height);s.frame.Size=UDim2.fromScale(n/packet.width,n/packet.height)
            if p.item=="airdrop" then s.frame.Rotation=math.deg(math.atan2(ty-fy0,tx-fx0))+45 -- the plane art points up-right
            else s.frame.Rotation=math.deg(math.atan2(ty-fy0,tx-fx0))+90 end -- PF - 4: the missiles' art points up; nose along the flight
        end
    end)
    remotes.State.OnClientEvent:Connect(function(packet: any)
        if type(packet)~="table" then return end
        if packet.kind=="Home" then latest=nil;placing=nil;lastEvent=nil;for id,s in shots do s.frame:Destroy();shots[id]=nil end;draw();return end
        if packet.kind~="Premium" then return end
        if latest and type(packet.matchId)=="number" and type(latest.matchId)=="number" and packet.matchId<latest.matchId then return end
        if latest and packet.matchId~=latest.matchId then lastEvent=nil end
        latest=packet;receivedAt=os.clock();sync(packet);draw()
    end)
    gameUI:GetPropertyChangedSignal("Visible"):Connect(draw)
    drawLater=draw
    world:GetPropertyChangedSignal("AbsoluteSize"):Connect(draw) -- PIVOT D12: zoom re-sizes the sprites like the base buildings
    -- ---------------------------------------------------------------- the wing slots' live states (MM: base-slot parity)
    -- ready / short (red price: gold) / blocked (no ready silo, all built) / cooling (a sweep + seconds, not a word); armed =
    -- BlueprintSelected. BattleHudPresentation animates them from these attributes as it does the base slots.
    local cooldowns: {[string]: {from: number, to: number}}={}
    local function option(item: string): any?
        for _,o in (latest and latest.options) or {} do if o.item==item then return o end end
        return nil
    end
    local function owned(item: string): number
        local n=0;for _,b in (latest and latest.buildings) or {} do if b.item==item and b.owner==1 then n+=1 end end;return n
    end
    local function nowTicks(): number return if latest then latest.ticks+(os.clock()-receivedAt)/STEP else 0 end
    -- Train / Invest options (PF - 2: kind "train" / "invest" on the Training Camp / Stock Exchange once built; UsePremium)
    local function isAction(o: any): boolean return o.kind=="train" or o.kind=="invest" end
    -- when an option is next free: its readyTick, or (Invest) the running investment's end (active.ends)
    local function readyOf(o: any): number?
        if type(o.readyTick)=="number" then return o.readyTick end
        local inv=o.active;if type(inv)=="table" and type(inv.ends)=="number" then return inv.ends end
        return nil
    end
    local function stateOf(o: any): (string,string?)
       local r=readyOf(o)
        if type(r)=="number" and latest and r>nowTicks() then
            local left=(r-nowTicks())*STEP
            if type(o.built)=="number" and o.built>nowTicks() then return "cooling","Building… "..clock(left) end
            if o.kind=="invest" then return "cooling","Investing: "..clock(left).." left" end
            return "cooling",if o.kind=="train" then "Training… "..clock(left) else "Ready in "..math.ceil(left).." s"
        end
        -- the actions (premium reshuffle): Train is blocked at max troops, short on gold; Invest is always ready when free
        if isAction(o) then
            if o.full then return "blocked","At max troops" end
            local gold=liveState and liveState.gold and liveState.gold[1]
            if o.kind=="train" and type(o.cost)=="number" and gold and gold<o.cost then return "short","Need "..short(o.cost-gold).." more gold" end
            return "ready",nil
        end
        if o.kind=="launch" then local why=City.siloReason(liveState);if why then return "blocked",why end end
        if not o.cost then return "blocked","All built" end
        local gold=liveState and liveState.gold and liveState.gold[1]
        if gold and gold<o.cost then return "short","Need "..short(o.cost-gold).." more gold" end
        return "ready",nil
    end
    local pressed: {[string]: {untilAt: number, text: string}}={} -- Train's "+5K" beat after a press
    local wasCooling: {[string]: boolean}={}
    local function flash(s: any)
        local f=s:FindFirstChild("PFFlash");if not f then return end
        local stroke=f:FindFirstChildOfClass("UIStroke");f.Visible=true
        if stroke then stroke.Transparency=0;TweenService:Create(stroke,TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1}):Play() end
        task.delay(.95,function() f.Visible=false end)
    end
    local paintInvest: ()->()
    paintSlots=function()
        if not wing or not latest then return end
        for item,slot in buttons do
            local o=option(item);if not o then continue end
            local st=stateOf(o)
            local s: any=slot
            local r=readyOf(o)
            local beat=pressed[item];if beat and os.clock()>beat.untilAt then pressed[item]=nil;beat=nil end
            -- the action words (Train: price · "+5K" · seconds · "Full"; Invest: the stake · its countdown)
            local actionText=if not isAction(o) then nil
                elseif beat then beat.text
                elseif st=="cooling" and r then clock((r-nowTicks())*STEP)
                elseif o.full then "Full"
                elseif o.kind=="invest" and type(o.stake)=="number" then City.compactPrice(short(o.stake))
                elseif type(o.cost)=="number" then City.compactPrice(short(o.cost)) else nil
            s.Cost.Text=if actionText then actionText elseif st=="cooling" and r then clock((r-nowTicks())*STEP) elseif o.cost then City.compactPrice(short(o.cost)) else "Max"
            if beat then s.Cost.TextColor3=Color3.fromRGB(122,184,255) end
            -- ready again after a cooldown: one blue ring
            if wasCooling[item] and st~="cooling" and isAction(o) then flash(s) end
            wasCooling[item]=st=="cooling"
            if not beat then s.Cost.TextColor3=City.priceColor(if st=="cooling" then "blocked" else st) end
            -- the rail's action chips (the board): "Train +5.7K" / "Full" / "◷ 0:45"; "Invest" / "◷ 1:47" with a gold bar along the foot
            if rail then
                local left=if r then (r-nowTicks())*STEP else nil
                local chip=if isAction(o) and not beat then Rail.actionChip(o.kind,st=="cooling",left,o.full,o.troops) else nil
                if chip then s.Cost.Text=chip end
                local running=o.kind=="invest" and type(o.active)=="table"
                if running then s.Cost.TextColor3=Color3.fromRGB(255,211,106) end
                local bar=s:FindFirstChild("Bar")
                if bar then bar.Visible=running;if running and left then bar.Fill.Size=UDim2.fromScale(math.clamp(1-left/Match.stock_exchange.Seconds,0,1),1) end end
            end
            s:SetAttribute("HudBlocked",st=="blocked");s:SetAttribute("Affordable",st~="short")
            s:SetAttribute("BlueprintSelected",placing==item);s:SetAttribute("HudSlotState",st)
            s.Icon.ImageTransparency=if st=="blocked" then .72 else 0
            local count=s:FindFirstChild("Count")
            if count then local n=if o.kind=="build" then owned(item) else 0;count.Text="×"..n;count.Visible=n>0 end
            -- the cooldown: from the readyTick first seen to it (a new readyTick starts a new sweep)
            if st=="cooling" and r then
                local c=cooldowns[item];if not c or c.to~=r then c={from=math.min(latest.ticks,r-1),to=r};cooldowns[item]=c end
            else cooldowns[item]=nil end
            -- (the rail's running investment shows its bar, not the veil: the card stays lit)
            local veil=s:FindFirstChild("PFCooldown");if veil then veil.Visible=st=="cooling" and not (rail and o.kind=="invest") end
        end
        paintInvest()
    end
    -- the sweeps run between packets (seconds and the veil's height)
    game:GetService("RunService").RenderStepped:Connect(function()
        if not wing or next(cooldowns)==nil or not latest then return end
        local now=nowTicks()
        for item,c in cooldowns do
            local s: any=buttons[item];local veil=s and s:FindFirstChild("PFCooldown")
            if not veil then continue end
            local left=math.max(0,c.to-now)
            if left<=0 then cooldowns[item]=nil;paintSlots();continue end
            veil.Size=UDim2.fromScale(1,math.clamp(left/math.max(1,c.to-c.from),0,1))
            if not pressed[item] then s.Cost.Text=if rail then "◷ "..clock(left*STEP) else clock(left*STEP) end -- the timer sits where the price does
            local bar=rail and s:FindFirstChild("Bar")
            if bar and bar.Visible then bar.Fill.Size=UDim2.fromScale(math.clamp(1-left*STEP/Match.stock_exchange.Seconds,0,1),1) end
        end
        if investOpen then paintInvest() end
    end)
    -- v2 (PF - 3, Ashton picked A "pick amount", author-pf3-invest-card): Ready = PUT IN (−/+, 25/50/75%/Max) · YOU GET BACK ·
    -- "Invest 1.2M"; Running = INVESTED · the bar · "1.92M in 1:47" · "Locked until it pays". The pick is a share of the max
    -- allowed now (PremiumRail.investAmount); the server clamps the amount to that max (PF - 2's UsePremium amount).
    local investPick: number?=nil -- nil = Max
    local investShown: boolean?=nil -- which state's shape the card has (true = running)
    local function investShape(card: any,running: boolean)
        if investShown==running then return end;investShown=running
        local h=card:GetAttribute(if running then "PFRunH" else "PFReadyH");local hh=card:GetAttribute("PFHeadH");local w=card:GetAttribute("DW")
        if type(h)~="number" or type(hh)~="number" or type(w)~="number" then return end
        local shape=card:FindFirstChild("Shape");if shape then shape.AspectRatio=w/h end
        card.Head.Size=UDim2.fromScale(1,hh/h)
        for _,state in {card.Ready,card.Running} do state.Position=UDim2.fromScale(0,hh/h);state.Size=UDim2.fromScale(1,(h-hh)/h) end
        card.Ready.Visible=not running;card.Running.Visible=running
    end
    local function paintInvest2(o: any)
        local card=investCard
        local rect=Sprites.icons and Sprites.icons.rects.stock_exchange
        if rect then local icon=card.Head.Icon;icon.Image=Sprites.icons.image;icon.ImageRectOffset=Vector2.new(rect.x,rect.y);icon.ImageRectSize=Vector2.new(rect.w,rect.h) end
        local inv=type(o.active)=="table" and o.active or nil
        local left=if inv and type(inv.ends)=="number" then math.max(0,(inv.ends-nowTicks())*STEP) else nil
        investShape(card,inv~=nil)
        card.Head.State.Text=if left then clock(left).." LEFT" else "READY"
        card.Head.State.TextColor3=if left then Color3.fromRGB(255,211,106) else Color3.fromRGB(141,151,166)
        if inv then
            local run=card.Running
            run.Value.Text=if type(inv.stake)=="number" then short(inv.stake) else "—"
            run.Track.Fill.Size=UDim2.fromScale(math.clamp(1-(left or 0)/Match.stock_exchange.Seconds,0,1),1)
            run.Pays.Text=(if type(inv.payout)=="number" then short(inv.payout) else "—").." in "..clock(left or 0)
            return
        end
        local ready=card.Ready
        local max=if type(o.stake)=="number" then o.stake else 0
        local amount=Rail.investAmount(max,investPick)
        local back=Rail.investBack(amount,o.stake,o.payout,o.gain)
        ready.Amount.Value.Text.Text=if amount>0 then short(amount) else "—"
        ready.Back.Value.Text=if amount>0 then short(back) else "—"
        ready.Back.Gain.Text=if amount>0 then "+"..short(back-amount) else ""
        for name,share in Rail.PRESETS do
            local chip=ready.Presets:FindFirstChild(name);if not chip then continue end
            local on=math.abs((investPick or 1)-share)<1e-6
            chip.BackgroundColor3=if on then Color3.fromRGB(29,43,74) else Color3.fromRGB(21,26,36)
            local r=chip:FindFirstChild("Rim");if r then r.Color=if on then Color3.fromRGB(79,134,255) else Color3.fromRGB(43,50,64) end
            chip.Label.TextColor3=if on then Color3.new(1,1,1) else Color3.fromRGB(195,203,216)
        end
        ready.Key.Label.Text=if amount>0 then "Invest "..short(amount) else "Nothing to invest yet"
        ready.Key.Active=amount>0;ready.Key.BackgroundTransparency=if amount>0 then 0 else .55
        ready.Fine.Text=if max>0 then "Up to "..short(max).." now (30 s of your income)" else "Earn some gold first"
    end
    -- the Invest card (v6, PF - 5's take B): STAKE › BACK IN 3:00, one key; a running investment shows its clock instead
    paintInvest=function()
        if not investCard then return end
        local o=option("stock_exchange");if o and o.kind~="invest" then o=nil end
        investCard.Visible=investOpen and (gridOpen or (rail~=nil and rail.Visible)) and o~=nil
        if not investCard.Visible or not o then return end
        if investCard:FindFirstChild("Ready") then paintInvest2(o);return end -- v2
        local rect=Sprites.icons and Sprites.icons.rects.stock_exchange
        if rect then investCard.Icon.Image=Sprites.icons.image;investCard.Icon.ImageRectOffset=Vector2.new(rect.x,rect.y);investCard.Icon.ImageRectSize=Vector2.new(rect.w,rect.h) end
        local inv=type(o.active)=="table" and o.active or nil
        local stake=if inv then inv.stake else o.stake
        local back=if inv then inv.payout else o.payout
        local left=if inv and type(inv.ends)=="number" then math.max(0,(inv.ends-nowTicks())*STEP) else nil
        investCard.Stake.Text=if type(stake)=="number" then short(stake) else "—"
        investCard.Back.Text=if type(back)=="number" then short(back) else "—"
        investCard.BackLabel.Text=if left then "BACK IN "..clock(left) else "BACK IN 3:00"
        investCard.State.Text=if left then clock(left).." LEFT" else "READY"
        investCard.State.TextColor3=if left then Color3.fromRGB(255,211,106) else Color3.fromRGB(150,158,172)
        local key=investCard.Key
        key.Label.Text=if left then "Investing…" elseif type(stake)=="number" then "Invest "..short(stake) else "Invest"
        key.Active=left==nil;key.AutoButtonColor=left==nil
        key.BackgroundTransparency=if left then .55 else 0
    end
    if investCard and investCard:FindFirstChild("Ready") then -- v2: the picker's keys, and Invest with the picked amount
        local ready=investCard.Ready
        ready.Amount.Minus.Activated:Connect(function() investPick=Rail.stepPick(investPick,-1);paintInvest() end)
        ready.Amount.Plus.Activated:Connect(function() investPick=Rail.stepPick(investPick,1);paintInvest() end)
        for name,share in Rail.PRESETS do
            local chip=ready.Presets:FindFirstChild(name)
            if chip then chip.Activated:Connect(function() investPick=if share>=1 then nil else share;paintInvest() end) end
        end
        ready.Key.Activated:Connect(function()
            local o=option("stock_exchange");if not o or o.kind~="invest" or not latest or type(o.active)=="table" then return end
            local amount=Rail.investAmount(o.stake,investPick);if amount<=0 then return end
            remotes.Command:FireServer({kind="UsePremium",unitType="stock_exchange",matchId=latest.matchId,amount=amount})
            investPick=nil;paintInvest() -- the card stays open: it turns into the Running card when the server's packet lands
        end)
    elseif investCard then
        investCard.Key.Activated:Connect(function()
            local o=option("stock_exchange");if not o or o.kind~="invest" or not latest or type(o.active)=="table" then return end
            remotes.Command:FireServer({kind="UsePremium",unitType="stock_exchange",matchId=latest.matchId})
            investOpen=false;paintInvest()
        end)
    end
    -- Train: one tap, no aim (PF - 4's 4b); Invest: opens the card above the slots
    act=function(item: string)
        local o=option(item);if not o or not latest then return end
        if o.kind=="invest" then investOpen=not investOpen;paintInvest();return end
        local st=stateOf(o);if st~="ready" then return end
        remotes.Command:FireServer({kind="UsePremium",unitType=item,matchId=latest.matchId})
        -- the press beat: the troops gained (the HUD's tenth), then the server's readyTick starts the cooldown
        local gain=type(o.troops)=="number" and "+"..short(math.floor(o.troops/10)) or "Train"
        pressed[item]={untilAt=os.clock()+.9,text=gain};paintSlots()
        task.delay(.95,function() if paintSlots then paintSlots() end end)
    end
    -- the hover / long-press card's content (City.premiumTip: the dock's own BlueprintTooltip)
    City.premiumHooks.tip=function(item: string): any?
        local o=option(item)
        if not o then -- the rail's locked card: what it does, its Cobalt price, where to get it
            local it=Arsenal.byId[item];if not (rail and it) then return nil end
            return {title=it.name,purpose=EFFECT[item] or "",reason=nil,state="blocked",price="◆ "..Rail.short(it.cobalt or 0).." Cobalt",owned="Unlock it in the Armory"}
        end
        local icon=ICON_OF[item] or item
        local name=if o.kind=="train" then "Train" elseif o.kind=="invest" then "Invest" else ((Arsenal.byId[icon] and Arsenal.byId[icon].name) or item)
        local st,why=stateOf(o)
        -- the actions: one line that says the trade (troops are the HUD's tenth)
        if isAction(o) then
            local purpose=if o.kind=="train" then string.format("+%s troops now for %s gold",type(o.troops)=="number" and short(math.floor(o.troops/10)) or "?",type(o.cost)=="number" and short(o.cost) or "?")
                else string.format("Stake %s, %s back in 3:00. A raider takes the stake.",type(o.stake)=="number" and short(o.stake) or "?",type(o.payout)=="number" and short(o.payout) or "?")
            return {title=(Arsenal.byId[icon] and Arsenal.byId[icon].name or name).." · "..name,purpose=purpose,reason=why,state=if st=="cooling" then "blocked" else st,
                price=if o.kind=="train" and type(o.cost)=="number" then short(o.cost).." gold" elseif o.kind=="invest" and type(o.stake)=="number" then short(o.stake).." gold" else "",
                owned=if o.kind=="train" then "45 s between presses" else "One investment at a time"}
        end
        local costs=Match[icon] and Match[icon].Costs or {}
        local ownedText
        if o.kind=="build" then
            local n=owned(item);local nxt=costs[n+2]
            ownedText=string.format("%d / %d built",n,#costs)..(if nxt then " · next "..short(nxt) else "")
        else
            local i=o.cost and table.find(costs,o.cost);local nxt=if i then (costs[i+1] or costs[#costs]) else nil
            ownedText=(if nxt then "Next "..short(nxt) else "Launch")..(if item=="airdrop" then " · 60 s cooldown" else "")
        end
        return {title=name,purpose=EFFECT[item] or "",reason=why,state=if st=="cooling" then "blocked" else st,
            price=if o.cost then short(o.cost).." gold" else "All built",owned=ownedText}
    end
    -- arming a slot shares the dock's placement: the Placement panel words it; Cancel / Esc / a blueprint end it (premiumHooks)
    local function word(item: string): (string,string)
        local option=nil;for _,o in (latest and latest.options) or {} do if o.item==item then option=o;break end end
        local name=(Arsenal.byId[item] and Arsenal.byId[item].name) or item
        local touch=UserInputService.TouchEnabled and not UserInputService.MouseEnabled
       local title=string.upper(name)..(if option and option.cost then " · "..short(option.cost).." gold" else "")
        if placeReason then return title,placeReason end
        if optionKind[item]=="launch" then return title,if touch then "Tap a target to launch" else "Click a target · Right-click cancel" end
        return title,if touch then "Tap your land to place" else "Click your land · Right-click cancel"
    end
    local armedAt=0 -- the arming click's own release must never place (live: it launched a Blitz at the tile under the dock)
    -- touch + a launch item: the panel is the base nukes' aim bar (name, cost, a chip, Launch)
    local function aimInfo(item: string): any?
        if not touch() or optionKind[item]~="launch" then return nil end
        local option=nil;for _,o in (latest and latest.options) or {} do if o.item==item then option=o;break end end
        local icon=item
        local rect=Sprites.icons and Sprites.icons.rects[icon]
        local radius=BLAST[item]
        local state=if not pinned then "tap" elseif radius and NukeSelfHit.covers(matchState,pinned,radius) then "self" else "ready"
        return {item=item,name=(Arsenal.byId[icon] and Arsenal.byId[icon].name) or item,cost=if option and option.cost then short(option.cost) else "",
            image=Sprites.icons and Sprites.icons.image,rect=rect,state=state,ready=pinned~=nil}
    end
    local function reword()
        if not placing then return end
        local title,line=word(placing);City.premiumPlacement(title,line,aimInfo(placing))
    end
    onReason=reword
    arm=function(item: string)
        armedAt=os.clock();pinned=nil;placeReason=nil
        if gridOpen then setGrid(false) end
        if placing==item then placing=nil;City.premiumPlacement(nil) else
            placing=item;reword()
            if okBuildAnim and buttons[item] then (BuildAnim :: any).press(buttons[item],true) end -- PF - 4: the card squashes
        end
        draw()
    end
    City.premiumHooks.cancel=function() if placing then placing=nil;pinned=nil;City.premiumPlacement(nil);draw() end end
    local function fire(tile: number)
        local kind=optionKind[placing :: string]
        if kind=="launch" then remotes.Command:FireServer({kind="LaunchPremium",unitType=placing,targetId=tile,matchId=latest.matchId})
        else remotes.Command:FireServer({kind="BuildPremium",unitType=placing,targetId=tile,matchId=latest.matchId}) end
        -- PF - 4: the card's gold confirm (the light runs round it, a shine crosses it) and its cost floats up
        local card=placing and buttons[placing :: string]
        if okBuildAnim and card then
            local cost=nil;for _,o in latest.options or {} do if o.item==placing and type(o.cost)=="number" and o.cost>0 then cost=short(o.cost) end end
            (BuildAnim :: any).confirm(card,true,cost)
        end
        holdCatcher=os.clock()+.2;placing=nil;pinned=nil;City.premiumPlacement(nil);draw()
        task.delay(.25,draw)
    end
    -- the aim bar's Launch (touch): fire the pin
    City.premiumHooks.launch=function() if placing and pinned and latest then fire(pinned) end end
    -- placement on the click's END (the map decides on InputEnded too; the catcher is still up then)
    UserInputService.InputEnded:Connect(function(input: InputObject)
        if not placing or not latest or not catcher.Visible then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local position=Vector2.new(input.Position.X,input.Position.Y)
        local size,origin=world.AbsoluteSize,world.AbsolutePosition
        if size.X<=0 or size.Y<=0 then return end
        local x=math.floor((position.X-origin.X)/size.X*latest.width)
        local y=math.floor((position.Y-origin.Y)/size.Y*latest.height)
        if x<0 or y<0 or x>=latest.width or y>=latest.height then return end
        -- a click on the bar itself is a button press, not a map tile
        local barPos,barSize=bar.AbsolutePosition,bar.AbsoluteSize
        if not wing and position.X>=barPos.X and position.X<=barPos.X+barSize.X and position.Y>=barPos.Y and position.Y<=barPos.Y+barSize.Y then return end
        -- with the wing: only a click that reaches the catcher places (a HUD key or an opaque HUD panel above it keeps it)
        if wing then
            local reached=false
            if os.clock()-armedAt<.15 then return end
            for _,object in playerGui:GetGuiObjectsAtPosition(position.X,position.Y) do
                if object==catcher then reached=true;break end
                if object:IsA("GuiButton") or (controls and object:IsDescendantOf(controls)) then return end
                if object:IsDescendantOf(gui) and object.BackgroundTransparency<1 and object~=gameUI and object~=gameUI.Parent then return end
            end
            if not reached then return end
        end
        local tile=y*latest.width+x+1
        -- touch + a launch item: the tap only pins (Launch fires it)
        if wing and aimInfo(placing) then pinned=tile;reword();return end
        fire(tile)
    end)
end
return M
