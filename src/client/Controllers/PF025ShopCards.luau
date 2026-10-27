--!strict
-- PF025 (PF - 1; Ashton: "Good, build all"): the Shop's pack + bundle cards, content and motion only (the layout is
-- authored: tools/atlas/author-pf025-shop-cards.luau).
--   * the scenes: each card's PF025Scene crossfades the 4 frames of its sheet (A shows frame i, B fades in frame i+1),
--     only while the Shop is on screen; reduced motion holds frame 1
--   * the price language: the page still writes Badge.Label ("SAVE 33%" / "OWNED") and Value ("Worth <s>1,350</s>
--     separately" / "All 4 items owned") on the bundle cards; this mirrors them into the corner sash and the struck VALUE
--     (the legacy line shows only for the other states)
--   * hover: the key's sheen sweeps, the scene brightens; the pack cards lift a little (the bundles' card kit lifts them)
--   * owned packs: every plinth ticked, the Cobalt slot hidden, "Everything in the pack is yours"
local Run=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local M={}
local scenes: {any}={}
local pageRoot: any=nil
local menuRoot: any=nil
local loop: RBXScriptConnection?=nil

local function reduced(): boolean return menuRoot~=nil and menuRoot:GetAttribute("ReducedMotion")==true end
local function onScreen(): boolean
    return pageRoot~=nil and pageRoot.Parent~=nil and pageRoot.Visible and (menuRoot==nil or menuRoot.Visible)
end
local function frameOffset(s: any,i: number): Vector2 return Vector2.new((i%2)*s.cell.X,(i//2)*s.cell.Y) end
local function step()
    if not onScreen() then return end
    local t=os.clock()
    for _,s in scenes do
        if not s.group.Parent then continue end
        local hold=reduced()
        local x=if hold then 0 else t/s.period*s.frames
        local i=math.floor(x)%s.frames;local f=if hold then 0 else x-math.floor(x)
        local ai=frameOffset(s,i);local bi=frameOffset(s,(i+1)%s.frames)
        if s.a.ImageRectOffset~=ai then s.a.ImageRectOffset=ai end
        if s.b.ImageRectOffset~=bi then s.b.ImageRectOffset=bi end
        s.b.ImageTransparency=1-f*f*(3-2*f) -- smoothstep
    end
end
local function sweep(layer: Instance?)
    local sheen=layer and layer:FindFirstChild("PF025Sheen");local band=sheen and sheen:FindFirstChild("Band")
    if not band or reduced() then return end
    band.Offset=Vector2.new(-1.2,0)
    Tween:Create(band,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Offset=Vector2.new(1.2,0)}):Play()
end
local function brighten(group: Instance?,hot: boolean)
    local sx=group and group:FindFirstChild("ShadeX") -- the left-to-right shade eases off while hot
    if sx and sx:IsA("Frame") then Tween:Create(sx,TweenInfo.new(.18),{BackgroundTransparency=if hot then .22 else 0}):Play() end
end
-- UI review 2026-10-26 (rules 2 + 4): the pack cards are centre-anchored (author-pf1-review-packs), so the lift grows the hovered
-- card from its centre; its neighbour (peers) eases down a little so the hovered one stands out. Offers' margins fit 1.02 + the rim.
local HOT,COOL=1.02,.985
local function hover(card: GuiButton,layer: Instance?,group: Instance?,lift: UIScale?,peers: {UIScale}?)
    local quick=TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    card.MouseEnter:Connect(function()
        sweep(layer);brighten(group,true)
        if not reduced() then
            if lift then Tween:Create(lift,quick,{Scale=HOT}):Play() end
            for _,p in peers or {} do Tween:Create(p,quick,{Scale=COOL}):Play() end
        end
        local rim=card:FindFirstChild("PF025Rim");if rim then Tween:Create(rim,TweenInfo.new(.16),{Transparency=0}):Play() end
    end)
    card.MouseLeave:Connect(function()
        brighten(group,false)
        if lift then Tween:Create(lift,quick,{Scale=1}):Play() end
        for _,p in peers or {} do Tween:Create(p,quick,{Scale=1}):Play() end
        local rim=card:FindFirstChild("PF025Rim");if rim then Tween:Create(rim,TweenInfo.new(.16),{Transparency=1}):Play() end
    end)
end
-- the bundle card: the page's Badge/Value text -> the sash and the struck VALUE
local function mirrorBundle(card: Instance,host: Instance)
    local badge=host:FindFirstChild("Badge");local label=badge and badge:FindFirstChild("Label")
    local value=host:FindFirstChild("Value");local sash=host:FindFirstChild("PF025Sash");local struck=host:FindFirstChild("PF025Value")
    if not (label and value and sash and struck) then return end
    local band=sash:FindFirstChild("Band")
    local function paint()
        local save=string.match(label.Text,"^SAVE%s*(%d+%%)$")
        sash.Visible=save~=nil
        if save and band then band.Label.Text="SAVE "..save
            -- a bundle copied from the template wears its own highlight on the sash
            if card:GetAttribute("PF025Tuned")~=true and badge:IsA("GuiObject") then band.Tone.Color=ColorSequence.new(badge.BackgroundColor3,badge.BackgroundColor3:Lerp(Color3.new(),.2)) end
        end
        local worth=string.match(value.Text,"<s>([%d,]+)</s>")
        struck.Visible=worth~=nil;value.Visible=worth==nil and value.Text~=""
        if worth then struck.Number.Text="<s>"..worth.."</s>" end
    end
    label:GetPropertyChangedSignal("Text"):Connect(paint);value:GetPropertyChangedSignal("Text"):Connect(paint)
    paint()
end
-- the pack card: owned (the key reads "✓ Owned") -> ticks, the Cobalt slot away, the owned line
local function mirrorPack(card: Instance,front: Instance,layer: Instance?)
    local price=layer and layer:FindFirstChild("PackPrice")
    if not price or not price:IsA("TextLabel") then return end
    local function paint()
        local own=string.find(price.Text,"Owned",1,true)~=nil
        local contents=front:FindFirstChild("Contents")
        if contents then for _,t in contents:GetChildren() do local tick=t:FindFirstChild("Plate") and t.Plate:FindFirstChild("PF025Tick");if tick then tick.Visible=own end end end
        local cobalt=front:FindFirstChild("Cobalt");if cobalt then cobalt.Visible=not own end
        local note=card:FindFirstChild("PF025Owned");if note then note.Visible=own end
    end
    price:GetPropertyChangedSignal("Text"):Connect(paint);paint()
end
local function addScene(group: Instance?)
    if not group or not group:IsA("CanvasGroup") then return end
    local cell=group:GetAttribute("PF025Cell");local a=group:FindFirstChild("A");local b=group:FindFirstChild("B")
    if typeof(cell)~="Vector2" or not a or not b then return end
    table.insert(scenes,{group=group,a=a,b=b,cell=cell,frames=group:GetAttribute("PF025Frames") or 4,period=group:GetAttribute("PF025Period") or 2})
end

-- shopPage: AtlasMenu.Pages.Shop; shop: its AtlasCommerceContent. Optional everywhere (a place without PF025: nothing).
function M.bind(shopPage: any,shop: any)
    local scroll=shop and shop:FindFirstChild("Scroll");if not scroll or scroll:GetAttribute("PF025Revision")==nil then return end
    pageRoot=shopPage;menuRoot=shopPage:FindFirstAncestor("AtlasMenu")
    local offers=scroll:FindFirstChild("Offers")
    local PACKS={Starter={front="Forge",buy="ForgeBuy"},Pro={front="Aurora",buy="AuroraBuy"}}
    for name,spec in PACKS do
        local card=offers and offers:FindFirstChild(name);if not card then continue end
        local front=card:FindFirstChild(spec.front);if front and front:FindFirstChild("Front") then front=front.Front end
        local layer=card:FindFirstChild("Purchase") and card.Purchase:FindFirstChild(spec.buy)
        addScene(card:FindFirstChild("PF025Scene"))
        local peers={}
        for other in PACKS do
            local o=other~=name and offers:FindFirstChild(other);local l=o and o:FindFirstChild("PF025Lift")
            if l and l:IsA("UIScale") then table.insert(peers,l) end
        end
        if card:IsA("GuiButton") then hover(card,layer,card:FindFirstChild("PF025Scene"),card:FindFirstChild("PF025Lift"),peers) end
        if front then mirrorPack(card,front,layer) end
    end
    local row=scroll:FindFirstChild("PFBundles");local strip=row and (row:FindFirstChild("Scroll") or row)
    local function bindBundle(card: Instance)
        if not card:IsA("GuiButton") then return end
        local host=card:FindFirstChild("PFCardBody") or card
        if not host:FindFirstChild("PF025Sash") then return end
        addScene(host:FindFirstChild("PF025Scene"))
        local layer=host:FindFirstChild("Purchase") and host.Purchase:FindFirstChild("BundleBuy")
        hover(card,layer,host:FindFirstChild("PF025Scene"),nil)
        mirrorBundle(card,host)
    end
    if strip then
        for _,card in strip:GetChildren() do bindBundle(card) end
        strip.ChildAdded:Connect(function(card) task.defer(bindBundle,card) end) -- a bundle copied from the template later
    end
    if not loop then loop=Run.RenderStepped:Connect(step) end
end
return M
