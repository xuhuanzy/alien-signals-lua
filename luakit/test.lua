---@namespace Luakit

---简单的 Lua 测试库
---@class TestFramework

local TestFramework = {}
TestFramework.__index = TestFramework

---@class ExpectObject
---@field value any
local ExpectObject = {}
ExpectObject.__index = ExpectObject

-- 测试统计
local stats = {
    total = 0,
    passed = 0,
    failed = 0,
    tests = {}
}

---创建期望对象
---@param value any
---@return ExpectObject
function TestFramework.expect(value)
    local obj = setmetatable({
        value = value
    }, ExpectObject)
    return obj
end

---检查值是否相等
---@param expected any
---@return boolean
function ExpectObject:toBe(expected)
    if self.value == expected then
        return true
    else
        error(string.format("Expected %s to be %s", tostring(self.value), tostring(expected)))
    end
end

---检查值是否不相等
---@param expected any
---@return boolean
function ExpectObject:notToBe(expected)
    if self.value ~= expected then
        return true
    else
        error(string.format("Expected %s not to be %s", tostring(self.value), tostring(expected)))
    end
end

---深度比较两个值
---@param a any
---@param b any
---@return boolean
local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= "table" then
        return a == b
    end

    -- 比较数组长度
    local lenA, lenB = #a, #b
    if lenA ~= lenB then
        return false
    end

    -- 比较数组元素
    for i = 1, lenA do
        if not deepEqual(a[i], b[i]) then
            return false
        end
    end

    -- 比较表的键值对
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then
            return false
        end
    end

    for k, v in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end

---检查值是否深度相等(用于数组和对象比较)
---@param expected any
---@return boolean
function ExpectObject:toEqual(expected)
    if deepEqual(self.value, expected) then
        return true
    else
        error(string.format("Expected %s to equal %s", tostring(self.value), tostring(expected)))
    end
end

---检查函数是否抛出错误
---@param expectedMessage? string 可选的错误消息
---@return boolean
function ExpectObject:toThrow(expectedMessage)
    if type(self.value) ~= "function" then
        error("Expected value to be a function")
    end

    local success, err = pcall(self.value)
    if success then
        error("Expected function to throw an error, but it didn't")
    end

    if expectedMessage and not string.find(tostring(err), expectedMessage, 1, true) then
        error(string.format("Expected function to throw error containing '%s', but got '%s'", expectedMessage,
            tostring(err)))
    end

    return true
end

---获取 not 版本的 expectObject
---@return table
function ExpectObject:not_()
    local notObj = {}
    setmetatable(notObj, {
        __index = function(_, key)
            if key == "toHaveBeenCalled" then
                return function()
                    if self.value.calls and self.value.calls > 0 then
                        error(string.format("Expected function to not have been called, but it was called %d times",
                            self.value.calls))
                    end
                    return true
                end
            end
            -- 可以添加更多 not 版本的断言
            return function()
                error("Not implemented: not." .. key)
            end
        end
    })
    ---@diagnostic disable-next-line: return-type-mismatch
    return notObj
end

---运行测试用例
---@param name string 测试名称
---@param testFn function 测试函数
function TestFramework.test(name, testFn)
    stats.total = stats.total + 1

    print(string.format("Running test: %s", name))

    local success, err = pcall(testFn)

    if success then
        stats.passed = stats.passed + 1
        print(string.format("✓ %s", name))
    else
        stats.failed = stats.failed + 1
        print(string.format("✗ %s", name))
        print(string.format("  Error: %s", tostring(err)))
    end

    table.insert(stats.tests, {
        name = name,
        success = success,
        error = err
    })
end

---显示测试结果
function TestFramework.testPrintStats()
    print("\n" .. string.rep("=", 50))
    print("测试结果统计:")
    print(string.format("总计: %d", stats.total))
    print(string.format("通过: %d", stats.passed))
    print(string.format("失败: %d", stats.failed))

    if stats.failed > 0 then
        print("\n失败的测试:")
        for _, test in ipairs(stats.tests) do
            if not test.success then
                print(string.format("  - %s: %s", test.name, test.error))
            end
        end
    end

    print(string.rep("=", 50))

    -- 重置统计
    stats.total = 0
    stats.passed = 0
    stats.failed = 0
    stats.tests = {}
end

return TestFramework
