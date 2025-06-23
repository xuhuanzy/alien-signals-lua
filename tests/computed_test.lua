-- Computed 相关测试
-- 从 TypeScript 测试代码转换而来

-- 导入测试框架和 alien-signals
local TestFramework = require('luakit.test')
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed

-- 使用测试框架
local test = TestFramework.test
local expect = TestFramework.expect
local testPrintStats = TestFramework.testPrintStats

-- 测试1: 应该正确地通过计算信号传播变化
test('should correctly propagate changes through computed signals', function()
    local src = signal(0)
    local c1 = computed(function()
        return src() % 2
    end)
    local c2 = computed(function()
        return c1()
    end)
    local c3 = computed(function()
        return c2()
    end)

    c3()
    src(1) -- c1 -> dirty, c2 -> toCheckDirty, c3 -> toCheckDirty
    c2()   -- c1 -> none, c2 -> none
    src(3) -- c1 -> dirty, c2 -> toCheckDirty

    expect(c3()):toBe(1)
end)

-- 测试2: 应该通过链式计算传播更新的源值
test('should propagate updated source value through chained computations', function()
    local src = signal(0)
    local a = computed(function()
        return src()
    end)
    local b = computed(function()
        return a() % 2
    end)
    local c = computed(function()
        return src()
    end)
    local d = computed(function()
        return b() + c()
    end)

    expect(d()):toBe(0)
    src(2)
    expect(d()):toBe(2)
end)

-- 测试3: 应处理在 checkDirty 期间间接更新的标志
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

    expect(d()):toBe(false)
    a(true)
    expect(d()):toBe(true)
end)

-- 测试4: 如果信号值被还原，则不应更新
test('should not update if the signal value is reverted', function()
    local times = 0

    local src = signal(0)
    local c1 = computed(function()
        times = times + 1
        return src()
    end)

    c1()
    expect(times):toBe(1)
    src(1)
    src(0)
    c1()
    expect(times):toBe(1)
end)

testPrintStats()
