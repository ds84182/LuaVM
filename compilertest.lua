require "luavm.bytecode"
require "luavm.compiler"
require "luavm.vm51"

local hello = io.open("hello.bcasm","r"):read("*a")
hello = compiler.compile(hello)
print(assert(loadstring(bytecode.save(hello)))())
print(vm.lua51.run(hello))
