local proxy = require("src.proxy")

local tostring = tostring
local type = type
local select = select
local rawget = rawget
local setmetatable = setmetatable
local table_concat = table.concat

---@class CommandBuilder
---@field _parts string[]
---@field _execute fun(command:string):any
---@field _proxyCache table<string, table>
---@field _boundMethods table<string, function>
---@field _handlers table<string, function>
---@field _class table
---@field _cachedCmd string
---@field _cachedSeparator string
---@field _dirty boolean
---@field _argBuffer any[]
---@field _argBufferLen integer
---@field _releaseHook fun(builder:CommandBuilder)|false
---@field _inPool boolean
local CommandBuilder = {}
CommandBuilder.__index = CommandBuilder

---@param self CommandBuilder
---@param separator string
---@return string
local function getCommandString(self, separator)
    if not self._dirty and self._cachedSeparator == separator then
        return self._cachedCmd
    end

    local cmd = table_concat(self._parts, separator)
    self._cachedCmd = cmd
    self._cachedSeparator = separator
    self._dirty = false
    return cmd
end

---@param opts any
---@return string separator
---@return boolean reset
local function normalizeBuildOptions(opts)
    local reset = true
    local separator = opts
    if type(opts) == "table" then
        reset = (opts.reset ~= false)
        separator = opts.separator
    end

    if type(separator) ~= "string" and separator ~= nil then
        separator = " "
    end

    return separator or " ", reset
end

---@param self CommandBuilder
---@param method function
---@return function
local function makeBoundMethod(self, method)
    return function(...)
        if select('#', ...) >= 1 and select(1, ...) == self then
            return method(self, select(2, ...))
        end
        return method(self, ...)
    end
end

---@param builder CommandBuilder
local function clearArgBuffer(builder)
    local prevLen = builder._argBufferLen or 0
    local argBuffer = builder._argBuffer
    for i = 1, prevLen do
        argBuffer[i] = nil
    end
    builder._argBufferLen = 0
end

---@param executeFn fun(command:string):any
---@param handlers table<string, function>
---@param releaseHook fun(builder:CommandBuilder)|false?
---@return CommandBuilder
local function newBuilder(executeFn, handlers, releaseHook)
    local self = setmetatable({}, CommandBuilder)
    self._parts = {}
    self._execute = executeFn
    self._proxyCache = {}
    self._boundMethods = {}
    self._handlers = handlers
    self._class = CommandBuilder
    self._cachedCmd = ""
    self._cachedSeparator = " "
    self._dirty = true
    self._argBuffer = {}
    self._argBufferLen = 0
    self._releaseHook = releaseHook or false
    self._inPool = false
    return self
end

---@param executeFn fun(command:string):any
---@param handlers table<string, function>
---@param releaseHook fun(builder:CommandBuilder)|false?
function CommandBuilder:_setContext(executeFn, handlers, releaseHook)
    self._execute = executeFn
    self._handlers = handlers
    self._releaseHook = releaseHook or false
    self._cachedCmd = ""
    self._cachedSeparator = " "
    self._dirty = true
    self._inPool = false
    self:_reset()
    clearArgBuffer(self)
end

function CommandBuilder:_releaseToPool()
    if self._inPool then
        return
    end

    local hook = rawget(self, "_releaseHook")
    if type(hook) == "function" then
        hook(self)
    end
end

---@param part any
---@return CommandBuilder
function CommandBuilder:_append(part)
    self._parts[#self._parts + 1] = tostring(part)
    self._dirty = true
    return self
end

function CommandBuilder:_reset()
    local parts = self._parts
    for i = #parts, 1, -1 do
        parts[i] = nil
    end
    self._dirty = true
end

---@param str any
---@return CommandBuilder
function CommandBuilder:raw(str)
    if str == nil then
        return self
    end
    self._parts[#self._parts + 1] = tostring(str)
    self._dirty = true
    return self
end

---@param str any?
---@return CommandBuilder
function CommandBuilder:chain(str)
    if #self._parts > 0 then
        self._parts[#self._parts] = tostring(self._parts[#self._parts]) .. ";"
    else
        self._parts[#self._parts + 1] = ";"
    end
    if str ~= nil then
        self._parts[#self._parts + 1] = tostring(str)
    end
    self._dirty = true
    return self
end

function CommandBuilder:__index(key)
    local method = rawget(CommandBuilder, key)
    if method then
        local boundMethods = rawget(self, "_boundMethods")
        if boundMethods then
            local cached = boundMethods[key]
            if cached then
                return cached
            end
        end

        local wrapper = makeBoundMethod(self, method)

        if boundMethods then
            boundMethods[key] = wrapper
        end
        return wrapper
    end

    return proxy.createProxy(self, key)
end

---@param opts? any
function CommandBuilder:execute(opts)
    local separator, reset = normalizeBuildOptions(opts)

    local cmd = getCommandString(self, separator)
    if reset then
        self:_reset()
        self:_releaseToPool()
    end
    return self._execute(cmd)
end

---@param opts? any
---@return string
function CommandBuilder:build(opts)
    local separator, reset = normalizeBuildOptions(opts)

    local cmd = getCommandString(self, separator)
    if reset then
        self:_reset()
        self:_releaseToPool()
    end
    return cmd
end

function CommandBuilder:__tostring()
    return self:build()
end

---@param opts? any
function CommandBuilder:__call(opts)
    return self:execute(opts)
end

return {
    CommandBuilder = CommandBuilder,
    newBuilder = newBuilder,
}
