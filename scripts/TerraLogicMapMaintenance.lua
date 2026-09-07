-- Shared SP/server mask scheduler. Uses the existing half-metre authority
-- and mask writer unchanged. Client transport is budgeted separately.
TerraLogicMapMaintenance = {
    presets = {
        gentle={cleanup=256, server=256, client=256, request=120, fastRequest=60, cooldown=50},
        fast={cleanup=768, server=768, client=768, request=60, fastRequest=30, cooldown=25}
    }
}
local M = TerraLogicMapMaintenance
local function nowMs() return g_currentMission ~= nil and g_currentMission.time or 0 end
local function key(x,z) return tostring(x)..":"..tostring(z) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1000000 end

function M:applyPreset(name)
    self.preset = name=="fast" and "fast" or "gentle"
    local p=self.presets[self.preset]; local s=TerraLogicSoilManager
    s.NETWORK_SERVER_TILE_CELLS_PER_FRAME=p.server
    s.NETWORK_TILE_APPLY_CELLS_PER_FRAME=p.client
    s.NETWORK_TILE_REQUEST_INTERVAL_MS=p.request
    s.NETWORK_TILE_FAST_REQUEST_INTERVAL_MS=p.fastRequest
    s.NETWORK_SERVER_TILE_COOLDOWN_MS=p.cooldown
    s.NETWORK_TILE_REFRESH_MS=self.preset=="fast" and 5000 or 12000
    s.NETWORK_TILE_MAX_PENDING_JOBS=4
    s.NETWORK_TILE_MAX_INFLIGHT_REQUESTS=4
end

function M:reset()
    self.interests={}; self.interestOrder={}; self.ownerCursor=0
    self.checked={}; self.recent={}; self.offsets={}
    self.globalJobs={}; self.cursor=0; self.cycles=0
    self.localTurns=0; self.completed=0
    self:applyPreset(TerraLogicSettings.mapUpdatePreset)
end

function M:getOffsets(radius)
    local offsets=self.offsets[radius]
    if offsets~=nil then return offsets end
    offsets={}
    for z=-radius,radius do for x=-radius,radius do
        if x*x+z*z<=(radius+0.75)^2 then
            offsets[#offsets+1]={x=x,z=z,d=x*x+z*z}
        end
    end end
    table.sort(offsets,function(a,b)
        if a.d==b.d then if a.z==b.z then return a.x<b.x end; return a.z<b.z end
        return a.d<b.d
    end)
    self.offsets[radius]=offsets
    return offsets
end

function M:setInterest(owner,x,z,radius)
    if not finite(x) or not finite(z) or not finite(radius) then return end
    local s=TerraLogicSoilManager; local half=(s.terrainSize or 2048)/2
    if math.abs(x)>half+32 or math.abs(z)>half+32 then return end
    -- Full-map view never promotes the whole world into the local queue.
    radius=math.max(1,math.min(32,math.ceil(radius/32)))
    local tx,tz=math.floor(x/32),math.floor(z/32)
    local old=self.interests[owner]
    if old==nil then self.interestOrder[#self.interestOrder+1]=owner end
    if old==nil or old.x~=tx or old.z~=tz or old.radius~=radius then
        self.interests[owner]={x=tx,z=tz,radius=radius,cursor=0,recentCursor=0,time=nowMs()}
    else old.time=nowMs() end
end

function M:markChanged(x,z)
    if self.inCleanup or self.recent==nil then return end
    local k=key(x,z)
    -- Coalesce writes, including the five separate soil layers.
    if self.recent[k]==nil then self.recent[k]=nowMs() end
end

function M:onCompleted(job)
    self.checked[key(job.tileX,job.tileZ)]=nowMs()
    self.recent[key(job.tileX,job.tileZ)]=nil
    self.completed=self.completed+1
    if job.globalIndex~=nil then
        self.cursor=job.globalIndex+1
    end
end

function M:queueLocal()
    local s=TerraLogicSoilManager; local now=nowMs()
    -- Expired/disconnected viewers must not consume somebody else's share.
    for i=#self.interestOrder,1,-1 do
        local owner=self.interestOrder[i]; local item=self.interests[owner]
        if item==nil or now-item.time>15000 then
            self.interests[owner]=nil; table.remove(self.interestOrder,i)
        end
    end
    for _=1,#self.interestOrder do
        self.ownerCursor=self.ownerCursor%#self.interestOrder+1
        local item=self.interests[self.interestOrder[self.ownerCursor]]
        local offsets=self:getOffsets(item.radius)
        self.localTurns=self.localTurns+1
        -- Alternate changed-first with a persistent fair cursor. Even constant
        -- work cannot starve ordinary visible tiles. Global has its own budget.
        local recentTurn=self.localTurns%2==1
        for pass=recentTurn and 1 or 2,2 do
            local cursorKey=pass==1 and "recentCursor" or "cursor"
            for _=1,math.min(#offsets,256) do
                local idx=item[cursorKey]%#offsets+1; item[cursorKey]=idx
                local p=offsets[idx]; local x,z=item.x+p.x,item.z+p.z
                local k=key(x,z); local last=self.checked[k]
                local changed=self.recent[k]
                local due=last==nil or now-last>=120000
                    or (changed~=nil and changed>=last and now-last>=10000)
                if due and (pass==2 or changed~=nil) then
                    if s:queueCoverageTile(x,z) then return true end
                end
            end
        end
    end
    return false
end

function M:queueGlobal()
    if #self.globalJobs>0 then return end
    local s=TerraLogicSoilManager
    local first=math.floor(-(s.terrainSize or 2048)/64)
    local side=math.ceil((s.terrainSize or 2048)/32)
    local total=side*side
    for _=1,16 do
        if self.cursor>=total then self.cursor=0; self.cycles=self.cycles+1 end
        local index=self.cursor
        local x,z=first+index%side,first+math.floor(index/side)
        local last=self.checked[key(x,z)]
        if last~=nil and nowMs()-last<120000 then
            self.cursor=self.cursor+1
        else
            local localJobs=s.coverageReconcileJobs
            s.coverageReconcileJobs=self.globalJobs
            local queued=s:queueCoverageTile(x,z)
            s.coverageReconcileJobs=localJobs
            if queued then self.globalJobs[1].globalIndex=index end
            -- If a local job owns this tile, wait for it; never skip unexamined terrain.
            return
        end
    end
end

function M:update()
    local s=TerraLogicSoilManager
    if g_server==nil or s.rasterReady~=true then return end
    local budget=self.presets[self.preset or "gentle"].cleanup
    self:queueGlobal()
    if #s.coverageReconcileJobs==0 then self:queueLocal() end
    self.inCleanup=true
    local globalShare=math.floor(budget/4)
    local left=s:processCoverageReconcileJobs(self.globalJobs,globalShare)
    local localLeft=s:processCoverageReconcileJobs(s.coverageReconcileJobs,
        budget-globalShare+left)
    -- Idle local budget goes to global work. The reverse happened above.
    if localLeft>0 then
        self:queueGlobal()
        s:processCoverageReconcileJobs(self.globalJobs,localLeft)
    end
    self.inCleanup=false
end

function M:getDebugText()
    local s=TerraLogicSoilManager
    local side=math.ceil((s.terrainSize or 2048)/32)
    if g_server==nil then
        return " | map updates "..tostring(self.preset).." (cleanup on server)"
    end
    return string.format(" | map updates %s cleanup cursor=%d/%d cycles=%d completed=%d localJobs=%d globalJobs=%d viewers=%d",
        self.preset or "gentle",self.cursor or 0,side*side,self.cycles or 0,
        self.completed or 0,#(s.coverageReconcileJobs or {}),
        #(self.globalJobs or {}),#(self.interestOrder or {}))
end
