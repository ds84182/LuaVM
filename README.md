LuaVM
=====

Lua Virtual Machine for Lua so you can Lua while you Lua

Usage
-----

To use LuaVM, first you must meet all the requirements:

* Lua 5.1 or later, later versions need to use a compatibility library
* A way to generate Lua 5.1 valid bytecode (a ASM suite is comming later)

Then, you must require the bytecode module and the vm module:

```
require("bytecode")
require("vm")
```

After that, simply call ```vm.run(bytecode.load([bytecode here]))```

Documentation
-------------

### bytecode.load(bytecode {string}) [table]
Loads valid Lua 5.1 bytecode into a table format.

### bytecode.save(loaded bytecode {table}) [string]
Saves loaded bytecode as valid Lua 5.1 bytecode. This is the absolute inverse of bytecode.load.

### vm.run(loaded bytecode {table}, arguments {table}, upvalues {table}, global environment {table}, hook {function})
Starts running bytecode. Arguments, Upvalues, Globals, and Hooks are optional.Returns whatever the emulated bytecode returns.
