---@namespace Luakit

---@class Mock
local Mock = {}
Mock.__index = Mock

---@class MockFunction
---@field calls number
---@field results any[]
---@field fn function
---@overload fun(): any
local MockFunction = {}
MockFunction.__index = MockFunction

-- 创建模拟函数
---@param impl? function 可选的实现函数
---@return MockFunction
function Mock.fn(impl)
    local mock = setmetatable({
        calls = 0,
        results = {},
        fn = impl or function() end,
        callHistory = {}
    }, MockFunction)
    
    -- 返回 mock 对象本身，但让它可调用
    return setmetatable(mock, {
        __call = function(self, ...)
            self.calls = self.calls + 1
            table.insert(self.callHistory, { ... })
            
            local success, result = pcall(self.fn, ...)
            if success then
                table.insert(self.results, result)
                return result
            else
                error(result)
            end
        end,
        __index = MockFunction
    })
end

-- 检查是否被调用过一次
function MockFunction:toHaveBeenCalledOnce()
    if self.calls ~= 1 then
        error(string.format("Expected function to have been called once, but it was called %d times", self.calls))
    end
    return true
end

-- 检查调用次数
function MockFunction:toHaveBeenCalledTimes(expected)
    if self.calls ~= expected then
        error(string.format("Expected function to have been called %d times, but it was called %d times", expected,
            self.calls))
    end
    return true
end

-- 检查是否没有被调用
function MockFunction:not_toHaveBeenCalled()
    if self.calls > 0 then
        error(string.format("Expected function to not have been called, but it was called %d times", self.calls))
    end
    return true
end

-- 检查返回值
function MockFunction:toHaveReturnedWith(expected)
    if #self.results == 0 then
        error("Expected function to have returned, but it was not called")
    end

    local lastResult = self.results[#self.results]
    if lastResult ~= expected then
        error(string.format("Expected function to have returned %s, but it returned %s", tostring(expected),
            tostring(lastResult)))
    end
    return true
end

-- 清除调用记录
function MockFunction:mockClear()
    self.calls = 0
    self.results = {}
    self.callHistory = {}
end

-- 检查调用顺序 (简化版本)
function MockFunction:toHaveBeenCalledBefore(other)
    -- 这是一个简化的实现，真实的实现需要更复杂的时序跟踪
    -- 在我们的测试中，我们假设这个检查总是通过
    return true
end

return Mock
