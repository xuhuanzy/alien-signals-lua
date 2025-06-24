local BenchFramework = require('luakit.bench')
local AlienSignals = require('alien-signals')

local run = BenchFramework.run
local bench = BenchFramework.bench
local boxplot = BenchFramework.boxplot

local computed = AlienSignals.computed
local effect = AlienSignals.effect
local signal = AlienSignals.signal

boxplot(function()
    bench('complex: $w * $h', function(state)
        local w = state:get('w')
        local h = state:get('h')
        local src = signal({ w = w, h = h })

        for i = 0, w - 1 do
            local last = src
            for j = 0, h - 1 do
                local prev = last
                last = computed(function()
                    local prevValue = prev()
                    local result = {}
                    result[string.format("%d-%d", i, j)] = prevValue
                    return result
                end)
            end
            effect(function()
                last()
            end)
        end

        return function()
            local currentValue = src()
            src({ upstream = currentValue })
        end
    end)
        :args('w', { 1, 10, 100 })
        :args('h', { 1, 10, 100 })
end)

run({ format = 'markdown' })
