-- 图更新相关测试
-- 从 TypeScript 测试代码转换而来
-- 测试来自 preact-signals 实现

-- 导入测试框架和 alien-signals
local TestFramework = require('luakit.test')
local AlienSignals = require('alien-signals')
local Mock = require('luakit.mock')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed
local effect = AlienSignals.effect

-- 使用测试框架
local test = TestFramework.test
local expect = TestFramework.expect
local testPrintStats = TestFramework.testPrintStats

-- 模拟 vi.fn
local vi = Mock

-- 图更新测试
print("=== 图更新测试 ===")

test('should drop A->B->A updates', function()
    --     A
    --   / |
    --  B  | <- Looks like a flag doesn't it? :D
    --   \ |
    --     C
    --     |
    --     D
    local a = signal(2)

    local b = computed(function()
        return a() - 1
    end)
    local c = computed(function()
        return a() + b()
    end)

    local compute = vi.fn(function()
        return "d: " .. c()
    end)
    ---@diagnostic disable-next-line: param-type-not-match
    local d = computed(compute)

    -- Trigger read
    expect(d()):toBe("d: 3")
    compute:toHaveBeenCalledOnce()
    compute:mockClear()

    a(4)
    d()
    compute:toHaveBeenCalledOnce()
end)

test('should only update every signal once (diamond graph)', function()
    -- In this scenario "D" should only update once when "A" receives
    -- an update. This is sometimes referred to as the "diamond" scenario.
    --     A
    --   /   \
    --  B     C
    --   \   /
    --     D

    local a = signal("a")
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        return a()
    end)

    local spy = vi.fn(function()
        return b() .. " " .. c()
    end)
    local d = computed(spy)

    expect(d()):toBe("a a")
    spy:toHaveBeenCalledOnce()

    a("aa")
    expect(d()):toBe("aa aa")
    spy:toHaveBeenCalledTimes(2)
end)

test('should only update every signal once (diamond graph + tail)', function()
    -- "E" will be likely updated twice if our mark+sweep logic is buggy.
    --     A
    --   /   \
    --  B     C
    --   \   /
    --     D
    --     |
    --     E

    local a = signal("a")
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        return a()
    end)

    local d = computed(function()
        return b() .. " " .. c()
    end)

    local spy = vi.fn(function()
        return d()
    end)
    local e = computed(spy)

    expect(e()):toBe("a a")
    spy:toHaveBeenCalledOnce()

    a("aa")
    expect(e()):toBe("aa aa")
    spy:toHaveBeenCalledTimes(2)
end)

test('should bail out if result is the same', function()
    -- Bail out if value of "B" never changes
    -- A->B->C
    local a = signal("a")
    local b = computed(function()
        a()
        return "foo"
    end)

    local spy = vi.fn(function()
        return b()
    end)
    local c = computed(spy)

    expect(c()):toBe("foo")
    spy:toHaveBeenCalledOnce()

    a("aa")
    expect(c()):toBe("foo")
    spy:toHaveBeenCalledOnce()
end)

test('should only update every signal once (jagged diamond graph + tails)', function()
    -- "F" and "G" will be likely updated twice if our mark+sweep logic is buggy.
    --     A
    --   /   \
    --  B     C
    --  |     |
    --  |     D
    --   \   /
    --     E
    --   /   \
    --  F     G
    local a = signal("a")

    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        return a()
    end)

    local d = computed(function()
        return c()
    end)

    local eSpy = vi.fn(function()
        return b() .. " " .. d()
    end)
    local e = computed(eSpy)

    local fSpy = vi.fn(function()
        return e()
    end)
    local f = computed(fSpy)
    local gSpy = vi.fn(function()
        return e()
    end)
    local g = computed(gSpy)

    expect(f()):toBe("a a")
    fSpy:toHaveBeenCalledTimes(1)

    expect(g()):toBe("a a")
    gSpy:toHaveBeenCalledTimes(1)

    eSpy:mockClear()
    fSpy:mockClear()
    gSpy:mockClear()

    a("b")

    expect(e()):toBe("b b")
    eSpy:toHaveBeenCalledTimes(1)

    expect(f()):toBe("b b")
    fSpy:toHaveBeenCalledTimes(1)

    expect(g()):toBe("b b")
    gSpy:toHaveBeenCalledTimes(1)

    eSpy:mockClear()
    fSpy:mockClear()
    gSpy:mockClear()

    a("c")

    expect(e()):toBe("c c")
    eSpy:toHaveBeenCalledTimes(1)

    expect(f()):toBe("c c")
    fSpy:toHaveBeenCalledTimes(1)

    expect(g()):toBe("c c")
    gSpy:toHaveBeenCalledTimes(1)

    -- top to bottom
    eSpy:toHaveBeenCalledBefore(fSpy)
    -- left to right
    fSpy:toHaveBeenCalledBefore(gSpy)
end)

test('should only subscribe to signals listened to', function()
    --    *A
    --   /   \
    -- *B     C <- we don't listen to C
    local a = signal("a")

    local b = computed(function()
        return a()
    end)
    local spy = vi.fn(function()
        return a()
    end)
    computed(spy)

    expect(b()):toBe("a")
    expect(spy):not_():toHaveBeenCalled()

    a("aa")
    expect(b()):toBe("aa")
    expect(spy):not_():toHaveBeenCalled()
end)

test('should only subscribe to signals listened to II', function()
    -- Here both "B" and "C" are active in the beginning, but
    -- "B" becomes inactive later. At that point it should
    -- not receive any updates anymore.
    --    *A
    --   /   \
    -- *B     D <- we don't listen to C
    --  |
    -- *C
    local a = signal("a")
    local spyB = vi.fn(function()
        return a()
    end)
    local b = computed(spyB)

    local spyC = vi.fn(function()
        return b()
    end)
    local c = computed(spyC)

    local d = computed(function()
        return a()
    end)

    local result = ""
    local unsub = effect(function()
        result = c()
    end)

    expect(result):toBe("a")
    expect(d()):toBe("a")

    spyB:mockClear()
    spyC:mockClear()
    unsub()

    a("aa")

    expect(spyB):not_():toHaveBeenCalled()
    expect(spyC):not_():toHaveBeenCalled()
    expect(d()):toBe("aa")
end)

test('should ensure subs update even if one dep unmarks it', function()
    -- In this scenario "C" always returns the same value. When "A"
    -- changes, "B" will update, then "C" at which point its update
    -- to "D" will be unmarked. But "D" must still update because
    -- "B" marked it. If "D" isn't updated, then we have a bug.
    --     A
    --   /   \
    --  B     *C <- returns same value every time
    --   \   /
    --     D
    local a = signal("a")
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        a()
        return "c"
    end)
    local spy = vi.fn(function()
        return b() .. " " .. c()
    end)
    local d = computed(spy)

    expect(d()):toBe("a c")
    spy:mockClear()

    a("aa")
    d()
    spy:toHaveReturnedWith("aa c")
end)

test('should ensure subs update even if two deps unmark it', function()
    -- In this scenario both "C" and "D" always return the same
    -- value. But "E" must still update because "A" marked it.
    -- If "E" isn't updated, then we have a bug.
    --     A
    --   / | \
    --  B *C *D
    --   \ | /
    --     E
    local a = signal("a")
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        a()
        return "c"
    end)
    local d = computed(function()
        a()
        return "d"
    end)
    local spy = vi.fn(function()
        return b() .. " " .. c() .. " " .. d()
    end)
    local e = computed(spy)

    expect(e()):toBe("a c d")
    spy:mockClear()

    a("aa")
    e()
    spy:toHaveReturnedWith("aa c d")
end)

test('should support lazy branches', function()
    local a = signal(0)
    local b = computed(function()
        return a()
    end)
    local c = computed(function()
        return (a() > 0) and a() or b()
    end)

    expect(c()):toBe(0)
    a(1)
    expect(c()):toBe(1)

    a(0)
    expect(c()):toBe(0)
end)

test('should not update a sub if all deps unmark it', function()
    -- In this scenario "B" and "C" always return the same value. When "A"
    -- changes, "D" should not update.
    --     A
    --   /   \
    -- *B     *C
    --   \   /
    --     D
    local a = signal("a")
    local b = computed(function()
        a()
        return "b"
    end)
    local c = computed(function()
        a()
        return "c"
    end)
    local spy = vi.fn(function()
        return b() .. " " .. c()
    end)
    local d = computed(spy)

    expect(d()):toBe("b c")
    spy:mockClear()

    a("aa")
    expect(spy):not_():toHaveBeenCalled()
end)

-- 错误处理测试
print("\n=== 错误处理测试 ===")

test('should keep graph consistent on errors during activation', function()
    local a = signal(0)
    local b = computed(function()
        error("fail")
    end)
    local c = computed(function()
        return a()
    end)

    expect(b):toThrow("fail")

    a(1)
    expect(c()):toBe(1)
end)

test('should keep graph consistent on errors in computeds', function()
    local a = signal(0)
    local b = computed(function()
        if a() == 1 then
            error("fail")
        end
        return a()
    end)
    local c = computed(function()
        return b()
    end)

    expect(c()):toBe(0)

    a(1)
    expect(b):toThrow("fail")

    a(2)
    expect(c()):toBe(2)
end)

-- 运行所有测试
testPrintStats()
