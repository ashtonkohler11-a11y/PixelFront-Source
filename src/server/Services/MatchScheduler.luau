--!strict
-- Cooperative scheduling only. Simulation order/state/PRNG remain in one coroutine.
-- Dependencies are injectable so FIFO, yielding and failure cleanup can be tested
-- without Roblox events or wall-clock delays.
local Scheduler={}
Scheduler.__index=Scheduler

function Scheduler.new(options: any, hooks: any): any
    assert(options.stepSeconds>0 and options.sliceSeconds>0 and options.maxFrameDelta>0)
    assert(options.maxCatchUpSteps>=1 and options.queueLimit>=1)
    return setmetatable({options=options,hooks=hooks,clock=options.clock or os.clock,
        yieldThread=options.yieldThread or task.wait,spawn=options.spawn or task.spawn},Scheduler)
end

function Scheduler:register(context: any)
    assert(not context.schedule,"Context already registered")
    context.schedule={busy=false,inStep=false,faulted=false,removing=false,retired=false,
        queue={},head=1,tail=0}
end

function Scheduler:recover(context: any)
    -- A new state replaces a failed state; retain later FIFO commands so their
    -- original match IDs are revalidated normally by the command handler.
    if context.schedule then context.schedule.faulted=false end
end

function Scheduler:_retire(context: any)
    local state=context.schedule
    if state.retired then return end
    state.retired=true;state.busy=false;state.inStep=false
    table.clear(state.queue);state.head=1;state.tail=0
    self.hooks.removed(context)
end

function Scheduler:remove(context: any)
    local state=context.schedule
    state.removing=true
    if not state.busy then self:_retire(context) end
end

function Scheduler:_drain(context: any)
    local state=context.schedule
    while state.head<=state.tail and not state.removing do
        local entry=state.queue[state.head]
        state.queue[state.head]=nil;state.head+=1
        self.hooks.command(context,entry)
    end
    if state.head>state.tail then table.clear(state.queue);state.head=1;state.tail=0 end
end

function Scheduler:immediateStep(context: any)
    local state=context.schedule
    assert(state.busy and not state.inStep and state.immediateStep,"Immediate turns require the serialized command drain")
    state.immediateStep()
end

function Scheduler:_launch(context: any)
    local state=context.schedule
    if state.busy or state.retired or state.removing then return end
    state.busy=true -- Set before spawn: callbacks cannot launch a second job.
    state.busySince=self.clock();state.busyWarned=false
    self.spawn(function()
        local workStarted=self.clock()
        local simStarted: number?=nil
        local simCpu,simSlices=0,0
        local function closeWork()
            local now=self.clock()
            if self.hooks.workSlice then self.hooks.workSlice(now-workStarted) end
            workStarted=now
        end
        local function closeSim()
            if simStarted==nil then return end
            local elapsed=self.clock()-simStarted
            simCpu+=elapsed;simSlices+=1;simStarted=nil
            if self.hooks.sliceEnd then self.hooks.sliceEnd(elapsed) end
        end
        local function beginSim()
            simStarted=self.clock()
            if self.hooks.sliceBegin then self.hooks.sliceBegin() end
        end
        local function yieldWork(inSimulation: boolean)
            if inSimulation then closeSim() end
            closeWork()
            self.yieldThread()
            workStarted=self.clock()
            if inSimulation then beginSim() end
        end
        local function cooperate()
            if self.clock()-workStarted>=self.options.sliceSeconds then yieldWork(true) end
        end
        local function runStep()
            local tickStarted=self.clock()
            simCpu,simSlices=0,0
            state.inStep=true
            beginSim()
            local result=self.hooks.step(context,cooperate)
            closeSim()
            state.inStep=false
            if self.hooks.tickTiming then self.hooks.tickTiming(context,simCpu,self.clock()-tickStarted,simSlices) end
            if not state.removing then self.hooks.commit(context,result)end
        end
        state.immediateStep=runStep
        -- xpcall keeps the stack: a live fault logs where it threw, not just the message.
        local ok,failure=xpcall(function()
            self:_drain(context)
            local steps=0
            while not state.removing and not state.faulted and not context.paused
                and context.accumulator>=self.options.stepSeconds and steps<self.options.maxCatchUpSteps do
                if self.clock()-workStarted>=self.options.sliceSeconds then
                    yieldWork(false)
                    -- This yield was between committed ticks. Pause, reset or
                    -- departure may have arrived while suspended; apply FIFO
                    -- and re-evaluate eligibility before consuming another tick.
                    if not state.removing then self:_drain(context) end
                    continue
                end
                context.accumulator-=self.options.stepSeconds
                runStep()
                steps+=1
                if state.removing then break end
                -- Publish only a completed tick, before commands that arrived
                -- while that tick was running. Each command revalidates its ID.
                self:_drain(context)
            end
            if not state.removing and not state.faulted then self.hooks.idle(context) end
        end,function(err) return debug.traceback(tostring(err),2) end)
        -- Close a marker even when simulation/commit/command code throws.
        closeSim();closeWork()
        state.inStep=false;state.busy=false;state.immediateStep=nil
        if not ok then
            state.faulted=true;context.paused=true;context.accumulator=0
            table.clear(state.queue);state.head=1;state.tail=0
            self.hooks.failed(context,tostring(failure))
        end
        if state.removing then self:_retire(context) end
    end)
end

function Scheduler:enqueue(context: any,entry: any): boolean
    local state=context.schedule
    if state.retired or state.removing then return false end
    if state.tail-state.head+1>=self.options.queueLimit then return false end
    state.tail+=1;state.queue[state.tail]=entry
    self:_launch(context)
    return true
end

function Scheduler:heartbeat(context: any,dt: number)
    local state=context.schedule
    if state.retired or state.removing then return end
    -- Time keeps accruing during a yielded tick; it is never silently discarded.
    -- Preserve the old per-Heartbeat clamp, speed and catch-up upper bound.
    if not context.paused and not state.faulted then
        if context.maxSpeed then
            context.accumulator=math.max(context.accumulator,self.options.stepSeconds*self.options.maxCatchUpSteps)
        else context.accumulator+=math.min(dt,self.options.maxFrameDelta)*context.speed end
    end
    context.snapshotTimer+=dt
    if state.busy then
        -- A job that never finishes freezes the match silently: say so once, with its phase and tick.
        local busyFor=self.clock()-(state.busySince or self.clock())
        if not state.busyWarned and busyFor>=(self.options.busyWarnSeconds or 10) and self.hooks.busyTooLong then
            state.busyWarned=true;self.hooks.busyTooLong(context,busyFor)
        end
        return
    end
    if state.head<=state.tail or (not context.paused and not state.faulted and context.accumulator>=self.options.stepSeconds) then
        self:_launch(context)
    elseif not state.faulted then
        self.hooks.idle(context)
    end
end

return table.freeze(Scheduler)
