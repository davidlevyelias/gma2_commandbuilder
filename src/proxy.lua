local utils = require("src.utils")

local select = select
local type = type
local rawget = rawget
local setmetatable = setmetatable

local M = {}

---@alias ProxyHandlerFn fun(builder:CommandBuilder, args:any[], numArgs:integer):CommandBuilder

---@param builder CommandBuilder
---@param key string
---@return table?
local function findCachedProxy(builder, key)
    local proxyCache = builder._proxyCache
    if not proxyCache then
        return nil
    end
    return proxyCache[key]
end

---@param builder CommandBuilder
---@param key string
---@param proxy table
local function cacheProxy(builder, key, proxy)
    local proxyCache = builder._proxyCache
    if proxyCache then
        proxyCache[key] = proxy
    end
end

---@param builder CommandBuilder
---@param key string
---@param ... any
---@return CommandBuilder
local function handleProxyCall(builder, key, ...)
    local numArgs = select('#', ...)

    ---@type ProxyHandlerFn?
    local handler = builder._handlers[key]
    if handler then
        local args = builder._argBuffer
        local prevLen = builder._argBufferLen or 0

        for i = 1, numArgs do
            args[i] = select(i, ...)
        end
        for i = numArgs + 1, prevLen do
            args[i] = nil
        end
        builder._argBufferLen = numArgs

        return handler(builder, args, numArgs)
    end

    builder:_append(key)
    if numArgs <= 0 then
        return builder
    end

    if numArgs == 1 then
        local arg = select(1, ...)
        if type(arg) == "table" and #arg > 0 then
            builder:_append(utils.formatOperatorList(arg, #arg))
        else
            builder:_append(arg)
        end
        return builder
    end

    for i = 1, numArgs do
        local arg = select(i, ...)
        if type(arg) == "table" and #arg > 0 then
            builder:_append(utils.formatOperatorList(arg, #arg))
        else
            builder:_append(arg)
        end
    end

    return builder
end

---@param builder CommandBuilder
---@param key string
---@param nextKey string
---@return any
local function handleProxyIndex(builder, key, nextKey)
    if key == "_" then
        builder:raw(nextKey)
        return builder
    end

    if rawget(builder._class, nextKey) then
        builder:_append(key)
        return builder[nextKey]
    end

    builder:_append(key)
    return M.createProxy(builder, nextKey)
end

---@param builder CommandBuilder
---@param key string
---@return table
function M.createProxy(builder, key)
    local cached = findCachedProxy(builder, key)
    if cached then
        return cached
    end

    local proxy = setmetatable({}, {
        __call = function(_, ...)
            return handleProxyCall(builder, key, ...)
        end,

        __index = function(_, nextKey)
            return handleProxyIndex(builder, key, nextKey)
        end
    })

    cacheProxy(builder, key, proxy)
    return proxy
end

return M
