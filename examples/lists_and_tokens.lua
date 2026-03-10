-- CommandBuilder v1 list and token examples
-- Run from repo root: lua .\examples\v1_lists_and_tokens.lua

package.path = package.path .. ';./?.lua;../?.lua'

local cmd = require('CommandBuilder')

local CMD = cmd.new({
    execute = function(command)
        print(command)
        return command
    end
})

-- List formatting for fixture/group
print(CMD.fixture(1, CMD.thru(10)).build())
print(CMD.group(5, CMD.thru(10), -3).build())
print(CMD.group({ 1, CMD.thru(10), CMD.minus(5), CMD.minus['foo'], CMD.plus(7), CMD.minus(-1) }).build())

-- Arg handling (v1 always sorts map keys)
print(CMD.store.sequence(1).cue(2).arg('merge').arg('nc').build())
print(CMD.appearance.macro(5).arg({ r = 100, g = 0, b = 100 }).build())
print(CMD.appearance.macro(5).arg({ key = 'value' }, 'overwrite', 'nc').build())

-- Additional list-mode example
CMD.unlock.macro({ 2, CMD.thru(11), CMD.minus(3) })()
