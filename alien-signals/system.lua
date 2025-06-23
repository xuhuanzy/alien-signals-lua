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

---@type {update: (fun(sub: ReactiveNode): boolean), notify: fun(sub: ReactiveNode), unwatched: fun(sub: ReactiveNode)}
local systemConfig

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
        local linkNode = sub.deps
        while linkNode ~= nil do
            if linkNode == checkLink then
                return true
            end
            if linkNode == depsTail then
                break
            end
            linkNode = linkNode.nextDep
        end
    end
    return false
end

---@param linkNode Link
local function shallowPropagate(linkNode)
    local notify = systemConfig.notify
    while linkNode ~= nil do
        local sub = linkNode.sub
        local nextSub = linkNode.nextSub
        local subFlags = sub.flags
        if (subFlags & (ReactiveFlags.Pending | ReactiveFlags.Dirty)) == ReactiveFlags.Pending then
            sub.flags = subFlags | ReactiveFlags.Dirty
            if (subFlags & ReactiveFlags.Watching) ~= 0 then
                notify(sub)
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
    local recursedCheck = sub.flags & ReactiveFlags.RecursedCheck
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
    local unwatched = systemConfig.unwatched
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
            unwatched(dep)
        end
    end
    return nextDep
end

---@param link Link
local function propagate(link)
    local notify = systemConfig.notify
    local next = link.nextSub
    local stack = nil ---@type Stack<Link?>?

    while true do
        local sub = link.sub
        local flags = sub.flags

        if (flags & (ReactiveFlags.Mutable | ReactiveFlags.Watching)) ~= 0 then
            if (flags & (ReactiveFlags.RecursedCheck | ReactiveFlags.Recursed | ReactiveFlags.Dirty | ReactiveFlags.Pending)) == 0 then
                sub.flags = flags | ReactiveFlags.Pending
            elseif (flags & (ReactiveFlags.RecursedCheck | ReactiveFlags.Recursed)) == 0 then
                flags = ReactiveFlags.None
            elseif (flags & ReactiveFlags.RecursedCheck) == 0 then
                sub.flags = (flags & (~ReactiveFlags.Recursed)) | ReactiveFlags.Pending
            elseif (flags & (ReactiveFlags.Dirty | ReactiveFlags.Pending)) == 0 and isValidLink(link, sub) then
                sub.flags = flags | (ReactiveFlags.Recursed | ReactiveFlags.Pending)
                flags = flags & ReactiveFlags.Mutable
            else
                flags = ReactiveFlags.None
            end

            if (flags & ReactiveFlags.Watching) ~= 0 then
                notify(sub)
            end

            if (flags & ReactiveFlags.Mutable) ~= 0 then
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
    sub.flags = (sub.flags & (~(ReactiveFlags.Recursed | ReactiveFlags.Dirty | ReactiveFlags.Pending))) |
        ReactiveFlags.RecursedCheck
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
    sub.flags = sub.flags & (~ReactiveFlags.RecursedCheck)
end


---@param link Link
---@param sub ReactiveNode
---@return boolean
local function checkDirty(link, sub)
    local update = systemConfig.update

    local stack = nil ---@type Stack<Link>?
    local checkDepth = 0

    ::continue::
    while true do
        local dep = link.dep
        local depFlags = dep.flags
        local dirty = false

        if (sub.flags & ReactiveFlags.Dirty) ~= 0 then
            dirty = true
        elseif (depFlags & (ReactiveFlags.Mutable | ReactiveFlags.Dirty)) == (ReactiveFlags.Mutable | ReactiveFlags.Dirty) then
            if update(dep) then
                local subs = dep.subs
                if subs ~= nil and subs.nextSub ~= nil then
                    shallowPropagate(subs)
                end
                dirty = true
            end
        elseif (depFlags & (ReactiveFlags.Mutable | ReactiveFlags.Pending)) == (ReactiveFlags.Mutable | ReactiveFlags.Pending) then
            if link.nextSub ~= nil or link.prevSub ~= nil then
                stack = { value = link, prev = stack } ---@as Stack<Link>?
            end
            if dep.deps ~= nil then
                link = dep.deps
                sub = dep
                checkDepth = checkDepth + 1
                goto continue
            end
        end

        if not dirty and link ~= nil and link.nextDep ~= nil then
            link = link.nextDep
            goto continue
        end

        while checkDepth > 0 do
            checkDepth = checkDepth - 1
            local firstSub = sub.subs
            if firstSub == nil then
                break
            end
            local hasMultipleSubs = firstSub.nextSub ~= nil
            if hasMultipleSubs then
                if stack ~= nil then
                    link = stack.value
                    stack = stack.prev
                else
                    link = firstSub
                end
            else
                link = firstSub
            end
            if dirty then
                if update(sub) then
                    if hasMultipleSubs then
                        shallowPropagate(firstSub)
                    end
                    sub = link.sub
                    goto continue
                end
            else
                sub.flags = sub.flags & (~ReactiveFlags.Pending)
            end
            sub = link.sub
            if link.nextDep ~= nil then
                link = link.nextDep
                goto continue
            end
            dirty = false
        end

        return dirty
    end
    return false
end

---创建响应式系统
---@param config {update: (fun(sub: ReactiveNode): boolean), notify: fun(sub: ReactiveNode), unwatched: fun(sub: ReactiveNode)}
local function createReactiveSystem(config)
    local update = config.update
    local notify = config.notify
    local unwatched = config.unwatched
    if systemConfig == nil then
        systemConfig = {
            update = update,
            notify = notify,
            unwatched = unwatched,
        }
    end
    systemConfig = {
        update = update,
        notify = notify,
        unwatched = unwatched,
    }
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
