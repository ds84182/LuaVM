local args = {...}
if #args < 2 then print("Usage: compile [bcasm] [luac]") return end

local inf = io.open(args[1],"r"):read"*a"
require "luavm.compiler"
require "luavm.bytecode"
io.open(args[2],"wb"):write(bytecode.save(compiler.compile(inf)))
