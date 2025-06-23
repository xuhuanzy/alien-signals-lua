---@namespace AlienSignals

-- 导入 system 模块
local system = require('alien-signals.system')
local ReactiveFlags = system.ReactiveFlags
local createReactiveSystem = system.createReactiveSystem
local link = system.link
local unlink = system.unlink
local propagate = system.propagate
local checkDirty = system.checkDirty
local endTracking = system.endTracking
local startTracking = system.startTracking
local shallowPropagate = system.shallowPropagate

---@enum EffectFlags
local EffectFlags = {
    Queued = 1 << 6, -- 64
}

-- 类型定义
---@alias EffectScope ReactiveNode

---@class Effect : ReactiveNode
---@field fn fun()

---@class Computed<T> : ReactiveNode
---@field value T
---@field getter fun(previousValue?: T): T

---@class Signal<T> : ReactiveNode
---@field previousValue T
---@field value T

-- 全局状态变量
local queuedEffects = {} ---@type (Effect | EffectScope?)[]

local batchDepth = 0
local notifyIndex = 0
local queuedEffectsLength = 0
local activeSub = nil ---@type ReactiveNode?
local activeScope = nil ---@type EffectScope?

-- 前向声明
local updateComputed, updateSignal, run, flush
local computedOper, signalOper, effectOper

---通知函数
---@param e Effect | EffectScope
local function notify(e)
    local flags = e.flags
    if (flags & 64) == 0 then -- EffectFlags.Queued
        e.flags = flags | 64 -- EffectFlags.Queued
        local subs = e.subs
        if subs ~= nil then
            notify(subs.sub)
        else
            queuedEffectsLength = queuedEffectsLength + 1
            queuedEffects[queuedEffectsLength] = e
        end
    end
end

-- 创建响应式系统
createReactiveSystem({
    ---@param signal Signal|Computed
    ---@return boolean
    update = function(signal)
        if signal.getter then
            return updateComputed(signal)
        else
            return updateSignal(signal, signal.value)
        end
    end,
    notify = notify,
    ---@param node Signal | Computed | Effect | EffectScope
    unwatched = function(node)
        if node.getter then
            local toRemove = node.deps
            if toRemove ~= nil then
                node.flags = 17 -- ReactiveFlags.Mutable | ReactiveFlags.Dirty
                repeat
                    toRemove = unlink(toRemove, node)
                until toRemove == nil
            end
        elseif not node.previousValue then
            effectOper(node)
        end
    end,
})



---获取当前订阅者
---@return ReactiveNode?
local function getCurrentSub()
    return activeSub
end

---设置当前订阅者
---@param sub ReactiveNode?
---@return ReactiveNode?
local function setCurrentSub(sub)
    local prevSub = activeSub
    activeSub = sub
    return prevSub
end

---获取当前作用域
---@return EffectScope?
local function getCurrentScope()
    return activeScope
end

---设置当前作用域
---@param scope EffectScope?
---@return EffectScope?
local function setCurrentScope(scope)
    local prevScope = activeScope
    activeScope = scope
    return prevScope
end

---开始批处理
local function startBatch()
    batchDepth = batchDepth + 1
end

---结束批处理
local function endBatch()
    batchDepth = batchDepth - 1
    if batchDepth == 0 then
        flush()
    end
end

-- Signal 创建函数
---创建信号
---@generic T
---@param initialValue? T
---@return (fun(): T) | (fun(value: T))
local function signal(initialValue)
    local signalNode = {
        previousValue = initialValue,
        value = initialValue,
        subs = nil,
        subsTail = nil,
        flags = 1, -- ReactiveFlags.Mutable
    }

    return function(...)
        return signalOper(signalNode, ...)
    end
end

-- Computed 创建函数
---创建计算属性
---@generic T
---@param getter fun(previousValue?: T): T
---@return fun(): T
local function computed(getter)
    local computedNode = {
        value = nil,
        subs = nil,
        subsTail = nil,
        deps = nil,
        depsTail = nil,
        flags = 17, -- ReactiveFlags.Mutable | ReactiveFlags.Dirty
        getter = getter,
    }

    return function()
        return computedOper(computedNode)
    end
end

-- Effect 创建函数
---创建副作用
---@param fn fun()
---@return fun()
local function effect(fn)
    ---@type Effect
    local effectNode = {
        fn = fn,
        subs = nil,
        subsTail = nil,
        deps = nil,
        depsTail = nil,
        flags = 2, -- ReactiveFlags.Watching
    }

    if activeSub ~= nil then
        link(effectNode, activeSub)
    elseif activeScope ~= nil then
        link(effectNode, activeScope)
    end

    local prev = setCurrentSub(effectNode)
    local success, err = pcall(effectNode.fn)
    setCurrentSub(prev)

    if not success then
        error(err)
    end

    return function()
        return effectOper(effectNode)
    end
end

-- EffectScope 创建函数
---创建副作用作用域
---@param fn fun()
---@return fun()
local function effectScope(fn)
    local scopeNode = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = 0, -- ReactiveFlags.None
    }

    if activeScope ~= nil then
        link(scopeNode, activeScope)
    end

    local prevSub = setCurrentSub(nil)
    local prevScope = setCurrentScope(scopeNode)
    local success, err = pcall(fn)
    setCurrentScope(prevScope)
    setCurrentSub(prevSub)

    if not success then
        error(err)
    end

    return function()
        return effectOper(scopeNode)
    end
end

-- 内部实现函数

---@param c Computed
---@return boolean
local function updateComputedPcall(c)
    local oldValue = c.value
    local newValue = c.getter(oldValue)
    c.value = newValue
    return oldValue ~= newValue
end

---更新计算属性
---@param c Computed
---@return boolean
updateComputed = function(c)
    local prevSub = setCurrentSub(c)
    startTracking(c)
    local success, result = pcall(updateComputedPcall, c)
    setCurrentSub(prevSub)
    endTracking(c)

    if not success then
        error(result)
    end
    ---@cast result -string
    return result
end

---更新信号
---@param s Signal
---@param value any
---@return boolean
updateSignal = function(s, value)
    s.flags = 1 -- ReactiveFlags.Mutable
    local changed = s.previousValue ~= value
    if changed then
        s.previousValue = value
    end
    return changed
end

---@param e Effect | EffectScope
local function runPcall(e)
    if e.fn then
        e.fn()
    end
end

---运行副作用
---@param e Effect | EffectScope
---@param flags ReactiveFlags
run = function(e, flags)
    ---@cast e.deps -?
    if (flags & 16) ~= 0 or -- ReactiveFlags.Dirty
        ((flags & 32) ~= 0 and checkDirty(e.deps, e)) then -- ReactiveFlags.Pending
        local prev = setCurrentSub(e)
        startTracking(e)
        local success, err = pcall(runPcall, e)
        setCurrentSub(prev)
        endTracking(e)

        if not success then
            error(err)
        end
        return
    elseif (flags & 32) ~= 0 then -- ReactiveFlags.Pending
        e.flags = flags & (~32) -- (~ReactiveFlags.Pending)
    end

    local link = e.deps
    while link ~= nil do
        local dep = link.dep
        local depFlags = dep.flags
        if (depFlags & 64) ~= 0 then -- EffectFlags.Queued
            run(dep, dep.flags & (~64)) -- (~EffectFlags.Queued)
            dep.flags = dep.flags & (~64) -- (~EffectFlags.Queued)
        end
        ---@cast link.nextDep -?
        link = link.nextDep
    end
end

---刷新队列
flush = function()
    while notifyIndex < queuedEffectsLength do
        notifyIndex = notifyIndex + 1
        local effect = queuedEffects[notifyIndex]
        queuedEffects[notifyIndex] = nil
        if effect then
            run(effect, effect.flags & (~64)) -- (~EffectFlags.Queued)
            effect.flags = effect.flags & (~64) -- (~EffectFlags.Queued)
        end
    end
    notifyIndex = 0
    queuedEffectsLength = 0
end

---计算属性操作函数
---@param self Computed
---@return any
computedOper = function(self)
    local flags = self.flags
    ---@cast self.deps -?
    if (flags & 16) ~= 0 or -- ReactiveFlags.Dirty
        ((flags & 32) ~= 0 and checkDirty(self.deps, self)) then -- ReactiveFlags.Pending
        if updateComputed(self) then
            local subs = self.subs
            if subs ~= nil then
                shallowPropagate(subs)
            end
        end
    elseif (flags & 32) ~= 0 then -- ReactiveFlags.Pending
        self.flags = flags & (~32) -- (~ReactiveFlags.Pending)
    end

    if activeSub ~= nil then
        link(self, activeSub)
    elseif activeScope ~= nil then
        link(self, activeScope)
    end

    return self.value
end

---信号操作函数
---@param self Signal
---@param newValue any
---@return any?
signalOper = function(self, newValue)
    if newValue then
        -- 设置值
        if self.value ~= newValue then
            self.value = newValue
            self.flags = 17 -- ReactiveFlags.Mutable | ReactiveFlags.Dirty
            local subs = self.subs
            if subs ~= nil then
                propagate(subs)
                if batchDepth == 0 then
                    flush()
                end
            end
        end
    else
        -- 获取值
        local value = self.value
        if (self.flags & 16) ~= 0 then -- ReactiveFlags.Dirty
            if updateSignal(self, value) then
                local subs = self.subs
                if subs ~= nil then
                    shallowPropagate(subs)
                end
            end
        end

        if activeSub ~= nil then
            link(self, activeSub)
        end

        return value
    end
end

---副作用操作函数
---@param self Effect | EffectScope
effectOper = function(self)
    local dep = self.deps
    while dep ~= nil do
        dep = unlink(dep, self)
    end

    local sub = self.subs
    if sub ~= nil then
        unlink(sub)
    end

    self.flags = 0 -- ReactiveFlags.None
end

-- 导出模块
return {
    -- 从 system 模块重新导出
    ReactiveFlags = ReactiveFlags,
    createReactiveSystem = createReactiveSystem,

    -- 全局状态
    batchDepth = function() return batchDepth end,

    -- API 函数
    getCurrentSub = getCurrentSub,
    setCurrentSub = setCurrentSub,
    getCurrentScope = getCurrentScope,
    setCurrentScope = setCurrentScope,
    startBatch = startBatch,
    endBatch = endBatch,

    -- 创建函数
    signal = signal,
    computed = computed,
    effect = effect,
    effectScope = effectScope,
}
