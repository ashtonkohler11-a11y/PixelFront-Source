--!strict
-- PF034 Discord feed: the text helpers every embed shares (pure: no Roblox APIs), plus Discord's embed limits.
-- Numbers read the way the game shows them (12,500 / 1.2M), times read as clocks (m:ss) or spans (2h 05m).
local Text = {}
-- Discord's limits: title 256, description 4096, 25 fields (name 256, value 1024), footer 2048, author 256, and
-- 6000 characters across every embed of one message; at most 10 embeds per message.
Text.LIMITS = table.freeze({title = 256, description = 4096, fields = 25, name = 256, value = 1024, footer = 2048,
    author = 256, total = 6000, embeds = 10})

local function finite(value: any): number?
    return if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then value else nil
end
Text.finite = finite

-- 12500 -> "12,500"
function Text.number(value: any): string
    local n = finite(value)
    if n == nil then return "?" end
    local negative = n < 0
    local digits = tostring(math.floor(math.abs(n) + 0.5))
    local out = ""
    while #digits > 3 do out = "," .. string.sub(digits, -3) .. out; digits = string.sub(digits, 1, -4) end
    return (if negative then "-" else "") .. digits .. out
end
-- 50000 -> "50K", 1250000 -> "1.3M", 950 -> "950" (at most 6 characters for the tables)
function Text.compact(value: any): string
    local n = finite(value)
    if n == nil then return "?" end
    local a = math.abs(n)
    local sign = if n < 0 then "-" else ""
    local function tenths(unit: number): string return string.format("%.1f", math.floor(a / unit * 10 + 0.5) / 10) end -- half up
    if a >= 1e9 then return sign .. tenths(1e9) .. "B" end
    if a >= 1e7 then return sign .. string.format("%dM", math.floor(a / 1e6 + 0.5)) end
    if a >= 1e6 then return sign .. tenths(1e6) .. "M" end
    if a >= 1e4 then return sign .. string.format("%dK", math.floor(a / 1e3 + 0.5)) end
    if a >= 1e3 then return sign .. tenths(1e3) .. "K" end
    return sign .. tostring(math.floor(a + 0.5))
end
-- 75 -> "1:15", 3725 -> "1:02:05"
function Text.clock(value: any): string
    local n = finite(value)
    if n == nil or n < 0 then return "-" end
    local s = math.floor(n + 0.5)
    if s >= 3600 then return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60) end
    return string.format("%d:%02d", s // 60, s % 60)
end
-- a span: "<1m", "34m", "2h 05m", "3d 4h"
function Text.duration(value: any): string
    local n = finite(value)
    if n == nil or n < 0 then return "?" end
    local s = math.floor(n)
    if s < 60 then return "<1m" end
    if s < 3600 then return tostring(s // 60) .. "m" end
    if s < 86400 then return string.format("%dh %02dm", s // 3600, (s // 60) % 60) end
    return string.format("%dd %dh", s // 86400, (s // 3600) % 24)
end
-- seconds since: "just now", "5 minutes ago", "2 days ago"
function Text.ago(value: any): string
    local n = finite(value)
    if n == nil then return "?" end
    local s = math.max(0, math.floor(n))
    local function unit(count: number, name: string): string return tostring(count) .. " " .. name .. (if count == 1 then "" else "s") .. " ago" end
    if s < 60 then return "just now" end
    if s < 3600 then return unit(s // 60, "minute") end
    if s < 86400 then return unit(s // 3600, "hour") end
    if s < 86400 * 14 then return unit(s // 86400, "day") end
    if s < 86400 * 60 then return unit(s // (86400 * 7), "week") end
    return unit(s // (86400 * 30), "month")
end
-- 1 -> "1st", 3 -> "3rd", 11 -> "11th"
function Text.ordinal(n: number): string
    local last2, last = n % 100, n % 10
    local suffix = if last2 >= 11 and last2 <= 13 then "th" elseif last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
    return tostring(n) .. suffix
end
function Text.clip(value: any, limit: number): string
    local s = tostring(value)
    if #s <= limit then return s end
    return string.sub(s, 1, math.max(0, limit - 3)) .. "..."
end
-- Roblox names are letters, digits and (inside a word) underscores, which Discord never formats: shown as they are.
-- Anything else that could be markdown is escaped.
function Text.escape(value: any): string
    local s = tostring(value)
    if string.match(s, "^[%w_ ]*$") then return s end
    return (string.gsub(s, "([%*_~`|>\\])", "\\%1"))
end
-- {"VIP", "VIP", "Starter Pack"} -> "VIP x2, Starter Pack" (repeats stay visible)
function Text.list(names: {string}): string
    local counts, order = {}, {}
    for _, name in names do
        if counts[name] then counts[name] += 1 else counts[name] = 1; table.insert(order, name) end
    end
    local parts = {}
    for _, name in order do table.insert(parts, if counts[name] > 1 then name .. " x" .. counts[name] else name) end
    return table.concat(parts, ", ")
end
-- "Free For All" -> "FFA"
function Text.mode(mode: any): string?
    if mode == "Free For All" then return "FFA" end
    if mode == "Team" then return "Teams" end
    return if type(mode) == "string" and mode ~= "" then mode else nil
end
function Text.pad(value: any, width: number, right: boolean?): string
    local s = tostring(value)
    if #s >= width then return s end
    local fill = string.rep(" ", width - #s)
    return if right then fill .. s else s .. fill
end

-- What Discord counts toward the 6000 per message.
function Text.size(embed: any): number
    local total = 0
    local function add(value: any) if type(value) == "string" then total += #value end end
    add(embed.title); add(embed.description)
    if type(embed.footer) == "table" then add(embed.footer.text) end
    if type(embed.author) == "table" then add(embed.author.name) end
    for _, field in embed.fields or {} do add(field.name); add(field.value) end
    return total
end
-- Clip every part to Discord's limits (an over-long embed is refused whole, so it is trimmed instead).
function Text.fit(embed: any): any
    local L = Text.LIMITS
    if embed.title then embed.title = Text.clip(embed.title, L.title) end
    if embed.description then embed.description = Text.clip(embed.description, L.description) end
    if type(embed.footer) == "table" and embed.footer.text then embed.footer.text = Text.clip(embed.footer.text, L.footer) end
    local fields = {}
    for _, field in embed.fields or {} do
        if #fields >= L.fields then break end
        if type(field.value) == "string" and field.value ~= "" then
            table.insert(fields, {name = Text.clip(field.name or "-", L.name), value = Text.clip(field.value, L.value), inline = field.inline == true})
        end
    end
    embed.fields = if #fields > 0 then fields else nil
    while Text.size(embed) > L.total - 200 and embed.fields and #embed.fields > 0 do table.remove(embed.fields) end
    return embed
end
-- Add a field unless it is empty, zero or none (Ashton: "if they have 0 of stats just remove it").
function Text.field(fields: {any}, name: string, value: any, inline: boolean?)
    if value == nil or value == false or value == "" or value == 0 then return end
    table.insert(fields, {name = name, value = tostring(value), inline = inline ~= false})
end

return table.freeze(Text)
