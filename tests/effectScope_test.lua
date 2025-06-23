-- EffectScope 相关测试
-- 从 TypeScript 测试代码转换而来

-- 导入测试框架和 alien-signals
local TestFramework = require('luakit.test')
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local effect = AlienSignals.effect
local effectScope = AlienSignals.effectScope

-- 使用测试框架
local test = TestFramework.test
local expect = TestFramework.expect
local testPrintStats = TestFramework.testPrintStats

-- 测试1: 停止后不应触发
test('should not trigger after stop', function()
    local count = signal(1)

    local triggers = 0
    local effect1

    local stopScope = effectScope(function()
        effect1 = effect(function()
            triggers = triggers + 1
            count()
        end)
        expect(triggers):toBe(1)

        count(2)
        expect(triggers):toBe(2)
    end)

    count(3)
    expect(triggers):toBe(3)
    stopScope()
    count(4)
    expect(triggers):toBe(3)
end)

-- 测试2: 如果在 effect 中创建，应处理内部 effects
test('should dispose inner effects if created in an effect', function()
    local source = signal(1)

    local triggers = 0

    effect(function()
        local dispose = effectScope(function()
            effect(function()
                source()
                triggers = triggers + 1
            end)
        end)

        -- effectScope 内的 effect 应该已经执行了一次
        expect(triggers):toBe(1)

        source(2)
        expect(triggers):toBe(2)
        dispose()
        source(3)
        expect(triggers):toBe(2)
    end)
end)

-- 运行所有测试
testPrintStats()
