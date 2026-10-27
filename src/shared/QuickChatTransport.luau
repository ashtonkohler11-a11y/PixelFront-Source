--!strict
--!native
-- Numeric Roblox IDs adapt the source recipient Map without sparse-key coercion.
local Wire = {}
local MAX = 9007199254740991
local function integer(value: any, minimum: number, maximum: number): boolean
    return type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum
end
local function keys(value: any, allowed: any): boolean
    if type(value) ~= "table" then return false end
    for key in value do if allowed[key] ~= true then return false end end
    return true
end
local function array(value: any): boolean
    if type(value) ~= "table" then return false end
    for key in value do if not integer(key, 1, #value) then return false end end
    return true
end
local function copy(records: any): any
    local result = {}
    for _, record in records do table.insert(result, {recipient = record.recipient, tick = record.tick}) end
    return result
end
local function same(a: any, b: any): boolean
    if #a ~= #b then return false end
    for index, record in a do
        if record.recipient ~= b[index].recipient or record.tick ~= b[index].tick then return false end
    end
    return true
end
local function valid(records: any, owner: number, count: number, tick: number): boolean
    if not array(records) then return false end
    local seen = {}
    for _, record in records do
        if not keys(record, {recipient = true, tick = true}) or not integer(record.recipient, 1, count)
            or record.recipient == owner or seen[record.recipient] or not integer(record.tick, 0, tick) then return false end
        seen[record.recipient] = true
    end
    return true
end

function Wire.encode(snapshot: any, previous: any?, full: boolean, count: number): any
    local saved = {quickChat = {}}
    local changes = {}
    for owner = 1, count do
        local records = (snapshot.quickChat and snapshot.quickChat[owner]) or {}
        saved.quickChat[owner] = copy(records)
        if not full and not same(records, previous.quickChat[owner]) then
            table.insert(changes, {owner = owner, records = copy(records)})
        end
    end
    if full then
        snapshot.quickChat = {}
        for owner = 1, count do snapshot.quickChat[owner] = copy(saved.quickChat[owner]) end
        snapshot.quickChatChanges = nil
    else snapshot.quickChat, snapshot.quickChatChanges = nil, changes end
    return saved
end

-- Return a detached candidate before any other transport collection mutates.
function Wire.decode(packet: any, previous: any?, full: boolean, count: number): (any?, string?)
    if not integer(packet.ticks, 0, MAX) then return nil, "quickChat.ticks" end
    local records = {}
    if full then
        if not array(packet.quickChat) or #packet.quickChat ~= count then return nil, "quickChat.ownerArray" end
        if packet.quickChatChanges ~= nil then return nil, "quickChat.fullChanges" end
        for owner = 1, count do
            if not valid(packet.quickChat[owner], owner, count, packet.ticks) then return nil, "quickChat[" .. owner .. "].records" end
            records[owner] = copy(packet.quickChat[owner])
        end
    else
        if not previous or not previous.quickChat then return nil, "quickChat.previous" end
        if packet.quickChat ~= nil or not array(packet.quickChatChanges) then return nil, "quickChat.changes" end
        local last = 0
        -- Validate the complete incoming graph before copying trusted collections.
        for index, change in packet.quickChatChanges do
            if not keys(change, {owner = true, records = true}) or not integer(change.owner, last + 1, count)
                or not valid(change.records, change.owner, count, packet.ticks) then return nil, "quickChatChanges[" .. index .. "]" end
            last = change.owner
        end
        if #packet.quickChatChanges == 0 then records = previous.quickChat
        else
            records = table.clone(previous.quickChat)
            for _, change in packet.quickChatChanges do records[change.owner] = copy(change.records) end
        end
    end
    return {quickChat = records}, nil
end

function Wire.apply(state: any, decoded: any)
    state.quickChat = decoded.quickChat
    state.quickChatChanges = nil
end

return table.freeze(Wire)
