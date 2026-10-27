--!strict
-- PF029 tutorial-only maps (Ashton 2026-10-11: Honshu replaces Italia as the tutorial map). HAND-AUTHORED, not generated.
-- OpenFrontMapCatalog is generated from the pinned Maps.gen.ts (tools/generate-map-catalog.cjs) and is never hand-edited,
-- so a map that exists only for the tutorial is listed here instead, in the same entry shape. The readers that resolve a
-- map type fall back to this list (MapData.generate, OpenFrontRoster's tribe-name themes, MatchMetadataTransport's
-- map-type check), and it is the tutorial gate's list (OpenFrontMatchAvailability.TutorialMaps). The pickers never offer
-- these maps. Compact only: the data is ServerStorage.OpenFrontMaps.<id>_Compact (Honshu: work/tutorialmap/honshu).
return table.freeze({maps=table.freeze({
    -- Japan's main island, cut from the official Japan Compact (work/tutorialmap/honshu/cut-report.json): one landmass,
    -- 628x556, 69,851 land tiles; manifest nations Tohoku, Kanto, Kansai, Chugoku. themes = the catalog's Japan entry
    -- ("asia" tribe names).
    table.freeze({id="Honshu",type="Honshu",translationKey="map.honshu",name="Honshu",categories=table.freeze({}),
        themes=table.freeze({"asia"}),defaultNationCount=4,compactWidth=628,compactHeight=556}),
})})
