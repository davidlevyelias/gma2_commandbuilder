local utils = require("src.utils")

local type = type
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local table_sort = table.sort

local M = {}

---@alias DefaultHandlerFn fun(builder:CommandBuilder, args:any[], numArgs:integer):CommandBuilder

---@class DefaultHandlersOpts
---@field sortArgKeys boolean?

---@param value any
---@return string
local function asString(value)
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

---@param builder CommandBuilder
---@param arg table
local function appendArgMapUnsorted(builder, arg)
    for key, val in pairs(arg) do
        key = asString(key)
        if val == true then
            builder:_append("/" .. key)
        elseif val == false or val == nil then
            -- skip
        else
            builder:_append("/" .. key .. "=" .. asString(val))
        end
    end
end

---@param builder CommandBuilder
---@param arg table
---@param keyBuffer string[]
local function appendArgMapSorted(builder, arg, keyBuffer)
    local keys = keyBuffer
    for i = #keys, 1, -1 do
        keys[i] = nil
    end

    for k, _ in pairs(arg) do
        keys[#keys + 1] = asString(k)
    end
    table_sort(keys)

    for _, key in ipairs(keys) do
        local val = arg[key]
        if val == true then
            builder:_append("/" .. key)
        elseif val == false or val == nil then
            -- skip
        else
            builder:_append("/" .. key .. "=" .. asString(val))
        end
    end
end

---@param builder CommandBuilder
---@param arg any[]
local function appendArgArray(builder, arg)
    for j = 1, #arg do
        builder:_append("/" .. asString(arg[j]))
    end
end

---@return DefaultHandlerFn
local function makeArgHandlerUnsorted()
    local function handleArgItemUnsorted(builder, arg)
        if type(arg) ~= "table" then
            builder:_append("/" .. asString(arg))
            return
        end

        if utils.isArrayTable(arg) then
            appendArgArray(builder, arg)
            return
        end

        appendArgMapUnsorted(builder, arg)
    end

    return function(builder, args, numArgs)
        if numArgs == 0 then
            return builder
        end

        for i = 1, numArgs do
            handleArgItemUnsorted(builder, args[i])
        end

        return builder
    end
end

---@return DefaultHandlerFn
local function makeArgHandlerSorted()
    local keyBuffer = {}

    local function handleArgItemSorted(builder, arg)
        if type(arg) ~= "table" then
            builder:_append("/" .. asString(arg))
            return
        end

        if utils.isArrayTable(arg) then
            appendArgArray(builder, arg)
            return
        end

        appendArgMapSorted(builder, arg, keyBuffer)
    end

    return function(builder, args, numArgs)
        if numArgs == 0 then
            return builder
        end

        for i = 1, numArgs do
            handleArgItemSorted(builder, args[i])
        end

        return builder
    end
end

---@param key string
---@return DefaultHandlerFn
local function makeThruHandler(key)
    return function(builder, args, numArgs)
        return utils.handleThruFormat(key, args, numArgs, builder)
    end
end

---@param key string
---@return DefaultHandlerFn
local function makeOperatorHandler(key)
    return function(builder, args, numArgs)
        return utils.handleOperatorFormat(key, args, numArgs, builder)
    end
end

---@type DefaultHandlerFn
local function rawHandler(builder, args, numArgs)
    if numArgs > 0 then
        return builder:raw(args[1])
    end
    return builder
end

---@param opts DefaultHandlersOpts?
---@return table<string, DefaultHandlerFn>
function M.createDefaultHandlers(opts)
    opts = opts or {}
    local sortArgKeys = (opts.sortArgKeys == true)

    ---@type table<string, DefaultHandlerFn>
    local handlers = {}
    handlers.arg = sortArgKeys and makeArgHandlerSorted() or makeArgHandlerUnsorted()

    handlers.fade = makeThruHandler("fade")
    handlers.delay = makeThruHandler("delay")
    handlers.fixture = makeOperatorHandler("fixture")
    handlers.group = makeOperatorHandler("group")
    handlers._ = rawHandler

    return handlers
end

return M
