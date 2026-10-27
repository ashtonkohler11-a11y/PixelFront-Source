--!strict
-- PF019 (PF - 3, MM 2026-10-06): reversible commerce switches.
-- passesVisible: gamepasses are deferred to their own pass. Until then the Shop's Passes tab and
-- Discover's Passes section stay hidden, so players never see "Permanent pass - template" /
-- "Template - not available yet". Set it to true to bring both back exactly as they were.
return table.freeze({
    passesVisible=true, -- PF020 G6 (MM 2026-10-07): the four-pass Passes tab is live
})
