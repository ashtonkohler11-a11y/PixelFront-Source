--!strict
-- PF029 tutorial-only maps. HAND-AUTHORED, not generated. OpenFrontMapCatalog is generated from the pinned Maps.gen.ts
-- (tools/generate-map-catalog.cjs) and is never hand-edited, so a map that exists only for a tutorial would be listed here
-- instead, in the same entry shape. The readers that resolve a map type fall back to this list (MapData.generate,
-- OpenFrontRoster's tribe-name themes, MatchMetadataTransport's map-type check), and it is the tutorial-map gate's list
-- (OpenFrontMatchAvailability.TutorialMaps: the mainland spawn rule). Compact only: data in ServerStorage.OpenFrontMaps.
-- EMPTY since 2026-10-27 (Ashton: "Delete the Honshu map"): the first match plays on the normal Compact United States
-- (MatchService.tutorialConfig), so no tutorial-only map exists; the hooks stay for any future one.
return table.freeze({maps=table.freeze({})})
