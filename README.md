LuaVM
=====

Lua Virtual Machine for Lua so you can Lua while you Lua

Usage
-----

To use LuaVM, first you must meet all the requirements:

* Lua 5.1 and 5.2 are the only versions supported. Unoffical versions of Lua (like LuaJIT, LuaJ, etc.) are not fully supported.
* A way to generate Lua 5.1 valid bytecode (an ASM suite is in the works, a Lua to bytecode compiler is coming)

Then, you must require the modules you need (sorry for the global namespace injections):

```
require("luavm.bytecode")
require("luavm.vm[your version here, 51 or 52]")
```

After that, simply call ```vm.lua[your version here, like 51 or 52].run(bytecode.load([bytecode here]))```

Documentation
-------------

### bytecode.load(bytecode)
Loads valid Lua 5.1 or 5.2 bytecode (as a string). Returns a table.

### bytecode.save(bytecode)
Redumps bytecode tables created from ```bytecode.new``` or ```bytecode.load```. Returns a string.

### vm.run(bytecode, arguments, upvalues, globals, hook)
Starts running bytecode. Arguments, Upvalues, Globals, and Hooks are optional. Returns whatever the emulated bytecode returns. Arguments, upvalues, and globals must be a table. Hook must be a function, it is called every single instruction.
