-- CommandBuilder v1 basic examples
-- Run from repo root: lua .\examples\v1_basic.lua

package.path = package.path .. ';./?.lua;../?.lua'

local cmd = require('CommandBuilder')

local CMD = cmd.new({
    execute = function(command)
        print(command)
        return command
    end
})

-- Basic fluent usage
CMD.feature('colorrgb').at.fade('2 thru 0 thru 2').execute()
CMD.attribute('dimmer').at(100).execute()
CMD.clearall().execute()

-- Build without execute
print(CMD.fixture(1, 2, 3, -5).build())

-- Direct call style (string.format behavior)
CMD('clearall')
CMD('fixture %d at %d', 5, 75)
