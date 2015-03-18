require "luavm.bytecode"
require "luavm.compiler"
require "luavm.vm"

local hello = io.open("hello.bcasm","r"):read("*a")
hello = compiler.compile(hello)
print(assert(loadstring(bytecode.save(hello)))())
print(vm.run(hello))
