require "luavm.bytecode"
print "required bytecode"

local args = {...}
print("Got args: ",args[1])
local file = table.remove(args,1)
print("File: ",file)
local bc = bytecode.load(string.dump(loadfile(file)))
print("Loaded bytecode")

bytecode.dump(bc)
