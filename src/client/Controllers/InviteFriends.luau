--!strict
-- PF - 5 Invite friends (Ashton approved the board 2026-10-25, work/pf5-main/boards/PF5-main-fixes-board.png: "Good, build").
-- AtlasMenu.PFInvite (tools/atlas/author-pf5-main.luau): your Roblox friends with headshots, searched, In PixelFront first,
-- then online, then offline. A friend in PixelFront gets "Invite to party" (the hub's party notice); anyone else gets
-- "Invite" = Roblox's own invite prompt for that friend. Closes on ✕, a tap outside, Escape. Content only: texts, images,
-- colours, visibility; rows are clones of the authored templates.
local Players=game:GetService("Players")
local View={};View.__index=View
local REFRESH=30 -- s: a reopen after this re-reads the friend list
local MAX_FRIENDS=200
local MAX=4
local SECTIONS={{key="pf",title="IN PIXELFRONT"},{key="on",title="ONLINE"},{key="off",title="OFFLINE"}}
local C={pf=Color3.fromHex("#3678ff"),on=Color3.fromHex("#3fcf6a"),off=Color3.fromHex("#5a5d66"),
    pfText=Color3.fromHex("#7ea4ff"),onText=Color3.fromHex("#5fd884"),offText=Color3.fromHex("#7d808a"),
    ink=Color3.fromHex("#f2f2f2"),soft=Color3.fromHex("#e6e6e6"),muted=Color3.fromHex("#8d93a3"),sent=Color3.fromHex("#6fe08a"),
    cobaltRim=Color3.fromHex("#a0beff"),white=Color3.new(1,1,1)}
local STATUS={pf="In PixelFront",on="Online",off="Offline"}
local SEAT_FILLS={Color3.fromHex("#3678ff"),Color3.fromHex("#e07a3a"),Color3.fromHex("#2e9e4f"),Color3.fromHex("#b07ad9")}

local function headshot(id: number): string return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",id) end

-- context: {invite=function(userId,inGame)->{ok,message}, partyOpen=function(), notify=function(text)?}
function View.new(root: Frame,context: any): any
    -- PF - 3 Invite v2 (2026-10-26; tools/atlas/author-pf3-invite-v2.luau): the refurbished modal takes over while it is authored
    if root:FindFirstChild("PFInviteV2") then return require(script.Parent.AtlasInviteV2).new(root,context) end
    local self: any=setmetatable({root=root,context=context,connections={},friends={},loadedAt=-math.huge,loading=false,
        sent={},rows={},sections={},model={},open=false,destroyed=false},View)
    local panel=root:WaitForChild("Panel") :: any
    self.panel=panel;self.list=panel.List;self.query=panel.Search.Query;self.templates=root:WaitForChild("Templates")
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    -- the click that opened it must not also close it (its release can land on the new scrim)
    local function shut() if os.clock()-(self.openedAt or 0)>.35 then self:setOpen(false) end end
    listen(root.Scrim.Activated,shut)
    listen(panel.CloseHit.Activated,shut)
    listen(panel.Close.Activated,shut)
    listen(self.query:GetPropertyChangedSignal("Text"),function() self:paintList() end)
    root.Visible=false
    return self
end

function View:isOpen(): boolean return self.open end
function View:setOpen(open: boolean)
    if self.destroyed then return end
    if open and not self.open then self.openedAt=os.clock() end
    self.open=open;self.root.Visible=open
    if not open then self.query:ReleaseFocus();return end
    if type(self.model.party)~="table" and self.context.partyOpen then self.context.partyOpen() end -- the code rides on every invite
    self:paintSeats();self:paintList()
    if os.clock()-self.loadedAt>REFRESH then self:load() end
end
function View:handleEscape(): boolean
    if self.open then self:setOpen(false);return true end
    return false
end
function View:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    if self.open then self:paintSeats();self:paintList() end
end

-- every friend (GetFriendsAsync pages) + where the online ones are (GetFriendsOnline: PlaceId = ours -> in PixelFront)
function View:load()
    if self.loading then return end
    self.loading=true
    if #self.friends==0 then self:paintList() end -- "Loading friends…"
    task.spawn(function()
        local me=Players.LocalPlayer
        local all,online={},{}
        local ok=pcall(function()
            local pages=Players:GetFriendsAsync(me.UserId)
            while true do
                for _,f in pages:GetCurrentPage() do
                    if #all<MAX_FRIENDS then table.insert(all,{id=f.Id,user=f.Username,name=f.DisplayName,online=f.IsOnline==true}) end
                end
                if pages.IsFinished or #all>=MAX_FRIENDS then break end
                pages:AdvanceToNextPageAsync()
            end
        end)
        pcall(function()
            for _,f in me:GetFriendsOnline(MAX_FRIENDS) do online[f.VisitorId]=f end
        end)
        if self.destroyed then return end
        for _,f in all do
            local o=online[f.id]
            f.kind=if o and o.PlaceId==game.PlaceId then "pf" elseif o or f.online then "on" else "off"
        end
        self.loading=false
        if ok then self.friends=all;self.loadedAt=os.clock() end
        self.failed=not ok
        if self.open then self:paintList() end
    end)
end

function View:members(): {any}
    local party=self.model.party
    return if type(party)=="table" and type(party.members)=="table" then party.members else {}
end
function View:paintSeats()
    local seats=self.panel:FindFirstChild("Seats");if not seats then return end
    local members=self:members()
    local me=Players.LocalPlayer
    if #members==0 and me then members={{userId=me.UserId}} end
    for i=1,MAX do
        local seat=seats:FindFirstChild("Seat"..i);if not seat then continue end
        local m=members[i];local id=m and tonumber(m.userId)
        local avatar,plus=seat:FindFirstChild("Avatar"),seat:FindFirstChild("Plus")
        if avatar then avatar.Visible=id~=nil and id>0;avatar.Image=if id and id>0 then headshot(id) else "" end
        if plus then plus.Visible=m==nil end
        seat.BackgroundColor3=if m then SEAT_FILLS[i] else Color3.fromHex("#292929")
        local rim=seat:FindFirstChild("Rim");if rim then rim.Color=if i==1 and m then C.pf else Color3.fromHex("#535353") end
    end
    local count=seats:FindFirstChild("Count");if count then count.Text=#members.."/"..MAX end
end

local function matches(f: any,q: string): boolean
    if q=="" then return true end
    return string.find(string.lower(f.name),q,1,true)~=nil or string.find(string.lower(f.user),q,1,true)~=nil
end
function View:section(index: number): any
    local s=self.sections[index]
    if not s then s=self.templates.Section:Clone();s.Parent=self.list;self.sections[index]=s end
    return s
end
function View:row(index: number): any
    local r=self.rows[index]
    if r then return r end
    r=self.templates.Row:Clone();r.Name="Row"..index;r.Parent=self.list
    table.insert(self.connections,r.Activated:Connect(function() local id=r:GetAttribute("PFFriend");if id then self:invite(id) end end))
    table.insert(self.connections,r.MouseEnter:Connect(function() r.BackgroundTransparency=.96 end))
    table.insert(self.connections,r.MouseLeave:Connect(function() r.BackgroundTransparency=1 end))
    self.rows[index]=r
    return r
end
-- one key look per state: party (cobalt), invite (outline), sent (green), and muted (in your party / party full)
function View:paintKey(r: any,state: string)
    local key=r.Key;local label=key.Label;local tone=key:FindFirstChild("Tone");local rim=key:FindFirstChild("PFStroke")
    local party=state=="party"
    if tone then tone.Enabled=party end
    key.BackgroundTransparency=if party then 0 elseif state=="sent" then .92 else .95
    key.BackgroundColor3=if state=="sent" then C.on else C.white
    if rim then
        rim.Color=if party then C.cobaltRim elseif state=="sent" then C.on else C.white
        rim.Transparency=if party then .45 elseif state=="sent" then .6 else .78
    end
    label.Text=({party="Invite to party",invite="Invite",sent="Sent",inParty="In party",full="Party full"})[state] or ""
    label.TextColor3=if party then C.white elseif state=="sent" then C.sent elseif state=="invite" then C.soft else C.muted
end
function View:paintList()
    if self.destroyed or not self.open then return end
    local q=string.lower(string.gsub(self.query.Text,"^%s*(.-)%s*$","%1"))
    local inParty={}
    for _,m in self:members() do if tonumber(m.userId) then inParty[tonumber(m.userId)]=true end end
    local full=#self:members()>=MAX
    local groups={pf={},on={},off={}}
    for _,f in self.friends do if matches(f,q) then table.insert(groups[f.kind],f) end end
    local order,rowN=0,0
    for i,sec in SECTIONS do
        local list=groups[sec.key]
        table.sort(list,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
        local head=self:section(i)
        head.Visible=#list>0
        order+=1;head.LayoutOrder=order
        head.Text=string.format('%s  <font color="#5d6270">%d</font>',sec.title,#list)
        for _,f in list do
            rowN+=1;order+=1
            local r=self:row(rowN)
            r.Visible=true;r.LayoutOrder=order;r:SetAttribute("PFFriend",f.id);r:SetAttribute("PFKind",f.kind)
            r.Avatar.Image=headshot(f.id);r.Avatar.Dot.BackgroundColor3=C[f.kind]
            -- the @handle only when it differs, and only while it fits at the floor
            local handle=if string.lower(f.user)~=string.lower(f.name) then string.format('  <font color="#7d808a">@%s</font>',f.user) else ""
            r.Display.Text=f.name..handle
            if handle~="" and not r.Display.TextFits then r.Display.Text=f.name end
            r.Status.Text=STATUS[f.kind];r.Status.TextColor3=C[f.kind.."Text"]
            local state=if inParty[f.id] then "inParty" elseif self.sent[f.id] then "sent" elseif f.kind=="pf" then (if full then "full" else "party") else "invite"
            self:paintKey(r,state)
        end
    end
    for i=rowN+1,#self.rows do self.rows[i].Visible=false;self.rows[i]:SetAttribute("PFFriend",nil) end
    local total=self.panel.Search:FindFirstChild("Total")
    if total then total.Text=if #self.friends>0 then string.format("%d friends",#self.friends) else "" end
    local empty=self.panel:FindFirstChild("Empty")
    if empty then
        empty.Visible=rowN==0
        empty.Text=if self.loading and #self.friends==0 then "Loading friends…" elseif self.failed and #self.friends==0 then "Your friends couldn't load. Try again soon."
            elseif #self.friends==0 then "No friends yet." else "No friends match that."
    end
end
function View:invite(id: number)
    local f;for _,x in self.friends do if x.id==id then f=x end end
    if not f or self.sent[id] then return end
    for _,m in self:members() do if tonumber(m.userId)==id then return end end
    local inGame=f.kind=="pf"
    if inGame and #self:members()>=MAX then return end
    -- "Sent" once it is: at once for a party notice, on the prompt's close (with this friend picked) for a Roblox invite
    local result=self.context.invite and self.context.invite(id,inGame,function(ids: {number})
        if self.destroyed then return end
        for _,x in ids do self.sent[x]=true end
        self:paintList()
    end)
    if type(result)=="table" and result.ok==false and self.context.notify and type(result.message)=="string" and result.message~="" then
        self.context.notify(result.message)
    end
end
function View:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
end
return View
