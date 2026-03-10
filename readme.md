# CommandBuilder

A lightweight, fluent API for building GMA2 command strings in Lua.

Current version: 2.0.0

## Overview

CommandBuilder provides a loose, chainable interface that translates method calls into
console command strings. Most inputs are appended as-is unless a built-in or registered
handler adds special formatting.

This repository currently uses the modular implementation:

- [CommandBuilder.lua](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/CommandBuilder.lua) is the entrypoint
- [src/cmd_factory.lua](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/src/cmd_factory.lua) exposes the public API

## Import

```lua
local cmd = require('CommandBuilder')
local CMD = cmd.new({
    execute = function(command)
        return gma.cmd(command)
    end
})
```

If `execute` is omitted, `gma.cmd` is used automatically when available.
Outside GMA2, it falls back to returning the built command string.

The module also exposes version fields:

```lua
print(cmd.VERSION)
print(cmd._VERSION)
```

## CMD.new(opts)

Creates a new CMD instance.

| Option | Type | Description |
| --- | --- | --- |
| `execute` | `fun(command:string):any` | Called by `.execute()` and `CMD(...)`. Defaults to `gma.cmd` when available, otherwise returns the string. |
| `sortArgKeys` | `boolean` | When `true`, map-table args in `arg({...})` are emitted with sorted keys. Default: `false`. |
| `builderPoolSize` | `integer` | Internal builder pool size. Default: `8`. Set `0` to disable pooling. |

Pooling notes:

- Pooling is an internal optimization and does not change API usage.
- If pooling is enabled, avoid holding long-lived builders across unrelated flows.

## Execution semantics

Most fluent calls build a `CommandBuilder` and do not execute immediately.

- Use `.execute()` to run via `opts.execute`
- Use `.build()` to return the command string
- Calling a builder as a function executes it (`builder()`)

That means some expressions need two calls when using implicit execute:

```lua
CMD.group[2]()     -- returns builder
CMD.group[2]()()   -- executes builder
```

## CMD usage

### Direct call style

```lua
CMD("clearall")
CMD("fixture %d at %d", 1, 100)
```

### Fluent builder style

```lua
CMD.feature("colorrgb").at.fade("2 thru 0 thru 2").execute()
CMD.attribute("dimmer").at(100).execute()
CMD.store.sequence(1).cue(2).arg("merge").arg("nc").execute()
```

### No-parens tokens

```lua
CMD.att.dimmer.execute()
CMD.clear.execute()
CMD.clearall.chain().fixture(1, 5)()
```

### Implicit execute

```lua
CMD.clearall()()
CMD.fixture(1, 5).raw("at 100")()
```

Indexing returns a builder, so implicit execute needs an extra final call:

```lua
CMD.group[2]()     -- returns builder
CMD.group[2]()()   -- executes builder
```

## Builder methods

### `build(opts?)`

Returns the command string.

- `opts` can be a string separator or a table `{ separator = " ", reset = true }`
- Default separator is a space
- Default `reset` is `true`

### `execute(opts?)`

Builds and executes via `opts.execute`. Accepts the same `opts` as `build()`.

### `raw(str)`

Appends raw text without formatting.

### `chain(str?)`

Appends a semicolon directly to the last part, then optionally appends `str`.

## Tokens and list mode

Array tables trigger operator formatting:

- `+` between values by default
- `thru` for decimal values between `0` and `1`
- `-` for negative numbers
- `CMD.thru(n)`, `CMD.minus(x)`, and `CMD.plus(x)` override formatting explicitly

Strings are appended as-is and do not imply minus unless wrapped in `CMD.minus()`.

Examples:

```lua
CMD.fixture(1, CMD.thru(10)).build()
CMD.group(5, CMD.thru(10), -3).build()
CMD.group({ 1, CMD.thru(10), CMD.minus(5), CMD.minus["foo"], CMD.plus(7) }).build()
```

Both call form and index form are supported for tokens:

```lua
CMD.thru(10)
CMD.thru[10]
CMD.minus(5)
CMD.minus["foo"]
CMD.plus(7)
CMD.plus["foo"]
```

## arg()

Supports flags, array tables, and map tables:

- `arg("merge", "nc")` -> `/merge /nc`
- `arg({ "merge", "nc" })` -> `/merge /nc`
- `arg({ key = "value" }, "overwrite", "nc")`

Map key order behavior:

- Default (`sortArgKeys = false`): Lua table iteration order via `pairs`
- Optional (`sortArgKeys = true`): alphabetical key order for deterministic output

`false` and `nil` values are skipped. `true` emits `/key` without `=value`.

Example:

```lua
CMD.appearance.macro(5).arg({ r = 100, g = 0, b = 100 }).build()
CMD.appearance.macro(5).arg({ key = "value" }, "overwrite", "nc").build()
```

## Raw helper

`CMD._` bypasses normal handler formatting and appends raw text directly:

```lua
CMD._("raw text").attribute("dimmer").at(100).execute()
CMD._["raw text"].attribute("dimmer").at(100).execute()
```

## Indexing syntax

Both dot and bracket indexing are supported anywhere in a chain:

```lua
CMD.group[2]().build()
CMD["delete"]["macro"][2]().build()
CMD.group[2]().execute()
CMD["delete"]["macro"][2]()()
```

## Handler extension

Handlers are per CMD instance.

### `register(key, handler, opts?)`

Registers a custom handler for this CMD instance.

- `opts.override = true` replaces an existing handler
- Returns `true` on success
- Returns `false, "exists"` if the key already exists and override is not enabled
- Returns `false, "invalid-key"` or `false, "invalid-handler"` for bad input

```lua
local ok, reason = CMD:register("flash", function(builder, args, numArgs)
    builder:raw("flash")
    if numArgs > 0 then
        builder:raw(tostring(args[1]))
    end
    return builder
end)

CMD:register("flash", function(builder)
    return builder:raw("flashfast")
end, { override = true })
```

### `unregister(key)`

Removes a handler from this CMD instance.

- Returns `true` when removed
- Returns `false` when the key is invalid or missing

```lua
CMD:unregister("flash")
```

## Examples

Example scripts are in [examples](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/examples):

- [examples/basic.lua](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/examples/basic.lua): quick fluent usage and direct call examples
- [examples/lists_and_tokens.lua](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/examples/lists_and_tokens.lua): selection lists, tokens, and `arg()` behavior
- [examples/chaining_and_index.lua](e:/Coding/MA2_Plugins/libraries/gma2_commandbuilder/examples/chaining_and_index.lua): chaining, raw helper, implicit execute, and index-based access

Run from repository root:

```powershell
lua .\examples\basic.lua
lua .\examples\lists_and_tokens.lua
lua .\examples\chaining_and_index.lua
```
