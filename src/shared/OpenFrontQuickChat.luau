--!strict
--!native
-- PlayerImpl/QuickChatExecution at OpenFrontIO 93a136a1 (AGPL-3.0).
-- Dense recipient records preserve source Map insertion order across remotes.
local Config = require(script.Parent.Config)
local Catalog = require(script.Parent.QuickChatCatalog)
local QuickChat = {}

local function entry(state: any, sender: number, recipient: number): any?
    for _, record in (state.quickChat and state.quickChat[sender]) or {} do
        if record.recipient == recipient then return record end
    end
    return nil
end

function QuickChat.install(state: any)
    state.quickChat = state.quickChat or {}
    for _, owner in state.playerOrder do state.quickChat[owner] = state.quickChat[owner] or {} end
end

function QuickChat.validKey(key: any): boolean
    return type(key) == "string" and Catalog.ByKey[key] ~= nil
end

function QuickChat.canSend(state: any, sender: number, recipient: number): boolean
    if sender == recipient then return false end
    local previous = entry(state, sender, recipient)
    return previous == nil or state.ticks - previous.tick >= (Config.QuickChatCooldown or 30)
end

function QuickChat.record(state: any, sender: number, recipient: number)
    local previous = entry(state, sender, recipient)
    if previous then previous.tick = state.ticks
    else table.insert(state.quickChat[sender], {recipient = recipient, tick = state.ticks}) end
end

function QuickChat.initExecution(state: any, execution: any)
    execution.active = state.players[execution.targetOwner] ~= nil
end

function QuickChat.tickExecution(state: any, execution: any, emit: (any) -> ())
    if not QuickChat.canSend(state, execution.owner, execution.targetOwner) then
        execution.active = false
        return
    end
    -- QuickChatKeySchema verifies this key before construction. Target selection
    -- is a UI requirement; the source execution always forwards an optional ID.
    local phrase = Catalog.ByKey[execution.quickChatKey]
    assert(phrase, "Quick Chat execution requires a source catalog key")
    QuickChat.record(state, execution.owner, execution.targetOwner)
    emit({type = "DisplayChatEvent", key = phrase.phraseKey, category = phrase.category,
        target = execution.targetPlayer, playerID = execution.targetOwner,
        isFrom = true, recipient = execution.owner, tick = state.ticks})
    emit({type = "DisplayChatEvent", key = phrase.phraseKey, category = phrase.category,
        target = execution.targetPlayer, playerID = execution.owner,
        isFrom = false, recipient = execution.targetOwner, tick = state.ticks})
    execution.active = false
end

function QuickChat.snapshot(state: any): any
    local result = {}
    for _, owner in state.playerOrder do
        local records = {}
        for _, record in state.quickChat[owner] do
            table.insert(records, {recipient = record.recipient, tick = record.tick})
        end
        result[owner] = records
    end
    return result
end

return table.freeze(QuickChat)
