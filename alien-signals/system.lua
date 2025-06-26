---@namespace AlienSignals

---@class ReactiveNode
---@field deps? Link
---@field depsTail? Link
---@field subs? Link
---@field subsTail? Link
---@field flags ReactiveFlags

---@class Link
---@field dep ReactiveNode
---@field sub ReactiveNode
---@field prevSub? Link
---@field nextSub? Link
---@field prevDep? Link
---@field nextDep? Link

---@class Stack<T>
---@field value T
---@field prev Stack<T>?


---@type fun(sub: ReactiveNode): boolean
local SystemUpdate

---@type fun(sub: ReactiveNode)
local SystemNotify

---@type fun(sub: ReactiveNode)
local SystemUnwatched

---@enum ReactiveFlags
local ReactiveFlags = {
    None = 0,
    Mutable = 1 << 0,       -- 1
    Watching = 1 << 1,      -- 2
    RecursedCheck = 1 << 2, -- 4
    Recursed = 1 << 3,      -- 8
    Dirty = 1 << 4,         -- 16
    Pending = 1 << 5,       -- 32
}

---@param checkLink Link
---@param sub ReactiveNode
---@return boolean
local function isValidLink(checkLink, sub)
    local depsTail = sub.depsTail
    if depsTail ~= nil then
        ---@cast sub.deps -?
        local linkNode = sub.deps
        repeat
            if linkNode == checkLink then
                return true
            end
            if linkNode == depsTail then
                break
            end
            ---@cast linkNode.nextDep -?
            linkNode = linkNode.nextDep
        until (linkNode == nil)
    end
    return false
end

---@param linkNode Link
local function shallowPropagate(linkNode)
    while linkNode ~= nil do
        local sub = linkNode.sub
        local nextSub = linkNode.nextSub
        local subFlags = sub.flags
        if (subFlags & 48) == 32 then   -- (ReactiveFlags.Pending | ReactiveFlags.Dirty) == ReactiveFlags.Pending
            sub.flags = subFlags | 16   -- ReactiveFlags.Dirty
            if (subFlags & 2) ~= 0 then -- ReactiveFlags.Watching
                SystemNotify(sub)
            end
        end
        ---@cast nextSub -?
        linkNode = nextSub
    end
end


---@param dep ReactiveNode
---@param sub ReactiveNode
local function link(dep, sub)
    local prevDep = sub.depsTail
    if prevDep ~= nil and prevDep.dep == dep then
        return
    end

    local nextDep = nil
    local recursedCheck = sub.flags & 4 -- ReactiveFlags.RecursedCheck
    if recursedCheck ~= 0 then
        if prevDep ~= nil then
            nextDep = prevDep.nextDep
        else
            nextDep = sub.deps
        end
        if nextDep ~= nil and nextDep.dep == dep then
            sub.depsTail = nextDep
            return
        end
    end

    local prevSub = dep.subsTail
    if prevSub ~= nil and prevSub.sub == sub and (recursedCheck == 0 or isValidLink(prevSub, sub)) then
        return
    end

    ---@type Link
    local newLink = {
        dep = dep,
        sub = sub,
        prevDep = prevDep,
        nextDep = nextDep,
        prevSub = prevSub,
        nextSub = nil,
    }

    sub.depsTail = newLink
    dep.subsTail = newLink

    if nextDep ~= nil then
        nextDep.prevDep = newLink
    end
    if prevDep ~= nil then
        prevDep.nextDep = newLink
    else
        sub.deps = newLink
    end
    if prevSub ~= nil then
        prevSub.nextSub = newLink
    else
        dep.subs = newLink
    end
end

---@param link Link
---@param sub? ReactiveNode
---@return Link?
local function unlink(link, sub)
    sub = sub or link.sub
    local dep = link.dep
    local prevDep = link.prevDep
    local nextDep = link.nextDep
    local nextSub = link.nextSub
    local prevSub = link.prevSub

    if nextDep ~= nil then
        nextDep.prevDep = prevDep
    else
        sub.depsTail = prevDep
    end
    if prevDep ~= nil then
        prevDep.nextDep = nextDep
    else
        sub.deps = nextDep
    end
    if nextSub ~= nil then
        nextSub.prevSub = prevSub
    else
        dep.subsTail = prevSub
    end
    if prevSub ~= nil then
        prevSub.nextSub = nextSub
    else
        dep.subs = nextSub
        if dep.subs == nil then
            SystemUnwatched(dep)
        end
    end
    return nextDep
end

---@param link Link
local function propagate(link)
    local next = link.nextSub
    local stack = nil ---@type Stack<Link?>?

    while true do
        local sub = link.sub
        local flags = sub.flags

        if (flags & 3) ~= 0 then                                     -- (ReactiveFlags.Mutable | ReactiveFlags.Watching)
            if (flags & 60) == 0 then                                -- (ReactiveFlags.RecursedCheck | ReactiveFlags.Recursed | ReactiveFlags.Dirty | ReactiveFlags.Pending)
                sub.flags = flags | 32                               -- ReactiveFlags.Pending
            elseif (flags & 12) == 0 then                            -- (ReactiveFlags.RecursedCheck | ReactiveFlags.Recursed)
                flags = 0                                            -- ReactiveFlags.None
            elseif (flags & 4) == 0 then                             -- ReactiveFlags.RecursedCheck
                sub.flags = (flags & (~8)) | 32                      -- (~ReactiveFlags.Recursed) | ReactiveFlags.Pending
            elseif (flags & 48) == 0 and isValidLink(link, sub) then -- (ReactiveFlags.Dirty | ReactiveFlags.Pending)
                sub.flags = flags | 40                               -- (ReactiveFlags.Recursed | ReactiveFlags.Pending)
                flags = flags & 1                                    -- ReactiveFlags.Mutable
            else
                flags = 0                                            -- ReactiveFlags.None
            end

            if (flags & 2) ~= 0 then -- ReactiveFlags.Watching
                SystemNotify(sub)
            end

            if (flags & 1) ~= 0 then -- ReactiveFlags.Mutable
                local subSubs = sub.subs
                if subSubs ~= nil then
                    link = subSubs
                    if subSubs.nextSub ~= nil then
                        stack = { value = next, prev = stack } ---@as Stack<Link>?
                        next = link.nextSub
                    end
                    goto continue
                end
            end
        end

        if next ~= nil then
            link = next
            next = link.nextSub
            goto continue
        end

        while stack ~= nil do
            ---@cast stack.value -?
            link = stack.value
            stack = stack.prev
            if link ~= nil then
                next = link.nextSub
                goto continue
            end
        end

        break
        ::continue::
    end
end

---@param sub ReactiveNode
local function startTracking(sub)
    sub.depsTail = nil
    sub.flags = (sub.flags & (~56)) | -- (~(ReactiveFlags.Recursed | ReactiveFlags.Dirty | ReactiveFlags.Pending))
        4                             -- ReactiveFlags.RecursedCheck
end

---@param sub ReactiveNode
local function endTracking(sub)
    local depsTail = sub.depsTail
    local toRemove
    if depsTail ~= nil then
        toRemove = depsTail.nextDep
    else
        toRemove = sub.deps
    end
    while toRemove ~= nil do
        toRemove = unlink(toRemove, sub)
    end
    sub.flags = sub.flags & (~4) -- (~ReactiveFlags.RecursedCheck)
end


---@param link Link
---@param sub ReactiveNode
---@return boolean
local function checkDirty(link, sub)
    local stack = nil ---@type Stack<Link>?
    local checkDepth = 0

    while true do
        ::top::
        local dep = link.dep
        local depFlags = dep.flags
        local dirty = false

        if (sub.flags & 16) ~= 0 then     -- ReactiveFlags.Dirty
            dirty = true
        elseif (depFlags & 17) == 17 then -- (ReactiveFlags.Mutable | ReactiveFlags.Dirty)
            if SystemUpdate(dep) then
                local subs = dep.subs ---@cast subs -?
                if subs.nextSub ~= nil then
                    shallowPropagate(subs)
                end
                dirty = true
            end
        elseif (depFlags & 33) == 33 then -- (ReactiveFlags.Mutable | ReactiveFlags.Pending)
            if link.nextSub ~= nil or link.prevSub ~= nil then
                stack = { value = link, prev = stack } ---@as Stack<Link>?
            end
            ---@cast dep.deps -?
            link = dep.deps
            sub = dep
            checkDepth = checkDepth + 1
            goto top
        end

        if not dirty and link ~= nil and link.nextDep ~= nil then
            link = link.nextDep
            goto top
        end


        while checkDepth > 0 do
            checkDepth = checkDepth - 1
            ---@cast sub.subs -?
            local firstSub = sub.subs
            local hasMultipleSubs = firstSub.nextSub ~= nil
            if hasMultipleSubs then
                ---@cast stack -?
                link = stack.value
                stack = stack.prev
            else
                link = firstSub
            end
            if dirty then
                if SystemUpdate(sub) then
                    if hasMultipleSubs then
                        shallowPropagate(firstSub)
                    end
                    sub = link.sub
                    goto continue_depth
                end
            else
                sub.flags = sub.flags & (~32) -- (~ReactiveFlags.Pending)
            end
            sub = link.sub
            if link.nextDep ~= nil then
                link = link.nextDep
                goto top
            end
            dirty = false
            ::continue_depth::
        end

        return dirty
    end
    return false
end

---创建响应式系统
---@param config {update: (fun(sub: ReactiveNode): boolean), notify: fun(sub: ReactiveNode), unwatched: fun(sub: ReactiveNode)}
local function createReactiveSystem(config)
    SystemUpdate = config.update
    SystemNotify = config.notify
    SystemUnwatched = config.unwatched
end

return {
    ReactiveFlags = ReactiveFlags,
    createReactiveSystem = createReactiveSystem,
    link = link,
    unlink = unlink,
    propagate = propagate,
    checkDirty = checkDirty,
    endTracking = endTracking,
    startTracking = startTracking,
    shallowPropagate = shallowPropagate,
}
