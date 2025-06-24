-- 导入 alien-signals
local AlienSignals = require('alien-signals')

-- 导入需要的函数
local signal = AlienSignals.signal
local computed = AlienSignals.computed
local effect = AlienSignals.effect


-- 辅助函数：获取内存使用
local function getMemoryUsage()
    collectgarbage("collect")
    collectgarbage("collect")             -- 双重回收确保清理完全
    return collectgarbage("count") * 1024 -- 转换为字节
end

-- 测试开始
local initialMem = getMemoryUsage()
print(string.format("Initial memory: %.2f KB", initialMem / 1024))

-- 测试1: 创建 10000 个 signals
local start = getMemoryUsage()
local signals = {}
for i = 1, 10000 do
    signals[i] = signal(0)
end
local endMem = getMemoryUsage()
print(string.format("signal: %.2f KB", (endMem - start) / 1024))

-- 测试2: 创建 10000 个 computeds
start = getMemoryUsage()
local computeds = {}
for i = 1, 10000 do
    local idx = i -- 捕获索引避免闭包问题
    computeds[i] = computed(function()
        return signals[idx]() + 1
    end)
end
endMem = getMemoryUsage()
print(string.format("computed: %.2f KB", (endMem - start) / 1024))

-- 测试3: 创建 10000 个 effects
start = getMemoryUsage()
for i = 1, 10000 do
    local idx = i -- 捕获索引避免闭包问题
    effect(function()
        computeds[idx]()
    end)
end
endMem = getMemoryUsage()
print(string.format("effect: %.2f KB", (endMem - start) / 1024))

-- 测试4: 创建树状结构
start = getMemoryUsage()
local w = 100
local h = 100
local src = signal(1)

for i = 1, w do
    local last = src
    for j = 1, h do
        local prev = last
        last = computed(function()
            return prev() + 1
        end)
        effect(function()
            last()
        end)
    end
end

src(src() + 1)
endMem = getMemoryUsage()
print(string.format("tree: %.2f KB", (endMem - start) / 1024))

local totalMem = getMemoryUsage()
print(string.format("Total memory used: %.2f KB", (totalMem - initialMem) / 1024))
