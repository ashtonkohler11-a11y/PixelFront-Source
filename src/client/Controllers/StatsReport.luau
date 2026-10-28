--!strict
-- STATS v3 §v2.2 (PF - 1, 2026-10-27; Ashton "Build it"): the client's StatsReport batcher. UI opens, products seen and
-- Robux prompts are client facts: they go to PF - 2's PlayerProfileService on OpenFrontRemotes.StatsReport (created there;
-- clamped, analytics only, never rewards). Names agreed with PF - 2:
--   {v=1, o={[surface]=n}, s={["key@placement"]=n}}  deltas since the last report: at match end (the end packet's
--       xpResult), just before a teleport (Return, Play again, a queue, a party) and every 60 s while something is counted;
--       never two inside the server's 5 s (it refuses a flood)
--   {v=1, p="key@placement"}  the moment a Robux purchase prompt opens (the server ties the purchase-finished signal to it
--       for the funnel's "bought" step); at most one per 2 s
-- key: the catalog id, "double2x" (the 2x Cobalt pass) or "revive". A game closed outright loses at most the last 60 s.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local M={}
local GAP=5 -- the server: one report per 5 s
local PROMPT_GAP=2 -- the server: one prompt per 2 s
local TICK=60
local CAP=1000 -- the server clamps a count to 1,000 a report; never send more
M.SURFACES=table.freeze({Shop=true,Armory=true,Inventory=true,Stats=true,Settings=true,HowToPlay=true,Party=true,Leaderboard=true,Daily=true,Build=true})
M.PLACEMENTS=table.freeze({home=true,armory=true,shop=true,["end"]=true,match=true,revive=true})
local opens: {[string]: number}={}
local seen: {[string]: number}={}
local dirty=false
local lastSent=-math.huge
local lastPrompt=-math.huge
local waiting=false
local started=false
local remote: RemoteEvent?=nil
M.clock=os.clock -- tests
M.remote=function(): RemoteEvent? -- tests replace it
    if remote and remote.Parent then return remote end
    local folder=RS:FindFirstChild("OpenFrontRemotes");local r=folder and folder:FindFirstChild("StatsReport")
    remote=if r and r:IsA("RemoteEvent") then r else nil
    return remote
end
local function fire(payload: any): boolean
    local r=M.remote();if not r then return false end
    return (pcall(function() (r :: RemoteEvent):FireServer(payload) end))
end

-- a surface opened (the Shop page, the Armory, How to play, the build radial, ...)
function M.open(surface: string)
    if not M.SURFACES[surface] then return end
    opens[surface]=math.min((opens[surface] or 0)+1,CAP);dirty=true
end
-- a product card or button shown to the player at a placement
function M.seen(key: string,placement: string)
    if type(key)~="string" or key=="" or not M.PLACEMENTS[placement] then return end
    local k=key.."@"..placement
    seen[k]=math.min((seen[k] or 0)+1,CAP);dirty=true
end
-- a Robux purchase prompt opening (sent at once, not batched)
function M.prompt(key: string,placement: string): boolean
    if type(key)~="string" or key=="" or not M.PLACEMENTS[placement] then return false end
    if M.clock()-lastPrompt<PROMPT_GAP then return false end -- the server would refuse it
    if not fire({v=1,p=key.."@"..placement}) then return false end
    lastPrompt=M.clock()
    return true
end

-- a prompt by its Roblox id (kind "Pass": a Game Pass id, else a Developer Product id) -> its catalog key
local function catalog(name: string): any
    local ok,c=pcall(function() return require(RS:WaitForChild("Shared",5):WaitForChild(name,5)) end)
    return if ok and type(c)=="table" then c else nil
end
function M.keyFor(kind: string,id: any): string?
    if type(id)~="number" or id<=0 then return nil end
    local A,C=catalog("ArsenalCatalog"),catalog("CosmeticCatalog")
    local found: any=nil
    if kind=="Pass" then
        found=C and ((C.passForGamePass and C.passForGamePass(id)) or (C.packForPass and C.packForPass(id))) or nil
    else
        found=(A and A.forProduct and A.forProduct(id)) or (C and C.packForProduct and C.packForProduct(id)) or nil
    end
    local key=if type(found)=="table" and type(found.id)=="string" then found.id else nil
    return if key=="pass_2x_cobalt" then "double2x" else key
end
function M.promptFor(kind: string,id: any,placement: string): boolean
    local key=M.keyFor(kind,id);return if key then M.prompt(key,placement) else false
end

local function send(): boolean
    if not fire({v=1,o=opens,s=seen}) then return false end -- kept for the next try
    opens,seen,dirty={},{},false;lastSent=M.clock()
    return true
end
-- what's counted, as soon as the server will take it (inside its 5 s: once it will)
function M.flush(): boolean
    if not dirty then return false end
    local wait=GAP-(M.clock()-lastSent)
    if wait>0 then
        if not waiting then waiting=true;task.delay(wait,function() waiting=false;M.flush() end) end
        return false
    end
    return send()
end
M._peek=function() return {o=opens,s=seen,dirty=dirty} end -- tests
M._reset=function() opens,seen,dirty,lastSent,lastPrompt,waiting={},{},false,-math.huge,-math.huge,false end -- tests

function M.start()
    if started then return end
    started=true
    -- match end: the end packet's xpResult, once a match
    local ended: any=nil
    local okF,Feed=pcall(require,script.Parent.MatchPacketFeed)
    if okF then (Feed :: any).subscribe(function(packet: any)
        if type(packet)=="table" and type(packet.xpResult)=="table" and packet.matchId~=ended then ended=packet.matchId;M.flush() end
    end) end
    -- just before a teleport this client starts or is sent on
    Players.LocalPlayer.OnTeleport:Connect(function(state: Enum.TeleportState)
        if state==Enum.TeleportState.Started or state==Enum.TeleportState.InProgress then M.flush() end
    end)
    task.spawn(function() while true do task.wait(TICK);M.flush() end end)
end
return M
