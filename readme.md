# CommandBuilder

A lightweight, fluent API for building GMA2 command strings in Lua.

Current version: 1.0.0

## Overview

CommandBuilder provides a loose, chainable interface that translates method calls into
console command strings. Most inputs are appended verbatim; a small set of named handlers
add special formatting (fixture/group selection lists, `/arg` flags, fade/delay ranges).

## Import

```lua
local cmd = require('CommandBuilder')
local CMD = cmd.new({
    execute = function(command)
        return gma.cmd(command)
    end
})
```

If `execute` is omitted, `gma.cmd` is used automatically when running inside GMA2.
Outside GMA2 (e.g. during testing), it falls back to returning the built command string.

## CMD.new(opts)

Creates a new CMD instance.

| Option    | Type                      | Description                                                              |
| --------- | ------------------------- | ------------------------------------------------------------------------ |
| `execute` | `fun(command:string):any` | Called by `.execute()` and `CMD(...)`. Defaults to `gma.cmd` when available, otherwise returns the string. |

## CMD usage

### Direct call (like gma.cmd)

```lua
CMD("clearall")
CMD("fixture %d at %d", 1, 100)
```

Supports `string.format`-style arguments when extra values are passed.

### Fluent builder

```lua
CMD.feature("colorrgb").at.fade("2 thru 0 thru 2").execute()
CMD.attribute("dimmer").at(100).execute()
CMD.store.sequence(1).cue(2).arg("merge").arg("nc").execute()
```

### No-parens (dot-chained tokens)

Accessing a key without calling it still accumulates it as a part. Use `.execute()` or
a trailing `()` to run it.

```lua
CMD.att.dimmer.execute()
CMD.clear.execute()
CMD.clearall.chain().fixture(1, 5)()
```

### Implicit execute

Any builder can be called as a function to execute immediately:

```lua
CMD.clearall()()
CMD.fixture(1, 5).raw("at 100")()
```

Note: indexing (`CMD.group[2]`) returns a builder, not a result. A final `()` executes it:

```lua
CMD.group[2]()     -- builds "group 2", does NOT execute
CMD.group[2]()()   -- builds and executes
```

## Builder methods

### `build(opts?)`

Returns the command string and resets the builder.

`opts` can be:

- a string — used as the part separator (default: `" "`)
- a table `{ separator?: string, reset?: boolean }` — `reset` defaults to `true`

```lua
local s = CMD.fixture(1, 2, 3).build()       -- "fixture 1 + 2 + 3"
local s = CMD.fixture(1).build({ reset = false }) -- keeps parts for reuse
```

### `execute(opts?)`

Builds the string and passes it to the `execute` function from `CMD.new`. Accepts the
same `opts` as `build()`.

### `raw(str)`

Appends a string without any processing.

```lua
CMD.feature("colorrgb").raw("at intensity 50").execute()
```

### `chain(str?)`

Appends a semicolon directly to the last part (no leading space), then optionally appends
`str`. Used to chain commands within a single builder.

```lua
CMD.clearall().chain().fixture(1, 5).raw("at 100").execute()
-- clearall; fixture 1 + 5 at 100
```

## Operator lists (fixture/group selections)

The `fixture` and `group` handlers accept operator-formatted lists.

**Multiple positional args:**

```lua
CMD.fixture(1, 2, 3, -5).build()
-- fixture 1 + 2 + 3 - 5
```

**Single array table:**

```lua
CMD.group({ 1, CMD.thru(10), CMD.minus(5), CMD.minus["foo"] }).build()
-- group 1 thru 10 - 5 - foo
```

**Formatting rules inside a list:**

| Value               | Result                      |
| ------------------- | --------------------------- |
| Positive number     | `+ n`                       |
| Negative number     | `- n` (absolute value)      |
| Decimal `0 < n < 1` | `thru <decimal part>`       |
| String              | appended as-is (always `+`) |
| `CMD.thru(n)`       | `thru n`                    |
| `CMD.minus(x)`      | `- x`                       |
| `CMD.plus(x)`       | `+ x`                       |

## Tokens

Tokens are helpers used inside selection lists or as inline range values.
Both call form and index form work:

### `CMD.thru(n)` / `CMD.thru[n]`

```lua
CMD.fixture(1, CMD.thru(10)).build()   -- fixture 1 thru 10
```

### `CMD.minus(x)` / `CMD.minus[x]`

```lua
CMD.group({ 1, CMD.thru(10), CMD.minus(3) }).build()   -- group 1 thru 10 - 3
```

Passing a negative number to `CMD.minus` normalises to its absolute value in lists.

### `CMD.plus(x)` / `CMD.plus[x]`

```lua
CMD.group({ 1, CMD.plus(5) }).build()   -- group 1 + 5
```

## arg handler

The `arg` handler appends `/flag`-style arguments.

**String / plain value** → appended with `/` prefix:

```lua
CMD.store.sequence(1).cue(2).arg("merge").arg("nc").build()
-- store sequence 1 cue 2 /merge /nc
```

**Array table** → each element gets a `/` prefix:

```lua
CMD.store.sequence(1).cue(2).arg({ "merge", "nc" }).build()
-- store sequence 1 cue 2 /merge /nc
```

**Map table** → keys are sorted, emitted as `/key` or `/key=value`:

```lua
CMD.appearance.macro(5).arg({ r = 100, g = 0, b = 100 }).build()
-- appearance macro 5 /b=100 /g=0 /r=100
```

`false` / `nil` values are skipped. `true` values emit the key only (`/key`).

## fade / delay handlers

Accept a plain string or multiple values joined with `thru`:

```lua
CMD.feature("colorrgb").at.fade("2 thru 0 thru 2").execute()
-- feature colorrgb at fade 2 thru 0 thru 2
```

## CMD.chain(...)

Joins multiple builders or strings into one builder with `; ` separating commands.

```lua
local combined = CMD.chain(
    CMD.clearall(),
    CMD.fixture(1, 5).raw("at 100"),
    CMD.store.sequence(1).cue(1)
)
combined.execute()
-- clearall; fixture 1 + 5 at 100; store sequence 1 cue 1
```

## CMD.\_ raw helper

`CMD._` bypasses all handler logic and appends the value directly, then continues the
fluent chain:

```lua
CMD._("raw text").attribute("dimmer").at(100).execute()
CMD._["raw text"].attribute("dimmer").at(100).execute()
```

## Indexing syntax

Both `.key` and `[key]` work interchangeably anywhere in a chain:

```lua
CMD.group[2]().build()               -- group 2
CMD["delete"]["macro"][2]().build()  -- delete macro 2
CMD.group[2]().execute()
CMD["delete"]["macro"][2]()()
```

## CMD.register(key, handler)

Registers a custom handler for a key. Handlers are shared globally across all CMD
instances created in the same module scope.

```lua
---@param builder table
---@param args any[]
---@param numArgs number
---@return table builder
CMD.register("at", function(builder, args, numArgs)
    -- custom formatting
    return builder
end)
```

If a handler already exists for `key` it is replaced immediately.

## Examples

Example scripts are in the `examples/` folder:

- `examples/basic.lua`: quick fluent usage and direct call examples.
- `examples/lists_and_tokens.lua`: fixture/group list formatting, tokens, and `arg()` behavior.
- `examples/chaining_and_index.lua`: chaining, raw helper, implicit execute, and index-based access.

Run from repository root:

```lua
lua .\examples\basic.lua
lua .\examples\lists_and_tokens.lua
lua .\examples\chaining_and_index.lua
```

## arg()

Supports flags, map tables, and mixed arguments:

- Non-table args are appended as flags: `arg("merge", "nc")` -> `/merge /nc`
- Map tables are expanded as key pairs: `arg({ r = 100, g = 0 })` -> `/r=100 /g=0`
- Mixed usage is allowed: `arg({ key = "value" }, "overwrite", "nc")`

Map key order behavior:

- Default (`sortArgKeys = false`): key order follows Lua table iteration order (`pairs`) and may vary.
- Optional (`sortArgKeys = true`): keys are sorted alphabetically for deterministic output.

```lua
CMD.store.sequence(1).cue(1).arg("merge", "nc")
CMD.appearance.macro(5).arg({ r = 100, g = 0, b = 100 })
CMD.appearance.macro(5).arg({ key = "value" }, "overwrite", "nc")
```

## Handler extension

Handlers are per CMD instance.

### register(key, handler, opts?)

Registers a custom handler for this CMD instance.

- `key`: string command token to handle
- `handler`: function `(builder, args, numArgs) -> builder`
- `opts.override`: boolean (default `false`)

Returns:

- `true` when registered
- `false, "exists"` when key already exists and override is not enabled
- `false, "invalid-key"` for empty/non-string key
- `false, "invalid-handler"` for non-function handler

```lua
local ok, reason = CMD:register("flash", function(builder, args, numArgs)
    builder:raw("flash")
    if numArgs > 0 then
        builder:raw(tostring(args[1]))
    end
    return builder
end)

-- Replace existing handler explicitly
CMD:register("flash", function(builder)
    return builder:raw("flashfast")
end, { override = true })
```

### unregister(key)

Removes a handler from this CMD instance.

- Returns `true` when removed
- Returns `false` when key is invalid or missing

```lua
CMD:unregister("flash")
```
