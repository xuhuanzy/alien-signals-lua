---@namespace AlienSignals

-- 导入 system 模块
local system = require('alien-signals.system')
local ReactiveFlags = system.ReactiveFlags
local createReactiveSystem = system.createReactiveSystem

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
    if (flags & EffectFlags.Queued) == 0 then
        e.flags = flags | EffectFlags.Queued
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
local reactiveSystem

reactiveSystem = createReactiveSystem({
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
                    toRemove = reactiveSystem.unlink(toRemove, node)
                until toRemove == nil
            end
        elseif not node.previousValue then
            effectOper(node)
        end
    end,
})

local link = reactiveSystem.link
local unlink = reactiveSystem.unlink
local propagate = reactiveSystem.propagate
local checkDirty = reactiveSystem.checkDirty
local endTracking = reactiveSystem.endTracking
local startTracking = reactiveSystem.startTracking
local shallowPropagate = reactiveSystem.shallowPropagate

-- 导出的 API 函数

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
        flags = ReactiveFlags.Mutable,
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
        flags = ReactiveFlags.Watching,
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
        flags = ReactiveFlags.None,
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

---更新计算属性
---@param c Computed
---@return boolean
updateComputed = function(c)
    local prevSub = setCurrentSub(c)
    startTracking(c)
    local success, result = pcall(function()
        local oldValue = c.value
        local newValue = c.getter(oldValue)
        c.value = newValue
        return oldValue ~= newValue
    end)
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
    s.flags = ReactiveFlags.Mutable
    local changed = s.previousValue ~= value
    if changed then
        s.previousValue = value
    end
    return changed
end

---运行副作用
---@param e Effect | EffectScope
---@param flags ReactiveFlags
run = function(e, flags)
    if (flags & ReactiveFlags.Dirty) ~= 0 or
        ((flags & ReactiveFlags.Pending) ~= 0 and e.deps and checkDirty(e.deps, e)) then
        local prev = setCurrentSub(e)
        startTracking(e)
        local success, err = pcall(function()
            if e.fn then
                e.fn()
            end
        end)
        setCurrentSub(prev)
        endTracking(e)

        if not success then
            error(err)
        end
        return
    elseif (flags & ReactiveFlags.Pending) ~= 0 then
        e.flags = flags & (~ReactiveFlags.Pending)
    end

    local link = e.deps
    while link ~= nil do
        local dep = link.dep
        local depFlags = dep.flags
        if (depFlags & EffectFlags.Queued) ~= 0 then
            run(dep, dep.flags & (~EffectFlags.Queued))
            dep.flags = dep.flags & (~EffectFlags.Queued)
        end
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
            run(effect, effect.flags & (~EffectFlags.Queued))
            effect.flags = effect.flags & (~EffectFlags.Queued)
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
    if (flags & ReactiveFlags.Dirty) ~= 0 or
        ((flags & ReactiveFlags.Pending) ~= 0 and self.deps and checkDirty(self.deps, self)) then
        if updateComputed(self) then
            local subs = self.subs
            if subs ~= nil then
                shallowPropagate(subs)
            end
        end
    elseif (flags & ReactiveFlags.Pending) ~= 0 then
        self.flags = flags & (~ReactiveFlags.Pending)
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
---@param ... any
---@return any?
signalOper = function(self, ...)
    local args = { ... }
    if #args > 0 then
        -- 设置值
        local newValue = args[1]
        if self.value ~= newValue then
            self.value = newValue
            self.flags = ReactiveFlags.Mutable | ReactiveFlags.Dirty
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
        if (self.flags & ReactiveFlags.Dirty) ~= 0 then
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
---@param this Effect | EffectScope
effectOper = function(this)
    local dep = this.deps
    while dep ~= nil do
        dep = unlink(dep, this)
    end

    local sub = this.subs
    if sub ~= nil then
        unlink(sub)
    end

    this.flags = ReactiveFlags.None
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
