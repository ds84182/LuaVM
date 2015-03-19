--reads lua 5.1 bytecode--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

local supportedTypes = string.dump(function() end):sub(7,12)

bytecode = {}
bytecode.debug = false
bytecode.lua51 = {}
bytecode[0x51] = bytecode.lua51
bytecode.lua52 = {}
bytecode[0x52] = bytecode.lua52

local function debug(...)
	if bytecode.debug then
		print(...)
	end
end

do
	local instructionNames = {
		[0]="MOVE","LOADK","LOADBOOL","LOADNIL",
		"GETUPVAL","GETGLOBAL","GETTABLE",
		"SETGLOBAL","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"
	}

	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end

	bytecode.lua51.instructionNames = instructionNames
	bytecode.lua51.instructions = ins
	bytecode.lua51.defaultReturn = 8388638

	local iABC = 0
	local iABx = 1
	local iAsBx = 2

	local instructionFormats = {
		[0]=iABC,iABx,iABC,iABC,
		iABC,iABx,iABC,
		iABx,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iABC,iABC,iABx,iABC
	}

	--instruction constants--
	local MOVE = 0
	local LOADK = 1
	local LOADBOOL = 2
	local LOADNIL = 3
	local GETUPVAL = 4
	local GETGLOBAL = 5
	local GETTABLE = 6
	local SETGLOBAL = 7
	local SETUPVAL = 8
	local SETTABLE = 9
	local NEWTABLE = 10
	local SELF = 11
	local ADD = 12
	local SUB = 13
	local MUL = 14
	local DIV = 15
	local MOD = 16
	local POW = 17
	local UNM = 18
	local NOT = 19
	local LEN = 20
	local CONCAT = 21
	local JMP = 22
	local EQ = 23
	local LT = 24
	local LE = 25
	local TEST = 26
	local TESTSET = 27
	local CALL = 28
	local TAILCALL = 29
	local RETURN = 30
	local FORLOOP = 31
	local FORPREP = 32
	local TFORLOOP = 33
	local SETLIST = 34
	local CLOSE = 35
	local CLOSURE = 36
	local VARARG = 37

	function bytecode.lua51.encode(inst,a,b,c)
		inst = type(inst) == "string" and ins[inst] or inst
		local format = instructionFormats[inst]
		return
			format == iABC and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x1FF),23), bit.blshift(bit.band(c,0x1FF),14)) or
			format == iABx and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x3FFFF),14)) or
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b+131071,0x3FFFF),14))
	end

	function bytecode.lua51.decode(inst)
		local opcode = bit.band(inst,0x3F)
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,23),0x1FF), bit.band(bit.brshift(inst,14),0x1FF)
		elseif format == iABx then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,14),0x3FFFF)
		elseif format == iAsBx then
			local sBx = bit.band(bit.brshift(inst,14),0x3FFFF)-131071
			return opcode, bit.band(bit.brshift(inst,6),0xFF), sBx
		else
			error(opcode.." "..format)
		end
	end
	
	bytecode.lua51.patcher = {}

	local function patchJumpsAndAdd(bc, pc, op)
		for i=0, #bc.instructions do
			local o,a,b,c = bytecode.decode(bc.instructions[i])
			if o == LOADBOOL then
				if c ~= 0 then
					if i+1 == pc then
						error("TODO: Patch LOADBOOL")
					end
				end
			elseif o == JMP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TEST then
				if i+1 == pc then
					error("TODO: Patch TEST")
				end
			elseif o == TESTSET then
				if i+1 == pc then
					error("TODO: Patch TESTSET")
				end
			elseif o == FORLOOP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == FORPREP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TFORPREP then
				if i+1 == pc then
					error("TODO: Patch TFORPREP")
				end
			end
			bc.instructions[i] = bytecode.encode(o,a,b,c)
			print(i,bc.instructions[i])
		end
	
		for i=#bc.instructions, pc, -1 do
			bc.instructions[i+1] = bc.instructions[i]
			bc.sourceLines[i+1] = bc.sourceLines[i]
		end
		bc.instructions[pc] = op
	end

	function bytecode.lua51.patcher.insert(bc, pc, inst)
		--insert commands, fix jump targets--
		patchJumpsAndAdd(bc, pc, inst)
	end

	function bytecode.lua51.patcher.replace(bc, pc, inst)
		bc.instructions[pc] = inst
	end

	function bytecode.lua51.patcher.find(bc, pc, o)
		for i=pc+1, #bc.instructions do
			local no = bytecode.decode(bc.instructions[i])
			if no == o then
				return i
			end
		end
	end

	function bytecode.lua51.patcher.addConstant(bc, const)
		--try find constant...---
		for i, v in pairs(bc.constants) do if v == const then return i end end
		bc.constants[#bc.constants+1] = const
		return #bc.constants
	end
end

function bytecode.load(bc)
	debug("Loading binary chunk with size "..#bc.."b")
	local idx = 1
	local integer, size_t
	local function u1()
		idx = idx+1
		return bc:byte(idx-1)
	end
	local function u2()
		local a,b = bc:byte(idx,idx+1)
		idx = idx+2
		return bit.blshift(b,8)+a
	end
	local function u4()
		local a,b,c,d = bc:byte(idx,idx+3)
		idx = idx+4
		return bit.blshift(d,24)+bit.blshift(c,16)+bit.blshift(b,8)+a
	end
	local function u8()
		local a,b,c,d,e,f,g,h = bc:byte(idx,idx+7)
		idx = idx+8
		return bit.blshift(d,24)+bit.blshift(c,16)+bit.blshift(b,8)+a
	end
	local function double()
		local x = bc:sub(idx,idx+7)
		idx = idx+8
		
		local sign = 1
		local mantissa = string.byte(x, 7) % 16
		for i = 6, 1, -1 do mantissa = mantissa * 256 + string.byte(x, i) end
		if string.byte(x, 8) > 127 then sign = -1 end
		local exponent = (string.byte(x, 8) % 128) * 16 +math.floor(string.byte(x, 7) / 16)
		if exponent == 0 then return 0 end
		mantissa = (math.ldexp(mantissa, -52) + 1) * sign
		return math.ldexp(mantissa, exponent - 1023)
	end
	local function ub(n)
		idx = idx+n
		return bc:sub(idx-n,idx-1)
	end
	local function us()
		local size = size_t()
		return ub(size):sub(1,-2)
	end
	
	--verify header--
	assert(ub(4) == "\27Lua", "invalid header signature")
	local version = u1()
	assert(version == 0x51 or version == 0x52, ("version not supported: Lua%X"):format(version))
	do
		local fmtver = u1()
		assert(fmtver == 0 or fmtver == 255, "unknown format version "..fmtver)
	end
	local types = ub(6)
	if types ~= supportedTypes then
		print("Warning: types do not match the currently running lua binary")
	end
	integer = types:byte(2) == 8 and u8 or u4
	if integer == u8 then print("Caution: Because you are on a 128bit(!?) platform, LuaVM2 will chop off the upper 4 bytes from integer!") end
	size_t = types:byte(3) == 8 and u8 or u4
	--if size_t == u8 then print("Caution: Because you are on a 64bit platform, LuaVM2 will chop off the upper 4 bytes from size_t!") end
	if version == 0x52 then
		ub(6)
	end
	debug("header is legit")
	
	local function chunk()
		local function instructionList()
			local instructions = {}
			for i=1, integer() do
				instructions[i-1] = u4()
			end
			return instructions
		end
		
		local function constantList()
			local constants = {}
			for i=1, integer() do
				local type = u1()
				if type == 0 then
					constants[i-1] = nil
				elseif type == 1 then
					constants[i-1] = u1() > 0
				elseif type == 3 then
					constants[i-1] = double()
				elseif type == 4 then
					constants[i-1] = us()
				else
					error("Type: "..type)
				end
				debug("Constant "..(i-1)..": "..tostring(constants[i-1]))
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
	return chunk()
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
	local ver = bytecode[bc.version]
	for i=0, #bc.instructions do
		local o,a,b,c = ver.decode(bc.instructions[i])
		print(i, ver.instructionNames[o], a, b, c)
	end
end
