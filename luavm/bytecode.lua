--reads lua 5.1 bytecode--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

local modulename = ...
modulename = modulename:match("^(.+)%..-$") or modulename

local function subrequire(sub, ...)
	local mod = {require(modulename.."."..sub)}
	if select('#', ...) > 0 then
		mod = {mod[1](...)}
	end
	return (table.unpack or unpack)(mod)
end

local supportedTypes = string.dump(function() end):sub(7,12)

bytecode = {}
bytecode.debug = false
bytecode.printDebug = function(fmt, ...)
	if bytecode.debug then
		print(fmt:format(...))
	end
end
bytecode.version = {}

if _VERSION >= "Lua 5.3" then
	bytecode.version.lua53 = subrequire("bytecode.lua53", bytecode)
	bytecode.version[0x53] = bytecode.version.lua53
	bytecode.version.S = bytecode.version.lua51
else
	--If not 5.3 or above, create bytecode.bit and bytecode.binarytypes
	
	--use bit32 if available, else use require "bit"
	if bit32 then
		bytecode.bit = {
			bor = bit32.bor,
			band = bit32.band,
			bnot = bit32.bnot,
			blshift = bit32.lshift,
			brshift = bit32.rshift
		}
	else
		local bitAvailable, bit = pcall(require, "bit")
		
		if bitAvailable then
			bytecode.bit = bit
		else
			error("TODO: Custom bitwise implementation here!")
		end
	end
	
	local bit = bytecode.bit
	
	local function grab_byte(v)
		return math.floor(v / 256), string.char(math.floor(v) % 256)
	end
	
	bytecode.binarytypes = {
		encode = {
			u1 = function(value, bigEndian)
				return string.char(value)
			end,
			u2 = function(value, bigEndian)
				local out = string.char(
					bit.band(value,0xFF),
					bit.brshift(bit.band(value,0xFF00),8)
				)
				
				if bigEndian then out = out:reverse() end
				return out
			end,
			u4 = function(value, bigEndian)
				local out = string.char(
					bit.band(value, 0xFF),
					bit.brshift(bit.band(value, 0xFF00), 8),
					bit.brshift(bit.band(value, 0xFF0000), 16),
					bit.brshift(bit.band(value, 0xFF000000), 24)
				)
				
				if bigEndian then out = out:reverse() end
				return out
			end,
			u8 = function(value, bigEndian) --CAUTION: This may not output correctly!
				local out = string.char(
					bit.band(value, 0xFF),
					bit.brshift(bit.band(value, 0xFF00), 8),
					bit.brshift(bit.band(value, 0xFF0000), 16),
					bit.brshift(bit.band(value, 0xFF000000), 24),
					bit.brshift(bit.band(value, 0xFF00000000), 32),
					bit.brshift(bit.band(value, 0xFF0000000000), 40),
					bit.brshift(bit.band(value, 0xFF000000000000), 48),
					bit.brshift(bit.band(value, 0xFF00000000000000), 56)
				)
				
				if bigEndian then out = out:reverse() end
				return out
			end,
			float = function(value, bigEndian)
				error("NYI")
			end,
			double = function(value, bigEndian)
				local sign = 0
				if x < 0 then sign = 1; x = -x end
				local mantissa, exponent = math.frexp(x)
				if x == 0 then -- zero
				mantissa, exponent = 0, 0
				else
				mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, 53)
				exponent = exponent + 1022
				end
				local v, byte = "" -- convert to bytes
				x = mantissa
				for i = 1,6 do
					x, byte = grab_byte(x); v = v..byte -- 47:0
				end
				x, byte = grab_byte(exponent * 16 + x); v = v..byte -- 55:48
				x, byte = grab_byte(sign * 128 + x); v = v..byte -- 63:56
				
				if bigEndian then v = v:reverse() end
				return v
			end,
		},
		decode = {
			u1 = function(bin, index, bigEndian)
				return bin:byte(index)
			end,
			u2 = function(bin, index, bigEndian)
				local a, b = bin:byte(index, index+1)
				return bigEndian and bit.blshift(a, 8)+b or bit.blshift(b, 8)+a
			end,
			u4 = function(bin, index, bigEndian)
				local a, b, c, d = bin:byte(index, index+3)
				return bigEndian and
					bit.blshift(a, 24)+bit.blshift(b, 16)+bit.blshift(c, 8)+d or
					bit.blshift(d, 24)+bit.blshift(c, 16)+bit.blshift(b, 8)+a
			end,
			u8 = function(bin, index, bigEndian) --CAUTION: This may output math.huge for large 64bit numbers!
				local a, b, c, d, e, f, g, h = bin:byte(index, index+7)
				return bigEndian and
					bit.blshift(a, 24)+bit.blshift(b, 16)+bit.blshift(c, 8)+d or
					bit.blshift(d, 24)+bit.blshift(c, 16)+bit.blshift(b, 8)+a
			end,
			float = function(bin, index, bigEndian)
				local x = bin:sub(index, index+3)
				if bigEndian then x = x:reverse() end
				
				local sign = 1
				local mantissa = string.byte(x, 3) % 128
				for i = 2, 1, -1 do mantissa = mantissa * 256 + string.byte(x, i) end
				if string.byte(x, 4) > 127 then sign = -1 end
				local exponent = (string.byte(x, 4) % 128) * 2 +
							   math.floor(string.byte(x, 3) / 128)
				if exponent == 0 then return 0 end
				mantissa = (math.ldexp(mantissa, -23) + 1) * sign
				return math.ldexp(mantissa, exponent - 127)
			end,
			double = function(bin, index, bigEndian)
				local x = bin:sub(index, index+7)
				if bigEndian then x = x:reverse() end
				
				local sign = 1
				local mantissa = string.byte(x, 7) % 16
				for i = 6, 1, -1 do mantissa = mantissa * 256 + string.byte(x, i) end
				if string.byte(x, 8) > 127 then sign = -1 end
				local exponent = (string.byte(x, 8) % 128) * 16 +math.floor(string.byte(x, 7) / 16)
				if exponent == 0 then return 0 end
				mantissa = (math.ldexp(mantissa, -52) + 1) * sign
				return math.ldexp(mantissa, exponent - 1023)
			end
		}
	}
end

if _VERSION >= "Lua 5.2" then
	bytecode.version.lua52 = subrequire("bytecode.lua52", bytecode)
	bytecode.version[0x52] = bytecode.version.lua52
	bytecode.version.R = bytecode.version.lua51
end

if _VERSION >= "Lua 5.1" then
	bytecode.version.lua51 = subrequire("bytecode.lua51", bytecode)
	bytecode.version[0x51] = bytecode.version.lua51
	bytecode.version.Q = bytecode.version.lua51
end

local debug = bytecode.printDebug
local bit = bytecode.bit
local binarytypes = bytecode.binarytypes

function bytecode.load(bc)
	local idx = 1
	local integer, size_t, number
	local bigEndian = false
	
	local function u1()
		idx = idx+1
		return binarytypes.decode.u1(bc, idx-1, bigEndian)
	end
	
	local function u2()
		idx = idx+2
		return binarytypes.decode.u2(bc, idx-2, bigEndian)
	end
	
	local function u4()
		idx = idx+4
		return binarytypes.decode.u4(bc, idx-4, bigEndian)
	end
	
	local function u8()
		idx = idx+8
		return binarytypes.decode.u8(bc, idx-8, bigEndian)
	end
	
	local function float()
		idx = idx+4
		return binarytypes.decode.float(bc, idx-4, bigEndian)
	end
	
	local function double(f)
		idx = idx+8
		return binarytypes.decode.float(bc, idx-8, bigEndian)
	end
	
	local function ub(n)
		idx = idx+n
		return bc:sub(idx-n,idx-1)
	end
	
	local function us()
		local size = size_t()
		--print(size)
		return ub(size):sub(1,-2)
	end
	
	--verify header--
	assert(bc:sub(1, 4) == "\27Lua", "invalid header signature")
	local versionCode = bc:byte(5)
	local version = bytecode.version[versionCode]
	assert(version and version.load, ("version not supported: Lua %X.%X"):format(math.floor(versionCode/16), versionCode%16))
	
	return version.load(bc)
	--[[
	do
		local fmtver = u1()
		assert(fmtver == 0 or fmtver == 255, "unknown format version "..fmtver)
	end
	local types = ub(6)
	if types ~= supportedTypes then
		print("Warning: types do not match the currently running lua binary")
	end
	bigEndian = types:byte(1) ~= 1
	integer = types:byte(2) == 8 and u8 or u4
	if integer == u8 then print("Caution: Because you are on a 128bit(!?) platform, LuaVM2 will chop off the upper 4 bytes from integer!") end
	size_t = types:byte(3) == 8 and u8 or u4
	--if size_t == u8 then print("Caution: Because you are on a 64bit platform, LuaVM2 will chop off the upper 4 bytes from size_t!") end
	number = types:byte(5) == 8 and double or float
	if version == 0x52 then
		ub(6)
	end
	debug("header is legit")
	
	local function chunk()
		local function instructionList()
			local instructions = {}
			local count = integer()
			for i=1, count do
				instructions[i-1] = u4()
			end
			return instructions
		end
		
		local function constantList()
			local constants = {}
			local c = integer()
			print(c)
			for i=1, c do
				local type = u1()
				if type == 0 then
					constants[i-1] = nil
				elseif type == 1 then
					constants[i-1] = u1() > 0
				elseif type == 3 then
					constants[i-1] = number(true)
				elseif type == 4 then
					constants[i-1] = us()
				else
					error("Type: "..type)
				end
				debug("Constant "..(i-1)..": "..tostring(constants[i-1]).." "..type)
			end
			return constants
		end
		
		local function functionPrototypeList()
			local functionPrototypes = {}
			for i=1, integer() do
				functionPrototypes[i-1] = chunk()
			end
			return functionPrototypes
		end
		
		local function sourceLineList()
			local sourceLines = {}
			for i=1, integer() do
				sourceLines[i-1] = integer()
			end
			return sourceLines
		end
		
		local function localList()
			local locals = {}
			for i=1, integer() do
				locals[i-1] = {
					name = us(),
					startpc = integer(),
					endpc = integer()
				}
			end
			return locals
		end
		
		local function upvalueList()
			local upvalues = {}
			for i=1, integer() do
				upvalues[i-1] = us()
			end
			return upvalues
		end
		
		--extract an lua chunk into a table--
		local c = {version = version}
		if version == 0x51 then
			c.name = us()
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nupval = u1()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvalues = upvalueList()
		elseif version == 0x52 then
			local function upvalueDefinitionList()
				local upvalues = {}
				for i=1, integer() do
					upvalues[i-1] = {instack=u1(),idx=u1()}
					debug(("upvalue %d instack=%d idx=%d"):format(i-1,upvalues[i-1].instack,upvalues[i-1].idx))
				end
				return upvalues
			end
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.upvalues = upvalueDefinitionList()
			c.name = us()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvaluesDebug = upvalueList()
		else
			error("Unknown lua version.")
		end
		return c
	end
	return chunk()]]
end

local header = "\27Lua"..string.char(0x51)..string.char(0)..supportedTypes
function bytecode.save(chunk)
	assert(chunk.version == 0x51, "Cannot save Lua versions greater than 5.1! Sorry!")
	local bc = {header}
	
	local function w1(b)
		bc[#bc+1] = string.char(b)
	end
	
	local function w2(s)
		bc[#bc+1] = string.char(bit.band(s,0xFF),bit.brshift(bit.band(s,0xFF00),8))
	end
	
	local function w4(s)
		bc[#bc+1] = string.char(
			bit.band(s,0xFF),bit.brshift(bit.band(s,0xFF00),8),
			bit.brshift(bit.band(s,0xFF0000),16),bit.brshift(bit.band(s,0xFF000000),24)
		)
	end
	
	local function grab_byte(v)
		return math.floor(v / 256), string.char(math.floor(v) % 256)
	end
	
	local function double(x)
		local sign = 0
		if x < 0 then sign = 1; x = -x end
		local mantissa, exponent = math.frexp(x)
		if x == 0 then -- zero
		mantissa, exponent = 0, 0
		else
		mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, 53)
		exponent = exponent + 1022
		end
		local v, byte = "" -- convert to bytes
		x = mantissa
		for i = 1,6 do
			x, byte = grab_byte(x); v = v..byte -- 47:0
		end
		x, byte = grab_byte(exponent * 16 + x); v = v..byte -- 55:48
		x, byte = grab_byte(sign * 128 + x); v = v..byte -- 63:56
		bc[#bc+1] = v
	end
	
	local function w8(s)
		w4(s)
		w4(0)
	end
	
	local integer = supportedTypes:byte(2) == 8 and w8 or w4
	if integer == u8 then print("Caution: Because you are on a 128bit(!?) platform, LuaVM2 will chop off the upper 4 bytes from integer!") end
	local size_t = supportedTypes:byte(3) == 8 and w8 or w4
	if size_t == u8 then print("Caution: Because you are on a 64bit platform, LuaVM2 will chop off the upper 4 bytes from size_t!") end
	
	local function ws(str)
		size_t(#str+1)
		bc[#bc+1] = str
		bc[#bc+1] = string.char(0)
	end
	
	local function len(t)
		local n = 0
		for i, v in pairs(t) do n = n+1 end
		return n
	end
	
	local function writeChunk(chunk)
		ws(chunk.name)
		integer(chunk.lineDefined)
		integer(chunk.lastLineDefined)
		w1(chunk.nupval)
		w1(chunk.nparam)
		w1(chunk.isvararg)
		w1(chunk.maxStack)
		
		integer(len(chunk.instructions))
		for i=0, len(chunk.instructions)-1 do
			w4(chunk.instructions[i])
		end
		
		integer(len(chunk.constants))
		for i=0, len(chunk.constants)-1 do
			local v = chunk.constants[i]
			local t = type(v)
			w1(t == "nil" and 0 or t == "boolean" and 1 or t == "number" and 3 or t == "string" and 4 or error("Unknown constant type."))
			if t == "boolean" then
				w1(v and 1 or 0)
			elseif t == "number" then
				double(v)
			elseif t == "string" then
				ws(v)
			end
		end
		
		integer(len(chunk.functionPrototypes))
		for i=0, len(chunk.functionPrototypes)-1 do
			writeChunk(chunk.functionPrototypes[i])
		end
		
		integer(len(chunk.sourceLines))
		for i=0, len(chunk.sourceLines)-1 do
			integer(chunk.sourceLines[i])
		end
		
		integer(len(chunk.locals))
		for i=0, len(chunk.locals)-1 do
			local l = chunk.locals[i]
			ws(l.name)
			integer(l.startpc)
			integer(l.endpc)
		end
		
		integer(len(chunk.upvalues))
		for i=0, len(chunk.upvalues)-1 do
			ws(chunk.upvalues[i])
		end
	end
	
	writeChunk(chunk)
	return table.concat(bc)
end

function bytecode.new(version)
	version = version or 0x51
	
	if version == 0x51 then
		return
		{
			version = 0x51,
			lineDefined = 0,
			isvararg = 2,
			sourceLines = {},
			nparam = 0,
			lastLineDefined = 0,
			maxStack = 2,
			upvalues = {},
			instructions = {[0]=8388638},
			locals = {},
			functionPrototypes = {},
			nupval = 0,
			name = "",
			constants = {}
		}
	elseif version == 0x52 then
		return {"TODO"}
	else
		error("Cannot create bytecode for "..string.format("%X",version)..".")
	end
end

function bytecode.dump(bc)
	local ver = bytecode.version[bc.header.version]
	for i=0, #bc.instructions do
		local o,a,b,c = ver.decode(bc.instructions[i])
		print(i, ver.instructionNames[o], a, b, c)
	end
end

--[[if _VERSION == "Lua 5.3" then
	require "luavm.bytecode_53"
end]]
