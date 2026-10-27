--!strict
-- Opt-in Studio measurements. No diagnostics or per-frame work in production.
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Performance = {}
local studio = RunService:IsStudio()
local enabled = studio and workspace:GetAttribute("OpenFrontProfile") == true
local side = if RunService:IsServer() then "Server" else "Client"
local samples: {[string]: {number}} = {}
local counters: {[string]: number} = {}
local windows: {any} = {}
local started = os.clock()
local sequence = 0
local windowStarted = workspace:GetServerTimeNow()

function Performance.enabled(): boolean return enabled end
function Performance.observe(name: string, value: number)
    if not enabled then return end
    local values=samples[name]
    if not values then values={};samples[name]=values end
    table.insert(values,value)
end

function Performance.start(): number?
    return if enabled then os.clock() else nil
end
function Performance.finish(name: string, time: number?)
    if not time then return end
    Performance.observe(name,os.clock()-time)
end
function Performance.count(name: string, value: number)
    if enabled then counters[name] = (counters[name] or 0) + value end
end
if studio then
    workspace:GetAttributeChangedSignal("OpenFrontProfile"):Connect(function()
        enabled = workspace:GetAttribute("OpenFrontProfile") == true
        samples, counters, windows = {}, {}, {}
        started = os.clock()
        sequence=0;windowStarted=workspace:GetServerTimeNow()
    end)
    if not RunService:IsServer() then
        RunService.RenderStepped:Connect(function(dt)
            if enabled then
                local values = samples.frame
                if not values then values = {}; samples.frame = values end
                table.insert(values, dt)
            end
        end)
    end
    RunService.Heartbeat:Connect(function()
        if not enabled or os.clock() - started < 5 then return end
        local metrics = {}
        for name, values in samples do
            table.sort(values)
            local total,over30=0,0
            for _, value in values do total += value;if value>.03 then over30+=1 end end
            metrics[name] = { count = #values, totalMs = total * 1000, meanMs = total / #values * 1000,
                p95Ms = values[math.ceil(#values * .95)] * 1000, p99Ms=values[math.ceil(#values*.99)]*1000,
                over30=over30, maxMs = values[#values] * 1000 }
        end
        sequence+=1
        local ended=workspace:GetServerTimeNow()
        table.insert(windows, { sequence=sequence,startedAt=windowStarted,endedAt=ended,
            wall = os.clock() - started, metrics = metrics, counters = counters })
        if #windows > 12 then table.remove(windows, 1) end
        workspace:SetAttribute("OpenFrontProfile" .. side, HttpService:JSONEncode(windows))
        samples, counters = {}, {}
        started = os.clock()
        windowStarted=ended
    end)
end
return table.freeze(Performance)
