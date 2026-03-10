---@diagnostic disable: undefined-field
local builderModule = require("src.builder")
local handlersModule = require("src.handlers")
local proxyModule = require("src.proxy")

local type = type
local tostring = tostring
local select = select
local rawget = rawget
local string_format = string.format
local setmetatable = setmetatable
local math_floor = math.floor

local newBuilder = builderModule.newBuilder

local M = {}

local VERSION = "2.0.0"
M.VERSION = VERSION
M._VERSION = VERSION

---@class CmdBuilderApi
---@field build fun(opts?:any):string
---@field execute fun(opts?:any):any
---@field raw fun(str:any):CmdBuilderApi
---@field chain fun(str?:any):CmdBuilderApi

---@class CmdToken
---@field value any
---@field __cmd_op string
---@field __cmd_value any

---@class CmdModule
---@field chain fun(...:any):any
---@field thru table
---@field minus table
---@field plus table
---@field register fun(self:CmdModule, key:string, handler:function, opts?:CmdRegisterOpts):boolean, string?
---@field unregister fun(self:CmdModule, key:string):boolean
---@field [string] any

---@class CmdModuleNewOpts
---@field execute? fun(command:string):any
---@field sortArgKeys boolean?
---@field builderPoolSize integer?

---@class CmdRegisterOpts
---@field override boolean?

local function makeTokenFactory(prefix, op)
    return setmetatable({}, {
        __call = function(_, value)
            local token = {
                value = value,
                __cmd_op = op,
                __cmd_value = value
            }
            return setmetatable(token, {
                __tostring = function(self)
                    return prefix .. tostring(self.value)
                end
            })
        end,
        __index = function(_, value)
            local token = {
                value = value,
                __cmd_op = op,
                __cmd_value = value
            }
            return setmetatable(token, {
                __tostring = function(self)
                    return prefix .. tostring(self.value)
                end
            })
        end
    })
end

local function make_chain(acquireBuilder)
    return function(...)
        local items = { ... }
        local chainBuilder = acquireBuilder()

        local added = false
        for i = 1, #items do
            local item = items[i]
            if item ~= nil then
                local text = tostring(item)
                if not added then
                    chainBuilder:raw(text)
                    added = true
                else
                    chainBuilder:chain(text)
                end
            end
        end

        return chainBuilder
    end
end

local function make_register(handlers)
    ---Register or replace a special handler for this CMD instance.
    ---By default, existing handlers are NOT overridden unless opts.override == true.
    ---@param _ table
    ---@param key string
    ---@param handler fun(builder:table, args:any[], numArgs:number):table
    ---@param opts CmdRegisterOpts?
    ---@return boolean ok
    ---@return string? reason
    return function(_, key, handler, opts)
        if type(key) ~= "string" or key == "" then
            return false, "invalid-key"
        end
        if type(handler) ~= "function" then
            return false, "invalid-handler"
        end

        local override = false
        if type(opts) == "table" and opts.override == true then
            override = true
        end

        if handlers[key] ~= nil and not override then
            return false, "exists"
        end

        handlers[key] = handler
        return true
    end
end

local function make_unregister(handlers)
    ---Remove a special handler from this CMD instance.
    ---@param _ table
    ---@param key string
    ---@return boolean removed
    return function(_, key)
        if type(key) ~= "string" or key == "" then
            return false
        end
        if handlers[key] == nil then
            return false
        end
        handlers[key] = nil
        return true
    end
end

local function make_cmd_index(acquireBuilder)
    return function(self, key)
        local direct = rawget(self, key)
        if direct ~= nil then
            return direct
        end
        return proxyModule.createProxy(acquireBuilder(), key)
    end
end

local function make_cmd_call(executeFn)
    return function(_, commandString, ...)
        if select('#', ...) > 0 then
            commandString = string_format(commandString, ...)
        end
        return executeFn(commandString)
    end
end

local function createBuilderPool(executeFn, handlers, builderPoolSize)
    local poolLimit = tonumber(builderPoolSize)
    if poolLimit == nil then
        poolLimit = 8
    end
    if poolLimit < 0 then
        poolLimit = 0
    end
    poolLimit = math_floor(poolLimit)

    if poolLimit <= 0 then
        return function()
            return newBuilder(executeFn, handlers, nil)
        end
    end

    local pool = {}

    local function releaseBuilder(builder)
        if builder._inPool then
            return
        end
        if #pool >= poolLimit then
            return
        end

        builder._inPool = true
        pool[#pool + 1] = builder
    end

    return function()
        local idx = #pool
        if idx > 0 then
            local builder = pool[idx]
            pool[idx] = nil
            builder:_setContext(executeFn, handlers, releaseBuilder)
            return builder
        end

        return newBuilder(executeFn, handlers, releaseBuilder)
    end
end

---@param opts CmdModuleNewOpts?
---@return CmdModule
function M.new(opts)
    opts = opts or {}

    local executeFn = opts.execute
    if type(executeFn) ~= "function" then
        if _G.gma and type(_G.gma.cmd) == "function" then
            executeFn = function(command)
                return _G.gma.cmd(command)
            end
        else
            executeFn = function(command)
                return command
            end
        end
    end

    local handlers = handlersModule.createDefaultHandlers({
        sortArgKeys = (opts.sortArgKeys == true)
    })

    local acquireBuilder = createBuilderPool(executeFn, handlers, opts.builderPoolSize)

    local CMD = {
        chain = make_chain(acquireBuilder),
        thru = makeTokenFactory("thru ", "thru"),
        minus = makeTokenFactory("-", "minus"),
        plus = makeTokenFactory("+", "plus"),
        register = make_register(handlers),
        unregister = make_unregister(handlers)
    }

    return setmetatable(CMD, {
        __index = make_cmd_index(acquireBuilder),
        __call = make_cmd_call(executeFn)
    })
end

return M
