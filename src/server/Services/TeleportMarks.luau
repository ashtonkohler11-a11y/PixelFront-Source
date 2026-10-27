--!strict
-- PF034 Discord feed: our own teleports mark the player first, so PlayerRemoving can tell a server hop (lobby -> match ->
-- lobby) from quitting the game. GlobalLobbyService marks every player it hands to TeleportAsync and clears the mark
-- when that teleport fails. A mark older than WINDOW seconds no longer counts. Server-only and never replicated.
local Marks = {}
Marks.WINDOW = 120
local marks: {[any]: number} = setmetatable({}, {__mode = "k"}) :: any
function Marks.mark(player: any) marks[player] = os.clock() end
function Marks.clear(player: any) marks[player] = nil end
function Marks.hopping(player: any): boolean
    local at = marks[player]
    return at ~= nil and os.clock() - at <= Marks.WINDOW
end
return Marks
