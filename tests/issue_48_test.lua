-- Issue #48 测试
-- 从 TypeScript 测试代码转换而来

-- 导入测试框架和 alien-signals
local TestFramework = require('luakit.test')
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed
local effect = AlienSignals.effect
local setCurrentSub = AlienSignals.setCurrentSub

-- 使用测试框架
local test = TestFramework.test
local expect = TestFramework.expect
local testPrintStats = TestFramework.testPrintStats

-- untracked 函数实现
---@generic T
---@param callback fun(): T
---@return T
local function untracked(callback)
    local currentSub = setCurrentSub(nil)
    local success, result = pcall(callback)
    setCurrentSub(currentSub)
    if not success then
        error(result)
    end
    return result
end

-- reaction 函数实现
---@generic T
---@param dataFn fun(): T
---@param effectFn fun(newValue: T, oldValue: T?)
---@param options? table
---@return fun()
local function reaction(dataFn, effectFn, options)
    options = options or {}

    local scheduler = options.scheduler or function(fn) fn() end
    local equals = options.equals or function(a, b) return a == b end
    local onError = options.onError
    local once = options.once or false
    local fireImmediately = options.fireImmediately or false

    local prevValue = nil
    local version = 0

    local tracked = computed(function()
        local success, result = pcall(dataFn)
        if not success then
            untracked(function()
                if onError then
                    onError(result)
                end
            end)
            return prevValue
        end
        return result
    end)

    local dispose
    dispose = effect(function()
        local current = tracked()
        if not fireImmediately and version == 0 then
            prevValue = current
        end
        version = version + 1
        if equals(current, prevValue) then
            return
        end
        local oldValue = prevValue
        prevValue = current
        untracked(function()
            scheduler(function()
                local success, err = pcall(effectFn, current, oldValue)
                if not success and onError then
                    onError(err)
                end

                if once then
                    if fireImmediately and version > 1 then
                        dispose()
                    elseif not fireImmediately and version > 0 then
                        dispose()
                    end
                end
            end)
        end)
    end)

    return dispose
end

-- 测试 #48
test('#48', function()
    local source = signal(0)
    local disposeInner

    reaction(
        function()
            return source()
        end,
        function(val)
            if val == 1 then
                disposeInner = reaction(
                    function()
                        return source()
                    end,
                    function()
                        -- 空函数
                    end
                )
            elseif val == 2 then
                if disposeInner then
                    disposeInner()
                end
            end
        end
    )

    source(1)
    source(2)
    source(3)
end)

testPrintStats()
