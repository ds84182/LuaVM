require "luavm.bytecode"
require "luavm.decompiler"

local function func()
	print("Hello!")
end

local bc = bytecode.load(string.dump(func))
bytecode.dump(bc)
local syntaxrep = decompiler.decompile(bc)

local source = decompiler.constructSyntax(syntaxrep,"pretty")

print(source)
