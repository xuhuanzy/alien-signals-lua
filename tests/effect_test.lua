-- Effect 相关测试
-- 从 TypeScript 测试代码转换而来

-- 导入测试框架和 alien-signals
local TestFramework = require('luakit.test')
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed
local effect = AlienSignals.effect
local effectScope = AlienSignals.effectScope
local setCurrentSub = AlienSignals.setCurrentSub
local startBatch = AlienSignals.startBatch
local endBatch = AlienSignals.endBatch

-- 使用测试框架
local test = TestFramework.test
local expect = TestFramework.expect
local testPrintStats = TestFramework.testPrintStats

-- 测试1: 当所有订阅者取消追踪时应清除订阅
test('should clear subscriptions when untracked by all subscribers', function()
    local bRunTimes = 0

    local a = signal(1)
    local b = computed(function()
        bRunTimes = bRunTimes + 1
        return a() * 2
    end)
    local stopEffect = effect(function()
        b()
    end)

    expect(bRunTimes):toBe(1)
    a(2)
    expect(bRunTimes):toBe(2)
    stopEffect()
    a(3)
    expect(bRunTimes):toBe(2)
end)

-- 测试2: 不应运行未追踪的内部 effect
test('should not run untracked inner effect', function()
    local a = signal(3)
    local b = computed(function()
        return a() > 0
    end)

    effect(function()
        if b() then
            effect(function()
                if a() == 0 then
                    error("bad")
                end
            end)
        end
    end)

    -- a(2)
    -- a(1)
    a(0)
end)

-- 测试3: 应该首先运行外部 effect
test('should run outer effect first', function()
    local a = signal(1)
    local b = signal(1)

    effect(function()
        if a() ~= 0 then
            effect(function()
                b()
                if a() == 0 then
                    error("bad")
                end
            end)
        else
            -- 空分支
        end
    end)

    startBatch()
    b(0)
    a(0)
    endBatch()
end)

-- 测试4: 解析可能脏状态时不应触发内部 effect
test('should not trigger inner effect when resolve maybe dirty', function()
    local a = signal(0)
    local b = computed(function()
        return a() % 2
    end)

    local innerTriggerTimes = 0

    effect(function()
        effect(function()
            b()
            innerTriggerTimes = innerTriggerTimes + 1
            if innerTriggerTimes >= 2 then
                error("bad")
            end
        end)
    end)

    a(2)
end)

-- 测试5: 应按顺序触发内部 effects
test('should trigger inner effects in sequence', function()
    local a = signal(0)
    local b = signal(0)
    local c = computed(function()
        return a() - b()
    end)
    local order = {}

    effect(function()
        c()

        effect(function()
            table.insert(order, 'first inner')
            a()
        end)

        effect(function()
            table.insert(order, 'last inner')
            a()
            b()
        end)
    end)

    -- 清空记录
    for i = #order, 1, -1 do
        order[i] = nil
    end

    startBatch()
    b(1)
    a(1)
    endBatch()

    expect(order):toEqual({ 'first inner', 'last inner' })
end)

-- 测试6: 在 effect scope 中应按顺序触发内部 effects
test('should trigger inner effects in sequence in effect scope', function()
    local a = signal(0)
    local b = signal(0)
    local order = {}

    effectScope(function()
        effect(function()
            table.insert(order, 'first inner')
            a()
        end)

        effect(function()
            table.insert(order, 'last inner')
            a()
            b()
        end)
    end)

    -- 清空记录
    for i = #order, 1, -1 do
        order[i] = nil
    end

    startBatch()
    b(1)
    a(1)
    endBatch()

    expect(order):toEqual({ 'first inner', 'last inner' })
end)

-- 测试7: 自定义 effect 应支持批处理
test('should custom effect support batch', function()
    local function batchEffect(fn)
        return effect(function()
            startBatch()
            local success, result = pcall(fn)
            endBatch()
            if not success then
                error(result)
            end
        end)
    end

    local logs = {}
    local a = signal(0)
    local b = signal(0)

    local aa = computed(function()
        table.insert(logs, 'aa-0')
        if a() == 0 then
            b(1)
        end
        table.insert(logs, 'aa-1')
    end)

    local bb = computed(function()
        table.insert(logs, 'bb')
        return b()
    end)

    batchEffect(function()
        bb()
    end)
    batchEffect(function()
        aa()
    end)

    expect(logs):toEqual({ 'bb', 'aa-0', 'aa-1', 'bb' })
end)

-- 测试8: 重复的订阅者不应影响通知顺序
test('should duplicate subscribers do not affect the notify order', function()
    local src1 = signal(0)
    local src2 = signal(0)
    local order = {}

    effect(function()
        table.insert(order, 'a')
        local currentSub = setCurrentSub(nil)
        local isOne = src2() == 1
        setCurrentSub(currentSub)
        if isOne then
            src1()
        end
        src2()
        src1()
    end)

    effect(function()
        table.insert(order, 'b')
        src1()
    end)

    src2(1) -- src1.subs: a -> b -> a

    -- 清空记录
    for i = #order, 1, -1 do
        order[i] = nil
    end

    src1(src1() + 1)

    expect(order):toEqual({ 'a', 'b' })
end)

-- 测试9: 应处理带有内部 effects 的副作用
test('should handle side effect with inner effects', function()
    local a = signal(0)
    local b = signal(0)
    local order = {}

    effect(function()
        effect(function()
            a()
            table.insert(order, 'a')
        end)
        effect(function()
            b()
            table.insert(order, 'b')
        end)
        expect(order):toEqual({ 'a', 'b' })

        -- 清空记录
        for i = #order, 1, -1 do
            order[i] = nil
        end

        b(1)
        a(1)
        expect(order):toEqual({ 'b', 'a' })
    end)
end)

-- 测试10: 应处理在 checkDirty 期间间接更新的标志
test('should handle flags are indirectly updated during checkDirty', function()
    local a = signal(false)
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        b()
        return 0
    end)
    local d = computed(function()
        c()
        return b()
    end)

    local triggers = 0

    effect(function()
        d()
        triggers = triggers + 1
    end)

    expect(triggers):toBe(1)
    a(true)
    expect(triggers):toBe(2)
end)

testPrintStats()
