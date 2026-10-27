--!strict
-- Pinned MapLayerPass: original nearest PNG texture, terrain mask, alpha.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Encoding=game:GetService("EncodingService")
local Layers={};Layers.__index=Layers
function Layers.load(map: any,rootOverride: Instance?): any
    local root=rootOverride or ReplicatedStorage:FindFirstChild("OpenFrontMapLayers")
    local id=map.manifest and map.manifest.id or map.mapType
    local folder=root and root:FindFirstChild(id or "")
    local records={}
    for _,spec in map.manifest and map.manifest.layers or {}do
        local imported=folder and folder:FindFirstChild(spec.id)
        if not imported or imported:GetAttribute("Ready")~=true then continue end
        assert(imported:GetAttribute("ReferenceRevision")=="93a136a1e2915ec7bb83e34980ba5836a91f63ee","Map layer reference mismatch")
        local chunks={};for index=1,imported:GetAttribute("Chunks")do table.insert(chunks,assert(imported:FindFirstChild(string.format("Data%04d",index)))::StringValue)end
        local encoded={};for _,chunk in chunks do table.insert(encoded,chunk.Value)end
        local compressed=Encoding:Base64Decode(buffer.fromstring(table.concat(encoded)))
        local width,height=imported:GetAttribute("Width"),imported:GetAttribute("Height")
        assert(Encoding:GetDecompressedBufferSize(compressed,Enum.CompressionAlgorithm.Zstd)==width*height*4,"Map layer size mismatch")
        table.insert(records,{id=spec.id,width=width,height=height,rgba=Encoding:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd),visible=true,alpha=1,placement=spec.placement,nukeable=spec.nukeable==true,destroyed={}})
    end
    return setmetatable({map=map,records=records},Layers)
end
function Layers:setVisible(id: string,visible: boolean)for _,record in self.records do if record.id==id then record.visible=visible end end end
function Layers:setAlpha(id: string,alpha: number)for _,record in self.records do if record.id==id then record.alpha=math.clamp(alpha,0,1)end end end
function Layers:markDestroyed(id: string,tiles: {number})for _,record in self.records do if record.id==id then for _,tile in tiles do if tile>=1 and tile<=self.map.width*self.map.height then record.destroyed[tile]=true end end end end end
function Layers:composite(base: Color3,x: number,y: number,terrainByte: number): Color3
    local land=bit32.band(terrainByte,128)~=0;local tile=y*self.map.width+x+1
    for _,record in self.records do
        if not record.visible or (record.placement=="water"and land)or (record.placement=="land"and not land)or record.nukeable and record.destroyed[tile]then continue end
        local px=math.min(record.width-1,math.floor((x+.5)/self.map.width*record.width));local py=math.min(record.height-1,math.floor((y+.5)/self.map.height*record.height))
        local at=(py*record.width+px)*4;local alpha=buffer.readu8(record.rgba,at+3)/255
        if alpha<.01 then continue end
        local color=Color3.fromRGB(buffer.readu8(record.rgba,at),buffer.readu8(record.rgba,at+1),buffer.readu8(record.rgba,at+2))
        base=base:Lerp(color,alpha*record.alpha)
    end
    return base
end
return Layers
