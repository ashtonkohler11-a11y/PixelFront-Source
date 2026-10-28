--!strict
-- Ashton's tips rule (2026-10-27, STATS-AND-RECS "Tips rule": "do the same rule for all those triggers like the wont reappear
-- but add a new one after 5 matches all beginner tips and shit should auto turn off"). One place every beginner tip asks:
--   * a tip retires for good once the player has done its thing (M.mark(id); MatchGuide watches the match for it), or, for a
--     notice that only explains (no action to take), once it has been shown SEEN_MAX times (M.seen(id))
--   * every beginner tip switches off once the player has played 5 matches: NewPlayerGuard.eligible, the same server-written
--     OpenFrontMatches count the send guard and the new-player grace read (unknown counts as experienced, as there)
--   * the tutorial is exempt (it's explicit): allowed(id, true) is always true
-- Both lists persist in the player's saved settings (settings.pfTipsDone / settings.pfTipsSeen), not per server.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Feed=require(script.Parent.MatchPacketFeed)
local M={}
M.DONE_KEY="settings.pfTipsDone" -- "border,city,…": the tips whose thing the player has done
M.SEEN_KEY="settings.pfTipsSeen" -- "reserve:2,guard:1": shows of the explain-only notices
M.SEEN_MAX=3
M.matches=function(): any -- tests replace it
    local me=Players.LocalPlayer;return me and me:GetAttribute("OpenFrontMatches")
end
M.prefs=function(): any return Feed.context and Feed.context.preferences end -- tests replace it
local guard: any=nil
local function eligible(matches: any): boolean
    if guard==nil then
        local ok,g=pcall(function() return require(RS:WaitForChild("Shared"):WaitForChild("NewPlayerGuard")) end)
        guard=if ok then g else false
    end
    if guard then return guard.eligible(matches,false) end
    return type(matches)=="number" and matches<5
end
-- still a beginner: under 5 matches played
function M.beginner(): boolean return eligible(M.matches()) end
local function read(key: string): string
    local p=M.prefs();local v=p and p.storage and p.storage[key]
    return if type(v)=="string" then v else ""
end
local function write(key: string,value: string)
    local p=M.prefs();if p and p.setCached then p:setCached(key,value) end
end
function M.done(id: string): boolean
    return table.find(string.split(read(M.DONE_KEY),","),id)~=nil
end
-- the player did the thing: this tip never shows again
function M.mark(id: string)
    if id=="" or M.done(id) then return end
    local s=read(M.DONE_KEY);write(M.DONE_KEY,if s=="" then id else s..","..id)
end
-- may this tip show now? (the tutorial: always)
function M.allowed(id: string,tutorial: boolean?): boolean
    if tutorial==true then return true end
    return M.beginner() and not M.done(id)
end
-- an explain-only notice was shown: after SEEN_MAX shows it retires
function M.seen(id: string)
    local counts,order={},{}
    for _,part in string.split(read(M.SEEN_KEY),",") do
        local k,n=string.match(part,"^([%w_]+):(%d+)$")
        if k then counts[k]=tonumber(n) :: number;table.insert(order,k) end
    end
    if not counts[id] then table.insert(order,id) end
    counts[id]=(counts[id] or 0)+1
    local out={};for _,k in order do table.insert(out,k..":"..counts[k]) end
    write(M.SEEN_KEY,table.concat(out,","))
    if counts[id]>=M.SEEN_MAX then M.mark(id) end
end
return M
