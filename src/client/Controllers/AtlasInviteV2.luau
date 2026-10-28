--!strict
-- PF - 3 Party / Invite v2 (UI review 2026-10-26; Ashton: the old modal "a bit refurbished like new one", board 08b approved).
-- Fills AtlasMenu.PFInvite.PFInviteV2 (tools/atlas/author-pf3-invite-v2.luau). InviteFriends (PF - 5) hands over while the layer
-- exists; same API (isOpen / setOpen / handleEscape / update / destroy) and the same friend loading and invite paths as PF - 5's
-- view: In PixelFront friends get the party notice, anyone else Roblox's own invite prompt.
--   Seats: you ringed blue, party members white, open seats "+"; n/4.  Tabs: Online (in PixelFront + online) | All.
--   Rows: the real headshot + a status dot, the name, "@handle · status" under it, one key: blue Invite → gold Sent ✓; In party /
--   Party full grey. Rows and section labels are placed in the list canvas's Scale (V2.layout, pure, tested).
local Players: any=nil -- set in new() (V2.entries / layout / keyState stay plain-Luau testable)
local Motion: any=nil -- PF - 4's UiMotion, set in new() (build-out motion; absent in the CLI tests)
local V2={};V2.__index=V2
local REFRESH,MAX_FRIENDS,MAX=30,200,4
V2.SECTIONS={{key="pf",title="IN PIXELFRONT"},{key="on",title="ONLINE"},{key="off",title="OFFLINE"}}
V2.LIST={w=802,h=694,section=28,row=88,gap=8,pad=60}
local STATUS={pf="In PixelFront",on="Online",off="Offline"}
local DOT={pf="#4f86ff",on="#5fd38a",off="#6f7889"}

-- The visible entries in order for a tab and query: {kind="section", key, title, n} and {kind="row", friend}. friends = {id, user,
-- name, kind}. Online = in PixelFront + online; All adds offline. Each section sorts by name and shows only when it has rows.
-- fill (the view passes true; UI audit build-out R12: "dead band under 3 online friends"): an Online tab with fewer than FILL rows
-- carries on into the offline section so the sheet never shows an empty half.
V2.FILL=6
function V2.entries(friends: {any},tab: string,query: string,fill: boolean?): {any}
    local q=string.lower((string.gsub(query,"^%s*(.-)%s*$","%1")))
    local groups={pf={},on={},off={}}
    local online=0
    for _,f in friends do
        local hit=q=="" or string.find(string.lower(f.name),q,1,true)~=nil or string.find(string.lower(f.user),q,1,true)~=nil
        if hit and f.kind~="off" then online+=1 end
        if hit then table.insert(groups[f.kind],f) end
    end
    if tab~="All" and not (fill and online<V2.FILL) then groups.off={} end
    local out={}
    for _,sec in V2.SECTIONS do
        local list=groups[sec.key]
        if #list==0 then continue end
        table.sort(list,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
        table.insert(out,{kind="section",key=sec.key,title=sec.title,n=#list})
        for _,f in list do table.insert(out,{kind="row",friend=f}) end
    end
    return out
end
-- Where each entry sits in the list canvas: returns the canvas height in view heights + {y, h} fractions of the canvas.
function V2.layout(entries: {any},spec: any): (number,{any})
    local y=0;local spots={}
    for i,e in entries do
        local h=if e.kind=="section" then spec.section else spec.row
        spots[i]={y=y,h=h}
        y+=h+spec.gap
    end
    local content=math.max(0,y-spec.gap)+spec.pad
    local canvas=math.max(spec.h,content)
    for _,s in spots do s.y/=canvas;s.h/=canvas end
    return canvas/spec.h,spots
end
-- A row's key: words and look ("invite" blue, "sent" gold, "muted" grey). sent / inParty from the view; full = 4 in the party.
function V2.keyState(f: any,sent: boolean,inParty: boolean,full: boolean): (string,string)
    if inParty then return "In party","muted" end
    if sent then return "Sent ✓","sent" end
    if f.kind=="pf" and full then return "Party full","muted" end
    return "Invite","invite"
end

local function headshot(id: number): string return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",id) end
local function find(root: Instance,path: string): any
    local node: any=root
    for part in string.gmatch(path,"[^.]+") do node=node and node:FindFirstChild(part) end
    return node
end

function V2.new(root: Frame,context: any): any
    Players=game:GetService("Players")
    local okM,M=pcall(function() return require(script.Parent.UiMotion) end);Motion=if okM and type(M)=="table" then M else nil
    local layer=root:WaitForChild("PFInviteV2")
    -- UI audit build-out (R3: on phones the sheet's top sat over Home's top-left discs): the Panel lives in PFSafe
    -- (author-pf3-build-lobby), which starts below Roblox's bar (TopbarLine.clearBelow, the sanctioned runtime position)
    local safe=layer:FindFirstChild("PFSafe")
    local panel=(if safe then safe:WaitForChild("Panel") else layer:WaitForChild("Panel")) :: any
    local self: any=setmetatable({root=root,layer=layer,panel=panel,context=context,connections={},friends={},loadedAt=-math.huge,loading=false,
        sent={},rows={},sections={},model={},open=false,destroyed=false,tab="Online",list=panel.List,query=panel.Search.Query,templates=layer.Templates},V2)
    for _,name in {"Panel","Halo"} do local n=root:FindFirstChild(name);if n and n:IsA("GuiObject") then n.Visible=false end end
    layer.Visible=true
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    if safe then local okLine,Line=pcall(function() return require(script.Parent.TopbarLine) end);if okLine and Line and Line.clearBelow then Line.clearBelow(safe,self.connections) end end
    local function shut() if os.clock()-(self.openedAt or 0)>.35 then self:setOpen(false) end end
    local scrim=root:FindFirstChild("Scrim");if scrim then listen(scrim.Activated,shut) end
    listen(panel.CloseHit.Activated,shut);listen(panel.Close.Activated,shut)
    listen(self.query:GetPropertyChangedSignal("Text"),function() self:paintList() end)
    -- UI audit R8: the tabs and each row's Invite key answer on their finger zones too (HitZone; author-pf3-hit-zones)
    local HitZone=require(script.Parent.HitZone);self.hitZone=HitZone
    for _,name in {"Online","All"} do listen(HitZone.signal(panel.Tabs[name]),function() self.tab=name;self:paintList() end) end
    root.Visible=false
    return self
end
function V2:isOpen(): boolean return self.open end
function V2:setOpen(open: boolean)
    if self.destroyed then return end
    local opening=open and not self.open
    if opening then self.openedAt=os.clock() end
    -- build-out motion: the sheet pops in (.94 -> 1, Back .2 s) over its fading scrim and closes in .1 s (UiMotion)
    local scrim=self.root:FindFirstChild("Scrim")
    if Motion and not open and self.open then
        self.open=false;self.query:ReleaseFocus()
        Motion.close(self.panel,{scrim=scrim},function() if not self.open then self.root.Visible=false end end)
        return
    end
    self.open=open;self.root.Visible=open
    if opening and Motion then Motion.open(self.panel,{scrim=scrim}) end
    if not open then self.query:ReleaseFocus();return end
    if type(self.model.party)~="table" and self.context.partyOpen then self.context.partyOpen() end
    self:paintSeats();self:paintList()
    if os.clock()-self.loadedAt>REFRESH then self:load() end
end
function V2:handleEscape(): boolean
    if self.open then self:setOpen(false);return true end
    return false
end
function V2:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    if self.open then self:paintSeats();self:paintList() end
end
function V2:load()
    if self.loading then return end
    self.loading=true
    if #self.friends==0 then self:paintList() end
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
        pcall(function() for _,f in me:GetFriendsOnline(MAX_FRIENDS) do online[f.VisitorId]=f end end)
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
function V2:members(): {any}
    local party=self.model.party
    return if type(party)=="table" and type(party.members)=="table" then party.members else {}
end
function V2:paintSeats()
    local seats=self.panel.Seats
    local members=self:members()
    local me=Players.LocalPlayer
    if #members==0 and me then members={{userId=me.UserId}} end
    for i=1,MAX do
        local seat=seats:FindFirstChild("Seat"..i);if not seat then continue end
        local m=members[i];local id=m and tonumber(m.userId)
        seat.Avatar.Visible=id~=nil and id>0;seat.Avatar.Image=if id and id>0 then headshot(id) else ""
        seat.Plus.Visible=m==nil
        local rim=seat:FindFirstChild("Rim")
        if rim then rim.Color=Color3.fromHex(if m and i==1 then "#4f86ff" elseif m then "#dfe5ee" else "#3a4252");rim.Transparency=if m then 0 else .2 end
    end
    seats.Count.Text=string.format('%d<font color="#8d97a6"> / %d</font>',#members,MAX)
end
function V2:entry(kind: string,index: number): any
    local pool=if kind=="section" then self.sections else self.rows
    local node=pool[index]
    if node then return node end
    if kind=="section" then node=self.templates.Section:Clone()
    else
        node=self.templates.Row:Clone()
        local function go() local id=node:GetAttribute("PFFriend");if id then self:invite(id) end end
        table.insert(self.connections,node.Activated:Connect(go))
        table.insert(self.connections,self.hitZone.signal(node.Key):Connect(go))
        local rim=node:FindFirstChild("Rim")
        local function hot(on: boolean) if rim then rim.Color=Color3.fromHex(if on then "#4f86ff" else "#222937");rim.Transparency=if on then .45 else 0 end end
        table.insert(self.connections,node.MouseEnter:Connect(function() hot(true) end))
        table.insert(self.connections,node.MouseLeave:Connect(function() hot(false) end))
        table.insert(self.connections,node.SelectionGained:Connect(function() hot(true) end))
        table.insert(self.connections,node.SelectionLost:Connect(function() hot(false) end))
    end
    node.Name=kind..index;node.Parent=self.list
    pool[index]=node
    return node
end
function V2:paintKey(r: any,words: string,look: string)
    local key=r.Key;local tone=key:FindFirstChild("Tone");local rim=key:FindFirstChild("PFStroke")
    if tone then tone.Enabled=look=="invite" end
    key.BackgroundColor3=Color3.fromHex(if look=="invite" then "#3b78f2" elseif look=="sent" then "#d9a12c" else "#1e242f")
    key.BackgroundTransparency=if look=="sent" then .9 else 0
    if rim then rim.Color=Color3.fromHex(if look=="sent" then "#6b5422" else "#2b3240");rim.Transparency=if look=="invite" then 1 else 0 end
    key.Label.Text=words
    key.Label.TextColor3=Color3.fromHex(if look=="invite" then "#ffffff" elseif look=="sent" then "#ffd36a" else "#7f8a9c")
end
function V2:paintList()
    if self.destroyed or not self.open then return end
    local tabs=self.panel.Tabs
    local online=0;for _,f in self.friends do if f.kind~="off" then online+=1 end end
    for name,n in {Online=online,All=#self.friends} do
        local b=tabs[name];local on=self.tab==name
        b.BackgroundColor3=Color3.fromHex(if on then "#1d2b4a" else "#0d1018");b.TextColor3=Color3.fromHex(if on then "#ffffff" else "#9aa3b2")
        local rim=b:FindFirstChild("Rim");if rim then rim.Color=Color3.fromHex(if on then "#4f86ff" else "#2b3240");rim.Thickness=if on then 2 else 1.5 end
        b.Text=(if name=="Online" then '<font color="#5fd38a">●</font> ' else "")..name..(if #self.friends>0 then " "..n else "")
    end
    local inParty={};for _,m in self:members() do if tonumber(m.userId) then inParty[tonumber(m.userId)]=true end end
    local full=#self:members()>=MAX
    local entries=V2.entries(self.friends,self.tab,self.query.Text,true)
    local scale,spots=V2.layout(entries,V2.LIST)
    -- CanvasSize's Scale reads against the ScrollingFrame's PARENT (the panel), not the list: convert, less the scrollbar
    local ls=self.list.Size
    self.list.CanvasSize=UDim2.new(ls.X.Scale,-self.list.ScrollBarThickness,ls.Y.Scale*scale,0)
    self.list.ScrollBarImageTransparency=if scale>1.001 then .15 else 1
    local nS,nR=0,0
    for i,e in entries do
        local node
        if e.kind=="section" then
            nS+=1;node=self:entry("section",nS)
            node.Text=string.format('%s  <font color="%s">%d</font>',e.title,DOT[e.key],e.n)
        else
            nR+=1;node=self:entry("row",nR)
            local f=e.friend
            node:SetAttribute("PFFriend",f.id)
            node.Avatar.Image=headshot(f.id);node.Avatar.Dot.BackgroundColor3=Color3.fromHex(DOT[f.kind])
            node.Display.Text=f.name
            local handle=if string.lower(f.user)~=string.lower(f.name) then "@"..f.user.." · " else ""
            node.Status.Text=string.format('%s<font color="%s">%s</font>',handle,DOT[f.kind],STATUS[f.kind])
            local words,look=V2.keyState(f,self.sent[f.id]==true,inParty[f.id]==true,full)
            self:paintKey(node,words,look)
            -- build-out motion: Invite -> Sent ✓ pops the key (1.08, Back) for that friend
            if Motion and look=="sent" and node:GetAttribute("PFKeyFor")==f.id and node:GetAttribute("PFKeyLook")~="sent" then Motion.pop(node.Key,1.08,.2) end
            node:SetAttribute("PFKeyFor",f.id);node:SetAttribute("PFKeyLook",look)
        end
        node.Visible=true
        node.Position=UDim2.fromScale(0,spots[i].y);node.Size=UDim2.fromScale(1,spots[i].h)
    end
    for i=nS+1,#self.sections do self.sections[i].Visible=false end
    for i=nR+1,#self.rows do self.rows[i].Visible=false;self.rows[i]:SetAttribute("PFFriend",nil) end
    self.panel.Fade.Visible=scale>1.001
    self.panel.Search.Total.Text="" -- build-out (R5): the All tab already counts them
    local empty=self.panel.Empty
    empty.Visible=nR==0
    empty.Text=if self.loading and #self.friends==0 then "Loading friends…" elseif self.failed and #self.friends==0 then "Your friends couldn't load. Try again soon."
        elseif #self.friends==0 then "No friends yet." elseif self.tab=="Online" and self.query.Text=="" then "No friends online right now." else "No friends match that."
end
function V2:invite(id: number)
    local f;for _,x in self.friends do if x.id==id then f=x end end
    if not f or self.sent[id] then return end
    for _,m in self:members() do if tonumber(m.userId)==id then return end end
    local inGame=f.kind=="pf"
    if inGame and #self:members()>=MAX then return end
    local result=self.context.invite and self.context.invite(id,inGame,function(ids: {number})
        if self.destroyed then return end
        for _,x in ids do self.sent[x]=true end
        self:paintList()
    end)
    if type(result)=="table" and result.ok==false and self.context.notify and type(result.message)=="string" and result.message~="" then
        self.context.notify(result.message)
    end
end
function V2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
end
return V2
