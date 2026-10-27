--!strict
-- PF045 Oil Rigs (PF - 3, sim only, behind Config.OilRigs.Enabled): the fixed rig spots per map, from PF - 2's study
-- (work/oilrigs/spots.json, pictures work/oilrigs/<map>.png): open water 5-25 tiles off a coast, about equally far from
-- the two nearest nations, >= 110 tiles apart. Keyed by "<width>x<height>" of the Compact map. Generated: do not edit.
return table.freeze({
    ["1400x774"]=table.freeze({ -- us: unitedstates-compact
        table.freeze({x=1231,y=217,tile=305032,offshore=16}),
        table.freeze({x=1171,y=319,tile=447772,offshore=8}),
        table.freeze({x=133,y=328,tile=459334,offshore=10}),
        table.freeze({x=989,y=281,tile=394390,offshore=7}),
        table.freeze({x=1021,y=634,tile=888622,offshore=9}),
        table.freeze({x=886,y=232,tile=325687,offshore=9}),
        table.freeze({x=179,y=56,tile=78580,offshore=9}),
        table.freeze({x=900,y=618,tile=866101,offshore=9}),
    }),
    ["1124x1012"]=table.freeze({ -- qing: qingchina-compact
        table.freeze({x=863,y=884,tile=994480,offshore=12}),
        table.freeze({x=979,y=778,tile=875452,offshore=18}),
        table.freeze({x=915,y=537,tile=604504,offshore=9}),
        table.freeze({x=1034,y=356,tile=401179,offshore=11}),
        table.freeze({x=1025,y=569,tile=640582,offshore=25}),
        table.freeze({x=899,y=428,tile=481972,offshore=9}),
        table.freeze({x=755,y=917,tile=1031464,offshore=9}),
        table.freeze({x=1009,y=982,tile=1104778,offshore=25}),
    }),
    ["974x1016"]=table.freeze({ -- africa: africa-compact
        table.freeze({x=725,y=74,tile=72802,offshore=16}),
        table.freeze({x=372,y=510,tile=497113,offshore=17}),
        table.freeze({x=113,y=458,tile=446206,offshore=14}),
        table.freeze({x=901,y=361,tile=352516,offshore=17}),
        table.freeze({x=414,y=21,tile=20869,offshore=5}),
        table.freeze({x=143,y=56,tile=54688,offshore=15}),
        table.freeze({x=862,y=754,tile=735259,offshore=8}),
        table.freeze({x=530,y=80,tile=78451,offshore=11}),
    }),
    ["1000x500"]=table.freeze({ -- world: world-compact
        table.freeze({x=476,y=82,tile=82477,offshore=13}),
        table.freeze({x=649,y=191,tile=191650,offshore=14}),
        table.freeze({x=269,y=211,tile=211270,offshore=7}),
        table.freeze({x=829,y=203,tile=203830,offshore=22}),
        table.freeze({x=591,y=285,tile=285592,offshore=14}),
        table.freeze({x=431,y=247,tile=247432,offshore=15}),
        table.freeze({x=242,y=67,tile=67243,offshore=6}),
        table.freeze({x=501,y=354,tile=354502,offshore=17}),
    }),
})
