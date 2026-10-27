--!strict
-- PF020 VIP (V3, PF - 2): per the G5b mockup, a VIP's chat line shows a gold VIP pill before the
-- name and the name in gold. VIP comes from the server-set, replicated player attribute OpenFrontVIP
-- (a Game Pass or a profile grant), never from message text. TextChatService allows one
-- OnIncomingMessage callback; this is it.
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local Tag={}
-- Rich text: <mark> draws the pill (GOLD.hi), the label is GOLD.ink; the name is GOLD.hi.
Tag.PILL='<mark color="#ffd77a" transparency="0"><font color="#2a1d06"><b> VIP </b></font></mark> '
Tag.NAME='<font color="#ffd77a">%s</font>'
local started=false
-- Pure: the prefix for a message's sender (nil when no tag applies). The sender's own prefix
-- markup is dropped so the gold name is not overridden by an inner colour.
function Tag.prefixFor(players: any, userId: number?, prefixText: string?): string?
    if type(userId)~="number" then return nil end
    local player=players:GetPlayerByUserId(userId)
    if not player or player:GetAttribute("OpenFrontVIPBadge")~=true then return nil end -- PF025: VIP and "VIP badge" Show
    local plain=string.gsub(prefixText or "","<[^>]*>","")
    return Tag.PILL..string.format(Tag.NAME,plain)
end
function Tag.start()
    if started then return end;started=true
    if TextChatService.ChatVersion~=Enum.ChatVersion.TextChatService then return end
    TextChatService.OnIncomingMessage=function(message: TextChatMessage)
        local source=message.TextSource
        local prefix=Tag.prefixFor(Players,source and source.UserId,message.PrefixText)
        if not prefix then return nil end
        local properties=Instance.new("TextChatMessageProperties")
        properties.PrefixText=prefix
        return properties
    end
end
return Tag
