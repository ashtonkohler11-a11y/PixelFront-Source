--!strict
--!native
-- Exact official terrain data is authored once in ReplicatedStorage.OpenFrontMap.
-- OpenFront GameMap.ts / TerrainMapLoader.ts at Config.ReferenceRevision.
local Config = require(script.Parent.Config)
export type Map = { width: number, height: number, land: { boolean }, landCount: number, terrain: buffer, name: string, navigation: any?, navigationRuntime: any?, manifest: any?, mapType: string?, mapSize: string?, asset: Instance?, waterVersion: number?, waterGraphVersion: number? }
local MapData = {}
local cached: Map? = nil
local variants: {[string]: Map} = setmetatable({}, {__mode="v"}) :: any
local Encoding = game:GetService("EncodingService")
local Http = game:GetService("HttpService")
function MapData.clone(map: Map): Map
    local result=table.clone(map)
    result.navigationRuntime=nil
    result.terrain=buffer.create(buffer.len(map.terrain));buffer.copy(result.terrain,0,map.terrain)
    result.land=table.clone(map.land)
    -- The water manager makes its own mutable minimap and graph from this bake.
    local navigation=MapData.navigation(map)
    result.navigation=if navigation then table.clone(navigation)else nil
    return result
end
local function chunks(folder: Instance, prefix: string, count: number): string
    local pieces=table.create(count)
    for i=1,count do
        local piece=folder:WaitForChild(string.format("%s%04d",prefix,i),15) :: StringValue
        assert(piece,"Missing official map chunk");pieces[i]=piece.Value
    end
    return table.concat(pieces)
end
function MapData.decompress(encoded: string, expectedSize: number?): buffer
    local compressed=Encoding:Base64Decode(buffer.fromstring(encoded))
    local size=Encoding:GetDecompressedBufferSize(compressed,Enum.CompressionAlgorithm.Zstd)
    assert(size~=nil and (expectedSize==nil or size==expectedSize),"Official map compressed dimensions differ")
    return Encoding:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd)
end

function MapData.neighbors(id: number, width: number, height: number, output: { number }?): { number }
    local result = output or {}
    if output then table.clear(result) end
    if id ~= id or id % 1 ~= 0 or id < 1 or id > width * height then return result end
    local x = (id - 1) % width
    -- Reference iteration order affects deterministic expansion/spawn ties.
    if id > width then table.insert(result, id - width) end
    if id <= width * (height - 1) then table.insert(result, id + width) end
    if x > 0 then table.insert(result, id - 1) end
    if x < width - 1 then table.insert(result, id + 1) end
    return result
end

function MapData.fromTerrain(width: number, height: number, terrain: buffer, landCount: number?, name: string?): Map
    assert(buffer.len(terrain) == width * height, "Terrain dimensions do not match")
    local land = table.create(width * height, false)
    local count = 0
    for id = 1, width * height do
        local value = buffer.readu8(terrain, id - 1)
        local passable = bit32.band(value, 128) ~= 0 and bit32.band(value, 31) ~= 31
        land[id] = passable
        if passable then count += 1 end
    end
    if landCount ~= nil then assert(count == landCount, "Official terrain land count differs from manifest") end
    return { width = width, height = height, terrain = terrain, land = land, landCount = count, name = name or "Reference fixture" }
end

function MapData.generate(_seed: number, mapType: string?, mapSize: string?): Map
    if mapType~=nil then
        local runService=game:GetService("RunService")
        local storage=if runService:IsRunning()and runService:IsClient()then game:GetService("ReplicatedStorage")else game:GetService("ServerStorage")
        if mapType=="World"and(mapSize==nil or mapSize=="Normal")and not storage:FindFirstChild("OpenFrontMaps")then return MapData.generate(_seed)end
        local key=mapType..":"..(mapSize or "Normal")
        -- A released replicated clone is destroyed; never serve a map bound to it.
        local hit=variants[key]
        if hit and hit.asset and hit.asset.Parent~=nil then return hit end
        variants[key]=nil
        local catalog=require(script.Parent.OpenFrontMapCatalog)
        local info=nil;for _,entry in catalog.maps do if entry.type==mapType then info=entry;break end end
        -- PF029: tutorial-only maps are not in the pinned catalog; their entries are OpenFrontTutorialMapCatalog's (none now)
        if not info then for _,entry in require(script.Parent.OpenFrontTutorialMapCatalog).maps do if entry.type==mapType then info=entry;break end end end
        assert(info,"Unknown official map")
        assert(mapSize==nil or mapSize=="Normal"or mapSize=="Compact","Invalid official map size")
        local assets=storage:WaitForChild("OpenFrontMaps",15)
        local asset=assets and assets:WaitForChild(info.id.."_"..(mapSize or "Normal"),15)
        assert(asset and asset:GetAttribute("Ready")==true,"Official selected map has not been imported")
        assert(asset:GetAttribute("ReferenceRevision")==Config.ReferenceRevision,"Map reference revision differs")
        local width,height=asset:GetAttribute("Width") :: number,asset:GetAttribute("Height") :: number
        local terrain=MapData.decompress(chunks(asset,"Terrain",asset:GetAttribute("TerrainChunks") :: number),width*height)
        local map=MapData.fromTerrain(width,height,terrain,asset:GetAttribute("LandCount") :: number,mapType)
        map.manifest=Http:JSONDecode((asset:WaitForChild("Manifest") :: StringValue).Value)
        map.mapType,map.mapSize,map.asset=mapType,mapSize or "Normal",asset
        variants[key]=map;return map
    end
    if cached then return cached end
    local asset = game:GetService("ReplicatedStorage"):WaitForChild(Config.Map.AssetName, 15)
    assert(asset and asset:GetAttribute("Ready") == true, "The official native map asset has not been imported")
    assert(asset:GetAttribute("ReferenceRevision") == Config.ReferenceRevision, "Map reference revision differs")
    local width = asset:GetAttribute("Width") :: number
    local height = asset:GetAttribute("Height") :: number
    local count = asset:GetAttribute("ChunkCount") :: number
    local pieces = table.create(count)
    for i = 1, count do
        local chunk = asset:WaitForChild(string.format("Chunk%04d", i), 15) :: StringValue
        assert(chunk, "Missing terrain chunk")
        pieces[i] = chunk.Value
    end
    local encoded = table.concat(pieces)
    assert(#encoded % 6 == 0, "Malformed terrain encoding")
    local terrain = buffer.create(width * height)
    local cursor = 0
    for offset = 1, #encoded, 6 do
        local length = tonumber(string.sub(encoded, offset, offset + 3), 16)
        local value = tonumber(string.sub(encoded, offset + 4, offset + 5), 16)
        assert(length and value and length > 0 and cursor + length <= width * height, "Invalid terrain run")
        buffer.fill(terrain, cursor, value, length)
        cursor += length
    end
    assert(cursor == width * height, "Truncated terrain")
    cached = MapData.fromTerrain(width, height, terrain, asset:GetAttribute("LandCount") :: number, asset:GetAttribute("MapName") :: string)
    local world=cached :: Map
    world.mapType="World";world.mapSize="Normal";world.asset=asset
    return cached :: Map
end

function MapData.navigation(map: Map): any?
    if map.navigation then return map.navigation end
    if map.asset and map.asset:GetAttribute("NavigationChunks")then
        local encoded=chunks(map.asset,"Navigation",map.asset:GetAttribute("NavigationChunks") :: number)
        map.navigation=Http:JSONDecode(buffer.tostring(MapData.decompress(encoded)))
    end
    return map.navigation
end

return table.freeze(MapData)
