--!strict
-- PF021 B (PF - 3): MatchController's decoded match packets for presentation-only listeners (the
-- tutorial tracker). Snapshots after the first are deltas, so a listener can't read the raw State
-- remote; MatchController publishes each packet right after it decodes it, and shares its audio and
-- preferences once. Listeners must not mutate the packet.
local Feed={}
local listeners: {(any)->()}={}
Feed.context={} :: any -- {audio, preferences} from MatchController
function Feed.subscribe(listener: (any)->()): ()->()
    table.insert(listeners,listener)
    return function() local index=table.find(listeners,listener);if index then table.remove(listeners,index) end end
end
function Feed.publish(packet: any)
    for _,listener in table.clone(listeners) do
        local ok,err=pcall(listener,packet)
        if not ok then warn("[MatchPacketFeed] "..tostring(err)) end
    end
end
function Feed.bind(context: any) Feed.context=context end
return Feed
