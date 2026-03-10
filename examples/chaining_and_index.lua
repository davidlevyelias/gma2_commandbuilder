-- CommandBuilder v1 chaining and indexing examples
-- Run from repo root: lua .\examples\v1_chaining_and_index.lua

package.path = package.path .. ';./?.lua;../?.lua'

local cmd = require('CommandBuilder')

local CMD = cmd.new({
    execute = function(command)
        print(command)
        return command
    end
})

-- Inline chaining
print(CMD.clearall().chain().fixture(1, 5).raw('at 100').build())

-- Join multiple commands into one builder
local cmd1 = CMD.clearall()
local cmd2 = CMD.fixture(1, 5).raw('at 100')
local cmd3 = CMD.store.sequence(1).cue(1)
local combined = CMD.chain(cmd1, cmd2, cmd3)
print(combined.build())
combined.execute()

-- Raw helper
CMD._('raw text').attribute('dimmer').at(100).execute()
CMD._['raw text'].attribute('dimmer').at(100).execute()

-- Implicit execute
CMD.clearall()()
CMD.fixture(1, 5).raw('at 100')()

-- No-parens tokens and indexing
CMD.clear.execute()
CMD.clearall.chain().fixture(1, 5)()
CMD.att.dimmer.execute()
CMD['delete']['macro'][2]()()
CMD.feature.colorrgb.at.fade[2]()()
