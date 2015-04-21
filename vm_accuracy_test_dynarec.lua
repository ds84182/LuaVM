require "vm_accuracy_test_common"
require "luavm.bytecode"
require "luavm.dynarec"

for test in iterateTests() do
	if test:sub(-4,-1) == ".lua" then
		local f,a,r = getTest(test)
		print("running "..test)
		local dyncode = table.concat(
			dynarec.compile(bytecode.load(string.dump(f)))
		,"\n")
		print(dyncode)
		local cr = {assert(loadstring(dyncode))(unpack(a))}
		assert(match(cr,r), test.." failed")
		print(test.." suceeded")
	end
end
