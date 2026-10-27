--!strict
-- PF019 Cobalt buy (PF - 3): did a Cobalt purchase really go through? Pure: no Instances, so
-- tools/run-pf019-cobalt-buy.mjs runs it under luau.exe. The key's success look must only follow
-- the server's answer, so a buy is judged from the commerce state the server drives:
--   * "pending" while the adapter has a request in flight (it saw the request go out);
--   * "success" once the request is answered and the server-confirmed profile owns the item;
--   * "fail" otherwise: answered without the item (not enough Cobalt, an error, the adapter's
--     timeout), or never sent at all.
local M={}

export type Buy={id: string, price: number?, balance: number?, seen: boolean}
export type Outcome={words: string?, spent: number?}

function M.start(id: string,price: number?,balance: number?): Buy
    return {id=id,price=price,balance=balance,seen=false}
end

-- model = the commerce state ({pending, message, profile={loaded, failed, owned, balance}}).
-- Returns nil without a buy; marks the buy as sent the first time it sees it pending.
function M.resolve(buy: Buy?,model: any): (string?,Outcome?)
    if not buy then return nil,nil end
    local state=if type(model)=="table" then model else {}
    if state.pending then buy.seen=true;return "pending",nil end
    local profile=if type(state.profile)=="table" then state.profile else {}
    local owned=type(profile.owned)=="table" and profile.owned[buy.id]==true
    if buy.seen and profile.loaded==true and profile.failed~=true and owned then
        local spent=if type(buy.balance)=="number" and type(profile.balance)=="number" then math.max(0,buy.balance-profile.balance) else buy.price
        return "success",{spent=spent}
    end
    return "fail",{words=M.failWords(state.message,profile.balance,buy.price)}
end

-- The key has room for two words: Cobalt short gets "Need Cobalt", anything else "Try again"
-- (the full reason stays on the page's status line).
function M.failWords(message: any,balance: any,price: any): string
    if type(message)=="string" and string.find(string.lower(message),"not enough",1,true) then return "Need Cobalt" end
    if type(balance)=="number" and type(price)=="number" and balance<price then return "Need Cobalt" end
    return "Try again"
end

return table.freeze(M)
