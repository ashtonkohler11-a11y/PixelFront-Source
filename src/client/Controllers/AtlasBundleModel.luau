--!strict
-- PF017-B: what a Shop bundle card says, from the catalog and the player's
-- owned set. Pure (no Instances), so the card copy is testable outside Studio.
-- Prices come only from CosmeticCatalog (bundlePrice adjusts for owned members).
local Catalog=require(game.ReplicatedStorage.Shared.CosmeticCatalog)
local Model={}

-- Short member labels for the tiles: the category word, as the M2 overlines (MM: "Skin", never "Territory").
Model.kinds=table.freeze({Skin="Skin",Flag="Flag",Crown="Crown",VFX="Effect",Banner="Banner",Frame="Frame",Buildings="Buildings"})

function Model.number(value: number): string
    local result=tostring(math.floor(value))
    while true do local replacement,count=string.gsub(result,"^(%-?%d+)(%d%d%d)","%1,%2");result=replacement;if count==0 then break end end
    return result
end

export type Member={id: string,name: string,kind: string,owned: boolean}
export type Card={id: string,name: string,members: {Member},price: number,total: number,missingValue: number,
    saving: number,percent: number,ownedCount: number,complete: boolean,overline: string,badge: string,value: string}

-- A bundle's colours as hex: card accent/highlight and its buy button (PF - 2's
-- PF017-A language: tone top/middle/bottom, rim, shimmer, price shade). The two
-- launch bundles are hand-tuned; any later bundle derives its look from its catalog
-- colours, so the authoring helper and the runtime row paint it the same way.
local TUNED={
    bundle_vanguard={tone={"#d64040","#ef4444","#961c1c"},rim="#fcd34d",shine="#ffeccd",shade="#500e0e"},
    bundle_cartographer={tone={"#40a0f0","#38bdf8","#7048de"},rim="#c4b5fd",shine="#e4f6ff",shade="#16265c"},
    -- PF020 G7 (PF - 3): the storm-steel key with a cyan rim and the Tempest-cyan SAVE pill. Its
    -- accent/highlight are tuned too, so the card reads the same whatever colours the catalog carries.
    bundle_tempest={accent="#7fe8ff",highlight="#7fe8ff",tone={"#5c6c88","#465570","#2c3648"},rim="#7fe8ff",shine="#e4f7ff",shade="#0a0f17"},
}
-- The hand-tuned look of a bundle without touching the catalog (the authoring helper builds the
-- Tempest card before its catalog entry exists); nil for a bundle that derives its look.
function Model.tuned(bundleId: string): any return TUNED[bundleId] end
-- PF020 G7: the storm card's hover (board: the wash brightens and the key's bolt lights).
Model.STORM=table.freeze({washRest=.45,washHot=.2,boltRest="#8b98ae",boltHot="#e4f7ff"})
local function mix(from: string,toward: string,t: number): string
    local function rgb(hex: string): (number,number,number)
        hex=string.gsub(hex,"#","");return tonumber(string.sub(hex,1,2),16) :: number,tonumber(string.sub(hex,3,4),16) :: number,tonumber(string.sub(hex,5,6),16) :: number
    end
    local r,g,b=rgb(from);local R,G,B=rgb(toward)
    return string.format("#%02x%02x%02x",math.round(r+(R-r)*t),math.round(g+(G-g)*t),math.round(b+(B-b)*t))
end
function Model.look(bundleId: string): any
    local item=assert(Catalog.byId[bundleId],"Unknown bundle")
    local tuned=TUNED[bundleId]
    local accent=if tuned and tuned.accent then tuned.accent else item.colors[1]
    local highlight=if tuned and tuned.highlight then tuned.highlight else item.colors[2] or accent
    return {accent=accent,highlight=highlight,
        tone=if tuned then tuned.tone else {mix(accent,"#ffffff",.12),accent,mix(accent,"#000000",.38)},
        rim=if tuned then tuned.rim else highlight,shine=if tuned then tuned.shine else mix(accent,"#ffffff",.85),
        shade=if tuned then tuned.shade else mix(accent,"#000000",.7)}
end

function Model.bundles(): {any}
    local result={}
    for _,item in Catalog.items do if item.category=="Bundle" then table.insert(result,item) end end
    return result
end

function Model.describe(bundleId: string,owned: {[string]: boolean}): Card
    local item=assert(Catalog.byId[bundleId],"Unknown bundle");assert(item.category=="Bundle","Not a bundle")
    -- PF020: a member without a price yet counts as 0 and leaves the bundle unpriced ("--"), not broken.
    local function value(id: string): number local p=Catalog.byId[id].price;return if type(p)=="number" then p else 0 end
    local members: {Member}={};local total,ownedCount=0,0
    for _,id in item.items do
        local member=assert(Catalog.byId[id],"Unknown bundle member");total+=value(id)
        local mine=owned[id]==true;if mine then ownedCount+=1 end
        table.insert(members,{id=id,name=member.name,kind=Model.kinds[member.category] or member.category,owned=mine})
    end
    local price,missing=Catalog.bundlePrice(item,owned)
    local complete=#missing==0 or owned[item.id]==true
    local priced=price~=nil
    local missingValue=0;for _,id in missing do missingValue+=value(id) end
    local saving=if complete or not priced then 0 else math.max(0,missingValue-(price :: number))
    local percent=if missingValue>0 and not complete then math.floor(saving/missingValue*100+.5) else 0
    local count=#members
    return {id=item.id,name=item.name,members=members,price=if complete then 0 else price :: any,total=total,missingValue=missingValue,
        saving=saving,percent=percent,ownedCount=ownedCount,complete=complete,
        overline=string.format("BUNDLE · %d ITEMS",count),
        badge=if complete then "OWNED" elseif not priced then "" else string.format("SAVE %d%%",percent),
        -- RichText: the separate total is struck through.
        value=if complete then string.format("All %d items owned",count)
            elseif not priced then "Not available"
            elseif ownedCount>0 then string.format("%d of %d owned · price adjusted",ownedCount,count)
            else string.format("Worth <s>%s</s> separately",Model.number(total))}
end

return table.freeze(Model)
