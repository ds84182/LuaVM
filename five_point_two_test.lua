require "luavm.bytecode"
require "luavm.vm"

local testbc = string.dump(function() print "Hello" end)
io.open("testbc.luac","wb"):write(testbc)
local testbcl = bytecode.load(testbc)
--local testbco = bytecode.save(testbcl)
--assert(testbc == testbco,"Bytecode save test failed, INCONSISTENT!")
print(vm.run(testbcl))
--print(loadstring(testbc)())
--print(loadstring(testbco)())
