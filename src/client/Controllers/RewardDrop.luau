--!strict
-- PF-043 D1c-2 (PF - 1; Ashton: "Good, build"; board work/pf043/boards/PF043-D1c-reward.png, Rocket League's item drop): one quick drop per
-- reward over everything (Background.PFRewardDrop, tools/atlas/author-pf043-reward-drop.luau). Display only: the caller has already
-- claimed on the server and hands the granted rewards in; the keys are Rocket League's "OK / OK to all":
--   Claim (big, selected)  next reward (the last one closes)        tap anywhere on idle / Enter / gamepad A
--   Equip                  equip a cosmetic, then next (items only) gamepad Y
--   Claim all              close the rest at once (2+ left)         gamepad X
-- A tap anywhere during the ~0.6 s drop skips to idle. Colour = the reward's kind (gold: an item, ice: Cobalt); the catalog has no
-- rarity. Reduced motion: the card fades in, no pop or flash. Content only: authored geometry; code sets texts, art, colours,
-- visibility and the drop's UIScale / transparencies.
local Drop={};Drop.__index=Drop
Drop.DURATION=.6
local GEM="rbxassetid://120204330036909"
-- A reward for the drop from a granted entry: Levels ({kind="item"|"cobalt", itemId?, amount?, level?}) or Daily ({item?, cobalt?}).
function Drop.entry(g: any,label: string?): any?
    if type(g)~="table" then return nil end
    local itemId=if type(g.itemId)=="string" then g.itemId elseif type(g.item)=="string" then g.item else nil
    if itemId then return {kind="item",itemId=itemId,label=label or (if tonumber(g.level) then "LEVEL "..g.level.." REWARD" else "REWARD")} end
    local amount=tonumber(g.amount) or tonumber(g.cobalt)
    if amount and amount>0 then return {kind="cobalt",amount=amount,label=label or (if tonumber(g.level) then "LEVEL "..g.level.." REWARD" else "REWARD")} end
    return nil
end
function Drop.grouped(n: number): string
    local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse();return (out:gsub("^,",""))
end
-- The drop's look at time t (seconds since the reward started): card scale/alpha, the flash, the glow, text + keys alpha.
function Drop.frame(t: number,reduced: boolean): any
    if reduced then local a=math.clamp(t/.25,0,1);return {scale=1,card=a,flash=0,glow=.6*a,ring=0,text=a,keys=a} end
    local function seg(a: number,b: number) return math.clamp((t-a)/(b-a),0,1) end
    local pop=seg(0,.12);local settle=seg(.12,.35);local reveal=seg(.25,.45);local keys=seg(.4,.6)
    local scale=if t<.12 then .55+.57*pop else 1.12-.12*settle
    return {scale=scale,card=math.clamp(.35+.65*pop,0,1),flash=if t<.12 then .55*pop else .55*(1-seg(.12,.3)),
        glow=if t<.12 then pop else 1-.3*settle,ring=1-seg(.12,.4),text=reveal,keys=keys}
end
-- Which keys show for a reward with `left` rewards still queued after it.
function Drop.keys(item: any,left: number): any
    return {claim=true,equip=type(item)=="table" and item.kind=="item",all=left>=1}
end

-- root = Background.PFRewardDrop; ctx: {equip=(itemId)->()?, reduced=()->boolean?}
function Drop.new(root: any,ctx: any?): any
    local self: any=setmetatable({root=root,ctx=ctx or {},queue={},index=0,t0=0,idle=false,connections={},onDone=nil},Drop)
    local stage=root:FindFirstChild("Stage")
    self.stage=stage
    local function on(name: string,fn: ()->())
        local b=root:FindFirstChild(name,true);if b and b:IsA("GuiButton") then table.insert(self.connections,b.Activated:Connect(fn)) end
    end
    on("Scrim",function() self:tap() end);on("Claim",function() self:claim() end);on("Equip",function() self:equip() end);on("All",function() self:claimAll() end)
    local UIS=game:GetService("UserInputService")
    table.insert(self.connections,UIS.InputBegan:Connect(function(input: InputObject)
        if not root.Visible then return end
        local k=input.KeyCode
        if k==Enum.KeyCode.Return or k==Enum.KeyCode.KeypadEnter or k==Enum.KeyCode.ButtonA then self:tap()
        elseif k==Enum.KeyCode.ButtonY then if self.idle then self:equip() end
        elseif k==Enum.KeyCode.ButtonX then if self.idle then self:claimAll() end end
    end))
    table.insert(self.connections,game:GetService("RunService").RenderStepped:Connect(function() self:step() end))
    root.Visible=false
    return self
end
local function part(self: any,name: string): any return self.stage and self.stage:FindFirstChild(name,true) end
function Drop:reduced(): boolean return self.ctx.reduced and self.ctx.reduced() or false end
-- play a list of rewards (Drop.entry shapes); onDone after the last one closes
function Drop:play(list: {any},onDone: (()->())?)
    local q={};for _,e in list do if type(e)=="table" then table.insert(q,e) end end
    if #q==0 then if onDone then onDone() end;return end
    self.queue=q;self.index=0;self.onDone=onDone
    self.root.Visible=true
    self:show(1)
end
function Drop:show(i: number)
    self.index=i;self.t0=os.clock();self.idle=false
    local item=self.queue[i]
    local gold,ice=Color3.fromHex("#ffd77a"),Color3.fromHex("#8fb6ff")
    local color=if item.kind=="item" or item.kind=="arsenal" then gold else ice
    local name,typeText="",""
    local art=part(self,"Art")
    if item.kind=="arsenal" then -- PF - 3 2026-10-25 (daily variant B): a premium building, shown as its Armory scene's first frame
        local okC,Catalog=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.ArsenalCatalog) :: any end)
        local entry=okC and Catalog.byId and Catalog.byId[item.itemId]
        name=if entry then tostring(entry.name) else tostring(item.itemId);typeText="Premium building"
        local okS,Showcase=pcall(require,script.Parent.ArmoryShowcase)
        local scene=okS and (Showcase :: any).items[item.itemId]
        if art then art.Image=if scene then scene.sheet else "";art.ImageRectOffset=Vector2.zero;art.ImageRectSize=Vector2.new(320,134) end
    elseif item.kind=="item" then
        local shared=game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        local ok,Catalog=pcall(function() return require(shared:FindFirstChild("CosmeticCatalog") :: any) end)
        local entry=ok and type(Catalog)=="table" and Catalog.byId and Catalog.byId[item.itemId]
        name=if entry then tostring(entry.name) else tostring(item.itemId);typeText=if entry then tostring(entry.category) else ""
        local okArt,Art=pcall(require,script.Parent.CosmeticArt)
        if art then art.Image="";art.ImageRectSize=Vector2.zero;if okArt then pcall((Art :: any).bind,art,item.itemId) end end
    else
        name="+"..Drop.grouped(item.amount).." Cobalt";typeText="Cobalt"
        if art then art.Image=GEM;art.ImageRectSize=Vector2.zero;art.ImageRectOffset=Vector2.zero end
    end
    local function set(n: string,text: string?,c: Color3?) local l=part(self,n);if l then if text then l.Text=text end;if c then l.TextColor3=c end end end
    set("Kind",item.label,color);set("Name",name);set("Type",typeText)
    local count=part(self,"Count");if count then count.Visible=#self.queue>1;local l=count:FindFirstChild("Label");if l then l.Text=i.." of "..#self.queue end end
    for _,n in {"CardRim","RingStroke"} do local s=part(self,n);if s and s:IsA("UIStroke") then s.Color=color end end
    local glow=part(self,"Glow");if glow then glow.ImageColor3=color end
    local k=Drop.keys(item,#self.queue-i)
    for name2,on in {Claim=k.claim,Equip=k.equip,All=k.all} do local b=part(self,name2);if b then b.Visible=on end end
    local badge=part(self,"AllCount");if badge then badge.Text=tostring(#self.queue-i+1) end
    if game:GetService("UserInputService").GamepadEnabled then local c=part(self,"Claim");if c then game:GetService("GuiService").SelectedObject=c end end
    self:step()
end
function Drop:step()
    if not self.root.Visible or self.index==0 then return end
    local t=os.clock()-self.t0
    if not self.idle and t>=Drop.DURATION then self.idle=true end
    local f=Drop.frame(if self.idle then Drop.DURATION else t,self:reduced())
    local pop=part(self,"Pop");if pop then pop.Scale=f.scale end
    local card=part(self,"Card");if card and card:IsA("CanvasGroup") then card.GroupTransparency=1-f.card end
    local flash=part(self,"Flash");if flash then flash.BackgroundTransparency=1-f.flash end
    local glow=part(self,"Glow");if glow then glow.ImageTransparency=1-.45*f.glow end -- subtle (Ashton: "careful on the glow")
    local ring=part(self,"RingStroke");if ring then ring.Transparency=1-.8*f.ring end
    for _,n in {"Kind","Name","Type"} do local l=part(self,n);if l then l.TextTransparency=1-f.text end end
    local keys=part(self,"Keys");if keys and keys:IsA("CanvasGroup") then keys.GroupTransparency=1-f.keys end
    local hint=part(self,"Hint");if hint then hint.TextTransparency=1-.6*f.keys end
end
-- a tap anywhere: skip the drop, or (idle) Claim
function Drop:tap() if not self.root.Visible then return end;if not self.idle then self.idle=true;self:step() else self:claim() end end
function Drop:claim()
    if not self.root.Visible then return end
    if self.index<#self.queue then self:show(self.index+1) else self:close() end
end
function Drop:equip()
    local item=self.queue[self.index]
    if item and item.kind=="item" then
        if self.ctx.equip then pcall(self.ctx.equip,item.itemId)
        else pcall(function() -- the shop's own Equip command (the server pushes the new look back)
            local RS=game:GetService("ReplicatedStorage")
            local entry=(require(RS.Shared.CosmeticCatalog) :: any).byId[item.itemId]
            local remote=RS:FindFirstChild("OpenFrontRemotes") and RS.OpenFrontRemotes:FindFirstChild("CosmeticsCommand")
            if entry and remote then (remote :: any):FireServer({kind="Equip",itemId=item.itemId,slot=entry.category,
                requestId=game:GetService("HttpService"):GenerateGUID(false)}) end
        end) end
    end
    self:claim()
end
function Drop:claimAll() if self.root.Visible then self:close() end end
function Drop:close()
    self.root.Visible=false;self.index=0;self.queue={}
    local GuiService=game:GetService("GuiService")
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then GuiService.SelectedObject=nil end
    local done=self.onDone;self.onDone=nil;if done then done() end
end
function Drop:destroy() for _,c in self.connections do c:Disconnect() end;table.clear(self.connections) end

-- One shared drop per GUI (the end card, the Shop row and the daily sheet all play through it).
local shared: any=nil
function Drop.get(gui: Instance?,ctx: any?): any?
    if shared and shared.root.Parent then return shared end
    local background=gui and gui:FindFirstChild("Background")
    local root=background and background:FindFirstChild("PFRewardDrop")
    if not root then return nil end
    shared=Drop.new(root,ctx);return shared
end
return Drop
