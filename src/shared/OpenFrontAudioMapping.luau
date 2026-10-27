--!strict
-- Maps exact source paths to explicitly supplied Roblox IDs; it never substitutes a sound.
-- PF043 H (PF - 3): PixelFront's own sounds (Shared.SoundList, ids in Shared.SoundIds) come first. A name is a SoundList
-- key ("u_click") or an old OpenFront cue ("click"), which resolves to the key that fills it. Until that key's file is
-- uploaded, an old original id (OpenFrontAudioIds) still plays for its cue; with neither the sound is silent.
local Catalog=require(script.Parent.OpenFrontAudioCatalog)
local Defaults=require(script.Parent.OpenFrontAudioIds)
local Sounds=require(script.Parent.SoundList)
local SoundIds=require(script.Parent.SoundIds)
local Mapping={}
local records={}
for _,record in Catalog.records do records[record.name]=record end
function Mapping.normalize(value: any): string?
    if type(value)~="string" then return nil end
    local id=string.match(value,"^rbxassetid://([1-9]%d*)$") or string.match(value,"^([1-9]%d*)$")
    return if id then "rbxassetid://"..id else nil
end
-- PF045 v3: a size variant ("g_send_2") of a row with sizes: (its row's key, its size)
function Mapping.variant(name: string): (string?,number?)
    local base,n=string.match(name,"^(.-)_(%d)$")
    local row=base and Sounds.rows[base]
    if row and row.sizes and tonumber(n) and tonumber(n)>=2 and tonumber(n)<=row.sizes then return base,tonumber(n) end
    return nil,nil
end
function Mapping.resolve(name: string,ids: {[string]: string}?): (string?,string)
    local base=Mapping.variant(name)
    if base then -- its own file when imported, else the base sound
        local own=Mapping.normalize((ids or SoundIds :: any)[name])
        if own then return own,"ready" end
        return Mapping.resolve(base,ids)
    end
    local key=Sounds.keyFor(name)
    if key then
        local id=Mapping.normalize((ids or SoundIds :: any)[key])
        if id then return id,"ready" end
        local old=records[name]
        if old and old.sourceAvailable then
            local legacy=Mapping.normalize((ids or Defaults)[old.url])
            if legacy then return legacy,"ready" end
        end
        return nil,"missing-sound-id"
    end
    local record=records[name]
    if not record then return nil,"unknown-cue" end
    if not record.sourceAvailable then return nil,"missing-original" end
    local id=Mapping.normalize((ids or Defaults)[record.url])
    return id,if id then "ready" else "missing-sound-id"
end
-- The playing rules for a name: {name, key, channel, loop, pri, gain, cd, max, once, per, duck} (nil when unknown)
local cache: {[string]: any}={}
function Mapping.record(name: string): any
    local hit=cache[name];if hit then return hit end
    local base=Mapping.variant(name)
    if base then -- a size variant: its row's rules (the same cooldown slot), its own file
        hit=table.clone(Mapping.record(base));hit.name=name;hit.url=name
        cache[name]=hit;return hit
    end
    local key=Sounds.keyFor(name)
    if key then
        local row=Sounds.rows[key]
        hit={name=name,key=key,channel=row.ch,loop=row.loop,pri=row.pri,gain=Sounds.gain(row.db),cd=row.cd,max=row.max or 3,
            once=row.once==true,per=row.per==true,duck=row.duck,url=key,tier=row.tier,share=row.share,esc=row.esc,cut=row.cut==true,sizes=row.sizes,pan=row.pan==true,nobusy=row.nobusy==true,jdb=row.jdb}
        cache[name]=hit;return hit
    end
    return records[name]
end
function Mapping.preview(category: string,ids: {[string]: string}?): (string?,string)
    local cue=({effects="build-city",alerts="nuke-warning",interface="click",music="menu-theme",ambience="a_wind"})[category]
    if not cue then return nil,"no-preview" end
    return Mapping.resolve(cue,ids)
end
-- How many sounds can play: PixelFront's list (one per key) plus the old cues no row fills
function Mapping.status(ids: {[string]: string}?): any
    local result={available=0,mapped=0,missingOriginal={},missingIds={}}
    for key in Sounds.rows do
        result.available+=1
        if Mapping.normalize((ids or SoundIds :: any)[key]) then result.mapped+=1 else table.insert(result.missingIds,key) end
    end
    local seen={}
    for _,record in Catalog.records do
        if seen[record.url] or Sounds.keyFor(record.name) then continue end;seen[record.url]=true
        local _,status=Mapping.resolve(record.name,ids)
        if status=="missing-original" then table.insert(result.missingOriginal,record.url)
        else result.available+=1;if status=="ready" then result.mapped+=1 else table.insert(result.missingIds,record.url) end end
    end
    table.sort(result.missingIds)
    return result
end
return Mapping
