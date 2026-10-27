--!strict
-- PF-029 load stages (PF - 2; MM 2026-10-17: ~8% of tutorial runs never finish loading). Server-side timestamps (os.clock)
-- of how far each player's client got on this server, read into the tutorial report (TutorialReport `boot`):
--   join     Players.PlayerAdded (GlobalLobbyService)
--   scripts  the client's first LocalScript ran: its device report arrived (DiscordFeedService, ClientInfo)
--   ui       MatchController built its UI: the boot handshake PreferencesCommand {kind="Ready"} (DiscordFeedService)
--   (ready)  the match's first Ready after the client decoded the map: TutorialReport's own `loaded`
-- hub: what the lobby saw before the teleport (TeleportData.boot from the hub's LoadStages.hub): device, whether its
-- scripts / UI ever ran there, and how long the player had been on the hub. Diagnostics only (TeleportData is
-- client-visible); nothing gameplay reads it.
local LoadStages = {}
local records: {[number]: any} = {}
local now = os.clock
function LoadStages.setClock(clock: () -> number) now = clock end -- tests
local function clean(hub: any): any?
    if type(hub) ~= "table" then return nil end
    return {dev = if type(hub.dev) == "string" and #hub.dev <= 16 then hub.dev else nil, scripts = hub.scripts == true, ui = hub.ui == true,
        hubFor = if type(hub.hubFor) == "number" and hub.hubFor == hub.hubFor then math.clamp(math.floor(hub.hubFor * 10 + 0.5) / 10, 0, 86400) else nil}
end
-- a (new) arrival on this server; hub = TeleportData.boot when it came from our own teleport
function LoadStages.join(userId: number, hub: any?)
    records[userId] = {join = now(), hub = clean(hub)}
end
function LoadStages.stamp(userId: number, stage: string, device: string?)
    local r = records[userId]
    if not r then r = {join = now()}; records[userId] = r end
    if r[stage] == nil then r[stage] = now() end
    if device and r.device == nil then r.device = device end
end
function LoadStages.get(userId: number): any? return records[userId] end
function LoadStages.forget(userId: number) records[userId] = nil end
-- the hub's view for the teleport: {dev, scripts, ui, hubFor}
function LoadStages.hub(userId: number): any?
    local r = records[userId]
    if not r then return nil end
    return {dev = r.device, scripts = r.scripts ~= nil, ui = r.ui ~= nil, hubFor = now() - r.join}
end
return LoadStages
