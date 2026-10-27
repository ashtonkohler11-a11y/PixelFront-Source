--!strict
-- PIVOT D12 (PF - 1): the Shop's own top bar, AtlasMenu.PFShopTop: Back · Cosmetics / Free · the Cobalt wallet (the lobby Header
-- hides while the Shop shows). Authored by tools/atlas/author-pivot-arsenal.luau (Scale + aspect). Cosmetics = the existing
-- AtlasCommerceContent; Free = the daily streak sheet (DailyView.openStreak).
-- PIVOT Armory (Ashton 2026-10-25: "shop is where everything else lies"): the premium items moved to their own page
-- (AtlasArmoryPage, AtlasMenu.PFArmory). The bar's Arsenal tab is hidden by author-pivot-armory; the Shop always opens on
-- Cosmetics. 2026-10-26 (retired-item cleanup): the old Pages.Shop.PFArsenal page is no longer read; this module is the bar alone.
local Gui=game:GetService("GuiService")
local Page={}
Page.__index=Page
local hex=Color3.fromHex
local function comma(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (out:gsub("^,",""))
end

function Page.new(root: Instance,context: any): any
    local top=root:FindFirstChild("PFShopTop")
    assert(top,"author-pivot-arsenal not installed")
    local self=setmetatable({root=root,top=top,context=context,on=false,balance=nil,connections={},destroyed=false},Page)
    local function listen(signal: any,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    local tabs=top.Row.Tabs
    -- a key and its invisible 44 dp hit (PFHit, over the key) both fire fn
    local function bind(button: any,fn: ()->())
        listen(button.Activated,fn)
        local hit=button:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then listen(hit.Activated,fn) end
    end
    -- the bar's left edge stays right of Roblox's top-bar pill (PF - 3's TopbarLine: the one sanctioned runtime position)
    local okLine,Line=pcall(require,script.Parent:FindFirstChild("TopbarLine") :: any)
    if okLine and Line and Line.keepRight then Line.keepRight(top,self.connections) end
    bind(top.Row.Back,function() if context.back then context.back() end end)
    bind(tabs.Cosmetics,function() if context.refreshCommerce then context.refreshCommerce() end end)
    bind(tabs.Free,function() if context.openFree then context.openFree() end end)
    bind(top.Wallet.Plus,function() if context.refreshCommerce then context.refreshCommerce() end end) -- the Cobalt packs live in Cosmetics
    -- the Free tab's dot follows the lobby's Shop-tab dot (FreeRewardsRow lights it while the daily claim is ready)
    local dot=context.freeDot
    if dot then
        local function paintDot() tabs.Free.Dot.Visible=dot.Visible end
        listen(dot:GetPropertyChangedSignal("Visible"),paintDot);paintDot()
    end
    if context.remotes then
        listen(context.remotes.CosmeticsState.OnClientEvent,function(packet: any)
            if type(packet)=="table" and packet.kind=="Cosmetics" and type(packet.balance)=="number" then self.balance=packet.balance;self:paint() end
        end)
    end
    self:paint()
    return self
end

-- the menu calls this after every navigate: the bar shows on the Shop (not over a match, not while the Armory covers it)
function Page:sync(page: string,locked: boolean,armory: boolean?)
    if self.destroyed then return end
    -- PF - 1 2026-10-25 (one bar): the Shop's own Header (title + categories) sits in this bar now, so the bar shows over a match
    -- too (its Back is "back to battle" there: context.back); the old Cosmetics / Free tabs are hidden (author-pf1-shop-onebar)
    local oneBar=self.top.Row:FindFirstChild("Header")~=nil
    local on=page=="Shop" and (oneBar or not locked) and not armory
    self.on=on;self.top.Visible=on
    -- the cosmetics shop's own wallet repeats the bar's: hidden while the bar shows
    local content=self.context.content
    local header=content and (content:FindFirstChild("Header") or self.top.Row:FindFirstChild("Header"))
    local wallet=header and header:FindFirstChild("Wallet")
    if wallet then wallet.Visible=not on end
    if content then content.Visible=true end
    if on then self.context.header.Visible=false end
    local tab=self.top.Row.Tabs:FindFirstChild("Cosmetics")
    if tab then tab.Line.Visible=true;tab.BackgroundTransparency=0;tab.Label.TextColor3=Color3.new(1,1,1) end
end
function Page:paint()
    if self.destroyed then return end
    self.top.Wallet.Amount.Text=if self.balance then comma(self.balance) else "…"
end
function Page:focusActive()
    if self.on then Gui.SelectedObject=self.top.Row.Tabs.Cosmetics end
end
function Page:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
end
return Page
