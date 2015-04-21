local vmversion = _VERSION:gsub("%D","")
require "luavm.bytecode"
print "required bytecode"
require("luavm.vm"..vmversion)
print "required vm51"
local lua = vm["lua"..vmversion]

local globals
globals = setmetatable({
	require = function(name)
		local filename = name:gsub("%.","/")..".lua"
		local file = io.open(filename)
		if file then
			file:close()
			local bc = bytecode.load(string.dump(loadfile(filename)))
			return lua.run(bc,nil,nil,globals)
		else
			return require(name)
		end
	end,
	loadstring = function(str,name)
		local bc = bytecode.load(string.dump(loadstring(str)))
		return function(...) return lua.run(bc,{...},nil,globals) end
	end,
	--[[loadfile = function(file)
		local bc = bytecode.load(string.dump(loadfile(file)))
		return function(...) return lua.run(bc,{...},nil,globals) end
	end]]
},{__index=_G})
print("Created globals")

local args = {...}
print("Got args: ",args[1])
local file = table.remove(args,1)
print("File: ",file)
local bc = bytecode.load(string.dump(loadfile(file)))
print("Loaded bytecode")

lua.run(bc,args,nil,globals)
