--!strict
-- PF037 growth hooks: the per-player record (pure; GrowthService owns the DataStore OpenFrontGrowth_v1 "u:<userId>").
-- wins (to ask for notifications after the 1st and a favorite after the 2nd), each ask once per account, who invited this
-- player (from their first visit's join data, only if they had never played), and the friends this player was paid for.
local Growth = {}
Growth.VERSION = 1
local function int(v: any): number return if type(v) == "number" and v == v and v > 0 and v < 2 ^ 53 then math.floor(v) else 0 end
function Growth.newRecord(): any
    return {v = Growth.VERSION, wins = 0, notifyAsked = false, favoriteAsked = false, referredBy = 0, referralDone = false, invites = {}, paid = {}}
end
function Growth.validate(raw: any): any?
    if raw == nil then return Growth.newRecord() end
    if type(raw) ~= "table" or raw.v ~= Growth.VERSION then return nil end
    local r = Growth.newRecord()
    r.wins, r.notifyAsked, r.favoriteAsked = int(raw.wins), raw.notifyAsked == true, raw.favoriteAsked == true
    r.referredBy, r.referralDone = int(raw.referredBy), raw.referralDone == true
    for _, id in (if type(raw.invites) == "table" then raw.invites else {}) do if int(id) > 0 and not table.find(r.invites, int(id)) then table.insert(r.invites, int(id)) end end
    for _, id in (if type(raw.paid) == "table" then raw.paid else {}) do if int(id) > 0 and not table.find(r.paid, int(id)) then table.insert(r.paid, int(id)) end end
    return r
end
-- A win at the grant moment: returns which asks are due now ("Notify" after the 1st win, "Favorite" from the 2nd), once each.
function Growth.win(record: any): {string}
    record.wins += 1
    local asks = {}
    if record.wins >= 1 and not record.notifyAsked then record.notifyAsked = true; table.insert(asks, "Notify")
    elseif record.wins >= 2 and not record.favoriteAsked then record.favoriteAsked = true; table.insert(asks, "Favorite") end
    return asks
end
-- The first visit through an invite: remember the inviter, only for a player who has never played (and not themself).
function Growth.referred(record: any, selfId: number, inviter: number, hasPlayed: boolean): boolean
    if record.referredBy ~= 0 or record.referralDone or hasPlayed or int(inviter) == 0 or inviter == selfId then return false end
    record.referredBy = int(inviter)
    return true
end
-- This player finished their first match: the inviter to credit (once), or nil.
function Growth.firstMatch(record: any): number?
    if record.referralDone or record.referredBy == 0 then return nil end
    record.referralDone = true
    return record.referredBy
end
-- The inviter's side: credit a friend (cap), true when newly credited.
function Growth.credit(record: any, friendId: number, cap: number): boolean
    if table.find(record.invites, friendId) or #record.invites >= cap then return false end
    table.insert(record.invites, friendId)
    return true
end
-- Credited friends not paid yet.
function Growth.unpaid(record: any): {number}
    local list = {}
    for _, id in record.invites do if not table.find(record.paid, id) then table.insert(list, id) end end
    return list
end
-- Two copies (this server's and the store's): never lose a win, an ask, a credit or a payment.
function Growth.merge(a: any, b: any): any
    local out = Growth.newRecord()
    out.wins = math.max(a.wins, b.wins)
    out.notifyAsked, out.favoriteAsked = a.notifyAsked or b.notifyAsked, a.favoriteAsked or b.favoriteAsked
    out.referredBy = if a.referredBy ~= 0 then a.referredBy else b.referredBy
    out.referralDone = a.referralDone or b.referralDone
    for _, list in {a.invites, b.invites} do for _, id in list do if not table.find(out.invites, id) then table.insert(out.invites, id) end end end
    for _, list in {a.paid, b.paid} do for _, id in list do if not table.find(out.paid, id) then table.insert(out.paid, id) end end end
    return out
end
return table.freeze(Growth)
