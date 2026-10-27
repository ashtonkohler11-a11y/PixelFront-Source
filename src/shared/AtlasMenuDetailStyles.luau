--!strict
-- PF-006 authored geometry only. No services, input, economy, animation or GUI allocation.
-- The native helper materializes these recipes once; AtlasMenuMotion owns their lifecycle.
export type Rect = {xs: number, xo: number, ys: number, yo: number}
export type Piece = {
    name: string, channel: string, position: Rect, size: Rect, color: string,
    step: number, alpha: number, rest: number, rotation: number?, idle: boolean?,
    interior: boolean?, travel: boolean?,
}
export type Recipe = {pieces: {Piece}, role: string, profile: string, safeInset: number}

local Styles = {}
Styles.version = "PF006-details-v2"
Styles.owner = "PF006MenuDetails"
Styles.maxPieces = 60
Styles.roles = table.freeze({
    territory = table.freeze({color = "3678FF", story = "Connected coast advances around a frontier"}),
    survey = table.freeze({color = "8CBBCD", story = "Survey rail and contour reveal"}),
    mint = table.freeze({color = "DDBF76", story = "Gilded stepped rim and restrained coin glint"}),
    crystal = table.freeze({color = "5D9EFF", story = "Cobalt seam advances along a crystal edge"}),
    claim = table.freeze({color = "75A6F5", story = "Owned selection seals its territory perimeter"}),
    route = table.freeze({color = "7BA5E1", story = "Short stepped route carries focus to the control"}),
    nav = table.freeze({color = "3678FF", story = "Pixel coastline beneath retained navigation underline"}),
    aurora = table.freeze({color = "9DDCCF", story = "Quiet northern-light edge; retained rays own the showcase"}),
})
Styles.profiles = table.freeze({card = 12, map = 10, metric = 5, row = 5,
    control = 4, nav = 4, header = 10, status = 3, field = 4, track = 2, carrier = 0})

local GOLD = "DDBF76"
local LIGHT_GOLD = "F2D999"
local function rect(xs: number, xo: number, ys: number, yo: number): Rect
    return {xs = xs, xo = xo, ys = ys, yo = yo}
end

function Styles.recipe(profile: string, role: string): Recipe
    local palette = (Styles.roles :: any)[role]
    local inset = (Styles.profiles :: any)[profile]
    assert(palette and inset, "Unknown PF-006 detail role/profile")
    if profile == "carrier" then
        -- One valid, invisible marker keeps central phase/progress discovery alive.
        -- Separate Forge artwork owns its pixels; this recipe owns no idle/travel.
        return {role=role,profile=profile,safeInset=0,pieces={{name="ProgressMarker",channel="corner",
            position=rect(0,0,0,0),size=rect(0,0,0,0),color=palette.color,
            step=0,alpha=1,rest=1,idle=false,travel=false}}}
    end
    local pieces: {Piece} = {}
    local function add(name: string, channel: string, position: Rect, size: Rect,
        step: number, alpha: number, rest: number, color: string?, rotation: number?, idle: boolean?, interior: boolean?, travel: boolean?)
        table.insert(pieces, {name = name, channel = channel, position = position, size = size,
            color = color or palette.color, step = step, alpha = alpha, rest = rest,
            rotation = rotation, idle = idle, interior = interior, travel = travel})
    end
    -- These are ornaments, with no count or monetary glyph. Four aligned native
    -- pieces form the original stepped coin silhouette entirely inside a gutter.
    local function coin(x: number, y: number, scaleX: number, scaleY: number)
        add("CoinCore", "coin", rect(scaleX, x + 2, scaleY, y), rect(0, 4, 0, 8), .8, .40, .65, GOLD)
        add("CoinShoulder", "coin", rect(scaleX, x, scaleY, y + 2), rect(0, 8, 0, 4), .8, .40, .65, GOLD)
        add("CoinInset", "coin", rect(scaleX, x + 3, scaleY, y + 3), rect(0, 2, 0, 3), .84, .32, .74, "886D39")
        add("CoinGlint", "coin", rect(scaleX, x + 2, scaleY, y + 1), rect(0, 3, 0, 1), .89, .18, .62, LIGHT_GOLD, nil, true)
    end
    local function bottom(count: number, height: number, start: number, span: number)
        for i = 1, count do
            local coast = if profile == "card" then ({3, 6, 4, 9, 6, 10, 7})[(i - 1) % 7 + 1]
                elseif role == "route" then (if i % 3 == 0 then height else math.max(1, height - 2))
                elseif role == "crystal" then (if i % 2 == 0 then height else math.max(1, height - 1))
                else height
            add("CellBottom" .. i, "cell", rect((i - 1) / count, 1, 1, -coast - 1),
                rect(1 / count, -1, 0, coast), start + (i - 1) / count * span, .86, 1)
        end
    end
    local function corners()
        add("CornerUpper", "corner", rect(0, 1, 0, 1), rect(0, inset - 1, 0, 1), .04, .34, .73, GOLD)
        add("CornerSide", "corner", rect(0, 1, 0, 2), rect(0, 1, 0, inset - 2), .05, .34, .73, GOLD)
        add("CornerLower", "corner", rect(1, -inset, 1, -2), rect(0, inset - 1, 0, 1), .92, .40, .79, GOLD)
    end
    local function conquest(columns: number, rows: number, x: number, y: number, width: number, height: number)
        local branches = {0, 1.4, .6}
        for row = 1, rows do for column = 1, columns do
            -- Every row starts at the same connected left coast. Branch delays
            -- begin after column one, so no lower-row island outruns its bridge.
            local rank = if column == 1 then 0 else (column - 1 + branches[(row - 1) % 3 + 1]) / (columns + 1.4)
            add("Conquest" .. row .. "_" .. column, "cell", rect(x + (column - 1) * width / columns, 0, y + (row - 1) * height / rows, 0),
                rect(width / columns, 0, height / rows, 0), rank, .88, .985, nil, nil, nil, true)
        end end
        for column = 1, 8 do
            add("Frontier" .. column, "frontier", rect(x + (column - 1) * width / 8, 0, y, 0),
                rect(0, 2, height, 0), (column - 1) / 8, .64, 1, nil, nil, nil, true, true)
        end
    end
    local function survey(x: number, y: number, width: number, height: number)
        for row = 1, 3 do for column = 1, 8 do
            add("Survey" .. row .. "_" .. column, "cell", rect(x + (column - 1) * width / 8, 0, y + (row - 1) * height / 3, 0),
                rect(width / 8, -1, height / 3, -1), (column - 1 + (row - 1) * .4) / 8, .93, .993, nil, nil, nil, true)
        end end
        for i = 1, 3 do
            add("SurveyCross" .. i, "rail", rect(x, 0, y + i * height / 4, 0), rect(width, 0, 0, 1), .2 * i, .68, .95, nil, nil, nil, true)
        end
        add("SurveyMeridian", "frontier", rect(x + width * .64, 0, y, 0), rect(0, 1, height, 0), .72, .64, 1, nil, nil, nil, true, true)
    end
    local function facets(x: number, y: number, width: number, height: number)
        for row = 1, 3 do for column = 1, 4 do
            add("Facet" .. row .. "_" .. column, "cell", rect(x + (column - 1) * width / 4 + width / 32, 0, y + (row - 1) * height / 3 + height / 18, 0),
                rect(width * .18, 0, height * .19, 0), (column - 1 + (3 - row) * .5) / 5, .91, .988, nil, 24, nil, true)
        end end
        for i = 1, 4 do
            add("CrystalSeam" .. i, "rail", rect(x + i * width / 5, 0, y, 0), rect(0, 1, height, 0), .18 * i, .72, .96, nil, nil, nil, true)
        end
    end
    local function claim(x: number, y: number, width: number, height: number)
        for row = 1, 3 do for column = 1, 6 do
            local rank = math.max(math.abs(column - 3.5) / 3.5, math.abs(row - 2) / 2)
            add("ClaimSeal" .. row .. "_" .. column, "cell", rect(x + (column - 1) * width / 6, 1, y + (row - 1) * height / 3, 1),
                rect(width / 6, -2, height / 3, -2), rank, .91, .988, nil, nil, nil, true)
        end end
        add("SealTop", "rail", rect(x, 1, y, 1), rect(width, -2, 0, 1), .78, .68, .93, GOLD, nil, nil, true)
        add("SealBottom", "rail", rect(x, 1, y + height, -2), rect(width, -2, 0, 1), .84, .68, .93, GOLD, nil, nil, true)
    end
    local function routing(x: number, y: number, width: number, height: number)
        local turns = {.75, .75, .55, .55, .35, .35, .55, .55, .25, .25, .45, .45}
        for i, level in turns do
            add("RouteStep" .. i, "cell", rect(x + (i - 1) * width / 12, 0, y + level * height, 0),
                rect(width / 12, 0, height * .12, 0), (i - 1) / 12, .86, .975, nil, nil, nil, true)
            if i > 1 and turns[i - 1] ~= level then
                add("RouteRise" .. i, "rail", rect(x + (i - 1) * width / 12, 0, y + math.min(level, turns[i - 1]) * height, 0),
                    rect(0, 1, math.abs(level - turns[i - 1]) * height, 0), (i - 1) / 12, .66, .98, nil, nil, nil, true)
            end
        end
        add("RouteArrival", "beacon", rect(x + width, -3, y + height * .45, 0), rect(0, 2, 0, 2), .96, .35, .75, GOLD, nil, true, true, true)
    end
    local function minting(x: number, y: number, width: number, height: number)
        for i = 1, 12 do
            add("GildedTile" .. i, "cell", rect(x + (i - 1) * width / 12, 0, y + (if i % 2 == 0 then .15 else .52) * height, 0),
                rect(width / 12, -1, height * .28, 0), (i - 1) / 12, .90, .99, GOLD, nil, nil, true)
        end
        for i = 1, 3 do
            add("MintBand" .. i, "band", rect(x + i * width / 4, 0, y, 0), rect(0, 3, height, 0), .18 * i, .94, .988, LIGHT_GOLD, 28, nil, true)
            add("MintGlint" .. i, "beacon", rect(x + i * width / 4, 0, y + .55 * height, 0), rect(0, 2, 0, 2), .23 * i, .48, .80, LIGHT_GOLD, nil, true, true, true)
        end
    end
    local function aurora(x: number, y: number, width: number, height: number)
        for i = 1, 3 do
            add("AuroraRibbon" .. i, "band", rect(x + i * width / 4, 0, y, 0), rect(width * .08, 0, height, 0),
                .2 * i, .96, .992, if i == 2 then "AB9BE0" else palette.color, -18, nil, true)
        end
        for i = 1, 12 do
            add("AuroraEdge" .. i, "cell", rect(x + (i - 1) * width / 12, 0, y + height * .75, 0),
                rect(width / 12, -1, height * .18, 0), (i - 1) / 12, .90, .99, nil, nil, nil, true)
        end
    end
    local function signature(x: number, y: number, width: number, height: number)
        if role == "territory" then conquest(12, 3, x, y, width, height)
        elseif role == "survey" then survey(x, y, width, height)
        elseif role == "crystal" then facets(x, y, width, height)
        elseif role == "claim" then claim(x, y, width, height)
        elseif role == "route" then routing(x, y, width, height)
        elseif role == "mint" then minting(x, y, width, height)
        elseif role == "aurora" then aurora(x, y, width, height)
        else
            for i = 1, 12 do
                add("NavCoast" .. i, "cell", rect((i - 1) / 12, 0, .76, 0), rect(1 / 12, 0, .08 + (i % 3) * .04, 0),
                    (i - 1) / 12, .85, .985, nil, nil, nil, true)
            end
        end
    end
    if profile == "card" then
        signature(0, .68, 1, .32)
        add("TopRail", "rail", rect(0, 12, 0, 1), rect(1, -24, 0, 1), .85, .64, .91)
        add("RightRail", "rail", rect(1, -2, 0, 12), rect(0, 1, 1, -24), .96, .64, .94)
        -- Diagonal survey bands sit inside the outer right gutter, clipped before art/text.
        for i = 1, 3 do
            add("Band" .. i, "band", rect(1, -7, .18 + (i - 1) * .24, 0),
                rect(0, 2, 0, 18), .15 * i, .94, .985, nil, 28)
        end
        corners(); coin(-11, 5, 1, 0)
        add("GoldBeacon", "beacon", rect(1, -5, 1, -18), rect(0, 2, 0, 2), .86, .30, .74, LIGHT_GOLD, nil, true)
    elseif profile == "map" then
        survey(0, 0, 1, 1)
        add("SurveyRail", "rail", rect(0, 1, 0, 1), rect(1, -2, 0, 1), .85, .42, .82)
        corners()
        add("SurveyBeacon", "beacon", rect(1, -4, 0, 12), rect(0, 2, 0, 2), .92, .28, .68, LIGHT_GOLD, nil, true)
    elseif profile == "header" then
        -- No horizontal ornament crosses a title, wallet/count, or navigation action.
        add("HeadingRail", "rail", rect(0, 1, 1, -2), rect(1, -2, 0, 1), .12, .59, .90)
        add("HeadingGilt", "corner", rect(0, 1, 0, 2), rect(0, 2, 0, 12), .2, .35, .76, GOLD)
        for i = 1, 3 do
            add("HeadingStep" .. i, "cell", rect(0, 1, 0, 17 + i * 5), rect(0, 2, 0, 4), i / 4, .78, .94)
        end
        coin(-10, 3, 1, 0)
    elseif profile == "status" then
        add("StatusRail", "rail", rect(0, 0, 1, -1), rect(1, 0, 0, 1), .1, .80, .95)
        for i = 1, 6 do
            add("StatusStep" .. i, "cell", rect((i - 1) / 6, 0, 1, -2), rect(1 / 6, -1, 0, 1),
                (i - 1) / 6, .67, 1)
        end
        add("StatusBeacon", "beacon", rect(0, 1, 0, 1), rect(0, 2, 0, 2), .85, .32, .72, GOLD, nil, true)
    elseif profile == "track" then
        bottom(10, 1, 0, .9)
        add("RouteFrontier", "frontier", rect(0, 1, 0, 0), rect(0, 1, 1, 0), .95, .45, 1)
    else
        if profile == "metric" or profile == "row" then signature(0, .68, 1, .32)
        else signature(0, 0, 1, 1) end
        corners()
        add("GiltPin", "beacon", rect(1, -3, 0, 2), rect(0, 1, 0, 1), .92, .28, .74, GOLD)
    end
    assert(#pieces <= Styles.maxPieces, "PF-006 recipe exceeds authored piece budget")
    return {pieces = pieces, role = role, profile = profile, safeInset = inset}
end

return table.freeze(Styles)
