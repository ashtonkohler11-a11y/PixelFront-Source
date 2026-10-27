--!strict
-- Forward and reverse Roblox identity lookups verified on 2026-10-04.
-- Names are provenance only; authorization uses the authenticated Player.UserId.
local users = table.freeze({
    [8987067356] = "6ixkxnii",
    [3120821415] = "Uhm_Ashton",
})
local Access = {}
function Access.allowed(userId: number): boolean
    return users[userId] ~= nil
end
return table.freeze(Access)
