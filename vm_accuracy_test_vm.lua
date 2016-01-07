require "vm_accuracy_test_common"
require "luavm.bytecode"
require "luavm.vm51"

for test in iterateTests() do
	if test:sub(-4,-1) == ".lua" then
		local f,a,r = getTest(test)
		local cr = {vm.lua51.run(bytecode.load(string.dump(f)),a)}
		assert(match(cr,r), test.." failed")
		print(test.." suceeded")
	end
end