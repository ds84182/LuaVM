local tests = {
	"bisect",
	"cf",
	"echo",
	"env",
	"factorial",
	"fib",
	"fibfor",
	"hello",
	"life",
	"printf",
	"readonly",
	"sieve",
	"sort"
}

local native = (...) ~= nil

if native then
	for i, v in pairs(tests) do
		arg = {}
		local s, e = pcall(loadfile("test/"..v..".lua"))
		if not s then print(e) end
	end
else
	local bytecode = require "luavm.bytecode"
	require "luavm.vm51"
	for i, v in pairs(tests) do
		arg = {}
		local s, e = pcall(vm.lua51.run,bytecode.load(string.dump(loadfile("test/"..v..".lua"))))
		if not s then print(e) end
	end
end
