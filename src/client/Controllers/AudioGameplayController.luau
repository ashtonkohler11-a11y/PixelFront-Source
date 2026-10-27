--!strict
-- Original SoundEffectController rules; caller supplies detached, ordered source update batches.
local Controller={};Controller.__index=Controller
local STATION={City=true,Factory=true,Port=true}
local INBOUND={NUKE_INBOUND=true,HYDROGEN_BOMB_INBOUND=true,MIRV_INBOUND=true}
local OWN_CREATED={Warship="build-warship",City="build-city",Port="build-port",["Defense Post"]="build-defense-post",
    ["SAM Launcher"]="sam-built",["Missile Silo"]="silo-built",Factory="build-factory",Transport="transport-ship"}
local GLOBAL_CREATED={["Atom Bomb"]="atom-launch",["Hydrogen Bomb"]="hydrogen-launch",MIRV="mirv-launch"}
function Controller.new(play: (string)->()): any
    return setmetatable({play=play,hadTrainStation={},lastMirv=-math.huge,lastWarning=-math.huge,lastStation=-math.huge,lastSweep=-math.huge},Controller)
end
function Controller:spawnIntent(myPlayer: number?) if myPlayer~=nil then self.play("spawn") end end
function Controller:handleUnit(frame: any,unit: any)
    local tick=frame.ticks
    if unit.active and unit.createdTick==tick then
        local global=GLOBAL_CREATED[unit.unitType]
        if global then self.play(global)elseif frame.myPlayer~=nil and unit.owner==frame.myPlayer then local own=OWN_CREATED[unit.unitType];if own then self.play(own)end end
    end
    if STATION[unit.unitType] then
        if not unit.active then self.hadTrainStation[unit.id]=nil
        else
            local previous=self.hadTrainStation[unit.id]
            if previous==false and unit.hasTrainStation and frame.myPlayer~=nil and unit.owner==frame.myPlayer and tick-self.lastStation>=10 then
                self.lastStation=tick;self.play("build-train-station")
            end
            self.hadTrainStation[unit.id]=unit.hasTrainStation==true
        end
    end
    if unit.active or not unit.reachedTarget then return end
    if unit.unitType=="Atom Bomb" then self.play("atom-hit")
    elseif unit.unitType=="Hydrogen Bomb" then self.play("hydrogen-hit")
    elseif unit.unitType=="MIRV Warhead" and tick-self.lastMirv>=5 then self.lastMirv=tick;self.play("atom-hit")end
end
function Controller:tick(frame: any)
    if frame.updates==nil then return end
    if frame.ticks-self.lastSweep>=100 then
        self.lastSweep=frame.ticks
        for id in self.hadTrainStation do local unit=frame.units[id];if not unit or not unit.active then self.hadTrainStation[id]=nil end end
    end
    for _,update in frame.updates.units or {} do local unit=frame.units[update.id];if unit then self:handleUnit(frame,unit)end end
    if #(frame.updates.spawnPhaseEnd or {})>0 then self.play("game-start")end
    if frame.myPlayer==nil then return end
    local me=frame.players[frame.myPlayer]
    for _,event in frame.updates.conquests or {} do if event.conquerorId==me.id then
        local player
        for _,candidate in frame.players do if candidate.id==event.conqueredId then player=candidate;break end end
        assert(player,"Missing source conquered participant")
        self.play(if player.playerType=="Human" then "conquered"else "ka-ching")
    end end
    for _,event in frame.updates.incoming or {} do
        if event.playerID==frame.myPlayer and INBOUND[event.messageType] and frame.ticks-self.lastWarning>=10 then self.lastWarning=frame.ticks;self.play("nuke-warning")end
    end
end
return Controller
