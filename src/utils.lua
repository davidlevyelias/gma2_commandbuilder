local M = {}

local type = type
local tostring = tostring
local math_abs = math.abs
local string_find = string.find
local string_sub = string.sub
local table_concat = table.concat

-- Fast-path assumption notes:
-- - Decimal extraction expects Lua tostring(number) output like "0.12" for 0 < n < 1.
-- - Numeric-only lists are formatted in a dedicated path to avoid generic mixed-type checks.
-- - Mixed lists still use valueToOperatorAndText for full token/table support.
---@param value number
---@return string? decimalPart
---@return string text
local function extractDecimalPart(value)
    local text = tostring(value)
    local dotPos = string_find(text, ".", 1, true)
    if not dotPos or dotPos >= #text then
        return nil, text
    end
    if string_sub(text, 1, dotPos - 1) ~= "0" then
        return nil, text
    end
    return string_sub(text, dotPos + 1), text
end

---@param value any
---@return boolean
local function isArrayTable(value)
    return type(value) == "table" and #value > 0
end

---@param result string
---@param op string
---@param value string
---@param isFirst boolean
---@return string
local function appendOperatorValue(result, op, value, isFirst)
    if isFirst then
        if op == "minus" then
            return "- " .. value
        elseif op == "thru" then
            return "thru " .. value
        end
        return value
    end

    if op == "minus" then
        return result .. " - " .. value
    elseif op == "thru" then
        return result .. " thru " .. value
    end
    return result .. " + " .. value
end

---@param val any
---@return string
---@return string
local function valueToOperatorAndText(val)
    local valType = type(val)

    if valType == "table" and val.__cmd_op ~= nil then
        local op = val.__cmd_op
        local raw = val.__cmd_value
        if (op == "minus" or op == "plus") and type(raw) == "number" and raw < 0 then
            raw = math_abs(raw)
        end
        return op, tostring(raw)
    end

    if isArrayTable(val) then
        return "plus", M.formatOperatorList(val, #val)
    end

    if valType == "number" then
        if val > 0 and val < 1 then
            local decimalPart, text = extractDecimalPart(val)
            if decimalPart then
                return "thru", decimalPart
            end
            return "plus", text
        end
        if val < 0 then
            return "minus", tostring(math_abs(val))
        end
        return "plus", tostring(val)
    end

    return "plus", tostring(val)
end

---@param args number[]
---@param numArgs integer
---@return string
local function formatNumericOperatorList(args, numArgs)
    -- Optimized for pure-number arrays (common fixture/group list usage).
    local result = ""
    for i = 1, numArgs do
        local val = args[i]
        local op
        local text

        if val > 0 and val < 1 then
            local decimalPart
            decimalPart, text = extractDecimalPart(val)
            if decimalPart then
                op = "thru"
                text = decimalPart
            else
                op = "plus"
            end
        elseif val < 0 then
            op = "minus"
            text = tostring(math_abs(val))
        else
            op = "plus"
            text = tostring(val)
        end

        result = appendOperatorValue(result, op, text, i == 1)
    end

    return result
end

---@param value any
---@return boolean
function M.isArrayTable(value)
    return isArrayTable(value)
end

---@param args any[]
---@param numArgs number
---@return string
function M.formatOperatorList(args, numArgs)
    if numArgs <= 0 then
        return ""
    end

    local first = args[1]
    if type(first) == "number" then
        local allNumeric = true
        for i = 2, numArgs do
            if type(args[i]) ~= "number" then
                allNumeric = false
                break
            end
        end
        if allNumeric then
            return formatNumericOperatorList(args, numArgs)
        end
    end

    local result = ""
    for i = 1, numArgs do
        local op, text = valueToOperatorAndText(args[i])
        result = appendOperatorValue(result, op, text, i == 1)
    end

    return result
end

---@param key string
---@param args any[]
---@param numArgs number
---@param builder table
---@return table
function M.handleThruFormat(key, args, numArgs, builder)
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
    return builder:_append(table_concat(parts, " thru "))
end

---@param key string
---@param args any[]
---@param numArgs number
---@param builder table
---@return table
function M.handleOperatorFormat(key, args, numArgs, builder)
    if numArgs == 0 then
        return builder:_append(key)
    end

    builder:_append(key)

    if numArgs == 1 and isArrayTable(args[1]) then
        return builder:_append(M.formatOperatorList(args[1], #args[1]))
    end

    return builder:_append(M.formatOperatorList(args, numArgs))
end

return M
