--!strict
-- PF-043 #8 v2 (PF - 1; Ashton on work/pf043/boards/PF043-D8b-leave.png: "I LOVE this absolutely, but this should only be for public
-- matches"; "never add friction to leaving"). The Leave confirm becomes a requeue moment on a PUBLIC match only: the authored
-- VariantExitConfirm.PFRequeue (tools/atlas/author-pf043-requeue-leave.luau) shows instead of today's Body, with the big "Find a new
-- match" key (MatchController ui.findNewMatch: the server seats you in the next public match and you go straight there), "Back to
-- lobby" (today's Leave) and "Stay". Solo, custom rooms, the tutorial, spectating and the "Match stopped" fault keep today's plain
-- Body, untouched. The busy key reads ui.requeueState() only (the queue backend may change). Content + visibility only.
local M={}
-- which body a shown confirm uses: "requeue" on a public match (not a fault prompt), else "plain"
function M.mode(canRequeue: boolean, fault: boolean, authored: boolean): string
    return if canRequeue and not fault and authored then "requeue" else "plain"
end
-- the busy key's two lines from a requeue state ({phase, seconds?, map?, players?, capacity?}) or nil (not seated yet)
function M.busyText(state: any): (string, string)
    if type(state)~="table" then return "Finding a match…","" end
    local secs=tonumber(state.seconds)
    local title=if secs and secs>=0 then string.format("Next match · %d:%02d",math.floor(secs)//60,math.floor(secs)%60)
        elseif state.phase=="Joining" or state.phase=="Starting" then "Joining…" else "Finding a match…"
    local parts={}
    if type(state.map)=="string" and state.map~="" then table.insert(parts,state.map) end
    if tonumber(state.players) and tonumber(state.capacity) then table.insert(parts,string.format("%d/%d",state.players,state.capacity)) end
    return title,table.concat(parts," · ")
end

-- confirm = Background.Game.VariantExitConfirm; hooks: {canRequeue=()->boolean, findNewMatch=()->boolean, requeueState=()->any?,
-- stay=()->(), leave=()->()}. Returns {destroy=()->()}.
function M.bind(confirm: any, hooks: any): any
    local handle: any={connections={}}
    local rq=confirm and confirm:FindFirstChild("PFRequeue")
    local body=confirm and confirm:FindFirstChild("Body")
    if not rq or not body then function handle.destroy() end;return handle end
    local GuiService=game:GetService("GuiService")
    local UIS=game:GetService("UserInputService")
    local find,lobby,stay=rq:FindFirstChild("Find"),rq:FindFirstChild("Lobby"),rq:FindFirstChild("Stay")
    local busy=false;local t0=0
    local function part(node: any,name: string): any return node and node:FindFirstChild(name,true) end
    local function setBusy(on: boolean)
        busy=on;t0=os.clock()
        local label,title,sub=part(find,"Label"),part(find,"BusyTitle"),part(find,"Sub")
        if label then label.Visible=not on end
        if title then title.Visible=on;if on then title.Text="Finding a match…" end end
        if sub then sub.Visible=on;sub.Text="" end
        local icon,spin=part(find,"Icon"),part(find,"Spinner")
        if icon then icon.Visible=not on end;if spin then spin.Visible=on end
        for _,k in {lobby,stay} do if k then k.Active=not on;k.AutoButtonColor=false;k.BackgroundTransparency=if on then .5 else 0 end end
    end
    local function shown()
        local fault=(body:FindFirstChild("Cancel") and not body.Cancel.Visible) or false -- VariantHud's "Match stopped" hides Stay
        local mode=M.mode(hooks.canRequeue and hooks.canRequeue() or false,fault,find~=nil)
        rq.Visible=mode=="requeue";body.Visible=mode~="requeue"
        setBusy(false)
        if mode=="requeue" and string.sub(UIS:GetLastInputType().Name,1,7)=="Gamepad" then GuiService.SelectedObject=find end
    end
    local function hidden()
        rq.Visible=false;body.Visible=true;setBusy(false)
        if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(rq) then GuiService.SelectedObject=nil end
    end
    table.insert(handle.connections,confirm:GetPropertyChangedSignal("Visible"):Connect(function() if confirm.Visible then shown() else hidden() end end))
    if find then table.insert(handle.connections,find.Activated:Connect(function()
        if busy then return end
        if hooks.findNewMatch and hooks.findNewMatch() then setBusy(true)
        elseif hooks.leave then hooks.leave() end -- the server couldn't requeue: a plain leave, never a dead key
    end)) end
    if lobby then table.insert(handle.connections,lobby.Activated:Connect(function() if not busy and hooks.leave then hooks.leave() end end)) end
    if stay then table.insert(handle.connections,stay.Activated:Connect(function() if not busy and hooks.stay then hooks.stay() end end)) end
    table.insert(handle.connections,game:GetService("RunService").RenderStepped:Connect(function()
        if not busy or not rq.Visible then return end
        local title,sub=M.busyText(hooks.requeueState and hooks.requeueState() or nil)
        local tl,sl=part(find,"BusyTitle"),part(find,"Sub")
        if tl and tl.Text~=title then tl.Text=title end
        if sl and sl.Text~=sub then sl.Text=sub end
        local spin=part(find,"Spinner");if spin then spin.Rotation=(os.clock()-t0)*360 end
    end))
    if confirm.Visible then shown() else hidden() end
    function handle.destroy() for _,c in handle.connections do c:Disconnect() end;table.clear(handle.connections) end
    return handle
end
return M
