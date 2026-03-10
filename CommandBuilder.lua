---@diagnostic disable: undefined-field

local M = {}

local VERSION = "1.0.0"
M.VERSION = VERSION
M._VERSION = VERSION

---@class CommandBuilder
---@field _parts string[]
---@field _execute fun(command:string):any
---@field _proxyCache table<string, table>
---@field _boundMethods table<string, function>
local CommandBuilder = {}
CommandBuilder.__index = CommandBuilder

---@param executeFn fun(command:string):any
---@return CommandBuilder
local function newBuilder(executeFn)
    local self = setmetatable({}, CommandBuilder)
    self._parts = {}
    self._execute = executeFn
    self._proxyCache = {}
    self._boundMethods = {}
    return self
end

---@param part any
---@return CommandBuilder
function CommandBuilder:_append(part)
    self._parts[#self._parts + 1] = tostring(part)
    return self
end

function CommandBuilder:_reset()
    self._parts = {}
end

---@param str any
---@return CommandBuilder
function CommandBuilder:raw(str)
    if str == nil then
        return self
    end
    self._parts[#self._parts + 1] = tostring(str)
    return self
end

---Chain another command by appending ";" (no left space) and optionally a string
---@param str any? Optional command string to append after the separator
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
    return self
end

-- ============================================================================
-- Special Key Handlers
-- ============================================================================

---Special handlers for specific keys
local specialHandlers = {}

---@param value any
---@return boolean
local function isArrayTable(value)
    return type(value) == "table" and #value > 0
end

---@param args any[]
---@param numArgs number
---@return string
local function formatOperatorList(args, numArgs)
    if numArgs <= 0 then
        return ""
    end

    local items = {}
    for i = 1, numArgs do
        local val = args[i]
        local valType = type(val)

        if valType == "table" and val.__cmd_op ~= nil then
            local op = val.__cmd_op
            local raw = val.__cmd_value
            if (op == "minus" or op == "plus") and type(raw) == "number" and raw < 0 then
                raw = math.abs(raw)
            end
            items[#items + 1] = { op = op, value = tostring(raw) }
        elseif isArrayTable(val) then
            items[#items + 1] = { op = "plus", value = formatOperatorList(val, #val) }
        elseif valType == "number" then
            if val > 0 and val < 1 then
                local decimalPart = string.match(tostring(val), "0%.(%d+)")
                if decimalPart then
                    items[#items + 1] = { op = "thru", value = decimalPart }
                else
                    items[#items + 1] = { op = "plus", value = tostring(val) }
                end
            elseif val < 0 then
                items[#items + 1] = { op = "minus", value = tostring(math.abs(val)) }
            else
                items[#items + 1] = { op = "plus", value = tostring(val) }
            end
        else
            -- Strings and other types are appended as-is (no implicit minus)
            items[#items + 1] = { op = "plus", value = tostring(val) }
        end
    end

    local result = ""
    for i, item in ipairs(items) do
        if i == 1 then
            if item.op == "minus" then
                result = "- " .. item.value
            elseif item.op == "thru" then
                result = "thru " .. item.value
            else
                result = item.value
            end
        else
            if item.op == "minus" then
                result = result .. " - " .. item.value
            elseif item.op == "thru" then
                result = result .. " thru " .. item.value
            else
                result = result .. " + " .. item.value
            end
        end
    end

    return result
end

---@param key string
---@param args any[]
---@param numArgs number
---@param builder CommandBuilder
---@return CommandBuilder
local function handleThruFormat(key, args, numArgs, builder)
    if numArgs == 0 then
        return builder:_append(key)
    elseif numArgs == 1 and type(args[1]) == "string" then
        builder:_append(key)
        return builder:_append(args[1])
    end

    builder:_append(key)
    local parts = {}
    for i = 1, numArgs do
        parts[i] = tostring(args[i])
    end
    return builder:_append(table.concat(parts, " thru "))
end

---@param key string
---@param args any[]
---@param numArgs number
---@param builder CommandBuilder
---@return CommandBuilder
local function handleOperatorFormat(key, args, numArgs, builder)
    if numArgs == 0 then
        return builder:_append(key)
    end

    builder:_append(key)

    if numArgs == 1 and isArrayTable(args[1]) then
        return builder:_append(formatOperatorList(args[1], #args[1]))
    end

    return builder:_append(formatOperatorList(args, numArgs))
end

specialHandlers.arg = function(builder, args, numArgs)
    if numArgs == 0 then
        return builder
    end

    for i = 1, numArgs do
        local arg = args[i]
        if type(arg) == "table" then
            if isArrayTable(arg) then
                for j = 1, #arg do
                    builder:_append("/" .. tostring(arg[j]))
                end
            else
                local keys = {}
                for k, _ in pairs(arg) do
                    keys[#keys + 1] = tostring(k)
                end
                table.sort(keys)

                for _, key in ipairs(keys) do
                    local val = arg[key]
                    if val == true then
                        builder:_append("/" .. key)
                    elseif val == false or val == nil then
                        -- skip
                    else
                        builder:_append("/" .. key .. "=" .. tostring(val))
                    end
                end
            end
        else
            builder:_append("/" .. tostring(arg))
        end
    end

    return builder
end

specialHandlers.fade = function(builder, args, numArgs)
    return handleThruFormat("fade", args, numArgs, builder)
end

specialHandlers.delay = function(builder, args, numArgs)
    return handleThruFormat("delay", args, numArgs, builder)
end

specialHandlers.fixture = function(builder, args, numArgs)
    return handleOperatorFormat("fixture", args, numArgs, builder)
end

specialHandlers.group = function(builder, args, numArgs)
    return handleOperatorFormat("group", args, numArgs, builder)
end

-- Raw passthrough handler: CMD._("text")
specialHandlers._ = function(builder, args, numArgs)
    if numArgs > 0 then
        return builder:raw(args[1])
    end
    return builder
end

-- ============================================================================
-- Proxy Creation
-- ============================================================================

local function createProxy(builder, key)
    local proxyCache = builder._proxyCache
    if proxyCache then
        local cached = proxyCache[key]
        if cached then
            return cached
        end
    end

    local proxy
    proxy = setmetatable({}, {
        __call = function(_, ...)
            local args = { ... }
            local numArgs = select('#', ...)

            local handler = specialHandlers[key]
            if handler then
                return handler(builder, args, numArgs)
            end

            builder:_append(key)
            if numArgs > 0 then
                for i = 1, numArgs do
                    local arg = args[i]
                    if isArrayTable(arg) then
                        builder:_append(formatOperatorList(arg, #arg))
                    else
                        builder:_append(arg)
                    end
                end
            end
            return builder
        end,

        __index = function(_, nextKey)
            if key == "_" then
                -- Allow CMD._["raw text"] as shorthand for raw()
                builder:raw(nextKey)
                return builder
            end

            -- If the next key is a real builder method, append current key and return it.
            if rawget(CommandBuilder, nextKey) then
                builder:_append(key)
                return builder[nextKey]
            end

            builder:_append(key)
            return createProxy(builder, nextKey)
        end
    })

    if proxyCache then
        proxyCache[key] = proxy
    end
    return proxy
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

        local wrapper = function(...)
            if select('#', ...) >= 1 and select(1, ...) == self then
                return method(self, select(2, ...))
            end
            return method(self, ...)
        end

        if boundMethods then
            boundMethods[key] = wrapper
        end
        return wrapper
    end

    return createProxy(self, key)
end

---@param opts any? string separator OR { separator?:string, reset?:boolean }
function CommandBuilder:execute(opts)
    local reset = true
    local separator = opts
    if type(opts) == "table" then
        reset = (opts.reset ~= false)
        separator = opts.separator
    end

    if type(separator) ~= "string" and separator ~= nil then
        separator = " "
    end
    separator = separator or " "

    local cmd = table.concat(self._parts, separator)
    if reset then
        self:_reset()
    end
    return self._execute(cmd)
end

---@param opts any? string separator OR { separator?:string, reset?:boolean }
---@return string
function CommandBuilder:build(opts)
    local reset = true
    local separator = opts
    if type(opts) == "table" then
        reset = (opts.reset ~= false)
        separator = opts.separator
    end

    if type(separator) ~= "string" and separator ~= nil then
        separator = " "
    end
    separator = separator or " "

    local cmd = table.concat(self._parts, separator)
    if reset then
        self:_reset()
    end
    return cmd
end

function CommandBuilder:__tostring()
    return self:build()
end

---Allow calling a builder like a function to execute.
---@param opts any? string separator OR { separator?:string, reset?:boolean }
function CommandBuilder:__call(opts)
    return self:execute(opts)
end

-- ============================================================================
-- CMD Factory
-- ============================================================================

---@class CmdModuleNewOpts
---@field execute fun(command:string):any

---Create a CMD instance.
-- opts.execute defaults to a function that returns the built command string.
---@param opts CmdModuleNewOpts?
---@return table
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

    local CMD = {
        ---Join multiple command builders (or strings) with "; " between commands.
        ---Returns a CommandBuilder instance so you can call :build() / :execute().
        ---Consumes builders (because tostring(builder) calls build()).
        ---@param ... any
        ---@return CommandBuilder
        chain = function(...)
            local items = { ... }
            local chainBuilder = newBuilder(executeFn)

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
        end,

        ---Helper token: CMD.thru(10) can be used inside fixture/group lists.
        ---@return table
        thru = makeTokenFactory("thru ", "thru"),

        ---Helper token: CMD.minus(5) or CMD.minus["foo"] -> "-5" / "-foo"
        ---@return table
        minus = makeTokenFactory("-", "minus"),

        ---Helper token: CMD.plus(5) or CMD.plus["foo"] -> "+5" / "+foo"
        ---@return table
        plus = makeTokenFactory("+", "plus"),

        ---Optional extension point for this instance.
        ---@param key string
        ---@param handler fun(builder:CommandBuilder, args:any[], numArgs:number):CommandBuilder
        register = function(_, key, handler)
            specialHandlers[key] = handler
        end
    }

    return setmetatable(CMD, {
        __index = function(self, key)
            local direct = rawget(self, key)
            if direct ~= nil then
                return direct
            end
            return createProxy(newBuilder(executeFn), key)
        end,
        __call = function(_, commandString, ...)
            if select('#', ...) > 0 then
                commandString = string.format(commandString, ...)
            end
            return executeFn(commandString)
        end
    })
end

return M
