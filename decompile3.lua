local bc = require "luavm.bytecode"
local decompiler = require "luavm.decompiler3"
serpent = require "serpent"

local function testFunc()
	print("Hello, World!", x+4)
	if y then
		print("y is set!")
	end
	local i = 0
	while i < 10 and w do
		if i == 5 or i == 5 then
			print('FIVE!')
		end
		if math.deg(math.pi) == 180 then
			print("PI == 180")
		end
		i = i+1
		print("i is", i)
	end
	if i > 4 and j or n == 4 then
		return 0
	end
	if q > p or r < n and f > 4 then
		return 1
	end
	for i=1, 10 do
		print(i)
	end
	return 5
end

-- not on and widgetPowerLevel > 0
--[[
0	{"getglobal", dest = 0, index = 0}
1	{"condop", "test", invert = true, target = 0}
2	{"jump", to = 8}
3	{"getglobal", dest = 0, index = 1}
4	{"condop", "<", invert = false, lhs = 258, rhs = 0}
5	{"jump", to = 8}
6	{"loadk", dest = 0, kst = 3}
7	{"return", base = 0, count = 1}
]]
-- not on and widgetPowerLevel > 0

-- not (on and widgetPowerLevel > 0)
--[[
0	{"getglobal", dest = 0, index = 0}
1	{"condop", "test", invert = false, target = 0}
2	{"jump", to = 6}
3	{"getglobal", dest = 0, index = 1}
4	{"condop", "<", invert = true, lhs = 258, rhs = 0}
5	{"jump", to = 8}
6	{"loadk", dest = 0, kst = 3}
7	{"return", base = 0, count = 1}
]]
-- on or widgetPowerLevel > 0

-- a or b > 0
--[[
0	{"getglobal", dest = 0, index = 0}
1	{"condop", "test", invert = false, target = 0}
2	{"jump", to = 6}
3	{"getglobal", dest = 0, index = 1}
4	{"condop", "<", invert = true, lhs = 258, rhs = 0}
5	{"jump", to = 8}
6	{"loadk", dest = 0, kst = 3}
7	{"return", base = 0, count = 1}
]]

-- a or b
--[[
8	{"getglobal", dest = 0, index = 4}
9	{"condop", "test", invert = true, target = 0}
10	{"jump", to = 14}
11	{"getglobal", dest = 0, index = 5}
12	{"condop", "test", invert = false, target = 0}
13	{"jump", to = 19}
]]
--

local function testFunc()
	if not (on and widgetPowerLevel > 0) then
		return not (on and widgetPowerLevel > 0)
	end

	if a or b then
		return a or b
	end
	if a and (b and c or d) or e then
		print("!")
	end
	if i > 4 and j or n == 4 then
		print("!!!")
	end
	if q > p or r < n and f > 4 then
		print("!!")
	end
	return a > a and (b > b and c or d) or e
end

local function testFunc1()
	while true do
		print("Hey")
		if j > 2 then
			print("Bye")
			break
		end
	end
	print("!")
	return a > 0 and b > 0
end

local function testFunc1()
	for i, v in pairs(_G) do
		print(i, v)
	end

	for i=1, 10 do
		print(i)
	end
end

local function testFunc1()
	while true do
		while true do
			print("!")
			break
		end
		print("!!")
	end
end

local function testFunc1()
	if j then
		print("J!")
		return j
	elseif q then
		print("Q!")
		if m then
			print("BUT M!")
		end
		return q
	else
		print("?!")
		return false
	end
	print("!")
	return true
end

local function testFunc1()
	if g > 3 then
		print("!")
	else
		g = 3
	end

	repeat
		print("jk")
	until not kidding
end

local function testFunc1()
	local g, s = 3, 0
	while g > 0 do
		local n = g * g
		s = s + n
		g = g - 1
	end
	if s > 4 then
		local q = s * s
		s = q * 0.5
	end
	return s, s * s, s * s * s
end

local function testFunc1()
	local q = 3
	do
		local g = 3
		local function x()
			g = 4
		end
		q = 4
	end
	return q
end

local function testFunc()
	local x = {}
	x.x = 5
	x.y = 3
	return x
end

local dump = string.dump(testFunc)
--local dump = io.open(..., "rb"):read("*a")
local chunk = bc.load(dump) --.functionPrototypes[1]
local decoded = decompiler.decoder.native().decodeChunk(chunk)

for i=0, decoded.last do
	print(i, serpent.line(decoded[i]))
end

bc.dump(chunk)

local source = decompiler.core.decompile(decoded, chunk, {
	asFunction = true
})

print()
for i=1, #source do
	print(source[i])
end

--[[x = 3
w = true
testFunc();
(function()
	local L_0, L_1
	print("Hello, World!", x+4)
	L_0 = y
	if L_0 then
	  print("y is set!")
	end
	L_0 = 0
	while L_0<10 and w do
	  if L_0==5 or L_0==5 then
		print("FIVE!")
	  end
	  L_1 = math.deg(math.pi)
	  if L_1==180 then
		print("PI == 180")
	  end
	  L_0 = L_0+1
	  print("i is", L_0)
	end
	if 4<L_0 and j or n==4 then
	  return 0
	end
	return 5
end)()]]
