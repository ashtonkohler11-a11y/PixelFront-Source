--!strict
-- PF - 1 2026-10-28 (Ashton: "we have to make starter pack box like 2x cobalt ... and show it as much as possible"): the one
-- Starter Pack (ArsenalCatalog.packs[1]: Bank + Artillery) as a Jackpot box wherever tools/atlas/author-pf1-starter-jackpot put
-- one. A box is any GuiObject with the attribute PFStarterJackpot:
--   "own"   this module shows it (the state is known, the pack still gives something new, and its PFFollow sibling shows)
--   "paint" its owner shows it (the end card's Unlock face: PF026EndScreen); this module only paints and binds
-- Painted: Key.Price (R$ 39), PFJPWas (the items bought one by one, struck: R$ 128), PFJPCoin.Label (−70%). Key / its PFHit
-- prompts the pack's product. Ownership: the CosmeticsState packet's arsenal.owned (a Ready asks for it).
local Players=game:GetService("Players")
local Market=game:GetService("MarketplaceService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local M={}
local ROBUX=utf8.char(0xE002)
local NB=utf8.char(0xA0)
-- the pack's numbers from the catalog (tests pass their own). live = {[productId] = Roblox's PriceInRobux}: where Roblox has
-- answered, its price wins over the catalog's (UI audit 2026-10-28: the box read R$ 39 while Roblox charged 32 for the pack)
-- owned = {[itemId] = true}: an item you already own comes as its Cobalt price instead (CosmeticProfiles.arsenalReceipt), so the
-- box says so ("Bank + 50K Cobalt"; UI audit build-out 2026-10-28: an Artillery bought alone, or an old Day 2 reward) and
-- strikes only what's new
local function short(v: number): string
    if v>=1e6 then return (string.gsub(string.format("%.1fM",v/1e6),"%.0M","M")) end
    if v>=1e3 then return (string.gsub(string.format("%.1fK",v/1e3),"%.0K","K")) end
    return tostring(math.floor(v))
end
function M.numbers(cat: any,live: {[number]: number}?,owned: {[string]: any}?): any?
    local pack=cat and cat.packs and cat.packs[1];if not pack then return nil end
    local function robux(entry: any): number?
        local p=live and live[entry.productId];if type(p)=="number" then return p end
        return if type(entry.robux)=="number" then entry.robux else nil
    end
    local price=robux(pack) or pack.robux
    local worth,refund,missing=0,0,{}
    for _,id in pack.items or {} do
        local it=cat.byId and cat.byId[id]
        if owned and owned[id]==true then refund+=(it and tonumber(it.cobalt)) or 0
        else local r=it and robux(it);if r then worth+=r end;table.insert(missing,(it and it.name) or id) end
    end
    local off=if worth>price then math.floor((1-price/worth)*100+.5) else 0
    return {pack=pack,price=ROBUX..NB..tostring(price),was=if worth>price then "<s>"..ROBUX..NB..tostring(worth).."</s>" else "",
        coin=if off>0 then "−"..tostring(off).."%" else "BEST DEAL",off=off,
        line=if refund>0 and #missing>0 then table.concat(missing," + ").." + "..short(refund).." Cobalt" else nil}
end
-- owned = every item of the pack owned
function M.owned(pack: any,owned: {[string]: any}?): boolean
    if not owned then return false end
    for _,id in pack.items or {} do if owned[id]~=true then return false end end
    return true
end
function M.paint(host: any,n: any,known: boolean,owned: boolean)
    -- (the parts may sit in a panel inside the host: the Shop's host is its list section)
    local key=host:FindFirstChild("Key",true);local price=key and key:FindFirstChild("Price")
    if price then price.Text=n.price end
    local was=host:FindFirstChild("PFJPWas",true);if was then was.Text=n.was;was.Visible=n.was~="" end
    local coin=host:FindFirstChild("PFJPCoin",true);local cl=coin and coin:FindFirstChild("Label");if cl then cl.Text=n.coin end
    -- the line ("Bank + Artillery · yours forever"; the end card's face reuses Items): the authored words (PFLineBase) unless
    -- an item is owned already, then what the pack still gives
    local line=host:FindFirstChild("PFJPLine",true) or (if host:GetAttribute("PFStarterJackpot")=="paint" then host:FindFirstChild("Items") else nil)
    if line then
        local base=line:GetAttribute("PFLineBase");if type(base)~="string" then base=line.Text;line:SetAttribute("PFLineBase",base) end
        local t=if n.line then n.line..(if string.find(base,"yours forever",1,true) then " · yours forever" else "") else base
        if line.Text~=t then line.Text=t end
    end
    if host:GetAttribute("PFStarterJackpot")=="own" then
        local list=M.follows(host)
        local any=#list==0;for _,f in list do if f.Visible then any=true end end
        host.Visible=known and not owned and any
    end
end
-- PFFollow: the sibling(s) the box shows with, "A" or "A|B|C" (any one showing is enough). UI lock-in BUILD-OUT (PF - 4,
-- R16 "the Starter box shown widely"): the Shop's box follows Offers|Currency|PFPassesVip|Catalog, so it heads every Shop tab
function M.follows(host: any): {any}
    local follow=host:GetAttribute("PFFollow");local list={}
    if type(follow)~="string" or not host.Parent then return list end
    for name in string.gmatch(follow,"[^|]+") do
        local f=host.Parent:FindFirstChild(name)
        if f and (typeof(f)~="Instance" or f:IsA("GuiObject")) then table.insert(list,f) end
    end
    return list
end
function M.start()
    local player=Players.LocalPlayer
    local gui=player:WaitForChild("PlayerGui"):WaitForChild("OpenFront")
    local ok,cat=pcall(function() return require(Shared:WaitForChild("ArsenalCatalog")) end)
    local n=if ok then M.numbers(cat) else nil
    if not n then return end
    local remotes=require(Shared:WaitForChild("Remotes")).client()
    local hosts: {any}={}
    local known,have=false,false
    -- Roblox's prices (filled below) and what you own: the numbers follow both
    local live: {[number]: number}={}
    local ownedNow: {[string]: any}?=nil
    local function repaint() for _,h in hosts do M.paint(h,n,known,have) end end
    local function renumber() local fresh=M.numbers(cat,live,ownedNow);if fresh then n=fresh end;repaint() end
    local function adopt(host: any)
        if not host:IsA("GuiObject") or host:GetAttribute("PFStarterJackpot")==nil or table.find(hosts,host) then return end
        table.insert(hosts,host)
        local key=host:FindFirstChild("Key",true)
        local function buy()
            if have or type(n.pack.productId)~="number" or n.pack.productId<=0 then return end
            local where=host:GetAttribute("PFWhere")
            pcall(function() require(script.Parent.StatsReport).promptFor("Product",n.pack.productId,if type(where)=="string" then where else "starter") end)
            pcall(function() Market:PromptProductPurchase(player,n.pack.productId) end)
        end
        if key and key:IsA("GuiButton") then -- (the end card's key is a Frame: its row's PFKey buys)
            key.Activated:Connect(buy)
            local hit=key:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then hit.Activated:Connect(buy) end
            -- the key grows from its centre on hover (PFHover: a UIScale the installer put on it)
            local s=key:FindFirstChild("PFHover")
            if s then
                -- BUILD-OUT (PF - 4): the shared press juice: hover 1.06, press .96, a Back release (UiMotion; it reuses PFHover)
                local okM,UiMotion=pcall(function() return require(script.Parent.UiMotion) end)
                if okM and type(UiMotion)=="table" and type((UiMotion :: any).press)=="function" then (UiMotion :: any).press(key,{hover=1.06,press=.96})
                else
                    local Tween=game:GetService("TweenService")
                    key.MouseEnter:Connect(function() Tween:Create(s,TweenInfo.new(.12),{Scale=1.06}):Play() end)
                    key.MouseLeave:Connect(function() Tween:Create(s,TweenInfo.new(.12),{Scale=1}):Play() end)
                end
            end
        end
        for _,f in M.follows(host) do (f :: any):GetPropertyChangedSignal("Visible"):Connect(function() M.paint(host,n,known,have) end) end
        M.paint(host,n,known,have)
    end
    for _,d in gui:GetDescendants() do adopt(d) end
    gui.DescendantAdded:Connect(function(d) task.defer(adopt,d) end)
    remotes.CosmeticsState.OnClientEvent:Connect(function(packet: any)
        if type(packet)~="table" or packet.kind~="Cosmetics" then return end
        if type(packet.arsenal)=="table" and type(packet.arsenal.owned)=="table" then
            known=true;have=M.owned(n.pack,packet.arsenal.owned);ownedNow=packet.arsenal.owned;renumber()
        end
    end)
    -- one Ready can go unanswered (asked before the server made the profile, or dropped by its command rate limit): until a
    -- packet with arsenal.owned arrives the boxes stay hidden, so ask again every 2 s (Ashton's live test 2026-10-28: all hidden)
    task.spawn(function()
        for _=1,30 do
            if known then return end
            remotes.CosmeticsCommand:FireServer({kind="Ready"})
            task.wait(2)
        end
    end)
    -- Roblox's own prices for the pack and its items (the catalog's numbers stand in until they answer, or if they fail)
    task.spawn(function()
        local ids={n.pack.productId}
        for _,id in n.pack.items or {} do local it=cat.byId and cat.byId[id];if it then table.insert(ids,it.productId) end end
        for _,id in ids do
            if type(id)~="number" or id<=0 then continue end
            local got,info=pcall(function() return Market:GetProductInfo(id,Enum.InfoType.Product) end)
            if got and type(info)=="table" and type(info.PriceInRobux)=="number" then live[id]=info.PriceInRobux end
        end
        if next(live)~=nil then renumber() end
    end)
end
return M
