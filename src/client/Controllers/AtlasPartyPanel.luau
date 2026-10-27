--!strict
-- PF036 Parties (PF - 3): the Party button left of the profile plate, its card (PARTY n/4, the code, four seats, Invite +
-- Leave; the leader can remove a seat), a friend's invite notice, the dock's "Party of 3" tab and the phone pill's stack.
-- Boards: docs/director/mockups/PF036/01-parties-lobby.png, 02-parties-phone-members.png. Nodes: tools/atlas/
-- author-pf036-parties.luau. Content only: texts, images, colours, visibility. The facade (PublicLobbyController) talks
-- to the server; the leader picks the match (AtlasPlayPage shows members "Leader picks").
local Players=game:GetService("Players")
local Input=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local Tween=game:GetService("TweenService")
local Panel={};Panel.__index=Panel
local MAX=4
local INVITE_SECONDS=30 -- a notice shows this long
local COMPACT=90 -- under this button width (phones, 720p) the button shows the 40 px icon (the full stack + n/4 needs 86)
-- the boards' seat colours, behind each headshot while it loads (and for Studio fakes)
local FILLS={Color3.fromHex("#3678ff"),Color3.fromHex("#e07a3a"),Color3.fromHex("#2e9e4f"),Color3.fromHex("#b07ad9")}
local C={muted=Color3.fromHex("#9a9a9a")}
local function headshot(userId: any): string
    return if type(userId)=="number" and userId>0 then "rbxthumb://type=AvatarHeadShot&id="..userId.."&w=48&h=48" else ""
end
local function paintSeat(image: any,member: any?,index: number)
    if not image then return end
    image.BackgroundColor3=FILLS[(index-1)%#FILLS+1]
    image.Image=if member then headshot(member.userId) else ""
end

function Panel.new(nodes: any,context: any): any
    local self: any=setmetatable({nodes=nodes,context=context,connections={},model={},open=false,destroyed=false,dismissedAt=nil},Panel)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local button,card=nodes.button,nodes.card
    -- PF - 5 Invite friends (AtlasMenu.PFInvite): INVITE opens it, here and on the home card
    local friendsModule=script.Parent:FindFirstChild("InviteFriends")
    if nodes.friends and friendsModule then
        local ok,view=pcall(function() return (require(friendsModule) :: any).new(nodes.friends,{partyOpen=context.facade.partyOpen,
            invite=context.facade.partyInviteFriend,notify=context.notify}) end)
        if ok then self.friends=view else warn("[Party] invite friends unavailable: "..tostring(view)) end
    end
    listen(button.Activated,function() self:toggle() end)
    for _,b in {button,card.Actions.Invite,card.Actions.Leave,nodes.notice.Join} do
        local scale=b:FindFirstChild("PFPress")
        if scale then
            listen(b.MouseButton1Down,function() scale.Scale=.97 end)
            listen(b.MouseButton1Up,function() Tween:Create(scale,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end)
        end
    end
    listen(card.Actions.Invite.Activated,function() self:invite() end)
    listen(card.Actions.Leave.Activated,function() self.context.facade.partyLeave();self:setOpen(false) end)
    for i=1,MAX do
        local row=card.Rows["Seat"..i]
        listen(row.Activated,function() if row.Empty.Visible then self:invite() end end)
        listen(row.Kick.Activated,function()
            local member=self.members and self.members[i]
            if member and not member.you then self.context.facade.partyKick(member.userId) end
        end)
    end
    listen(nodes.notice.Join.Activated,function()
        local invite=self.model.partyInvite
        if type(invite)=="table" then self.context.facade.partyJoin(invite.code) end
    end)
    listen(nodes.notice.Close.Activated,function() self.context.facade.dismissPartyInvite() end)
    -- a tap or click outside the card closes it
    listen(Input.InputBegan,function(input)
        if not self.open then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local p=Vector2.new(input.Position.X,input.Position.Y) -- PF044: InputObject.Position is already GUI space (no inset)
        local function inside(g: GuiObject): boolean
            local a,s=g.AbsolutePosition,g.AbsoluteSize
            return p.X>=a.X and p.Y>=a.Y and p.X<=a.X+s.X and p.Y<=a.Y+s.Y
        end
        if not inside(card) and not inside(button) then self:setOpen(false);self.outsideAt=os.clock() end
    end)
    listen(button:GetPropertyChangedSignal("AbsoluteSize"),function() self:paintButton() end)
    local dock=nodes.tab and nodes.tab.Parent and nodes.tab.Parent:FindFirstChild("Card")
    if dock then listen(dock:GetPropertyChangedSignal("Visible"),function() self:paintQueue() end) end
    self:paint()
    return self
end

function Panel:toggle()
    self:setOpen(not self.open)
end
function Panel:setOpen(open: boolean)
    if self.destroyed then return end
    -- PF - 5 (Ashton: "it just goes away then when I lift mouse click it turns on again"): a press outside the card closes it on
    -- InputBegan; the same click's release (an opener's Activated) must not open it again
    if open and not self.open and self.outsideAt and os.clock()-self.outsideAt<.5 then self.outsideAt=nil;return end
    self.open=open
    -- the first open makes your party (just you, leading) so the code is ready to share
    if open and type(self.model.party)~="table" then self.context.facade.partyOpen() end
    if open then self.context.facade.dismissPartyInvite() end
    self:paint()
end
-- PF - 5: the friends screen; a second INVITE while it shows closes it
function Panel:openFriends()
    if not self.friends then self:invite();return end
    local show=not self.friends:isOpen()
    if show then self:setOpen(false);if type(self.model.party)~="table" then self.context.facade.partyOpen() end end
    self.friends:setOpen(show)
end
function Panel:invite()
    if self.friends then self:openFriends();return end
    local result=self.context.facade.partyInvite()
    if type(result)=="table" and result.ok==false and self.context.notify then self.context.notify(tostring(result.message)) end
end
function Panel:handleEscape(): boolean
    if self.friends and self.friends:handleEscape() then return true end
    if self.open then self:setOpen(false);return true end
    return false
end

function Panel:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    -- PF045 v2: a new invite for you; a friend joins your party (never on the first fill)
    local was=self.model
    local function size(m: any): number local p=m and m.party;return if type(p)=="table" and type(p.members)=="table" then #p.members else 0 end
    local function inviteAt(m: any): any local i=m and m.partyInvite;return if type(i)=="table" then i.at else nil end
    self.model=model
    if self.friends then self.friends:update(model) end
    if self.painted then
        local sfx=require(script.Parent.Sfx)
        if inviteAt(model)~=nil and inviteAt(model)~=inviteAt(was) and self:inviteShown() then sfx.play("u_invite")
        elseif size(model)>size(was) and size(was)>0 then sfx.play("u_join") end
    end
    self.painted=true
    self:paint()
end

-- The button: Full (desktop) or Compact (phones); solo = you + "+", a party = the stack and n/4; Dot = an invite waiting.
function Panel:paintButton()
    local party=self.model.party
    local members=if type(party)=="table" and type(party.members)=="table" then party.members else {}
    local size=#members
    local compact=self.nodes.button.AbsoluteSize.X<COMPACT
    local full,small=self.nodes.button.Full,self.nodes.button.Compact
    full.Visible=not compact;small.Visible=compact
    local solo=size<=1
    local me=Players.LocalPlayer
    local you={userId=if me then me.UserId else 0}
    -- Full
    full.Stack.Visible=not solo;full.Count.Visible=not solo;full.Me.Visible=solo;full.Plus.Visible=solo
    for i=1,3 do local seat=full.Stack["Seat"..i];seat.Visible=members[i]~=nil;paintSeat(seat,members[i],i) end
    full.Count.Text=size.."/"..MAX
    paintSeat(full.Me,you,1)
    -- Compact
    small.Seat1.Visible=not solo;small.Seat2.Visible=not solo and size>=2;small.Badge.Visible=not solo
    small.Me.Visible=solo;small.Plus.Visible=solo
    for i=1,2 do paintSeat(small["Seat"..i],members[i],i) end
    small.Badge.Count.Text=tostring(size)
    paintSeat(small.Me,you,1)
    self.nodes.button.Dot.Visible=self:inviteShown()~=nil and not self.open
end
function Panel:inviteShown(): any?
    local invite=self.model.partyInvite
    if type(invite)~="table" or type(invite.at)~="number" or os.clock()-invite.at>INVITE_SECONDS then return nil end
    local party=self.model.party
    if type(party)=="table" and party.code==invite.code then return nil end
    return invite
end

function Panel:paintCard()
    local card=self.nodes.card
    local party=self.model.party
    local members=if type(party)=="table" and type(party.members)=="table" then party.members else {}
    self.members=members
    local isLeader=type(party)=="table" and party.isLeader==true
    card.Head.Count.Text=#members.." / "..MAX
    card.Head.Code.Value.Text=if type(party)=="table" and type(party.code)=="string" then party.code else "·····"
    for i=1,MAX do
        local row=card.Rows["Seat"..i]
        local member=members[i]
        row.Avatar.Visible=member~=nil;row.Line.Visible=member~=nil;row.Empty.Visible=member==nil
        row.Selectable=member==nil;row.Active=member==nil
        if member then
            paintSeat(row.Avatar,member,i)
            row.Line.PlayerName.Text=tostring(member.name or "")
            row.Line.Crown.Visible=member.leader==true
            row.You.Visible=member.you==true
            row.Kick.Visible=isLeader and not member.you
        else row.You.Visible=false;row.Kick.Visible=false end
    end
    card.Actions.Invite.Visible=#members<MAX
end

function Panel:paintNotice()
    local notice=self.nodes.notice
    local invite=self:inviteShown()
    notice.Visible=invite~=nil and not self.open
    if not invite then return end
    local from=invite.from or {}
    notice.Title.Text=tostring(from.name or "A friend").." invited you"
    notice.Sub.Text="Party · "..tostring(invite.size or 1).." / "..MAX
    paintSeat(notice.Avatar,from,2)
end

-- The queue: "Party of n" on the dock (desktop), the stack in the pill (phones). Only while you queue with the party.
function Panel:paintQueue()
    local party=self.model.party;local room=self.model.room
    local members=if type(party)=="table" and type(party.members)=="table" then party.members else {}
    local together=#members>1 and type(room)=="table" and room.kind=="public"
    local tab,stack=self.nodes.tab,self.nodes.pillStack
    if tab then
        local dock=tab.Parent and tab.Parent:FindFirstChild("Card")
        tab.Visible=together and (dock==nil or (dock :: any).Visible) -- on the dock's edge, so only while the card (not the pill) shows
        tab.Label.Text="Party of "..#members
        for i=1,3 do local seat=tab.Stack["Seat"..i];seat.Visible=members[i]~=nil;paintSeat(seat,members[i],i) end
    end
    if stack then
        stack.Visible=together
        for i=1,3 do local seat=stack["Seat"..i];seat.Visible=members[i]~=nil;paintSeat(seat,members[i],i) end
        local chip=stack.Parent and stack.Parent:FindFirstChild("Map")
        if chip and chip:IsA("GuiObject") then chip.Visible=not together end
    end
end

function Panel:paint()
    if self.destroyed then return end
    self.nodes.card.Visible=self.open;self.nodes.pointer.Visible=self.open
    self:paintButton();self:paintCard();self:paintNotice();self:paintQueue()
end
-- The notice times out on its own (AtlasMenuController's clock).
function Panel:updateTime()
    if self.destroyed then return end
    local shown=self:inviteShown()~=nil
    if self.nodes.notice.Visible~=(shown and not self.open) then self:paint() end
end
function Panel:isOpen(): boolean return self.open end
function Panel:destroy()
    if self.destroyed then return end;self.destroyed=true
    if self.friends then self.friends:destroy() end
    for _,c in self.connections do c:Disconnect() end
end
return Panel
