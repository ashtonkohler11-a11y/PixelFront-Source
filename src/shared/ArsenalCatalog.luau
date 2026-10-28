--!strict
-- PF044 Arsenal (docs/director/MONETIZATION-SETS.md: Warfare v4, Industry v4): the premium in-match items a player unlocks
-- once per account, read from Config.Arsenal. Shared by the Shop (PF - 1) and the server wallet (CosmeticProfiles, injected
-- through CosmeticService). Ownership lives in the cosmetic profile's `owned` as Catalog.ownedKey(id) ("arsenal_<id>"), so
-- the profile schema is unchanged and a Cobalt unlock is one wallet transaction.
--   items  (shelf order) {id, name, set, cobalt, robux, productId (0 = no Robux product yet), prestige}
--   packs  {id, name, set, items = {ids}, cobalt (bonus), robux, productId}; Robux only
--   retiredPacks: off sale; only forProduct still finds them, so an old receipt grants what was bought
local Config=require(script.Parent.Config)
local Catalog={}
Catalog.PREFIX="arsenal_"
local function product(v: any): number return if type(v)=="number" and v>0 and v%1==0 then v else 0 end
local items,packs,byId,byProduct={},{},{},{}
for _,raw in Config.Arsenal.Items do
    local item=table.freeze({id=raw.Id,name=raw.Name,set=raw.Set,cobalt=raw.Cobalt,robux=raw.Robux,productId=product(raw.ProductId),prestige=raw.Prestige==true,kind="item"})
    table.insert(items,item);byId[item.id]=item
    if item.productId>0 then byProduct[item.productId]=item end
end
for _,raw in Config.Arsenal.Packs do
    local pack=table.freeze({id=raw.Id,name=raw.Name,set=raw.Set,items=raw.Items,cobalt=raw.Cobalt,robux=raw.Robux,productId=product(raw.ProductId),kind="pack"})
    table.insert(packs,pack);byId[pack.id]=pack
    if pack.productId>0 then byProduct[pack.productId]=pack end
end
local retiredPacks={}
for _,raw in Config.Arsenal.RetiredPacks or {} do
    local pack=table.freeze({id=raw.Id,name=raw.Name,set=raw.Set,items=raw.Items,cobalt=raw.Cobalt,robux=raw.Robux,productId=product(raw.ProductId),kind="pack",retired=true})
    table.insert(retiredPacks,pack)
    if pack.productId>0 and not byProduct[pack.productId] then byProduct[pack.productId]=pack end
end
Catalog.retiredPacks=table.freeze(retiredPacks)
Catalog.items=table.freeze(items)
Catalog.packs=table.freeze(packs)
Catalog.byId=table.freeze(byId)
function Catalog.ownedKey(id: string): string return Catalog.PREFIX..id end
-- the item or pack a Developer Product unlocks (nil: not an Arsenal product)
function Catalog.forProduct(productId: any): any? return if type(productId)=="number" then byProduct[productId] else nil end
-- Industry v4 (2026-10-25): retired items and what an account that unlocked one owns instead. The stored `arsenal_<old>`
-- key stays (retired ownership IDs are preserved); a Royal Mint owner also gets Cobalt back (CosmeticProfiles.retireArsenal).
-- Premium reshuffle (2026-10-25): the Longshot -> Warden, the Bounty Office -> Stock Exchange, the Insurance Office ->
-- Training Camp (owners keep the value: equal or better, the Longshot's 50,000 Cobalt difference back).
Catalog.RETIRED=table.freeze({mint="bank",royal_mint="bank",longshot="warden",bounty_office="stock_exchange",insurance_office="training_camp"})
Catalog.RETIRED_REFUND=table.freeze({royal_mint=320000,longshot=50000}) -- royal_mint: 350,000 less the Bank's 30,000; longshot: 250,000 less the Warden's 200,000
-- {[itemId]=true} for every Arsenal item (not pack) in a profile's `owned`
function Catalog.owned(owned: any): {[string]: boolean}
    local result={}
    if type(owned)~="table" then return result end
    for _,item in items do if owned[Catalog.PREFIX..item.id]==true then result[item.id]=true end end
    for old,new in Catalog.RETIRED do if owned[Catalog.PREFIX..old]==true and byId[new] then result[new]=true end end
    return result
end
return table.freeze(Catalog)
