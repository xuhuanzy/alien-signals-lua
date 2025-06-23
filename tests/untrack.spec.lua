local test = require('luakit.test').test
local expect = require('luakit.test').expect
local testPrintStats = require('luakit.test').testPrintStats
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed
local effect = AlienSignals.effect
local effectScope = AlienSignals.effectScope
local setCurrentSub = AlienSignals.setCurrentSub

-- 测试1: 在 computed 中暂停追踪
test('should pause tracking in computed', function()
    local src = signal(0)

    local computedTriggerTimes = 0
    local c = computed(function()
        computedTriggerTimes = computedTriggerTimes + 1
        local currentSub = setCurrentSub(nil) -- 暂停追踪
        -- 由于追踪被暂停, 所以此时调用 src 不会被记录到依赖中, 即后面修改 src 也不会触发 computed 的重新计算
        local value = src()
        setCurrentSub(currentSub) -- 恢复追踪
        return value
    end)

    expect(c()):toBe(0)
    expect(computedTriggerTimes):toBe(1)

    -- 修改源信号多次
    src(1)
    src(2)
    src(3)

    -- computed 应该没有重新计算, 因为追踪被暂停了
    expect(c()):toBe(0)
    expect(computedTriggerTimes):toBe(1)
end)

-- 测试2: 在 effect 中暂停追踪
test('should pause tracking in effect', function()
    local src = signal(0)
    local is = signal(0)

    local effectTriggerTimes = 0
    effect(function()
        effectTriggerTimes = effectTriggerTimes + 1
        local isValue = is()
        if isValue ~= 0 then
            local currentSub = setCurrentSub(nil)
            local srcValue = src()
            setCurrentSub(currentSub)
        end
    end)

    expect(effectTriggerTimes):toBe(1)

    -- 启用条件
    is(1)
    expect(effectTriggerTimes):toBe(2)

    -- 修改 src, 但由于追踪暂停, effect 不应该触发
    src(1)
    src(2)
    src(3)
    expect(effectTriggerTimes):toBe(2)

    -- 再次修改条件
    is(2)
    expect(effectTriggerTimes):toBe(3)

    -- 再次修改 src, effect 仍然不应该触发
    src(4)
    src(5)
    src(6)
    expect(effectTriggerTimes):toBe(3)

    -- 关闭条件
    is(0)
    expect(effectTriggerTimes):toBe(4)

    -- 修改 src, effect 仍然不应该触发
    src(7)
    src(8)
    src(9)
    expect(effectTriggerTimes):toBe(4)
end)

-- 测试3: 在 effect scope 中暂停追踪
test('should pause tracking in effect scope', function()
    local src = signal(0)

    local effectTriggerTimes = 0
    effectScope(function()
        effect(function()
            effectTriggerTimes = effectTriggerTimes + 1
            local currentSub = setCurrentSub(nil)
            local srcValue = src()
            setCurrentSub(currentSub)
        end)
    end)

    expect(effectTriggerTimes):toBe(1)

    -- 修改源信号多次, effect 不应该重新触发
    src(1)
    src(2)
    src(3)
    expect(effectTriggerTimes):toBe(1)
end)

testPrintStats()
