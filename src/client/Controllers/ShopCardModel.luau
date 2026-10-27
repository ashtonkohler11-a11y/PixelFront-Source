--!strict
-- PF019 (PF - 3): what a lobby shop card SAYS (approved M2; M6 is the bar). Pure: no
-- Instances, so tools/run-pf019-shop-cards.mjs runs it under luau.exe.
--   * Overline: the category word in the set colour (SKIN / FLAG / CROWN / EFFECT / COBALT ...).
--   * Set colour: the pack's colour for pack items, else the item's own signature colour
--     (its first vivid palette entry), with a few named exceptions (M2: "orange Ember").
--   * One action, never a dead button: Cobalt price, "Need N more" (opens Cobalt), View pack,
--     Equip, or the Equipped state. Whether a price can really be bought stays with
--     AtlasCommercePage:purchaseState (truthful purchases); this only words it.
local M={}

M.OVERLINES=table.freeze({Skin="SKIN",Flag="FLAG",Crown="CROWN",VFX="EFFECT",Frame="FRAME",Banner="BANNER",
    Buildings="BUILDINGS",Missiles="MISSILE",Bundle="BUNDLE",Currency="COBALT",PremiumPack="PACK",Offer="PACK",
    Nameplate="NAMEPLATE",Title="TITLE"})
-- Pack colours (the PF017 pack links) and the named exceptions to the palette rule.
M.PACK_SETS=table.freeze({pack_aurora="#72f4ce",pack_starter="#ffae48"})
M.SET_OVERRIDES=table.freeze({vfx_ember="#fb923c"})
M.NEUTRAL="#8c8c8c"

function M.overline(category: string): string
    return M.OVERLINES[category] or string.upper(category)
end

-- "#rrggbb" -> r,g,b in [0,1]
function M.rgb(hex: string): (number,number,number)
    local h=string.gsub(hex,"#","")
    return tonumber(string.sub(h,1,2),16)/255,tonumber(string.sub(h,3,4),16)/255,tonumber(string.sub(h,5,6),16)/255
end
-- Saturation and value (HSV) of a hex colour.
function M.sv(hex: string): (number,number)
    local r,g,b=M.rgb(hex)
    local hi,lo=math.max(r,g,b),math.min(r,g,b)
    return if hi>0 then (hi-lo)/hi else 0,hi
end
-- The set colour as hex. packId: the pack an item belongs to (nil when none).
function M.setHex(item: any,packId: string?): string
    if packId and M.PACK_SETS[packId] then return M.PACK_SETS[packId] end
    if type(item)~="table" then return M.NEUTRAL end
    if M.SET_OVERRIDES[item.id] then return M.SET_OVERRIDES[item.id] end
    local colors=if type(item.colors)=="table" then item.colors else {}
    -- First vivid entry: readable on the #1f1f1f panel and clearly coloured.
    for _,hex in colors do
        local s,v=M.sv(hex)
        if s>=.35 and v>=.75 then return hex end
    end
    -- Otherwise the most colourful entry (a silver crown stays silver), else neutral.
    local best,score=M.NEUTRAL,-1
    for _,hex in colors do local s,v=M.sv(hex);if s*v>score and v>=.55 then best,score=hex,s*v end end
    return best
end

function M.number(value: any): string
    if type(value)~="number" or value~=value then return "--" end
    local result=tostring(math.floor(value))
    while true do local replacement,count=string.gsub(result,"^(%-?%d+)(%d%d%d)","%1,%2");result=replacement;if count==0 then break end end
    return result
end

export type ActionInput={owned: boolean, equipped: boolean, canEquip: boolean, ready: boolean, packOnly: boolean, passName: string?,
    price: number?, balance: number?, canBuy: boolean, state: string}
export type Action={kind: string, text: string, active: boolean, gem: boolean}
-- kinds: "buy" (raised Cobalt price + gem), "short" (dim "Need N more", opens Cobalt), "pack"
-- (View pack, pack-colour outline), "equip" (raised), "equipped" (cobalt fill, a state),
-- "owned" (a state while the profile loads), "wait" (Loading / Updating / Not available).
function M.action(input: ActionInput): Action
    if input.owned then
        if input.equipped then return {kind="equipped",text="Equipped",active=false,gem=false} end
        if input.canEquip and input.ready then return {kind="equip",text="Equip",active=true,gem=false} end
        return {kind="owned",text="Owned",active=false,gem=false}
    end
    if input.packOnly then return {kind="pack",text="View pack",active=true,gem=false} end
    -- PF020: a pass-only cosmetic is never sold on its own (e.g. "Comes with VIP").
    if input.passName then return {kind="pass",text="Comes with "..input.passName,active=false,gem=false} end
    if input.price==nil then return {kind="wait",text=if input.state=="Available" then "Not available" else input.state,active=false,gem=false} end
    if input.state=="Need Cobalt" and type(input.balance)=="number" then
        return {kind="short",text="Need "..M.number(math.max(1,input.price-input.balance)).." more",active=true,gem=true}
    end
    if input.canBuy then return {kind="buy",text=M.number(input.price),active=true,gem=true} end
    -- Loading / Updating / Unavailable: the price stays visible, dimmed, until it is real.
    return {kind="wait",text=M.number(input.price),active=false,gem=true}
end

-- Inventory cards (the same M2 card, owned items only): Equip / the Equipped state; bundles and
-- packs are collections, not slots, so they say Owned. While the profile loads: Owned.
export type InventoryInput={equippable: boolean, equipped: boolean, ready: boolean}
function M.inventoryAction(input: InventoryInput): Action
    if not input.equippable then return {kind="owned",text="Owned",active=false,gem=false} end
    if input.equipped then return {kind="equipped",text="Equipped",active=false,gem=false} end
    if input.ready then return {kind="equip",text="Equip",active=true,gem=false} end
    return {kind="owned",text="Owned",active=false,gem=false}
end

return table.freeze(M)
