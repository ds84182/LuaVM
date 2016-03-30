local bytecode = require "luavm.bytecode"
local lua = require "luavm.vm".native()

local gbpkgs = {}

local globals
globals = setmetatable({
	require = function(name)
		if gbpkgs[name] then return gbpkgs[name] end
		
		local filename = name:gsub("%.","/")..".lua"
		local file = io.open(filename)
		if file then
			file:close()
			local bc = bytecode.load(string.dump(loadfile(filename)))
			gbpkgs[name] = lua.run(bc,{name},nil,globals)
			return gbpkgs[name]
		else
			return require(name)
		end
	end,
	loadstring = function(str,name)
		local bc = bytecode.load(string.dump(loadstring(str, name)))
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
--local bc = bytecode.load(io.open(file,"rb"):read("*a"))
print("Loaded bytecode")

lua.run(bc,args,nil,globals)
