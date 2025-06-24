---@namespace Luakit

---@class BenchFramework

local BenchFramework = {}
BenchFramework.__index = BenchFramework

---@class BenchmarkState
---@field args table<string, any>
local BenchmarkState = {}
BenchmarkState.__index = BenchmarkState

---@class Benchmark
---@field name string
---@field fn function
---@field argValues table<string, any[]>
---@field argOrder string[]
---@field state BenchmarkState
local Benchmark = {}
Benchmark.__index = Benchmark

-- Global state
local benchmarks = {} ---@type Benchmark[]
local currentScope = nil ---@type string?

---Create a new benchmark state
---@param args table<string, any>
---@return BenchmarkState
local function createState(args)
    local state = setmetatable({
        args = args or {}
    }, BenchmarkState)
    return state
end

---Get argument value from state
---@param key string
---@return any
function BenchmarkState:get(key)
    return self.args[key]
end

---Create a new benchmark
---@param name string
---@param fn function
---@return Benchmark
local function createBenchmark(name, fn)
    local benchmark = setmetatable({
        name = name,
        fn = fn,
        argValues = {},
        argOrder = {},
        ---@diagnostic disable-next-line: missing-parameter
        state = createState()
    }, Benchmark)
    return benchmark
end

---Add arguments to benchmark
---@param key string
---@param values any[]
---@return Benchmark
function Benchmark:args(key, values)
    -- Keep track of argument order before setting values
    if not self.argValues[key] then
        table.insert(self.argOrder, key)
    end
    self.argValues[key] = values
    return self
end

---Generate all argument combinations
---@return table[]
function Benchmark:generateArgCombinations()
    local combinations = {}
    local keys = {}
    local values = {}

    -- Use the original order of argument definition
    for _, key in ipairs(self.argOrder) do
        table.insert(keys, key)
        table.insert(values, self.argValues[key])
    end

    if #keys == 0 then
        return { {} }
    end

    -- Generate combinations recursively
    local function generateCombos(index, current)
        if index > #keys then
            table.insert(combinations, current)
            return
        end

        local key = keys[index]
        local vals = values[index]

        for _, val in ipairs(vals) do
            local newCurrent = {}
            for k, v in pairs(current) do
                newCurrent[k] = v
            end
            newCurrent[key] = val
            generateCombos(index + 1, newCurrent)
        end
    end

    generateCombos(1, {})
    return combinations
end

---Run a single benchmark iteration
---@param argCombination table
---@return number, any -- time in nanoseconds, result
function Benchmark:runIteration(argCombination)
    local state = createState(argCombination)

    -- Handle generator function pattern
    local benchFn
    if type(self.fn) == "function" then
        local result = self.fn(state)
        if type(result) == "function" then
            benchFn = result
        elseif result == nil then
            -- If function returns nil, use the original function
            benchFn = self.fn
        else
            error("Benchmark function must return a function when using generator pattern")
        end
    else
        benchFn = self.fn
    end

    -- Measure execution time with higher precision
    local startTime = os.clock()
    local result
    if benchFn then
        result = benchFn()
    end
    local endTime = os.clock()

    local timeSeconds = endTime - startTime
    local timeNs = timeSeconds * 1e9 -- Convert to nanoseconds

    -- If time is too small, run multiple iterations to get measurable time
    if timeNs < 1000 then -- Less than 1 microsecond
        local iterations = 1000
        startTime = os.clock()
        for i = 1, iterations do
            if benchFn then
                result = benchFn()
            end
        end
        endTime = os.clock()
        timeNs = ((endTime - startTime) * 1e9) / iterations
    end

    return timeNs, result
end

---Format benchmark name with arguments
---@param argCombination table
---@return string
function Benchmark:formatName(argCombination)
    local name = self.name
    for key, value in pairs(argCombination) do
        name = name:gsub("%$" .. key, tostring(value))
    end
    return name
end

---Run benchmark with statistics collection
---@param argCombination table
---@return table -- statistics
function Benchmark:run(argCombination)
    local iterations = 10 -- Default iterations (reduced for testing)
    local times = {}
    local minTime = math.huge
    local maxTime = 0 ---@type number
    local totalTime = 0 ---@type number

    -- Warmup
    for i = 1, 2 do
        self:runIteration(argCombination)
    end

    -- Actual measurements
    for i = 1, iterations do
        local time = self:runIteration(argCombination)
        table.insert(times, time)
        totalTime = totalTime + time
        minTime = math.min(minTime, time)
        maxTime = math.max(maxTime, time)
    end

    local avgTime = totalTime / iterations

    -- Calculate percentiles
    table.sort(times)
    local p50 = times[math.floor(iterations * 0.5)]
    local p75 = times[math.floor(iterations * 0.75)]
    local p99 = times[math.floor(iterations * 0.99)]

    return {
        name = self:formatName(argCombination),
        iterations = iterations,
        avgTime = avgTime,
        minTime = minTime,
        maxTime = maxTime,
        p50 = p50,
        p75 = p75,
        p99 = p99,
        times = times
    }
end

---Create a benchmark
---@param name string
---@param fn fun(state: BenchmarkState): any
---@return Benchmark
function BenchFramework.bench(name, fn)
    local benchmark = createBenchmark(name, fn)
    table.insert(benchmarks, benchmark)
    return benchmark
end

---Run benchmarks in a boxplot scope
---@param fn function
function BenchFramework.boxplot(fn)
    currentScope = "boxplot"
    fn()
    currentScope = nil
end

---Format time for display with proper precision and fixed width
---@param timeNs number
---@param width number
---@return string
local function formatTime(timeNs, width)
    width = width or 11
    local value, unit
    -- Convert to appropriate unit with proper thresholds
    if timeNs >= 1000000000 then
        value = timeNs / 1000000000
        unit = "s"
    elseif timeNs >= 999999.5 then -- Use 999999.5 to handle floating point precision
        value = timeNs / 1000000
        unit = "ms"
    elseif timeNs >= 999.5 then -- Use 999.5 to handle floating point precision
        value = timeNs / 1000
        unit = "µs"
    else
        value = timeNs
        unit = "ns"
    end

    if value >= 1000 then
        if unit == "ns" then
            value = value / 1000
            unit = "µs"
        elseif unit == "µs" then
            value = value / 1000
            unit = "ms"
        elseif unit == "ms" then
            value = value / 1000
            unit = "s"
        end
    end

    local value_str = string.format("%.2f", value)
    local timeStr = string.format("%6s %s", value_str, unit)

    -- Right-align the time string within the specified width
    local formatStr = string.format("%%%ds", width)
    return string.format(formatStr, timeStr)
end

---Format time with /iter suffix for average times with fixed width
---@param timeNs number
---@param width number
---@return string
local function formatTimeWithIter(timeNs, width)
    width = width or 16
    local value, unit
    -- Convert to appropriate unit with proper thresholds
    if timeNs >= 1000000000 then
        value = timeNs / 1000000000
        unit = "s/iter"
    elseif timeNs >= 999999.5 then -- Use 999999.5 to handle floating point precision
        value = timeNs / 1000000
        unit = "ms/iter"
    elseif timeNs >= 999.5 then -- Use 999.5 to handle floating point precision
        value = timeNs / 1000
        unit = "µs/iter"
    else
        value = timeNs
        unit = "ns/iter"
    end

    -- Check if we need to convert to a higher unit (including rounding cases)
    if value >= 999.95 then -- 999.95 rounds to 1000.00
        if unit == "ns/iter" then
            value = value / 1000
            unit = "µs/iter"
        elseif unit == "µs/iter" then
            value = value / 1000
            unit = "ms/iter"
        elseif unit == "ms/iter" then
            value = value / 1000
            unit = "s/iter"
        end
    end

    -- Format with exactly 3 digits before decimal point
    local value_str = string.format("%.2f", value)
    -- 长度不够`6`位，补齐
    local timeStr = string.format("%6s %s", value_str, unit)

    -- Right-align the time string within the specified width
    local formatStr = string.format("%%%ds", width)
    return string.format(formatStr, timeStr)
end

---Format time with backticks for markdown
---@param timeNs number
---@param withIter boolean
---@param width number
---@return string
local function formatTimeMarkdown(timeNs, withIter, width)
    local timeStr = withIter and formatTimeWithIter(timeNs, width) or formatTime(timeNs, width)
    return string.format("`%s`", timeStr)
end

---Run all benchmarks
---@param options? table
function BenchFramework.run(options)
    options = options or {}
    local format = options.format or "default"

    -- Collect all results first
    local allResults = {}
    for _, benchmark in ipairs(benchmarks) do
        local combinations = benchmark:generateArgCombinations()
        for _, combination in ipairs(combinations) do
            local stats = benchmark:run(combination)
            table.insert(allResults, stats)
        end
    end

    if format == "markdown" then
        -- Print markdown table header
        print("| benchmark          |              avg |         min |         p75 |         p99 |         max |")
        print("| ------------------ | ---------------- | ----------- | ----------- | ----------- | ----------- |")

        -- Print each result
        for _, stats in ipairs(allResults) do
            print(string.format("| %-18s | %16s | %11s | %11s | %11s | %11s |",
                stats.name,
                formatTimeMarkdown(stats.avgTime, true, 14),
                formatTimeMarkdown(stats.minTime, false, 9),
                formatTimeMarkdown(stats.p75, false, 9),
                formatTimeMarkdown(stats.p99, false, 9),
                formatTimeMarkdown(stats.maxTime, false, 9)))
        end
    else
        -- Default format - similar to mitata's console output
        print(string.rep("-", 80))

        -- Calculate column widths
        local maxNameWidth = 0
        for _, stats in ipairs(allResults) do
            maxNameWidth = math.max(maxNameWidth, #stats.name)
        end
        maxNameWidth = math.max(maxNameWidth, 18) -- minimum width

        -- Print each result
        for _, stats in ipairs(allResults) do
            local nameFormat = string.format("%%-%ds", maxNameWidth)
            print(string.format(nameFormat .. " %s %s %s %s %s",
                stats.name,
                formatTimeWithIter(stats.avgTime, 16),
                formatTime(stats.minTime, 11),
                formatTime(stats.p75, 11),
                formatTime(stats.p99, 11),
                formatTime(stats.maxTime, 11)))
        end

        print(string.rep("-", 80))
    end

    -- Clear benchmarks for next run
    benchmarks = {}
end

return BenchFramework
